extends RefCounted
## observe module — the read surface. Rooted at the scene (never /root), so editor GUI / autoloads /
## the harness are excluded by construction. (--diff / --mark are core, applied to any verb.)

var s

func register_into(server) -> void:
	s = server
	s.registry.register("observe", "inspect", _inspect, {
		"help": "read the scene snapshot (path -> type/script/props); mints an @eN ref per node.",
		"target": "auto",
		"args": [
			{"name": "--root", "type": "string", "required": false, "default": "", "help": "subtree root (path or @ref)"},
			{"name": "--depth", "type": "int", "required": false, "default": -1, "help": "max depth (default: unbounded)"},
			{"name": "--nodes", "type": "bool", "required": false, "default": false, "help": "include scene nodes (default)"},
			{"name": "--full", "type": "bool", "required": false, "default": false, "help": "all storage props (vs salient set)"},
			{"name": "--ui", "type": "bool", "required": false, "default": false, "help": "only visible Controls, each with its screen rect (for click --ref)"},
		],
	})
	s.registry.register("observe", "screenshot", _screenshot, {
		"help": "capture the viewport (game) / edited sub-viewport (editor) as base64.",
		"target": "auto", "async": true,
		"args": [
			{"name": "--out", "type": "string", "required": false, "default": "", "help": "client writes the image here"},
			{"name": "--format", "type": "string", "required": false, "default": "webp", "help": "webp|png"},
		],
	})

func _inspect(p: Dictionary) -> Variant:
	var root = s.target_root()
	if str(p.get("root", "")) != "":
		root = s.resolve_node(str(p["root"]))
	if root == null:
		return s.err("not_found", "no scene open / root not found")
	var depth := int(p.get("depth", -1))
	if depth < 0:
		depth = 1 << 30
	var snap = s.diff.snapshot(root, depth, bool(p.get("full", false)))
	# --ui: keep only visible Controls and attach each one's screen rect (the old `uisnapshot`).
	if bool(p.get("ui", false)) and not bool(p.get("nodes", false)):
		var filtered := {}
		for path in snap:
			var n: Node = root if str(path) == "." else root.get_node_or_null(NodePath(str(path)))
			if n is Control and (n as Control).is_visible_in_tree():
				var r := (n as Control).get_global_rect()
				var entry: Dictionary = snap[path]
				entry["rect"] = [r.position.x, r.position.y, r.size.x, r.size.y]
				filtered[path] = entry
		snap = filtered
	# Mint @eN refs for every reported node (resolvable later via @ref / used by input verbs).
	var paths: Array = snap.keys()
	var nodes := []
	for pth in paths:
		nodes.append(root if str(pth) == "." else root.get_node_or_null(NodePath(str(pth))))
	var refs = s.mint_refs(nodes)
	for i in paths.size():
		(snap[paths[i]] as Dictionary)["ref"] = refs[i]
	return snap

func _screenshot(p: Dictionary) -> Variant:
	await s.get_tree().process_frame
	var img: Image = null
	if s.is_editor():
		var ei = s.editor_interface()
		if ei == null:
			return s.err("editor_only", "EditorInterface unavailable")
		# The editor sub-viewport only renders while its main-screen panel is active, so switch to
		# 2D/3D (per the scene root), let it render, capture, then restore the prior screen.
		var root = s.target_root()
		var screen := "3D" if root is Node3D else "2D"
		var main: Node = ei.get_editor_main_screen()
		var prev := ""
		for c in main.get_children():
			if c.visible:
				prev = _screen_of(c)
				break
		ei.set_main_screen_editor(screen)
		for _i in 4:
			await s.get_tree().process_frame
		var vp: SubViewport = ei.get_editor_viewport_3d() if screen == "3D" else ei.get_editor_viewport_2d()
		if vp != null:
			img = vp.get_texture().get_image()
		if prev != "" and prev != screen:
			ei.set_main_screen_editor(prev)
	else:
		img = s.get_viewport().get_texture().get_image()
	if img == null:
		return s.err("handler_error", "failed to capture viewport")
	var fmt := str(p.get("format", "webp"))
	var buf: PackedByteArray
	if fmt == "png":
		buf = img.save_png_to_buffer()
	else:
		buf = img.save_webp_to_buffer()
	return {"format": fmt, "width": img.get_width(), "height": img.get_height(), "b64": Marshalls.raw_to_base64(buf)}

func _screen_of(node: Node) -> String:
	# Map a visible main-screen editor (auto-named @ClassName@id) back to a set_main_screen_editor name.
	var n := str(node.name)
	if "CanvasItemEditor" in n:
		return "2D"
	if "Node3DEditor" in n:
		return "3D"
	if "EditorAssetLibrary" in n:
		return "AssetLib"
	if "WindowWrapper" in n:
		return "Script" if node.find_child("*ScriptEditor*", true, false) != null else "Game"
	return ""
