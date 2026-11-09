extends Node2D
## Shared geometry and capacity. This component never distributes enemy coordinates.
const DEFENDER = preload("res://scripts/organized_defender.gd")
@export var arrival_radius: float = 65.0
@export var spacing: float = 30.0
@export var minimum_radius: float = 65.0
@export var contraction_delay: float = 8.0
@export var intercept_distance: float = 55.0
@export var assistance_distance: float = 100.0
@export var decision_interval: float = 0.35
@export var failed_route_memory: float = 6.0
@export var assistance_switch_margin: int = 2
@export var church_marker_path: NodePath
@export var church_building_path: NodePath
@export var outward_direction: Vector2 = Vector2.DOWN
@export var debug_enabled: bool = false:
	set(value):
		debug_enabled = value
		queue_redraw()
var residents: Array[Node] = []
var members: Dictionary = {}
var places: Dictionary = {}
var controllers: Dictionary = {}
var outside_since: Dictionary = {}
var settling: Dictionary = {}
var center: Vector2
var forward: Vector2 = Vector2.DOWN
var radius: float = 65.0
var low_density: float = 0.0
var physical_population: int = 0
var capacity_population: int = 0
var configured: bool = false
var arrival_marker: Node2D
var slots: Array[Vector2] = []
var _next_refresh: float = 0.0
var _last_refresh: float = 0.0
var _started: bool = false
var _next_transfer: float = 0.0
var _slot_radius: float = -1.0
var _capacity_cache: Dictionary = {}
@onready var service = get_parent()

func initialize(actors: Array[Node]) -> void:
	residents = actors.duplicate()
	var map = service.get_parent()
	if not church_marker_path.is_empty(): arrival_marker = map.get_node_or_null(church_marker_path)
	if arrival_marker == null: arrival_marker = map.get_node_or_null("VillagePointsOfInterest/Church")
	if arrival_marker == null: arrival_marker = map.get_node_or_null("PointsOfInterest/Church")
	if arrival_marker == null: return # No church in the small test map; keep its previous AI.
	center = arrival_marker.global_position
	var building = map.get_node_or_null(church_building_path) if not church_building_path.is_empty() else map.get_node_or_null("NavigationRegion2D/Buildings/Public/Church")
	forward = outward_direction.normalized()
	if building != null: forward = building.global_position.direction_to(center)
	if forward.is_zero_approx(): forward = Vector2.DOWN
	configured = true
	radius = maxf(minimum_radius, spacing * 2.0)
	for actor in residents:
		controllers[actor.get_instance_id()] = DEFENDER.new(self, actor)

func active() -> bool:
	return configured and is_instance_valid(service.alert) and service.alert.level == service.alert.Level.ORGANIZED_DEFENSE

func register_resident(actor: Node) -> void:
	if residents.has(actor): return
	residents.append(actor)
	if configured:
		controllers[actor.get_instance_id()] = DEFENDER.new(self, actor)

func eligible(actor: Variant) -> bool:
	# Mixed physical queries also return zombies and scenery. Only registered
	# mission residents have the infection-state contract used below.
	if not is_instance_valid(actor) or not (actor is Node): return false
	if not controllers.has(actor.get_instance_id()): return false
	return not actor.is_queued_for_deletion() and actor.is_alive() and actor.infection_state != actor.InfectionState.TRANSFORMING

func sector_rects(extent: float) -> Array[Rect2]:
	var side := extent * 0.65
	var front := extent * 0.55
	var width := spacing * 2.0
	var back := -spacing * 1.5
	return [
		Rect2(-side - width, back, width, front - back),
		Rect2(-side, front, side * 2.0, width),
		Rect2(side, back, width, front - back),
	]

func formation_local(point: Vector2) -> Vector2:
	var offset := point - center
	return Vector2(offset.dot(forward.orthogonal()), offset.dot(forward))

func formation_world(point: Vector2) -> Vector2:
	return center + forward.orthogonal() * point.x + forward * point.y

func inside(point: Vector2, margin: float = 0.0) -> bool:
	var local := formation_local(point)
	for rect in sector_rects(radius):
		if rect.grow(margin).has_point(local): return true
	# The priest and his two protectors stand between the three lines.
	return Rect2(-spacing * 1.5, -spacing * 0.5, spacing * 3.0, spacing).grow(margin).has_point(local)

func sector(point: Vector2) -> int:
	var local := formation_local(point)
	var rects := sector_rects(radius)
	var best := 0
	var distance := INF
	for i in rects.size():
		var rect := rects[i]
		var gap := local.distance_squared_to(local.clamp(rect.position, rect.end))
		if gap < distance:
			best = i
			distance = gap
	return best

func central_role(actor: Node2D) -> bool:
	return actor.priest_routine != null or actor.priest_guard != null

