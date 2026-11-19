extends SceneTree

const MISSION_ONE = preload("res://scenes/village_simulation_map.tscn")
const TEST_MAP = preload("res://scenes/test_map.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")

class MeasuredMission extends "res://scripts/test_map.gd":
	var candidate_scans := 0

	func _available_command_units() -> Array[Node]:
		candidate_scans += 1
		return super._available_command_units()

var mission: Node2D
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func until(predicate: Callable, limit: int) -> bool:
	for index in limit:
		if predicate.call():
			return true
		await frames(1)
	return predicate.call()


func setup(scene: PackedScene, race: String, measured := false) -> void:
	if is_instance_valid(mission):
		mission.queue_free()
		await frames(2)
	mission = scene.instantiate()
	if measured:
		mission.placement.free()
		mission.command_overlay.free()
		mission.set_script(MeasuredMission)
	mission.set_meta("race_id", race)
	root.add_child(mission)
	for resident in mission.villagers:
		resident.autonomous_movement_enabled = false
		resident.threat_detection.detection_enabled = false
		resident.set_physics_process(false)
	await until(func(): return NavigationServer2D.map_get_iteration_id(
		mission.get_world_2d().navigation_map) > 0, 120)
	await frames(4)


func mouse(button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = root.get_canvas_transform() * point
	mission._input(event)


func click_hud(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func center_camera(point: Vector2) -> void:
	var camera: Camera2D = mission.get_node("Camera2D")
	camera.global_position = point
	camera.force_update_scroll()


func spawn(point: Vector2, frozen := true) -> Node2D:
	var unit := ZOMBIE.instantiate() as CharacterBody2D
	unit.position = point
	mission.add_child(unit)
	unit.set_physics_process(not frozen)
	if frozen:
		unit.navigation_agent.avoidance_enabled = false
	return unit


func convert_resident(resident: Node2D) -> Node2D:
	var previous := get_nodes_in_group("player_units")
	resident.apply_player_infection(10.0)
	resident.take_damage(1000.0)
	for unit in get_nodes_in_group("player_units"):
		if not previous.has(unit):
			unit.set_physics_process(false)
			unit.navigation_agent.avoidance_enabled = false
			return unit
	return null


func run() -> void:
	seed(3003)
	root.size = Vector2i(1280, 720)
	await race_and_global_orders()
	await assault_input()
	await building_exit()
	await horde_placement()
	mission.queue_free()
	await frames(2)
	print("IDEA-003: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)


func race_and_global_orders() -> void:
	await setup(MISSION_ONE, "manual_test")
	var manual := spawn(Vector2(650, 1000))
	await frames(2)
	check(mission.horde_commands == null and mission.mission_hud.global_cancel_button == null,
		"Mission 1 standalone default is overridden by the supplied race")
	center_camera(manual.global_position)
	mouse(MOUSE_BUTTON_LEFT, true, manual.global_position)
	mouse(MOUSE_BUTTON_LEFT, false, manual.global_position)
	await frames(2)
	check(manual.is_selected and mission._command_units() == [manual],
		"Manual command mode still supports click selection on Mission 1")

	await setup(TEST_MAP, "zombie")
	var units := get_nodes_in_group("player_units")
	for index in units.size():
		units[index].global_position = [Vector2(110, 340), Vector2(200, 420), Vector2(590, 360)][index]
		units[index].set_physics_process(false)
	for resident in mission.villagers:
		resident.global_position = Vector2(1160, 590)
	await frames(2)
	var horde = mission.horde_commands
	check(horde != null and mission.mission_hud.monster_button == null,
		"Zombie race activates global control on a different map")
	var first: Node2D = units[0]
	mouse(MOUSE_BUTTON_LEFT, true, first.global_position)
	mouse(MOUSE_BUTTON_LEFT, false, first.global_position)
	await frames(2)
	check(units.all(func(unit): return not unit.is_selected), "LMB never selects playable zombies")
	var center := Vector2(430, 360)
	mouse(MOUSE_BUTTON_RIGHT, true, Vector2(390, 360))
	check(mission.command_active and horde.order == horde.Order.NONE, "RMB previews before global dispatch")
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_canvas_transform() * center
	mission._input(motion)
	mission._update_command_preview(0.2)
	check(mission.command_center.is_equal_approx(center) and is_equal_approx(mission.command_radius, 64.0),
		"IDEA-001 preview follows the cursor and grows linearly")
	mouse(MOUSE_BUTTON_RIGHT, false, center)
	check(units.all(func(unit): return unit.follows_horde_order and unit.has_target),
		"Every exterior zombie receives the movement order across the map")
	var old_destinations: Dictionary = horde.move_slots.duplicate()
	for unit in units:
		unit.global_position = unit.target_position
		unit._finish_movement_target()
	var moved := convert_resident(mission.villagers[2])
	check(horde.order == horde.Order.MOVE and moved != null and moved.follows_horde_order
		and units.all(func(unit): return not unit.has_player_order and unit.target_position == old_destinations[unit])
		and not old_destinations.values().has(moved.target_position),
		"Outdoor conversion inherits completed movement without changing existing slots")

	var targets: Array = [mission.villagers[0], mission.villagers[1]]
	targets[0].global_position = Vector2(710, 350)
	targets[1].global_position = Vector2(740, 350)
	mission._issue_command(Vector2(725, 350), 36.0)
	check(horde.order == horde.Order.ATTACK and first.priority_targets == targets
		and units[1].priority_targets == [targets[1], targets[0]],
		"Global attack replaces movement and retains cyclic first-target assignment")
	var reinforcement := convert_resident(mission.villagers[3])
	check(reinforcement != null and reinforcement.priority_targets.size() == 2
		and reinforcement.follows_horde_order, "Outdoor conversion inherits the original attack list")
	targets[0].take_damage(1000.0)
	first._update_aggro_target(0.0)
	check(first.aggro_target == targets[1], "Existing attack AI retargets surviving designated enemies")
	click_hud(mission.mission_hud.global_cancel_button)
	check(horde.order == horde.Order.NONE and first.priority_targets.is_empty()
		and first.aggro_target == null and not first.has_target, "Cancel button stops the active attack")
	first.aggro_candidates.clear()
	first._update_aggro_target(0.0)
	check(not first.has_target, "With nobody nearby cancellation leaves the zombie idle")
	mission._issue_area_move_order(center, 24.0)
	var enemy: Node2D = targets[1]
	enemy.global_position = first.global_position + Vector2(32, 0)
	await frames(3)
	check(first.aggro_candidates.has(enemy), "Detection still observes enemies during an order")
	click_hud(mission.mission_hud.global_cancel_button)
	first._update_aggro_target(0.0)
	check(first.aggro_target == enemy and first.has_target and not first.has_player_order,
		"Cancelling movement restores autonomous pursuit of a detected enemy")

	mission._issue_area_move_order(center, 24.0)
	mouse(MOUSE_BUTTON_RIGHT, true, center)
	click_hud(mission.mission_hud.global_cancel_button)
	mouse(MOUSE_BUTTON_RIGHT, false, center)
	check(not mission.command_active and horde.order == horde.Order.NONE,
		"Cancelling the global order disarms any unfinished circle before RMB release")

	mission._issue_command(enemy.global_position, 4.0)
	enemy.take_damage(1000.0)
	mission._process(0.0)
	check(horde.order == horde.Order.NONE and mission.mission_hud.global_cancel_button.disabled,
		"Attack order expires when the original exterior target list is exhausted")


func assault_input() -> void:
	await setup(MISSION_ONE, "zombie", true)
	var horde = mission.horde_commands
	var hud: Control = mission.mission_hud
	var first: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]
	var second: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home2")]
	var nav: RID = mission.get_world_2d().navigation_map
	var goal := NavigationServer2D.map_get_closest_point(nav, Vector2(800, 800))
	center_camera(first.global_position)
	mission._issue_area_move_order(goal, 48.0)
	click_hud(hud.building_button)
	mouse(MOUSE_BUTTON_LEFT, true, first.global_position)
	mouse(MOUSE_BUTTON_LEFT, false, first.global_position)
	mouse(MOUSE_BUTTON_RIGHT, false, first.global_position)
	check(not mission.choosing_building and not hud.building_button.button_pressed
		and hud.assault_status.text.is_empty() and first.attackers.is_empty()
		and horde.order == horde.Order.MOVE, "World LMB exits armed assault mode before any hold")

	click_hud(hud.building_button)
	mouse(MOUSE_BUTTON_RIGHT, true, first.global_position)
	mouse(MOUSE_BUTTON_RIGHT, false, first.global_position)
	check(mission.choosing_building and "Нет доступных" in hud.assault_status.text
		and horde.order == horde.Order.MOVE, "Zero candidates keeps assault mode and the active global command")

	var near := spawn(first.layout.exterior(22.0))
	var second_nearest := spawn(first.layout.exterior(45.0, 12.0))
	var far := spawn(first.layout.exterior(82.0, -18.0))
	await frames(3)
	mission._issue_area_move_order(goal, 48.0)
	check(near.follows_horde_order and far.follows_horde_order, "Exterior fixture zombies have a prior global move")
	var far_destination: Vector2 = far.target_position
	mission.candidate_scans = 0
	mouse(MOUSE_BUTTON_RIGHT, true, first.global_position)
	check(horde.assault_quantity == 1 and horde.assault_building == first, "RMB locks the building and starts at one")
	mission._process(0.34)
	check(horde.assault_quantity == 1, "Counter waits for the configured first interval")
	mission._process(0.01)
	hud.refresh_units()
	await frames(2)
	check(horde.assault_quantity == 2 and mission.candidate_scans == 0 and first.attackers.is_empty()
		and "2" in hud.assault_status.text, "Hold updates quantity and HUD without accessing candidates")
	click_hud(hud.global_cancel_button)
	mouse(MOUSE_BUTTON_RIGHT, false, first.global_position)
	check(mission.candidate_scans == 0 and horde.assault_quantity == 0 and mission.choosing_building
		and first.attackers.is_empty() and near.follows_horde_order and far.target_position == far_destination,
		"LMB during hold cancels preparation without also clicking the HUD or dispatching")

	mouse(MOUSE_BUTTON_RIGHT, true, first.global_position)
	mission._process(0.35)
	# Membership is determined at release, even when an actor moves during preparation.
	near.global_position = first.layout.exterior(105.0)
	far.global_position = first.layout.exterior(24.0)
	mouse(MOUSE_BUTTON_RIGHT, false, first.global_position)
	check(mission.candidate_scans == 1 and far.building_task == first and second_nearest.building_task == first
		and near.building_task == null and near.follows_horde_order and not mission.choosing_building
		and "2" in hud.assault_status.text and horde.order == horde.Order.MOVE,
		"RMB release scans once, dispatches the two nearest door candidates and preserves other orders")
	click_hud(hud.global_cancel_button)
	check(not near.follows_horde_order and far.building_task == first and second_nearest.building_task == first
		and hud.assault_status.text.is_empty() and hud.global_cancel_button.disabled,
		"Global cancellation clears assault feedback and preserves confirmed assaults")

	far.global_position = second.layout.exterior(22.0)
	second_nearest.global_position = second.layout.exterior(88.0)
	center_camera(second.global_position)
	click_hud(hud.building_button)
	mouse(MOUSE_BUTTON_RIGHT, true, second.global_position)
	mouse(MOUSE_BUTTON_RIGHT, false, second.global_position)
	check(far.building_task == second and not first.attackers.has(far) and second_nearest.building_task == first,
		"New assault may reassign the nearest exterior attacker from another building")
	check(horde.order == horde.Order.NONE and not hud.global_cancel_button.disabled,
		"Assault confirmation can be dismissed even without a global order")
	click_hud(hud.global_cancel_button)
	check(hud.assault_status.text.is_empty() and far.building_task == second and second_nearest.building_task == first,
		"Hiding an assault-only confirmation leaves both assignments in place")

	click_hud(hud.building_button)
	mouse(MOUSE_BUTTON_RIGHT, true, second.global_position)
	mission._process(3.5)
	check(horde.assault_quantity == 11, "Large quantity grows at the same constant rate")
	mouse(MOUSE_BUTTON_RIGHT, false, second.global_position)
	check(second.attackers.size() == 3 and "3" in hud.assault_status.text and not mission.choosing_building,
		"An oversized request sends all available zombies and reports the actual count")
	center_camera(goal)
	mouse(MOUSE_BUTTON_RIGHT, true, goal)
	mouse(MOUSE_BUTTON_RIGHT, false, goal)
	check(horde.order == horde.Order.MOVE and second.attackers.is_empty() and first.attackers.is_empty()
		and [near, far, second_nearest].all(func(unit): return unit.follows_horde_order)
		and hud.assault_status.text.is_empty(),
		"Next ordinary RMB command overrides exterior assault assignments and clears the prior confirmation")


func building_exit() -> void:
	await setup(MISSION_ONE, "zombie")
	var house: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]
	var navigation_ready := func() -> bool:
		return NavigationServer2D.map_get_iteration_id(house.layout.map) > 0 and house.shelter_approach().is_finite()
	if not await until(navigation_ready, 300):
		check(false, "Navigation synchronizes at the shelter entrance")
		return
	var resident: Node2D = mission.villagers[0]
	resident.global_position = house.layout.exterior(42.0)
	resident.attack_damage = 0.0
	var sheltered := house.request_shelter(resident) and await until(func(): return resident.interior_building == house, 160)
	check(sheltered, "Resident physically shelters before the assault")
	if not sheltered:
		print("Shelter state: ", resident.global_position, " door approach ", house.shelter_approach(),
			" crossing ", house._crossing, " active lane ", house._crossing_approach)
		return
	var previous_resident: Node2D = mission.villagers[1]
	previous_resident.global_position = Vector2(170, 900)
	var autonomous := convert_resident(previous_resident)
	check(autonomous != null and autonomous.can_receive_player_orders()
		and not autonomous.has_target and not autonomous.follows_horde_order,
		"Outdoor conversion without an active global order is autonomous")
	house.door_hp = 0.0
	house._refresh_entrance()
	var unit := spawn(house.layout.exterior(62.0), false)
	unit.infection_chance = 0.0
	unit.attack_damage = 0.0
	unit.issue_player_building_order(house)
	check(await until(func(): return unit.interior_building == house, 360) and house.battle_active,
		"Zombie enters physically and participates in the existing battle")
	mission.mission_hud.refresh_units()
	check(mission.mission_hud.monster_count.text == "Монстры: 2" and mission._available_command_units() == [autonomous],
		"HUD counts the zombie inside the building while orders only reach the exterior zombie")
	mission._issue_area_move_order(Vector2(240, 530), 48.0)
	check(not unit.can_receive_player_orders() and unit.building_task == house and not unit.follows_horde_order,
		"Global orders exclude interior combatants")
	mission.cancel_global_order()
	check(house.battle_active and unit.interior_building == house, "Global cancellation cannot stop the interior battle")
	unit.attack_damage = 1000.0
	check(await until(func(): return resident.is_dead(), 300), "Autonomous building combat resolves with existing attacks")
	check(await until(func(): return unit.clearing_building_exit, 240), "Physically exited zombie starts the door-clearance movement")
	var clearance_destination: Vector2 = unit.target_position
	mission._issue_area_move_order(Vector2(240, 530), 48.0)
	check(not unit.can_receive_player_orders() and unit.target_position == clearance_destination
		and not unit.follows_horde_order, "New global order cannot interrupt the doorway clearance")
	check(await until(func(): return unit.follows_horde_order, 240) and unit.can_receive_player_orders()
		and unit.global_position.distance_to(clearance_destination) <= 10.0,
		"Zombie reaches the clearance point before inheriting the latest movement")
	unit.take_damage(1000.0)
	mission.mission_hud.refresh_units()
	check(mission.mission_hud.monster_count.text == "Монстры: 1", "A zombie death reduces the total count")


func horde_placement() -> void:
	await setup(TEST_MAP, "zombie")
	for resident in mission.villagers:
		resident.global_position = Vector2(1160, 600)
	var initial := get_nodes_in_group("player_units")
	for unit in initial:
		unit.queue_free()
	await frames(2)
	var center := Vector2(430, 360)
	var nav: RID = mission.get_world_2d().navigation_map
	var wave: Array[Node2D] = []
	for index in 6:
		var point := Vector2(73.0 + 28.0 * (index % 7), 142.0 + 32.0 * floorf(index / 7.0))
		wave.append(spawn(point))
	await frames(2)
	var roomy_center := Vector2(375, 360)
	var fills_interior := true
	for trial in range(4):
		seed(49 + trial)
		mission._issue_area_move_order(roomy_center, 160.0)
		var destinations: Array[Vector2] = []
		for unit in wave:
			if unit.follows_horde_order:
				destinations.append(unit.target_position)
		fills_interior = fills_interior and destinations.size() == wave.size() and destinations.all(
			func(point): return point.distance_to(roomy_center) <= 160.0)
		fills_interior = fills_interior and destinations.any(func(point): return point.distance_to(roomy_center) <= 16.0)
		fills_interior = fills_interior and destinations.filter(func(point): return point.distance_to(roomy_center) < 120.0).size() >= 3
	check(fills_interior, "Six zombies with room to spare use the center and interior across random draws")

	for index in range(6, 40):
		var point := Vector2(73.0 + 28.0 * (index % 7), 142.0 + 32.0 * floorf(index / 7.0))
		wave.append(spawn(point))
	await frames(2)
	seed(3003)
	var started := Time.get_ticks_usec()
	mission._issue_area_move_order(center, 24.0)
	print("40-zombie command dispatch in ms: ", (Time.get_ticks_usec() - started) / 1000.0)
	var destinations: Array[Vector2] = []
	var inside := 0
	for unit in wave:
		var point: Vector2 = unit.target_position
		var route := NavigationServer2D.map_get_path(nav, unit.global_position, point, true)
		if unit.follows_horde_order and not route.is_empty() and route[-1].distance_to(point) < 2.0:
			if not destinations.has(point) and mission._building_at(point) == null:
				destinations.append(point)
				if point.distance_to(center) <= 24.0:
					inside += 1
	check(destinations.size() == wave.size() and inside > 0 and inside < wave.size(),
		"Large horde fills the small circle and spills to distinct reachable positions outside buildings")
	var delayed: Node2D = wave[0]
	var failed_slot: Vector2 = delayed.target_position
	var neighbor_slot: Vector2 = wave[1].target_position
	delayed._finish_movement_target()
	check(await until(func(): return delayed.follows_horde_order, 90)
		and delayed.target_position != failed_slot and wave[1].target_position == neighbor_slot,
		"A stalled global move can try a spare slot without rebuilding the horde assignment")
	wave[1]._finish_movement_target()
	mission.cancel_global_order()
	await frames(40)
	check(wave.all(func(unit): return not unit.follows_horde_order),
		"Cancellation also prevents a scheduled placement retry")

	for unit in wave:
		unit.queue_free()
	await frames(2)
	wave.clear()
	for index in 6:
		wave.append(spawn(Vector2(175 + 27 * (index % 3), 214 + 32 * floorf(index / 3.0)), false))
	await frames(2)
	seed(35)
	var gathering_center := Vector2(350, 371)
	mission._issue_area_move_order(gathering_center, 56.0)
	var gathered := func() -> bool:
		return wave.all(func(unit):
			return unit.last_move_reached or unit.global_position.distance_to(gathering_center) <= 64.0)
	var reached := await until(gathered, 1200)
	if not reached:
		print("Horde routes: ", wave.map(func(unit): return [unit.global_position, unit.target_position, unit.has_target, unit.last_move_reached]))
	check(reached,
		"Moving horde travels around authored obstacles and reaches the gathering area")
