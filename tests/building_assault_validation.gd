extends SceneTree

const TEST_MAP = preload("res://scenes/test_map.tscn")
const SIMULATION_MAP = preload("res://scenes/village_simulation_map.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")

var failures := 0
var checks := 0
var mission: Node2D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func until(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await physics_frame
		await process_frame
	return predicate.call()


func setup(scene: PackedScene) -> void:
	if is_instance_valid(mission):
		mission.queue_free()
		await process_frame
	mission = scene.instantiate()
	root.add_child(mission)
	mission.set_process(false)
	for zombie in get_nodes_in_group("player_units"):
		zombie.queue_free()
	for resident in mission.villagers:
		resident.autonomous_movement_enabled = false
		resident.threat_detection.detection_enabled = false
		resident.threat_detection.debug_enabled = false
		resident.local_warning.debug_enabled = false
	await frames(4)


func spawn(at: Vector2) -> Node2D:
	var zombie := ZOMBIE.instantiate() as CharacterBody2D
	zombie.position = mission.to_local(at)
	zombie.infection_chance = 0.0
	mission.add_child(zombie)
	return zombie


func test_building(name: String) -> InteractiveBuilding:
	return mission.get_node("NavigationRegion2D/Solids/" + name + "/InteractiveBuilding") as InteractiveBuilding


func select_assault(zombie: Node2D, building: InteractiveBuilding) -> void:
	var selected: Array[Node] = [zombie]
	mission._apply_selection(selected)
	mission.mission_hud.building_button.pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_canvas_transform() * building.global_position
	mission._input(click)


func run() -> void:
	await geometry_and_noise()
	await ordinary_warning()
	await clear_and_convert()
	await simultaneous_assaults()
	await defend_and_rebuild()
	await outdoor_defense()
	await civilian_contact_defense()
	await repair_without_breach()
	await crowded_assault()
	mission.queue_free()
	await process_frame
	print("IDEA-002: ", checks - failures, "/", checks, " checks passed")
	quit(0 if failures == 0 else 1)


func geometry_and_noise() -> void:
	await setup(SIMULATION_MAP)
	await until(func(): return NavigationServer2D.map_get_closest_point(mission.get_world_2d().navigation_map, Vector2(800, 800)).length() > 0.0, 160)
	check(mission.buildings.size() == 25, "Mission 1 attaches interiors to all 25 authored entrances")
	var probe := ZOMBIE.instantiate() as CharacterBody2D
	var body_query := PhysicsShapeQueryParameters2D.new()
	body_query.shape = probe.get_node("CollisionShape2D").shape
	body_query.collision_mask = 1
	probe.free()
	var world := mission.get_world_2d() as World2D
	for building in mission.buildings:
		var layout: BuildingInterior = building.layout
		if not building.shelter_approach().is_finite() or NavigationServer2D.map_get_iteration_id(layout.map) == 0:
			var outdoor := mission.get_world_2d().navigation_map
			print(building.get_parent().name, " outside nav: ", NavigationServer2D.map_get_iteration_id(outdoor),
				" inside nav: ", NavigationServer2D.map_get_iteration_id(layout.map),
				" approach delta: ", NavigationServer2D.map_get_closest_point(outdoor, layout.exterior()).distance_to(layout.exterior()))
		check(building.shelter_approach().is_finite() and NavigationServer2D.map_get_iteration_id(layout.map) > 0,
			"Exterior access and synchronized interior navigation: " + str(building.get_parent().name))
		var clear := true
		for depth in [25.0, 12.0, 0.0, -12.0, -BuildingInterior.PORTAL_OFFSET]:
			body_query.transform = Transform2D(0.0, layout.exterior(depth))
			var hit := world.direct_space_state.intersect_shape(body_query, 1)
			if not hit.is_empty():
				print("Entrance collision: ", building.get_parent().name, " depth ", depth, " with ", hit[0].collider.get_path(), " at ", body_query.transform.origin)
				clear = false
		for repair in layout.repair_points:
			var goal := layout.to_global(repair)
			var path := NavigationServer2D.map_get_path(layout.map, layout.interior(), goal, true)
			if path.is_empty() or path[-1].distance_to(goal) > 1.0:
				print("Repair path: ", building.get_parent().name, " ", path, " expected ", goal)
				clear = false
		check(clear, "Physical entrance and both repair positions are reachable: " + str(building.get_parent().name))
	var cottage: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]
	var civilian: Node2D = mission.villagers[0]
	var guard: Node2D = mission.get_node("Villagers/Guard25")
	civilian.global_position = cottage.shelter_approach() + Vector2(45, 0)
	guard.global_position = cottage.shelter_approach() + Vector2(0, 55)
	mission.emit_break_in_noise(cottage, cottage.layout.exterior(0.0), cottage.shelter_approach())
	check(civilian.local_warning.has_report(), "Break-in uses civilian hearing")
	check(guard.guard_ai.memory.tasks.any(func(task): return task.report.get("kind") == &"break_in"),
		"Hearing offers a guard investigation at the entrance")
	check(mission.get_node("VillageAlert").level == 0, "Sound alone does not escalate the village")
	guard.autonomous_movement_enabled = true
	check(await until(func(): return guard.global_position.distance_to(cottage.shelter_approach()) <= 8.0, 210),
		"Guard uses the existing investigation route to the sound source")
	var camera: Camera2D = mission.get_node("Camera2D")
	camera._set_zoom_level(camera.max_zoom)
	check(await until(func(): return cottage.layout.roof[0].modulate.a == 0.0, 60), "Near-max zoom reveals the interior")
	camera._set_zoom_level(camera.min_zoom)
	check(await until(func(): return cottage.layout.roof[0].modulate.a == 1.0, 60), "Normal zoom restores the roof")
	var church: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Church")]
	var priest: Node2D = mission.get_node("Villagers/Priest30")
	guard.global_position = church.layout.exterior(40.0, -12.0)
	priest.global_position = church.layout.exterior(62.0, 25.0)
	check(church.request_shelter(guard) and church.request_shelter(priest), "Guard and priest can enter through an authored building entrance")
	check(await until(func(): return church.workers.has(guard) and church.workers.has(priest) and church.reinforcement > 0.03, 280),
		"Repair assignments accept guards and priests with the same rules")


