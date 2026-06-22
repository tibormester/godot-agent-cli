extends RefCounted
## core module — meta + run control. (attach/launch/kill are client-side; they spawn/connect
## to the OS process and never reach the server.)

const Config := preload("res://addons/godot_agent_cli/core/config.gd")
const Check := preload("res://addons/godot_agent_cli/core/check_lib.gd")

var s: GdliServer

func register_into(server: GdliServer) -> void:
	s = server
	s.registry.register("core", "verbs", _list, {
		"help": "list every registered verb with its target + args (the live registry).",
		"target": "auto", "args": [],
	})
	s.registry.register("core", "config", _config, {
		"help": "report modules + ports; --enable/--disable a module (persists, applies live).",
		"target": "auto",
		"args": [
			{"name": "--enable", "type": "string", "required": false, "default": "", "help": "re-enable a module"},
			{"name": "--disable", "type": "string", "required": false, "default": "", "help": "disable a module"},
		],
	})
	s.registry.register("core", "mark", _list_marks, {
		"help": "list named diff checkpoints (create via <verb> --mark <name>; re-marking overwrites).",
		"target": "auto",
		"args": [{"name": "--list", "type": "bool", "required": false, "default": false, "help": "list checkpoints (default)"}],
	})
	s.registry.register("core", "check", _check, {
		"help": "compile-check every .gd under res://; returns the files that fail to parse (or none).",
		"target": "auto", "args": [],
	})

func _list(_p: Dictionary) -> Variant:
	return s.registry.list_meta()

func _config(p: Dictionary) -> Variant:
	var enable := str(p.get("enable", ""))
	var disable := str(p.get("disable", ""))
	if not enable.is_empty() or not disable.is_empty():
		var dis: Array = Config.load_config()["disabled"]
		if not disable.is_empty() and disable != "core" and not dis.has(disable):
			dis.append(disable)
		if not enable.is_empty():
			dis.erase(enable)
		var e := Config.save_config(dis)
		if e != OK:
			return s.err("handler_error", "cannot write config: " + error_string(e))
		s.reload_config()
	return {
		"instance": "editor" if s.is_editor() else "game",
		"port": s._port(),
		"modules": s.registry.all_modules(),
		"disabled": s.registry.disabled_list(),
	}

func _list_marks(_p: Dictionary) -> Variant:
	return {"marks": s.mark_names()}

func _check(_p: Dictionary) -> Variant:
	return {"failures": Check.failing_scripts("res://")}
