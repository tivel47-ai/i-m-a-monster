extends Sprite2D

signal death_finished

const HUMAN_VISUAL = preload("res://scripts/peasant_visual.gd")
const ATLAS = preload("res://assets/sprites/characters/guards/crossbow.png")
const CELL := Vector2(176, 128)
const ANCHOR := Vector2(88, 116)
const HEALTH_BAR_Y := HUMAN_VISUAL.HEALTH_BAR_Y - 2.0

# Five source views per directional clip (S, SE, E, NE, N).
# The turntable and ready stances have dedicated western poses.
const READY_ROW := 2
const IDLE_ROW := 3
const WALK_ROW := 8
const RUN_ROW := 13
const SHOT_ROW := 18
const RELOAD_ROW := 23
const PUSH_ROW := 28
const SWEEP_ROW := 33
const HURT_ROW := 38
const FALL_FORWARD_ROW := 43
const FALL_BACK_ROW := 48
const BELL_ROW := 53
const ACTION_FRAMES := 6
const CONTACT_FRAME := 3
const SHOT_FRAME_TIME := 0.08
const RELOAD_DELAY := (ACTION_FRAMES - CONTACT_FRAME) * SHOT_FRAME_TIME
const AIM_HOLD := 0.30
const RETREAT_STRIDE := 29.0
const TURN_STEP := TAU / 16.0
const BOLT_ORIGINS := [
	Vector2(88, 52), Vector2(130, 45), Vector2(127, 44), Vector2(110, 29), Vector2(88, 39),
]

enum Motion { IDLE, WALK, RUN, RETREAT }
enum Clip { NONE, SHOT, MELEE, HURT, DEATH }

var _actor: Node2D
var _melee_timer: Timer
var _last_position: Vector2
var _direction := 2 # Sixteen indices, starting south and advancing via east.
var _turn_time := 0.0
var _motion := Motion.IDLE
var _stride := 0.0
var _idle_time := 0.0
var _aim_time := 0.0
var _reload_started_at := -INF
var _next_melee_row := PUSH_ROW
var _death_row := FALL_FORWARD_ROW
var _clip := Clip.NONE
var _clip_row := 0
var _clip_first := 0
var _clip_frame_time := 0.0
var _clip_elapsed := 0.0


func _ready() -> void:
	_actor = get_parent() as Node2D
	_melee_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	if hash(_actor.get_instance_id()) & 1:
		_death_row = FALL_BACK_ROW
	texture = ATLAS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = HUMAN_VISUAL.FEET_Y
	scale = Vector2.ONE * (HUMAN_VISUAL.WORLD_HEIGHT / HUMAN_VISUAL.FRAME_HEIGHT)
	offset = -ANCHOR
	_show_directional(0, IDLE_ROW)


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	_aim_time = maxf(0.0, _aim_time - delta)
	if _clip == Clip.DEATH:
		_advance_clip(delta)
		return

	var distance := displacement.length()
	var motion := _movement(distance, delta)
	if motion != _motion:
		_motion = motion
		_stride = 0.0
		_idle_time = 0.0
	if motion != Motion.IDLE:
		_clip = Clip.NONE
		_direction = _direction_for(displacement.angle())
		_turn_time = 0.0
		_show_movement(distance)
		return

	var windup_frame := _windup_frame()
	if _clip == Clip.HURT and windup_frame >= 0:
		_clip = Clip.NONE
	if _clip != Clip.NONE and _advance_clip(delta):
		return
	if windup_frame >= 0:
		_show_directional(windup_frame, _next_melee_row)
		return
	if _show_turn(delta):
		return
	if _show_reload():
		return
	if _aim_time > 0.0:
		_show_frame(_direction >> 1, READY_ROW)
		return

	_idle_time += delta
	_show_directional(int(_idle_time * 4.0) % 4, IDLE_ROW)


func hold_aim() -> void:
	_aim_time = AIM_HOLD


func play_shot(heading: Vector2, now: float) -> void:
	_set_heading(heading)
	_reload_started_at = now
	_start_clip(Clip.SHOT, SHOT_ROW, CONTACT_FRAME, SHOT_FRAME_TIME)


func bolt_display_offset() -> Vector2:
	var view := _direction >> 1
	var local_offset: Vector2 = BOLT_ORIGINS[8 - view if flip_h else view] - ANCHOR
	if flip_h:
		local_offset.x = -local_offset.x
	return position + local_offset * scale


func play_impact(heading: Vector2, interval: float) -> void:
	_set_heading(heading)
	_start_clip(Clip.MELEE, _next_melee_row, CONTACT_FRAME, _melee_frame_time(interval))
	_next_melee_row = SWEEP_ROW if _next_melee_row == PUSH_ROW else PUSH_ROW


