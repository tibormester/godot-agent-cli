extends RefCounted

const DemoConfig = preload("res://addons/gdli_plugin_example/demo/demo_config.gd")

var owner: Node
var terminal

var active := false
var pending_loop_start := false
var loop_once := false
var waiting_for_loop_end := false
var elapsed := 0.0
var frame_elapsed := 0.0
var frame_count := 0
var seconds := 45.0
var fps := 8
var width := 640
var output_path := "res://addons/gdli_plugin_example/docs/assets/demo-autoplay.webm"
var ffmpeg_path := "ffmpeg"
var frame_dir_abs := ""

func _init(scene_owner: Node) -> void:
	owner = scene_owner

func bind(terminal_controller) -> void:
	terminal = terminal_controller

func start(options: Dictionary) -> Dictionary:
	seconds = max(1.0, float(options.get("record-seconds", seconds)))
	fps = clampi(int(options.get("record-fps", fps)), 1, 30)
	width = clampi(int(options.get("record-width", width)), 240, 1280)
	output_path = str(options.get("record-out", output_path))
	ffmpeg_path = str(options.get("ffmpeg", ffmpeg_path))
	loop_once = bool(options.get("record-loop", false))
	waiting_for_loop_end = false
	frame_count = 0
	elapsed = 0.0
	frame_elapsed = 1.0 / float(fps)
	frame_dir_abs = ProjectSettings.globalize_path(DemoConfig.RECORDING_FRAME_DIR)
	_prepare_recording_frame_dir()
	pending_loop_start = loop_once
	active = not loop_once
	return {
		"active": active,
		"pending_loop_start": pending_loop_start,
		"loop": loop_once,
		"fps": fps,
		"width": width,
		"seconds": seconds,
		"frames": frame_dir_abs,
		"out": ProjectSettings.globalize_path(output_path),
	}

func update(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	frame_elapsed += delta
	var interval := 1.0 / float(fps)
	if frame_elapsed >= interval:
		frame_elapsed = 0.0
		capture_frame()
	if elapsed >= seconds:
		active = false
		pending_loop_start = false
		waiting_for_loop_end = false
		finish()

func begin_loop_recording() -> void:
	pending_loop_start = false
	active = true
	elapsed = 0.0
	frame_elapsed = 0.0
	capture_frame()

func finish_loop_recording() -> void:
	waiting_for_loop_end = false
	active = false
	finish()

func capture_frame() -> void:
	var img := owner.get_viewport().get_texture().get_image()
	if img == null:
		return
	var target_height: int = maxi(1, int(round(float(width) * float(img.get_height()) / float(img.get_width()))))
	img.resize(width, target_height, Image.INTERPOLATE_LANCZOS)
	var frame_path := frame_dir_abs.path_join("frame_%04d.png" % frame_count)
	var err := img.save_png(frame_path)
	if err == OK:
		frame_count += 1

func finish() -> void:
	var out_abs := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())
	if frame_count <= 0:
		terminal.append_terminal("recording failed: no frames captured")
		return
	var args := PackedStringArray([
		"-y",
		"-framerate", str(fps),
		"-i", frame_dir_abs.path_join("frame_%04d.png"),
		"-c:v", "libvpx-vp9",
		"-b:v", "0",
		"-crf", "42",
		"-pix_fmt", "yuv420p",
		out_abs,
	])
	var output: Array = []
	var exit_code := OS.execute(ffmpeg_path, args, output, true)
	if exit_code == 0:
		terminal.append_terminal("recording saved: %s (%d frames at %d fps)" % [out_abs, frame_count, fps])
	else:
		terminal.append_terminal("recording frames saved: %s\nffmpeg failed with exit code %d" % [frame_dir_abs, exit_code])

func _prepare_recording_frame_dir() -> void:
	DirAccess.make_dir_recursive_absolute(frame_dir_abs)
	var dir := DirAccess.open(frame_dir_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".png") or name.ends_with(".webm")):
			DirAccess.remove_absolute(frame_dir_abs.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
