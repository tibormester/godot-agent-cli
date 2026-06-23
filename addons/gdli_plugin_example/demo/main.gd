extends Node2D

signal terminal_command_finished(command: String, result: Variant)

const ARENA_CENTER := Vector2(640, 250)
const ARENA_RADIUS := 220.0
const PLAYER_SPEED := 230.0
const SWORD_RANGE := 92.0
const SWORD_ARC_DEGREES := 58.0
const ENEMY_HP := 2
const MAX_STACK := 5
const TERMINAL_HINT := "type gdli --help for info"
const TERMINAL_INPUT_MIN_HEIGHT := 42.0
const TERMINAL_INPUT_LINE_HEIGHT := 22.0
const TERMINAL_INPUT_PADDING := 18.0
const TERMINAL_INPUT_MAX_LINES := 4
const TERMINAL_INPUT_ROW_BOTTOM := 390.0
const TERMINAL_INPUT_OUTPUT_GAP := 14.0
const TERMINAL_SCROLL_LINES := 4
const TERMINAL_IDLE_COLLAPSE_MSEC := 3500
const TERMINAL_OUTPUT_TOP_EXPANDED := 18.0
const TERMINAL_OUTPUT_LINE_HEIGHT := 26.0
const TERMINAL_SHADE_PADDING := 10.0
const ACTION_MOVE_UP := "gdli_demo_move_up"
const ACTION_MOVE_DOWN := "gdli_demo_move_down"
const ACTION_MOVE_LEFT := "gdli_demo_move_left"
const ACTION_MOVE_RIGHT := "gdli_demo_move_right"
const ACTION_INTERACT := "gdli_demo_interact"
const ACTION_OPEN_INVENTORY := "gdli_demo_open_inventory"
const GDLI_UNIVERSAL_FLAGS := """Universal flags (work on any verb):
  --diff [mark]     whole-scene delta before/after the command (or vs a named mark). Replaces the
                    verb's normal output; add --data to show both.
  --mark <name>     save the post-command scene as a checkpoint ('gdli mark' lists them; re-marking
                    the same name overwrites).
  --ticks <n>       (with --diff/--mark) wait n idle frames before the after-snapshot. default 0
  --physics <n>     (with --diff/--mark) wait n physics frames instead.
  --time <s>        (with --diff/--mark) wait s seconds instead.
  --ignore <glob>   drop matching scene-relative paths from the diff (one-shot; e.g. Mover, UI/*).
  ignore add/list/remove/clear
                    manage process-global diff ignores for noisy subtrees.
  --data            show the verb's own data even when --diff is present.
  --headless        if nothing's running, spawn a transient HEADLESS instance for this command only
                    (no window) and stop it after. Bare eval does this by default when no instance is up.
  --timeout <dur>   stop waiting after dur; launch saves session defaults.
  --timewarning <dur>
                    warn while a command is still running; use 0 to disable.
  --json            machine-readable single-line output.
  --game / --editor / --port <n>   force the target instance."""
const GEM_DROP_CHANCE := 0.18
const TUTORIAL_TYPE_DELAY := 0.012
const TUTORIAL_AUTOPLAY_SUBMIT_DELAY := 0.5
const TUTORIAL_LOOP_DELAY := 1.25
const RECORDING_FRAME_DIR := "user://gdli_demo_recording/frames"

var wave := 1
var enemy_seq := 0
var loot_seq := 0
var swing_seq := 0
var dragging_loot: Node2D = null
var drag_offset := Vector2.ZERO
var drag_start_position := Vector2.ZERO
var drag_source_slot := -1
var pending_inventory_drag_slot := -1
var pending_inventory_drag_type := ""
var transcript: Array[String] = []
var terminal_scroll_line := 0
var terminal_last_output_msec := 0
var terminal_collapsed := false
var tutorial_active := false
var tutorial_index := -1
var tutorial_typing := false
var tutorial_autoplay := false
var recording_active := false
var recording_pending_loop_start := false
var recording_loop_once := false
var recording_waiting_for_loop_end := false
var recording_elapsed := 0.0
var recording_frame_elapsed := 0.0
var recording_frame_count := 0
var recording_seconds := 45.0
var recording_fps := 8
var recording_width := 640
var recording_output_path := "res://addons/gdli_plugin_example/docs/assets/demo-autoplay.webm"
var recording_ffmpeg_path := "ffmpeg"
var recording_frame_dir_abs := ""
var inventory := [
	{"type": "", "count": 0},
	{"type": "", "count": 0},
	{"type": "", "count": 0},
	{"type": "", "count": 0},
]

@onready var arena: Node2D = $Arena
@onready var player: Node2D = $Arena/Player
@onready var player_body = $Arena/Player/Body
@onready var sword_arc = $Arena/Player/SwordArc
@onready var enemies_root: Node2D = $Arena/Enemies
@onready var loot_root: Node2D = $Arena/Loot
@onready var status_label: Label = $Hud/StatusLabel
@onready var inventory_panel: PanelContainer = $Hud/InventoryPanel
@onready var slot_buttons: Array[Button] = [
	$Hud/InventoryPanel/Margin/Rows/Slots/Slot1,
	$Hud/InventoryPanel/Margin/Rows/Slots/Slot2,
	$Hud/InventoryPanel/Margin/Rows/Slots/Slot3,
	$Hud/InventoryPanel/Margin/Rows/Slots/Slot4,
]
@onready var wave_popup: PanelContainer = $Hud/WavePopup
@onready var next_wave_button: Button = $Hud/WavePopup/Margin/Rows/NextWaveButton
@onready var terminal_panel: Control = $TerminalPanel
@onready var terminal_shade: ColorRect = $TerminalPanel/TerminalShade
@onready var terminal_output: RichTextLabel = $TerminalPanel/TerminalOutput
@onready var tutorial_button: Button = $TerminalPanel/TutorialButton
@onready var input_row: HBoxContainer = $TerminalPanel/InputRow
@onready var command_input: TextEdit = $TerminalPanel/InputRow/CommandInput
@onready var submit_button: Button = $TerminalPanel/InputRow/SubmitButton
@onready var tutorial_popup: PanelContainer = $Hud/TutorialPopup
@onready var tutorial_title: Label = $Hud/TutorialPopup/Margin/Rows/Title
@onready var tutorial_body: Label = $Hud/TutorialPopup/Margin/Rows/Body

