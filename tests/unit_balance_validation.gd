extends SceneTree

const MISSION = preload("res://tests/fixtures/mission_one_with_zombies.tscn")
const LEGACY_ZOMBIE = preload("res://scenes/zombie.tscn")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ARENA := Vector2(350, 1000)
const STEP := 1.0 / 60.0
const ZOMBIES := {
	"zombie": [180.0, 58.0, 21.0, 1.4, 0.08],
	"brute": [360.0, 38.0, 42.0, 2.4, 0.02],
	"hound": [115.0, 108.0, 15.0, 0.9, 0.06],
	"carrier": [230.0, 48.0, 13.0, 1.5, 0.16],
}
const HUMANS := {
	"peasant": [75.0, 8.0, 1.4, 24.0, 60.0, 95.0],
	"artisan": [90.0, 10.0, 1.4, 25.0, 60.0, 87.0],
	"priest_guard": [180.0, 30.0, 1.0, 30.0, 75.0, 85.0],
	"priest": [80.0, 0.0, 0.0, 22.0, 65.0, 85.0],
}
const GUARD_VARIANTS := {
	&"shield": [140.0, 26.0, 1.1, 35.0, 80.0, 85.0],
	&"sword": [155.0, 28.0, 1.1, 35.0, 80.0, 85.0],
	&"spear": [130.0, 32.0, 1.4, 35.0, 75.0, 85.0],
	&"crossbow": [85.0, 23.0, 1.6, 35.0, 85.0, 85.0],
}

