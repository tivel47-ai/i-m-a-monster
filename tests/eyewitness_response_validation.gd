extends "res://tests/guard_ai_validation.gd"

func prepare() -> Node2D:
	await fixture()
	for guard in guards: guard.actor.position = Vector2(2600, 1700)
	for civilian in civilians: civilian.actor.position = Vector2(2600, 1800)
	var source = civilians[0].actor
	source.position = Vector2(1500, 1000)
	source.autonomous_movement_enabled = true
	source.threat_detection.detection_enabled = true
	source.threat_detection.recognition_delay_min = 0.05
	source.threat_detection.recognition_delay_max = 0.05
	source.threat_reaction.flee_weight = 1
	source.threat_reaction.shelter_weight = 0
	source.threat_reaction.warning_weight = 0
	source.threat_reaction.frozen_weight = 0
	source.threat_reaction.reporting_share_of_escape = 1.0
	source.threat_reaction.reaction_random.seed = 501
	civilians[0].courage = 1
	civilians[0].arming_probability = 1
	guards[0].actor.position = Vector2(1340, 1000)
	enable(guards[0])
	enemies[0].position = Vector2(1580, 1000)
	enemies[0].infection_chance = 0
	return source

func run() -> void:
	var source = await prepare()
	var g = guards[0]
	guards[1].actor.position = Vector2(1340, 1040)
	enable(guards[1])
	var joined := false
	var peer_joined := false
	var checked_after_battle := false
	var peaceful_on_kill := false
	var victory := false
	var origin: Vector2 = source.position
	for tick in range(4200):
		await frames(1)
		joined = joined or (civilians[0].leader == g and not alert.bell_activated)
		peer_joined = peer_joined or (g.investigation.peer != null and is_instance_valid(g.investigation.peer.get_ref()))
		if not enemies[0].is_alive():
			victory = true
			if g.investigation.phase == g.investigation.Phase.SWEEP: checked_after_battle = true
			if g.investigation.completed_checks == 0 and not source.threat_reaction.seeking_home: peaceful_on_kill = true
		if g.investigation.completed_responses > 0: break
	print("RESPONSE METRICS joined=",joined," peer=",peer_joined," victory=",victory," checks=",g.investigation.completed_checks," position=",source.position," responses=",g.investigation.completed_responses," phase=",g.investigation.phase)
	check(source.position.distance_to(origin)>40 and joined, "A real firsthand witness runs to a guard, reports and joins before any bell")
	check(peer_joined, "The investigating guard recruits a locally encountered peer defender")
	check(victory and checked_after_battle and not peaceful_on_kill and g.investigation.completed_checks>=2,
		"A manageable real combat is followed by physical nearby checks before any all-clear")
	print("ALL CLEAR METRICS leader=",civilians[0].leader," refuge=",source.threat_reaction.seeking_home," infection=",source.infection_state," clear=",source.local_warning.cleared_incidents," firsthand=",source.local_warning.firsthand_report," heard=",civilians[0].reported_danger)
	check(g.investigation.completed_responses>0 and not alert.bell_activated and civilians[0].leader==null and not source.threat_reaction.seeking_home,
		"Completed local verification releases the witness into ordinary life without ringing the bell")
	await frames(300)
	check(source.has_destination or source.is_performing_activity or source.wait_remaining>0, "The reassured survivor actually resumes the ordinary activity cycle")
	check(guards[4].investigation.phase==guards[4].investigation.Phase.NONE and guards[4].memory.incidents.is_empty(), "A distant guard learns no coordinates or victory remotely")
	check(g.followers.size()<=2 and guards[1].followers.size()<=2, "Pre-alarm investigations retain the two-civilian group cap")
	var old_report = report_for(enemies[0].get_instance_id(), enemies[0].position)
	old_report.observed_at = 0.5
	check(not g.receive_message(old_report, source) and not civilians[0].receive_message(old_report, g.actor),
		"An already checked incident cannot be resurrected by an older local report")
	await prepare()
	source = civilians[0].actor
	g = guards[0]
	for i in range(3):
		enemies[i].position = Vector2(1580, 980+i*20)
		enemies[i].infection_chance = 0
	civilians[0].arming_probability = 0
	var escalated := false
	for tick in range(3600):
		await frames(1)
		escalated = escalated or g.investigation.phase == g.investigation.Phase.ESCALATING
		if alert.bell_activated: break
	check(escalated and alert.bell_activated and g.actor.global_position.distance_to(defense.bell.global_position)<=defense.bell_reach,
		"An overwhelming personally discovered threat causes flight and real timed bell interaction")
	check(g.mobilizing and g.investigation.completed_responses==0, "Physical alarm switches to the existing mobilization without a false local victory")
	source = await prepare()
	g = guards[0]
	enemies[0].position = Vector2(100, 100)
	source.threat_detection.detection_enabled = false
	var report = report_for(90001, Vector2(1570,1000))
	source.position = g.actor.position + Vector2(25,0)
	source.threat_reaction.seeking_home = true
	source.escort.reporter.observe(report)
	source.local_warning.firsthand_report = report.duplicate(true)
	check(g.receive_eyewitness(report,source), "A physical firsthand meeting creates one bounded local response")
	for i in [1,2]:
		civilians[i].actor.position=g.actor.position+Vector2(-20, i*12)
		civilians[i].courage=1
		civilians[i].actor.autonomous_movement_enabled=true
	g.sense()
	g.investigation.recruit_locally()
	check(g.followers.is_empty() and g.investigation.peer == null, "The guard waits for the witness before inviting help for the investigation")
	await frames(5)
	check(civilians[0].leader==g and g.followers.size()<=2, "Nearby volunteers cannot take the reserved eyewitness's group slot")
	var started: float = g.investigation.started
	for i in range(30): g.receive_eyewitness(report,source)
	print("REPEAT METRICS started=",started," current=",g.investigation.started," tasks=",g.memory.tasks.size()," phase=",g.investigation.phase," position=",g.actor.position)
	check(g.investigation.started==started and g.memory.tasks.size()<=g.task_capacity, "Repeated testimony cannot restart or multiply the response")
	paused = true
	var position: Vector2 = g.actor.position
	await frames(30)
	check(g.actor.position==position and g.investigation.started==started, "Pause freezes response movement and clocks")
	paused = false
	g.investigation.end("infeasible", "test blocked approach")
	check(source.threat_reaction.seeking_home and g.investigation.completed_responses==0,
		"An interrupted or failed check releases the group without falsely reassuring the witness")
	source = await prepare()
	g = guards[0]
	enemies[0].position = Vector2(100,100)
	source.threat_detection.detection_enabled = false
	source.position = g.actor.position + Vector2(25,0)
	report = report_for(enemies[0].get_instance_id(), Vector2(1570,1000))
	source.threat_reaction.seeking_home = true
	source.escort.reporter.observe(report)
	source.local_warning.firsthand_report = report.duplicate(true)
	g.receive_eyewitness(report, source)
	for tick in range(2400):
		await frames(1)
		if g.investigation.completed_responses>0: break
	check(g.investigation.completed_responses>0 and not g.investigation.verified_victory and not source.threat_reaction.seeking_home,
		"A physically checked empty area permits a local return without falsely proving the hidden enemy dead")
	source.threat_detection.detection_enabled = true
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		enemies[0].position = source.position + direction * 60
		if source.threat_detection._is_visible_target(enemies[0]): break
	await frames(12)
	var fresh: Dictionary = source.local_warning.firsthand_report
	check(source.threat_reaction.seeking_home and not fresh.is_empty() and fresh.incident==report.incident
		and float(fresh.observed_at)>float(report.observed_at)
		and (not source.escort.reporter.report.is_empty() or is_instance_valid(civilians[0].leader)),
		"A new firsthand sighting of the same surviving monster invalidates the old all-clear")
	source = await prepare()
	for guard in guards:
		guard.actor.autonomous_movement_enabled = false
		guard.actor.position = Vector2(2600,1700)
	# The western witness sees a real zombie, but cannot reach the post within the time budget.
	source.escort.reporting_seconds = 1.0
	await frames(30)
	var snapshot: Vector2 = source.local_warning.firsthand_report.point
	var showed_route: bool = source.escort.reporter.goal.is_finite()
	enemies[0].position = Vector2(100,100)
	for frame in range(240):
		await frames(1)
		showed_route = showed_route or source.escort.reporter.goal.is_finite()
	check(not showed_route and source.escort.reporter.report.is_empty() and source.local_warning.firsthand_report.point == snapshot
		and source.threat_reaction.reaction_state == source.threat_reaction.Reaction.SEEKING_SHELTER and alert.score == 0,
		"A witness with no local guard or reachable post takes shelter without a blind R detour")
	await check_guard_choice_and_meeting()
	await check_post_search()
	await check_late_guard_reply()
	map.queue_free()
	await frames(3)
	print("Eyewitness response validation failures: ",failures)
	quit(1 if failures else 0)

