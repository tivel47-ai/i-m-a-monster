extends SceneTree

var failures := 0
var checks := 0
var alert: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(label)

func expect_danger(expected: float, label: String) -> void:
	check(is_equal_approx(alert.danger, expected), "%s: expected %s, got %s" % [label, expected, alert.danger])

func recognize(resident: Node2D) -> void:
	var sensor = resident.threat_detection
	sensor.reset_awareness()
	sensor.recognition_delay_min = 0.0
	sensor.recognition_delay_max = 0.0
	sensor._physics_process(0.0)

func see_bodies(resident: Node2D) -> void:
	var perception = resident.get_node("CorpsePerception")
	perception._physics_process(1.0)

func run() -> void:
	var map = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	var service = map.get_node("VillageDefense")
	alert = service.alert
	alert.set_physics_process(false)
	var square: Vector2 = map.get_node("VillagePointsOfInterest/Square").global_position
	var villagers = map.get_node("Villagers")
	var witness = villagers.get_node("Peasant1")
	var other = villagers.get_node("Peasant2")
	var body = villagers.get_node("Peasant3")
	var old_body = villagers.get_node("Peasant4")
	var guard = villagers.get_node("Guard25")
	var second_guard = villagers.get_node("Guard26")
	var fallen_guard = villagers.get_node("Guard27")
	var priest_guard = villagers.get_node("PriestGuard1")
	var zombies = map.get_node("Zombies").get_children()
	var first: Node2D = zombies[0]
	var previous: Node2D = zombies[1]
	var third: Node2D = zombies[2]
	for resident in map.villagers:
		resident.set_physics_process(false)
		resident.autonomous_movement_enabled = false
		resident.threat_detection.set_physics_process(false)
		resident.local_warning.set_physics_process(false)
		resident.get_node("CorpsePerception").set_physics_process(false)
		resident.global_position = Vector2(100, 100)
	for zombie in zombies:
		zombie.set_physics_process(false)
		zombie.get_node("AggroArea").monitoring = false
		zombie.global_position = Vector2(100, 150)
	witness.global_position = square
	other.global_position = square + Vector2(0, 15)
	first.global_position = square + Vector2(40, 0)
	old_body.global_position = square + Vector2(0, 35)
	guard.global_position = square + Vector2(0, -20)
	witness.escort.report_to_guard_enabled = false
	await physics_frame
	old_body._die()
	recognize(witness)
	check(witness.get_recognized_threat() == first and alert.level == alert.Level.NORMAL, "Private recognition before the bell stays local")
	see_bodies(guard)
	alert.confirm_threat(guard, previous.get_instance_id())
	check(alert.registered_corpses.has(old_body.get_instance_id()) and alert.level == alert.Level.SUSPICION, "Pre-bell guard confirmation still registers suspicion")
	guard.global_position = service.bell.global_position
	check(service.ring(guard), "ALARM still requires the physical bell")
	expect_danger(0, "The bell starts the new meter at zero")
	witness.threat_detection._physics_process(0.0)
	expect_danger(5, "Civilian still seeing an uncredited monster after the bell counts immediately")
	recognize(other)
	see_bodies(witness)
	alert.confirm_threat(guard, first.get_instance_id())
	alert.confirm_threat(guard, previous.get_instance_id())
	expect_danger(5, "Other observers, pre-bell confirmations and the old registered body add nothing")
	alert._physics_process(1.0)
	expect_danger(5, "Civilian sight alone does not change the continuous guard rate")

	body.global_position = square + Vector2(50, 15)
	fallen_guard.global_position = square + Vector2(0, 55)
	body._die()
	fallen_guard._die()
	expect_danger(5, "Deaths without confirmed observation do not raise danger")
	see_bodies(witness)
	expect_danger(30, "Civilian confirms one ordinary body and one guard body at their prior weights")
	guard.global_position = square + Vector2(0, -20)
	see_bodies(guard)
	expect_danger(30, "A later guard confirmation does not count either death again")

	priest_guard.global_position = square + Vector2(0, 20)
	first.global_position = square + Vector2(0, -500)
	third.global_position = square + Vector2(45, 10)
	await physics_frame
	recognize(priest_guard)
	expect_danger(35, "Personal priest guard counts a new direct sighting")
	recognize(witness)
	expect_danger(35, "A civilian does not duplicate the priest guard's sighting")

	second_guard.global_position = square + Vector2(0, 30)
	alert.confirm_threat(second_guard, third.get_instance_id())
	guard.guard_ai.visible_enemies.assign([third])
	second_guard.guard_ai.visible_enemies.assign([third])
	alert._physics_process(1.0)
	expect_danger(36, "Two guards contribute one continuous point for the same visible zombie")
	first.global_position = square + Vector2(45, -10)
	previous.global_position = square + Vector2(45, 25)
	guard.guard_ai.visible_enemies.assign([first, previous, third])
	check(is_equal_approx(alert.visible_danger_cap, 5.0) and is_equal_approx(alert.danger_threshold, 100.0), "Existing cap and threshold defaults are retained")
	alert.visible_danger_cap = 2.0
	alert._physics_process(1.0)
	expect_danger(38, "Continuous growth is capped independently of discrete weights")
	for zombie in zombies: zombie.global_position = square + Vector2(0, -500)
	alert._physics_process(1.0)
	expect_danger(38, "Remembered enemies out of sight do not sustain the rate")
	alert.add_danger(alert.danger_threshold - alert.danger)
	check(alert.level == alert.Level.ORGANIZED_DEFENSE, "The existing threshold triggers defense immediately")
	print("Alarm sightings: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
