# Godot --headless --path . --script tests/villager_activities_validation.gd --fixed-fps 60
extends "res://tests/villager_movement_validation.gd"


func weights(resident: Node, home: float, work: float, social: float, wander: float) -> void:
	resident.home_weight = home
	resident.work_weight = work
	resident.social_weight = social
	resident.wander_weight = wander


func run() -> void:
	seed(1202)
	await load_peaceful_map()
	var navigation_map: RID = map.get_world_2d().navigation_map
	for index in range(4):
		var resident = map.villagers[index]
		resident.set_physics_process(false)
		resident._stop_movement()
		resident.position = Vector2(90, 300 + index * 25)
	await frames(3)
	var expected_work := ["FieldApproach", "GardenApproach", "WorkshopApproach"]
	for index in range(4):
		var resident = map.villagers[index]
		check(resident.move_speed == 55.0, "Profile preserves Stage 1.1 movement speed: %d" % index)
		var expected_weights := [25.0, 45.0, 20.0, 10.0] if index < 3 else [50.0, 0.0, 40.0, 10.0]
		check([resident.home_weight, resident.work_weight, resident.social_weight, resident.wander_weight] == expected_weights,
			"Scene configures the intended profile weights: %d" % index)
		if index < 3:
			check(resident.get_node(resident.work_point_path).name == expected_work[index], "Profile uses its assigned workplace: %d" % index)
		await travel_to_activity(resident, resident.Activity.HOME, navigation_map)
		if index < 3:
			await travel_to_activity(resident, resident.Activity.WORK, navigation_map)
	var resident = map.villagers[0]
	await travel_to_activity(resident, resident.Activity.SOCIAL, navigation_map)
	await travel_to_activity(resident, resident.Activity.WANDER, navigation_map)
	# Sample selection at the same neutral position, so all four activities are available.
	for index in range(4):
		var subject = map.villagers[index]
		subject.position = Vector2(800, 390)
		if index < 3:
			weights(subject, 25, 45, 20, 10)
		else:
			weights(subject, 50, 0, 40, 10)
		var counts := [0, 0, 0, 0]
		for sample in range(1000):
			subject._choose_destination(navigation_map)
			if subject.current_activity >= 0:
				counts[subject.current_activity] += 1
		print("PROFILE SAMPLE ", index, " HOME/WORK/SOCIAL/WANDER: ", counts)
		if index < 3:
			check(counts[1] > 350 and counts[1] < 550 and counts[1] > counts[3] * 2,
				"Work is preferred to wandering over 1000 choices: %d" % index)
			check(counts[0] > 150 and counts[2] > 120 and counts[3] > 40,
				"Other activities retain their provisional share: %d" % index)
		else:
			check(counts[1] == 0 and counts[0] > 400 and counts[2] > 300,
				"Ordinary villager prioritizes home/social visits without work")
		subject._stop_movement()
		subject.position = Vector2(90, 300 + index * 25)
	resident.position = Vector2(800, 390)
	weights(resident, 25, 100000, 20, 10)
	var workplace: Marker2D = resident.get_node(resident.work_point_path)
	var original_work_position := workplace.position
	for invalid_position in [Vector2(330, 245), Vector2(-100, -100)]:
		workplace.position = invalid_position
		var fallback_valid := true
		for sample in range(100):
			resident._choose_destination(navigation_map)
			fallback_valid = fallback_valid and resident.has_destination and resident.current_activity != resident.Activity.WORK and resident.destination != invalid_position
		check(fallback_valid, "Unavailable workplace falls back to valid activities: %s" % invalid_position)
	workplace.position = original_work_position
	var original_path: NodePath = resident.work_point_path
	resident.work_point_path = NodePath("../MissingWorkplace")
	resident._choose_destination(navigation_map)
	check(resident.has_destination and resident.current_activity != resident.Activity.WORK, "Missing preferred marker does not break selection")
	resident.work_point_path = original_path
	weights(resident, 0, 1, 0, 0)
	resident._choose_destination(navigation_map)
	check(resident.current_activity == resident.Activity.WORK and resident.destination == workplace.global_position,
		"Restored workplace can be selected again")
	# At home, repeated home selection is excluded in favour of another available activity.
	resident.position = resident.get_node(resident.home_point_path).global_position
	weights(resident, 100000, 1, 1, 1)
	var no_repeat := true
	for sample in range(100):
		resident._choose_destination(navigation_map)
		no_repeat = no_repeat and resident.current_activity != resident.Activity.HOME and resident.has_destination
	check(no_repeat, "Resident leaves current location instead of repeatedly selecting home")
	weights(resident, 0, 0, 0, 0)
	resident._choose_destination(navigation_map)
	check(not resident.has_destination and resident.current_activity == resident.Activity.NONE and resident.wait_remaining >= 2,
		"All disabled weights produce bounded retry waiting")
	await check_activity_interrupt(resident, navigation_map)
	await clear_map()
	print("Villager activities validation failures: ", failures)
	quit(1 if failures else 0)


