extends CharacterBody2D

const VILLAGER_COLLISION_LAYER := 8
const VILLAGER_APPROACH_DISTANCE := 12.0
const INFECTION_DISTANCE := 32.0
const AGGRO_REACQUIRE_DELAY_SECONDS := 0.3
const CROWD_PUSH_CLEARANCE := 48.0

@export var move_speed: float = 100.0
@export var max_health: float = 120.0
@export var attack_damage: float = 20.0
@export var attack_interval: float = 1.0
@export_range(0.0, 1.0, 0.01) var infection_chance: float = 0.15
@export var crowd_push_distance: float = 24.0
@export var crowd_push_speed: float = 60.0
@export var crowd_return_delay: float = 0.75
@export var crowd_return_speed: float = 35.0

var is_selected: bool = false
var current_health: float
var is_dead: bool = false
var target_position: Vector2
var has_target: bool = false
var has_player_order: bool = false
var aggro_reacquire_delay: float = 0.0
var aggro_target: Node2D
var aggro_candidates: Array[Node2D] = []
var crowd_rest_position: Vector2
var crowd_is_displaced: bool = false
var crowd_is_returning: bool = false
var crowd_return_delay_remaining: float = 0.0
var crowd_pusher: Node2D
var crowd_default_navigation_radius: float
var crowd_default_target_desired_distance: float

@onready var zombie_visual: Polygon2D = $Polygon2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var death_marker_a: Line2D = $DeathMarkerA
@onready var death_marker_b: Line2D = $DeathMarkerB


func _ready() -> void:
	current_health = maxf(max_health, 0.0)
	crowd_default_navigation_radius = navigation_agent.radius
	crowd_default_target_desired_distance = navigation_agent.target_desired_distance
	var attack_timer := Timer.new()
	attack_timer.name = "EncounterAttackTimer"
	attack_timer.wait_time = maxf(attack_interval, 0.01)
	attack_timer.timeout.connect(_on_encounter_attack_timer_timeout)
	add_child(attack_timer)
	if current_health == 0.0:
		_die()


func set_selected(value: bool) -> void:
	if is_dead:
		return
	is_selected = value
	queue_redraw()


func _draw() -> void:
	if is_dead:
		return

	var health_ratio := current_health / max_health if max_health > 0.0 else 0.0
	var health_rect := Rect2(-12.0, -34.0, 24.0, 4.0)
	draw_rect(health_rect, Color(0.12, 0.12, 0.12, 0.9), true)
	draw_rect(
		Rect2(health_rect.position + Vector2(1.0, 1.0), Vector2(22.0 * health_ratio, 2.0)),
		Color(0.25, 0.85, 0.25),
		true
	)
	draw_rect(health_rect, Color(0.05, 0.05, 0.05), false, 1.0)

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


func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	queue_redraw()
	if current_health == 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return

	is_dead = true
	current_health = 0.0
	is_selected = false
	has_target = false
	has_player_order = false
	aggro_reacquire_delay = 0.0
	velocity = Vector2.ZERO
	aggro_candidates.clear()

	var attack_timer := get_node_or_null("EncounterAttackTimer") as Timer
	if attack_timer != null:
		attack_timer.stop()

	if (
		aggro_target != null
		and is_instance_valid(aggro_target)
		and aggro_target.has_method("leave_encounter")
	):
		aggro_target.call("leave_encounter", self)
	aggro_target = null

	remove_from_group("player_units")
	crowd_is_displaced = false
	crowd_is_returning = false
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	$Area2D.collision_layer = 0
	$Area2D.collision_mask = 0
	$AggroArea.set_deferred("monitoring", false)
	$AggroArea.set_deferred("monitorable", false)
	navigation_agent.navigation_layers = 0
	navigation_agent.velocity = Vector2.ZERO
	navigation_agent.avoidance_enabled = false
	z_index = 0
	death_marker_a.show()
	death_marker_b.show()
	queue_redraw()


func is_alive() -> bool:
	return not is_dead


func issue_player_move_order(destination: Vector2) -> void:
	if is_dead:
		return

	_prepare_for_player_order()
	has_target = true
	target_position = destination
	navigation_agent.target_position = destination
	queue_redraw()


func issue_player_area_move_order(destination: Vector2) -> void:
	if is_dead:
		return

	_prepare_for_player_order()
	has_target = true
	target_position = destination
	navigation_agent.target_position = destination
	queue_redraw()


func issue_player_area_hold_order() -> void:
	if is_dead:
		return

	_prepare_for_player_order()
	has_target = false
	has_player_order = false
	aggro_reacquire_delay = AGGRO_REACQUIRE_DELAY_SECONDS
	target_position = global_position
	navigation_agent.target_position = global_position
	navigation_agent.velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	queue_redraw()


