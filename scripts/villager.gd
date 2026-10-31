extends CharacterBody2D

const MOVEMENT_STALL_TIMEOUT := 3.0

signal converted(villager: Node)
signal died(villager: Node)

enum InfectionState {
	AVAILABLE,
	IN_COLLISION,
	TRANSFORMING,
	CONVERTED,
	DEAD,
}

enum Activity { NONE = -1, HOME, WORK, SOCIAL, WANDER }

@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var transformation_duration: float = 2.0
@export var autonomous_movement_enabled: bool = true
@export var points_of_interest_path: NodePath
@export var move_speed: float = 55.0
@export var wait_duration_min: float = 2.0
@export var wait_duration_max: float = 5.0
@export var arrival_tolerance: float = 4.0

@export_group("Peaceful activities")
@export_enum("Villager", "Peasant", "Craftsman") var civilian_profile: String = "Villager"
@export var home_point_path: NodePath
@export var work_point_path: NodePath
@export var home_weight: float = 25.0
@export var work_weight: float = 45.0
@export var social_weight: float = 20.0
@export var wander_weight: float = 10.0
@export var home_duration: Vector2 = Vector2(4.0, 8.0)
@export var work_duration: Vector2 = Vector2(6.0, 12.0)
@export var social_duration: Vector2 = Vector2(3.0, 6.0)
@export var wander_duration: Vector2 = Vector2(2.0, 4.0)

var current_activity: Activity = Activity.NONE
var is_performing_activity: bool = false

var has_destination: bool = false
var destination: Vector2
var wait_remaining: float = 0.0
var progress_position: Vector2
var stalled_seconds: float = 0.0

var infection_state: InfectionState = InfectionState.AVAILABLE
var current_health: float
var converted_color: Color
var encounter_participants: Array[Node2D] = []

@onready var polygon: Polygon2D = $Polygon2D
@onready var transformation_timer: Timer = $TransformationTimer
@onready var encounter_attack_timer: Timer = Timer.new()
@onready var death_marker_a: Line2D = $DeathMarkerA
@onready var death_marker_b: Line2D = $DeathMarkerB
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	current_health = maxf(max_health, 0.0)
	encounter_attack_timer.name = "EncounterAttackTimer"
	encounter_attack_timer.wait_time = maxf(attack_interval, 0.01)
	encounter_attack_timer.timeout.connect(_on_encounter_attack_timer_timeout)
	add_child(encounter_attack_timer)
	if current_health == 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE:
		_stop_movement()
		return
	var navigation_map := navigation_agent.get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return
	navigation_agent.max_speed = maxf(move_speed, 0.0)
	navigation_agent.target_desired_distance = maxf(arrival_tolerance, 0.5)
	if not has_destination:
		wait_remaining = maxf(wait_remaining - delta, 0.0)
		if wait_remaining == 0.0:
			_choose_destination(navigation_map)
		return
	if global_position.distance_to(destination) <= navigation_agent.target_desired_distance:
		_begin_wait(true)
		return
	if global_position.distance_squared_to(progress_position) >= 4.0:
		progress_position = global_position
		stalled_seconds = 0.0
	else:
		stalled_seconds += delta
	if stalled_seconds >= MOVEMENT_STALL_TIMEOUT:
		_begin_wait()
		return
	var next_position := navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		_begin_wait()
		return
	navigation_agent.velocity = global_position.direction_to(next_position) * maxf(move_speed, 0.0)


func _choose_destination(navigation_map: RID) -> void:
	var points := get_node_or_null(points_of_interest_path) if not points_of_interest_path.is_empty() else null
	if points == null:
		_begin_wait()
		return
	var options: Array[Dictionary] = []
	var total_weight := 0.0
	for activity in [Activity.HOME, Activity.WORK, Activity.SOCIAL, Activity.WANDER]:
		var weight := _activity_weight(activity)
		if weight <= 0.0:
			continue
		var candidates: Array[Marker2D] = []
		for candidate in _activity_points(activity, points):
			if _is_destination_valid(candidate.global_position, navigation_map):
				candidates.append(candidate)
		if not candidates.is_empty():
			options.append({"activity": activity, "weight": weight, "points": candidates})
			total_weight += weight
	if options.is_empty():
		_begin_wait()
		return
	var roll := randf() * total_weight
	var selected: Dictionary = options[-1]
	for option in options:
		roll -= float(option["weight"])
		if roll < 0.0:
			selected = option
			break
	current_activity = selected["activity"]
	is_performing_activity = false
	var candidates: Array = selected["points"]
	destination = candidates.pick_random().global_position
	navigation_agent.target_position = destination
	has_destination = true
	progress_position = global_position
	stalled_seconds = 0.0


