extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const LEGACY = preload("res://scenes/test_map.tscn")
const WEAPONS = preload("res://scripts/civilian_weapon_catalog.gd")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const ARENA := Vector2(350, 1000)

var mission: Node2D
var checks := 0
var failures := 0
var projectile: Node2D


func _initialize() -> void:
	run.call_deferred()


func check(result: bool, description: String) -> void:
	checks += 1
	if result:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func start_mission() -> void:
	mission = MISSION.instantiate()
	mission.set_meta("developer_mode", true)
	root.add_child(mission)
	for resident in mission.villagers:
		resident.autonomous_movement_enabled = false
		resident.threat_detection.detection_enabled = false
	await frames(3)


func resident(role: String, point := ARENA) -> Node2D:
	mission._developer_place_human(role, point)
	var unit: Node2D = mission.villagers.back()
	unit.autonomous_movement_enabled = false
	unit.threat_detection.detection_enabled = false
	return unit


func monster(point: Vector2) -> Node2D:
	var unit := ZOMBIE.instantiate()
	unit.position = point
	unit.infection_chance = 0.0
	mission.add_child(unit)
	unit.set_physics_process(false)
	unit.get_node("AggroArea").monitoring = false
	return unit


func choose_weapon(unit: Node2D, id: StringName) -> void:
	var random := RandomNumberGenerator.new()
	for seed_value in range(1000):
		random.seed = seed_value
		if unit.escort.catalog.choose(unit.escort.role(), random) == id:
			unit.escort.weapon_rng.seed = seed_value
			return
	check(false, "Fixture can choose " + str(id))


func aim(unit: Node2D, inaccurate: bool) -> void:
	var random := RandomNumberGenerator.new()
	for seed_value in range(100):
		random.seed = seed_value
		if (random.randf() < unit.escort.weapon_profile.error) == inaccurate:
			unit.escort.weapon_rng.seed = seed_value
			return


