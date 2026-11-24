extends Sprite2D

signal death_finished

const ART = preload("res://assets/sprites/characters/brute/frames.gd")
const WORLD_HEIGHT := 33.6
const FEET_Y := 5.5
# Account for the raised fist in the overhead attack.
const HEALTH_BAR_Y := FEET_Y - WORLD_HEIGHT * 1.12 - 4.0
const TURN_STEP_TIME := 0.035
const TURN_ANGLE := TAU / 16.0
const TURN_HYSTERESIS := PI / 90.0
const MOVE_THRESHOLD := 4.0
const STRIDE_DISTANCE := 60.0
const WINDUP_TIMES := [0.46, 0.41, 0.52]
const HURT_CHANCE := 0.5

enum Phase { FREE, ATTACK, HURT, DEATH }

var _actor: Node2D
var _timer: Timer
var _last_position: Vector2
var _direction := 2
var _desired_direction := 2
var _turn_time := 0.0
var _moving := false
var _walk_phase := 0.0
var _idle_time := 0.0
var _next_attack := 0
var _death_variant := 0
var _variation := RandomNumberGenerator.new()
var _phase := Phase.FREE
var _clip: Array
var _clip_sector := 0
var _clip_frame_start := 0
var _clip_time := 0.0
var _clip_duration := 0.0


func _ready() -> void:
	_actor = get_parent() as Node2D
	_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	_variation.seed = _actor.get_instance_id()
	_next_attack = _variation.randi_range(0, WINDUP_TIMES.size() - 1)
	_death_variant = _variation.randi_range(0, 1)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y
	offset = -Vector2(ART.ANCHOR)
	_show_turn()


func _physics_process(delta: float) -> void:
	var motion := _actor.global_position - _last_position
	_last_position = _actor.global_position
	var opponent = _actor.get("aggro_target")
	var windup := _windup_progress(opponent)
	if _phase == Phase.HURT and windup >= 0.0:
		_phase = Phase.FREE
	if _phase != Phase.FREE:
		_clip_time += delta
		if _clip_time < _clip_duration:
			_show_active_clip()
			return
		if _phase == Phase.DEATH:
			_show(_clip_sector, _clip[-1])
			set_physics_process(false)
			death_finished.emit()
			return
		_phase = Phase.FREE

	var moving := motion.length() >= MOVE_THRESHOLD * delta
	if moving != _moving:
		_moving = moving
		_walk_phase = 0.0
		_idle_time = 0.0

	var fighting := is_instance_valid(opponent) and not _timer.is_stopped()
	if moving:
		_walk_phase = fposmod(_walk_phase + motion.length() / STRIDE_DISTANCE, 1.0)
	if fighting and (windup >= 0.0 or not moving):
		_aim(opponent.global_position - _actor.global_position)
	elif moving:
		_aim(motion)
	if _advance_turn(delta):
		_show_turn()
		return

	var sector := _sector()
	if windup >= 0.0:
		var attack: Array = ART.VIEWS[sector].attacks[_next_attack]
		var contact: int = ART.VIEWS[sector].contacts[_next_attack]
		_show(sector, attack[clampi(int(windup * contact), 0, contact - 1)])
		return
	if moving:
		var steps: Array = ART.VIEWS[sector].walk
		var weight_shift := 1.0 - 0.022 * (0.5 + 0.5 * cos(_walk_phase * TAU * 2.0))
		_show(sector, steps[int(_walk_phase * steps.size())], weight_shift)
		return
	_idle_time += delta
	_show_idle()


func vision_direction() -> int:
	return posmod(_direction + 1, 16) >> 1


func play_attack(direction: Vector2, interval: float) -> void:
	if _phase == Phase.DEATH:
		return
	_aim(direction, false)
	_direction = _desired_direction
	_turn_time = 0.0
	var sector := _sector()
	var view: Dictionary = ART.VIEWS[sector]
	_start_clip(Phase.ATTACK, sector, view.attacks[_next_attack], view.contacts[_next_attack],
		minf(0.43, interval * 0.46))
	_next_attack = (_next_attack + 1) % WINDUP_TIMES.size()


func play_hurt() -> void:
	if _phase != Phase.FREE or _windup_progress(_actor.get("aggro_target")) >= 0.0:
		return
	if _variation.randf() < HURT_CHANCE:
		var sector := _sector()
		_start_clip(Phase.HURT, sector, ART.VIEWS[sector].hurt, 0, 0.32)


func play_death() -> void:
	var sector := _sector()
	_start_clip(Phase.DEATH, sector, ART.VIEWS[sector].deaths[_death_variant], 0, 0.94)


func _windup_progress(opponent: Variant) -> float:
	if not is_instance_valid(opponent) or _timer.is_stopped():
		return -1.0
	var duration := minf(WINDUP_TIMES[_next_attack], _timer.wait_time * 0.46)
	return 1.0 - _timer.time_left / duration


func _start_clip(phase: Phase, sector: int, frames: Array, first: int, duration: float) -> void:
	_phase = phase
	_clip = frames
	_clip_sector = sector
	_clip_frame_start = first
	_clip_duration = duration
	_clip_time = 0.0
	_idle_time = 0.0
	_show_active_clip()


func _show_active_clip() -> void:
	var frame := _clip_frame_start + int(_clip_time / _clip_duration * (_clip.size() - _clip_frame_start))
	_show(_clip_sector, _clip[mini(frame, _clip.size() - 1)])


func _aim(direction: Vector2, use_hysteresis := true) -> void:
	if direction.is_zero_approx():
		return
	var angle := PI / 2.0 - direction.angle()
	if not use_hysteresis or absf(angle_difference(_desired_direction * TURN_ANGLE, angle)) > TURN_ANGLE * 0.5 + TURN_HYSTERESIS:
		_desired_direction = posmod(roundi(angle / TURN_ANGLE), 16)


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


func _sector() -> int:
	# The turntable has 16 orientations. Action atlases cover the four quarters.
	return _direction >> 2


func _show_idle() -> void:
	if _direction != 2:
		# Keep the exact facing when breathing in a direction without a drawn idle cycle.
		_show_turn(1.0 + sin(_idle_time * TAU / 1.8) * 0.018)
		return
	var breathing: Array = ART.IDLE_BREATHING
	var glance: Array = ART.IDLE_GLANCE
	var breath_duration := breathing.size() * 0.18
	var glance_duration := glance.size() * 0.16
	var elapsed := fposmod(_idle_time, breath_duration * 3.0 + glance_duration)
	if elapsed < breath_duration * 3.0:
		_show(0, breathing[int(elapsed / 0.18) % breathing.size()])
	else:
		_show(0, glance[mini(int((elapsed - breath_duration * 3.0) / 0.16), glance.size() - 1)])


func _show_turn(breath := 1.0) -> void:
	_show(0, _direction, breath)


func _show(sector: int, frame: int, breath := 1.0) -> void:
	var atlas: Texture2D = ART.VIEWS[sector].texture
	var cell := Vector2(frame % ART.COLUMNS, floori(float(frame) / ART.COLUMNS))
	var region := Rect2(cell * Vector2(ART.CELL), Vector2(ART.CELL))
	var pixels_to_world := WORLD_HEIGHT / ART.STANDING_HEIGHT
	if texture != atlas or region_rect != region:
		texture = atlas
		region_rect = region
	scale = Vector2(1.0 / sqrt(breath), breath) * pixels_to_world