func travel_to_activity(resident: Node2D, activity: int, navigation_map: RID) -> void:
	resident.position = Vector2(800, 390)
	resident._stop_movement()
	resident.wait_remaining = 0.0
	weights(resident, 0, 0, 0, 0)
	match activity:
		0: resident.home_weight = 1
		1: resident.work_weight = 1
		2: resident.social_weight = 1
		3: resident.wander_weight = 1
	await frames(3)
	resident._choose_destination(navigation_map)
	var target: Vector2 = resident.destination
	var correct_target: bool = resident.has_destination and resident.current_activity == activity
	if activity == resident.Activity.HOME:
		correct_target = correct_target and target == resident.get_node(resident.home_point_path).global_position
	elif activity == resident.Activity.WORK:
		correct_target = correct_target and target == resident.get_node(resident.work_point_path).global_position
	var clear := true
	resident.set_physics_process(true)
	for frame in range(2400):
		await frames(1)
		if frame % 10 == 0:
			clear = clear and not overlaps_building(resident, resident.position)
		if resident.is_performing_activity:
			break
	check(correct_target and clear and resident.is_performing_activity
		and resident.position.distance_to(target) <= resident.arrival_tolerance,
		"Profile %s reaches activity %d without crossing buildings" % [resident.name, activity])
	var ranges := [Vector2(4, 8), Vector2(6, 12), Vector2(3, 6), Vector2(2, 4)]
	check(resident.wait_remaining >= ranges[activity].x and resident.wait_remaining <= ranges[activity].y,
		"Activity %d uses its expected arrival duration" % activity)
	var arrived: Vector2 = resident.position
	await frames(60)
	check(resident.is_performing_activity and resident.position.is_equal_approx(arrived),
		"Activity %d waits at destination before selecting again" % activity)
	resident.set_physics_process(false)
	resident._stop_movement()
	resident.position = Vector2(90, 300 + map.villagers.find(resident) * 25)


func check_activity_interrupt(resident: Node2D, navigation_map: RID) -> void:
	resident.position = Vector2(800, 390)
	weights(resident, 0, 1, 0, 0)
	resident._choose_destination(navigation_map)
	# Enter the same arrival state used after physically reaching the activity.
	resident.position = resident.destination
	resident._begin_wait(true)
	check(resident.is_performing_activity, "Combat fixture begins during work activity")
	var zombie = load("res://scenes/zombie.tscn").instantiate()
	zombie.position = resident.position + Vector2(20, 0)
	map.add_child(zombie)
	zombie.set_physics_process(false)
	resident.begin_encounter(Color.GREEN, zombie)
	check(resident.current_activity == resident.Activity.NONE and not resident.is_performing_activity and not resident.has_destination,
		"Combat immediately cancels peaceful work and navigation")
	resident.set_physics_process(true)
	var position_before: Vector2 = resident.position
	await frames(30)
	check(resident.position.is_equal_approx(position_before) and resident.current_activity == resident.Activity.NONE,
		"No peaceful activity runs during combat")
	weights(resident, 25, 45, 20, 10)
	resident.leave_encounter(zombie)
	await frames(330)
	check(resident.is_available_for_infection() and resident.current_activity != resident.Activity.NONE,
		"Survivor resumes fresh activity selection after encounter")
	resident.begin_encounter(Color.GREEN, zombie)
	resident.receive_zombie_attack(20, 1.0, zombie)
	check(resident.current_activity == resident.Activity.NONE and not resident.is_performing_activity,
		"Transformation cannot retain civilian activity")
