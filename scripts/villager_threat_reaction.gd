extends Node2D

signal warning_attempted(threat_position: Vector2)

enum Reaction { NONE, FLEEING, SEEKING_SHELTER, WARNING, FROZEN, REPORTING }

@export var reactions_enabled: bool = true
@export var flee_weight: float = 50.0
@export var shelter_weight: float = 25.0
## Obsolete serialized W/weight settings, retained only for old resources.
@export_storage var warning_weight: float = 20.0
@export_storage var frozen_weight: float = 5.0
@export_range(0.0, 1.0) var hesitation_probability: float = 0.05
## Post-flight reporting weight; the initial choice preserves W/Z odds.
@export_range(0.0, 1.0) var reporting_share_of_escape: float = 0.5
@export var fleeing_speed: float = 85.0
@export var escape_distance: float = 180.0
@export var threat_clearance: float = 40.0
@export var home_approach_radius: float = 36.0
@export_storage var warning_duration: float = 1.0 # obsolete; no warning timer
@export var frozen_duration: Vector2 = Vector2(1.0, 3.0)
@export var safety_timeout: float = 3.0
## Reassessment interval, not an end condition while danger remains visible.
@export var max_response_duration: float = 12.0
@export var response_cooldown: float = 4.0
@export var reassess_interval: float = 0.75
@export var threat_movement_threshold: float = 32.0
## Attempts per planning batch; later scheduled batches remain permitted.
@export var max_route_attempts: int = 4
@export var debug_enabled: bool = true

var reaction_state: Reaction = Reaction.NONE
var has_route: bool = false
var route_destination: Vector2
var episode_active: bool = false
var threat_target: Node2D
var threat_position: Vector2
var route_threat_position: Vector2
var threat_id: int = 0
var episode_targets: Dictionary = {}
var handled_targets: Dictionary = {}
var episode_elapsed: float = 0.0
var safe_elapsed: float = 0.0
var action_remaining: float = 0.0
var cooldown_remaining: float = 0.0
var refresh_remaining: float = 0.0
var reassessment_remaining: float = 0.0
var route_attempts: int = 0
var freeze_used: bool = false
var warning_sent: bool = false
var report_based: bool = false
var after_flight: Reaction = Reaction.NONE
## Surviving an encounter changes the civilian's plan for the rest of this mission.
## Cancelling a movement/combat response must not erase this personal decision.
var seeking_home: bool = false
var sheltered_at_home: bool = false
var home_destination: Vector2 = Vector2.INF
var home_retry_remaining: float = 0.0
var reaction_random := RandomNumberGenerator.new()

@onready var villager = get_parent()
@onready var sensor = get_parent().get_node("ThreatDetection")


func _ready() -> void:
	reaction_random.randomize()


func choose_reaction(_allow_reporting: bool = false) -> Reaction:
	return Reaction.FROZEN if reaction_random.randf() < hesitation_probability else Reaction.FLEEING


func recognize_threat(target: Node2D) -> void:
	if _guard_controls_reaction() or not reactions_enabled or not villager.autonomous_movement_enabled or not villager.is_available_for_infection():
		return
	if not sensor._is_visible_target(target):
		return
	if report_based:
		cancel_response()
	seeking_home = true
	sheltered_at_home = false
	if episode_active:
		episode_targets[target.get_instance_id()] = true
		_consider_target(target)
		return
	# A returning monster is immediate danger even during the old recovery pause.
	if handled_targets.has(target.get_instance_id()):
		return
	villager._stop_movement()
	threat_target = target
	threat_position = target.global_position
	threat_id = target.get_instance_id()
	episode_targets = {threat_id: true}
	episode_active = true
	report_based = false
	episode_elapsed = 0
	safe_elapsed = 0
	route_attempts = 0
	freeze_used = false
	warning_sent = false
	reassessment_remaining = 0
	var selected := choose_reaction()
	after_flight = Reaction.NONE
	_enter_reaction(selected)


func _can_report(incident: int) -> bool:
	return villager.escort != null and villager.escort.reporter.can_start(incident)


