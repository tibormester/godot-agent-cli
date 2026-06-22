extends RefCounted
## Shared compile-check: re-parse every .gd under a root and return the ones that fail to compile.
## Used by both the `check` server verb (live instance) and tools/check.gd (headless --script fallback),
## so the two hybrid paths share one definition of "compiles".

static func failing_scripts(root := "res://") -> Array:
	var out := []
	for f in _gd_files(root):
		if not _compiles(f):
			out.append(f)
	return out

# Compile a file from disk in isolation and report whether it parsed/analyzed clean. We compile a
# standalone GDScript (not ResourceLoader.load — that returns a non-null *invalid* object for parse
# errors) and read reload()'s error code. `class_name` declarations are blanked first (line numbers
# preserved) so reload() never re-registers an already-registered global class, which segfaults.
static func _compiles(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		if (lines[i] as String).strip_edges().begins_with("class_name"):
			lines[i] = ""
	var gd := GDScript.new()
	gd.source_code = "\n".join(lines)
	return gd.reload() == OK

static func _gd_files(dir_path: String) -> Array:
	var out := []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("."):   # skip .godot / .gdli / other dot-dirs
				out.append_array(_gd_files(dir_path.path_join(name)))
		elif name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out
