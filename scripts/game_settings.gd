extends RefCounted

const PATH := "user://settings.cfg"
const DEFAULT_KEYS := {
	"camera_up": KEY_W, "camera_left": KEY_A, "camera_down": KEY_S, "camera_right": KEY_D,
	"race_ability": KEY_F,
	"ability_slot_1": KEY_1, "ability_slot_2": KEY_2, "ability_slot_3": KEY_3,
	"ability_slot_4": KEY_4, "ability_slot_5": KEY_5, "ability_slot_6": KEY_6,
	"ability_slot_7": KEY_7, "ability_slot_8": KEY_8, "ability_slot_9": KEY_9,
	"ability_slot_10": KEY_0,
}
var keys: Dictionary = DEFAULT_KEYS.duplicate()
var fullscreen := false
var camera_speed := 500.0

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		fullscreen = config.get_value("display", "fullscreen", false) == true
		var speed = config.get_value("camera", "speed", 500.0)
		if (speed is float or speed is int) and is_finite(float(speed)):
			camera_speed = clampf(float(speed), 200.0, 900.0)
		var loaded := DEFAULT_KEYS.duplicate()
		for action in DEFAULT_KEYS:
			var key: Variant = config.get_value("controls", action, DEFAULT_KEYS[action])
			if key is int and can_bind(key):
				loaded[action] = key
		if loaded.values().size() == _distinct_count(loaded):
			keys = loaded
	apply()

static func can_bind(key: int) -> bool:
	return key > 0 and key not in [
		KEY_ESCAPE, KEY_SPACE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META,
	] and not OS.get_keycode_string(key).is_empty()

func _distinct_count(bindings: Dictionary) -> int:
	var used := {}
	for key in bindings.values():
		used[key] = true
	return used.size()

func apply() -> void:
	apply_display()
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		Input.action_release(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
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
