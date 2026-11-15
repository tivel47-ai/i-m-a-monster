# Godot --headless --path . --script tests/infection_validation.gd --fixed-fps 60
extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")

var app: Node
var mission: Node2D
var ability: RefCounted
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


func frame() -> void:
	await physics_frame
	await process_frame


func until(predicate: Callable, frame_limit: int) -> bool:
	for i in frame_limit:
		if predicate.call():
			return true
		await frame()
	return predicate.call()


func launch() -> void:
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._start_mission()
	mission = app.mission
	ability = mission.zombie_infection
	await frame()


func restart() -> void:
	app._pause()
	app._restart_mission()
	mission = app.mission
	ability = mission.zombie_infection
	await frame()


func residents(role: String) -> Array:
	return mission.villagers.filter(func(actor):
		return is_instance_valid(actor) and actor.is_alive() and actor.get_meta("village_role", "") == role)


func tap_screen(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func tap_world(point: Vector2) -> void:
	var camera := mission.get_node("Camera2D") as Camera2D
	camera.global_position = point
	camera.force_update_scroll()
	tap_screen(root.get_canvas_transform() * point)


func choose_infection() -> void:
	tap_screen(mission.mission_hud.infection_button.get_global_rect().get_center())


func spawn_zombie(point: Vector2) -> Node2D:
	var zombie := ZOMBIE.instantiate() as CharacterBody2D
	zombie.position = mission.to_local(point)
	mission.add_child(zombie)
	zombie.set_physics_process(false)
	return zombie


func lethal_attack(actor: Node2D, zombie: Node2D, chance := 0.0) -> void:
	actor.begin_encounter(Color.GREEN, zombie)
	actor.receive_zombie_attack(1000.0, chance, zombie)


func settle_residents() -> void:
	for actor in mission.villagers:
		if is_instance_valid(actor):
			actor.autonomous_movement_enabled = false


func run() -> void:
	seed(1249)
	root.size = Vector2i(1280, 720)
	app = MAIN.instantiate()
	root.add_child(app)
	await launch()
	await outdoors_and_recovery()
	await restart()
	await interiors()
	await restart()
	await threshold_conversion()
	await lifecycle()
	app.queue_free()
	await frame()
	print("Infection and mission lifecycle: ", checks - failures, "/", checks, " passed")
	quit(0 if failures == 0 else 1)


func outdoors_and_recovery() -> void:
	var hud = mission.mission_hud
	var peasant: Node2D = residents("peasant")[0]
	var artisan: Node2D = residents("artisan")[0]
	var priest: Node2D = residents("priest")[0]
	var guard: Node2D = residents("guard")[0]
	var initial := {}
	for actor in residents("peasant"):
		initial[actor] = actor.position
	var alert = mission.get_node("VillageAlert")
	check(get_nodes_in_group("player_units").is_empty() and app.screen == app.Screen.GAMEPLAY and not paused,
		"Mission 1 starts active, without zombies or initial pause")
	check(await until(func(): return initial.keys().any(
		func(actor): return actor.position.distance_to(initial[actor]) > 2.0
	), 240),
		"Village routines run before the outbreak")
	check(ability.charges == 3 and "×3" in hud.infection_button.text and hud.infection_button.icon != null
		and hud.infection_segments.size() == 5 and hud.infection_button.get_global_rect().end.x < 1280 * 0.32,
		"Dedicated HUD button, icon, three charges and five segments outside the hotbar")
	choose_infection()
	check(ability.targeting, "Clicking the dedicated button enters targeting")
	tap_world(priest.global_position)
	tap_world(guard.global_position)
	tap_world(Vector2(1500, 920))
	check(ability.charges == 3 and not guard.has_player_infection() and not priest.has_player_infection(),
		"Guard, priest and empty ground consume no charges")
	tap_world(peasant.global_position)
	check(peasant.has_player_infection() and ability.targeting and ability.charges == 2
		and peasant.infection_source == peasant.InfectionSource.PLAYER_ABILITY
		and is_equal_approx(peasant.player_infection_timer.wait_time, 10.0),
		"Outdoor click starts guaranteed ten-second infection and leaves targeting active")
	tap_world(peasant.global_position)
	check(ability.charges == 2, "Same resident cannot be infected again")
	var after_cast := peasant.position
	check(await until(func(): return peasant.position.distance_to(after_cast) > 2.0, 90)
		and peasant.is_available_for_infection() and alert.level == alert.Level.NORMAL
		and mission.infected_residents == 0 and get_nodes_in_group("player_units").is_empty(),
		"Secret infection preserves movement, eligibility for zombie combat, alert and objective counters")
	var remaining: float = peasant.player_infection_timer.time_left
	app._pause()
	for i in 20:
		await frame()
	check(is_equal_approx(peasant.player_infection_timer.time_left, remaining), "Pause menu freezes infection simulation time")
	app._resume()
	var camera := mission.get_node("Camera2D") as Camera2D
	var camera_before := camera.position
	check(await until(func(): return is_instance_valid(peasant) and peasant.player_infection_timer.time_left < 0.2, 650),
		"Pending infection persists until near the end of its ten-second timer")
	check(mission.infected_residents == 0, "Pending infection adds no victory progress")
	check(await until(func(): return mission.infected_residents == 1, 30)
		and get_nodes_in_group("player_units").size() == 1 and camera.position == camera_before,
		"Natural expiry spawns one player zombie without moving the camera")
	settle_residents()
	var zombie: Node2D = get_nodes_in_group("player_units")[0]
	zombie.set_physics_process(false)
	zombie.set_selected(true)
	var destination := Vector2(200, 900)
	zombie.issue_player_area_move_order(destination)
	tap_screen(Vector2(640, 360), MOUSE_BUTTON_RIGHT)
	check(not ability.targeting and zombie.is_selected and zombie.target_position == destination,
		"RMB cancels ability aiming without changing selection or issuing an order")
	choose_infection()
	tap_world(artisan.global_position)
	check(artisan.has_player_infection() and ability.charges == 1
		and zombie.is_selected and zombie.target_position == destination, "Craftsman can be infected without replacing a selected zombie's order")
	lethal_attack(artisan, zombie, 1.0)
	artisan._on_transformation_timer_timeout()
	artisan._complete_conversion()
	check(mission.infected_residents == 2 and mission.killed_residents == 0 and ability.recovery_progress == 0
		and get_nodes_in_group("player_units").size() == 2 and artisan.player_infection_timer.is_stopped(),
		"Lethal zombie hit converts secretly infected resident once and earns no kill credit")
	var uncredited: Node2D = residents("peasant")[0]
	uncredited.take_damage(1000.0)
	check(ability.recovery_progress == 0, "Unattributed deaths earn no charge progress")
	var combat_conversion: Node2D = residents("peasant")[0]
	lethal_attack(combat_conversion, zombie, 1.0)
	check(combat_conversion.infection_state == combat_conversion.InfectionState.TRANSFORMING
		and not ability.infect(combat_conversion), "Existing successful combat infection excludes a duplicate player application")
	check(await until(func(): return mission.infected_residents == 3, 135) and ability.recovery_progress == 0,
		"Ordinary combat conversion retains its own timer and earns no charge progress")
	var starting_segments: Color = hud.infection_segments[0].color
	lethal_attack(guard, zombie)
	lethal_attack(priest, zombie)
	mission._on_resident_died(priest)
	check(ability.recovery_progress == 2 and ability.charges == 1
		and hud.infection_segments[0].color != starting_segments and hud.infection_segments[1].color == hud.infection_segments[0].color
		and hud.infection_segments[2].color == starting_segments, "Guard and priest kills count once and fill two HUD segments")
	for i in 18:
		lethal_attack(residents("peasant")[0], zombie)
	check(ability.charges == 5 and ability.recovery_progress == 0 and "×5" in hud.infection_button.text,
		"Twenty qualifying kills restore four charges and zero the segments with no three-charge cap")


func shelter(building: InteractiveBuilding, actor: Node2D) -> bool:
	actor.global_position = building.shelter_approach()
	return building.request_shelter(actor) and await until(func(): return actor.interior_building == building, 150)


func interiors() -> void:
	settle_residents()
	var building: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]
	var first: Node2D = residents("peasant")[0]
	var second: Node2D = residents("peasant")[1]
	var walking: Node2D = residents("peasant")[2]
	var guard: Node2D = residents("guard")[0]
	for i in 5:
		await frame()
	check(await shelter(building, guard) and await shelter(building, first) and await shelter(building, second),
		"Two peasants and a guard enter via standard building transitions")
	choose_infection()
	tap_world(building.global_position)
	check(first.has_player_infection() != second.has_player_infection() and not guard.has_player_infection()
		and ability.charges == 2, "Building click selects one eligible occupant and excludes the guard")
	tap_world(building.global_position)
	tap_world(building.global_position)
	check(first.has_player_infection() and second.has_player_infection() and ability.charges == 1 and ability.targeting,
		"Repeated building clicks target different residents and skip an exhausted candidate pool")
	walking.global_position = building.shelter_approach()
	tap_world(walking.global_position)
	check(walking.has_player_infection() and ability.charges == 0 and not ability.targeting
		and mission.mission_hud.infection_button.disabled, "Last charge exits targeting and disables the button")
	check(await shelter(building, walking) and walking.has_player_infection(),
		"An outdoor infection follows the same resident into a building")
	building.request_resident_exit(walking)
	check(await until(func(): return walking.interior_building == null, 180)
		and walking.has_player_infection(), "Indoor-to-outdoor transition retains the infection")
	walking.take_damage(1000.0)
	check(mission.infected_residents == 1 and building.monsters.is_empty(),
		"Lethal damage after exiting converts at the outdoor location")
	var outdoor: Node2D = get_nodes_in_group("player_units")[0]
	outdoor.global_position = Vector2(170, 900)
	outdoor.set_physics_process(false)
	building.door_hp = 0.0
	building.barricade_hp = 25.0
	building._refresh_entrance()
	first.take_damage(1000.0)
	var first_inside: Node2D = building.monsters[0]
	first_inside.current_health = 1000.0
	first_inside.attack_damage = 0.0
	first_inside.infection_chance = 0.0
	check(await until(func(): return building.monsters.size() == 2, 650)
		and mission.infected_residents == 3 and ability.recovery_progress == 0,
		"Interior death and normal expiry create exactly two inside zombies, without recovery credit")
	if building.monsters.size() != 2:
		return
	var inside: Node2D = building.monsters[0]
	building.monsters[0].infection_chance = 0.0
	building.monsters[1].infection_chance = 0.0
	inside.attack_damage = 1000.0
	outdoor.set_selected(false)
	mission.mission_hud._select_all_zombies()
	inside.issue_player_area_move_order(Vector2(200, 800))
	check(not inside.can_receive_player_orders() and not inside.is_selected and not inside.has_target
		and mission._command_units() == [outdoor], "Group selection and direct orders exclude interior zombies")
	check(await until(func(): return guard.is_dead(), 360)
		and ability.recovery_progress == 1, "Interior combat uses existing AI, and a non-converting interior kill counts")
	check(await until(func(): return building.monsters.is_empty(), 480) and building.barricade_hp == 0.0
		and inside.can_receive_player_orders(), "Both zombies destroy the barricade from inside and exit")
	inside.set_selected(true)
	inside.issue_player_move_order(Vector2(600, 550))
	check(inside.is_selected and inside.has_target, "Ordinary selection and orders resume after exit")


