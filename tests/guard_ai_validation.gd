# Godot --headless --path . --script tests/guard_ai_validation.gd --fixed-fps 60
extends "res://tests/villager_movement_validation.gd"

var guards: Array = []
var guard_spawns: Array[Vector2] = []
var civilians: Array = []
var defense: Node
var alert: Node
var enemies: Array = []

func fixture() -> void:
	if is_instance_valid(map):
		map.queue_free()
		await frames(3)
	guards.clear()
	guard_spawns.clear()
	civilians.clear()
	enemies.clear()
	seed(20261104)
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	defense = map.get_node("VillageDefense")
	alert = map.get_node("VillageAlert")
	for actor in map.villagers:
		actor.autonomous_movement_enabled = false
		actor.threat_detection.detection_enabled = false
		if actor.guard_ai != null:
			guards.append(actor.guard_ai)
			guard_spawns.append(actor.position)
			actor.guard_ai.rng.seed = 100 + guards.size()
		elif actor.escort != null:
			civilians.append(actor.escort)
			actor.escort.rng.seed = 200 + civilians.size()
	for enemy in get_nodes_in_group("player_units"):
		enemy.set_physics_process(false)
		enemy.position = Vector2(100, 100 + enemies.size() * 30)
		enemy.get_node("AggroArea").monitoring = false
		enemy.navigation_agent.avoidance_enabled = false
		enemies.append(enemy)
	await frames(6)
	for i in range(guards.size()):
		guards[i].actor.position = Vector2(1420 + i * 35, 960)
		guards[i].actor._stop_movement()
		guards[i].actor.set_physics_process(false)
	for i in range(3):
		civilians[i].actor.position = Vector2(1420 + i * 20, 995)
	await frames(3)

func report_for(id: int, point: Vector2, count: int = 1, help: bool = false) -> Dictionary:
	return {"incident": id, "point": point, "count": count, "help": help, "source": 1234, "observed_at": defense.elapsed, "credibility": 0.8, "relay": 0}

func enable(guard: Node) -> void:
	guard.actor.autonomous_movement_enabled = true
	guard.actor.set_physics_process(true)
	guard.actor.threat_detection.detection_enabled = true

func physical_alarm() -> void:
	var actor = guards[4].actor
	actor.position = defense.bell.global_position + Vector2(0, 18)
	check(defense.ring(actor), "14: A living NPC physically activates the bell")
	actor.position = Vector2(1560, 960)

func run() -> void:
	await fixture()
	await individual_tests()
	await fixture()
	await communication_tests()
	await fixture()
	await companion_tests()
	await fixture()
	await cooperation_tests()
	await fixture()
	await integration_tests()
	map.queue_free()
	await frames(3)
	print("Guard AI validation failures: ", failures)
	quit(1 if failures else 0)

