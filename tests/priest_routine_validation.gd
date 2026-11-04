# Godot --headless --path . --script tests/priest_routine_validation.gd --fixed-fps 60 -- --seed=4101
extends "res://tests/simulation_map_validation.gd"

var priest: Node
var routine: Node
var test_seed := 4101

func fixture(all_residents: bool) -> void:
	seed(test_seed)
	map=load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	units=get_nodes_in_group("player_units")
	reset_units(Vector2(100,100))
	for unit in units:
		unit.get_node("AggroArea").monitoring=false
		unit.aggro_candidates.clear()
	priest=map.get_node("Villagers/Priest30")
	routine=priest.priest_routine
	for actor in map.villagers: actor.autonomous_movement_enabled=all_residents or actor==priest
	for index in range(59): map.get_node("ActivityZones").get_child(index)._random.seed=test_seed*100+index
	await frames(5)
	nav=map.get_world_2d().navigation_map

func clear_fixture() -> void:
	map.queue_free()
	await frames(3)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): test_seed=int(argument.trim_prefix("--seed="))
	if not OS.get_cmdline_user_args().has("--lifecycle-only"):
		await fixture(true)
		check_assignments()
		await observe_roles()
		await clear_fixture()
	await fixture(false)
	await check_unavailable_and_overrides()
	await check_interruptions()
	await clear_fixture()
	await fixture(false)
	await check_conversion()
	await clear_fixture()
	print("Priest routine validation failures: ",failures," seed=",test_seed)
	quit(1 if failures else 0)

func check_assignments() -> void:
	var expected := [["HomeChapel","WorkChurch","SocialChurch","WalkChurch"],["WorkCemetery","WalkCemetery"],["SocialSquare","SocialWell"]]
	var paths := [routine.chapel_zone_paths,routine.cemetery_zone_paths,routine.public_zone_paths]
	var safe := true
	for territory in range(3):
		var names: Array[String]=[]
		for path in paths[territory]:
			var zone: ActivityZone2D=routine.get_node_or_null(path)
			if zone==null:
				safe=false
				continue
			names.append(str(zone.name))
			safe=safe and zone.allows_resident(priest) and priest.activity_zone_paths.has(priest.get_path_to(zone)) and routine.zone_territory(zone)==territory
			for attempt in range(4):
				var sample:=zone.sample_destination(priest,PackedVector2Array(),null,5,5)
				safe=safe and not sample.is_empty()
				if not sample.is_empty(): safe=safe and body_clear(sample[0],priest.get_node("CollisionShape2D").shape) and clear_path(path_to(priest.position,sample[0]))
		check(names==expected[territory],"Existing assigned territories resolve without new polygons: "+str(names))
	check(safe,"All priest territories offer navigable outdoor destinations outside walls, gravestones and fences")

