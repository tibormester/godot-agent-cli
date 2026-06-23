extends Node
class_name GdliServer
## The shared core, hosted twice: as the game autoload and, via plugin.gd, inside the editor — each on
## its own ephemeral port, recorded in .gdli/<game|editor>.port (clients discover it from there). One
## TCP conn per command; {id,cmd,params} -> {id,ok,data}|{id,ok:false,err}.
## Modules build on the helpers at the bottom (resolve_node / target_root / codec / diff / refs).

const Registry := preload("res://addons/godot_agent_cli/core/registry.gd")
const Config := preload("res://addons/godot_agent_cli/core/config.gd")
const Codec := preload("res://addons/godot_agent_cli/core/codec.gd")
const Diff := preload("res://addons/godot_agent_cli/core/diff.gd")

const MODULES := {
	"core": "res://addons/godot_agent_cli/modules/core_mod.gd",
	"scene": "res://addons/godot_agent_cli/modules/scene_mod.gd",
	"node": "res://addons/godot_agent_cli/modules/node_mod.gd",
	"observe": "res://addons/godot_agent_cli/modules/observe_mod.gd",
	"input": "res://addons/godot_agent_cli/modules/input_mod.gd",
	"introspect": "res://addons/godot_agent_cli/modules/introspect_mod.gd",
	"eval": "res://addons/godot_agent_cli/modules/eval_mod.gd",
	"file": "res://addons/godot_agent_cli/modules/file_mod.gd",
}

var self_drive := true

var registry := Registry.new()
var diff := Diff.new()

const CONFIG_PATH := "res://addons/godot_agent_cli/config.json"
const DIFF_DEPTH := 1000      # whole-scene snapshot depth for --diff / --mark

var _server: TCPServer = null
var _clients: Array = []
var _modules: Array = []      # keep module instances alive (handlers are bound to them)
var _refs := {}               # "@eN" -> live Node (path-independent; survives reparent/rename)
var _ref_by_id := {}          # node instance_id -> "@eN" (reuse the same ref for the same node)
var _ref_seq := 0             # monotonic ref counter (stable across calls, never reset)
var _marks := {}              # mark name -> snapshot (named diff checkpoints)
var _global_ignores: Array = [] # process-local diff ignore globs; changed via ignore add/remove/clear
var _config_mtime := 0
var _bound_port := 0          # actual port we ended up listening on

# --- Lifecycle ---

func _ready() -> void:
	# Built-ins + discovered plugins ALL register; the denylist config gates dispatch/list, so a
	# disabled module can be toggled back on live without a restart.
	for name in MODULES:
		var mod: RefCounted = load(MODULES[name]).new()
		mod.register_into(self)
		_modules.append(mod)
	_discover_plugins()
	reload_config()

	_server = TCPServer.new()
	var e := _server.listen(_configured_port())
	if e != OK:
		push_error("GodotAgentCli: listen failed: %s" % error_string(e))
		_server = null
		return
	_bound_port = _server.get_local_port()
	_write_port_file(_bound_port)
	print("GodotAgentCli: listening on %d (%s)" % [_bound_port, "editor" if is_editor() else "game"])

func _exit_tree() -> void:
	if _server != null:
		_server.stop()
		_server = null
	_clients.clear()
	var d := DirAccess.open("res://.gdli")
	if d != null:
		d.remove("%s.port" % ("editor" if is_editor() else "game"))

func _process(_delta: float) -> void:
	if self_drive:
		poll()

func _configured_port() -> int:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--godot-cli-port="):
			return int(arg.split("=")[1])
	return 0    # 0 -> OS assigns a free ephemeral port (multi-worktree safe)

func _port() -> int:
	return _bound_port

func reload_config() -> void:
	registry.set_disabled(Config.load_config()["disabled"])
	_config_mtime = FileAccess.get_modified_time(CONFIG_PATH)

func _maybe_reload_config() -> void:
	if FileAccess.get_modified_time(CONFIG_PATH) != _config_mtime:
		reload_config()

