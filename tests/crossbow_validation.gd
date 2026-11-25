extends SceneTree

const MISSION = preload("res://tests/fixtures/mission_one_with_zombies.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const FORMS = preload("res://scripts/zombie_mission_build.gd")
const BOLT = preload("res://scripts/defender_projectile.gd")
const VISUAL = preload("res://scripts/crossbow_guard_visual.gd")
const CENTER := Vector2(4100, 2100)
const STEP := 1.0 / 60.0

var mission: Node2D
var defense: Node
var checks := 0
var failures := 0


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
		await process_frame


func run() -> void:
	mission = MISSION.instantiate()
	mission.set_meta("developer_mode", true)
	root.add_child(mission)
	mission.set_process(false)
	defense = mission.get_node("VillageDefense")
	mission.get_node("LastStand").set_physics_process(false)
	for resident in mission.villagers:
		resident.autonomous_movement_enabled = false
		resident.threat_detection.detection_enabled = false
	for zombie in mission._owned_zombies():
		zombie.set_physics_process(false)
	var arena := NavigationRegion2D.new()
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([CENTER + Vector2(-300, -300), CENTER + Vector2(300, -300),
		CENTER + Vector2(300, 300), CENTER + Vector2(-300, 300)])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	arena.navigation_polygon = polygon
	mission.add_child(arena)
	await frames(5)
	await test_bolts()
	await test_approach()
	await test_melee()
	await test_guard_ai()
	await test_disengagement()
	await test_protection()
	await test_defensive_post()
	await test_squad()
	await test_visual_lifecycle()
	mission.queue_free()
	await frames(2)
	print("Crossbow validation: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func guard(variant := &"crossbow", point := CENTER, squad: Node = null) -> Node2D:
	var actor: Node2D = mission._spawn_reinforcement(variant, point, squad)
	actor.set_physics_process(false)
	actor.threat_detection.detection_enabled = false
	actor.unit_vision.face(Vector2.RIGHT)
	return actor


func monster(form: String, point: Vector2) -> Node2D:
	var actor := ZOMBIE.instantiate()
	FORMS.apply_form(actor, form, true)
	actor.position = mission.to_local(point)
	mission.add_child(actor)
	actor.set_physics_process(false)
	actor.infection_chance = 0.0
	actor.get_node("AggroArea").monitoring = false
	return actor


func latest_bolt() -> Node2D:
	for child in mission.get_children():
		if child.get_script() == BOLT and not child.is_queued_for_deletion():
			return child
	return null


func wall(point: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = mission.to_local(point)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	mission.add_child(body)
	return body


func test_bolts() -> void:
	var shooter := guard()
	var ally := guard(&"shield", CENTER + Vector2(90, 0))
	var target := monster("", CENTER + Vector2(175, 0))
	var far_target := monster("", CENTER + Vector2(205, 20))
	await frames(2)
	check(shooter.unit_vision.contains(CENTER + Vector2(0, 250))
		and not shooter.unit_vision.contains(CENTER + Vector2(-5, 0))
		and not shooter.unit_vision.contains(CENTER + Vector2(251, 0)), "250-unit vision includes the front semicircle and its 180-degree boundary")
	check(not shooter.try_fire_defense_bolt(far_target), "A visible target beyond 200 cannot be shot")
	shooter.velocity = Vector2.RIGHT * 85
	check(not shooter.try_fire_defense_bolt(target), "Moving shooter cannot fire")
	shooter.velocity = Vector2.ZERO
	check(shooter.guard_ai.hold_for_bolt(target), "Guard fires at 175 units")
	var visual: Sprite2D = shooter.get_node("CrossbowVisual")
	check(visual.region_rect.position == Vector2(VISUAL.CONTACT_FRAME, VISUAL.SHOT_ROW + 2) * VISUAL.CELL,
		"Eastward shot uses the release pose on the same tick as the bolt")
	var bolt := latest_bolt()
	check(is_instance_valid(bolt) and bolt.damage == 40.0 and bolt.speed == 280.0 and bolt.remaining == 200.0, "Bolt inherits the ranged profile on launch")
	if is_instance_valid(bolt):
		var start := bolt.global_position
		check(start == shooter.global_position and bolt.display_origin_offset.x > 0.0
			and bolt.display_origin_offset.y < 0.0, "Bolt is drawn at the crossbow while the physical ray starts at the actor")
		var started_at: float = defense.elapsed
		await frames(6)
		var speed: float = start.distance_to(bolt.global_position) / (defense.elapsed - started_at)
		check(absf(speed - 280.0) < 0.1, "Physical bolt travels at 280 units per simulation second (%.2f)" % speed)
		var before_pause := bolt.global_position
		var pause_time: float = defense.elapsed
		var reload: float = shooter.ranged_ready_at
		var paused_pose := visual.region_rect
		paused = true
		await frames(8)
		check(bolt.global_position == before_pause and defense.elapsed == pause_time and shooter.ranged_ready_at == reload
			and visual.region_rect == paused_pose and not shooter.try_fire_defense_bolt(target),
			"Pause suspends the visual pose, bolt travel and simulation reload")
		paused = false
	var reload_at: float = shooter.ranged_ready_at
	var organized = load("res://scripts/organized_defender.gd").new(defense.organized, shooter)
	var alternative := monster("", CENTER + Vector2(150, 30))
	check(organized.shoot(alternative) and shooter.ranged_ready_at == reload_at, "Changing target and entering organized behavior preserves reload")
	await frames(42)
	check(target.current_health == 140.0 and ally.current_health == ally.max_health
		and alternative.current_health == alternative.max_health, "Only the target takes 40 damage through the friendly guard")
	check(visual.region_rect.position.y == (VISUAL.RELOAD_ROW + 2) * VISUAL.CELL.y,
		"Stationary crossbow uses its reload poses during the existing cooldown")
	target.queue_free()
	ally.queue_free()
	alternative.queue_free()
	await frames(2)
	while defense.elapsed + STEP < reload_at:
		await frames(1)
	check(organized.shoot(far_target) == false and shooter.ranged_ready_at == reload_at, "Reload and range use independent gates")
	await frames(2)
	var moving_target := monster("", CENTER + Vector2(155, 0))
	var blocker := wall(CENTER + Vector2(80, 0), Vector2(8, 60))
	await frames(2)
	check(not organized.shoot(moving_target) and shooter.ranged_ready_at == reload_at, "Wall blocks target acquisition even after reload")
	blocker.queue_free()
	await frames(2)
	check(organized.shoot(moving_target) and is_equal_approx(shooter.ranged_ready_at - defense.elapsed, 2.8), "Organized defender fires on the same 2.8-second clock")
	blocker = wall(CENTER + Vector2(80, 0), Vector2(8, 60))
	await frames(48)
	check(moving_target.current_health == moving_target.max_health and latest_bolt() == null, "Wall intercepts a bolt in flight")
	blocker.queue_free()
	while defense.elapsed < shooter.ranged_ready_at:
		await frames(1)
	check(shooter.try_fire_defense_bolt(moving_target), "Crossbow can fire again after reload")
	var miss := latest_bolt()
	if is_instance_valid(miss):
		moving_target.move_and_collide(Vector2.DOWN * 35.0)
	await frames(50)
	check(moving_target.current_health == moving_target.max_health and not is_instance_valid(miss), "Ordinary lateral movement avoids a straight bolt that expires at its travel limit")
	for actor in [shooter, moving_target, far_target]: actor.queue_free()
	await frames(2)


func test_approach() -> void:
	var shooter := guard()
	var target := monster("", CENTER + Vector2(225, 0))
	await frames(2)
	check(shooter.guard_ai.engage_target(target, STEP, CENTER, 260.0) and shooter.has_destination
		and shooter.ranged_ready_at == 0.0, "A visible target beyond range prompts movement and no immediate shot")
	for i in 50:
		if shooter.ranged_ready_at > 0.0: break
		await frames(1)
		shooter.guard_ai.engage_target(target, STEP, CENTER, 260.0)
	var distance := shooter.global_position.distance_to(target.global_position)
	check(shooter.ranged_ready_at > 0.0 and not shooter.has_destination and distance <= 200.0 and distance > 190.0,
		"Approach stops and fires at the first valid firing position")
	shooter.queue_free()
	target.queue_free()
	await frames(50)


func test_melee() -> void:
	var shooter := guard()
	var target := monster("", CENTER + Vector2(12, 0))
	await frames(2)
	check(shooter.try_fire_defense_bolt(target), "Initial ranged shot starts reload before contact")
	var bolt := latest_bolt()
	if is_instance_valid(bolt): bolt.queue_free()
	var reload: float = shooter.ranged_ready_at
	check(target.engage_defender(shooter) and shooter.is_in_collision(), "A monster can force a real encounter")
	check(not shooter.try_fire_defense_bolt(target), "Melee collision suppresses ranged fire")
	await frames(89)
	check(target.current_health == target.max_health and shooter.current_health == shooter.max_health - 21.0,
		"Incoming melee damage lands before the crossbow's 1.6-second counter")
	await frames(11)
	check(target.current_health == target.max_health - 8.0 and shooter.ranged_ready_at == reload, "Counterattack deals 8 and leaves ranged reload intact")
	var visual: Sprite2D = shooter.get_node("CrossbowVisual")
	check(visual.region_rect.position.y == (VISUAL.PUSH_ROW + 2) * VISUAL.CELL.y,
		"Actual melee contact interrupts the visible reload with the crossbow push")
	shooter.leave_encounter(target)
	check(not shooter.is_in_collision() and not shooter.encounter_participants.has(target), "Ordinary encounter release still works")
	check(shooter.try_fire_defense_bolt(target) and shooter.ranged_ready_at == reload, "Leaving melee does not grant a second shot")
	target.infection_chance = 1.0
	check(target.engage_defender(shooter), "Released monster can reengage")
	await frames(91)
	check(shooter.infection_state == shooter.InfectionState.TRANSFORMING, "An engaged crossbow can be infected")
	shooter.queue_free()
	target.queue_free()
	await frames(2)


func step_back(shooter: Node2D, enemies: Array[Node2D], allies: Array[Node2D] = []) -> bool:
	var guard_ai: Node = shooter.guard_ai
	return guard_ai.crossbow_disengage(STEP, enemies, allies, [&"guard"], guard_ai.can_step_back)


func test_guard_ai() -> void:
	mission._guard_variants.assign([&"crossbow"])
	if not mission.developer_place("guard", CENTER):
		check(false, "Developer places an ordinary guard for autonomous combat")
		return
	var shooter: Node2D = mission.villagers.back()
	var target := monster("", CENTER + Vector2(165, 0))
	shooter.unit_vision.face(Vector2.RIGHT)
	shooter.guard_patrol.patrol_enabled = false
	shooter.threat_detection.recognition_delay_min = 0.0
	shooter.threat_detection.recognition_delay_max = 0.0
	for i in 50:
		if shooter.ranged_ready_at > 0.0: break
		await frames(1)
	check(shooter.ranged_ready_at > 0.0 and shooter.global_position.distance_to(CENTER) < shooter.arrival_tolerance,
		"Ordinary Guard AI recognizes and shoots a safe target without unnecessary movement")
	target.global_position = shooter.global_position + Vector2(50, 0)
	var tactics: RefCounted = shooter.guard_ai.crossbow
	for i in 45:
		if tactics.goal.is_finite(): break
		await frames(1)
	check(tactics.goal.is_finite() and tactics.goal.x < shooter.global_position.x and tactics.spent > 0.0,
		"Ordinary Guard AI responds to the same recognized monster approaching")
	shooter.queue_free()
	target.queue_free()
	await frames(50)


func test_disengagement() -> void:
	for form in ["", "brute", "carrier", "hound"]:
		var shooter := guard()
		var target := monster(form, CENTER + Vector2(54, 0))
		await frames(2)
		var tactics: RefCounted = shooter.guard_ai.crossbow
		check(step_back(shooter, [target]), "Recognized %s at 54 units triggers a navigable disengagement" % target.name)
		var goal: Vector2 = tactics.goal
		var spent: float = tactics.spent
		var initial_anchor: Vector2 = tactics.episode_origin
		check(goal.is_finite() and goal.distance_to(target.global_position) >= 145.0 and spent <= 120.0, "Open-space retreat favors the preferred distance within budget")
		if form == "":
			var paused_position := shooter.global_position
			var retry_at: float = tactics.next_attempt
			paused = true
			await frames(8)
			check(shooter.global_position == paused_position and tactics.next_attempt == retry_at,
				"Pause suspends maneuver movement and timing")
			paused = false
		for i in 125:
			if not tactics.goal.is_finite(): break
			await frames(1)
			var visible: Array[Node2D] = []
			if shooter.threat_detection._is_visible_target(target): visible.append(target)
			step_back(shooter, visible)
		check(not tactics.goal.is_finite() and shooter.global_position.distance_to(goal) <= shooter.arrival_tolerance, "Movement follows the selected navigation destination")
		check(shooter.guard_ai.hold_for_bolt(target) and shooter.ranged_ready_at > 0.0, "Turns back toward the recognized threat and resumes fire")
		var other := monster("", shooter.global_position + Vector2(54, 0))
		await frames(1)
		check(not step_back(shooter, [other]) and tactics.spent == spent and tactics.episode_origin == initial_anchor, "Switching targets and losing sight cannot renew the budget or bypass the maneuver interval")
		tactics.end_if_quiet(defense.elapsed + 13.0, initial_anchor)
		check(tactics.spent == spent, "A quiet interval away from the original area cannot reset a retreat budget")
		if form == "":
			# Attempt a second maneuver after the interval using the remaining route budget.
			tactics.next_attempt = defense.elapsed
			step_back(shooter, [other])
			check(tactics.spent <= 120.0 and (not tactics.goal.is_finite() or tactics.goal.distance_to(initial_anchor) <= 120.0),
				"A second maneuver is bounded cumulatively and remains anchored to the local combat area")
			tactics.spent = 120.0
			tactics.interrupt()
			shooter.guard_ai.halt()
			check(not step_back(shooter, [other]), "An exhausted retreat budget falls back to standing combat")
			shooter.global_position = initial_anchor
			tactics.end_if_quiet(defense.elapsed + 13.0, initial_anchor)
			check(tactics.spent == 0.0 and not tactics.episode_origin.is_finite(), "After quiet and return to the original area a new episode gets a fresh budget")
		if form == "hound":
			target.global_position = shooter.global_position + Vector2(12, 0)
			await frames(1)
			check(target.engage_defender(shooter), "A Runner that reaches contact can engage after a maneuver")
			target.infection_chance = 0.0
			shooter.current_health = 15.0
			await frames(62)
			check(not shooter.is_alive(), "An engaged Runner can kill the Crossbowman")
		for actor in [shooter, target, other]: actor.queue_free()
		await frames(3)


func test_protection() -> void:
	var shooter := guard()
	var target := monster("", CENTER + Vector2(54, 0))
	var ally := guard(&"spear", CENTER + Vector2(-12, 35))
	var other_crossbow := guard(&"crossbow", CENTER + Vector2(-12, -35))
	await frames(2)
	var tactics: RefCounted = shooter.guard_ai.crossbow
	var protected_point := ally.global_position + target.global_position.direction_to(ally.global_position) * 35.0
	check(step_back(shooter, [target], [other_crossbow, ally]) and tactics.goal.is_equal_approx(protected_point),
		"Prefers a position 35 units behind a melee guard relative to the threat")
	check(not ally.has_destination and not ally.is_in_collision(), "Using a protector does not issue orders to the ally")
	tactics.interrupt()
	shooter.guard_ai.halt()
	tactics.next_attempt = 0.0
	tactics.spent = 0.0
	var barrier := wall(CENTER + Vector2(-8, 44), Vector2(85, 8))
	await frames(2)
	var crossbow_point := other_crossbow.global_position + target.global_position.direction_to(other_crossbow.global_position) * 35.0
	check(step_back(shooter, [target], [other_crossbow, ally]) and not tactics.goal.is_equal_approx(protected_point)
		and not tactics.goal.is_equal_approx(crossbow_point), "Rejects a blocked protective route and a ranged ally")
	barrier.queue_free()
	tactics.interrupt()
	shooter.guard_ai.halt()
	tactics.next_attempt = 0.0
	tactics.spent = 0.0
	ally.take_damage(ally.max_health)
	await frames(2)
	check(step_back(shooter, [target], [ally]) and not tactics.goal.is_equal_approx(protected_point),
		"A fallen ally no longer provides tactical cover")
	shooter.queue_free()
	ally.queue_free()
	other_crossbow.queue_free()
	target.queue_free()
	await frames(2)

	shooter = guard()
	target = monster("", CENTER + Vector2(54, 0))
	var flank := monster("", CENTER + Vector2(-35, 12))
	await frames(2)
	tactics = shooter.guard_ai.crossbow
	shooter.unit_vision.face(Vector2.LEFT)
	# Observe the flank first, then turn right. Tactical routes may use the
	# last observation from the flank but may only shoot what they can see.
	var observed: Array[Node2D] = [flank]
	tactics._observe(defense.elapsed, observed)
	shooter.unit_vision.face(Vector2.RIGHT)
	check(not shooter.try_fire_defense_bolt(flank), "Known threat behind the unit still cannot be shot")
	var moved := step_back(shooter, [target])
	var direct := CENTER + Vector2(-96, 0)
	check(not moved or not tactics.goal.is_equal_approx(direct), "A previously seen flanking threat rules out retreat straight through it")
	for actor in [shooter, target, flank]: actor.queue_free()
	await frames(3)

	shooter = guard()
	target = monster("", CENTER + Vector2(50, 0))
	flank = monster("", CENTER + Vector2(-50, 0))
	var north := monster("", CENTER + Vector2(0, -50))
	var south := monster("", CENTER + Vector2(0, 50))
	await frames(2)
	tactics = shooter.guard_ai.crossbow
	shooter.unit_vision.face(Vector2.LEFT)
	observed.assign([flank, north, south])
	tactics._observe(defense.elapsed, observed)
	shooter.unit_vision.face(Vector2.RIGHT)
	check(not step_back(shooter, [target, north, south]) and tactics.spent == 0.0,
		"Surrounded shooter cannot pick a route through its locally known threats")
	for actor in [shooter, target, flank, north, south]: actor.queue_free()
	await frames(3)

	shooter = guard()
	target = monster("", CENTER + Vector2(54, 0))
	barrier = wall(CENTER + Vector2(-9, 0), Vector2(8, 300))
	var upper := wall(CENTER + Vector2(0, -14), Vector2(30, 8))
	var lower := wall(CENTER + Vector2(0, 14), Vector2(30, 8))
	await frames(2)
	tactics = shooter.guard_ai.crossbow
	check(not step_back(shooter, [target]) and not tactics.goal.is_finite() and tactics.spent == 0.0, "Blocked pocket cannot select an invalid route")
	check(shooter.guard_ai.hold_for_bolt(target) and not shooter.has_destination, "Trapped defender stands and fires instead of retrying every tick")
	for actor in [shooter, target, barrier, upper, lower]: actor.queue_free()
	await frames(50)


func test_defensive_post() -> void:
	var formation: Node = defense.organized
	var post := Vector2(1410, 638)
	var shooter := guard(&"crossbow", post)
	var melee := guard(&"shield", post + Vector2(26, 10))
	formation.set_physics_process(false)
	for actor in [shooter, melee]:
		formation.register_resident(actor)
		formation.members[actor.get_instance_id()] = weakref(actor)
		formation.places[actor.get_instance_id()] = actor.global_position
	shooter.unit_vision.face(Vector2.DOWN)
	shooter.threat_detection.detection_enabled = true
	var target := monster("", post + Vector2(0, 130))
	var behavior: RefCounted = formation.controller(shooter)
	await frames(2)
	behavior.enemies.assign([target])
	check(behavior.defend_crossbow_post(post, STEP, true) and not shooter.has_destination and shooter.ranged_ready_at > 0.0,
		"Fortified crossbow holds its assigned post against a safe target")
	target.global_position = post + Vector2(0, 54)
	await frames(2)
	var initial_slots: Dictionary = formation.places.duplicate()
	behavior.enemies.assign([target])
	behavior.defend_crossbow_post(post, STEP, true)
	var tactics: RefCounted = shooter.guard_ai.crossbow
	var goal: Vector2 = tactics.goal
	check(goal.is_finite() and formation.inside(goal) and formation.sector(goal) == formation.sector(post)
		and formation.places == initial_slots, "Near threat permits same-sector cover without releasing or moving either post")
	for i in 85:
		if not tactics.goal.is_finite(): break
		await frames(1)
		behavior.defend_crossbow_post(post, STEP, i % 21 == 0)
	check(shooter.global_position.distance_to(goal) <= shooter.arrival_tolerance
		and behavior.defend_crossbow_post(post, STEP, true) and not shooter.has_destination,
		"Reached protected position is held while return remains unsafe")
	target.queue_free()
	behavior.enemies.clear()
	# Advance beyond the quiet observation lifetime without changing the
	# current reservation or running the rest of the village simulation.
	defense.elapsed += 13.0
	await frames(2)
	behavior.defend_crossbow_post(post, STEP, true)
	check(shooter.has_destination and shooter.destination == post and formation.places == initial_slots,
		"Safe recovery uses the original defensive slot")
	for actor in [shooter, melee]:
		formation.members.erase(actor.get_instance_id())
		formation.release_place(actor)
		actor.queue_free()
	await frames(2)


func test_squad() -> void:
	var squad := mission.get_node("LastStand/Reinforcements")
	var shooter := guard(&"crossbow", CENTER, squad)
	var shield := guard(&"shield", CENTER + Vector2(-8, 30), squad)
	var target := monster("", CENTER + Vector2(54, 0))
	await frames(2)
	squad.soldiers.assign([shield, shooter])
	squad.mode = squad.Mode.COMBAT
	squad.encounter_origin = CENTER
	squad.waypoint = CENTER
	squad.target = target
	squad.target_point = target.global_position
	shooter.guard_ai.visible_enemies.assign([target])
	shooter.guard_ai.local_allies.assign([shield])
	var tactics: RefCounted = shooter.guard_ai.crossbow
	squad.update_soldier(shooter.guard_ai, STEP)
	check(tactics.goal.is_finite() and tactics.goal.distance_to(squad.encounter_origin) <= squad.pursuit_limit
		and not shield.has_destination, "Squad crossbow disengages with allied protection inside the original encounter")
	squad._begin_regroup()
	squad.update_soldier(shooter.guard_ai, STEP)
	check(not tactics.goal.is_finite() and tactics.spent > 0.0, "Regroup cancels independent movement and preserves the episode budget")
	squad.mode = squad.Mode.MARCH
	squad.heading = Vector2.RIGHT
	squad.path = PackedVector2Array([CENTER + Vector2(100, 0)])
	squad.path_index = 0
	squad._assign_goals(CENTER)
	check(squad.goals[shooter].x < squad.goals[shield].x, "Crossbow marches behind the melee guard")
	squad.mode = squad.Mode.COMBAT
	squad.target = target
	target.global_position = shooter.global_position + Vector2(100, 0)
	squad.target_point = target.global_position
	shooter.guard_ai.halt()
	shooter.unit_vision.face(Vector2.RIGHT)
	await frames(2)
	squad.update_soldier(shooter.guard_ai, STEP)
	var ready_at: float = shooter.ranged_ready_at
	shooter.reinforcement_squad = null
	shooter.guard_ai.next_decision = defense.elapsed + 1.0
	shooter.guard_ai.update_ai(STEP)
	check(ready_at > defense.elapsed and shooter.ranged_ready_at == ready_at and tactics.spent > 0.0 and tactics.scope == [&"guard"],
		"Returning from squad control to ordinary Guard AI retains reload and spent retreat budget")
	for actor in [shooter, shield, target]: actor.queue_free()
	await frames(2)


func test_visual_lifecycle() -> void:
	var shooter := guard()
	var visual: Sprite2D = shooter.get_node("CrossbowVisual")
	check(visual.texture == VISUAL.ATLAS and not shooter.polygon.visible,
		"Mission 1 crossbow uses its own atlas instead of the marker")
	var mapped_views := true
	for direction in range(8):
		shooter.unit_vision.face(Vector2.from_angle(PI / 2.0 - direction * TAU / 8.0))
		await frames(8)
		var row := VISUAL.IDLE_ROW + (direction if direction <= 4 else 8 - direction)
		mapped_views = (mapped_views and visual.flip_h == (direction > 4)
			and visual.region_rect.position.y == row * VISUAL.CELL.y)
	check(mapped_views, "Idle follows all eight gameplay headings with the correct mirror")

	var bell := mission.get_node("NavigationRegion2D/Buildings/Public/AlarmBell")
	bell._show_pose(shooter, 1)
	var pulling: Sprite2D = shooter.get_node("BellPullPose")
	check(pulling.texture == VISUAL.ATLAS and pulling.region_rect.position.y == VISUAL.BELL_ROW * VISUAL.CELL.y
		and not visual.visible, "Bell uses the crossbowman's own pose")
	shooter.clear_bell_pose()
	shooter.take_damage(1.0)
	check(visual.visible and visual._clip_row == VISUAL.HURT_ROW, "Surviving damage plays the reaction")
	for index in range(2):
		var body := shooter if index == 0 else guard(&"crossbow", CENTER + Vector2(20, 0))
		var body_visual: Sprite2D = body.get_node("CrossbowVisual")
		body_visual._death_row = VISUAL.FALL_FORWARD_ROW if index == 0 else VISUAL.FALL_BACK_ROW
		body.take_damage(body.max_health)
		await frames(39)
		check(body_visual._clip_row == body_visual._death_row and not body_visual.is_physics_processing()
			and body_visual.region_rect.position.x == (VISUAL.ACTION_FRAMES - 1) * VISUAL.CELL.x,
			"Fall %d keeps the last corpse pose and finishes its visual lifecycle" % index)
		body.queue_free()
	await frames(2)