var tutorial_steps: Array[Dictionary] = [
	{"chapter": "Setup and Help", "command": "gdli --help", "title": "Setup and Help", "body": "Start with the same hint the terminal shows on load. This expands to the live verb registry and the universal flags that work on every verb."},
	{"chapter": "Setup and Help", "command": "gdli verbs", "title": "Live Verb Registry", "body": "The registry is not static documentation. It is read from the running server, including plugin verbs discovered under addons."},
	{"chapter": "Setup and Help", "command": "gdli help inspect", "title": "Progressive Help", "body": "Help for one verb shows its target and accepted options. The inspect verb is the map for scene structure and UI refs."},
	{"chapter": "Diffs, Marks, and Proof", "command": "gdli ignore add TerminalPanel", "title": "Ignore Noisy Output", "body": "The terminal changes after almost every command, and large text diffs are expensive. Add it once to the process-global ignore list instead of repeating --ignore on every diff."},
	{"chapter": "Diffs, Marks, and Proof", "command": "gdli ignore list", "title": "List Global Ignores", "body": "Process-global ignores combine with one-shot --ignore. They live only in this running Godot instance and are reset on kill/relaunch."},
	{"chapter": "Observe the Scene", "command": "gdli inspect --ui", "title": "Find UI Refs", "body": "Visible Controls get stable refs. Use these refs instead of brittle screen coordinates when clicking UI."},
	{"chapter": "Observe the Scene", "command": "gdli inspect --root Arena --depth 2", "title": "Scope Inspection", "body": "Inspect can focus on a subtree. Here it reads just the arena, player, enemies, and loot roots."},
	{"chapter": "Diffs, Marks, and Proof", "command": "gdli inspect --mark tutorial_before_spawn", "title": "Mark a Baseline", "body": "Marks are in-memory checkpoints. Later commands can diff against this named baseline."},
	{"chapter": "Plugin Verbs", "command": "gdli gdli_plugin example greet Codex", "title": "Plugin Smoke Test", "body": "The example addon registers a namespaced verb. This proves plugin discovery and routing."},
	{"chapter": "Plugin Verbs", "command": "gdli gdli_plugin example enemies spawn 2 --diff", "title": "Domain Verb With Diff", "body": "A game-specific verb can do a meaningful composite action. The dispatcher adds structural proof with --diff."},
	{"chapter": "Diffs, Marks, and Proof", "command": "gdli inspect --diff tutorial_before_spawn", "title": "Compare Against Mark", "body": "This shows the cumulative scene changes since the baseline mark."},
	{"chapter": "Eval and Macros", "command": "gdli eval 'root.get_child_count()'", "title": "Eval Expression", "body": "Eval runs a small GDScript expression against the current scene root and returns the value."},
	{"chapter": "Eval and Macros", "command": "gdli eval --save child_count 'root.get_child_count()'", "title": "Save an Eval Handle", "body": "Saved eval handles live under .gdli/handles. They are ephemeral macros, not committed plugin logic."},
	{"chapter": "Eval and Macros", "command": "gdli eval '@child_count'", "title": "Run an Eval Handle", "body": "The @handle form reuses the saved code. Additional tokens would be available as argv."},
	{"chapter": "Eval and Macros", "command": "gdli eval --list", "title": "List Eval Handles", "body": "List the saved handles to verify that the macro exists in the running project state."},
	{"chapter": "Eval and Macros", "command": "gdli eval --file res://addons/gdli_plugin_example/demo/tutorial_steps/01_eval_gdli_bridge.gd", "title": "Eval File and gdli()", "body": "A file-based eval script can call gdli(\"...\") with the same CLI vocabulary. Persistent shared logic should still be a plugin."},
	{"chapter": "Input and UI Refs", "command": "gdli enter text \"gdli verbs\" --ref TerminalPanel/InputRow/CommandInput --clear", "title": "Type Into Text Input", "body": "This uses the input pipeline to focus the terminal input and type a command. The terminal is globally ignored for diffs, so this step is visual/interactive proof rather than structural proof."},
	{"chapter": "Input and UI Refs", "command": "gdli key D --hold --diff --ticks 8", "title": "Hold a Key", "body": "Input verbs use the real Godot input pipeline. Holding D moves the player and the diff shows the position change."},
	{"chapter": "Input and UI Refs", "command": "gdli key D --release", "title": "Release a Key", "body": "Held keys should be released explicitly so later tutorial steps start from a predictable input state."},
	{"chapter": "Playtest Review Loop", "command": "gdli click 752 286 --diff --ticks 1", "title": "Click to Attack", "body": "This is a player-like action, not a state shortcut. The first hit should shrink an enemy HP bar."},
	{"chapter": "Playtest Review Loop", "command": "gdli click 752 286 --diff --ticks 2", "title": "Confirm Loot Drop", "body": "The second hit should remove the enemy and add loot. Visual proof and structural proof should agree."},
	{"chapter": "Playtest Review Loop", "command": "gdli inspect --mark before_loot", "title": "Mark Before Loot", "body": "Mark the state after loot drops so the inventory action can be proved as a multi-step change."},
	{"chapter": "Playtest Review Loop", "command": "gdli drag --ref Arena/Loot/Loot1 --ref2 Hud/InventoryPanel/Margin/Rows/Slots/Slot1 --ticks 2", "title": "Drag Loot by Ref", "body": "Refs let input target scene nodes and UI controls without pixel math. The loot should stack into Slot1."},
	{"chapter": "Playtest Review Loop", "command": "gdli inspect --diff before_loot", "title": "Diff the Loot Move", "body": "The diff should show Loot1 leaving the world and Slot1 text changing."},
	{"chapter": "Playtest Review Loop", "command": "gdli drag --ref Hud/InventoryPanel/Margin/Rows/Slots/Slot1 700 230 --hold --diff --ticks 1", "title": "Hold a Drag", "body": "A held drag instantiates the item while the button remains down. This makes drag-in-progress behavior inspectable."},
	{"chapter": "Playtest Review Loop", "command": "gdli release 700 230 --ticks 1", "title": "Release the Drag", "body": "Release completes the input gesture and leaves the dragged item back in the scene."},
	{"chapter": "Plugin Verbs", "command": "gdli eval --file res://addons/gdli_plugin_example/demo/tutorial_steps/02_spawn_loot.gd --diff", "title": "Deterministic Tutorial Setup", "body": "Some tutorial setup is scripted with eval files so the following domain verb has predictable scene state."},
	{"chapter": "Plugin Verbs", "command": "gdli gdli_plugin example items collect best --diff", "title": "Collect Into Best Slot", "body": "This domain verb chooses an existing compatible stack or an empty slot. The diff proves item removal and inventory text changes."},
	{"chapter": "Plugin Verbs", "command": "gdli gdli_plugin example wave finish --diff", "title": "Finish a Wave", "body": "The wave verb clears enemies and shows the non-blocking next-wave popup."},
	{"chapter": "Plugin Verbs", "command": "gdli gdli_plugin example wave next --diff", "title": "Start Next Wave", "body": "The next-wave verb advances the demo and spawns a new enemy set."},
	{"chapter": "Maintain and Extend", "command": "gdli config", "title": "Runtime Config", "body": "Config reports modules and disabled modules. Docs discuss disabling mutating modules during playtest review."},
	{"chapter": "Maintain and Extend", "command": "gdli help check", "title": "Compile Check", "body": "The check verb compile-checks project scripts. The in-game tutorial shows its help; run gdli check from the host terminal during verification."},
	{"chapter": "Maintain and Extend", "command": "gdli mark", "title": "List Marks", "body": "Marks are per-instance proof checkpoints. This final step lists the marks made during the tutorial."},
]