func _activity_points(activity: Activity, points: Node) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	if activity == Activity.HOME or activity == Activity.WORK:
		var path := home_point_path if activity == Activity.HOME else work_point_path
		var marker := get_node_or_null(path) if not path.is_empty() else null
		if marker is Marker2D:
			result.append(marker)
	else:
		for marker in points.get_children():
			if marker is Marker2D and (activity == Activity.WANDER or marker.is_in_group("civilian_social_points")):
				result.append(marker)
	return result


func _activity_weight(activity: Activity) -> float:
	match activity:
		Activity.HOME: return maxf(home_weight, 0.0)
		Activity.WORK: return maxf(work_weight, 0.0)
		Activity.SOCIAL: return maxf(social_weight, 0.0)
		Activity.WANDER: return maxf(wander_weight, 0.0)
	return 0.0


func _activity_duration(activity: Activity) -> Vector2:
	match activity:
		Activity.HOME: return home_duration
		Activity.WORK: return work_duration
		Activity.SOCIAL: return social_duration
		Activity.WANDER: return wander_duration
	return Vector2(wait_duration_min, wait_duration_max)


func _is_destination_valid(point: Vector2, navigation_map: RID) -> bool:
	if global_position.distance_to(point) <= maxf(arrival_tolerance, 0.5):
		return false
	if NavigationServer2D.map_get_closest_point(navigation_map, point).distance_to(point) > 1.0:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = $CollisionShape2D.shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	var path := NavigationServer2D.map_get_path(navigation_map, global_position, point, true, navigation_agent.navigation_layers)
	return not path.is_empty() and path[-1].distance_to(point) <= 1.0


func _stop_movement() -> void:
	has_destination = false
	current_activity = Activity.NONE
	is_performing_activity = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO


func _begin_wait(arrived: bool = false) -> void:
	var activity := current_activity if arrived else Activity.NONE
	_stop_movement()
	current_activity = activity
	is_performing_activity = activity != Activity.NONE
	var duration := _activity_duration(activity)
	var minimum := maxf(duration.x, 0.0)
	wait_remaining = randf_range(minimum, maxf(duration.y, minimum))


func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE or not has_destination:
		velocity = Vector2.ZERO
		return
	velocity = safe_velocity
	move_and_slide()


func is_available_for_infection() -> bool:
	return infection_state == InfectionState.AVAILABLE and current_health > 0.0


func is_in_collision() -> bool:
	return not encounter_participants.is_empty()


func can_join_encounter() -> bool:
	return (
		current_health > 0.0
		and infection_state in [InfectionState.IN_COLLISION, InfectionState.TRANSFORMING]
		and (infection_state != InfectionState.TRANSFORMING or not encounter_participants.is_empty())
	)


func is_converted() -> bool:
	return infection_state == InfectionState.CONVERTED


func is_dead() -> bool:
	return infection_state == InfectionState.DEAD


func is_alive() -> bool:
	return (
		infection_state != InfectionState.DEAD
		and infection_state != InfectionState.CONVERTED
	)


func take_damage(amount: float) -> void:
	if not is_alive() or current_health <= 0.0 or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	queue_redraw()
	if current_health > 0.0:
		return

	if infection_state == InfectionState.TRANSFORMING:
		_end_encounter()
	else:
		_die()


