extends CharacterBody2D

const MOVEMENT_STALL_TIMEOUT := 3.0

signal converted(villager: Node)
signal died(villager: Node)
signal threat_recognized(zombie: Node2D)
signal warning_attempted(villager: Node2D, threat_position: Vector2)
signal encounter_started(zombie: Node2D)

enum InfectionState {
	AVAILABLE,
	IN_COLLISION,
	TRANSFORMING,
	CONVERTED,
	DEAD,
}

enum Activity { NONE = -1, HOME, WORK, SOCIAL, WANDER }
enum NavigationResult { MOVING, ARRIVED, FAILED }

@export var max_health: float = 100.0
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var transformation_duration: float = 2.0
@export var autonomous_movement_enabled: bool = true
@export var points_of_interest_path: NodePath
@export var move_speed: float = 35.0
@export var wait_duration_min: float = 2.0
@export var wait_duration_max: float = 5.0
@export var arrival_tolerance: float = 4.0
@export_group("Defensive ranged equipment")
## Opt-in equipment; existing maps keep their current melee assignments.
@export var defense_ranged_weapon: bool = false
@export var defense_weapon_range: float = 150.0
@export var defense_projectile_speed: float = 280.0

@export_group("Peaceful activities")
@export_enum("Villager", "Peasant", "Craftsman") var civilian_profile: String = "Villager"
@export var home_point_path: NodePath
@export var work_point_path: NodePath
@export var home_weight: float = 25.0
@export var work_weight: float = 45.0
@export var social_weight: float = 20.0
@export var wander_weight: float = 10.0
@export var home_duration: Vector2 = Vector2(12.0, 24.0)
@export var work_duration: Vector2 = Vector2(18.0, 36.0)
@export var social_duration: Vector2 = Vector2(9.0, 18.0)
@export var wander_duration: Vector2 = Vector2(6.0, 12.0)

@export_group("Activity zones")
## Explicit assignments only; empty keeps the existing marker-based behavior.
@export var activity_zone_paths: Array[NodePath] = []
## Functional shelter markers may remain available without serving peaceful AI.
@export var marker_activity_fallback_enabled: bool = true
@export var preferred_district: StringName
@export_range(1, 10, 0.1) var district_zone_preference: float = 3.0
## Zero disables distance preference; otherwise this is the distance falloff scale.
@export_range(0, 3000, 10) var nearby_zone_distance: float = 0.0
## X: radius factor, Y: pause-duration factor, Z: movement-probability factor.
@export var home_local_rules: Vector3 = Vector3(0.65, 1.5, 0.6)
@export var work_local_rules: Vector3 = Vector3(0.5, 2.0, 0.4)
@export var social_local_rules: Vector3 = Vector3(0.8, 1.0, 1.2)
@export var wander_local_rules: Vector3 = Vector3(1.3, 0.5, 1.8)
@export_range(0, 1, 0.01) var local_long_move_chance: float = 0.1

var _using_zone: bool = false
var current_zone: ActivityZone2D
var local_wait_remaining: float = 0.0
var _last_local_origin: Vector2 = Vector2.INF
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
var defense: Node
var guard_ai: Node
var escort: Node
@onready var priest_guard = get_node_or_null("PriestGuard")

@onready var polygon: Polygon2D = $Polygon2D
@onready var transformation_timer: Timer = $TransformationTimer
@onready var encounter_attack_timer: Timer = Timer.new()
@onready var death_marker_a: Line2D = $DeathMarkerA
@onready var death_marker_b: Line2D = $DeathMarkerB
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var threat_detection = $ThreatDetection
@onready var threat_reaction = $ThreatReaction
@onready var local_warning = $LocalWarning
@onready var guard_patrol = get_node_or_null("GuardPatrol")
@onready var priest_routine = get_node_or_null("PriestRoutine")