func _ready() -> void:
	randomize()
	ensure_demo_input_actions()
	_add_godot_icon_visual(player_body, Color(0.28, 0.55, 0.78, 1.0), false)
	wave_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_wave_button.focus_mode = Control.FOCUS_NONE
	next_wave_button.pressed.connect(_start_next_wave)
	tutorial_button.pressed.connect(_on_tutorial_button_pressed)
	terminal_command_finished.connect(_on_terminal_command_finished)
	submit_button.pressed.connect(_submit_terminal)
	command_input.gui_input.connect(_on_command_input_gui_input)
	command_input.text_changed.connect(_sync_terminal_input_height)
	command_input.focus_entered.connect(_refresh_terminal_layout)
	command_input.focus_exited.connect(_refresh_terminal_layout)
	_reset_terminal()
	_sync_terminal_input_height()
	_spawn_wave()
	_update_inventory_ui()
	_update_status()

func setup_demo_project_globals(options: Dictionary = {}) -> Dictionary:
	var result := ensure_demo_input_actions()
	if bool(options.get("record", false)):
		result["recording"] = _start_tutorial_recording(options)
	if bool(options.get("autoplay", false)):
		call_deferred("_start_tutorial", true)
		result["autoplay"] = {
			"started": true,
			"submit_delay_seconds": TUTORIAL_AUTOPLAY_SUBMIT_DELAY,
			"loops": true,
		}
	return result

func gdli_plugin_example_setup(options: Dictionary = {}) -> Dictionary:
	return setup_demo_project_globals(options)

func reset_demo_state() -> Dictionary:
	wave = 1
	enemy_seq = 0
	loot_seq = 0
	swing_seq = 0
	dragging_loot = null
	drag_source_slot = -1
	pending_inventory_drag_slot = -1
	pending_inventory_drag_type = ""
	player.position = ARENA_CENTER
	sword_arc.visible = false
	wave_popup.visible = false
	_clear_children_now(enemies_root)
	_clear_children_now(loot_root)
	for child in arena.get_children():
		if child != enemies_root and child != loot_root and child != player:
			_remove_child_now(child)
	for i in inventory.size():
		inventory[i] = {"type": "", "count": 0}
	_spawn_wave()
	_update_inventory_ui()
	_update_status()
	return {
		"ok": true,
		"wave": wave,
		"enemy_count": enemies_root.get_child_count(),
		"loot_count": _loot_count(),
	}

func tutorial_spawn_loot() -> Dictionary:
	var spawned := []
	var coin := _spawn_loot(ARENA_CENTER + Vector2(-72, 88), "coin")
	var gem := _spawn_loot(ARENA_CENTER + Vector2(-28, 92), "gem")
	spawned.append(coin.name)
	spawned.append(gem.name)
	_update_status()
	return {
		"ok": true,
		"spawned": spawned,
		"loot_count": _loot_count(),
	}

func ensure_demo_input_actions() -> Dictionary:
	var actions := {
		ACTION_MOVE_UP: KEY_W,
		ACTION_MOVE_DOWN: KEY_S,
		ACTION_MOVE_LEFT: KEY_A,
		ACTION_MOVE_RIGHT: KEY_D,
		ACTION_INTERACT: KEY_E,
		ACTION_OPEN_INVENTORY: KEY_I,
	}
	for action_name in actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action_name]
		InputMap.action_add_event(action_name, event)
	return {
		"ok": true,
		"actions": actions.keys(),
		"persistent": false,
	}

func clear_console() -> Dictionary:
	_reset_terminal()
	return {
		"ok": true,
		"hint": TERMINAL_HINT,
	}

func gdli_plugin_example_console_clear() -> Dictionary:
	return clear_console()

func spawn_enemies(count: int = 1) -> Dictionary:
	var spawned: Array[String] = []
	for i in range(max(0, count)):
		enemy_seq += 1
		var angle := TAU * float(enemy_seq % 12) / 12.0
		var radius := 96.0 + 22.0 * float(enemy_seq % 4)
		var pos := ARENA_CENTER + Vector2(cos(angle), sin(angle)) * radius
		_spawn_enemy(pos)
		spawned.append(enemies_root.get_child(enemies_root.get_child_count() - 1).name)
	_update_status()
	return {
		"ok": true,
		"spawned": spawned,
		"enemy_count": enemies_root.get_child_count(),
		"wave": wave,
	}

func clear_enemies() -> Dictionary:
	var cleared := enemies_root.get_child_count()
	_clear_children_now(enemies_root)
	wave_popup.visible = false
	_update_status()
	return {
		"ok": true,
		"cleared": cleared,
		"enemy_count": 0,
		"wave": wave,
	}

func gdli_plugin_example_enemies_clear() -> Dictionary:
	return clear_enemies()

func gdli_plugin_example_enemies_spawn(count: int = 1) -> Dictionary:
	return spawn_enemies(count)

func start_wave(next_wave: int = -1) -> Dictionary:
	if next_wave > 0:
		wave = next_wave
	_spawn_wave()
	return {
		"ok": true,
		"wave": wave,
		"enemy_count": enemies_root.get_child_count(),
	}

func finish_wave() -> Dictionary:
	var cleared := enemies_root.get_child_count()
	_clear_children_now(enemies_root)
	wave_popup.visible = true
	_update_status()
	return {
		"ok": true,
		"cleared": cleared,
		"wave": wave,
		"next_wave": wave + 1,
	}

func gdli_plugin_example_wave_next() -> Dictionary:
	return start_wave(wave + 1)

func gdli_plugin_example_wave_finish() -> Dictionary:
	return finish_wave()

