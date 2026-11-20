extends Sprite2D

const ATLAS = preload("res://assets/sprites/characters/peasant/frames.png")
const CELL := Vector2(160, 128)
const ANCHOR := Vector2(80, 116)
const FRAME_HEIGHT := 100.0
const WORLD_HEIGHT := 25.2
const FEET_Y := 5.5
const HEALTH_BAR_Y := FEET_Y - WORLD_HEIGHT - 5.0
const COMBAT_HEALTH_BAR_Y := HEALTH_BAR_Y - 2.0
const TURN_STEP := TAU / 16.0
const TURN_HYSTERESIS := deg_to_rad(2.0)
const TURN_STEP_TIME := 0.035
const MOVE_THRESHOLD := 4.0
const WALK_CYCLE_DISTANCE := 36.0
const RUN_CYCLE_DISTANCE := 34.0
const WALK_FRAMES := 12
const RUN_FRAMES := 10
const IDLE_FRAMES := 8
const IDLE_FRAME_TIME := 0.20
# Two turn rows, two idle rows, five pairs of walk/run rows, then the combat views.
const IDLE_ROW := 2
const MOVEMENT_ROW := 4
const ACTION_ROW := 14
const ACTION_ROWS_PER_VIEW := 6
const ATTACK_COUNT := 3
const CONTACT_FRAME := 4
const ACTION_FRAMES := 8
const HURT_FRAMES := 6
const HURT_ROW := 3
const DEATH_ROW := 4
const WINDUP_TIMES := [0.34, 0.46, 0.40]

enum Motion { IDLE, WALK, RUN }
enum Clip { NONE, ATTACK, HURT, DEATH }

var _actor: CharacterBody2D
var _reaction: Node
var _timer: Timer
var _last_position: Vector2
var _direction := 2 # S, SSE, SE, ... around the turntable
var _desired_direction := 2
var _turn_time := 0.0
var _motion := Motion.IDLE
var _stride := 0.0
var _idle_time := 0.0
var _next_attack := 0
var _death_variant := 0
var _clip := Clip.NONE
var _clip_row := 0
var _clip_mirrored := false
var _clip_first := 0
var _clip_frames := 0
var _clip_time := 0.0
var _clip_duration := 0.0


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	_reaction = _actor.get_node("ThreatReaction")
	_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	var variation := RandomNumberGenerator.new()
	variation.seed = _actor.get_instance_id()
	_next_attack = variation.randi_range(0, ATTACK_COUNT - 1)
	_death_variant = variation.randi_range(0, 1)
	texture = ATLAS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y
	offset = -ANCHOR
	_show_turn()


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	if _clip == Clip.DEATH:
		_advance_clip(delta)
		return

	var opponent := _actor.call("_encounter_attack_target") as Node2D if not _timer.is_stopped() else null
	var windup := _windup_progress(opponent)
	if _clip == Clip.HURT and windup >= 0.0:
		_clip = Clip.NONE
	if _clip != Clip.NONE and _advance_clip(delta):
		return

	var distance := displacement.length()
	var motion := Motion.IDLE
	if distance >= MOVE_THRESHOLD * delta and distance < WORLD_HEIGHT:
		motion = Motion.RUN if _is_running(distance / delta) else Motion.WALK
	if motion != _motion:
		_idle_time = 0.0
		if _motion == Motion.IDLE:
			_stride = 0.0
		_motion = motion

	if motion != Motion.IDLE:
		var cycle_distance := RUN_CYCLE_DISTANCE if motion == Motion.RUN else WALK_CYCLE_DISTANCE
		_stride = fposmod(_stride + distance / cycle_distance, 1.0)
	if opponent != null:
		_aim(opponent.global_position - _actor.global_position)
	elif motion != Motion.IDLE:
		_aim(displacement)
	if _advance_turn(delta):
		_show_turn()
	elif windup >= 0.0:
		var frame := clampi(int(windup * CONTACT_FRAME), 0, CONTACT_FRAME - 1)
		_show_pose(frame, _action_view_row() + _next_attack, _direction > 8)
	elif motion != Motion.IDLE:
		_show_locomotion()
	else:
		_idle_time += delta
		_show_idle()


func play_impact(direction: Vector2, interval: float) -> void:
	if _clip == Clip.DEATH:
		return
	_aim(direction, false)
	_direction = _desired_direction
	_turn_time = 0.0
	_start_clip(Clip.ATTACK, _next_attack, CONTACT_FRAME, ACTION_FRAMES, minf(0.36, interval * 0.44))
	_next_attack = (_next_attack + 1) % ATTACK_COUNT


