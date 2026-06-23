extends RefCounted
## core module — meta + run control. (attach/launch/kill are client-side; they spawn/connect
## to the OS process and never reach the server.)

const Config := preload("res://addons/godot_agent_cli/core/config.gd")
const Check := preload("res://addons/godot_agent_cli/core/check_lib.gd")

var s

func register_into(server) -> void:
	s = server
	s.registry.register("core", "verbs", _list, {
		"help": "list every registered verb with its target + args (the live registry).",
		"target": "auto", "args": [],
	})
	s.registry.register("core", "config", _config, {
		"help": "report modules + ports; --enable/--disable a module (persists, applies live).",
		"target": "auto",
		"args": [
			{"name": "--list", "type": "bool", "required": false, "default": false, "help": "report modules + ports (default)"},
			{"name": "--enable", "type": "string", "required": false, "default": "", "help": "re-enable a module"},
			{"name": "--disable", "type": "string", "required": false, "default": "", "help": "disable a module"},
		],
	})
	s.registry.register("core", "mark", _list_marks, {
		"help": "list named diff checkpoints (create via <verb> --mark <name>; re-marking overwrites).",
		"target": "auto",
		"args": [{"name": "--list", "type": "bool", "required": false, "default": false, "help": "list checkpoints (default)"}],
	})
	s.registry.register("core", "ignore list", _ignore_list, {
		"help": "list process-global diff ignore globs for this running Godot instance.",
		"target": "auto",
		"args": [],
	})
	s.registry.register("core", "ignore add", _ignore_add, {
		"help": "add a process-global diff ignore glob; combines with one-shot --ignore.",
		"target": "auto",
		"args": [{"name": "pattern", "type": "string", "required": true, "help": "scene-relative path or glob, e.g. TerminalPanel or UI/*"}],
	})
	s.registry.register("core", "ignore remove", _ignore_remove, {
		"help": "remove a process-global diff ignore glob.",
		"target": "auto",
		"args": [{"name": "pattern", "type": "string", "required": true, "help": "exact ignore pattern to remove"}],
	})
	s.registry.register("core", "ignore clear", _ignore_clear, {
		"help": "clear all process-global diff ignore globs.",
		"target": "auto",
		"args": [],
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

func _ignore_list(_p: Dictionary) -> Variant:
	return {"ignores": s.ignore_list()}

func _ignore_add(p: Dictionary) -> Variant:
	return s.ignore_add(str(p.get("pattern", "")))

func _ignore_remove(p: Dictionary) -> Variant:
	return s.ignore_remove(str(p.get("pattern", "")))

func _ignore_clear(_p: Dictionary) -> Variant:
	return s.ignore_clear()

func _check(_p: Dictionary) -> Variant:
	return {"failures": Check.failing_scripts("res://")}