func collect_loot_into_best_inventory(loot_name: String = "") -> Dictionary:
	var collected: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for loot in loot_root.get_children():
		if loot_name != "" and loot.name != loot_name and str(loot.get_path()) != loot_name:
			continue
		var slot_index := _best_inventory_slot_for(str(loot.get_meta("type")))
		if slot_index < 0:
			skipped.append({
				"loot": loot.name,
				"reason": "inventory_full",
			})
			continue
		var loot_type := str(loot.get_meta("type"))
		if _add_loot_to_slot(loot, slot_index):
			collected.append({
				"loot": loot.name,
				"type": loot_type,
				"slot": slot_index + 1,
			})
			loot.queue_free()
	if loot_name != "" and collected.is_empty() and skipped.is_empty():
		return {
			"ok": false,
			"code": "loot_not_found",
			"message": "No matching loot found: %s" % loot_name,
		}
	_update_inventory_ui()
	_update_status()
	return {
		"ok": skipped.is_empty(),
		"collected": collected,
		"skipped": skipped,
		"inventory": inventory.duplicate(true),
	}

func gdli_plugin_example_items_collect_best() -> Dictionary:
	return collect_loot_into_best_inventory()

func _process(delta: float) -> void:
	_update_player_movement(delta)
	_update_dragged_loot()
	_update_terminal_collapse()
	_update_tutorial_recording(delta)
	queue_redraw()

func _draw() -> void:
	draw_circle(ARENA_CENTER, ARENA_RADIUS + 12.0, Color(0.05, 0.08, 0.09, 0.9))
	draw_circle(ARENA_CENTER, ARENA_RADIUS + 7.0, Color(0.22, 0.28, 0.28, 0.9))
	draw_circle(ARENA_CENTER, ARENA_RADIUS, Color(0.1, 0.13, 0.14, 0.95))
	draw_arc(ARENA_CENTER, ARENA_RADIUS, 0.0, TAU, 160, Color(0.84, 0.68, 0.28, 1.0), 4.0)
	draw_arc(ARENA_CENTER, ARENA_RADIUS - 38.0, 0.0, TAU, 160, Color(0.22, 0.32, 0.31, 0.9), 2.0)
	draw_arc(ARENA_CENTER, ARENA_RADIUS - 74.0, 0.0, TAU, 160, Color(0.12, 0.2, 0.2, 0.65), 1.0)

func _input(event: InputEvent) -> void:
	if tutorial_active and not tutorial_typing and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_submit_terminal()
			return
	if dragging_loot == null and pending_inventory_drag_slot < 0 and _terminal_handles_event(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _try_start_drag(event.position):
				return
			_swing_at(event.position)
		else:
			_drop_dragged_loot(event.position)
	if event is InputEventMouseMotion:
		_update_pending_inventory_drag(event.position)
		_update_dragged_loot(event.position)

func _terminal_handles_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if command_input.get_global_rect().has_point(event.position):
			command_input.grab_focus()
			return true
		if not terminal_panel.get_global_rect().has_point(event.position) and command_input.has_focus():
			command_input.release_focus()
			return false
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if terminal_panel.get_global_rect().has_point(event.position):
			var over_input := command_input.get_global_rect().has_point(event.position)
			var output_is_target := terminal_output.get_global_rect().has_point(event.position) or not terminal_output.get_selected_text().is_empty()
			if over_input and _terminal_input_line_count() > 1 and not output_is_target:
				return true
			var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			_scroll_terminal_output(direction * TERMINAL_SCROLL_LINES)
			get_viewport().set_input_as_handled()
			return true
	if command_input.has_focus() and event is InputEventKey:
		return true
	if event is InputEventMouse and terminal_panel.get_global_rect().has_point(event.position):
		return true
	return false

func _update_player_movement(delta: float) -> void:
	if command_input.has_focus():
		return
	var axis := Vector2(
		Input.get_action_strength(ACTION_MOVE_RIGHT) - Input.get_action_strength(ACTION_MOVE_LEFT),
		Input.get_action_strength(ACTION_MOVE_DOWN) - Input.get_action_strength(ACTION_MOVE_UP)
	)
	if axis.length() > 0.0:
		_move_player(axis.normalized() * PLAYER_SPEED * delta)

func _move_player(offset: Vector2) -> void:
	var target := player.position + offset
	var from_center := target - ARENA_CENTER
	if from_center.length() > ARENA_RADIUS - 20.0:
		target = ARENA_CENTER + from_center.normalized() * (ARENA_RADIUS - 20.0)
	player.position = target
	_update_status()

func _swing_at(pos: Vector2) -> void:
	var direction := pos - player.global_position
	if direction.length() < 4.0:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	swing_seq += 1
	sword_arc.visible = true
	sword_arc.rotation = direction.angle()
	sword_arc.modulate.a = 0.82
	var hit_count := 0
	for enemy in enemies_root.get_children():
		var enemy_dir: Vector2 = enemy.global_position - player.global_position
		if enemy_dir.length() <= SWORD_RANGE and abs(rad_to_deg(direction.angle_to(enemy_dir.normalized()))) <= SWORD_ARC_DEGREES * 0.5:
			_damage_enemy(enemy, 1)
			hit_count += 1
	_show_damage_text(player.global_position + direction * 64.0, "swing %d" % swing_seq, Color(0.9, 0.96, 1.0, 1.0))
	get_tree().create_timer(0.5).timeout.connect(func(): sword_arc.visible = false)
	if hit_count == 0:
		_update_status()

func _damage_enemy(enemy: Node2D, amount: int) -> void:
	var hp := int(enemy.get_meta("hp")) - amount
	enemy.set_meta("hp", hp)
	_update_enemy_hp(enemy)
	_show_damage_text(enemy.global_position + Vector2(0, -38), "-%d" % amount, Color(1.0, 0.38, 0.24, 1.0))
	if hp <= 0:
		_spawn_loot(enemy.global_position, str(enemy.get_meta("loot_type")))
		enemy.queue_free()
		await get_tree().process_frame
		_check_wave_clear()
	else:
		_update_status()

func _spawn_wave() -> void:
	wave_popup.visible = false
	_clear_children_now(enemies_root)
	var count := wave + 2
	for i in count:
		enemy_seq += 1
		var angle := TAU * float(i) / float(count) + wave * 0.31
		var radius := 118.0 + 24.0 * float(i % 3)
		var pos := ARENA_CENTER + Vector2(cos(angle), sin(angle)) * radius
		_spawn_enemy(pos)
	_update_status()

func _spawn_enemy(pos: Vector2) -> void:
	var enemy := Node2D.new()
	enemy.name = "Enemy%d" % enemy_seq
	enemy.position = pos
	enemy.set_meta("hp", ENEMY_HP)
	enemy.set_meta("max_hp", ENEMY_HP)
	enemy.set_meta("loot_type", "gem" if randf() < GEM_DROP_CHANCE else "coin")
	enemies_root.add_child(enemy)

	var body := Node2D.new()
	body.name = "Body"
	body.scale = Vector2(0.86, 0.86)
	enemy.add_child(body)
	_add_godot_icon_visual(body, Color(0.95, 0.1, 0.1, 1.0), true)

	var bar_back := ColorRect.new()
	bar_back.name = "HpBack"
	bar_back.position = Vector2(-20, -28)
	bar_back.size = Vector2(40, 6)
	bar_back.color = Color(0.12, 0.12, 0.13, 1.0)
	enemy.add_child(bar_back)

	var bar_fill := ColorRect.new()
	bar_fill.name = "HpFill"
	bar_fill.position = Vector2(-19, -27)
	bar_fill.size = Vector2(38, 4)
	bar_fill.color = Color(0.18, 0.9, 0.35, 1.0)
	enemy.add_child(bar_fill)

func _update_enemy_hp(enemy: Node2D) -> void:
	var fill := enemy.get_node_or_null("HpFill") as ColorRect
	if fill == null:
		return
	var hp: int = max(0, int(enemy.get_meta("hp")))
	var max_hp: int = max(1, int(enemy.get_meta("max_hp")))
	fill.size.x = 38.0 * float(hp) / float(max_hp)

func _show_damage_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.name = "Damage%d" % Time.get_ticks_msec()
	label.global_position = pos
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	arena.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -24), 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.finished.connect(label.queue_free)

