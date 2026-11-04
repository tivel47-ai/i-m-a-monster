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
	source.escort.reporter.report = report.duplicate(true)
	source.local_warning.firsthand_report = report.duplicate(true)
	check(g.receive_eyewitness(report,source), "A physical firsthand meeting creates one bounded local response")
	for i in [1,2]:
		civilians[i].actor.position=g.actor.position+Vector2(-20, i*12)
		civilians[i].courage=1
		civilians[i].actor.autonomous_movement_enabled=true
	g.sense()
	g.investigation.recruit_locally()
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
	source.escort.reporter.report = report.duplicate(true)
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
	defense.guard_contact_points.clear()
	defense.guard_contact_points.append(Vector2(1400,1000))
	defense.guard_contact_points.append(Vector2(1300,1000))
	await frames(30)
	var snapshot: Vector2 = source.local_warning.firsthand_report.point
	enemies[0].position = Vector2(100,100)
	await frames(240)
	check(source.escort.reporter.visited.size()>=2 and source.local_warning.firsthand_report.point==snapshot,
		"Without a visible guard the messenger physically checks successive known duty points, without tracking a hidden monster")
	source.escort.reporting_seconds = 0.1
	await frames(10)
	check(source.escort.reporter.report.is_empty() and source.threat_reaction.seeking_home and alert.score==0,
		"A bounded unsuccessful guard search falls back to home refuge without inventing a delivered report")
	map.queue_free()
	await frames(3)
	print("Eyewitness response validation failures: ",failures)
	quit(1 if failures else 0)