func _ready() -> void:
	add_to_group("activity_zone_residents")
	current_health = maxf(max_health, 0.0)
	encounter_attack_timer.name = "EncounterAttackTimer"
	encounter_attack_timer.wait_time = maxf(attack_interval, 0.01)
	encounter_attack_timer.timeout.connect(_on_encounter_attack_timer_timeout)
	add_child(encounter_attack_timer)
	if current_health == 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if defense != null and priest_guard != null and autonomous_movement_enabled:
		if priest_guard.update_ai(delta): return
	if defense != null and guard_ai != null and autonomous_movement_enabled:
		if guard_ai.update_ai(delta): return
	if defense != null and defense.organized != null and autonomous_movement_enabled:
		if defense.organized.update_actor(self, delta): return
	if escort != null and autonomous_movement_enabled and infection_state == InfectionState.IN_COLLISION:
		escort.update_combat()
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE:
		threat_reaction.cancel_response()
		_stop_movement()
		return
	var navigation_map := navigation_agent.get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return
	if priest_routine != null and defense != null and is_instance_valid(defense.priest_ai) and defense.priest_ai.actor == self:
		if defense.priest_ai.update_priest(delta): return
	if escort != null and escort.update_escort(delta): return
	if (not has_tactical_controller()) and threat_reaction.update_response(delta):
		return
	if guard_patrol!=null and guard_patrol.update_patrol(delta):
		return
	if _using_zone:
		if not is_instance_valid(current_zone) or not current_zone.allows_resident(self) or not current_zone.has_valid_polygon():
			_begin_wait()
			return
		if is_performing_activity:
			_update_zone_activity(delta)
			return
	if not has_destination:
		wait_remaining = maxf(wait_remaining - delta, 0.0)
		if wait_remaining == 0.0:
			_choose_destination(navigation_map)
		return
	var result := _advance_navigation(destination, move_speed, delta)
	if result != NavigationResult.MOVING:
		_begin_wait(result == NavigationResult.ARRIVED)


func _advance_navigation(goal: Vector2, speed: float, delta: float) -> NavigationResult:
	navigation_agent.max_speed = maxf(speed, 0.0)
	navigation_agent.target_desired_distance = maxf(arrival_tolerance, 0.5)
	if global_position.distance_to(goal) <= navigation_agent.target_desired_distance:
		return NavigationResult.ARRIVED
	if global_position.distance_squared_to(progress_position) >= 4.0:
		progress_position = global_position
		stalled_seconds = 0.0
	else:
		stalled_seconds += delta
	if stalled_seconds >= MOVEMENT_STALL_TIMEOUT:
		return NavigationResult.FAILED
	var next_position := navigation_agent.get_next_path_position()
	if navigation_agent.is_navigation_finished():
		return NavigationResult.FAILED
	navigation_agent.velocity = global_position.direction_to(next_position) * maxf(speed, 0.0)
	return NavigationResult.MOVING


func _choose_destination(navigation_map: RID) -> void:
	var points := get_node_or_null(points_of_interest_path) if not points_of_interest_path.is_empty() else null
	var options: Array[Dictionary] = []
	var total_weight := 0.0
	for activity in [Activity.HOME, Activity.WORK, Activity.SOCIAL, Activity.WANDER]:
		var weight := _activity_weight(activity)
		if weight <= 0.0:
			continue
		var candidates: Array[Dictionary] = []
		for path in activity_zone_paths:
			var zone := get_node_or_null(path) as ActivityZone2D if not path.is_empty() else null
			if zone == null or zone.activity != activity or not zone.allows_resident(self):
				continue
			var sample := zone.sample_destination(self, _zone_reservations(zone), null,
				maxf(arrival_tolerance, 0.5) + 1.0, maxf(arrival_tolerance, 0.5) + 1.0)
			if not sample.is_empty():
				candidates.append({"point": sample[0], "zone": zone})
		# Prefer assigned zones; unavailable assignments retain safe marker fallback.
		if candidates.is_empty() and marker_activity_fallback_enabled:
			for candidate in _activity_points(activity, points):
				if _is_destination_valid(candidate.global_position, navigation_map):
					candidates.append({"point": candidate.global_position, "zone": null})
		if not candidates.is_empty():
			options.append({"activity": activity, "weight": weight, "points": candidates})
			total_weight += weight
	if priest_routine != null and priest_routine.routine_enabled:
		options = priest_routine.filter_options(options)
		total_weight = 0.0
		for option in options: total_weight += float(option.weight)
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
	var target := _choose_activity_target(candidates)
	current_zone = target["zone"]
	_using_zone = current_zone != null
	wait_remaining = 0.0
	local_wait_remaining = 0.0
	_last_local_origin = Vector2.INF
	_set_peaceful_destination(target["point"])