func _start_reporting() -> bool:
	if villager.escort == null: return false
	if is_instance_valid(threat_target) and sensor._is_visible_target(threat_target):
		villager.local_warning._remember_observation(threat_target)
	return villager.escort.reporter.observe(villager.local_warning.firsthand_report)


func start_guard_run(point: Vector2) -> void:
	cancel_response()
	villager._stop_movement()
	seeking_home = true
	episode_active = true
	threat_position = point
	_enter_reaction(Reaction.REPORTING)


func finish_guard_run(retry_after_flight: bool = false) -> void:
	if reaction_state != Reaction.REPORTING: return
	cancel_response()
	villager._stop_movement()
	var target: Node2D = villager.get_recognized_threat()
	if sensor._is_visible_target(target):
		episode_active = true
		episode_elapsed = 0
		safe_elapsed = 0
		route_attempts = 0
		freeze_used = false
		after_flight = Reaction.REPORTING if retry_after_flight else Reaction.SEEKING_SHELTER
		_consider_target(target)
		_enter_reaction(Reaction.FLEEING)
	else:
		_update_home(0.0)


func respond_to_report(point: Vector2) -> void:
	if _guard_controls_reaction() or not reactions_enabled or not villager.autonomous_movement_enabled or not villager.is_available_for_infection():
		return
	seeking_home = true
	var direct: Node2D = villager.get_recognized_threat()
	if is_instance_valid(direct) and sensor._is_visible_target(direct):
		recognize_threat(direct)
		return
	if episode_active:
		if report_based and not point.is_equal_approx(threat_position):
			threat_position = point
			home_retry_remaining = 0
		return
	villager._stop_movement()
	episode_active = true
	report_based = true
	threat_target = null
	threat_position = point
	threat_id = 0
	episode_targets.clear()
	episode_elapsed = 0
	safe_elapsed = 0
	route_attempts = 0
	freeze_used = false
	warning_sent = true
	reassessment_remaining = 0
	reaction_state = Reaction.SEEKING_SHELTER
	home_retry_remaining = 0
	queue_redraw()


func finish_heard_report() -> void:
	if not report_based:
		return
	report_based = false
	episode_active = false
	home_retry_remaining = 0


func _guard_controls_reaction() -> bool:
	return villager.guard_ai != null and villager.guard_ai.enabled


func update_response(delta: float) -> bool:
	if _guard_controls_reaction(): return false
	if not reactions_enabled:
		cancel_response()
		return false
	cooldown_remaining = maxf(0, cooldown_remaining - delta)
	if reaction_state == Reaction.REPORTING:
		# The reporter owns this route and can request a new escape if it becomes unsafe.
		_stop_velocity()
		return true
	if report_based:
		if villager.local_warning.has_report():
			episode_elapsed += delta
			return _update_home(delta)
		finish_heard_report()
	var visible := _visible_threats()
	if visible.is_empty():
		safe_elapsed += delta
	else:
		safe_elapsed = 0
	if safe_elapsed >= maxf(safety_timeout, 0.1):
		handled_targets.clear()
	if not episode_active:
		var recognized: Node2D = villager.get_recognized_threat()
		if is_instance_valid(recognized):
			recognize_threat(recognized)
		if not episode_active and not seeking_home and villager.local_warning.has_report():
			respond_to_report(villager.local_warning.reported_position)
			if report_based:
				return _update_home(delta)
		if not episode_active:
			if reassessment_remaining > 0:
				reassessment_remaining = maxf(0, reassessment_remaining - delta)
				villager._stop_movement()
				if reassessment_remaining > 0 and safe_elapsed < maxf(safety_timeout, 0.1): return true
			return _update_home(delta) if seeking_home else false
	episode_elapsed += delta
	if safe_elapsed >= maxf(safety_timeout, 0.1):
		_finish_episode()
		return true
	# A time limit is a reassessment boundary, never evidence that danger ended.
	if episode_elapsed >= maxf(max_response_duration, 0.1):
		episode_elapsed = 0
		route_attempts = 0
		refresh_remaining = 0
		if reaction_state != Reaction.FLEEING or not has_route:
			_enter_reaction(Reaction.FLEEING)
	if not sensor._is_valid_zombie(threat_target):
		threat_target = null
	refresh_remaining = maxf(0, refresh_remaining - delta)
	if refresh_remaining == 0:
		if not report_based:
			for candidate in visible:
				_consider_target(candidate)
			if is_instance_valid(threat_target) and sensor._is_visible_target(threat_target):
				threat_position = threat_target.global_position
		if reaction_state in [Reaction.FLEEING, Reaction.SEEKING_SHELTER]:
			if (not has_route and reaction_state == Reaction.FLEEING) or (has_route and villager.global_position.distance_to(route_destination) > maxf(villager.arrival_tolerance, 0.5) and (
				threat_position.distance_to(route_threat_position) >= maxf(threat_movement_threshold, 1)
				or not _route_is_safe(route_destination))):
				_plan_route()
		refresh_remaining = maxf(reassess_interval, 0.1)
	if reaction_state == Reaction.FROZEN:
		action_remaining = maxf(0, action_remaining - delta)
		if action_remaining == 0:
			_enter_reaction(Reaction.FLEEING)
	elif has_route:
		var result: int = villager._advance_navigation(route_destination, fleeing_speed, delta)
		if result != villager.NavigationResult.MOVING:
			has_route = false
			_stop_velocity()
			if result == villager.NavigationResult.FAILED:
				_enter_reaction(Reaction.FLEEING)
			elif reaction_state == Reaction.FLEEING and not visible.is_empty():
				# Continue past this waypoint without waiting for the refresh interval.
				route_attempts = 0
				_plan_route()
	queue_redraw()
	return true


