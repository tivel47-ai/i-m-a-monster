extends CharacterBody2D

const VILLAGER_COLLISION_LAYER := 8
const VILLAGER_APPROACH_DISTANCE := 12.0
const INFECTION_DISTANCE := 24.0
const AGGRO_REACQUIRE_DELAY_SECONDS := 0.3

@export var move_speed: float = 100.0
@export var max_health: float = 120.0
@export var attack_damage: float = 20.0
@export var attack_interval: float = 1.0
@export_range(0.0, 1.0, 0.01) var infection_chance: float = 0.15

var is_selected: bool = false
var current_health: float
var is_dead: bool = false
var target_position: Vector2
var has_target: bool = false
var has_player_order: bool = false
var aggro_reacquire_delay: float = 0.0
var aggro_target: Node2D
var aggro_candidates: Array[Node2D] = []

@onready var zombie_visual: Polygon2D = $Polygon2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var death_marker_a: Line2D = $DeathMarkerA
@onready var death_marker_b: Line2D = $DeathMarkerB


func _ready() -> void:
	current_health = maxf(max_health, 0.0)
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
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	$Area2D.collision_layer = 0
	$Area2D.collision_mask = 0
	$AggroArea.set_deferred("monitoring", false)
	$AggroArea.set_deferred("monitorable", false)
	navigation_agent.navigation_layers = 0
	death_marker_a.show()
	death_marker_b.show()
	queue_redraw()


func is_alive() -> bool:
	return not is_dead


func issue_player_move_order(destination: Vector2) -> void:
	if is_dead:
		return

	if (
		aggro_target != null
		and is_instance_valid(aggro_target)
		and aggro_target.has_method("leave_encounter")
	):
		aggro_target.call("leave_encounter", self)

	aggro_target = null
	has_target = true
	has_player_order = true
	aggro_reacquire_delay = 0.0
	target_position = destination
	navigation_agent.target_position = destination
	queue_redraw()


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
		if aggro_target == null and has_player_order:
			has_player_order = false
			aggro_reacquire_delay = AGGRO_REACQUIRE_DELAY_SECONDS
		queue_redraw()
		return

	velocity = global_position.direction_to(next_path_position) * move_speed
	move_and_slide()

	if navigation_agent.is_navigation_finished():
		has_target = false
		velocity = Vector2.ZERO
		if aggro_target == null and has_player_order:
			has_player_order = false
			aggro_reacquire_delay = AGGRO_REACQUIRE_DELAY_SECONDS
	queue_redraw()
