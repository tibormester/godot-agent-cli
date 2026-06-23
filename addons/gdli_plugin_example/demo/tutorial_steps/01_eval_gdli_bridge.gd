extends "res://addons/godot_agent_cli/core/eval_base.gd"

func run():
	return {
		"bridge": gdli("gdli_plugin example greet Tutorial"),
		"root": root.name,
		"child_count": root.get_child_count(),
	}
