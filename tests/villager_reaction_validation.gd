# Godot --headless --path . --script tests/villager_reaction_validation.gd --fixed-fps 60
extends "res://tests/villager_threat_validation.gd"

var response: Node2D
var warning_events := 0


func response_fixture(state: int) -> void:
	await fixture()
	response = resident.get_node("ThreatReaction")
	response.reactions_enabled = true
	response.flee_weight = 1 if state == response.Reaction.FLEEING else 0
	response.shelter_weight = 1 if state == response.Reaction.SEEKING_SHELTER else 0
	response.warning_weight = 1 if state == response.Reaction.WARNING else 0
	response.frozen_weight = 1 if state == response.Reaction.FROZEN else 0
	response.reaction_random.seed = 1404
	resident.autonomous_movement_enabled = true
	resident.wait_remaining = 100
	resident.current_activity = resident.Activity.WORK
	resident.is_performing_activity = true
	resident.warning_attempted.connect(func(source: Node2D, _position: Vector2):
		if source == resident:
			warning_events += 1)
	warning_events = 0
	sensor.recognition_delay_min = 0.1
	sensor.recognition_delay_max = 0.1
	zombie.position = Vector2(880, 390)


func run() -> void:
	await response_fixture(1)
	response.flee_weight = 50
	response.shelter_weight = 25
	response.warning_weight = 20
	response.frozen_weight = 5
	var counts := [0, 0, 0, 0, 0]
	for sample in range(10000):
		counts[response.choose_reaction()] += 1
	check(counts[1] > 4700 and counts[1] < 5300 and counts[2] > 2200 and counts[2] < 2800
		and counts[3] > 1700 and counts[3] < 2300 and counts[4] > 350 and counts[4] < 650,
		"Independent reaction RNG follows 50/25/20/5 weights: %s" % [counts])
	await clear_map()
	await check_escape()
	await check_continued_escape()
	await check_route_reassessment()
	await check_shelter()
	await check_warning_and_recovery()
	await check_frozen_and_combat()
	await check_post_combat_and_conversion()
	print("Villager reaction validation failures: ", failures)
	quit(1 if failures else 0)


func check_escape() -> void:
	await response_fixture(1)
	await frames(10)
	check(response.episode_active and response.reaction_state == response.Reaction.FLEEING
		and not resident.is_performing_activity and resident.current_activity == resident.Activity.NONE,
		"Confirmed threat interrupts peaceful activity and selects fleeing")
	var distance_before: float = resident.position.distance_to(zombie.position)
	var safe := true
	for frame in range(90):
		await frames(1)
		safe = safe and not overlaps_building(resident, resident.position)
	check(safe and resident.position.distance_to(zombie.position) > distance_before + 35,
		"Fleeing increases distance while respecting physical buildings")
	check(resident.navigation_agent.max_speed == 85, "Fleeing uses provisional speed 85")
	# Navigation failure must release a stale route and stay within the finite budget.
	resident.move_speed = 0
	response.fleeing_speed = 0
	response.safety_timeout = 30
	var tries_before: int = response.route_attempts
	await frames(220)
	check(response.route_attempts > tries_before and response.route_attempts <= response.max_route_attempts,
		"Blocked escape recovers with a bounded number of route attempts")
	zombie.queue_free()
	await frames(2)
	check(not is_instance_valid(response.threat_target), "Removed threat reference is cleared safely during response")
	await clear_map()
	# Escape near a house and navigation edge, with the same physical movement helper.
	await response_fixture(1)
	resident.position = Vector2(330, 175)
	zombie.position = Vector2(400, 175)
	await frames(10)
	safe = true
	var navigation_map: RID = map.get_world_2d().navigation_map
	for frame in range(100):
		await frames(1)
		safe = safe and not overlaps_building(resident, resident.position)
		if response.has_route:
			safe = safe and NavigationServer2D.map_get_closest_point(navigation_map, response.route_destination).distance_to(response.route_destination) < 1
	check(safe and resident.position.distance_to(zombie.position) > 100, "Escape routes near house stay on navigation and clear obstacles")
	await clear_map()