func ordinary_warning() -> void:
	await setup(TEST_MAP)
	var witness: Node2D = mission.villagers[0]
	var listener: Node2D = mission.villagers[1]
	witness.global_position = Vector2(800, 390)
	listener.global_position = Vector2(680, 350)
	var threat := spawn(Vector2(880, 390))
	await frames(2)
	witness.autonomous_movement_enabled = true
	witness.threat_detection.recognized_target = threat
	witness.threat_reaction.seeking_home = true
	witness.local_warning._update_escape_warning()
	check(listener.local_warning.has_report() and listener.local_warning.reported_position == threat.global_position,
		"Existing escape cries still send civilian warnings through the shared hearing handler")


func clear_and_convert() -> void:
	await setup(TEST_MAP)
	check(mission.buildings.size() == 9, "Test map attaches interiors to its nine buildings")
	var house := test_building("HouseNW")
	var other := test_building("HouseSE")
	var resident: Node2D = mission.villagers[0]
	resident.autonomous_movement_enabled = true
	resident.global_position = mission.get_node("VillagePointsOfInterest/ResidentialStreet").global_position
	resident.threat_reaction.threat_position = Vector2(1100, 560)
	resident.threat_reaction.seeking_home = true
	check(await until(func(): return resident.interior_building == house, 210), "Existing shelter reaction physically enters the assigned house")
	check(house.door_closed and not house.layout.door_shape.disabled, "Shelter closes a solid original door")
	var reinforcement_at_entry := house.reinforcement
	await frames(120)
	check(house.reinforcement > reinforcement_at_entry and house.reinforcement < 1.0, "Original reinforcement increases gradually")
	var fighter := spawn(house.layout.exterior(72.0, -36.0))
	var reserve := spawn(house.layout.exterior(75.0, 35.0))
	var other_unit := spawn(other.layout.exterior(65.0))
	await frames(3)
	var selected: Array[Node] = [fighter]
	mission._apply_selection(selected)
	mission._issue_command(house.global_position, 50.0)
	check(fighter.building_task == null and fighter.priority_targets.is_empty(), "RMB over house does not attack it or include sheltered targets")
	select_assault(fighter, house)
	check(fighter.building_task == house and not mission.choosing_building, "Orders button and a map click select an explicit assault")
	var before_pause := fighter.global_position
	paused = true
	await frames(20)
	check(fighter.global_position == before_pause and house.door_hp == house.rules.door_health, "Tactical pause freezes assault movement and structure damage")
	paused = false
	other_unit.issue_player_building_order(other)
	check(other.attackers.has(other_unit) and house.attackers.has(fighter), "Different houses have independent attack orders")
	other_unit.issue_player_area_hold_order()
	check(not other.attackers.has(other_unit) and house.attackers.has(fighter), "Redirecting an approaching unit only cancels its assignment")
	check(await until(func(): return house.door_hp < house.rules.door_health, 240), "Assault approaches and damages the original door")
	house.rules.maximum_slowdown = 0.1
	var reinforced: float = house.reinforcement
	await frames(15)
	var gain: float = house.reinforcement - reinforced
	check(is_equal_approx(gain, 0.25 * 0.9 / house.rules.reinforcement_seconds), "A hit slows construction up to the configured cap")
	var damage: float = house.door_hp
	fighter.issue_player_move_order(house.layout.exterior(75.0))
	await frames(25)
	check(house.door_hp == damage and fighter.building_task == null, "Redirect during damage preserves door HP")
	fighter.infection_chance = 1.0
	fighter.issue_player_building_order(house)
	check(await until(func(): return fighter.interior_building == house, 650), "Zombie physically enters after breaching an unfinished door")
	check(house.door_hp == 0.0 and house.reinforcement_hp == 0.0, "Incomplete reinforcement collapses with the original door")
	fighter.issue_player_area_hold_order()
	fighter.set_selected(true)
	check(not fighter.is_selected and not fighter.can_receive_player_orders() and house.monsters.has(fighter), "Interior unit rejects selection and player orders")
	reserve.issue_player_building_order(house)
	check(reserve.can_receive_player_orders(), "Approaching reinforcement is still commandable")
	check(await until(func(): return resident.infection_state == resident.InfectionState.TRANSFORMING, 250), "Interior combat uses existing transformation state")
	check(house.battle_active, "Pending transformation keeps the battle unresolved")
	check(await until(func(): return mission.infected_residents == 1, 180), "Resident conversion counts through existing mission accounting")
	var converted: Node2D
	for zombie in get_nodes_in_group("player_units"):
		if zombie not in [fighter, reserve, other_unit]:
			converted = zombie
	check(converted != null and converted.interior_building == house and not converted.can_receive_player_orders(), "Converted zombie joins the same house with command lock")
	var exited := await until(func(): return fighter.can_receive_player_orders() and is_instance_valid(converted) and converted.can_receive_player_orders(), 480)
	if not exited:
		print("Exit diagnostic: ", house._crossing, " started ", house._crossing_started,
			" fighter ", house.layout.to_local(fighter.global_position), " converted ", house.layout.to_local(converted.global_position),
			" reserve ", house.layout.to_local(reserve.global_position), " door ", house.layout.entrance, " path ", house._paths)
	check(exited, "Survivors and conversions physically exit and regain command authority")
	check(await until(func(): return house.attackers.is_empty() and house.monsters.is_empty(), 300),
		"Cleared house finishes incoming orders and tracks no phantom occupants")


