extends Node

const VILLAGE_ALERT = preload("res://scripts/village_alert.gd")
const RESIDENT_RADIUS := 250.0
const ZOMBIE_RADIUS := 200.0
const DIRECTION_STEP := TAU / 8.0

var radius: float
var panoramic := false
var _actor: Node2D
var _visual: Sprite2D
var _alert: VILLAGE_ALERT
var _last_position: Vector2
var _fallback_angle := PI / 4.0
var _pose_angle := INF


static func attach(actor: Node2D, visual: Sprite2D, view_radius: float, full_circle := false) -> Node:
	var mission := actor.get_parent()
	while mission != null and not mission.get_meta("directional_unit_vision", false):
		mission = mission.get_parent()
	if mission == null:
		return null
	var vision := new()
	vision.name = "UnitVision"
	vision.radius = view_radius
	vision.panoramic = full_circle
	vision._actor = actor
	vision._visual = visual
	if not full_circle:
		vision._alert = mission.get_node_or_null("VillageAlert") as VILLAGE_ALERT
	vision._last_position = actor.global_position
	actor.add_child(vision)
	vision.set_physics_process(visual == null and not full_circle)
	return vision


func _physics_process(_delta: float) -> void:
	if _actor.is_alive():
		var displacement := _actor.global_position - _last_position
		_last_position = _actor.global_position
		if displacement.length_squared() >= 0.0001:
			face(displacement)


func face(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		_fallback_angle = snappedf(direction.angle(), DIRECTION_STEP)


func face_at_rest(direction: Vector2) -> void:
	# The last navigation step may have landed after the previous vision tick.
	_last_position = _actor.global_position
	face(direction)


func face_for_pose(direction: Vector2) -> void:
	_pose_angle = INF if direction.is_zero_approx() else snappedf(direction.angle(), DIRECTION_STEP)


func facing_angle() -> float:
	if _pose_angle != INF:
		return _pose_angle
	if _visual != null:
		# Sprite indices start at south and advance toward east.
		return PI / 2.0 - _visual.vision_direction() * DIRECTION_STEP
	return _fallback_angle


func contains(world_point: Vector2) -> bool:
	var offset := world_point - _actor.global_position
	var distance_squared := offset.length_squared()
	var radius_squared := radius * radius
	if radius <= 0.0 or (distance_squared > radius_squared and not is_equal_approx(distance_squared, radius_squared)):
		return false
	var rear_fraction := _rear_fraction()
	if rear_fraction == 1.0 or Vector2.from_angle(facing_angle()).dot(offset) >= -0.0001:
		return true
	var rear_radius_squared := radius_squared * rear_fraction * rear_fraction
	return rear_fraction > 0.0 and (distance_squared <= rear_radius_squared
		or is_equal_approx(distance_squared, rear_radius_squared))


func _rear_fraction() -> float:
	if panoramic:
		return 1.0
	if not is_instance_valid(_alert):
		return 0.0
	match _alert.level:
		VILLAGE_ALERT.Level.SUSPICION:
			return 1.0 / 3.0
		VILLAGE_ALERT.Level.ALARM:
			return 0.5
		VILLAGE_ALERT.Level.ORGANIZED_DEFENSE, VILLAGE_ALERT.Level.LAST_STAND:
			return 1.0
	return 0.0


func draw_outline(canvas: Node2D, color: Color) -> void:
	if radius <= 0.0:
		return
	var center := canvas.to_local(_actor.global_position)
	var rear_fraction := _rear_fraction()
	if rear_fraction == 1.0:
		canvas.draw_arc(center, radius, 0.0, TAU, 64, color, 1.5, true)
		return
	var angle := facing_angle()
	var edge := Vector2.from_angle(angle + PI / 2.0) * radius
	canvas.draw_arc(center, radius, angle - PI / 2.0, angle + PI / 2.0, 32, color, 1.5, true)
	if rear_fraction == 0.0:
		canvas.draw_line(center - edge, center + edge, color, 1.5, true)
	else:
		var rear_edge := edge * rear_fraction
		canvas.draw_arc(center, radius * rear_fraction, angle + PI / 2.0, angle + 3.0 * PI / 2.0, 32, color, 1.5, true)
		canvas.draw_line(center - edge, center - rear_edge, color, 1.5, true)
		canvas.draw_line(center + rear_edge, center + edge, color, 1.5, true)
	canvas.draw_line(center, center + Vector2.from_angle(angle) * radius * 0.18, color, 2.0, true)
