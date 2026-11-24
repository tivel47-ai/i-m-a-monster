extends RefCounted
## One limited disengagement budget per guard, shared by all assignments.
const BALANCE = preload("res://scripts/mission_one_unit_balance.gd")
const TUNING := BALANCE.CROSSBOW_TACTICS
const TERRITORY_SAMPLE_STEP := 12.0
const ROUTE_TOLERANCE := 8.0

var actor: Node2D
var episode_origin := Vector2.INF
var last_contact := -INF
var spent := 0.0
var next_attempt := 0.0
var goal := Vector2.INF
var hold_position := Vector2.INF
var aim := Vector2.INF
var scope: Array = []
var route := PackedVector2Array()
var route_index := 0
var observations: Dictionary = {}
var next_check := 0.0
var next_observation := 0.0
var settled_at := -INF
var last_step_at := -INF
var previous_position := Vector2.INF
var traveled := 0.0
var reserved := 0.0


func _init(resident: Node2D) -> void:
	actor = resident


func interrupt() -> void:
	if goal.is_finite():
		hold_position = actor.global_position
	goal = Vector2.INF


func note_contact(now: float) -> void:
	if not episode_origin.is_finite():
		episode_origin = actor.global_position
	last_contact = now


func remembers(enemy: Node2D, now: float) -> bool:
	var observation: Dictionary = observations.get(enemy.get_instance_id(), {})
	return not observation.is_empty() and now - observation.time < TUNING.quiet_seconds


func end_if_quiet(now: float, recovery_point: Vector2) -> void:
	if goal.is_finite() or now - last_contact < TUNING.quiet_seconds:
		return
	if recovery_point.is_finite() and actor.global_position.distance_to(recovery_point) > TUNING.protection_offset:
		return
	episode_origin = Vector2.INF
	hold_position = Vector2.INF
	observations.clear()
	spent = 0.0


func can_recover(point: Vector2, now: float, enemies: Array[Node2D], allowed: Callable) -> bool:
	_observe(now, enemies)
	var origin := actor.global_position
	for threat in observations.values():
		if point.distance_to(threat.point) <= TUNING.disengage_distance:
			return false
	if origin.distance_to(point) <= actor.arrival_tolerance:
		return true
	var path: PackedVector2Array = actor._validated_path_to(point, actor.navigation_agent.get_navigation_map())
	var previous := origin
	for waypoint in path:
		if not _safe_segment(previous, waypoint, origin, allowed):
			return false
		previous = waypoint
	return not path.is_empty()


func step(now: float, delta: float, enemies: Array[Node2D], allies: Array[Node2D],
		assignment: Array, allowed: Callable, move: Callable, stop: Callable, decision_interval: float,
		allow_plan := true, trigger_allowed := Callable()) -> bool:
	if now - last_step_at > delta * 1.5:
		interrupt()
	last_step_at = now
	if scope != assignment:
		if goal.is_finite(): stop.call()
		interrupt()
		hold_position = Vector2.INF
		if episode_origin.is_finite() and not scope.is_empty():
			episode_origin = actor.global_position
		scope = assignment
	if goal.is_finite():
		return _advance(now, delta, enemies, allowed, move, stop, decision_interval)
	if enemies.is_empty():
		return false
	note_contact(now)
	if now >= next_observation:
		next_observation = now + decision_interval
		_observe(now, enemies)
	if not allow_plan or now < next_attempt or spent + TUNING.minimum_gain >= TUNING.retreat_budget:
		return false
	var origin := actor.global_position
	if not _in_area(origin, allowed):
		return false
	var danger := false
	for enemy in enemies:
		if (is_instance_valid(enemy) and origin.distance_to(enemy.global_position) <= TUNING.disengage_distance
			and (not trigger_allowed.is_valid() or trigger_allowed.call(enemy.global_position))):
			danger = true
			break
	if not danger:
		return false
	var current := _observe(now, enemies)
	var threat := _closest_threat(origin, current, trigger_allowed)
	if threat.is_empty() or origin.distance_to(threat.point) > TUNING.disengage_distance:
		return false
	next_attempt = now + TUNING.maneuver_interval
	var selected := _protected_route(threat.point, allies, allowed)
	if selected.is_empty():
		selected = _independent_route(threat.point, allowed)
	if selected.is_empty():
		return false
	route = selected.path
	route_index = 0
	goal = route[-1]
	aim = selected.aim
	reserved = selected.length
	spent += reserved
	traveled = 0.0
	previous_position = origin
	next_check = now + decision_interval
	stop.call()
	return _advance(now, delta, enemies, allowed, move, stop, decision_interval)


func _observe(now: float, enemies: Array[Node2D]) -> Array[Dictionary]:
	for id in observations.keys():
		if now - observations[id].time >= TUNING.quiet_seconds:
			observations.erase(id)
	var current: Array[Dictionary] = []
	for enemy in enemies:
		if actor.threat_detection._is_visible_target(enemy):
			var observation := {
				"point": enemy.global_position, "reach": enemy.INFECTION_DISTANCE, "time": now}
			observations[enemy.get_instance_id()] = observation
			current.append(observation)
	return current


func _closest_threat(point: Vector2, threats: Array, allowed := Callable()) -> Dictionary:
	var closest: Dictionary = {}
	var gap := INF
	for threat in threats:
		if allowed.is_valid() and not allowed.call(threat.point):
			continue
		var distance: float = point.distance_squared_to(threat.point)
		if distance < gap:
			gap = distance
			closest = threat
	return closest