func simultaneous_assaults() -> void:
	await setup(TEST_MAP)
	var north := test_building("HouseNW")
	var south := test_building("HouseSE")
	var north_resident: Node2D = mission.villagers[0]
	var south_resident: Node2D = mission.villagers[2]
	north_resident.global_position = north.layout.exterior(40.0)
	south_resident.global_position = south.layout.exterior(40.0)
	north_resident.attack_damage = 0.0
	south_resident.attack_damage = 0.0
	north.request_shelter(north_resident)
	south.request_shelter(south_resident)
	check(await until(func(): return north.residents.size() == 1 and south.residents.size() == 1, 150),
		"Two buildings can shelter residents independently")
	var north_first := spawn(north.layout.exterior(50.0))
	var south_first := spawn(south.layout.exterior(50.0))
	north_first.attack_damage = 110.0
	south_first.attack_damage = 110.0
	north_first.issue_player_building_order(north)
	south_first.issue_player_building_order(south)
	check(await until(func(): return north.battle_active and south.battle_active, 200),
		"Two interior battles run simultaneously")
	north_first.attack_damage = 1.0
	south_first.attack_damage = 1.0
	var joining := spawn(north.layout.exterior(70.0, -28.0))
	var redirected := spawn(north.layout.exterior(90.0, 28.0))
	joining.attack_damage = 1.0
	joining.issue_player_building_order(north)
	redirected.issue_player_building_order(north)
	redirected.issue_player_move_order(north.layout.exterior(85.0, 35.0))
	var joined := await until(func(): return joining.interior_building == north, 240)
	if not joined:
		print("Join diagnostic: ", north._crossing, " started ", north._crossing_started, " entering ",
			north.layout.to_local(joining.global_position), " first ", north.layout.to_local(north_first.global_position),
			" resident ", north.layout.to_local(north_resident.global_position), " door ", north.layout.entrance)
	check(joined, "Additional attackers physically enter an ongoing battle")
	check(north.monsters.size() == 2 and south.monsters.size() == 1 and redirected.can_receive_player_orders() and redirected.building_task == null,
		"Reinforcements join one encounter, with per-unit cancellation outside")


