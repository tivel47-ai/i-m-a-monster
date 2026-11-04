# Godot --headless --path . --script tests/village_alert_validation.gd --fixed-fps 60
extends "res://tests/villager_warning_validation.gd"
var alert: Node

func run() -> void:
	await check_events_and_knowledge()
	await check_private_combat()
	await check_model()
	await check_large_population()
	await check_mission_lifecycle()
	print("Village alert validation failures: ",failures)
	quit(1 if failures else 0)

func check_events_and_knowledge() -> void:
	await warning_fixture()
	alert=map.get_node("VillageAlert")
	check(alert._registered.size()==4 and alert.score==0 and alert.level==alert.Level.NORMAL,"Fresh mission registers four residents with no public information")
	alert.initialize(map.villagers)
	check(alert._registered.size()==4,"Repeated initialization does not duplicate registration")
	await frames(10)
	check(alert.score==0,"Private visual recognition does not inform the village")
	await frames(18)
	check(report.has_report() and alert.score==20 and alert.incident_counts.get(&"communicated",0)==1,"Completed audible WARNING contributes only after a real local delivery")
	var clock:float=alert.quiet_elapsed
	for i in range(100):
		resident.threat_recognized.emit(zombie)
		resident.warning_attempted.emit(resident,Vector2(880,390))
	check(alert.score==20 and alert.quiet_elapsed==clock,"Duplicate observations and local deliveries do not renew public evidence")
	var distant=map.villagers[2]
	check(distant.get_recognized_threat()==null and not distant.local_warning.has_report(),"Public suspicion does not expose hidden coordinates to a distant NPC")
	alert.debug_enabled=true
	await frames(1)
	check(alert._debug_layer.visible and "SUSPICION" in alert._debug_label.text,"Debug shows suspicion from actually communicated information")
	alert.debug_enabled=false
	await frames(1)
	check(not alert._debug_layer.visible,"Optional debug remains independently switchable")
	await clear_map()

func check_private_combat() -> void:
	await fixture()
	alert=map.get_node("VillageAlert")
	for actor in map.villagers:
		actor.local_warning.communication_enabled=false
		actor.threat_detection.detection_enabled=false
	resident.threat_recognized.emit(zombie)
	resident.begin_encounter(Color.GREEN,zombie)
	check(alert.score==0,"Recognition and a real encounter with no communicated report stay private")
	resident.take_damage(1000)
	check(alert.score==0 and map.killed_residents==1,"Unwitnessed hostile death changes mission statistics, not village knowledge")
	await clear_map()
	await fixture()
	alert=map.get_node("VillageAlert")
	for actor in map.villagers:
		actor.local_warning.communication_enabled=false
		actor.threat_detection.detection_enabled=false
	resident.begin_encounter(Color.GREEN,zombie)
	resident.receive_zombie_attack(10,1.0,zombie)
	resident.take_damage(1000)
	await frames(130)
	check(alert.score==0 and map.infected_residents==1 and map.killed_residents==0,"Unwitnessed conversion also grants no global knowledge and preserves conversion accounting")
	await clear_map()

func check_large_population() -> void:
	map=load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	alert=map.get_node("VillageAlert")
	for actor in map.villagers:
		actor.autonomous_movement_enabled=false
		actor.threat_detection.detection_enabled=false
	for unit in get_nodes_in_group("player_units"):
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled=false
	await frames(5)
	check(alert._registered.size()==30 and alert.score==0,"Thirty residents register independently of public incident state")
	var target=get_nodes_in_group("player_units")[0]
	for actor in map.villagers:
		for i in range(10): actor.threat_recognized.emit(target)
	check(alert.score==0,"Three hundred private signal notifications cannot magically alert the village")
	var sender=map.villagers[0]
	var receiver=map.villagers[1]
	sender.position=Vector2(1450,1000)
	receiver.position=Vector2(1500,1000)
	target.position=Vector2(1500,1040)
	await frames(3)
	sender.threat_recognized.emit(target)
	sender.threat_reaction.episode_active=true
	sender.threat_reaction.report_based=false
	sender.threat_reaction.warning_sent=true
	sender.threat_reaction.threat_id=target.get_instance_id()
	sender.warning_attempted.emit(sender,target.position)
	check(receiver.local_warning.has_report() and alert.score==20,"Large mission uses the same accepted local-delivery rule")
	var before:float=alert.score
	sender.begin_encounter(Color.GREEN,target)
	sender.take_damage(1000)
	check(alert.score==before,"A reported incident is not counted again as automatic combat and outcome increments")
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
	check(model.level == model.Level.SUSPICION, "Score sixty retains SUSPICION without physical bell activation")
	model._record(&"test", 4, 1000)
	check(model.score == 100 and model.level == model.Level.SUSPICION, "Score is capped and organized defense is unreachable")
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
	check(is_equal_approx(model.score, 55.5) and model.level == model.Level.SUSPICION,
		"Suspicion score decays independently of physical alarm activation")
	model._physics_process(0.05)
	check(is_equal_approx(model.score, 55) and model.level == model.Level.SUSPICION,
		"Score fifty-five remains SUSPICION; no ALARM was raised")
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
		and transitions.size() == 2, "Quiet mission eventually reaches zero with exactly two suspicion transitions")
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
		check(absf(model.score - 30) < 0.001 and model.level == model.Level.SUSPICION,
			"Editable settings and consistent physics delta at %d FPS" % fps)
		model.queue_free()
		await frames(2)


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
