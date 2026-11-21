extends "res://scripts/ordinary_zombie_visual.gd"

const IDLE_TIME := 0.75
const WALK_TIME := 0.95
const RUSH_TIME := 0.50
const ATTACK_TIME := 0.60
const PASS_TIME := IDLE_TIME + WALK_TIME + RUSH_TIME + ATTACK_TIME
const WALK_RANGE := 5.0

var _elapsed := 0.0


func _ready() -> void:
	_setup_sprite()
	set_physics_process(false)
	_show_preview_pose()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed = fposmod(_elapsed + delta, PASS_TIME * 2.0 * ART.WINDUP_TIMES.size())
	_show_preview_pose()


func _show_preview_pose() -> void:
	var pass_index := int(_elapsed / PASS_TIME)
	var returning := pass_index % 2 != 0
	var time := fposmod(_elapsed, PASS_TIME)
	var travel := clampf((time - IDLE_TIME) / (WALK_TIME + RUSH_TIME), 0.0, 1.0)
	_direction = 7 if returning else 1
	position.x = lerpf(-WALK_RANGE, WALK_RANGE, 1.0 - travel if returning else travel)
	if time < IDLE_TIME:
		_idle_time = time
		_show_idle()
	elif time < IDLE_TIME + WALK_TIME:
		var phase := fposmod((time - IDLE_TIME) * 1.7, 1.0)
		_show_cycle(ART.Clip.WALK, ART.walk_frame(phase))
	elif time < IDLE_TIME + WALK_TIME + RUSH_TIME:
		var phase := fposmod((time - IDLE_TIME - WALK_TIME) * 2.6, 1.0)
		_show_cycle(ART.Clip.RUSH, int(phase * ART.FRAME_COUNT))
	else:
		var progress := (time - IDLE_TIME - WALK_TIME - RUSH_TIME) / ATTACK_TIME
		var row := ART.Clip.SWIPE + int(pass_index / 2.0) % ART.WINDUP_TIMES.size()
		_show_cycle(row, mini(int(progress * ART.FRAME_COUNT), ART.FRAME_COUNT - 1))