func _prepare_for_player_order() -> void:
	_cancel_crowd_displacement()
	if (
		aggro_target != null
		and is_instance_valid(aggro_target)
		and aggro_target.has_method("leave_encounter")
	):
		aggro_target.call("leave_encounter", self)

	aggro_target = null
	has_player_order = true
	aggro_reacquire_delay = 0.0


func on_encounter_ended(villager: Node) -> void:
	if aggro_target != villager:
		return

	var attack_timer := get_node_or_null("EncounterAttackTimer") as Timer
	if attack_timer != null:
		attack_timer.stop()
	aggro_target = null
	has_target = false
	velocity = Vector2.ZERO


func _on_encounter_attack_timer_timeout() -> void:
	if is_dead or aggro_target == null or not is_instance_valid(aggro_target):
		return
	if not aggro_target.call("is_encounter_owner", self):
		return

	var villager := aggro_target
	if not villager.has_method("receive_zombie_attack"):
		return
	villager.call("receive_zombie_attack", attack_damage, infection_chance, self)


func _on_aggro_area_body_entered(body: Node2D) -> void:
	if is_dead:
		return
	if not body is PhysicsBody2D:
		return
	var physics_body := body as PhysicsBody2D
	if (physics_body.collision_layer & VILLAGER_COLLISION_LAYER) == 0:
		return
	if not aggro_candidates.has(body):
		aggro_candidates.append(body)


func _on_aggro_area_body_exited(body: Node2D) -> void:
	if is_dead:
		return
	aggro_candidates.erase(body)
	if body == aggro_target:
		if body.has_method("is_in_collision") and body.call("is_in_collision"):
			return
		aggro_target = null
		has_target = false
		velocity = Vector2.ZERO


func _update_aggro_target(delta: float) -> void:
	if is_dead:
		return
	if has_player_order:
		return
	if aggro_reacquire_delay > 0.0:
		aggro_reacquire_delay = maxf(aggro_reacquire_delay - delta, 0.0)
		return

	if aggro_target != null:
		if is_instance_valid(aggro_target) and _has_line_of_sight(aggro_target):
			if aggro_target.call("is_in_collision"):
				if aggro_target.call("is_encounter_owner", self):
					has_target = false
					velocity = Vector2.ZERO
					return

				if global_position.distance_to(aggro_target.global_position) <= INFECTION_DISTANCE:
					if aggro_target.call("begin_encounter", zombie_visual.color, self):
						has_target = false
						velocity = Vector2.ZERO
						_start_encounter_attack_timer()
					else:
						aggro_target = null
						has_target = false
					return

				if not has_target:
					_set_aggro_destination()
				return
			elif aggro_target.call("is_available_for_infection"):
				if global_position.distance_to(aggro_target.global_position) <= INFECTION_DISTANCE:
					if aggro_target.call("begin_encounter", zombie_visual.color, self):
						has_target = false
						velocity = Vector2.ZERO
						_start_encounter_attack_timer()
						return

					aggro_target = null
					has_target = false
					velocity = Vector2.ZERO
				else:
					if not has_target:
						_set_aggro_destination()
					return
			else:
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
		var can_join_encounter: bool = (
			candidate.has_method("can_join_encounter")
			and candidate.call("can_join_encounter")
		)
		if not candidate.call("is_available_for_infection") and not can_join_encounter:
			continue

		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_visible_target = candidate

	if closest_visible_target == null:
		return

	aggro_target = closest_visible_target
	if global_position.distance_to(aggro_target.global_position) <= INFECTION_DISTANCE:
		if aggro_target.call("begin_encounter", zombie_visual.color, self):
			has_target = false
			velocity = Vector2.ZERO
			_start_encounter_attack_timer()
		return
	_set_aggro_destination()


func _start_encounter_attack_timer() -> void:
	var attack_timer := get_node("EncounterAttackTimer") as Timer
	attack_timer.wait_time = maxf(attack_interval, 0.01)
	attack_timer.start()


func _set_aggro_destination() -> void:
	if aggro_target == null or not is_instance_valid(aggro_target):
		return

	_cancel_crowd_displacement()
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


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_aggro_target(delta)
	if aggro_target != null:
		_cancel_crowd_displacement()
	elif crowd_is_displaced and not has_target and not has_player_order:
		if _crowd_pusher_is_nearby():
			crowd_return_delay_remaining = maxf(crowd_return_delay, 0.0)
		elif crowd_return_delay_remaining > 0.0:
			crowd_return_delay_remaining = maxf(crowd_return_delay_remaining - delta, 0.0)
		else:
			crowd_is_returning = true
			navigation_agent.target_desired_distance = 1.0
			has_target = true
			navigation_agent.target_position = crowd_rest_position

	if not has_target:
		navigation_agent.velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		return

	if NavigationServer2D.map_get_iteration_id(
		navigation_agent.get_navigation_map()
	) == 0:
		navigation_agent.velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		return

	var next_path_position := navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		_finish_movement_target()
		return

	var desired_direction := global_position.direction_to(next_path_position)
	_push_blocking_idle_zombies(desired_direction)
	if has_player_order and _is_waiting_for_crowd_to_yield(desired_direction):
		navigation_agent.velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		return

	var desired_speed := move_speed
	if crowd_is_displaced:
		desired_speed = minf(
			move_speed,
			crowd_return_speed if crowd_is_returning else crowd_push_speed
		)
	navigation_agent.velocity = desired_direction * desired_speed
	queue_redraw()