func observe_roles() -> void:
	var activity_time := [0.0,0.0,0.0]
	var spatial_primary := 0.0
	var visits := [0,0,0]
	var local_distance := [0.0,0.0,0.0]
	var resting := [0.0,0.0,0.0]
	var duration_min := [INF,INF,INF]
	var clocks_safe := true
	var geometry_safe := true
	var transitions_safe := true
	var failed_routes := 0
	var clock_ended_walks := 0
	var longest_idle := 0.0
	var idle := 0.0
	var last_completed := -1
	var guard_peak := 0
	var guard_empty := 0
	var guard_failures := 0
	var guards: Array[Node]=[]
	for actor in map.villagers:
		if actor.guard_patrol!=null: guards.append(actor)
	for tick in range(54000):
		var position: Vector2=priest.position
		var performing: bool=priest.is_performing_activity
		var remaining: float=priest.wait_remaining
		var moving: bool=priest.has_destination
		var goal: Vector2=priest.destination
		var zone: ActivityZone2D=priest.current_zone
		var previous_territory: int=routine.zone_territory(zone)
		var before_guard_failures: Array[int]=[]
		for guard in guards: before_guard_failures.append(guard.guard_patrol._retries)
		await frames(1)
		if priest.is_performing_activity:
			var territory: int=routine.zone_territory(priest.current_zone)
			geometry_safe=geometry_safe and territory>=0 and priest.current_zone.contains_world_point(priest.position)
			if territory>=0:
				activity_time[territory]+=1.0/60
				if not priest.has_destination: resting[territory]+=1.0/60
				if performing and zone==priest.current_zone:
					local_distance[territory]+=priest.position.distance_to(position)
					clocks_safe=clocks_safe and absf(priest.wait_remaining-(remaining-1.0/60))<0.0001
				else:
					visits[territory]+=1
					duration_min[territory]=minf(duration_min[territory],priest.wait_remaining)
					if last_completed==1 or last_completed==2: transitions_safe=transitions_safe and territory==0
					if last_completed==0: transitions_safe=transitions_safe and territory in [1,2]
			idle=0
		elif performing:
			clocks_safe=clocks_safe and remaining<=1.0/60+0.0001
			last_completed=previous_territory
		elif not priest.has_destination:
			idle+=1.0/60
			longest_idle=maxf(longest_idle,idle)
		else:
			idle=0
			clocks_safe=clocks_safe and priest.wait_remaining==0
		if moving and not priest.has_destination and priest.position.distance_to(goal)>priest.arrival_tolerance+0.1:
			print("PRIEST ROUTE STOP seed=",test_seed," time=",tick/60.0," performing=",performing," remaining=",remaining," after_performing=",priest.is_performing_activity," distance=",priest.position.distance_to(goal)," stalled=",priest.stalled_seconds)
			if performing and remaining<=1.0/60+0.0001: clock_ended_walks+=1
			else: failed_routes+=1
		if priest.has_destination and not moving:
			geometry_safe=geometry_safe and is_instance_valid(priest.current_zone) and priest.current_zone.contains_world_point(priest.destination)
			geometry_safe=geometry_safe and body_clear(priest.destination,priest.get_node("CollisionShape2D").shape)
		var near:=0
		var claims:=0
		for index in range(guards.size()):
			var patrol=guards[index].guard_patrol
			if patrol.is_near_post(): near+=1
			if patrol.state in [patrol.State.POST,patrol.State.RETURNING_POST]: claims+=1
			if patrol._retries>before_guard_failures[index]: guard_failures+=1
		guard_peak=maxi(guard_peak,near)
		transitions_safe=transitions_safe and claims<=2
		if tick>600 and near==0: guard_empty+=1
		if tick%30==0:
			geometry_safe=geometry_safe and body_clear(priest.position,priest.get_node("CollisionShape2D").shape)
			for guard in guards: geometry_safe=geometry_safe and body_clear(guard.position,guard.get_node("CollisionShape2D").shape)
		var within_primary:=false
		for path in routine.chapel_zone_paths+routine.cemetery_zone_paths:
			if routine.get_node(path).contains_world_point(priest.position): within_primary=true
		if within_primary: spatial_primary+=1.0/60
	var total: float=activity_time[0]+activity_time[1]+activity_time[2]
	var percent: float=100*(activity_time[0]+activity_time[1])/maxf(total,0.01)
	print("PRIEST METRICS seed=",test_seed," activity_seconds=",activity_time," primary_activity_percent=",percent," primary_spatial_seconds=",spatial_primary," visits=",visits," completed=",routine.completed_activities," cemetery_completed=",routine.completed_cemetery_visits," public_completed=",routine.completed_public_visits," local_distance=",local_distance," resting=",resting," min_durations=",duration_min," failed_routes=",failed_routes," clock_ended_walks=",clock_ended_walks," longest_unplanned_idle=",longest_idle)
	check(percent>=80 and activity_time[0]>activity_time[1] and activity_time[1]>activity_time[2],"Actual peaceful activity time stays predominantly at chapel/cemetery, with chapel the principal workplace")
	check(visits[0]>=3 and visits[1]>=2 and visits[2]>=1 and routine.completed_cemetery_visits>=2 and routine.completed_public_visits>=1 and transitions_safe,"Completed chapel/cemetery alternation, return after cemetery and occasional public visit occur physically")
	check(duration_min[0]>=routine.chapel_duration.x-0.02 and duration_min[1]>=routine.cemetery_duration.x-0.02 and duration_min[2]>=routine.public_duration.x-0.02,"All three territories start their configured long/short activity clocks only on arrival")
	check(clocks_safe and geometry_safe and longest_idle<10,"Activity timers finish without resets; real local and inter-zone movement stays safe with no prolonged unplanned inactivity")
	check(local_distance[0]>10 and local_distance[1]>10 and resting[0]>activity_time[0]*0.5 and resting[1]>activity_time[1]*0.3,"Priest actually walks within both primary territories and spends substantial time calmly resting")
	check(failed_routes==0,"Priest completes peaceful navigation without failed local/travel routes")
	var rotation:=true
	for guard in guards:
		var patrol=guard.guard_patrol
		print("STAGE4 GUARD ",guard.name," patrol=",patrol.patrol_seconds," post=",patrol.post_seconds," laps=",patrol.completed_laps," visits=",patrol.post_visits)
		rotation=rotation and patrol.patrol_seconds>patrol.post_seconds and patrol.completed_laps>=1
	print("STAGE4 GUARD SUMMARY peak=",guard_peak," empty_frames=",guard_empty," failed_route_attempts=",guard_failures)
	check(guard_peak<=2 and guard_empty==0 and rotation,"Full thirty-resident simulation retains guard occupancy, meaningful patrols and actual rotation for 900 seconds")