func _visible_threats() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in sensor.nearby_threats():
		if candidate is Node2D and sensor._is_visible_target(candidate):
			result.append(candidate)
	return result


func _consider_target(candidate: Node2D) -> void:
	if not is_instance_valid(threat_target) or not sensor._is_visible_target(threat_target) or (
		villager.global_position.distance_to(candidate.global_position) + 25 < villager.global_position.distance_to(threat_target.global_position)):
		threat_target = candidate
		threat_id = candidate.get_instance_id()
		episode_targets[threat_id] = true
		threat_position = candidate.global_position


func _enter_reaction(state: Reaction) -> void:
	# Legacy W requests no longer create a stationary action.
	if state == Reaction.WARNING: state = Reaction.FLEEING
	reaction_state = state
	has_route = false
	_stop_velocity()
	refresh_remaining = maxf(reassess_interval, 0.1)
	if state == Reaction.FROZEN:
		freeze_used = true
		var minimum := maxf(frozen_duration.x, 0)
		action_remaining = reaction_random.randf_range(minimum, maxf(frozen_duration.y, minimum))
	elif state != Reaction.REPORTING:
		_plan_route()
	queue_redraw()


func _plan_route() -> void:
	if route_attempts >= maxi(max_route_attempts, 1):
		# Each call has a finite candidate set; renew the batch instead of stalling.
		route_attempts = 0
	route_attempts += 1
	var choices: Array[Vector2] = []
	var own_home := Vector2.INF
	if reaction_state == Reaction.SEEKING_SHELTER:
		var home := villager.get_node_or_null(villager.home_point_path) if not villager.home_point_path.is_empty() else null
		if home is Marker2D:
			own_home = home.global_position
			choices.append(own_home)
		var points := villager.get_node_or_null(villager.points_of_interest_path) if not villager.points_of_interest_path.is_empty() else null
		if points != null:
			for marker in points.get_children():
				if marker is Marker2D and marker.is_in_group("civilian_shelter_points") and not choices.has(marker.global_position):
					choices.append(marker.global_position)
	else:
		var away: Vector2 = threat_position.direction_to(villager.global_position)
		if away.is_zero_approx():
			away = Vector2.RIGHT
		var navigation_map: RID = villager.navigation_agent.get_navigation_map()
		for distance in [maxf(escape_distance, 40), maxf(escape_distance * 0.5, 40)]:
			for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.57, -1.57]:
				var raw: Vector2 = villager.global_position + away.rotated(angle) * distance
				var point := NavigationServer2D.map_get_closest_point(navigation_map, raw)
				if point.distance_to(raw) <= 48:
					choices.append(point)
	var best: Array[Vector2] = []
	var best_score := -INF
	var current_distance: float = villager.global_position.distance_to(threat_position)
	for point in choices:
		var gain: float = point.distance_to(threat_position) - current_distance
		if point == own_home:
			if _safe_route_length(point, true, true) == INF: continue
		elif gain < 10 or point.distance_to(threat_position) < maxf(threat_clearance, 1) or not _route_is_safe(point):
			continue
		if reaction_state == Reaction.SEEKING_SHELTER:
			best = [point]
			break
		var score: float = gain - villager.global_position.distance_to(point) * 0.15
		if score > best_score:
			best_score = score
			best = [point]
	if best.is_empty():
		has_route = false
		_stop_velocity()
		if reaction_state == Reaction.SEEKING_SHELTER:
			_enter_reaction(Reaction.FLEEING)
		return
	route_destination = best[0]
	route_threat_position = threat_position
	villager.navigation_agent.target_position = route_destination
	villager.progress_position = villager.global_position
	villager.stalled_seconds = 0
	has_route = true


