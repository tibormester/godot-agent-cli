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

async function fetchRegistry(sendOpts = {}) {
  if (_registry) return _registry;
  const port = await availablePort();
  if (port == null) {
    const e = new Error('no instance running (gdli launch)');
    e.code = 'no_instance';
    throw e;
  }
  const res = await send(port, 'verbs', {}, undefined, sendOpts);
  if (!res.ok) {
    const e = new Error((res.err && res.err.message) || 'failed to fetch registry');
    e.code = (res.err && res.err.code) || 'list_failed';
    throw e;
  }
  _registry = res.data;
  return _registry;
}

// Greedily match the longest registered verb name that is a prefix of the argv tokens.
// Node uses this only to choose the target instance; the server parses the command itself.
function matchVerb(registry, tokens) {
  const names = new Set(registry.map((v) => v.name));
  let best = null;
  for (let n = tokens.length; n >= 1; n--) {
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

module.exports = { fetchRegistry, matchVerb, resolvePort, clientErr, resetPorts };
