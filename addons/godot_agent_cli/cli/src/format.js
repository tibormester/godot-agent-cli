function printOk(data, json, env, showData) {
  const diff = env && env.diff;
  const marked = env && env.marked;
  const warning = env && env.warning;
  // When a diff was requested, the diff IS the answer — suppress the verb's own data dump
  // (e.g. inspect's whole-scene snapshot) unless --data asks for it.
  const withData = showData || diff === undefined;
  if (json) {
    const out = { ok: true };
    if (withData) out.data = data;
    if (diff !== undefined) out.diff = diff;
    if (marked !== undefined) out.marked = marked;
    if (warning !== undefined) out.warning = warning;
    process.stdout.write(JSON.stringify(out) + '\n');
  } else {
    if (withData) process.stdout.write(JSON.stringify(data, null, 2) + '\n');
    if (diff !== undefined) process.stdout.write('diff:\n' + JSON.stringify(diff, null, 2) + '\n');
    if (marked !== undefined) process.stdout.write(`marked: ${marked}\n`);
  }
}

function printErr(code, message, json) {
  if (json) {
    process.stdout.write(JSON.stringify({ ok: false, error: { code, message } }) + '\n');
  } else {
    process.stderr.write(`error: ${code}: ${message}\n`);
  }
}

// Plain text (already-formatted lines from meta verbs); honors --json by wrapping.
function printLine(line, json, data) {
  if (json) {
    process.stdout.write(JSON.stringify({ ok: true, data: data !== undefined ? data : line }) + '\n');
  } else {
    process.stdout.write(line + '\n');
  }
}

function renderRegistry(registry) {
  const byModule = {};
  for (const v of registry) {
    (byModule[v.module] = byModule[v.module] || []).push(v);
  }
  const out = [];
  for (const mod of Object.keys(byModule).sort()) {
    out.push(`\n${mod}`);
    for (const v of byModule[mod].sort((a, b) => a.name.localeCompare(b.name))) {
      out.push(`  ${v.name}  [${v.target}]  ${v.help}`);
    }
  }
  return out.join('\n').trim();
}

function renderVerbHelp(v) {
  const out = [`${v.name}  [${v.target}]  ${v.help}`];
  if (v.args && v.args.length) {
    out.push('args:');
    for (const a of v.args) {
      const req = a.required ? ' (required)' : '';
      const def =
        a.default !== undefined && a.default !== null && a.default !== ''
          ? ` [default: ${JSON.stringify(a.default)}]`
          : '';
      out.push(`  ${a.name} <${a.type}>${req}${def}  ${a.help || ''}`);
    }
  }
  return out.join('\n');
}

const UNIVERSAL_FLAGS = `Universal flags (work on any verb):
  --diff [mark]     whole-scene delta before/after the command (or vs a named mark). Replaces the
                    verb's normal output; add --data to show both.
  --mark <name>     save the post-command scene as a checkpoint ('gdli mark' lists them; re-marking
                    the same name overwrites).
  --ticks <n>       (with --diff/--mark) wait n idle frames before the after-snapshot. default 0
  --physics <n>     (with --diff/--mark) wait n physics frames instead.
  --time <s>        (with --diff/--mark) wait s seconds instead.
  --ignore <glob>   drop matching scene-relative paths from the diff (one-shot; e.g. Mover, UI/*).
  --data            show the verb's own data even when --diff is present.
  --headless        if nothing's running, spawn a transient HEADLESS instance for this command only
                    (no window) and stop it after. Bare eval does this by default when no instance is up.
  --timeout <dur>   stop waiting after dur (e.g. 500ms, 5s, 2m; bare numbers are seconds).
  --timewarning <dur>  warn after dur while still waiting. Use 0 to disable.
                    With --diff/--mark, requested settle time is added to both budgets.
  --json            machine-readable single-line output.
  --game / --editor / --port <n>   force the target instance.`;

const STATIC_USAGE = `gdli — Godot Agent CLI

usage: gdli <verb> [args] [global flags]

No Godot instance is running — but most verbs auto-launch one if needed (game by default; the
editor for editor-only verbs). Bare eval defaults to a transient, no-window run.
  gdli launch [--game|--editor] [--scene <path>] [--godot <path>]   default: game
      [--timeout <dur>] [--timewarning <dur>]                       save session defaults
  gdli launch --in-editor                                    open editor if needed, then play its scene
  gdli status [path]                                         report what's running for a project
  gdli kill [--both|--all|--editor|--game|--in-editor]       default: both processes

Set up the addon in your Godot project:
  gdli install [dir]                                         copy bundled addon (default: cwd)

Other:
  gdli check                                                 compile-check every .gd -> 'ok' or errors

Client-meta verbs (work offline):
  launch, status, kill, check, install, help, verbs

Once an instance is up, 'gdli verbs' lists every live server verb (scene load, node add, inspect,
screenshot, ...) and 'gdli help <verb>' details one. --godot/--scene apply to 'gdli launch' only.

${UNIVERSAL_FLAGS}`;

module.exports = { printOk, printErr, printLine, renderRegistry, renderVerbHelp, STATIC_USAGE, UNIVERSAL_FLAGS };
