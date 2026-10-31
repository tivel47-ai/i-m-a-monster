extends Camera2D

@export var move_speed: float = 500.0


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	global_position += direction * move_speed * delta
