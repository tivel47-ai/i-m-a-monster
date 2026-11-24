extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const VISUAL = preload("res://scripts/infected_form_visual.gd")
const ORIGIN := Vector2(350.0, 1000.0)
const START_DISTANCE := 43.0

var _mission: Node2D
var _runner: CharacterBody2D
var _resident: CharacterBody2D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_mission = MISSION.instantiate()
	_mission.set_meta("developer_mode", true)
	root.add_child(_mission)
	_mission.mission_build = _mission._make_ability_runtime(PROGRESSION._fresh_state())
	await _frames(6)
	if (
		not _mission.developer_place(PROGRESSION.CARRIER, ORIGIN + Vector2(-70.0, 45.0))
		or not _mission.developer_place(PROGRESSION.HOUND, ORIGIN)
		or not _mission.developer_place("peasant", ORIGIN + Vector2(START_DISTANCE, 0.0))
	):
		_check(false, "Mission 1 accepts both forms and the target")
		quit(1)
		return
	var zombies: Array = _mission._owned_zombies()
	var carrier: CharacterBody2D = zombies[-2]
	_runner = zombies[-1]
	var residents: Array = _mission.villagers
	_resident = residents[-1]
	carrier.set_physics_process(false)
	_resident.set_physics_process(false)
	_resident.get_node("EncounterAttackTimer").stop()
	_runner.infection_chance = 0.0
	_check(carrier.get_roster_portrait() != null and _runner.get_roster_portrait() != null
		and carrier.has_node("InfectedFormVisual") and _runner.has_node("InfectedFormVisual"),
		"Both developer-spawned forms use their own atlas and roster portrait")
	var visual := _runner.get_node("InfectedFormVisual") as VISUAL
	var carrier_visual := carrier.get_node("InfectedFormVisual") as VISUAL
	_check_runner_idle(visual)
	_check_movement_cycle(_runner, visual, VISUAL.Clip.RUN, 2.0, "Runner")
	_check_movement_cycle(carrier, carrier_visual, VISUAL.Clip.WALK, 1.30, "Carrier")
	var health: float = _resident.current_health

	_attack()
	await _frames(7)
	_check(_runner._pounce_elapsed > 0.0 and visual._clip == VISUAL.Clip.POUNCE
		and _resident.current_health == health, "First attack winds up without damage")
	_mission.toggle_tactical_pause()
	var paused_position := _runner.global_position
	var paused_frame := visual.region_rect
	await _frames(9)
	_check(paused and _runner.global_position == paused_position and visual.region_rect == paused_frame
		and _resident.current_health == health, "Tactical pause freezes the jump and its impact")
	_mission.toggle_tactical_pause()
	await _frames(8)
	_check(visual._clip == VISUAL.Clip.POUNCE and visual.position.y < VISUAL.FEET_Y - 8.0
		and _frame_id(visual) >= VISUAL.CLIPS[VISUAL.Clip.POUNCE].x + 2
		and _resident.current_health == health, "The visible airborne pose precedes landing damage")
	await _frames(11)
	_check(_runner.global_position.distance_to(_resident.global_position) < 20.8
		and _resident.is_encounter_owner(_runner)
		and is_equal_approx(_resident.current_health, health - _runner.attack_damage),
		"Landing closes distance and resolves exactly one standard hit")
	_check(visual._clip == VISUAL.Clip.SPECIAL, "Landing displays the pounce contact and recovery")
	_check(_frame_id(visual) == VISUAL.CLIPS[VISUAL.Clip.SPECIAL].x + VISUAL.POUNCE_LANDING_FRAME
		and is_equal_approx(visual.position.y, VISUAL.FEET_Y),
		"The pounce keeps its contact pose briefly on screen")
	_resident.get_node("EncounterAttackTimer").stop()
	await _frames(61)
	_check(_runner._pounce_elapsed < 0.0 and _resident.is_encounter_owner(_runner)
		and is_equal_approx(_resident.current_health, health - _runner.attack_damage * 2.0),
		"Following hit in the same encounter uses the regular melee timer")

	await _check_repeat_pounce()

	await _reset_positions()
	var wall := StaticBody2D.new()
	wall.position = ORIGIN + Vector2(17.0, 0.0)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(5.0, 60.0)
	collider.shape = shape
	wall.add_child(collider)
	_mission.add_child(wall)
	await _frames(2)
	_attack()
	await _frames(20)
	_check(_runner._pounce_elapsed < 0.0 and _runner.global_position.x < wall.global_position.x
		and _resident.current_health == health, "An obstacle blocks the opening jump")
	wall.queue_free()

	await _reset_positions()
	_attack()
	await _frames(3)
	_check(_runner._pounce_elapsed > 0.0, "Runner commits to a clear launch")
	var crossing := StaticBody2D.new()
	crossing.position = ORIGIN + Vector2(15.0, 0.0)
	var crossing_shape := CollisionShape2D.new()
	crossing_shape.shape = shape
	crossing.add_child(crossing_shape)
	_mission.add_child(crossing)
	await _frames(17)
	_check(_runner._pounce_elapsed < 0.0 and _runner.global_position.x < crossing.global_position.x
		and _resident.current_health == health, "An obstacle that enters the path stops the jump")
	crossing.queue_free()

	await _reset_positions()
	_attack()
	await _frames(6)
	_check(_runner._pounce_elapsed > 0.0, "Pounce re-arms after closing and reopening the gap")
	_resident.global_position += Vector2(0.0, -40.0)
	await _frames(22)
	_check(_runner._pounce_elapsed < 0.0 and _resident.current_health == health
		and not _resident.is_encounter_owner(_runner), "A target that escapes contact takes no hit")

	await _reset_positions()
	_attack()
	await _frames(6)
	_check(_runner._pounce_elapsed > 0.0, "Runner starts another fresh opening")
	_runner.issue_player_move_order(ORIGIN + Vector2(-50.0, 0.0))
	await _frames(14)
	_check(_runner._pounce_elapsed < 0.0 and _resident.current_health == health
		and not _resident.is_encounter_owner(_runner), "A new movement order cancels an airborne attack")

	await _reset_positions()
	_runner.issue_player_area_hold_order()
	await _frames(25)
	_check(_runner.aggro_target == _resident and _runner._pounce_elapsed > 0.0,
		"An automatically selected target triggers the jump")
	await _frames(23)
	_check(_runner.aggro_target == _resident and _resident.is_encounter_owner(_runner)
		and is_equal_approx(_resident.current_health, health - _runner.attack_damage),
		"Automatic target acquisition uses the same opening jump")

	await _reset_positions()
	_attack()
	await _frames(14)
	_check(visual._clip == VISUAL.Clip.POUNCE and visual.position.y < VISUAL.FEET_Y,
		"The Runner is airborne before the approaching target enters its path")
	_resident.global_position = _runner.global_position + Vector2(9.0, 0.0)
	await _frames(2)
	_check(_resident.is_encounter_owner(_runner) and visual._clip == VISUAL.Clip.SPECIAL
		and is_equal_approx(_resident.current_health, health - _runner.attack_damage),
		"Contact with the chosen opponent lands the pounce instead of canceling it")

	await _check_runner_death(visual)

	print("Runner pounce: %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check_movement_cycle(
	actor: CharacterBody2D, visual: VISUAL, clip: VISUAL.Clip, distance: float, label: String
) -> void:
	var origin := actor.global_position
	var frames_seen := {}
	var textures_seen := {}
	var stayed_in_cycle := true
	var frames: Vector2i = VISUAL.CLIPS[clip]
	for tick in 64:
		var direction := Vector2(0.8, 0.6 if tick < 32 else -0.6)
		actor.global_position += direction * distance
		visual._physics_process(1.0 / 60.0)
		var frame := _frame_id(visual)
		frames_seen[frame] = true
		textures_seen[visual.texture] = true
		stayed_in_cycle = stayed_in_cycle and frame >= frames.x and frame < frames.x + frames.y
	actor.global_position = origin
	visual._previous_position = origin
	_check(stayed_in_cycle and frames_seen.size() == 16 and textures_seen.size() == 2,
		label + " keeps the 16-phase movement clip through a change of direction")


