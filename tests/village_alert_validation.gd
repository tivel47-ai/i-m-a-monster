# Godot --headless --path . --script tests/village_alert_validation.gd --fixed-fps 60
extends "res://tests/villager_warning_validation.gd"

var alert: Node


func run() -> void:
	await check_events_and_knowledge()
	await check_combat_outcomes()
	await check_model()
	await check_large_population()
	await check_mission_lifecycle()
	print("Village alert validation failures: ", failures)
	quit(1 if failures else 0)


func check_events_and_knowledge() -> void:
	await warning_fixture()
	alert = map.get_node("VillageAlert")
	check(alert.score == 0 and alert.level == alert.Level.NORMAL and not alert.debug_enabled,
		"Fresh four-resident mission starts NORMAL with optional debug hidden")
	check(alert._registered.size() == 4, "All four residents are registered once")
	alert.initialize(map.villagers)
	check(alert._registered.size() == 4, "Initialization does not duplicate subscriptions")
	await frames(10)
	check(alert.score == 20 and alert.level == alert.Level.SUSPICION
		and alert.incident_counts.get(&"recognition", 0) == 1,
		"Real delayed direct recognition raises suspicion once")
	await frames(18)
	check(alert.score == 30 and report.has_report() and alert.incident_counts.get(&"warning", 0) == 1,
		"Completed direct WARNING contributes ten points separately from listener delivery")
	var quiet_before: float = alert.quiet_elapsed
	for i in range(100):
		resident.threat_recognized.emit(zombie)
		resident.warning_attempted.emit(resident, Vector2(880, 390))
	check(alert.score == 30 and alert.quiet_elapsed == quiet_before,
		"Repeated observations and broadcasts cannot farm points or reset quiet timer")
	receiver.set_physics_process(false)
	receiver.threat_reaction._stop_velocity()
	receiver.position = Vector2(680, 350)
	await frames(70)
	resident.warning_attempted.emit(resident, Vector2(880, 390))
	check(report.remaining > 9.9 and alert.score == 30,
		"Legitimate later local refresh does not create a new global incident")
	# A second observer of the same zombie shares the recognition key.
	map.villagers[2].threat_recognized.emit(zombie)
	check(alert.score == 30, "Different observers of the same zombie do not multiply recognition points")
	var distant = map.villagers[3]
	var before_position: Vector2 = distant.threat_reaction.threat_position
	alert._record(&"combat", 999001, 30)
	check(alert.level == alert.Level.ALARM and distant.get_recognized_threat() == null
		and not distant.local_warning.has_report() and not distant.threat_reaction.episode_active
		and distant.threat_reaction.threat_position == before_position,
		"Global ALARM grants no hidden target, report, coordinates or fleeing to distant civilian")
	var prior: float = alert.score
	receiver.threat_reaction.report_based = true
	receiver.warning_attempted.emit(receiver, Vector2(880, 390))
	check(alert.score == prior, "Warning-only recipient cannot escalate by attempting rebroadcast")
	alert.debug_enabled = true
	await frames(1)
	check(alert._debug_layer.visible and "ALARM" in alert._debug_label.text
		and "Alert Score:" in alert._debug_label.text and "Decay:" in alert._debug_label.text,
		"Optional independent debug display shows level, score and decay")
	alert.debug_enabled = false
	await frames(1)
	check(not alert._debug_layer.visible, "Debug can be hidden without touching mission HUD")
	await clear_map()