func defend_and_rebuild() -> void:
	await setup(TEST_MAP)
	var house := test_building("HouseNE")
	var defender: Node2D = mission.villagers[1]
	var helper: Node2D = mission.villagers[3]
	defender.global_position = house.layout.exterior(43.0)
	helper.global_position = house.layout.exterior(60.0, 30.0)
	check(house.request_shelter(defender) and house.request_shelter(helper), "Two residents can request the same shelter")
	check(await until(func(): return house.residents.size() == 2, 280), "Second resident passes through the original door without overlapping the first")
	check(await until(func(): return house.reinforcement == 1.0, 850), "Workers finish the original reinforcement")
	var first := spawn(house.layout.exterior(54.0))
	first.attack_damage = 150.0
	first.current_health = 5.0
	first.issue_player_building_order(house)
	check(await until(func(): return house.door_hp == 0.0, 170), "Strong strike destroys the original door")
	check(house.reinforcement_hp > 0.0 and not house.layout.door_shape.disabled, "Completed reinforcement remains a solid obstacle")
	var incoming := spawn(house.layout.exterior(115.0, 35.0))
	incoming.move_speed = 2.0
	incoming.issue_player_building_order(house)
	defender.current_health = 50.0
	helper.current_health = 50.0
	check(await until(func(): return first.is_dead, 480), "Residents defend physically with existing melee damage")
	await frames(3)
	check(house.recovery_remaining > 4.5 and house.attackers.has(incoming), "Defeat starts the full pause and keeps incoming orders")
	var defender_hp: float = defender.current_health
	var helper_hp: float = helper.current_health
	await frames(60)
	check(defender.current_health == defender_hp and helper.current_health == helper_hp, "No healing during the post-combat pause")
	check(await until(func(): return house.recovery_remaining == 0.0, 330), "Post-combat pause expires")
	await frames(20)
	if defender.current_health <= defender_hp or helper.current_health <= helper_hp:
		print("Healing diagnostic: ", defender_hp, " -> ", defender.current_health, "; ", helper_hp, " -> ", helper.current_health, " workers ", house.workers, " active ", house.battle_active, " damage ", house.damage_remaining)
	check(defender.current_health > defender_hp and helper.current_health > helper_hp, "Survivors recover actual HP")
	check(house.damage_remaining > 0.0 and house.barricade_hp == 0.0 and house.layout.door_shape.disabled,
		"Damage cooldown runs in parallel while the entrance stays open")
	check(await until(func(): return house.barricade_hp > 0.0, 490), "Survivors build from zero when eligible")
	check(house.barricade_hp < 1.0 and not house.layout.door_shape.disabled, "First positive HP immediately blocks passage")
	await until(func(): return (house.workers[0] != null and house.workers[1] != null and
		house.workers[0].global_position.distance_to(house.layout.to_global(house.layout.repair_points[0])) <= house.ARRIVAL and
		house.workers[1].global_position.distance_to(house.layout.to_global(house.layout.repair_points[1])) <= house.ARRIVAL), 150)
	var work_hp := house.barricade_hp
	await frames(60)
	if house.barricade_hp - work_hp <= house.rules.build_per_second:
		print("Repair diagnostic: ", work_hp, " -> ", house.barricade_hp, " workers ", house.workers, " positions ",
			house.layout.to_local(defender.global_position), " ", house.layout.to_local(helper.global_position), " goals ", house.layout.repair_points)
	check(house.workers.has(defender) and house.workers.has(helper) and house.barricade_hp - work_hp > house.rules.build_per_second,
		"Both assigned workers contribute with diminishing efficiency")
	check(house.barricade_hp - work_hp < 2.0 * house.rules.build_per_second, "The second repair worker contributes less than the first")
	check(await until(func(): return house.barricade_hp == house.rules.barricade_health, 650), "Temporary barricade reaches configured HP")
	incoming.attack_damage = 5.0
	incoming.move_speed = 100.0
	defender.current_health = 60.0
	var hit := await until(func(): return house.barricade_hp < house.rules.barricade_health, 200)
	if not hit:
		print("Hit diagnostic: ", house.layout.to_local(incoming.global_position), " door ", house.layout.entrance,
			" depth ", house.layout.depth(incoming), " crossing ", house._crossing, " orders ", house.attackers, " path ", house._paths)
	check(hit, "Zombie hits reduce temporary barricade HP")
	check(house.layout.barricade_bar.visible and house.layout.barricade_ratio < 1.0,
		"Damage reduces the temporary barricade bar fill")
	var exterior_hp: float = defender.current_health
	await frames(45)
	check(defender.current_health > exterior_hp and not house.battle_active, "A non-repairing resident heals during exterior damage")
	incoming.issue_player_area_hold_order()
	var damaged_barricade := house.barricade_hp
	await frames(45)
	check(house.barricade_hp == damaged_barricade and house.damage_remaining > 0.0, "Cancellation leaves temporary barricade damage and repair delay intact")
	incoming.current_health = 5.0
	incoming.attack_damage = 150.0
	incoming.issue_player_building_order(house)
	check(await until(func(): return house.battle_active, 180), "A later wave destroys the temporary barricade and reopens the battle")
	check(house.barricade_hp == 0.0 and house.door_hp == 0.0 and house.layout.door_shape.disabled,
		"Zero HP reopens the doorway and never restores the original door")
	check(await until(func(): return incoming.is_dead, 300), "Second defense uses the same physical combat")
	await frames(3)
	check(house.recovery_remaining > 4.5, "Second defense restarts the full recovery pause")

	# Let workers reach their stations, then enable building on the exact
	# crossing frame to exercise the collision resolution deterministically.
	var speed := house.rules.build_per_second
	house.rules.build_per_second = 0.0
	await until(func(): return house.damage_remaining == 0.0, 640)
	await frames(150)
	var crossing := spawn(house.layout.exterior(37.0))
	crossing.issue_player_building_order(house)
	check(await until(func(): return house._crossing_started and absf(house.layout.depth(crossing)) < 5.0, 150),
		"Zombie can partially cross an open doorway")
	house.rules.build_per_second = speed
	await frames(1)
	check(house.barricade_hp > 0.0 and not house.layout.door_shape.disabled
		and house.layout.depth(crossing) >= house.layout.clearance(crossing),
		"First HP clears the intersecting body to the exterior before enabling collision")
	check(crossing.current_health == crossing.max_health and house.attackers.has(crossing)
		and float(house.attackers[crossing].next_hit) > house._elapsed,
		"Displacement preserves HP and the assault order and applies the short attack delay")


