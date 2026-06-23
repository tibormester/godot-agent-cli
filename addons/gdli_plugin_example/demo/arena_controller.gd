extends RefCounted

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")
const DemoVisualFactory = preload("res://addons/gdli_plugin_example/demo/demo_visual_factory.gd")

var owner: Node2D
var arena: Node2D
var player: Node2D
var player_body: Node
var sword_arc: Node2D
var enemies_root: Node2D
var loot_root: Node2D
var wave_popup: Control
var status_changed: Callable

var wave := 1
var enemy_seq := 0
var loot_seq := 0
var swing_seq := 0

func _init(scene_owner: Node2D) -> void:
	owner = scene_owner

func bind(nodes: Dictionary, on_status_changed: Callable) -> void:
	arena = nodes["arena"]
	player = nodes["player"]
	player_body = nodes["player_body"]
	sword_arc = nodes["sword_arc"]
	enemies_root = nodes["enemies_root"]
	loot_root = nodes["loot_root"]
	wave_popup = nodes["wave_popup"]
	status_changed = on_status_changed
	DemoVisualFactory.add_godot_icon_visual(player_body, Color(0.28, 0.55, 0.78, 1.0), false)

func reset() -> Dictionary:
	wave = 1
	enemy_seq = 0
	loot_seq = 0
	swing_seq = 0
	player.position = DemoConfig.ARENA_CENTER
	sword_arc.visible = false
	wave_popup.visible = false
	_clear_children_now(enemies_root)
	_clear_children_now(loot_root)
	for child in arena.get_children():
		if child != enemies_root and child != loot_root and child != player:
			_remove_child_now(child)
	spawn_wave()
	_emit_status_changed()
	return {
		"ok": true,
		"wave": wave,
		"enemy_count": enemies_root.get_child_count(),
		"loot_count": loot_count(),
	}

func spawn_enemies(count: int = 1) -> Dictionary:
	var spawned: Array[String] = []
	for i in range(max(0, count)):
		enemy_seq += 1
		var angle := TAU * float(enemy_seq % 12) / 12.0
		var radius := 96.0 + 22.0 * float(enemy_seq % 4)
		var pos := DemoConfig.ARENA_CENTER + Vector2(cos(angle), sin(angle)) * radius
		_spawn_enemy(pos)
		spawned.append(enemies_root.get_child(enemies_root.get_child_count() - 1).name)
	_emit_status_changed()
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
	_emit_status_changed()
	return {
		"ok": true,
		"cleared": cleared,
		"enemy_count": 0,
		"wave": wave,
	}

func start_wave(next_wave: int = -1) -> Dictionary:
	if next_wave > 0:
		wave = next_wave
	spawn_wave()
	return {
		"ok": true,
		"wave": wave,
		"enemy_count": enemies_root.get_child_count(),
	}

func finish_wave() -> Dictionary:
	var cleared := enemies_root.get_child_count()
	_clear_children_now(enemies_root)
	wave_popup.visible = true
	_emit_status_changed()
	return {
		"ok": true,
		"cleared": cleared,
		"wave": wave,
		"next_wave": wave + 1,
	}

func start_next_wave() -> void:
	wave += 1
	spawn_wave()

func spawn_wave() -> void:
	wave_popup.visible = false
	_clear_children_now(enemies_root)
	var count := wave + 2
	for i in count:
		enemy_seq += 1
		var angle := TAU * float(i) / float(count) + wave * 0.31
		var radius := 118.0 + 24.0 * float(i % 3)
		var pos := DemoConfig.ARENA_CENTER + Vector2(cos(angle), sin(angle)) * radius
		_spawn_enemy(pos)
	_emit_status_changed()

func update_player_movement(delta: float, blocked: bool) -> void:
	if blocked:
		return
	var axis := Vector2(
		Input.get_action_strength(DemoConfig.ACTION_MOVE_RIGHT) - Input.get_action_strength(DemoConfig.ACTION_MOVE_LEFT),
		Input.get_action_strength(DemoConfig.ACTION_MOVE_DOWN) - Input.get_action_strength(DemoConfig.ACTION_MOVE_UP)
	)
	if axis.length() > 0.0:
		move_player(axis.normalized() * DemoConfig.PLAYER_SPEED * delta)

