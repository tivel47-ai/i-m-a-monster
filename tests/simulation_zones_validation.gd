# Godot --headless --path . --script tests/simulation_zones_validation.gd --fixed-fps 60
extends "res://tests/simulation_map_validation.gd"


func run() -> void:
	seed(3303)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units = get_nodes_in_group("player_units")
	for actor in map.villagers:
		actor.autonomous_movement_enabled = false
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring = false
		unit.aggro_candidates.clear()
	await frames(5)
	nav = map.get_world_2d().navigation_map
	await check_assignments_and_destinations()
	await check_preferences()
	await check_unavailable()
	await check_bridge_travel()
	await observe_village(180)
	map.queue_free()
	await frames(3)
	print("Simulation zones validation failures: ", failures)
	quit(1 if failures else 0)


func zone_list(actor: Node) -> Array[ActivityZone2D]:
	var zones: Array[ActivityZone2D] = []
	for path in actor.activity_zone_paths:
		var zone := actor.get_node_or_null(path) as ActivityZone2D
		if zone != null: zones.append(zone)
	return zones


func check_assignments_and_destinations() -> void:
	var counts := [0,0,0,0]
	var geometry := true
	var generated: Array[Node] = map.get_node("ActivityZones").get_children()
	for index in range(generated.size()):
		var zone: ActivityZone2D = generated[index]
		zone._random.seed = 330300 + index
		counts[zone.activity] += 1
		geometry = geometry and zone.has_valid_polygon() and not (zone as Node) is CollisionObject2D and not zone.debug_enabled
	check(counts == [14,21,9,8] and geometry, "52 editable non-physical zones: 14 HOME, 21 WORK, 9 SOCIAL, 8 WANDER")
	check(not map.has_node("ResidentRoutes") and map.get_node("VillagePointsOfInterest").get_child_count() == 43, "All 150 obsolete individual markers are gone; 43 functional approaches remain")
	var used := {}
	var sampled := {}
	for index in range(map.villagers.size()):
		var actor = map.villagers[index]
		var role: String = actor.get_meta("village_role")
		var activities := [false,false,false,false]
		var correct: bool = actor.home_duration == Vector2(12,24) and actor.work_duration == Vector2(18,36) and actor.move_speed == 35
		correct = correct and not actor.marker_activity_fallback_enabled and actor.private_shelter_marker() is Marker2D
		if role == "artisan": correct = correct and actor.home_weight == 0.0 and actor.private_shelter_marker() == actor.get_node_or_null(actor.work_point_path)
		for zone in zone_list(actor):
			correct = correct and zone.allows_resident(actor)
			if role in ["peasant", "artisan"] and zone.activity == actor.Activity.SOCIAL:
				correct = correct and zone.zone_id in [&"SocialSquare", &"SocialChurch", &"SocialTavern"]
			activities[zone.activity] = true
			used[zone.zone_id] = true
			if zone.activity == actor.Activity.HOME:
				var expected := "Home%02d" % (index%12+1) if index<24 else ("HomeGuardPost" if index<29 else "HomeChapel")
				correct = correct and str(zone.zone_id) == expected
			if zone.activity == actor.Activity.WORK:
				correct = correct and (str(zone.zone_id) == "Work"+str(actor.get_meta("work_site")) or (role == "artisan" and zone.zone_id == &"WorkWell") or str(zone.zone_id).begins_with("WorkGarden") or (role == "guard" and zone.zone_id == &"WorkGuardRoad") or (role == "priest" and zone.zone_id == &"WorkCemetery"))
			if sampled.has(zone.zone_id): continue
			var safe := true
			var local_usable := false
			for attempt in range(8):
				# Use the actual peaceful-AI contract: interior arrival margin and
				# a physically checked <=5-unit start connector (Stage 2).
				var result := zone.sample_destination(actor, PackedVector2Array(), null,
					actor.arrival_tolerance+1.0, actor.arrival_tolerance+1.0)
				safe = safe and result.size() == 1
				if result.is_empty(): continue
				var point := result[0]
				var path := path_to(actor.position,point)
				safe = safe and zone.contains_world_point(point) and body_clear(point,actor.get_node("CollisionShape2D").shape) and not path.is_empty() and path[-1].distance_to(point)<=1 and clear_path(path)
				var origin: Vector2 = actor.position
				actor.position=point
				var local_point := zone.sample_local_destination(actor,zone.local_move_radius,12)
				local_usable = local_usable or not local_point.is_empty()
				actor.position=origin
			check(local_usable,"Authored territory supports an actual contained local navigation route: "+str(zone.zone_id))
			check(safe,"Eight reachable collision-free destinations in authored zone: "+str(zone.zone_id))
			sampled[zone.zone_id] = true
		check(correct and activities == ([false,true,true,true] if role == "artisan" else [true,true,true,true]), "Resident %d has correct home/work, social/walk access and functional shelter: %s" % [index,str(actor.name)])
	check(used.size()==52 and sampled.size()==52, "Every generated territory has an assigned resident and validated usable destinations")
	var social_users := {}
	for actor in map.villagers:
		for zone in zone_list(actor):
			if zone.activity == 2: social_users[zone.zone_id] = int(social_users.get(zone.zone_id,0)) + 1
	check(social_users.size()==9 and int(social_users.get(&"SocialSquare",0))==30, "Public gathering areas are shared by multiple actual residents")


