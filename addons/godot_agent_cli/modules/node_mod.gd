extends RefCounted
## node module — generic node CRUD + method calls, all through the codec. Paths relative to the
## scene root; @eN refs accepted anywhere a path is.

var s

func register_into(server) -> void:
	s = server
	var path_arg := {"name": "path", "type": "string", "required": true, "default": "", "help": "node path or @ref"}
	s.registry.register("node", "node get", _node_get, {
		"help": "a node's properties (codec-encoded), script, groups, children.",
		"target": "auto",
		"args": [path_arg,
			{"name": "--grep", "type": "string", "required": false, "default": "", "help": "regex over property names"}],
	})
	s.registry.register("node", "node set", _node_set, {
		"help": "set one property (value decoded via codec / expression), read back.",
		"target": "auto",
		"args": [path_arg,
			{"name": "property", "type": "string", "required": true, "default": "", "help": "property name"},
			{"name": "value", "type": "string", "required": true, "default": "", "help": "value (json tag or expression)"}],
	})
	s.registry.register("node", "node add", _add, {
		"help": "instantiate a class under a parent; owner set to the scene so it persists on save.",
		"target": "auto",
		"args": [
			{"name": "parent", "type": "string", "required": true, "default": "", "help": "parent path or @ref"},
			{"name": "type", "type": "string", "required": true, "default": "", "help": "class name"},
			{"name": "--name", "type": "string", "required": false, "default": "", "help": "node name"},
			{"name": "--props", "type": "json", "required": false, "default": {}, "help": "initial properties"}],
	})
	s.registry.register("node", "node remove", _remove, {
		"help": "remove + free a node.", "target": "auto", "args": [path_arg],
	})
	s.registry.register("node", "node reparent", _reparent, {
		"help": "move a node under a new parent.", "target": "auto",
		"args": [path_arg, {"name": "new_parent", "type": "string", "required": true, "default": "", "help": "new parent path or @ref"}],
	})
	s.registry.register("node", "node call", _call, {
		"help": "call a method with codec-decoded args; returns the encoded result.",
		"target": "auto",
		"args": [path_arg,
			{"name": "method", "type": "string", "required": true, "default": "", "help": "method name"},
			{"name": "--args", "type": "json", "required": false, "default": [], "help": "argument array"}],
	})
	s.registry.register("node", "node attach", _attach, {
		"help": "attach a script resource to a node.", "target": "auto",
		"args": [path_arg, {"name": "script", "type": "string", "required": true, "default": "", "help": "res:// script path"}],
	})
	s.registry.register("node", "node detach", _detach, {
		"help": "remove a node's script.", "target": "auto", "args": [path_arg],
	})

func _node_get(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var props := {}
	for prop in node.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			continue
		if not (usage & PROPERTY_USAGE_STORAGE or usage & PROPERTY_USAGE_EDITOR):
			continue
		props[str(prop["name"])] = s.to_json(node.get(prop["name"]))

	var grep := str(p.get("grep", ""))
	if not grep.is_empty():
		var re := RegEx.new()
		if re.compile(grep) == OK:
			var filtered := {}
			for k in props:
				if re.search(k) != null:
					filtered[k] = props[k]
			props = filtered

	var groups := []
	for g in node.get_groups():
		groups.append(str(g))
	var children := []
	for c in node.get_children():
		children.append(str(c.name))
	var data := {"name": str(node.name), "type": node.get_class(), "path": s.rel_path(node),
		"properties": props, "groups": groups, "children": children}
	var scr = node.get_script()
	if scr != null and scr.resource_path != "":
		data["script"] = scr.resource_path
	return data

func _node_set(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var prop := str(p.get("property", ""))
	if prop.is_empty():
		return s.err("bad_params", "missing property")
	node.set(prop, s.from_json(p.get("value")))
	return {"path": s.rel_path(node), "property": prop, "value": s.to_json(node.get(prop))}

func _add(p: Dictionary) -> Variant:
	var parent = s.resolve_node(str(p.get("parent", "")))
	if parent == null:
		return s.err("not_found", "parent not found: " + str(p.get("parent", "")))
	var type := str(p.get("type", ""))
	if not ClassDB.class_exists(type):
		return s.err("bad_params", "unknown class: " + type)
	if not ClassDB.can_instantiate(type):
		return s.err("bad_params", "cannot instantiate: " + type)
	var node: Node = ClassDB.instantiate(type)
	if str(p.get("name", "")) != "":
		node.name = str(p["name"])
	var props: Dictionary = p.get("props", {})
	for k in props:
		node.set(k, s.from_json(props[k]))
	parent.add_child(node)
	var root = s.target_root()
	if root != null:
		node.owner = root
	return {"path": s.rel_path(node), "type": type, "name": str(node.name)}

func _remove(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var rel = s.rel_path(node)
	var name := str(node.name)
	node.get_parent().remove_child(node)
	node.queue_free()
	return {"removed": rel, "name": name}

func _reparent(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var np = s.resolve_node(str(p.get("new_parent", "")))
	if np == null:
		return s.err("not_found", "new parent not found: " + str(p.get("new_parent", "")))
	node.reparent(np)
	return {"path": s.rel_path(node), "name": str(node.name)}

func _call(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var method := str(p.get("method", ""))
	if not node.has_method(method):
		return s.err("bad_params", "method not found: " + method)
	var args := []
	for a in p.get("args", []):
		args.append(s.from_json(a))
	return s.to_json(node.callv(method, args))

func _attach(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	var sp := str(p.get("script", ""))
	var scr: Variant = load(sp)
	if scr == null:
		return s.err("bad_params", "cannot load script: " + sp)
	node.set_script(scr)
	return {"path": s.rel_path(node), "script": sp}

func _detach(p: Dictionary) -> Variant:
	var node = s.resolve_node(str(p.get("path", "")))
	if node == null:
		return s.err("not_found", "node not found: " + str(p.get("path", "")))
	node.set_script(null)
	return {"path": s.rel_path(node)}