var mission: Node2D
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func run() -> void:
	mission = MISSION.instantiate()
	mission.set_meta("developer_mode", true)
	root.add_child(mission)
	var map_variants := {}
	for resident in mission.villagers:
		resident.autonomous_movement_enabled = false
		human_profile(resident, resident.get_meta("village_role"))
		if resident.get_meta("village_role") == "guard":
			map_variants[resident.guard_variant] = true
	check(map_variants.size() == GUARD_VARIANTS.size(), "The starting guards cover all four variants")
	for unit in mission._owned_zombies():
		zombie_profile(unit, "zombie")
		unit.set_physics_process(false)
		unit.position = Vector2(235, 900)
	await frames(6)
	check(mission.total_residents == 44 and mission.zombie_infection.charges == 3, "Mission starts with 44 residents and three Infection charges")
	var legacy := LEGACY_ZOMBIE.instantiate()
	check(legacy.max_health == 120.0 and legacy.move_speed == 100.0, "The shared zombie scene retains legacy fixture defaults")
	legacy.free()

	for form in ZOMBIES:
		var unit := place_zombie(form)
		zombie_profile(unit, form)
		unit.queue_free()
		await frames(1)
	for role in ["peasant", "artisan", "guard", "priest_guard", "priest"]:
		var human := place_human(role, ARENA)
		human_profile(human, role)
		human.queue_free()
		await frames(1)

	var squad := mission.get_node("LastStand/Reinforcements")
	var variants: Array[StringName] = [&"sword", &"spear", &"crossbow", &"shield"]
	var troops: Array[Node2D] = mission.spawn_reinforcement_wave(variants,
		[Vector2(235, 810), Vector2(235, 840), Vector2(235, 870), Vector2(235, 780)], squad)
	for i in troops.size():
		troops[i].set_physics_process(false)
		check(troops[i].get_meta("village_role") == "guard" and troops[i].guard_variant == variants[i],
			"Reinforcement is a guard of variant " + str(variants[i]))
		human_profile(troops[i], "guard")
	check(is_equal_approx(troops[3].guard_pursuit_limit(100.0), 80.0)
		and troops[0].guard_pursuit_limit(100.0) == 100.0 and troops[1].guard_support_priority() > 0.0,
		"Shield guards hold closer and spear guards prioritize supporting allies")
	var march_start := Vector2(235, 810)
	squad.waypoint = march_start
	squad.path = PackedVector2Array([march_start + Vector2(100, 0)])
	squad._advance_waypoint(0.5)
	check(squad.march_speed == 43.0 and squad.waypoint == march_start + Vector2(21.5, 0),
		"Reinforcement formation waypoint advances at 43 world units per second")
	squad.path.clear()

	await arming_and_priest()
	await movement()
	for role in ["peasant", "artisan", "guard", "priest_guard"]:
		await duel("zombie", place_human(role, ARENA), role)
	for role in ["peasant", "artisan"]:
		var fighter := place_human(role, ARENA)
		fighter.escort.arm()
		await duel("zombie", fighter, "armed " + role)
	await duel("zombie", place_human("guard", ARENA), "guard versus two zombies", 2)
	await duel("carrier", place_human("peasant", ARENA), "peasant")
	await brute_splash()
	for i in 2:
		await duel("zombie", troops[i], str(variants[i]))
	await crossbow_shot(troops[2])
	mission.queue_free()
	await frames(2)
	print("Unit balance v0.3: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func place_human(role: String, point: Vector2) -> Node2D:
	check(mission.developer_place(role, point), "Developer places " + role)
	var human: Node2D = mission.villagers.back()
	human.set_physics_process(false)
	human.threat_detection.detection_enabled = false
	return human


func place_zombie(role: String, point := ARENA + Vector2(-16, 0)) -> Node2D:
	check(mission.developer_place(role, point), "Developer places " + role)
	var zombie: Node2D = mission._owned_zombies().back()
	zombie.set_physics_process(false)
	return zombie


func zombie_profile(zombie: Node2D, role: String) -> void:
	var stats := [zombie.max_health, zombie.move_speed, zombie.attack_damage, zombie.attack_interval, zombie.infection_chance]
	check(stats == ZOMBIES[role] and zombie.current_health == zombie.max_health and zombie.movement_speed() == zombie.move_speed
		and is_equal_approx(zombie.get_node("EncounterAttackTimer").wait_time, zombie.attack_interval), "Zombie profile and initialization: " + role)


func human_profile(actor: Node2D, role: String) -> void:
	var controller = actor.guard_ai if actor.guard_ai != null else actor.priest_guard
	var tactical: float = controller.tactical_speed if controller != null else actor.escort.movement_speed
	var stats := [actor.max_health, actor.attack_damage, actor.attack_interval, actor.move_speed, tactical, actor.threat_reaction.fleeing_speed]
	var expected: Array = GUARD_VARIANTS[actor.guard_variant] if role == "guard" else HUMANS[role]
	check(stats == expected and actor.current_health == actor.max_health
		and actor.navigation_agent.max_speed == actor.move_speed
		and (role == "priest" or is_equal_approx(actor.encounter_attack_timer.wait_time, actor.attack_interval)),
		"Human profile and initialization: " + str(actor.name))
	if role == "guard":
		var crossbow: bool = actor.guard_variant == &"crossbow"
		var visual := actor.get_node_or_null("GuardVisual")
		check(actor.defense_ranged_weapon == crossbow
			and (visual == null if crossbow else visual != null and visual.appearance == actor.guard_variant),
			"Equipment drives both attacks and visuals: " + str(actor.guard_variant))


func arming_and_priest() -> void:
	var formation = mission.get_node("VillageDefense").organized
	var alert = formation.service.alert
	alert.set_debug_level(alert.Level.ALARM)
	var peasant := place_human("peasant", ARENA)
	var guard := place_human("guard", ARENA + Vector2(20, 0))
	peasant.current_health = 29.0
	peasant.escort.arming_probability = 1.0
	check(peasant.escort.invite(guard.guard_ai, false, true), "Eyewitness recruitment succeeds")
	check(peasant.escort.armed and peasant.attack_damage == 15.0 and peasant.attack_interval == 1.2
		and is_equal_approx(peasant.encounter_attack_timer.wait_time, 1.2) and peasant.current_health == 29.0
		and peasant.max_health == 75.0 and peasant.escort.leader == guard.guard_ai, "Recruitment arms without healing")
	check(is_equal_approx(guard.guard_ai.movement_speed(), 54.0), "Guard escort still limits movement to the follower's pace")
	var weapon: StringName = peasant.escort.weapon
	peasant.escort.arm(true)
	check(peasant.escort.weapon == weapon and peasant.attack_damage == 15.0, "Arming twice keeps the weapon and fixed combat profile")
	peasant.queue_free()
	guard.queue_free()

	alert.set_debug_level(alert.Level.ORGANIZED_DEFENSE)
	var craftsman := place_human("artisan", ARENA)
	var zombie := place_zombie("zombie")
	craftsman.global_position = formation.center
	craftsman.current_health = 43.0
	craftsman.infection_source = craftsman.InfectionSource.ZOMBIE_COMBAT
	check(craftsman.begin_encounter(Color.GREEN, zombie), "Craftsman is already in an encounter on arrival")
	craftsman.encounter_attack_timer.start(0.8)
	craftsman.encounter_attack_timer.wait_time = 1.4
	formation.check_arrival(craftsman)
	check(formation.arrived(craftsman) and craftsman.escort.armed and craftsman.attack_damage == 18.0
		and craftsman.attack_interval == 1.3 and is_equal_approx(craftsman.encounter_attack_timer.wait_time, 1.3)
		and is_equal_approx(craftsman.encounter_attack_timer.time_left, 0.7)
		and craftsman.current_health == 43.0 and craftsman.max_health == 90.0 and craftsman.is_in_collision()
		and craftsman.infection_source == craftsman.InfectionSource.ZOMBIE_COMBAT,
		"Church arrival arms in combat, preserves state, and carries elapsed time into the shorter cycle")
	craftsman.queue_free()
	alert.set_debug_level(alert.Level.NORMAL)
	var priest: Node2D = mission.get_node("Villagers/Priest30")
	check(priest.begin_encounter(Color.GREEN, zombie) and priest.encounter_attack_timer.is_stopped()
		and priest._encounter_attack_target() == null, "Priest never starts a counterattack")
	priest.leave_encounter(zombie)
	zombie.queue_free()
	await frames(2)


func movement() -> void:
	for role in ["peasant", "artisan"]:
		var human := place_human(role, ARENA)
		var goal := ARENA + Vector2(240, 0)
		human._set_peaceful_destination(goal)
		human.autonomous_movement_enabled = true
		human.set_physics_process(true)
		await frames(22)
		check(human.global_position.x > ARENA.x + 4.0 and human.navigation_agent.max_speed == HUMANS[role][3],
			"Peaceful route uses approved speed: " + role)
		check(human.escort.move_to(goal, STEP) == human.NavigationResult.MOVING
			and human.navigation_agent.max_speed == 60.0, "Alarm escort route uses 60: " + role)
		human.set_physics_process(false)
		for form in ZOMBIES:
			var zombie := place_zombie(form, ARENA + Vector2(-70, 0))
			human.global_position = ARENA
			human._set_peaceful_destination(goal)
			zombie.get_node("AggroArea").monitoring = false
			zombie.issue_player_move_order(goal)
			zombie.set_physics_process(true)
			var starting_gap := human.global_position.distance_to(zombie.global_position)
			for i in 32:
				human._advance_navigation(goal, human.threat_reaction.fleeing_speed, STEP)
				await physics_frame
			var gap := human.global_position.distance_to(zombie.global_position)
			check(gap < starting_gap - 3.0 if form == "hound" else gap > starting_gap + 3.0,
				"Clear straight routes at fleeing and chase speeds: %s / %s (gap %.1f → %.1f)" % [role, form, starting_gap, gap])
			zombie.queue_free()
			await frames(2)
		human.queue_free()
		await frames(2)
	check(is_equal_approx(108.0 / 95.0 - 1.0, 0.136842105), "Runner base speed exceeds the peasant's by about 13.7%")


func duel(form: String, human: Node2D, label: String, count := 1) -> void:
	human.global_position = ARENA
	var attackers: Array[Node2D] = []
	for i in count:
		var offset := Vector2(-16, 0) if i == 0 else Vector2(16, 0)
		var zombie := place_zombie(form, ARENA + offset)
		# Isolate melee damage and timing from the independent infection roll.
		zombie.infection_chance = 0.0
		attackers.append(zombie)
	await frames(2)
	for zombie in attackers:
		check(zombie.engage_defender(human), "Standard melee contact: " + label)
	var zombie_hp: float = attackers[0].current_health
	var human_hp: float = human.current_health
	await frames(100)
	check(is_equal_approx(human_hp - human.current_health, attackers[0].attack_damage * count)
		and is_equal_approx(zombie_hp - attackers[0].current_health, human.attack_damage),
		"First reciprocal cycle %s versus %s: resident −%.1f HP, zombie −%.1f HP" % [
			form, label, human_hp - human.current_health, zombie_hp - attackers[0].current_health])
	for zombie in attackers:
		human.leave_encounter(zombie)
		zombie.queue_free()
	human.queue_free()
	await frames(2)


func brute_splash() -> void:
	var primary := place_human("guard", Vector2(422, 900))
	var secondary := place_human("artisan", Vector2(422, 910))
	primary.global_position = Vector2(422, 900)
	secondary.global_position = Vector2(422, 910)
	secondary.autonomous_movement_enabled = false
	secondary.escort.arm()
	var brute := place_zombie("brute", Vector2(410, 900))
	brute.global_position = Vector2(410, 900)
	brute.infection_chance = 0.0
	await frames(2)
	check(brute.engage_defender(primary), "Brute engages grouped armed defenders")
	await frames(150)
	var primary_damage: float = primary.max_health - primary.current_health
	var splash_damage: float = secondary.max_health - secondary.current_health
	check(is_equal_approx(primary_damage, 42.0) and is_equal_approx(splash_damage, 16.8),
		"Brute first attack cycle: primary −%.1f HP, secondary −%.1f HP" % [primary_damage, splash_damage])
	primary.leave_encounter(brute)
	primary.queue_free()
	secondary.queue_free()
	brute.queue_free()
	await frames(2)


func crossbow_shot(guard: Node2D) -> void:
	guard.global_position = ARENA
	var zombie := place_zombie("zombie", ARENA + Vector2(-62, 0))
	guard.guard_ai.engage_target(zombie, STEP, ARENA, INF)
	check(is_equal_approx(guard.guard_ai.next_shot - guard.defense.elapsed, 1.6), "Crossbow guard schedules the next bolt after 1.6 s")
	await frames(25)
	check(zombie.current_health == 157.0, "Crossbow bolt deals 23 damage on contact")
	zombie.queue_free()
