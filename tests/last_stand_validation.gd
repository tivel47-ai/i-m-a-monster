extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const MONSTER = preload("res://scenes/zombie.tscn")
const SECTION = preload("res://scripts/last_stand_barricade.gd")

var mission: Node2D
var last: Node
var defense: Node
var formation: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, description: String) -> void:
	checks += 1
	if value:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func until(predicate: Callable, limit: int) -> bool:
	for i in limit:
		if predicate.call():
			return true
		await frames(1)
	return predicate.call()


func setup() -> void:
	if is_instance_valid(mission):
		mission.queue_free()
		await frames(2)
	mission = MISSION.instantiate()
	root.add_child(mission)
	mission.set_process(false)
	last = mission.get_node("LastStand")
	last.set_physics_process(false)
	defense = mission.get_node("VillageDefense")
	formation = defense.organized
	for actor in mission.villagers:
		actor.autonomous_movement_enabled = false
		actor.threat_detection.detection_enabled = false
	await frames(4)
	await until(func(): return last.church.shelter_approach().is_finite(), 160)


func activate_defense() -> void:
	defense.alert.bell_activated = true
	defense.alert.advance_level(defense.alert.Level.ALARM)
	defense.alert.add_danger(defense.alert.danger_threshold)


func assemble(actor: Node2D) -> void:
	var previous := actor.global_position
	actor.global_position = formation.center
	formation.check_arrival(actor)
	actor.global_position = previous


func spawn_monster(point: Vector2, autonomous := false, detect_residents := false) -> Node2D:
	var unit := MONSTER.instantiate()
	unit.position = mission.to_local(point)
	mission.add_child(unit)
	unit.set_physics_process(autonomous)
	unit.get_node("AggroArea").monitoring = detect_residents
	return unit


