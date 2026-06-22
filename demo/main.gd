extends Node2D

var ticks := 0
var interacts := 0
var clicks := 0
var last_key := ""

func _ready() -> void:
	$Button.pressed.connect(func(): clicks += 1)

func _process(_delta: float) -> void:
	ticks += 1
	$Mover.position.x = 100.0 + sin(ticks * 0.05) * 50.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interacts += 1
	if event is InputEventKey and event.pressed and not event.echo:
		last_key = OS.get_keycode_string(event.keycode)

func ping_back(n: int) -> int:
	return n * 2