func await_activity(max_frames: int=3600) -> bool:
	for tick in range(max_frames):
		if priest.is_performing_activity: return true
		await frames(1)
	return false

func check_unavailable_and_overrides() -> void:
	priest._stop_movement()
	var phase: int=routine.territory
	var enabled: Array[bool]=[]
	for path in routine.chapel_zone_paths:
		var zone=routine.get_node(path)
		enabled.append(zone.zone_enabled)
		zone.zone_enabled=false
	await frames(180)
	check(not priest.has_destination and not priest.is_performing_activity and routine.territory==phase and routine.completed_activities==0,"Unavailable chapel waits without selecting unrelated territory or completing a failed visit")
	for index in range(routine.chapel_zone_paths.size()): routine.get_node(routine.chapel_zone_paths[index]).zone_enabled=enabled[index]
	check(await await_activity(),"Restoring safe assigned territory recovers real travel and activity")
	var zone: ActivityZone2D=priest.current_zone
	var original: Vector2=zone.duration_override
	zone.duration_override=Vector2(101,101)
	check(priest._activity_duration(priest.current_activity)==Vector2(101,101),"Authored zone duration override retains precedence over role defaults")
	zone.duration_override=original
	routine.routine_enabled=false
	check(priest._activity_duration(priest.current_activity)==priest.work_duration or priest._activity_duration(priest.current_activity)==priest.home_duration or priest._activity_duration(priest.current_activity)==priest.social_duration or priest._activity_duration(priest.current_activity)==priest.wander_duration,"Disabling routine restores existing civilian duration configuration")
	routine.routine_enabled=true
	# Expiring an activity may intentionally stop an unfinished local route.
	var local_goal := zone.sample_local_destination(priest, 90, 12)
	check(not local_goal.is_empty(),"Clock-expiry fixture has a real reachable local destination")
	if not local_goal.is_empty():
		var completed: int=routine.completed_activities
		priest._set_peaceful_destination(local_goal[0])
		priest.wait_remaining=1.0/60
		await frames(1)
		check(not priest.has_destination and not priest.is_performing_activity and routine.completed_activities==completed+1 and routine.territory==routine.Territory.CEMETERY,"Activity clock ends even during a local walk; intentional stop completes one visit")
	check(await await_activity(),"Normal clock expiry leads to a real cemetery visit")

func enemy_near_actor() -> Node2D:
	var enemy=load("res://scenes/zombie.tscn").instantiate()
	for index in range(8):
		var point: Vector2=priest.position+Vector2.from_angle(TAU*index/8.0)*65
		var ray:=PhysicsRayQueryParameters2D.create(priest.position,point,1)
		if body_clear(point) and map.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			enemy.position=point
			break
	map.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.navigation_agent.avoidance_enabled=false
	return enemy

