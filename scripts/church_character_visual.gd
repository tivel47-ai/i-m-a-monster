extends Sprite2D

signal death_finished

const HUMAN_VISUAL = preload("res://scripts/peasant_visual.gd")
const PRIEST_ATLAS = preload("res://assets/sprites/characters/priest/frames.png")
const ESCORT_ATLAS = preload("res://assets/sprites/characters/priest_escort/frames.png")
const CELL := Vector2(192, 144)
const SPRITE_FEET_Y := 123.0
const HEALTH_BAR_Y := HUMAN_VISUAL.COMBAT_HEALTH_BAR_Y - 2.0
const TURN_STEP := TAU / 16.0
const TURN_HYSTERESIS := deg_to_rad(2.0)
const TURN_STEP_SECONDS := 0.035
const STANCE_ROW := 2
const IDLE_ROW := 3
const MOVEMENT_ROW := 5
const SERMON_ROW := 21
const BELL_ROW := 24
const ACTION_ROW := 25
const GUARD_ACTION_ROWS := 6
const PRIEST_ACTION_ROWS := 3
const GUARD_ATTACKS := 3
const GUARD_IMPACT_FRAME := 3
const GUARD_ACTION_FRAMES := 6
const PRIEST_ACTION_FRAMES := 8
const HURT_FRAMES := 6
const SERMON_FRAMES := 8
const SERMON_VARIANTS := 3
const SERMON_FRAME_SECONDS := 0.20
const BELL_FRAMES := 8
const WALK_DISTANCE := 28.0
const RUN_DISTANCE := 37.0

enum Motion { STOP, WALK, RUN }
enum Action { NONE, ATTACK, HURT, DEATH }

var is_escort := false
var _actor: CharacterBody2D
var _melee_timer: Timer
var _last_position: Vector2
var _direction := 2 # S, SSE, SE ... clockwise on the reference sheets.
var _desired_direction := 2
var _turn_time := 0.0
var _motion := Motion.STOP
var _stride := 0.0
var _idle_time := 0.0
var _sermon_time := 0.0
var _attack_variant := 0
var _death_variant := 0
var _action := Action.NONE
var _action_row := 0
var _action_flip := false
var _action_first := 0
var _action_count := 0
var _action_time := 0.0
var _action_frame_seconds := 0.0


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	_melee_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	var variation := RandomNumberGenerator.new()
	variation.seed = _actor.get_instance_id()
	_attack_variant = variation.randi_range(0, GUARD_ATTACKS - 1)
	_death_variant = variation.randi_range(0, 1)
	texture = ESCORT_ATLAS if is_escort else PRIEST_ATLAS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = HUMAN_VISUAL.FEET_Y
	offset.y = CELL.y * 0.5 - SPRITE_FEET_Y
	_show_turn()


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	var opponent := _opponent()
	var windup := _is_winding_up(opponent)
	if _action == Action.HURT and windup:
		_action = Action.NONE
	if _action != Action.NONE and _advance_action(delta):
		return

	_update_motion(displacement.length(), delta)
	var bell_frame := _bell_frame()
	var preaching: bool = (_motion == Motion.STOP and not is_escort
		and not is_instance_valid(_actor.interior_building) and _actor.priest_routine.is_preaching)
	if not preaching:
		_sermon_time = 0.0
	if opponent != null:
		_aim(opponent.global_position - _actor.global_position)
	elif _motion != Motion.STOP:
		_aim(displacement)
	elif bell_frame >= 0 or preaching:
		_aim(Vector2(-1.0 if _is_west() else 1.0, 1.0))

	if _advance_turn(delta):
		_show_turn()
	elif opponent != null:
		_show_combat(opponent)
	elif _motion != Motion.STOP:
		_show_locomotion()
	elif bell_frame >= 0:
		_show_frame(bell_frame, BELL_ROW, _is_west())
	elif preaching:
		_show_sermon(delta)
	else:
		_idle_time += delta
		_show_idle()


func play_impact(heading: Vector2, interval: float) -> void:
	if not is_escort or _action == Action.DEATH:
		return
	_aim(heading, false)
	_direction = _desired_direction
	_turn_time = 0.0
	_start_action(Action.ATTACK, _action_row_base() + _attack_variant, GUARD_IMPACT_FRAME, GUARD_ACTION_FRAMES, _attack_frame_seconds(interval))
	_attack_variant = (_attack_variant + 1) % GUARD_ATTACKS


func play_hurt() -> void:
	if _action != Action.NONE or _is_winding_up(_opponent()):
		return
	var row := _action_row_base() + (GUARD_ATTACKS if is_escort else 0)
	_start_action(Action.HURT, row, 0, HURT_FRAMES, 0.05)


func play_death() -> void:
	var row := _action_row_base() + (GUARD_ATTACKS if is_escort else 0) + 1 + _death_variant
	var frames := GUARD_ACTION_FRAMES if is_escort else PRIEST_ACTION_FRAMES
	_start_action(Action.DEATH, row, 0, frames, 0.10 if is_escort else 0.105)


func _start_action(action: Action, row: int, first: int, count: int, seconds: float) -> void:
	_action = action
	_action_row = row
	_action_flip = not is_escort and _is_west()
	_action_first = first
	_action_count = count
	_action_time = 0.0
	_action_frame_seconds = seconds
	_idle_time = 0.0
	_sermon_time = 0.0
	_show_frame(first, row, _action_flip)


func _advance_action(delta: float) -> bool:
	_action_time += delta
	var frame := _action_first + int(_action_time / _action_frame_seconds)
	if frame < _action_count:
		_show_frame(frame, _action_row, _action_flip)
		return true
	if _action == Action.DEATH:
		_show_frame(_action_count - 1, _action_row, _action_flip)
		set_physics_process(false)
		death_finished.emit()
		return true
	_action = Action.NONE
	return false