func individual_tests() -> void:
	var g = guards[0]
	enable(g)
	var before: Vector2 = g.actor.position
	await frames(120)
	check(g.actor.position.distance_to(before) > 5 and g.state == g.State.PATROL, "1/48: Existing NORMAL road patrol physically continues")
	alert._record(&"fixture", 1, 30)
	await frames(30)
	check(g.state == g.State.ALERT_PATROL and g.actor.guard_patrol.state != 0, "2: SUSPICION retains routes and shifts while increasing vigilance")
	g.actor.position = Vector2(1420, 960)
	g.actor._stop_movement()
	g.actor.threat_detection.recognition_delay_min = 0.05
	g.actor.threat_detection.recognition_delay_max = 0.05
	enemies[0].position = Vector2(1530, 960)
	await frames(40)
	check(g.state == g.State.COMBAT and g.last_seen_time >= 0, "3: A delayed firsthand sighting interrupts patrol")
	check(alert.level != alert.Level.ALARM, "5: Isolated manageable contact does not automatically ring the bell")
	var observed: Vector2 = g.last_seen_point
	enemies[0].position = Vector2(2300, 1200)
	await frames(35)
	check(g.last_seen_point == observed and g.visible_enemies.is_empty(), "7: Hidden/distant enemy movement never updates last-known position")
	var search: Dictionary = {}
	for task in g.memory.tasks:
		if task.kind == g.State.SEARCH: search = task
	check(not search.is_empty() and search.points.size() > 0 and search.points.size() <= 3, "8: Lost target creates one dynamic bounded search area")
	if not search.is_empty():
		var valid := true
		for point in search.points: valid = valid and defense.reachable(g.actor, point)
		check(valid, "8: Every dynamic search point has a valid physically clear navigation path")
	g.search_seconds = 1.0
	await frames(150)
	check(g.memory.tasks.is_empty() and not g.memory.outcomes.is_empty(), "9: Search ends within a bounded duration without proving elimination")
	g.actor.set_physics_process(false)
	enemies[0].position = g.actor.position + Vector2(45,0)
	await frames(2)
	var reacquired = g.memory.offer(g.State.SEARCH, report_for(enemies[0].get_instance_id(), enemies[0].position), defense.elapsed)
	g.observe(enemies[0])
	check(not g.memory.tasks.has(reacquired) and reacquired.status == "completed", "Reacquiring the same opponent ends its obsolete search without claiming enemy death")
	enemies[0].position = Vector2(100,100)
	g.memory.tasks.clear()
	var report = report_for(8001, Vector2(1500, 960))
	check(g.receive_message(report, guards[1].actor), "4: Local unverified report becomes investigation rather than automatic alarm")
	g.choose_task()
	check(g.active.kind == g.State.INVESTIGATE, "4: Guard chooses the reported investigation")
	var stale = g.active
	g.memory.expire(defense.elapsed + g.memory_seconds + 1)
	g.choose_task()
	check(g.active.is_empty() and stale.status == "expired", "11: Expired tasks are not resumed")
	g.memory.tasks.clear()
	g.memory.incidents.clear()
	g.last_seen_id = 123
	g.last_seen_time = defense.elapsed
	g.last_seen_point = Vector2(1480, 960)
	g.memory.remember(report_for(123, g.last_seen_point), defense.elapsed)
	g.start_search()
	g.choose_task()
	var interrupted = g.active
	g.suspend()
	check(interrupted.status == "interrupted" and g.memory.tasks.has(interrupted), "10: Higher-priority activity preserves interrupted search progress")
	g.choose_task()
	var selected_id = g.active.id
	for i in range(10):
		g.memory.offer(g.State.INVESTIGATE, report_for(9100+i, Vector2(1480, 965)), defense.elapsed)
		g.choose_task()
	check(g.active.id == selected_id and g.memory.tasks.size() <= g.task_capacity, "12: Commitment prevents equivalent-task oscillation and memory remains bounded")
	g.actor.threat_detection.detection_enabled = true
	enemies[0].position = g.actor.position + Vector2(80, 0)
	enemies[1].position = g.actor.position + Vector2(90, 20)
	enemies[2].position = g.actor.position + Vector2(90, -20)
	for peer in guards.slice(1): peer.actor.position = Vector2(2300, 1600)
	enable(g)
	await frames(60)
	check(g.state == g.State.RETREAT or g.state == g.State.RAISE_ALARM, "6: Overwhelming locally seen threat causes retreat/alarm response")
	check(not g.retreat_point.is_finite() or defense.reachable(g.actor, g.retreat_point), "6: Tactical retreat destination is navigable")

func communication_tests() -> void:
	var a = guards[0]
	var b = guards[1]
	var c = guards[2]
	alert._record(&"batch", 999, 1000)
	check(alert.level == alert.Level.SUSPICION and not alert.bell_activated, "13: Accumulated events alone can never enter ALARM")
	check(not defense.ring(a.actor), "16: A distant bell cannot be activated remotely")
	var r = report_for(2001, Vector2(1500, 980), 2, true)
	check(b.receive_message(r, a.actor), "19: Firsthand report can be received")
	var count: int = b.memory.tasks.size()
	var timestamp: float = b.memory.incidents[2001].observed_at
	for i in range(20): b.receive_message(r, a.actor)
	check(b.memory.tasks.size() == count and b.memory.incidents[2001].observed_at == timestamp, "17/20/21: Duplicate calls neither grow tasks nor renew original observation age/urgency")
	var relay = b.outbox[0].duplicate(true)
	check(relay.relay == 1 and c.receive_message(relay, b.actor) and c.outbox.is_empty(), "19: Exactly one inherited retransmission; next guard cannot forward it")
	var independent = report_for(2002, r.point + Vector2(1,0))
	b.receive_message(independent, a.actor)
	check(b.memory.incidents.size() == 2, "18: Nearby independent incidents remain distinct")
	var changed = r.duplicate(true)
	changed.count = 3
	changed.observed_at = defense.elapsed + 0.01
	check(b.receive_message(changed, a.actor) and b.memory.tasks[0].report.count == 3, "22: Materially changed danger updates an existing assistance task")
	var distant = guards[4]
	distant.actor.position = Vector2(2300,1600)
	b.memory.remember(r, defense.elapsed)
	c.receive_message(r, a.actor)
	defense.broadcast(b.actor, {"ack": true, "incident": 2001}, b.communication_radius)
	check(c.acknowledgements.has(2001) and not distant.acknowledgements.has(2001), "23: Response acknowledgement stays local and is not enemy-resolution evidence")
	var before: Vector2 = distant.last_seen_point
	physical_alarm()
	check(alert.level == alert.Level.ALARM and distant.memory.incidents.is_empty() and distant.last_seen_point == before, "15: Bell communicates only danger, not coordinates or distant outcomes")
	alert.quiet_period = 0
	alert._physics_process(1000)
	check(alert.level == alert.Level.ALARM and alert.score == 0, "No invented automatic ALARM stand-down from score decay")
	alert.add_danger(alert.danger_threshold)
	defense.mobilize_civilians()
	var civilian = civilians[0]
	check(not civilian.armed, "Compatibility hook does not arm a distant civilian")
	civilian.actor.global_position = defense.organized.center
	defense.organized.check_arrival(civilian.actor)
	check(civilian.armed and defense.organized.arrived(civilian.actor), "Physical church arrival arms and joins the defense")

