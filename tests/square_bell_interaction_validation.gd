extends SceneTree

const MISSION := preload("res://scenes/village_simulation_map.tscn")
const POSE_CELL := 128

var mission: Node2D
var defense: Node
var bell: Node2D
var alert: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func step() -> void:
	await physics_frame
	await process_frame


func until(predicate: Callable, steps: int) -> bool:
	for i in steps:
		if predicate.call(): return true
		await step()
	return predicate.call()


func setup() -> void:
	if is_instance_valid(mission):
		mission.queue_free()
		await step()
	mission = MISSION.instantiate()
	root.add_child(mission)
	defense = mission.get_node("VillageDefense")
	bell = defense.square_bell
	alert = defense.alert
	for actor in mission.villagers:
		actor.autonomous_movement_enabled = false
		actor.threat_detection.detection_enabled = false
	for i in 4:
		await step()


func pose(actor: Node2D) -> int:
	var sprite := actor.get_node_or_null("BellPullPose") as Sprite2D
	return int(sprite.region_rect.position.x / POSE_CELL) if sprite != null and sprite.visible else -1


func select_civilian_attempt(actor: Node2D) -> void:
	actor.autonomous_movement_enabled = true
	actor.escort.rare_bell_pending = true
	actor.escort.rare_bell_ready = true
	actor.escort.rare_bell_started = defense.elapsed


func guard_rings() -> void:
	await setup()
	var actor: Node2D = mission.get_node("Villagers/Guard25")
	var approach: Vector2 = bell.approach_position()
	var start: Vector2 = bell.global_position + Vector2(-37, 23)
	actor.global_position = start
	actor.autonomous_movement_enabled = true
	await step()
	check(start.distance_to(bell.global_position) < defense.bell_reach and not defense.at_bell(actor),
		"A nearby guard on the wrong side cannot start a normal pull")
	var report: Dictionary = actor.guard_ai._report(42, actor.global_position, 0)
	check(actor.guard_ai.raise_alarm_for_confirmed_death(report), "An existing alarm task finds the rope approach")
	check(await until(func(): return pose(actor) == 1, 190), "Guard walks around the bell and actually grips the rope")
	check(actor.global_position.distance_to(approach) <= actor.arrival_tolerance
		and actor.global_position.distance_to(start) > 50.0, "The actor's physical body reaches the interaction slot")
	check(alert.level < alert.Level.ALARM and not alert.bell_audio.playing,
		"Reaching and gripping are silent")
	var position_at_grip := actor.global_position
	var rope_at_grip: Vector2 = bell._rope_end
	check(await until(func(): return pose(actor) == 3, 65), "The pull advances through distinct poses")
	check(actor.global_position.is_equal_approx(position_at_grip) and bell._rope_end.y > rope_at_grip.y + 7.0,
		"The rope follows the lowering hands without moving the actor's feet")
	check(await until(func(): return alert.bell_source == alert.BellSource.SQUARE, 20),
		"The completed pull raises the existing square alarm")
	check(alert.bell_audio.playing and defense.operating_bell(actor) and pose(actor) == 3,
		"The strike starts the sound with the guard still gripping the rope")
	var audio: AudioStreamPlayer = alert.bell_audio
	var duration := audio.stream.get_length()
	var deadline := Time.get_ticks_msec() + ceili((duration + 2.0) * 1000.0)
	var swinging_near_end := false
	var stayed_at_rope := true
	var pull_poses: Array[int] = []
	var released_at_end := false
	while audio.playing and Time.get_ticks_msec() < deadline:
		var time_left := duration - audio.get_playback_position()
		var current_pose := pose(actor)
		stayed_at_rope = stayed_at_rope and defense.operating_bell(actor) \
			and actor.global_position.is_equal_approx(position_at_grip) and current_pose in [1, 2, 3, 4]
		if current_pose in [1, 2, 3] and not pull_poses.has(current_pose):
			pull_poses.append(current_pose)
		if current_pose == 4 and time_left < 0.28:
			released_at_end = true
		if time_left <= 1.0 and current_pose in [1, 2, 3] and absf(bell._angle) > deg_to_rad(1.0):
			swinging_near_end = true
		await step()
	check(stayed_at_rope and pull_poses.size() == 3, "The guard stays at the rope and cycles through all pulling poses")
	check(swinging_near_end and released_at_end, "The guard is still ringing in the last second and releases at the end")
	check(not audio.playing and await until(func(): return is_zero_approx(bell._angle) and pose(actor) == -1, 8),
		"The bell and the guard exit the interaction when playback ends")
	check(await until(func(): return actor.global_position.distance_to(position_at_grip) > actor.arrival_tolerance, 120),
		"The guard resumes autonomous movement after releasing the rope")


func civilian_attempts() -> void:
	await setup()
	var peasant: Node2D = mission.get_node("Villagers/Peasant19")
	var artisan: Node2D = mission.get_node("Villagers/Artisan20")
	var approach: Vector2 = bell.approach_position()
	peasant.global_position = approach
	await step()
	select_civilian_attempt(peasant)
	check(await until(func(): return pose(peasant) == 2, 45), "The civilian alarm task begins a visible pull")
	peasant.autonomous_movement_enabled = false
	await step()
	await step()
	check(pose(peasant) == -1 and alert.level < alert.Level.ALARM and not alert.bell_audio.playing,
		"Interrupting a pull restores the unit and leaves the bell silent")
	peasant.global_position += Vector2(0, 65)
	artisan.global_position = approach + Vector2(20, 16)
	await step()
	select_civilian_attempt(artisan)
	check(await until(func(): return pose(artisan) == 1, 125), "A different resident can walk up and take the freed rope")
	check(alert.level < alert.Level.ALARM, "The new user starts a fresh pull")
	check(await until(func(): return alert.bell_source == alert.BellSource.SQUARE, 65),
		"A civilian completing the same physical interaction raises the alarm")
	check(defense.operating_bell(artisan), "The civilian stays by the rope after the strike")
	artisan.autonomous_movement_enabled = false
	check(await until(func(): return pose(artisan) == -1, 8) and alert.bell_audio.playing,
		"Forced interruption releases the resident while the already sounded alarm continues")
	alert.bell_audio.stop()
	await step()


func run() -> void:
	await guard_rings()
	await civilian_attempts()
	mission.queue_free()
	await step()
	print("Square bell: ", checks - failures, "/", checks)
	quit(1 if failures else 0)
