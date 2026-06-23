extends RefCounted
## Scoped gdli example plugin.
##
## This addon demonstrates collision-resistant plugin naming and thin domain
## verbs. The commands intentionally call a small public API on the current
## scene instead of reaching into demo internals.

const MODULE := "gdli_plugin_example"
const ROOT_VERB := "gdli_plugin example"

var server

func register_into(srv) -> void:
	server = srv
	_register("greet", _greet, "greet by name (proves plugin auto-discovery + routing).", [
		{"name": "name", "type": "string", "required": false, "default": "world", "help": "who to greet"},
	])
	_register("setup", _setup, "configure demo-specific runtime project state.", [
		{"name": "--autoplay", "type": "bool", "required": false, "default": false, "help": "start the tutorial and auto-submit each typed command after a short pause"},
		{"name": "--record", "type": "bool", "required": false, "default": false, "help": "capture a low-resolution tutorial recording"},
		{"name": "--record-loop", "type": "bool", "required": false, "default": false, "help": "record one autoplay tutorial loop and stop when it returns to step 1"},
		{"name": "--record-out", "type": "string", "required": false, "default": "res://addons/gdli_plugin_example/docs/assets/demo-autoplay.webm", "help": "video output path for --record"},
		{"name": "--record-seconds", "type": "float", "required": false, "default": 45.0, "help": "seconds to record"},
		{"name": "--record-fps", "type": "int", "required": false, "default": 8, "help": "capture frames per second"},
		{"name": "--record-width", "type": "int", "required": false, "default": 640, "help": "recorded video width in pixels"},
		{"name": "--ffmpeg", "type": "string", "required": false, "default": "ffmpeg", "help": "ffmpeg executable for encoding the captured frames"},
	])
	_register("console clear", _console_clear, "clear the gdli demo console transcript.")
	_register("enemies clear", _enemies_clear, "clear enemies through the demo scene API.")
	_register("enemies spawn", _enemies_spawn, "spawn enemies through the demo scene API.", [
		{"name": "count", "type": "int", "required": false, "default": 1, "help": "number of enemies to spawn"},
	])
	_register("wave next", _wave_next, "advance to the next demo wave.")
	_register("wave finish", _wave_finish, "finish the current demo wave.")
	_register("items collect best", _items_collect_best, "collect scene loot into the best inventory slot.")

func _register(suffix: String, handler: Callable, help: String, args: Array = []) -> void:
	server.registry.register(MODULE, "%s %s" % [ROOT_VERB, suffix], handler, {
		"help": help,
		"target": "game",
		"args": args,
	})

func _greet(p: Dictionary) -> Variant:
	return {"greeting": "hello, %s" % str(p.get("name", "world"))}

func _setup(p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_setup", [p])

func _console_clear(_p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_console_clear")

func _enemies_clear(_p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_enemies_clear")

func _enemies_spawn(p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_enemies_spawn", [maxi(0, int(p.get("count", 1)))])

func _wave_next(_p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_wave_next")

func _wave_finish(_p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_wave_finish")

func _items_collect_best(_p: Dictionary) -> Variant:
	return _call_scene("gdli_plugin_example_items_collect_best")

func _call_scene(method: String, args: Array = []) -> Variant:
	var root: Node = server.target_root()
	if root == null:
		return server.err("wrong_scene", "no current scene is available")
	if not root.has_method(method):
		return server.err(
			"missing_method",
			"current scene '%s' does not implement %s()" % [str(root.name), method]
		)
	return root.callv(method, args)