func controller(actor: Node) -> RefCounted:
	return controllers.get(actor.get_instance_id()) if is_instance_valid(actor) else null

func arrived(actor: Node) -> bool:
	return is_instance_valid(actor) and members.has(actor.get_instance_id())

func check_arrival(actor: Node2D) -> void:
	if not active() or not eligible(actor) or arrived(actor): return
	if not service.visible(actor, arrival_marker, arrival_radius): return
	var id = actor.get_instance_id()
	members[id] = weakref(actor)
	settling[id] = true
	if actor.escort != null:
		actor.escort.arm(true)
		if is_instance_valid(actor.escort.leader): actor.escort.release("physical church arrival")
	_next_refresh = 0.0

func _physics_process(_delta: float) -> void:
	if not active(): return
	if not _started:
		_started = true
		_last_refresh = service.elapsed
		for behavior in controllers.values(): behavior.activate()
	for actor in residents:
		if eligible(actor): check_arrival(actor)
	if service.elapsed < _next_refresh: return
	var elapsed = maxf(service.elapsed - _last_refresh, 0.0)
	_last_refresh = service.elapsed
	_next_refresh = service.elapsed + maxf(decision_interval, 0.05)
	refresh(elapsed)
	if debug_enabled: queue_redraw()

func _draw() -> void:
	if not debug_enabled or not active(): return
	for rect in sector_rects(radius):
		var polygon := PackedVector2Array()
		for point: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			polygon.append(to_local(formation_world(point)))
		draw_colored_polygon(polygon, Color(0.2, 0.6, 1.0, 0.08))
		polygon.append(polygon[0])
		draw_polyline(polygon, Color(0.2, 0.6, 1.0, 0.65), 1.5)
	draw_arc(to_local(center), arrival_radius, 0, TAU, 48, Color(0.2, 1.0, 0.4, 0.5))
	for point in places.values(): draw_circle(to_local(point), 3.0, Color(0.2, 0.6, 1.0, 0.8))

func refresh(delta: float) -> void:
	var representative: Node2D
	for actor in residents:
		if eligible(actor):
			representative = actor
			break
	for id in controllers.keys():
		if not eligible(controllers[id].actor):
			controllers.erase(id)
			members.erase(id)
			places.erase(id)
			outside_since.erase(id)
			settling.erase(id)
	residents = residents.filter(func(actor): return eligible(actor))
	if representative == null: return
	if NavigationServer2D.map_get_iteration_id(representative.navigation_agent.get_navigation_map()) == 0: return
	if slots.is_empty():
		slots = build_slots(representative, radius)
		_slot_radius = radius
	physical_population = 0
	capacity_population = 0
	var immediate = false
	for actor in residents:
		var id = actor.get_instance_id()
		var within = inside(actor.global_position)
		if within: physical_population += 1 # All living residents, including priest and personal guards.
		if arrived(actor):
			if within:
				outside_since.erase(id)
				settling.erase(id)
			elif not outside_since.has(id): outside_since[id] = service.elapsed
			var returning_nearby = inside(actor.global_position, spacing) and controller(actor).mode in ["return", "travel", "position"]
			if within or settling.has(id) or returning_nearby or service.elapsed - float(outside_since.get(id, service.elapsed)) < contraction_delay:
				capacity_population += 1
		var behavior = controller(actor)
		if (within or inside(actor.global_position, intercept_distance)) and (actor.is_in_collision() or behavior.immediate_until > service.elapsed): immediate = true
	capacity_population = maxi(capacity_population, physical_population)
	if immediate: return # Only danger at the church, never a remote battle elsewhere.
	var wanted = maxf(minimum_radius, sqrt(float(capacity_population)) * spacing)
	var candidate_slots = build_slots(representative, wanted)
	# Bounded work per refresh, not a maximum resident capacity. Obstructed maps grow progressively.
	for attempt in range(6):
		if candidate_slots.size() >= capacity_population: break
		wanted += spacing
		candidate_slots = build_slots(representative, wanted)
	if candidate_slots.size() < capacity_population:
		wanted = maxf(wanted, radius + spacing)
		candidate_slots = build_slots(representative, wanted)
	if wanted < radius - spacing * 0.5:
		low_density += delta
		if low_density < contraction_delay: return
	elif wanted <= radius:
		low_density = 0.0
		if _slot_radius == radius: return
	else: low_density = 0.0
	radius = wanted
	slots = candidate_slots
	_slot_radius = radius
	# Keep every still-valid reservation. Invalid outer places are reacquired locally.
	for id in places.keys():
		if not inside(places[id]): places.erase(id)
	# Reserve the support group's physical space before ordinary arrivals fill
	# the rear. Its movement and combat still belong to PriestGuard.
	for resident in residents:
		if resident.priest_routine == null or not arrived(resident): continue
		var priest_place = position_for(resident)
		if not priest_place.is_finite(): continue
		for protector in residents:
			if protector.priest_guard != null and arrived(protector):
				position_for(protector, priest_place, protector.priest_guard.protection_radius * 0.8)

