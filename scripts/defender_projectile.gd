extends Node2D
## Straight, non-homing shot. Layer 8 (friendly residents) is deliberately excluded.
const BARRICADE = preload("res://scripts/last_stand_barricade.gd")
const CIVILIAN_BLOCKERS := 1 | BARRICADE.MONSTER_OBSTACLE | BuildingInterior.ACCESS_LAYER

signal impacted(weapon: StringName, world_point: Vector2, monster: Node2D)

var weapon: StringName
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
	match weapon:
		&"sling":
			draw_circle(Vector2.ZERO, 2.0, Color("c5d5e2"))
			return
		&"hunting_bow":
			draw_line(Vector2(-8, 0), Vector2(5, 0), Color("e3e9bf"), 1.8)
			draw_polyline(PackedVector2Array([Vector2(1, -2), Vector2(5, 0), Vector2(1, 2)]), Color("e3e9bf"))
			return
	var weight := 1.0 - minf(_distance_traveled / display_convergence_distance, 1.0)
	var display_position := display_origin_offset.rotated(-rotation) * weight
	draw_line(display_position + Vector2(-6, 0), display_position + Vector2(3, 0), Color(0.85, 0.75, 0.45), 1.5)

func _physics_process(delta: float) -> void:
	var distance = minf(speed * delta, remaining)
	var end = global_position + direction * distance
	var ray = PhysicsRayQueryParameters2D.create(global_position, end, 1 | 2)
	if not weapon.is_empty():
		ray.collision_mask = CIVILIAN_BLOCKERS | 2
	var hit = get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var body = hit.collider
		var monster: Node2D
		if body.is_in_group("player_units") and body.interior_building == interior_building and body.is_alive():
			monster = body
			body.take_damage(damage, direction)
		impacted.emit(weapon, hit.position, monster)
		queue_free()
		return
	global_position = end
	remaining -= distance
	if display_origin_offset != Vector2.ZERO and _distance_traveled < display_convergence_distance:
		_distance_traveled += distance
		queue_redraw()
	if remaining <= 0.0: queue_free()
