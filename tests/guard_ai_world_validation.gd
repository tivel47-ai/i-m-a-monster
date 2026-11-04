# Additional physical integration scenarios; no mocked navigation or combat results.
extends "res://tests/guard_ai_validation.gd"

func run() -> void:
	await fixture()
	var g = guards[0]
	var r = report_for(60001, Vector2(1550, 980))
	g.receive_message(r, guards[1].actor)
	for other in guards.slice(1): other.actor.position = Vector2(2100 + guards.find(other)*20,1700)
	for civilian in civilians.slice(0,3): civilian.actor.position = Vector2(2100 + civilians.find(civilian)*20,1800)
	var origin: Vector2 = g.actor.position
	enable(g)
	for i in range(720):
		await frames(1)
		if not g.memory.outcomes.is_empty(): break
	print("INVESTIGATE METRICS ", g.actor.position, " origin=", origin, " state=",g.state," active=",g.active," outcomes=",g.memory.outcomes)
	check(g.actor.position.distance_to(origin) > 50 and not g.memory.outcomes.is_empty() and g.memory.outcomes[-1].status == "completed", "WORLD: Report investigation physically reaches and inspects an area")
	await fixture()
	g = guards[0]
	for other in guards.slice(1): other.actor.position = Vector2(2100 + guards.find(other)*20,1700)
	for civilian in civilians.slice(0,3): civilian.actor.position = Vector2(2100 + civilians.find(civilian)*20,1800)
	g.offer_alarm(report_for(60002, Vector2(1500,960), 3))
	enable(g)
	for i in range(900):
		await frames(1)
		if alert.bell_activated: break
	print("BELL METRICS ", g.actor.position, " bell=",defense.bell.global_position," state=",g.state," active=",g.active," outcomes=",g.memory.outcomes)
	check(alert.bell_activated and g.actor.position.distance_to(defense.bell.global_position) <= defense.bell_reach, "WORLD: Alarm task navigates to the bell and performs timed physical interaction")
	await fixture()
	g = guards[0]
	var b = guards[1]
	g.actor.position = Vector2(1450,960)
	b.actor.position = Vector2(1450,985)
	enemies[0].position = Vector2(1465,970)
	enemies[0].infection_chance = 0 # isolate real damage from probabilistic conversion
	var health: float = enemies[0].current_health
	var defender_health: float = g.actor.current_health
	enable(g)
	enable(b)
	await frames(150)
	check(enemies[0].current_health < health and (g.actor.current_health < defender_health or b.actor.current_health < b.actor.max_health), "WORLD: Guard combat uses real reciprocal damage timers")
	check(g.actor.encounter_attack_timer.time_left > 0 or b.actor.encounter_attack_timer.time_left > 0 or not enemies[0].is_alive(), "WORLD: Nearby guards can contribute individual attacks to an existing encounter")
	await fixture()
	g = guards[0]
	g.actor.position = Vector2(620,540)
	enemies[0].position = Vector2(620,405)
	enable(g)
	await frames(45)
	check(g.visible_enemies.is_empty() and g.last_seen_time < 0, "WORLD: Opaque building blocks guard knowledge inside detection radius")
	await fixture()
	physical_alarm()
	g = guards[0]
	b = guards[1]
	g.territory_margin = 2000
	b.territory_margin = 2000
	for other in guards.slice(2): other.actor.position = Vector2(2100 + guards.find(other)*20,1700)
	for civilian in civilians.slice(0,3): civilian.actor.position = Vector2(2100 + civilians.find(civilian)*20,1800)
	g.propose_cooperation(b, report_for(60004,Vector2(1510,990)))
	g.mobilizing = false # isolate waypoint execution; recruitment priority has its own regression
	b.mobilizing = false
	var agreed: Vector2 = g.alliance.point
	for task in b.memory.tasks.duplicate():
		if task.kind == b.State.INVESTIGATE: b.memory.finish(task,"canceled","adopted shared check")
	enable(g)
	enable(b)
	for i in range(600):
		await frames(1)
		if g.alliance.is_empty() and b.alliance.is_empty(): break
	print("COOP METRICS ",g.actor.position," / ",b.actor.position," agreed=",agreed," alliance=",g.alliance," / ",b.alliance)
	check(g.actor.position.distance_to(agreed) < 25 and b.actor.position.distance_to(agreed) < 25 and g.alliance.is_empty() and b.alliance.is_empty(), "WORLD: Two autonomous patrols physically converge on their communicated common point")
	await fixture()
	physical_alarm()
	g = guards[0]
	b = guards[1]
	g.territory_margin = 2000
	b.territory_margin = 2000
	g.search_seconds = 0.5
	b.search_seconds = 0.5
	for guard in [g,b]:
		guard.actor.threat_detection.recognition_delay_min = 0.05
		guard.actor.threat_detection.recognition_delay_max = 0.05
	check(g.propose_cooperation(b,report_for(60005,Vector2(1640,990))), "WORLD: Interruption fixture agrees on a waypoint beyond immediate arrival radius")
	enemies[0].position = Vector2(1500,960)
	enemies[0].infection_chance = 0
	enable(g)
	enable(b)
	await frames(60)
	check(not g.alliance.is_empty() and g.alliance.task.status == "interrupted", "WORLD: Actual enemy recognition interrupts, but preserves, the joint task")
	enemies[0].position = Vector2(100,100)
	for i in range(int((maxf(g.memory_seconds,b.memory_seconds) + 2) * 60)):
		await frames(1)
		if g.alliance.is_empty() and b.alliance.is_empty(): break
	check(g.alliance.is_empty() and b.alliance.is_empty(), "WORLD: After combat/search interruption both patrols reevaluate and finish or end cooperation within bounds")
	await fixture()
	physical_alarm()
	var civilian = civilians[0]
	civilian.actor.position = guards[0].actor.position + Vector2(0,30)
	civilian.courage = 1.0
	civilian.rng.seed = 9047
	var armed_count := 0
	for i in range(600):
		civilian.next_invitation = 0
		civilian.armed = false
		civilian.invite(guards[0])
		if civilian.armed: armed_count += 1
		civilian.release("independent sampling fixture")
	check(armed_count > 300 and armed_count < 420 and civilian.equipment_rolls == 600, "WORLD: Seeded independent recruitment decisions sample the 60 percent probability without group quotas")
	print("ARMING SAMPLE: ",armed_count," / 600")
	await fixture()
	physical_alarm()
	for i in range(guards.size()):
		guards[i].actor.position = guard_spawns[i]
	for actor in map.villagers:
		actor.autonomous_movement_enabled = true
		actor.set_physics_process(true)
		actor.threat_detection.detection_enabled = true
	var positions: Array[Vector2] = []
	for guard in guards: positions.append(guard.actor.position)
	await frames(10800) # 180 simulated seconds with all 30 inhabitants
	var moving := 0
	var followers := 0
	var valid := true
	for i in range(guards.size()):
		if guards[i].actor.position.distance_to(positions[i]) > 30: moving += 1
		followers += guards[i].followers.size()
		valid = valid and guards[i].followers.size() <= 2
		# Territorial duty constrains chosen patrol destinations. A physical path
		# may leave a narrow route corridor to navigate an obstacle or rejoin it.
		if guards[i].state == guards[i].State.ALERT_PATROL and guards[i].movement_goal.is_finite():
			valid = valid and guards[i].territory_distance(guards[i].movement_goal) <= guards[i].territory_margin
	print("WORLD METRICS: moving guards=",moving," active civilian followers=",followers)
	check(moving == 5 and valid, "WORLD: 180-second ALARM simulation moves all five defenders without crowding a single global target or violating capacities")
	map.queue_free()
	await frames(3)
	print("Guard AI world validation failures: ",failures)
	quit(1 if failures else 0)