func threshold_conversion() -> void:
	settle_residents()
	var building: InteractiveBuilding = mission.shelter_buildings[mission.get_node("VillagePointsOfInterest/Home1")]
	var resident: Node2D = residents("peasant")[0]
	check(await shelter(building, resident), "Resident enters before threshold conversion test")
	ability.infect(resident)
	building.request_resident_exit(resident)
	if not await until(func(): return building._crossing_started and building.layout.depth(resident) > -5.0, 180):
		check(false, "Resident reaches the threshold on their way out")
		return
	resident.take_damage(1000.0)
	check(building.monsters.size() == 1 and building._crossing == null,
		"Conversion at the threshold replaces the resident on the interior side and releases the crossing")
	var zombie: Node2D = building.monsters[0]
	check(await until(func(): return zombie.can_receive_player_orders(), 480),
		"Converted zombie can open a route out through the original blocked door")


func lifecycle() -> void:
	await restart()
	settle_residents()
	var previous: Node2D = mission
	var actors := residents("peasant")
	var zombie := spawn_zombie(Vector2(170, 900))
	lethal_attack(residents("guard")[0], zombie)
	zombie._die()
	for i in 3:
		ability.infect(actors[i])
	check(ability.charges == 0 and get_nodes_in_group("player_units").is_empty(), "Mission permits zero units and no unused charges")
	await restart()
	check(not is_instance_valid(previous) and ability.charges == 3 and ability.recovery_progress == 0
		and mission.infected_residents == 0 and get_nodes_in_group("player_units").is_empty(),
		"Restart discards pending timers and resets charges, progress and army")
	for i in 3:
		var resident: Node2D = residents("peasant")[0]
		ability.infect(resident)
		resident.take_damage(1000.0)
	for unit in get_nodes_in_group("player_units"):
		unit._die()
	var alert = mission.get_node("VillageAlert")
	for stage in [alert.Level.NORMAL, alert.Level.ORGANIZED_DEFENSE]:
		alert.set_debug_level(stage)
		var observer: Node2D = residents("peasant")[-1]
		var start := observer.position
		check(await until(func(): return observer.position.distance_to(start) > 0.5, 150)
			and app.screen == app.Screen.GAMEPLAY and mission.mission_state == mission.MissionState.ACTIVE
			and ability.charges == 0 and get_nodes_in_group("player_units").is_empty(),
			"Zero monsters, charges and pending infections leave simulation active at level %d" % stage)
	app._pause()
	app._show(app.Screen.CONFIRM_LEAVE)
	app._leave_mission()
	await frame()
	check(app.screen == app.Screen.MAIN and app.mission == null and not paused, "Voluntary exit from depleted attempt shows no result")
	await launch()
	settle_residents()
	var pending: Node2D = residents("peasant")[0]
	var paused_by_result: Node2D = residents("peasant")[1]
	var active_alert = mission.get_node("VillageAlert")
	active_alert.set_debug_level(active_alert.Level.ORGANIZED_DEFENSE)
	check(ability.infect(pending) and ability.infect(paused_by_result),
		"Organized defense does not block new infections")
	var victims: Array[Node] = mission.villagers
	for actor in victims:
		if actor not in [pending, paused_by_result] and mission.killed_residents < 35:
			actor.take_damage(1000.0)
	check(mission.mission_state == mission.MissionState.ACTIVE and mission.infected_residents == 0,
		"35 outcomes and one pending infection do not meet the objective")
	pending.take_damage(1000.0)
	check(await until(func(): return app.screen == app.Screen.RESULTS, 5)
		and "Победа" in app.result_text.text and "Заражено: 1" in app.result_text.text
		and "Убито: 35" in app.result_text.text, "36th completed outcome opens the existing victory screen")
	var remaining: float = paused_by_result.player_infection_timer.time_left
	for i in 10:
		await frame()
	check(is_equal_approx(remaining, paused_by_result.player_infection_timer.time_left) and mission.infected_residents == 1,
		"Victory stops other pending infections and keeps the result counters stable")
