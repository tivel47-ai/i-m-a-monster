# Regression from recording 17_52_58: actual escape cries and durable refuge.
extends "res://tests/guard_ai_validation.gd"

func isolate() -> void:
	for guard in guards: guard.actor.position = Vector2(2600, 1700)
	for civilian in civilians:
		civilian.actor.position = Vector2(2600, 1800)
		# Isolate the home fallback; eyewitness dispatch has its own world tests.
		civilian.report_to_guard_enabled = false

func start_witness() -> Node2D:
	var actor = civilians[0].actor
	actor.position = Vector2(1500, 1000)
	actor.autonomous_movement_enabled = true
	actor.threat_detection.detection_enabled = true
	actor.threat_detection.recognition_delay_min = 0.05
	actor.threat_detection.recognition_delay_max = 0.05
	actor.threat_reaction.flee_weight = 1
	actor.threat_reaction.shelter_weight = 0
	actor.threat_reaction.warning_weight = 0
	actor.threat_reaction.frozen_weight = 0
	actor.threat_reaction.reaction_random.seed = 304
	enemies[0].position = Vector2(1580, 1000)
	return actor

func run() -> void:
	await fixture()
	isolate()
	var witness = start_witness()
	var listener = civilians[1].actor
	listener.position = Vector2(1340, 1000)
	listener.autonomous_movement_enabled = true
	listener.threat_reaction.reaction_random.seed = 305
	var second_hop = civilians[2].actor
	second_hop.position = Vector2(1180, 1000)
	await frames(30)
	check(witness.threat_reaction.episode_active and witness.threat_reaction.reaction_state == witness.threat_reaction.Reaction.FLEEING,
		"A firsthand witness actually flees without rolling stationary W")
	check(witness.local_warning.notifications_delivered > 0 and listener.local_warning.has_report() and alert.score == alert.recognition_points,
		"A cry during actual flight reaches a local listener and raises public suspicion")
	check(not second_hop.local_warning.has_report() and listener.local_warning.notifications_delivered == 0,
		"Hearing alone cannot propagate a recursive warning to the next street")
	check(alert.level == alert.Level.SUSPICION and not alert.bell_activated,
		"An audible warning raises suspicion without remotely activating the bell")
	enemies[0].position = Vector2(100, 100)
	await frames(180)
	var snapshot: Vector2 = witness.local_warning.firsthand_report.point
	await frames(7200)
	for actor in [witness, listener]:
		var response = actor.threat_reaction
		var home = actor.get_node(actor.home_point_path)
		check(response.seeking_home and response.sheltered_at_home and not response.episode_active and not response.has_route
			and response.reaction_state == response.Reaction.SEEKING_SHELTER and actor.position.distance_to(home.position) <= 36 + actor.arrival_tolerance,
			"Witness and warned survivor reach their own exterior home and remain S beyond all short timeouts: %s" % actor.name)
		check(not actor.has_destination and not actor.is_performing_activity and actor.current_activity == actor.Activity.NONE,
			"Home refuge cannot fall through into ordinary work or social activity: %s" % actor.name)
	check(not listener.local_warning.has_report() and witness.local_warning.firsthand_report.point == snapshot,
		"Expired reported coordinates do not track a hidden enemy or erase the refuge decision")
	var home_position: Vector2 = witness.position
	await frames(600)
	check(witness.position.distance_to(home_position) < 1 and witness.threat_reaction.sheltered_at_home,
		"A sheltered survivor keeps standing S instead of walking back to the attack site")
	paused = true
	var clock: float = defense.elapsed
	await frames(30)
	check(defense.elapsed == clock and witness.position == home_position, "Pause freezes refuge and communication clocks")
	paused = false
	enemies[0].position = witness.position + Vector2(60, 0)
	await frames(35)
	check(witness.threat_reaction.episode_active and not witness.threat_reaction.sheltered_at_home,
		"A new personally visible monster interrupts S and resumes immediate survival")
	witness.take_damage(5)
	check(witness.current_health == witness.max_health - 5, "Standing at a home grants no immunity or barricade")
	await fixture()
	isolate()
	witness = start_witness()
	await frames(90)
	check(witness.local_warning.notifications_delivered == 0 and alert.score == 0,
		"Actual cries from an isolated fleeing witness do not create omniscient village knowledge")
	witness.begin_encounter(Color.GREEN, enemies[0])
	witness.take_damage(1000)
	await frames(3)
	check(alert.score == 0 and not witness.threat_reaction.seeking_home and not witness.threat_reaction.has_route,
		"An unheard attack/death still awards no public points and clears refuge state")
	await fixture()
	isolate()
	witness = start_witness()
	await frames(30)
	var old_report: Dictionary = witness.local_warning.firsthand_report.duplicate()
	enemies[0].position = Vector2(100, 100)
	await frames(330)
	listener = civilians[1].actor
	listener.position = witness.position + Vector2(20, 0)
	await frames(65)
	check(listener.local_warning.has_report() and listener.local_warning.remaining < 6
		and witness.local_warning.firsthand_report.observed_at == old_report.observed_at,
		"A witness meeting a listener later transmits the original age rather than a fresh ten-second rumor")
	await frames(600)
	check(not listener.local_warning.has_report(), "A lost sighting eventually stops being transmitted")
	await fixture()
	isolate()
	witness = start_witness()
	var guard = guards[0]
	guard.actor.position = Vector2(1360, 1000)
	await frames(30)
	check(guard.memory.incidents.has(enemies[0].get_instance_id()) and alert.score > 0,
		"A nearby guard receives a fleeing civilian's real firsthand incident through the existing protocol")
	# Physical alarm and voluntary recruitment may supersede the refuge plan.
	physical_alarm()
	witness.position = guard.actor.position + Vector2(20, 0)
	civilians[0].courage = 1
	civilians[0].next_invitation = 0
	check(civilians[0].invite(guard), "An alarmed witness can still accept a local guard's invitation")
	enemies[0].position = Vector2(100, 100)
	await frames(20)
	check(civilians[0].leader == guard and not witness.threat_reaction.episode_active,
		"Following a recruited guard overrides the independent home movement")
	civilians[0].release("regression")
	await frames(10)
	check(witness.threat_reaction.seeking_home, "Leaving a group preserves the survivor's home fallback")
	await fixture()
	isolate()
	witness = civilians[0].actor
	witness.position = Vector2(1500, 1000)
	witness.autonomous_movement_enabled = true
	enemies[0].position = witness.position + Vector2(18, 0)
	witness.begin_encounter(Color.GREEN, enemies[0])
	check(witness.threat_reaction.seeking_home and not witness.threat_reaction.episode_active,
		"An ambushed survivor remembers danger even when combat precedes visual recognition")
	witness.leave_encounter(enemies[0])
	enemies[0].position = Vector2(100, 100)
	await frames(3600)
	print("AMBUSH REFUGE position=", witness.position, " home=", witness.get_node(witness.home_point_path).position,
		" goal=", witness.threat_reaction.home_destination, " has_route=", witness.threat_reaction.has_route,
		" seeking=", witness.threat_reaction.seeking_home, " state=", witness.infection_state, " velocity=", witness.velocity)
	check(witness.threat_reaction.sheltered_at_home and witness.current_activity == witness.Activity.NONE,
		"An ambushed survivor physically reaches home after combat instead of resuming work")
	witness.begin_encounter(Color.GREEN, enemies[0])
	witness.receive_zombie_attack(20, 1.0, enemies[0])
	check(not witness.threat_reaction.seeking_home and not witness.threat_reaction.has_route,
		"Transformation clears persistent refuge and movement immediately")
	map.queue_free()
	await frames(3)
	print("Civilian fear validation failures: ", failures)
	quit(1 if failures else 0)