func _spawn_loot(pos: Vector2, loot_type: String) -> Node2D:
	loot_seq += 1
	var loot := Node2D.new()
	loot.name = "Loot%d" % loot_seq
	loot.position = pos + Vector2(18, 12)
	loot.set_meta("type", loot_type)
	loot_root.add_child(loot)

	if loot_type == "coin":
		_add_coin_visual(loot)
	else:
		_add_gem_visual(loot)

	var label := Label.new()
	label.name = "TypeLabel"
	label.position = Vector2(-16, 14)
	label.text = loot_type
	label.add_theme_font_size_override("font_size", 12)
	loot.add_child(label)
	return loot

func _add_godot_icon_visual(root: Node, body_color: Color, angry: bool) -> void:
	for child in root.get_children():
		child.queue_free()

	var head := Polygon2D.new()
	head.name = "GodotHead"
	head.polygon = PackedVector2Array([
		Vector2(-24, -8),
		Vector2(-16, -22),
		Vector2(-7, -16),
		Vector2(-3, -28),
		Vector2(9, -28),
		Vector2(13, -16),
		Vector2(22, -22),
		Vector2(30, -8),
		Vector2(22, 20),
		Vector2(-16, 20),
	])
	head.color = body_color
	root.add_child(head)

	var chin := Polygon2D.new()
	chin.name = "GodotChin"
	chin.polygon = PackedVector2Array([
		Vector2(-18, 4),
		Vector2(24, 4),
		Vector2(18, 25),
		Vector2(-12, 25),
	])
	chin.color = body_color
	root.add_child(chin)

	_add_eye_visual(root, Vector2(-9, 3), angry)
	_add_eye_visual(root, Vector2(13, 3), angry)

	var nose := Line2D.new()
	nose.name = "GodotNose"
	nose.points = PackedVector2Array([Vector2(2, 8), Vector2(2, 18)])
	nose.width = 4.0
	nose.default_color = Color(0.96, 0.98, 1.0, 1.0)
	root.add_child(nose)

	if angry:
		var left_brow := Line2D.new()
		left_brow.name = "LeftAngryBrow"
		left_brow.points = PackedVector2Array([Vector2(-18, -8), Vector2(-5, -2)])
		left_brow.width = 3.0
		left_brow.default_color = Color(0.18, 0.02, 0.02, 1.0)
		root.add_child(left_brow)

		var right_brow := Line2D.new()
		right_brow.name = "RightAngryBrow"
		right_brow.points = PackedVector2Array([Vector2(22, -8), Vector2(9, -2)])
		right_brow.width = 3.0
		right_brow.default_color = Color(0.18, 0.02, 0.02, 1.0)
		root.add_child(right_brow)

func _add_eye_visual(root: Node, position: Vector2, angry: bool) -> void:
	var eye := Polygon2D.new()
	eye.name = "Eye"
	eye.position = position
	eye.polygon = _circle_points(8.0, 24)
	eye.color = Color(0.96, 0.98, 1.0, 1.0)
	root.add_child(eye)

	var pupil := Polygon2D.new()
	pupil.name = "Pupil"
	pupil.position = position
	pupil.polygon = _circle_points(4.6 if angry else 4.2, 20)
	pupil.color = Color(0.08, 0.09, 0.1, 1.0)
	root.add_child(pupil)

func _add_coin_visual(loot: Node2D) -> void:
	var rim := Polygon2D.new()
	rim.name = "Body"
	rim.polygon = _circle_points(14.0, 32)
	rim.color = Color(0.96, 0.56, 0.08, 1.0)
	loot.add_child(rim)

	var face := Polygon2D.new()
	face.name = "CoinFace"
	face.polygon = _circle_points(10.0, 32)
	face.color = Color(1.0, 0.83, 0.25, 1.0)
	loot.add_child(face)

	var shine := Line2D.new()
	shine.name = "CoinShine"
	shine.points = PackedVector2Array([Vector2(-4, -8), Vector2(5, -8)])
	shine.width = 2.0
	shine.default_color = Color(1.0, 0.96, 0.56, 1.0)
	loot.add_child(shine)

func _add_gem_visual(loot: Node2D) -> void:
	var gem := Polygon2D.new()
	gem.name = "Body"
	gem.polygon = PackedVector2Array([
		Vector2(0, -17),
		Vector2(15, -5),
		Vector2(10, 12),
		Vector2(0, 18),
		Vector2(-10, 12),
		Vector2(-15, -5),
	])
	gem.color = Color(0.24, 0.82, 1.0, 1.0)
	loot.add_child(gem)

	var top_facet := Polygon2D.new()
	top_facet.name = "GemTopFacet"
	top_facet.polygon = PackedVector2Array([Vector2(0, -17), Vector2(15, -5), Vector2(0, 0), Vector2(-15, -5)])
	top_facet.color = Color(0.68, 0.95, 1.0, 1.0)
	loot.add_child(top_facet)

	var side_facet := Polygon2D.new()
	side_facet.name = "GemSideFacet"
	side_facet.polygon = PackedVector2Array([Vector2(0, 0), Vector2(15, -5), Vector2(10, 12), Vector2(0, 18)])
	side_facet.color = Color(0.16, 0.55, 0.95, 0.9)
	loot.add_child(side_facet)

	var glint := Line2D.new()
	glint.name = "GemGlint"
	glint.points = PackedVector2Array([Vector2(-5, -8), Vector2(0, -12), Vector2(5, -8)])
	glint.width = 2.0
	glint.default_color = Color(0.92, 1.0, 1.0, 1.0)
	loot.add_child(glint)

