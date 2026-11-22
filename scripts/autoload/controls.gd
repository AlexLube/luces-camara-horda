extends Node
## Input actions for keyboard, gamepad and touch. Keyboard keys can be rebound from Options and are saved.

const ACTIONS := {
	"move_left":  {"keys": [KEY_A, KEY_LEFT],  "pad_axis": [JOY_AXIS_LEFT_X, -1.0], "pad_btn": [JOY_BUTTON_DPAD_LEFT]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT], "pad_axis": [JOY_AXIS_LEFT_X, 1.0],  "pad_btn": [JOY_BUTTON_DPAD_RIGHT]},
	"move_up":    {"keys": [KEY_W, KEY_UP],    "pad_axis": [JOY_AXIS_LEFT_Y, -1.0], "pad_btn": [JOY_BUTTON_DPAD_UP]},
	"move_down":  {"keys": [KEY_S, KEY_DOWN],  "pad_axis": [JOY_AXIS_LEFT_Y, 1.0],  "pad_btn": [JOY_BUTTON_DPAD_DOWN]},
	"pause":      {"keys": [KEY_ESCAPE, KEY_P], "pad_btn": [JOY_BUTTON_START]},
	"pick_1":     {"keys": [KEY_1]},
	"pick_2":     {"keys": [KEY_2]},
	"pick_3":     {"keys": [KEY_3]},
	"pick_4":     {"keys": [KEY_4]},
	"reroll":     {"keys": [KEY_R], "pad_btn": [JOY_BUTTON_Y]},
	"skip":       {"keys": [KEY_X], "pad_btn": [JOY_BUTTON_X]},
	"banish":     {"keys": [KEY_B], "pad_btn": [JOY_BUTTON_LEFT_SHOULDER]},
}
const REBINDABLE := ["move_up", "move_down", "move_left", "move_right", "pause", "reroll", "skip", "banish"]

func _ready() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a): InputMap.add_action(a, 0.25)
	apply()

## Rebuild every action from the defaults plus the saved keyboard overrides.
func apply() -> void:
	var binds: Dictionary = Save.data.options.get("binds", {}) if Save.data.size() > 0 else {}
	for a in ACTIONS:
		InputMap.action_erase_events(a)
		var keys: Array = binds.get(a, ACTIONS[a].keys)
		for k in keys:
			var e := InputEventKey.new()
			e.physical_keycode = int(k)
			InputMap.action_add_event(a, e)
		if ACTIONS[a].has("pad_axis"):
			var m := InputEventJoypadMotion.new()
			m.axis = ACTIONS[a].pad_axis[0]
			m.axis_value = ACTIONS[a].pad_axis[1]
			InputMap.action_add_event(a, m)
		for b in ACTIONS[a].get("pad_btn", []):
			var j := InputEventJoypadButton.new()
			j.button_index = b
			InputMap.action_add_event(a, j)

func rebind(action: String, keycode: int) -> void:
	Save.data.options.binds[action] = [keycode]
	Save.save_game()
	apply()

func reset() -> void:
	Save.data.options.binds = {}
	Save.save_game()
	apply()

func key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey: return OS.get_keycode_string(e.physical_keycode)
	return "-"

## Movement vector from keyboard/gamepad (touch is added by the run's virtual stick).
func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.2)
