# Godot --headless --path . --script tests/villager_threat_validation.gd --fixed-fps 60
extends "res://tests/villager_movement_validation.gd"

var resident: Node2D
var sensor: Node2D
var zombie: Node2D
var recognition_events: Array[Node2D] = []


func fixture() -> void:
	await load_peaceful_map()
	for civilian in map.villagers:
		civilian.autonomous_movement_enabled = false
		civilian.get_node("ThreatDetection").detection_enabled = false
	resident = map.villagers[0]
	resident.position = Vector2(800, 390)
	sensor = resident.get_node("ThreatDetection")
	sensor.detection_enabled = true
	sensor.recognition_delay_min = 0.5
	sensor.recognition_delay_max = 0.5
	resident.threat_recognized.connect(func(target: Node2D): recognition_events.append(target))
	recognition_events.clear()
	zombie = frozen_zombie(Vector2(1000, 390))
	await frames(3)
	sensor.reset_awareness()


func frozen_zombie(position: Vector2) -> Node2D:
	var unit = load("res://scenes/zombie.tscn").instantiate()
	unit.position = position
	map.add_child(unit)
	unit.set_physics_process(false)
	unit.navigation_agent.avoidance_enabled = false
	return unit


func run() -> void:
	seed(1303)
	await fixture()
	check(not sensor.debug_enabled, "Threat debug indicator defaults to disabled")
	await frames(40)
	check(sensor.awareness == sensor.Awareness.UNAWARE and recognition_events.is_empty(), "Out-of-range zombie is ignored")
	zombie.position = Vector2(900, 390)
	await frames(2)
	check(sensor.awareness == sensor.Awareness.RECOGNIZING and sensor.pending_target == zombie
		and resident.get_recognized_threat() == null, "Visible zombie starts pending recognition, without confirmation")
	await frames(20)
	check(recognition_events.is_empty(), "Recognition cannot complete before configured delay")
	await frames(15)
	check(sensor.awareness == sensor.Awareness.AWARE and resident.get_recognized_threat() == zombie
		and recognition_events.size() == 1, "Recognition confirms target and emits one villager event after delay")
	await frames(90)
	check(recognition_events.size() == 1, "Confirmed threat does not emit duplicate events each frame")
	zombie.position = Vector2(951, 390)
	await frames(2)
	check(sensor.awareness == sensor.Awareness.UNAWARE and resident.get_recognized_threat() == null, "Confirmed target leaving range clears awareness")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()]:
		sensor.reset_awareness()
		zombie.position = resident.position + direction * 70
		await frames(35)
		check(resident.get_recognized_threat() == zombie, "360-degree recognition: %s" % direction)
	await check_occlusion()
	await check_multiple_targets()
	await check_timing()
	await check_independent_villagers()
	await check_peaceful_activity()
	resident.take_damage(1000)
	var death_events := recognition_events.size()
	await frames(80)
	check(sensor.awareness == sensor.Awareness.UNAWARE and resident.get_recognized_threat() == null
		and recognition_events.size() == death_events and not sensor.is_physics_processing(), "Dead villager clears awareness and emits no further events")
	await clear_map()
	await fixture()
	zombie.position = resident.position + Vector2(80, 0)
	await frames(35)
	resident.begin_encounter(Color.GREEN, zombie)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Combat immediately clears awareness independently of infection state")
	await frames(40)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Combat suppresses recognition without changing encounter ownership")
	check(resident.is_encounter_owner(zombie), "Threat detection leaves combat participation unchanged")
	resident.leave_encounter(zombie)
	await frames(15)
	check(sensor.awareness == sensor.Awareness.RECOGNIZING, "Survivor begins a fresh recognition delay after interrupted combat")
	await frames(20)
	check(resident.get_recognized_threat() == zombie, "Survivor can confirm a visible threat again after combat")
	resident.begin_encounter(Color.GREEN, zombie)
	resident.receive_zombie_attack(20, 1.0, zombie)
	resident.leave_encounter(zombie)
	var transform_events := recognition_events.size()
	await frames(35)
	check(resident.infection_state == resident.InfectionState.TRANSFORMING and sensor.awareness == sensor.Awareness.UNAWARE
		and recognition_events.size() == transform_events, "Transformation suppresses awareness events")
	# Keep the converted node for inspection; production callback normally removes it.
	resident.converted.disconnect(map._on_resident_converted)
	await frames(130)
	check(resident.is_converted() and sensor.awareness == sensor.Awareness.UNAWARE
		and not sensor.is_physics_processing() and recognition_events.size() == transform_events,
		"Converted villager permanently stops detection and events")
	await clear_map()
	print("Villager threat validation failures: ", failures)
	quit(1 if failures else 0)


func check_occlusion() -> void:
	resident.position = Vector2(330, 175)
	zombie.position = Vector2(330, 320)
	sensor.reset_awareness()
	await frames(40)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "House blocks recognition inside detection range")
	zombie.position = Vector2(400, 175)
	await frames(15)
	check(sensor.awareness == sensor.Awareness.RECOGNIZING and sensor.recognition_elapsed > 0, "Open LOS starts accumulating recognition")
	zombie.position = Vector2(330, 320)
	await frames(2)
	check(sensor.awareness == sensor.Awareness.UNAWARE and sensor.recognition_elapsed == 0, "Wall occlusion cancels and resets pending recognition")
	zombie.position = Vector2(400, 175)
	await frames(25)
	check(sensor.awareness == sensor.Awareness.RECOGNIZING, "Restored visibility starts a fresh full delay")
	await frames(10)
	check(resident.get_recognized_threat() == zombie, "Recognition restarts successfully after LOS is restored")
	zombie.position = Vector2(330, 320)
	await frames(2)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Confirmed awareness clears when target goes behind house")
	resident.position = Vector2(560, 220)
	zombie.position = Vector2(625, 220)
	await frames(35)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Short wall also blocks recognition")
	resident.position = Vector2(800, 390)


