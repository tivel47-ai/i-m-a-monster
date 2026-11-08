extends SceneTree

var failures := 0
var checks := 0
var map: Node
var service: Node
var ai: Node
var priest: Node2D
var civilians: Array[Node2D] = []
var guards: Array[Node2D] = []
var zombie: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

func fixture(with_church: bool = true) -> void:
	map = load("res://scenes/village_simulation_map.tscn").instantiate()
	if not with_church: map.get_node("VillagePointsOfInterest/Church").free()
	root.add_child(map)
	service = map.get_node("VillageDefense")
	ai = service.priest_ai
	priest = ai.actor
	civilians.clear()
	guards.clear()
	for resident in map.villagers:
		resident.set_physics_process(false)
		resident.threat_detection.set_physics_process(false)
		resident.local_warning.set_physics_process(false)
		if resident.escort != null and resident.escort.can_recruit(): civilians.append(resident)
		if resident.guard_ai != null: guards.append(resident)
	for unit in get_nodes_in_group("player_units"):
		unit.set_physics_process(false)
		unit.get_node("AggroArea").monitoring = false
		unit.global_position = Vector2(50, 50)
		zombie = unit
	var navigation_map: RID = priest.navigation_agent.get_navigation_map()
	var ready := false
	for frame in range(90):
		await physics_frame
		if NavigationServer2D.map_get_iteration_id(navigation_map) == 0: continue
		ready = NavigationServer2D.map_get_closest_point(navigation_map, ai.square.global_position).is_equal_approx(ai.square.global_position)
		if ready: break
	check(ready, "Village navigation has synchronized")

func sound_alarm() -> void:
	var old_position := priest.global_position
	priest.global_position = service.bell.global_position
	check(service.ring(priest), "Existing physical bell activates ALARM")
	priest.global_position = old_position

func gather() -> void:
	priest.global_position = ai.square.global_position
	check(not ai.update_priest(0.016), "NORMAL leaves the peaceful controller in charge")
	service.alert.advance_level(service.alert.Level.SUSPICION)
	check(not ai.update_priest(0.016), "SUSPICION leaves the peaceful controller in charge")
	sound_alarm()
	check(ai.update_priest(0.016) and ai.site == ai.square, "Priest already at the square uses that site")
	for index in range(5):
		var resident := civilians[index]
		resident.global_position = ai.square.global_position + Vector2(30 + index * 5, 5 + index * 2)
		resident.escort.rng.seed = 99 + index
		resident.escort.safety_marker = ai.square
		resident.escort.safety_point = resident.global_position
	civilians[2].escort.safety_marker = civilians[2].get_node(civilians[2].home_point_path)
	civilians[3].escort.leader = guards[0].guard_ai
	civilians[3].escort.mode = civilians[3].escort.Mode.FOLLOWING
	guards[0].guard_ai.followers.append(civilians[3].escort)
	civilians[4].escort.safety_point += Vector2(0, 45)
	var home_point: Vector2 = civilians[2].escort.safety_point
	for index in range(5):
		check(ai.update_member(civilians[index].escort, 0.016) == (index < 2), "Gathering eligibility case %d" % index)
	check(civilians[2].escort.safety_point == home_point, "Home shelter keeps its destination")
	check(civilians[3].escort.leader == guards[0].guard_ai, "Gathering leaves the guard escort in place")
	var first: Vector2 = civilians[0].escort.safety_point
	var second: Vector2 = civilians[1].escort.safety_point
	check(first.distance_to(second) >= ai.gathering_spacing, "Gathering positions are separated")
	check(first.distance_to(priest.global_position) <= ai.gathering_radius and second.distance_to(priest.global_position) <= ai.gathering_radius, "Both positions are within the gathering area")
	priest.global_position += Vector2(1, 0)
	ai.update_member(civilians[0].escort, 0.016)
	check(civilians[0].escort.safety_point == first, "A small priest movement keeps an assigned position")
	civilians[1].threat_reaction.seeking_home = true
	ai.refresh(map.villagers)
	check(not ai.members.has(civilians[1].get_instance_id()), "An overriding personal refuge clears membership")

