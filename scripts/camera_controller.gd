extends Camera2D

@export var move_speed: float = 500.0
@export_range(0.1, 4.0, 0.1) var min_zoom: float = 1.0
@export_range(0.1, 4.0, 0.1) var max_zoom: float = 2.0
@export_range(0.01, 1.0, 0.01) var zoom_step: float = 0.1


func _ready() -> void:
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
	zoom = Vector2.ONE * clampf(value, min_zoom, maxf(min_zoom, max_zoom))
	# Keep selection and orders correct even later in the same input batch.
	force_update_scroll()


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	global_position += direction * move_speed * delta
