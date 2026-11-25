extends Node2D
## Straight, non-homing shot. Layer 8 (friendly residents) is deliberately excluded.
var direction: Vector2
var damage: float
var speed: float = 280.0
var remaining: float = 150.0
var interior_building: Node
var display_origin_offset := Vector2.ZERO
var display_convergence_distance := 1.0
var _distance_traveled := 0.0

func _ready() -> void:
	z_index = 3
	rotation = direction.angle()
	queue_redraw()

func _draw() -> void:
	var weight := 1.0 - minf(_distance_traveled / display_convergence_distance, 1.0)
	var display_position := display_origin_offset.rotated(-rotation) * weight
	draw_line(display_position + Vector2(-6, 0), display_position + Vector2(3, 0), Color(0.85, 0.75, 0.45), 1.5)

func _physics_process(delta: float) -> void:
	var distance = minf(speed * delta, remaining)
	var end = global_position + direction * distance
	var ray = PhysicsRayQueryParameters2D.create(global_position, end, 1 | 2)
	var hit = get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var body = hit.collider
		if body.is_in_group("player_units") and body.interior_building == interior_building and body.is_alive():
			body.take_damage(damage, direction)
		queue_free()
		return
	global_position = end
	remaining -= distance
	if display_origin_offset != Vector2.ZERO and _distance_traveled < display_convergence_distance:
		_distance_traveled += distance
		queue_redraw()
	if remaining <= 0.0: queue_free()