func _route_is_safe(point: Vector2, remember_last_position: bool = true) -> bool:
	return _safe_route_length(point, remember_last_position) < INF


func _safe_route_length(point: Vector2, remember_last_position: bool = true, clear_destination: bool = false) -> float:
	if not point.is_finite(): return INF
	var navigation_map: RID = villager.navigation_agent.get_navigation_map()
	var distance: float = villager.global_position.distance_to(point)
	var path := PackedVector2Array()
	if distance > villager.arrival_tolerance:
		path = villager._validated_path_to(point, navigation_map)
		if path.is_empty(): return INF
	var dangers: Array[Vector2] = []
	if remember_last_position: dangers.append(threat_position)
	for candidate in _visible_threats():
		dangers.append(candidate.global_position)
	for danger in dangers:
		if clear_destination and point.distance_to(danger) < threat_clearance:
			return INF
		var clearance := minf(maxf(threat_clearance, 1), maxf(villager.global_position.distance_to(danger) - 4, 1))
		for index in range(1, path.size()):
			if Geometry2D.get_closest_point_to_segment(danger, path[index - 1], path[index]).distance_to(danger) < clearance:
				return INF
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length if not path.is_empty() else distance


func _stop_velocity() -> void:
	villager.velocity = Vector2.ZERO
	villager.navigation_agent.velocity = Vector2.ZERO


func _finish_episode() -> void:
	var warn_guard := false
	if reaction_state == Reaction.FLEEING and after_flight != Reaction.SEEKING_SHELTER:
		var observation: Dictionary = villager.local_warning.firsthand_report
		if _can_report(int(observation.get("incident", 0))):
			var weight := maxf(flee_weight, 0) * clampf(reporting_share_of_escape, 0, 1)
			warn_guard = after_flight == Reaction.REPORTING or reaction_random.randf() * (weight + maxf(shelter_weight, 0)) < weight
	var completed_targets := episode_targets.duplicate()
	cancel_response()
	if safe_elapsed < maxf(safety_timeout, 0.1):
		handled_targets.merge(completed_targets)
	else:
		handled_targets.clear()
	cooldown_remaining = maxf(response_cooldown, 0)
	villager.wait_remaining = 0
	if warn_guard and _start_reporting(): return
	_update_home(0.0)


