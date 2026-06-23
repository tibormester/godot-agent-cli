extends RefCounted

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")

var owner: Node
var terminal_panel: Control
var terminal_shade: ColorRect
var terminal_output: RichTextLabel
var tutorial_button: Button
var input_row: HBoxContainer
var command_input: TextEdit
var submit_button: Button
var submit_blocked: Callable

var transcript: Array[String] = []
var terminal_last_output_msec := 0
var terminal_collapsed := false

func _init(scene_owner: Node) -> void:
	owner = scene_owner

func bind(nodes: Dictionary, is_submit_blocked: Callable) -> void:
	terminal_panel = nodes["terminal_panel"]
	terminal_shade = nodes["terminal_shade"]
	terminal_output = nodes["terminal_output"]
	tutorial_button = nodes["tutorial_button"]
	input_row = nodes["input_row"]
	command_input = nodes["command_input"]
	submit_button = nodes["submit_button"]
	submit_blocked = is_submit_blocked
	submit_button.pressed.connect(submit_terminal)
	command_input.gui_input.connect(on_command_input_gui_input)
	command_input.text_changed.connect(sync_terminal_input_height)
	command_input.focus_entered.connect(refresh_terminal_layout)
	command_input.focus_exited.connect(refresh_terminal_layout)
	terminal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terminal_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE

func clear_console() -> Dictionary:
	reset_terminal()
	return {
		"ok": true,
		"hint": DemoConfig.TERMINAL_HINT,
	}

func submit_terminal() -> void:
	if submit_blocked.is_valid() and bool(submit_blocked.call()):
		return
	var command := command_input.text.strip_edges()
	if command.is_empty():
		return
	command_input.text = ""
	sync_terminal_input_height()
	command_input.release_focus()
	await run_terminal_command(command)

func on_command_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if event.shift_pressed:
				return
			command_input.accept_event()
			owner.get_viewport().set_input_as_handled()
			submit_terminal()

func terminal_handles_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if command_input.get_global_rect().has_point(event.position):
			command_input.grab_focus()
			return true
		if terminal_collapsed and terminal_output.get_global_rect().has_point(event.position):
			expand_terminal_output()
			return true
		if not terminal_panel.get_global_rect().has_point(event.position) and command_input.has_focus():
			command_input.release_focus()
			return false
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if terminal_output.get_global_rect().has_point(event.position):
			var over_input := command_input.get_global_rect().has_point(event.position)
			var output_is_target := terminal_output.get_global_rect().has_point(event.position) or not terminal_output.get_selected_text().is_empty()
			if over_input and terminal_input_line_count() > 1 and not output_is_target:
				return true
			if terminal_collapsed:
				expand_terminal_output()
			var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			scroll_terminal_output(direction * DemoConfig.TERMINAL_SCROLL_LINES)
			owner.get_viewport().set_input_as_handled()
			return true
	if command_input.has_focus() and event is InputEventKey:
		return true
	if event is InputEventMouse and terminal_owns_mouse_position(event.position):
		return true
	return false

func sync_terminal_input_height() -> void:
	var line_count: int = max(1, command_input.get_line_count())
	var visible_lines: int = min(line_count, DemoConfig.TERMINAL_INPUT_MAX_LINES)
	var height: float = max(DemoConfig.TERMINAL_INPUT_MIN_HEIGHT, float(visible_lines) * DemoConfig.TERMINAL_INPUT_LINE_HEIGHT + DemoConfig.TERMINAL_INPUT_PADDING)
	command_input.custom_minimum_size.y = height
	submit_button.custom_minimum_size.y = height
	input_row.offset_top = DemoConfig.TERMINAL_INPUT_ROW_BOTTOM - height
	input_row.offset_bottom = DemoConfig.TERMINAL_INPUT_ROW_BOTTOM
	refresh_terminal_layout()