func play_hurt() -> void:
	if _clip != Clip.NONE:
		return
	var opponent := _actor.call("_encounter_attack_target") as Node2D if not _timer.is_stopped() else null
	if _windup_progress(opponent) < 0.0:
		_start_clip(Clip.HURT, HURT_ROW, 0, HURT_FRAMES, 0.30)


func play_death() -> void:
	_start_clip(Clip.DEATH, DEATH_ROW + _death_variant, 0, ACTION_FRAMES, 0.84)


func _start_clip(clip: Clip, row: int, first: int, frames: int, duration: float) -> void:
	_clip = clip
	_clip_row = _action_view_row() + row
	_clip_mirrored = _direction > 8
	_clip_first = first
	_clip_frames = frames
	_clip_time = 0.0
	_clip_duration = duration
	_idle_time = 0.0
	_show_pose(first, _clip_row, _clip_mirrored)


func _advance_clip(delta: float) -> bool:
	_clip_time += delta
	if _clip_time < _clip_duration:
		var frame := _clip_first + int(_clip_time / _clip_duration * (_clip_frames - _clip_first))
		_show_pose(frame, _clip_row, _clip_mirrored)
		return true
	if _clip == Clip.DEATH:
		_show_pose(_clip_frames - 1, _clip_row, _clip_mirrored)
		set_physics_process(false)
		return true
	_clip = Clip.NONE
	return false


func _windup_progress(opponent: Node2D) -> float:
	if opponent == null:
		return -1.0
	var duration := minf(WINDUP_TIMES[_next_attack], _timer.wait_time * 0.46)
	return 1.0 - _timer.time_left / duration


func _aim(direction: Vector2, use_hysteresis := true) -> void:
	if direction.is_zero_approx():
		return
	var angle := PI / 2.0 - direction.angle()
	if not use_hysteresis or absf(angle_difference(_desired_direction * TURN_STEP, angle)) > TURN_STEP * 0.5 + TURN_HYSTERESIS:
		_desired_direction = posmod(roundi(angle / TURN_STEP), 16)


func _advance_turn(delta: float) -> bool:
	if _direction == _desired_direction:
		_turn_time = 0.0
		return false
	_turn_time += delta
	if _turn_time >= TURN_STEP_TIME:
		_turn_time -= TURN_STEP_TIME
		var difference := posmod(_desired_direction - _direction, 16)
		_direction = posmod(_direction + (1 if difference <= 8 else -1), 16)
	return true


func _is_running(speed: float) -> bool:
	if _reaction.reaction_state in [_reaction.Reaction.FLEEING, _reaction.Reaction.SEEKING_SHELTER]:
		return true
	# Building traversal and escorts can move the actor without a personal flee route.
	return speed >= _reaction.fleeing_speed * 0.8


func _action_view_row() -> int:
	var rear := mini(_direction, 16 - _direction) > 4
	return ACTION_ROW + (ACTION_ROWS_PER_VIEW if rear else 0)


func _show_locomotion() -> void:
	var direction := posmod(_direction + 1, 16) >> 1
	var mirrored := direction > 4
	var view := 8 - direction if mirrored else direction
	var running := _motion == Motion.RUN
	var frame := int(_stride * (RUN_FRAMES if running else WALK_FRAMES))
	_show_pose(frame, MOVEMENT_ROW + view * 2 + int(running), mirrored)


func _show_idle() -> void:
	if _direction != 2 and _direction != 14:
		_show_turn(1.0 + sin(_idle_time * TAU / 1.8) * 0.012)
		return
	var step := int(_idle_time / IDLE_FRAME_TIME) % (IDLE_FRAMES * 4)
	var row := IDLE_ROW + int(step >= IDLE_FRAMES * 3)
	_show_pose(step % IDLE_FRAMES, row, _direction == 14)


func _show_turn(breath := 1.0) -> void:
	_show_pose(_direction % 8, _direction >> 3, false, breath)


func _show_pose(column: int, row: int, mirrored: bool, breath := 1.0) -> void:
	var frame := Rect2(Vector2(column, row) * CELL, CELL)
	if region_rect != frame:
		region_rect = frame
	if flip_h != mirrored:
		flip_h = mirrored
	scale = Vector2(1.0 / sqrt(breath), breath) * (WORLD_HEIGHT / FRAME_HEIGHT)
