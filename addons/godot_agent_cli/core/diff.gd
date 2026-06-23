extends RefCounted
## Scene snapshot + compare — the structural test signal. snapshot() rooted at a scene subtree
## (never /root: the caller passes the scene), internal nodes dropped by get_children() default.
## Default capture = a salient prop set (readable diffs); full = all storage props.

const Codec := preload("res://addons/godot_agent_cli/core/codec.gd")

const SALIENT := [
	"visible", "modulate", "position", "global_position", "rotation", "rotation_degrees",
	"scale", "size", "z_index", "text", "value", "disabled", "button_pressed", "frame",
	"current", "enabled", "stream", "playing",
]

func snapshot(root: Node, depth: int, full := false, ignores: Array = []) -> Dictionary:
	var out := {}
	if root != null:
		_walk(root, root, depth, 0, out, full, ignores)
	return out

func _walk(root: Node, node: Node, depth: int, d: int, out: Dictionary, full: bool, ignores: Array) -> void:
	var rel := "." if node == root else str(root.get_path_to(node))
	if rel != "." and _ignored(rel, ignores):
		return
	out[rel] = _capture(node, full)
	if d < depth:
		for c in node.get_children():
			_walk(root, c, depth, d + 1, out, full, ignores)

func _capture(node: Node, full: bool) -> Dictionary:
	var e := {"type": node.get_class()}
	var scr = node.get_script()
	if scr != null and scr.resource_path != "":
		e["script"] = scr.resource_path
	var props := {}
	if full:
		for p in node.get_property_list():
			var usage: int = p["usage"]
			if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
				continue
			if not (usage & PROPERTY_USAGE_STORAGE):
				continue
			props[p["name"]] = Codec.to_json(node.get(p["name"]))
	else:
		for name in SALIENT:
			if name in node:
				props[name] = Codec.to_json(node.get(name))
	e["props"] = props
	return e

func compare(old: Dictionary, new: Dictionary) -> Dictionary:
	var added := []
	var removed := []
	var changed := []
	for path in new:
		if old.has(path):
			_diff_entry(path, old[path], new[path], changed)
		else:
			added.append(path)
	for path in old:
		if not new.has(path):
			removed.append(path)
	added.sort()
	removed.sort()
	return {"added": added, "removed": removed, "changed": changed}

func _diff_entry(path: String, a: Dictionary, b: Dictionary, changed: Array) -> void:
	if a.get("type") != b.get("type"):
		changed.append({"path": path, "field": "type", "from": a.get("type"), "to": b.get("type")})
	if a.get("script", "") != b.get("script", ""):
		changed.append({"path": path, "field": "script", "from": a.get("script", null), "to": b.get("script", null)})
	var ap: Dictionary = a.get("props", {})
	var bp: Dictionary = b.get("props", {})
	for k in bp:
		if not ap.has(k):
			changed.append({"path": path, "field": k, "from": null, "to": bp[k]})
		elif not _eq(ap[k], bp[k]):
			changed.append({"path": path, "field": k, "from": ap[k], "to": bp[k]})
	for k in ap:
		if not bp.has(k):
			changed.append({"path": path, "field": k, "from": ap[k], "to": null})

func _eq(a: Variant, b: Variant) -> bool:
	return a == b

func filter_delta(delta: Dictionary, ignores: Array) -> Dictionary:
	# Drop added/removed/changed entries whose scene-relative path matches an ignore token.
	# One-shot (nothing persists). Tokens are globs: a bare token also covers that subtree.
	if ignores.is_empty():
		return delta
	return {
		"added": (delta["added"] as Array).filter(func(x): return not _ignored(x, ignores)),
		"removed": (delta["removed"] as Array).filter(func(x): return not _ignored(x, ignores)),
		"changed": (delta["changed"] as Array).filter(func(x): return not _ignored(x["path"], ignores)),
	}

func _ignored(path: String, ignores: Array) -> bool:
	for ig in ignores:
		var pat := str(ig)
		if path == pat or path.begins_with(pat + "/") or path.match(pat):
			return true
	return false
