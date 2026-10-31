# Godot --headless --path . --script tests/villager_movement_validation.gd --fixed-fps 60
extends SceneTree

var failures := 0
var map: Node2D


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


func load_peaceful_map() -> void:
	map = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	for zombie in get_nodes_in_group("player_units"):
		zombie.queue_free()
	await frames(3)
	# A reused world map may still contain the previous region's iteration.
	for attempt in range(120):
		if NavigationServer2D.map_get_closest_point(map.get_world_2d().navigation_map, Vector2(800, 390)).distance_to(Vector2(800, 390)) < 1.0:
			break
		await frames(1)


func clear_map() -> void:
	map.queue_free()
	await frames(2)


func set_points(positions: Array[Vector2]) -> void:
	var points := map.get_node("VillagePointsOfInterest")
	for old in points.get_children():
		points.remove_child(old)
		old.queue_free()
	for position in positions:
		var marker := Marker2D.new()
		marker.position = position
		points.add_child(marker)


func keep_one_resident() -> Node2D:
	for index in range(1, map.villagers.size()):
		map.villagers[index].queue_free()
	var resident: Node2D = map.villagers[0]
	resident._stop_movement()
	resident.wait_remaining = 0.0
	return resident


func overlaps_building(resident: Node2D, position: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = resident.get_node("CollisionShape2D").shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 1
	return not map.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func run() -> void:
	seed(1101)
	await load_peaceful_map()
	var navigation_map: RID = map.get_world_2d().navigation_map
	var points: Array[Vector2] = []
	for marker in map.get_node("VillagePointsOfInterest").get_children():
		points.append(marker.global_position)
		check(NavigationServer2D.map_get_closest_point(navigation_map, marker.global_position).distance_to(marker.global_position) < 1.0
			and not overlaps_building(map.villagers[0], marker.global_position), "POI on clear navigation: " + str(marker.name))
	var arrivals := [0, 0, 0, 0]
	var departures := [0, 0, 0, 0]
	var travelled := [0.0, 0.0, 0.0, 0.0]
	var safe := true
	var stable := true
	var waits_valid := true
	for frame in range(6000):
		var positions: Array[Vector2] = []
		var was_moving: Array[bool] = []
		var destinations: Array[Vector2] = []
		for resident in map.villagers:
			positions.append(resident.position)
			was_moving.append(resident.has_destination)
			destinations.append(resident.destination)
		await frames(1)
		for index in range(4):
			var resident = map.villagers[index]
			travelled[index] += resident.position.distance_to(positions[index])
			if was_moving[index] and not resident.has_destination:
				if resident.position.distance_to(destinations[index]) <= resident.arrival_tolerance:
					arrivals[index] += 1
				waits_valid = waits_valid and resident.wait_remaining >= 2.0 and resident.wait_remaining <= 5.0
			elif not was_moving[index] and resident.has_destination:
				departures[index] += 1
				stable = stable and points.has(resident.destination)
			elif was_moving[index] and resident.has_destination:
				stable = stable and resident.destination == destinations[index]
			elif resident.wait_remaining > 0.0:
				stable = stable and resident.position.is_equal_approx(positions[index])
			if frame % 10 == 0:
				safe = safe and not overlaps_building(resident, resident.position)
	for index in range(4):
		check(travelled[index] > 100 and arrivals[index] >= 2 and departures[index] >= 2,
			"Resident %d repeats movement/wait loop (arrivals %d, departures %d)" % [index, arrivals[index], departures[index]])
	check(safe, "Four residents never overlap buildings during 100 simulated seconds")
	check(stable, "Destinations remain stable on routes; waiting residents stay still")
	check(waits_valid, "Normal waits remain within 2-5 seconds")
	await clear_map()
	await check_obstacle_and_retry()
	await check_chase_and_interruptions()
	print("Villager movement validation failures: ", failures)
	quit(1 if failures else 0)


func check_obstacle_and_retry() -> void:
	await load_peaceful_map()
	var resident = keep_one_resident()
	resident.position = Vector2(330, 165)
	set_points([Vector2(330, 320), Vector2(330, 245), Vector2(-100, -100)])
	await frames(3)
	check(resident.has_destination and resident.destination == Vector2(330, 320), "Reject POIs inside house and outside navigation")
	# Force a temporary stall, then verify the watchdog returns to waiting.
	resident.move_speed = 0.0
	await frames(200)
	check(not resident.has_destination and resident.wait_remaining > 0, "Stalled route is released after timeout")
	resident.move_speed = 55.0
	var safe := true
	var arrived := false
	for frame in range(1200):
		await frames(1)
		safe = safe and not overlaps_building(resident, resident.position)
		if not resident.has_destination and resident.position.distance_to(Vector2(330, 320)) <= resident.arrival_tolerance:
			arrived = true
			break
	check(arrived and safe, "Retry navigates around house and stops at destination")
	var stopped: Vector2 = resident.position
	await frames(90)
	check(resident.position.is_equal_approx(stopped) and not resident.has_destination, "Resident waits at least 1.5 seconds after arrival")
	set_points([])
	resident.wait_remaining = 0.0
	await frames(10)
	check(not resident.has_destination and resident.velocity == Vector2.ZERO, "No POIs safely leaves resident waiting")
	set_points([Vector2(800, 390)])
	resident.wait_remaining = 0.0
	await frames(20)
	check(resident.has_destination and resident.velocity.length() > 0, "Death fixture starts with a moving resident")
	var death_position: Vector2 = resident.position
	resident.take_damage(1000)
	resident.take_damage(1000)
	await frames(180)
	check(resident.is_dead() and resident.position.is_equal_approx(death_position) and not resident.navigation_agent.avoidance_enabled,
		"Dead resident permanently stops movement and avoidance")
	check(map.killed_residents == 1, "Moving resident death counted exactly once")
	await clear_map()


func check_chase_and_interruptions() -> void:
	await load_peaceful_map()
	var resident = keep_one_resident()
	resident.position = Vector2(800, 390)
	resident.attack_interval = 10.0
	resident.encounter_attack_timer.wait_time = 10.0
	set_points([Vector2(1100, 360), Vector2(800, 390)])
	var zombie = load("res://scenes/zombie.tscn").instantiate()
	zombie.position = Vector2(700, 390)
	zombie.attack_interval = 10.0
	map.add_child(zombie)
	var origin: Vector2 = resident.position
	await frames(40)
	check(resident.position.distance_to(origin) > 15 and zombie.aggro_target == resident,
		"Zombie detects a resident while civilian keeps walking")
	check(zombie.aggro_destination_origin.distance_to(origin) > 8,
		"Zombie refreshes pursuit route for moving target")
	for frame in range(240):
		if resident.is_in_collision():
			break
		await frames(1)
	check(resident.is_encounter_owner(zombie), "Zombie catches moving resident and starts encounter")
	var encounter_position: Vector2 = resident.position
	await frames(20)
	check(not resident.has_destination and resident.velocity == Vector2.ZERO
		and resident.position.is_equal_approx(encounter_position), "Combat immediately suspends civilian movement")
	# Multiple participants retain ownership until the final participant leaves.
	var second = load("res://scenes/zombie.tscn").instantiate()
	second.position = resident.position + Vector2(0, 20)
	map.add_child(second)
	second.set_physics_process(false)
	check(resident.begin_encounter(Color.GREEN, second), "Second participant joins moving resident's encounter")
	resident.leave_encounter(zombie)
	zombie.set_physics_process(false)
	await frames(10)
	check(not resident.has_destination and resident.is_encounter_owner(second), "Remaining participant keeps civilian movement suspended")
	resident.leave_encounter(second)
	await frames(330)
	check(resident.is_available_for_infection() and resident.position.distance_to(encounter_position) > 5,
		"Survivor resumes peaceful movement after interrupted encounter")
	resident.begin_encounter(Color.GREEN, second)
	resident.receive_zombie_attack(20, 1.0, second)
	resident.leave_encounter(second)
	resident.take_damage(1000)
	var conversion_position: Vector2 = resident.position
	var reference: WeakRef = weakref(resident)
	await frames(60)
	check(resident.infection_state == resident.InfectionState.TRANSFORMING and not resident.has_destination
		and resident.position.is_equal_approx(conversion_position), "Transformation stops AI even after lethal damage and encounter exit")
	await frames(90)
	check(reference.get_ref() == null and map.infected_residents == 1 and map.killed_residents == 0,
		"Conversion removes civilian and counts it exactly once")
	var converted = get_nodes_in_group("player_units")[-1]
	check(converted.position.is_equal_approx(conversion_position) and converted.has_method("issue_player_move_order"),
		"Conversion creates controllable zombie at stopped civilian position")
	await clear_map()
