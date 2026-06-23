# Writing a gdli plugin

A plugin adds verbs to the harness, alongside the built-in verbs, driven by the same
`gdli` client. The whole contract is **one file**.

## What does gdli do?

Gdli is a Node.js client that runs in your terminal. Paired with the gdli addon inside Godot â€” one instance in the editor (an @tool EditorPlugin) and one in the running game (an autoload), on separate ports.
Gdli handles the networking between the terminal cli and the addon as well as routing between the editor and game processes.
Additionally, Gdli implements core functionality sufficient for an agent to play and develop any game with Godot.

## What should a plugin do?

A plugin can do anything. I won't decide for you, but I will describe how I am creating plugins.
For granular actions, the gdli core is sufficient, but for more complex or repetitive composite actions, the granular vocabulary is painfully verbose and inefficient.
I enjoy using a model <-> view-controller split, where my game logic has no dependencies and the view controller depends on Godot. For my game's gdli plugin, I reuse this seam and create the plugin as a secondary controller and keep godot as the view. This makes it much easier for an agent to dynamically work with my live game.

## The contract

Drop `addons/<your_addon>/gdli_module.gd`:

```gdscript
extends RefCounted
var server

func register_into(srv) -> void:
	server = srv
	srv.registry.register("mygame", "mygame fps", _fps, {
		"help": "current frames per second.",
		"target": "game",
		"args": [],
	})

func _fps(_p: Dictionary) -> Variant:
	return {"fps": Performance.get_monitor(Performance.TIME_FPS)}
```

The harness scans `res://addons/*/gdli_module.gd` at boot **in both processes** (the editor
instance and the game instance), instantiates yours, and calls `register_into(server)` with that
process's live server. Your verb now shows up in `gdli verbs` and routes with zero client changes:

```
gdli mygame fps   ->   {"fps": 60}
```

The repository also ships a runnable plugin at `addons/gdli_plugin_example/gdli_module.gd`; use it as
a smoke test before writing your own. Its demo scene lives under
`res://addons/gdli_plugin_example/demo/main.tscn` and includes a `?` tutorial built from
the examples in the README, this plugin guide, and the bundled skills.

```
gdli gdli_plugin example greet Codex   ->   {"greeting": "hello, Codex"}
gdli gdli_plugin example setup --autoplay --record --record-seconds 45 --record-fps 8 --record-width 640
```

The setup verb keeps project-global demo state runtime-only, can auto-play the tutorial by typing each
command into the real in-game terminal, and can record a small WebM for embedded docs or review. The
tutorial adds `TerminalPanel` to the process-global ignore list before expensive diff steps.

## `register(module, name, handler, meta)`

- **module** â€” your namespace (e.g. `"mygame"`). Used for grouping and `gdli config --disable mygame`.
- **name** â€” the verb's CLI path *and* its wire id (e.g. `"mygame spawn"`). Multi-word is fine (the
  client greedily matches the longest registered name). Namespace it under your module to avoid
  colliding with the built-ins.
- **handler** â€” a `Callable`, `func(params: Dictionary) -> Variant`.
- **meta** â€” `{help, target, async?, args}`:
  - **help** â€” one line.
  - **target** â€” routing policy: `"auto"` (game if running, else the editor scene), `"game"`, or
    `"editor"`. The client picks the process from this.
  - **async** â€” set `true` if your handler `await`s (deferred ops); dispatch will await it.
  - **args** â€” `[{name, type, required, default, help}]`. A `name` without dashes is **positional**;
    with dashes it's a **flag**. `type` âˆˆ `string|int|float|bool|json`. The **param key your handler
    reads = the name minus leading dashes** (`--root` â†’ `params.root`, positional `path` â†’ `params.path`).

## Handlers

```gdscript
func _spawn(p: Dictionary) -> Variant:
	var parent = server.resolve_node(str(p.get("parent", "")))      # scene-relative path or @ref
	if parent == null:
		return server.err("not_found", "no node: " + str(p.get("parent", "")))
	var pos = server.from_json(p.get("at"))                          # decode a typed input
	...
	return {"spawned": server.rel_path(node), "at": server.to_json(pos)}   # encode typed output
```

- **Read args** from `p` by key (name minus dashes).
- **Decode typed inputs** with `server.from_json(...)` â€” it accepts the tagged form
  `{"__t":"Vector2","v":[1,2]}` *or* a Godot expression string (`"Vector2(1,2)"`). Plain
  strings/ints/bools come through as-is.
