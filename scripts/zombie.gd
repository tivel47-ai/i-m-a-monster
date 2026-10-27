extends Node2D

@export var move_speed: float = 100.0

var is_selected: bool = false
var target_position: Vector2
var has_target: bool = false

@onready var input_area: Area2D = $Area2D


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _is_mouse_over_zombie() -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collision_mask = input_area.collision_layer
	query.collide_with_areas = true
	query.collide_with_bodies = false

	for result in get_world_2d().direct_space_state.intersect_point(query):
		if result["collider"] == input_area:
			return true
	return false


func _draw() -> void:
	if is_selected:
		draw_arc(
			Vector2.ZERO,
			24.0,
			0.0,
			TAU,
			32,
			Color.YELLOW,
			2.0
		)

	if has_target:
		var marker_position := to_local(target_position)
		var marker_color := Color(0.3, 0.9, 1.0)
		draw_arc(marker_position, 10.0, 0.0, TAU, 24, marker_color, 2.0)
		draw_line(
			marker_position + Vector2(-14.0, 0.0),
			marker_position + Vector2(14.0, 0.0),
			marker_color,
			2.0
		)
		draw_line(
			marker_position + Vector2(0.0, -14.0),
			marker_position + Vector2(0.0, 14.0),
			marker_color,
			2.0
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			set_selected(_is_mouse_over_zombie())
		elif is_selected and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			target_position = get_global_mouse_position()
			has_target = true
			queue_redraw()


func _physics_process(delta: float) -> void:
	if not has_target:
		return

	global_position = global_position.move_toward(
		target_position,
		move_speed * delta
	)
	if global_position.is_equal_approx(target_position):
		has_target = false
	queue_redraw()
