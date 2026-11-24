extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const TEST_MAP = preload("res://scenes/test_map.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const BUILD = preload("res://scripts/zombie_mission_build.gd")
const VISUAL = preload("res://scripts/brute_visual.gd")
const ART = preload("res://assets/sprites/characters/brute/frames.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var mission := MISSION.instantiate()
	mission.set_meta("developer_mode", true)
	root.add_child(mission)
	for frame in 6:
		await physics_frame
	var start := Vector2(350, 1000)
	var placed: bool = mission.developer_place(PROGRESSION.BRUTE, start)
	_check(placed, "Developer placement makes a Brute")
	if not placed:
		quit(1)
		return
	var brute: Node2D = mission._owned_zombies().back()
	var visual := brute.get_node_or_null("BruteVisual") as VISUAL
	_check(visual != null and not brute.get_node("Polygon2D").visible, "Mission 1 shows the Brute sprite")
	if visual == null:
		quit(1)
		return
	_check(brute.get_node("CollisionShape2D").shape.size == Vector2(7.8, 15.6)
		and brute.attack_damage == 42.0 and brute.attack_interval == 2.4, "Collider and combat stats match the form")
	visual._show_idle()
	_check(_frame_id(visual) in ART.IDLE_BREATHING, "Brute begins with the breathing cycle")
	visual._idle_time = 5.56
	visual._show_idle()
	_check(_frame_id(visual) in ART.IDLE_GLANCE, "Idle cycles periodically switch to the glance")
	var textures := {}
	for view in ART.VIEWS:
		textures[view.texture] = true
	_check(textures.size() == 4, "Every action sector has its own drawing atlas")
	_check(mission.developer_place("zombie", start + Vector2(-44, 3)), "Regular zombie can be placed alongside Brute")
	var ordinary: Node = mission._owned_zombies().back()
	_check(ordinary.has_node("OrdinaryZombieVisual") and not ordinary.has_node("BruteVisual"), "Ordinary sprite still loads")

	var state := PROGRESSION._fresh_state()
	state.paid[PROGRESSION.BRUTE] = [PROGRESSION.NODES[PROGRESSION.BRUTE].costs[0]]
	mission.mission_build = mission._make_ability_runtime(state)
	var peasants: Array = mission.villagers.filter(func(unit): return unit.get_meta("village_role", "") == "peasant")
	var resident: Node = peasants[0]
	_check(resident.apply_player_infection(10.0), "Mission resident accepts direct Infection")
	for value in 1000:
		seed(value)
		if PROGRESSION.choose_form(mission.mission_build.build, randf()) == PROGRESSION.BRUTE:
			seed(value)
			break
	resident.player_infection_timer.timeout.emit()
	var converted: Node = mission._owned_zombies().back()
	_check(converted != brute and converted.has_node("BruteVisual"), "Converted Brute uses the same sprite path")

	brute.issue_player_move_order(start + Vector2(75, 75))
	await create_timer(0.65).timeout
	_check(brute.global_position.distance_to(start) > 12.0 and _frame_id(visual) in ART.VIEWS[0].walk,
		"Real navigation order advances the walk cycle")
	mission.toggle_tactical_pause()
	var paused_frame := visual.region_rect
	var paused_point := brute.global_position
	await create_timer(0.16).timeout
	_check(paused and visual.region_rect == paused_frame and brute.global_position == paused_point, "Tactical pause freezes sprite and world")
	mission.toggle_tactical_pause()
	brute.set_physics_process(false)
	visual.set_physics_process(false)
	for direction in 16:
		var step := Vector2.from_angle(PI / 2.0 - direction * TAU / 16.0)
		for tick in 9:
			brute.global_position += step
			visual._physics_process(0.04)
		_check(visual._direction == direction and visual.texture == ART.VIEWS[direction >> 2].texture
			and not visual.flip_h, "Walking reaches orientation %d in the right atlas" % direction)

	var target: Node2D = peasants[1]
	target.set_physics_process(false)
	target.global_position = brute.global_position + Vector2(12, 8)
	brute.infection_chance = 0.0
	brute.aggro_target = target
	_check(target.begin_encounter(brute.zombie_visual.color, brute), "Real encounter accepts Brute")
	var timer: Timer = brute.get_node("EncounterAttackTimer")
	timer.start(0.10)
	timer.wait_time = brute.effective_attack_interval()
	var windup_health: float = target.current_health
	for tick in 10:
		visual._physics_process(0.04)
	var pending: int = visual._next_attack
	var windup: Array = ART.VIEWS[0].attacks[pending].slice(0, ART.VIEWS[0].contacts[pending])
	_check(_frame_id(visual) in windup and target.current_health == windup_health,
		"Windup uses the encounter countdown without applying damage")
	var windup_frame := _frame_id(visual)
	var health_before: float = brute.current_health
	var random_before := visual._variation.state
	brute.take_damage(5.0)
	_check(brute.current_health == health_before - 5.0 and _frame_id(visual) == windup_frame
		and visual._phase == VISUAL.Phase.FREE and visual._variation.state == random_before,
		"Damage during windup applies without interrupting or rolling a recoil")
	var varied := {}
	for attack in 3:
		target.current_health = target.max_health
		var variant := visual._next_attack
		var before: float = target.current_health
		brute._on_encounter_attack_timer_timeout()
		_check(is_equal_approx(before - target.current_health, brute.attack_damage)
			and _frame_id(visual) == ART.VIEWS[0].attacks[variant][ART.VIEWS[0].contacts[variant]],
			"Encounter hit applies damage once and selects the contact frame")
		varied[_frame_id(visual)] = true
		var contact_frame := _frame_id(visual)
		brute.take_damage(1.0)
		var kept_contact := visual._phase == VISUAL.Phase.ATTACK and _frame_id(visual) == contact_frame
		visual._physics_process(0.16)
		var recovery_frame := _frame_id(visual)
		brute.take_damage(1.0)
		_check(kept_contact and visual._phase == VISUAL.Phase.ATTACK and _frame_id(visual) == recovery_frame,
			"Damage during contact and recovery preserves the ongoing swing")
		target.global_position = brute.global_position + Vector2(12, 8)
		timer.stop()
		visual._physics_process(0.5)
	_check(varied.size() == 3, "The three attack variants alternate")
	_check(visual._phase == VISUAL.Phase.FREE and visual._variation.state == random_before,
		"Hits during attacks are neither rolled nor queued for later")

	var expected := RandomNumberGenerator.new()
	expected.seed = 406
	visual._variation.seed = expected.seed
	var matches := true
	var reactions := 0
	var last_successful_roll := 0
	for hit in 24:
		var roll_state := expected.state
		var should_react := expected.randf() < 0.5
		brute.take_damage(1.0)
		var reacted := visual._phase == VISUAL.Phase.HURT
		matches = matches and reacted == should_react
		if reacted:
			last_successful_roll = roll_state
			reactions += 1
		visual._physics_process(0.4)
	_check(matches and reactions > 0 and reactions < 24 and visual._variation.state == expected.state,
		"Eligible hits use independent one-in-two recoil rolls")
	visual._variation.state = last_successful_roll
	brute.take_damage(5.0)
	_check(visual._phase == VISUAL.Phase.HURT and _frame_id(visual) == ART.VIEWS[0].hurt[0],
		"Nonlethal damage starts recoil")
	visual._physics_process(0.16)
	_check(_frame_id(visual) == ART.VIEWS[0].hurt[2], "Recoil reaches the middle pose")
	timer.start(0.10)
	timer.wait_time = brute.effective_attack_interval()
	pending = visual._next_attack
	windup = ART.VIEWS[0].attacks[pending].slice(0, ART.VIEWS[0].contacts[pending])
	visual._physics_process(0.04)
	_check(visual._phase == VISUAL.Phase.FREE and _frame_id(visual) in windup,
		"Starting windup supersedes a recoil already in progress")
	timer.stop()

	for variant in 2:
		var falling: Node2D = ZOMBIE.instantiate()
		BUILD.apply_form(falling, PROGRESSION.BRUTE)
		falling.position = start + Vector2(65.0 + variant * 70.0, 12)
		mission.add_child(falling)
		var sprite := falling.get_node("BruteVisual") as VISUAL
		sprite._death_variant = variant
		falling.take_damage(10000.0)
		sprite._physics_process(1.0)
		_check(falling.is_dead and _frame_id(sprite) == ART.VIEWS[0].deaths[variant][-1]
			and not sprite.is_physics_processing() and not falling.get_node("DeathMarkerA").visible,
			"Death variant %d keeps its own final pose" % variant)

	await _capture(mission, start)
	mission.queue_free()
	await process_frame
	var sandbox := TEST_MAP.instantiate()
	root.add_child(sandbox)
	var legacy: Node2D = ZOMBIE.instantiate()
	BUILD.apply_form(legacy, PROGRESSION.BRUTE)
	sandbox.add_child(legacy)
	_check(not legacy.has_node("BruteVisual") and legacy.get_node("Polygon2D").visible,
		"Test map still uses its original Brute marker")
	sandbox.queue_free()
	await process_frame
	print("Brute visual validation: %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _frame_id(sprite: Sprite2D) -> int:
	var cell := Vector2i(sprite.region_rect.position) / ART.CELL
	return cell.x + cell.y * ART.COLUMNS


func _capture(mission: Node2D, center: Vector2) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty():
		return
	var camera := mission.get_node("Camera2D") as Camera2D
	camera.global_position = center + Vector2(45, 0)
	camera.zoom = Vector2(2, 2)
	camera.reset_smoothing()
	var model: Node2D = ZOMBIE.instantiate()
	BUILD.apply_form(model, PROGRESSION.BRUTE)
	model.position = center + Vector2(-18, -12)
	mission.add_child(model)
	model.set_physics_process(false)
	var sprite := model.get_node("BruteVisual") as VISUAL
	sprite.set_physics_process(false)
	sprite._show_turn()
	var windup: Node2D = ZOMBIE.instantiate()
	BUILD.apply_form(windup, PROGRESSION.BRUTE)
	windup.position = center + Vector2(75, -35)
	mission.add_child(windup)
	windup.set_physics_process(false)
	var windup_sprite := windup.get_node("BruteVisual") as VISUAL
	windup_sprite.set_physics_process(false)
	windup_sprite._show(3, ART.VIEWS[3].attacks[2][1])
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(args[0]) == OK, "Captured the sprite on the mission terrain")


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
