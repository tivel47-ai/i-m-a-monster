# Godot --headless --path . --script tests/village_validation.gd --fixed-fps 60
extends SceneTree

var failures := 0
var map: Node2D
var navigation_map: RID

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func path_is_clear(path: PackedVector2Array) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var body := RectangleShape2D.new()
	body.size = map.get_node("Zombie/CollisionShape2D").shape.size
	query.shape = body
	query.collision_mask = 1
	for index in range(1, path.size()):
		var distance := path[index - 1].distance_to(path[index])
		for sample in range(ceili(distance / 4.0) + 1):
			var point := path[index - 1].lerp(path[index], minf(sample * 4.0 / maxf(distance, 0.01), 1.0))
			query.transform = Transform2D(0, point)
			if not map.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return false
	return true

func run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	map = main.get_node("test_map")
	await frames(5)
	navigation_map = map.get_world_2d().navigation_map
	check(NavigationServer2D.map_get_iteration_id(navigation_map) > 0, "Main scene loads with synchronized navigation")
	check(map.total_residents == 4 and map.mission_state == map.MissionState.ACTIVE, "Mission initializes with four residents")
	var units := get_nodes_in_group("player_units")
	for unit in units + map.villagers:
		check(NavigationServer2D.map_get_closest_point(navigation_map, unit.global_position).distance_to(unit.global_position) < 0.1,
			"Spawn on navigation: " + str(unit.name))
		var query := PhysicsPointQueryParameters2D.new()
		query.position = unit.global_position
		query.collision_mask = 1
		check(map.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "Spawn outside solids: " + str(unit.name))
	for solid in get_nodes_in_group("village_solids"):
		check(NavigationServer2D.map_get_closest_point(navigation_map, solid.global_position).distance_to(solid.global_position) > 1,
			"Solid excluded from navigation: " + str(solid.name))
		var shape := solid.get_node("CollisionShape2D") as CollisionShape2D
		var footprint := solid.get_node("Footprint") as Polygon2D
		check(shape.shape.get_rect().is_equal_approx(Rect2(footprint.polygon[0], footprint.polygon[2] - footprint.polygon[0])),
			"Collision matches visible footprint: " + str(solid.name))
	# Verify every polygon belongs to the same connected component, not just
	# named routes. Sample physical clearance of paths to every polygon center.
	var polygon := (map.get_node("NavigationRegion2D") as NavigationRegion2D).navigation_polygon
	var vertices := polygon.vertices
	var all_connected := true
	var all_clear := true
	for index in range(polygon.get_polygon_count()):
		var indices := polygon.get_polygon(index)
		var center := Vector2.ZERO
		for vertex in indices:
			center += vertices[vertex]
		center /= indices.size()
		var path := NavigationServer2D.map_get_path(navigation_map, Vector2(800, 390), center, true)
		all_connected = all_connected and not path.is_empty() and path[-1].distance_to(center) < 0.1
		all_clear = all_clear and path_is_clear(path)
	check(all_connected, "Every navigation polygon connects to square")
	check(all_clear, "Paths to all polygon centers clear the current zombie body")
	var zombie = units[0]
	zombie.position = Vector2(330, 175)
	var sight_target := Node2D.new()
	map.add_child(sight_target)
	sight_target.position = Vector2(330, 320)
	await frames(2)
	check(not zombie._has_line_of_sight(sight_target), "House blocks existing zombie line-of-sight query")
	check(zombie.test_move(zombie.global_transform, Vector2(0, 100)), "House physically blocks zombie body motion")
	zombie.position = Vector2(560, 220)
	sight_target.position = Vector2(625, 220)
	check(not zombie._has_line_of_sight(sight_target), "Short wall blocks line-of-sight")
	zombie.position = Vector2(610, 350)
	sight_target.position = Vector2(680, 350)
	check(zombie._has_line_of_sight(sight_target), "Open street preserves line-of-sight")
	sight_target.queue_free()
	# Isolate movement from encounters; production behavior is left unchanged.
	for unit in units:
		unit.get_node("AggroArea").monitoring = false
		unit.aggro_candidates.clear()
		unit.aggro_target = null
	await frames(2)
	var starts := [Vector2(100, 360), Vector2(1190, 360), Vector2(800, 610)]
	var goals := [Vector2(660, 360), Vector2(800, 360), Vector2(800, 400)]
	var route_names := ["Western residential", "Eastern service", "Southern bypass"]
	for route in range(starts.size()):
		var path := NavigationServer2D.map_get_path(navigation_map, starts[route], goals[route], true)
		check(not path.is_empty() and path[-1].distance_to(goals[route]) < 0.1 and path_is_clear(path), route_names[route] + " approach has a physically clear path")
		for index in range(units.size()):
			var unit = units[index]
			unit.issue_player_area_hold_order()
			unit.position = starts[route] + Vector2(0, (index - 1) * 38)
			unit.set_selected(index == 0)
		await frames(3)
		map._issue_point_move_order(goals[route])
		await frames(600)
		check(zombie.last_move_reached and not zombie.has_player_order, route_names[route] + " individual order arrives: %s -> %s" % [zombie.position, zombie.target_position])
		for index in range(units.size()):
			units[index].position = starts[route] + Vector2(0, (index - 1) * 38)
			units[index].set_selected(true)
		await frames(3)
		map._issue_point_move_order(goals[route])
		var destinations: Array[Vector2] = []
		for unit in units:
			check(unit.has_player_order and not destinations.has(unit.target_position), route_names[route] + " group receives distinct reachable targets")
			destinations.append(unit.target_position)
		await frames(900)
		for unit in units:
			check(unit.last_move_reached and not unit.has_player_order, route_names[route] + " group member arrives: %s -> %s" % [unit.position, unit.target_position])
	# Re-enable the real detection area to check autonomous aggression and
	# priority of a subsequent player order, without waiting for random combat.
	zombie.position = Vector2(700, 340)
	zombie.get_node("AggroArea").monitoring = true
	await frames(10)
	check(zombie.aggro_target == map.villagers[0], "Autonomous aggression acquires a visible resident")
	zombie.issue_player_move_order(Vector2(900, 360))
	await frames(2)
	check(zombie.has_player_order and zombie.aggro_target == null, "Player move order takes priority over aggression")
	# UI, counting and the unchanged victory threshold on this scene.
	for resident in map.villagers:
		resident.take_damage(1000)
	check(map.killed_residents == 4 and map.mission_state == map.MissionState.WON,
		"Existing death accounting reaches mission victory")
	check(map.progress_label.text == "Прогресс: 100%" and map.status_label.text.begins_with("ПОБЕДА"), "Mission UI displays progress and victory")
	main.queue_free()
	await frames(2)
	print("Village validation failures: ", failures)
	quit(1 if failures else 0)
