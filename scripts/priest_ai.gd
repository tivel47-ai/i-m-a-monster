extends Node
## ALARM owns the priest's route. OrganizedDefense owns all church mobilization.
const MORALE = preload("res://scripts/priest_morale.gd")

@export_group("Gathering (provisional)")
@export var gathering_radius: float = 105.0
@export var gathering_spacing: float = 25.0
@export var site_marker_radius: float = 75.0
@export var gathering_recheck: float = 0.5

@export_group("Morale")
@export var alarm_morale_radius: float = 120.0
@export var defense_morale_radius: float = 185.0
@export var residual_seconds: float = 10.0
## Provisional reduction of ordinary panic probability under ALARM.
@export_range(0.0, 0.95) var alarm_calming: float = 0.4

var actor: Node2D
var service: Node
var morale: RefCounted
var site: Node2D
var church: Node2D
var square: Node2D
var members: Dictionary = {}
var next_gathering: Dictionary = {}
var next_plan: float = 0.0
var destination := Vector2.INF
var started: bool = false

func initialize(priest: Node2D, defense: Node) -> void:
	actor = priest
	service = defense
	morale = MORALE.new(self)
	church = service.organized.arrival_marker
	var points = actor.get_node_or_null(actor.points_of_interest_path) if not actor.points_of_interest_path.is_empty() else null
	if points != null: square = points.get_node_or_null("Square")
	actor.died.connect(_source_lost)
	actor.converted.connect(_source_lost)
	actor.tree_exiting.connect(_clear)
	service.alert.level_changed.connect(_alert_changed)

func _source_lost(_resident: Node2D) -> void:
	_clear()

func _clear() -> void:
	morale.coverage.clear()
	clear_gathering()

func _alert_changed(_previous: int, level: int) -> void:
	if level != service.alert.Level.ALARM: clear_gathering()

func clear_gathering() -> void:
	for id in members.keys(): release_member(id)
	next_gathering.clear()
	site = null

func release_member(id: int) -> void:
	var assignment: Dictionary = members[id]
	members.erase(id)
	if not is_instance_valid(service): return
	var resident = assignment.owner.get_ref()
	# A civilian still sheltering at the same site can keep their current safety
	# reservation as an ordinary shelter position after the gathering dissolves.
	if alarm_active() and is_instance_valid(resident) and not resident.is_queued_for_deletion() \
		and resident.is_available_for_infection() and resident.escort.safety_marker == site \
		and not is_instance_valid(resident.escort.leader) and not resident.threat_reaction.seeking_home \
		and not resident.threat_reaction.episode_active and in_site(site, resident.global_position):
		return
	var reservation: Dictionary = service.safety_reservations.get(id, {})
	if reservation.get("point") == assignment.point: service.safety_reservations.erase(id)

func alarm_active() -> bool:
	return is_instance_valid(actor) and actor.is_alive() and is_instance_valid(service) \
		and is_instance_valid(service.alert) and service.alert.level == service.alert.Level.ALARM

func in_site(marker: Node2D, point: Vector2) -> bool:
	if not is_instance_valid(marker): return false
	var routine = actor.priest_routine
	var paths = routine.chapel_zone_paths if marker == church else routine.public_zone_paths
	for path in paths:
		var zone = routine.get_node_or_null(path)
		if zone != null and zone.contains_world_point(point): return true
	return point.distance_to(marker.global_position) <= site_marker_radius

func safe_site(marker: Node2D) -> bool:
	return is_instance_valid(marker) and not actor.escort.site_is_unsafe(marker) \
		and actor.threat_reaction._safe_route_length(marker.global_position, false, true) < INF

func update_priest(delta: float) -> bool:
	if not alarm_active(): return false
	if not started:
		started = true
		actor.threat_reaction.cancel_response()
		actor._stop_movement()
	if service.elapsed >= next_plan:
		next_plan = service.elapsed + maxf(gathering_recheck, 0.1)
		actor.escort.observe_site_danger()
		if not is_instance_valid(site) or not safe_site(site):
			clear_gathering()
			# Keep the public place already reached. Otherwise prefer the church.
			for marker in [square, church] if in_site(square, actor.global_position) else [church, square]:
				if safe_site(marker):
					site = marker
					break
		if is_instance_valid(site): destination = site.global_position
		else: destination = Vector2.INF
	if not destination.is_finite():
		actor._stop_movement()
		return true
	if actor.escort.move_to(destination, delta) == actor.NavigationResult.FAILED:
		actor._stop_movement()
		clear_gathering()
		destination = Vector2.INF
	return true

func can_gather(resident: Node2D) -> bool:
	if not alarm_active() or not actor.is_available_for_infection() or not is_instance_valid(site):
		return false
	if not in_site(site, actor.global_position) or not service.visible(actor, site, INF): return false
	if not resident.autonomous_movement_enabled or not resident.is_available_for_infection(): return false
	var escort = resident.escort
	return escort != null and escort.can_recruit() and escort.mode == escort.Mode.INDEPENDENT \
		and not is_instance_valid(escort.leader) and escort.safety_marker == site and escort.safety_point.is_finite() \
		and not resident.threat_reaction.seeking_home and not resident.threat_reaction.episode_active \
		and resident.get_recognized_threat() == null and in_site(site, resident.global_position) \
		and not escort.site_is_unsafe(site) and service.visible(resident, actor, gathering_radius)

func refresh(residents: Array[Node]) -> void:
	morale.refresh(residents)
	for id in members.keys():
		var resident = members[id].owner.get_ref()
		if not is_instance_valid(resident) or resident.is_queued_for_deletion() or not can_gather(resident):
			release_member(id)
	for id in next_gathering.keys():
		if service.elapsed >= float(next_gathering[id]): next_gathering.erase(id)

func update_member(escort: Node, delta: float) -> bool:
	var resident: Node2D = escort.actor
	var id := resident.get_instance_id()
	if not can_gather(resident):
		if members.has(id): release_member(id)
		return false
	var joined := members.has(id)
	if not joined and resident.global_position.distance_to(escort.safety_point) > resident.arrival_tolerance:
		return false
	var anchor: Vector2 = actor.global_position
	if not joined or escort.safety_point.distance_to(anchor) > gathering_radius:
		if service.elapsed < float(next_gathering.get(id, 0.0)): return false
		next_gathering[id] = service.elapsed + maxf(gathering_recheck, 0.1)
		var allowed := func(point: Vector2) -> bool:
			return point.distance_to(anchor) >= gathering_spacing and in_site(site, point) \
				and resident.threat_reaction._safe_route_length(point, false, true) < INF
		var point: Vector2 = service.reserve_safety(resident, site, escort.rng, false, 0.0, INF, allowed,
			anchor, gathering_radius, gathering_spacing)
		if not point.is_finite(): return false
		escort.safety_point = point
		escort.idle_walking = false
		members[id] = {"owner": weakref(resident), "point": point}
		# A nearby prior route may still own the agent's target.
		escort.goal = Vector2.INF
	if resident.threat_reaction._safe_route_length(escort.safety_point, false, true) == INF:
		resident._stop_movement()
		return true
	var result = escort.move_to(escort.safety_point, delta, escort.idle_speed)
	if result == resident.NavigationResult.FAILED:
		release_member(id)
		resident._stop_movement()
	return true

func calming(resident: Node2D) -> float:
	if service.alert.level == service.alert.Level.ALARM and morale.supports(resident):
		return alarm_calming
	return 0.0

func steadfast(resident: Node2D) -> bool:
	return service.organized.active() and morale.supports(resident)
