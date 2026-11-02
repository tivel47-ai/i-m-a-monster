extends Control

# Read serialized geometry without instantiating gameplay scripts or AI.
var shapes: Array[Dictionary] = []
var map_rect := Rect2()

func show_mission(scene_path: String) -> void:
	shapes.clear()
	map_rect = Rect2()
	var scene := load(scene_path) as PackedScene
	if scene != null:
		_collect_scene(scene, Transform2D.IDENTITY)
	queue_redraw()

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
		shapes.append({"points": points, "color": properties.get("color", Color.WHITE)})
		for point_index in range(points.size()):
			if first_shape and point_index == 0:
				map_rect = Rect2(points[point_index], Vector2.ZERO)
			else:
				map_rect = map_rect.expand(points[point_index])

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101711"))
	if map_rect.size.x <= 0 or map_rect.size.y <= 0: return
	var available := (size - Vector2(16, 16)).max(Vector2.ONE)
	var ratio := minf(available.x / map_rect.size.x, available.y / map_rect.size.y)
	var origin := (size - map_rect.size * ratio) * 0.5
	for shape in shapes:
		var points := PackedVector2Array()
		for point in shape.points:
			points.append(origin + (point - map_rect.position) * ratio)
		draw_colored_polygon(points, shape.color)
	draw_rect(Rect2(origin, map_rect.size * ratio), Color("819374"), false, 1.0)