func _circle_points(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _try_start_drag(pos: Vector2) -> bool:
	for loot in loot_root.get_children():
		if loot.global_position.distance_to(pos) <= 24.0:
			dragging_loot = loot
			drag_offset = loot.global_position - pos
			drag_start_position = loot.global_position
			drag_source_slot = -1
			loot.z_index = 20
			return true
	for i in slot_buttons.size():
		var slot: Dictionary = inventory[i]
		if int(slot["count"]) > 0 and slot_buttons[i].get_global_rect().has_point(pos):
			pending_inventory_drag_slot = i
			pending_inventory_drag_type = str(slot["type"])
			return true
	return false

func _update_pending_inventory_drag(pos: Vector2) -> void:
	if pending_inventory_drag_slot < 0 or dragging_loot != null:
		return
	if slot_buttons[pending_inventory_drag_slot].get_global_rect().has_point(pos):
		return
	drag_source_slot = pending_inventory_drag_slot
	dragging_loot = _spawn_loot(pos, pending_inventory_drag_type)
	dragging_loot.z_index = 20
	drag_offset = Vector2.ZERO
	drag_start_position = dragging_loot.global_position
	_remove_one_from_slot(drag_source_slot)
	pending_inventory_drag_slot = -1
	pending_inventory_drag_type = ""
	_update_inventory_ui()
	_update_status()

func _update_dragged_loot(pos := Vector2.INF) -> void:
	if dragging_loot == null or not is_instance_valid(dragging_loot):
		dragging_loot = null
		return
	var pointer := get_viewport().get_mouse_position() if pos == Vector2.INF else pos
	dragging_loot.global_position = pointer + drag_offset

func _drop_dragged_loot(pos: Vector2) -> void:
	if pending_inventory_drag_slot >= 0:
		pending_inventory_drag_slot = -1
		pending_inventory_drag_type = ""
		return
	if dragging_loot == null:
		return
	var accepted := false
	var target_slot := -1
	for i in slot_buttons.size():
		if slot_buttons[i].get_global_rect().has_point(pos):
			target_slot = i
			accepted = _add_loot_to_slot(dragging_loot, i)
			break
	if accepted:
		dragging_loot.queue_free()
	else:
		if drag_source_slot >= 0 and target_slot >= 0:
			if _add_loot_to_slot(dragging_loot, drag_source_slot):
				dragging_loot.queue_free()
			else:
				dragging_loot.z_index = 0
		elif drag_source_slot >= 0:
			dragging_loot.z_index = 0
		else:
			dragging_loot.global_position = drag_start_position
			dragging_loot.z_index = 0
	dragging_loot = null
	drag_source_slot = -1
	_update_inventory_ui()
	_update_status()

func _add_loot_to_slot(loot: Node2D, slot_index: int) -> bool:
	var loot_type := str(loot.get_meta("type"))
	var slot: Dictionary = inventory[slot_index]
	if str(slot["type"]).is_empty():
		slot["type"] = loot_type
		slot["count"] = 1
		inventory[slot_index] = slot
		return true
	if slot["type"] == loot_type and int(slot["count"]) < MAX_STACK:
		slot["count"] = int(slot["count"]) + 1
		inventory[slot_index] = slot
		return true
	return false

func _best_inventory_slot_for(loot_type: String) -> int:
	for i in inventory.size():
		var slot: Dictionary = inventory[i]
		if slot["type"] == loot_type and int(slot["count"]) < MAX_STACK:
			return i
	for i in inventory.size():
		var slot: Dictionary = inventory[i]
		if str(slot["type"]).is_empty():
			return i
	return -1

func _remove_one_from_slot(slot_index: int) -> void:
	var slot: Dictionary = inventory[slot_index]
	slot["count"] = max(0, int(slot["count"]) - 1)
	if int(slot["count"]) == 0:
		slot["type"] = ""
	inventory[slot_index] = slot

func _check_wave_clear() -> void:
	if enemies_root.get_child_count() == 0:
		wave_popup.visible = true
	_update_status()

func _start_next_wave() -> void:
	wave += 1
	_spawn_wave()

func _update_inventory_ui() -> void:
	for i in slot_buttons.size():
		var slot: Dictionary = inventory[i]
		if str(slot["type"]).is_empty():
			slot_buttons[i].text = "Empty"
		else:
			slot_buttons[i].text = "%s\n%d/%d" % [str(slot["type"]).capitalize(), int(slot["count"]), MAX_STACK]

func _update_status() -> void:
	status_label.text = "Wave %d  Enemies %d  Loot %d\nWASD moves. Click swings. Drag loot into inventory." % [
		wave,
		enemies_root.get_child_count(),
		_loot_count(),
	]
	next_wave_button.text = "Start Wave %d" % (wave + 1)

func _loot_count() -> int:
	var count := 0
	for loot in loot_root.get_children():
		if not loot.is_queued_for_deletion():
			count += 1
	return count

func _clear_children_now(root: Node) -> void:
	for child in root.get_children():
		_remove_child_now(child)

func _remove_child_now(child: Node) -> void:
	var parent := child.get_parent()
	if parent != null:
		parent.remove_child(child)
	child.queue_free()

func _start_tutorial_recording(options: Dictionary) -> Dictionary:
	recording_seconds = max(1.0, float(options.get("record-seconds", recording_seconds)))
	recording_fps = clampi(int(options.get("record-fps", recording_fps)), 1, 30)
	recording_width = clampi(int(options.get("record-width", recording_width)), 240, 1280)
	recording_output_path = str(options.get("record-out", recording_output_path))
	recording_ffmpeg_path = str(options.get("ffmpeg", recording_ffmpeg_path))
	recording_loop_once = bool(options.get("record-loop", false))
	recording_waiting_for_loop_end = false
	recording_frame_count = 0
	recording_elapsed = 0.0
	recording_frame_elapsed = 1.0 / float(recording_fps)
	recording_frame_dir_abs = ProjectSettings.globalize_path(RECORDING_FRAME_DIR)
	_prepare_recording_frame_dir()
	recording_pending_loop_start = recording_loop_once
	recording_active = not recording_loop_once
	return {
		"active": recording_active,
		"pending_loop_start": recording_pending_loop_start,
		"loop": recording_loop_once,
		"fps": recording_fps,
		"width": recording_width,
		"seconds": recording_seconds,
		"frames": recording_frame_dir_abs,
		"out": ProjectSettings.globalize_path(recording_output_path),
	}

func _prepare_recording_frame_dir() -> void:
	DirAccess.make_dir_recursive_absolute(recording_frame_dir_abs)
	var dir := DirAccess.open(recording_frame_dir_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".png") or name.ends_with(".webm")):
			DirAccess.remove_absolute(recording_frame_dir_abs.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()

func _update_tutorial_recording(delta: float) -> void:
	if not recording_active:
		return
	recording_elapsed += delta
	recording_frame_elapsed += delta
	var interval := 1.0 / float(recording_fps)
	if recording_frame_elapsed >= interval:
		recording_frame_elapsed = 0.0
		_capture_tutorial_recording_frame()
	if recording_elapsed >= recording_seconds:
		recording_active = false
		recording_pending_loop_start = false
		recording_waiting_for_loop_end = false
		_finish_tutorial_recording()

func _capture_tutorial_recording_frame() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var target_height: int = maxi(1, int(round(float(recording_width) * float(img.get_height()) / float(img.get_width()))))
	img.resize(recording_width, target_height, Image.INTERPOLATE_LANCZOS)
	var frame_path := recording_frame_dir_abs.path_join("frame_%04d.png" % recording_frame_count)
	var err := img.save_png(frame_path)
	if err == OK:
		recording_frame_count += 1

func _finish_tutorial_recording() -> void:
	var out_abs := ProjectSettings.globalize_path(recording_output_path)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())
	if recording_frame_count <= 0:
		_append_terminal("recording failed: no frames captured")
		return
	var args := PackedStringArray([
		"-y",
		"-framerate", str(recording_fps),
		"-i", recording_frame_dir_abs.path_join("frame_%04d.png"),
		"-c:v", "libvpx-vp9",
		"-b:v", "0",
		"-crf", "42",
		"-pix_fmt", "yuv420p",
		out_abs,
	])
	var output: Array = []
	var exit_code := OS.execute(recording_ffmpeg_path, args, output, true)
	if exit_code == 0:
		_append_terminal("recording saved: %s (%d frames at %d fps)" % [out_abs, recording_frame_count, recording_fps])
	else:
		_append_terminal("recording frames saved: %s\nffmpeg failed with exit code %d" % [recording_frame_dir_abs, exit_code])

