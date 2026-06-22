---
name: gdli-develop-debug
description: Use when developing or debugging a Godot 4.x project through the gdli CLI — launching the editor/game, inspecting and mutating the live scene tree, proving changes with diffs, filtering noise, and scripting with eval. Power-user reference for the filtering args and the eval bridge.
---

# gdli — develop & debug

`gdli` drives a live Godot project over TCP. Verbs route to the running **game** if up, else the **editor** —
you never pick a port. Run `gdli verbs` for the live list, `gdli help <verb>` for one.

## Lifecycle (client-side)
- `gdli launch` — run the **game** (default). `gdli launch --editor` opens the editor; `--scene <path>` / `--godot <path>` optional.
- `gdli launch --in-editor` — ask an open editor to play its current scene (game spawns as the editor's child).
- `gdli status [path]` — what's running + ports. `gdli kill [--game|--editor|--in-editor]` — default kills both.
- `gdli check` — compile-check every `.gd` (instant if an instance is up, else headless). Failures land in `.gdli/failures.log` too.

## Verbs (server-side)
| Module | Verbs |
|---|---|
| scene | `scene tree` · `scene load <res://…>` · `scene save` (editor) |
| node | `node get <path> [--grep <re>]` · `node set <path> <prop> <value>` · `node add <parent> <Class> [--name --props]` · `node remove/reparent/call [--args]/attach/detach` |
| observe | `inspect [--root --depth --full --ui]` · `screenshot [--out --format]` |
| input (game) | `click` · `drag` · `hover` · `key <name>` · `act <action>` · `scroll` (positions: `x y` or `--ref @eN`) |
| introspect | `class list` · `class info <Class>` |
| eval | `eval <code | @handle> [--file --save --list --entry]` |
| file (editor) | `file read/create/list/delete` |

Paths are **scene-relative** (`.` = scene root); `@eN` refs (from `inspect`) work anywhere a path does.
Values decode via the codec: a tag (`{"__t":"Vector2","v":[1,2]}`) **or** a GDScript expression string
(`"Vector2(1,2)"`). `node set <value>` takes one such token raw; `--props`/`node call --args` are **JSON**
wrappers whose elements then decode (`--props '{"position":"Vector2(1,2)"}'`).

## Universal flags — proof & filtering (any verb)
- `--diff [mark]` — whole-scene delta before/after the command (`{added,removed,changed}`). Prints **only** the diff; add `--data` to also show the verb's return.
- `--mark <name>` — checkpoint the post-command scene; `--diff <name>` compares the current scene against that checkpoint. `gdli mark` lists them; re-marking overwrites. Marks live in the running instance (lost on kill).
- Settle (only with `--diff`/`--mark`; default = immediate): `--ticks <n>` idle frames · `--physics <n>` physics frames · `--time <s>` seconds — let deferred/physics effects land before the after-snapshot.
- `--ignore <globs>` — drop matching scene-relative paths from the diff (one-shot). `--ignore Mover` hides that node + subtree; `--ignore "UI/*"` globs; comma-separate to drop several: `--ignore "Mover,UI/*"`.
- `inspect` filters: `--root <path|@ref>` subtree only · `--depth <n>` cap (default unbounded) · `--full` all storage props (vs the salient set) · `--ui` only visible Controls, each with its screen rect.
- `node get --grep <regex>` filters property names.

## eval — the escape hatch & macro engine
`root` (scene root), `argv` (tokens after `@handle`), and **`gdli("verb args")`** are in scope. `gdli(...)` runs any
verb in-process by the *same string you'd type at the CLI* and returns its raw result — reuse the CLI vocabulary, no second API.
- Forms: a single expression (auto-returned), a statement block, or a full file (just write `func run():`/`func run(argv):` + helpers — no base class to extend).
- `eval --file <path>` runs a file. `eval --save <name> "<code>"` saves a macro to `.gdli/handles/`; `eval @<name> [args…]` runs it; `eval --list` lists. Macros are ephemeral (persistent logic → a plugin).
- Compile errors surface automatically.

## Common scenarios
```
gdli launch                                            # game up
gdli inspect --ui                                      # what's on screen (refs + rects)
gdli node add . Sprite2D --name Hero --diff            # add + prove it landed
gdli node set Hero position "Vector2(100,50)" --diff   # change one prop, see only the delta
gdli node get Hero --grep "position|scale"             # just the transform props
gdli inspect --mark t0; gdli act jump; gdli inspect --diff t0 --physics 6 --ignore Mover
                                                       # what the jump changed, after 6 physics frames, minus the demo mover
gdli eval 'root.get_node("Hero").get_child_count()'    # quick read (single expr, auto-returned)
gdli eval 'gdli("node add . Timer --name T")["path"]'  # compose a verb in raw GDScript (one expr)
gdli eval --file scripts/spawn_wave.gd                 # multi-statement logic: write func run(): in a file
gdli eval --save bullets 'root.get_tree().get_nodes_in_group("bullets").size()'
gdli eval @bullets                                     # reuse it
gdli check                                             # did anything stop compiling?
gdli kill
```

Tip: when a command fails, check `.gdli/failures.log` (timestamp · command · error), segmented per `launch`.
