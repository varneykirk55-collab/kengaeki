extends Node
## Registers KENGEKI's input actions at startup so bindings live in one place.
## Actions can still be rebound later through InputMap (e.g. by an options menu).

const KEY_BINDINGS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"dodge": [KEY_SPACE],
	"block": [KEY_F, KEY_CTRL],
	"lock_on": [KEY_Q],
	"switch_target": [KEY_TAB],
	"toggle_menu": [KEY_ESCAPE, KEY_M],
	"jump": [KEY_C],
	"toggle_sword": [KEY_E],
	"light_attack": [],
	"heavy_attack": [KEY_R],
}

const MOUSE_BINDINGS := {
	"light_attack": [MOUSE_BUTTON_LEFT],
	"heavy_attack": [MOUSE_BUTTON_RIGHT],
	"lock_on": [MOUSE_BUTTON_MIDDLE],
	"block": [MOUSE_BUTTON_XBUTTON1],
	"camera_zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"camera_zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
}

const JOY_BUTTONS := {
	"dodge": [JOY_BUTTON_B],
	"light_attack": [JOY_BUTTON_X],
	"heavy_attack": [JOY_BUTTON_Y],
	"block": [JOY_BUTTON_LEFT_SHOULDER],
	"lock_on": [JOY_BUTTON_RIGHT_STICK],
	"switch_target": [JOY_BUTTON_RIGHT_SHOULDER],
	"sprint": [JOY_BUTTON_LEFT_STICK],
	"toggle_menu": [JOY_BUTTON_START],
	"jump": [JOY_BUTTON_A],
	"toggle_sword": [JOY_BUTTON_DPAD_UP],
}

const JOY_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"camera_left": [JOY_AXIS_RIGHT_X, -1.0],
	"camera_right": [JOY_AXIS_RIGHT_X, 1.0],
	"camera_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"camera_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func _enter_tree() -> void:
	for action in KEY_BINDINGS:
		_ensure_action(action)
		for keycode in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action in MOUSE_BINDINGS:
		_ensure_action(action)
		for button in MOUSE_BINDINGS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in JOY_BUTTONS:
		_ensure_action(action)
		for button in JOY_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action in JOY_AXES:
		_ensure_action(action, 0.2)
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXES[action][0]
		ev.axis_value = JOY_AXES[action][1]
		InputMap.action_add_event(action, ev)


func _ensure_action(action: StringName, deadzone: float = 0.5) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