func _submit_terminal() -> void:
	if tutorial_typing:
		return
	var command := command_input.text.strip_edges()
	if command.is_empty():
		return
	command_input.text = ""
	_sync_terminal_input_height()
	command_input.release_focus()
	await _run_terminal_command(command)

func _on_command_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if event.shift_pressed:
				return
			command_input.accept_event()
			get_viewport().set_input_as_handled()
			_submit_terminal()

func _sync_terminal_input_height() -> void:
	var line_count: int = max(1, command_input.get_line_count())
	var visible_lines: int = min(line_count, TERMINAL_INPUT_MAX_LINES)
	var height: float = max(TERMINAL_INPUT_MIN_HEIGHT, float(visible_lines) * TERMINAL_INPUT_LINE_HEIGHT + TERMINAL_INPUT_PADDING)
	command_input.custom_minimum_size.y = height
	submit_button.custom_minimum_size.y = height
	input_row.offset_top = TERMINAL_INPUT_ROW_BOTTOM - height
	input_row.offset_bottom = TERMINAL_INPUT_ROW_BOTTOM
	_refresh_terminal_layout()

func _refresh_terminal_layout() -> void:
	var should_collapse := _should_collapse_terminal_output()
	if should_collapse == terminal_collapsed and terminal_output.offset_bottom > 0.0:
		return
	terminal_collapsed = should_collapse
	var output_bottom := input_row.offset_top - TERMINAL_INPUT_OUTPUT_GAP
	if terminal_collapsed:
		terminal_output.offset_top = output_bottom - TERMINAL_OUTPUT_LINE_HEIGHT
		terminal_output.offset_bottom = output_bottom
		terminal_shade.offset_top = terminal_output.offset_top - TERMINAL_SHADE_PADDING
		terminal_shade.offset_bottom = input_row.offset_bottom + TERMINAL_SHADE_PADDING
	else:
		terminal_output.offset_top = TERMINAL_OUTPUT_TOP_EXPANDED
		terminal_output.offset_bottom = output_bottom
		terminal_shade.offset_top = 0.0
		terminal_shade.offset_bottom = TERMINAL_INPUT_ROW_BOTTOM + TERMINAL_SHADE_PADDING
	_scroll_terminal_to_end()

func _should_collapse_terminal_output() -> bool:
	if command_input.has_focus():
		return false
	if not terminal_output.get_selected_text().is_empty():
		return false
	return Time.get_ticks_msec() - terminal_last_output_msec >= TERMINAL_IDLE_COLLAPSE_MSEC

func _update_terminal_collapse() -> void:
	_refresh_terminal_layout()

func _terminal_input_line_count() -> int:
	return max(1, command_input.get_line_count())

func _scroll_terminal_output(line_delta: int) -> void:
	var scrollbar := terminal_output.get_v_scroll_bar()
	if scrollbar == null:
		return
	scrollbar.value = clampf(scrollbar.value + float(line_delta) * scrollbar.step, scrollbar.min_value, scrollbar.max_value)

func _on_tutorial_button_pressed() -> void:
	_start_tutorial(false)

func _start_tutorial(autoplay: bool = false) -> void:
	var finishing_loop_recording := recording_loop_once and recording_waiting_for_loop_end
	tutorial_active = false
	tutorial_typing = false
	tutorial_autoplay = autoplay
	reset_demo_state()
	_reset_terminal()
	tutorial_active = true
	tutorial_index = 0
	_show_tutorial_step()
	if recording_pending_loop_start:
		recording_pending_loop_start = false
		recording_active = true
		recording_elapsed = 0.0
		recording_frame_elapsed = 0.0
		_capture_tutorial_recording_frame()
	elif finishing_loop_recording:
		recording_waiting_for_loop_end = false
		await get_tree().process_frame
		_capture_tutorial_recording_frame()
		recording_active = false
		_finish_tutorial_recording()
	_type_tutorial_command(str(tutorial_steps[tutorial_index]["command"]))