func _update_home(delta: float) -> bool:
	# Both a heard warning and recovery from an encounter use the assigned home.
	if villager.has_destination or villager.current_activity != villager.Activity.NONE:
		villager._stop_movement()
	reaction_state = Reaction.SEEKING_SHELTER
	home_retry_remaining = maxf(home_retry_remaining - delta, 0.0)
	var report: Dictionary = villager.local_warning.firsthand_report
	var remember_last = villager.local_warning.has_report() or (not report.is_empty() and villager.defense != null
		and villager.defense.elapsed - float(report.observed_at) <= villager.local_warning.report_duration)
	if home_retry_remaining == 0 and home_destination.is_finite():
		home_retry_remaining = maxf(reassess_interval, 0.1)
		if _safe_route_length(home_destination, remember_last, true) == INF:
			has_route = false
			sheltered_at_home = false
			home_destination = Vector2.INF
			if villager.defense != null: villager.defense.release_safety(villager)
	if not has_route:
		_stop_velocity()
		if home_destination.is_finite() and villager.global_position.distance_to(home_destination) <= villager.arrival_tolerance:
			sheltered_at_home = true
			queue_redraw()
			return true
		if home_retry_remaining > 0: return true
		home_retry_remaining = maxf(reassess_interval, 0.1)
		var home = villager.get_node_or_null(villager.home_point_path) if not villager.home_point_path.is_empty() else null
		if not home is Node2D: return true
		var point: Vector2 = home.global_position
		if villager.defense != null:
			var safe := func(candidate: Vector2) -> bool: return _safe_route_length(candidate, remember_last, true) < INF
			point = villager.defense.reserve_safety(villager, home, reaction_random, false, 40.0, maxf(home_approach_radius, 0.0), safe)
		elif _safe_route_length(point, remember_last, true) == INF:
			point = Vector2.INF
		if not point.is_finite():
			return true
		home_destination = point
		route_destination = point
		villager.navigation_agent.target_position = point
		villager.progress_position = villager.global_position
		villager.stalled_seconds = 0
		has_route = true
	var result: int = villager._advance_navigation(home_destination, fleeing_speed, delta)
	if result != villager.NavigationResult.MOVING:
		has_route = false
		_stop_velocity()
		sheltered_at_home = result == villager.NavigationResult.ARRIVED
		if not sheltered_at_home:
			home_destination = Vector2.INF
			if villager.defense != null: villager.defense.release_safety(villager)
	queue_redraw()
	return true


func cancel_response() -> void:
	if reaction_state == Reaction.REPORTING and villager.escort != null:
		villager.escort.reporter.cancel()
	if villager.defense != null and seeking_home: villager.defense.release_safety(villager)
	if not villager.is_alive() or villager.infection_state == villager.InfectionState.TRANSFORMING:
		seeking_home = false
	home_destination = Vector2.INF
	sheltered_at_home = false
	home_retry_remaining = 0.0
	episode_active = false
	report_based = false
	after_flight = Reaction.NONE
	reaction_state = Reaction.NONE
	has_route = false
	threat_target = null
	threat_id = 0
	episode_targets.clear()
	action_remaining = 0
	reassessment_remaining = 0
	_stop_velocity()
	queue_redraw()


func request_reassessment() -> void:
	if reactions_enabled:
		handled_targets.clear()
		cooldown_remaining = 0
		reassessment_remaining = maxf(safety_timeout, 0.1)
		villager.wait_remaining = 0

func complete_investigation(incident: int, resolved: Array = []) -> bool:
	if not villager.is_available_for_infection() or villager.get_recognized_threat() != null: return false
	var known = resolved.duplicate()
	if not known.has(incident): known.append(incident)
	if villager.escort != null and not villager.escort.reported_danger.is_empty() and not known.has(int(villager.escort.reported_danger.incident)): return false
	var firsthand: Dictionary = villager.local_warning.firsthand_report
	if not firsthand.is_empty() and not known.has(int(firsthand.incident)): return false
	for id in known: villager.local_warning.cleared_incidents[id] = villager.defense.elapsed
	villager.local_warning.clear_report()
	villager.local_warning.firsthand_report.clear()
	cancel_response()
	seeking_home = false
	handled_targets.clear()
	cooldown_remaining = 0.0
	villager._stop_movement()
	villager.wait_remaining = 0.0
	return true


func interrupt_warning() -> void:
	if episode_active and reaction_state == Reaction.WARNING:
		warning_sent = true
		_enter_reaction(Reaction.FLEEING)


func _draw() -> void:
	if reaction_state in [Reaction.NONE, Reaction.REPORTING] or not (debug_enabled or sensor.debug_enabled):
		return
	var labels := ["", "F", "S", "W", "Z"]
	var colors := [Color.WHITE, Color.CYAN, Color.CORNFLOWER_BLUE, Color.ORANGE, Color.MEDIUM_PURPLE]
	draw_string(ThemeDB.fallback_font, Vector2(6, -20), labels[reaction_state], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, colors[reaction_state])