func check_continued_escape() -> void:
	await response_fixture(1)
	resident.position = Vector2(600, 360)
	zombie.position = Vector2(680, 360)
	# A slow test speed permits a chase longer than 12 seconds on the small map.
	response.fleeing_speed = 20
	response.max_route_attempts = 1
	response.threat_movement_threshold = 10000
	await frames(10)
	var destinations: Array[Vector2] = [response.route_destination]
	var moving_frames := 0
	var visible_frames := 0
	var reached_waypoints := 0
	var stayed_active := true
	var clear := true
	for frame in range(960):
		var previous_goal: Vector2 = response.route_destination
		var behind: Vector2 = -resident.velocity.normalized() if resident.velocity.length() > 1 else resident.position.direction_to(zombie.position)
		for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.57, -1.57, PI]:
			zombie.position = resident.position + behind.rotated(angle) * 35
			if sensor._is_visible_target(zombie) and not overlaps_building(zombie, zombie.position):
				break
		await frames(1)
		if response.route_destination != previous_goal and resident.position.distance_to(previous_goal) <= resident.arrival_tolerance:
			reached_waypoints += 1
		stayed_active = stayed_active and response.episode_active and response.reaction_state == response.Reaction.FLEEING
		if sensor._is_visible_target(zombie):
			visible_frames += 1
		if response.has_route and resident.velocity.length() > 1:
			moving_frames += 1
		if response.has_route and not destinations.has(response.route_destination):
			destinations.append(response.route_destination)
		if frame % 10 == 0:
			clear = clear and not overlaps_building(resident, resident.position)
	check(visible_frames > 900, "Long-chase fixture maintains visible danger for over 12 seconds")
	check(stayed_active and moving_frames > 900 and clear,
		"Visible danger keeps civilian fleeing beyond time and route-attempt limits")
	check(destinations.size() >= 2 and reached_waypoints >= 1,
		"Physically reaching escape waypoint immediately continues with another route during chase")
	zombie.queue_free()
	await frames(200)
	check(not response.episode_active, "Continued escape still ends after sustained safety")
	await clear_map()


func check_route_reassessment() -> void:
	await response_fixture(1)
	await frames(10)
	var elapsed_before: float = response.episode_elapsed
	zombie.position = Vector2(1100, 390)
	await frames(20)
	check(response.episode_active and sensor.awareness == sensor.Awareness.UNAWARE,
		"Brief loss of visibility preserves active response")
	zombie.position = resident.position + Vector2(80, 0)
	await frames(20)
	check(response.episode_active and response.episode_elapsed > elapsed_before + 0.5,
		"Reacquisition continues the same episode instead of restarting selection")
	var attempts_before: int = response.route_attempts
	zombie.position = resident.position + resident.position.direction_to(resident.navigation_agent.get_next_path_position()) * 25
	await frames(50)
	check(response.route_attempts > attempts_before and response.route_attempts <= response.max_route_attempts
		and (not response.has_route or response.route_destination.distance_to(zombie.position) >= response.threat_clearance),
		"Threat making escape unsafe triggers limited reassessment")
	await clear_map()


func check_shelter() -> void:
	await response_fixture(2)
	response.safety_timeout = 30
	response.max_response_duration = 30
	await frames(10)
	var home: Marker2D = resident.get_node(resident.home_point_path)
	check(response.reaction_state == response.Reaction.SEEKING_SHELTER and response.route_destination == home.global_position,
		"Shelter seeking prefers a safe assigned exterior home point")
	check(resident.navigation_agent.max_speed == response.fleeing_speed,
		"Shelter seeking uses the same running speed as fleeing")
	response.fleeing_speed = 90
	await frames(2)
	check(resident.navigation_agent.max_speed == 90,
		"Shelter seeking follows the shared configurable running speed")
	for frame in range(1100):
		if response.episode_active and not response.has_route:
			break
		await frames(1)
	check(resident.position.distance_to(home.global_position) <= resident.arrival_tolerance
		and resident.is_available_for_infection(), "Resident reaches exterior shelter and remains a valid combat target")
	var health: float = resident.current_health
	resident.take_damage(5)
	check(resident.current_health == health - 5, "Exterior shelter grants no damage immunity")
	await clear_map()
	await response_fixture(2)
	home = resident.get_node(resident.home_point_path)
	home.position = zombie.position + Vector2(5, 0)
	await frames(10)
	check(response.reaction_state == response.Reaction.SEEKING_SHELTER
		and response.route_destination != home.global_position and response.route_destination.distance_to(zombie.position) >= response.threat_clearance,
		"Unsafe home beside zombie is replaced by another safe exterior shelter")
	await clear_map()
	await response_fixture(2)
	home = resident.get_node(resident.home_point_path)
	home.position = Vector2(330, 245)
	for marker in map.get_node("VillagePointsOfInterest").get_children():
		marker.remove_from_group("civilian_shelter_points")
	await frames(10)
	check(response.episode_active and response.reaction_state != response.Reaction.SEEKING_SHELTER,
		"Unreachable home without other shelters falls back to escape")
	await clear_map()


