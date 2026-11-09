extends "res://tests/organized_defense_smoke.gd"

func run() -> void:
	await fixture()
	await frames(30)
	var civilian = civilians[0].escort
	civilian.rng.seed = 91037
	var home = civilian.actor.private_shelter_marker()
	var public_count := 0
	var home_count := 0
	for i in range(100):
		var marker = civilian.choose_safety_marker()
		if marker == home: home_count += 1
		elif marker != null and marker.name in ["Church", "Square"]: public_count += 1
	check(public_count > home_count and public_count + home_count == 100, "ALARM choices favor church and square over private shelter")
	service.release_safety(civilian.actor)
	civilian.safety_point = Vector2.INF
	civilian.alarm_home_probability = 1.0
	service.alert.bell_activated = true
	service.alert.advance_level(service.alert.Level.ALARM)
	civilian.next_decision = 0.0
	civilian.update_escort(0.016)
	check(civilian.actor.threat_reaction.seeking_home and not civilian.safety_point.is_finite(), "A home choice enters persistent S shelter behavior")
	civilian.actor.threat_reaction.update_response(0.016)
	check(civilian.actor.threat_reaction.reaction_state == civilian.actor.threat_reaction.Reaction.SEEKING_SHELTER, "Homebound civilian shows S rather than local idle walking")
	var artisan = map.get_node("Villagers/Artisan20").escort
	artisan.alarm_home_probability = 1.0
	artisan.next_decision = 0.0
	artisan.update_escort(0.016)
	check(artisan.actor.threat_reaction.seeking_home and artisan.actor.private_shelter_marker() == artisan.actor.get_node(artisan.actor.work_point_path),
		"Artisan keeps the approved workshop as its private S shelter")
	var stranded = civilians[4].escort
	stranded.actor.home_point_path = NodePath()
	stranded.actor.points_of_interest_path = NodePath()
	stranded.next_decision = 0.0
	check(stranded.update_escort(0.016) and not stranded.actor.has_destination,
		"No reachable shelter does not resume peaceful walking during ALARM")
	var priest = map.get_node("Villagers/Priest30")
	var protector = map.get_node("Villagers/PriestGuard1")
	var enemy = units[0]
	priest.global_position = formation.center
	protector.global_position = formation.center + Vector2(0, 10)
	enemy.global_position = formation.center + Vector2(0, 95)
	protector.priest_guard.observe(enemy)
	protector.priest_guard.update_ai(0.016)
	check(protector.priest_guard.movement_goal.is_finite() and protector.priest_guard.movement_goal.distance_to(enemy.global_position) < 10.0,
		"Protector intercepts a personally visible enemy approaching the priest before melee contact")
	activate()
	await frames(2)
	var defender = civilians[1]
	var companion = civilians[2]
	var extra = civilians[3]
	defender.global_position = formation.center + Vector2(-50, 0)
	companion.global_position = formation.center + Vector2(-10, 0)
	extra.global_position = formation.center + Vector2(-15, 10)
	enemy.global_position = formation.center
	var behavior = formation.controller(defender)
	var companion_behavior = formation.controller(companion)
	var extra_behavior = formation.controller(extra)
	formation.places[defender.get_instance_id()] = defender.global_position
	behavior.enemies.append(enemy)
	behavior.allies.append(companion)
	behavior.allies.append(extra)
	companion.encounter_participants.append(enemy)
	companion_behavior.target = enemy
	extra_behavior.target = enemy
	check(behavior.target_load(enemy) >= 2 and behavior.choose_target(true) == enemy,
		"Nearby defender helps an attacked neighbor across a sector boundary even when two allies already engage")
	map.queue_free()
	await frames(2)
	print("ALARM/defense regression checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