func _write_port_file(port: int) -> void:
	var mode := "editor" if is_editor() else "game"
	var d := DirAccess.open("res://")
	if d != null and not d.dir_exists(".gdli"):
		d.make_dir(".gdli")
	var f := FileAccess.open("res://.gdli/%s.port" % mode, FileAccess.WRITE)
	if f != null:
		f.store_string(str(port))
		f.close()

func _discover_plugins() -> void:
	# Convention: any other addon dropping a `gdli_module.gd` (with register_into(server)) is
	# auto-loaded — its verbs join `verbs` and route by their meta.target with zero client changes.
	var dir := DirAccess.open("res://addons")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and name != "godot_agent_cli":
			var path := "res://addons/%s/gdli_module.gd" % name
			if FileAccess.file_exists(path):
				var mod: RefCounted = load(path).new()
				mod.register_into(self)
				_modules.append(mod)
				print("GodotAgentCli: loaded plugin '%s'" % name)
		name = dir.get_next()
	dir.list_dir_end()

# --- TCP poll / protocol ---

func poll() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buffer": ""})
	var drop: Array = []
	for i in _clients.size():
		var c: Dictionary = _clients[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		match peer.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				var n := peer.get_available_bytes()
				if n > 0:
					var got := peer.get_data(n)
					if got[0] == OK:
						c["buffer"] += (got[1] as PackedByteArray).get_string_from_utf8()
						_drain(c)
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				drop.append(i)
	for i in range(drop.size() - 1, -1, -1):
		_clients.remove_at(drop[i])

func _drain(c: Dictionary) -> void:
	while true:
		var buf: String = c["buffer"]
		var idx := buf.find("\n")
		if idx == -1:
			break
		var line := buf.substr(0, idx)
		c["buffer"] = buf.substr(idx + 1)
		if not line.strip_edges().is_empty():
			_handle(c, line)

func _handle(c: Dictionary, line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if not (parsed is Dictionary):
		_send(c, {"id": "", "ok": false, "err": {"code": "bad_params", "message": "Invalid JSON"}})
		return
	var id := str(parsed.get("id", ""))
	var cmd := str(parsed.get("cmd", ""))
	var params: Dictionary = parsed.get("params", {})
	await _dispatch(c, id, cmd, params)

func _dispatch(c: Dictionary, id: String, cmd: String, params: Dictionary) -> void:
	_maybe_reload_config()
	if cmd == "__gdli_run":
		var tokens: Variant = params.get("tokens", [])
		if not (tokens is Array):
			_reply_err(c, id, "bad_params", "__gdli_run expects tokens:Array")
			return
		await _dispatch_tokens(c, id, tokens)
		return
	# Reserved control commands (not registry verbs, so they never show in `verbs`): editor run control
	# that the client sends for `launch --in-editor` / `kill --in-editor`.
	if cmd == "play" or cmd == "stop":
		var ctl := _editor_control(cmd)
		if Registry.is_err(ctl):
			_reply_err(c, id, str(ctl.get("code", "handler_error")), str(ctl.get("message", "")))
		else:
			_send(c, {"id": id, "ok": true, "data": ctl})
		return
	var e := registry.entry(cmd)
	if e.is_empty():
		_reply_err(c, id, "not_found", "Unknown verb: " + cmd)
		return
	if not registry.module_enabled(e["module"]):
		_reply_err(c, id, "disabled", "Module disabled: " + e["module"])
		return
	var handler: Callable = e["handler"]
	var meta: Dictionary = e["meta"]

	# --diff / --mark are cross-cutting and handled HERE, so every verb (and plugin) gets them for
	# free and never sees them. Bare --diff = whole-scene before/after this command; --diff <mark> =
	# current vs a named checkpoint; --mark <name> stores the post-command state.
	var want_diff := params.has("diff")
	var mark_name := str(params.get("mark", ""))
	var diff_mark := ""
	var ignores := _ignore_list(params)
	var before := {}
	if want_diff:
		var dv: Variant = params["diff"]
		if dv is String and not (dv as String).is_empty() and _marks.has(dv):
			diff_mark = dv
		else:
			before = _scene_snapshot(ignores)

	var result: Variant
	if meta.get("async", false):
		result = await handler.call(params)
	else:
		result = handler.call(params)
	if Registry.is_err(result):
		_reply_err(c, id, str(result.get("code", "handler_error")), str(result.get("message", "")))
		return

	var response := {"id": id, "ok": true, "data": result}
	if want_diff or not mark_name.is_empty():
		await _settle(params)
		var after := _scene_snapshot(ignores)
		if want_diff:
			var base: Dictionary = _marks.get(diff_mark, {}) if not diff_mark.is_empty() else before
			response["diff"] = diff.filter_delta(diff.compare(base, after), ignores)
		if not mark_name.is_empty():
			_marks[mark_name] = after
			response["marked"] = mark_name
	_send(c, response)

func _reply_err(c: Dictionary, id: String, code: String, message: String) -> void:
	_send(c, {"id": id, "ok": false, "err": {"code": code, "message": message}})

func _send(c: Dictionary, response: Dictionary) -> void:
	var peer: StreamPeerTCP = c["peer"]
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())

func _dispatch_tokens(c: Dictionary, id: String, tokens: Array) -> void:
	var matched: Variant = _verb_from_tokens(tokens)
	if Registry.is_err(matched):
		_reply_err(c, id, str(matched.get("code", "bad_params")), str(matched.get("message", "")))
		return
	var e: Dictionary = registry.entry(str(matched["name"]))
	var meta: Dictionary = e["meta"]
	var params: Variant = _params_from_tokens(meta.get("args", []), matched["rest"])
	if Registry.is_err(params):
		_reply_err(c, id, str(params.get("code", "bad_params")), str(params.get("message", "")))
		return
	await _dispatch(c, id, str(matched["name"]), params)

# --- Helpers for modules ---

func err(code: String, message: String) -> Dictionary:
	return Registry.err(code, message)

func is_err(v: Variant) -> bool:
	return Registry.is_err(v)

func is_editor() -> bool:
	return Engine.is_editor_hint()

func editor_interface() -> Object:
	if Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	return null

func _editor_control(cmd: String) -> Dictionary:
	# play/stop the game from the editor (EditorInterface lives only here).
	if not is_editor():
		return err("editor_only", cmd + " runs on the editor instance")
	var ei := editor_interface()
	if ei == null:
		return err("editor_only", "EditorInterface unavailable")
	if cmd == "play":
		if ei.get_edited_scene_root() != null:
			ei.play_current_scene()
		else:
			ei.play_main_scene()
		return {"started": true}
	ei.stop_playing_scene()
	return {"stopped": true}

func target_root() -> Node:
	if is_editor():
		var ei := editor_interface()
		return ei.get_edited_scene_root() if ei != null else null
	return get_tree().current_scene

func to_json(v: Variant) -> Variant:
	return Codec.to_json(v)

func from_json(v: Variant) -> Variant:
	return Codec.from_json(v)

func rel_path(node: Node) -> String:
	var root := target_root()
	if root == null or node == null:
		return ""
	return "." if node == root else str(root.get_path_to(node))

func resolve_node(path_or_ref: String) -> Node:
	# @refs point at the live Node object (not a path), so they survive reparent/rename and stay valid
	# until the node is freed; a stale/unknown ref returns null (callers surface an error).
	if path_or_ref.begins_with("@"):
		var n: Variant = _refs.get(path_or_ref)
		if n != null and is_instance_valid(n):
			return n
		_refs.erase(path_or_ref)
		return null
	var root := target_root()
	if root == null:
		return null
	if path_or_ref.is_empty() or path_or_ref == ".":
		return root
	return root.get_node_or_null(NodePath(path_or_ref))

func mint_refs(nodes: Array) -> Array:
	var labels := []
	for n in nodes:
		labels.append(_ref_for(n))
	return labels

# Stable @eN per node for the process lifetime: the same live node always gets the same ref (keyed by
# instance id), so refs don't churn between inspects and survive path changes. New nodes get fresh ids.
func _ref_for(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	var id := n.get_instance_id()
	if _ref_by_id.has(id):
		var existing: String = _ref_by_id[id]
		if _refs.has(existing) and is_instance_valid(_refs[existing]):
			return existing
	_ref_seq += 1
	var ref := "@e%d" % _ref_seq
	_refs[ref] = n
	_ref_by_id[id] = ref
	return ref

func mark_names() -> Array:
	return _marks.keys()

func ignore_list() -> Array:
	return _global_ignores.duplicate()

func ignore_add(pattern: String) -> Dictionary:
	var p := pattern.strip_edges()
	if p.is_empty():
		return err("bad_params", "ignore pattern cannot be empty")
	if not _global_ignores.has(p):
		_global_ignores.append(p)
	return {"ignores": ignore_list()}

func ignore_remove(pattern: String) -> Dictionary:
	var p := pattern.strip_edges()
	if p.is_empty():
		return err("bad_params", "ignore pattern cannot be empty")
	_global_ignores.erase(p)
	return {"ignores": ignore_list()}

func ignore_clear() -> Dictionary:
	_global_ignores.clear()
	return {"ignores": []}

func _settle(params: Dictionary) -> void:
	# Variable post-command delay before the --diff/--mark "after" snapshot. One of (mutually
	# exclusive, precedence time > physics > ticks); default = 0 idle frames (snapshot immediately).
	if params.has("time"):
		await get_tree().create_timer(float(params["time"])).timeout
	elif params.has("physics"):
		for _i in int(params["physics"]):
			await get_tree().physics_frame
	else:
		for _i in int(params.get("ticks", 0)):
			await get_tree().process_frame

func screen_pos(node_or_ref: String) -> Variant:
	# Resolve a node path / @ref to a screen position (Control center, else Node2D origin). null if N/A.
	var n := resolve_node(node_or_ref)
	if n is Control:
		var r: Rect2 = (n as Control).get_global_rect()
		return r.position + r.size * 0.5
	if n is Node2D:
		return (n as Node2D).global_position
	return null

func _scene_snapshot(ignores: Array = []) -> Dictionary:
	return diff.snapshot(target_root(), DIFF_DEPTH, false, ignores)

func _ignore_list(params: Dictionary) -> Array:
	var out := _global_ignores.duplicate()
	for tok in str(params.get("ignore", "")).split(",", false):
		var t := tok.strip_edges()
		if not t.is_empty() and not out.has(t):
			out.append(t)
	return out

# --- gdli() bridge: run a registered verb by its CLI string, in-process, returning the raw result. ---
# Used by eval scripts (via GdliEval.gdli) and available to plugins. This is the same token/arg parser
# the CLI reaches through __gdli_run, so CLI strings mean the same thing in code and at the terminal.
func call_gdli_string(cmd: String) -> Variant:
	var toks := _tokenize(cmd)
	var matched: Variant = _verb_from_tokens(toks)
	if Registry.is_err(matched):
		return matched
	var name := str(matched["name"])
	var e := registry.entry(name)
	if not registry.module_enabled(str(e["module"])):
		return err("disabled", "module disabled: " + str(e["module"]))
	var meta: Dictionary = e["meta"]
	if meta.get("async", false):
		return err("bad_params", "gdli() cannot call async verb: " + name)
	var params: Variant = _params_from_tokens(meta.get("args", []), matched["rest"])
	if Registry.is_err(params):
		return params
	return _call_sync_with_core(e, params)

func call_gdli_string_async(cmd: String) -> Variant:
	var toks := _tokenize(cmd)
	var matched: Variant = _verb_from_tokens(toks)
	if Registry.is_err(matched):
		return matched
	var name := str(matched["name"])
	var e := registry.entry(name)
	if not registry.module_enabled(str(e["module"])):
		return err("disabled", "module disabled: " + str(e["module"]))
	var params: Variant = _params_from_tokens(e["meta"].get("args", []), matched["rest"])
	if Registry.is_err(params):
		return params
	return await _call_with_core(e, params)

func _verb_from_tokens(tokens: Array) -> Variant:
	if tokens.is_empty():
		return err("bad_params", "empty gdli command")
	for n in range(tokens.size(), 0, -1):
		var cand := ""
		for k in n:
			cand += str(tokens[k]) + " "
		cand = cand.strip_edges()
		if registry.has(cand):
			return {"name": cand, "rest": tokens.slice(n)}
	var rendered := ""
	for tok in tokens:
		rendered += str(tok) + " "
	return err("not_found", "unknown verb: " + rendered.strip_edges())

func _call_sync_with_core(entry: Dictionary, params: Dictionary) -> Variant:
	var want_diff := params.has("diff")
	var mark_name := str(params.get("mark", ""))
	var diff_mark := ""
	var ignores := _ignore_list(params)
	var before := {}
	if want_diff:
		var dv: Variant = params["diff"]
		if dv is String and not (dv as String).is_empty() and _marks.has(dv):
			diff_mark = dv
		else:
			before = _scene_snapshot(ignores)
	var result: Variant = (entry["handler"] as Callable).call(params)
	if Registry.is_err(result):
		return result
	if not want_diff and mark_name.is_empty():
		return result
	var after := _scene_snapshot(ignores)
	var response := {"data": result}
	if want_diff:
		var base: Dictionary = _marks.get(diff_mark, {}) if not diff_mark.is_empty() else before
		response["diff"] = diff.filter_delta(diff.compare(base, after), ignores)
	if not mark_name.is_empty():
		_marks[mark_name] = after
		response["marked"] = mark_name
	return response

func _call_with_core(entry: Dictionary, params: Dictionary) -> Variant:
	var meta: Dictionary = entry["meta"]
	var want_diff := params.has("diff")
	var mark_name := str(params.get("mark", ""))
	var diff_mark := ""
	var ignores := _ignore_list(params)
	var before := {}
	if want_diff:
		var dv: Variant = params["diff"]
		if dv is String and not (dv as String).is_empty() and _marks.has(dv):
			diff_mark = dv
		else:
			before = _scene_snapshot(ignores)
	var result: Variant
	if meta.get("async", false):
		result = await (entry["handler"] as Callable).call(params)
	else:
		result = (entry["handler"] as Callable).call(params)
	if Registry.is_err(result):
		return result
	if not want_diff and mark_name.is_empty():
		return result
	await _settle(params)
	var after := _scene_snapshot(ignores)
	var response := {"data": result}
	if want_diff:
		var base: Dictionary = _marks.get(diff_mark, {}) if not diff_mark.is_empty() else before
		response["diff"] = diff.filter_delta(diff.compare(base, after), ignores)
	if not mark_name.is_empty():
		_marks[mark_name] = after
		response["marked"] = mark_name
	return response

func _tokenize(text: String) -> Array:
	var toks := []
	var cur := ""
	var quote := ""
	for i in text.length():
		var ch := text[i]
		if quote != "":
			if ch == quote:
				quote = ""
			else:
				cur += ch
		elif ch == '"' or ch == "'":
			quote = ch
		elif ch == " " or ch == "\t":
			if cur != "":
				toks.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		toks.append(cur)
	return toks

# Build a params dict from a verb's arg specs + the remaining tokens.
func _params_from_tokens(specs: Array, tokens: Array) -> Variant:
	var extracted: Variant = _extract_core_tokens(tokens)
	if Registry.is_err(extracted):
		return extracted
	var params: Dictionary = extracted["core"]
	tokens = extracted["rest"]
	var flag_specs := {}
	var pos_specs := []
	for a in specs:
		if str(a["name"]).begins_with("-"):
			flag_specs[str(a["name"])] = a
		else:
			pos_specs.append(a)
	var positionals := []
	var i := 0
	while i < tokens.size():
		var tok := str(tokens[i])
		if tok.begins_with("-") and flag_specs.has(tok):
			var spec: Dictionary = flag_specs[tok]
			var key := tok.lstrip("-")
			if str(spec.get("type", "string")) == "bool":
				params[key] = true
			else:
				i += 1
				if i >= tokens.size():
					return err("bad_params", "flag %s expects a value" % tok)
				params[key] = _coerce(str(spec.get("type", "string")), str(tokens[i]))
		elif tok.begins_with("-") and tok.length() > 1 and not tok.is_valid_float():
			return err("bad_params", "unknown flag: " + tok)
		else:
			positionals.append(tok)
		i += 1
	var consumed := 0
	for j in pos_specs.size():
		var spec: Dictionary = pos_specs[j]
		var key := str(spec["name"]).lstrip("-")
		if bool(spec.get("variadic", false)):
			var rest := []
			for k in range(j, positionals.size()):
				rest.append(_coerce(str(spec.get("type", "string")), str(positionals[k])))
			params[key] = rest
			consumed = positionals.size()
			break
		if j < positionals.size():
			params[key] = _coerce(str(spec.get("type", "string")), str(positionals[j]))
			consumed = j + 1
	if consumed < positionals.size():
		var extra := ""
		for k in range(consumed, positionals.size()):
			extra += str(positionals[k]) + " "
		return err("bad_params", "unexpected argument: " + extra.strip_edges())
	for a in specs:
		var key := str(a["name"]).lstrip("-")
		if not params.has(key) and str(a.get("type", "string")) != "bool":
			var dv: Variant = a.get("default", null)
			if dv != null and str(dv) != "":
				params[key] = dv
	for a in specs:
		if bool(a.get("required", false)):
			var key := str(a["name"]).lstrip("-")
			if not params.has(key):
				return err("bad_params", "missing required arg: " + str(a["name"]))
	return params

func _extract_core_tokens(tokens: Array) -> Variant:
	var params := {}
	var rest := []
	var i := 0
	while i < tokens.size():
		var tok := str(tokens[i])
		if tok == "--diff":
			var next: Variant = null
			if i + 1 < tokens.size():
				next = tokens[i + 1]
			if next == null or str(next).begins_with("-"):
				params["diff"] = true
			elif _marks.has(str(next)):
				params["diff"] = str(next)
				i += 1
			else:
				params["diff"] = true
		elif tok == "--mark":
			i += 1
			if i >= tokens.size():
				return err("bad_params", "flag --mark expects a value")
			params["mark"] = str(tokens[i])
		elif tok == "--ticks":
			i += 1
			if i >= tokens.size():
				return err("bad_params", "flag --ticks expects a value")
			params["ticks"] = int(str(tokens[i]))
		elif tok == "--physics":
			i += 1
			if i >= tokens.size():
				return err("bad_params", "flag --physics expects a value")
			params["physics"] = int(str(tokens[i]))
		elif tok == "--time":
			i += 1
			if i >= tokens.size():
				return err("bad_params", "flag --time expects a value")
			params["time"] = float(str(tokens[i]))
		elif tok == "--ignore":
			i += 1
			if i >= tokens.size():
				return err("bad_params", "flag --ignore expects a value")
			params["ignore"] = str(tokens[i])
		elif tok == "--data":
			params["data"] = true
		else:
			rest.append(tok)
		i += 1
	return {"core": params, "rest": rest}

func _coerce(t: String, v: String) -> Variant:
	match t:
		"int": return v.to_int()
		"float": return v.to_float()
		"bool": return true
		"json": return JSON.parse_string(v)
		_: return v

func module_names() -> Array:
	return MODULES.keys()
