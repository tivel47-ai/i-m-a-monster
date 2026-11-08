extends RefCounted
## Shared authoring helper: serialized mission and village builder use identical routes.
static func navigable(map: Node, point: Vector2) -> Vector2:
	var mesh: NavigationPolygon = map.get_node("NavigationRegion2D").navigation_polygon
	# The builder installs the existing mesh after population.
	if mesh == null: mesh = load("res://scenes/village_simulation_navigation.tres")
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

static func section(map: Node, title: String, start: Vector2, end: Vector2) -> PackedVector2Array:
	var road = map.get_node("Roads/" + title + "0")
	var points: PackedVector2Array = road.get_meta("centerline")
	var first := 0
	var last := 0
	for i in range(points.size()):
		if points[i].distance_to(start) < points[first].distance_to(start): first = i
		if points[i].distance_to(end) < points[last].distance_to(end): last = i
	var result := PackedVector2Array()
	var step := 1 if last >= first else -1
	for i in range(first, last + step, step):
		var point := navigable(map, points[i])
		if result.is_empty() or result[-1].distance_to(point) > 1: result.append(point)
	return result

static func round_trip(route: PackedVector2Array) -> PackedVector2Array:
	var result := route.duplicate()
	for i in range(route.size() - 2, -1, -1): result.append(route[i])
	return result

static func install(map: Node) -> void:
	var start := Vector2(1420,557)
	var east := section(map,"NorthLane",start,Vector2(1778,496))
	var access := section(map,"CemeteryAccess",start,Vector2(1560,420))
	var north := access.duplicate()
	north.append_array(section(map,"CemeteryWest",Vector2(1560,420),Vector2(1560,200)))
	var cemetery_east := access.duplicate()
	cemetery_east.append_array(section(map,"CemeteryEast",Vector2(1560,420),Vector2(1850,420)))
	var first := round_trip(east)
	first.append_array(round_trip(north))
	first.append_array(round_trip(cemetery_east))
	var second := round_trip(section(map,"NorthLane",start,Vector2(1100,555)))
	second.append_array(round_trip(section(map,"ChurchLane",start,Vector2(1480,720))))
	for i in range(2):
		var title := "PriestGuard" + str(i + 1)
		var route: PackedVector2Array = first if i == 0 else second
		if map.has_node("Villagers/" + title):
			var existing = map.get_node("Villagers/" + title).get_node_or_null("PriestGuard")
			if existing != null and existing.patrol_points.is_empty(): existing.patrol_points = route
			continue
		var actor = load("res://scenes/priest_guard.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		actor.name = title
		map.get_node("Villagers").add_child(actor)
		actor.owner = map
		actor.position = Vector2(1440,557) if i == 0 else Vector2(1350,580)
		map.set_editable_instance(actor,true)
		actor.get_node("PriestGuard").slot = i
		actor.get_node("PriestGuard").patrol_points = route
