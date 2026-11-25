extends Control

const FOG_SHADER := preload("res://scripts/mission_selection_fog.gdshader")
const FOG_TEXTURE := preload("res://assets/ui/mission_selection_death_fog.png")
const REVEAL_SECONDS := 1.05

# Draw a captured map, or fall back to serialized geometry without starting gameplay.
var preview_texture: Texture2D
var shapes: Array[Dictionary] = []
var map_rect := Rect2()
var reveal_progress := 0.0
var _drawn_map_rect := Rect2()
var _fog_material := ShaderMaterial.new()
var _reveal_tween: Tween

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fog_material.shader = FOG_SHADER
	_fog_material.set_shader_parameter("fog_texture", FOG_TEXTURE)
	var fog := ColorRect.new()
	fog.material = _fog_material
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog)
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_map()

func clear_mission() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
		_reveal_tween = null
	_set_reveal_progress(0.0)
	shapes.clear()
	map_rect = Rect2()
	preview_texture = null
	_layout_map()

func show_mission(scene_path: String, preview_path := "") -> void:
	clear_mission()
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path, "Texture2D"):
		preview_texture = load(preview_path) as Texture2D
	if preview_texture != null:
		map_rect = Rect2(Vector2.ZERO, preview_texture.get_size())
	else:
		var scene := load(scene_path) as PackedScene
		if scene != null:
			_collect_scene(scene, Transform2D.IDENTITY)
			var state := scene.get_state()
			for index in range(state.get_node_property_count(0)):
				if state.get_node_property_name(0, index) == &"metadata/map_size":
					var map_size: Vector2 = state.get_node_property_value(0, index)
					if map_size.x > 0.0 and map_size.y > 0.0:
						map_rect = Rect2(Vector2.ZERO, map_size)
					break
	_layout_map()
	if map_rect.has_area():
		_reveal_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_reveal_tween.tween_method(_set_reveal_progress, 0.0, 1.0, REVEAL_SECONDS)

func _set_reveal_progress(value: float) -> void:
	reveal_progress = value
	_fog_material.set_shader_parameter("reveal", value)

func _collect_scene(scene: PackedScene, base_transform: Transform2D) -> void:
	var state := scene.get_state()
	var transforms: Dictionary = {}
	for index in range(state.get_node_count()):
		var path := state.get_node_path(index)
		var parent_path := state.get_node_path(index, true)
		if index > 0 and not transforms.has(parent_path): continue
		var instance := state.get_node_instance(index)
		var type := state.get_node_type(index)
		if instance != null: type = instance.get_state().get_node_type(0)
		if type in [&"CharacterBody2D", &"CanvasLayer", &"Camera2D"]: continue
		var properties: Dictionary = {}
		for property_index in range(state.get_node_property_count(index)):
			properties[state.get_node_property_name(index, property_index)] = state.get_node_property_value(index, property_index)
		if not properties.get("visible", true): continue
		var local := Transform2D(properties.get("rotation", 0.0), properties.get("scale", Vector2.ONE), properties.get("skew", 0.0), properties.get("position", Vector2.ZERO))
		var transform: Transform2D = transforms.get(parent_path, base_transform) * local
		transforms[path] = transform
		if instance != null:
			_collect_scene(instance, transform)
		if type != &"Polygon2D": continue
		var polygon: PackedVector2Array = properties.get("polygon", PackedVector2Array())
		if polygon.size() < 3: continue
		var points: PackedVector2Array = transform * polygon
		var first_shape := shapes.is_empty()
		var shape := {"points": points, "color": properties.get("color", Color.WHITE)}
		var texture := properties.get("texture") as Texture2D
		var uv: PackedVector2Array = properties.get("uv", PackedVector2Array())
		if texture != null and uv.size() == points.size():
			var normalized_uv := PackedVector2Array()
			for pixel_uv in uv: normalized_uv.append(pixel_uv / texture.get_size())
			shape["texture"] = texture
			shape["uv"] = normalized_uv
		shapes.append(shape)
		for point_index in range(points.size()):
			if first_shape and point_index == 0:
				map_rect = Rect2(points[point_index], Vector2.ZERO)
			else:
				map_rect = map_rect.expand(points[point_index])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_map()

func _layout_map() -> void:
	_fog_material.set_shader_parameter("canvas_size", size.max(Vector2.ONE))
	_drawn_map_rect = Rect2()
	if map_rect.has_area():
		var area := Rect2(Vector2(12, 8), (size - Vector2(24, 98)).max(Vector2.ONE))
		var ratio := minf(area.size.x / map_rect.size.x, area.size.y / map_rect.size.y)
		var drawn_size := map_rect.size * ratio
		_drawn_map_rect = Rect2(area.get_center() - drawn_size * 0.5, drawn_size)
		var origin := _drawn_map_rect.position
		_fog_material.set_shader_parameter("map_frame", Vector4(origin.x, origin.y, drawn_size.x, drawn_size.y))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("131613"))
	if not _drawn_map_rect.has_area(): return
	if preview_texture != null:
		draw_texture_rect(preview_texture, _drawn_map_rect, false)
	else:
		var ratio := _drawn_map_rect.size.x / map_rect.size.x
		for shape in shapes:
			var points := PackedVector2Array()
			for point in shape.points:
				points.append(_drawn_map_rect.position + (point - map_rect.position) * ratio)
			if shape.has("texture"):
				draw_polygon(points, PackedColorArray([shape.color]), shape.uv, shape.texture)
			else:
				draw_colored_polygon(points, shape.color)
