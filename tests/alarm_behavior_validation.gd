# Regressions from recordings 17_05_08 and 17_10_36.
extends "res://tests/guard_ai_validation.gd"

func run() -> void:
	await fixture()
	await isolated_incident()
	await fixture()
	await recruitment_priority()
	await fixture()
	await gathering_activity()
	await fixture()
	await gathering_evacuation()
	map.queue_free()
	await frames(3)
	print("Alarm behavior validation failures: ",failures)
	quit(1 if failures else 0)

func isolate_square() -> void:
	for guard in guards: guard.actor.position = Vector2(2300,1700)
	for civilian in civilians: civilian.actor.position = Vector2(2300,1800)

func isolated_incident() -> void:
	isolate_square()
	var victim = civilians[0].actor
	victim.position = Vector2(1500,1000)
	enemies[0].position = victim.position + Vector2(18,0)
	enemies[0].infection_chance = 0
	await frames(3)
	victim.threat_recognized.emit(enemies[0])
	check(alert.score == 0, "Private recognition by an isolated victim does not raise village suspicion")
	victim.threat_reaction.episode_active = true
	victim.threat_reaction.warning_sent = true
	victim.threat_reaction.threat_id = enemies[0].get_instance_id()
	victim.warning_attempted.emit(victim,enemies[0].position)
	check(victim.local_warning.notifications_delivered == 0 and alert.score == 0, "An unheard warning with no local recipient does not raise public suspicion")
	victim.begin_encounter(Color.GREEN,enemies[0])
	check(alert.score == 0, "Uncommunicated combat does not raise village suspicion")
	victim.take_damage(1000)
	check(alert.score == 0 and alert.level == alert.Level.NORMAL and map.killed_residents == 1, "Unwitnessed death stays private while mission death statistics remain correct")
	var source = guards[0]
	var recipient = guards[1]
	source.actor.position = Vector2(1450,970)
	recipient.actor.position = Vector2(1500,970)
	await frames(3)
	var report = report_for(71001,Vector2(1520,980))
	defense.broadcast(source.actor,report,180)
	check(alert.score == alert.recognition_points and alert.incident_counts.get(&"communicated",0)==1, "Accepted local information raises suspicion once per original incident")
	for i in range(20): defense.broadcast(source.actor,report,180)
	check(alert.score == alert.recognition_points, "Repeated reports do not stack sighting/combat/death into 20/40/60")

func recruitment_priority() -> void:
	isolate_square()
	var g = guards[0]
	g.actor.position = defense.bell.position + Vector2(0,18)
	g.actor.autonomous_movement_enabled = true
	var r = report_for(72001,map.get_node("VillagePointsOfInterest/Square").position)
	g.memory.remember(r,defense.elapsed)
	var search = g.memory.offer(g.State.SEARCH,r,defense.elapsed)
	search.points = PackedVector2Array([r.point])
	search.look = 0.0
	g.active = search
	search.status = "active"
	check(defense.ring(g.actor), "Guard actually raises the physical alarm")
	g.update_ai(0.016)
	check(g.mobilizing and g.state != g.State.SEARCH and search.status == "interrupted", "After bell, recruitment interrupts an old search instead of sending the guard alone")
	check(g.mobilization_goal.is_finite() and g.mobilization_goal.distance_to(r.point)>g.search_radius, "Recruitment does not disguise a return to the last known enemy position as a visit to a gathering place")
	for i in range(2):
		var civilian = civilians[i]
		civilian.actor.position = g.actor.position + Vector2(-30-i*20,25)
		civilian.courage = 1
		civilian.next_invitation = 0
	await frames(3)
	g.next_recruitment = 0
	g.update_ai(0.016)
	check(g.followers.size()==2 and g.ready_followers()==2, "Guard recruits available local companions before resuming interrupted work")

func gathering_activity() -> void:
	isolate_square()
	physical_alarm()
	var c = civilians[0]
	var square = map.get_node("VillagePointsOfInterest/Square")
	c.actor.position = Vector2(1500,1000)
	c.actor.autonomous_movement_enabled = true
	c.safety_marker = square
	c.safety_point = defense.reserve_safety(c.actor,square,c.rng)
	check(c.safety_point.is_finite(), "Gathering site offers a real navigable reserved position")
	c.actor.position = c.safety_point
	c.reset_idle_pause()
	var start: Vector2 = c.actor.position
	c.actor.set_physics_process(true)
	var displacement := 0.0
	for i in range(1800):
		await frames(1)
		displacement = maxf(displacement,c.actor.position.distance_to(start))
	check(c.idle_moves >= 1 and displacement>5, "Default alarm activity alternates waiting and physical local movement over 30 seconds")
	var before: Vector2 = c.actor.position
	var timer: float = c.idle_remaining
	paused = true
	await frames(30)
	check(c.actor.position==before and c.idle_remaining==timer, "Tactical pause freezes local gathering activity")
	paused = false

func gathering_evacuation() -> void:
	isolate_square()
	physical_alarm()
	var c = civilians[0]
	var square = map.get_node("VillagePointsOfInterest/Square")
	c.actor.position = Vector2(1500,1000)
	c.actor.autonomous_movement_enabled = true
	c.safety_marker = square
	c.safety_point = c.actor.position
	for i in range(3): enemies[i].position = c.actor.position + Vector2(40+i*15,0)
	await frames(3)
	c.actor.threat_detection.recognized_target = enemies[0]
	c.actor.threat_detection.awareness = c.actor.threat_detection.Awareness.AWARE
	c.next_decision = 0
	c.update_escort(0.016)
	check(c.unsafe_sites.has(square.get_instance_id()) and c.prefer_private_until > defense.elapsed and c.safety_marker==null, "Personally observed horde invalidates the gathering place and is remembered")
	check(civilians[1].unsafe_sites.is_empty(), "Remote residents do not magically learn the danger of this site")
	for enemy in enemies: enemy.position = Vector2(100,100)
	await frames(3)
	c.actor.threat_detection.reset_awareness()
	c.actor.threat_reaction.cancel_response()
	c.actor.local_warning.clear_report()
	defense.elapsed += 5 # beyond old short calm timeout, within danger memory
	c.next_decision = 0
	c.update_escort(0.016)
	var home = c.actor.get_node(c.actor.home_point_path)
	check(c.safety_marker==home and c.safety_point.is_finite(), "After losing sight of a horde, civilian heads home instead of calmly returning to the square")
	check(c.site_is_unsafe(square), "A few quiet seconds do not erase locally known danger")
	var listener = civilians[1]
	listener.actor.position = Vector2(1500,1100)
	guards[1].actor.position = Vector2(1500,1080)
	await frames(2)
	var report = report_for(73001,Vector2(1500,1000),3)
	check(listener.receive_message(report,guards[1].actor) and listener.site_is_unsafe(square), "A credible local report can warn a civilian before they have chosen any gathering destination")
	var until: float = listener.prefer_private_until
	listener.receive_message(report,guards[1].actor)
	check(listener.prefer_private_until == until, "Repeating an unchanged report does not renew dangerous-site memory")
