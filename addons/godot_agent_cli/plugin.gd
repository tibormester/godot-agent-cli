@tool
extends EditorPlugin

const AUTOLOAD := "GodotAgentCli"
const SERVER := "res://addons/godot_agent_cli/core/server.gd"

var _editor_server: Node = null

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		add_autoload_singleton(AUTOLOAD, SERVER)
	_editor_server = load(SERVER).new()
	_editor_server.name = "GodotAgentCliEditor"
	_editor_server.self_drive = false
	add_child(_editor_server)

func _exit_tree() -> void:
	if is_instance_valid(_editor_server):
		_editor_server.queue_free()
		_editor_server = null

func _process(_delta: float) -> void:
	# Drive the editor server explicitly — robust against editor idle throttling and
	# any ambiguity about whether an EditorPlugin child receives _process.
	if is_instance_valid(_editor_server):
		_editor_server.poll()
