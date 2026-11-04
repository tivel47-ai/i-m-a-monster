# Regression scenarios derived from the user's three recordings and debugger screenshots.
extends "res://tests/guard_ai_validation.gd"

func run() -> void:
	await fixture()
	var g = guards[0]
	var enemy = enemies[0]
	enemy.position = g.actor.position + Vector2(18,0)
	enemy.infection_chance = 0
	await frames(2)
	var health: float = g.actor.current_health
	for i in range(95):
		enemy.engage_defender(g.actor)
		await frames(1)
	check(g.actor.current_health < health, "BUG 1: repeated melee contact must not postpone the zombie attack timer forever")
	await fixture()
	g = guards[0]
	enemy = enemies[0]
	for other in guards.slice(1): other.actor.position = Vector2(2200,1700)
	g.actor.current_health = 15 # fixture: vulnerable guard, not a gameplay-stat change
	enemy.position = g.actor.position + Vector2(18,0)
	enemy.infection_chance = 0
	await frames(2)
	enemy.engage_defender(g.actor)
	enable(g)
	await frames(100)
	check(g.actor.is_dead(), "BUG 2: a caught retreating guard must remain in actual melee long enough for an attack")
	await blocker_test()
	await fixture()
	g = guards[0]
	var follower = civilians[0]
	follower.leader = g
	g.followers.append(follower)
	follower.actor.queue_free()
	await frames(2)
	g.maintain_followers()
	check(g.followers.is_empty(), "BUG 4: a freed follower is removed by index without typed-array erase errors")
	check(alert.quiet_period >= 60, "BUG 5: suspicion quiet period allows long village trips before score decay")
	await fixture()
	physical_alarm()
	var goals: Array[Vector2] = []
	var distributed := true
	for civilian in civilians:
		if not civilian.can_recruit(): continue
		civilian.actor.autonomous_movement_enabled = true
		civilian.update_escort(0.016)
		if civilian.safety_point.is_finite():
			for goal in goals:
				if goal.distance_to(civilian.safety_point) < 12: distributed = false
			goals.append(civilian.safety_point)
	check(goals.size() >= 15 and distributed, "BUG 6: independent alarm civilians reserve separated destinations instead of identical marker coordinates")
	await recovery_priority_test()
	map.queue_free()
	await frames(3)
	print("Guard bugfix validation failures: ",failures)
	quit(1 if failures else 0)

func blocker_test() -> void:
	await fixture()
	for guard in guards: guard.actor.position = Vector2(2200,1700)
	for civilian in civilians.slice(1): civilian.actor.position = Vector2(2200,1800)
	var attacker = enemies[0]
	var blocker = enemies[1]
	var target = civilians[0].actor
	attacker.position = Vector2(1420,960)
	blocker.position = Vector2(1460,960)
	target.position = Vector2(1530,960)
	attacker.infection_chance = 0
	blocker.navigation_agent.avoidance_enabled = true
	attacker.navigation_agent.avoidance_enabled = true
	await frames(3)
	attacker.aggro_candidates.assign([target])
	attacker.set_physics_process(true)
	for i in range(600): await frames(1)
	print("BLOCK METRICS attacker=",attacker.position," target=",target.position," hp=",target.current_health," recoveries=",attacker.navigation_recoveries," collisions=",attacker.get_slide_collision_count()," chasing=",attacker.aggro_target," nav=",attacker.navigation_agent.target_position)
	check(target.current_health < target.max_health,"BUG 3: autonomous chase navigates around a stationary allied body and actually attacks")

func recovery_priority_test() -> void:
	await fixture()
	for guard in guards: guard.actor.position = Vector2(2200,1700)
	for civilian in civilians: civilian.actor.position = Vector2(2200,1800)
	var attacker = enemies[0]
	attacker.position = Vector2(1420,960)
	await frames(2)
	attacker.issue_player_move_order(Vector2(1600,980))
	var original: Vector2 = attacker.navigation_agent.target_position
	check(attacker._try_navigation_detour(), "A blocked movement can choose a reachable temporary side point")
	guards[0].actor.position = attacker.position + Vector2(18,0)
	attacker.engage_defender(guards[0].actor)
	check(attacker.has_player_order and attacker.navigation_agent.target_position == original, "Melee contact during a detour preserves the original player destination")
	attacker.issue_player_move_order(Vector2(1450,1050))
	check(attacker.detour_remaining == 0 and attacker.recovery_attempts == 0 and attacker.navigation_agent.target_position == Vector2(1450,1050), "A new player order cancels old navigation recovery")