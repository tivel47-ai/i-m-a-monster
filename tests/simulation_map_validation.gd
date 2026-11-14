# Godot --headless --path . --script tests/simulation_map_validation.gd --fixed-fps 60
extends SceneTree

var failures := 0
var map: Node2D
var nav: RID
var units: Array[Node]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func body_clear(at: Vector2, shape: Shape2D = null) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape if shape != null else units[0].get_node("CollisionShape2D").shape
	query.transform = Transform2D(0,at)
	query.collision_mask = 1
	return map.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func clear_path(path: PackedVector2Array) -> bool:
	for i in range(1,path.size()):
		var length := path[i-1].distance_to(path[i])
		for sample in range(ceili(length/8.0)+1):
			if not body_clear(path[i-1].lerp(path[i],minf(sample*8.0/maxf(length,0.01),1.0))): return false
	return not path.is_empty()

func path_to(start: Vector2, goal: Vector2) -> PackedVector2Array:
	return NavigationServer2D.map_get_path(nav,start,goal,true)

func reset_units(at: Vector2) -> void:
	for i in range(units.size()):
		units[i].issue_player_area_hold_order()
		units[i].position = at+Vector2(0,(i-1)*35)
		units[i].set_selected(true)

func run() -> void:
	seed(104729)
	root.size = Vector2i(1280,720)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units = get_nodes_in_group("player_units")
	for resident in map.villagers: resident.autonomous_movement_enabled = false
	await frames(5)
	nav = map.get_world_2d().navigation_map
	check(map.get_meta("map_size")==Vector2(3000,2000) and map.get_node("Camera2D").map_bounds==Rect2(0,0,3000,2000),"World and camera bounds are 3000 x 2000")
	check(map.total_residents==44 and units.size()==3 and map.mission_state==map.MissionState.ACTIVE,"Forty-four counted residents and three playable zombies initialize")
	var roles := {"peasant":0,"artisan":0,"guard":0,"priest":0,"priest_guard":0}
	var valid_configuration := true
	for resident in map.villagers:
		roles[resident.get_meta("village_role")] += 1
		valid_configuration = valid_configuration and resident.get_node_or_null(resident.home_point_path) is Marker2D and resident.get_node_or_null(resident.points_of_interest_path)!=null and not resident.activity_zone_paths.is_empty() and not resident.marker_activity_fallback_enabled
	check(roles=={"peasant":26,"artisan":5,"guard":10,"priest":1,"priest_guard":2},"Role allocation is 26 / 5 / 10 / 1 / 2 with dedicated priest protectors")
	check(valid_configuration,"Every NPC has zone assignments and preserved functional shelter references")
	var types := {"small":0,"large":0,"square":0,"L":0,"farmhouse":0}
	for house in get_nodes_in_group("simulation_houses"):
		types[house.get_meta("building_type")] += 1
		check(house.get_node("Footprint").polygon==house.get_node("CollisionPolygon2D").polygon,"Exact visible/collision contour: "+house.name)
	check(types=={"small":4,"large":3,"square":2,"L":2,"farmhouse":1},"Exactly twelve homes with required shape distribution")
	for unit in units+map.villagers:
		check(NavigationServer2D.map_get_closest_point(nav,unit.global_position).distance_to(unit.global_position)<1 and body_clear(unit.global_position),"Valid spawn with full zombie-body clearance: "+unit.name)
	var square := Vector2(1520,947)
	for point in map.get_node("VillagePointsOfInterest").get_children():
		var path := path_to(square,point.global_position)
		check(not path.is_empty() and path[-1].distance_to(point.global_position)<1 and clear_path(path),"Reachable, physically clear activity point: "+point.name)
	var mesh: NavigationPolygon = map.get_node("NavigationRegion2D").navigation_polygon
	var disconnected: Array[int] = []
	var blocked: Array[int] = []
	for i in range(mesh.get_polygon_count()):
		var center := Vector2.ZERO
		var indices := mesh.get_polygon(i)
		for index in indices: center += mesh.vertices[index]
		center /= indices.size()
		var path := path_to(square,center)
		# Engine endpoint precision on very long, thin edge polygons can exceed
		# one unit; two is still below existing villager/zombie arrival tolerances.
		if path.is_empty() or path[-1].distance_to(center)>2:
			disconnected.append(i)
			print("Disconnected nav polygon ",i," center=",center," path endpoint=",path[-1] if not path.is_empty() else Vector2.INF)
		elif not clear_path(path): blocked.append(i)
	check(disconnected.is_empty(),"All navmesh polygons connect to square; disconnected="+str(disconnected))
	check(blocked.is_empty(),"Paths to all polygon centers clear real zombie body; blocked="+str(blocked))
	for at in [Vector2(2700,200),Vector2(2715,460),Vector2(2705,1430),Vector2(2770,1680)]:
		check(not body_clear(at) and NavigationServer2D.map_get_closest_point(nav,at).distance_to(at)>25,"Deep water physically and navigationally excluded: "+str(at))
	var bridge_path := path_to(Vector2(2500,900),Vector2(2880,900))
	var crosses_deck := false
	for i in range(1,bridge_path.size()):
		var a := bridge_path[i-1]
		var b := bridge_path[i]
		if minf(a.x,b.x)<=2740 and maxf(a.x,b.x)>=2740 and absf(b.x-a.x)>0.01:
			var y := lerpf(a.y,b.y,(2740-a.x)/(b.x-a.x))
			if y>1124 and y<1236: crosses_deck = true
	check(not bridge_path.is_empty() and bridge_path[-1].distance_to(Vector2(2880,900))<1 and crosses_deck and clear_path(bridge_path),"Far-bank route crosses only the bridge deck")
	# L notch remains open, unlike an oversized bounding rectangle.
	var l_house := map.get_node("NavigationRegion2D/Buildings/Residential/Cottage10") as Node2D
	check(body_clear(l_house.to_global(Vector2(52,45))),"L-shaped house leaves its visible notch physically open")
	var around_l := path_to(l_house.to_global(Vector2(125,-70)),l_house.to_global(Vector2(-125,80)))
	check(clear_path(around_l),"Existing navigation routes around actual L contour")
	var target := Node2D.new()
	map.add_child(target)
	units[0].position = Vector2(620,360)
	target.position = Vector2(620,580)
	await frames(2)
	check(not units[0]._has_line_of_sight(target),"House blocks existing zombie sight ray")
	var detector: Node = map.villagers[0].threat_detection
	map.villagers[0].position = Vector2(620,540)
	units[0].position = Vector2(620,405)
	await frames(2)
	check(not detector._is_visible_target(units[0]),"Existing villager detection ray is blocked by house within detection radius")
	units[0].position = Vector2(1500,920)
	target.position = Vector2(1560,960)
	check(units[0]._has_line_of_sight(target),"Square preserves open sight")
	target.queue_free()
	# First isolate movement from encounters and civilian traffic.
	for resident in map.villagers: resident.process_mode = Node.PROCESS_MODE_DISABLED
	for unit in units:
		unit.get_node("AggroArea").monitoring = false
		unit.aggro_candidates.clear()
		unit.aggro_target = null
	# Real perception and escape on cultivated, traversable terrain.
	var farmer: Node2D = map.villagers[12]
	farmer.process_mode = Node.PROCESS_MODE_INHERIT
	farmer.autonomous_movement_enabled = true
	farmer.position = Vector2(300,1510)
	farmer.threat_detection.recognition_delay_min = 0.1
	farmer.threat_detection.recognition_delay_max = 0.1
	var response: Node = farmer.threat_reaction
	response.flee_weight = 1
	response.shelter_weight = 0
	response.warning_weight = 0
	response.frozen_weight = 0
	units[0].issue_player_area_hold_order()
	units[0].position = Vector2(180,1510)
	await frames(15)
	check((response.episode_active and response.reaction_state==response.Reaction.FLEEING) or not farmer.escort.reporter.report.is_empty(),
		"Threat in open field triggers immediate flight or the firsthand guard-report route")
	await frames(60)
	check(farmer.position.distance_to(units[0].position)>160 and body_clear(farmer.position),"Real farmer escapes across cultivated ground without crop collision")
	farmer.process_mode = Node.PROCESS_MODE_DISABLED
	# Actual one-hop warning near the workshops, with a remote district listener.
	var speaker: Node2D = map.villagers[19]
	var listener: Node2D = map.villagers[23]
	speaker.threat_reaction.episode_active = true
	speaker.threat_reaction.warning_sent = true
	speaker.threat_reaction.report_based = false
	speaker.warning_attempted.emit(speaker,Vector2(2130,800))
	check(listener.local_warning.has_report() and not map.villagers[24].local_warning.has_report(),"Artisan warning reaches nearby NPC but not distant guard district")
	speaker.threat_reaction.cancel_response()
	for resident in map.villagers: resident.local_warning.clear_report()
	reset_units(Vector2(2600,1180))
	await frames(3)
	units[0].set_selected(true)
	units[1].set_selected(false)
	units[2].set_selected(false)
	map._issue_area_move_order(Vector2(2880,1180))
	await frames(330)
	check(units[0].last_move_reached and units[0].position.x>2850,"Real zombie crosses bridge with existing point order")
	reset_units(Vector2(2580,1180))
	await frames(3)
	map._issue_area_move_order(Vector2(2890,1180))
	var distinct: Array[Vector2] = []
	for unit in units:
		check(unit.has_player_order and not distinct.has(unit.target_position),"Bridge group receives distinct existing area-order destination")
		distinct.append(unit.target_position)
	await frames(700)
	for unit in units: check(unit.last_move_reached and unit.position.x>2820,"Real group member reaches far bank: %s -> %s, order=%s"%[unit.position,unit.target_position,unit.has_player_order])
	# Peaceful observation: civilians resume activities; guards patrol or remain on duty.
	reset_units(Vector2(100,100))
	var origins: Array[Vector2] = []
	var travelled: Array[float] = []
	for resident in map.villagers:
		resident.process_mode = Node.PROCESS_MODE_INHERIT
		resident.autonomous_movement_enabled = true
		origins.append(resident.position)
		travelled.append(0.0)
	var arrivals := {}
	var no_wall_crossing := true
	for tick in range(120):
		await frames(30)
		for i in range(map.villagers.size()):
			var resident: Node2D = map.villagers[i]
			travelled[i] = maxf(travelled[i],origins[i].distance_to(resident.position))
			if resident.is_performing_activity: arrivals[i]=true
			no_wall_crossing = no_wall_crossing and body_clear(resident.position,resident.get_node("CollisionShape2D").shape)
	var moving_civilians := 0
	var moving_guards := 0
	var stationed_guards := 0
	for i in range(map.villagers.size()):
		var resident: Node = map.villagers[i]
		if resident.priest_guard != null: continue
		if resident.guard_patrol == null:
			if travelled[i]>30: moving_civilians+=1
		elif travelled[i]>30:
			moving_guards+=1
		elif resident.guard_patrol.state==resident.guard_patrol.State.POST and resident.guard_patrol.is_near_post():
			stationed_guards+=1
		else:
			print("Inactive guard: ",resident.name," state=",resident.guard_patrol.state," distance=",travelled[i])
	check(moving_civilians==32 and moving_guards>=9 and moving_guards+stationed_guards==10,"All 32 civilians and at least nine guards actually travel in 60 seconds; remaining guard must be on post duty: civilians=%s patrol=%s stationed=%s"%[moving_civilians,moving_guards,stationed_guards])
	check(arrivals.size()>15 and no_wall_crossing,"Peaceful activity arrivals and no static-obstacle overlap; arrivals="+str(arrivals.size()))
	# Existing mission threshold and idempotent counts on larger population.
	for i in range(35): map._on_resident_died(map.villagers[i])
	check(map.mission_state==map.MissionState.ACTIVE,"35 of 44 does not complete 80 percent objective")
	map._on_resident_died(map.villagers[35])
	map._on_resident_died(map.villagers[35])
	check(map.killed_residents==36 and map.mission_state==map.MissionState.WON,"36 of 44 completes objective with duplicate protection")
	map.queue_free()
	await frames(3)
	var original: Node2D = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(original)
	await frames(4)
	check(original.total_residents==4 and get_nodes_in_group("player_units").size()==3,"Original test scene remains independently loadable")
	original.queue_free()
	await frames(3)
	print("Simulation map validation failures: ",failures)
	quit(1 if failures else 0)