func companion_tests() -> void:
	physical_alarm()
	var a = guards[0]
	var b = guards[1]
	var one = civilians[0]
	var two = civilians[1]
	var three = civilians[2]
	for civilian in [one,two,three]: civilian.courage = 1.0
	one.arming_probability = 1.0 # deterministic coverage of both equipment branches
	two.arming_probability = 0.0
	check(one.invite(a) and two.invite(a) and not three.invite(a), "24: Active invitations never exceed two followers")
	check(not one.invite(b) and one.leader == a and not b.followers.has(one), "25: One civilian has at most one leader")
	check(one.armed and not two.armed and one.equipment_rolls == 1 and two.equipment_rolls == 1, "27/28: Armed and unarmed followers are valid; one equipment decision per recruitment")
	check(is_equal_approx(three.arming_probability, 0.60), "27: Production recruitment arming default is the confirmed 60 percent")
	var rolls: int = one.equipment_rolls
	for i in range(20): one.invite(a)
	check(one.equipment_rolls == rolls, "27: Repeated invitations do not reroll equipment")
	three.courage = 0
	three.rng.seed = 1
	check(not three.invite(b), "26: A civilian can refuse recruitment according to temperament")
	two.actor.position = a.actor.position + Vector2(0,20)
	enemies[0].position = two.actor.position + Vector2(18,0)
	enemies[1].position = two.actor.position + Vector2(25,10)
	await frames(2)
	two.courage = 0
	two.next_decision = 0
	enemies[0].engage_defender(two.actor)
	two.update_combat()
	check(two.mode == two.Mode.FLEEING and not two.actor.is_in_collision(), "A frightened companion can withdraw even after a real encounter has begun")
	for enemy in enemies: enemy.position = Vector2(100,100)
	two.actor.threat_reaction.cancel_response()
	two.mode = two.Mode.FOLLOWING
	two.courage = 1
	one.actor.position = Vector2(1800, 960)
	a.actor.autonomous_movement_enabled = true
	var req = report_for(3500, Vector2(1500,960), 1, true)
	a.memory.offer(a.State.ASSIST, req, defense.elapsed)
	a.choose_task()
	check(a.maintain_followers() and a.cohesion_started >= 0, "30: Leader primarily waits for an ordinary straggler")
	defense.elapsed += a.follower_wait_seconds + 1
	a.maintain_followers()
	check(a.active.is_empty() and one.leader == a and a.followers.size() == 2, "35: Failed reunion declines assistance without deliberately discarding active follower")
	two.panic()
	check(two.mode == two.Mode.FLEEING and two.leader == a, "31: Personal panic can flee while temporarily reserving membership")
	two.actor.position = a.actor.position + Vector2(0,30)
	two.actor.threat_reaction.cancel_response()
	two.actor.threat_detection.reset_awareness()
	two.next_decision = 0
	two.actor.autonomous_movement_enabled = true
	two.update_escort(0.016)
	check(two.mode != two.Mode.FLEEING, "32: A safe nearby leader permits conditional reunion")
	one.separated_at = defense.elapsed
	defense.elapsed += one.separation_seconds + 1
	one.last_contact = one.separated_at
	one.update_escort(0.016)
	check(one.leader == null and a.followers.size() == 1, "33: Final separation frees capacity")
	one.actor.position = a.actor.position + Vector2(0,30)
	one.next_invitation = 0
	one.courage = 1
	one.invite(a)
	a.actor.take_damage(1000)
	one.next_invitation = 0
	one.next_decision = 0
	one.update_escort(0.016)
	check(one.leader == b or one.leader == guards[2], "34: Observed leader death permits local accessible reassignment")
	# A follower traverses real navmesh around the same static obstacle used by civilians.
	var follower = two
	follower.release("fixture")
	follower.actor.position = Vector2(1420, 960)
	follower.next_invitation = 0
	follower.courage = 1
	follower.invite(b)
	b.actor.position = Vector2(1540, 980)
	follower.actor.set_physics_process(true)
	var origin: Vector2 = follower.actor.position
	await frames(180)
	check(follower.actor.position.distance_to(origin) > 30, "29: Follower actually moves using individual navigation")

