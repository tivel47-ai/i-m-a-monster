# Godot --headless --path . --script tests/villager_zone_validation.gd --fixed-fps 60
extends "res://tests/villager_activities_validation.gd"

const ZONE = preload("res://scripts/activity_zone_2d.gd")


func rectangle(at: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([at, at + Vector2(size.x, 0), at + size, at + Vector2(0, size.y)])


func zone_fixture(activity: int = 0) -> Dictionary:
	await load_peaceful_map()
	for index in range(4):
		var actor = map.villagers[index]
		actor.set_physics_process(false)
		actor.threat_detection.detection_enabled = false
		actor._stop_movement()
		actor.position = Vector2(90, 300 + index * 30)
	var actor = map.villagers[0]
	actor.position = Vector2(580, 390)
	actor.points_of_interest_path = NodePath()
	weights(actor, 0, 0, 0, 0)
	match activity:
		0: actor.home_weight = 1
		1: actor.work_weight = 1
		2: actor.social_weight = 1
		3: actor.wander_weight = 1
	var zone = ZONE.new()
	zone.polygon = rectangle(Vector2(725, 310), Vector2(180, 145))
	zone.activity = activity
	zone.local_pause_duration = Vector2(0.4, 0.8)
	zone.local_move_probability = 1.0
	zone._random.seed = 2202 + activity
	map.add_child(zone)
	actor.activity_zone_paths.assign([actor.get_path_to(zone)])
	await frames(3)
	actor._choose_destination(actor.navigation_agent.get_navigation_map())
	actor.set_physics_process(true)
	return {"actor": actor, "zone": zone}


func await_arrival(actor: Node) -> bool:
	for tick in range(1500):
		if actor.is_performing_activity: return true
		await frames(1)
	return false


func await_local_walk(actor: Node) -> bool:
	for tick in range(1800):
		if actor.is_performing_activity and actor.has_destination: return true
		await frames(1)
	return false


func moving_fixture() -> Dictionary:
	var data := await zone_fixture()
	var actor = data.actor
	data.zone.duration_override = Vector2(24, 24)
	data.zone.local_pause_duration = Vector2(0.25, 0.25)
	data.zone.local_move_radius = 65
	actor.home_local_rules = Vector3.ONE
	check(await await_local_walk(actor), "Interruption fixture reaches a real local walking phase")
	return data


func frozen_enemy(at: Vector2) -> Node2D:
	var enemy = load("res://scenes/zombie.tscn").instantiate()
	enemy.position = at
	map.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.navigation_agent.avoidance_enabled = false
	return enemy


func run() -> void:
	seed(2202)
	for activity in range(4): await check_activity_cycle(activity)
	await check_weighted_zones()
	await check_geometry_and_failures()
	await check_pause()
	await check_direct_threat()
	await check_local_warning()
	await check_combat_lifecycle()
	await check_shared_zone()
	await check_playground()
	print("Villager zone validation failures: ", failures)
	quit(1 if failures else 0)


func check_activity_cycle(activity: int) -> void:
	var data := await zone_fixture(activity)
	var actor = data.actor
	var zone = data.zone
	check(actor.current_zone == zone and actor.has_destination and not actor.is_performing_activity and actor.wait_remaining == 0,
		"Activity %d selects assigned zone before starting its timer" % activity)
	await frames(60)
	check(not actor.is_performing_activity and actor.wait_remaining == 0 and actor.navigation_agent.max_speed == 35,
		"Activity %d travel uses normal speed and consumes no activity time" % activity)
	check(await await_arrival(actor) and zone.contains_world_point(actor.position), "Activity %d physically arrives inside its zone" % activity)
	var duration: Vector2 = actor._activity_duration(activity)
	var expected := [Vector2(12, 24), Vector2(18, 36), Vector2(9, 18), Vector2(6, 12)]
	check(duration == expected[activity] and actor.wait_remaining >= duration.x and actor.wait_remaining <= duration.y,
		"Activity %d uses new Inspector duration only after arrival" % activity)
	var rules: Vector3 = actor._local_rules(activity)
	var defaults := [Vector3(0.65, 1.5, 0.6), Vector3(0.5, 2, 0.4), Vector3(0.8, 1, 1.2), Vector3(1.3, 0.5, 1.8)]
	check(rules == defaults[activity] and actor.local_wait_remaining >= maxf(zone.local_pause_duration.x * rules.y, 0.25)
		and actor.local_wait_remaining <= maxf(zone.local_pause_duration.y * rules.y, 0.25), "Activity %d applies its own radius/pause/probability profile" % activity)
	weights(actor, 0, 0, 0, 0) # Expiry must be visible, without an immediate new activity.
	var initial: float = actor.wait_remaining
	var elapsed := 0.0
	var moving := 0
	var waiting := 0
	var targets := 0
	var valid := true
	var clock_valid := true
	var stable := true
	var slower := true
	for tick in range(2600):
		var before: Vector2 = actor.position
		var was_moving: bool = actor.has_destination
		var remaining: float = actor.wait_remaining
		await frames(1)
		elapsed += 1.0 / 60.0
		if not actor.is_performing_activity: break
		clock_valid = clock_valid and absf(actor.wait_remaining - (remaining - 1.0 / 60.0)) < 0.0001
		valid = valid and actor.current_zone == zone and actor.current_activity == activity and zone.contains_world_point(actor.position) and not overlaps_building(actor, actor.position)
		if actor.has_destination:
			moving += 1
			slower = slower and actor.velocity.length() <= 30.01 and actor.position.distance_to(before) <= 30.0 / 60.0 + 0.05
			if not was_moving:
				targets += 1
				var distance: float = before.distance_to(actor.destination)
				valid = valid and distance >= 11.9 and distance <= zone.local_move_radius * rules.x * 1.8 + 0.1
				var path := NavigationServer2D.map_get_path(actor.navigation_agent.get_navigation_map(), actor.position, actor.destination, true)
				for index in range(1, path.size()): valid = valid and zone.contains_world_segment(path[index - 1], path[index])
		else:
			waiting += 1
			if not was_moving: stable = stable and actor.position.is_equal_approx(before) and actor.stalled_seconds == 0
	check(valid and targets >= 1 and moving > 5 and waiting > 10, "Activity %d alternates real local routes and pauses inside its assigned zone" % activity)
	check(clock_valid and absf(elapsed - initial) < 0.04 and actor.current_activity == actor.Activity.NONE and actor.current_zone == null,
		"Activity %d has one uninterrupted clock through local arrivals and expires on time" % activity)
	check(stable and slower and actor.move_speed == 35 and actor._local_rules(activity) == rules,
		"Activity %d intentional pauses bypass stall detection; walking stays slower than travel" % activity)
	actor.set(["home_weight", "work_weight", "social_weight", "wander_weight"][activity], 1.0)
	await frames(2)
	check(actor.current_activity != actor.Activity.NONE, "Activity expiry permits normal weighted selection again")
	await clear_map()


func check_geometry_and_failures() -> void:
	var data := await zone_fixture()
	var actor = data.actor
	var zone = data.zone
	zone.duration_override = Vector2(12, 12)
	zone.local_move_radius = 3 # No displacement can satisfy the anti-jitter minimum.
	zone.local_pause_duration = Vector2(0.25, 0.25)
	actor.home_local_rules = Vector3.ONE
	check(await await_arrival(actor) and is_equal_approx(actor.wait_remaining, 12), "Zone duration override is configurable and applied at arrival")
	var at: Vector2 = actor.position
	await frames(300)
	check(actor.position.is_equal_approx(at) and not actor.has_destination and actor.is_performing_activity
		and actor.wait_remaining > 6.9 and actor.wait_remaining < 7.1 and actor.stalled_seconds == 0,
		"Unavailable local destinations cause bounded waiting without resetting or terminating activity")
	zone.local_move_radius = 65
	check(await await_local_walk(actor), "Local movement resumes on a later scheduled attempt when destinations become available")
	zone.zone_enabled = false
	await frames(1)
	check(actor.current_zone == null and actor.current_activity == actor.Activity.NONE and not actor.has_destination and actor.local_wait_remaining == 0,
		"Disabling a zone cancels local movement and releases its activity state")
	zone.zone_enabled = true
	actor.wait_remaining = 0
	check(await await_local_walk(actor), "Re-enabled zone can be selected again")
	zone.queue_free()
	await frames(2)
	check(actor.current_zone == null and not actor.has_destination and actor.local_wait_remaining == 0, "Deleting active zone safely releases resident without stale timers")
	var invalid = ZONE.new()
	invalid.polygon = rectangle(Vector2(-400, -400), Vector2(40, 40))
	map.add_child(invalid)
	actor.activity_zone_paths.assign([actor.get_path_to(invalid)])
	actor._choose_destination(actor.navigation_agent.get_navigation_map())
	check(not actor.has_destination and actor.wait_remaining >= 2, "No reachable zone or markers leaves a safe retry wait")
	actor.points_of_interest_path = NodePath("../VillagePointsOfInterest")
	actor._choose_destination(actor.navigation_agent.get_navigation_map())
	check(actor.has_destination and actor.current_zone == null and actor.destination == actor.get_node(actor.home_point_path).global_position,
		"Unavailable zone retains functional marker-based HOME fallback and shelter assignment")
	actor.set_physics_process(false)
	actor._stop_movement()
	actor.points_of_interest_path = NodePath()
	var drift = ZONE.new()
	drift.polygon = rectangle(Vector2(725, 310), Vector2(180, 145))
	map.add_child(drift)
	actor.position = Vector2(880, 426.5)
	await frames(3)
	var goal := Vector2(880, 405)
	check(not drift.is_destination_valid(goal, actor) and drift.is_destination_valid(goal, actor, PackedVector2Array(), true, 5.0),
		"Only zone-AI opt-in tolerates a small physically clear arrival drift; foundation default remains strict")
	actor.position = Vector2(880, 431)
	check(not drift.is_destination_valid(goal, actor, PackedVector2Array(), true, 5.0), "Arrival drift beyond configured allowance remains unavailable")
	actor.position = Vector2(880, 426.5)
	var shape_node: CollisionShape2D = actor.get_node("CollisionShape2D")
	var original_shape: Shape2D = shape_node.shape
	var small_shape := RectangleShape2D.new()
	small_shape.size = Vector2(0.5, 0.5)
	shape_node.shape = small_shape
	var barrier := StaticBody2D.new()
	barrier.position = Vector2(880, 425)
	var barrier_shape := CollisionShape2D.new()
	var rectangle_shape := RectangleShape2D.new()
	rectangle_shape.size = Vector2(2, 0.5)
	barrier_shape.shape = rectangle_shape
	barrier.add_child(barrier_shape)
	map.add_child(barrier)
	await frames(3)
	check(not drift.is_destination_valid(goal, actor, PackedVector2Array(), true, 5.0), "Shape sweep rejects an obstacle on the short arrival-drift connector")
	shape_node.shape = original_shape
	barrier.queue_free()
	drift.queue_free()
	await frames(3)
	var concave = ZONE.new()
	concave.polygon = PackedVector2Array([Vector2(720, 310), Vector2(900, 310), Vector2(900, 350), Vector2(760, 350), Vector2(760, 450), Vector2(720, 450)])
	map.add_child(concave)
	actor.position = Vector2(740, 430)
	await frames(3)
	var across := Vector2(880, 330)
	check(concave.is_destination_valid(across, actor) and not concave.contains_world_segment(actor.position, across)
		and not concave.is_destination_valid(across, actor, PackedVector2Array(), true), "Local validation rejects navmesh shortcuts across a concave zone's exterior")
	var inside := true
	var count := 0
	for index in range(100):
		var sample: Array[Vector2] = concave.sample_local_destination(actor, 60, 12)
		if sample.is_empty(): continue
		count += 1
		var path := NavigationServer2D.map_get_path(actor.navigation_agent.get_navigation_map(), actor.position, sample[0], true)
		for segment in range(1, path.size()): inside = inside and concave.contains_world_segment(path[segment - 1], path[segment])
	check(inside and count > 50, "Nearby sampler accepts contained routes without crossing concave cut-outs")
	await clear_map()


func check_pause() -> void:
	var data := await moving_fixture()
	var actor = data.actor
	var at: Vector2 = actor.position
	var activity_time: float = actor.wait_remaining
	var pause_time: float = actor.local_wait_remaining
	var target: Vector2 = actor.navigation_agent.target_position
	paused = true
	await frames(120)
	check(actor.position.is_equal_approx(at) and actor.wait_remaining == activity_time and actor.local_wait_remaining == pause_time
		and actor.navigation_agent.target_position == target, "Tactical pause freezes local route, both clocks and navigation assignment")
	paused = false
	await frames(20)
	check(actor.wait_remaining < activity_time and actor.position.distance_to(at) > 1, "Unpausing resumes the same activity and local route")
	for tick in range(300):
		if not actor.has_destination: break
		await frames(1)
	at = actor.position
	activity_time = actor.wait_remaining
	pause_time = actor.local_wait_remaining
	paused = true
	await frames(120)
	check(not actor.has_destination and actor.position == at and actor.wait_remaining == activity_time and actor.local_wait_remaining == pause_time,
		"Tactical pause also freezes intentional stationary phase")
	paused = false
	await clear_map()


func check_direct_threat() -> void:
	var data := await moving_fixture()
	var actor = data.actor
	var origin: Vector2 = actor.position
	actor.threat_reaction.reactions_enabled = true
	actor.threat_reaction.flee_weight = 1
	actor.threat_reaction.shelter_weight = 0
	actor.threat_reaction.warning_weight = 0
	actor.threat_reaction.frozen_weight = 0
	actor.threat_detection.detection_enabled = true
	actor.threat_detection.recognition_delay_min = 0.1
	actor.threat_detection.recognition_delay_max = 0.1
	var enemy := frozen_enemy(actor.position + Vector2(80, 0))
	await frames(15)
	check(actor.get_recognized_threat() == enemy and actor.threat_reaction.episode_active and actor.current_zone == null
		and not actor.is_performing_activity and actor.local_wait_remaining == 0, "Actual delayed threat recognition immediately cancels local activity and clocks")
	var owns_route := true
	for tick in range(120):
		await frames(1)
		if actor.threat_reaction.has_route:
			owns_route = owns_route and actor.navigation_agent.target_position == actor.threat_reaction.route_destination
	check(owns_route and actor.position.distance_to(origin) > 65 and not data.zone.contains_world_point(actor.position),
		"Existing fleeing owns agent target and can leave zone without peaceful timers or boundary clamp interfering")
	enemy.queue_free()
	await frames(330)
	check(not actor.threat_reaction.episode_active and actor.current_zone == data.zone and actor.current_activity == actor.Activity.HOME,
		"After danger ends, existing reassessment permits fresh zone activity selection")
	await clear_map()


func check_local_warning() -> void:
	var data := await moving_fixture()
	var actor = data.actor
	actor.threat_reaction.reactions_enabled = true
	var speaker = map.villagers[1]
	speaker.position = actor.position + Vector2(65, 0)
	speaker.wait_remaining = 100
	speaker.threat_reaction.reactions_enabled = true
	speaker.threat_reaction.flee_weight = 0
	speaker.threat_reaction.shelter_weight = 0
	speaker.threat_reaction.warning_weight = 1
	speaker.threat_reaction.frozen_weight = 0
	speaker.threat_detection.detection_enabled = true
	speaker.threat_detection.recognition_delay_min = 0.1
	speaker.threat_detection.recognition_delay_max = 0.1
	speaker.set_physics_process(true)
	var enemy := frozen_enemy(speaker.position + Vector2(50, 0))
	for tick in range(120):
		if actor.local_warning.has_report(): break
		await frames(1)
	check(actor.local_warning.has_report() and actor.threat_reaction.report_based and actor.get_recognized_threat() == null
		and actor.current_zone == null and actor.local_wait_remaining == 0 and not actor.is_performing_activity,
		"Actual completed one-hop warning overrides zone behavior without fabricating direct awareness")
	speaker.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.queue_free()
	var owns_route := true
	for tick in range(120):
		await frames(1)
		if actor.threat_reaction.has_route:
			owns_route = owns_route and actor.navigation_agent.target_position == actor.threat_reaction.route_destination
	check(owns_route and actor.current_zone == null, "Report-based fleeing retains target ownership after local timers would have expired")
	await frames(600)
	check(not actor.local_warning.has_report() and not actor.threat_reaction.episode_active and actor.current_zone == data.zone,
		"Report expiration releases existing response and resumes fresh peaceful zone selection")
	await clear_map()


func check_combat_lifecycle() -> void:
	var data := await moving_fixture()
	var actor = data.actor
	actor.threat_reaction.reactions_enabled = true
	var enemy := frozen_enemy(actor.position + Vector2(20, 0))
	actor.begin_encounter(Color.GREEN, enemy)
	var at: Vector2 = actor.position
	await frames(40)
	check(actor.is_in_collision() and actor.position.is_equal_approx(at) and actor.current_zone == null
		and actor.local_wait_remaining == 0 and not actor.has_destination, "Combat stops local movement and clears zone timers")
	actor.leave_encounter(enemy)
	enemy.queue_free()
	await frames(330)
	check(actor.is_available_for_infection() and actor.current_zone == data.zone, "Surviving combat returns through existing reassessment to fresh zone selection")
	await clear_map()
	data = await moving_fixture()
	actor = data.actor
	at = actor.position
	actor.take_damage(1000)
	actor.take_damage(1000)
	await frames(120)
	check(actor.is_dead() and actor.position == at and actor.current_zone == null and actor.local_wait_remaining == 0
		and not actor.has_destination and map.killed_residents == 1, "Death permanently stops zone AI and retains idempotent mission accounting")
	await clear_map()
	data = await moving_fixture()
	actor = data.actor
	enemy = frozen_enemy(actor.position + Vector2(20, 0))
	actor.begin_encounter(Color.GREEN, enemy)
	actor.receive_zombie_attack(20, 1.0, enemy)
	actor.leave_encounter(enemy)
	enemy.queue_free()
	at = actor.position
	var reference: WeakRef = weakref(actor)
	await frames(60)
	check(actor.infection_state == actor.InfectionState.TRANSFORMING and actor.position == at and actor.current_zone == null
		and actor.local_wait_remaining == 0 and not actor.has_destination, "Transformation prevents any stale local route or activity")
	await frames(90)
	check(reference.get_ref() == null and map.infected_residents == 1 and get_nodes_in_group("player_units").size() == 1,
		"Completed transformation still creates a controllable zombie with one mission outcome")
	await clear_map()


func check_shared_zone() -> void:
	var data := await zone_fixture(2)
	var zone = data.zone
	zone.duration_override = Vector2(20, 20)
	zone.local_pause_duration = Vector2(0.5, 1.2)
	zone.local_move_radius = 70
	zone.local_move_probability = 0.8
	var starts := [Vector2(780, 335), Vector2(885, 345), Vector2(780, 425), Vector2(850, 410)]
	for index in range(4):
		var actor = map.villagers[index]
		actor._stop_movement()
		actor.position = starts[index]
		check(NavigationServer2D.map_get_closest_point(actor.navigation_agent.get_navigation_map(), actor.position).distance_to(actor.position) <= 1,
			"Shared-zone spawn %d is on actual navmesh outside the well's bake clearance" % index)
		actor.points_of_interest_path = NodePath()
		actor.activity_zone_paths.assign([actor.get_path_to(zone)])
		weights(actor, 0, 0, 1, 0)
		actor.set_physics_process(true)
	var travelled := [0.0, 0.0, 0.0, 0.0]
	var waits := [0, 0, 0, 0]
	var local_routes := [0, 0, 0, 0]
	var arrivals := [0, 0, 0, 0]
	var valid := true
	var separated := true
	for tick in range(7200):
		var before: Array[Vector2] = []
		var moving: Array[bool] = []
		var performing: Array[bool] = []
		for actor in map.villagers:
			before.append(actor.position)
			moving.append(actor.has_destination)
			performing.append(actor.is_performing_activity)
		await frames(1)
		for index in range(4):
			var actor = map.villagers[index]
			travelled[index] += actor.position.distance_to(before[index])
			if not performing[index] and actor.is_performing_activity: arrivals[index] += 1
			if actor.is_performing_activity:
				valid = valid and actor.current_zone == zone and zone.contains_world_point(actor.position)
				if not actor.has_destination: waits[index] += 1
				elif not moving[index]:
					local_routes[index] += 1
					for other in map.villagers:
						if other != actor and other.has_destination:
							separated = separated and actor.destination.distance_to(other.destination) >= zone.minimum_separation - 0.01
			if tick % 5 == 0:
				valid = valid and not overlaps_building(actor, actor.position)
				for other in map.villagers:
					if actor != other: valid = valid and actor.position.distance_to(other.position) >= 7.0
	for index in range(4):
		if arrivals[index]<3:
			var observed = map.villagers[index]
			print("CROWD RETRY STATE ",index," position=",observed.position," closest=",NavigationServer2D.map_get_closest_point(observed.navigation_agent.get_navigation_map(),observed.position)," wait=",observed.wait_remaining," goal=",observed.destination," zone=",observed.current_zone," performing=",observed.is_performing_activity," moving=",observed.has_destination)
		check(travelled[index] > 100 and waits[index] > 60 and local_routes[index] >= 3 and arrivals[index] >= 3,
			"Shared-zone resident %d keeps walking, resting and restarting activities over 120 seconds: travel %.1f, routes %d, arrivals %d" % [index, travelled[index], local_routes[index], arrivals[index]])
	check(valid and separated, "Four real residents share one zone without leaving it during activities, crossing solids, overlapping centers or reserving clustered endpoints")
	await clear_map()


func check_weighted_zones() -> void:
	var data := await zone_fixture()
	var actor = data.actor
	actor.set_physics_process(false)
	actor.position = Vector2(800, 390)
	var paths: Array[NodePath] = [actor.get_path_to(data.zone)]
	for activity in range(1, 4):
		var zone = ZONE.new()
		zone.polygon = data.zone.polygon
		zone.activity = activity
		zone._random.seed = 3300 + activity
		map.add_child(zone)
		paths.append(actor.get_path_to(zone))
	actor.activity_zone_paths.assign(paths)
	weights(actor, 25, 45, 20, 10)
	var counts := [0, 0, 0, 0]
	for sample in range(1000):
		actor._choose_destination(actor.navigation_agent.get_navigation_map())
		if actor.current_zone != null: counts[actor.current_activity] += 1
	check(counts[1] > 350 and counts[1] < 550 and counts[0] > 150 and counts[2] > 120 and counts[3] > 40,
		"Four available polygon activities retain weighted selection over 1000 choices: " + str(counts))
	await clear_map()


func check_playground() -> void:
	map = load("res://tests/fixtures/activity_zone_playground.tscn").instantiate()
	root.add_child(map)
	var arrived := {}
	var valid := true
	for tick in range(1200):
		await frames(1)
		for index in range(4):
			var actor = map.villagers[index]
			if actor.is_performing_activity:
				arrived[index] = true
				valid = valid and actor.current_zone != null and actor.current_zone.activity == index and actor.current_zone.contains_world_point(actor.position)
	check(arrived.size() == 4 and valid and map.total_residents == 4, "F6 playground loads four representative activities and all residents physically reach assigned zones")
	await clear_map()
