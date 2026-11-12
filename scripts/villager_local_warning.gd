extends Node2D

enum Knowledge { NORMAL, WARNED, DIRECTLY_AWARE }

@export var communication_enabled: bool = true
@export var hearing_radius: float = 180.0
@export var report_duration: float = 10.0
@export var duplicate_distance: float = 32.0
@export var duplicate_refresh_interval: float = 1.0
## A firsthand witness can call for help while running, without a stationary W roll.
@export var escape_warning_interval: float = 1.0
@export var debug_enabled: bool = true

var reported_position: Vector2
var received_at: float = -1.0
var remaining: float = 0.0
var local_time: float = 0.0
var reports_received: int = 0
var notifications_delivered: int = 0
var firsthand_report: Dictionary = {}
var cleared_incidents: Dictionary = {}
var next_escape_warning: float = 0.0
var sending_escape_warning: bool = false

@onready var villager = get_parent()
@onready var sensor = get_parent().get_node("ThreatDetection")


func _ready() -> void:
	villager.warning_attempted.connect(_on_warning_attempted)
	villager.threat_recognized.connect(_remember_observation)


func _remember_observation(target: Node2D) -> void:
	if villager.defense == null or not sensor._is_visible_target(target): return
	var count := 0
	for enemy in sensor.nearby_threats():
		if sensor._is_visible_target(enemy): count += 1
	firsthand_report = {"incident": target.get_instance_id(), "point": target.global_position, "count": maxi(count, 1), "source": villager.get_instance_id(), "observed_at": villager.defense.elapsed, "credibility": 0.75, "relay": 0, "help": false}
	if villager.escort != null and villager.escort.reporter.has_live_report() and villager.escort.reporter.observe(firsthand_report):
		firsthand_report.witness = true


func _physics_process(delta: float) -> void:
	local_time += maxf(delta, 0.0)
	if not communication_enabled or not _can_receive():
		clear_report()
		if not villager.is_alive():
			set_physics_process(false)
		return
	if remaining > 0:
		remaining = maxf(remaining - delta, 0.0)
		if remaining == 0:
			clear_report()
	_update_escape_warning()
	queue_redraw()


func _update_escape_warning() -> void:
	if is_instance_valid(villager.interior_building): return
	if escape_warning_interval <= 0 or local_time < next_escape_warning or not villager.autonomous_movement_enabled or not villager.is_available_for_infection(): return
	if villager.has_tactical_controller(): return # guards use their own local protocol
	var reaction = villager.threat_reaction
	if not reaction.seeking_home or reaction.report_based or reaction.reaction_state == reaction.Reaction.FROZEN: return
	next_escape_warning = local_time + maxf(escape_warning_interval, duplicate_refresh_interval + 0.01)
	var target = villager.get_recognized_threat()
	if is_instance_valid(target) and sensor._is_visible_target(target): _remember_observation(target)
	var fresh: bool = not firsthand_report.is_empty() and villager.defense.elapsed - float(firsthand_report.observed_at) <= report_duration
	var guard_report: Dictionary = {}
	if villager.escort != null and villager.escort.reporter.has_live_report():
		if villager.escort.reporter.report.get("kind", "") != "corpse":
			guard_report = villager.escort.reporter.report
	if not fresh and guard_report.is_empty(): return
	# This flag is scoped to synchronous delivery, never inherited by recipients.
	sending_escape_warning = true
	if fresh: _deliver_warning(firsthand_report.point)
	if not guard_report.is_empty() and (not fresh or guard_report.incident != firsthand_report.incident):
		_deliver_warning(guard_report.point, guard_report)
	sending_escape_warning = false


func _can_receive() -> bool:
	return not villager.is_queued_for_deletion() and villager.current_health > 0 and villager.infection_state in [
		villager.InfectionState.AVAILABLE, villager.InfectionState.IN_COLLISION]


func has_report() -> bool:
	return communication_enabled and remaining > 0 and _can_receive()


func get_knowledge() -> Knowledge:
	if is_instance_valid(villager.get_recognized_threat()):
		return Knowledge.DIRECTLY_AWARE
	return Knowledge.WARNED if has_report() else Knowledge.NORMAL


