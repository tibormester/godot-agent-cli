extends RefCounted
## file module — project file CRUD (res://). Editor-pinned (authoring); default-off in strict preset.
## The host already has native file tools; this exists for in-engine project files.

var s

func register_into(server) -> void:
	s = server
	s.registry.register("file", "file create", _create, {
		"help": "write a project file (creates parent dirs).", "target": "editor",
		"args": [
			{"name": "path", "type": "string", "required": true, "default": "", "help": "res:// or absolute path"},
			{"name": "content", "type": "string", "required": false, "default": "", "help": "file contents"}],
	})
	s.registry.register("file", "file read", _read, {
		"help": "read a project file as text.", "target": "editor",
		"args": [{"name": "path", "type": "string", "required": true, "default": "", "help": "res:// or absolute path"}],
	})
	s.registry.register("file", "file list", _list, {
		"help": "list a directory (files + subdirs).", "target": "editor",
		"args": [
			{"name": "path", "type": "string", "required": false, "default": "res://", "help": "directory"},
			{"name": "--pattern", "type": "string", "required": false, "default": "", "help": "glob filter"}],
	})
	s.registry.register("file", "file delete", _delete, {
		"help": "delete a project file.", "target": "editor",
		"args": [{"name": "path", "type": "string", "required": true, "default": "", "help": "res:// or absolute path"}],
	})

func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _create(p: Dictionary) -> Variant:
	var path := str(p.get("path", ""))
	if path.is_empty():
		return s.err("bad_params", "missing path")
	var content := str(p.get("content", ""))
	var abs := _abs(path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		return s.err("handler_error", "cannot write: " + error_string(FileAccess.get_open_error()))
	f.store_string(content)
	f.close()
	return {"path": path, "size": content.length()}

func _read(p: Dictionary) -> Variant:
	var path := str(p.get("path", ""))
	if path.is_empty():
		return s.err("bad_params", "missing path")
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		return s.err("not_found", "cannot read: " + error_string(FileAccess.get_open_error()))
	var content := f.get_as_text()
	f.close()
	return {"path": path, "content": content}

func _list(p: Dictionary) -> Variant:
	var path := str(p.get("path", "res://"))
	var pattern := str(p.get("pattern", ""))
	var dir := DirAccess.open(_abs(path))
	if dir == null:
		return s.err("not_found", "cannot open dir: " + error_string(DirAccess.get_open_error()))
	var files := []
	var dirs := []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			if dir.current_is_dir():
				dirs.append(name)
			elif pattern.is_empty() or name.match(pattern):
				files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	dirs.sort()
	return {"path": path, "files": files, "directories": dirs}

func _delete(p: Dictionary) -> Variant:
	var path := str(p.get("path", ""))
	if path.is_empty():
		return s.err("bad_params", "missing path")
	var e := DirAccess.remove_absolute(_abs(path))
	if e != OK:
		return s.err("handler_error", "cannot delete: " + error_string(e))
	return {"deleted": path}
