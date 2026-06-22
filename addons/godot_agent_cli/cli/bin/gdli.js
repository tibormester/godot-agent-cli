#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { send, projectRoot } = require('../src/client');
const { fetchRegistry, matchVerb, parseArgs, resolvePort, clientErr, fetchMarks } = require('../src/router');
const launch = require('../src/launch');
const install = require('../src/install');
const fmt = require('../src/format');

const META_VERBS = new Set(['launch', 'status', 'kill', 'check', 'install', 'help', 'verbs']);

const RAW_ARGS = process.argv.slice(2);

function gdliLogPath() {
  return path.join(projectRoot(process.cwd()), '.gdli', 'failures.log');
}
function sessionPendingPath() {
  return path.join(projectRoot(process.cwd()), '.gdli', 'session.pending');
}

// A new session's marker is written lazily: launch stashes it as "pending", and it's flushed to the log
// only if/when that session produces a failure — so clean (failure-free) runs leave no marker behind.
function logSession(mode) {
  try {
    const file = sessionPendingPath();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `\n# ── session: ${mode} @ ${new Date().toISOString()} ──\n`);
  } catch (e) {}
}
function flushPendingSession(logFile) {
  const p = sessionPendingPath();
  if (!fs.existsSync(p)) return;
  const marker = fs.readFileSync(p, 'utf8');
  if (marker) fs.appendFileSync(logFile, marker);
  fs.unlinkSync(p);
}

// Append a failed command to the per-project failure log (best-effort; never throws). A testing aid:
// review .gdli/failures.log to see what went wrong this session. The session marker (if any) is flushed
// just before the first failure of that session.
function recordFailure(code, message) {
  try {
    const file = gdliLogPath();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    flushPendingSession(file);
    const cmd = RAW_ARGS.filter((a) => a !== '--json').join(' ');
    fs.appendFileSync(file, `${new Date().toISOString()}\t${cmd}\t${code}: ${message}\n`);
  } catch (e) { /* logging must never break the CLI */ }
}

// Print an error to the user AND record it to the failure log.
function emitErr(code, message, opts) {
  recordFailure(code, message);
  fmt.printErr(code, message, opts.json);
}

function parseGlobals(argv) {
  const opts = { json: false, data: false, game: false, editor: false, port: null, godot: null, scene: null, inEditor: false };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--json': opts.json = true; break;
      case '--data': opts.data = true; break;
      case '--game': opts.game = true; break;
      case '--editor': opts.editor = true; break;
      case '--port': opts.port = parseInt(argv[++i], 10); break;
      case '--in-editor': opts.inEditor = true; break;
      case '--godot': opts.godot = argv[++i]; break;
      case '--scene': opts.scene = argv[++i]; break;
      case '--help': case '-h': rest.unshift('help'); break;
      default: rest.push(a);
    }
  }
  return { opts, rest };
}

async function handleHelp(rest, opts) {
  const verbName = rest.join(' ');
  let registry = null;
  try {
    registry = await fetchRegistry();
  } catch (e) {
    // no instance: static usage only
    fmt.printLine(fmt.STATIC_USAGE, opts.json, { usage: 'offline' });
    return 0;
  }
  if (verbName) {
    const v = registry.find((x) => x.name === verbName);
    if (!v) {
      emitErr('not_found', `unknown verb: ${verbName}`, opts);
      return 1;
    }
    fmt.printLine(fmt.renderVerbHelp(v) + '\n\n' + fmt.UNIVERSAL_FLAGS, opts.json, v);
    return 0;
  }
  fmt.printLine(fmt.renderRegistry(registry) + '\n\n' + fmt.UNIVERSAL_FLAGS, opts.json, registry);
  return 0;
}

async function handleVerbs(opts) {
  const registry = await fetchRegistry();
  fmt.printLine(fmt.renderRegistry(registry), opts.json, registry);
  return 0;
}

