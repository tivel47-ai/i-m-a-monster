# Godot --headless --path . --script tests/activity_zone_validation.gd --fixed-fps 60
extends "res://tests/villager_movement_validation.gd"

const ZONE = preload("res://scripts/activity_zone_2d.gd")
var rng := RandomNumberGenerator.new()


func rectangle(at: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([at, at + Vector2(size.x, 0), at + size, at + Vector2(0, size.y)])


func make_zone(outline: PackedVector2Array):
	var zone = ZONE.new()
	zone.polygon = outline
	map.add_child(zone)
	return zone


func run() -> void:
	rng.seed = 1789
	await check_geometry()
	await load_peaceful_map()
	for resident in map.villagers:
		resident.set_physics_process(false)
		resident._stop_movement()
		resident.position = Vector2(100, 300 + map.villagers.find(resident) * 30)
	await frames(3)
	await check_validation()
	await check_physical_route()
	await clear_map()
	print("Activity zone validation failures: ", failures)
	quit(1 if failures else 0)


func check_geometry() -> void:
	var parent := Node2D.new()
	root.add_child(parent)
	var zone = load("res://scenes/activity_zone_2d.tscn").instantiate()
	parent.add_child(zone)
	check(zone is Polygon2D and not zone is CollisionObject2D and zone.color.a == 0.0 and not zone.debug_enabled,
		"Reusable zone has native polygon editing, hidden rendering and no physics object")
	check(zone.contains_world_point(Vector2.ZERO) and zone.contains_world_point(Vector2(64, 0))
		and not zone.contains_world_point(Vector2(65, 0)), "Containment includes polygon boundary and excludes outside")
	# A large concave notch; bounding-box-only sampling would put points outside.
	zone.polygon = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 20), Vector2(20, 20), Vector2(20, 100), Vector2(0, 100)])
	parent.position = Vector2(240, 100)
	parent.rotation = 0.6
	parent.scale = Vector2(-1.4, 0.75)
	zone.position = Vector2(15, -10)
	zone.rotation = -0.2
	zone.offset = Vector2(12, -17)
	var inside := true
	var samples := {}
	var horizontal := 0
	for index in range(1200):
		var result: Array[Vector2] = zone.sample_polygon_point(rng)
		inside = inside and result.size() == 1
		if result.is_empty():
			continue
		var local: Vector2 = zone.to_local(result[0]) - zone.offset
		inside = inside and Geometry2D.is_point_in_polygon(local, zone.polygon) and not (local.x > 20 and local.y > 20)
		if local.x > 20: horizontal += 1
		samples[result[0]] = true
	check(inside and samples.size() > 1150, "1200 distinct samples respect concavity and nested mirrored/rotated/scaled transforms")
	check(horizontal > 450 and horizontal < 620, "Area-weighted triangulation samples both concave arms proportionally")
	check(not zone.contains_world_point(zone.to_global(zone.offset + Vector2(60, 60))), "Concave notch is excluded")
	var reversed: PackedVector2Array = zone.polygon.duplicate()
	reversed.reverse()
	zone.polygon = reversed
	check(zone.has_valid_polygon() and not zone.sample_polygon_point(rng).is_empty(), "Either polygon winding is supported")
	zone.polygon = rectangle(Vector2(300, 300), Vector2(20, 20))
	check(not zone.contains_world_point(zone.to_global(zone.offset + Vector2(10, 10))) and zone.contains_world_point(zone.to_global(zone.offset + Vector2(310, 310))),
		"Editing polygon invalidates cached triangulation")
	for bad in [PackedVector2Array(), PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(20, 0)]),
		PackedVector2Array([Vector2.ZERO, Vector2(20, 20), Vector2(0, 20), Vector2(20, 0)]),
		PackedVector2Array([Vector2.ZERO, Vector2(20, 0), Vector2.ZERO, Vector2(0, 20)]),
		PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(10, 0), Vector2(10, 20), Vector2(0, 20)]),
		PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(10, 30), Vector2(10, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]),
		PackedVector2Array([Vector2.INF, Vector2(20, 0), Vector2(0, 20)])]:
		zone.polygon = bad
		check(not zone.has_valid_polygon() and zone.sample_polygon_point(rng).is_empty(), "Malformed polygon safely returns no sample: " + str(bad))
	zone.polygon = rectangle(Vector2.ZERO, Vector2(20, 20))
	zone.transform = Transform2D(Vector2.ZERO, Vector2.DOWN, Vector2.ZERO)
	check(not zone.has_valid_polygon(), "Singular zone transform cannot be sampled")
	zone.transform = Transform2D.IDENTITY
	zone.offset = Vector2.INF
	check(zone.sample_polygon_point(rng).is_empty(), "Non-finite polygon offset cannot produce a destination")
	zone.offset = Vector2.ZERO
	zone.position = Vector2.INF
	check(zone.sample_polygon_point(rng).is_empty(), "Non-finite global transform cannot produce a destination")
	parent.queue_free()
	await frames(2)


