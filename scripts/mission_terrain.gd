extends Polygon2D

const SURFACE := preload("res://scripts/mission_terrain_surface.gdshader")
const WIND := preload("res://scripts/mission_terrain_wind.gdshader")
const TERRAIN_DISTANCE := preload("res://scripts/mission_terrain_distance.gd")
const MEADOW := preload("res://assets/maps/mission_01/meadow.png")
const DIRT := preload("res://assets/maps/mission_01/dirt.png")
const WATER := preload("res://assets/maps/mission_01/river.png")
const TIMBER := preload("res://assets/maps/mission_01/timber.png")
const GRASS := preload("res://assets/maps/mission_01/grass_tuft.png")
const TREES := preload("res://assets/maps/mission_01/trees.png")
const GROUND_DETAILS := preload("res://assets/maps/mission_01/ground_details.png")
const MEADOW_DETAILS := preload("res://assets/maps/mission_01/meadow_details.png")

enum Kind { MEADOW, ROAD, FIELD, WATER, DECK, BANK, RAIL, RUT }
enum Detail { STONE, BUSH, PUDDLE, THICKET, WILD_GROWTH, GROUND_SCATTER }
const TREE_REGIONS := [
	Rect2(155, 157, 373, 355), Rect2(705, 60, 391, 465),
	Rect2(109, 731, 468, 398), Rect2(696, 703, 447, 426),
]
const TRUNK_ORIGINS := [
	Vector2(186, 339), Vector2(200, 449), Vector2(224, 382), Vector2(217, 410),
]
const TREE_ORDER := [0, 2, 1, 0, 2, 3, 0, 1, 2, 0, 1]
const GRASS_ROOT := Vector2(137, 278)
const DETAIL_REGIONS := [
	[Rect2(86, 134, 275, 185), Rect2(528, 174, 195, 122), Rect2(892, 158, 284, 152)],
	[Rect2(52, 502, 333, 236), Rect2(462, 528, 338, 198), Rect2(910, 525, 266, 200)],
	[Rect2(56, 954, 334, 192), Rect2(475, 996, 309, 124), Rect2(891, 971, 288, 156)],
	[Rect2(17, 75, 382, 317), Rect2(432, 88, 384, 283), Rect2(836, 86, 404, 289)],
	[Rect2(34, 479, 350, 306), Rect2(436, 494, 376, 282), Rect2(848, 497, 380, 278)],
	[Rect2(45, 932, 312, 203), Rect2(444, 934, 347, 196), Rect2(863, 936, 357, 199)],
]
const DETAIL_NAMES := ["Stone", "Bush", "Puddle", "Thicket", "WildGrowth", "GroundScatter"]
const DETAIL_WIDTHS := [
	Vector2(16, 39), Vector2(34, 60), Vector2(31, 60),
	Vector2(50, 81), Vector2(23, 48), Vector2(26, 48),
]
const PUDDLE_CLEARINGS := [
	Vector2(260, 320), Vector2(854, 245), Vector2(2545, 330), Vector2(2360, 126),
	Vector2(1370, 1120), Vector2(1690, 1030), Vector2(2250, 761), Vector2(2930, 905),
	Vector2(520, 1490), Vector2(2070, 1650), Vector2(2505, 1860),
]
const MEADOW_PATCHES := [
	# Clearings along the western edge and around the cottages.
	Vector2(152, 620), Vector2(243, 815), Vector2(100, 827), Vector2(402, 420), Vector2(710, 471),
	Vector2(914, 341), Vector2(1210, 478), Vector2(1140, 626), Vector2(565, 670),
	Vector2(637, 851), Vector2(1055, 789), Vector2(1233, 958), Vector2(1330, 1110),
	# Yards and open ground between the square, the smithy and the river.
	Vector2(1577, 685), Vector2(1650, 768), Vector2(1900, 592), Vector2(2085, 686),
	Vector2(2435, 701), Vector2(2525, 426), Vector2(1935, 982), Vector2(2162, 986), Vector2(2480, 1114),
	Vector2(2847, 689), Vector2(2905, 1011), Vector2(2865, 1293),
	# Margins of the fields and the larger southern meadows.
	Vector2(618, 1156), Vector2(485, 1470), Vector2(641, 1665), Vector2(737, 1530),
	Vector2(1442, 1330), Vector2(1517, 1660), Vector2(1660, 1526), Vector2(1900, 1650),
	Vector2(2050, 1465), Vector2(2490, 1491), Vector2(2525, 1681), Vector2(1350, 1848),
	Vector2(1593, 1873), Vector2(2135, 1868), Vector2(2274, 1588),
]

