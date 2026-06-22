extends RefCounted
## Variant <-> JSON codec. Tagged form {"__t":"Vector2","v":[1,2]} for non-JSON Variants,
## node refs as {"__t":"Node","path":"/root/.."}; primitives pass through. Decode also accepts
## a Godot expression string ("Vector2(1,2)") via Expression as a fallback.

static func to_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return str(v)
		TYPE_VECTOR2:
			return {"__t": "Vector2", "v": [v.x, v.y]}
		TYPE_VECTOR2I:
			return {"__t": "Vector2i", "v": [v.x, v.y]}
		TYPE_VECTOR3:
			return {"__t": "Vector3", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR3I:
			return {"__t": "Vector3i", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR4:
			return {"__t": "Vector4", "v": [v.x, v.y, v.z, v.w]}
		TYPE_VECTOR4I:
			return {"__t": "Vector4i", "v": [v.x, v.y, v.z, v.w]}
		TYPE_COLOR:
			return {"__t": "Color", "v": [v.r, v.g, v.b, v.a]}
		TYPE_RECT2:
			return {"__t": "Rect2", "v": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_RECT2I:
			return {"__t": "Rect2i", "v": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_QUATERNION:
			return {"__t": "Quaternion", "v": [v.x, v.y, v.z, v.w]}
		TYPE_PLANE:
			return {"__t": "Plane", "v": [v.normal.x, v.normal.y, v.normal.z, v.d]}
		TYPE_TRANSFORM2D:
			return {"__t": "Transform2D", "v": [v.x.x, v.x.y, v.y.x, v.y.y, v.origin.x, v.origin.y]}
		TYPE_BASIS:
			return {"__t": "Basis", "v": [v.x.x, v.x.y, v.x.z, v.y.x, v.y.y, v.y.z, v.z.x, v.z.y, v.z.z]}
		TYPE_TRANSFORM3D:
			var t := v as Transform3D
			var b := t.basis
			var o := t.origin
			return {"__t": "Transform3D", "v": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]}
		TYPE_AABB:
			return {"__t": "AABB", "v": [v.position.x, v.position.y, v.position.z, v.size.x, v.size.y, v.size.z]}
		TYPE_NODE_PATH:
			return {"__t": "NodePath", "v": str(v)}
		TYPE_RID:
			return {"__t": "RID", "v": v.get_id()}
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = to_json(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for item in v:
				a.append(to_json(item))
			return a
		TYPE_PACKED_BYTE_ARRAY:
			return {"__t": "PackedByteArray", "b64": Marshalls.raw_to_base64(v)}
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var a := []
			for item in v:
				a.append(item)
			return a
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var a := []
			for item in v:
				a.append(to_json(item))
			return a
		TYPE_OBJECT:
			if v == null:
				return null
			if v is Node:
				return {"__t": "Node", "class": v.get_class(), "path": str(v.get_path())}
			if v is Resource:
				var r := {"__t": "Resource", "class": v.get_class()}
				if not v.resource_path.is_empty():
					r["path"] = v.resource_path
				return r
			return {"__t": "Object", "class": v.get_class()}
	return str(v)


static func from_json(v: Variant) -> Variant:
	# A raw string value may itself be JSON (e.g. a tag `{"__t":"Vector2","v":[1,2]}` passed straight to
	# `node set <value>`). Try JSON first; if it yields a structured value, decode that — so the tag form
	# works everywhere, not just nested in --props/--args. Non-JSON strings fall through to Expression.
	if v is String and not (v as String).is_empty():
		var j: Variant = JSON.parse_string(v)
		if j is Dictionary or j is Array:
			return from_json(j)
	if v is Dictionary:
		if v.has("__t"):
			var a: Array = v.get("v", [])
			match v["__t"]:
				"Vector2": return Vector2(a[0], a[1])
				"Vector2i": return Vector2i(a[0], a[1])
				"Vector3": return Vector3(a[0], a[1], a[2])
				"Vector3i": return Vector3i(a[0], a[1], a[2])
				"Vector4": return Vector4(a[0], a[1], a[2], a[3])
				"Vector4i": return Vector4i(a[0], a[1], a[2], a[3])
				"Color": return Color(a[0], a[1], a[2], a[3])
				"Rect2": return Rect2(a[0], a[1], a[2], a[3])
				"Rect2i": return Rect2i(a[0], a[1], a[2], a[3])
				"Quaternion": return Quaternion(a[0], a[1], a[2], a[3])
				"Plane": return Plane(a[0], a[1], a[2], a[3])
				"Transform2D": return Transform2D(Vector2(a[0], a[1]), Vector2(a[2], a[3]), Vector2(a[4], a[5]))
				"Basis": return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
				"AABB": return AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]))
				"NodePath": return NodePath(str(v.get("v", "")))
				"PackedByteArray": return Marshalls.base64_to_raw(str(v.get("b64", "")))
			return v
		var d := {}
		for k in v:
			d[k] = from_json(v[k])
		return d
	if v is Array:
		var a := []
		for item in v:
			a.append(from_json(item))
		return a
	if v is String and not (v as String).is_empty():
		var expr := Expression.new()
		if expr.parse(v) == OK:
			var r: Variant = expr.execute([], null, false)
			if not expr.has_execute_failed():
				return r
	return v