func check_validation() -> void:
	var resident = map.villagers[0]
	resident.position = Vector2(800, 390)
	var zone = make_zone(rectangle(Vector2(735, 340), Vector2(130, 100)))
	var origin: Vector2 = resident.position
	var old_target: Vector2 = resident.navigation_agent.target_position
	var valid := true
	var reservations := PackedVector2Array([Vector2(800, 390)])
	for index in range(150):
		var result: Array[Vector2] = zone.sample_destination(resident, reservations, rng)
		valid = valid and result.size() == 1
		if result.is_empty(): continue
		var point := result[0]
		var path := NavigationServer2D.map_get_path(resident.navigation_agent.get_navigation_map(), origin, point, true)
		valid = valid and Geometry2D.is_point_in_polygon(point, zone.polygon) and not overlaps_building(resident, point)
		valid = valid and point.distance_to(reservations[0]) >= zone.minimum_separation and not path.is_empty() and path[-1].distance_to(point) <= 1
	check(valid, "150 destinations are contained, on navigation, reachable, physically clear and separated from reservation")
	check(resident.position == origin and resident.navigation_agent.target_position == old_target and not resident.has_destination,
		"Sampling never moves resident, starts an activity or overwrites agent target")
	check(not zone.is_destination_valid(Vector2.INF, resident) and not zone.is_destination_valid(Vector2(950, 390), resident),
		"Invalid and outside coordinates are rejected")
	zone.zone_enabled = false
	check(zone.sample_destination(resident).is_empty(), "Disabled zone is unavailable")
	zone.zone_enabled = true
	zone.allowed_roles = PackedStringArray(["priest"])
	check(not zone.allows_resident(resident), "Role restriction rejects unmatched resident")
	resident.set_meta("village_role", "priest")
	check(zone.allows_resident(resident), "Role metadata allows matching resident")
	zone.allowed_residents.assign([NodePath("../MissingResident")])
	check(not zone.allows_resident(resident), "Role and identity restrictions must both match")
	zone.allowed_residents.assign([zone.get_path_to(resident)])
	check(zone.allows_resident(resident), "Explicit relative identity assignment is resolved")
	zone.allowed_roles = PackedStringArray()
	zone.allowed_residents.clear()
	zone.minimum_separation = 200
	check(zone.sample_destination(resident, reservations, rng).is_empty(), "Fully reserved zone exhausts bounded attempts without unsafe fallback")
	# RNG-state comparison proves failed search consumes only the bounded batch.
	for attempts in [0, 3, 1000]:
		zone.sampling_attempts = attempts
		var reference := RandomNumberGenerator.new()
		reference.seed = 55
		var bounded := RandomNumberGenerator.new()
		bounded.seed = 55
		for index in range(clampi(attempts, 1, 64)): zone.sample_polygon_point(reference)
		var unavailable: Array[Vector2] = zone.sample_destination(resident, reservations, bounded)
		check(unavailable.is_empty() and reference.state == bounded.state, "Failure uses clamped retry budget: " + str(attempts))
	zone.sampling_attempts = 24
	zone.minimum_separation = 12
	var neighbour = map.villagers[1]
	neighbour.position = Vector2(810, 390)
	await frames(3)
	check(not zone.is_destination_valid(neighbour.position, resident) and not zone.is_destination_valid(Vector2(798, 390), resident),
		"Existing occupied-body layer prevents overlap and excessive clustering")
	var shared := PackedVector2Array()
	var sharing_valid := true
	for subject in map.villagers:
		var result: Array[Vector2] = zone.sample_destination(subject, shared, rng)
		sharing_valid = sharing_valid and result.size() == 1
		if result.is_empty(): continue
		for point in shared: sharing_valid = sharing_valid and point.distance_to(result[0]) >= zone.minimum_separation
		shared.append(result[0])
	check(sharing_valid and shared.size() == 4, "Four actual residents can share a zone with caller-owned reservations")
	neighbour.position = Vector2(100, 330)
	# Put a static obstacle ON the navmesh to independently test body safety.
	var blocker := StaticBody2D.new()
	blocker.position = Vector2(840, 390)
	blocker.collision_layer = 1
	var collision := CollisionShape2D.new()
	var blocker_shape := RectangleShape2D.new()
	blocker_shape.size = Vector2(10, 10)
	collision.shape = blocker_shape
	blocker.add_child(collision)
	map.add_child(blocker)
	await frames(3)
	check(not zone.is_destination_valid(Vector2(840, 390), resident), "Static obstacle is rejected even when navmesh still covers it")
	var body_shape: CollisionShape2D = resident.get_node("CollisionShape2D")
	body_shape.position = Vector2(18, 0)
	check(not zone.is_destination_valid(Vector2(822, 390), resident), "Collision validation includes offset collision child")
	body_shape.position = Vector2.ZERO
	resident.rotation = PI * 0.5
	check(not zone.is_destination_valid(Vector2(829, 390), resident), "Collision validation preserves rotated body footprint")
	resident.rotation = 0
	resident.scale = Vector2(2, 1)
	check(not zone.is_destination_valid(Vector2(831, 390), resident), "Collision validation includes scaled resident footprint")
	resident.scale = Vector2.ONE
	var blocked = make_zone(rectangle(Vector2(838, 388), Vector2(4, 4)))
	check(blocked.sample_destination(resident, PackedVector2Array(), rng).is_empty(), "Wholly obstructed zone returns no destination")
	blocked.queue_free()
	blocker.queue_free()
	var house = make_zone(rectangle(Vector2(310, 230), Vector2(30, 30)))
	check(house.sample_destination(resident, PackedVector2Array(), rng).is_empty(), "Existing house interior has no valid destination")
	house.queue_free()
	var outside = make_zone(rectangle(Vector2(-500, -500), Vector2(20, 20)))
	check(outside.sample_destination(resident).is_empty(), "Off-navmesh zone is unavailable without projecting outside its polygon")
	outside.queue_free()
	var region := NavigationRegion2D.new()
	var mesh := NavigationPolygon.new()
	mesh.vertices = rectangle(Vector2(1500, 300), Vector2(200, 200))
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = mesh
	map.add_child(region)
	var island = make_zone(rectangle(Vector2(1540, 340), Vector2(100, 100)))
	check(await wait_for_navigation(resident.navigation_agent.get_navigation_map(), Vector2(1560, 360), 1), "Disconnected test island has synchronized navigation")
	check(island.sample_destination(resident).is_empty(), "Navigable but disconnected island rejects partial navigation paths")
	region.navigation_layers = 2
	resident.position = Vector2(1560, 360)
	check(await wait_for_navigation(resident.navigation_agent.get_navigation_map(), resident.position, 2), "Island navigation-layer edit has synchronized")
	check(island.sample_destination(resident).is_empty(), "Navigation layer mask is respected")
	resident.navigation_agent.navigation_layers = 2
	check(not island.sample_destination(resident).is_empty(), "Matching navigation layer makes the same island available")
	resident.navigation_agent.navigation_layers = 1
	resident.position = Vector2(-50, -50)
	check(zone.sample_destination(resident).is_empty(), "Off-mesh origin is rejected instead of silently projected")
	resident.position = origin
	var saved_map: RID = resident.navigation_agent.get_navigation_map()
	var inactive_map := NavigationServer2D.map_create()
	resident.navigation_agent.set_navigation_map(inactive_map)
	check(zone.sample_destination(resident).is_empty(), "Unsynchronized or inactive navigation map returns no sample")
	resident.navigation_agent.set_navigation_map(saved_map)
	NavigationServer2D.free_rid(inactive_map)
	body_shape.disabled = true
	check(zone.sample_destination(resident).is_empty(), "Disabled collision shape cannot be validated")
	body_shape.disabled = false
	check(zone.sample_destination(null).is_empty(), "Missing resident safely returns no sample")
	island.queue_free()
	region.queue_free()
	zone.queue_free()
	await frames(4)


