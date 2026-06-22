---
name: gdli-maintain-extend
description: Use when modifying the gdli harness itself — adding or changing verbs, touching the core, or writing a plugin. Gives the top-down architecture, a map of entry points into the codebase, and the design principles that shaped it.
---

# gdli — maintain & extend

## Architecture (top-down)
A dependency-free **Node client** talks to a **GDScript server** over TCP/NDJSON: one TCP conn per command,
`{id,cmd,params}` → `{id,ok,data}` | `{id,ok:false,err:{code,message}}`. The *same* GDScript core is hosted **twice** —
as an `@tool EditorPlugin` (editor) and an autoload (game) — each binding an **ephemeral** port written to
`.gdli/<editor|game>.port`. The client discovers the port from cwd and routes each verb by its `meta.target`
(`auto` = game-if-up-else-editor; `game`; `editor`). Snapshots are rooted at the **scene** (never `/root`), so editor
GUI / autoloads / the harness are excluded by construction.

A verb is `register(module, name, handler, meta)`; `name` is **both** the CLI path and the wire `cmd`. Plugins
register the same way → their verbs appear in `verbs` and route with **zero client changes**.

## Codebase map (entry points)
**Client (`addons/godot_agent_cli/cli/`)** — `node addons/godot_agent_cli/cli/bin/gdli.js`
- `bin/gdli.js` — arg parsing, meta-verb dispatch (launch/status/kill/check/install/help/verbs), failure logging.
- `src/router.js` — registry fetch + cache, longest-prefix verb match, arg parsing, port resolution.
- `src/client.js` — TCP `send`/`probe`, `projectRoot`, `resolvePorts`.
- `src/launch.js` — spawn/kill processes, `status`, in-editor `play`/`stop`, headless `check`.
- `src/format.js` — output rendering, `STATIC_USAGE`, `UNIVERSAL_FLAGS`. `src/install.js` — copy the addon into a project.

**Server (`addons/godot_agent_cli/`)**
- `plugin.gd` — `@tool` EditorPlugin: adds the autoload + hosts the editor server.
- `core/server.gd` (`class_name GdliServer`) — TCP poll, `_dispatch` (incl. `--diff`/`--mark`/settle + reserved `play`/`stop` control commands), and the helper API modules use (`resolve_node`, `target_root`, `to_json`/`from_json`, `diff`, `mint_refs`, `screen_pos`, `call_gdli_string`, `err`).
- `core/registry.gd` · `codec.gd` · `diff.gd` (snapshot/compare/glob-filter) · `config.gd` (denylist) · `check_lib.gd` · `eval_base.gd` (`GdliEval` context for eval scripts).
- `modules/*_mod.gd` — one file per module (core/scene/node/observe/input/introspect/eval/file), each a `register_into(server)`.
- `tools/check.gd` — headless compile-checker entry. `config.json` — disabled-module denylist.

**Plugins** — drop `addons/<name>/gdli_module.gd` with `register_into(server)`; auto-discovered at boot. Full guide: `docs/PLUGINS.md`. Reference: `addons/example_plugin/`.

## Adding a verb
- **Built-in**: add a `register(...)` + handler in the relevant `modules/<x>_mod.gd`. Handler is `func(p: Dictionary) -> Variant`; read args by key (dashes stripped), return any JSON-able value or `s.err(code, msg)`.
- **Plugin**: same, in your own addon's `gdli_module.gd` — no client changes.

## Design principles (what shaped this)
1. **Test like the player.** No unit tests — they're a false sense of confidence and tech debt. Manual playtesting with paired visual + scene-tree proof is the gate. (`tests/` was deleted on purpose.)
2. **Say less, do more.** Minimize tokens/latency on critical paths. `gdli`≈2 tokens, `<verb>`≈1, `--flag`≈2 — ~3–10 tokens/action vs verbose, research-heavy GDScript.
3. **Don't make the agent worry.** Lean defaults that just work, progressive disclosure in `--help`, one vocabulary reused everywhere (the CLI strings work inside `eval` via `gdli("…")`).
4. **One core, hosted twice.** Don't fork editor/game logic; share it and branch on `is_editor()` where needed.
5. **Diffs + `@eN` refs are the differentiators.** Structural proof on every action; handles instead of pixel coordinates.
6. **Extend via plugins**, not core bloat — fits a model ↔ view-controller split (game logic dependency-free; the plugin is a second controller over the live game).

## Gotchas (learned the hard way)
- GDScript `:=` can't infer through Variant-returning calls — type explicitly or leave untyped.
- `_get`/`_set` are reserved Object virtuals — don't name handlers that.
- Launch the **GUI** Godot exe, not `_console.exe` (the wrapper orphans windows past tree-kill).
- Editor `screenshot` must switch the main screen to 2D/3D, render, capture, then restore.
- New `class_name` (e.g. `GdliEval`) needs an editor scan to register — open the editor once (or `godot --import`); inline eval sidesteps this by extending the base via path (`eval_mod.gd` does `extends "<eval_base.gd>"`).
- Review by driving the tool live, then **kill every instance** so nothing orphans.