- **Return** any JSON-able value as `data` â€” strings/numbers/bools/arrays/dicts pass through. Engine
  types (Vector2, Color, Node, â€¦) don't *need* encoding: `JSON.stringify` auto-converts them to a lossy
  string (`Vector2(1,2)` â†’ `"(1.0, 2.0)"`), fine if you're just printing. Wrap with `server.to_json(...)`
  only when you want the **structured, machine-readable** form (`{"__t":"Vector2","v":[1,2]}`) â€”
  parseable back, round-trippable into a typed arg, diffable. That's why the built-ins use it.
- **Fail** by returning `server.err(code, message)` (codes are free-form; the built-ins use
  `not_found`/`bad_params`/`handler_error`/`editor_only`/`game_only`). Anything else is success.

## The `server` API

`server` is the live core for *this* process. Plugins call it dynamically (no type import):

| Call | Does |
|---|---|
| `server.registry.register(...)` | register a verb |
| `server.to_json(v)` / `from_json(v)` | the Variant â†” JSON codec |
| `server.resolve_node(path\|@ref)` | a node by scene-relative path or `@eN` ref (or null) |
| `server.target_root()` | the scene root (game `current_scene` / editor edited scene) |
| `server.rel_path(node)` | node â†’ scene-relative path string |
| `server.is_editor()` | which process you're in |
| `server.editor_interface()` | `EditorInterface` (editor only) or null |
| `server.diff.snapshot(root, depth, full)` / `diff.compare(old, new)` | structural snapshots/diffs |
| `server.ignore_list()` / `ignore_add(pattern)` / `ignore_remove(pattern)` / `ignore_clear()` | process-global diff ignore state |
| `server.mint_refs(nodes)` | mint `@eN` refs for those nodes (returns `["@e1", â€¦]`) |
| `server.screen_pos(node\|@ref)` | a node/ref â†’ screen position (Control center / Node2D origin, else null) |
| `server.call_gdli_string(cmd)` | run any verb by its CLI string in-process, raw result (the `gdli("â€¦")` bridge in eval) |
| `server.err(code, msg)` | return an error |

(`--diff` / `--mark` are handled by the dispatcher around *every* verb, so plugins never touch them â€”
your handler just mutates the scene and the core snapshots before/after. Process-global ignores are
also applied by the core before snapshotting. There's no per-verb baseline API.)

## Refs (`@eN`)

A ref is a short, stable handle for a node so an agent doesn't have to echo long paths. The lifecycle is
two halves, both on `server`, so your plugin can mint and consume them exactly like the built-ins:

- **Mint** â€” `server.mint_refs(nodes)` assigns `@e1, @e2, â€¦` to a list of nodes and returns the labels.
  The built-in `inspect` (and `inspect --ui`) calls this so every node it reports carries a `ref`. Minting
  resets the table, so the most recent snapshot's refs are the live ones.
- **Consume** â€” `server.resolve_node("@e2")` returns the node (it accepts a path *or* a ref everywhere),
  and `server.screen_pos("@e2")` returns its screen position. Every input verb (`click`, `drag`,
  `release`, `hover`, `scroll`) accepts a ref via `--ref`/`--ref2` in place of `x y` coordinates, by routing through
  `screen_pos`. A plugin that takes a position should do the same: `var pos = server.screen_pos(p.get("ref", ""))`.

`server` is also a `Node`, so `server.get_tree()`, `server.add_child(...)` work (e.g. to `await
server.get_tree().process_frame` in an async handler).

## Targeting

The target policy routes the verb but since `auto` can land either way, you can make verbs polymorphic based on is_editor():

```gdscript
if not server.is_editor():
	pass  # game instance logic
# or, for input-like verbs:
if server.is_editor():
	pass  # editor instance logic
```

## Reaching autoloads

`resolve_node` is **scene-scoped**. Autoloads and singletons live under `/root` (siblings of the
scene), so reach them via the tree root:

```gdscript
var autoload = server.get_tree().root.get_node_or_null("MyAutoload")
if autoload == null:
	return server.err("handler_error", "autoload not present")

data = {}

autoload.verb_relevant_method(data)

return data
```

## Lifecycle

- **Enable/disable** â€” your module toggles by name: `gdli config --disable mygame` (persists, applies
  live; the server mtime-watches `config.json`). Disabled modules vanish from `verbs` and dispatch.
- **Two instances** â€” a `game`-target verb runs in the game process against the game server; an
  `editor`-target verb runs in the editor. `auto`-target verbs run in both, prefering game over editor.
   Each process has its own plugin instance; you never reach cross processes â€” the client routes per verb.

## Testing

Drive it with the tool: `gdli verbs` shows your verbs; run them and assert via the structural diff
(`<verb> --diff`) or `eval`. If the scene has high-churn debug UI, add a process-global ignore once
before proof commands, for example `gdli ignore add DebugOverlay`.