var _water: ShaderMaterial
var _grass_wind: ShaderMaterial
var _tree_wind: ShaderMaterial
var _bush_wind: ShaderMaterial
var _edge_fade: GradientTexture2D
var _tree_shadow: GradientTexture2D
var _blocked_ground: Array[Dictionary] = []
var _motion_time := 0.0


func _ready() -> void:
	# The serialized texture is a snapshot of these layers for the editor and mission selector.
	texture = null
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = _surface(Kind.MEADOW, MEADOW, Vector2(222, 222))
	_edge_fade = GradientTexture2D.new()
	_edge_fade.gradient = Gradient.new()
	_edge_fade.gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	_edge_fade.gradient.colors = PackedColorArray([Color.TRANSPARENT, Color.WHITE, Color.TRANSPARENT])
	_edge_fade.fill_to = Vector2(0, 1)

	var map := get_parent()
	var roads := map.get_node("Roads") as Node2D
	var region := map.get_node("NavigationRegion2D") as Node2D
	var environment := map.get_node("Environment") as Node2D
	var map_size: Vector2 = map.get_meta("map_size")
	var map_bounds := Rect2(to_local(map.to_global(Vector2.ZERO)), map_size)
	_add_roads(roads, environment.get_node("WorkYard"), map_bounds)
	_add_fields(environment)
	var water_outline := _add_river(roads, region.get_node("River"), map_bounds)
	_add_vegetation(region, map_bounds, water_outline)


func _process(delta: float) -> void:
	_motion_time += delta
	_water.set_shader_parameter("motion_time", _motion_time)
	_grass_wind.set_shader_parameter("motion_time", _motion_time)
	_tree_wind.set_shader_parameter("motion_time", _motion_time)
	_bush_wind.set_shader_parameter("motion_time", _motion_time)


func _surface(kind: Kind, detail: Texture2D, tile_size: Vector2) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SURFACE
	result.set_shader_parameter("surface_kind", kind)
	result.set_shader_parameter("surface_texture", detail)
	result.set_shader_parameter("tile_size", tile_size)
	return result


func _outline(source: Polygon2D, world_adjustment := Transform2D.IDENTITY) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in source.polygon:
		points.append(to_local(world_adjustment * source.to_global(point + source.offset)))
	return points


func _fill(title: StringName, points: PackedVector2Array, surface: ShaderMaterial) -> void:
	var fill := Polygon2D.new()
	fill.name = title
	fill.polygon = points
	fill.antialiased = true
	fill.material = surface
	add_child(fill)


func _fill_mask(title: StringName, mask: Dictionary, map_bounds: Rect2, surface: ShaderMaterial) -> void:
	_set_edge_map(surface, mask)
	var bounds := map_bounds.intersection(mask.bounds)
	_fill(title, PackedVector2Array([
		bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y),
	]), surface)


func _set_edge_map(surface: ShaderMaterial, mask: Dictionary) -> void:
	var bounds: Rect2 = mask.bounds
	surface.set_shader_parameter("edge_map", mask.texture)
	surface.set_shader_parameter("edge_origin", bounds.position)
	surface.set_shader_parameter("edge_size", bounds.size)
	surface.set_shader_parameter("edge_texel_size", TERRAIN_DISTANCE.TEXEL_SIZE)


func _feather(points: PackedVector2Array, surface: ShaderMaterial, width: float, closed := true) -> void:
	var edge := Line2D.new()
	edge.points = points
	edge.closed = closed
	edge.width = width
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.texture = _edge_fade
	edge.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	edge.material = surface
	add_child(edge)


func _exclude(points: PackedVector2Array) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	_blocked_ground.append({"bounds": bounds, "points": points})


