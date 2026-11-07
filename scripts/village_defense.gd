extends Node
## Mission-scoped clock and physical queries, never a shared tactical blackboard.
const CORPSE = preload("res://scripts/corpse_perception.gd")
const GUARD = preload("res://scripts/guard_ai.gd")
const ESCORT = preload("res://scripts/civilian_escort.gd")
@export var bell_reach: float = 24.0
@export var bell_interaction_seconds: float = 1.0
@export var safety_spacing: float = 24.0
@export var safety_radius: float = 75.0
var safety_reservations: Dictionary = {}
var has_guards: bool = false
var guard_posts: Array[Vector2] = []
var elapsed: float = 0.0
var alert: Node
var bell: Node2D

func initialize(residents: Array[Node], village_alert: Node) -> void:
	alert = village_alert
	bell = get_parent().get_node_or_null("VillagePointsOfInterest/Bell")
	if bell == null: bell = get_parent().get_node_or_null("PointsOfInterest/Bell")
	if bell == null: bell = get_parent().get_node_or_null("NavigationRegion2D/Solids/Bell")
	for actor in residents:
		actor.defense = self
		var perception = CORPSE.new()
		perception.name = "CorpsePerception"
		actor.add_child(perception)
		if actor.priest_guard != null:
			continue
		if actor.guard_patrol != null:
			has_guards = true
			var ai = actor.get_node_or_null("GuardAI")
			if ai == null:
				ai = GUARD.new()
				ai.name = "GuardAI"
				actor.add_child(ai)
			actor.guard_ai = ai
			var access = actor.guard_patrol._access()
			if access != null:
				var approach: PackedVector2Array = access.world_points()
				if not approach.is_empty() and not guard_posts.has(approach[-1]): guard_posts.append(approach[-1])
		else:
			var escort = actor.get_node_or_null("CivilianEscort")
			if escort == null:
				escort = ESCORT.new()
				escort.name = "CivilianEscort"
				actor.add_child(escort)
			actor.escort = escort

func _physics_process(delta: float) -> void:
	elapsed += delta

func nearby(actor: Node2D, radius: float, mask: int = 8) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var shape = CircleShape2D.new()
	shape.radius = maxf(radius, 0.1)
	var query = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, actor.global_position)
	query.collision_mask = mask
	query.exclude = [actor.get_rid()]
	for hit in actor.get_world_2d().direct_space_state.intersect_shape(query, 64):
		var body = hit.collider
		if body is Node2D and get_parent().is_ancestor_of(body) and not result.has(body): result.append(body)
	return result

func release_safety(actor: Node2D) -> void:
	safety_reservations.erase(actor.get_instance_id())

func reserve_safety(actor: Node2D, marker: Node2D, random: RandomNumberGenerator, local: bool = false, local_radius: float = 40.0, marker_radius: float = INF, allowed: Callable = Callable()) -> Vector2:
	# Movement reservations only, never enemy knowledge or an NPC command bus.
	var reserved = PackedVector2Array()
	for id in safety_reservations.keys():
		var entry: Dictionary = safety_reservations[id]
		var owner = entry.owner.get_ref()
		if not is_instance_valid(owner) or not owner.is_alive() or owner.escort == null or is_instance_valid(owner.escort.leader):
			safety_reservations.erase(id)
		elif id != actor.get_instance_id(): reserved.append(entry.point)
	var zones: Array[Node] = []
	for path in actor.activity_zone_paths:
		var zone = actor.get_node_or_null(path)
		if zone == null or not zone.allows_resident(actor): continue
		if zone.get_node_or_null(zone.location_path) == marker or zone.contains_world_point(marker.global_position): zones.append(zone)
	for attempt in range(40):
		var point: Vector2
		if not zones.is_empty():
			var zone = zones[attempt % zones.size()]
			var sample = zone.sample_local_destination(actor, local_radius, 10.0, Vector2.INF, reserved, random) if local else zone.sample_destination(actor, reserved, random, actor.arrival_tolerance + 1, actor.arrival_tolerance + 1)
			if sample.is_empty(): continue
			point = sample[0]
		else:
			var origin = actor.global_position if local else marker.global_position
			point = origin + Vector2.from_angle(random.randf() * TAU) * sqrt(random.randf()) * (local_radius if local else safety_radius)
			if local and (point.distance_to(marker.global_position) > safety_radius or point.distance_to(actor.global_position) < 10): continue
			var snapped = NavigationServer2D.map_get_closest_point(actor.navigation_agent.get_navigation_map(), point)
			if snapped.distance_to(point) > actor.arrival_tolerance: continue
			point = snapped
		if point.distance_to(marker.global_position) > marker_radius: continue
		var free = true
		for other in reserved:
			if point.distance_to(other) < safety_spacing: free = false
		if not free: continue
		if not (allowed.call(point) if allowed.is_valid() else reachable(actor, point)): continue
		safety_reservations[actor.get_instance_id()] = {"owner": weakref(actor), "point": point}
		return point
	return Vector2.INF

