extends Node2D

signal warning_attempted(threat_position: Vector2)

enum Reaction { NONE, FLEEING, SEEKING_SHELTER, WARNING, FROZEN }

@export var reactions_enabled: bool = true
@export var flee_weight: float = 50.0
@export var shelter_weight: float = 25.0
@export var warning_weight: float = 20.0
@export var frozen_weight: float = 5.0
@export var fleeing_speed: float = 85.0
@export var escape_distance: float = 180.0
@export var threat_clearance: float = 40.0
@export var warning_duration: float = 1.0
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
var reaction_random := RandomNumberGenerator.new()

@onready var villager = get_parent()
@onready var sensor = get_parent().get_node("ThreatDetection")


func _ready() -> void:
	reaction_random.randomize()


func choose_reaction() -> Reaction:
	var weights := [maxf(flee_weight, 0), maxf(shelter_weight, 0), maxf(warning_weight, 0), maxf(frozen_weight, 0)]
	var total: float = weights.reduce(func(a: float, b: float): return a + b, 0.0)
	var roll := reaction_random.randf() * total
	for index in range(weights.size()):
		roll -= weights[index]
		if roll < 0:
			return index + 1 as Reaction
	return Reaction.FLEEING


func recognize_threat(target: Node2D) -> void:
	if not reactions_enabled or not villager.autonomous_movement_enabled or not villager.is_available_for_infection():
		return
	if not sensor._is_visible_target(target):
		return
	if episode_active:
		# Personal recognition supersedes a static report without rerolling.
		if report_based:
			refresh_remaining = 0
		report_based = false
		episode_targets[target.get_instance_id()] = true
		_consider_target(target)
		return
	if cooldown_remaining > 0 or handled_targets.has(target.get_instance_id()):
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
	_enter_reaction(choose_reaction())


func respond_to_report(point: Vector2) -> void:
	if not reactions_enabled or not villager.autonomous_movement_enabled or not villager.is_available_for_infection():
		return
	var direct: Node2D = villager.get_recognized_threat()
	if is_instance_valid(direct) and sensor._is_visible_target(direct):
		recognize_threat(direct)
		return
	if episode_active:
		if report_based and point.distance_to(threat_position) >= maxf(threat_movement_threshold, 1):
			threat_position = point
			refresh_remaining = 0
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
	_enter_reaction(Reaction.FLEEING)


func update_response(delta: float) -> bool:
	if not reactions_enabled:
		cancel_response()
		return false
	cooldown_remaining = maxf(0, cooldown_remaining - delta)
	var visible := _visible_threats()
	if visible.is_empty() and not (report_based and villager.local_warning.has_report()):
		safe_elapsed += delta
	else:
		safe_elapsed = 0
	if safe_elapsed >= maxf(safety_timeout, 0.1):
		handled_targets.clear()
	if not episode_active:
		var recognized: Node2D = villager.get_recognized_threat()
		if is_instance_valid(recognized):
			recognize_threat(recognized)
		if not episode_active and villager.local_warning.has_report():
			respond_to_report(villager.local_warning.reported_position)
		if not episode_active:
			if reassessment_remaining > 0:
				reassessment_remaining = maxf(0, reassessment_remaining - delta)
				villager._stop_movement()
				return reassessment_remaining > 0 and safe_elapsed < maxf(safety_timeout, 0.1)
			return false
	if report_based and not villager.local_warning.has_report():
		cancel_response()
		villager.wait_remaining = 0
		return false
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
	if reaction_state in [Reaction.WARNING, Reaction.FROZEN]:
		action_remaining = maxf(0, action_remaining - delta)
		if action_remaining == 0:
			if reaction_state == Reaction.WARNING and not warning_sent and not report_based:
				warning_sent = true
				warning_attempted.emit(threat_position)
				if not villager.is_available_for_infection():
					return true
			_enter_reaction(Reaction.FLEEING)
	elif has_route:
		var result: int = villager._advance_navigation(route_destination, fleeing_speed, delta)
		if result != villager.NavigationResult.MOVING:
			has_route = false
			_stop_velocity()
			if result == villager.NavigationResult.FAILED:
				_enter_reaction(Reaction.FLEEING)
			elif reaction_state == Reaction.FLEEING and (not visible.is_empty() or (report_based and villager.local_warning.has_report())):
				# Continue past this waypoint without waiting for the refresh interval.
				route_attempts = 0
				_plan_route()
	queue_redraw()
	return true