func receive_zombie_attack(amount: float, chance: float, zombie: Node2D) -> void:
	if (
		not is_alive()
		or current_health <= 0.0
		or not encounter_participants.has(zombie)
		or amount <= 0.0
	):
		return

	if (
		infection_state == InfectionState.IN_COLLISION
		and randf() < clampf(chance, 0.0, 1.0)
	):
		var zombie_visual := zombie.get_node_or_null("Polygon2D") as Polygon2D
		if zombie_visual != null:
			converted_color = zombie_visual.color
		_start_transformation()

	take_damage(amount)


func _start_transformation() -> void:
	if infection_state != InfectionState.IN_COLLISION:
		return

	infection_state = InfectionState.TRANSFORMING
	_stop_movement()
	transformation_timer.wait_time = maxf(transformation_duration, 0.01)
	transformation_timer.start()


func _die() -> void:
	if infection_state == InfectionState.DEAD:
		return

	infection_state = InfectionState.DEAD
	_stop_movement()
	navigation_agent.avoidance_enabled = false
	current_health = 0.0
	transformation_timer.stop()
	_end_encounter()
	z_index = 0
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	death_marker_a.show()
	death_marker_b.show()
	queue_redraw()
	died.emit(self)


func begin_encounter(result_color: Color, zombie: Node2D) -> bool:
	if (
		not is_alive()
		or current_health <= 0.0
		or infection_state
		not in [InfectionState.AVAILABLE, InfectionState.IN_COLLISION, InfectionState.TRANSFORMING]
		or (
			infection_state == InfectionState.TRANSFORMING
			and encounter_participants.is_empty()
		)
		or not zombie.has_method("is_alive")
		or not zombie.call("is_alive")
	):
		return false

	if infection_state == InfectionState.AVAILABLE:
		infection_state = InfectionState.IN_COLLISION
		_begin_wait()
		converted_color = result_color
	if not encounter_participants.has(zombie):
		encounter_participants.append(zombie)
		if encounter_attack_timer.is_stopped():
			encounter_attack_timer.start()
	return true


func is_encounter_owner(zombie: Node2D) -> bool:
	return encounter_participants.has(zombie)


func cancel_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func leave_encounter(zombie: Node2D) -> void:
	if not encounter_participants.has(zombie):
		return

	encounter_participants.erase(zombie)
	if is_instance_valid(zombie) and zombie.has_method("on_encounter_ended"):
		zombie.call("on_encounter_ended", self)
	if encounter_participants.is_empty():
		encounter_attack_timer.stop()
	if encounter_participants.is_empty() and infection_state == InfectionState.IN_COLLISION:
		infection_state = InfectionState.AVAILABLE
	elif encounter_participants.is_empty() and infection_state == InfectionState.TRANSFORMING:
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.set_deferred("disabled", true)


func _end_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func _on_encounter_attack_timer_timeout() -> void:
	if not is_alive() or encounter_participants.is_empty():
		encounter_attack_timer.stop()
		return

	for participant in encounter_participants:
		if (
			is_instance_valid(participant)
			and participant.has_method("is_alive")
			and participant.has_method("take_damage")
			and participant.call("is_alive")
		):
			participant.call("take_damage", attack_damage)
			return

	encounter_attack_timer.stop()


func _on_transformation_timer_timeout() -> void:
	if infection_state != InfectionState.TRANSFORMING:
		return

	infection_state = InfectionState.CONVERTED
	_stop_movement()
	navigation_agent.avoidance_enabled = false
	_end_encounter()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape2D.set_deferred("disabled", true)
	polygon.color = converted_color
	converted.emit(self)


func _draw() -> void:
	if infection_state == InfectionState.DEAD:
		return

	var health_ratio := current_health / max_health if max_health > 0.0 else 0.0
	var health_rect := Rect2(-5.85, -16.25, 11.7, 2.6)
	draw_rect(health_rect, Color(0.12, 0.12, 0.12, 0.9), true)
	draw_rect(
		Rect2(health_rect.position + Vector2(0.65, 0.65), Vector2(10.4 * health_ratio, 1.3)),
		Color(0.9, 0.2, 0.2),
		true
	)
	draw_rect(health_rect, Color(0.05, 0.05, 0.05), false, 0.65)
