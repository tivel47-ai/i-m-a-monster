extends RefCounted
## Short exterior approaches around bodies. Each leg is followed explicitly so
## the static navigation mesh cannot cut the corner through the fighting line.

const LOCAL_DISTANCE := 110.0
const EXTRA_DISTANCE := 96.0
const BACKSTEP := 25.0
const RETRY_FRAMES := 16
const SLOT_ANGLES := [0.0, -30.0, 30.0, -60.0, 60.0, -90.0, 90.0, -120.0, 120.0, -150.0, 150.0, 180.0]
const LANE_OFFSETS := [25.0, -25.0, 45.0, -45.0, 65.0, -65.0]

var target: Node2D
var path := PackedVector2Array()
var next_check := 0
var last_update := -2
var last_position := Vector2.INF
var query := PhysicsShapeQueryParameters2D.new()


func cancel() -> void:
	last_update = -2
	path.clear()
	target = null


func move(actor: CharacterBody2D, agent: NavigationAgent2D, speed: float, delta: float) -> void:
	agent.velocity = Vector2.ZERO
	actor.velocity = Vector2.ZERO
	if not path.is_empty():
		actor.velocity = ((path[0] - actor.global_position) / delta).limit_length(speed)
		actor.move_and_slide()


static func enabled_for(actor: Node) -> bool:
	var ancestor := actor.get_parent()
	while ancestor != null:
		if ancestor.get_meta("local_melee_routing", false):
			return true
		ancestor = ancestor.get_parent()
	return false


func applies(actor: Node2D, enemy: Node2D, melee_distance: float) -> bool:
	if not is_instance_valid(enemy) or is_instance_valid(actor.interior_building) or is_instance_valid(enemy.interior_building):
		return false
	var limit := LOCAL_DISTANCE
	if target == enemy and not path.is_empty() and last_update >= Engine.get_physics_frames() - 1:
		# The first lateral step can briefly increase the distance to the target.
		limit += BACKSTEP + absf(LANE_OFFSETS[-1])
	var distance_squared := actor.global_position.distance_squared_to(enemy.global_position)
	return (
		distance_squared <= limit * limit and distance_squared > melee_distance * melee_distance
		and _clear_sight(actor.get_world_2d().direct_space_state, actor.global_position, enemy.global_position)
	)


func update(
	actor: CharacterBody2D, enemy: Node2D, melee_distance: float,
	home := Vector2.INF, leash := INF
) -> bool:
	var frame := Engine.get_physics_frames()
	var origin := actor.global_position
	var space := actor.get_world_2d().direct_space_state
	if target != enemy or last_update < frame - 1:
		path.clear()
		next_check = 0
		last_position = Vector2.INF
	target = enemy
	last_update = frame
	if not path.is_empty() and origin.distance_squared_to(path[0]) <= 0.25:
		path.remove_at(0)
	if frame >= next_check:
		_configure_query(actor)
		var moving := origin.distance_squared_to(last_position) >= 9.0
		if (
			path.is_empty() or not moving
			or not _within_leash(path, home, leash)
			or not _valid_slot(space, path[-1], enemy.global_position, melee_distance)
			or not _clear_leg(space, origin, path[0])
		):
			path = _find_path(actor, enemy.global_position, melee_distance, home, leash)
		last_position = origin
		next_check = frame + RETRY_FRAMES + actor.get_instance_id() % 5
		return true
	return false


func try_target(actor: CharacterBody2D, enemy: Node2D, reach: float, home := Vector2.INF, leash := INF) -> bool:
	var alternative := _find_path(actor, enemy.global_position, reach, home, leash)
	if alternative.is_empty():
		return false
	target = enemy
	path = alternative
	return true


func _configure_query(actor: CharacterBody2D) -> void:
	query.shape = actor.get_node("CollisionShape2D").shape
	query.exclude = [actor.get_rid()]
	query.collision_mask = actor.collision_mask
	query.margin = 1.5


