extends StaticBody2D
## The square's single physical rope. AI still decides when to attempt an alarm.

const GUARD_POSES := preload("res://assets/sprites/characters/bell_pull/guards.png")
const CIVILIAN_POSES := preload("res://assets/sprites/characters/bell_pull/civilians.png")
const HUMAN_VISUAL := preload("res://scripts/peasant_visual.gd")
const CELL := Vector2(128, 160)
const FEET := Vector2(72, 136)
const POSE_SCALE := HUMAN_VISUAL.WORLD_HEIGHT / HUMAN_VISUAL.FRAME_HEIGHT
const GUARD_ROLES := [&"shield", &"sword", &"spear"]
const CIVILIAN_ROLES := [&"peasant", &"artisan", &"priest"]
# Grip, middle pull and full pull, in the baked atlas cells.
const GUARD_HANDS := [
	[Vector2(49.2, 40.0), Vector2(53.0, 67.8), Vector2(64.3, 86.1)],
	[Vector2(48.1, 40.3), Vector2(52.5, 66.7), Vector2(64.1, 87.0)],
	[Vector2(49.1, 38.8), Vector2(51.7, 66.5), Vector2(62.5, 86.4)],
]
const CIVILIAN_HANDS := [
	[Vector2(52.6, 42.5), Vector2(56.2, 65.3), Vector2(60.4, 88.1)],
	[Vector2(53.6, 41.9), Vector2(56.2, 65.3), Vector2(58.8, 87.9)],
	[Vector2(52.9, 40.9), Vector2(56.2, 65.7), Vector2(58.8, 88.9)],
]
const APPROACH := Vector2(27, 24)
const PATH_ENTRY := Vector2(30, 40)
const APPROACH_SPEED := 32.0
const PEAK_ANGLE := deg_to_rad(19.0)
const RELEASE_SECONDS := 0.24
const SILENT_SWING_SECONDS := 1.55
const SWING_PERIOD := 1.25
const SWING_FADE_SECONDS := 1.5
const AXLE_LEFT := Vector2(-7.0, -13.1)
const AXLE_RIGHT := Vector2(8.0, -15.1)
const LEVER_JOINT := Vector2(11.0, -14.8)
const LEVER_LENGTH := 11.0
const REST_ROPE_END := Vector2(21.0, 6.0)

var _puller: Node2D
var _pull_frame := -1
var _elapsed := 0.0
var _swing_age := -1.0
var _ringing_audio: AudioStreamPlayer
var _angle := 0.0
var _rope_end := REST_ROPE_END
var _rope_bend := 0.0

@onready var _bell: Node2D = $Swing
@onready var _clapper: Node2D = $Swing/Clapper
@onready var _hardware: Node2D = $Hardware


func _ready() -> void:
	# A missed request means the villager's AI chose something else this frame.
	process_physics_priority = 10
	_hardware.draw.connect(_draw_hardware)
	_clapper.draw.connect(_draw_clapper)


func approach_position() -> Vector2:
	return to_global(APPROACH)


func navigation_entry() -> Vector2:
	return to_global(PATH_ENTRY)


func on_final_approach(actor: Node2D) -> bool:
	var position_on_path := Geometry2D.get_closest_point_to_segment(
		actor.global_position, navigation_entry(), approach_position())
	return actor.global_position.distance_to(position_on_path) <= actor.arrival_tolerance


func step_to_rope(actor: CharacterBody2D, delta: float) -> int:
	# The baked mesh has clearance around the frame. Traverse the last few
	# units with the actual collision body from the edge of that clearance.
	actor._stop_movement()
	var motion := (approach_position() - actor.global_position).limit_length(APPROACH_SPEED * delta)
	if actor.move_and_collide(motion) != null:
		return actor.NavigationResult.FAILED
	return actor.NavigationResult.MOVING


func at_rope(actor: Node2D) -> bool:
	return actor.global_position.distance_to(approach_position()) <= actor.arrival_tolerance


func pull(actor: Node2D, delta: float, seconds: float) -> float:
	if _swing_age >= 0.0 or not _can_hold(actor) or (is_instance_valid(_puller) and _puller != actor):
		return 0.0
	var frame := Engine.get_physics_frames()
	if _pull_frame == frame: return _elapsed
	if not is_instance_valid(_puller):
		_puller = actor
		_elapsed = 0.0
	_pull_frame = frame
	_elapsed += delta
	var progress := clampf(_elapsed / maxf(seconds, delta), 0.0, 1.0)
	var pose := 0
	if progress >= 0.86:
		pose = 3
	elif progress >= 0.52:
		pose = 2
	elif progress >= 0.21:
		pose = 1
	var end := _show_pose(actor, pose)
	_move_mechanism(-PEAK_ANGLE * smoothstep(0.22, 1.0, progress), end)
	return _elapsed


func strike(actor: Node2D, audio: AudioStreamPlayer) -> void:
	if _puller != actor: _clear_puller()
	_swing_age = 0.0
	_ringing_audio = audio if is_instance_valid(audio) and audio.stream != null else null
	_move_mechanism(-PEAK_ANGLE, _show_pose(actor, 3) if _puller == actor else REST_ROPE_END)


func is_operating(actor: Node2D) -> bool:
	return _puller == actor and _swing_age >= 0.0 and _can_hold(actor)


