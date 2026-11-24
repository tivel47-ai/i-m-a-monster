extends RefCounted

const PATH := "user://settings.cfg"
const BUILDING_ASSAULT := "monster_building_assault"
const CANCEL_HORDE_ORDER := "monster_cancel_horde_order"
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
		var key: Variant = config.get_value("controls", action, "")
		if key is int and (key == KEY_NONE or (can_bind(key) and not used.has(key))):
			loaded[action] = key
			used[key] = true
	for action in defaults:
		if loaded.has(action):
			continue
		var key: int = defaults[action]
		loaded[action] = KEY_NONE if used.has(key) else key
		used[key] = true
	return loaded

static func can_bind(key: int) -> bool:
	return key > 0 and key not in [
		KEY_ESCAPE, KEY_SPACE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META,
	] and not OS.get_keycode_string(key).is_empty()

func apply() -> void:
	apply_display()
	for action in keys:
		apply_key(action, keys[action])

static func apply_key(action: String, key: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	Input.action_release(action)
	InputMap.action_erase_events(action)
	if key == KEY_NONE:
		return
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
