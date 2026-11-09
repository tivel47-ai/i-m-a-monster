extends RefCounted
## Default church patrol branches shared by the mission and the map builder.
static func navigable(mesh: NavigationPolygon, point: Vector2) -> Vector2:
	var vertices := mesh.get_vertices()
	var closest := point
	var distance := INF
	for i in range(mesh.get_polygon_count()):
		var outline := PackedVector2Array()
		for index in mesh.get_polygon(i): outline.append(vertices[index])
		if Geometry2D.is_point_in_polygon(point, outline): return point
		for j in range(outline.size()):
			var candidate := Geometry2D.get_closest_point_to_segment(point, outline[j], outline[(j+1)%outline.size()])
			if candidate.distance_squared_to(point) < distance:
				distance = candidate.distance_squared_to(point)
				closest = candidate
	return closest

static func section(map: Node2D, region: NavigationRegion2D, title: String, start: Vector2, end: Vector2) -> PackedVector2Array:
	var road := map.get_node_or_null("Roads/" + title + "0")
	if road == null: return PackedVector2Array()
	var points: PackedVector2Array = road.get_meta("centerline", PackedVector2Array())
	if points.is_empty(): return PackedVector2Array()
	var first := 0
	var last := 0
	for i in range(points.size()):
		if points[i].distance_to(start) < points[first].distance_to(start): first = i
		if points[i].distance_to(end) < points[last].distance_to(end): last = i
	var result := PackedVector2Array()
	var step := 1 if last >= first else -1
	var to_region := region.transform.affine_inverse()
	for i in range(first, last + step, step):
		var point := region.transform * navigable(region.navigation_polygon, to_region * points[i])
		if result.is_empty() or result[-1].distance_to(point) > 1: result.append(point)
	return result

static func round_trip(route: PackedVector2Array) -> PackedVector2Array:
	var result := route.duplicate()
	for i in range(route.size() - 2, -1, -1): result.append(route[i])
	return result

static func route_for(map: Node2D, slot: int) -> PackedVector2Array:
	var region := map.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	if region == null or region.navigation_polygon == null: return PackedVector2Array()
	if region.navigation_polygon.get_polygon_count() == 0: return PackedVector2Array()
	var start := Vector2(1420,557)
	if slot != 0:
		var west := round_trip(section(map, region, "NorthLane", start, Vector2(1100,555)))
		west.append_array(round_trip(section(map, region, "ChurchLane", start, Vector2(1480,720))))
		return map.global_transform * west

	var east := section(map, region, "NorthLane", start, Vector2(1778,496))
	var access := section(map, region, "CemeteryAccess", start, Vector2(1560,420))
	var north := access.duplicate()
	north.append_array(section(map, region, "CemeteryWest", Vector2(1560,420), Vector2(1560,200)))
	var cemetery_east := access.duplicate()
	cemetery_east.append_array(section(map, region, "CemeteryEast", Vector2(1560,420), Vector2(1850,420)))
	var first := round_trip(east)
	first.append_array(round_trip(north))
	first.append_array(round_trip(cemetery_east))
	return map.global_transform * first