func _check_runner_idle(visual: VISUAL) -> void:
	var stable := 0
	for direction in range(16):
		visual._face(Vector2.from_angle(PI / 2.0 - direction * VISUAL.TURN_STEP))
		visual._idle_elapsed = 0.0
		visual._show_idle()
		var initial := visual.transform
		var initial_frame := visual.region_rect
		var initial_motion: Vector2 = visual._idle_material.get_shader_parameter("idle_motion")
		visual._idle_elapsed = 0.64
		visual._show_idle()
		var breath_motion: Vector2 = visual._idle_material.get_shader_parameter("idle_motion")
		visual._idle_elapsed = 4.48
		visual._show_idle()
		var glance_motion: Vector2 = visual._idle_material.get_shader_parameter("idle_motion")
		if visual._direction == direction and visual.transform == initial and (
			visual.region_rect == initial_frame and absf(breath_motion.y) > absf(initial_motion.y)
			and absf(glance_motion.x) > absf(breath_motion.x)
		):
			stable += 1
	_check(stable == 16, "All sixteen idle facings breathe and glance without changing the source pose or anchor")


func _check_repeat_pounce() -> void:
	var opponent_position := _resident.global_position
	var health: float = _resident.current_health
	_runner.issue_player_move_order(opponent_position - Vector2(33.0, 0.0))
	await _frames(12)
	var gap := _runner.global_position.distance_to(opponent_position)
	_attack()
	await _frames(3)
	_check(gap > _runner.INFECTION_DISTANCE and gap < _runner.POUNCE_REARM_DISTANCE
		and _runner._pounce_elapsed < 0.0, "A brief step back and a fresh order do not rearm pounce")
	await _frames(12)
	_check(_resident.is_encounter_owner(_runner), "A short retreat still lets the Runner return to melee")

	_runner.issue_player_move_order(opponent_position - Vector2(60.0, 0.0))
	for frame in range(40):
		await _frames(1)
		if _runner.global_position.distance_to(opponent_position) >= 51.0:
			break
	gap = _runner.global_position.distance_to(opponent_position)
	_attack()
	await _frames(3)
	_check(gap > 48.0 and gap <= _runner.POUNCE_RANGE and _runner._pounce_elapsed > 0.0,
		"Retreating by two melee radii immediately re-arms a jump from up to three")
	await _frames(24)
	_check(_resident.is_encounter_owner(_runner) and is_equal_approx(_resident.current_health, health - _runner.attack_damage),
		"The repeat jump lands one hit on the same opponent")

	_runner.global_position = opponent_position - Vector2(55.0, 0.0)
	await _frames(3)
	_check(not _resident.is_encounter_owner(_runner) and _runner._pounce_elapsed > 0.0,
		"Forced separation restarts the jump pursuit without a new attack order")


