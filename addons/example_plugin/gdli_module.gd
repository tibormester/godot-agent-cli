extends RefCounted
## Example gdli plugin. Drop an addon folder containing a `gdli_module.gd` that exposes
## register_into(server); the harness auto-discovers it at boot, its verbs show up in `list`,
## and they route by their meta.target with zero client changes. Toggle it like any module
## (`gdli config --disable example`). Delete this folder to remove the example.
##
## `server` is the live GdliServer — plugins call its helpers dynamically (no type import needed):
##   server.to_json(v) / from_json(v) · resolve_node(path|@ref) · target_root() · is_editor()
##   diff.snapshot(root,depth) · mint_refs(nodes) · err(code,msg)

var server

func register_into(srv) -> void:
	server = srv
	server.registry.register("example", "example greet", _greet, {
		"help": "demo plugin verb — greet by name (proves auto-discovery + routing).",
		"target": "auto",
		"args": [{"name": "name", "type": "string", "required": false, "default": "world", "help": "who to greet"}],
	})

func _greet(p: Dictionary) -> Variant:
	return {"greeting": "hello, %s" % str(p.get("name", "world"))}