func _add_roads(roads: Node2D, yard: Polygon2D, map_bounds: Rect2) -> void:
	var dirt := _surface(Kind.ROAD, DIRT, Vector2(185, 185))
	var wear := _surface(Kind.RUT, DIRT, Vector2(185, 185))
	var yard_outline := _outline(yard)
	var contours: Array[PackedVector2Array] = [yard_outline]
	var rutted_roads: Array[Polygon2D] = []
	_exclude(yard_outline)
	yard.hide()

	for road in roads.get_children():
		if not road is Polygon2D or road.name in [&"RiverBanks", &"RiverWater"]:
			continue
		var points := _outline(road)
		_exclude(points)
		contours.append(_extend_to_map_edge(points, map_bounds, Vector2.AXIS_X, 0.1))
		if road.get_meta("road_width", 0.0) >= 36.0:
			rutted_roads.append(road)
	var mask := TERRAIN_DISTANCE.build(contours)
	_fill_mask(&"RoadSurface", mask, map_bounds, dirt)
	_set_edge_map(wear, mask)
	for road in rutted_roads:
		_add_ruts(road, wear)


func _extend_to_map_edge(points: PackedVector2Array, bounds: Rect2, axis: int, tolerance: float) -> PackedVector2Array:
	# Continue contours past the camera limits so open roads and river ends don't fade into grass.
	var result := points.duplicate()
	for index in range(points.size()):
		var point := points[index]
		var near_edge := absf(point[axis] - bounds.position[axis]) <= tolerance
		var far_edge := absf(point[axis] - bounds.end[axis]) <= tolerance
		if not near_edge and not far_edge:
			continue
		var previous := points[posmod(index - 1, points.size())]
		var next := points[(index + 1) % points.size()]
		var direction := point - (previous if absf(point[axis] - previous[axis]) > tolerance else next)
		if absf(direction[axis]) > tolerance:
			result[index] += direction * (TERRAIN_DISTANCE.PADDING / absf(direction[axis]))
	return result


func _add_ruts(road: Polygon2D, wear: ShaderMaterial) -> void:
	var route := PackedVector2Array()
	for point: Vector2 in road.get_meta("centerline", PackedVector2Array()):
		var at := to_local(road.to_global(point))
		if route.is_empty() or not route[-1].is_equal_approx(at):
			route.append(at)
	if route.size() < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var spacing: float = road.get_meta("road_width") * 0.24
	for index in range(route.size()):
		var forward := route[mini(index + 1, route.size() - 1)] - route[maxi(index - 1, 0)]
		var offset := forward.normalized().orthogonal() * spacing
		left.append(route[index] - offset)
		right.append(route[index] + offset)
	_feather(left, wear, 9.0, false)
	_feather(right, wear, 9.0, false)


func _add_fields(environment: Node2D) -> void:
	for plot in environment.get_children():
		if not plot.is_in_group("simulation_fields"):
			continue
		var furrows := _surface(Kind.FIELD, DIRT, Vector2(145, 145))
		var axis := Vector2.RIGHT if plot.name in [&"Garden0", &"WestField", &"SouthField"] else Vector2.DOWN
		furrows.set_shader_parameter("pattern_axis", axis)
		var points := _outline(plot)
		_feather(points, furrows, 7.0)
		_fill(plot.name, points, furrows)
		_exclude(points)
		plot.hide()


func _add_river(roads: Node2D, river: Node2D, map_bounds: Rect2) -> PackedVector2Array:
	# The river polygons were authored in the local coordinates of the physical river.
	var map := get_parent() as Node2D
	var river_transform := river.global_transform * map.global_transform.affine_inverse()
	var bank_outline := _outline(roads.get_node("RiverBanks"), river_transform)
	var bank_edge := _extend_to_map_edge(bank_outline, map_bounds, Vector2.AXIS_Y, 8.0)
	var bank_mask := TERRAIN_DISTANCE.build([bank_edge])
	_fill_mask(&"RiverBanks", bank_mask, map_bounds, _surface(Kind.BANK, DIRT, Vector2(172, 172)))

	var water_outline := _outline(roads.get_node("RiverWater"), river_transform)
	var shoreline := _extend_to_map_edge(water_outline, map_bounds, Vector2.AXIS_Y, 8.0)
	var mask := TERRAIN_DISTANCE.build([shoreline])
	_water = _surface(Kind.WATER, WATER, Vector2(190, 180))
	_fill_mask(&"RiverWater", mask, map_bounds, _water)
	_exclude(water_outline)

	var deck := roads.get_node("WoodenBridge/Deck") as Polygon2D
	var timber := _surface(Kind.DECK, TIMBER, Vector2(80, 155))
	timber.set_shader_parameter("pattern_origin", river_transform * deck.global_position)
	var deck_outline := _outline(deck, river_transform)
	_fill(&"BridgeDeck", deck_outline, timber)
	_exclude(deck_outline)
	var guardrail := _surface(Kind.RAIL, TIMBER, Vector2(110, 40))
	for rail in river.get_node("BridgeRails").get_children():
		_fill(rail.name, _outline(rail.get_node("Footprint")), guardrail)
	return water_outline