func _find_path(
	actor: CharacterBody2D, center: Vector2, melee_distance: float, home: Vector2, leash: float
) -> PackedVector2Array:
	var space := actor.get_world_2d().direct_space_state
	var origin := actor.global_position
	var forward := origin.direction_to(center)
	var side := forward.orthogonal()
	var reach := melee_distance - 0.8
	var best := PackedVector2Array()
	var cost := origin.distance_to(center) + EXTRA_DISTANCE
	var reserved := _reserved_slots(actor, center, melee_distance)
	var slots := PackedVector2Array()
	var spacing := (query.shape as RectangleShape2D).size + Vector2.ONE * 3.0
	for angle: float in SLOT_ANGLES:
		var point := center - forward.rotated(deg_to_rad(angle)) * reach
		if not _valid_slot(space, point, center, melee_distance) or point.distance_to(home) > leash:
			continue
		if reserved.any(func(other: Vector2) -> bool:
			var separation := (point - other).abs()
			return separation.x < spacing.x and separation.y < spacing.y
		):
			continue
		var distance := origin.distance_to(point)
		if distance < cost and _clear_leg(space, origin, point):
			best = PackedVector2Array([point])
			cost = distance
		slots.append(point)
	if slots.is_empty() or not best.is_empty():
		return best

	for backstep: float in [0.0, BACKSTEP]:
		var start := origin - forward * backstep
		var prefix := PackedVector2Array()
		if backstep > 0.0:
			if start.distance_to(home) > leash or not _clear_leg(space, origin, start):
				continue
			prefix.append(start)
		for offset: float in LANE_OFFSETS:
			var entry := start + side * offset
			var exit := center + side * offset
			var entry_cost := backstep + absf(offset)
			if entry_cost >= cost or entry.distance_to(home) > leash or not _clear_leg(space, start, entry):
				continue
			var lane_cost := entry_cost + entry.distance_to(exit)
			var lane_clear := lane_cost < cost and exit.distance_to(home) <= leash and _clear_leg(space, entry, exit)
			for point in slots:
				var direct_cost := entry_cost + entry.distance_to(point)
				if direct_cost < cost and _clear_leg(space, entry, point):
					best = prefix + PackedVector2Array([entry, point])
					cost = direct_cost
				var turn_cost := lane_cost + exit.distance_to(point)
				if lane_clear and turn_cost < cost and _clear_leg(space, exit, point):
					best = prefix + PackedVector2Array([entry, exit, point])
					cost = turn_cost
	return best


func _reserved_slots(actor: CharacterBody2D, center: Vector2, reach: float) -> Array[Vector2]:
	var nearby := CircleShape2D.new()
	nearby.radius = LOCAL_DISTANCE + reach
	var scan := PhysicsShapeQueryParameters2D.new()
	scan.shape = nearby
	scan.transform = Transform2D(0.0, center)
	scan.collision_mask = actor.collision_layer
	scan.exclude = query.exclude
	var reserved: Array[Vector2] = []
	var frame := Engine.get_physics_frames()
	for hit in actor.get_world_2d().direct_space_state.intersect_shape(scan, 64):
		var peer: Variant = hit.collider.get("melee_route")
		if peer != null and peer.last_update >= frame - 1 and not peer.path.is_empty():
			reserved.append(peer.path[-1])
	return reserved


func _within_leash(points: PackedVector2Array, home: Vector2, leash: float) -> bool:
	for point in points:
		if point.distance_to(home) > leash:
			return false
	return true


func _valid_slot(space: PhysicsDirectSpaceState2D, point: Vector2, center: Vector2, reach: float) -> bool:
	query.motion = Vector2.ZERO
	query.transform = Transform2D(0.0, point)
	return (
		point.distance_squared_to(center) <= reach * reach
		and _clear_sight(space, point, center)
		and space.intersect_shape(query, 1).is_empty()
	)


func _clear_leg(space: PhysicsDirectSpaceState2D, start: Vector2, end: Vector2) -> bool:
	query.motion = Vector2.ZERO
	query.transform = Transform2D(0.0, end)
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.transform = Transform2D(0.0, start)
	query.motion = end - start
	return space.cast_motion(query)[0] >= 1.0


func _clear_sight(space: PhysicsDirectSpaceState2D, start: Vector2, end: Vector2) -> bool:
	return space.intersect_ray(PhysicsRayQueryParameters2D.create(start, end, 1)).is_empty()