func run() -> void:
	await start_mission()
	await diagnostics_layout()
	var legacy := LEGACY.instantiate()
	check(legacy.civilian_weapon_catalog == null, "Test map has no civilian catalogue")
	legacy.free()
	config()
	await acquisition()
	await melee()
	await shooting()
	await incidental_and_obstructed_shots()
	await tactics()
	await rear_priority()
	mission.queue_free()
	await frames(2)
	await start_mission()
	check(mission.mission_hud.civilian_armament_snapshot().armed == 0, "Mission restart resets equipment")
	mission.queue_free()
	await frames(2)
	print("Civilian armament: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func config() -> void:
	var rules: WEAPONS = mission.civilian_weapon_catalog
	check(mission.civilian_weapons_valid and rules.validation_error().is_empty(), "Mission loads all seven definitions")
	var random := RandomNumberGenerator.new()
	for role in ["peasant", "artisan"]:
		random.seed = 371
		var actual := {}
		for i in 10000:
			var id := rules.choose(role, random)
			actual[id] = int(actual.get(id, 0)) + 1
		var col := 0 if role == "peasant" else 1
		var correct := true
		for id in rules.weapons:
			var weight: int = rules.weapons[id].weights[col]
			correct = correct and (int(actual.get(id, 0)) == 0 if weight == 0
				else absf(float(actual.get(id, 0)) / 100.0 - weight) < 1.5)
		check(correct, "Seeded catalogue distribution for " + role)
	var invalid := WEAPONS.new()
	invalid.weapons[&"sling"].weights = [0, 15]
	check(not invalid.validation_error().is_empty(), "Invalid weights are rejected")


func diagnostics_layout() -> void:
	var hud: Node = mission.mission_hud
	var selected := resident("artisan")
	choose_weapon(selected, &"hunting_bow")
	selected.escort.arm_from(WEAPONS.Source.SHELTER)
	hud._armament_inspected = weakref(selected)
	hud._armament_panel.show()
	var original_size := root.size
	for size in [Vector2i(1280, 720), Vector2i(960, 720)]:
		root.size = size
		await process_frame
		hud._refresh_armament_diagnostics()
		await process_frame
		var bounds: Rect2 = hud._armament_panel.get_global_rect()
		check(root.get_visible_rect().encloses(bounds) and hud._armament_detail.text.contains("Охотничий лук"),
			"Developer diagnostics fit with the long equipment name at %s" % str(size))
	root.size = original_size
	hud._armament_panel.hide()
	selected.queue_free()
	await frames(2)


func acquisition() -> void:
	var alert: Node = mission.get_node("VillageAlert")
	var defense: Node = mission.get_node("VillageDefense")
	var formation: Node = defense.organized
	var snapshot: Dictionary = mission.mission_hud.civilian_armament_snapshot()
	check(snapshot.living == 31 and snapshot.armed == 0, "All 31 civilians start unarmed")
	var guard := resident("guard", ARENA + Vector2(25, 0))
	var early := resident("peasant")
	guard.guard_ai.investigation.phase = guard.guard_ai.investigation.Phase.CONTACT
	early.current_health = 29.0
	choose_weapon(early, &"pitchfork")
	check(early.escort.invite(guard.guard_ai, true, true) and alert.level == alert.Level.NORMAL,
		"An accepted eyewitness becomes a group member before the bell")
	check(early.escort.weapon == &"pitchfork" and early.escort.weapon_source == WEAPONS.Source.RECRUITMENT
		and early.current_health == 29.0 and early.max_health == 75.0, "Recruitment immediately equips without healing")
	early.escort.release("fixture")
	guard.guard_ai.investigation.phase = guard.guard_ai.investigation.Phase.NONE
	check(not early.escort.arm_from(WEAPONS.Source.SHELTER) and early.escort.equipment_rolls == 1
		and early.escort.weapon_source == WEAPONS.Source.RECRUITMENT, "Group release and subsequent events retain first equipment")
	var refusal := resident("peasant", ARENA + Vector2(0, 25))
	refusal.escort.courage = -1.0
	alert.set_debug_level(alert.Level.ALARM)
	check(not refusal.escort.invite(guard.guard_ai) and not refusal.escort.armed, "Refusal and ALARM grant no equipment")
	guard.queue_free()

	var cottage: InteractiveBuilding
	var workshop: InteractiveBuilding
	var public_building: InteractiveBuilding
	for building in mission.buildings:
		match str(building.get_parent().name):
			"Cottage06": cottage = building
			"Blacksmith": workshop = building
			"Tavern": public_building = building
	check(cottage != null and workshop != null and public_building != null, "Mission shelter fixtures are present")
	if cottage != null and workshop != null and public_building != null:
		for i in range(120):
			if cottage.shelter_approach().is_finite() and NavigationServer2D.map_get_iteration_id(cottage.layout.map) > 0:
				break
			await frames(1)
		var outsider := resident("peasant", cottage.shelter_approach())
		check(cottage.request_shelter(outsider) and not outsider.escort.armed, "Outside and queued are not occupancy")
		for i in range(120):
			if outsider.escort.armed: break
			await frames(1)
		check(outsider.interior_building == cottage and outsider.escort.weapon_source == WEAPONS.Source.SHELTER,
			"Physical cottage entry and locking equip a non-owner")
		var craftsman := resident("artisan")
		craftsman.interior_building = workshop
		workshop.residents.append(craftsman)
		workshop.door_closed = false
		workshop._refresh_entrance()
		check(not craftsman.escort.armed, "Unlocked interior does not grant equipment")
		craftsman.apply_player_infection(10.0)
		workshop.door_closed = true
		workshop._refresh_entrance()
		check(craftsman.escort.weapon_source == WEAPONS.Source.SHELTER and craftsman.has_player_infection(),
			"Locking equips occupants without changing hidden infection")
		workshop.residents.erase(craftsman)
		craftsman.interior_building = public_building
		public_building.residents.append(craftsman)
		var patron := resident("peasant")
		patron.interior_building = public_building
		public_building.residents.append(patron)
		public_building.door_closed = true
		public_building._refresh_entrance()
		check(not patron.escort.armed, "Public building is ineligible")
		patron.queue_free()
		craftsman.interior_building = null
		public_building.residents.erase(craftsman)
		craftsman._complete_conversion()
		check(not craftsman.escort.armed and not craftsman.has_meta("civilian_weapon"), "Conversion clears functional equipment")
		outsider.queue_free()

	alert.set_debug_level(alert.Level.ORGANIZED_DEFENSE)
	formation.check_arrival(refusal)
	check(not refusal.escort.armed, "Defense activation does not arm a distant resident")
	refusal.global_position = formation.center
	formation.check_arrival(refusal)
	check(formation.arrived(refusal) and refusal.escort.weapon_source == WEAPONS.Source.CHURCH, "Arrival physically inside the existing perimeter equips")
	var late := resident("artisan")
	alert.advance_level(alert.Level.LAST_STAND)
	formation.check_arrival(late)
	check(not late.escort.armed, "Last Stand does not grant remote equipment")
	late.global_position = formation.center
	formation.check_arrival(late)
	check(formation.arrived(late) and late.escort.weapon_source == WEAPONS.Source.CHURCH, "Physical late arrival still equips")
	var transforming := resident("artisan")
	transforming.infection_state = transforming.InfectionState.TRANSFORMING
	check(not transforming.escort.arm_from(WEAPONS.Source.CHURCH), "An active transformation blocks armament")
	transforming.queue_free()
	late._die()
	check(not late.escort.armed, "Death clears functional equipment")
	snapshot = mission.mission_hud.civilian_armament_snapshot()
	var sum := 0
	for count in snapshot.weapons.values():
		sum += count
	check(sum == snapshot.armed and snapshot.armed == snapshot.ranged + snapshot.melee, "Diagnostics reconcile weapon totals")
	var saved: Array[Node] = mission.villagers
	var empty: Array[Node] = []
	mission.villagers = empty
	check(mission.mission_hud.civilian_armament_snapshot().living == 0, "Diagnostics handle empty population")
	mission.villagers = saved
	check(mission.mission_hud._civilian_armament_details(early).contains("Вступление в группу")
		and mission.mission_hud._civilian_armament_details(early).contains("27.04"),
		"Inspection reads the original source and effective reach")
	refusal.queue_free()
	early.queue_free()
	alert.set_debug_level(alert.Level.NORMAL)
	await frames(2)
	for converted in mission._owned_zombies():
		check(not converted.has_meta("civilian_weapon"), "A converted monster receives no human weapon")
		converted.queue_free()
	await frames(2)


func melee() -> void:
	var target := monster(ARENA + Vector2(24, 0))
	var attacker := resident("peasant")
	choose_weapon(attacker, &"pitchfork")
	attacker.escort.arm_from(WEAPONS.Source.RECRUITMENT)
	await frames(2)
	check(attacker.try_melee_contact(target) and not attacker.is_encounter_owner(target)
		and absf(attacker.melee_reach() - 27.04) < 0.001, "Pitchfork reaches beyond reciprocal monster contact")
	var hp: float = target.current_health
	attacker._on_encounter_attack_timer_timeout()
	check(is_equal_approx(hp - target.current_health, 13.5),
		"Pitchfork uses the derived damage (observed %.3f)" % (hp - target.current_health))
	attacker.queue_free()
	target.queue_free()
	await frames(2)

	var hammer := resident("artisan")
	target = monster(ARENA + Vector2(20, 0))
	choose_weapon(hammer, &"hammer")
	hammer.encounter_attack_timer.start(0.8)
	hammer.escort.arm_from(WEAPONS.Source.CHURCH)
	check(is_equal_approx(hammer.encounter_attack_timer.time_left, 0.8), "Equipment preserves the active attack clock")
	await frames(2)
	check(not hammer.try_melee_contact(target) and target.engage_defender(hammer), "Hammer has shorter reach without changing the monster's reach")
	hp = target.current_health
	hammer._on_encounter_attack_timer_timeout()
	check(target.current_health == hp, "Hammer cannot damage outside its effective reach")
	hammer.autonomous_movement_enabled = true
	await frames(4)
	check(hammer.global_position.distance_to(target.global_position) <= hammer.melee_reach(),
		"A short weapon closes the last part of an existing contact before striking")
	hammer._on_encounter_attack_timer_timeout()
	check(is_equal_approx(hp - target.current_health, 22.5), "Hammer applies its own damage inside its reach")
	hammer.queue_free()
	target.queue_free()
	await frames(2)


func shooting() -> void:
	for id in [&"sling", &"hunting_bow"]:
		var unit := resident("peasant")
		choose_weapon(unit, id)
		unit.escort.arm_from(WEAPONS.Source.RECRUITMENT)
		unit.civilian_projectile_released.connect(func(shot): projectile = shot)
		unit.unit_vision.face_at_rest(Vector2.RIGHT)
		var target := monster(ARENA + Vector2(95, 0))
		var friend := resident("artisan", ARENA + Vector2(48, 0))
		var health: float = target.current_health
		await frames(3)
		aim(unit, false)
		projectile = null
		check(unit.try_fire_defense_bolt(target) and is_instance_valid(projectile)
			and projectile.weapon == id and projectile.direction.is_equal_approx(Vector2.RIGHT), "Accurate shot is physical: " + str(id))
		if is_instance_valid(projectile):
			var point := projectile.global_position
			paused = true
			await frames(4)
			check(projectile.global_position == point, "A shot pauses with the simulation")
			paused = false
		await frames(40)
		check(is_equal_approx(health - target.current_health, unit.defense_ranged_damage) and friend.current_health == friend.max_health,
			"Physical impact damages the monster and passes through a human")
		target.global_position = ARENA + Vector2(18, 0)
		check(target.engage_defender(unit), "A ranged civilian can be forced into melee")
		health = target.current_health
		unit._on_encounter_attack_timer_timeout()
		check(target.current_health == health and unit.attack_damage == 8.0 and unit.attack_interval == 1.4,
			"Ranged cooldown gates melee fallback, which keeps the unarmed profile")
		unit.leave_encounter(target)
		target.global_position = ARENA + Vector2(95, 0)
		await frames(2)
		unit.ranged_ready_at = 0.0
		aim(unit, true)
		projectile = null
		health = target.current_health
		check(unit.try_fire_defense_bolt(target) and is_instance_valid(projectile) and absf(projectile.direction.y) > 0.1,
			"Stationary target can receive a visibly deviated trajectory: " + str(id))
		await frames(50)
		check(not is_instance_valid(projectile) and target.current_health == health, "Miss cleans up at the range limit")
		unit.queue_free()
		target.queue_free()
		friend.queue_free()
		await frames(2)


func incidental_and_obstructed_shots() -> void:
	var unit := resident("peasant")
	choose_weapon(unit, &"sling")
	unit.escort.arm_from(WEAPONS.Source.RECRUITMENT)
	unit.civilian_projectile_released.connect(func(shot): projectile = shot)
	unit.unit_vision.face_at_rest(Vector2.RIGHT)
	var target := monster(ARENA + Vector2(95, 0))
	await frames(3)
	var target_health: float = target.current_health
	aim(unit, true)
	projectile = null
	unit.try_fire_defense_bolt(target)
	if not is_instance_valid(projectile):
		check(false, "An inaccurate projectile can be observed in flight")
		return
	var incidental := monster(ARENA + projectile.direction * 58.0)
	var incidental_health: float = incidental.current_health
	await frames(26)
	check(is_equal_approx(incidental_health - incidental.current_health, 8.0)
		and target_health == target.current_health, "A deviant trajectory damages the monster it actually hits")
	incidental.queue_free()
	await frames(2)
	unit.ranged_ready_at = 0.0
	aim(unit, false)
	projectile = null
	unit.try_fire_defense_bolt(target)
	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = 32
	obstacle.position = ARENA + Vector2(45, 0)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(6, 30)
	collision.shape = shape
	obstacle.add_child(collision)
	mission.add_child(obstacle)
	await frames(28)
	check(not is_instance_valid(projectile) and target_health == target.current_health,
		"A barricade blocks a civilian projectile already in flight")
	obstacle.queue_free()
	unit.queue_free()
	target.queue_free()
	await frames(2)


func tactics() -> void:
	var ranged := resident("peasant")
	choose_weapon(ranged, &"sling")
	ranged.escort.arm_from(WEAPONS.Source.RECRUITMENT)
	ranged.unit_vision.face_at_rest(Vector2.RIGHT)
	var target := monster(ARENA + Vector2(70, 0))
	target.attack_damage = 21.0
	target.attack_interval = 1.4
	await frames(3)
	check(not ranged.escort.can_resist(target), "A lone ranged civilian can decline a superior visible threat")
	mission._guard_variants.assign([&"spear", &"spear"])
	var leader := resident("guard", ARENA + Vector2(45, 0))
	var ally := resident("guard", ARENA + Vector2(46, -22))
	await frames(3)
	ranged.escort._assessment_until = 0.0
	check(ranged.escort.can_resist(target), "Nearby visible support changes the local decision")
	var stay_in_arena := func(point: Vector2): return point.distance_to(ARENA) <= 80.0
	check(ranged.escort.support_ranged(target, 1.0 / 60.0, stay_in_arena, leader)
		and ranged.escort._ranged_goal.is_finite() and ranged.escort._ranged_goal.x < leader.global_position.x,
		"A free firing position can be chosen behind friendly cover")
	ranged._stop_movement()
	ranged.global_position = ARENA
	target.global_position = ARENA + Vector2(30, 0)
	ranged.escort._ranged_goal = Vector2.INF
	ranged.escort._next_ranged_plan = 0.0
	await frames(2)
	check(ranged.escort.support_ranged(target, 1.0 / 60.0, stay_in_arena)
		and ranged.escort._ranged_goal.is_finite() and ranged.escort._ranged_goal.distance_to(target.global_position) > 39.0,
		"Closing danger triggers a reachable retreat inside the permitted area")
	for unit in [ranged, leader, ally, target]:
		unit.queue_free()
	await frames(2)


func rear_priority() -> void:
	var formation: Node = mission.get_node("VillageDefense").organized
	var ranged := resident("peasant", formation.center)
	choose_weapon(ranged, &"sling")
	ranged.escort.arm_from(WEAPONS.Source.CHURCH)
	mission._guard_variants.assign([&"crossbow"])
	var professional := resident("guard", formation.center + Vector2(20, 0))
	mission._guard_variants.assign([&"sword"])
	var melee_guard := resident("guard", formation.center + Vector2(1, 0))
	var rear: Vector2 = formation.center
	var second_rear := rear + Vector2(0, 22)
	var front := rear + Vector2(0, 44)
	var posts: Array[Vector2] = [rear, second_rear, front]
	formation.slots = posts
	formation._slot_ranks = {rear: 2, second_rear: 1, front: 0}
	formation._slot_sections = {rear: 0, second_rear: 0, front: 0}
	formation.members.clear()
	formation.places.clear()
	for unit in [ranged, professional, melee_guard]:
		formation.members[unit.get_instance_id()] = weakref(unit)
	formation.assign_rank_posts()
	check(formation.places.get(professional.get_instance_id()) == rear
		and formation.places.get(ranged.get_instance_id()) == second_rear
		and formation.places.get(melee_guard.get_instance_id()) == front,
		"Existing rank allocator gives the best rear spot to the professional before the closer civilian")