func _wind(bend: float, height: float) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = WIND
	result.set_shader_parameter("bend", bend)
	result.set_shader_parameter("flexible_height", height)
	return result


func _add_vegetation(region: Node2D, map_bounds: Rect2, water_outline: PackedVector2Array) -> void:
	_grass_wind = _wind(53.0, 250.0)
	_tree_wind = _wind(25.0, 320.0)
	_bush_wind = _wind(18.0, 170.0)
	var puddles := Node2D.new()
	puddles.name = "Puddles"
	add_child(puddles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	var map := get_parent() as Node2D
	for building in region.get_node("Buildings").find_children("Footprint", "Polygon2D"):
		_exclude(_outline(building))
	for _index in range(720):
		var position_on_map := Vector2(rng.randf_range(24.0, map_bounds.size.x - 24.0),
			rng.randf_range(36.0, map_bounds.size.y - 24.0))
		var anchor := to_local(map.to_global(position_on_map))
		if _plantable(anchor):
			_tuft(anchor, rng.randf_range(0.022, 0.058), rng.randf_range(0.66, 0.93))
	_add_reeds(water_outline, rng)

	_tree_shadow = GradientTexture2D.new()
	_tree_shadow.gradient = Gradient.new()
	_tree_shadow.gradient.colors = PackedColorArray([Color(0.04, 0.06, 0.06, 0.48), Color(0.04, 0.06, 0.06, 0.0)])
	_tree_shadow.fill = GradientTexture2D.FILL_RADIAL
	_tree_shadow.fill_from = Vector2(0.5, 0.5)
	_tree_shadow.fill_to = Vector2(1, 0.5)
	var silhouettes := Node2D.new()
	silhouettes.name = "TreeCanopies"
	silhouettes.y_sort_enabled = true
	add_child(silhouettes)

	for index in range(19):
		var x := 52.0 + index * 158.0 + rng.randf_range(-26.0, 26.0)
		if x < 2590.0 or x > 2820.0:
			_edge_tree(silhouettes, Vector2(x, rng.randf_range(21.0, 44.0)), rng)
			_edge_tree(silhouettes, Vector2(x, map_bounds.size.y + rng.randf_range(-8.0, 20.0)), rng)
	for index in range(14):
		var y := 68.0 + index * 144.0 + rng.randf_range(-28.0, 28.0)
		if absf(y - 960.0) > 64.0:
			_edge_tree(silhouettes, Vector2(rng.randf_range(-12.0, 15.0), y), rng)
		_edge_tree(silhouettes, Vector2(map_bounds.size.x + rng.randf_range(-13.0, 8.0), y), rng)

	var tree_nodes := region.get_node("Trees").get_children()
	for index in range(tree_nodes.size()):
		var tree := tree_nodes[index] as StaticBody2D
		if tree == null:
			continue
		var collider := tree.get_node("CollisionPolygon2D") as CollisionPolygon2D
		var radius := collider.polygon[0].length()
		var variant: int = TREE_ORDER[index % TREE_ORDER.size()]
		if tree.name == &"FarBankOak":
			variant = 2
		elif tree.name == &"FarBankAsh":
			variant = 1
		_tree(silhouettes, tree.name, to_local(tree.global_position), variant, maxf(84.0, radius * 4.2), 1.0)

	_add_ground_details(region, map_bounds, silhouettes, puddles)
	_blocked_ground.clear()


func _add_ground_details(region: Node2D, bounds: Rect2, vegetation: Node2D, puddles: Node2D) -> void:
	var trees := region.get_node("Trees")
	for group in [trees, region.get_node("Fences"), region.get_node("Boundaries"), region.get_node("River/BridgeRails")]:
		for footprint in group.find_children("Footprint", "Polygon2D"):
			_exclude(_outline(footprint))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	# Accepted positions and their clearances are shared by all three detail types.
	var placed: Array[Vector3] = []
	for point: Vector2 in PUDDLE_CLEARINGS:
		_place_detail(Detail.PUDDLE, puddles, bounds.position + point, bounds, placed, rng)
	var grove_details := [Detail.PUDDLE, Detail.BUSH, Detail.STONE, Detail.BUSH, Detail.STONE]
	for kind: Detail in grove_details:
		var layer := puddles if kind == Detail.PUDDLE else vegetation
		for tree: Node2D in trees.get_children():
			if kind == Detail.PUDDLE and rng.randf() > 0.35:
				continue
			var center := to_local(tree.global_position)
			for _attempt in range(4):
				var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
				var anchor := center + direction * rng.randf_range(41.0, 112.0)
				if _place_detail(kind, layer, anchor, bounds, placed, rng):
					break

	# Scatter more sparsely between groves, giving each patch of meadow a chance.
	const CELL_SIZE := 210.0
	for row in range(ceili(bounds.size.y / CELL_SIZE)):
		for column in range(ceili(bounds.size.x / CELL_SIZE)):
			if rng.randf() < 0.25:
				continue
			var cell := bounds.position + Vector2(column, row) * CELL_SIZE
			var kind := Detail.STONE if rng.randf() < 0.54 else Detail.BUSH
			for _attempt in range(3):
				var anchor := cell + Vector2(rng.randf(), rng.randf()) * CELL_SIZE
				if _place_detail(kind, vegetation, anchor, bounds, placed, rng):
					break
	_exclude(_outline(region.get_node("River/RiverStore/Footprint")))
	_add_meadow_patches(bounds, vegetation, placed)


func _add_meadow_patches(bounds: Rect2, vegetation: Node2D, placed: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	var composition := [Detail.THICKET, Detail.WILD_GROWTH, Detail.GROUND_SCATTER, Detail.WILD_GROWTH]
	for point: Vector2 in MEADOW_PATCHES:
		var center := bounds.position + point
		for kind: Detail in composition:
			for attempt in range(14):
				var anchor := center
				if kind != Detail.THICKET or attempt > 0:
					var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
					anchor += direction * rng.randf_range(28.0, 92.0)
				if _place_detail(kind, vegetation, anchor, bounds, placed, rng):
					break


func _place_detail(kind: Detail, layer: Node2D, anchor: Vector2, bounds: Rect2,
		placed: Array[Vector3], rng: RandomNumberGenerator) -> bool:
	var widths: Vector2 = DETAIL_WIDTHS[kind]
	var width := rng.randf_range(widths.x, widths.y)
	var clearance := width * 0.61 + 5.0
	if not bounds.grow(-clearance).has_point(anchor) or not _plantable(anchor, clearance):
		return false
	var meadow := kind >= Detail.THICKET
	# Allow foliage to meet in a patch while keeping each prop clear of authored features.
	var spacing_scale := 0.76 if meadow else 1.0
	var ground_aspect := Vector2(1.0, 1.22) if meadow else Vector2.ONE
	for other in placed:
		var spacing := (clearance + other.z) * spacing_scale
		var offset := (anchor - Vector2(other.x, other.y)) * ground_aspect
		if offset.length_squared() < spacing * spacing:
			return false

	var sprite := Sprite2D.new()
	sprite.name = DETAIL_NAMES[kind] + str(placed.size())
	sprite.texture = MEADOW_DETAILS if meadow else GROUND_DETAILS
	sprite.region_enabled = true
	var variant := rng.randi_range(0, 2)
	var cell: Rect2 = DETAIL_REGIONS[kind][variant]
	sprite.region_rect = cell
	sprite.position = anchor
	sprite.scale = Vector2.ONE * (width / cell.size.x)
	sprite.flip_h = rng.randf() < 0.5
	var shade := rng.randf_range(0.80, 0.97)
	sprite.modulate = Color(shade * 0.95, shade * 1.02, shade)
	var flat := kind == Detail.GROUND_SCATTER or (kind == Detail.WILD_GROWTH and variant == 2)
	if kind == Detail.PUDDLE:
		sprite.rotation = rng.randf_range(-0.48, 0.48)
	else:
		sprite.offset.y = -cell.size.y * (0.12 if flat else 0.29)
	if kind == Detail.BUSH or kind == Detail.THICKET or (kind == Detail.WILD_GROWTH and not flat):
		sprite.material = _bush_wind
	layer.add_child(sprite)
	placed.append(Vector3(anchor.x, anchor.y, clearance))
	return true


func _add_reeds(water_outline: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	for index in range(water_outline.size()):
		var start := water_outline[index]
		var finish := water_outline[(index + 1) % water_outline.size()]
		var segment := finish - start
		if absf(segment.y) < 25.0:
			continue
		var outward := segment.normalized().orthogonal()
		if Geometry2D.is_point_in_polygon(start.lerp(finish, 0.5) + outward * 4.0, water_outline):
			outward = -outward
		var clusters := maxi(1, roundi(segment.length() / 51.0))
		for cluster in range(clusters):
			var center := start.lerp(finish, (float(cluster) + rng.randf_range(0.16, 0.84)) / float(clusters))
			for _blade in range(rng.randi_range(1, 3)):
				var anchor := center + outward * rng.randf_range(4.0, 13.0)
				anchor += segment.normalized() * rng.randf_range(-9.0, 9.0)
				if _plantable(anchor):
					_tuft(anchor, rng.randf_range(0.031, 0.068), rng.randf_range(0.76, 0.99))


func _tuft(anchor: Vector2, size: float, shade: float) -> void:
	var tuft := Sprite2D.new()
	tuft.texture = GRASS
	tuft.material = _grass_wind
	tuft.centered = false
	tuft.offset = -GRASS_ROOT
	tuft.position = anchor
	tuft.scale = Vector2(size, size * 0.85)
	tuft.modulate = Color(shade * 0.94, shade, shade)
	add_child(tuft)


func _plantable(anchor: Vector2, clearance := 0.0) -> bool:
	for shape in _blocked_ground:
		var bounds: Rect2 = shape.bounds
		if not bounds.grow(clearance).has_point(anchor):
			continue
		var points: PackedVector2Array = shape.points
		if Geometry2D.is_point_in_polygon(anchor, points):
			return false
		if clearance > 0.0:
			for index in range(points.size()):
				var nearest := Geometry2D.get_closest_point_to_segment(
					anchor, points[index], points[(index + 1) % points.size()])
				if anchor.distance_squared_to(nearest) < clearance * clearance:
					return false
	return true


func _edge_tree(layer: Node2D, map_point: Vector2, rng: RandomNumberGenerator) -> void:
	var map := get_parent() as Node2D
	var anchor := to_local(map.to_global(map_point))
	_tree(layer, &"BorderTree", anchor, rng.randi_range(0, 3), rng.randf_range(76.0, 119.0), 0.82)


func _tree(layer: Node2D, title: StringName, anchor: Vector2, variant: int, width: float, shade: float) -> void:
	var tree_art := Node2D.new()
	tree_art.name = title
	tree_art.position = anchor
	layer.add_child(tree_art)
	var shadow := Sprite2D.new()
	shadow.texture = _tree_shadow
	shadow.scale = Vector2(width * 0.74, width * 0.28) / _tree_shadow.get_size()
	shadow.position = Vector2(3, -3)
	tree_art.add_child(shadow)
	var crown := Sprite2D.new()
	var region: Rect2 = TREE_REGIONS[variant]
	crown.texture = TREES
	crown.region_enabled = true
	crown.region_rect = region
	crown.centered = false
	crown.offset = -TRUNK_ORIGINS[variant]
	crown.scale = Vector2(1.0, 0.87) * width / region.size.x
	crown.modulate = Color(shade, shade, shade)
	crown.material = _tree_wind
	tree_art.add_child(crown)
