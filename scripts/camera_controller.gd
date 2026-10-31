extends Camera2D

@export var move_speed: float = 500.0
@export_range(0.1, 4.0, 0.1) var min_zoom: float = 1.0
@export_range(0.1, 4.0, 0.1) var max_zoom: float = 2.0
@export_range(0.01, 1.0, 0.01) var zoom_step: float = 0.15
# Authoritative rectangular visual map area in world coordinates.
@export var map_bounds: Rect2 = Rect2(0, 0, 1280, 720)


func _ready() -> void:
	assert(map_bounds.size.x > 0.0 and map_bounds.size.y > 0.0, "Map bounds must have positive dimensions.")
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_set_zoom_level(zoom.x)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_zoom_level(zoom.x + zoom_step)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_zoom_level(zoom.x - zoom_step)
	else:
		return
	get_viewport().set_input_as_handled()


func _set_zoom_level(value: float) -> void:
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


func _on_viewport_size_changed() -> void:
	_set_zoom_level(zoom.x)


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	global_position += direction * move_speed * delta
	_set_zoom_level(zoom.x)