func check_combat_outcomes() -> void:
	await fixture()
	alert = map.get_node("VillageAlert")
	sensor.detection_enabled = false
	resident.begin_encounter(Color.GREEN, zombie)
	check(alert.score == 20 and alert.incident_counts.get(&"combat", 0) == 1,
		"First actual encounter contributes combat points without requiring prior recognition")
	for i in range(100):
		resident.begin_encounter(Color.GREEN, zombie)
	var second = frozen_zombie(Vector2(1000, 440))
	resident.begin_encounter(Color.GREEN, second)
	check(alert.score == 20, "Repeated calls and multiple attackers do not duplicate a continuous encounter")
	resident.cancel_encounter()
	resident.begin_encounter(Color.GREEN, zombie)
	check(alert.score == 20, "Same resident cannot farm combat points by leaving and rejoining")
	resident.take_damage(1000)
	check(alert.score == 40 and map.killed_residents == 1 and alert.incident_counts.get(&"outcome", 0) == 1,
		"Hostile death contributes one outcome and preserves mission counters")
	resident.died.emit(resident)
	resident.converted.emit(resident)
	check(alert.score == 40 and map.killed_residents == 1 and map.infected_residents == 0,
		"Repeated death/conversion notifications share one outcome key")
	map.villagers[1].take_damage(1000)
	check(alert.score == 40, "Death without a recorded hostile encounter adds no danger score")
	await clear_map()
	await fixture()
	alert = map.get_node("VillageAlert")
	sensor.detection_enabled = false
	resident.begin_encounter(Color.GREEN, zombie)
	resident.receive_zombie_attack(10, 1.0, zombie)
	resident.take_damage(1000)
	check(alert.score == 20, "Transformation and zero health during it do not prematurely count an outcome")
	await frames(130)
	check(alert.score == 40 and map.infected_residents == 1 and map.killed_residents == 0
		and alert.incident_counts.get(&"outcome", 0) == 1,
		"Real conversion contributes once before resident removal and zombie replacement")
	await clear_map()


func check_model() -> void:
	var model = load("res://scripts/village_alert.gd").new()
	root.add_child(model)
	model.set_physics_process(false)
	var transitions: Array = []
	model.level_changed.connect(func(old: int, current: int): transitions.append([old, current]))
	model._record(&"test", 1, 19)
	check(model.level == model.Level.NORMAL, "Score below suspicion threshold stays NORMAL")
	model._record(&"test", 2, 1)
	check(model.level == model.Level.SUSPICION, "Exact threshold twenty enters SUSPICION")
	model._record(&"test", 3, 40)
	check(model.level == model.Level.ALARM, "Exact threshold sixty enters ALARM")
	model._record(&"test", 4, 1000)
	check(model.score == 100 and model.level == model.Level.ALARM, "Score is capped and organized defense is unreachable")
	model.quiet_period = 1
	model.decay_per_second = 10
	model._physics_process(0.75)
	check(model.score == 100 and not model.decay_active, "Quiet period postpones decay")
	model._physics_process(0.5)
	check(is_equal_approx(model.score, 97.5) and model.decay_active,
		"Decay credits only frame fraction beyond quiet boundary")
	model._record(&"test", 5, 1)
	check(model.quiet_elapsed == 0 and not model.decay_active, "A new meaningful incident interrupts decay")
	model._physics_process(5.3)
	check(is_equal_approx(model.score, 55.5) and model.level == model.Level.ALARM,
		"Hysteresis retains ALARM below rise threshold until lower boundary")
	model._physics_process(0.05)
	check(is_equal_approx(model.score, 55) and model.level == model.Level.SUSPICION,
		"ALARM drops at provisional fifty-five boundary")
	model._physics_process(3.95)
	check(is_equal_approx(model.score, 15.5) and model.level == model.Level.SUSPICION,
		"Suspicion is retained above lower fifteen boundary")
	model._physics_process(0.05)
	check(is_equal_approx(model.score, 15) and model.level == model.Level.NORMAL,
		"Suspicion drops to NORMAL at fifteen")
	model._record(&"test", 6, 1)
	check(model.level == model.Level.NORMAL, "Small increase after demotion does not oscillate into suspicion")
	model._physics_process(100)
	check(model.score == 0 and model.level == model.Level.NORMAL and not model.decay_active
		and transitions.size() == 4, "Quiet mission eventually reaches zero with exactly four stable transitions")
	model.queue_free()
	await frames(2)
	# Editable thresholds, contributions and frame-rate-independent time.
	for fps in [30, 60, 120]:
		model = load("res://scripts/village_alert.gd").new()
		root.add_child(model)
		model.set_physics_process(false)
		model.max_score = 80
		model.suspicion_threshold = 10
		model.alarm_threshold = 30
		model.quiet_period = 1
		model.decay_per_second = 5
		model._record(&"test", 1, 40)
		for i in range(3 * fps): model._physics_process(1.0 / fps)
		check(absf(model.score - 30) < 0.001 and model.level == model.Level.ALARM,
			"Editable settings and consistent physics delta at %d FPS" % fps)
		model.queue_free()
		await frames(2)


