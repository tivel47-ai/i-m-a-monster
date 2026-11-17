extends Node

const CATALOG = preload("res://scripts/mission_catalog.gd")
const SAVE_PATH := "user://race_cursor.cfg"
const CURSOR_SHAPES := [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND]
const MIN_PRESS_MSEC := 100

var race_id := ""
var _selection_dirty := false
var _cursor: Dictionary = {}
var _pressed_at := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_watch_window(get_tree().root)
	get_tree().node_added.connect(_watch_window)
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved_race: Variant = config.get_value("cursor", "race_id", "")
		if saved_race is String and CATALOG.RACES.has(saved_race):
			_apply_race(saved_race)


func select_race(id: String) -> void:
	if not CATALOG.RACES.has(id):
		return
	if id != race_id:
		_apply_race(id)
	_selection_dirty = true
	_save_selection()


func _apply_race(id: String) -> void:
	race_id = id
	_cursor = CATALOG.RACES[id].get("cursor", {})
	_reset_pose()


func _save_selection() -> void:
	if not _selection_dirty:
		return
	var config := ConfigFile.new()
	config.set_value("cursor", "race_id", race_id)
	var temporary := "%s.%d.tmp" % [SAVE_PATH, OS.get_process_id()]
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, SAVE_PATH)
	_selection_dirty = error != OK
	if _selection_dirty:
		DirAccess.remove_absolute(temporary)
		push_warning("Не удалось сохранить расу курсора: %s" % error_string(error))


func _watch_window(node: Node) -> void:
	if node is Window:
		node.window_input.connect(_on_window_input.bind(node))


func _on_window_input(event: InputEvent, window: Window) -> void:
	# The parent window already emits input forwarded to embedded dialogs.
	if _cursor.is_empty() or window.is_embedded():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed_at = Time.get_ticks_msec()
		_set_texture(_cursor.pressed)
		set_process(true)


func _process(_delta: float) -> void:
	# Keep quick clicks visible and detect release even if another node handles it.
	if Time.get_ticks_msec() - _pressed_at >= MIN_PRESS_MSEC and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_reset_pose()


func _reset_pose() -> void:
	set_process(false)
	_set_texture(_cursor.get("idle"))


func _set_texture(texture: Texture2D) -> void:
	for shape in CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(texture, shape, _cursor.get("hotspot", Vector2.ZERO))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_processing():
		_reset_pose()


func _exit_tree() -> void:
	_save_selection()
	_set_texture(null)
