extends RefCounted

static func add_godot_icon_visual(root: Node, body_color: Color, angry: bool) -> void:
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

static func add_coin_visual(loot: Node2D) -> void:
	var rim := Polygon2D.new()
	rim.name = "Body"
	rim.polygon = circle_points(14.0, 32)
	rim.color = Color(0.96, 0.56, 0.08, 1.0)
	loot.add_child(rim)

	var face := Polygon2D.new()
	face.name = "CoinFace"
	face.polygon = circle_points(10.0, 32)
	face.color = Color(1.0, 0.83, 0.25, 1.0)
	loot.add_child(face)

	var shine := Line2D.new()
	shine.name = "CoinShine"
	shine.points = PackedVector2Array([Vector2(-4, -8), Vector2(5, -8)])
	shine.width = 2.0
	shine.default_color = Color(1.0, 0.96, 0.56, 1.0)
	loot.add_child(shine)

static func add_gem_visual(loot: Node2D) -> void:
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

static func circle_points(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

static func _add_eye_visual(root: Node, position: Vector2, angry: bool) -> void:
	var eye := Polygon2D.new()
	eye.name = "Eye"
	eye.position = position
	eye.polygon = circle_points(8.0, 24)
	eye.color = Color(0.96, 0.98, 1.0, 1.0)
	root.add_child(eye)

	var pupil := Polygon2D.new()
	pupil.name = "Pupil"
	pupil.position = position
	pupil.polygon = circle_points(4.6 if angry else 4.2, 20)
	pupil.color = Color(0.08, 0.09, 0.1, 1.0)
	root.add_child(pupil)
