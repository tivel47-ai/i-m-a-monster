extends Sprite2D

signal death_finished

const CARRIER_SOUTH = preload("res://assets/sprites/characters/carrier/south.png")
const CARRIER_NORTH = preload("res://assets/sprites/characters/carrier/north.png")
const RUNNER_SOUTH = preload("res://assets/sprites/characters/runner/south.png")
const RUNNER_NORTH = preload("res://assets/sprites/characters/runner/north.png")
const RUNNER_IDLE = preload("res://scripts/runner_idle.gdshader")
const CELL := Vector2i(128, 112)
const COLUMNS := 10
const FEET_Y := 5.5
const ART_HEIGHT := 76.0
const CARRIER_HEIGHT := 27.0
const RUNNER_HEIGHT := 22.5
const TURN_STEP := TAU / 16.0
const TURN_TIME := 0.024
const TURN_HYSTERESIS := PI / 90.0
const HEADING_RESPONSE := 17.0
const START_MOVING_SPEED := 12.0
const STOP_MOVING_SPEED := 7.0
const CONTACT_FRAME := 4
const CONTACT_HOLD := 0.27
const POUNCE_LANDING_FRAME := 5
const POUNCE_LIFT := 11.0
const IDLE_FRAME_TIME := 0.16

enum Clip { FREE, BREATH, GLANCE, WALK, RUN, SWIPE, GRAB, SPECIAL, HURT, FALL_FORWARD, FALL_BACK, POUNCE }

# First cell and frame count. Turntable poses occupy cells 0 through 15.
const CLIPS := {
	Clip.BREATH: Vector2i(16, 8),
	Clip.GLANCE: Vector2i(24, 8),
	Clip.WALK: Vector2i(32, 16),
	Clip.RUN: Vector2i(48, 16),
	Clip.SWIPE: Vector2i(64, 8),
	Clip.GRAB: Vector2i(72, 8),
	Clip.SPECIAL: Vector2i(80, 8),
	Clip.HURT: Vector2i(88, 6),
	Clip.FALL_FORWARD: Vector2i(94, 8),
	Clip.FALL_BACK: Vector2i(102, 8),
	Clip.POUNCE: Vector2i(80, 8),
}

var is_runner := false
var _actor: Node2D
var _timer: Timer
var _south: Texture2D
var _north: Texture2D
var _idle_material: ShaderMaterial
var _direction := 2
var _desired_direction := 2
var _turn_elapsed := 0.0
var _previous_position: Vector2
var _idle_elapsed := 0.0
var _stride := 0.0
var _movement_heading := 0.0
var _locomotion := Clip.FREE
var _next_attack := Clip.SWIPE
var _death := Clip.FALL_FORWARD
var _clip := Clip.FREE
var _clip_first := 0
var _clip_elapsed := 0.0
var _clip_duration := 0.0


func _ready() -> void:
	_actor = get_parent() as Node2D
	_timer = _actor.get_node("EncounterAttackTimer")
	_previous_position = _actor.global_position
	_south = RUNNER_SOUTH if is_runner else CARRIER_SOUTH
	_north = RUNNER_NORTH if is_runner else CARRIER_NORTH
	var variation := _actor.get_instance_id()
	_next_attack += variation % _attack_count()
	_death += variation % 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if is_runner:
		_idle_material = ShaderMaterial.new()
		_idle_material.shader = RUNNER_IDLE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	region_enabled = true
	region_filter_clip_enabled = true
	offset.y = CELL.y * 0.5 - 92.0
	position.y = FEET_Y
	scale = Vector2.ONE * (body_height() / ART_HEIGHT)
	_show(_south, _direction)


func health_bar_y() -> float:
	return position.y - (RUNNER_HEIGHT + 14.0 if is_runner else CARRIER_HEIGHT + 11.0)


func body_height() -> float:
	return RUNNER_HEIGHT if is_runner else CARRIER_HEIGHT


func _physics_process(delta: float) -> void:
	var motion := _actor.global_position - _previous_position
	_previous_position = _actor.global_position
	if _clip == Clip.POUNCE:
		return
	var opponent = _actor.get("aggro_target")
	var windup := _windup_progress(opponent)
	if _clip == Clip.HURT and windup >= 0.0:
		_clip = Clip.FREE
	if _clip != Clip.FREE and _advance_clip(delta):
		return

	var distance := motion.length()
	var speed := distance / delta
	var was_moving := _locomotion != Clip.FREE
	var moving := speed >= (STOP_MOVING_SPEED if was_moving else START_MOVING_SPEED)
	var run_speed := 84.0 if _locomotion == Clip.RUN else 96.0
	var rushing := moving and (is_instance_valid(opponent) or (is_runner and speed >= run_speed))
	var movement_clip := (Clip.RUN if rushing else Clip.WALK) if moving else Clip.FREE
	if moving:
		if not was_moving and _idle_elapsed > 0.30:
			_stride = 0.0
		if was_moving:
			_movement_heading = lerp_angle(_movement_heading, motion.angle(), 1.0 - exp(-HEADING_RESPONSE * delta))
		else:
			_movement_heading = motion.angle()
		_idle_elapsed = 0.0
		var walk_distance := 58.0 if is_runner else 52.0
		var run_distance := 76.0 if is_runner else 60.0
		_stride = fposmod(_stride + distance / (run_distance if rushing else walk_distance), 1.0)
	_locomotion = movement_clip

	if windup >= 0.0:
		_face(opponent.global_position - _actor.global_position)
		_show_clip(_next_attack, mini(int(windup * CONTACT_FRAME), CONTACT_FRAME - 1))
	elif moving:
		_aim(Vector2.from_angle(_movement_heading))
		_direction = _desired_direction
		_turn_elapsed = 0.0
		_show_clip(movement_clip, int(_stride * CLIPS[movement_clip].y))
	else:
		if is_instance_valid(opponent):
			_aim(opponent.global_position - _actor.global_position)
		if _advance_turn(delta):
			_show(_south, _direction)
			return
		_idle_elapsed += delta
		_show_idle()