func refresh_terminal_layout() -> void:
	var should_collapse := should_collapse_terminal_output()
	if should_collapse == terminal_collapsed and terminal_output.offset_bottom > 0.0:
		return
	terminal_collapsed = should_collapse
	var output_bottom := input_row.offset_top - DemoConfig.TERMINAL_INPUT_OUTPUT_GAP
	if terminal_collapsed:
		terminal_output.offset_top = output_bottom - DemoConfig.TERMINAL_OUTPUT_LINE_HEIGHT
		terminal_output.offset_bottom = output_bottom
		terminal_shade.offset_top = terminal_output.offset_top - DemoConfig.TERMINAL_SHADE_PADDING
		terminal_shade.offset_bottom = input_row.offset_bottom + DemoConfig.TERMINAL_SHADE_PADDING
	else:
		terminal_output.offset_top = DemoConfig.TERMINAL_OUTPUT_TOP_EXPANDED
		terminal_output.offset_bottom = output_bottom
		terminal_shade.offset_top = 0.0
		terminal_shade.offset_bottom = DemoConfig.TERMINAL_INPUT_ROW_BOTTOM + DemoConfig.TERMINAL_SHADE_PADDING
	scroll_terminal_to_end()

func update_terminal_collapse() -> void:
	refresh_terminal_layout()

func terminal_input_line_count() -> int:
	return max(1, command_input.get_line_count())

func has_input_focus() -> bool:
	return command_input.has_focus()

func run_terminal_command(command: String) -> Variant:
	append_terminal("$ " + command)
	if command == "clear":
		reset_terminal()
		var cleared := {"ok": true, "cleared": true}
		owner.terminal_command_finished.emit(command, cleared)
		return cleared
	var server := owner.get_node_or_null("/root/GodotAgentCli")
	if server == null or not (server.has_method("call_gdli_string_async") or server.has_method("call_gdli_string")):
		append_terminal("GodotAgentCli singleton not found.")
		var missing := {"code": "not_found", "message": "GodotAgentCli singleton not found."}
		owner.terminal_command_finished.emit(command, missing)
		return missing
	var routed := command
	if routed.begins_with("gdli "):
		routed = routed.substr(5).strip_edges()
	if routed.begins_with("help "):
		var help_text := format_terminal_help(routed.substr(5).strip_edges(), server)
		append_terminal(help_text)
		owner.terminal_command_finished.emit(command, help_text)
		return help_text
	if routed == "--help" or routed == "help":
		routed = "verbs"
	var result: Variant
	if server.has_method("call_gdli_string_async"):
		result = await server.call_gdli_string_async(routed)
	else:
		result = server.call_gdli_string(routed)
	var formatted := format_terminal_result(result)
	if (command == "gdli --help" or command == "gdli help" or command == "--help" or command == "help") and looks_like_registry(result):
		formatted += "\n\n" + DemoConfig.GDLI_UNIVERSAL_FLAGS
	append_terminal(formatted)
	owner.terminal_command_finished.emit(command, result)
	return result

func append_terminal(line: String) -> void:
	terminal_last_output_msec = Time.get_ticks_msec()
	transcript.append(line)
	while transcript.size() > 80:
		transcript.pop_front()
	terminal_output.text = "\n".join(transcript)
	refresh_terminal_layout()
	await owner.get_tree().process_frame
	scroll_terminal_to_end()

func reset_terminal() -> void:
	terminal_last_output_msec = Time.get_ticks_msec()
	transcript.clear()
	transcript.append(DemoConfig.TERMINAL_HINT)
	terminal_output.text = DemoConfig.TERMINAL_HINT
	refresh_terminal_layout()

func format_terminal_help(verb_name: String, server: Node) -> String:
	var result: Variant = server.call_gdli_string("verbs")
	if not looks_like_registry(result):
		return format_terminal_result(result)
	for entry in result:
		if str(entry.get("name", "")) == verb_name:
			return render_verb_help(entry) + "\n\n" + DemoConfig.GDLI_UNIVERSAL_FLAGS
	return "error: not_found: unknown verb: %s" % verb_name

func format_terminal_result(value: Variant) -> String:
	if value is Dictionary and value.has("code") and value.has("message"):
		return "error: %s: %s" % [str(value["code"]), str(value["message"])]
	if value is Dictionary and (value.has("diff") or value.has("marked")):
		return format_terminal_envelope(value)
	if looks_like_registry(value):
		return render_registry(value)
	return format_terminal_data(value)

