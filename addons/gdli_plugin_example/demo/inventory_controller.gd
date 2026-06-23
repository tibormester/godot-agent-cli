extends RefCounted

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")

var loot_root: Node2D
var slot_buttons: Array[Button] = []
var spawn_loot: Callable
var status_changed: Callable

var dragging_loot: Node2D = null
var drag_offset := Vector2.ZERO
var drag_start_position := Vector2.ZERO
var drag_source_slot := -1
var pending_inventory_drag_slot := -1
var pending_inventory_drag_type := ""
var inventory := [
	{"type": "", "count": 0},
	{"type": "", "count": 0},
	{"type": "", "count": 0},
	{"type": "", "count": 0},
]

func bind(nodes: Dictionary, loot_spawner: Callable, on_status_changed: Callable) -> void:
	loot_root = nodes["loot_root"]
	slot_buttons = nodes["slot_buttons"]
	spawn_loot = loot_spawner
	status_changed = on_status_changed

func reset() -> void:
	dragging_loot = null
	drag_source_slot = -1
	pending_inventory_drag_slot = -1
	pending_inventory_drag_type = ""
	for i in inventory.size():
		inventory[i] = {"type": "", "count": 0}
	update_inventory_ui()

func collect_loot_into_best_inventory(loot_name: String = "") -> Dictionary:
	var collected: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	for loot in loot_root.get_children():
		if loot_name != "" and loot.name != loot_name and str(loot.get_path()) != loot_name:
			continue
		var slot_index := best_inventory_slot_for(str(loot.get_meta("type")))
		if slot_index < 0:
			skipped.append({
				"loot": loot.name,
				"reason": "inventory_full",
			})
			continue
		var loot_type := str(loot.get_meta("type"))
		if add_loot_to_slot(loot, slot_index):
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
	update_inventory_ui()
	_emit_status_changed()
	return {
		"ok": skipped.is_empty(),
		"collected": collected,
		"skipped": skipped,
		"inventory": inventory.duplicate(true),
	}

func try_start_drag(pos: Vector2) -> bool:
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

func update_pending_inventory_drag(pos: Vector2) -> void:
	if pending_inventory_drag_slot < 0 or dragging_loot != null:
		return
	if slot_buttons[pending_inventory_drag_slot].get_global_rect().has_point(pos):
		return
	drag_source_slot = pending_inventory_drag_slot
	dragging_loot = spawn_loot.call(pos, pending_inventory_drag_type)
	dragging_loot.z_index = 20
	drag_offset = Vector2.ZERO
	drag_start_position = dragging_loot.global_position
	remove_one_from_slot(drag_source_slot)
	pending_inventory_drag_slot = -1
	pending_inventory_drag_type = ""
	update_inventory_ui()
	_emit_status_changed()

func update_dragged_loot(pos := Vector2.INF) -> void:
	if dragging_loot == null or not is_instance_valid(dragging_loot):
		dragging_loot = null
		return
	var pointer := loot_root.get_viewport().get_mouse_position() if pos == Vector2.INF else pos
	dragging_loot.global_position = pointer + drag_offset

func drop_dragged_loot(pos: Vector2) -> void:
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
			accepted = add_loot_to_slot(dragging_loot, i)
			break
	if accepted:
		dragging_loot.queue_free()
	else:
		if drag_source_slot >= 0 and target_slot >= 0:
			if add_loot_to_slot(dragging_loot, drag_source_slot):
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
	update_inventory_ui()
	_emit_status_changed()

func is_dragging_or_pending() -> bool:
	return dragging_loot != null or pending_inventory_drag_slot >= 0

func update_inventory_ui() -> void:
	for i in slot_buttons.size():
		var slot: Dictionary = inventory[i]
		if str(slot["type"]).is_empty():
			slot_buttons[i].text = "Empty"
		else:
			slot_buttons[i].text = "%s\n%d/%d" % [str(slot["type"]).capitalize(), int(slot["count"]), DemoConfig.MAX_STACK]

func add_loot_to_slot(loot: Node2D, slot_index: int) -> bool:
	var loot_type := str(loot.get_meta("type"))
	var slot: Dictionary = inventory[slot_index]
	if str(slot["type"]).is_empty():
		slot["type"] = loot_type
		slot["count"] = 1
		inventory[slot_index] = slot
		return true
	if slot["type"] == loot_type and int(slot["count"]) < DemoConfig.MAX_STACK:
		slot["count"] = int(slot["count"]) + 1
		inventory[slot_index] = slot
		return true
	return false

func best_inventory_slot_for(loot_type: String) -> int:
	for i in inventory.size():
		var slot: Dictionary = inventory[i]
		if slot["type"] == loot_type and int(slot["count"]) < DemoConfig.MAX_STACK:
			return i
	for i in inventory.size():
		var slot: Dictionary = inventory[i]
		if str(slot["type"]).is_empty():
			return i
	return -1

func remove_one_from_slot(slot_index: int) -> void:
	var slot: Dictionary = inventory[slot_index]
	slot["count"] = max(0, int(slot["count"]) - 1)
	if int(slot["count"]) == 0:
		slot["type"] = ""
	inventory[slot_index] = slot

func _emit_status_changed() -> void:
	if status_changed.is_valid():
		status_changed.call()
