@tool
extends Node2D

const GRAVESTONES := preload("res://assets/maps/mission_01/gravestones.png")
const FENCES := preload("res://assets/maps/mission_01/fences.png")
const CELL := Vector2(48, 64)
const POST_SPACING := 36.0

enum FenceStyle { FARM, CEMETERY, BRIDGE }

var _props: Node2D
var _shadow: GradientTexture2D
var _contact_shadows: Array[Rect2] = []


func _ready() -> void:
	_shadow = GradientTexture2D.new()
	_shadow.gradient = Gradient.new()
	_shadow.gradient.colors = PackedColorArray([Color(0.035, 0.045, 0.048, 0.48), Color(0.035, 0.045, 0.048, 0)])
	_shadow.fill = GradientTexture2D.FILL_RADIAL
	_shadow.fill_from = Vector2(0.5, 0.5)
	_shadow.fill_to = Vector2(1, 0.5)
	_props = Node2D.new()
	_props.name = &"SpritesAndRails"
	_props.y_sort_enabled = true
	_props.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_props)

	var region := get_parent()
	var buildings := region.get_node("Buildings/Public")
	for grave: StaticBody2D in buildings.find_children("Grave*", "StaticBody2D", false):
		var variant := String(grave.name).trim_prefix("Grave").to_int() % 8
		var ground := to_local(grave.global_position) + Vector2(0, 4)
		var cell_origin := Vector2(variant % 4, floori(variant / 4.0)) * CELL
		_add_sprite(grave.name, GRAVESTONES, cell_origin, ground, 56, 0.40)
		_contact_shadows.append(Rect2(ground - Vector2(11, 4), Vector2(24, 9)))

	var posts: Dictionary[Vector2, bool] = {}
	for boundary in region.get_node("Fences").get_children():
		for section in boundary.get_children():
			var style := FenceStyle.CEMETERY if section.get_meta("enclosure") == "Environment/CemeteryYard" else FenceStyle.FARM
			_add_fence(section, style, posts)
	for rail in region.get_node("River/BridgeRails").get_children():
		_add_fence(rail, FenceStyle.BRIDGE, posts)
	queue_redraw()


func _draw() -> void:
	if _shadow == null:
		return
	for rect in _contact_shadows:
		draw_texture_rect(_shadow, rect, false)


func _add_fence(body: StaticBody2D, style: FenceStyle, posts: Dictionary[Vector2, bool]) -> void:
	var collider := body.get_node("CollisionPolygon2D") as CollisionPolygon2D
	var corners := collider.polygon
	# The two short edges of the saved rectangle give the actual endpoints in plan.
	var start := to_local(collider.to_global((corners[0] + corners[3]) * 0.5))
	var end := to_local(collider.to_global((corners[1] + corners[2]) * 0.5))
	var bay_count := maxi(1, ceili(start.distance_to(end) / POST_SPACING))
	var bridge := style == FenceStyle.BRIDGE
	var cemetery := style == FenceStyle.CEMETERY
	var previous := start
	for index in range(bay_count + 1):
		var ground := start.lerp(end, float(index) / bay_count)
		if index > 0:
			var half_width := 1.5 if bridge else 1.1
			_add_rail(previous, ground, 6.0 if bridge else 4.75, half_width, cemetery)
			_add_rail(previous, ground, 13.9 if bridge else 10.8, half_width, cemetery)
		previous = ground

		# Adjacent sections may share a corner or lie on opposite sides of one join.
		var key := ground.snapped(Vector2(0.1, 0.1))
		if posts.has(key):
			continue
		posts[key] = true
		var stone_pier := cemetery and (index == bay_count or index % 4 == 0)
		var variant := 3 if bridge else (2 if stone_pier else absi(roundi(ground.x + ground.y)) % 2)
		_add_sprite(&"Post", FENCES, Vector2(variant * CELL.x, 0), ground + Vector2(0, 2), 57, 0.33 if bridge else 0.29)
		_contact_shadows.append(Rect2(ground - Vector2(5, 2), Vector2(12, 6)))


func _add_sprite(title: StringName, atlas: Texture2D, cell_origin: Vector2, ground: Vector2, baseline: float, sprite_scale: float) -> void:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(cell_origin, CELL)
	texture.filter_clip = true
	var sprite := Sprite2D.new()
	sprite.name = title
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = Vector2(-CELL.x * 0.5, -baseline)
	sprite.position = ground
	sprite.scale = Vector2.ONE * sprite_scale
	_props.add_child(sprite)


func _add_rail(start: Vector2, end: Vector2, height: float, half_width: float, aged: bool) -> void:
	var across := start.direction_to(end).orthogonal() * half_width
	if across.y < 0:
		across = -across
	var center := (start + end) * 0.5
	var a := start - center + Vector2(0, -height)
	var b := end - center + Vector2(0, -height)
	var points := PackedVector2Array([a - across, b - across, b + across, a + across])
	var offset := 128.0 if aged else 0.0
	var uvs := PackedVector2Array([
		Vector2(10 + offset, 84), Vector2(118 + offset, 84),
		Vector2(118 + offset, 93), Vector2(10 + offset, 93),
	])
	var faces: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 2, 3])]
	# A vertical span shows the narrow top in this projection. Its front is edge-on.
	if absf(a.x - b.x) > 0.01:
		var thickness := Vector2(0, half_width * 1.65)
		points.append_array(PackedVector2Array([a + across, b + across, b + across + thickness, a + across + thickness]))
		uvs.append_array(PackedVector2Array([
			Vector2(10 + offset, 105), Vector2(118 + offset, 105),
			Vector2(118 + offset, 117), Vector2(10 + offset, 117),
		]))
		faces.append(PackedInt32Array([4, 5, 6, 7]))
	var rail := Polygon2D.new()
	rail.name = &"Rail"
	rail.position = center
	rail.texture = FENCES
	rail.polygon = points
	rail.uv = uvs
	rail.polygons = faces
	_props.add_child(rail)
