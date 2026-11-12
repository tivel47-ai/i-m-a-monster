extends Node2D
## Straight, non-homing shot. Layer 8 (friendly residents) is deliberately excluded.
var direction: Vector2
var damage: float
var speed: float = 280.0
var remaining: float = 150.0
var interior_building: Node

func _ready() -> void:
	z_index = 3
	rotation = direction.angle()
	queue_redraw()

func _draw() -> void:
	draw_line(Vector2(-6, 0), Vector2(3, 0), Color(0.85, 0.75, 0.45), 1.5)

func _physics_process(delta: float) -> void:
	var distance = minf(speed * delta, remaining)
	var end = global_position + direction * distance
	var ray = PhysicsRayQueryParameters2D.create(global_position, end, 1 | 2)
	var hit = get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var body = hit.collider
		if body.is_in_group("player_units") and body.interior_building == interior_building and body.is_alive(): body.take_damage(damage)
		queue_free()
		return
	global_position = end
	remaining -= distance
	if remaining <= 0.0: queue_free()