func _zone_preference_weight(zone: ActivityZone2D) -> float:
	var weight := 1.0
	if not preferred_district.is_empty() and zone.district_id == preferred_district:
		weight *= maxf(district_zone_preference, 1.0)
	if nearby_zone_distance > 0.0:
		weight /= 1.0 + global_position.distance_to(zone.global_position) / nearby_zone_distance
	return weight


func _choose_activity_target(candidates: Array) -> Dictionary:
	# Neutral assignments retain Stage 2's uniform choice and random sequence.
	if preferred_district.is_empty() and nearby_zone_distance <= 0.0:
		return candidates.pick_random()
	var total := 0.0
	for candidate in candidates:
		total += _zone_preference_weight(candidate["zone"]) if candidate["zone"] != null else 1.0
	var roll := randf() * total
	for candidate in candidates:
		roll -= _zone_preference_weight(candidate["zone"]) if candidate["zone"] != null else 1.0
		if roll < 0.0: return candidate
	return candidates[-1]


func _activity_points(activity: Activity, points: Node) -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	if points == null:
		return result
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
	if is_instance_valid(current_zone) and current_zone.activity == activity and current_zone.duration_override != Vector2.ZERO:
		return current_zone.duration_override
	if priest_routine != null and priest_routine.routine_enabled:
		return priest_routine.activity_duration(current_zone, Vector2(wait_duration_min, wait_duration_max))
	match activity:
		Activity.HOME: return home_duration
		Activity.WORK: return work_duration
		Activity.SOCIAL: return social_duration
		Activity.WANDER: return wander_duration
	return Vector2(wait_duration_min, wait_duration_max)


func _is_destination_valid(point: Vector2, navigation_map: RID) -> bool:
	return not _validated_path_to(point, navigation_map).is_empty()


func _validated_path_to(point: Vector2, navigation_map: RID) -> PackedVector2Array:
	if global_position.distance_to(point) <= maxf(arrival_tolerance, 0.5):
		return PackedVector2Array()
	if NavigationServer2D.map_get_closest_point(navigation_map, point).distance_to(point) > 1.0:
		return PackedVector2Array()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = $CollisionShape2D.shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return PackedVector2Array()
	var path := NavigationServer2D.map_get_path(navigation_map, global_position, point, true, navigation_agent.navigation_layers)
	return path if not path.is_empty() and path[-1].distance_to(point) <= 1.0 else PackedVector2Array()


func _stop_movement() -> void:
	if guard_patrol!=null: guard_patrol.cancel_patrol()
	if _using_zone:
		wait_remaining = 0.0
	_using_zone = false
	current_zone = null
	local_wait_remaining = 0.0
	_last_local_origin = Vector2.INF
	has_destination = false
	current_activity = Activity.NONE
	is_performing_activity = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO


func _begin_wait(arrived: bool = false) -> void:
	var activity := current_activity if arrived else Activity.NONE
	var zone := current_zone if arrived and is_instance_valid(current_zone) else null
	_stop_movement()
	current_zone = zone
	_using_zone = zone != null
	current_activity = activity
	is_performing_activity = activity != Activity.NONE
	var duration := _activity_duration(activity)
	var minimum := maxf(duration.x, 0.0)
	wait_remaining = randf_range(minimum, maxf(duration.y, minimum))
	if current_zone != null:
		_begin_local_pause()


