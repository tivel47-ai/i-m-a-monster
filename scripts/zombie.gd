extends CharacterBody2D

const VILLAGER_COLLISION_LAYER := 8
const VILLAGER_APPROACH_DISTANCE := 12.0
const INFECTION_DISTANCE := 24.0

@export var move_speed: float = 100.0

var is_selected: bool = false
var target_position: Vector2
var has_target: bool = false
var has_player_order: bool = false
var aggro_target: Node2D
var aggro_candidates: Array[Node2D] = []

@onready var zombie_visual: Polygon2D = $Polygon2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


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

	if has_player_order:
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
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and is_selected
	):
		if aggro_target != null and aggro_target.has_method("cancel_encounter"):
			aggro_target.call("cancel_encounter")
		aggro_target = null
		target_position = get_global_mouse_position()
		has_player_order = true
		has_target = true
		navigation_agent.target_position = target_position
		queue_redraw()


func _on_aggro_area_body_entered(body: Node2D) -> void:
	if not body is PhysicsBody2D:
		return
	var physics_body := body as PhysicsBody2D
	if (physics_body.collision_layer & VILLAGER_COLLISION_LAYER) == 0:
		return
	if not aggro_candidates.has(body):
		aggro_candidates.append(body)


func _on_aggro_area_body_exited(body: Node2D) -> void:
	aggro_candidates.erase(body)
	if body == aggro_target:
		if body.has_method("is_in_collision") and body.call("is_in_collision"):
			return
		aggro_target = null
		has_target = false
		velocity = Vector2.ZERO


func _update_aggro_target() -> void:
	if has_player_order:
		return

	if aggro_target != null:
		if is_instance_valid(aggro_target) and _has_line_of_sight(aggro_target):
			if aggro_target.call("is_in_collision"):
				has_target = false
				velocity = Vector2.ZERO
				return

			if aggro_target.call("is_available_for_infection"):
				if global_position.distance_to(aggro_target.global_position) <= INFECTION_DISTANCE:
					if aggro_target.call("begin_encounter", zombie_visual.color):
						has_target = false
						velocity = Vector2.ZERO
					return

				if not has_target:
					_set_aggro_destination()
				return

			aggro_target = null
			has_target = false
			velocity = Vector2.ZERO
		else:
			aggro_target = null
			has_target = false
			velocity = Vector2.ZERO

	var closest_visible_target: Node2D
	var closest_distance_squared := INF
	for candidate in aggro_candidates:
		if not is_instance_valid(candidate) or not _has_line_of_sight(candidate):
			continue
		if not candidate.has_method("is_available_for_infection"):
			continue
		if not candidate.call("is_available_for_infection"):
			continue

		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_visible_target = candidate

	if closest_visible_target == null:
		return

	aggro_target = closest_visible_target
	if global_position.distance_to(aggro_target.global_position) <= INFECTION_DISTANCE:
		if aggro_target.call("begin_encounter", zombie_visual.color):
			has_target = false
			velocity = Vector2.ZERO
		return
	_set_aggro_destination()


func _set_aggro_destination() -> void:
	if aggro_target == null or not is_instance_valid(aggro_target):
		return

	var direction_to_zombie := aggro_target.global_position.direction_to(global_position)
	navigation_agent.target_position = (
		aggro_target.global_position
		+ direction_to_zombie * VILLAGER_APPROACH_DISTANCE
	)
	has_target = true


func _has_line_of_sight(target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(_delta: float) -> void:
	_update_aggro_target()
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
		if aggro_target == null:
			has_player_order = false
		queue_redraw()
		return

	velocity = global_position.direction_to(next_path_position) * move_speed
	move_and_slide()

	if navigation_agent.is_navigation_finished():
		has_target = false
		velocity = Vector2.ZERO
		if aggro_target == null:
			has_player_order = false
	queue_redraw()
