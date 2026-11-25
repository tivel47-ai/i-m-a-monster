extends Camera2D

signal zoom_changed(fraction: float)

const SETTINGS = preload("res://scripts/game_settings.gd")

@export var move_speed: float = 500.0
@export_range(0.1, 4.0, 0.1) var min_zoom: float = 1.0
@export_range(0.1, 4.0, 0.1) var max_zoom: float = 2.0
@export_range(0.01, 1.0, 0.01) var zoom_step: float = 0.15
# Authoritative rectangular visual map area in world coordinates.
@export var map_bounds: Rect2 = Rect2(0, 0, 1280, 720)
@export var use_zoom_bindings := false

var zoom_pointer_over_ui: Callable


func _ready() -> void:
	assert(map_bounds.size.x > 0.0 and map_bounds.size.y > 0.0, "Map bounds must have positive dimensions.")
	if use_zoom_bindings:
		for action: String in SETTINGS.CAMERA_ZOOM:
			if not InputMap.has_action(action):
				SETTINGS.apply_key(action, SETTINGS.CAMERA_ZOOM[action].bindings)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_set_zoom_level(zoom.x)


func _input(event: InputEvent) -> void:
	var direction := _zoom_direction(event)
	if direction == 0:
		return
	_set_zoom_level(zoom.x + direction * zoom_step)
	get_viewport().set_input_as_handled()


func _zoom_direction(event: InputEvent) -> int:
	if not use_zoom_bindings:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				return 1
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return -1
		return 0
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if zoom_pointer_over_ui.is_valid() and zoom_pointer_over_ui.call(event.position):
			return 0
	if event.is_action_pressed(SETTINGS.CAMERA_ZOOM_IN):
		return 1
	if event.is_action_pressed(SETTINGS.CAMERA_ZOOM_OUT):
		return -1
	return 0


func _set_zoom_level(value: float) -> void:
	var previous_zoom := zoom.x
	var viewport_size := get_viewport_rect().size
	var fit_zoom := maxf(viewport_size.x / map_bounds.size.x, viewport_size.y / map_bounds.size.y)
	var effective_min := maxf(min_zoom, fit_zoom)
	# Only override the configured maximum when fitting the map requires it.
	zoom = Vector2.ONE * clampf(value, effective_min, maxf(max_zoom, effective_min))
	var half_size := viewport_size / zoom * 0.5
	var center := global_position + offset
	center = center.clamp(map_bounds.position + half_size, map_bounds.end - half_size)
	global_position = center - offset
	# Keep selection and orders correct even later in the same input batch.
	force_update_scroll()
	if not is_equal_approx(zoom.x, previous_zoom):
		zoom_changed.emit(zoom_fraction())


func zoom_fraction() -> float:
	return clampf((zoom.x - min_zoom) / maxf(max_zoom - min_zoom, 0.001), 0.0, 1.0)


func _on_viewport_size_changed() -> void:
	_set_zoom_level(zoom.x)


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	global_position += direction * move_speed * delta
	_set_zoom_level(zoom.x)
