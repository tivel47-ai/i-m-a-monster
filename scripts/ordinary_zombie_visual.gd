extends Sprite2D

const ART = preload("res://assets/sprites/characters/ordinary_zombie/frames.gd")
# Match the peasant's pixels-to-world ratio. The slouched stance is 4 px shorter.
const PIXEL_SCALE := 25.2 / 100.0
const FEET_Y := 5.5
const HEALTH_BAR_Y := FEET_Y - ART.STANDING_HEIGHT * PIXEL_SCALE - 7.0
const DIRECTION_STEP := TAU / 8.0
const TURN_HYSTERESIS := deg_to_rad(3.0)
const TURN_STEP_TIME := 0.045
const MOVE_THRESHOLD := 4.0
const HURT_TIME := 0.30
const DEATH_TIME := 0.80

var appearance := 0

var _actor: CharacterBody2D
var _timer: Timer
var _last_position: Vector2
var _direction := 1 # S, SE, E, NE, N, NW, W, SW
var _desired_direction := 1
var _turn_time := 0.0
var _moving := false
var _stride := 0.0
var _idle_time := 0.0
var _next_attack := 0
var _death_row: int = ART.Clip.DEATH_FORWARD
var _clip_row := -1
var _clip_first := 0
var _clip_time := 0.0
var _clip_duration := 0.0


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	var variation := RandomNumberGenerator.new()
	variation.seed = _actor.get_instance_id()
	_next_attack = variation.randi_range(0, ART.WINDUP_TIMES.size() - 1)
	_death_row = ART.Clip.DEATH_FORWARD + variation.randi_range(0, 1)
	_setup_sprite()
	_show_turn()


func _setup_sprite() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y
	offset = -ART.ANCHOR
	scale = Vector2.ONE * PIXEL_SCALE


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	var opponent := _actor.get("aggro_target") as Node2D
	var windup := _windup_progress(opponent)
	if _clip_row == ART.Clip.HURT and windup >= 0.0:
		_clip_row = -1
	if _clip_row >= 0 and _advance_clip(delta):
		return

	var distance := displacement.length()
	var speed := distance / delta
	var moving := speed >= MOVE_THRESHOLD and distance < ART.STANDING_HEIGHT * PIXEL_SCALE
	var base_speed := float(_actor.get("move_speed"))
	var rushing := moving and speed >= base_speed * 0.80 and (
		is_instance_valid(opponent) or speed > base_speed * 1.08)
	if moving != _moving:
		_moving = moving
		_idle_time = 0.0
		if moving:
			_stride = 0.0
	if moving:
		var cycle_distance := ART.RUSH_DISTANCE if rushing else ART.WALK_DISTANCE
		_stride = fposmod(_stride + distance / cycle_distance, 1.0)

	if is_instance_valid(opponent) and (windup >= 0.0 or not moving):
		_aim(opponent.global_position - _actor.global_position)
	elif moving:
		_aim(displacement)
	if _advance_turn(delta):
		_show_turn()
	elif windup >= 0.0:
		_show_cycle(ART.Clip.SWIPE + _next_attack, mini(int(windup * ART.CONTACT_FRAME), ART.CONTACT_FRAME - 1))
	elif moving:
		var frame := int(_stride * ART.FRAME_COUNT) if rushing else ART.walk_frame(_stride)
		_show_cycle(ART.Clip.RUSH if rushing else ART.Clip.WALK, frame)
	else:
		_idle_time += delta
		_show_idle()


func play_attack(direction: Vector2, interval: float) -> void:
	if _clip_row >= ART.Clip.DEATH_FORWARD:
		return
	_aim(direction, false)
	_direction = _desired_direction
	_turn_time = 0.0
	_start_clip(ART.Clip.SWIPE + _next_attack, ART.CONTACT_FRAME, minf(0.33, interval * 0.44))
	_next_attack = (_next_attack + 1) % ART.WINDUP_TIMES.size()


func play_hurt() -> void:
	if _clip_row < 0 and _windup_progress(_actor.get("aggro_target")) < 0.0:
		_start_clip(ART.Clip.HURT, 0, HURT_TIME)


func play_death() -> void:
	_start_clip(_death_row, 0, DEATH_TIME)


func _windup_progress(opponent: Variant) -> float:
	if not is_instance_valid(opponent) or _timer.is_stopped():
		return -1.0
	var windup := minf(float(ART.WINDUP_TIMES[_next_attack]), _timer.wait_time * 0.46)
	return 1.0 - _timer.time_left / windup


func _start_clip(row: int, first: int, duration: float) -> void:
	_clip_row = row
	_clip_first = first
	_clip_time = 0.0
	_clip_duration = duration
	_idle_time = 0.0
	_show_cycle(row, first)


func _advance_clip(delta: float) -> bool:
	_clip_time += delta
	if _clip_time < _clip_duration:
		var frame := _clip_first + int(_clip_time / _clip_duration * (ART.FRAME_COUNT - _clip_first))
		_show_cycle(_clip_row, frame)
		return true
	if _clip_row >= ART.Clip.DEATH_FORWARD:
		_show_cycle(_clip_row, ART.FRAME_COUNT - 1)
		set_physics_process(false)
		return true
	_clip_row = -1
	return false


func _aim(direction: Vector2, use_hysteresis := true) -> void:
	if direction.is_zero_approx():
		return
	var angle := PI / 2.0 - direction.angle()
	if not use_hysteresis or absf(angle_difference(_desired_direction * DIRECTION_STEP, angle)) > DIRECTION_STEP * 0.5 + TURN_HYSTERESIS:
		_desired_direction = posmod(roundi(angle / DIRECTION_STEP), 8)


func _advance_turn(delta: float) -> bool:
	if _direction == _desired_direction:
		_turn_time = 0.0
		return false
	_turn_time += delta
	if _turn_time >= TURN_STEP_TIME:
		_turn_time -= TURN_STEP_TIME
		var distance := posmod(_desired_direction - _direction, 8)
		_direction = posmod(_direction + (1 if distance <= 4 else -1), 8)
	return true


func _show_idle() -> void:
	if _direction % 2 == 0:
		_show_turn()
		scale.y = PIXEL_SCALE * (1.0 + sin(_idle_time * TAU / ART.IDLE_TIME) * 0.015)
	else:
		var phase := fposmod(_idle_time / ART.IDLE_TIME, 1.0)
		_show_cycle(ART.Clip.IDLE, int(phase * ART.FRAME_COUNT))


func _show_turn() -> void:
	_display(ART.TURN[appearance], _direction, 0, false)


func _show_cycle(row: int, frame: int) -> void:
	var sector := _direction >> 1
	var views: Array = ART.VIEWS[appearance]
	var mirror := views.size() == 2 and sector >= 2
	var view := 3 - sector if mirror else sector
	_display(views[view], frame, row, mirror, view)


func _display(sheet: Texture2D, column: int, row: int, mirror: bool, view := -1) -> void:
	var region := Rect2(Vector2(column, row) * ART.CELL, ART.CELL)
	if scale.y != PIXEL_SCALE:
		scale.y = PIXEL_SCALE
	if texture == sheet and region_rect == region and flip_h == mirror:
		return
	if texture != sheet:
		texture = sheet
		self_modulate = ART.VIEW_TINTS[appearance][view] if view >= 0 and ART.VIEW_TINTS.has(appearance) else Color.WHITE
	region_rect = region
	flip_h = mirror
