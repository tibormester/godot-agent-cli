---
name: gdli-develop-debug
description: Use when developing or debugging a Godot 4.x project through the gdli CLI â€” launching the editor/game, inspecting and mutating the live scene tree, proving changes with diffs, filtering noise, and scripting with eval. Power-user reference for the filtering args and the eval bridge.
---

# gdli â€” develop & debug

`gdli` drives a live Godot project over TCP. Verbs route to the running **game** if up, else the **editor** â€”
you never pick a port. Run `gdli verbs` for the live list, `gdli help <verb>` for one.

## Lifecycle (client-side)
- **Auto-launch (default):** you don't have to `launch` first â€” any verb that needs an instance spawns one (game by default; editor for `file`/`scene save`) and leaves it up for reuse. Bare `gdli eval ...` is the exception: if nothing is running, it uses a throwaway headless game instance and stops it after. `--headless <verb>` gives other verbs the same one-shot no-window behavior.
- `gdli launch` â€” run the **game** (default; explicit `--game`). `gdli launch --editor` opens the editor; `--scene <path>` / `--godot <path>` optional.
- `gdli launch --in-editor` â€” ask an open editor to play its current scene (game spawns as the editor's child).
- `gdli status [path]` â€” what's running + ports. `gdli kill [--both|--all|--game|--editor|--in-editor]` â€” default kills both.
- `gdli check` â€” compile-check every `.gd` (instant if an instance is up, else headless). Failures land in `.gdli/failures.log` too.
- Timing: `--timeout <dur>` stops the client waiting for a response; `--timewarning <dur>` warns while still waiting. Use on `launch` to save game/editor session defaults, or on one command to override. Durations accept `500ms`, `5s`, `2m`; bare numbers are seconds. This is client wall-clock behavior, so it cannot preempt GDScript already blocking Godot's main thread.

## Verbs (server-side)
| Module | Verbs |
|---|---|
| scene | `scene tree` Â· `scene load <res://â€¦>` Â· `scene save` (editor) |
| node | `node get <path> [--grep <re>]` Â· `node set <path> <prop> <value>` Â· `node add <parent> <Class> [--name --props]` Â· `node remove/reparent/call [--args]/attach/detach` |
| observe | `inspect [--root --depth --nodes --full --ui]` Â· `screenshot [--out --format]` |
| input (game) | `click` Â· `drag` Â· `hover` Â· `key <name>` Â· `act <action>` Â· `scroll` Â· `enter text` (positions: `x y` or `--ref '@eN'`) |
| introspect | `class list` Â· `class info <Class>` |
| eval | `eval <code | @handle> [--file --save --list --entry]` |
| file (editor) | `file read/create/list/delete` |

Paths are **scene-relative** (`.` = scene root); `@eN` refs (from `inspect`) work anywhere a path does.
Values decode via the codec: a tag (`{"__t":"Vector2","v":[1,2]}`) **or** a GDScript expression string
(`"Vector2(1,2)"`). `node set <value>` takes one such token raw; `--props`/`node call --args` are **JSON**
wrappers whose elements then decode (`--props '{"position":"Vector2(1,2)"}'`).

## Universal flags â€” proof & filtering (any verb)
- `--diff [mark]` â€” whole-scene delta before/after the command (`{added,removed,changed}`). Prints **only** the diff; add `--data` to also show the verb's return.
- `--mark <name>` â€” checkpoint the post-command scene; `--diff <name>` compares the current scene against that checkpoint. `gdli mark` lists them; re-marking overwrites. Marks live in the running instance (lost on kill).
- Settle (only with `--diff`/`--mark`; default = immediate): `--ticks <n>` idle frames Â· `--physics <n>` physics frames Â· `--time <s>` seconds â€” let deferred/physics effects land before the after-snapshot.
- `--ignore <globs>` â€” drop matching scene-relative paths from the diff (one-shot). `--ignore "UI/*"` hides matching UI subtrees; comma-separate to drop several: `--ignore "UI/*,DebugOverlay"`.
- `gdli ignore add <glob>` / `ignore list` / `ignore remove` / `ignore clear` manage process-global diff ignores. Use this for high-churn subtrees like `TerminalPanel` so later diffs skip them before snapshotting.
- `inspect` filters: `--root <path|@ref>` subtree only Â· `--depth <n>` cap (default unbounded) Â· `--full` all storage props (vs the salient set) Â· `--ui` only visible Controls, each with its screen rect.
- `node get --grep <regex>` filters property names.

## eval â€” the escape hatch & macro engine
`root` (scene root), `argv` (tokens after `@handle`), and **`gdli("verb args")`** are in scope. `gdli(...)` runs any
verb in-process by the *same string you'd type at the CLI* and returns its raw result â€” reuse the CLI vocabulary, no second API.
- Launch behavior: if a game or editor is running, `eval` uses it; otherwise bare `gdli eval ...` defaults to transient headless game. Use `--game`, `--editor`, or `--port` to force a live target.
- Forms: a single expression (auto-returned), a statement block, or a full file (just write `func run():`/`func run(argv):` + helpers â€” no base class to extend).
- `eval --file <path>` runs a file. `eval --save <name> "<code>"` saves a macro to `.gdli/handles/`; `eval '@<name>' [argsâ€¦]` runs it; `eval --list` lists. Macros are ephemeral (persistent logic â†’ a plugin).
- Compile errors surface automatically.

## Common scenarios
The repository demo (`res://addons/gdli_plugin_example/demo/main.tscn`) is a small arena game with a transparent typed terminal.
WASD moves the player, clicks swing a sword, enemies take two hits and drop loot, and loot can be
dragged into inventory slots. The terminal starts with only `type gdli --help for info`; submitted
commands call the `GodotAgentCli` singleton command parser directly. Press `?` in the terminal for a
long tutorial built from the README, plugin guide, and skill examples.

```
gdli launch --scene res://addons/gdli_plugin_example/demo/main.tscn --timeout 45s --timewarning 10s
gdli ignore add TerminalPanel                         # skip expensive terminal transcript diffs
gdli inspect --ui
gdli enter text "gdli --help" --ref TerminalPanel/InputRow/CommandInput --clear --submit
gdli key D --hold --diff --ticks 8                     # move player toward Enemy1
gdli key D --release
gdli click 752 286 --diff --ticks 1                    # first hit: HP bar shrinks
gdli click 752 286 --diff --ticks 2                    # second hit: enemy removed, loot drops
gdli inspect --mark before_loot
gdli drag --ref Arena/Loot/Loot1 --ref2 Hud/InventoryPanel/Margin/Rows/Slots/Slot1 --ticks 2
gdli inspect --diff before_loot                        # loot removed from world, Slot1 stack increments
gdli drag --ref Hud/InventoryPanel/Margin/Rows/Slots/Slot1 700 230 --hold --diff --ticks 1
gdli release 700 230 --ticks 1                         # release held inventory item back into the scene
gdli eval 'root.get_child_count()'                     # quick read (single expr, auto-returned)
gdli eval --save child_count 'root.get_child_count()'
gdli eval '@child_count'                               # reuse it
gdli eval --file res://addons/gdli_plugin_example/demo/tutorial_steps/01_eval_gdli_bridge.gd
gdli gdli_plugin example greet Codex                   # bundled plugin smoke test
gdli eval --file res://addons/gdli_plugin_example/demo/tutorial_steps/02_spawn_loot.gd --diff
gdli gdli_plugin example items collect best --diff
gdli check                                             # did anything stop compiling?
gdli kill
```

Tip: when a command fails, check `.gdli/failures.log` (timestamp Â· command Â· error), segmented per `launch`.
