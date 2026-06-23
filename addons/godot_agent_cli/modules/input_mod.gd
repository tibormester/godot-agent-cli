extends RefCounted
## input module — the real input pipeline (Input.parse_input_event), so the game reacts exactly
## as to a user. Game-pinned (inert in the editor). Positions from x/y or --ref (@eN -> node center).

var s

func register_into(server) -> void:
	s = server
	var pos_args := [
		{"name": "x", "type": "float", "required": false, "default": 0.0, "help": "x (omit if --ref)"},
		{"name": "y", "type": "float", "required": false, "default": 0.0, "help": "y (omit if --ref)"},
		{"name": "--ref", "type": "string", "required": false, "default": "", "help": "target node/@ref (uses its center)"},
		{"name": "--mods", "type": "json", "required": false, "default": [], "help": "modifiers: shift/ctrl/alt/meta"},
	]
	s.registry.register("input", "click", _click, {
		"help": "click at x y or --ref.", "target": "game",
		"args": pos_args + [{"name": "--button", "type": "string", "required": false, "default": "left", "help": "left|right|middle"}],
	})
	s.registry.register("input", "drag", _drag, {
		"help": "press at (x y), move to (x2 y2), then release unless --hold.", "target": "game",
		"args": [
			{"name": "x", "type": "float", "required": false, "default": 0.0, "help": "from x (omit if --ref)"},
			{"name": "y", "type": "float", "required": false, "default": 0.0, "help": "from y (omit if --ref)"},
			{"name": "x2", "type": "float", "required": false, "default": 0.0, "help": "to x (omit if --ref2)"},
			{"name": "y2", "type": "float", "required": false, "default": 0.0, "help": "to y (omit if --ref2)"},
			{"name": "--ref", "type": "string", "required": false, "default": "", "help": "from node/@ref (center)"},
			{"name": "--ref2", "type": "string", "required": false, "default": "", "help": "to node/@ref (center)"},
			{"name": "--button", "type": "string", "required": false, "default": "left", "help": "left|right|middle"},
			{"name": "--mods", "type": "json", "required": false, "default": [], "help": "modifiers"},
			{"name": "--hold", "type": "bool", "required": false, "default": false, "help": "press and move, but do not release"}],
	})
	s.registry.register("input", "release", _release, {
		"help": "release a held mouse button at x y or --ref.", "target": "game",
		"args": pos_args + [{"name": "--button", "type": "string", "required": false, "default": "left", "help": "left|right|middle"}],
	})
	s.registry.register("input", "hover", _hover, {
		"help": "move the mouse to x y or --ref.", "target": "game", "args": pos_args,
	})
	s.registry.register("input", "key", _key, {
		"help": "press+release a key by name; optionally --hold or --release.", "target": "game",
		"args": [
			{"name": "key", "type": "string", "required": true, "default": "", "help": "key name"},
			{"name": "--mods", "type": "json", "required": false, "default": [], "help": "modifiers"},
			{"name": "--hold", "type": "bool", "required": false, "default": false, "help": "press without releasing"},
			{"name": "--release", "type": "bool", "required": false, "default": false, "help": "release without pressing"}],
	})
	s.registry.register("input", "enter text", _enter_text, {
		"help": "focus a text input, insert text, and optionally submit it.",
		"target": "game",
		"async": true,
		"args": [
			{"name": "text", "type": "string", "required": true, "default": "", "help": "text to enter; quote strings with spaces"},
			{"name": "--ref", "type": "string", "required": false, "default": "", "help": "LineEdit/TextEdit path or @ref; omitted = focused or only visible text input"},
			{"name": "--clear", "type": "bool", "required": false, "default": false, "help": "clear existing text first"},
			{"name": "--submit", "type": "bool", "required": false, "default": false, "help": "press Enter after inserting text"}],
	})
	s.registry.register("input", "act", _act, {
		"help": "fire an input action; optionally --hold or --release. Must exist in the InputMap.", "target": "game",
		"args": [
			{"name": "action", "type": "string", "required": true, "default": "", "help": "action name"},
			{"name": "--hold", "type": "bool", "required": false, "default": false, "help": "press without releasing"},
			{"name": "--release", "type": "bool", "required": false, "default": false, "help": "release without pressing"}],
	})
	s.registry.register("input", "scroll", _scroll, {
		"help": "mouse wheel at x y.", "target": "game",
		"args": [
			{"name": "x", "type": "float", "required": false, "default": 0.0, "help": "x"},
			{"name": "y", "type": "float", "required": false, "default": 0.0, "help": "y"},
			{"name": "--ref", "type": "string", "required": false, "default": "", "help": "target node/@ref (center)"},
			{"name": "--dir", "type": "string", "required": false, "default": "down", "help": "up|down|left|right"},
			{"name": "--amount", "type": "int", "required": false, "default": 1, "help": "wheel ticks"}],
	})