func format_terminal_envelope(env: Dictionary) -> String:
	var lines: Array[String] = []
	if not env.has("diff"):
		lines.append(format_terminal_data(env.get("data")))
	if env.has("diff"):
		lines.append("diff:\n" + JSON.stringify(env["diff"], "  "))
	if env.has("marked"):
		lines.append("marked: " + str(env["marked"]))
	return "\n".join(lines)

func format_terminal_data(value: Variant) -> String:
	if looks_like_registry(value):
		return render_registry(value)
	return JSON.stringify(value, "  ")

func looks_like_registry(value: Variant) -> bool:
	if not (value is Array):
		return false
	if value.is_empty():
		return false
	for entry in value:
		if not (entry is Dictionary) or not entry.has("module") or not entry.has("name") or not entry.has("target") or not entry.has("help"):
			return false
	return true

func render_registry(registry: Array) -> String:
	var modules := {}
	for entry in registry:
		var module := str(entry.get("module", ""))
		if not modules.has(module):
			modules[module] = []
		(modules[module] as Array).append(entry)
	var module_names := modules.keys()
	module_names.sort()
	var lines: Array[String] = []
	for module in module_names:
		lines.append("\n" + str(module))
		var entries: Array = modules[module]
		entries.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
		for entry in entries:
			lines.append("  %s  [%s]  %s" % [str(entry.get("name", "")), str(entry.get("target", "auto")), str(entry.get("help", ""))])
	return "\n".join(lines).strip_edges()

func render_verb_help(entry: Dictionary) -> String:
	var lines: Array[String] = ["%s  [%s]  %s" % [str(entry.get("name", "")), str(entry.get("target", "auto")), str(entry.get("help", ""))]]
	var args: Array = entry.get("args", [])
	if not args.is_empty():
		lines.append("args:")
		for arg in args:
			var required := " (required)" if bool(arg.get("required", false)) else ""
			var default_text := ""
			if arg.has("default") and arg["default"] != null and str(arg["default"]) != "":
				default_text = " [default: %s]" % JSON.stringify(arg["default"])
			lines.append("  %s <%s>%s%s  %s" % [str(arg.get("name", "")), str(arg.get("type", "string")), required, default_text, str(arg.get("help", ""))])
	return "\n".join(lines)

func should_collapse_terminal_output() -> bool:
	if command_input.has_focus():
		return false
	if not terminal_output.get_selected_text().is_empty():
		return false
	return Time.get_ticks_msec() - terminal_last_output_msec >= DemoConfig.TERMINAL_IDLE_COLLAPSE_MSEC

func terminal_owns_mouse_position(position: Vector2) -> bool:
	if command_input.get_global_rect().has_point(position):
		return true
	if submit_button.get_global_rect().has_point(position):
		return true
	if input_row.get_global_rect().has_point(position):
		return true
	if tutorial_button.get_global_rect().has_point(position):
		return true
	if terminal_output.get_global_rect().has_point(position):
		return true
	return false

func expand_terminal_output() -> void:
	terminal_last_output_msec = Time.get_ticks_msec()
	if terminal_collapsed:
		terminal_collapsed = false
	terminal_output.offset_top = DemoConfig.TERMINAL_OUTPUT_TOP_EXPANDED
	terminal_output.offset_bottom = input_row.offset_top - DemoConfig.TERMINAL_INPUT_OUTPUT_GAP
	terminal_shade.offset_top = 0.0
	terminal_shade.offset_bottom = DemoConfig.TERMINAL_INPUT_ROW_BOTTOM + DemoConfig.TERMINAL_SHADE_PADDING
	scroll_terminal_to_end()

func scroll_terminal_output(line_delta: int) -> void:
	var scrollbar := terminal_output.get_v_scroll_bar()
	if scrollbar == null:
		return
	scrollbar.value = clampf(scrollbar.value + float(line_delta) * scrollbar.step, scrollbar.min_value, scrollbar.max_value)

func scroll_terminal_to_end() -> void:
	terminal_output.scroll_to_line(max(terminal_output.get_line_count() - 1, 0))
