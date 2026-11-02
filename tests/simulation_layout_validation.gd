# Godot --headless --path . --script tests/simulation_layout_validation.gd --fixed-fps 60
extends "res://tests/simulation_map_validation.gd"

func area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(polygon.size()): result += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(result)*0.5

func world_polygon(node: Polygon2D) -> PackedVector2Array:
	return node.global_transform*node.polygon

func boundary_distance(at: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for i in range(polygon.size()):
		distance = minf(distance,at.distance_to(Geometry2D.get_closest_point_to_segment(at,polygon[i],polygon[(i+1)%polygon.size()])))
	return distance

func run() -> void:
	seed(221102)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units = get_nodes_in_group("player_units")
	for resident in map.villagers: resident.autonomous_movement_enabled = false
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring = false
		unit.aggro_candidates.clear()
	await frames(5)
	nav = map.get_world_2d().navigation_map
	var roads: Array[Polygon2D] = []
	for child in map.get_node("Roads").get_children():
		if child is Polygon2D and child.color in [Color("71654f"),Color("645d47")]: roads.append(child)
	var cemetery_separated := true
	var north_street := world_polygon(map.get_node("Roads/NorthLane0"))
	for path_name in ["CemeteryWest0","CemeteryNorth0","CemeteryEast0"]:
		# Check the actual road surfaces including their curved edges, not anchors.
		for expanded_path in Geometry2D.offset_polygon(world_polygon(map.get_node("Roads/"+path_name)),20.0):
			if not Geometry2D.intersect_polygons(expanded_path,north_street).is_empty(): cemetery_separated = false
	check(cemetery_separated,"Cemetery loop has at least 20 units of ground separating it from the main northern road")
	var conflicts: Array[String] = []
	for road in roads:
		for building in map.get_node("NavigationRegion2D").find_children("*","StaticBody2D",true,false):
			if not building.has_meta("building_type"): continue
			for intersection in Geometry2D.intersect_polygons(world_polygon(road),world_polygon(building.get_node("Footprint"))):
				if area(intersection)>0.5:
					conflicts.append(str(road.name)+" / "+str(building.name)+" area="+str(snappedf(area(intersection),0.1)))
	check(conflicts.is_empty(),"Road surfaces never overlap buildings: "+str(conflicts))
	var crop_conflicts: Array[String] = []
	for plot in get_nodes_in_group("simulation_fields"):
		for road in roads:
			for intersection in Geometry2D.intersect_polygons(world_polygon(plot),world_polygon(road)):
				if area(intersection)>0.5: crop_conflicts.append(str(plot.name)+" / "+str(road.name))
		for building in map.get_node("NavigationRegion2D").find_children("*","StaticBody2D",true,false):
			if not building.has_meta("building_type"): continue
			for intersection in Geometry2D.intersect_polygons(world_polygon(plot),world_polygon(building.get_node("Footprint"))):
				if area(intersection)>0.5: crop_conflicts.append(str(plot.name)+" / "+str(building.name))
	check(crop_conflicts.is_empty(),"Cultivated plots never overlap roads or buildings: "+str(crop_conflicts))
	var fence_conflicts: Array[String] = []
	for fence in get_nodes_in_group("simulation_fences"):
		var enclosure: Node2D = map.get_node_or_null(fence.get_meta("enclosure",""))
		check(enclosure!=null and enclosure.is_in_group("simulation_enclosures"),"Fence belongs to a named enclosure: "+str(fence.get_path()))
		if enclosure==null: continue
		var boundary: PackedVector2Array = world_polygon(enclosure) if enclosure is Polygon2D else enclosure.global_transform*enclosure.get_meta("boundary")
		check(boundary_distance(fence.global_position,boundary)<96,"Fence follows its plot boundary: "+str(fence.get_path()))
		var footprint := world_polygon(fence.get_node("Footprint"))
		for plot in get_nodes_in_group("simulation_fields"):
			for intersection in Geometry2D.intersect_polygons(footprint,world_polygon(plot)):
				if area(intersection)>0.5: fence_conflicts.append(str(fence.get_path())+" / "+str(plot.name))
		for other in get_nodes_in_group("simulation_solids"):
			if other==fence: continue
			var joint := false
			if other.is_in_group("simulation_fences") and other.get_meta("enclosure")==fence.get_meta("enclosure"):
				for a in fence.get_meta("ends"):
					for b in other.get_meta("ends"):
						if a.distance_to(b)<0.1: joint = true
			if joint: continue # Boards meet at the intended corner posts.
			for intersection in Geometry2D.intersect_polygons(footprint,world_polygon(other.get_node("Footprint"))):
				if area(intersection)>0.5: fence_conflicts.append(str(fence.get_path())+" / "+str(other.name))
	check(fence_conflicts.is_empty(),"Enclosure fences clear crops, buildings, trees and other obstacles: "+str(fence_conflicts))
	var vegetables: Polygon2D = map.get_node("Environment/Vegetables")
	var plot_bounds := Rect2(vegetables.polygon[0],Vector2.ZERO)
	for vertex in vegetables.polygon: plot_bounds = plot_bounds.expand(vertex)
	check(vegetables.polygon.size()==4 and is_equal_approx(area(vegetables.polygon),plot_bounds.get_area()) and plot_bounds.size.x>=2*plot_bounds.size.y and area(vegetables.polygon)>30000 and plot_bounds.position.y>=1800,"Southwest plot is a larger elongated rectangle below the farm road")
	var prop_conflicts: Array[String] = []
	for road in roads:
		for solid in get_nodes_in_group("simulation_solids"):
			if solid.has_meta("building_type") or "River" in str(solid.get_path()) or "Boundaries" in str(solid.get_path()): continue
			# Roads are covered by the square here; its well and bell intentionally
			# stand on the plaza surface, with navigation routing around them.
			if Geometry2D.is_point_in_polygon(solid.global_position,world_polygon(map.get_node("Roads/Square"))): continue
			for intersection in Geometry2D.intersect_polygons(world_polygon(road),world_polygon(solid.get_node("Footprint"))):
				if area(intersection)>0.5: prop_conflicts.append(str(road.name)+" / "+str(solid.name))
	check(prop_conflicts.is_empty(),"Roads outside the square also clear graves, trees, fences and yard props: "+str(prop_conflicts))
	var connected_roads: Array[Polygon2D] = [map.get_node("Roads/MainStreet0")]
	var expanded := true
	while expanded:
		expanded = false
		for road in roads:
			if connected_roads.has(road): continue
			for other in connected_roads:
				if not Geometry2D.intersect_polygons(world_polygon(road),world_polygon(other)).is_empty():
					connected_roads.append(road)
					expanded = true
					break
	check(connected_roads.size()==roads.size(),"All visible road surfaces form one connected network")
	var dangling: Array[String] = []
	for road in roads:
		if not road.has_meta("centerline"):
			dangling.append(str(road.name)+" missing authored endpoints")
			continue
		var centerline: PackedVector2Array = road.get_meta("centerline")
		for endpoint in [centerline[0],centerline[-1]]:
			var connected: bool = endpoint.x<=0.1 or endpoint.y<=0.1 or endpoint.x>=2999.9 or endpoint.y>=1999.9
			for other in roads:
				if other!=road and Geometry2D.is_point_in_polygon(endpoint,world_polygon(other)): connected = true
			for field in get_nodes_in_group("simulation_fields"):
				if boundary_distance(endpoint,world_polygon(field))<=12: connected = true
			if Geometry2D.is_point_in_polygon(endpoint,world_polygon(map.get_node("Roads/Square"))): connected = true
			for building in map.get_node("NavigationRegion2D").find_children("*","StaticBody2D",true,false):
				if building.has_node("Door") and endpoint.distance_to(building.get_node("Door").to_global(Vector2(0,4)))<=6: connected = true
			if not connected: dangling.append(str(road.name)+" "+str(endpoint))
	check(dangling.is_empty(),"Every road end joins another road, square, door, field or map entrance: "+str(dangling))
	check(not map.has_node("ResidentRoutes"), "Obsolete per-resident movement marker containers are removed")
	var zones := map.get_node("ActivityZones").get_children()
	check(zones.size() < 75 and zones.size() > 30, "Activity territories are shared rather than 150 individual replacements")
	for zone in zones:
		var valid: bool = zone is ActivityZone2D and zone.has_valid_polygon()
		if valid and not zone.location_path.is_empty(): valid = zone.get_node_or_null(zone.location_path) != null
		check(valid, "Authored activity polygon and location are valid: " + str(zone.name))
	# Zone dynamics and complete activity transitions are validated separately by
	# simulation_zones_validation; layout checks retain all geography assertions above.
	map.queue_free()
	await frames(3)
	print("Simulation layout validation failures: ",failures)
	quit(1 if failures else 0)
