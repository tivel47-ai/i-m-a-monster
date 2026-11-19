extends Node2D
## Mission-owned lifecycle. Timers run with the pausable physics simulation.

const SECTION = preload("res://scripts/last_stand_barricade.gd")
const SQUAD = preload("res://scripts/reinforcement_squad.gd")
const PRIEST_SIGNAL_SECONDS := 10.0
const RESIDENT_SIGNAL_SECONDS := 20.0
const TRAVEL_SECONDS := 90.0

enum Wave { UNSENT, TRAVELING, ARRIVED, CANCELLED }

@export var worker_hp_per_second := 6.0
@export var work_spacing := 24.0
@export var work_reach := 4.0
@export var retry_seconds := 0.75
@export var defense_spacing := 22.0
@export var village_territory: Rect2
@export var beacon_position: Vector2

var mission: Node2D
var defense: Node
var formation: Node
var church: InteractiveBuilding
var squad: Node
var residents: Array[Node] = []
var sections: Array[StaticBody2D] = []
var assignments: Dictionary = {}
var worker_retry: Dictionary = {}
var total_max_hp := 0.0
var construction_enabled := false
var signal_ready := false
var operator: CharacterBody2D
var beacon_lit := false
var church_posts_active := false
var wave := Wave.UNSENT
var signal_remaining := 0.0
var travel_remaining := 0.0
var next_update := 0.0
var signal_started_frame := -1
var defense_bounds: Rect2
var defense_edges: Array[Vector3] = []
var door_posts := PackedVector2Array()


func initialize(owner_map: Node2D, service: Node) -> void:
	mission = owner_map
	defense = service
	formation = defense.organized
	residents = mission.villagers.duplicate()
	for actor in residents:
		actor.died.connect(remove_worker)
		actor.converted.connect(remove_worker)
	for building in mission.buildings:
		if building.get_parent().get_meta("building_type", "") == "church":
			church = building
			break
	for child in $Barricades.get_children():
		if child.get_script() == SECTION:
			sections.append(child)
			total_max_hp += child.max_hp
			child.health_changed.connect(_section_changed.bind(child))
	squad = $Reinforcements
	squad.initialize(self)
	if church == null or not formation.configured or total_max_hp <= 0.0:
		push_error("Last Stand requires a church, organized defense, and positive barricade capacity.")
		set_physics_process(false)
		return
	church.signal_operator_entered.connect(_on_operator_entered)
	_configure_defense_bounds()
	defense.last_stand = self
	process_physics_priority = -5


func living_resident(actor: Variant) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.is_alive()


func supports(actor: Node2D) -> bool:
	return (beacon_lit and living_resident(actor) and actor.defense == defense
		and village_territory.has_point(to_local(actor.global_position))
		and (residents.has(actor) or actor.reinforcement_squad == squad))


func _configure_defense_bounds() -> void:
	defense_bounds = Rect2(church.layout.exterior(), Vector2.ZERO)
	for section in sections:
		for end: float in [-0.5, 0.5]:
			defense_bounds = defense_bounds.expand(section.to_global(Vector2(section.length * end, 0)))
		var direction: Vector2 = section.global_transform.y.normalized()
		if section.defender_side != 0:
			direction = -direction
		var edge: float = direction.dot(section.global_position) + section.thickness * 0.5 + 9.0
		defense_edges.append(Vector3(direction.x, direction.y, edge))


func inside_defenses(point: Vector2, margin := 0.0) -> bool:
	if not defense_bounds.grow(margin).has_point(point):
		return false
	for edge in defense_edges:
		if point.x * edge.x + point.y * edge.y < edge.z - margin:
			return false
	return true


func defense_side(point: Vector2) -> int:
	var closest := INF
	var side := 1
	for section in sections:
		var local: Vector2 = section.to_local(point)
		var distance := local.distance_squared_to(Vector2(clampf(local.x, -section.length * 0.5, section.length * 0.5), 0))
		if distance < closest:
			closest = distance
			side = section.side
	return side


func defense_ranks(step: float) -> Array[PackedVector2Array]:
	var ranks: Array[PackedVector2Array] = []
	var upper_edge := Vector2(defense_bounds.position.x, defense_bounds.position.y + step * 0.5)
	for rank in range(3):
		# The deeper gap leaves room for a defender to pass lengthwise
		# between ranks already in position.
		var inset := step * (rank * 1.5 + 0.5)
		var anchors := PackedVector2Array()
		var directions := PackedVector2Array()
		for edge in defense_edges:
			var inward := Vector2(edge.x, edge.y)
			anchors.append(inward * (edge.z + inset))
			directions.append(inward.orthogonal())
		var corners := PackedVector2Array()
		corners.append(Geometry2D.line_intersects_line(upper_edge, Vector2.RIGHT, anchors[0], directions[0]))
		for i in range(1, anchors.size()):
			corners.append(Geometry2D.line_intersects_line(anchors[i - 1], directions[i - 1], anchors[i], directions[i]))
		corners.append(Geometry2D.line_intersects_line(anchors[-1], directions[-1], upper_edge, Vector2.RIGHT))
		var points := PackedVector2Array()
		for i in anchors.size():
			var start := corners[i]
			var end := corners[i + 1]
			if (end - start).dot(directions[i]) >= 0.0:
				continue
			var columns := maxi(1, floori(start.distance_to(end) / step))
			for column in columns:
				points.append(start.lerp(end, (column + 0.5) / columns))
		ranks.append(points)
	return ranks


