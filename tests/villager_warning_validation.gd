# Godot --headless --path . --script tests/villager_warning_validation.gd --fixed-fps 60
extends "res://tests/villager_reaction_validation.gd"

var receiver: Node2D
var report: Node2D


func warning_fixture() -> void:
	await response_fixture(3)
	response.warning_duration = 0.25
	response.fleeing_speed = 0
	map.villagers[1].position = Vector2(680, 350)
	map.villagers[2].position = Vector2(470, 360)
	map.villagers[3].position = Vector2(520, 350)
	receiver = map.villagers[1]
	report = receiver.get_node("LocalWarning")
	receiver.autonomous_movement_enabled = true
	receiver.wait_remaining = 100
	receiver.current_activity = receiver.Activity.HOME
	receiver.is_performing_activity = true
	receiver.threat_reaction.reactions_enabled = true


func run() -> void:
	await warning_fixture()
	var sound_ray := PhysicsRayQueryParameters2D.create(resident.position, receiver.position)
	sound_ray.collision_mask = 1
	await frames(2)
	check(not map.get_world_2d().direct_space_state.intersect_ray(sound_ray).is_empty(), "Warning fixture has a solid obstacle between speaker and listener")
	check(not report.has_report(), "Unfinished warning delivers nothing")
	await frames(26)
	check(warning_events == 1 and report.has_report() and report.reports_received == 1,
		"Completed warning reaches nearby living villager through obstacle")
	check(not map.villagers[2].local_warning.has_report() and not map.villagers[3].local_warning.has_report(),
		"Outside hearing radius villagers receive nothing, including potential second-hop listener")
	check(resident.local_warning.notifications_delivered == 1, "Single broadcast delivers a bounded one-hop notification count")
	var snapshot: Vector2 = report.reported_position
	check(snapshot == Vector2(880, 390) and report.received_at >= 0 and report.remaining > 9,
		"Receiver stores last observed position, receipt time and provisional ten-second relevance")
	check(receiver.threat_detection.awareness == receiver.threat_detection.Awareness.UNAWARE
		and receiver.get_recognized_threat() == null and report.get_knowledge() == report.Knowledge.WARNED,
		"Warning does not forge direct visual awareness or a zombie reference")
	check(receiver.threat_reaction.report_based and receiver.threat_reaction.threat_target == null
		and receiver.current_activity == receiver.Activity.NONE, "Report interrupts peaceful activity using existing response without fake target")
	var distance_before: float = receiver.position.distance_to(snapshot)
	await frames(45)
	check(receiver.position.distance_to(snapshot) > distance_before + 10 and not overlaps_building(receiver, receiver.position),
		"Warned villager moves away from reported danger through existing navigation")
	check(receiver.local_warning.notifications_delivered == 0 and not map.villagers[3].local_warning.has_report(),
		"Second-hand information does not create a recursive warning cascade")
	# Freeze parent navigation only; local knowledge clock continues independently.
	receiver.set_physics_process(false)
	receiver.threat_reaction._stop_velocity()
	receiver.position = Vector2(680, 350)
	await frames(2)
	var episode_before: float = receiver.threat_reaction.episode_elapsed
	var receipts_before: int = report.reports_received
	var receipt_before: float = report.received_at
	for duplicate in range(100):
		resident.warning_attempted.emit(resident, snapshot)
	check(report.reports_received <= receipts_before + 1 and receiver.threat_reaction.episode_elapsed == episode_before,
		"One hundred duplicate messages cannot cause repeated response restarts")
	var accepted: int = report.reports_received
	var accepted_at: float = report.received_at
	resident.warning_attempted.emit(resident, snapshot)
	check(report.reports_received == accepted and report.received_at == accepted_at,
		"Immediate duplicates neither refresh timeout nor deliver additional accepted reports")
	await frames(70)
	resident.warning_attempted.emit(resident, snapshot)
	check(report.received_at > receipt_before and report.remaining > 9.9 and report.reports_received == accepted + 1,
		"A later genuine warning refreshes relevance without restarting active episode")
	zombie.position = Vector2(1180, 360)
	await frames(20)
	check(report.reported_position == snapshot and receiver.threat_reaction.threat_position == snapshot
		and receiver.get_recognized_threat() == null, "Moving hidden zombie does not update second-hand snapshot")
	await frames(610)
	check(not report.has_report() and report.get_knowledge() == report.Knowledge.NORMAL
		and not receiver.threat_reaction.episode_active and not receiver.threat_reaction.has_route,
		"Unrefreshed report expires and clears warning-only navigation lock")
	receiver.set_physics_process(true)
	await frames(10)
	check(receiver.has_destination or receiver.is_performing_activity, "Expired warning permits peaceful activities to resume")
	await clear_map()
	await check_radius_and_invalid_reports()
	await check_failed_report_response()
	await check_direct_priority_and_combat()
	await check_warning_lifecycle()
	print("Villager warning validation failures: ", failures)
	quit(1 if failures else 0)