func _local_rules(activity: Activity) -> Vector3:
	if priest_routine != null and priest_routine.routine_enabled:
		var base := _civilian_local_rules(activity)
		return priest_routine.local_rules(current_zone, base)
	return _civilian_local_rules(activity)


func _civilian_local_rules(activity: Activity) -> Vector3:
	match activity:
		Activity.HOME: return home_local_rules
		Activity.WORK: return work_local_rules
		Activity.SOCIAL: return social_local_rules
		Activity.WANDER: return wander_local_rules
	return Vector3.ONE


func _zone_local_speed() -> float:
	var speed := minf(maxf(current_zone.local_move_speed, 0.0), maxf(move_speed, 0.0) * 0.9)
	if priest_routine != null and priest_routine.routine_enabled and priest_routine.zone_territory(current_zone) in [0, 1]:
		speed = minf(speed, maxf(priest_routine.primary_local_speed, 0.0))
	return speed


func _set_peaceful_destination(point: Vector2) -> void:
	destination = point
	navigation_agent.target_position = point
	has_destination = true
	progress_position = global_position
	stalled_seconds = 0.0


func _zone_reservations(zone: ActivityZone2D) -> PackedVector2Array:
	var positions := PackedVector2Array()
	for resident in get_tree().get_nodes_in_group("activity_zone_residents"):
		if resident == self or resident.is_queued_for_deletion() or resident.get_world_2d() != get_world_2d():
			continue
		if is_instance_valid(resident.current_zone) and resident.has_destination and resident.is_available_for_infection() and zone.contains_world_point(resident.destination):
			positions.append(resident.destination)
	return positions


func _begin_local_pause() -> void:
	has_destination = false
	velocity = Vector2.ZERO
	navigation_agent.velocity = Vector2.ZERO
	stalled_seconds = 0.0
	var interval := current_zone.local_pause_duration * maxf(_local_rules(current_activity).y, 0.0)
	var minimum := maxf(interval.x, 0.25)
	local_wait_remaining = randf_range(minimum, maxf(interval.y, minimum))


func _update_zone_activity(delta: float) -> void:
	if not current_zone.contains_world_point(global_position):
		_begin_wait()
		return
	# One activity clock covers every local route and every intentional pause.
	wait_remaining = maxf(wait_remaining - delta, 0.0)
	if wait_remaining == 0.0:
		if priest_routine != null and priest_routine.routine_enabled:
			priest_routine.activity_completed(current_zone)
		_stop_movement()
		return
	_advance_local_zone_cycle(delta)


func _advance_local_zone_cycle(delta: float) -> void:
	if has_destination:
		var result := _advance_navigation(destination, _zone_local_speed(), delta)
		if result != NavigationResult.MOVING:
			_begin_local_pause()
		return
	local_wait_remaining = maxf(local_wait_remaining - delta, 0.0)
	if local_wait_remaining > 0.0:
		return
	var rules := _local_rules(current_activity)
	var probability := clampf(current_zone.local_move_probability * rules.z, 0.0, 1.0)
	if _zone_local_speed() <= 0.0 or randf() >= probability:
		_begin_local_pause()
		return
	var radius := maxf(current_zone.local_move_radius * rules.x, 0.0)
	if randf() < clampf(local_long_move_chance, 0.0, 1.0):
		radius *= 1.8
	var sample := current_zone.sample_local_destination(self, radius,
		maxf(arrival_tolerance * 3.0, 10.0), _last_local_origin, _zone_reservations(current_zone))
	if sample.is_empty():
		_begin_local_pause()
		return
	_last_local_origin = global_position
	_set_peaceful_destination(sample[0])


