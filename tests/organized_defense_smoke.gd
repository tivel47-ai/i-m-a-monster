extends SceneTree
var failures: int = 0
var checks: int = 0
var map: Node
var formation: Node
var service: Node
var guards: Array = []
var civilians: Array = []
var units: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func fixture() -> void:
	if is_instance_valid(map):
		map.queue_free()
		await frames(2)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	guards.clear()
	civilians.clear()
	units = get_nodes_in_group("player_units")
	for unit in units:
		unit.set_physics_process(false)
		unit.get_node("AggroArea").monitoring = false
		unit.global_position = Vector2(100, 100)
	for resident in map.villagers:
		resident.autonomous_movement_enabled = false
		if resident.guard_ai != null: guards.append(resident)
		elif resident.escort != null and resident.escort.can_recruit(): civilians.append(resident)
	await frames(3)
	service = map.get_node("VillageDefense")
	formation = service.organized

func activate() -> void:
	service.alert.bell_activated = true
	service.alert.advance_level(service.alert.Level.ALARM)
	service.alert.add_danger(service.alert.danger_threshold)

func run() -> void:
	await fixture()
	for level in [0, 1, 2]:
		service.alert.level = level
		check(not formation.update_actor(civilians[0], 0.016), "Earlier alert level leaves defense controller inactive: " + str(level))
	service.alert.level = 0
	var guard = guards[0]
	var first = civilians[0]
	var second = civilians[1]
	first.escort.leader = guard.guard_ai
	second.escort.leader = guard.guard_ai
	guard.guard_ai.followers.assign([first.escort, second.escort])
	first.global_position = Vector2(800, 900)
	second.global_position = Vector2(850, 900)
	activate()
	await frames(2)
	check(formation.active() and formation.forward.dot(Vector2.DOWN) > 0.99, "Existing threshold activates outward church defense")
	check(not first.escort.armed and not second.escort.armed, "No remote equipment on activation")
	check(guard.guard_ai.followers.size() == 2, "Transition preserves both escort responsibilities")
	first.global_position = formation.center
	first.infection_state = first.InfectionState.IN_COLLISION
	formation.check_arrival(first)
	check(first.escort.armed and formation.arrived(first), "Arrival during combat immediately equips and joins")
	check(guard.guard_ai.followers.size() == 1 and second.escort.leader == guard.guard_ai, "Arrival releases only that follower")
	first.infection_state = first.InfectionState.AVAILABLE
	second.global_position = formation.center + Vector2(0, 20)
	formation.check_arrival(second)
	check(guard.guard_ai.followers.is_empty(), "Second arrival completes escort independently")
	var priest = map.get_node("Villagers/Priest30")
	priest.global_position = formation.center
	formation.check_arrival(priest)
	check(not priest.escort.armed and formation.arrived(priest), "Priest joins unarmed")
	var late = civilians.slice(2, 6)
	for actor in map.villagers:
		if late.has(actor):
			actor.global_position = Vector2(900, 900)
			continue
		actor.global_position = formation.center
		formation.check_arrival(actor)
		actor.global_position = Vector2(900, 900)
	formation.refresh(0.0)
	check(formation.slots.size() >= formation.members.size(), "Obstacle-filtered capacity accommodates all current members")
	var points: Array[Vector2] = []
	for actor in map.villagers:
		if not formation.arrived(actor): continue
		var point: Vector2 = formation.position_for(actor)
		check(point.is_finite() and formation.inside(point), "Interior place for " + actor.name)
		if point.is_finite():
			for other in points: check(point.distance_to(other) >= formation.spacing * 0.9, "Reservations remain separated")
			points.append(point)
			actor.global_position = point
	formation.refresh(0.0)
	check(formation.physical_population == formation.members.size(), "Physical density includes priest and personal guards")
	var broad: float = formation.radius
	var excursion = guards[0]
	excursion.global_position = formation.center + Vector2(0, broad + 120)
	formation.refresh(0.1)
	check(is_equal_approx(formation.radius, broad), "Brief excursion cannot immediately contract geometry")
	check(formation.physical_population == formation.members.size() - 1, "Excursion excluded from physical occupancy immediately")
	excursion.global_position = formation.places[excursion.get_instance_id()]
	for actor in civilians.slice(6, 16): actor.infection_state = actor.InfectionState.TRANSFORMING
	formation.refresh(formation.contraction_delay + 0.1)
	check(formation.radius < broad, "Sustained losses reduce exterior area")
	var compact: float = formation.radius
	var protector = map.get_node("Villagers/PriestGuard1")
	check(protector.guard_ai == null and protector.priest_guard != null, "Personal guards retain their separate controller")
	for actor in late:
		actor.global_position = formation.center + Vector2(0, 10)
		formation.check_arrival(actor)
	formation.controller(priest).immediate_until = service.elapsed + 1.0
	formation.refresh(0.5)
	check(is_equal_approx(formation.radius, compact), "Immediate threat defers resizing even before melee starts")
	formation.controller(priest).immediate_until = 0.0
	formation.refresh(0.5)
	check(formation.radius > compact, "Late arrival permits re-expansion after contraction")
	check(formation.members.has(priest.get_instance_id()), "Priest remains included in membership")
	await tactical_checks()
	await sector_support_check()
	await sector_transfer_check()
	await flank_reinforcement_check()
	await density_checks()
	await ranged_checks()
	await movement_check()
	map.queue_free()
	await frames(2)
	print("ORGANIZED_DEFENSE focused checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)

func tactical_checks() -> void:
	await fixture()
	activate()
	await frames(2)
	var guard = guards[0]
	var helper = guards[1]
	var behavior = formation.controller(guard)
	formation.radius = 125.0
	guard.global_position = formation.center + Vector2(0, 75)
	helper.global_position = guard.global_position + Vector2(0, 30)
	formation.members[guard.get_instance_id()] = weakref(guard)
	formation.members[helper.get_instance_id()] = weakref(helper)
	formation.places[guard.get_instance_id()] = guard.global_position
	behavior.allies.assign([helper])
	units[0].global_position = formation.center + Vector2(75, 50)
	units[1].global_position = formation.center + Vector2(-75, 50)
	units[2].global_position = formation.center + Vector2(-85, 55)
	behavior.enemies.assign([units[0], units[1], units[2]])
	var bigger = formation.sector(units[1].global_position)
	check(behavior.assistance_sector() == bigger, "Adjacent assistance prefers local zombie count")
	behavior.enemies.assign([units[0], units[1]])
	check(behavior.assistance_sector() == bigger, "Small count fluctuation preserves assistance commitment")
	units[2].global_position = formation.center + Vector2(0, 105)
	behavior.enemies.assign([units[0], units[1], units[2]])
	check(behavior.assistance_sector() == formation.sector(guard.global_position), "Own threatened sector cannot be abandoned")
	behavior.enemies.assign([units[2]])
	behavior.allies.clear()
	check(behavior.assistance_sector() == formation.sector(guard.global_position), "Last local defender remains in sector")
	guard.global_position = formation.center + Vector2(0, 100)
	formation.places[guard.get_instance_id()] = guard.global_position
	units[0].global_position = guard.global_position + Vector2(0, 24)
	units[1].global_position = guard.global_position + Vector2(0, -24)
	behavior.enemies.assign([units[0], units[1]])
	behavior.allies.clear()
	check(behavior.choose_target(true) == units[1], "Target selection prefers deeper penetration")
	behavior.allies.assign([helper])
	formation.controller(helper).target = units[1]
	check(behavior.target_load(units[1]) == 1, "Local visible ally target contributes to distribution")
	behavior.remember_failure(formation.center)
	check(behavior.failed_point(formation.center), "Failed route endpoint remembered for reassessment")
	units[2].global_position = Vector2(100, 100)
	units[0].global_position = guard.global_position + Vector2(0, 16)
	await frames(2)
	units[0].engage_defender(guard)
	behavior.update(0.016)
	check(guard.is_in_collision() and not guard.has_destination, "Direct melee holds position instead of reforming or escaping")
	check(behavior.help_sector == -1, "Direct attack interrupts assistance")
	units[0].global_position += Vector2(200, 0)
	behavior.update(0.016)
	check(not guard.is_in_collision(), "Separated melee target cannot continue remote damage")

func sector_support_check() -> void:
	await fixture()
	activate()
	await frames(2)
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	var front = civilians[0]
	var supporter = civilians[1]
	var cover = civilians[2]
	var enemy = units[0]
	formation.radius = 140.0
	front.global_position = formation.center + Vector2(135, 10)
	supporter.global_position = front.global_position + Vector2(-30, 18)
	cover.global_position = front.global_position + Vector2(0, 36)
	for defender in [front, supporter, cover]:
		formation.members[defender.get_instance_id()] = weakref(defender)
		formation.places[defender.get_instance_id()] = defender.global_position
	enemy.global_position = front.global_position + Vector2(16, 0)
	await frames(2)
	check(enemy.engage_defender(front), "Enemy physically attacks the right line")
	var helper = formation.controller(supporter)
	helper.sense()
	check(helper.enemies.has(enemy) and helper.choose_target(true) == enemy, "Nearby defender reacts immediately to visible attack")
	var reserve = formation.controller(cover)
	reserve.sense()
	helper.engage(enemy, 0.016)
	check(helper.target == enemy and supporter.has_destination, "Supporter starts a reachable approach on a different side")
	check(reserve.choose_target(true) == enemy, "Third nearby defender may help an attacked neighbor when no other enemy needs interception")

func sector_transfer_check() -> void:
	await fixture()
	activate()
	await frames(2)
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	formation.radius = 150.0
	formation.slots = formation.build_slots(civilians[0], formation.radius)
	formation.places.clear()
	var flank: Array[Vector2] = []
	for point in formation.slots:
		if not formation.central_slot(point) and formation.sector(point) == 2: flank.append(point)
	check(flank.size() >= 4, "Flank provides two rows of reachable positions")
	if flank.size() < 4: return
	for i in 4:
		var defender = civilians[i]
		formation.places[defender.get_instance_id()] = flank[i]
		defender.global_position = flank[i]
	await frames(1)
	var first: Vector2 = formation.position_for(civilians[0], Vector2.INF, INF, true, true)
	var second: Vector2 = formation.position_for(civilians[1], Vector2.INF, INF, true, true)
	check(formation.sector(first) == 1, "Idle defender fills a gap in the neighboring underfilled line")
	check(formation.sector(second) == 2, "Transfer cooldown prevents simultaneous reassignment")

func flank_reinforcement_check() -> void:
	await fixture()
	activate()
	await frames(2)
	formation.set_physics_process(false)
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	formation.radius = 150.0
	formation.slots = formation.build_slots(civilians[0], formation.radius)
	formation.places.clear()
	formation.members.clear()
	var flanks: Array[Array] = [[], [], []]
	for point in formation.slots:
		if not formation.central_slot(point): flanks[formation.sector(point)].append(point)
	check(flanks[0].size() >= 4 and flanks[1].size() >= 4 and flanks[2].size() >= 4,
		"Three flanks have enough reachable places for loss and reinforcement")
	if flanks[0].size() < 4 or flanks[1].size() < 4 or flanks[2].size() < 4: return
	var assigned: Array[Array] = [[], [], []]
	for side in range(3):
		for i in 4:
			var defender = civilians[side * 4 + i]
			defender.global_position = flanks[side][i]
			formation.members[defender.get_instance_id()] = weakref(defender)
			formation.places[defender.get_instance_id()] = flanks[side][i]
			assigned[side].append(defender)
	formation.update_flank_strength()
	check(formation._flank_peak == [4, 4, 4], "Peak records the established strength of each flank")
	for i in range(3):
		var lost = assigned[2][i]
		formation.members.erase(lost.get_instance_id())
		formation.places.erase(lost.get_instance_id())
		lost.global_position = Vector2(900, 900)
	var west = assigned[0][0]
	formation.controller(west).mode = "combat"
	check(formation.reinforcement_target(west) == -1, "Fighting defender does not leave the intact donor flank")
	formation.controller(west).mode = "position"
	check(formation.reinforcement_target(west) == 2, "Idle intact west flank recognizes east below 30 percent")
	formation.controller(west).next_decision = 0.0
	formation.controller(west).next_gap_check = 0.0
	formation.update_actor(west, 0.016)
	var first: Vector2 = formation.places.get(west.get_instance_id(), Vector2.INF)
	check(formation.sector(first) == 2, "West defender can reinforce east directly")
	formation._next_transfer = 0.0
	var south = assigned[1][0]
	check(formation.reinforcement_target(south) == 2, "Reinforcement continues until the weakened flank reaches 60 percent")
	var second: Vector2 = formation.position_for(south, Vector2.INF, INF, true, true, 2)
	check(formation.sector(second) == 2, "Second donor fills another east place")
	check(formation.reinforcement_target(assigned[0][1]) == -1, "Reinforcement stops after the recovery target")

func ranged_checks() -> void:
	await fixture()
	activate()
	await frames(2)
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	var shooter = guards[0]
	var ally = civilians[0]
	var enemy = units[0]
	shooter.global_position = Vector2(1360, 620)
	ally.global_position = Vector2(1400, 620)
	enemy.global_position = Vector2(1450, 620)
	shooter.defense_ranged_weapon = true # Focused fixture only; no map equipment change.
	var behavior = formation.controller(shooter)
	await frames(2)
	var health: float = enemy.current_health
	var friendly_health: float = ally.current_health
	check(behavior.shoot(enemy), "Configured ranged guard can fire at a visible in-range enemy")
	await frames(30)
	check(enemy.current_health < health, "Physical bolt reaches enemy through an ally")
	check(ally.current_health == friendly_health, "Friendly bolt does not damage ally")
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(1400, 620)
	var collision = CollisionShape2D.new()
	var rectangle = RectangleShape2D.new()
	rectangle.size = Vector2(8, 60)
	collision.shape = rectangle
	wall.add_child(collision)
	map.add_child(wall)
	await frames(2)
	check(not behavior.shoot(enemy), "Solid obstacle prevents ranged targeting")
	formation.members[shooter.get_instance_id()] = weakref(shooter)
	behavior.engage(enemy, 0.016)
	check(not shooter.has_destination, "Ranged defender never walks forward to bypass a blocked shot")
	var projectile = load("res://scripts/defender_projectile.gd").new()
	projectile.position = shooter.global_position
	projectile.direction = Vector2.RIGHT
	projectile.damage = shooter.attack_damage
	map.add_child(projectile)
	health = enemy.current_health
	await frames(30)
	check(enemy.current_health == health, "In-flight projectile also stops at a wall")
	wall.queue_free()
	shooter.defense_ranged_weapon = false

func density_checks() -> void:
	await fixture()
	activate()
	await frames(2)
	formation.members.clear()
	formation.places.clear()
	formation.settling.clear()
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	var participants = civilians.slice(0, 12)
	for resident in participants:
		resident.global_position = formation.center
		formation.check_arrival(resident)
		resident.global_position = Vector2(900, 900)
	formation.refresh(0.0)
	for resident in participants:
		resident.global_position = formation.position_for(resident)
	formation.refresh(0.0)
	var initial: float = formation.radius
	var away = participants.slice(0, 6)
	for resident in away: resident.global_position = formation.center + Vector2(0, initial + 150)
	formation.refresh(0.1)
	check(formation.physical_population == 6 and formation.capacity_population == 12, "Density excludes excursions while capacity retains short absence grace")
	service.elapsed += formation.contraction_delay + 0.1
	formation.refresh(formation.contraction_delay + 0.1)
	check(formation.radius < initial, "Sustained low physical occupancy contracts without requiring casualties")
	var smaller: float = formation.radius
	for resident in away: resident.global_position = formation.center + Vector2(0, 10)
	formation.refresh(0.1)
	check(formation.radius > smaller, "Returning living residents restore required capacity")
	var removed = away[0]
	var id: int = removed.get_instance_id()
	removed.queue_free()
	await frames(2)
	formation.refresh(0.1)
	check(not formation.controllers.has(id) and not formation.members.has(id) and not formation.places.has(id), "Freed resident leaves no stale membership or position")

func movement_check() -> void:
	await fixture()
	await frames(30) # Wait for the imported navigation region to sync in headless runs.
	activate()
	await frames(2)
	var actor = civilians[0]
	actor.global_position = formation.center + Vector2(0, formation.arrival_radius + 20)
	var start: Vector2 = actor.global_position
	actor.autonomous_movement_enabled = true
	await frames(45)
	check(actor.global_position.distance_to(start) > 5.0, "Real navigation physically advances civilian toward church")
	check(formation.arrived(actor) and actor.escort.armed, "Physical movement triggers arrival and equipment")
	check(map.mission_state == map.MissionState.ACTIVE, "Defense does not change mission completion state")