func check_warning_and_recovery() -> void:
	await response_fixture(3)
	response.warning_duration = 0.5
	response.fleeing_speed = 0
	response.max_response_duration = 2
	await frames(10)
	check(response.reaction_state == response.Reaction.WARNING and warning_events == 0, "Warning prepares without immediate event")
	var stopped: Vector2 = resident.position
	await frames(15)
	check(warning_events == 0 and resident.position.is_equal_approx(stopped), "Warning waits its configured preparation duration")
	await frames(25)
	check(warning_events == 1 and response.reaction_state == response.Reaction.FLEEING, "Warning emits once then follows up with escape")
	var closer = frozen_zombie(resident.position + Vector2(-30, 0))
	await frames(400)
	check(response.episode_active and response.reaction_state == response.Reaction.FLEEING and warning_events == 1,
		"Continuous danger keeps escape active without repeated warning loops")
	closer.queue_free()
	# Brief occlusion cannot re-arm the completed episode.
	zombie.position = Vector2(1000, 390)
	await frames(30)
	zombie.position = Vector2(880, 390)
	await frames(50)
	check(warning_events == 1 and response.episode_active, "Brief threat loss and reacquisition do not reroll ongoing response")
	zombie.position = Vector2(1000, 390)
	await frames(200)
	check(resident.has_destination or resident.is_performing_activity or resident.wait_remaining > 0,
		"Villager returns to ordinary activity cycle after safety timeout")
	# The recovery cooldown now begins only after actual safety, not a time cap.
	await frames(250)
	resident._stop_movement()
	resident.position = Vector2(800, 390)
	resident.wait_remaining = 100
	zombie.position = Vector2(880, 390)
	await frames(50)
	check(warning_events == 2, "A genuinely new danger episode can warn again after sustained safety")
	await clear_map()
	await response_fixture(3)
	response.warning_duration = 1
	await frames(10)
	resident.take_damage(5)
	await frames(80)
	check(warning_events == 0 and response.reaction_state != response.Reaction.WARNING,
		"Nonlethal damage cancels pending warning even outside an encounter")
	await clear_map()
	await response_fixture(3)
	response.warning_duration = 1
	await frames(10)
	resident.begin_encounter(Color.GREEN, zombie)
	await frames(80)
	check(warning_events == 0 and not response.episode_active, "Combat cancels warning before completion")
	resident.take_damage(1000)
	await frames(80)
	check(warning_events == 0 and not response.has_route, "Dead villager cannot complete pending warning or react")
	await clear_map()


func check_frozen_and_combat() -> void:
	await response_fixture(4)
	response.frozen_duration = Vector2(1, 1)
	await frames(10)
	var stopped: Vector2 = resident.position
	await frames(40)
	check(response.reaction_state == response.Reaction.FROZEN and resident.position.is_equal_approx(stopped), "Frozen resident remains stationary for configured duration")
	await frames(25)
	check(response.reaction_state == response.Reaction.FLEEING and response.freeze_used,
		"Freeze ends with escape instead of another random freeze")
	resident.begin_encounter(Color.GREEN, zombie)
	stopped = resident.position
	resident._on_navigation_velocity_computed(Vector2(100, 0))
	check(not response.episode_active and not response.has_route and resident.position.is_equal_approx(stopped), "Combat cancels escape and rejects stale avoidance velocity")
	await clear_map()
	await response_fixture(4)
	await frames(10)
	var health: float = resident.current_health
	resident.begin_encounter(Color.GREEN, zombie)
	resident.receive_zombie_attack(20, 0, zombie)
	check(resident.current_health == health - 20 and resident.is_in_collision(), "Frozen civilian remains vulnerable to normal zombie damage")
	await clear_map()


func check_post_combat_and_conversion() -> void:
	await response_fixture(1)
	await frames(10)
	resident.begin_encounter(Color.GREEN, zombie)
	resident.leave_encounter(zombie)
	await frames(2)
	check(not resident.has_destination and response.reassessment_remaining > 0, "Cancelled encounter reassesses threat before starting peaceful route")
	await frames(10)
	check(response.episode_active and resident.is_available_for_infection(), "Survivor starts a fresh response to still-visible danger")
	var second = frozen_zombie(resident.position + Vector2(-30, 0))
	var original_state: int = response.reaction_state
	response.refresh_remaining = 0
	await frames(2)
	check(response.threat_target == second and response.reaction_state == original_state,
		"Substantially closer visible danger updates context without rerolling reaction")
	resident.begin_encounter(Color.GREEN, second)
	resident.receive_zombie_attack(20, 1.0, second)
	resident.leave_encounter(second)
	var position_before: Vector2 = resident.position
	await frames(60)
	check(resident.infection_state == resident.InfectionState.TRANSFORMING and not response.episode_active
		and resident.position.is_equal_approx(position_before), "Transformation permanently interrupts civilian response movement")
	var reference: WeakRef = weakref(resident)
	await frames(90)
	check(reference.get_ref() == null and map.infected_residents == 1 and map.killed_residents == 0,
		"Conversion after reaction still creates zombie and counts outcome exactly once")
	await clear_map()
	# An actual pursuing zombie can catch a faster-than-walking civilian.
	await response_fixture(1)
	zombie.set_physics_process(true)
	zombie.navigation_agent.avoidance_enabled = true
	zombie.infection_chance = 0
	var caught := false
	for frame in range(1000):
		await frames(1)
		if resident.is_in_collision():
			caught = true
			break
	check(caught, "Existing zombie pursuit can catch and attack a fleeing civilian")
	await clear_map()
