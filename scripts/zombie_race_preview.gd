extends MeshInstance2D

const PORTRAIT_SHADER = preload("res://scripts/zombie_race_portrait.gdshader")
const CELL_SIZE := 512
const GRID_SEGMENTS := 32
const MESH_ORIGIN := Vector2(256, 480)
const LENGTH := 24.0

static var _portrait_mesh: ArrayMesh

var appearance := 0
var portrait_height := 0.0
var _elapsed := 0.0
var _pace := 1.0
var _portrait_material: ShaderMaterial


func set_portrait(atlas: Texture2D, ground: Vector2, hip: Vector2, neck: Vector2, height: float,
		phase: float, pace: float, haze: float, mirrored: bool) -> void:
	if _portrait_mesh == null:
		_portrait_mesh = _build_mesh(atlas.get_size())
	mesh = _portrait_mesh
	texture = atlas
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait_height = height
	_pace = pace
	_portrait_material = ShaderMaterial.new()
	_portrait_material.shader = PORTRAIT_SHADER
	_portrait_material.set_shader_parameter("mesh_origin", MESH_ORIGIN)
	_portrait_material.set_shader_parameter("ground", ground)
	_portrait_material.set_shader_parameter("hip", hip)
	_portrait_material.set_shader_parameter("neck", neck)
	_portrait_material.set_shader_parameter("portrait_height", height)
	_portrait_material.set_shader_parameter("haze", haze)
	_portrait_material.set_shader_parameter("facing", -1.0 if mirrored else 1.0)
	material = _portrait_material
	_elapsed = phase
	_update_pose()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_elapsed = fposmod(_elapsed + delta * _pace, LENGTH)
		_update_pose()


func _update_pose() -> void:
	var breath := sin(_elapsed * TAU / 6.0)
	var sway := sin(_elapsed * TAU / 12.0 - 0.6)
	var glance := _ease(7.0, 9.6) * (1.0 - _ease(10.7, 13.6))
	_portrait_material.set_shader_parameter("torso_motion",
		Vector3(deg_to_rad(1.5 * sway + 0.5 * glance), 1.0 + 0.009 * breath, 1.0 + 0.012 * breath))
	_portrait_material.set_shader_parameter("head_motion",
		Vector2(deg_to_rad(-5.5 * glance - 0.65 * sway), glance))


func _ease(begin: float, end: float) -> float:
	var t := clampf(inverse_lerp(begin, end, _elapsed), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


static func _build_mesh(atlas_size: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := GRID_SEGMENTS + 1
	var step := float(CELL_SIZE) / GRID_SEGMENTS
	for row in stride:
		for column in stride:
			var point := Vector2(column, row) * step
			surface.set_uv(point / atlas_size)
			var vertex := point - MESH_ORIGIN
			surface.add_vertex(Vector3(vertex.x, vertex.y, 0.0))
	for row in GRID_SEGMENTS:
		for column in GRID_SEGMENTS:
			var top := row * stride + column
			var bottom := top + stride
			for index in [top, top + 1, bottom, top + 1, bottom + 1, bottom]:
				surface.add_index(index)
	return surface.commit()
