extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const MONSTER = preload("res://scenes/zombie.tscn")

var mission: Node2D
var last: Node
var defense: Node
var alert: Node
var priest: Node2D
var guards: Array
var protectors: Array
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if value:
		print("PASS: ", description)
	else:
		failed += 1
		push_error(description)

func step() -> void:
	await physics_frame
	await process_frame

func wait_for(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call(): return true
		await step()
	return predicate.call()

func setup() -> void:
	if is_instance_valid(mission):
		mission.queue_free()
		await step()
		await step()
	mission = MISSION.instantiate()
	root.add_child(mission)
	last = mission.get_node("LastStand")
	defense = mission.get_node("VillageDefense")
	alert = defense.alert
	priest = mission.get_node("Villagers/Priest30")
	guards = mission.villagers.filter(func(actor): return actor.guard_ai != null)
	protectors = mission.villagers.filter(func(actor): return actor.priest_guard != null)
	for actor in mission.villagers:
		actor.autonomous_movement_enabled = false
		actor.threat_detection.detection_enabled = false
	for i in 4:
		await step()
	await wait_for(func(): return last.church.shelter_approach().is_finite(), 150)

func shelter(witness: bool) -> bool:
	priest.global_position = last.church.shelter_approach()
	if witness:
		var monster := MONSTER.instantiate()
		monster.position = priest.position + Vector2(0, 95)
		mission.add_child(monster)
		monster.set_physics_process(false)
		monster.get_node("AggroArea").monitoring = false
		priest.autonomous_movement_enabled = true
		await step()
		priest.threat_reaction.recognize_threat(monster)
		check(priest.threat_reaction.shelter_after_sighting, "A visible living zombie marks the priest's shelter episode")
		priest.autonomous_movement_enabled = false
		monster.queue_free()
		await step()
		priest.global_position = last.church.shelter_approach()
	if not last.church.request_shelter(priest):
		return false
	return await wait_for(func(): return priest.interior_building == last.church, 180)

func church_alarm_and_beacon() -> void:
	await setup()
	check(guards.all(func(actor): return last.church_search_route(actor).size() == 3),
		"Every starting ordinary guard has three accessible church observation points")
	check(await shelter(true), "Priest physically enters the church")
	check(last.church.door_closed and last.church.door_hp == 500.0 and last.church.layout.barricade_ratio == 1.0, "Full crossing seals the 500 HP door in the same physics frame")
	check(alert.level == alert.Level.NORMAL and is_finite(last.church_bell_ends_at), "Personal sighting starts a timer before any global alert")
	for actor in protectors:
		actor.global_position = last.door_post(actor.priest_guard.slot) + Vector2(0, 22)
		actor.autonomous_movement_enabled = true
	check(await wait_for(func(): return protectors.all(func(actor):
		return actor.global_position.distance_to(last.door_post(actor.priest_guard.slot)) <= actor.arrival_tolerance), 100),
		"Both bodyguards physically take their doorway posts while the village is still calm")
	var civilian: Node2D = mission.villagers.filter(func(actor): return actor.escort != null and actor.escort.can_recruit())[0]
	civilian.global_position = defense.organized.center + Vector2(0, 68)
	check(defense.steadfast(civilian), "Sheltered priest gives courage from the church before the bell")
	civilian.global_position += Vector2(0, 600)
	check(defense.steadfast(civilian), "Courage has the existing residual effect")
	var guard: Node2D = guards[0]
	guard.global_position = Vector2(1390, 669)
	civilian.global_position = Vector2(1412, 665)
	civilian.escort.courage = 1.0
	var ends_at: float = last.church_bell_ends_at
	check(await wait_for(func(): return defense.elapsed >= ends_at - 0.1, 700), "Countdown uses mission time")
	check(alert.level == alert.Level.NORMAL and not alert.activate_church_bell(priest), "An early call cannot complete the church bell")
	check(await wait_for(func(): return alert.level == alert.Level.ALARM, 25), "Church bell raises the global level after ten game seconds")
	check(alert.bell_source == alert.BellSource.CHURCH and alert.danger == 0.0, "Alarm identifies the church and starts the usual danger meter at zero")
	check(last.church_bell_audio.playing, "The church plays its imported ringing sound on successful activation")
	check(guards.all(func(actor): return actor.guard_ai.church_inspection_until > defense.elapsed and not actor.guard_ai.mobilizing), "Ordinary guards receive church inspection instead of square mobilization")
	check(protectors.all(func(actor): return actor.guard_ai == null), "Bodyguards stay assigned to the doorway")
	guard.autonomous_movement_enabled = true
	civilian.autonomous_movement_enabled = true
	check(await wait_for(func(): return civilian.escort.leader == guard.guard_ai, 100), "Guard recruits a visible citizen during the church route")
	var route: PackedVector2Array = guard.guard_ai.church_inspection_route
	check(route.size() == 3 and Array(route).all(func(point): return last.keeps_door_clear(point, last.defense_spacing)), "Church route uses three exterior observation points and leaves the doorway clear")
	check(await wait_for(func(): return guard.guard_ai.church_inspection_until < 0.0, 1250), "Guard completes the observation route and resumes ALARM duties")
	check(guard.guard_ai.church_inspection_index == route.size() and civilian.escort.leader == guard.guard_ai, "The observation task ends with its follower still in the group")
	last.church._damage_entrance(90.0)
	alert.add_danger(alert.danger_threshold)
	check(alert.level == alert.Level.ORGANIZED_DEFENSE and last.operator == priest and last.signal_remaining == 10.0,
		"Entering organized defense starts a ten-second beacon preparation with the priest already inside")
	check(not last.construction_enabled and last.church.door_hp == 410.0 and last.wave == last.Wave.UNSENT,
		"Beacon starts ahead of construction without restoring the door or starting the wave early")
	last.church._damage_entrance(410.0)
	last.church.request_resident_exit(priest)
	check(not last.church.departing.has(priest), "Early sheltered priest stays inside during organized defense after a breach")
	check(await wait_for(func(): return last.beacon_lit, 615), "Beacon lights after preparation")
	check(alert.level == alert.Level.LAST_STAND and last.wave == last.Wave.TRAVELING and is_equal_approx(last.travel_remaining, 90.0),
		"The beacon starts the regular 90-second reinforcement timer")

func interrupted_bells() -> void:
	await setup()
	check(await shelter(true), "Priest starts preparation in the breach fixture")
	last.church._damage_entrance(500.0)
	await step()
	await step()
	check(not is_finite(last.church_bell_ends_at) and alert.level < alert.Level.ALARM, "A destroyed door cancels the attempt")

	await setup()
	check(await shelter(true), "Priest starts preparation in the square-first fixture")
	var guard: Node2D = guards[0]
	guard.global_position = defense.bell.global_position + Vector2(0, 39)
	check(defense.ring(guard), "Ordinary guard physically rings the square bell")
	await step()
	await step()
	check(not is_finite(last.church_bell_ends_at) and alert.bell_source == alert.BellSource.SQUARE
		and guard.guard_ai.mobilizing and guard.guard_ai.church_inspection_until < 0.0, "Square bell cancels the church countdown and preserves normal mobilization")

	await setup()
	check(await shelter(false), "Priest can shelter without a personal sighting")
	check(last.church.door_hp == 500.0 and not is_finite(last.church_bell_ends_at), "Shelter and doorway posts do not require a sighting, but the bell does")

	await setup()
	check(await shelter(true), "Priest starts preparation before transformation")
	priest._start_transformation(null, true)
	await step()
	await step()
	check(not is_finite(last.church_bell_ends_at) and alert.level < alert.Level.ALARM, "Starting transformation cancels the bell")
	var nearby: Node2D = guards[0]
	nearby.global_position = defense.organized.center + Vector2(0, 68)
	check(defense.steadfast(nearby), "A living priest still provides church morale while transforming")

func run() -> void:
	await church_alarm_and_beacon()
	await interrupted_bells()
	mission.queue_free()
	await step()
	print("Church bell: ", checks - failed, "/", checks)
	quit(1 if failed else 0)