func vision_direction() -> int:
	return posmod(_direction + 1, 16) >> 1


func play_attack(direction: Vector2, interval: float) -> void:
	if _clip >= Clip.FALL_FORWARD:
		return
	_face(direction)
	_start_clip(_next_attack, CONTACT_FRAME, minf(0.46, interval * 0.46))
	_next_attack = Clip.SWIPE + (_next_attack - Clip.SWIPE + 1) % _attack_count()


func play_hurt() -> void:
	if _clip == Clip.FREE and _windup_progress(_actor.get("aggro_target")) < 0.0:
		_start_clip(Clip.HURT, 0, 0.42 if is_runner else 0.48)


func play_death() -> void:
	position.y = FEET_Y
	_start_clip(_death, 0, 1.05 if is_runner else 1.16)


func show_pounce(direction: Vector2, windup: float, flight: float) -> void:
	_face(direction)
	_clip = Clip.POUNCE
	position.y = FEET_Y - sin(flight * PI) * POUNCE_LIFT
	var frame := mini(int(windup * 2.0), 1)
	if flight > 0.0:
		frame = 2 + mini(int(flight * 3.0), 2)
	_show_clip(Clip.POUNCE, frame)


func finish_pounce(direction: Vector2) -> void:
	position.y = FEET_Y
	_face(direction)
	_start_clip(Clip.SPECIAL, POUNCE_LANDING_FRAME, 0.36)


func cancel_pounce() -> void:
	if _clip == Clip.POUNCE:
		position.y = FEET_Y
		_clip = Clip.FREE
		_show(_south, _direction)


func _attack_count() -> int:
	return 2 if is_runner else 3


func _windup_progress(opponent: Variant) -> float:
	if not is_instance_valid(opponent) or _timer.is_stopped():
		return -1.0
	var windup_time := 0.45 if is_runner else 0.51
	return 1.0 - _timer.time_left / minf(windup_time, _timer.wait_time * 0.48)


func _start_clip(clip: Clip, first: int, duration: float) -> void:
	_clip = clip
	_clip_first = first
	_clip_elapsed = 0.0
	_clip_duration = duration
	_idle_elapsed = 0.0
	_show_clip(clip, first)


func _advance_clip(delta: float) -> bool:
	_clip_elapsed += delta
	var last: int = CLIPS[_clip].y - 1
	if _clip_elapsed < _clip_duration:
		var progress := _clip_elapsed / _clip_duration
		var frame := _clip_first + int(progress * (last + 1 - _clip_first))
		if _clip in [Clip.SWIPE, Clip.GRAB, Clip.SPECIAL]:
			frame = _clip_first
			if progress >= CONTACT_HOLD:
				var recovery := inverse_lerp(CONTACT_HOLD, 1.0, progress)
				frame += 1 + int(recovery * (last - _clip_first))
		_show_clip(_clip, mini(frame, last))
		return true
	if _clip in [Clip.FALL_FORWARD, Clip.FALL_BACK]:
		_show_clip(_clip, last)
		set_physics_process(false)
		death_finished.emit()
		return true
	_clip = Clip.FREE
	return false


func _face(direction: Vector2) -> void:
	_aim(direction, false)
	_direction = _desired_direction
	_turn_elapsed = 0.0


func _aim(direction: Vector2, hysteresis := true) -> void:
	if direction.is_zero_approx():
		return
	var angle := PI / 2.0 - direction.angle()
	if not hysteresis or absf(angle_difference(_desired_direction * TURN_STEP, angle)) > TURN_STEP * 0.5 + TURN_HYSTERESIS:
		_desired_direction = posmod(roundi(angle / TURN_STEP), 16)


func _advance_turn(delta: float) -> bool:
	if _direction == _desired_direction:
		_turn_elapsed = 0.0
		return false
	_turn_elapsed += delta
	if _turn_elapsed >= TURN_TIME:
		_turn_elapsed -= TURN_TIME
		var distance := posmod(_desired_direction - _direction, 16)
		_direction = posmod(_direction + (1 if distance <= 8 else -1), 16)
	return true


func _show_idle() -> void:
	var phase := fposmod(_idle_elapsed / IDLE_FRAME_TIME, 32.0)
	if is_runner:
		var breath := 0.5 - 0.5 * cos(phase * TAU / 8.0)
		var glance := sin(PI * clampf((phase - 24.0) / 8.0, 0.0, 1.0))
		var facing := -1.0 if _direction >= 8 else 1.0
		var motion := Vector2(facing * (0.8 * breath + 3.6 * glance), -2.2 * breath)
		_show(_south, _direction, false, _idle_material)
		_idle_material.set_shader_parameter("idle_motion", motion)
		return
	var frame := int(phase)
	if _direction % 4 != 2:
		_show(_south, _direction)
		return
	_show_clip(Clip.GLANCE if frame >= 24 else Clip.BREATH, frame % 8)


func _show_clip(clip: Clip, frame: int) -> void:
	var sector := _direction >> 2
	var atlas := _south if sector == 0 or sector == 3 else _north
	_show(atlas, CLIPS[clip].x + frame, sector >= 2)


func _show(atlas: Texture2D, frame: int, mirror := false, frame_material: Material = null) -> void:
	var cell := Vector2i(frame % COLUMNS, frame / COLUMNS)
	material = frame_material
	texture = atlas
	region_rect = Rect2(Vector2(cell * CELL), Vector2(CELL))
	flip_h = mirror