func play_hurt() -> void:
	if _clip == Clip.NONE and _motion == Motion.IDLE:
		_start_clip(Clip.HURT, HURT_ROW, 0, 0.07)


func play_death() -> void:
	_direction = ((_direction + 1) % 16) & ~1
	_start_clip(Clip.DEATH, _death_row, 0, 0.10)


func _movement(distance: float, delta: float) -> Motion:
	if distance < HUMAN_VISUAL.MOVE_THRESHOLD * delta or distance >= HUMAN_VISUAL.WORLD_HEIGHT:
		return Motion.IDLE
	if _actor.guard_ai != null and _actor.guard_ai.crossbow != null and _actor.guard_ai.crossbow.goal.is_finite():
		return Motion.RETREAT
	return Motion.RUN if distance / delta > _actor.move_speed * 1.35 else Motion.WALK


func _show_movement(distance: float) -> void:
	var walking := _motion == Motion.WALK
	var cycle_distance := 25.0 if walking else HUMAN_VISUAL.RUN_CYCLE_DISTANCE
	if _motion == Motion.RETREAT:
		cycle_distance = RETREAT_STRIDE
	_stride = fposmod(_stride + distance / cycle_distance, 1.0)
	_show_directional(int(_stride * (8 if walking else 10)), WALK_ROW if walking else RUN_ROW)


func _windup_frame() -> int:
	if _melee_timer.is_stopped():
		return -1
	var frame_time := _melee_frame_time(_melee_timer.wait_time)
	if _melee_timer.time_left > frame_time * CONTACT_FRAME:
		return -1
	var target: Node2D = _actor._encounter_attack_target()
	if target == null:
		return -1
	_set_heading(target.global_position - _actor.global_position)
	return clampi(CONTACT_FRAME - ceili(_melee_timer.time_left / frame_time), 0, CONTACT_FRAME - 1)


func _melee_frame_time(interval: float) -> float:
	return minf(0.10, interval / ACTION_FRAMES)


func _start_clip(clip: Clip, row: int, first: int, frame_time: float) -> void:
	_clip = clip
	_clip_row = row
	_clip_first = first
	_clip_frame_time = frame_time
	_clip_elapsed = 0.0
	_show_directional(first, row)


func _advance_clip(delta: float) -> bool:
	_clip_elapsed += delta
	var frame := _clip_first + int(_clip_elapsed / _clip_frame_time)
	if frame < ACTION_FRAMES:
		_show_directional(frame, _clip_row)
		return true
	if _clip == Clip.DEATH:
		_show_directional(ACTION_FRAMES - 1, _clip_row)
		set_physics_process(false)
		death_finished.emit()
		return true
	_clip = Clip.NONE
	return false


func _show_reload() -> bool:
	if not is_instance_valid(_actor.defense) or _reload_started_at == -INF:
		return false
	var start := _reload_started_at + RELOAD_DELAY
	var end := lerpf(start, _actor.ranged_ready_at, 0.88)
	var now: float = _actor.defense.elapsed
	if now >= end:
		return false
	var fraction := clampf((now - start) / maxf(end - start, 0.01), 0.0, 1.0)
	_show_directional(mini(int(fraction * ACTION_FRAMES), ACTION_FRAMES - 1), RELOAD_ROW)
	return true


func _show_turn(delta: float) -> bool:
	if _actor.unit_vision == null:
		return false
	var desired := _direction_for(_actor.unit_vision.facing_angle())
	if desired == _direction:
		_turn_time = 0.0
		return false
	_turn_time += delta
	if _turn_time >= HUMAN_VISUAL.TURN_STEP_TIME:
		var difference := posmod(desired - _direction + 8, 16) - 8
		_direction = posmod(_direction + signi(difference), 16)
		_turn_time -= HUMAN_VISUAL.TURN_STEP_TIME
	_show_frame(_direction % 8, _direction >> 3)
	return true


func _set_heading(heading: Vector2) -> void:
	if not heading.is_zero_approx():
		_direction = _direction_for(heading.angle())
		_turn_time = 0.0


func _direction_for(angle: float) -> int:
	return posmod(roundi((PI / 2.0 - angle) / (2.0 * TURN_STEP)), 8) * 2


func _show_directional(column: int, first_row: int) -> void:
	var view := _direction >> 1
	var mirrored := view > 4
	_show_frame(column, first_row + (8 - view if mirrored else view), mirrored)


func _show_frame(column: int, row: int, mirrored := false) -> void:
	flip_h = mirrored
	region_rect = Rect2(Vector2(column, row) * CELL, CELL)
