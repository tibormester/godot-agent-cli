const { probe, send, resolvePorts } = require('./client');

let _registry = null;

let _ports = null;
function ports() {
  if (!_ports) _ports = resolvePorts(process.cwd());
  return _ports;
}
// After an auto-launch the server writes a fresh ephemeral .gdli/<mode>.port; drop the cache so the
// next lookup re-reads it (and clear the registry cache so we re-fetch from the new instance).
function resetPorts() {
  _ports = null;
  _registry = null;
}

async function availablePort() {
  const { game, editor } = ports();
  if (await probe(game)) return game;
  if (await probe(editor)) return editor;
  return null;
}

async function fetchRegistry() {
  if (_registry) return _registry;
  const port = await availablePort();
  if (port == null) {
    const e = new Error('no instance running (gdli launch)');
    e.code = 'no_instance';
    throw e;
  }
  const res = await send(port, 'verbs', {});
  if (!res.ok) {
    const e = new Error((res.err && res.err.message) || 'failed to fetch registry');
    e.code = (res.err && res.err.code) || 'list_failed';
    throw e;
  }
  _registry = res.data;
  return _registry;
}

// Greedily match the LONGEST registered verb name that is a prefix of the argv tokens.
function matchVerb(registry, tokens) {
  const names = new Set(registry.map((v) => v.name));
  let best = null;
  for (let n = Math.min(tokens.length, 4); n >= 1; n--) {
    const candidate = tokens.slice(0, n).join(' ');
    if (names.has(candidate)) {
      best = { name: candidate, rest: tokens.slice(n) };
      break;
    }
  }
  if (!best) return null;
  best.meta = registry.find((v) => v.name === best.name);
  return best;
}

function coerce(type, value) {
  switch (type) {
    case 'int': return parseInt(value, 10);
    case 'float': return parseFloat(value);
    case 'bool': return true;
    case 'json': return JSON.parse(value);
    default: return value;
  }
}

const _marksByPort = {};

async function fetchMarks(port) {
  if (port in _marksByPort) return _marksByPort[port];
  let names = new Set();
  try {
    const res = await send(port, 'mark', {});
    if (res.ok && res.data && Array.isArray(res.data.marks)) {
      names = new Set(res.data.marks);
    }
  } catch (e) {
    names = new Set();
  }
  _marksByPort[port] = names;
  return names;
}

// Strip the universal core flags (--diff/--mark/--ticks/--physics/--time/--ignore) out of
// the token stream before the verb's own meta.args parsing runs. These are valid
// on EVERY verb and must never trip the "unknown flag" check.
async function extractCore(tokens, ctx) {
  const params = {};
  const rest = [];
  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    if (tok === '--diff') {
      const next = tokens[i + 1];
      if (next === undefined || next.startsWith('-')) {
        params.diff = true;
      } else {
        const marks = ctx && ctx.port != null && ctx.fetchMarks
          ? await ctx.fetchMarks(ctx.port)
          : new Set();
        if (marks.has(next)) {
          params.diff = next;
          i++;
        } else {
          params.diff = true;
        }
      }
    } else if (tok === '--mark') {
      i++;
      if (i >= tokens.length) throw clientErr('flag --mark expects a value');
      params.mark = tokens[i];
    } else if (tok === '--ticks') {
      i++;
      if (i >= tokens.length) throw clientErr('flag --ticks expects a value');
      params.ticks = parseInt(tokens[i], 10);
    } else if (tok === '--physics') {
      i++;
      if (i >= tokens.length) throw clientErr('flag --physics expects a value');
      params.physics = parseInt(tokens[i], 10);
    } else if (tok === '--time') {
      i++;
      if (i >= tokens.length) throw clientErr('flag --time expects a value');
      params.time = parseFloat(tokens[i]);
    } else if (tok === '--ignore') {
      i++;
      if (i >= tokens.length) throw clientErr('flag --ignore expects a value');
      params.ignore = tokens[i];
    } else {
      rest.push(tok);
    }
  }
  return { core: params, rest };
}

// meta.args entries: {name, type, required, default, help}. A name with leading
// dashes is a flag; otherwise it is positional. param key = name with dashes stripped.
async function parseArgs(meta, tokens, ctx) {
  const { core, rest: tokensRest } = await extractCore(tokens, ctx);
  tokens = tokensRest;

  const specs = meta.args || [];
  const flagSpecs = specs.filter((a) => a.name.startsWith('-'));
  const posSpecs = specs.filter((a) => !a.name.startsWith('-'));
  const flagByName = {};
  for (const f of flagSpecs) flagByName[f.name] = f;

  const params = {};
  const positionals = [];

  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    if (tok.startsWith('-') && flagByName[tok]) {
      const spec = flagByName[tok];
      const key = spec.name.replace(/^-+/, '');
      if (spec.type === 'bool') {
        params[key] = true;
      } else {
        i++;
        if (i >= tokens.length) {
          throw clientErr(`flag ${tok} expects a value`);
        }
        params[key] = coerce(spec.type, tokens[i]);
      }
    } else if (tok.startsWith('-') && tok.length > 1 && isNaN(Number(tok))) {
      throw clientErr(`unknown flag: ${tok}`);
    } else {
      positionals.push(tok);
    }
  }

  // Assign positionals; a `variadic` last spec absorbs the rest. Never silently drop extras — error.
  let consumed = 0;
  for (let i = 0; i < posSpecs.length; i++) {
    const spec = posSpecs[i];
    const key = spec.name.replace(/^-+/, '');
    if (spec.variadic) {
      params[key] = positionals.slice(i).map((t) => coerce(spec.type, t));
      consumed = positionals.length;
      break;
    }
    if (i < positionals.length) {
      params[key] = coerce(spec.type, positionals[i]);
      consumed = i + 1;
    }
  }
  if (consumed < positionals.length) {
    throw clientErr(`unexpected argument: ${positionals.slice(consumed).join(' ')}`);
  }

  for (const spec of specs) {
    const key = spec.name.replace(/^-+/, '');
    // Bool defaults stay off the wire unless the flag is present.
    if (!(key in params) && spec.type !== 'bool' &&
        spec.default !== undefined && spec.default !== null && spec.default !== '') {
      params[key] = spec.default;
    }
  }

  for (const spec of specs) {
    const key = spec.name.replace(/^-+/, '');
    if (spec.required && !(key in params)) {
      throw clientErr(`missing required arg: ${spec.name}`);
    }
  }

  Object.assign(params, core);
  return params;
}

function clientErr(message) {
  const e = new Error(message);
  e.client = true;
  return e;
}

// Resolve the port for a verb given its target policy + global overrides.
async function resolvePort(target, opts) {
  const { game, editor } = ports();
  if (opts.port != null) return opts.port;
  if (opts.game) return ensureUp(game, 'game instance not running');
  if (opts.editor) return ensureUp(editor, 'editor instance not running (gdli launch)');
  if (target === 'game') return ensureUp(game, 'game instance not running');
  if (target === 'editor') return ensureUp(editor, 'editor instance not running (gdli launch)');
  // auto
  if (await probe(game)) return game;
  if (await probe(editor)) return editor;
  throw clientErr('no instance running (gdli launch)');
}

async function ensureUp(port, msg) {
  if (await probe(port)) return port;
  throw clientErr(msg);
}

module.exports = { fetchRegistry, matchVerb, parseArgs, resolvePort, clientErr, fetchMarks, resetPorts };
