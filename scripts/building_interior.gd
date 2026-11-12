class_name BuildingInterior
extends Node2D

const ACCESS_LAYER := 16
const WALL_WIDTH := 5.0
const DOOR_HALF_DEPTH := WALL_WIDTH / 2.0
const NAV_CLEARANCE := 14.0
const PORTAL_OFFSET := 18.0
const EXTERIOR_OFFSET := 32.0

var outline: PackedVector2Array
var entrance: Vector2
var outward: Vector2
var across: Vector2
var half_width: float
var repair_points: PackedVector2Array
var rest_points: PackedVector2Array
var roof: Array[CanvasItem] = []
var threshold: StaticBody2D
var door_shape: CollisionShape2D
var door_visual: Polygon2D
var barricade_bar: Node2D
var barricade_ratio := 0.0
var map := RID()
var region := RID()


func configure(body: StaticBody2D, door_hint: Vector2) -> bool:
	var shape := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var polygon := body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if polygon != null:
		outline = polygon.transform * polygon.polygon
	elif shape != null and shape.shape is RectangleShape2D:
		var size: Vector2 = shape.shape.size
		outline = shape.transform * _rectangle(Rect2(-size / 2.0, size))
	else:
		return false
	var edge := _choose_entrance(door_hint)
	if edge < 0:
		return false
	var inset := Geometry2D.offset_polygon(outline, -NAV_CLEARANCE)
	if inset.size() != 1:
		return false
	var floor: PackedVector2Array = inset[0]
	if not Geometry2D.is_point_in_polygon(entrance - outward * PORTAL_OFFSET, floor):
		return false
	_build_walls(body, edge, floor)
	if polygon != null:
		polygon.disabled = true
	else:
		shape.disabled = true
	_create_navigation(floor)
	_create_presentation(body)
	repair_points = PackedVector2Array([
		_floor_point(entrance - outward * 22.0 - across * (half_width - 4.0), floor),
		_floor_point(entrance - outward * 22.0 + across * (half_width - 4.0), floor),
	])
	rest_points = _rest_positions(floor)
	return true


func _choose_entrance(hint: Vector2) -> int:
	var best := INF
	var edge := -1
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var length := a.distance_to(b)
		if length < 38.0:
			continue
		var tangent := a.direction_to(b)
		var width := minf(28.0, (length - 12.0) * 0.5)
		var at := a + tangent * clampf((hint - a).dot(tangent), width + 6.0, length - width - 6.0)
		var distance := at.distance_squared_to(hint)
		if distance < best:
			best = distance
			edge = i
			entrance = at
			across = tangent
			half_width = width
	if edge != -1:
		outward = across.orthogonal()
		if Geometry2D.is_point_in_polygon(entrance + outward * 2.0, outline):
			outward = -outward
	return edge


func _build_walls(body: StaticBody2D, edge: int, floor: PackedVector2Array) -> void:
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if i == edge:
			_wall(body, a, entrance - across * half_width)
			_wall(body, entrance + across * half_width, b)
		else:
			_wall(body, a, b)
	_add_partition(body, floor)
	threshold = StaticBody2D.new()
	threshold.name = "EntranceAccess"
	threshold.collision_layer = ACCESS_LAYER
	threshold.collision_mask = 0
	add_child(threshold)
	var a := entrance - across * half_width
	var b := entrance + across * half_width
	# Keep the blocking slab on the exterior side. A body entirely past the
	# footprint edge is already clear to close the door behind it.
	_add_shape(threshold, a, b).position += outward * DOOR_HALF_DEPTH
	var door := StaticBody2D.new()
	door.name = "DoorAndBarricades"
	door.collision_mask = 0
	add_child(door)
	door_shape = _add_shape(door, a, b)
	door_shape.position += outward * DOOR_HALF_DEPTH
	door_shape.disabled = true
	door_visual = _segment(a, b, Color("58402e"), WALL_WIDTH + 2.0)
	door_visual.z_index = 4
	door_visual.hide()


func _add_partition(body: StaticBody2D, floor: PackedVector2Array) -> void:
	if outline.size() != 4:
		return
	# Work in doorway coordinates so a rotated footprint keeps the partition
	# across the room, clear of the entrance and both work positions.
	var min_side := INF
	var max_side := -INF
	var depth := 0.0
	for point in outline:
		var relative := point - entrance
		min_side = minf(min_side, relative.dot(across))
		max_side = maxf(max_side, relative.dot(across))
		depth = maxf(depth, relative.dot(-outward))
	if max_side - min_side < 105.0 or depth < 88.0:
		return
	var middle := entrance - outward * depth * 0.5
	var wall_side := min_side if -min_side > max_side else max_side
	var start := middle + across * wall_side
	var end := middle + across * ((min_side + max_side) * 0.5 + signf(wall_side) * 8.0)
	var along := start.direction_to(end)
	var padding := along.orthogonal() * (NAV_CLEARANCE + WALL_WIDTH / 2.0)
	var near_end := start - along * NAV_CLEARANCE
	var far_end := end + along * NAV_CLEARANCE
	var barrier := PackedVector2Array([near_end - padding, far_end - padding, far_end + padding, near_end + padding])
	var rooms := Geometry2D.clip_polygons(floor, barrier)
	if rooms.size() == 1 and rooms[0].size() >= 4:
		floor.clear()
		floor.append_array(rooms[0])
		_wall(body, start, end)