func setup_mission_cottage() -> InteractiveBuilding:
	await setup(SIMULATION_MAP)
	await until(func(): return NavigationServer2D.map_get_closest_point(mission.get_world_2d().navigation_map, Vector2(800, 800)).length() > 0.0, 160)
	return mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]


func outdoor_defense() -> void:
	var house := await setup_mission_cottage()
	var guard: Node2D = mission.get_node("Villagers/Guard25")
	var resident: Node2D = mission.villagers[0]
	var removed := Node2D.new()
	guard.guard_ai.local_allies.append(removed)
	removed.free()
	var investigation = guard.guard_ai.investigation
	investigation.phase = investigation.Phase.APPROACH
	investigation.report = {"incident": 1}
	guard.guard_ai.next_recruitment = 0.0
	investigation.recruit_locally()
	check(guard.guard_ai.available_local_allies().is_empty() and guard.guard_ai.next_recruitment > 0.0,
		"Investigation safely skips a resident freed after the local scan")
	investigation.phase = investigation.Phase.NONE
	resident.global_position = house.layout.exterior(42.0)
	guard.global_position = house.layout.exterior(90.0)
	house.request_shelter(resident)
	check(await until(func(): return resident.interior_building == house, 140), "Outdoor defense fixture closes the door")
	var attacker := spawn(house.layout.exterior(52.0))
	attacker.attack_damage = 2.0
	attacker.issue_player_building_order(house)
	check(await until(func(): return house.door_hp < house.rules.door_health, 150), "Outdoor defender can see an attacker at a closed door")
	guard.guard_ai.territory_margin = 10000.0
	guard.threat_detection.detection_enabled = true
	guard.autonomous_movement_enabled = true
	check(await until(func(): return attacker.current_health < attacker.max_health, 280),
		"Guard approaches reachable melee range and damages the zombie before entry")
	check(house.door_hp > 0.0 and attacker.interior_building == null and attacker.building_task == house,
		"Outdoor melee leaves the building order assigned and the unit commandable")