func check_multiple_targets() -> void:
	zombie.position = resident.position + Vector2(100, 0)
	var second = frozen_zombie(resident.position + Vector2(-80, 0))
	sensor.reset_awareness()
	await frames(10)
	check(sensor.pending_target == second, "Nearest visible live zombie selected from multiple candidates")
	zombie.position = resident.position + Vector2(60, 0)
	await frames(10)
	check(sensor.pending_target == second, "Pending candidate retained when another zombie becomes slightly closer")
	second.take_damage(1000)
	await frames(2)
	check(sensor.pending_target == zombie and sensor.recognition_elapsed < 0.05, "Dead candidate replaced without transferring recognition progress")
	await frames(20)
	check(sensor.awareness == sensor.Awareness.RECOGNIZING, "Replacement zombie requires its own complete delay")
	await frames(15)
	check(resident.get_recognized_threat() == zombie, "Replacement target recognized while corpse is ignored")
	var third = frozen_zombie(resident.position + Vector2(-40, 0))
	await frames(35)
	check(resident.get_recognized_threat() == zombie, "Confirmed target retained despite nearer live alternative")
	zombie.queue_free()
	await frames(2)
	check(sensor.pending_target == third and resident.get_recognized_threat() == null, "Removed target safely replaced with a fresh pending reference")
	third.remove_from_group("player_units")
	await frames(35)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Target no longer qualifying as zombie is ignored")
	third.add_to_group("player_units")
	await frames(35)
	check(resident.get_recognized_threat() == third, "Newly valid zombie requires fresh recognition")
	third.collision_layer = 0
	await frames(2)
	check(sensor.awareness == sensor.Awareness.UNAWARE, "Invalid collision-layer target clears awareness")
	third.queue_free()
	second.queue_free()
	zombie = frozen_zombie(resident.position + Vector2(80, 0))
	await frames(2)


func check_timing() -> void:
	sensor.set_physics_process(false)
	for fps in [30, 60, 120]:
		sensor.reset_awareness()
		sensor._physics_process(1.0 / fps)
		var elapsed := 0.0
		while sensor.awareness != sensor.Awareness.AWARE and elapsed < 1.5:
			elapsed += 1.0 / fps
			sensor._physics_process(1.0 / fps)
		check(elapsed >= 0.49999 and elapsed <= 0.5 + 1.0 / fps + 0.00001,
			"Recognition timing uses seconds with physics delta at %d FPS" % fps)
	sensor.recognition_delay_min = 0.5
	sensor.recognition_delay_max = 1.0
	var samples: Array[float] = []
	for attempt in range(20):
		sensor.reset_awareness()
		sensor._physics_process(1.0 / 60)
		samples.append(sensor.recognition_required)
	check(samples.min() >= 0.5 and samples.max() <= 1.0 and samples.max() - samples.min() > 0.1,
		"Each recognition attempt samples a new delay in the configured range")
	sensor.recognition_delay_max = 0.5
	sensor.reset_awareness()
	sensor.set_physics_process(true)


func check_independent_villagers() -> void:
	resident.position = Vector2(800, 390)
	zombie.position = Vector2(880, 390)
	var other = map.villagers[1]
	var other_position: Vector2 = other.position
	other.position = Vector2(850, 390)
	var other_sensor = other.get_node("ThreatDetection")
	other_sensor.detection_enabled = true
	other_sensor.recognition_delay_min = 1.0
	other_sensor.recognition_delay_max = 1.0
	sensor.reset_awareness()
	await frames(35)
	check(sensor.awareness == sensor.Awareness.AWARE and other_sensor.awareness == other_sensor.Awareness.RECOGNIZING,
		"Villagers maintain independent recognition timers and awareness states")
	await frames(35)
	check(other.get_recognized_threat() == zombie, "Second villager confirms its own target independently")
	other_sensor.detection_enabled = false
	other.position = other_position


func check_peaceful_activity() -> void:
	resident.position = Vector2(800, 390)
	resident.work_weight = 0
	resident.social_weight = 0
	resident.wander_weight = 0
	resident.home_weight = 1
	resident.wait_remaining = 0
	resident.autonomous_movement_enabled = true
	await frames(5)
	var original_destination: Vector2 = resident.destination
	var position_before: Vector2 = resident.position
	sensor.reset_awareness()
	await frames(35)
	check(sensor.awareness == sensor.Awareness.AWARE and resident.has_destination
		and resident.destination == original_destination and resident.position.distance_to(position_before) > 10,
		"Recognition and confirmation preserve peaceful route and movement")
	resident.autonomous_movement_enabled = false
	await frames(2)
	resident.current_activity = resident.Activity.HOME
	resident.is_performing_activity = true
	resident.wait_remaining = 7.0
	resident.autonomous_movement_enabled = true
	sensor.reset_awareness()
	await frames(35)
	check(sensor.awareness == sensor.Awareness.AWARE and resident.is_performing_activity
		and resident.current_activity == resident.Activity.HOME and resident.wait_remaining > 6,
		"Confirmed threat leaves ongoing peaceful activity intact")