func _push_blocking_idle_zombies(direction: Vector2) -> void:
	if not has_player_order:
		return

	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit == self or not unit.has_method("_receive_crowd_push"):
			continue

		var offset: Vector2 = unit.global_position - global_position
		var forward_distance := offset.dot(direction)
		var lateral_distance := absf(offset.cross(direction))
		var push_trigger_distance := maxf(
			crowd_push_distance + navigation_agent.radius + 20.0,
			navigation_agent.neighbor_distance
		)
		if (
			forward_distance > 0.0
			and forward_distance <= push_trigger_distance
			and lateral_distance <= 20.0
		):
			unit.call("_receive_crowd_push", direction, global_position, self)


func _is_waiting_for_crowd_to_yield(direction: Vector2) -> bool:
	var push_trigger_distance := maxf(
		crowd_push_distance + navigation_agent.radius + 20.0,
		navigation_agent.neighbor_distance
	)
	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit == self or not unit.crowd_is_displaced:
			continue

		var offset: Vector2 = unit.global_position - global_position
		var forward_distance := offset.dot(direction)
		var lateral_distance := absf(offset.cross(direction))
		if (
			forward_distance > -20.0
			and forward_distance <= push_trigger_distance
			and lateral_distance < CROWD_PUSH_CLEARANCE - 8.0
		):
			return true
	return false


func _on_navigation_agent_velocity_computed(safe_velocity: Vector2) -> void:
	if is_dead or not has_target:
		velocity = Vector2.ZERO
		return

	velocity = safe_velocity
	move_and_slide()
	_push_crowd_zombies_from_collisions()
	if navigation_agent.is_navigation_finished():
		_finish_movement_target()


func _push_crowd_zombies_from_collisions() -> void:
	if not has_player_order:
		return

	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var other := collision.get_collider() as Node
		if (
			other == null
			or not other.is_in_group("player_units")
			or not other.has_method("_receive_crowd_push")
		):
			continue

		other.call("_receive_crowd_push", -collision.get_normal(), global_position, self)


func _receive_crowd_push(
	direction: Vector2, pusher_position: Vector2, pusher: Node2D
) -> void:
	if (
		is_dead
		or has_player_order
		or aggro_target != null
		or has_target and not crowd_is_displaced
		or not get_node("EncounterAttackTimer").is_stopped()
		or crowd_is_displaced
	):
		return

	var movement_direction := direction.normalized()
	if movement_direction.is_zero_approx():
		return
	var side_direction := movement_direction.orthogonal()
	var side_offset := (global_position - pusher_position).dot(side_direction)
	var side_sign := signf(side_offset)
	if is_zero_approx(side_sign):
		side_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	var push_direction := side_direction * side_sign
	var push_distance := maxf(
		crowd_push_distance,
		CROWD_PUSH_CLEARANCE - absf(side_offset)
	)

	if not crowd_is_displaced:
		crowd_rest_position = global_position
	crowd_is_displaced = true
	crowd_is_returning = false
	crowd_return_delay_remaining = 0.0
	crowd_pusher = pusher
	navigation_agent.radius = 0.0
	has_target = true
	navigation_agent.target_position = (
		crowd_rest_position + push_direction * maxf(push_distance, 1.0)
	)


func _crowd_pusher_is_nearby() -> bool:
	return (
		crowd_pusher != null
		and is_instance_valid(crowd_pusher)
		and not crowd_pusher.is_dead
		and crowd_pusher.has_player_order
		and crowd_pusher.global_position.distance_to(crowd_rest_position)
		<= crowd_push_distance + CROWD_PUSH_CLEARANCE
	)


func _cancel_crowd_displacement() -> void:
	crowd_is_displaced = false
	crowd_is_returning = false
	crowd_return_delay_remaining = 0.0
	crowd_pusher = null
	navigation_agent.radius = crowd_default_navigation_radius
	navigation_agent.target_desired_distance = crowd_default_target_desired_distance


func _finish_movement_target() -> void:
	has_target = false
	navigation_agent.velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	if crowd_is_displaced:
		if crowd_is_returning:
			_cancel_crowd_displacement()
		else:
			crowd_return_delay_remaining = maxf(crowd_return_delay, 0.0)
	if aggro_target == null and has_player_order:
		has_player_order = false
		aggro_reacquire_delay = AGGRO_REACQUIRE_DELAY_SECONDS
	queue_redraw()