func _physics_process(delta: float) -> void:
	if _swing_age >= 0.0:
		_swing_age += delta
		var swing_time := _swing_age
		var duration := SILENT_SWING_SECONDS
		if is_instance_valid(_ringing_audio):
			swing_time = _ringing_audio.get_playback_position()
			var stream := _ringing_audio.stream
			duration = stream.get_length() if _ringing_audio.playing and stream != null else 0.0
		var time_left := duration - swing_time
		if time_left <= 0.0:
			_clear_puller()
			_swing_age = -1.0
			_ringing_audio = null
			_move_mechanism(0.0, REST_ROPE_END)
		else:
			var decay := exp(-0.8 * swing_time / duration)
			var fade := smoothstep(0.0, minf(SWING_FADE_SECONDS, duration * 0.5), time_left)
			var phase := cos(TAU * swing_time / SWING_PERIOD)
			var angle := -PEAK_ANGLE * decay * fade * phase
			if is_instance_valid(_puller) and is_operating(_puller):
				if time_left > RELEASE_SECONDS:
					var pose := 1 + roundi((1.0 + phase) * fade)
					_move_mechanism(angle, _show_pose(_puller, pose))
					return
				_show_pose(_puller, 4)
			else:
				_clear_puller()
			var rebound := sin(TAU * 2.1 * _swing_age) * exp(-3.7 * _swing_age)
			var end := REST_ROPE_END.lerp(_rope_end, exp(-18.0 * delta))
			_move_mechanism(angle, end, 4.0 * rebound)
		return
	if _pull_frame == Engine.get_physics_frames() and _can_hold(_puller):
		return
	_clear_puller()
	if not is_zero_approx(_angle) or not _rope_end.is_equal_approx(REST_ROPE_END):
		var angle := move_toward(_angle, 0.0, delta * 2.4)
		_move_mechanism(angle, _rope_end.move_toward(REST_ROPE_END, delta * 58.0))


func _can_hold(actor: Node2D) -> bool:
	return (
		is_instance_valid(actor) and not actor.is_queued_for_deletion()
		and actor.autonomous_movement_enabled and actor.is_available_for_infection()
		and not is_instance_valid(actor.building_task) and not is_instance_valid(actor.interior_building)
		and at_rope(actor)
	)


func _clear_puller() -> void:
	if is_instance_valid(_puller): _puller.clear_bell_pose()
	_puller = null
	_pull_frame = -1
	_elapsed = 0.0


func _show_pose(actor: Node2D, pose: int) -> Vector2:
	var role: StringName = actor.bell_pose_role()
	var row := GUARD_ROLES.find(role)
	var atlas := GUARD_POSES
	var hands := GUARD_HANDS
	if row == -1:
		atlas = CIVILIAN_POSES
		hands = CIVILIAN_HANDS
		row = maxi(0, CIVILIAN_ROLES.find(role))
	var frame := Rect2(Vector2(pose, row) * CELL, CELL)
	actor.show_bell_pose(atlas, frame, FEET, global_position - actor.global_position)
	if pose == 0 or pose == 4: return REST_ROPE_END
	var hand: Vector2 = hands[row][pose - 1]
	var contact := (hand - FEET) * POSE_SCALE + Vector2(0.0, HUMAN_VISUAL.FEET_Y)
	return to_local(actor.to_global(contact))


func _move_mechanism(angle: float, end: Vector2, bend := 0.0) -> void:
	_angle = angle
	_rope_end = end
	_rope_bend = bend
	_bell.rotation = angle
	_clapper.rotation = -angle * 1.4
	_hardware.queue_redraw()


func _draw_hardware() -> void:
	var lever_end := LEVER_JOINT + Vector2(LEVER_LENGTH, -2.0).rotated(-_angle * 1.55)
	_hardware.draw_line(AXLE_LEFT, AXLE_RIGHT, Color("2c2620"), 2.45, true)
	_hardware.draw_line(AXLE_LEFT + Vector2.UP * 0.7, AXLE_RIGHT + Vector2.UP * 0.7, Color("676056"), 0.8, true)
	_hardware.draw_line(AXLE_RIGHT, lever_end, Color("2c2620"), 2.1, true)
	_hardware.draw_line(LEVER_JOINT + Vector2.UP * 0.5, lever_end + Vector2.UP * 0.5, Color("736358"), 0.7, true)
	var rope := PackedVector2Array()
	for i in 5:
		var fraction := float(i) / 4.0
		rope.append(lever_end.lerp(_rope_end, fraction) + Vector2(_rope_bend * sin(PI * fraction), 0.0))
	_hardware.draw_polyline(rope, Color("4a3727"), 1.5, true)
	_hardware.draw_polyline(rope, Color("9a805e"), 0.65, true)
	_hardware.draw_circle(_rope_end, 0.65, Color("6c5038"), true)
	_hardware.draw_circle(lever_end, 0.9, Color("6e5b46"), true)


func _draw_clapper() -> void:
	_clapper.draw_line(Vector2.ZERO, Vector2(0.0, 2.6), Color("382a1b"), 0.9, true)
	_clapper.draw_circle(Vector2(0.0, 2.6), 0.95, Color("61482c"), true)
	_clapper.draw_circle(Vector2(-0.25, 2.4), 0.4, Color("9d7849"), true)


func _draw() -> void:
	draw_set_transform(Vector2(0.0, 13.5), -0.14, Vector2(1.6, 0.5))
	for radius in [13.0, 11.0, 9.0]:
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.055, 0.035, 0.13), true)
	draw_set_transform(Vector2.ZERO)
