extends RefCounted

const ARENA_CENTER := Vector2(640, 250)
const ARENA_RADIUS := 220.0
const PLAYER_SPEED := 230.0
const SWORD_RANGE := 92.0
const SWORD_ARC_DEGREES := 58.0
const ENEMY_HP := 2
const MAX_STACK := 5
const GEM_DROP_CHANCE := 0.18

const TERMINAL_HINT := "type gdli --help for info"
const TERMINAL_INPUT_MIN_HEIGHT := 42.0
const TERMINAL_INPUT_LINE_HEIGHT := 22.0
const TERMINAL_INPUT_PADDING := 18.0
const TERMINAL_INPUT_MAX_LINES := 4
const TERMINAL_INPUT_ROW_BOTTOM := 390.0
const TERMINAL_INPUT_OUTPUT_GAP := 14.0
const TERMINAL_SCROLL_LINES := 4
const TERMINAL_IDLE_COLLAPSE_MSEC := 3500
const TERMINAL_OUTPUT_TOP_EXPANDED := 18.0
const TERMINAL_OUTPUT_LINE_HEIGHT := 26.0
const TERMINAL_SHADE_PADDING := 10.0

const ACTION_MOVE_UP := "gdli_demo_move_up"
const ACTION_MOVE_DOWN := "gdli_demo_move_down"
const ACTION_MOVE_LEFT := "gdli_demo_move_left"
const ACTION_MOVE_RIGHT := "gdli_demo_move_right"
const ACTION_INTERACT := "gdli_demo_interact"
const ACTION_OPEN_INVENTORY := "gdli_demo_open_inventory"

const TUTORIAL_TYPE_DELAY := 0.012
const TUTORIAL_AUTOPLAY_SUBMIT_DELAY := 0.5
const TUTORIAL_LOOP_DELAY := 1.25
const RECORDING_FRAME_DIR := "user://gdli_demo_recording/frames"

const GDLI_UNIVERSAL_FLAGS := """Universal flags (work on any verb):
  --diff [mark]     whole-scene delta before/after the command (or vs a named mark). Replaces the
                    verb's normal output; add --data to show both.
  --mark <name>     save the post-command scene as a checkpoint ('gdli mark' lists them; re-marking
                    the same name overwrites).
  --ticks <n>       (with --diff/--mark) wait n idle frames before the after-snapshot. default 0
  --physics <n>     (with --diff/--mark) wait n physics frames instead.
  --time <s>        (with --diff/--mark) wait s seconds instead.
  --ignore <glob>   drop matching scene-relative paths from the diff (one-shot; e.g. Mover, UI/*).
  ignore add/list/remove/clear
                    manage process-global diff ignores for noisy subtrees.
  --data            show the verb's own data even when --diff is present.
  --headless        if nothing's running, spawn a transient HEADLESS instance for this command only
                    (no window) and stop it after. Bare eval does this by default when no instance is up.
  --timeout <dur>   stop waiting after dur; launch saves session defaults.
  --timewarning <dur>
                    warn while a command is still running; use 0 to disable.
  --json            machine-readable single-line output.
  --game / --editor / --port <n>   force the target instance."""

static func ensure_demo_input_actions() -> Dictionary:
	var actions := {
		ACTION_MOVE_UP: KEY_W,
		ACTION_MOVE_DOWN: KEY_S,
		ACTION_MOVE_LEFT: KEY_A,
		ACTION_MOVE_RIGHT: KEY_D,
		ACTION_INTERACT: KEY_E,
		ACTION_OPEN_INVENTORY: KEY_I,
	}
	for action_name in actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)
		var event := InputEventKey.new()
		event.physical_keycode = actions[action_name]
		InputMap.action_add_event(action_name, event)
	return {
		"ok": true,
		"actions": actions.keys(),
		"persistent": false,
	}
