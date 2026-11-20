extends Sprite2D

const ATLAS = preload("res://assets/sprites/characters/peasant/frames.png")
const CELL_SIZE := Vector2(128, 128)
const FRAME_HEIGHT := 100.0
const FRAME_FEET_Y := 116.0
const WORLD_HEIGHT := 25.2
const FEET_Y := 5.5
const HEALTH_BAR_Y := FEET_Y - WORLD_HEIGHT - 5.0
const IDLE_FPS := 4.0
const WALK_CYCLE_DISTANCE := 40.0
const RUN_CYCLE_DISTANCE := 34.0
const MOVE_THRESHOLD := 4.0
const DIRECTION_CHANGE_ANGLE := deg_to_rad(27.5)

enum Motion { IDLE, WALK, RUN }

var _actor: CharacterBody2D
var _reaction: Node
var _last_position: Vector2
var _direction := 1 # S, SE, E, NE, N, NW, W, SW
var _motion := Motion.IDLE
var _phase := 0.0


func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	_reaction = _actor.get_node("ThreatReaction")
	_last_position = _actor.global_position
	texture = ATLAS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y
	scale = Vector2.ONE * (WORLD_HEIGHT / FRAME_HEIGHT)
	offset.y = CELL_SIZE.y * 0.5 - FRAME_FEET_Y
	_show_pose(0, 3 * _direction, false)


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	var distance := displacement.length()
	var speed := distance / delta
	var motion := Motion.IDLE
	if speed >= MOVE_THRESHOLD and distance < WORLD_HEIGHT:
		_update_direction(displacement)
		motion = Motion.RUN if _is_running(speed) else Motion.WALK

	if motion != _motion:
		_motion = motion
		_phase = 0.0

	var mirrored := _direction > 4
	var direction := 8 - _direction if mirrored else _direction
	var row := 3 * direction + _motion
	match _motion:
		Motion.IDLE:
			_phase = fposmod(_phase + delta * IDLE_FPS / 4.0, 1.0)
			_show_pose(int(_phase * 4.0), row, mirrored)
		Motion.WALK:
			_phase = fposmod(_phase + distance / WALK_CYCLE_DISTANCE, 1.0)
			_show_pose(int(_phase * 8.0), row, mirrored)
		Motion.RUN:
			_phase = fposmod(_phase + distance / RUN_CYCLE_DISTANCE, 1.0)
			_show_pose(int(_phase * 6.0), row, mirrored)


func _update_direction(displacement: Vector2) -> void:
	var heading := PI / 2.0 - displacement.angle()
	var facing := _direction * PI / 4.0
	# A small margin keeps root motion near a sector boundary from flipping the sprite back and forth.
	if absf(angle_difference(heading, facing)) > DIRECTION_CHANGE_ANGLE:
		_direction = posmod(roundi(heading / (PI / 4.0)), 8)


func _is_running(speed: float) -> bool:
	if _reaction.reaction_state in [_reaction.Reaction.FLEEING, _reaction.Reaction.SEEKING_SHELTER]:
		return true
	# Building traversal and escorts can move the actor without a personal flee route.
	return speed >= _reaction.fleeing_speed * 0.8


func _show_pose(column: int, row: int, mirrored: bool) -> void:
	var frame := Rect2(Vector2(column, row) * CELL_SIZE, CELL_SIZE)
	if region_rect != frame:
		region_rect = frame
	if flip_h != mirrored:
		flip_h = mirrored
