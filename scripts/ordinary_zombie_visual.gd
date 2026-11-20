extends Sprite2D

const ART = preload("res://assets/sprites/characters/ordinary_zombie/frames.gd")
const WORLD_HEIGHT := 25.2
const FEET_Y := 5.5
const HEALTH_BAR_Y := FEET_Y - WORLD_HEIGHT - 5.0
const IDLE_FPS := 4.0
const WALK_FPS := 12.0
const DEATH_FPS := 10.0
const MAX_SWING_FRAME_TIME := 0.08
const IMPACT_FRAME := 3
const SWING_FRAMES := 6
const MOVE_THRESHOLD := 4.0

var _actor: Node2D
var _encounter_timer: Timer
var _last_position: Vector2
var _direction := 1 # S, SE, E, NE, N, NW, W, SW
var _moving := false
var _motion_time := 0.0
var _swing_time := -1.0
var _swing_frame_time := MAX_SWING_FRAME_TIME
var _death_time := -1.0


func _ready() -> void:
	_actor = get_parent() as Node2D
	_encounter_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	_setup_sprite()
	_display(ART.BASE, ART.TURN[_direction], ART.TURN_HEIGHT, false)


func _setup_sprite() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y


func _physics_process(delta: float) -> void:
	var motion := _actor.global_position - _last_position
	_last_position = _actor.global_position
	if _death_time >= 0.0:
		_death_time += delta
		var frame := mini(int(_death_time * DEATH_FPS), ART.DEATH.size() - 1)
		_display(ART.BASE, ART.DEATH[frame], ART.DEATH_HEIGHT, _direction > 4)
		if frame == ART.DEATH.size() - 1:
			set_physics_process(false)
		return
	if _swing_time >= 0.0:
		_swing_time += delta
		var frame := int(_swing_time / _swing_frame_time)
		if frame < SWING_FRAMES:
			_show_cycle(&"attack", frame)
			return
		_swing_time = -1.0

	var actual_speed := motion.length() / delta
	var moving := actual_speed >= MOVE_THRESHOLD
	if moving != _moving:
		_motion_time = 0.0
		_moving = moving
	if moving:
		_face(motion)
		_motion_time += delta * clampf(actual_speed / 100.0, 0.35, 1.65)
		_show_cycle(&"walk", int(_motion_time * WALK_FPS) % 8)
		return

	var opponent := _actor.get("aggro_target") as Node2D
	if is_instance_valid(opponent) and not _encounter_timer.is_stopped():
		_face(opponent.global_position - _actor.global_position)
		var frame_time := _frame_time(_encounter_timer.wait_time)
		var remaining := _encounter_timer.time_left
		if remaining <= frame_time * IMPACT_FRAME:
			var frame := clampi(IMPACT_FRAME - ceili(remaining / frame_time), 0, IMPACT_FRAME - 1)
			_show_cycle(&"attack", frame)
			return

	_motion_time += delta
	_show_cycle(&"idle", int(_motion_time * IDLE_FPS) % 4)


func play_attack(direction: Vector2, interval: float, at_impact: bool) -> void:
	if _death_time >= 0.0:
		return
	_face(direction)
	_swing_frame_time = _frame_time(interval)
	var frame := IMPACT_FRAME if at_impact else 0
	_swing_time = frame * _swing_frame_time
	_show_cycle(&"attack", frame)


func play_death() -> void:
	_death_time = 0.0
	_display(ART.BASE, ART.DEATH[0], ART.DEATH_HEIGHT, _direction > 4)


func _face(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		_direction = posmod(roundi((PI / 2.0 - direction.angle()) / (PI / 4.0)), 8)


func _frame_time(interval: float) -> float:
	return minf(MAX_SWING_FRAME_TIME, interval / SWING_FRAMES)


func _show_cycle(clip: StringName, frame: int) -> void:
	var mirrored := _direction > 4
	var cycle: Dictionary = ART.CYCLES[8 - _direction if mirrored else _direction]
	var pose: Array = cycle[clip][frame]
	_display(cycle.texture, pose, cycle.height, mirrored)


func _display(sheet: Texture2D, pose: Array, height: float, mirrored: bool) -> void:
	var region := Rect2(pose[0], pose[1], pose[2], pose[3])
	if texture == sheet and region_rect == region and flip_h == mirrored:
		return
	texture = sheet
	region_rect = region
	flip_h = mirrored
	var anchor_x: int = pose[2] - pose[4] if mirrored else pose[4]
	offset = Vector2(-anchor_x, -pose[5])
	scale = Vector2.ONE * (WORLD_HEIGHT / height)
