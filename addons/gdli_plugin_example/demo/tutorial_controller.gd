extends RefCounted

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")
const TutorialSteps = preload("res://addons/gdli_plugin_example/demo/tutorial_steps.gd")

var owner: Node
var terminal
var recording
var tutorial_popup: PanelContainer
var tutorial_title: Label
var tutorial_body: Label
var reset_demo: Callable

var steps: Array[Dictionary] = []
var active := false
var index := -1
var typing := false
var autoplay := false

func _init(scene_owner: Node) -> void:
	owner = scene_owner

func bind(nodes: Dictionary, terminal_controller, recording_controller, reset_demo_state: Callable) -> void:
	tutorial_popup = nodes["tutorial_popup"]
	tutorial_title = nodes["tutorial_title"]
	tutorial_body = nodes["tutorial_body"]
	terminal = terminal_controller
	recording = recording_controller
	reset_demo = reset_demo_state
	steps = TutorialSteps.all()
	nodes["tutorial_button"].pressed.connect(on_tutorial_button_pressed)
	owner.terminal_command_finished.connect(on_terminal_command_finished)

func start_requested_by_setup() -> Dictionary:
	owner.call_deferred("_start_tutorial_autoplay")
	return {
		"started": true,
		"submit_delay_seconds": DemoConfig.TUTORIAL_AUTOPLAY_SUBMIT_DELAY,
		"loops": true,
	}

func on_tutorial_button_pressed() -> void:
	start(false)

func start(should_autoplay: bool = false) -> void:
	var finishing_loop_recording: bool = recording.loop_once and recording.waiting_for_loop_end
	active = false
	typing = false
	autoplay = should_autoplay
	if reset_demo.is_valid():
		reset_demo.call()
	terminal.reset_terminal()
	active = true
	index = 0
	show_step()
	if recording.pending_loop_start:
		recording.begin_loop_recording()
	elif finishing_loop_recording:
		recording.waiting_for_loop_end = false
		await owner.get_tree().process_frame
		recording.capture_frame()
		recording.finish_loop_recording()
	type_command(str(steps[index]["command"]))

func show_step() -> void:
	if index < 0 or index >= steps.size():
		return
	var step := steps[index]
	tutorial_popup.visible = true
	tutorial_title.text = "Step %d/%d - %s" % [
		index + 1,
		steps.size(),
		str(step.get("chapter", "Tutorial")),
	]
	tutorial_body.text = "%s\n\nCommand:\n%s\n\nPress Enter or the arrow button to run it." % [
		str(step.get("body", "")),
		str(step.get("command", "")),
	]

func type_command(command: String) -> void:
	typing = true
	terminal.command_input.text = ""
	terminal.command_input.grab_focus()
	for i in command.length():
		if not active:
			typing = false
			return
		terminal.command_input.text += command[i]
		terminal.command_input.set_caret_line(terminal.command_input.get_line_count() - 1)
		terminal.command_input.set_caret_column(terminal.command_input.get_line(terminal.command_input.get_caret_line()).length())
		terminal.sync_terminal_input_height()
		await owner.get_tree().create_timer(DemoConfig.TUTORIAL_TYPE_DELAY).timeout
	typing = false
	if autoplay and active:
		await owner.get_tree().create_timer(DemoConfig.TUTORIAL_AUTOPLAY_SUBMIT_DELAY).timeout
		if autoplay and active and terminal.command_input.text.strip_edges() == command:
			await terminal.submit_terminal()

func on_terminal_command_finished(command: String, _result: Variant) -> void:
	if not active or index < 0 or index >= steps.size():
		return
	var expected := str(steps[index].get("command", ""))
	if command != expected:
		return
	index += 1
	if index >= steps.size():
		active = false
		tutorial_popup.visible = true
		tutorial_title.text = "Tutorial complete"
		if autoplay:
			tutorial_body.text = "The documentation-derived walkthrough is complete. Restarting from step 1."
			if recording.loop_once and recording.active:
				recording.waiting_for_loop_end = true
			terminal.command_input.text = ""
			terminal.sync_terminal_input_height()
			await owner.get_tree().create_timer(DemoConfig.TUTORIAL_LOOP_DELAY).timeout
			if autoplay:
				start(true)
			return
		tutorial_body.text = "The documentation-derived walkthrough is complete. The terminal remains live, and the scene can still be played normally."
		terminal.command_input.text = ""
		terminal.sync_terminal_input_height()
		return
	show_step()
	type_command(str(steps[index]["command"]))
