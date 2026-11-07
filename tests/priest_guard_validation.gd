extends "res://tests/simulation_map_validation.gd"

func run() -> void:
	seed(7126)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units = get_nodes_in_group("player_units")
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring = false
		unit.aggro_candidates.clear()
	for actor in map.villagers: actor.autonomous_movement_enabled = false
	var priest = map.get_node("Villagers/Priest30")
	priest.position = Vector2(1730,250)
	var first = map.get_node("Villagers/PriestGuard1")
	var second = map.get_node("Villagers/PriestGuard2")
	var guards: Array[Node] = [first,second]
	for actor in guards: actor.autonomous_movement_enabled = true
	await frames(5)
	nav = map.get_world_2d().navigation_map
	check(map.total_residents == 32 and ceili(map.total_residents * map.TARGET_PERCENT / 100.0) == 26, "Two added residents count toward the 26-of-32 objective")
	for actor in guards:
		check(actor.guard_ai == null and actor.escort == null and actor.guard_patrol == null, "Protector excluded from guard reports, recruitment, post duty: " + actor.name)
		check(actor.max_health == map.villagers[24].max_health and actor.attack_damage == map.villagers[24].attack_damage and actor.get_node("CollisionShape2D").shape.size == Vector2(7.8,15.6), "Existing guard combat stats and physical size preserved")
		var clear := true
		for point in actor.priest_guard.patrol_points:
			var valid = body_clear(point,actor.get_node("CollisionShape2D").shape) and NavigationServer2D.map_get_closest_point(nav,point).distance_to(point) < 1
			if not valid: print("Invalid point: ", point, " snapped ", NavigationServer2D.map_get_closest_point(nav,point))
			clear = clear and valid
		check(clear, "Every patrol waypoint is navigable and clear: " + actor.name)
	var visited := [{},{}]
	var on_roads := true
	for tick in range(7200):
		for i in range(2):
			visited[i][guards[i].priest_guard.patrol_index] = true
			if tick % 30 == 0:
				var road_found := false
				for road in map.get_node("Roads").get_children():
					if road is Polygon2D and Geometry2D.is_point_in_polygon(road.to_local(guards[i].global_position),road.polygon): road_found = true
				on_roads = on_roads and road_found
		await frames(1)
	for actor in guards: print("Patrol diagnostic ",actor.name," at ",actor.position," index ",actor.priest_guard.patrol_index," target ",actor.priest_guard.patrol_points[actor.priest_guard.patrol_index]," count ",actor.priest_guard.patrol_points.size())
	for i in range(2): check(visited[i].size() == guards[i].priest_guard.patrol_points.size(), "Both directions of every patrol branch visited: " + guards[i].name + " " + str(visited[i].size()))
	check(on_roads, "Actual peaceful patrol stays on drawn road surfaces")
	# Returning before any firsthand evidence releases the temporary group.
	priest.position = Vector2(1530,965)
	first.position = Vector2(1508,987)
	second.position = Vector2(1552,987)
	await frames(4)
	check(priest.priest_routine.protectors.size() == 2 and first.priest_guard.joined and second.priest_guard.joined, "Leaving church grounds joins both protectors to the priest")
	priest.position = Vector2(1420,557)
	await frames(4)
	check(priest.priest_routine.protectors.is_empty() and first.priest_guard.state == first.priest_guard.State.PATROL, "Safe return releases temporary escort")
	# Neither hearsay nor village suspicion grants firsthand evidence.
	first.local_warning.receive_warning(map.villagers[0],first.position)
	map.get_node("VillageAlert").advance_level(1)
	await frames(4)
	check(not first.priest_guard.permanent and not second.priest_guard.permanent, "SUSPICION and hearsay do not latch protection")
	# A real nearby corpse is detected by the existing LOS-limited perception.
	first.position = Vector2(1420,570)
	second.position = Vector2(1100,555)
	map.villagers[0].position = Vector2(1450,570)
	map.villagers[0].take_damage(1000)
	await frames(65)
	check(first.priest_guard.permanent and not second.priest_guard.permanent, "Only the protector personally seeing the corpse latches permanent duty")
	# Recognition and physical combat use the normal encounter timers.
	var enemy = units[0]
	enemy.position = Vector2(1460,575)
	enemy.attack_damage = 0.1
	enemy.infection_chance = 0.0
	first.threat_detection.recognition_delay_min = 0.0
	first.threat_detection.recognition_delay_max = 0.0
	var before: float = enemy.current_health
	await frames(240)
	check(enemy.current_health < before, "Protector intercepts a nearby monster and inflicts real timed melee damage")
	enemy.position = Vector2(1800,550)
	await frames(60)
	check(not first.is_in_collision() and first.global_position.distance_to(priest.position) < 100, "Distant enemy ends melee and is not pursued away from the priest")
	# Sounding the bell summons even a distant guard and never releases it again.
	var alert = map.get_node("VillageAlert")
	alert.activate_bell(priest)
	await frames(900)
	check(second.priest_guard.permanent and second.priest_guard.joined, "ALARM summons the distant protector into the group")
	alert.danger = alert.danger_threshold
	alert.advance_level(alert.Level.ORGANIZED_DEFENSE)
	await frames(10)
	check(first.priest_guard.joined and second.priest_guard.joined, "Organized defense retains the priest's group")
	priest.take_damage(1000)
	await frames(120)
	check(first.priest_guard.state == first.priest_guard.State.CHURCH_DEFENSE and second.priest_guard.state == second.priest_guard.State.CHURCH_DEFENSE and priest.priest_routine.protectors.is_empty(), "Priest death transfers protectors to church defense and clears group")
	map.queue_free()
	await frames(3)
	await check_conversion_and_evidence()
	print("Priest guard validation failures: ", failures)
	quit(1 if failures else 0)