func run() -> void:
	await setup()
	await test_construction()
	await test_worker_ai()
	await test_signal()
	await test_wave_and_squad()
	await setup()
	await test_replacement_and_cancellation()
	await setup()
	await test_march_corner()
	await setup()
	await test_formation_ranks()
	await setup()
	await test_barricade_aggro()
	await setup()
	await test_arrivals_at_barricade_line()
	await setup()
	await test_fortified_flanks()
	await setup()
	await test_converted_melee_support()
	mission.queue_free()
	await frames(2)
	print("IDEA-005: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures else 0)


func test_construction() -> void:
	var initial: int = last.residents.size()
	var west: StaticBody2D = last.sections[0]
	var south: StaticBody2D = last.sections[2]
	check(initial == 44 and last.sections.size() == 5 and last.total_max_hp == 1200.0, "Mission 1 registers the original population and five required sections")
	check(west.collision_layer == 0 and west.hp == 0.0 and west.needs_work(), "An untouched section is constructible and collision-free")
	var positions: Array[Vector2] = formation.build_slots(last.residents[0], formation.radius)
	check(positions.size() >= initial and positions.all(func(point): return last.inside_defenses(point) and last.keeps_door_clear(point, last.defense_spacing * 0.9)), "The entire garrison fits on protected posts with a clear church entrance before construction")
	check(formation.build_slots(last.residents[0], 400.0) == positions, "Population pressure cannot expand posts outside the barricades")
	activate_defense()
	check(formation.active(), "Uses the existing alert escalation")
	for actor in last.residents.slice(0, 21):
		assemble(actor)
	last._check_assembly()
	check(not last.construction_enabled, "21 of 44 residents is below the assembly threshold")
	var hidden: Node = last.residents[0]
	check(hidden.apply_player_infection(1000.0), "A hidden infection can coexist with assembly")
	var casualty: Node = last.residents[21]
	var converted: Node = last.residents[22]
	casualty._die()
	converted._complete_conversion()
	last._check_assembly()
	check(last.construction_enabled, "21 of 42 living residents counts hidden infection and excludes the killed and converted")
	var limits: Array[Node] = last.residents.duplicate()
	last.residents.clear()
	last._check_assembly()
	check(last.construction_enabled, "Construction stays enabled after the assembled population falls")
	last.construction_enabled = false
	last._check_assembly()
	check(not last.construction_enabled, "An empty population cannot unlock construction")
	last.residents = limits
	last.construction_enabled = true
	check(last.sections.all(func(section): return not section.work_points.is_empty()), "Each authored section has a reachable generated work position")
	check(last.sections.all(func(section): return Array(section.work_points).all(last.inside_defenses)), "Every work point stays on the protected side of the line")
	check(south.work_points.size() > west.work_points.size(), "Longer sections supply more work positions")
	var initial_points: int = west.work_points.size()
	var nav := mission.get_world_2d().navigation_map
	var inaccessible := SECTION.new()
	inaccessible.position = Vector2(-900, -900)
	mission.add_child(inaccessible)
	inaccessible.prepare_work_points(nav, formation.center, 24.0, 9.0)
	check(inaccessible.work_points.is_empty(), "Positions outside the navmesh are excluded in place")
	inaccessible.queue_free()
	if initial_points < 2:
		return
	var worker: Node2D = last.residents[1]
	var other: Node2D = last.residents[2]
	var position: Vector2 = west.work_points[0]
	formation.places[worker.get_instance_id()] = position
	formation.places[other.get_instance_id()] = position
	var controller: RefCounted = formation.controller(worker)
	var peer: RefCounted = formation.controller(other)
	var task := {"section": west, "index": 0}
	last.assignments[worker] = task
	last.assignments[other] = task.duplicate()
	worker.global_position = position + Vector2(22, 0)
	check(last.update_work(controller, 0.5) and west.hp == 0.0 and west.occupants.is_empty(), "Travel earns zero HP and does not occupy the reserved position")
	worker.global_position = position
	check(last.update_work(controller, 0.5) and west.hp == 3.0 and west.occupants[0] == worker, "First physical worker creates the barricade on the first HP tick")
	other.global_position = position + Vector2(3, 0)
	check(not last.update_work(peer, 0.5) and not last.assignments.has(other), "Second worker abandons an occupied position")
	last.assignments[other] = {"section": west, "index": 1}
	other.global_position = west.work_points[1]
	last.update_work(controller, 0.5)
	last.update_work(peer, 0.5)
	check(west.hp == 9.0, "Two active positions contribute additively to the same HP")
	last.stop_work(worker)
	last.stop_work(other)
	check(west.occupants.is_empty() and west.hp == 9.0, "Interruption releases positions and preserves the work")
	for actor in last.residents:
		if is_instance_valid(actor) and formation.central_role(actor):
			check(not last.update_work(formation.controller(actor), 1.0), "Priest and personal guards cannot build")
	var guard: Node2D = mission.get_node("Villagers/Guard25")
	assemble(guard)
	guard.global_position = west.work_points[0]
	var side_job: Dictionary = last._find_work(guard, west.side)
	check(not side_job.is_empty() and side_job.section == west, "A late ordinary guard selects the closest available section on its flank")
	last.assignments[guard] = {"section": west, "index": 0}
	last.update_work(formation.controller(guard), 0.5)
	check(west.hp == 12.0, "Ordinary guards contribute HP at the work position")
	guard._die()
	check(west.occupants.is_empty() and not last.assignments.has(guard), "A dead worker immediately releases the position")
	var start: Vector2 = west.to_global(Vector2(0, -35))
	var goal: Vector2 = west.to_global(Vector2(0, 35))
	var monster := spawn_monster(start)
	await frames(2)
	check(monster.test_move(monster.global_transform, goal - start), "A partially built barricade physically blocks monster travel")
	worker.global_position = west.global_position
	check(worker.barricade_speed_factor() == 0.5 and not worker.test_move(worker.global_transform, Vector2(-9, 0)), "Villagers can cross at half speed")
	worker.global_position = position + Vector2(65, 0)
	check(worker.barricade_speed_factor() == 1.0, "Villagers regain their full speed away from the section")
	west.build(50.0)
	monster.set_physics_process(true)
	monster.issue_player_move_order(goal)
	check(await until(func(): return west.hp < 62.0, 100), "A monster on a normal movement order attacks the blocking section")
	monster.queue_free()
	await frames(2)
	var damaged: float = west.hp
	west.build(1.0)
	check(west.hp == damaged + 1.0, "Repair increases the damaged section's same HP")
	west.build(500.0)
	check(west.hp == west.max_hp and not west.needs_work() and not last.signal_ready, "HP caps at maximum and one complete section is below total readiness")
	west.take_damage(500.0)
	check(west.collision_layer == 0 and west.state == SECTION.State.DESTROYED and not west.build(1.0), "Destroyed sections reopen the path permanently")


func test_signal() -> void:
	var church: InteractiveBuilding = last.church
	var south: StaticBody2D = last.sections[2]
	var east: StaticBody2D = last.sections[4]
	south.build(240.0)
	east.build(119.0)
	check(not last.signal_ready and last.wave == last.Wave.UNSENT, "359 of 1200 HP leaves the emergency request unavailable")
	east.build(1.0)
	var priest: Node2D = mission.get_node("Villagers/Priest30")
	check(last.signal_ready and last.operator == priest and last.wave == last.Wave.UNSENT, "30% aggregate HP latches and immediately assigns the living priest")
	south.take_damage(240.0)
	east.take_damage(120.0)
	check(last.signal_ready and last.operator == priest, "Later damage cannot reverse readiness")
	var recipient: Node2D = last.residents[3]
	priest.global_position = church.shelter_approach() + Vector2(12, 60)
	recipient.global_position = priest.global_position + Vector2(45, 8)
	check(defense.steadfast(recipient), "The priest's usual morale applies before entry")
	var protectors: Array[Node] = last.residents.filter(func(actor): return is_instance_valid(actor) and actor.priest_guard != null)
	for protector in protectors:
		protector.global_position = priest.global_position + Vector2(-30 if protector.priest_guard.slot == 0 else 30, 36)
		protector.autonomous_movement_enabled = true
	await frames(2)
	check(not last.church_posts_active and protectors.all(func(actor): return actor.priest_guard.joined and actor.priest_guard.state == actor.priest_guard.State.ESCORT), "The guards follow the priest while he is still outside the church")
	check(await until(func(): return priest.interior_building == church, 220), "The priest navigates to the door and physically enters using the existing threshold")
	check(church.signal_sealed and church.door_closed and church.door_hp == church.rules.barricade_health * 5.0, "First entry seals the entrance at five residential barricades' HP")
	check(not defense.steadfast(recipient) and not last.beacon_lit, "Priest morale stops on entry before the beacon activates")
	check(last.signal_remaining == 10.0, "Priest activation starts at 10 game seconds")
	check(last.church_posts_active and defense.alert.level == defense.alert.Level.ORGANIZED_DEFENSE, "The sealed door activates its posts before the alert stage changes")
	defense.alert.set_debug_level(defense.alert.Level.LAST_STAND)
	check(defense.alert.level == defense.alert.Level.ORGANIZED_DEFENSE, "The debug selector cannot skip the signal")
	for protector in protectors:
		protector.global_position = last.door_post(protector.priest_guard.slot) + Vector2(0, 22)
		protector.autonomous_movement_enabled = true
	await frames(2)
	check(protectors.all(func(actor): return actor.interior_building == null and actor.priest_guard.state == actor.priest_guard.State.CHURCH_DEFENSE), "Both personal guards defend the church from outside")
	check(await until(func(): return protectors.all(func(actor): return actor.global_position.distance_to(last.door_post(actor.priest_guard.slot)) <= actor.arrival_tolerance), 75), "Both guards physically take different posts beside the actual doorway")
	for protector in protectors:
		protector.autonomous_movement_enabled = false
	last._update_signal(9.9)
	check(not last.beacon_lit and last.wave == last.Wave.UNSENT and defense.alert.level == defense.alert.Level.ORGANIZED_DEFENSE, "A partial activation sends no wave and keeps organized defense")
	last._update_signal(0.1)
	check(last.beacon_lit and last.travel_remaining == 90.0, "Signal completion permanently lights the beacon and initializes 90 game seconds")
	check(defense.alert.level == defense.alert.Level.LAST_STAND and formation.active(), "The beacon advances to Last Stand with the formation still active")
	check(mission.mission_hud.alert_label.text == "Деревня: Последний оплот", "The public HUD immediately shows the final village stage")
	defense.alert.set_debug_level(defense.alert.Level.ORGANIZED_DEFENSE)
	defense.alert.set_debug_level(defense.alert.Level.LAST_STAND)
	check(defense.alert.level == defense.alert.Level.LAST_STAND and last.travel_remaining == 90.0, "Developer stage changes preserve the sent signal and timer")
	recipient.global_position = Vector2(2230, 805)
	check(defense.steadfast(recipient), "Church morale reaches an eligible resident across the village")
	priest._die()
	var attacker := spawn_monster(church.shelter_approach())
	attacker.attack_damage = 600.0
	attacker.issue_player_building_order(church)
	check(await until(func(): return church.door_hp == 0.0, 160), "An ordinary monster assault breaks the fortified church entrance")
	attacker.queue_free()
	await frames(2)
	check(last.beacon_lit and not church.restoration_allowed, "Beacon survives operator loss and the door cannot be rebuilt")


func test_worker_ai() -> void:
	var section: StaticBody2D = last.sections[1]
	var worker: Node2D = last.residents[4]
	var controller: RefCounted = formation.controller(worker)
	var home: Vector2 = section.work_points[0]
	worker.global_position = home + Vector2(28, -25)
	formation.places[worker.get_instance_id()] = home
	var index: int = section.work_points.size()
	section.work_points.append(Vector2(-300, -300))
	last.assignments[worker] = {"section": section, "index": index}
	check(not last.update_work(controller, 0.016) and formation.places.has(worker.get_instance_id()), "An unreachable job drops without losing the defensive post")
	section.work_points.remove_at(index)
	last.assignments[worker] = {"section": section, "index": 0}
	worker.autonomous_movement_enabled = true
	check(await until(func(): return section.hp > 0.0, 130), "The ordinary defender AI walks to the site and builds on arrival")
	var opponent := spawn_monster(worker.global_position + Vector2(16, 0))
	await frames(2)
	opponent.engage_defender(worker)
	var remaining: float = section.hp
	await frames(3)
	check(worker.is_in_collision() and section.hp == remaining and not last.assignments.has(worker), "Physical combat interrupts a worker's live task without HP decay")
	worker.autonomous_movement_enabled = false
	worker.leave_encounter(opponent)
	controller.enemies.append(opponent)
	opponent.queue_free()
	await frames(2)
	last.assignments[worker] = {"section": section, "index": 0}
	worker.global_position = home
	check(last.update_work(controller, 0.016) and section.hp > remaining, "The builder resumes work with a freed enemy still in its last observation")
	controller.enemies.clear()
	section.take_damage(section.max_hp)


func test_wave_and_squad() -> void:
	var squad: Node = last.squad
	var nav := mission.get_world_2d().navigation_map
	squad.rng.seed = 380
	var sample: Array[StringName] = []
	sample.resize(13)
	sample.fill(&"sword")
	squad.guard_variants = sample
	var blockers: Array[Node2D] = []
	for entry in squad.entry_points:
		var positions: PackedVector2Array = squad._spawn_positions(nav, entry)
		check(positions.size() == 13, "Road %s fits the maximum default wave" % str(entry))
		if not positions.is_empty():
			blockers.append(spawn_monster(positions[0]))
	for point in squad.patrol_points:
		check(NavigationServer2D.map_get_closest_point(nav, point).distance_to(point) <= 0.5, "Patrol point is on the existing navmesh")
	squad.guard_variants.clear()
	last.set_physics_process(true)
	await frames(2)
	paused = true
	var remaining: float = last.travel_remaining
	await frames(5)
	check(last.travel_remaining == remaining, "The hidden countdown freezes on tactical simulation pause")
	paused = false
	Engine.time_scale = 2.0
	await frames(4)
	check(remaining - last.travel_remaining > 0.10, "The countdown follows scaled simulation time")
	Engine.time_scale = 1.0
	last.set_physics_process(false)
	var entries: PackedVector2Array = squad.entry_points
	last._physics_process(last.travel_remaining - 0.01)
	check(last.wave == last.Wave.TRAVELING and last.travel_remaining > 0.0, "Reinforcements wait the full travel time")
	last._physics_process(0.01)
	check(last.wave == last.Wave.TRAVELING and last.travel_remaining <= 0.000001 and mission.reinforcement_units.is_empty(), "An unavailable entrance keeps the expired request pending")
	if blockers.size() < 2:
		return
	blockers[1].queue_free()
	await frames(2)
	check(squad._spawn_positions(nav, entries[0]).is_empty(), "A monster occupying a deployment slot blocks the entire entry")
	last.next_update = 0.0
	last._physics_process(0.016)
	check(last.wave == last.Wave.ARRIVED and squad.soldiers.size() >= 9 and squad.soldiers.size() <= 13, "Pending wave spawns once at the remaining road without restarting the timer")
	blockers[0].queue_free()
	if squad.soldiers.is_empty():
		return
	var original_count: int = last.residents.size()
	var expanded_count: int = original_count + squad.soldiers.size()
	check(mission.total_residents == expanded_count and squad.soldiers.all(func(actor): return actor.global_position.distance_to(entries[1]) < 110.0 and not formation.eligible(actor)), "All soldiers arrive together and count for victory while keeping their own squad roster")
	var expanded_goal := ceili(float(expanded_count * mission.TARGET_PERCENT) / 100.0)
	await frames(9)
	check(mission.mission_hud.objective_label.text.begins_with("Цель: %d из %d жителей" % [expanded_goal, expanded_count]), "The visible objective rises automatically when the wave deploys")
	var crossbows: int = squad.soldiers.filter(func(actor): return actor.defense_ranged_weapon).size()
	check(crossbows > 0 and crossbows * 2 < squad.soldiers.size() and squad.guard_variants.has(&"spear")
		and squad.guard_variants.has(&"shield") and squad.guard_variants.has(&"sword")
		and squad.soldiers.all(func(actor): return actor.get_meta("village_role") == "guard"),
		"The wave contains all four guard variants with a crossbow minority")
	check(not squad.try_arrive(), "An arrived wave cannot be spawned a second time")
	var soldier: Node2D = squad.soldiers[0]
	check(not defense.steadfast(soldier), "A soldier outside the village does not receive the church aura")
	check(not soldier.guard_ai.receive_message({"kind": &"enemy"}, last.residents[0]), "A reinforcement guard rejects a local defender report")
	var start: Vector2 = squad.waypoint
	var soldier_start := soldier.global_position
	check(await until(func(): return squad.waypoint.distance_to(start) > 28.0, 120), "The virtual waypoint marches toward the church on the real navmesh")
	check(soldier.global_position.distance_to(soldier_start) > 10.0, "An arrived guard physically follows the shared waypoint")
	check(squad.patrol_index == -1, "Church approach remains the first destination")
	squad.set_physics_process(false)
	var checkpoint: Vector2 = squad.church_approach
	for i in squad.soldiers.size():
		squad.soldiers[i].global_position = checkpoint + Vector2((i % 4) * 16, 18 + floori(i / 4.0) * 16)
	check(defense.steadfast(soldier), "Arrived soldiers inside the village receive the church aura")
	squad.waypoint = checkpoint
	squad.path = PackedVector2Array([checkpoint])
	squad.path_index = 0
	squad.late_since.clear()
	squad._advance_waypoint(0.016)
	check(squad.patrol_index == 0, "Reaching the church starts the first ordered patrol leg")
	for _i in squad.patrol_points.size():
		squad._finish_leg()
	check(squad.patrol_index == 0, "Patrol cycles in authored order even without detected monsters")
	var combat_point := Vector2(350, 1000)
	squad.waypoint = combat_point
	soldier.global_position = combat_point + Vector2(0, 25)
	var intruder := spawn_monster(combat_point + Vector2(80, 0))
	soldier.unit_vision.face_for_pose(soldier.global_position.direction_to(intruder.global_position))
	soldier.threat_detection.recognition_delay_min = 0.0
	soldier.threat_detection.recognition_delay_max = 0.0
	var ranged_guard: Node2D = squad.soldiers.filter(func(member): return member.defense_ranged_weapon)[0]
	ranged_guard.global_position = combat_point
	ranged_guard.unit_vision.face_for_pose(ranged_guard.global_position.direction_to(intruder.global_position))
	for member in squad.soldiers:
		if member != soldier:
			member.threat_detection.detection_enabled = false
	await frames(3)
	squad._make_decisions(defense.elapsed)
	check(squad.mode == squad.Mode.COMBAT and squad.target == intruder, "Personal monster detection interrupts the squad's patrol")
	check(await until(func(): return ranged_guard.guard_ai.next_shot > 0.0, 90), "A crossbow guard fires a bolt at a shared target")
	squad.pursuit_limit = 25.0
	squad._make_decisions(defense.elapsed)
	check(squad.mode == squad.Mode.REGROUP and squad.target == null, "The squad gives up a detected target outside its pursuit limit and regroups")
	var isolated: Node2D = squad.soldiers[-1]
	isolated.global_position = Vector2(200, 100)
	squad._make_decisions(defense.elapsed + squad.wait_seconds + 1.0)
	squad._make_decisions(defense.elapsed + squad.wait_seconds * 2.0 + 2.0)
	check(squad.isolated.has(isolated) and isolated.is_alive(), "A laggard is released from synchronization without despawning")
	isolated.global_position = squad.waypoint
	squad._update_cohesion(squad.waypoint, defense.elapsed + 20.0)
	check(not squad.isolated.has(isolated), "An isolated living soldier can rejoin")
	soldier.apply_player_infection(1000.0)
	soldier._complete_conversion()
	check(mission.total_residents == expanded_count and mission.converted_resident_ids.has(soldier.get_instance_id()), "Converted reinforcements advance the objective without shrinking the population")
	var casualty: Node2D = squad.soldiers[1]
	casualty._die()
	check(mission.dead_resident_ids.has(casualty.get_instance_id()) and mission.total_residents == expanded_count, "Killed reinforcements also advance the objective exactly once")
	var old_goal := ceili(float(original_count * mission.TARGET_PERCENT) / 100.0)
	for i in range(mission.infected_residents + mission.killed_residents, expanded_goal):
		mission.dead_resident_ids[-i - 1] = true
		if i + 1 == old_goal:
			mission._refresh_mission_progress()
			check(not mission.primary_objective_completed(), "The old threshold cannot win after the wave arrives")
	mission._refresh_mission_progress()
	check(mission.primary_objective_completed(), "The expanded threshold wins the mission")
	last._physics_process(1.0)
	check(last.wave == last.Wave.ARRIVED and isolated.is_alive(), "The completed objective leaves arrived soldiers in the world")


func test_replacement_and_cancellation() -> void:
	activate_defense()
	var priest: Node2D = mission.get_node("Villagers/Priest30")
	var church: InteractiveBuilding = last.church
	var substitute: Node2D = last.residents[0]
	last.signal_ready = true
	substitute.global_position = church.shelter_approach() + Vector2(5, 0)
	last._assign_operator()
	priest.global_position = church.shelter_approach()
	check(await until(func(): return priest.interior_building == church, 150), "Priest can enter before the replacement scenario")
	priest._die()
	last._assign_operator()
	check(last.operator == substitute and not is_instance_valid(substitute.building_task), "Nearest available replacement waits outside the intact sealed entrance")
	last._update_signal(100.0)
	check(not last.beacon_lit, "A dead operator cannot finish the signal")
	church._damage_entrance(1000.0)
	last._assign_operator()
	check(await until(func(): return substitute.interior_building == church, 150), "Replacement physically enters after the breach")
	check(last.signal_remaining == 20.0 and church.door_hp == 0.0, "Villager activation takes 20 seconds and cannot reseal the door")
	await frames(2)
	last._update_signal(20.0)
	await frames(1)
	check(last.wave == last.Wave.TRAVELING and last.travel_remaining == 90.0 and defense.alert.level == defense.alert.Level.LAST_STAND, "The substitute starts the same travel time and Last Stand stage")
	mission.mission_state = mission.MissionState.WON
	last._physics_process(90.0)
	check(last.wave == last.Wave.CANCELLED and mission.reinforcement_units.is_empty(), "Primary objective cancels before physical arrival")
	mission.mission_state = mission.MissionState.ACTIVE
	last.wave = last.Wave.TRAVELING
	last.travel_remaining = 0.0
	for actor in last.residents:
		if is_instance_valid(actor) and actor.is_alive():
			actor.infection_state = actor.InfectionState.DEAD
	last._physics_process(0.016)
	check(last.wave == last.Wave.CANCELLED and mission.reinforcement_units.is_empty(), "Elimination cancels an expired wave while deployment is still pending")


func test_formation_ranks() -> void:
	activate_defense()
	for section in last.sections:
		section.build(section.max_hp)
	var defenders: Array[Node] = last.residents.filter(func(actor): return not formation.central_role(actor))
	for i in defenders.size():
		var actor: Node2D = defenders[i]
		assemble(actor)
		var column := i % 10
		var row := floori(i / 10.0)
		actor.global_position = formation.center + Vector2((column - 4.5) * 22.0, 18.0 + 22.0 * row)
		actor.autonomous_movement_enabled = true
	check(await until(func(): return formation.places.size() == defenders.size(), 220), "All ordinary defenders reserve a distinct place on the completed line")
	var front: int = formation.slots.filter(func(point): return formation._slot_ranks.get(point, -1) == 0).size()
	var occupied_front: int = formation.places.values().filter(func(point): return formation._slot_ranks.get(point, -1) == 0).size()
	check(front > 0 and occupied_front == front, "The filled front rank spans the entire available perimeter")
	var occupied_rows: Array = formation.places.values().map(func(point): return formation._slot_ranks.get(point, -1))
	check(not occupied_rows.has(-1) and [0, 1, 2].all(occupied_rows.has), "All three barricade-aligned ranks are occupied")
	check(await until(func(): return defenders.all(func(actor): return actor.global_position.distance_to(formation.places.get(actor.get_instance_id(), Vector2.INF)) <= actor.arrival_tolerance + 0.5), 400), "The assembled defenders physically settle on their ranked posts")
	var reservations: Dictionary = formation.places.duplicate()
	await frames(65)
	check(formation.places == reservations and defenders.all(func(actor): return not actor.has_destination and actor.velocity.is_zero_approx()), "The defenders hold their assigned ranks without idle transfers")


func test_barricade_aggro() -> void:
	var west: StaticBody2D = last.sections[0]
	var resident: Node2D = last.residents[0]
	for actor in last.residents:
		actor.global_position = Vector2(2300, 800)
	resident.global_position = west.to_global(Vector2(0, 34))
	west.build(35.0)
	var monster := spawn_monster(west.to_global(Vector2(0, -55)), true, true)
	await frames(3)
	check(monster._has_line_of_sight(resident) and not monster._has_line_of_sight(resident, true), "The barricade permits vision while blocking melee")
	check(await until(func(): return west.hp < 35.0, 95), "An unordered monster sees the resident, approaches, and attacks the blocking barricade")
	check(monster.aggro_target == resident and not resident.is_in_collision() and west.to_local(monster.global_position).y < 0.0, "The monster retains its target and stays outside until the breach")
	check(await until(func(): return west.state == SECTION.State.DESTROYED and resident.is_encounter_owner(monster), 140), "After destroying the barricade the same monster reaches the same resident")

func stage_ordinary_posts(count: int) -> Array[Node]:
	for actor in last.residents:
		actor.global_position = Vector2(2300, 800)
	var actors: Array[Node] = last.residents.filter(func(actor): return not formation.central_role(actor))
	var slots: Array[Vector2] = formation.build_slots(actors[0], formation.radius)
	var ordinary_posts := slots.filter(func(point): return formation._slot_ranks.has(point))
	for i in count:
		var actor := actors[i] as Node2D
		actor.global_position = ordinary_posts[i]
		formation.check_arrival(actor)
		formation.places[actor.get_instance_id()] = ordinary_posts[i]
	return actors

func test_arrivals_at_barricade_line() -> void:
	activate_defense()
	var actors := stage_ordinary_posts(21)
	var late := actors[21] as Node2D
	late.global_position = Vector2(1417, 725)
	last._check_assembly()
	check(not last.construction_enabled and not formation.arrived(late), "An occupied front rank still needs the actual next arrival before construction")
	late.autonomous_movement_enabled = true
	check(await until(func(): return formation.arrived(late), 270), "A newcomer crosses the occupied southern rank and is counted at the inner perimeter")
	check(formation.center.distance_to(late.global_position) > formation.arrival_radius, "The resident does not need to reach the former central arrival circle")
	last._check_assembly()
	check(last.construction_enabled, "The newcomer unlocks barricade work at exactly half the village")
	for actor in actors.slice(0, 22): actor.autonomous_movement_enabled = true
	check(await until(func(): return last.sections.all(func(section): return section.hp > 0.0), 375), "Workers reach their assigned points and start all five sections with the front rank already present")
	var used := {}
	for job in last.assignments.values():
		var key := Vector2i(job.section.get_instance_id(), job.index)
		used[key] = true
	check(used.size() == last.assignments.size(), "Each work position is reserved by at most one traveling or active builder")

func test_fortified_flanks() -> void:
	activate_defense()
	var actors := stage_ordinary_posts(41)
	for section in last.sections:
		section.build(section.max_hp)
	for actor in actors:
		actor.autonomous_movement_enabled = true
		actor.threat_detection.detection_enabled = true
		actor.current_health = 10000.0
	await frames(24)
	var original: Dictionary = formation.places.duplicate()
	var strength: Array[int] = formation.flank_counts()
	var east := spawn_monster(Vector2(1613, 550))
	east.current_health = 10000.0
	await frames(70)
	check(formation.places == original and formation.flank_counts() == strength, "Merely seeing a monster outside the east wall transfers no one")
	east.global_position = Vector2(1484, 620)
	await frames(50)
	var held := true
	var pursuers := 0
	var local_response := false
	for actor in actors:
		var post: Vector2 = original[actor.get_instance_id()]
		var behavior: RefCounted = formation.controller(actor)
		if formation.sector(post) != formation.sector(east.global_position):
			held = held and actor.global_position.distance_to(post) <= actor.arrival_tolerance and behavior.target == null
		else:
			local_response = local_response or behavior.target == east or actor.encounter_participants.has(east)
			if behavior.target == east and not behavior.ranged(): pursuers += 1
	check(formation.inside(east.global_position) and formation.sector(east.global_position) == 2 and held, "A monster inside the east flank does not pull other flanks out of position")
	check(local_response and pursuers <= 3, "The attacked flank responds with a bounded number of assigned melee pursuers")
	east.queue_free()
	await frames(3)
	var survivors := 2
	for actor in actors:
		if formation.sector(original[actor.get_instance_id()]) != 2: continue
		if survivors > 0:
			survivors -= 1
		else:
			actor._die()
	var goal := ceili(strength[2] * formation.flank_reinforcement_goal)
	check(await until(func(): return formation.flank_counts()[2] >= goal, 850), "Actual east-flank losses dispatch enough defenders from other sectors")
	var replenished: Array[int] = formation.flank_counts(true)
	check(replenished[2] == goal and replenished[0] >= ceili(strength[0] * formation.flank_donor_floor) and replenished[1] >= ceili(strength[1] * formation.flank_donor_floor), "Transfers stop at the recovery target and leave both donor sectors guarded")


func test_converted_melee_support() -> void:
	activate_defense()
	var actors := stage_ordinary_posts(4)
	var candidate := actors[0] as Node2D
	var converted := actors[1] as Node2D
	var converted_id := converted.get_instance_id()
	var enemy := spawn_monster(candidate.global_position + Vector2(30, 0))
	for actor in actors.slice(1, 4):
		formation.controller(actor).target = enemy
	check(not formation.melee_support_available(candidate, enemy), "Three live defenders fill the melee support limit")
	# Hold the periodic roster refresh so the real conversion frees the node
	# while other defenders can still consult its controller.
	formation.set_physics_process(false)
	converted._complete_conversion()
	await frames(2)
	check(not is_instance_valid(converted) and formation.controllers.has(converted_id), "Converted defender is freed before the roster refresh")
	check(formation.melee_support_available(candidate, enemy), "Melee support excludes the freed defender before the roster refresh")
	formation.refresh(0.0)
	check(not formation.controllers.has(converted_id) and not formation.places.has(converted_id), "The next refresh removes the converted defender and its post")


func test_march_corner() -> void:
	var squad: Node = last.squad
	squad.base_count = 13
	squad.count_variation = 0
	squad.rng.seed = 8
	var deployed: bool = squad.try_arrive()
	check(deployed, "A full thirteen-person squad deploys for the tavern route")
	if not deployed:
		return
	var nav := mission.get_world_2d().navigation_map
	var start := NavigationServer2D.map_get_closest_point(nav, Vector2(2070, 1438))
	var goal := NavigationServer2D.map_get_closest_point(nav, Vector2(1795, 1418))
	var path := NavigationServer2D.map_get_path(nav, start, goal, true)
	check(path.size() > 3, "The route passes around the tavern on the existing navmesh")
	squad.waypoint = start
	squad.heading = start.direction_to(goal)
	squad.church_approach = goal
	for i in squad.soldiers.size():
		var side: Vector2 = squad.heading.orthogonal() * (i % 4 - 1.5) * 19.0
		var row := floori(i / 4.0) * 23.0
		squad.soldiers[i].global_position = NavigationServer2D.map_get_closest_point(nav, start + side - squad.heading * row)
	var leading: Node2D = squad.soldiers[0]
	var previous := leading.global_position
	var longest_stall := 0
	var still := 0
	for i in 420:
		await frames(1)
		if i >= 45:
			still = still + 1 if leading.global_position.distance_to(previous) < 0.08 else 0
			longest_stall = maxi(longest_stall, still)
		previous = leading.global_position
	check(leading.global_position.x < 1840.0 and squad.waypoint.x < 1850.0, "The physical squad advances past the tavern turn")
	check(longest_stall < 15 and squad.late_since.is_empty(), "Continuous march clears the turn (longest stall %d frames, waiting for %d)" % [longest_stall, squad.late_since.size()])
