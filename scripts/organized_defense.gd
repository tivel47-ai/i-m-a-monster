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

func eligible(actor: Variant) -> bool:
	# Mixed physical queries also return zombies and scenery. Only registered
	# mission residents have the infection-state contract used below.
	if not is_instance_valid(actor) or not (actor is Node): return false
	if not controllers.has(actor.get_instance_id()): return false
	return not actor.is_queued_for_deletion() and actor.is_alive() and actor.infection_state != actor.InfectionState.TRANSFORMING

func inside(point: Vector2, extent: float = -1.0) -> bool:
	return point.distance_to(center) <= (radius if extent < 0 else extent) and (point - center).dot(forward) >= -0.01

func sector(point: Vector2) -> int:
	var offset = point - center
	var angle = atan2(offset.dot(forward.orthogonal()), maxf(offset.dot(forward), 0.01))
	return clampi(int(floor((angle + PI / 2.0) / (PI / 3.0))), 0, 2)

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
	var polygon = PackedVector2Array([to_local(center)])
	for i in range(33): polygon.append(to_local(center + forward.rotated(-PI / 2.0 + PI * float(i) / 32.0) * radius))
	draw_colored_polygon(polygon, Color(0.2, 0.6, 1.0, 0.08))
	polygon.append(to_local(center))
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
			var returning_nearby = actor.global_position.distance_to(center) <= radius + spacing and controller(actor).mode in ["return", "travel", "position"]
			if within or settling.has(id) or returning_nearby or service.elapsed - float(outside_since.get(id, service.elapsed)) < contraction_delay:
				capacity_population += 1
		var behavior = controller(actor)
		if (within or actor.global_position.distance_to(center) <= radius + intercept_distance) and (actor.is_in_collision() or behavior.immediate_until > service.elapsed): immediate = true
	capacity_population = maxi(capacity_population, physical_population)
	if immediate: return # Only danger at the church, never a remote battle elsewhere.
	var wanted = maxf(minimum_radius, sqrt(float(capacity_population) * spacing * spacing * 2.0 / PI) + spacing)
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
	var result: Array[Vector2] = []
	var step = maxf(spacing, actor.navigation_agent.radius * 2.0 + 2.0)
	var count = int(ceil(extent / step))
	var nav = actor.navigation_agent.get_navigation_map()
	var key = Vector3(extent, step, NavigationServer2D.map_get_iteration_id(nav))
	if _capacity_cache.has(key): return _capacity_cache[key]
	var origin = NavigationServer2D.map_get_closest_point(nav, center)
	for y in range(0, count + 1):
		for x in range(-count, count + 1):
			var point = center + forward * (step * (y + 0.5)) + forward.orthogonal() * (step * (x + 0.5 * (y % 2)))
			if not inside(point, extent): continue
			if NavigationServer2D.map_get_closest_point(nav, point).distance_to(point) > 1.0: continue
			var query = PhysicsShapeQueryParameters2D.new()
			query.shape = actor.get_node("CollisionShape2D").shape
			query.transform = Transform2D(0, point)
			query.collision_mask = 1
			if not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			var path = NavigationServer2D.map_get_path(nav, origin, point, true, actor.navigation_agent.navigation_layers)
			if path.is_empty() or path[-1].distance_to(point) > 1.0: continue
			result.append(point)
	_capacity_cache[key] = result
	return result

func position_for(actor: Node2D, anchor: Vector2 = Vector2.INF, limit: float = INF, rebalance: bool = false) -> Vector2:
	var id = actor.get_instance_id()
	if not rebalance and places.has(id) and inside(places[id]) and (not anchor.is_finite() or places[id].distance_to(anchor) <= limit): return places[id]
	var best = Vector2.INF
	var best_score = INF
	var behavior = controller(actor)
	var nearby_residents = service.nearby(actor, maxf(radius * 2, spacing))
	for point in slots:
		if anchor.is_finite() and point.distance_to(anchor) > limit: continue
		if behavior != null and behavior.failed_point(point): continue
		var free = true
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
		var preferred = radius * (0.75 if actor.guard_ai != null else 0.35)
		if actor.priest_routine != null: preferred = spacing
		var value = actor.global_position.distance_to(point) + absf(point.distance_to(center) - preferred)
		if arrived(actor): value += absi(sector(point) - sector(actor.global_position)) * spacing
		# A local hole becomes more attractive than an overcrowded position. No
		# global formation reset, and travel cost prevents exchanging equal slots.
		for other in places:
			if other != id: value += maxf(spacing * 2.0 - places[other].distance_to(point), 0.0)
		if anchor.is_finite(): value += point.distance_to(anchor)
		if value < best_score:
			best = point
			best_score = value
	if best.is_finite(): places[id] = best
	return best

func release_place(actor: Node) -> void:
	places.erase(actor.get_instance_id())

func update_actor(actor: Node2D, delta: float) -> bool:
	if not active() or not eligible(actor): return false
	check_arrival(actor)
	var behavior = controller(actor)
	return behavior.update(delta) if behavior != null else false