func build_slots(actor: Node2D, extent: float) -> Array[Vector2]:
	var step := maxf(spacing, actor.navigation_agent.radius * 2.0 + 2.0)
	var nav: RID = actor.navigation_agent.get_navigation_map()
	var key := Vector3(extent, step, NavigationServer2D.map_get_iteration_id(nav))
	if _capacity_cache.has(key): return _capacity_cache[key]
	var candidates: Array[Vector2] = [center, formation_world(Vector2(-step, 0)), formation_world(Vector2(step, 0))]
	for rect in sector_rects(extent):
		var columns := maxi(1, int(floor(rect.size.x / step)))
		var rows := maxi(1, int(floor(rect.size.y / step)))
		var size := Vector2(columns - 1, rows - 1) * step
		for row in rows:
			for column in columns:
				candidates.append(formation_world(rect.get_center() - size * 0.5 + Vector2(column, row) * step))
	var result: Array[Vector2] = []
	var origin := NavigationServer2D.map_get_closest_point(nav, center)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = actor.get_node("CollisionShape2D").shape
	query.collision_mask = 1
	for point in candidates:
		if NavigationServer2D.map_get_closest_point(nav, point).distance_to(point) > 1.0: continue
		query.transform = Transform2D(0, point)
		if not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		var path := NavigationServer2D.map_get_path(nav, origin, point, true, actor.navigation_agent.navigation_layers)
		if path.is_empty() or path[-1].distance_to(point) > 1.0: continue
		result.append(point)
	_capacity_cache[key] = result
	return result

func central_slot(point: Vector2) -> bool:
	return Rect2(-spacing * 1.5, -spacing * 0.5, spacing * 3.0, spacing).has_point(formation_local(point))

func front_rank(point: Vector2, side: int) -> float:
	var local := formation_local(point)
	if side == 1: return local.y
	return absf(local.x)

func position_for(actor: Node2D, anchor: Vector2 = Vector2.INF, limit: float = INF, rebalance: bool = false, allow_transfer: bool = false) -> Vector2:
	var id := actor.get_instance_id()
	var previous: Vector2 = places.get(id, Vector2.INF)
	if not rebalance and previous.is_finite() and (not anchor.is_finite() or previous.distance_to(anchor) <= limit): return previous
	var central := central_role(actor)
	var own := sector(previous) if previous.is_finite() else -1
	var counts := [0, 0, 0]
	for other in places:
		if other != id and not central_slot(places[other]): counts[sector(places[other])] += 1
	var best := previous if rebalance else Vector2.INF
	var best_score := INF
	var behavior = controller(actor)
	var nearby_residents = service.nearby(actor, assistance_distance + spacing)
	for point in slots:
		if central != central_slot(point): continue
		if anchor.is_finite() and point.distance_to(anchor) > limit: continue
		if behavior != null and behavior.failed_point(point): continue
		var side := sector(point)
		if rebalance and own >= 0:
			if side != own:
				if not allow_transfer or service.elapsed < _next_transfer or absi(side - own) != 1 or counts[own] <= counts[side]: continue
			elif front_rank(point, side) <= front_rank(previous, own) + 1.0: continue
		var free := true
		for other in places:
			if other != id and places[other].distance_to(point) < spacing * 0.9:
				free = false
				break
		if not free: continue
		for other in nearby_residents:
			if eligible(other) and other.global_position.distance_to(point) < spacing * 0.65 and other.global_position.distance_to(point) < actor.global_position.distance_to(point):
				free = false
				break
		if not free or not service.reachable(actor, point): continue
		if rebalance and behavior != null and not behavior.safe_path(point): continue
		var value := actor.global_position.distance_to(point)
		if central:
			var preferred := center
			if actor.priest_guard != null:
				var offset := -spacing if actor.priest_guard.slot == 0 else spacing
				preferred = formation_world(Vector2(offset, 0))
			value += point.distance_to(preferred) * 4.0
		else:
			value += counts[side] * spacing * 4.0 - front_rank(point, side)
		if value < best_score:
			best = point
			best_score = value
	if best.is_finite():
		places[id] = best
		if rebalance and own >= 0 and sector(best) != own: _next_transfer = service.elapsed + 1.0
	return best

func release_place(actor: Node) -> void:
	places.erase(actor.get_instance_id())

func update_actor(actor: Node2D, delta: float) -> bool:
	if not active() or not eligible(actor): return false
	check_arrival(actor)
	var behavior = controller(actor)
	return behavior.update(delta) if behavior != null else false