func check_guard_choice_and_meeting() -> void:
	for both_guards in [true, false]:
		var source = await prepare()
		var across_wall = guards[0]
		var open_route = guards[1]
		source.position = Vector2(1376, 868)
		across_wall.actor.position = Vector2(1484, 868)
		open_route.actor.position = Vector2(1376, 996)
		open_route.actor.autonomous_movement_enabled = both_guards
		across_wall.actor.set_physics_process(false)
		source.set_physics_process(false)
		source.threat_detection.detection_enabled = false
		enemies[0].position = Vector2(100, 100)
		await frames(3)
		var reaction = source.threat_reaction
		reaction.seeking_home = true
		reaction.episode_active = true
		reaction.warning_sent = true
		reaction.threat_position = Vector2(1300, 830)
		var message = report_for(90123, reaction.threat_position)
		message.source = source.get_instance_id()
		message.witness = true
		source.escort.reporter.observe(message)
		source.local_warning.firsthand_report = message
		var hidden_length: float = source.escort.reporter.contact_distance(across_wall)
		var open_length: float = source.escort.reporter.contact_distance(open_route)
		check(not defense.visible(source, across_wall.actor, 180) and hidden_length < INF and hidden_length > open_length
			and source.position.distance_to(across_wall.actor.position) < source.position.distance_to(open_route.actor.position),
			"The well makes the geometrically closer guard slower to reach by a real route")
		source.warning_attempted.emit(source, reaction.threat_position)
		if both_guards:
			check(source.escort.reporter.assigned_guard() == open_route and across_wall.investigation.phase == across_wall.investigation.Phase.NONE,
				"The shorter accessible route wins the actual audible response over a closer guard behind a wall")
		else:
			var point: Vector2 = source.escort.reporter.meeting_point
			check(source.escort.reporter.assigned_guard() == across_wall and point == across_wall.investigation.contact_point,
				"An audible reply across the wall gives both participants the same fixed meeting point")
			source.set_physics_process(true)
			across_wall.actor.set_physics_process(true)
			for frame in range(360):
				await frames(1)
				if source.escort.leader == across_wall: break
			check(source.escort.leader == across_wall and not source.escort.reporter.post_target.is_finite(),
				"The hidden responding guard meets the witness before a trip to the post")