func check_conversion_and_evidence() -> void:
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units = get_nodes_in_group("player_units")
	reset_units(Vector2(100,100))
	for actor in map.villagers: actor.autonomous_movement_enabled = false
	for enemy in units:
		enemy.get_node("AggroArea").monitoring = false
		enemy.infection_chance = 0.0
	var priest = map.get_node("Villagers/Priest30")
	var guard = map.get_node("Villagers/PriestGuard1")
	var other = map.get_node("Villagers/PriestGuard2")
	guard.autonomous_movement_enabled = true
	guard.position = Vector2(1440,570)
	other.position = Vector2(1100,555)
	units[0].position = Vector2(1500,580)
	await frames(100)
	check(guard.priest_guard.permanent and not other.priest_guard.permanent and map.get_node("VillageAlert").level < 2, "Firsthand monster recognition independently latches permanent protection before ALARM")
	units[0].position = Vector2(100,100)
	await frames(10)
	var civilian = map.villagers[1]
	civilian.position = guard.position + Vector2(0,30)
	civilian.autonomous_movement_enabled = true
	var report = {"kind":"corpse","incident":12345,"point":civilian.position,"observed_at":civilian.defense.elapsed}
	civilian.escort.reporter.observe(report)
	civilian.escort.reporter._request_visible_guard()
	check(civilian.escort.reporter.assigned_guard() == null, "Nearby protector is not selected as the civilian report recipient")
	civilian.autonomous_movement_enabled = false
	# Conversion goes through the real resident replacement path.
	units[0].position = priest.position + Vector2(10,0)
	priest.begin_encounter(Color.GREEN,units[0])
	priest._start_transformation()
	priest.transformation_timer.stop()
	priest._on_transformation_timer_timeout()
	await frames(5)
	var converted: Node2D
	for enemy in get_nodes_in_group("player_units"):
		if not units.has(enemy): converted = enemy
	check(converted != null and guard.priest_guard.state == guard.priest_guard.State.CHURCH_DEFENSE, "Priest conversion replaces the leader with a monster and transfers protection to church")
	if converted != null:
		converted.issue_player_area_hold_order()
		converted.infection_chance = 0.0
		converted.attack_damage = 0.1
		var hp: float = converted.current_health
		await frames(240)
		check(not is_instance_valid(converted) or converted.current_health < hp, "Converted priest is attacked as a hostile monster near the church")
	guard.take_damage(1000)
	await frames(3)
	check(not guard.priest_guard.joined, "Dead protector leaves its group without retaining a stale member")
	map.queue_free()
	await frames(3)
