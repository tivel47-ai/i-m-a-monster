extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func observe_corpses(actor: Node2D) -> void:
	actor.threat_detection.detection_enabled = true
	actor.get_node("CorpsePerception")._physics_process(1.0)


func run() -> void:
	var mission := MISSION.instantiate()
	root.add_child(mission)
	var defense: Node = mission.get_node("VillageDefense")
	var alert: Node = defense.alert
	var residents: Node = mission.get_node("Villagers")
	for actor in mission.villagers:
		actor.set_physics_process(false)
		actor.threat_detection.detection_enabled = false
		actor.get_node("CorpsePerception").set_physics_process(false)
		actor.autonomous_movement_enabled = false
		actor.global_position = Vector2(100, 100)

	var center: Vector2 = mission.get_node("VillagePointsOfInterest/Square").global_position
	var body: Node2D = residents.get_node("Guard25")
	var runner: Node2D = residents.get_node("Guard26")
	var busy: Node2D = residents.get_node("Guard27")
	var replacement: Node2D = residents.get_node("Guard28")
	var witness: Node2D = residents.get_node("Peasant1")
	var civilian_body: Node2D = residents.get_node("Peasant2")
	body.global_position = center + Vector2(30, 0)
	runner.global_position = center + Vector2(0, -20)
	busy.global_position = center + Vector2(0, 20)
	replacement.global_position = center + Vector2(-30, 20)
	witness.global_position = center + Vector2(-5, 20)
	for actor in [runner, busy, replacement, witness]:
		actor.autonomous_movement_enabled = true
	for step in 120:
		await physics_frame
		if (NavigationServer2D.map_get_iteration_id(runner.navigation_agent.get_navigation_map()) > 0
			and defense.alarm_point(runner).is_finite()):
			break

	body.take_damage(1000.0)
	var id := body.get_instance_id()
	observe_corpses(runner)
	check(alert.level == alert.Level.SUSPICION and runner.guard_ai.has_confirmed_death_alarm(),
		"Personal sight of a fallen guard immediately assigns the physical bell task")
	observe_corpses(replacement)
	check(not replacement.guard_ai.has_confirmed_death_alarm(),
		"Repeated observation does not duplicate an existing living guard's bell task")

	runner.global_position = center + Vector2(450, 0)
	runner.take_damage(1000.0)
	check(alert.level == alert.Level.SUSPICION and alert.registered_corpses.has(id),
		"A dead runner leaves one registered incident and no alarm")
	observe_corpses(replacement)
	check(replacement.guard_ai.has_confirmed_death_alarm()
		and int(alert.incident_counts.get(&"defender_loss", 0)) == 1,
		"Another guard can take the same body to the bell without counting the death twice")

	replacement.guard_ai.finish("infeasible", "fixture blocks the first replacement")
	var helper: Node2D = residents.get_node("Guard29")
	helper.autonomous_movement_enabled = true
	helper.global_position = center + Vector2(-25, 20)
	replacement.global_position = Vector2(100, 100)
	replacement.autonomous_movement_enabled = false
	observe_corpses(witness)
	var reporter: RefCounted = witness.escort.reporter
	check(int(reporter.report.get("incident", 0)) == id, "Civilian can report the original body after a failed bell attempt")
	reporter._request_visible_guard()
	check(reporter.assigned_guard() == busy.guard_ai, "Initially the messenger approaches the nearest free guard")
	var existing_task := {"kind": busy.guard_ai.State.INVESTIGATE}
	busy.guard_ai.active = existing_task
	reporter.update(0.0)
	reporter._request_visible_guard()
	check(reporter.assigned_guard() == helper.guard_ai, "Messenger chooses a free guard over the nearer investigating guard")
	reporter.update(0.0)
	check(busy.guard_ai.active == existing_task and helper.guard_ai.investigation.is_investigating_corpse(id)
		and not helper.guard_ai.has_confirmed_death_alarm(),
		"Report sends the free guard to investigate before personal confirmation")
	observe_corpses(helper)
	check(helper.guard_ai.has_confirmed_death_alarm() and not alert.bell_activated,
		"Personal confirmation replaces the investigation with a bell task")

	civilian_body.global_position = center + Vector2(-35, 45)
	civilian_body.take_damage(1000.0)
	observe_corpses(busy)
	var civilian_id := civilian_body.get_instance_id()
	alert.first_corpse_probability = 1.0
	var first_decision: bool = alert.decide_corpse_alarm([civilian_id])
	observe_corpses(helper)
	check(first_decision and not alert.decide_corpse_alarm([civilian_id])
		and alert.registered_civilian_corpses == 1,
		"Civilian remains registered once with a single chance to raise the alarm")

	helper.global_position = helper.guard_ai.active.point
	helper.guard_ai.update_ai(defense.bell_interaction_seconds + 0.1)
	check(alert.level == alert.Level.ALARM and helper.global_position.distance_to(defense.bell.global_position) <= defense.bell_reach,
		"Replacement raises ALARM through actual interaction in bell range")
	observe_corpses(busy)
	check(is_zero_approx(alert.danger), "Previously registered bodies still add no danger after the bell")
	mission.queue_free()
	await process_frame
	print("Guard corpse alarm validation failures: ", failures)
	quit(1 if failures else 0)