func check_post_search() -> void:
	var source = await prepare()
	for guard in guards:
		guard.actor.autonomous_movement_enabled = false
		guard.actor.position = Vector2(2600, 1700)
	enemies[0].position = Vector2(100, 100)
	source.threat_detection.detection_enabled = false
	source.position = Vector2(2180, 1640)
	await frames(3)
	var post: Vector2 = defense.guard_posts[0]
	var message = report_for(90124, Vector2(2050, 1700))
	source.threat_reaction.threat_position = message.point
	source.threat_reaction.seeking_home = true
	source.escort.reporter.observe(message)
	await frames(3)
	check(source.escort.reporter.goal == post, "Without a local responder the witness walks to the actual exterior post approach")
	for frame in range(480):
		await frames(1)
		if source.escort.reporter.report.is_empty(): break
	check(source.escort.reporter.post_arrived_at >= 0 and source.escort.reporter.report.is_empty()
		and source.threat_reaction.seeking_home and alert.score == 0,
		"After checking the empty post the witness goes to shelter without another detour")

func check_late_guard_reply() -> void:
	var source = await prepare()
	var guard = guards[0]
	guard.actor.position = Vector2(1330, 1000)
	guard.actor.autonomous_movement_enabled = false
	guard.actor.set_physics_process(false)
	source.set_physics_process(false)
	source.threat_detection.detection_enabled = false
	enemies[0].position = Vector2(100, 100)
	var listener = civilians[1].actor
	listener.position = Vector2(1510, 1040)
	await frames(3)
	var message = report_for(90125, Vector2(1580, 1000))
	message.source = source.get_instance_id()
	message.witness = true
	source.local_warning.firsthand_report = message
	source.threat_reaction.seeking_home = true
	source.threat_reaction.threat_position = message.point
	source.escort.reporter.observe(message)
	await frames(75)
	check(guard.memory.incidents.has(message.incident) and source.escort.reporter.assigned_guard() == null and listener.local_warning.has_report(),
		"The first call records evidence while the nearby guard is unavailable")
	await frames(615)
	guard.actor.autonomous_movement_enabled = true
	await frames(70)
	check(source.escort.reporter.assigned_guard() == guard and not listener.local_warning.has_report()
		and float(guard.memory.incidents[message.incident].observed_at) == float(message.observed_at),
		"A guard can answer an already known call after civilian warnings expire, without refreshing the report")
	var point: Vector2 = source.escort.reporter.meeting_point
	source.set_physics_process(true)
	guard.actor.set_physics_process(true)
	var held_point := true
	var used_route := false
	for frame in range(360):
		await frames(1)
		if source.escort.leader == guard: break
		held_point = held_point and guard.actor.global_position.distance_to(point) < 2.0
		used_route = used_route or source.escort.reporter.goal == point
	check(source.escort.leader == guard and held_point and used_route,
		"The running witness reaches the stationary responder on one fixed meeting route")
