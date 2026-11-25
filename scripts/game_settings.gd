extends RefCounted

const PATH := "user://settings.cfg"
const BUILDING_ASSAULT := "monster_building_assault"
const CANCEL_HORDE_ORDER := "monster_cancel_horde_order"
const CAMERA_ZOOM_IN := "camera_zoom_in"
const CAMERA_ZOOM_OUT := "camera_zoom_out"
# Mouse buttons use negative IDs so existing physical key codes stay intact.
const CAMERA_ZOOM := {
	CAMERA_ZOOM_IN: {"title": "Приблизить камеру", "bindings": [KEY_EQUAL, KEY_KP_ADD, -MOUSE_BUTTON_WHEEL_UP]},
	CAMERA_ZOOM_OUT: {"title": "Отдалить камеру", "bindings": [KEY_MINUS, KEY_KP_SUBTRACT, -MOUSE_BUTTON_WHEEL_DOWN]},
}
const MONSTER_COMMANDS := {
	BUILDING_ASSAULT: {"title": "Штурм здания", "key": KEY_E},
	CANCEL_HORDE_ORDER: {"title": "Отменить приказ орде", "key": KEY_C},
}
const DEFAULT_KEYS := {
	"camera_up": KEY_W, "camera_left": KEY_A, "camera_down": KEY_S, "camera_right": KEY_D,
	"race_ability": KEY_F,
	"ability_slot_1": KEY_1, "ability_slot_2": KEY_2, "ability_slot_3": KEY_3,
	"ability_slot_4": KEY_4, "ability_slot_5": KEY_5, "ability_slot_6": KEY_6,
	"ability_slot_7": KEY_7, "ability_slot_8": KEY_8, "ability_slot_9": KEY_9,
	"ability_slot_10": KEY_0,
}
var keys: Dictionary = _default_keys()
var fullscreen := false
var camera_speed := 500.0

static func _default_keys() -> Dictionary:
	var defaults := DEFAULT_KEYS.duplicate()
	for action in MONSTER_COMMANDS:
		defaults[action] = MONSTER_COMMANDS[action].key
	for action in CAMERA_ZOOM:
		defaults[action] = CAMERA_ZOOM[action].bindings.duplicate()
	return defaults

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		fullscreen = config.get_value("display", "fullscreen", false) == true
		var speed = config.get_value("camera", "speed", 500.0)
		if (speed is float or speed is int) and is_finite(float(speed)):
			camera_speed = clampf(float(speed), 200.0, 900.0)
		keys = _load_keys(config)
	apply()

static func _load_keys(config: ConfigFile) -> Dictionary:
	var defaults := _default_keys()
	var loaded := {}
	var used := {}
	# Keep saved assignments ahead of defaults for actions introduced later.
	for action in defaults:
		var saved: Variant = config.get_value("controls", action, "")
		if CAMERA_ZOOM.has(action):
			if saved is Array and saved.all(func(binding: Variant) -> bool:
				return binding is int and (can_bind(binding) or can_bind_mouse(-binding))):
				loaded[action] = []
				for binding in saved:
					if not used.has(binding):
						loaded[action].append(binding)
						used[binding] = true
		elif saved is int and (saved == KEY_NONE or (can_bind(saved) and not used.has(saved))):
			loaded[action] = saved
			used[saved] = true
	for action in defaults:
		if loaded.has(action):
			continue
		if CAMERA_ZOOM.has(action):
			# Entries in the two zoom defaults are distinct from each other.
			loaded[action] = defaults[action].filter(func(binding: int) -> bool: return not used.has(binding))
		else:
			var key: int = defaults[action]
			loaded[action] = KEY_NONE if used.has(key) else key
			used[key] = true
	return loaded

static func can_bind(key: int) -> bool:
	return key > 0 and key not in [
		KEY_ESCAPE, KEY_SPACE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META,
	] and not OS.get_keycode_string(key).is_empty()

static func can_bind_mouse(button: int) -> bool:
	return button >= MOUSE_BUTTON_LEFT and button <= MOUSE_BUTTON_XBUTTON2

func apply() -> void:
	apply_display()
	for action in keys:
		apply_key(action, keys[action])

static func apply_key(action: String, binding: Variant) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	Input.action_release(action)
	InputMap.action_erase_events(action)
	for key: int in (binding if binding is Array else [binding]):
		if key < 0:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = -key
			InputMap.action_add_event(action, mouse)
		elif key != KEY_NONE:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("camera", "speed", camera_speed)
	for action in keys:
		config.set_value("controls", action, keys[action])
	return config.save(PATH)
