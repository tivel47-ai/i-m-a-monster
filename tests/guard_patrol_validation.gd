# Godot --headless --path . --script tests/guard_patrol_validation.gd --fixed-fps 60
extends "res://tests/simulation_map_validation.gd"

func run() -> void:
	seed(4404)
	map=load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units=get_nodes_in_group("player_units")
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring=false
		unit.aggro_candidates.clear()
	var guards: Array[Node]=[]
	for actor in map.villagers:
		actor.autonomous_movement_enabled=actor.get_meta("village_role")=="guard"
		if actor.autonomous_movement_enabled: guards.append(actor)
	await frames(5)
	nav=map.get_world_2d().navigation_map
	check(guards.size()==10,"Ten real guards use optional patrol components; civilian simulation stays separate")
	var route_names: Dictionary={}
	for actor in guards:
		var patrol: Node=actor.guard_patrol
		check(patrol!=null and patrol._route()!=null and patrol._access()!=null,"Patrol, post and access assignments resolve: "+str(actor.name))
		route_names[str(patrol._route().name)]=true
	var valid_routes:=true
	for route in map.get_node("GuardPatrolRoutes").get_children():
		var line: PackedVector2Array=route.world_points()
		for point in line:
			valid_routes=valid_routes and NavigationServer2D.map_get_closest_point(nav,point).distance_to(point)<=1 and body_clear(point)
		for index in range(1,line.size()):
			var path:=path_to(line[index-1],line[index])
			valid_routes=valid_routes and not path.is_empty() and path[-1].distance_to(line[index])<=1 and clear_path(path)
	check(valid_routes and route_names.size()==5,"Five distinct road circuits and shared post approach are navigable with real body clearance")
	var roads: Array[Polygon2D]=[]
	for node in map.get_node("Roads").get_children():
		if node is Polygon2D and (node.has_meta("centerline") or node.name==&"Square"): roads.append(node)
	var road_samples:=0
	var on_road:=0
	var post_peak:=0
	var empty_post_frames:=0
	var in_patrol: Array[float] = []
	var stationed: Array[float] = []
	var distance: Array[float] = []
	for samples in [in_patrol, stationed, distance]:
		samples.resize(guards.size())
		samples.fill(0.0)
	var safe:=true
	var claims_safe:=true
	for tick in range(54000): # 900 simulated seconds, several full patrol rotations.
		var before: Array[Vector2]=[]
		for actor in guards: before.append(actor.position)
		await frames(1)
		var near:=0
		var claims:=0
		for index in range(guards.size()):
			var actor=guards[index]
			var patrol=actor.guard_patrol
			distance[index]+=actor.position.distance_to(before[index])
			if patrol.is_near_post(): near+=1
			if patrol.state in [patrol.State.POST,patrol.State.RETURNING_POST]: claims+=1
			if patrol.state==patrol.State.PATROL: in_patrol[index]+=1.0/60
			if patrol.state==patrol.State.POST: stationed[index]+=1.0/60
			if tick%60==0:
				safe=safe and body_clear(actor.position,actor.get_node("CollisionShape2D").shape)
				if tick>1800 and patrol.state==patrol.State.PATROL and actor.has_destination:
					road_samples+=1
					for road in roads:
						if Geometry2D.is_point_in_polygon(actor.position,road.global_transform*road.polygon):
							on_road+=1
							break
		post_peak=maxi(post_peak,near)
		claims_safe=claims_safe and claims<=2
		if near==0 and tick>600: empty_post_frames+=1
	check(post_peak<=2 and claims_safe,"At most two guards physically near post and no more than two incoming/on-duty claims; peak="+str(post_peak))
	check(empty_post_frames==0,"Post retains a guard until relief arrives; empty frames="+str(empty_post_frames))
	var total_patrol:=0.0
	var total_stationed:=0.0
	for index in range(guards.size()):
		var patrol=guards[index].guard_patrol
		total_patrol+=in_patrol[index]
		total_stationed+=stationed[index]
		print("GUARD METRICS ",guards[index].name," patrol=",snappedf(in_patrol[index],0.1)," post=",snappedf(stationed[index],0.1)," distance=",snappedf(distance[index],0.1)," laps=",patrol.completed_laps," visits=",patrol.post_visits," position=",guards[index].position," state=",patrol.state)
		check(in_patrol[index]>stationed[index] and distance[index]>3000 and patrol.completed_laps>=1,"Guard spends more time on patrol, walks real roads and completes a circuit: "+str(guards[index].name))
	print("GUARD SUMMARY patrol_seconds=",total_patrol," post_seconds=",total_stationed," road coverage=",float(on_road)/maxi(road_samples,1)," near_post_peak=",post_peak)
	check(safe and total_patrol>total_stationed*2 and road_samples>100 and float(on_road)/road_samples>0.9,"Majority of guard time is actual road patrol, with no static-obstacle crossings")
	await check_failed_relief(guards)
	await check_interruptions(guards)
	map.queue_free()
	await frames(3)
	print("Guard patrol validation failures: ",failures)
	quit(1 if failures else 0)