async function handleScreenshot(verb, params, port, opts) {
  // --out is client-side only; strip before sending.
  const out = params.out;
  delete params.out;
  const res = await send(port, verb.name, params);
  if (!res.ok) {
    emitErr(res.err.code, res.err.message, opts);
    return 1;
  }
  const { format, width, height, b64 } = res.data;
  const dest = out || path.resolve(process.cwd(), `gdli-screenshot.${format}`);
  fs.writeFileSync(dest, Buffer.from(b64, 'base64'));
  fmt.printOk({ path: dest, width, height }, opts.json);
  return 0;
}

// Hybrid compile check: use a running instance if one's up (fast `check` server verb), else spawn a
// headless Godot to re-parse the project. Either way: print 'ok', or the failing files (+ messages).
async function handleCheck(opts) {
  let port = null;
  try { port = await resolvePort('auto', opts); } catch (e) { port = null; }

  let failures = [];
  let errLines = [];
  if (port) {
    const res = await send(port, 'check', {});
    if (!res.ok) { emitErr(res.err.code, res.err.message, opts); return 1; }
    failures = (res.data && res.data.failures) || [];
  } else {
    const r = launch.check(opts);
    if (r.error) { emitErr('check_error', r.error, opts); return 1; }
    failures = r.failures || [];
    errLines = r.errLines || [];
  }

  if (failures.length === 0) {
    fmt.printLine('ok', opts.json, { ok: true, failures: [] });
    return 0;
  }
  recordFailure('check', `${failures.length} script(s) failed to compile`);
  if (opts.json) {
    process.stdout.write(JSON.stringify({ ok: false, failures, errors: errLines }) + '\n');
  } else {
    const lines = [`${failures.length} script(s) failed to compile:`];
    for (const f of failures) lines.push('  ' + f);
    if (errLines.length) { lines.push(''); for (const l of errLines) lines.push(l); }
    process.stdout.write(lines.join('\n') + '\n');
  }
  return 1;
}

async function handleServerVerb(rest, opts) {
  const registry = await fetchRegistry();
  const verb = matchVerb(registry, rest);
  if (!verb) {
    throw clientErr(`unknown verb: ${rest.join(' ')}`);
  }

  const port = await resolvePort(verb.meta.target, opts);
  const params = await parseArgs(verb.meta, verb.rest, { port, fetchMarks });

  if (verb.name === 'screenshot') {
    return handleScreenshot(verb, params, port, opts);
  }

  const res = await send(port, verb.name, params);
  if (!res.ok) {
    emitErr(res.err.code, res.err.message, opts);
    return 1;
  }
  fmt.printOk(res.data, opts.json, res, opts.data);
  return 0;
}

async function main() {
  const { opts, rest } = parseGlobals(process.argv.slice(2));

  if (rest.length === 0) {
    fmt.printLine(fmt.STATIC_USAGE, opts.json, { usage: 'offline' });
    return 0;
  }

  const head = rest[0];

  if (head === 'help') return handleHelp(rest.slice(1), opts);
  if (head === 'verbs') return handleVerbs(opts);

  if (head === 'launch') {
    logSession(opts.editor ? 'editor' : opts.inEditor ? 'in-editor' : 'game');
    const r = await launch.launch(opts);
    if (r.ok === false) recordFailure('launch_failed', r.line);
    fmt.printLine(r.line, opts.json, { launched: r.ok !== false });
    return r.ok === false ? 1 : 0;
  }
  if (head === 'status') {
    const r = await launch.status(rest[1]);
    fmt.printLine(r.line, opts.json, { game: r.game, editor: r.editor });
    return 0;
  }
  if (head === 'check') return handleCheck(opts);
  if (head === 'kill') {
    const r = await launch.kill(opts);
    fmt.printLine(r.line, opts.json, { killed: true });
    return 0;
  }
  if (head === 'install') {
    const r = install.install(opts, rest.slice(1));
    if (!r.ok) {
      emitErr('client_error', r.line, opts);
      return 1;
    }
    fmt.printLine(r.line, opts.json, { installed: true, dest: r.dest, overwrote: r.overwrote });
    return 0;
  }

  return handleServerVerb(rest, opts);
}

main()
  .then((code) => process.exit(code || 0))
  .catch((e) => {
    const json = process.argv.includes('--json');
    const code = e.code || 'client_error';
    recordFailure(code, e.message);
    fmt.printErr(code, e.message, json);
    process.exit(1);
  });