func _check_runner_death(visual: VISUAL) -> void:
	var fluids := _mission.get_node("CombatFluids")
	var count: int = fluids._pools.size()
	_runner.take_damage(_runner.current_health)
	await _frames(72)
	var last_frame: int = VISUAL.CLIPS[visual._death].x + VISUAL.CLIPS[visual._death].y - 1
	var bounds: Rect2 = fluids._pose_bounds(visual)
	_check(_runner.is_dead and _frame_id(visual) == last_frame and not visual.is_physics_processing()
		and bounds.size.x >= VISUAL.RUNNER_HEIGHT, "The corpse retains the final full-length Runner pose")
	_check(fluids._pools.size() == count + 1 and (
		fluids._pools[-1].sprite.global_position.distance_to(bounds.get_center()) < 0.26
	), "The slime pool is centered under the visible body")


func _frame_id(visual: VISUAL) -> int:
	var cell := Vector2i(visual.region_rect.position) / VISUAL.CELL
	return cell.y * VISUAL.COLUMNS + cell.x


func _reset_positions() -> void:
	_runner.issue_player_move_order(ORIGIN)
	_runner.has_target = false
	_resident.global_position = ORIGIN + Vector2(START_DISTANCE, 0.0)
	_resident.current_health = _resident.max_health
	# Cross the rearm boundary while a player move order suppresses combat.
	_runner.global_position = _resident.global_position - Vector2(25.0, 0.0)
	await _frames(2)
	_runner.global_position = ORIGIN
	await _frames(2)


func _attack() -> void:
	var targets: Array[Node2D] = [_resident]
	_runner.issue_player_attack_order(targets)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error(message)