func check_physical_route() -> void:
	var resident = map.villagers[0]
	resident.position = Vector2(330, 165)
	var zone = make_zone(rectangle(Vector2(315, 315), Vector2(30, 20)))
	await frames(3)
	var result: Array[Vector2] = zone.sample_destination(resident, PackedVector2Array(), rng)
	check(result.size() == 1, "Destination beyond real house is available")
	if result.is_empty(): return
	# Drive the existing navigation function from this fixture, not new zone AI.
	resident.destination = result[0]
	resident.has_destination = true
	resident.navigation_agent.target_position = result[0]
	resident.progress_position = resident.position
	resident.stalled_seconds = 0
	var reached := false
	var safe := true
	var travelled := 0.0
	for tick in range(1500):
		var before: Vector2 = resident.position
		var status: int = resident._advance_navigation(result[0], resident.move_speed, 1.0 / 60.0)
		await frames(1)
		travelled += before.distance_to(resident.position)
		safe = safe and not overlaps_building(resident, resident.position)
		if status == resident.NavigationResult.ARRIVED:
			reached = true
			break
		if status == resident.NavigationResult.FAILED: break
	check(reached and safe and travelled > 180 and zone.contains_world_point(resident.position),
		"Real NavigationAgent2D walks around house to sampled destination without crossing static geometry")
	resident._stop_movement()
	zone.queue_free()
	await frames(2)


func wait_for_navigation(navigation_map: RID, point: Vector2, layers: int) -> bool:
	# Navigation region edits are asynchronous, even with --fixed-fps.
	for attempt in range(120):
		var path := NavigationServer2D.map_get_path(navigation_map, point, point + Vector2(3, 3), true, layers)
		if not path.is_empty() and path[0].distance_to(point) <= 1 and path[-1].distance_to(point + Vector2(3, 3)) <= 1:
			return true
		await frames(1)
	return false