func check_preferences() -> void:
	var actor = map.villagers[0]
	var near: ActivityZone2D = map.get_node("ActivityZones/SocialNorthwest")
	var far: ActivityZone2D = map.get_node("ActivityZones/SocialChurch")
	var candidates := [{"zone":near,"point":near.global_position},{"zone":far,"point":far.global_position}]
	var same_district := 0
	for attempt in range(2000):
		var choice: Dictionary = actor._choose_activity_target(candidates)
		if choice.zone == near: same_district += 1
	check(same_district>1500 and same_district<2000 and actor._zone_preference_weight(near)>actor._zone_preference_weight(far),
		"Familiar nearby district is preferred but distant valid visits remain possible: "+str(same_district)+" / 2000")
	var saved_district: StringName = actor.preferred_district
	var saved_distance: float = actor.nearby_zone_distance
	actor.preferred_district = &""
	actor.nearby_zone_distance = 0
	var neutral := 0
	for attempt in range(2000):
		if actor._choose_activity_target(candidates).zone == near: neutral += 1
	check(neutral>850 and neutral<1150, "Inspector can disable territorial preferences without removing candidates")
	actor.preferred_district = saved_district
	actor.nearby_zone_distance = saved_distance
	# Real path from a residence to a distant field may leave BOTH activity polygons.
	var home: ActivityZone2D = map.get_node("ActivityZones/Home01")
	var work: ActivityZone2D = map.get_node("ActivityZones/WorkFieldsWest")
	var a := home.sample_destination(actor)[0]
	var b := work.sample_destination(actor)[0]
	var path := path_to(a,b)
	var outside := false
	for vertex in path:
		outside = outside or (not home.contains_world_point(vertex) and not work.contains_world_point(vertex))
	check(not path.is_empty() and clear_path(path) and outside and a.distance_to(b)>900, "Ordinary inter-zone navigation still allows long travel outside activity boundaries")


func check_unavailable() -> void:
	var actor = map.villagers[0]
	var saved: Array[NodePath] = actor.activity_zone_paths.duplicate()
	var home: ActivityZone2D = map.get_node("ActivityZones/Home01")
	actor.activity_zone_paths.assign([actor.get_path_to(home)])
	home.zone_enabled = false
	actor._choose_destination(nav)
	check(not actor.has_destination and actor.current_zone==null and actor.wait_remaining>=2,
		"Unavailable assigned territory yields bounded waiting without using functional shelter markers as peaceful fallback")
	home.zone_enabled = true
	actor.activity_zone_paths.assign(saved)
	actor._choose_destination(nav)
	check(actor.current_zone!=null and actor.has_destination, "Restored territory permits valid activity selection again")
	actor._stop_movement()
	actor.wait_remaining = 0


