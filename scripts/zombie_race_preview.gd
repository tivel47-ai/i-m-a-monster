extends "res://scripts/ordinary_zombie_visual.gd"

const IDLE_TIME := 1.0
const WALK_TIME := 1.25
const PASS_TIME := IDLE_TIME + WALK_TIME + SWING_FRAMES * MAX_SWING_FRAME_TIME
const WALK_RANGE := 10.0

var _elapsed := 0.0


func _ready() -> void:
	_setup_sprite()
	set_physics_process(false)
	_show_preview_pose()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed = fposmod(_elapsed + delta, PASS_TIME * 2.0)
	_show_preview_pose()


func _show_preview_pose() -> void:
	var returning := _elapsed >= PASS_TIME
	var time := fposmod(_elapsed, PASS_TIME)
	var travel := clampf((time - IDLE_TIME) / WALK_TIME, 0.0, 1.0)
	_direction = 7 if returning else 1
	position.x = lerpf(-WALK_RANGE, WALK_RANGE, 1.0 - travel if returning else travel)
	if time < IDLE_TIME:
		_show_cycle(&"idle", int(time * IDLE_FPS))
	elif time < IDLE_TIME + WALK_TIME:
		_show_cycle(&"walk", int((time - IDLE_TIME) * WALK_FPS) % 8)
	else:
		var attack_time := time - IDLE_TIME - WALK_TIME
		_show_cycle(&"attack", mini(int(attack_time / MAX_SWING_FRAME_TIME), SWING_FRAMES - 1))