func morale_and_defense() -> void:
	var first := civilians[0]
	var second := civilians[1]
	var other := civilians[5]
	priest.global_position = Vector2(1360, 275)
	first.global_position = Vector2(1480, 275)
	second.global_position = priest.global_position + Vector2(0, -60)
	other.global_position = priest.global_position + Vector2(-65, 0)
	check(not service.visible(first, priest, INF) and ai.morale.supports(first), "A church wall blocks sight and allows morale")
	check(ai.morale.supports(other) and not ai.members.has(other.get_instance_id()), "An independent non-member receives morale")
	check(other.local_warning.firsthand_report.is_empty() and not other.local_warning.has_report(), "Morale leaves threat knowledge empty")
	# Identical random draws at the existing panic decision with and without support.
	var supported := 0
	var unsupported := 0
	other.escort.rng.seed = 100
	for index in range(128):
		if other.escort.panic_occurs(0.3): supported += 1
	other.global_position += Vector2(-300, 0)
	ai.morale.coverage.erase(other.get_instance_id())
	other.escort.rng.seed = 100
	for index in range(128):
		if other.escort.panic_occurs(0.3): unsupported += 1
	check(supported > 0 and supported < unsupported, "ALARM reduces actual panic decisions and allows flight")
	ai.morale.supports(second)
	first.global_position += Vector2(400, 0)
	ai.refresh(map.villagers)
	service.elapsed += 4.0
	second.global_position += Vector2(-400, 0)
	ai.refresh(map.villagers)
	service.elapsed += 6.01
	check(not ai.morale.supports(first) and ai.morale.supports(second), "Each recipient expires according to its own exit")
	check(first.escort.mode == first.escort.Mode.INDEPENDENT, "Expiry does not trigger panic")
	first.global_position = priest.global_position + Vector2(-60, 0)
	check(ai.morale.supports(first), "Re-entry restores direct support")
	first.global_position += Vector2(-400, 0)
	check(ai.morale.supports(first), "Another exit starts a fresh residual effect")
	check(ai.morale.radius() == ai.alarm_morale_radius, "ALARM uses its own radius")
	service.alert.add_danger(service.alert.danger_threshold)
	check(ai.members.is_empty() and service.organized.active(), "Existing defense activates and takes over gathering")
	service.organized.radius = 500.0
	check(ai.morale.radius() == ai.defense_morale_radius, "Defense radius is independent of the semicircle")
	first.global_position = service.organized.center
	priest.global_position = service.organized.center + Vector2(0, 35)
	service.organized.check_arrival(first)
	check(service.organized.arrived(first) and first.escort.armed and first.escort.steadfast(), "Arrival immediately arms and joins an affected defender")
	check(not first.escort.panic_occurs(0.0), "An affected defender declines ordinary panic")
	check(is_instance_valid(civilians[3].escort.leader), "Mobilization preserves the escort of a resident still en route")
	service.organized.check_arrival(priest)
	service.organized.refresh(0.0)
	service.organized.update_actor(priest, 0.016)
	check(service.organized.arrived(priest) and not priest.escort.armed, "Priest uses the existing formation unarmed")
	check(service.organized.controller(priest).mode == "position", "The arrived priest has only the formation position order")

func civilian_fear() -> void:
	var resident := civilians[6]
	var reaction = resident.threat_reaction
	var home: Node2D = resident.get_node(resident.home_point_path)
	resident.global_position = home.global_position
	priest.global_position = home.global_position + Vector2(0, 30)
	var direction := Vector2.ZERO
	for index in range(12):
		var trial := Vector2.from_angle(index * TAU / 12.0)
		zombie.global_position = resident.global_position + trial * 75
		if resident.threat_detection._is_visible_target(zombie):
			direction = trial
			break
	check(not direction.is_zero_approx(), "Fixture finds a visible non-immediate threat at the home approach")
	if direction.is_zero_approx(): return
	reaction.hesitation_probability = 0.0
	ai.alarm_calming = 0.95
	var probe := RandomNumberGenerator.new()
	for candidate in range(32):
		probe.seed = candidate
		probe.randf()
		if probe.randf() >= ai.alarm_calming: continue
		reaction.reaction_random.seed = candidate
		break
	reaction.recognize_threat(zombie)
	check(reaction.calm_home and reaction.reaction_state == reaction.Reaction.SEEKING_SHELTER, "An independent civilian can choose a controlled route to their own shelter")
	zombie.global_position = resident.global_position + direction * 10
	await physics_frame
	reaction.update_response(0.016)
	check(reaction.reaction_state == reaction.Reaction.FLEEING, "An immediate threat still triggers flight under morale")

func lifecycle(convert: bool) -> void:
	var resident := civilians[0]
	priest.global_position = service.organized.center
	resident.global_position = priest.global_position + Vector2(0, 30)
	priest.take_damage(1.0)
	zombie.global_position = priest.global_position
	check(priest.begin_encounter(Color.WHITE, zombie), "Priest can still enter physical contact")
	check(priest.encounter_attack_timer.is_stopped() and ai.morale.supports(resident), "Contact preserves morale and starts no priest attack")
	priest._start_transformation()
	check(priest.infection_state == priest.InfectionState.TRANSFORMING and ai.morale.supports(resident), "A transforming priest remains a morale source")
	for guard_name in ["PriestGuard1", "PriestGuard2"]:
		var guard = map.get_node("Villagers/" + guard_name)
		check(guard.priest_guard.priest_alive(), "Personal guard keeps the transforming priest as protectee")
	resident.global_position += Vector2(400, 0)
	check(ai.morale.supports(resident), "Residual morale is active before source loss")
	if convert: priest._on_transformation_timer_timeout()
	else: priest._die()
	check(ai.morale.coverage.is_empty() and not ai.morale.supports(resident), "DEAD/CONVERTED immediately clears residual morale")
	for guard_name in ["PriestGuard1", "PriestGuard2"]:
		var guard = map.get_node("Villagers/" + guard_name)
		guard.priest_guard.update_ai(0.016)
		check(guard.priest_guard.state == guard.priest_guard.State.CHURCH_DEFENSE, "Surviving personal guard switches to the church entrance")

func run() -> void:
	await fixture()
	gather()
	morale_and_defense()
	lifecycle(true)
	map.queue_free()
	await process_frame
	await fixture()
	priest.global_position = map.get_node("VillagePointsOfInterest/Cemetery").global_position
	sound_alarm()
	check(ai.update_priest(0.016) and ai.site == ai.church and priest.has_destination, "Cemetery ALARM starts travel to the accessible church")
	await civilian_fear()
	lifecycle(false)
	map.queue_free()
	await process_frame
	await fixture(false)
	priest.global_position = ai.square.global_position
	sound_alarm()
	check(ai.update_priest(0.016) and ai.site == ai.square, "A map without a church marker can use its square under ALARM")
	service.alert.add_danger(service.alert.danger_threshold)
	check(not service.organized.active() and ai.members.is_empty(), "No church formation is created without a church marker")
	var before_pause: float = service.elapsed
	paused = true
	for frame in range(3): await physics_frame
	check(service.elapsed == before_pause, "Mission clock remains fixed during pause")
	paused = false
	print("Priest AI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