func observe_village(seconds: int) -> void:
	seed(3303)
	for index in range(map.get_node("ActivityZones").get_child_count()):
		map.get_node("ActivityZones").get_child(index)._random.seed=330300+index
	var travel: Array[float] = []
	var local_travel: Array[float] = []
	var arrivals: Array[int] = []
	var completed: Array[int] = []
	var local_routes: Array[int] = []
	var visited: Array[Dictionary] = []
	for actor in map.villagers:
		actor.autonomous_movement_enabled = true
		actor.wait_remaining = 0
		travel.append(0)
		local_travel.append(0)
		arrivals.append(0)
		completed.append(0)
		local_routes.append(0)
		visited.append({})
	var safe := true
	var clocks := true
	var contained := true
	var distinct := true
	var peak_neighbours := 0
	var observed_seconds := 0.0
	for tick in range(seconds*120): # At least 180 s; allow a bounded second window for random work pauses.
		var before: Array[Vector2] = []
		var performing: Array[bool] = []
		var moving: Array[bool] = []
		var remaining: Array[float] = []
		var previous_zones: Array[Node] = []
		for actor in map.villagers:
			before.append(actor.position)
			performing.append(actor.is_performing_activity)
			moving.append(actor.has_destination)
			remaining.append(actor.wait_remaining)
			previous_zones.append(actor.current_zone)
		await frames(1)
		for index in range(30):
			var actor = map.villagers[index]
			var distance: float = actor.position.distance_to(before[index])
			travel[index] += distance
			if actor.guard_patrol!=null:
				if tick%30==0: safe=safe and body_clear(actor.position,actor.get_node("CollisionShape2D").shape)
				continue
			if not performing[index] and actor.is_performing_activity:
				arrivals[index]+=1
				visited[index][actor.current_zone.zone_id]=true
			if performing[index] and not actor.is_performing_activity:
				if remaining[index] <= 1.0/60.0+0.0001: completed[index]+=1
				else: print("EARLY ACTIVITY EXIT ",actor.name," remaining=",remaining[index]," at=",actor.position)
			if actor.is_performing_activity:
				contained = contained and is_instance_valid(actor.current_zone) and actor.current_zone.contains_world_point(actor.position)
				if performing[index] and previous_zones[index]==actor.current_zone:
					clocks = clocks and absf(actor.wait_remaining-(remaining[index]-1.0/60.0))<0.0001
					local_travel[index]+=distance
				if actor.has_destination and not moving[index]: local_routes[index]+=1
			elif actor.has_destination:
				clocks = clocks and actor.wait_remaining==0
			if actor.has_destination and not moving[index]:
				contained = contained and actor.current_zone!=null and actor.current_zone.contains_world_point(actor.destination)
				for other in map.villagers:
					if actor!=other and other.has_destination: distinct = distinct and actor.destination.distance_to(other.destination)>0.01
			if tick%30==0:
				safe = safe and body_clear(actor.position,actor.get_node("CollisionShape2D").shape)
				var nearby := 0
				for other in map.villagers:
					if other.position.distance_to(actor.position)<40: nearby+=1
					if actor!=other: safe = safe and actor.position.distance_to(other.position)>7
				peak_neighbours=maxi(peak_neighbours,nearby)
		observed_seconds = (tick+1)/60.0
		if tick+1 == seconds*60:
			var walkers := 0
			for distance in local_travel:
				if distance>5: walkers+=1
			print("INITIAL 180 SECOND WINDOW actual local walkers=",walkers," / 25 civilians (5 guards use patrol routes)")
		if tick+1 >= seconds*60 and tick%60 == 59:
			var all_transitioned := true
			for index in range(30):
				if map.villagers[index].guard_patrol!=null:
					all_transitioned=all_transitioned and map.villagers[index].guard_patrol.waypoints_reached>10 and travel[index]>60
					continue
				all_transitioned = all_transitioned and local_travel[index]>5 and arrivals[index]>=2 and completed[index]>=1 and visited[index].size()>=2
			if all_transitioned: break
	for index in range(30):
		if map.villagers[index].guard_patrol!=null:
			check(travel[index]>60 and map.villagers[index].guard_patrol.waypoints_reached>10,
				"Guard physically follows road patrol instead of civilian zone cycles: "+str(map.villagers[index].name))
			continue
		print("ZONE OBSERVATION ",map.villagers[index].name," travel=",snappedf(travel[index],0.1)," local=",snappedf(local_travel[index],0.1)," arrivals=",arrivals[index]," completed=",completed[index]," local routes=",local_routes[index]," zones=",visited[index].size())
		check(travel[index]>60 and local_travel[index]>5 and arrivals[index]>=2 and completed[index]>=1 and visited[index].size()>=2,
			"Real zone entry, local walking, completed activity and subsequent territory reached: "+str(map.villagers[index].name))
	check(safe and contained and clocks and distinct,"All thirty preserve physical safety, zone boundaries, activity clocks and distinct assigned destinations")
	print("VILLAGE ZONE SIMULATION seconds=",observed_seconds," peak neighbours within 40=",peak_neighbours)


func check_bridge_travel() -> void:
	var actor=map.villagers[0]
	var original_position: Vector2=actor.position
	var original_paths: Array[NodePath]=actor.activity_zone_paths.duplicate()
	var original_weights := [actor.home_weight,actor.work_weight,actor.social_weight,actor.wander_weight]
	var transit := load("res://scenes/activity_zone_2d.tscn").instantiate() as ActivityZone2D
	transit.polygon=PackedVector2Array([Vector2(2860,1145),Vector2(2940,1145),Vector2(2940,1220),Vector2(2860,1220)])
	transit.activity=transit.Activity.WANDER
	transit._random.seed=3399
	map.add_child(transit)
	actor._stop_movement()
	actor.position=Vector2(2600,1180)
	actor.activity_zone_paths.assign([actor.get_path_to(transit)])
	actor.home_weight=0
	actor.work_weight=0
	actor.social_weight=0
	actor.wander_weight=1
	await frames(3)
	actor._choose_destination(nav)
	actor.autonomous_movement_enabled=true
	var safe := true
	for tick in range(1200):
		await frames(1)
		if tick%5==0: safe=safe and body_clear(actor.position,actor.get_node("CollisionShape2D").shape)
		if actor.is_performing_activity: break
	check(safe and actor.is_performing_activity and actor.current_zone==transit and actor.position.x>2820,
		"Real resident crosses bridge to an activity zone on the far bank using ordinary inter-zone navigation")
	actor.autonomous_movement_enabled=false
	actor._stop_movement()
	actor.wait_remaining=0
	actor.position=original_position
	actor.activity_zone_paths.assign(original_paths)
	actor.home_weight=original_weights[0]
	actor.work_weight=original_weights[1]
	actor.social_weight=original_weights[2]
	actor.wander_weight=original_weights[3]
	transit.queue_free()
	await frames(3)