func _opponent() -> Node2D:
	if not is_escort or _action == Action.DEATH or _melee_timer.is_stopped():
		return null
	return _actor.call("_encounter_attack_target") as Node2D


func _is_winding_up(opponent: Node2D) -> bool:
	return opponent != null and _melee_timer.time_left <= _attack_frame_seconds(_melee_timer.wait_time) * GUARD_IMPACT_FRAME


func _attack_frame_seconds(interval: float) -> float:
	return minf(0.10, interval / GUARD_ACTION_FRAMES)


func _action_row_base() -> int:
	var rear := mini(_direction, 16 - _direction) > 4
	if is_escort:
		var quadrant := int(rear) + 2 * int(_is_west())
		return ACTION_ROW + quadrant * GUARD_ACTION_ROWS
	return ACTION_ROW + int(rear) * PRIEST_ACTION_ROWS


func _show_combat(opponent: Node2D) -> void:
	if not _is_winding_up(opponent):
		_show_frame(_movement_direction(), STANCE_ROW)
		return
	var frame := clampi(GUARD_IMPACT_FRAME - ceili(_melee_timer.time_left / _attack_frame_seconds(_melee_timer.wait_time)), 0, GUARD_IMPACT_FRAME - 1)
	_show_frame(frame, _action_row_base() + _attack_variant)


func _update_motion(distance: float, delta: float) -> void:
	var motion := Motion.STOP
	if distance >= 4.0 * delta and distance < HUMAN_VISUAL.WORLD_HEIGHT:
		motion = Motion.RUN if _is_running(distance / delta) else Motion.WALK
	if _motion != motion:
		_idle_time = 0.0
		if _motion == Motion.STOP:
			_stride = 0.0
		_motion = motion
	if motion != Motion.STOP:
		var cycle_distance := RUN_DISTANCE if motion == Motion.RUN else WALK_DISTANCE
		_stride = fposmod(_stride + distance / cycle_distance, 1.0)


func _is_running(speed: float) -> bool:
	if is_escort:
		return speed > _actor.move_speed + 8.0 and speed >= _actor.priest_guard.tactical_speed * 0.65
	var reaction: Node = _actor.threat_reaction
	var tactical_threshold: float = _actor.tactical_move_speed(reaction.fleeing_speed) * 0.8
	return reaction.reaction_state in [reaction.Reaction.FLEEING, reaction.Reaction.SEEKING_SHELTER] or speed >= tactical_threshold


func _aim(heading: Vector2, hysteresis := true) -> void:
	if heading.is_zero_approx():
		return
	var angle := PI / 2.0 - heading.angle()
	if not hysteresis or absf(angle_difference(_desired_direction * TURN_STEP, angle)) > TURN_STEP * 0.5 + TURN_HYSTERESIS:
		_desired_direction = posmod(roundi(angle / TURN_STEP), 16)


func _advance_turn(delta: float) -> bool:
	if _direction == _desired_direction:
		_turn_time = 0.0
		return false
	_turn_time += delta
	if _turn_time >= TURN_STEP_SECONDS:
		_turn_time -= TURN_STEP_SECONDS
		var difference := posmod(_desired_direction - _direction, 16)
		_direction = posmod(_direction + (1 if difference <= 8 else -1), 16)
	return true


func _movement_direction() -> int:
	return posmod(_direction + 1, 16) >> 1


func _is_west() -> bool:
	return _direction > 8


func _show_locomotion() -> void:
	var heading := _movement_direction()
	var running := _motion == Motion.RUN
	var mirrored := not is_escort and heading > 4
	var view := 8 - heading if mirrored else heading
	var frames := 10 if running else (8 if is_escort else 12)
	_show_frame(int(_stride * frames), MOVEMENT_ROW + 2 * view + int(running), mirrored)


func _show_idle() -> void:
	if is_escort and _direction == 2:
		_show_frame(int(_idle_time * 4.0) % 4, IDLE_ROW)
	elif not is_escort and _direction in [2, 14]:
		var step := int(_idle_time * 5.0) % 32
		_show_frame(step % 8, IDLE_ROW + int(step >= 24), _is_west())
	else:
		_show_turn(1.0 + sin(_idle_time * TAU / 1.8) * 0.012)


func _bell_frame() -> int:
	if is_escort or not is_instance_valid(_actor.defense):
		return -1
	var service: Node = _actor.defense.last_stand
	return service.church_bell_visual_frame(_actor, BELL_FRAMES) if is_instance_valid(service) else -1


func _show_sermon(delta: float) -> void:
	var step := int(_sermon_time / SERMON_FRAME_SECONDS) % (SERMON_VARIANTS * SERMON_FRAMES)
	_show_frame(step % SERMON_FRAMES, SERMON_ROW + step / SERMON_FRAMES, _is_west())
	_sermon_time += delta


func _show_turn(breath := 1.0) -> void:
	_show_frame(_direction % 8, _direction >> 3, false, breath)


func _show_frame(column: int, row: int, mirrored := false, breath := 1.0) -> void:
	var frame := Rect2(Vector2(column, row) * CELL, CELL)
	if frame != region_rect:
		region_rect = frame
	# Escort frames are authored for each side. Mirroring would swap the equipment hands.
	flip_h = mirrored and not is_escort
	scale = Vector2(1.0 / sqrt(breath), breath) * (HUMAN_VISUAL.WORLD_HEIGHT / HUMAN_VISUAL.FRAME_HEIGHT)
