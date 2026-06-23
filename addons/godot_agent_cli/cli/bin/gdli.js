#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { send, projectRoot, probe, resolvePorts } = require('../src/client');
const { fetchRegistry, matchVerb, resolvePort, clientErr, resetPorts } = require('../src/router');
const launch = require('../src/launch');
const install = require('../src/install');
const fmt = require('../src/format');
const timing = require('../src/timing');

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

function targetForPort(port, opts) {
  if (opts.game) return 'game';
  if (opts.editor) return 'editor';
  const ps = resolvePorts(process.cwd());
  if (port === ps.game) return 'game';
  if (port === ps.editor) return 'editor';
  return 'auto';
}

function parseGlobals(argv) {
  const opts = { json: false, data: false, game: false, editor: false, all: false, port: null, godot: null, scene: null, inEditor: false, headless: false, timeoutMs: null, warningMs: null };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--json': opts.json = true; break;
      case '--data': opts.data = true; break;
      case '--game': opts.game = true; break;
      case '--editor': opts.editor = true; break;
      case '--all':
      case '--both': opts.all = true; break;
      case '--port': opts.port = parseInt(argv[++i], 10); break;
      case '--in-editor': opts.inEditor = true; break;
      case '--godot': opts.godot = argv[++i]; break;
      case '--scene': opts.scene = argv[++i]; break;
      case '--headless': opts.headless = true; break;
      case '--timeout': opts.timeoutMs = timing.parseDurationMs(argv[++i], '--timeout'); break;
      case '--timewarning': opts.warningMs = timing.parseDurationMs(argv[++i], '--timewarning'); break;
      case '--help': case '-h': rest.unshift('help'); break;
      default: rest.push(a);
    }
  }
  return { opts, rest };
}

// --- Auto-launch: if a verb needs a live instance and none is up, spawn one (default behavior).
// Mode follows the verb's target — editor-only built-ins get an editor, everything else a game.
async function anyInstanceUp() {
  const { game, editor } = resolvePorts(process.cwd());
  if (await probe(game)) return 'game';
  if (await probe(editor)) return 'editor';
  return null;
}

function autoLaunchMode(rest, opts) {
  if (opts.editor) return 'editor';
  if (opts.game) return 'game';
  if (rest[0] === 'file') return 'editor';
  if (rest[0] === 'scene' && rest[1] === 'save') return 'editor';
  return 'game';
}

function defaultsToHeadless(rest, opts) {
  return rest[0] === 'eval' &&
    !opts.game &&
    !opts.editor &&
    !opts.inEditor &&
    opts.port == null;
}

async function autoLaunch(mode, opts, headless) {
  logSession(headless ? `${mode} (headless)` : mode);
  const r = await launch.launch({ ...opts, editor: mode === 'editor', game: mode === 'game', headless });
  if (r.ok === false || !r.port) {
    throw clientErr(`auto-launch (${mode}${headless ? ', headless' : ''}) failed: ${r.line}`);
  }
  resetPorts();
  return r;
}

function teardownLaunched(r, mode, opts) {
  return async () => {
    if (r && r.pid) {
      try { execFileSync('taskkill', ['/PID', String(r.pid), '/T', '/F'], { stdio: 'ignore' }); } catch (e) {}
      const root = projectRoot(opts.cwd);
      try { fs.unlinkSync(path.join(root, '.gdli', `${mode}.pid`)); } catch (e) {}
      return;
    }
    try { await launch.kill({ cwd: opts.cwd, [mode]: true }); } catch (e) {}
  };
}

// Guarantee an instance is available to serve this run. Returns a teardown fn (to stop a one-shot
// headless instance) or null. With --headless, the spawned instance is transient and stopped after.
async function ensureInstance(rest, opts) {
  if (opts.port != null) return null; // explicit target — assume the caller manages it
  const existing = await anyInstanceUp();

  if (opts.headless) {
    if (existing) {
      if (!opts.json) process.stderr.write(`note: ${existing} already running — --headless ignored, using it\n`);
      return null;
    }
    const mode = autoLaunchMode(rest, opts);
    const r = await autoLaunch(mode, opts, true);
    if (!opts.json) process.stderr.write(`(spawned a headless ${mode} for this command; stopping it after)\n`);
    return teardownLaunched(r, mode, opts);
  }

  if (existing) return null;

  const mode = autoLaunchMode(rest, opts);
  if (defaultsToHeadless(rest, opts)) {
    const r = await autoLaunch(mode, opts, true);
    if (!opts.json) process.stderr.write(`(spawned a headless ${mode} for eval; stopping it after)\n`);
    return teardownLaunched(r, mode, opts);
  }

  await autoLaunch(mode, opts, false);
  if (!opts.json) process.stderr.write(`(auto-launched ${mode}; run 'gdli kill' to stop it)\n`);
  return null;
}