func civilian_contact_defense() -> void:
	var house := await setup_mission_cottage()
	var sheltering: Node2D = mission.villagers[0]
	sheltering.global_position = house.layout.exterior(45.0)
	house.request_shelter(sheltering)
	await until(func(): return sheltering.interior_building == house, 140)
	var attacker := spawn(house.layout.exterior(58.0))
	attacker.attack_damage = 1.0
	attacker.issue_player_building_order(house)
	await until(func(): return house.door_hp < house.rules.door_health, 150)
	var passerby: Node2D = mission.villagers[1]
	passerby.global_position = attacker.global_position + Vector2(16.0, 0.0)
	check(await until(func(): return attacker.current_health < attacker.max_health, 160),
		"A civilian caught in direct contact can strike back during an outdoor assault")


func repair_without_breach() -> void:
	var house := await setup_mission_cottage()
	var resident: Node2D = mission.villagers[0]
	resident.global_position = house.layout.exterior(46.0)
	house.rules.damage_cooldown = 1.0
	house.request_shelter(resident)
	check(await until(func(): return house.layout.barricade_bar.visible and house.reinforcement > 0.01, 190),
		"Barricade bar displays gradual initial reinforcement")
	var attacker := spawn(house.layout.exterior(61.0))
	attacker.attack_damage = 160.0
	attacker.issue_player_building_order(house)
	check(await until(func(): return house.door_hp == 0.0, 150), "An outdoor attacker destroys the original entrance")
	attacker.issue_player_move_order(house.layout.exterior(80.0, 25.0))
	check(not house.battle_active and not house.layout.barricade_bar.visible and house.barricade_hp == 0.0,
		"The ruined entrance has zero HP and no bar while awaiting repairs")
	check(await until(func(): return house.barricade_hp > 0.0, 240),
		"A survivor rebuilds after an aborted breach with no interior battle")
	check(is_equal_approx(house.layout.barricade_ratio, house.barricade_hp / house.rules.barricade_health),
		"Temporary barricade fill directly reflects its current HP")


func crowded_assault() -> void:
	var house := await setup_mission_cottage()
	var resident: Node2D = mission.villagers[0]
	resident.global_position = house.layout.exterior(42.0)
	resident.max_health = 600.0
	resident.current_health = 600.0
	resident.attack_damage = 0.0
	house.request_shelter(resident)
	await until(func(): return resident.interior_building == house, 140)
	var wave: Array[Node2D] = []
	for side in [0.0, 24.0, 48.0, 72.0]:
		var zombie := spawn(house.layout.exterior(62.0, side))
		wave.append(zombie)
		zombie.issue_player_building_order(house)
	var entered := await until(func(): return house.monsters.size() == wave.size(), 520)
	if not entered:
		print("Crowd diagnostic: lane ", house._crossing_lane, " door ", house.layout.entrance,
			" residents ", house.layout.to_local(resident.global_position), " inside ", house.monsters.size(),
			" depths ", wave.map(func(zombie): return house.layout.depth(zombie)),
			" positions ", wave.map(func(zombie): return house.layout.to_local(zombie.global_position)),
			" targets ", wave.map(func(zombie): return zombie.aggro_target), " melee ", house._melee_positions)
	check(entered, "Four tightly grouped assaulters pass through a shared doorway")
	var contacts := await until(func(): return resident.encounter_participants.size() >= 2, 300)
	if not contacts:
		print("Melee diagnostic: target ", resident.global_position, " positions ",
			wave.map(func(zombie): return [zombie.global_position, zombie.global_position.distance_to(resident.global_position), zombie._has_line_of_sight(resident)]),
			" melee ", house._melee_positions, " paths ", house._paths)
	check(contacts, "Interior combatants can reach separate melee contacts on the same resident")