func check_interruptions(guards: Array[Node]) -> void:
	var actor=guards[2]
	var patrol=actor.guard_patrol
	var goal: Vector2=actor.navigation_agent.target_position
	var elapsed: float=patrol.patrol_elapsed
	var position: Vector2=actor.position
	var duty: float=patrol.duty_remaining
	var pause_time: float=patrol.pause_remaining
	paused=true
	await frames(90)
	check(actor.position==position and patrol.patrol_elapsed==elapsed and actor.navigation_agent.target_position==goal and patrol.duty_remaining==duty and patrol.pause_remaining==pause_time,"Tactical pause freezes patrol movement and timers")
	paused=false
	actor.threat_reaction.reactions_enabled=true
	actor.threat_reaction.flee_weight=1
	actor.threat_reaction.shelter_weight=0
	actor.threat_reaction.warning_weight=0
	actor.threat_reaction.frozen_weight=0
	actor.threat_detection.recognition_delay_min=0.1
	actor.threat_detection.recognition_delay_max=0.1
	actor.threat_detection.detection_enabled=true
	var observation_before: float = actor.guard_ai.last_seen_time
	var enemy=load("res://scenes/zombie.tscn").instantiate()
	for index in range(8):
		var point: Vector2=actor.position+Vector2.from_angle(TAU*index/8.0)*65
		var ray:=PhysicsRayQueryParameters2D.create(actor.position,point,1)
		if body_clear(point) and map.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			enemy.position=point
			break
	map.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.navigation_agent.avoidance_enabled=false
	for tick in range(60):
		await frames(1)
		if actor.guard_ai.last_seen_time > observation_before: break
	await frames(30) # perception signal may precede the next bounded decision tick
	check(actor.guard_ai.last_seen_time > observation_before and patrol.state==patrol.State.IDLE,"Actual guard recognition interrupts patrol and releases post claim without forcing a particular B2 decision")
	var owned:=true
	for tick in range(60):
		await frames(1)
		if actor.has_destination: owned=owned and patrol.state==patrol.State.IDLE
	check(owned,"Patrol cannot overwrite guard tactical movement")
	enemy.queue_free()
	await frames(900) # bounded guard search replaces the former civilian safety timeout
	check(patrol.state!=patrol.State.IDLE and not actor.threat_reaction.episode_active,"Guard resumes peaceful patrol after existing reassessment")
	actor.take_damage(1000)
	await frames(2)
	check(actor.is_dead() and patrol.state==patrol.State.IDLE and not actor.has_destination,"Death cancels patrol and duty reservation")
	var survivor=guards[3]
	var opponent=load("res://scenes/zombie.tscn").instantiate()
	opponent.position=survivor.position+Vector2(20,0)
	map.add_child(opponent)
	opponent.set_physics_process(false)
	opponent.navigation_agent.avoidance_enabled=false
	survivor.begin_encounter(Color.GREEN,opponent)
	await frames(15)
	check(survivor.guard_patrol.state==survivor.guard_patrol.State.IDLE and not survivor.has_destination,"Combat suspends guard patrol and frees duty claim")
	survivor.receive_zombie_attack(20,1.0,opponent)
	check(survivor.infection_state==survivor.InfectionState.TRANSFORMING and survivor.guard_patrol.state==survivor.guard_patrol.State.IDLE,"Infection cannot retain a peaceful guard patrol")
	survivor.leave_encounter(opponent)
	opponent.queue_free()
	var reference: WeakRef=weakref(survivor)
	await frames(150)
	check(reference.get_ref()==null and map.infected_residents==1,"Transformation removes guard component and retains one mission conversion")


func check_failed_relief(guards: Array[Node]) -> void:
	var actor: Node
	for tick in range(3600):
		for guard in guards:
			if guard.guard_patrol.state==guard.guard_patrol.State.PATROL and guard.guard_patrol._can_return():
				actor=guard
				break
		if actor!=null: break
		await frames(1)
	check(actor!=null,"A patrol guard can request relief without exceeding post capacity")
	if actor==null: return
	var patrol=actor.guard_patrol
	var original_position: Vector2=actor.position
	var original_speed: float=patrol.patrol_speed
	actor._stop_movement()
	actor.position=Vector2(2060,1320)
	check(patrol._begin_return(),"Failed-relief fixture reserves one incoming slot")
	patrol.patrol_speed=0
	await frames(900)
	check(patrol.state!=patrol.State.POST and not patrol.is_near_post(),"A physically stalled relief never counts as arrival or dismisses the stationed guard")
	patrol.patrol_speed=original_speed
	actor._stop_movement()
	actor.position=original_position
	await frames(3)
