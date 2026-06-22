extends SceneTree
## gdli compile-check — the headless fallback for `gdli check` when no instance is running. Run:
##   godot --headless --path <project> --script res://addons/godot_agent_cli/tools/check.gd
## Prints a one-line JSON sentinel of the .gd files that fail to compile, then quits 0 (clean) / 1.
## The engine's own parse-error text (stderr) carries the line/message detail the client surfaces.
## (Work happens in _initialize(), not _init(): quit() only takes effect once the main loop is live.)

const Check := preload("res://addons/godot_agent_cli/core/check_lib.gd")

func _initialize() -> void:
	var failures := Check.failing_scripts("res://")
	print("GDLI_CHECK_RESULT:" + JSON.stringify(failures))
	quit(1 if failures.size() > 0 else 0)
