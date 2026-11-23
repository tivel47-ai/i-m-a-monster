class_name ChurchDoorVisual
extends Node2D

const SWING_SECONDS := 0.38

@export var initially_open := true
@export var animates_light := true

var _intact := true
var _target := 1.0
var _swing: Tween
var _light_time := 0.0
var _opening := 1.0:
	set(value):
		_opening = value
		set_instance_shader_parameter(&"opening", value)


func _ready() -> void:
	_target = 1.0 if initially_open else 0.0
	_opening = _target
	set_process(animates_light)


func _process(delta: float) -> void:
	if _intact and _opening <= 0.0:
		return
	_light_time += delta
	set_instance_shader_parameter(&"light_time", _light_time)


func update_door(blocked: bool, intact: bool) -> void:
	var target := 0.0 if blocked else 1.0
	if _target == target and _intact == intact:
		return
	if _swing != null:
		_swing.kill()
	_target = target
	_intact = intact
	set_instance_shader_parameter(&"intact", intact)
	if not intact or is_equal_approx(_opening, target):
		_opening = target
		return
	_swing = create_tween().set_trans(Tween.TRANS_SINE)
	_swing.tween_property(self, "_opening", target, SWING_SECONDS * absf(_opening - target))