func check_radius_and_invalid_reports() -> void:
	await warning_fixture()
	report.hearing_radius = 20
	await frames(28)
	check(not report.has_report(), "Per-listener configurable hearing radius limits delivery")
	report.hearing_radius = 180
	resident.warning_attempted.emit(resident, Vector2(NAN, 0))
	resident.warning_attempted.emit(resident, Vector2(100000, 100000))
	check(not report.has_report(), "Non-finite and distant invalid report locations are rejected")
	resident.warning_attempted.emit(resident, Vector2(880, 390))
	check(report.has_report(), "Listener can receive a later valid report after invalid data")
	# Even forced warning state cannot rebroadcast information based only on hearing.
	receiver.threat_reaction.warning_sent = true
	receiver.warning_attempted.emit(receiver, report.reported_position)
	check(receiver.local_warning.notifications_delivered == 0 and not map.villagers[3].local_warning.has_report(),
		"Broadcast gate rejects warning-only origin even if its event is manually emitted")
	await clear_map()


func check_failed_report_response() -> void:
	await warning_fixture()
	report.report_duration = 0.5
	receiver.threat_reaction.escape_distance = 100000
	await frames(28)
	check(report.has_report() and receiver.threat_reaction.episode_active and not receiver.threat_reaction.has_route,
		"Unavailable escape route uses existing bounded fallback for a report")
	await frames(60)
	check(not report.has_report() and not receiver.threat_reaction.episode_active
		and (receiver.has_destination or receiver.is_performing_activity),
		"Failed warning-only response expires without permanently freezing civilian AI")
	await clear_map()


func check_direct_priority_and_combat() -> void:
	await warning_fixture()
	await frames(28)
	check(report.has_report(), "Priority fixture begins with second-hand warning")
	receiver.position = Vector2(800, 390)
	receiver._stop_movement()
	receiver.wait_remaining = 100
	receiver.threat_detection.detection_enabled = true
	receiver.threat_detection.recognition_delay_min = 0.1
	receiver.threat_detection.recognition_delay_max = 0.1
	await frames(12)
	check(receiver.get_recognized_threat() == zombie and not receiver.threat_reaction.report_based
		and report.get_knowledge() == report.Knowledge.DIRECTLY_AWARE, "Personal visual recognition takes priority over heard information")
	var elapsed_before: float = receiver.threat_reaction.episode_elapsed
	resident.warning_attempted.emit(resident, Vector2(180, 200))
	check(receiver.threat_reaction.threat_target == zombie and not receiver.threat_reaction.report_based
		and receiver.threat_reaction.episode_elapsed == elapsed_before, "New report cannot replace or restart a directly recognized threat")
	report.report_duration = 0.1
	report.remaining = 0.1
	await frames(10)
	check(not report.has_report() and receiver.threat_reaction.episode_active and not receiver.threat_reaction.report_based,
		"Report expiration does not cancel an active direct-vision response")
	receiver.begin_encounter(Color.GREEN, zombie)
	check(not receiver.threat_reaction.episode_active and not receiver.threat_reaction.has_route, "Combat immediately overrides report and direct responses")
	var position_before: Vector2 = receiver.position
	resident.warning_attempted.emit(resident, Vector2(880, 390))
	receiver._on_navigation_velocity_computed(Vector2(100, 0))
	await frames(5)
	check(receiver.position.is_equal_approx(position_before) and receiver.is_encounter_owner(zombie),
		"Receiving a warning in combat cannot resume navigation or change encounter")
	await clear_map()


func check_warning_lifecycle() -> void:
	await warning_fixture()
	await frames(28)
	receiver.take_damage(1000)
	check(not report.has_report() and not receiver.threat_reaction.episode_active, "Death immediately clears reported danger and warning response")
	resident.warning_attempted.emit(resident, Vector2(880, 390))
	check(not report.has_report(), "Dead villager cannot receive new warnings")
	await clear_map()
	await warning_fixture()
	await frames(28)
	receiver.begin_encounter(Color.GREEN, zombie)
	receiver.receive_zombie_attack(20, 1.0, zombie)
	check(not report.has_report() and not receiver.threat_reaction.episode_active, "Transformation clears local warning knowledge and response")
	receiver.leave_encounter(zombie)
	var reference: WeakRef = weakref(receiver)
	await frames(150)
	check(reference.get_ref() == null and map.infected_residents == 1 and map.killed_residents == 0,
		"Conversion after hearing warning still creates zombie and counts one outcome")
	await clear_map()
