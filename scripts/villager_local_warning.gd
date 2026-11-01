extends Node2D

enum Knowledge { NORMAL, WARNED, DIRECTLY_AWARE }

@export var communication_enabled: bool = true
@export var hearing_radius: float = 180.0
@export var report_duration: float = 10.0
@export var duplicate_distance: float = 32.0
@export var duplicate_refresh_interval: float = 1.0
@export var debug_enabled: bool = false

var reported_position: Vector2
var received_at: float = -1.0
var remaining: float = 0.0
var local_time: float = 0.0
var reports_received: int = 0
var notifications_delivered: int = 0

@onready var villager = get_parent()
@onready var sensor = get_parent().get_node("ThreatDetection")


func _ready() -> void:
	villager.warning_attempted.connect(_on_warning_attempted)


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
	queue_redraw()


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
	# Delivery is event-driven and single-hop; receivers never broadcast here.
	for candidate in get_tree().get_nodes_in_group("civilian_warning_receivers"):
		if candidate == villager or not candidate is Node2D or candidate.is_queued_for_deletion():
			continue
		if candidate.get_world_2d() != villager.get_world_2d():
			continue
		var receiver = candidate.get_node_or_null("LocalWarning")
		if receiver != null and receiver.receive_warning(villager, point):
			notifications_delivered += 1


func receive_warning(source: Variant, point: Vector2) -> bool:
	if not communication_enabled or not _can_receive() or not is_instance_valid(source) or source == villager:
		return false
	if source.is_queued_for_deletion() or not source.is_in_group("civilian_warning_receivers") or not source.is_available_for_infection():
		return false
	if source.get_world_2d() != villager.get_world_2d() or source.threat_reaction.report_based or not source.threat_reaction.episode_active or not source.threat_reaction.warning_sent:
		return false
	if hearing_radius <= 0 or source.global_position.distance_to(villager.global_position) > hearing_radius or not _valid_position(point):
		return false
	if has_report() and point.distance_to(reported_position) <= maxf(duplicate_distance, 0) and local_time - received_at < maxf(duplicate_refresh_interval, 0):
		return false
	reported_position = point
	received_at = local_time
	remaining = maxf(report_duration, 0)
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
	if villager.threat_reaction.report_based:
		villager.threat_reaction.cancel_response()
		villager.wait_remaining = 0
	queue_redraw()


func _draw() -> void:
	if has_report() and (debug_enabled or sensor.debug_enabled):
		draw_rect(Rect2(-10, -24, 4, 4), Color.ORANGE, false, 1.0)