func door_post(slot: int) -> Vector2:
	if door_posts.is_empty():
		var nav := get_world_2d().navigation_map
		if NavigationServer2D.map_get_iteration_id(nav) == 0:
			return Vector2.INF
		for side: float in [-1.0, 1.0]:
			var post := church.layout.exterior(BuildingInterior.EXTERIOR_OFFSET, side * (church.layout.half_width + 10.0))
			door_posts.append(NavigationServer2D.map_get_closest_point(nav, post))
	return door_posts[0 if slot == 0 else 1]


func keeps_door_clear(point: Vector2, clearance: float) -> bool:
	var offset := point - church.layout.exterior()
	if absf(offset.dot(church.layout.across)) < church.layout.half_width and offset.dot(church.layout.outward) < BuildingInterior.EXTERIOR_OFFSET + 10.0:
		return false
	return point.distance_to(door_post(0)) >= clearance and point.distance_to(door_post(1)) >= clearance


func _physics_process(delta: float) -> void:
	if church == null:
		return
	_update_signal(delta)
	var arrival_due := false
	if wave == Wave.TRAVELING:
		if mission.primary_objective_completed() or not residents.any(living_resident):
			wave = Wave.CANCELLED
		elif signal_started_frame != Engine.get_physics_frames():
			var was_traveling := travel_remaining > 0.000001
			travel_remaining = maxf(travel_remaining - delta, 0.0)
			arrival_due = travel_remaining <= 0.000001 and (was_traveling or defense.elapsed >= next_update)
	if arrival_due and squad.try_arrive():
		wave = Wave.ARRIVED
	if defense.elapsed < next_update:
		return
	next_update = defense.elapsed + retry_seconds
	for actor in assignments.keys():
		if not living_resident(actor) or not actor.is_available_for_infection() or is_instance_valid(actor.building_task):
			stop_work(actor)
	if not construction_enabled and formation.active():
		_check_assembly()
	if signal_ready and not beacon_lit:
		_assign_operator()


func _check_assembly() -> void:
	var nav := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(nav) == 0:
		return
	var population := 0
	var assembled := 0
	var clearance := 0.0
	for actor in residents:
		if living_resident(actor):
			population += 1
			clearance = maxf(clearance, actor.navigation_agent.radius)
			if formation.arrived(actor):
				assembled += 1
	if population == 0 or assembled * 2 < population:
		return
	construction_enabled = true
	for actor in residents:
		if living_resident(actor):
			worker_retry[actor] = defense.elapsed + retry_seconds * float(actor.get_instance_id() % 23) / 23.0
	for section in sections:
		section.prepare_work_points(nav, formation.center, work_spacing, clearance)
		var valid := PackedVector2Array()
		for point: Vector2 in section.work_points:
			if inside_defenses(point):
				valid.append(point)
		section.work_points = valid


func _section_changed(section: StaticBody2D) -> void:
	if not section.needs_work():
		for actor in assignments.keys():
			if assignments[actor].section == section:
				stop_work(actor)
	_check_readiness()


func _check_readiness() -> void:
	if signal_ready or not construction_enabled or total_max_hp <= 0.0:
		return
	var total_hp := 0.0
	for section in sections:
		total_hp += section.hp
	if total_hp >= total_max_hp * 0.3:
		signal_ready = true
		_assign_operator()


func update_work(behavior: RefCounted, delta: float) -> bool:
	var actor: CharacterBody2D = behavior.actor
	if not construction_enabled or actor == operator or formation.central_role(actor) or not formation.arrived(actor):
		return false
	if not residents.has(actor) or not actor.is_available_for_infection() or is_instance_valid(actor.building_task):
		return false
	if not assignments.has(actor):
		if defense.elapsed < float(worker_retry.get(actor, 0.0)):
			return false
		worker_retry[actor] = defense.elapsed + retry_seconds
		var job := _find_work(actor, formation.sector(behavior.home()))
		if job.is_empty():
			return false
		assignments[actor] = job
	var assignment: Dictionary = assignments[actor]
	var section: StaticBody2D = assignment.section
	var index: int = assignment.index
	var point: Vector2 = section.work_points[index]
	# The AI just checked its individual combat priorities. A worker can leave
	# a section it sees is unsafe without changing anyone else's assignment.
	if not section.needs_work() or section.occupants.get(index, actor) != actor:
		stop_work(actor)
		return false
	for enemy in behavior.enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive() or formation.sector(enemy.global_position) != section.side: continue
		var approach := Geometry2D.get_closest_point_to_segment(enemy.global_position, actor.global_position, point)
		if approach.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE + actor.navigation_agent.radius:
			stop_work(actor)
			return false
	var at_work := actor.global_position.distance_to(point) <= work_reach
	var result: int = behavior.move_in_formation(point, delta, work_reach)
	if result == actor.NavigationResult.FAILED:
		stop_work(actor)
		return false
	behavior.mode = "barricade"
	if not at_work:
		section.occupants.erase(index)
		return true
	section.occupants[index] = actor
	section.build(worker_hp_per_second * delta)
	return true