func _pos(p: Dictionary) -> Variant:
	return _resolve_pos(str(p.get("ref", "")), float(p.get("x", 0.0)), float(p.get("y", 0.0)))

func _pos2(p: Dictionary) -> Variant:
	if str(p.get("ref2", "")).is_empty() and not str(p.get("ref", "")).is_empty() and float(p.get("x2", 0.0)) == 0.0 and float(p.get("y2", 0.0)) == 0.0:
		return _resolve_pos("", float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	return _resolve_pos(str(p.get("ref2", "")), float(p.get("x2", 0.0)), float(p.get("y2", 0.0)))

# A given --ref must resolve; a stale/unknown ref is an error, NOT a silent click at (0,0). Without a
# ref, use the x/y coordinates.
func _resolve_pos(ref: String, x: float, y: float) -> Variant:
	if ref.is_empty():
		return Vector2(x, y)
	var n = s.resolve_node(ref)
	if n == null:
		return s.err("not_found", "unresolved ref '%s' (re-inspect for a fresh @ref)" % ref)
	var sp: Variant = s.screen_pos(ref)
	if sp == null:
		return s.err("bad_params", "node has no screen position: " + ref)
	return sp

func _apply_mods(ev: InputEventWithModifiers, p: Dictionary) -> void:
	var mods: Array = p.get("mods", [])
	ev.shift_pressed = "shift" in mods
	ev.ctrl_pressed = "ctrl" in mods
	ev.alt_pressed = "alt" in mods
	ev.meta_pressed = "meta" in mods

func _button_index(name: String) -> int:
	match name:
		"right": return MOUSE_BUTTON_RIGHT
		"middle": return MOUSE_BUTTON_MIDDLE
		_: return MOUSE_BUTTON_LEFT

func _mouse_button(pos: Vector2, idx: int, pressed: bool, p: Dictionary) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	_apply_mods(ev, p)
	Input.parse_input_event(ev)

func _motion(pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = relative
	Input.parse_input_event(ev)

func _click(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var pos = _pos(p)
	if s.is_err(pos): return pos
	var idx := _button_index(str(p.get("button", "left")))
	_motion(pos, Vector2.ZERO)
	_mouse_button(pos, idx, true, p)
	_mouse_button(pos, idx, false, p)
	return {"clicked": [pos.x, pos.y], "button": str(p.get("button", "left"))}

func _drag(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var a = _pos(p)
	if s.is_err(a): return a
	var b = _pos2(p)
	if s.is_err(b): return b
	var idx := _button_index(str(p.get("button", "left")))
	_motion(a, Vector2.ZERO)
	_mouse_button(a, idx, true, p)
	_motion(b, b - a)
	if not bool(p.get("hold", false)):
		_mouse_button(b, idx, false, p)
	return {"from": [a.x, a.y], "to": [b.x, b.y], "held": bool(p.get("hold", false))}

func _release(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var pos = _pos(p)
	if s.is_err(pos): return pos
	var idx := _button_index(str(p.get("button", "left")))
	_motion(pos, Vector2.ZERO)
	_mouse_button(pos, idx, false, p)
	return {"released": [pos.x, pos.y], "button": str(p.get("button", "left"))}

func _hover(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var pos = _pos(p)
	if s.is_err(pos): return pos
	_motion(pos, Vector2.ZERO)
	return {"hover": [pos.x, pos.y]}

func _key(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var name := str(p.get("key", ""))
	var keycode := OS.find_keycode_from_string(name)
	if keycode == KEY_NONE:
		return s.err("bad_params", "unknown key: " + name)
	var sequence := [true, false]
	if bool(p.get("hold", false)):
		sequence = [true]
	elif bool(p.get("release", false)):
		sequence = [false]
	for pressed in sequence:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		if pressed:
			ev.unicode = _unicode_for_key(name, keycode, p)
		ev.pressed = pressed
		_apply_mods(ev, p)
		Input.parse_input_event(ev)
	return {"key": name, "held": bool(p.get("hold", false)), "released": bool(p.get("release", false))}

func _enter_text(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var target = _resolve_text_input(str(p.get("ref", "")))
	if s.is_err(target):
		return target
	target.grab_focus()
	await s.get_tree().process_frame
	if bool(p.get("clear", false)):
		target.text = ""
	if target is LineEdit:
		(target as LineEdit).caret_column = (target as LineEdit).text.length()
		(target as LineEdit).insert_text_at_caret(str(p.get("text", "")))
	elif target is TextEdit:
		(target as TextEdit).set_caret_column((target as TextEdit).get_line((target as TextEdit).get_caret_line()).length())
		(target as TextEdit).insert_text_at_caret(str(p.get("text", "")))
	if bool(p.get("submit", false)):
		await s.get_tree().process_frame
		_key({"key": "Enter", "mods": []})
		await s.get_tree().process_frame
	return {"path": s.rel_path(target), "text": target.text, "submitted": bool(p.get("submit", false))}

func _resolve_text_input(ref: String) -> Variant:
	if not ref.is_empty():
		var n = s.resolve_node(ref)
		if n == null:
			return s.err("not_found", "unresolved ref '%s' (re-inspect for a fresh @ref)" % ref)
		if n is LineEdit or n is TextEdit:
			return n
		return s.err("bad_params", "target is not a LineEdit/TextEdit: " + ref)
	var focus = s.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return focus
	var matches: Array = []
	_collect_visible_text_inputs(s.target_root(), matches)
	if matches.size() == 1:
		return matches[0]
	if matches.is_empty():
		return s.err("not_found", "no visible LineEdit/TextEdit found; pass --ref")
	return s.err("bad_params", "multiple visible text inputs found; pass --ref")

func _collect_visible_text_inputs(n: Node, out: Array) -> void:
	if n == null:
		return
	if (n is LineEdit or n is TextEdit) and (n as Control).is_visible_in_tree():
		out.append(n)
	for child in n.get_children():
		_collect_visible_text_inputs(child, out)

func _unicode_for_key(name: String, keycode: int, p: Dictionary) -> int:
	if name.length() == 1:
		var ch := name
		var mods: Array = p.get("mods", [])
		if not ("shift" in mods):
			ch = ch.to_lower()
		return ch.unicode_at(0)
	match keycode:
		KEY_SPACE:
			return 32
		KEY_MINUS:
			return 45
		KEY_PERIOD:
			return 46
		KEY_COMMA:
			return 44
		KEY_SLASH:
			return 47
		KEY_BACKSLASH:
			return 92
		KEY_SEMICOLON:
			return 59
		KEY_APOSTROPHE:
			return 39
		KEY_BRACKETLEFT:
			return 91
		KEY_BRACKETRIGHT:
			return 93
		KEY_EQUAL:
			return 61
		KEY_QUOTELEFT:
			return 96
		_:
			return 0

func _act(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var action := str(p.get("action", ""))
	if not InputMap.has_action(action):
		return s.err("bad_params", "action not in InputMap: " + action)
	var sequence := [true, false]
	if bool(p.get("hold", false)):
		sequence = [true]
	elif bool(p.get("release", false)):
		sequence = [false]
	for pressed in sequence:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
	return {"action": action, "held": bool(p.get("hold", false)), "released": bool(p.get("release", false))}

func _scroll(p: Dictionary) -> Variant:
	if s.is_editor():
		return s.err("game_only", "input runs on the game instance")
	var pos = _pos(p)
	if s.is_err(pos): return pos
	var idx := MOUSE_BUTTON_WHEEL_DOWN
	match str(p.get("dir", "down")):
		"up": idx = MOUSE_BUTTON_WHEEL_UP
		"left": idx = MOUSE_BUTTON_WHEEL_LEFT
		"right": idx = MOUSE_BUTTON_WHEEL_RIGHT
	var amount := int(p.get("amount", 1))
	for i in amount:
		_mouse_button(pos, idx, true, p)
		_mouse_button(pos, idx, false, p)
	return {"scroll": str(p.get("dir", "down")), "amount": amount}
