const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { probe, send, resolvePorts, projectRoot } = require('./client');
const timing = require('./timing');

// Default to the GUI exe (single process) NOT the _console.exe wrapper: the wrapper relaunches
// the editor as a sibling process the pid-tree kill misses, leaving orphan windows. Set GODOT_BIN
// to the _console variant if you need stdout in the launch log.
const DEFAULT_GODOT =
  process.env.GODOT_BIN ||
  'C:\\Program Files (x86)\\Godot\\Godot_v4.7-stable_mono_win64\\Godot_v4.7-stable_mono_win64\\Godot_v4.7-stable_mono_win64.exe';

function gdliDir(root) {
  const d = path.join(root, '.gdli');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function launch(opts) {
  const root = projectRoot(opts.cwd);

  // --in-editor: use an open editor when available; otherwise start one, then ask it to play.
  if (opts.inEditor) {
    if (opts.saveTiming) {
      timing.saveSessionTiming(root, 'editor', {
        timeoutMs: opts.timeoutMs ?? timing.DEFAULT_TIMEOUT_MS,
        warningMs: opts.warningMs ?? timing.DEFAULT_WARNING_MS,
      });
    }
    const ps = resolvePorts(root);
    let editorPort = ps.editor;
    let launched = null;
    if (!(await probe(editorPort))) {
      launched = await launch({ ...opts, inEditor: false, editor: true, game: false });
      if (launched.ok === false || !launched.port) {
        return {
          line: `editor launch failed: ${launched.line}`,
          ok: false,
        };
      }
      editorPort = launched.port;
    }
    const res = await send(editorPort, 'play', {}, undefined, timing.sendOptions(opts, 'editor'));
    const prefix = launched ? `${launched.line}\n` : '';
    return { line: res.ok ? `${prefix}editor: play started` : `${prefix}play failed: ${res.err && res.err.message}`, ok: !!res.ok };
  }

  const mode = opts.editor ? 'editor' : 'game';
  if (opts.saveTiming) {
    timing.saveSessionTiming(root, mode, {
      timeoutMs: opts.timeoutMs ?? timing.DEFAULT_TIMEOUT_MS,
      warningMs: opts.warningMs ?? timing.DEFAULT_WARNING_MS,
    });
  }
  const godot = opts.godot || DEFAULT_GODOT;
  const args = [];
  if (opts.headless) args.push('--headless');
  args.push('--path', root);
  if (mode === 'editor') {
    args.push('-e');
  } else if (opts.scene) {
    args.push(opts.scene);
  }

  const dir = gdliDir(root);
  const logPath = path.join(dir, `launch-${mode}.log`);
  const fd = fs.openSync(logPath, 'w');
  const child = spawn(godot, args, { detached: true, stdio: ['ignore', fd, fd] });
  child.unref();
  fs.writeFileSync(path.join(dir, `${mode}.pid`), String(child.pid));

  // The server writes .gdli/<mode>.port once it binds; wait for that file, then probe its port.
  const portFile = path.join(dir, `${mode}.port`);
  const deadline = Date.now() + 40000;
  let port = null;
  while (Date.now() < deadline) {
    if (fs.existsSync(portFile)) {
      const p = parseInt(fs.readFileSync(portFile, 'utf8').trim(), 10);
      if (p && (await probe(p))) { port = p; break; }
    }
    await sleep(300);
  }

  const tag = opts.headless ? `${mode} (headless)` : mode;
  if (port) {
    return { line: `launched ${tag} pid=${child.pid} port=${port}`, ok: true, port, mode, pid: child.pid };
  }
  return {
    line: `warning: ${tag} pid=${child.pid} did not report a port within 40s (still running, check ${logPath})`,
    ok: true, port: null, mode, pid: child.pid,
  };
}

async function status(pathArg) {
  const root = projectRoot(pathArg || process.cwd());
  const ps = resolvePorts(root);
  const game = await probe(ps.game);
  const editor = await probe(ps.editor);
  const line = [
    `project: ${root}`,
    `game: ${game ? `up (${ps.game})` : 'down'}`,
    `editor: ${editor ? `up (${ps.editor})` : 'down'}`,
  ].join('\n');
  return { line, game, editor };
}

function killOne(root, mode) {
  const pidPath = path.join(root, '.gdli', `${mode}.pid`);
  if (!fs.existsSync(pidPath)) return null;
  const pid = fs.readFileSync(pidPath, 'utf8').trim();
  let killed = false;
  if (pid) {
    try {
      execFileSync('taskkill', ['/PID', pid, '/T', '/F'], { stdio: 'ignore' });
      killed = true;
    } catch (e) {
      // process already gone — ignore
    }
  }
  try {
    fs.unlinkSync(pidPath);
  } catch (e) {}
  return { mode, pid, killed };
}

async function kill(opts) {
  const root = projectRoot(opts.cwd);

  if (opts.inEditor) {
    const ps = resolvePorts(root);
    if (await probe(ps.editor)) {
      const res = await send(ps.editor, 'stop', {}, undefined, timing.sendOptions(opts, 'editor'));
      return { line: res.ok ? 'editor: stopped game' : `stop failed: ${res.err && res.err.message}` };
    }
    return { line: 'editor not running' };
  }

  let modes;
  if (opts.editor) modes = ['editor'];
  else if (opts.game) modes = ['game'];
  else modes = ['editor', 'game'];

  const results = [];
  for (const m of modes) {
    const r = killOne(root, m);
    if (r) results.push(r);
  }
  if (results.length === 0) {
    return { line: 'nothing to kill (no pid files)' };
  }
  const line = results
    .map((r) => (r.killed ? `killed ${r.mode} (pid ${r.pid})` : `${r.mode} pid ${r.pid} not running (cleaned up)`))
    .join('\n');
  return { line };
}

// Headless compile-check fallback for `gdli check` when no instance is running: boot Godot with the
// bundled checker script and parse its JSON sentinel + the engine's parse-error text (file:line).
async function check(opts) {
  const root = projectRoot(opts.cwd);
  const godot = opts.godot || DEFAULT_GODOT;
  const checkerDisk = path.join(root, 'addons', 'godot_agent_cli', 'tools', 'check.gd');
  if (!fs.existsSync(checkerDisk)) {
    return { error: `checker missing (${checkerDisk}); run 'gdli install'` };
  }
  const r = await runGodotCheck(godot, root, opts);
  if (r.error) {
    if (r.error.code === 'ENOENT') return { error: `Godot binary not found: ${godot} (set GODOT_BIN or --godot)` };
    return { error: `check failed to run: ${r.error.message}` };
  }
  const all = (r.stdout || '') + '\n' + (r.stderr || '');
  const m = all.match(/GDLI_CHECK_RESULT:(.*)/);
  if (!m) {
    return { error: 'checker produced no result\n' + all.trim().split(/\r?\n/).slice(-8).join('\n') };
  }
  let failures = [];
  try { failures = JSON.parse(m[1].trim()); } catch (e) { failures = []; }
  // Keep the message + its location line; drop the checker's own stack frames ([N] … check_lib.gd).
  const errLines = (r.stderr || '')
    .split(/\r?\n/)
    .map((l) => l.replace(/\s+$/, ''))
    .filter((l) => l.trim() && /SCRIPT ERROR|Parse Error|at: GDScript::reload/i.test(l));
  return { failures, errLines, warning: r.warning };
}

function runGodotCheck(godot, root, opts) {
  return new Promise((resolve) => {
    const timeoutMs = opts.timeoutMs ?? 120000;
    const warningMs = Math.max(0, Number(opts.warningMs ?? 0));
    const child = spawn(
      godot,
      ['--headless', '--path', root, '--script', 'res://addons/godot_agent_cli/tools/check.gd'],
      { stdio: ['ignore', 'pipe', 'pipe'] }
    );
    let stdout = '';
    let stderr = '';
    let settled = false;
    let warned = false;
    const startedAt = Date.now();
    const warningTimer = warningMs > 0 ? setTimeout(() => {
      if (settled) return;
      warned = true;
      if (!opts.json) process.stderr.write(`warning: command still running after ${Date.now() - startedAt}ms\n`);
    }, warningMs) : null;
    const timeoutTimer = setTimeout(() => {
      if (settled) return;
      settled = true;
      if (warningTimer) clearTimeout(warningTimer);
      try { execFileSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' }); } catch (e) {
        try { child.kill('SIGKILL'); } catch (_e) {}
      }
      resolve({ error: new Error(`request timed out after ${timeoutMs}ms`) });
    }, timeoutMs);
    child.stdout.on('data', (chunk) => { stdout += chunk.toString('utf8'); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString('utf8'); });
    child.once('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutTimer);
      if (warningTimer) clearTimeout(warningTimer);
      resolve({ error });
    });
    child.once('close', () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeoutTimer);
      if (warningTimer) clearTimeout(warningTimer);
      resolve({
        stdout,
        stderr,
        warning: warned ? { code: 'slow_command', elapsed_ms: Date.now() - startedAt } : undefined,
      });
    });
  });
}

module.exports = { launch, status, kill, check, projectRoot, DEFAULT_GODOT };
