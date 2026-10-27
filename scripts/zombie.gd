extends CharacterBody2D

@export var move_speed: float = 100.0

var is_selected: bool = false
var target_position: Vector2
var has_target: bool = false

@onready var input_area: Area2D = $Area2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D


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
			navigation_agent.target_position = target_position
			has_target = true
			queue_redraw()


func _physics_process(_delta: float) -> void:
	if not has_target:
		return

	if NavigationServer2D.map_get_iteration_id(
		navigation_agent.get_navigation_map()
	) == 0:
		velocity = Vector2.ZERO
		return

	var next_path_position := navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		has_target = false
		velocity = Vector2.ZERO
		queue_redraw()
		return

	velocity = global_position.direction_to(next_path_position) * move_speed
	move_and_slide()

	if navigation_agent.is_navigation_finished():
		has_target = false
		velocity = Vector2.ZERO
	queue_redraw()