func visible(actor: Node2D, other: Node2D, radius: float) -> bool:
	if not is_instance_valid(other) or actor.global_position.distance_to(other.global_position) > radius: return false
	var ray = PhysicsRayQueryParameters2D.create(actor.global_position, other.global_position, 1, [actor.get_rid()])
	return actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func reachable(actor: Node2D, point: Vector2) -> bool:
	if not point.is_finite(): return false
	if actor.global_position.distance_to(point) <= actor.arrival_tolerance: return true
	return actor._is_destination_valid(point, actor.navigation_agent.get_navigation_map())

func sample_points(actor: Node2D, center: Vector2, radius: float, count: int = 3) -> PackedVector2Array:
	var candidates: Array[Dictionary] = []
	var nav: RID = actor.navigation_agent.get_navigation_map()
	for i in range(12):
		var desired = center + Vector2.from_angle(float(i) * TAU / 12.0) * radius * (0.55 if i % 2 else 1.0)
		var point = NavigationServer2D.map_get_closest_point(nav, desired)
		if point.distance_to(desired) > radius * 0.5 or not reachable(actor, point): continue
		# Prefer a useful view toward the area rather than points behind opaque walls.
		var ray = PhysicsRayQueryParameters2D.create(point, center, 1, [actor.get_rid()])
		var score = point.distance_to(actor.global_position)
		if not actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): score += radius * 2
		candidates.append({"point": point, "score": score, "index": i})
	candidates.sort_custom(func(a, b): return a.score < b.score if a.score != b.score else a.index < b.index)
	var points = PackedVector2Array()
	for candidate in candidates:
		var distinct = true
		for point in points:
			if point.distance_to(candidate.point) < radius * 0.45: distinct = false
		if distinct: points.append(candidate.point)
		if points.size() >= count: break
	return points

func ring(actor: Node2D) -> bool:
	if not can_process() or not is_instance_valid(bell) or not actor.is_available_for_infection() or actor.global_position.distance_to(bell.global_position) > bell_reach:
		return false
	if not bell_visible(actor): return false
	return alert.activate_bell(actor)

func bell_visible(actor: Node2D) -> bool:
	if not is_instance_valid(bell): return false
	var excluded: Array[RID] = [actor.get_rid()]
	if bell is CollisionObject2D: excluded.append(bell.get_rid())
	var ray = PhysicsRayQueryParameters2D.create(actor.global_position, bell.global_position, 1, excluded)
	return actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func alarm_point(actor: Node2D) -> Vector2:
	if not is_instance_valid(bell): return Vector2.INF
	if reachable(actor, bell.global_position): return bell.global_position
	for point in sample_points(actor, bell.global_position, bell_reach, 8):
		if point.distance_to(bell.global_position) <= bell_reach: return point
	return Vector2.INF

func broadcast(sender: Node2D, message: Dictionary, radius: float) -> void:
	if not can_process() or not sender.is_alive() or not sender.local_warning.communication_enabled: return
	# No recursive delivery: recipients only store, relay on their next decision tick.
	for other in nearby(sender, radius):
		if not other.is_alive(): continue
		if other.guard_ai != null: other.guard_ai.receive_message(message, sender)
		elif other.escort != null: other.escort.receive_message(message, sender)

func mobilize_civilians() -> void:
	# Extension hook only: callers must already establish ORGANIZED_DEFENSE.
	if alert.level != alert.Level.ORGANIZED_DEFENSE: return
	for actor in get_parent().villagers:
		if is_instance_valid(actor) and actor.escort != null and actor.is_available_for_infection() and actor.escort.can_recruit():
			actor.escort.arm()
