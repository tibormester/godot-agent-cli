extends RefCounted
## eval module — run GDScript against the live tree; the escape hatch + the macro engine. In scope:
## `root` (scene root), `argv` (tokens after `eval @handle`), and `gdli("verb args")` (invoke any verb,
## raw result). Accepts a single expression (auto-returned), a statement block, or a full file (just
## funcs incl. an entry — `func run():` / `func run(argv):`, or `--entry <name>`; no base to extend).
## Save reusable macros with --save, run them with `@name`.
## Macros live in the gitignored `.gdli/handles/` (ephemeral by design — persistent logic = a plugin).

const Registry := preload("res://addons/godot_agent_cli/core/registry.gd")
const EVAL_BASE := "res://addons/godot_agent_cli/core/eval_base.gd"
const HANDLE_DIR := "res://.gdli/handles"

var s

func register_into(server) -> void:
	s = server
	s.registry.register("eval", "eval", _eval, {
		"help": "run GDScript (expr / block / full file); `root`, `argv`, `gdli(\"…\")` in scope.",
		"target": "auto",
		"args": [
			{"name": "code", "type": "string", "required": false, "default": "", "help": "GDScript, or @handle to run a saved macro"},
			{"name": "args", "type": "string", "required": false, "default": "", "variadic": true, "help": "trailing args for @handle / --file (exposed as argv)"},
			{"name": "--file", "type": "string", "required": false, "default": "", "help": "run GDScript from a file (res:// or project-relative)"},
			{"name": "--save", "type": "string", "required": false, "default": "", "help": "save the code as an ephemeral handle (.gdli/handles/<name>.gd)"},
			{"name": "--entry", "type": "string", "required": false, "default": "run", "help": "entry func for a full-file script (default: run; may take argv)"},
			{"name": "--list", "type": "bool", "required": false, "default": false, "help": "list saved handles"},
		],
	})

func _eval(p: Dictionary) -> Variant:
	if bool(p.get("list", false)):
		return {"handles": _list_handles()}

	var argv := []
	var code: Variant = _resolve_code(p, argv)
	if Registry.is_err(code):
		return code
	if str(code).strip_edges().is_empty():
		return s.err("bad_params", "no code (pass code, --file, or @handle)")

	var save := str(p.get("save", ""))
	if not save.is_empty():
		var werr := _save_handle(save, str(code))
		if werr != OK:
			return s.err("handler_error", "cannot save handle: " + error_string(werr))
		return {"saved": save, "path": "%s/%s.gd" % [HANDLE_DIR, save]}

	return _compile_and_run(str(code), argv, str(p.get("entry", "run")))

# Resolve the source: --file wins, then @handle (filling argv with its trailing tokens), else inline code.
func _resolve_code(p: Dictionary, argv: Array) -> Variant:
	for a in p.get("args", []):  # trailing positionals → argv (e.g. `eval @h a b` or `eval --file x.gd a b`)
		argv.append(str(a))
	var file := str(p.get("file", ""))
	if not file.is_empty():
		return _read_file(file)
	var code := str(p.get("code", ""))
	if code.begins_with("@"):
		var parts := code.split(" ", false)  # also supports the quoted form `eval '@h a b'`
		var name := parts[0].substr(1)
		for i in range(1, parts.size()):
			argv.append(parts[i])
		return _read_file("%s/%s.gd" % [HANDLE_DIR, name])
	return code

func _compile_and_run(code: String, argv: Array, entry: String) -> Variant:
	var script := GDScript.new()
	if _has_top_level_func(code):
		# Full file: the author just writes funcs. If they declared no base, inject the eval context
		# (by path, so it works even on a cold class cache) — `root`/`argv`/`gdli()` come for free.
		script.source_code = code if _has_extends(code) else "extends \"%s\"\n%s" % [EVAL_BASE, code]
	else:
		var lines := code.split("\n")
		if lines.size() == 1:
			script.source_code = "extends \"%s\"\nfunc %s():\n\treturn %s\n" % [EVAL_BASE, entry, code.strip_edges()]
		else:
			var body := ""
			for line in lines:
				body += "\t" + line + "\n"
			script.source_code = "extends \"%s\"\nfunc %s():\n%s" % [EVAL_BASE, entry, body]
	# Compile is implicit — the agent never thinks about the compiler; only a failure is surfaced.
	if script.reload() != OK:
		return s.err("handler_error", "GDScript compile error")
	var obj: Object = script.new()
	if obj is Node:
		s.add_child(obj)
	obj.set("root", s.target_root())
	obj.set("argv", argv)
	obj.set("_srv", s)
	var result: Variant = _call_entry(obj, entry, argv)
	if obj is Node:
		(obj as Node).queue_free()
	if Registry.is_err(result):
		return result
	return s.to_json(result)

# Call the entry func, passing argv only if it declares a parameter (so `run()` and `run(argv)` both work).
func _call_entry(obj: Object, entry: String, argv: Array) -> Variant:
	for m in obj.get_method_list():
		if str(m["name"]) == entry:
			if (m.get("args", []) as Array).is_empty():
				return obj.call(entry)
			return obj.call(entry, argv)
	return s.err("handler_error", "eval: no entry func `%s()` (name it `run` or pass --entry)" % entry)

func _has_top_level_func(code: String) -> bool:
	for line in code.split("\n"):
		if line.begins_with("func "):
			return true
	return false

# Does the script declare its own base? (first significant line is `extends ...`)
func _has_extends(code: String) -> bool:
	for line in code.split("\n"):
		var t := line.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		return t.begins_with("extends")
	return false

func _read_file(path: String) -> Variant:
	var fp := path
	if not (fp.begins_with("res://") or fp.begins_with("user://") or fp.is_absolute_path()):
		fp = "res://" + fp
	if not FileAccess.file_exists(fp):
		return s.err("not_found", "no such file: " + fp)
	return FileAccess.get_file_as_string(fp)

func _save_handle(name: String, code: String) -> int:
	var d := DirAccess.open("res://")
	if d != null and not d.dir_exists(".gdli/handles"):
		d.make_dir_recursive(".gdli/handles")
	var f := FileAccess.open("%s/%s.gd" % [HANDLE_DIR, name], FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(code)
	f.close()
	return OK

func _list_handles() -> Array:
	var out := []
	var d := DirAccess.open(HANDLE_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".gd"):
			out.append(n.trim_suffix(".gd"))
		n = d.get_next()
	d.list_dir_end()
	return out
