extends RefCounted
## Reads/writes res://addons/godot_agent_cli/config.json — a denylist {"disabled":[modules]}.
## Everything (built-ins + discovered plugins) is on by default; list modules here to turn them off.
## Missing/invalid -> nothing disabled. The server re-reads this on change (mtime-watched), so editing
## it by the CLI, in the editor, or by hand all take effect live.

const PATH := "res://addons/godot_agent_cli/config.json"

static func load_config() -> Dictionary:
	var fallback := {"disabled": []}
	if not FileAccess.file_exists(PATH):
		return fallback
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return fallback
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary):
		return fallback
	if not (data.get("disabled") is Array):
		data["disabled"] = []
	return data

static func save_config(disabled: Array) -> int:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"disabled": disabled}, "\t"))
	f.close()
	return OK