func check_interruptions() -> void:
	var completed: int=routine.completed_activities
	var phase: int=routine.territory
	var position: Vector2=priest.position
	var remaining: float=priest.wait_remaining
	paused=true
	await frames(90)
	check(priest.position==position and priest.wait_remaining==remaining and routine.completed_activities==completed,"Tactical pause freezes priest movement, activity clock and routine")
	paused=false
	priest.threat_reaction.flee_weight=1
	priest.threat_reaction.shelter_weight=0
	priest.threat_reaction.warning_weight=0
	priest.threat_reaction.frozen_weight=0
	priest.threat_detection.recognition_delay_min=0.1
	priest.threat_detection.recognition_delay_max=0.1
	var enemy=enemy_near_actor()
	await frames(3)
	check(not priest.threat_reaction.episode_active,"Priest still observes existing recognition delay")
	for tick in range(60):
		await frames(1)
		if priest.threat_reaction.episode_active: break
	check(priest.threat_reaction.episode_active and priest.current_zone==null and not priest.is_performing_activity and routine.completed_activities==completed and routine.territory==phase,"Actual visual recognition interrupts priest routine without completing or skipping its visit")
	var owned:=true
	for tick in range(60):
		await frames(1)
		if priest.threat_reaction.has_route: owned=owned and priest.navigation_agent.target_position==priest.threat_reaction.route_destination
	check(owned,"Priest selection cannot overwrite active threat-response navigation")
	enemy.queue_free()
	await frames(30)
	check(priest.threat_reaction.episode_active,"Removing threat preserves existing safety/reassessment delay")
	check(await await_refuge() and routine.completed_activities==completed and routine.territory==phase,"After danger the priest takes exterior refuge without falsely completing a peaceful visit")
	completed=routine.completed_activities
	var speaker=map.villagers[0]
	speaker.position=priest.position+Vector2(35,0)
	speaker.threat_reaction.episode_active=true
	speaker.threat_reaction.warning_sent=true
	speaker.threat_reaction.report_based=false
	speaker.warning_attempted.emit(speaker,priest.position+Vector2(65,0))
	check(priest.local_warning.has_report() and priest.threat_reaction.report_based and priest.current_zone==null and routine.completed_activities==completed,"Real one-hop local warning interrupts priest activity without advancing the routine")
	speaker.threat_reaction.cancel_response()
	await frames(720)
	check(not priest.local_warning.has_report() and not priest.threat_reaction.episode_active,"Existing report expiry safely releases priest response")
	check(await await_refuge() and routine.completed_activities==completed,"After a local warning the priest remains in exterior refuge instead of resuming peaceful visits")
	enemy=enemy_near_actor()
	priest.threat_detection.detection_enabled=false
	priest.begin_encounter(Color.GREEN,enemy)
	await frames(30)
	check(not priest.has_destination and priest.current_zone==null and priest.is_in_collision(),"Combat suspends priest peaceful selection and movement")
	priest.leave_encounter(enemy)
	enemy.queue_free()
	check(await await_refuge() and routine.completed_activities==completed,"A priest surviving combat keeps the same home refuge fallback as other civilians")
	completed=routine.completed_activities
	priest.take_damage(1000)
	await frames(30)
	check(priest.is_dead() and priest.current_zone==null and not priest.has_destination and routine.completed_activities==completed,"Death permanently stops priest routine without false activity completion")

func await_refuge() -> bool:
	for tick in range(3600):
		await frames(1)
		if priest.threat_reaction.sheltered_at_home: return true
	return false

func check_conversion() -> void:
	check(await await_activity(),"Conversion fixture reaches its real assigned chapel territory")
	priest.threat_detection.detection_enabled=false
	var enemy=enemy_near_actor()
	var completed: int=routine.completed_activities
	priest.begin_encounter(Color.GREEN,enemy)
	priest.receive_zombie_attack(20,1.0,enemy)
	check(priest.infection_state==priest.InfectionState.TRANSFORMING and priest.current_zone==null and not priest.has_destination and routine.completed_activities==completed,"Infection immediately stops priest activity without advancing the routine")
	priest.leave_encounter(enemy)
	enemy.queue_free()
	var reference: WeakRef=weakref(priest)
	await frames(150)
	check(reference.get_ref()==null and map.infected_residents==1,"Transformation removes priest component and preserves single mission conversion accounting")