func _protected_route(threat: Vector2, allies: Array[Node2D], allowed: Callable) -> Dictionary:
	var best: Dictionary = {}
	for ally in allies:
		if not _protective_ally(ally) or not allowed.call(ally.global_position):
			continue
		var away := threat.direction_to(ally.global_position)
		if away.is_zero_approx():
			continue
		var candidate := _evaluate(ally.global_position + away * TUNING.protection_offset, allowed)
		if not candidate.is_empty() and (best.is_empty() or candidate.score < best.score):
			best = candidate
	return best


func _protective_ally(ally: Node2D) -> bool:
	return (is_instance_valid(ally) and not ally.is_queued_for_deletion() and ally.is_alive()
		and ally.guard_ai != null and ally.guard_ai.enabled and ally.priest_guard == null
		and ally.infection_state != ally.InfectionState.TRANSFORMING and not ally.defense_ranged_weapon
		and ally.guard_variant in [BALANCE.SHIELD, BALANCE.SWORD, BALANCE.SPEAR]
		and ally.guard_ai.state not in [ally.guard_ai.State.RETREAT, ally.guard_ai.State.RAISE_ALARM]
		and ally.interior_building == actor.interior_building
		and actor.defense.visible(actor, ally, TUNING.protection_radius))


func _independent_route(threat: Vector2, allowed: Callable) -> Dictionary:
	var origin := actor.global_position
	var away := threat.direction_to(origin)
	var stride := minf(TUNING.preferred_distance - origin.distance_to(threat), TUNING.retreat_budget - spent)
	var best: Dictionary = {}
	for scale: float in [1.0, 0.55, 0.3]:
		for turn: float in [0.0, PI / 4, -PI / 4, PI / 2, -PI / 2]:
			var candidate := _evaluate(origin + away.rotated(turn) * stride * scale, allowed)
			if not candidate.is_empty() and (best.is_empty() or candidate.score < best.score):
				best = candidate
	return best


func _evaluate(point: Vector2, allowed: Callable) -> Dictionary:
	var origin := actor.global_position
	var budget: float = TUNING.retreat_budget - spent
	var distance := origin.distance_to(point)
	if distance <= actor.arrival_tolerance or distance > budget or not _in_area(point, allowed):
		return {}
	var threats := observations.values()
	var closest_at_start: Vector2 = _closest_threat(origin, threats).point
	var closest_at_end: Vector2 = _closest_threat(point, threats).point
	if point.distance_to(closest_at_end) < origin.distance_to(closest_at_start) + TUNING.minimum_gain:
		return {}
	var firing_point := Vector2.INF
	var firing_distance := INF
	for threat in observations.values():
		var gap: float = point.distance_to(threat.point)
		if gap < firing_distance and gap <= actor.defense_weapon_range and actor.defense._melee_line_clear(actor, point, threat.point):
			firing_point = threat.point
			firing_distance = gap
	if not firing_point.is_finite():
		return {}
	var path: PackedVector2Array = actor._validated_path_to(point, actor.navigation_agent.get_navigation_map())
	if path.is_empty():
		return {}
	var length := 0.0
	var previous := origin
	for waypoint in path:
		length += previous.distance_to(waypoint)
		if length > budget or not _safe_segment(previous, waypoint, origin, allowed):
			return {}
		previous = waypoint
	return {"path": path, "length": length, "aim": firing_point,
		"score": absf(TUNING.preferred_distance - firing_distance) + length * 0.25}


func _in_area(point: Vector2, allowed: Callable) -> bool:
	return episode_origin.distance_to(point) <= TUNING.retreat_budget and allowed.call(point)


func _safe_segment(start: Vector2, end: Vector2, origin: Vector2, allowed: Callable) -> bool:
	if not start.is_equal_approx(end) and not actor.defense._melee_line_clear(actor, start, end):
		return false
	var checks := maxi(ceili(start.distance_to(end) / TERRITORY_SAMPLE_STEP), 1)
	for i in range(1, checks + 1):
		if not _in_area(start.lerp(end, float(i) / checks), allowed):
			return false
	for threat in observations.values():
		var point: Vector2 = threat.point
		var initial := origin.distance_to(point)
		var clearance := minf(initial - 1.0, maxf(threat.reach + actor.navigation_agent.radius, TUNING.disengage_distance))
		if Geometry2D.get_closest_point_to_segment(point, start, end).distance_to(point) < clearance:
			return false
	return true


func _advance(now: float, delta: float, enemies: Array[Node2D], allowed: Callable,
		move: Callable, stop: Callable, decision_interval: float) -> bool:
	var origin := actor.global_position
	var previous_overrun := maxf(traveled - reserved, 0.0)
	traveled += previous_position.distance_to(origin)
	spent += maxf(traveled - reserved, 0.0) - previous_overrun
	previous_position = origin
	while route_index < route.size() and origin.distance_to(route[route_index]) <= ROUTE_TOLERANCE:
		route_index += 1
	if now >= next_check:
		next_check = now + decision_interval
		if not enemies.is_empty():
			note_contact(now)
			_observe(now, enemies)
		var previous := origin
		for index in range(route_index, route.size()):
			var waypoint := route[index]
			if not _safe_segment(previous, waypoint, origin, allowed):
				return _finish(now, stop)
			previous = waypoint
	if (not _in_area(origin, allowed)
		or maxf(reserved - traveled, 0.0) + TUNING.retreat_budget - spent <= actor.guard_ai.movement_speed() * delta):
		return _finish(now, stop)
	var result: int = move.call(goal, delta)
	if result != actor.NavigationResult.MOVING:
		return _finish(now, stop)
	return true


func _finish(now: float, stop: Callable) -> bool:
	stop.call()
	interrupt()
	settled_at = now
	if actor.unit_vision != null:
		actor.unit_vision.face_at_rest(aim - actor.global_position)
	return true