func _on_navigation_velocity_computed(safe_velocity: Vector2) -> void:
	if not autonomous_movement_enabled or infection_state != InfectionState.AVAILABLE or not (has_destination or threat_reaction.has_route):
		velocity = Vector2.ZERO
		return
	if _using_zone and not is_instance_valid(current_zone):
		velocity = Vector2.ZERO
		return
	if is_performing_activity and is_instance_valid(current_zone) and not threat_reaction.has_route:
		# Bound avoidance/slide displacement by the distance to any polygon edge.
		# Geometry only: no per-frame path or physics-space queries.
		var clearance := maxf(current_zone.distance_to_boundary(global_position) - 0.05, 0.0)
		safe_velocity = safe_velocity.limit_length(clearance / maxf(get_physics_process_delta_time(), 0.000001))
	velocity = safe_velocity
	move_and_slide()


func has_tactical_controller() -> bool:
	if priest_routine != null and defense != null and is_instance_valid(defense.priest_ai) and defense.priest_ai.actor == self and defense.priest_ai.alarm_active():
		return true
	return priest_guard != null or (guard_ai != null and guard_ai.enabled) or (defense != null and defense.organized != null and defense.organized.active())


func get_recognized_threat() -> Node2D:
	return threat_detection.get_recognized_target()


func _on_threat_recognized(zombie: Node2D) -> void:
	if is_available_for_infection():
		if not has_tactical_controller(): threat_reaction.recognize_threat(zombie)
		threat_recognized.emit(zombie)


func _on_warning_attempted(threat_position: Vector2) -> void:
	if is_available_for_infection():
		warning_attempted.emit(self, threat_position)


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

	threat_reaction.interrupt_warning()
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
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
	_stop_movement()
	transformation_timer.wait_time = maxf(transformation_duration, 0.01)
	transformation_timer.start()


func _die() -> void:
	if infection_state == InfectionState.DEAD:
		return

	infection_state = InfectionState.DEAD
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
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

	var starting_encounter := infection_state == InfectionState.AVAILABLE
	if starting_encounter:
		if not has_tactical_controller():
			threat_reaction.seeking_home = true
			threat_reaction.threat_position = zombie.global_position
			local_warning._remember_observation(zombie)
		infection_state = InfectionState.IN_COLLISION
		threat_reaction.cancel_response()
		threat_detection.reset_awareness()
		_begin_wait()
		converted_color = result_color
	if not encounter_participants.has(zombie):
		encounter_participants.append(zombie)
		if priest_routine == null and encounter_attack_timer.is_stopped():
			encounter_attack_timer.start()
	if starting_encounter:
		encounter_started.emit(zombie)
	return true


func is_encounter_owner(zombie: Node2D) -> bool:
	return encounter_participants.has(zombie)


func cancel_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func leave_encounter(zombie: Variant) -> void:
	if is_instance_valid(zombie):
		if not encounter_participants.has(zombie): return
		encounter_participants.erase(zombie)
		if zombie.has_method("on_encounter_ended"): zombie.call("on_encounter_ended", self)
	else:
		# A despawned opponent cannot be passed to a typed Array.has/erase.
		for index in range(encounter_participants.size() - 1, -1, -1):
			if not is_instance_valid(encounter_participants[index]): encounter_participants.remove_at(index)
	if encounter_participants.is_empty():
		encounter_attack_timer.stop()
	if encounter_participants.is_empty() and infection_state == InfectionState.IN_COLLISION:
		infection_state = InfectionState.AVAILABLE
		if not has_tactical_controller(): threat_reaction.request_reassessment()
	elif encounter_participants.is_empty() and infection_state == InfectionState.TRANSFORMING:
		collision_layer = 0
		collision_mask = 0
		$CollisionShape2D.set_deferred("disabled", true)


func _end_encounter() -> void:
	for participant in encounter_participants.duplicate():
		leave_encounter(participant)


func _on_encounter_attack_timer_timeout() -> void:
	if priest_routine != null:
		encounter_attack_timer.stop()
		return
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
	local_warning.clear_report()
	threat_reaction.cancel_response()
	threat_detection.reset_awareness()
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
