extends Node2D

signal terminal_command_finished(command: String, result: Variant)

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")
const ArenaController = preload("res://addons/gdli_plugin_example/demo/arena_controller.gd")
const InventoryController = preload("res://addons/gdli_plugin_example/demo/inventory_controller.gd")
const RecordingController = preload("res://addons/gdli_plugin_example/demo/recording_controller.gd")
const TerminalController = preload("res://addons/gdli_plugin_example/demo/terminal_controller.gd")
const TutorialController = preload("res://addons/gdli_plugin_example/demo/tutorial_controller.gd")

@onready var arena: Node2D = $Arena
@onready var player: Node2D = $Arena/Player
@onready var player_body = $Arena/Player/Body
@onready var sword_arc = $Arena/Player/SwordArc
@onready var enemies_root: Node2D = $Arena/Enemies
@onready var loot_root: Node2D = $Arena/Loot
@onready var status_label: Label = $Hud/StatusLabel
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

var arena_controller
var inventory_controller
var recording_controller
var terminal_controller
var tutorial_controller

func _ready() -> void:
	randomize()
	DemoConfig.ensure_demo_input_actions()
	_bind_controllers()
	wave_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_wave_button.focus_mode = Control.FOCUS_NONE
	next_wave_button.pressed.connect(arena_controller.start_next_wave)
	terminal_controller.reset_terminal()
	terminal_controller.sync_terminal_input_height()
	arena_controller.spawn_wave()
	inventory_controller.update_inventory_ui()
	_update_status()

func setup_demo_project_globals(options: Dictionary = {}) -> Dictionary:
	var result := ensure_demo_input_actions()
	if bool(options.get("record", false)):
		result["recording"] = recording_controller.start(options)
	if bool(options.get("autoplay", false)):
		result["autoplay"] = tutorial_controller.start_requested_by_setup()
	return result

func gdli_plugin_example_setup(options: Dictionary = {}) -> Dictionary:
	return setup_demo_project_globals(options)

func reset_demo_state() -> Dictionary:
	var result: Dictionary = arena_controller.reset()
	inventory_controller.reset()
	_update_status()
	return result

func tutorial_spawn_loot() -> Dictionary:
	var spawned := []
	var coin: Node2D = arena_controller.spawn_loot(DemoConfig.ARENA_CENTER + Vector2(-72, 88), "coin")
	var gem: Node2D = arena_controller.spawn_loot(DemoConfig.ARENA_CENTER + Vector2(-28, 92), "gem")
	spawned.append(coin.name)
	spawned.append(gem.name)
	_update_status()
	return {
		"ok": true,
		"spawned": spawned,
		"loot_count": arena_controller.loot_count(),
	}

func ensure_demo_input_actions() -> Dictionary:
	return DemoConfig.ensure_demo_input_actions()

func clear_console() -> Dictionary:
	return terminal_controller.clear_console()

func gdli_plugin_example_console_clear() -> Dictionary:
	return clear_console()

func spawn_enemies(count: int = 1) -> Dictionary:
	return arena_controller.spawn_enemies(count)

func clear_enemies() -> Dictionary:
	return arena_controller.clear_enemies()

func gdli_plugin_example_enemies_clear() -> Dictionary:
	return clear_enemies()

func gdli_plugin_example_enemies_spawn(count: int = 1) -> Dictionary:
	return spawn_enemies(count)

func start_wave(next_wave: int = -1) -> Dictionary:
	return arena_controller.start_wave(next_wave)

func finish_wave() -> Dictionary:
	return arena_controller.finish_wave()

func gdli_plugin_example_wave_next() -> Dictionary:
	return start_wave(arena_controller.wave + 1)

func gdli_plugin_example_wave_finish() -> Dictionary:
	return finish_wave()

func collect_loot_into_best_inventory(loot_name: String = "") -> Dictionary:
	return inventory_controller.collect_loot_into_best_inventory(loot_name)

func gdli_plugin_example_items_collect_best() -> Dictionary:
	return collect_loot_into_best_inventory()

func ping_back(n: int) -> int:
	return n * 2

func _process(delta: float) -> void:
	arena_controller.update_player_movement(delta, terminal_controller.has_input_focus())
	inventory_controller.update_dragged_loot()
	terminal_controller.update_terminal_collapse()
	recording_controller.update(delta)
	queue_redraw()

func _draw() -> void:
	draw_circle(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS + 12.0, Color(0.05, 0.08, 0.09, 0.9))
	draw_circle(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS + 7.0, Color(0.22, 0.28, 0.28, 0.9))
	draw_circle(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS, Color(0.1, 0.13, 0.14, 0.95))
	draw_arc(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS, 0.0, TAU, 160, Color(0.84, 0.68, 0.28, 1.0), 4.0)
	draw_arc(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS - 38.0, 0.0, TAU, 160, Color(0.22, 0.32, 0.31, 0.9), 2.0)
	draw_arc(DemoConfig.ARENA_CENTER, DemoConfig.ARENA_RADIUS - 74.0, 0.0, TAU, 160, Color(0.12, 0.2, 0.2, 0.65), 1.0)

func _input(event: InputEvent) -> void:
	if tutorial_controller.active and not tutorial_controller.typing and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			terminal_controller.submit_terminal()
			return
	if not inventory_controller.is_dragging_or_pending() and terminal_controller.terminal_handles_event(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if inventory_controller.try_start_drag(event.position):
				return
			arena_controller.swing_at(event.position)
		else:
			inventory_controller.drop_dragged_loot(event.position)
	if event is InputEventMouseMotion:
		inventory_controller.update_pending_inventory_drag(event.position)
		inventory_controller.update_dragged_loot(event.position)

func _start_tutorial_autoplay() -> void:
	tutorial_controller.start(true)

func _bind_controllers() -> void:
	arena_controller = ArenaController.new(self)
	inventory_controller = InventoryController.new()
	recording_controller = RecordingController.new(self)
	terminal_controller = TerminalController.new(self)
	tutorial_controller = TutorialController.new(self)

	arena_controller.bind({
		"arena": arena,
		"player": player,
		"player_body": player_body,
		"sword_arc": sword_arc,
		"enemies_root": enemies_root,
		"loot_root": loot_root,
		"wave_popup": wave_popup,
	}, _update_status)
	inventory_controller.bind({
		"loot_root": loot_root,
		"slot_buttons": slot_buttons,
	}, arena_controller.spawn_loot, _update_status)
	terminal_controller.bind({
		"terminal_panel": terminal_panel,
		"terminal_shade": terminal_shade,
		"terminal_output": terminal_output,
		"tutorial_button": tutorial_button,
		"input_row": input_row,
		"command_input": command_input,
		"submit_button": submit_button,
	}, _terminal_submit_blocked)
	recording_controller.bind(terminal_controller)
	tutorial_controller.bind({
		"tutorial_button": tutorial_button,
		"tutorial_popup": tutorial_popup,
		"tutorial_title": tutorial_title,
		"tutorial_body": tutorial_body,
	}, terminal_controller, recording_controller, reset_demo_state)

func _terminal_submit_blocked() -> bool:
	return tutorial_controller.typing

func _update_status() -> void:
	status_label.text = "Wave %d  Enemies %d  Loot %d\nWASD moves. Click swings. Drag loot into inventory." % [
		arena_controller.wave,
		enemies_root.get_child_count(),
		arena_controller.loot_count(),
	]
	next_wave_button.text = "Start Wave %d" % (arena_controller.wave + 1)