func _valid_position(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	var navigation_map: RID = villager.get_world_2d().navigation_map
	return NavigationServer2D.map_get_iteration_id(navigation_map) > 0 and NavigationServer2D.map_get_closest_point(
		navigation_map, point).distance_to(point) <= 64.0


func _on_warning_attempted(source: Node2D, point: Vector2) -> void:
	if not communication_enabled or source != villager or not villager.is_available_for_infection():
		return
	var reaction = villager.threat_reaction
	if reaction.report_based or not reaction.episode_active or not reaction.warning_sent or not _valid_position(point):
		return
	var target = villager.get_recognized_threat()
	if is_instance_valid(target) and sensor._is_visible_target(target): _remember_observation(target)
	next_escape_warning = local_time + maxf(escape_warning_interval, duplicate_refresh_interval + 0.01)
	_deliver_warning(point)


func _deliver_warning(point: Vector2, guard_report: Dictionary = {}) -> void:
	# Both a completed W action and an escape cry use the same local delivery.
	var listeners: Array[Node2D] = []
	var distances := {}
	for candidate in get_tree().get_nodes_in_group("civilian_warning_receivers"):
		if candidate == villager or not candidate is Node2D or candidate.is_queued_for_deletion():
			continue
		if candidate.get_world_2d() != villager.get_world_2d():
			continue
		if not guard_report.is_empty() and candidate.guard_ai == null: continue
		var receiver = candidate.get_node_or_null("LocalWarning")
		var distance: float = candidate.global_position.distance_to(villager.global_position)
		if receiver == null or distance > receiver.hearing_radius: continue
		listeners.append(candidate)
		if candidate.guard_ai != null and villager.escort != null and not villager.escort.reporter.report.is_empty():
			distance = villager.escort.reporter.contact_distance(candidate.guard_ai)
		distances[candidate] = distance
	listeners.sort_custom(func(a, b): return distances[a] < distances[b])
	for candidate in listeners:
		var receiver = candidate.get_node("LocalWarning")
		if receiver != null and receiver.receive_warning(villager, point, guard_report):
			notifications_delivered += 1


func receive_warning(source: Variant, point: Vector2, guard_report: Dictionary = {}) -> bool:
	if villager.priest_guard != null: return false
	if not communication_enabled or not _can_receive() or not is_instance_valid(source) or source == villager:
		return false
	if source.is_queued_for_deletion() or not source.is_in_group("civilian_warning_receivers") or not source.is_available_for_infection():
		return false
	if source.get_world_2d() != villager.get_world_2d() or source.threat_reaction.report_based:
		return false
	if not source.local_warning.sending_escape_warning and (not source.threat_reaction.episode_active or not source.threat_reaction.warning_sent):
		return false
	if hearing_radius <= 0 or source.global_position.distance_to(villager.global_position) > hearing_radius or not _valid_position(point):
		return false
	var incoming: Dictionary = source.local_warning.firsthand_report if guard_report.is_empty() else guard_report
	if not incoming.is_empty() and cleared_incidents.has(incoming.incident) and float(incoming.observed_at) <= float(cleared_incidents[incoming.incident]): return false
	if villager.guard_ai != null and not incoming.is_empty():
		var accepted: bool = villager.guard_ai.receive_message(incoming, source)
		if accepted:
			reports_received += 1
		return accepted
	if not guard_report.is_empty(): return false
	if not _accept_report(point, incoming): return false
	if villager.defense != null and not source.local_warning.firsthand_report.is_empty():
		if villager.escort != null: villager.escort.learn_site_danger(source.local_warning.firsthand_report)
		villager.defense.alert.report_delivered(source, villager, source.local_warning.firsthand_report)
	return true


func hear_break_in(incident: int, origin: Vector2, approach: Vector2) -> bool:
	if not communication_enabled or not _can_receive() or hearing_radius <= 0.0 or is_instance_valid(villager.interior_building):
		return false
	if villager.global_position.distance_to(origin) > hearing_radius or not _valid_position(approach):
		return false
	if villager.guard_ai != null:
		if villager.guard_ai.hear_break_in(incident, approach):
			reports_received += 1
			return true
		return false
	if villager.priest_guard != null:
		return false
	return _accept_report(origin)


func _accept_report(point: Vector2, incoming: Dictionary = {}) -> bool:
	if has_report() and point.distance_to(reported_position) <= maxf(duplicate_distance, 0) and local_time - received_at < maxf(duplicate_refresh_interval, 0):
		return false
	reported_position = point
	received_at = local_time
	remaining = maxf(report_duration, 0)
	if incoming.has("observed_at") and villager.defense != null:
		remaining = minf(remaining, maxf(report_duration - (villager.defense.elapsed - float(incoming.observed_at)), 0.0))
	if remaining == 0:
		clear_report()
		return false
	reports_received += 1
	villager.threat_reaction.respond_to_report(point)
	queue_redraw()
	return true


func clear_report() -> void:
	remaining = 0
	received_at = -1
	reported_position = Vector2.ZERO
	villager.threat_reaction.finish_heard_report()
	queue_redraw()


func _draw() -> void:
	if is_instance_valid(villager.interior_building): return
	if villager.escort != null and villager.escort.reporter.goal.is_finite() and villager.escort.reporter.has_live_report() and (debug_enabled or sensor.debug_enabled):
		draw_string(ThemeDB.fallback_font, Vector2(6, -32), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.ORANGE)
	if has_report() and (debug_enabled or sensor.debug_enabled):
		draw_rect(Rect2(-10, -24, 4, 4), Color.ORANGE, false, 1.0)