func _show_tutorial_step() -> void:
	if tutorial_index < 0 or tutorial_index >= tutorial_steps.size():
		return
	var step := tutorial_steps[tutorial_index]
	tutorial_popup.visible = true
	tutorial_title.text = "Step %d/%d - %s" % [
		tutorial_index + 1,
		tutorial_steps.size(),
		str(step.get("chapter", "Tutorial")),
	]
	tutorial_body.text = "%s\n\nCommand:\n%s\n\nPress Enter or the arrow button to run it." % [
		str(step.get("body", "")),
		str(step.get("command", "")),
	]

func _type_tutorial_command(command: String) -> void:
	tutorial_typing = true
	command_input.text = ""
	command_input.grab_focus()
	for i in command.length():
		if not tutorial_active:
			tutorial_typing = false
			return
		command_input.text += command[i]
		command_input.set_caret_line(command_input.get_line_count() - 1)
		command_input.set_caret_column(command_input.get_line(command_input.get_caret_line()).length())
		_sync_terminal_input_height()
		await get_tree().create_timer(TUTORIAL_TYPE_DELAY).timeout
	tutorial_typing = false
	if tutorial_autoplay and tutorial_active:
		await get_tree().create_timer(TUTORIAL_AUTOPLAY_SUBMIT_DELAY).timeout
		if tutorial_autoplay and tutorial_active and command_input.text.strip_edges() == command:
			await _submit_terminal()

func _on_terminal_command_finished(command: String, _result: Variant) -> void:
	if not tutorial_active or tutorial_index < 0 or tutorial_index >= tutorial_steps.size():
		return
	var expected := str(tutorial_steps[tutorial_index].get("command", ""))
	if command != expected:
		return
	tutorial_index += 1
	if tutorial_index >= tutorial_steps.size():
		tutorial_active = false
		tutorial_popup.visible = true
		tutorial_title.text = "Tutorial complete"
		if tutorial_autoplay:
			tutorial_body.text = "The documentation-derived walkthrough is complete. Restarting from step 1."
			if recording_loop_once and recording_active:
				recording_waiting_for_loop_end = true
			command_input.text = ""
			_sync_terminal_input_height()
			await get_tree().create_timer(TUTORIAL_LOOP_DELAY).timeout
			if tutorial_autoplay:
				_start_tutorial(true)
			return
		tutorial_body.text = "The documentation-derived walkthrough is complete. The terminal remains live, and the scene can still be played normally."
		command_input.text = ""
		_sync_terminal_input_height()
		return
	_show_tutorial_step()
	_type_tutorial_command(str(tutorial_steps[tutorial_index]["command"]))

func _run_terminal_command(command: String) -> Variant:
	_append_terminal("$ " + command)
	if command == "clear":
		_reset_terminal()
		var cleared := {"ok": true, "cleared": true}
		terminal_command_finished.emit(command, cleared)
		return cleared
	var server := get_node_or_null("/root/GodotAgentCli")
	if server == null or not (server.has_method("call_gdli_string_async") or server.has_method("call_gdli_string")):
		_append_terminal("GodotAgentCli singleton not found.")
		var missing := {"code": "not_found", "message": "GodotAgentCli singleton not found."}
		terminal_command_finished.emit(command, missing)
		return missing
	var routed := command
	if routed.begins_with("gdli "):
		routed = routed.substr(5).strip_edges()
	if routed.begins_with("help "):
		var help_text := _format_terminal_help(routed.substr(5).strip_edges(), server)
		_append_terminal(help_text)
		terminal_command_finished.emit(command, help_text)
		return help_text
	if routed == "--help" or routed == "help":
		routed = "verbs"
	var result: Variant
	if server.has_method("call_gdli_string_async"):
		result = await server.call_gdli_string_async(routed)
	else:
		result = server.call_gdli_string(routed)
	var formatted := _format_terminal_result(result)
	if (command == "gdli --help" or command == "gdli help" or command == "--help" or command == "help") and _looks_like_registry(result):
		formatted += "\n\n" + GDLI_UNIVERSAL_FLAGS
	_append_terminal(formatted)
	terminal_command_finished.emit(command, result)
	return result

func _format_terminal_help(verb_name: String, server: Node) -> String:
	var result: Variant = server.call_gdli_string("verbs")
	if not _looks_like_registry(result):
		return _format_terminal_result(result)
	for entry in result:
		if str(entry.get("name", "")) == verb_name:
			return _render_verb_help(entry) + "\n\n" + GDLI_UNIVERSAL_FLAGS
	return "error: not_found: unknown verb: %s" % verb_name

func _format_terminal_result(value: Variant) -> String:
	if value is Dictionary and value.has("code") and value.has("message"):
		return "error: %s: %s" % [str(value["code"]), str(value["message"])]
	if value is Dictionary and (value.has("diff") or value.has("marked")):
		return _format_terminal_envelope(value)
	if _looks_like_registry(value):
		return _render_registry(value)
	return _format_terminal_data(value)

func _format_terminal_envelope(env: Dictionary) -> String:
	var lines: Array[String] = []
	if not env.has("diff"):
		lines.append(_format_terminal_data(env.get("data")))
	if env.has("diff"):
		lines.append("diff:\n" + JSON.stringify(env["diff"], "  "))
	if env.has("marked"):
		lines.append("marked: " + str(env["marked"]))
	return "\n".join(lines)

func _format_terminal_data(value: Variant) -> String:
	if _looks_like_registry(value):
		return _render_registry(value)
	return JSON.stringify(value, "  ")

func _looks_like_registry(value: Variant) -> bool:
	if not (value is Array):
		return false
	if value.is_empty():
		return false
	for entry in value:
		if not (entry is Dictionary) or not entry.has("module") or not entry.has("name") or not entry.has("target") or not entry.has("help"):
			return false
	return true

func _render_registry(registry: Array) -> String:
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

func _render_verb_help(entry: Dictionary) -> String:
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

func _append_terminal(line: String) -> void:
	terminal_last_output_msec = Time.get_ticks_msec()
	transcript.append(line)
	while transcript.size() > 80:
		transcript.pop_front()
	terminal_output.text = "\n".join(transcript)
	_refresh_terminal_layout()
	await get_tree().process_frame
	_scroll_terminal_to_end()

func _reset_terminal() -> void:
	terminal_last_output_msec = Time.get_ticks_msec()
	transcript.clear()
	transcript.append(TERMINAL_HINT)
	terminal_output.text = TERMINAL_HINT
	_refresh_terminal_layout()

func _scroll_terminal_to_end() -> void:
	terminal_output.scroll_to_line(max(terminal_output.get_line_count() - 1, 0))

func ping_back(n: int) -> int:
	return n * 2