func move_player(offset: Vector2) -> void:
	var target := player.position + offset
	var from_center := target - DemoConfig.ARENA_CENTER
	if from_center.length() > DemoConfig.ARENA_RADIUS - 20.0:
		target = DemoConfig.ARENA_CENTER + from_center.normalized() * (DemoConfig.ARENA_RADIUS - 20.0)
	player.position = target
	_emit_status_changed()

func swing_at(pos: Vector2) -> void:
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
		if enemy_dir.length() <= DemoConfig.SWORD_RANGE and abs(rad_to_deg(direction.angle_to(enemy_dir.normalized()))) <= DemoConfig.SWORD_ARC_DEGREES * 0.5:
			damage_enemy(enemy, 1)
			hit_count += 1
	show_damage_text(player.global_position + direction * 64.0, "swing %d" % swing_seq, Color(0.9, 0.96, 1.0, 1.0))
	owner.get_tree().create_timer(0.5).timeout.connect(func(): sword_arc.visible = false)
	if hit_count == 0:
		_emit_status_changed()

func damage_enemy(enemy: Node2D, amount: int) -> void:
	var hp := int(enemy.get_meta("hp")) - amount
	enemy.set_meta("hp", hp)
	_update_enemy_hp(enemy)
	show_damage_text(enemy.global_position + Vector2(0, -38), "-%d" % amount, Color(1.0, 0.38, 0.24, 1.0))
	if hp <= 0:
		spawn_loot(enemy.global_position, str(enemy.get_meta("loot_type")))
		enemy.queue_free()
		await owner.get_tree().process_frame
		check_wave_clear()
	else:
		_emit_status_changed()

func spawn_loot(pos: Vector2, loot_type: String) -> Node2D:
	loot_seq += 1
	var loot := Node2D.new()
	loot.name = "Loot%d" % loot_seq
	loot.position = pos + Vector2(18, 12)
	loot.set_meta("type", loot_type)
	loot_root.add_child(loot)

	if loot_type == "coin":
		DemoVisualFactory.add_coin_visual(loot)
	else:
		DemoVisualFactory.add_gem_visual(loot)

	var label := Label.new()
	label.name = "TypeLabel"
	label.position = Vector2(-16, 14)
	label.text = loot_type
	label.add_theme_font_size_override("font_size", 12)
	loot.add_child(label)
	return loot

func show_damage_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.name = "Damage%d" % Time.get_ticks_msec()
	label.global_position = pos
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	arena.add_child(label)
	var tween := owner.create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -24), 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.finished.connect(label.queue_free)

func check_wave_clear() -> void:
	if enemies_root.get_child_count() == 0:
		wave_popup.visible = true
	_emit_status_changed()

func loot_count() -> int:
	var count := 0
	for loot in loot_root.get_children():
		if not loot.is_queued_for_deletion():
			count += 1
	return count

func clear_children_now(root: Node) -> void:
	_clear_children_now(root)

func _spawn_enemy(pos: Vector2) -> void:
	var enemy := Node2D.new()
	enemy.name = "Enemy%d" % enemy_seq
	enemy.position = pos
	enemy.set_meta("hp", DemoConfig.ENEMY_HP)
	enemy.set_meta("max_hp", DemoConfig.ENEMY_HP)
	enemy.set_meta("loot_type", "gem" if randf() < DemoConfig.GEM_DROP_CHANCE else "coin")
	enemies_root.add_child(enemy)

	var body := Node2D.new()
	body.name = "Body"
	body.scale = Vector2(0.86, 0.86)
	enemy.add_child(body)
	DemoVisualFactory.add_godot_icon_visual(body, Color(0.95, 0.1, 0.1, 1.0), true)

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

func _clear_children_now(root: Node) -> void:
	for child in root.get_children():
		_remove_child_now(child)

func _remove_child_now(child: Node) -> void:
	var parent := child.get_parent()
	if parent != null:
		parent.remove_child(child)
	child.queue_free()

func _emit_status_changed() -> void:
	if status_changed.is_valid():
		status_changed.call()