func check_large_population() -> void:
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	alert = map.get_node("VillageAlert")
	for civilian in map.villagers:
		civilian.autonomous_movement_enabled = false
		civilian.threat_detection.detection_enabled = false
	for unit in get_nodes_in_group("player_units"):
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	await frames(5)
	for attempt in range(120):
		var nav_point := NavigationServer2D.map_get_closest_point(map.get_world_2d().navigation_map, Vector2(1520, 947))
		if nav_point.distance_to(Vector2(1520, 947)) < 1:
			break
		await frames(1)
	check(map.total_residents == 30 and alert._registered.size() == 30 and alert.score == 0,
		"Large mission registers all thirty civilian roles without specialized controllers")
	var target = get_nodes_in_group("player_units")[0]
	# Deliver the existing contracts from every registered source, without forcing
	# thirty NPCs into a geometry-dependent visual/combat fixture at once.
	for civilian in map.villagers:
		for duplicate in range(10): civilian.threat_recognized.emit(target)
	check(alert.score == 20 and alert.incident_counts.get(&"recognition", 0) == 1,
		"Three hundred recognition notifications across thirty residents remain one incident")
	for civilian in map.villagers:
		civilian.threat_reaction.episode_active = true
		civilian.threat_reaction.warning_sent = true
		civilian.threat_reaction.threat_id = target.get_instance_id()
		civilian.warning_attempted.emit(civilian, target.global_position)
	check(alert.score == 30 and alert.incident_counts.get(&"warning", 0) == 1,
		"Thirty valid warning sources about one zombie contribute only once")
	var last = map.villagers[29]
	last.begin_encounter(Color.GREEN, target)
	check(alert.score == 50 and alert.incident_counts.get(&"combat", 0) == 1,
		"Last registered resident can report combat independently of profession")
	last.take_damage(1000)
	check(alert.score == 70 and alert.level == alert.Level.ALARM and map.killed_residents == 1
		and map.mission_state == map.MissionState.ACTIVE,
		"Large mission escalates from events without changing victory objective or outcome")
	for civilian in map.villagers:
		if civilian.is_available_for_infection(): civilian.begin_encounter(Color.GREEN, target)
	check(alert.score == 100 and alert.level != alert.Level.ORGANIZED_DEFENSE,
		"Thirty-resident event batch is capped and never activates defense")
	await clear_map()


func check_mission_lifecycle() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(3)
	for mission_id in ["village", "village", "mission_1", "village"]:
		app.selected_mission = mission_id
		app.selected_race = "zombie"
		app.screen = app.Screen.RACES
		app._start_mission()
		alert = app.mission.get_node("VillageAlert")
		check(alert.score == 0 and alert.level == alert.Level.NORMAL and alert._seen.is_empty(),
			"Menu launch/restart/switch starts isolated alert state: %s" % mission_id)
		alert.quiet_period = 0
		alert._record(&"test", 1, 70)
		app._pause()
		var before: float = alert.score
		var timer: float = alert.quiet_elapsed
		await frames(30)
		check(paused and alert.score == before and alert.quiet_elapsed == timer,
			"Existing menu pause freezes alert score and simulated clock: %s" % mission_id)
		app._resume()
		await frames(3)
		check(alert.score < before, "Existing resume restarts decay")
		app._on_mission_finished("victory", {"total": app.mission.total_residents, "infected": 0, "killed": 0})
		before = alert.score
		timer = alert.quiet_elapsed
		await frames(5)
		check(alert.score == before and alert.quiet_elapsed == timer,
			"Mission result disables alert together with gameplay")
		app._dispose_mission()
		await frames(3)
	app.queue_free()
	await frames(3)
