extends "res://addons/godot_agent_cli/core/eval_base.gd"

func run():
	if not root.has_method("tutorial_spawn_loot"):
		return {"ok": false, "message": "current scene is not the gdli tutorial demo"}
	return root.tutorial_spawn_loot()
