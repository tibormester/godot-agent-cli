extends RefCounted
## The command registry: maps a CLI verb path ("scene load", "node add", "inspect") to a
## handler + meta. Built-ins register at boot; a plugin calls register() the same way, so its
## verbs appear in `verbs` and route with zero client changes. `name` is BOTH the wire `cmd`
## and the CLI path; `module` governs enable/disable + help grouping.

const ERR_KEY := "__err"

var _verbs := {}     # name -> {module, name, handler:Callable, meta:Dictionary}
var _disabled := {}  # module -> true  (denylist: everything registered is on by default)

static func err(code: String, message: String) -> Dictionary:
	return {ERR_KEY: true, "code": code, "message": message}

static func is_err(v: Variant) -> bool:
	return v is Dictionary and v.get(ERR_KEY, false) == true

func set_disabled(modules: Array) -> void:
	_disabled.clear()
	for m in modules:
		if str(m) != "core":  # core is never disablable (verbs/config/mark/check live here)
			_disabled[str(m)] = true

func module_enabled(module: String) -> bool:
	return not _disabled.has(module)

func disabled_list() -> Array:
	return _disabled.keys()

func all_modules() -> Array:
	var seen := {}
	for name in _verbs:
		seen[_verbs[name]["module"]] = true
	return seen.keys()

func register(module: String, name: String, handler: Callable, meta: Dictionary) -> void:
	_verbs[name] = {"module": module, "name": name, "handler": handler, "meta": meta}

func has(name: String) -> bool:
	return _verbs.has(name)

func entry(name: String) -> Dictionary:
	return _verbs.get(name, {})

func list_meta() -> Array:
	var out := []
	for name in _verbs:
		var e: Dictionary = _verbs[name]
		if not module_enabled(e["module"]):  # disabled modules vanish from the surface
			continue
		var m: Dictionary = e["meta"]
		out.append({
			"module": e["module"],
			"name": name,
			"target": m.get("target", "auto"),
			"help": m.get("help", ""),
			"args": m.get("args", []),
			"async": m.get("async", false),
			"enabled": module_enabled(e["module"]),
		})
	out.sort_custom(func(x, y): return x["name"] < y["name"])
	return out
