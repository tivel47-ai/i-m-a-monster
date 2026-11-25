extends Sprite2D

const PORTRAIT_SHADER = preload("res://scripts/zombie_race_portrait.gdshader")

enum Pose { REST, INHALE, EXHALE, GLANCE_START, GLANCE, SWAY }
const LENGTH := 8.65
const TIMELINE := [
	Vector2(0.00, Pose.REST), Vector2(0.42, Pose.INHALE), Vector2(0.70, Pose.REST),
	Vector2(1.00, Pose.EXHALE), Vector2(1.36, Pose.REST), Vector2(1.84, Pose.INHALE),
	Vector2(2.12, Pose.REST), Vector2(2.40, Pose.EXHALE), Vector2(2.72, Pose.REST),
	Vector2(3.28, Pose.GLANCE_START), Vector2(3.53, Pose.GLANCE),
	Vector2(4.38, Pose.GLANCE_START), Vector2(4.67, Pose.REST),
	Vector2(5.22, Pose.INHALE), Vector2(5.57, Pose.REST),
	Vector2(5.92, Pose.EXHALE), Vector2(6.25, Pose.REST),
	Vector2(6.92, Pose.EXHALE), Vector2(7.18, Pose.SWAY),
	Vector2(7.58, Pose.EXHALE), Vector2(7.88, Pose.REST),
]

var appearance := 0
var portrait_height := 0.0
var _elapsed := 0.0
var _pose := -1
var _ground_points: Array[Vector2]
var _frame_size: Vector2
var _portrait_material: ShaderMaterial


func set_portrait(atlas: Texture2D, ground_points: Array[Vector2], height: float,
		phase: float, haze: float) -> void:
	texture = atlas
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	_frame_size = atlas.get_size() / Vector2(3, 2)
	_ground_points = ground_points
	portrait_height = height
	_portrait_material = ShaderMaterial.new()
	_portrait_material.shader = PORTRAIT_SHADER
	_portrait_material.set_shader_parameter("haze", haze)
	material = _portrait_material
	_elapsed = phase
	_update_pose()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_elapsed = fposmod(_elapsed + delta, LENGTH)
		_update_pose()


func _update_pose() -> void:
	for index in range(TIMELINE.size() - 1, -1, -1):
		if _elapsed >= TIMELINE[index].x:
			_show_pose(int(TIMELINE[index].y))
			return


func _show_pose(pose: int) -> void:
	if _pose == pose:
		return
	_pose = pose
	var frame_origin := Vector2(pose % 3, floori(pose / 3.0)) * _frame_size
	var ground := _ground_points[pose]
	region_rect = Rect2(frame_origin, _frame_size)
	offset = Vector2(ground.x - _frame_size.x if flip_h else -ground.x, -ground.y)
	var atlas_size := texture.get_size()
	var atlas_ground := (frame_origin + ground) / atlas_size
	var rest_ground := _ground_points[Pose.REST] / atlas_size
	_portrait_material.set_shader_parameter("rest_offset", rest_ground - atlas_ground)
	_portrait_material.set_shader_parameter("ground_height", Vector2(atlas_ground.y, portrait_height / atlas_size.y))