// Once the verb's real target is known, make sure THAT mode is up — the registry-fetch launch may have
// started the other one (e.g. a plugin editor-verb we couldn't classify up front). No-op for 'auto'
// (any running instance satisfies it) and when not auto-launching.
async function ensureTarget(target, opts) {
  if (opts.headless || opts.port != null) return;
  const mode = (opts.editor || target === 'editor') ? 'editor'
    : (opts.game || target === 'game') ? 'game' : null;
  if (mode == null) return;
  const { game, editor } = resolvePorts(process.cwd());
  if (await probe(mode === 'editor' ? editor : game)) return;
  await autoLaunch(mode, opts, false);
  if (!opts.json) process.stderr.write(`(auto-launched ${mode} for ${target}-target verb; 'gdli kill' to stop)\n`);
}

async function handleHelp(rest, opts) {
  const verbName = rest.join(' ');
  let registry = null;
  try {
    registry = await fetchRegistry(timing.sendOptions(opts, 'auto'));
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
  const teardown = await ensureInstance(['verbs'], opts);
  try {
    const registry = await fetchRegistry(timing.sendOptions(opts, 'auto'));
    fmt.printLine(fmt.renderRegistry(registry), opts.json, registry);
    return 0;
  } finally {
    if (teardown) await teardown();
  }
}

function extractFlagValue(tokens, flag) {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] === flag) return tokens[i + 1] || '';
  }
  return '';
}

async function handleScreenshot(tokens, port, opts) {
  const out = extractFlagValue(tokens, '--out');
  const res = await send(port, '__gdli_run', { tokens }, undefined, timing.sendOptions(opts, targetForPort(port, opts), tokens));
  if (!res.ok) {
    emitErr(res.err.code, res.err.message, opts);
    return 1;
  }
  const { format, width, height, b64 } = res.data;
  const dest = out || path.resolve(process.cwd(), `gdli-screenshot.${format}`);
  fs.writeFileSync(dest, Buffer.from(b64, 'base64'));
  fmt.printOk({ path: dest, width, height }, opts.json, res);
  return 0;
}

// Hybrid compile check: use a running instance if one's up (fast `check` server verb), else spawn a
// headless Godot to re-parse the project. Either way: print 'ok', or the failing files (+ messages).
async function handleCheck(opts) {
  let port = null;
  try { port = await resolvePort('auto', opts); } catch (e) { port = null; }

  let failures = [];
  let errLines = [];
  let warning = null;
  if (port) {
    const res = await send(port, 'check', {}, undefined, timing.sendOptions(opts, targetForPort(port, opts)));
    if (!res.ok) { emitErr(res.err.code, res.err.message, opts); return 1; }
    failures = (res.data && res.data.failures) || [];
    warning = res.warning || null;
  } else {
    const r = await launch.check(opts);
    if (r.error) { emitErr('check_error', r.error.message || r.error, opts); return 1; }
    failures = r.failures || [];
    errLines = r.errLines || [];
    warning = r.warning || null;
  }

  if (failures.length === 0) {
    const data = { ok: true, failures: [] };
    if (warning) data.warning = warning;
    fmt.printLine('ok', opts.json, data);
    return 0;
  }
  recordFailure('check', `${failures.length} script(s) failed to compile`);
  if (opts.json) {
    const out = { ok: false, failures, errors: errLines };
    if (warning) out.warning = warning;
    process.stdout.write(JSON.stringify(out) + '\n');
  } else {
    const lines = [`${failures.length} script(s) failed to compile:`];
    for (const f of failures) lines.push('  ' + f);
    if (errLines.length) { lines.push(''); for (const l of errLines) lines.push(l); }
    process.stdout.write(lines.join('\n') + '\n');
  }
  return 1;
}

async function handleServerVerb(rest, opts) {
  const teardown = await ensureInstance(rest, opts);
  try {
    const registry = await fetchRegistry(timing.sendOptions(opts, 'auto'));
    const verb = matchVerb(registry, rest);
    if (!verb) {
      throw clientErr(`unknown verb: ${rest.join(' ')}`);
    }

    await ensureTarget(verb.meta.target, opts);
    const port = await resolvePort(verb.meta.target, opts);
    if (verb.name === 'screenshot') {
      return await handleScreenshot(rest, port, opts);
    }

    const sendTarget = verb.meta.target === 'auto' ? targetForPort(port, opts) : verb.meta.target;
    const res = await send(port, '__gdli_run', { tokens: rest }, undefined, timing.sendOptions(opts, sendTarget, rest));
    if (!res.ok) {
      emitErr(res.err.code, res.err.message, opts);
      return 1;
    }
    fmt.printOk(res.data, opts.json, res, opts.data);
    return 0;
  } finally {
    if (teardown) await teardown();
  }
}

async function main() {
  const { opts, rest } = parseGlobals(process.argv.slice(2));

  if (rest.length === 0) {
    fmt.printLine(fmt.STATIC_USAGE, opts.json, { usage: 'offline' });
    return 0;
  }

  const head = rest[0];

  if (opts.all && head !== 'kill') {
    emitErr('client_error', '--all/--both only applies to kill', opts);
    return 1;
  }

  if (head === 'help') return handleHelp(rest.slice(1), opts);
  if (head === 'verbs') return handleVerbs(opts);

  if (head === 'launch') {
    logSession(opts.editor ? 'editor' : opts.inEditor ? 'in-editor' : 'game');
    const r = await launch.launch({ ...opts, saveTiming: true });
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
    if (opts.all) opts.game = opts.editor = false;
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