func _visible_threats() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group("player_units"):
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
	reaction_state = state
	has_route = false
	_stop_velocity()
	refresh_remaining = maxf(reassess_interval, 0.1)
	if state == Reaction.WARNING:
		action_remaining = maxf(warning_duration, 0)
	elif state == Reaction.FROZEN:
		freeze_used = true
		var minimum := maxf(frozen_duration.x, 0)
		action_remaining = reaction_random.randf_range(minimum, maxf(frozen_duration.y, minimum))
	else:
		_plan_route()
	queue_redraw()


func _plan_route() -> void:
	if route_attempts >= maxi(max_route_attempts, 1):
		# Each call has a finite candidate set; renew the batch instead of stalling.
		route_attempts = 0
	route_attempts += 1
	var choices: Array[Vector2] = []
	if reaction_state == Reaction.SEEKING_SHELTER:
		var home := villager.get_node_or_null(villager.home_point_path) if not villager.home_point_path.is_empty() else null
		if home is Marker2D:
			choices.append(home.global_position)
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
		if gain < 10 or point.distance_to(threat_position) < maxf(threat_clearance, 1) or not _route_is_safe(point):
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
		elif not freeze_used:
			_enter_reaction(Reaction.FROZEN)
		return
	route_destination = best[0]
	route_threat_position = threat_position
	villager.navigation_agent.target_position = route_destination
	villager.progress_position = villager.global_position
	villager.stalled_seconds = 0
	has_route = true


func _route_is_safe(point: Vector2) -> bool:
	var navigation_map: RID = villager.navigation_agent.get_navigation_map()
	if not villager._is_destination_valid(point, navigation_map):
		return false
	var path := NavigationServer2D.map_get_path(navigation_map, villager.global_position, point, true, villager.navigation_agent.navigation_layers)
	var dangers: Array[Vector2] = [threat_position]
	for candidate in _visible_threats():
		dangers.append(candidate.global_position)
	for danger in dangers:
		var clearance := minf(maxf(threat_clearance, 1), maxf(villager.global_position.distance_to(danger) - 4, 1))
		for index in range(1, path.size()):
			if Geometry2D.get_closest_point_to_segment(danger, path[index - 1], path[index]).distance_to(danger) < clearance:
				return false
	return true


func _stop_velocity() -> void:
	villager.velocity = Vector2.ZERO
	villager.navigation_agent.velocity = Vector2.ZERO


func _finish_episode() -> void:
	var completed_targets := episode_targets.duplicate()
	cancel_response()
	if safe_elapsed < maxf(safety_timeout, 0.1):
		handled_targets.merge(completed_targets)
	else:
		handled_targets.clear()
	cooldown_remaining = maxf(response_cooldown, 0)
	villager.wait_remaining = 0


func cancel_response() -> void:
	episode_active = false
	report_based = false
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


func interrupt_warning() -> void:
	if episode_active and reaction_state == Reaction.WARNING:
		warning_sent = true
		_enter_reaction(Reaction.FLEEING)


func _draw() -> void:
	if reaction_state == Reaction.NONE or not (debug_enabled or sensor.debug_enabled):
		return
	var labels := ["", "F", "S", "W", "Z"]
	var colors := [Color.WHITE, Color.CYAN, Color.CORNFLOWER_BLUE, Color.ORANGE, Color.MEDIUM_PURPLE]
	draw_string(ThemeDB.fallback_font, Vector2(6, -20), labels[reaction_state], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, colors[reaction_state])
