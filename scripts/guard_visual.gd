extends Sprite2D

signal death_finished

const HUMAN_VISUAL = preload("res://scripts/peasant_visual.gd")
const SHIELD := &"shield"
const SWORD := &"sword"
const SPEAR := &"spear"
const ATLASES := {
	SHIELD: preload("res://assets/sprites/characters/guards/shield.png"),
	SWORD: preload("res://assets/sprites/characters/guards/sword.png"),
	SPEAR: preload("res://assets/sprites/characters/guards/spear.png"),
}
const CELL_HEIGHT := 160.0
const FRAME_HEIGHT := 100.0
const FRAME_FEET_Y := 135.0
const WORLD_HEIGHT := HUMAN_VISUAL.WORLD_HEIGHT
const FEET_Y := HUMAN_VISUAL.FEET_Y
const HEALTH_BAR_Y := HUMAN_VISUAL.HEALTH_BAR_Y
const SPEAR_HEALTH_BAR_Y := HEALTH_BAR_Y - 4.0
const IDLE_FPS := 4.0
const DEATH_FPS := 10.0
const MOVE_THRESHOLD := 4.0
const DIRECTION_CHANGE_ANGLE := deg_to_rad(27.5)
const MAX_ATTACK_FRAME_SECONDS := 0.10
const IMPACT_FRAME := 3
const ACTION_FRAMES := 6
const DIRECTIONAL_IDLE_ROW := 0
const DIRECTIONAL_WALK_ROW := 5
const DIRECTIONAL_ATTACK_ROW := 10
const DIRECTIONAL_DEATH_ROW := 15
const DIRECTIONAL_MOVEMENT_WIDTH := 128.0
const DIRECTIONAL_ACTION_WIDTHS := {SHIELD: 176.0, SWORD: 176.0, SPEAR: 288.0}
const DIRECTIONAL_WALK_DISTANCES := [22.0, 25.0, 28.0, 25.0, 22.0]

var appearance: StringName = SHIELD
var _actor: Node2D
var _melee_timer: Timer
var _last_position: Vector2
var _direction := 1 # S, SE, E, NE, N, NW, W, SW
var _moving := false
var _phase := 0.0
var _impact_time := -1.0
var _attack_frame_seconds := MAX_ATTACK_FRAME_SECONDS
var _death_time := -1.0


func _ready() -> void:
	_actor = get_parent() as Node2D
	_melee_timer = _actor.get_node("EncounterAttackTimer") as Timer
	_last_position = _actor.global_position
	texture = ATLASES[appearance]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	region_enabled = true
	region_filter_clip_enabled = true
	position.y = FEET_Y
	scale = Vector2.ONE * (WORLD_HEIGHT / FRAME_HEIGHT)
	offset.y = CELL_HEIGHT * 0.5 - FRAME_FEET_Y
	_show_frame(0, DIRECTIONAL_IDLE_ROW)


func _physics_process(delta: float) -> void:
	var displacement := _actor.global_position - _last_position
	_last_position = _actor.global_position
	if _death_time >= 0.0:
		_death_time += delta
		var frame := mini(int(_death_time * DEATH_FPS), ACTION_FRAMES - 1)
		_show_frame(frame, DIRECTIONAL_DEATH_ROW)
		if _death_time >= ACTION_FRAMES / DEATH_FPS:
			set_physics_process(false)
			death_finished.emit()
		return

	if _impact_time >= 0.0:
		_impact_time += delta
		var frame := IMPACT_FRAME + int(_impact_time / _attack_frame_seconds)
		if frame < ACTION_FRAMES:
			_show_frame(frame, DIRECTIONAL_ATTACK_ROW)
			return
		_impact_time = -1.0

	var distance := displacement.length()
	var moving := distance >= MOVE_THRESHOLD * delta and distance < WORLD_HEIGHT
	if _moving != moving:
		_moving = moving
		_phase = 0.0
	if moving:
		_face(displacement)
		var cycle_distance: float = DIRECTIONAL_WALK_DISTANCES[_atlas_direction()]
		_phase = fposmod(_phase + distance / cycle_distance, 1.0)
		_show_frame(int(_phase * 8.0), DIRECTIONAL_WALK_ROW)
		return

	if not _melee_timer.is_stopped():
		var frame_seconds := _frame_seconds(_melee_timer.wait_time)
		# Sword users hold a drawn stance between attacks while stopped.
		if appearance != SPEAR or _melee_timer.time_left <= frame_seconds * IMPACT_FRAME:
			var target := _actor.call("_encounter_attack_target") as Node2D
			if target != null:
				var heading := target.global_position - _actor.global_position
				_face(heading)
				var frame := clampi(IMPACT_FRAME - ceili(_melee_timer.time_left / frame_seconds), 0, IMPACT_FRAME - 1)
				_show_frame(frame, DIRECTIONAL_ATTACK_ROW)
				return

	_phase = fposmod(_phase + delta * IDLE_FPS / 4.0, 1.0)
	_show_frame(int(_phase * 4.0), DIRECTIONAL_IDLE_ROW)


func vision_direction() -> int:
	return _direction


func play_impact(heading: Vector2, interval: float) -> void:
	if _death_time >= 0.0:
		return
	_face(heading)
	_impact_time = 0.0
	_attack_frame_seconds = _frame_seconds(interval)
	_show_frame(IMPACT_FRAME, DIRECTIONAL_ATTACK_ROW)


func play_death() -> void:
	_death_time = 0.0
	_show_frame(0, DIRECTIONAL_DEATH_ROW)


func health_bar_y() -> float:
	return SPEAR_HEALTH_BAR_Y if appearance == SPEAR else HEALTH_BAR_Y


func _face(heading: Vector2) -> void:
	if heading.is_zero_approx():
		return
	var angle := PI / 2.0 - heading.angle()
	if absf(angle_difference(angle, _direction * PI / 4.0)) > DIRECTION_CHANGE_ANGLE:
		_direction = posmod(roundi(angle / (PI / 4.0)), 8)


func _frame_seconds(interval: float) -> float:
	return minf(MAX_ATTACK_FRAME_SECONDS, interval / ACTION_FRAMES)


func _atlas_direction() -> int:
	return 8 - _direction if _direction > 4 else _direction


func _show_frame(column: int, first_row: int) -> void:
	var width: float = (
		DIRECTIONAL_MOVEMENT_WIDTH
		if first_row < DIRECTIONAL_ATTACK_ROW
		else DIRECTIONAL_ACTION_WIDTHS[appearance]
	)
	var cell := Vector2(width, CELL_HEIGHT)
	var row := first_row + _atlas_direction()
	var frame := Rect2(Vector2(column, row) * cell, cell)
	if region_rect != frame:
		region_rect = frame
	var mirrored := _direction > 4
	if flip_h != mirrored:
		flip_h = mirrored