func _wall(body: StaticBody2D, a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 0.1:
		return
	_add_shape(body, a, b)
	_segment(a, b, Color("484037"), WALL_WIDTH).z_index = 1


func _add_shape(body: StaticBody2D, a: Vector2, b: Vector2) -> CollisionShape2D:
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(a.distance_to(b), WALL_WIDTH)
	collider.shape = rectangle
	collider.position = (a + b) / 2.0
	collider.rotation = (b - a).angle()
	body.add_child(collider)
	return collider


func _segment(a: Vector2, b: Vector2, color: Color, width: float) -> Polygon2D:
	var side := a.direction_to(b).orthogonal() * width / 2.0
	return _surface(PackedVector2Array([a - side, b - side, b + side, a + side]), color)


func _surface(points: PackedVector2Array, color: Color) -> Polygon2D:
	var surface := Polygon2D.new()
	surface.polygon = points
	surface.color = color
	add_child(surface)
	return surface


func _create_presentation(body: StaticBody2D) -> void:
	var footprint := body.get_node_or_null("Footprint") as Polygon2D
	_surface(outline, Color("85705a")).z_index = 0
	for child in body.get_children():
		if child is Polygon2D or child is Line2D or child is Label:
			child.z_index = 5
			roof.append(child)
	if footprint != null:
		footprint.z_index = 4
	# Keep a visible entrance marker when the roof is opaque or the passage is open.
	var step := entrance + outward * 6.0
	_segment(step - across * half_width, step + across * half_width, Color("b8a17e"), 4.0).z_index = 3
	barricade_bar = Node2D.new()
	barricade_bar.name = "BarricadeHealth"
	barricade_bar.z_index = 6
	barricade_bar.hide()
	add_child(barricade_bar)
	barricade_bar.global_position = to_global(step) + Vector2(0.0, -10.0)
	barricade_bar.global_rotation = 0.0
	barricade_bar.draw.connect(_draw_barricade_bar)


func set_barricade_health(current: float, maximum: float) -> void:
	barricade_ratio = clampf(current / maxf(maximum, 0.01), 0.0, 1.0)
	barricade_bar.visible = barricade_ratio > 0.0
	barricade_bar.queue_redraw()


func _draw_barricade_bar() -> void:
	barricade_bar.draw_rect(Rect2(-15.0, -2.0, 30.0, 4.0), Color("221c17"))
	barricade_bar.draw_rect(Rect2(-14.0, -1.0, 28.0 * barricade_ratio, 2.0), Color("d4ac66"))


func _create_navigation(floor: PackedVector2Array) -> void:
	map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(map, true)
	region = NavigationServer2D.region_create()
	var nav := NavigationPolygon.new()
	nav.vertices = floor
	var indices := Geometry2D.triangulate_polygon(floor)
	for i in range(0, indices.size(), 3):
		nav.add_polygon(PackedInt32Array([indices[i], indices[i + 1], indices[i + 2]]))
	NavigationServer2D.region_set_navigation_polygon(region, nav)
	NavigationServer2D.region_set_transform(region, global_transform)
	NavigationServer2D.region_set_map(region, map)


func _floor_point(point: Vector2, floor: PackedVector2Array) -> Vector2:
	if Geometry2D.is_point_in_polygon(point, floor):
		return point
	var nearest := floor[0]
	for i in floor.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, floor[i], floor[(i + 1) % floor.size()])
		if candidate.distance_squared_to(point) < nearest.distance_squared_to(point):
			nearest = candidate
	return nearest


func _rest_positions(floor: PackedVector2Array) -> PackedVector2Array:
	var bounds := Rect2(floor[0], Vector2.ZERO)
	for point in floor:
		bounds = bounds.expand(point)
	var candidates: Array[Vector2] = []
	for y in range(ceili(bounds.position.y + 1), floori(bounds.end.y), 18):
		for x in range(ceili(bounds.position.x + 1), floori(bounds.end.x), 18):
			var point := Vector2(x, y)
			if point.distance_to(entrance) > 33.0 and Geometry2D.is_point_in_polygon(point, floor):
				candidates.append(point)
	candidates.sort_custom(func(a: Vector2, b: Vector2): return a.distance_squared_to(entrance) > b.distance_squared_to(entrance))
	if candidates.is_empty():
		candidates.append(entrance - outward * PORTAL_OFFSET)
	return PackedVector2Array(candidates)


func exterior(offset: float = EXTERIOR_OFFSET, side: float = 0.0) -> Vector2:
	return to_global(entrance + outward * offset + across * side)


func interior(side: float = 0.0, depth: float = PORTAL_OFFSET) -> Vector2:
	return to_global(entrance - outward * depth + across * side)


func depth(actor: CharacterBody2D) -> float:
	return depth_at(actor.global_position)


func depth_at(point: Vector2) -> float:
	return (to_local(point) - entrance).dot(outward)


func clearance(actor: CharacterBody2D) -> float:
	return _body_extent(actor, outward) + WALL_WIDTH


func entry_clearance(actor: CharacterBody2D) -> float:
	return _body_extent(actor, outward) + 0.1


func side_clearance(actor: CharacterBody2D) -> float:
	return _body_extent(actor, across)


func _body_extent(actor: CharacterBody2D, axis: Vector2) -> float:
	var shape: RectangleShape2D = actor.get_node("CollisionShape2D").shape
	var direction := (to_global(axis) - global_position).normalized()
	return (absf(direction.x) * shape.size.x + absf(direction.y) * shape.size.y) * 0.5


func set_blocked(blocked: bool, color: Color) -> void:
	door_shape.disabled = not blocked
	door_visual.visible = blocked
	door_visual.color = color


func _exit_tree() -> void:
	if region.is_valid():
		NavigationServer2D.free_rid(region)
	if map.is_valid():
		NavigationServer2D.free_rid(map)


static func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