func _find_work(actor: Node2D, side: int) -> Dictionary:
	var best := {}
	var best_distance := INF
	var reserved: Dictionary = {}
	for job in assignments.values():
		if not reserved.has(job.section): reserved[job.section] = []
		reserved[job.section].append(job.index)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = actor.get_node("CollisionShape2D").shape
	query.collision_mask = 8
	query.exclude = [actor.get_rid()]
	var space := actor.get_world_2d().direct_space_state
	for section in sections:
		if section.side != side or not section.needs_work(): continue
		var booked: Array = reserved.get(section, [])
		for i in section.work_points.size():
			if section.occupants.has(i) or booked.has(i): continue
			var point: Vector2 = section.work_points[i]
			var distance := actor.global_position.distance_squared_to(point)
			if distance >= best_distance: continue
			query.transform = Transform2D(actor.global_rotation, point)
			if not space.intersect_shape(query, 1).is_empty() or not defense.reachable(actor, point): continue
			best = {"section": section, "index": i}
			best_distance = distance
	return best


func stop_work(actor: Variant) -> void:
	if not assignments.has(actor):
		return
	var job: Dictionary = assignments[actor]
	if job.section.occupants.get(job.index) == actor:
		job.section.occupants.erase(job.index)
	assignments.erase(actor)
	worker_retry[actor] = defense.elapsed + retry_seconds


func remove_worker(actor: Node) -> void:
	stop_work(actor)
	worker_retry.erase(actor)


func crossing_speed(actor: Node2D) -> float:
	for section in sections:
		if section.state == SECTION.State.EXISTING and section.overlaps(actor.global_position, 4.0):
			return 0.5
	return 1.0


func _assign_operator() -> void:
	if beacon_lit:
		return
	if not living_resident(operator):
		operator = null
		signal_remaining = 0.0
		var nearest := INF
		for actor in residents:
			if not living_resident(actor):
				continue
			if actor.priest_routine != null:
				operator = actor
				break
			if actor.priest_guard != null or not actor.is_available_for_infection() or is_instance_valid(actor.building_task):
				continue
			var distance: float = actor.global_position.distance_squared_to(church.layout.exterior())
			if distance < nearest:
				nearest = distance
				operator = actor
	if not is_instance_valid(operator):
		return
	stop_work(operator)
	if is_instance_valid(operator.interior_building) and operator.interior_building != church:
		operator.interior_building.request_resident_exit(operator)
	if operator.interior_building == church or not is_instance_valid(operator.building_task):
		church.request_signal_entry(operator)


func _on_operator_entered(actor: Node2D) -> void:
	if actor != operator or beacon_lit:
		return
	if church.signal_sealed and church.door_closed and church.door_hp > 0.0:
		church_posts_active = true
	signal_remaining = PRIEST_SIGNAL_SECONDS if operator.priest_routine != null else RESIDENT_SIGNAL_SECONDS
	signal_started_frame = Engine.get_physics_frames()


func _update_signal(delta: float) -> void:
	if beacon_lit or not living_resident(operator) or operator.interior_building != church:
		return
	if signal_remaining <= 0.0 or signal_started_frame == Engine.get_physics_frames():
		return
	signal_remaining = maxf(signal_remaining - delta, 0.0)
	if signal_remaining > 0.000001:
		return
	beacon_lit = true
	wave = Wave.TRAVELING
	travel_remaining = TRAVEL_SECONDS
	signal_started_frame = Engine.get_physics_frames()
	defense.alert.advance_level(defense.alert.Level.LAST_STAND)
	queue_redraw()


func _draw() -> void:
	if not beacon_lit:
		return
	draw_circle(beacon_position, 23.0, Color("#e8a55540"))
	draw_colored_polygon(PackedVector2Array([
		beacon_position + Vector2(-9, 9), beacon_position + Vector2(-6, -4),
		beacon_position + Vector2(-2, 0), beacon_position + Vector2(3, -17),
		beacon_position + Vector2(9, 3), beacon_position + Vector2(7, 9),
	]), Color("#ffba5f"))
	draw_circle(beacon_position + Vector2(0, 4), 4.0, Color("#fff3c4"))