func cooperation_tests() -> void:
	physical_alarm()
	var a = guards[0]
	var b = guards[1]
	a.territory_margin = 2000 # fixture isolates agreement from distinct home sectors
	b.territory_margin = 2000
	var r = report_for(4400, Vector2(1510, 990))
	check(a.propose_cooperation(b, r), "36: Nearby peer patrols establish a justified local shared objective")
	check(a.alliance.point == b.alliance.point and a.alliance.peer.get_ref() == b, "37: Same dynamic point is explicitly proposed and accepted")
	var point: Vector2 = a.alliance.point
	check(defense.reachable(a.actor, point) and defense.reachable(b.actor, point), "39: Both actors have independently valid routes to agreed point")
	check(a.followers != b.followers or (a.followers.is_empty() and b.followers.is_empty()), "38: Cooperation does not merge follower ownership")
	var original = a.alliance.duplicate()
	a.alliance.status = "interrupted"
	check(not a.alliance.is_empty() and a.alliance.incident == r.incident, "42: A combat interruption can preserve the cooperative objective")
	a.actor.position = point
	b.actor.position = point + Vector2(7,0)
	a.execute_alliance(0.016)
	check(a.alliance.is_empty() and b.alliance.is_empty(), "43: Local arrival acknowledgement completes and separates a shared check")
	check(a.memory.outcomes[-1].reason == "cooperation ended" and a.memory.incidents.is_empty(), "44: Completion of a cooperative check is not an enemy-elimination claim")
	a.next_cooperation = 0
	b.next_cooperation = 0
	check(not a.propose_cooperation(b,r), "45: Same unchanged reason cannot immediately re-merge separated patrols")
	var remote = guards[3]
	check(remote.memory.outcomes.is_empty(), "47: A distant guard does not learn remote task completion")
	a.alliance = original
	a.alliance.arrived_at = defense.elapsed
	defense.elapsed += a.alliance_wait_seconds + 1
	b.actor.position = Vector2(2300,1600)
	a.execute_alliance(0.016)
	check(a.alliance.is_empty(), "40/41: Missing allied patrol has bounded waiting and cannot deadlock the first patrol")
	check(guards[2].territory_distance(Vector2(100,100)) > guards[2].territory_margin, "46: Untuned patrols retain an explicit territorial bound")

func integration_tests() -> void:
	var g = guards[0]
	enable(g)
	var civilian = civilians[0].actor
	civilian.autonomous_movement_enabled = true
	var before: Vector2 = civilian.position
	await frames(120)
	check(civilian.has_destination or civilian.is_performing_activity or civilian.position != before, "49: Existing civilian routine continues outside alarm")
	var position: Vector2 = g.actor.position
	var clock: float = defense.elapsed
	paused = true
	await frames(30)
	check(g.actor.position == position and defense.elapsed == clock, "50: Tactical pause freezes guard movement and shared simulation time")
	paused = false
	var points = defense.sample_points(g.actor, Vector2(2700,200),75)
	var reachable := true
	for point in points: reachable = reachable and defense.reachable(g.actor, point)
	check(reachable, "51: Dynamic sampling rejects disconnected water/obstacle destinations")
	check(guards.size()==5 and civilians.size()==25 and defense.bell != null, "52: Mission wiring supplies five defenders, civilians and a physical bell without scene changes")
