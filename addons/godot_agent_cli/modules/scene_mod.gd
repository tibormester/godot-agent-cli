extends RefCounted
## scene module — structural tree + open/persist. Paths are relative to the scene root.

var s

func register_into(server) -> void:
	s = server
	s.registry.register("scene", "scene tree", _tree, {
		"help": "the scene tree (name/type/path/script), rooted at the scene.",
		"target": "auto",
		"args": [
			{"name": "--root", "type": "string", "required": false, "default": "", "help": "subtree root (path or @ref)"},
			{"name": "--depth", "type": "int", "required": false, "default": 20, "help": "max depth"},
		],
	})
	s.registry.register("scene", "scene load", _load, {
		"help": "open a scene (editor) / change the running scene (game). Default = main scene.",
		"target": "auto", "async": true,
		"args": [
			{"name": "path", "type": "string", "required": false, "default": "", "help": "res:// scene path"},
			{"name": "--main", "type": "bool", "required": false, "default": false, "help": "load the project main scene (default)"},
		],
	})
	s.registry.register("scene", "scene save", _save, {
		"help": "persist the scene to its .tscn (editor save; game pack+save).",
		"target": "editor",
		"args": [{"name": "--path", "type": "string", "required": false, "default": "", "help": "save-as path"}],
	})

func _tree(p: Dictionary) -> Variant:
	var root = s.target_root()
	if str(p.get("root", "")) != "":
		root = s.resolve_node(str(p["root"]))
	if root == null:
		return s.err("not_found", "no scene open / root not found")
	return _node_tree(s.target_root(), root, int(p.get("depth", 20)), 0)

func _node_tree(scene_root: Node, node: Node, depth: int, d: int) -> Dictionary:
	var e := {
		"name": str(node.name),
		"type": node.get_class(),
		"path": "." if node == scene_root else str(scene_root.get_path_to(node)),
	}
	var scr = node.get_script()
	if scr != null and scr.resource_path != "":
		e["script"] = scr.resource_path
	var kids := []
	if d < depth:
		for c in node.get_children():
			kids.append(_node_tree(scene_root, c, depth, d + 1))
	elif node.get_child_count() > 0:
		e["child_count"] = node.get_child_count()
	e["children"] = kids
	return e

func _load(p: Dictionary) -> Variant:
	var path := str(p.get("path", ""))
	if bool(p.get("main", false)):
		path = ""
	if path.is_empty():
		path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if path.is_empty():
		return s.err("bad_params", "no path and no main scene configured")
	if s.is_editor():
		var ei = s.editor_interface()
		if ei == null:
			return s.err("editor_only", "EditorInterface unavailable")
		ei.open_scene_from_path(path)
		await s.get_tree().process_frame
		return {"scene": path}
	var e = s.get_tree().change_scene_to_file(path)
	if e != OK:
		return s.err("handler_error", "change_scene failed: " + error_string(e))
	await s.get_tree().process_frame
	return {"scene": path}

func _save(p: Dictionary) -> Variant:
	var path := str(p.get("path", ""))
	if s.is_editor():
		var ei = s.editor_interface()
		if ei == null:
			return s.err("editor_only", "EditorInterface unavailable")
		var root = s.target_root()
		if root == null:
			return s.err("not_found", "no scene open in the editor")
		if path.is_empty():
			ei.save_scene()
			return {"saved": root.scene_file_path}
		ei.save_scene_as(path)
		return {"saved": path}
	var groot = s.target_root()
	if groot == null:
		return s.err("not_found", "no current scene")
	if path.is_empty():
		path = groot.scene_file_path
	if path.is_empty():
		return s.err("bad_params", "no path and scene has no file path")
	_own_recursive(groot, groot)
	var ps := PackedScene.new()
	var e := ps.pack(groot)
	if e != OK:
		return s.err("handler_error", "pack failed: " + error_string(e))
	e = ResourceSaver.save(ps, path)
	if e != OK:
		return s.err("handler_error", "save failed: " + error_string(e))
	return {"saved": path}

func _own_recursive(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for c in node.get_children():
		_own_recursive(c, owner)
