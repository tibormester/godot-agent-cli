extends RefCounted
## introspect module — ClassDB queries (identical in editor and game).

var s

func register_into(server) -> void:
	s = server
	s.registry.register("introspect", "class list", _list, {
		"help": "instantiable classes, optionally filtered by substring / base class.",
		"target": "auto",
		"args": [
			{"name": "filter", "type": "string", "required": false, "default": "", "help": "name substring"},
			{"name": "--base", "type": "string", "required": false, "default": "", "help": "must derive from"},
		],
	})
	s.registry.register("introspect", "class info", _info, {
		"help": "a class's parent, properties, methods, signals.",
		"target": "auto",
		"args": [{"name": "class", "type": "string", "required": true, "default": "", "help": "class name"}],
	})

func _list(p: Dictionary) -> Variant:
	var filter := str(p.get("filter", "")).to_lower()
	var base := str(p.get("base", ""))
	var out := []
	for cls in ClassDB.get_class_list():
		if not ClassDB.can_instantiate(cls):
			continue
		if not base.is_empty() and not ClassDB.is_parent_class(cls, base):
			continue
		if not filter.is_empty() and not str(cls).to_lower().contains(filter):
			continue
		out.append(str(cls))
	out.sort()
	return out

func _info(p: Dictionary) -> Variant:
	var cls := str(p.get("class", ""))
	if not ClassDB.class_exists(cls):
		return s.err("bad_params", "unknown class: " + cls)
	var props := []
	for prop in ClassDB.class_get_property_list(cls):
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_CATEGORY or usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			continue
		if not (usage & PROPERTY_USAGE_STORAGE or usage & PROPERTY_USAGE_EDITOR):
			continue
		props.append({"name": prop["name"], "type": type_string(prop["type"])})
	var methods := []
	for m in ClassDB.class_get_method_list(cls):
		var margs := []
		for arg in m.get("args", []):
			margs.append({"name": arg["name"], "type": type_string(arg["type"])})
		methods.append({"name": m["name"], "args": margs})
	var sigs := []
	for sig in ClassDB.class_get_signal_list(cls):
		sigs.append(str(sig["name"]))
	return {
		"class": cls,
		"parent": str(ClassDB.get_parent_class(cls)),
		"can_instantiate": ClassDB.can_instantiate(cls),
		"properties": props,
		"methods": methods,
		"signals": sigs,
	}
