extends Node
## Civilian alarm behavior with a persistent refuge or gathering destination.
enum Mode { INDEPENDENT, FOLLOWING, FLEEING, REUNION }
const REPORTER = preload("res://scripts/civilian_reporter.gd")
const WEAPONS = preload("res://scripts/civilian_weapon_catalog.gd")
@export var report_to_guard_enabled: bool = true
@export var reporting_seconds: float = 45.0
@export var reporting_search_distance: float = 900.0
@export_range(0, 1) var courage: float = 0.55
@export_range(0, 1) var arming_probability: float = 0.60
@export var guard_courage_bonus: float = 0.2
@export var perceived_risk_penalty: float = 0.35
@export var panic_courage_factor: float = 0.5
@export var peasant_weapons: Array[StringName] = [&"pitchfork", &"pitchfork", &"axe", &"club", &"torch"]
@export var artisan_weapons: Array[StringName] = [&"hammer", &"hammer", &"axe", &"club", &"craft_tool"]
@export var contact_radius: float = 150.0
@export var separation_seconds: float = 12.0
@export var refusal_seconds: float = 15.0
@export var follow_distance: float = 24.0
@export var movement_speed: float = 60.0
@export var decision_interval: float = 0.5
@export var alarm_enemy_count: int = 2
@export var idle_radius: float = 40.0
@export var idle_speed: float = 20.0
@export var idle_pause: Vector2 = Vector2(3.0, 7.0)
@export var idle_move_probability: float = 0.65
@export var gathering_enemy_count: int = 3
@export var gathering_danger_radius: float = 180.0
@export var dangerous_site_memory: float = 90.0
@export_range(0, 1) var alarm_home_probability: float = 0.2
var leader: Node
var mode: Mode = Mode.INDEPENDENT
var armed: bool = false
var weapon: StringName = &""
var weapon_source: WEAPONS.Source = WEAPONS.Source.NONE
var catalog: WEAPONS
var weapon_profile: Dictionary:
	get:
		return catalog.weapons.get(weapon, {}) if catalog != null and armed else {}
var equipment_rolls: int = 0
var last_leader_point: Vector2 = Vector2.INF
var last_contact: float = -1.0
var separated_at: float = -1.0
var next_invitation: float = 0.0
var next_decision: float = 0.0
var safety_point: Vector2 = Vector2.INF
var safety_marker: Node2D
var idle_remaining: float = 0.0
var idle_walking: bool = false
var idle_moves: int = 0
var unsafe_sites: Dictionary = {}
var prefer_private_until: float = 0.0
var goal: Vector2 = Vector2.INF
var bell_elapsed: float = 0.0
var rare_bell_pending: bool = false
var rare_bell_ready: bool = false
var rare_bell_started: float = 0.0
var bell_rolls: int = 0
var bell_targets: Dictionary = {}
var reported_danger: Dictionary = {}
var leader_lost: bool = false
var reporter: RefCounted
var rng = RandomNumberGenerator.new()
var weapon_rng := RandomNumberGenerator.new()
var _initiative_origin := Vector2.INF
var _initiative_until := 0.0
var _assessment_target: Node2D
var _assessment_until := 0.0
var _assessment := false
var _ranged_goal := Vector2.INF
var _ranged_target: Node2D
var _next_ranged_plan := 0.0
@onready var actor = get_parent()

func _ready() -> void:
	movement_speed = actor.tactical_move_speed(movement_speed)
	catalog = actor.defense.get_parent().get("civilian_weapon_catalog")
	rng.randomize()
	weapon_rng.randomize()
	reporter = REPORTER.new(self)
	actor.defense.alert.level_changed.connect(_alert_changed)

func role() -> String:
	var ordinary_profiles := {"Villager": "peasant", "Peasant": "peasant", "Craftsman": "artisan"}
	return str(actor.get_meta("village_role", ordinary_profiles.get(actor.civilian_profile, "")))

func can_recruit() -> bool:
	return role() in ["peasant", "artisan"] and actor.is_available_for_infection()

func arm(at_church: bool = false) -> void:
	if catalog != null:
		return
	var eligible_arrival = at_church and role() in ["peasant", "artisan"] and actor.is_alive() and actor.infection_state != actor.InfectionState.TRANSFORMING
	if (not can_recruit() and not eligible_arrival) or armed: return
	armed = true
	var weapons = peasant_weapons if role() == "peasant" else artisan_weapons
	if weapons.is_empty(): weapons = [&"club"]
	weapon = weapons[rng.randi_range(0, weapons.size() - 1)]
	actor.set_meta("civilian_weapon", weapon)
	actor.apply_armed_combat_profile()


func arm_on_arrival() -> void:
	if catalog != null:
		arm_from(WEAPONS.Source.CHURCH)
	else:
		arm(true)


func arm_from(source: WEAPONS.Source) -> bool:
	if (source == WEAPONS.Source.NONE or catalog == null or not actor.defense.get_parent().civilian_weapons_valid or not actor.can_process()
		or armed or not actor.is_alive() or actor.infection_state == actor.InfectionState.TRANSFORMING):
		return false
	var selected := catalog.choose(role(), weapon_rng)
	if selected.is_empty():
		return false
	armed = true
	weapon = selected
	weapon_source = source
	equipment_rolls += 1
	actor.set_meta("civilian_weapon", weapon)
	actor.apply_civilian_weapon(weapon_profile)
	return true


func clear_equipment() -> void:
	if catalog == null or not armed:
		return
	armed = false
	weapon = &""
	weapon_source = WEAPONS.Source.NONE
	_ranged_target = null
	_ranged_goal = Vector2.INF
	_assessment_target = null
	actor.remove_meta("civilian_weapon")
	actor.clear_civilian_weapon()

func invite(guard: Node, investigation: bool = false, eyewitness: bool = false) -> bool:
	var now: float = actor.defense.elapsed
	if not guard.actor.is_available_for_infection(): return false
	if not can_recruit() or is_instance_valid(leader) or (not eyewitness and now < next_invitation) or guard.followers.size() >= 2: return false
	if actor.defense.alert.level < actor.defense.alert.Level.ALARM and not investigation: return false
	if investigation and not eyewitness and actor.threat_reaction.seeking_home: return false
	if investigation and guard.investigation.phase == guard.investigation.Phase.NONE: return false
	if not actor.defense.visible(actor, guard.actor, guard.recruitment_radius): return false
	next_invitation = now + refusal_seconds
	var danger = 0.0 if actor.get_recognized_threat() == null else perceived_risk_penalty
	if not eyewitness and rng.randf() > clampf(courage + guard_courage_bonus - danger, 0.0, 1.0): return false
	cancel_rare_bell()
	leader = guard
	reporter.report.clear()
	reporter.assigned = null
	actor.defense.release_safety(actor)
	safety_point = Vector2.INF
	safety_marker = null
	idle_walking = false
	guard.followers.append(self)
	mode = Mode.FOLLOWING
	leader_lost = false
	last_leader_point = guard.actor.global_position
	last_contact = now
	separated_at = -1.0
	if catalog != null:
		arm_from(WEAPONS.Source.RECRUITMENT)
	else:
		equipment_rolls += 1
		if rng.randf() < arming_probability: arm()
	actor.threat_reaction.cancel_response()
	actor._stop_movement()
	return true

func finish_investigation(incident: int, resolved: Array = []) -> void:
	# A local all-clear releases this group's fear, never every villager's memory.
	release("local area checked")
	if actor.threat_reaction.complete_investigation(incident, resolved):
		reporter.reset(incident)
		reported_danger.clear()

func release(_reason: String) -> void:
	if is_instance_valid(leader): leader.followers.erase(self)
	leader = null
	mode = Mode.INDEPENDENT
	separated_at = -1.0
	goal = Vector2.INF
	actor.defense.release_safety(actor)
	safety_point = Vector2.INF
	safety_marker = null
	idle_walking = false

func receive_message(message: Dictionary, sender: Node2D) -> bool:
	if message.get("kind", "") == "corpse": return false
	if not is_instance_valid(sender) or not sender.is_alive() or sender.defense != actor.defense or actor.global_position.distance_to(sender.global_position) > actor.local_warning.hearing_radius: return false
	if not actor.is_alive() or not actor.local_warning.communication_enabled or message.get("ack", false): return false
	if actor.local_warning.cleared_incidents.has(message.incident) and float(message.observed_at) <= float(actor.local_warning.cleared_incidents[message.incident]): return false
	if actor.defense.elapsed - float(message.observed_at) > actor.local_warning.report_duration: return false
	if not reported_danger.is_empty() and float(message.observed_at) <= float(reported_danger.observed_at): return false
	reported_danger = message.duplicate(true)
	learn_site_danger(message)
	if not is_instance_valid(leader):
		var remaining := maxf(actor.local_warning.report_duration - (actor.defense.elapsed - float(message.observed_at)), 0.0)
		if remaining > 0:
			actor.local_warning.reported_position = message.point
			actor.local_warning.remaining = remaining
			actor.local_warning.received_at = actor.local_warning.local_time
			actor.threat_reaction.respond_to_report(message.point)
	actor.defense.alert.report_delivered(sender, actor, message)
	return true

func move_to(point: Vector2, delta: float, speed: float = -1.0) -> int:
	if actor.global_position.distance_to(point) <= actor.arrival_tolerance:
		actor.has_destination = false
		actor.navigation_agent.velocity = Vector2.ZERO
		actor.velocity = Vector2.ZERO
		goal = Vector2.INF
		return actor.NavigationResult.ARRIVED
	if not goal.is_finite() or point.distance_to(goal) > 8.0 or not actor.has_destination:
		if not actor.defense.reachable(actor, point): return actor.NavigationResult.FAILED
		actor._stop_movement()
		actor._set_peaceful_destination(point)
		goal = point
	return actor._advance_navigation(point, movement_speed if speed < 0 else speed, delta)

func mark_unsafe_site(observed_at: float) -> void:
	if not is_instance_valid(safety_marker): return
	remember_unsafe_marker(safety_marker, observed_at)

func remember_unsafe_marker(marker: Node2D, observed_at: float) -> void:
	var id = marker.get_instance_id()
	var previous: Dictionary = unsafe_sites.get(id, {})
	if not previous.is_empty() and observed_at <= float(previous.observed_at): return
	unsafe_sites[id] = {"point": marker.global_position, "observed_at": observed_at, "until": observed_at + dangerous_site_memory}
	prefer_private_until = maxf(prefer_private_until, observed_at + dangerous_site_memory)
	if marker == safety_marker:
		actor.defense.release_safety(actor)
		safety_point = Vector2.INF
		safety_marker = null
		idle_walking = false
		idle_remaining = 0.0

func known_safety_sites() -> Array[Node2D]:
	var sites: Array[Node2D] = []
	if is_instance_valid(safety_marker): sites.append(safety_marker)
	var points = actor.get_node_or_null(actor.points_of_interest_path)
	if points != null:
		for marker in points.get_children():
			if marker is Marker2D and marker.is_in_group("civilian_social_points") and not sites.has(marker): sites.append(marker)
	return sites

func learn_site_danger(report: Dictionary) -> void:
	if int(report.get("count", 0)) < gathering_enemy_count or actor.defense.elapsed - float(report.observed_at) >= dangerous_site_memory: return
	if float(report.get("credibility", 0.0)) < 0.5: return
	for marker in known_safety_sites():
		if report.point.distance_to(marker.global_position) <= gathering_danger_radius: remember_unsafe_marker(marker, float(report.observed_at))

func observe_site_danger() -> void:
	if actor.get_recognized_threat() == null: return
	var visible: Array[Node2D] = []
	for enemy in actor.threat_detection.nearby_threats():
		if actor.threat_detection._is_visible_target(enemy): visible.append(enemy)
	for marker in known_safety_sites():
		var count = 0
		for enemy in visible:
			if enemy.global_position.distance_to(marker.global_position) <= gathering_danger_radius: count += 1
		if count >= maxi(gathering_enemy_count, 1): remember_unsafe_marker(marker, actor.defense.elapsed)

func site_is_unsafe(marker: Node2D) -> bool:
	var now: float = actor.defense.elapsed
	for id in unsafe_sites.keys():
		if now >= float(unsafe_sites[id].until):
			unsafe_sites.erase(id)
		elif marker.global_position.distance_to(unsafe_sites[id].point) <= gathering_danger_radius:
			return true
	return false

func choose_safety_marker() -> Node2D:
	var private_sites: Array[Node2D] = []
	var public_sites: Array[Node2D] = []
	var home = actor.private_shelter_marker()
	if home is Node2D: private_sites.append(home)
	if role() == "artisan":
		var workshop = actor.get_node_or_null(actor.work_point_path)
		if workshop is Node2D and workshop != home: private_sites.append(workshop)
	var points = actor.get_node_or_null(actor.points_of_interest_path)
	if points != null:
		for name in ["Church", "Square"]:
			var marker = points.get_node_or_null(name)
			if marker is Marker2D: public_sites.append(marker)
	var prefer_private = actor.defense.elapsed < prefer_private_until or rng.randf() < alarm_home_probability
	var groups = [private_sites, public_sites] if prefer_private else [public_sites, private_sites]
	for candidates in groups:
		while not candidates.is_empty():
			var marker = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
			if site_is_unsafe(marker): continue
			# Markers can sit inside a building; test an actual navigable place in its zone.
			var point = actor.defense.reserve_safety(actor, marker, rng)
			if point.is_finite():
				safety_point = point
				return marker
	return null

func reset_idle_pause() -> void:
	idle_walking = false
	var minimum = maxf(idle_pause.x, 0.1)
	idle_remaining = rng.randf_range(minimum, maxf(idle_pause.y, minimum))

func update_safe_activity(delta: float) -> void:
	if actor.global_position.distance_to(safety_point) > actor.arrival_tolerance:
		var result = move_to(safety_point, delta, idle_speed if idle_walking else movement_speed)
		if result == actor.NavigationResult.FAILED:
			actor.defense.release_safety(actor)
			safety_point = Vector2.INF
			idle_walking = false
		elif result == actor.NavigationResult.ARRIVED: reset_idle_pause()
		return
	if idle_walking: reset_idle_pause()
	actor.has_destination = false
	actor.navigation_agent.velocity = Vector2.ZERO
	actor.velocity = Vector2.ZERO
	idle_remaining = maxf(idle_remaining - delta, 0.0)
	if idle_remaining > 0: return
	reset_idle_pause()
	if not is_instance_valid(safety_marker) or rng.randf() >= idle_move_probability: return
	var point = actor.defense.reserve_safety(actor, safety_marker, rng, true, idle_radius)
	if point.is_finite():
		safety_point = point
		idle_walking = true
		idle_moves += 1

func panic(contact: Node2D = null) -> void:
	if steadfast(): return
	if separated_at < 0: separated_at = actor.defense.elapsed
	mode = Mode.FLEEING
	actor.threat_reaction.cancel_response()
	var target: Node2D = contact if is_instance_valid(contact) else actor.get_recognized_threat()
	if target != null: actor.threat_reaction.recognize_threat(target)
	if target != null: actor.threat_reaction._enter_reaction(actor.threat_reaction.Reaction.FLEEING)

func steadfast() -> bool:
	return actor.defense.steadfast(actor)

func panic_occurs(resistance: float) -> bool:
	if steadfast(): return false
	var calming: float = actor.defense.calming(actor)
	return rng.randf() > 1.0 - (1.0 - clampf(resistance, 0.0, 1.0)) * (1.0 - calming)


func _allied_combatants(radius: float) -> Array[Node2D]:
	var allies: Array[Node2D] = []
	for ally in actor.defense.nearby(actor, radius):
		if ((ally.guard_ai != null or ally.priest_guard != null or ally.is_in_collision()
			or (ally.escort != null and ally.escort.armed)) and ally.is_alive()
			and (ally.attack_damage > 0.0 or ally.defense_ranged_weapon)
			and not is_instance_valid(ally.interior_building) and actor.defense.visible(actor, ally, radius)):
			allies.append(ally)
	return allies


func can_resist(enemy: Node2D) -> bool:
	if catalog == null or not armed or not actor.threat_detection._is_visible_target(enemy):
		return false
	var now: float = actor.defense.elapsed
	if _assessment_target == enemy and now < _assessment_until:
		return _assessment
	_assessment_target = enemy
	_assessment_until = now + catalog.maneuver_interval
	var own_power: float = actor.attack_damage / actor.attack_interval
	if actor.has_civilian_ranged_weapon() and actor.global_position.distance_to(enemy.global_position) > actor.melee_reach():
		own_power = actor.defense_ranged_damage / actor.defense_ranged_interval * (1.0 - weapon_profile.error)
	var health: float = clampf(actor.current_health / actor.max_health, 0.0, 1.0)
	var morale: float = 1.0 if steadfast() else maxf(courage, actor.defense.calming(actor))
	var support := own_power * health * (0.5 + morale)
	for ally in _allied_combatants(catalog.initiative_radius):
		support += ally.attack_damage / maxf(ally.attack_interval, 0.01) * catalog.support_weight
	var opposition := 0.0
	var worst_hit := 0.0
	for threat in actor.threat_reaction._visible_threats():
		if threat == enemy or actor.global_position.distance_to(threat.global_position) <= catalog.initiative_radius:
			opposition += threat.attack_damage / maxf(threat.effective_attack_interval(), 0.01)
			worst_hit = maxf(worst_hit, threat.attack_damage)
	_assessment = actor.current_health > worst_hit and support >= opposition
	return _assessment


func can_start_local_defense(enemy: Node2D) -> bool:
	return (catalog != null and armed and mode == Mode.INDEPENDENT
		and not actor.threat_reaction.episode_active and not actor.threat_reaction.seeking_home
		and not actor.local_warning.has_report() and not reporter.has_live_report()
		and not rare_bell_pending and not is_instance_valid(actor.building_task)
		and actor.global_position.distance_to(enemy.global_position) <= catalog.initiative_radius
		and can_resist(enemy))


func update_local_defense(delta: float) -> bool:
	if catalog == null or not armed:
		return false
	var enemy: Node2D = actor.get_recognized_threat()
	if (not is_instance_valid(enemy) or not can_start_local_defense(enemy)
		or (_initiative_origin.is_finite() and enemy.global_position.distance_to(_initiative_origin) > catalog.initiative_radius)):
		_initiative_origin = Vector2.INF
		return false
	if not _initiative_origin.is_finite():
		_initiative_origin = actor.global_position
		# Reevaluate through the normal survival response if fighting stalls.
		_initiative_until = actor.defense.elapsed + separation_seconds
	if actor.defense.elapsed >= _initiative_until:
		return false
	if actor.has_civilian_ranged_weapon():
		var within_leash := func(point: Vector2): return point.distance_to(_initiative_origin) <= catalog.initiative_radius
		return support_ranged(enemy, delta, within_leash)
	return support_melee(enemy, delta, _initiative_origin, catalog.initiative_radius)


func support_melee(enemy: Node2D, delta: float, anchor: Vector2, leash: float) -> bool:
	if actor.try_melee_contact(enemy):
		actor._stop_movement()
		return true
	if actor._uses_local_melee_route(enemy):
		return actor._advance_melee_route(enemy, movement_speed, delta, anchor, leash)
	var approach: Vector2 = actor.defense.combat_approach(actor, enemy, goal)
	return (approach.is_finite() and approach.distance_to(anchor) <= leash
		and move_to(approach, delta) != actor.NavigationResult.FAILED)


func support_ranged(enemy: Node2D, delta: float, allowed: Callable, protector: Node2D = null) -> bool:
	if not actor.has_civilian_ranged_weapon() or not actor.threat_detection._is_visible_target(enemy):
		return false
	var now: float = actor.defense.elapsed
	var distance: float = actor.global_position.distance_to(enemy.global_position)
	var range_limit: float = actor.defense_weapon_range
	var retreat := distance < catalog.retreat_fraction * range_limit
	if _ranged_target != enemy:
		_ranged_target = enemy
		_ranged_goal = Vector2.INF
	var manageable := can_resist(enemy)
	if _ranged_goal.is_finite() and (not allowed.call(_ranged_goal) or (
		retreat and _ranged_goal.distance_to(enemy.global_position) <= distance + actor.arrival_tolerance)):
		_ranged_goal = Vector2.INF
	var valid_station: bool = allowed.call(actor.global_position)
	if now >= _next_ranged_plan and not _ranged_goal.is_finite():
		_next_ranged_plan = now + catalog.maneuver_interval
		if retreat or (manageable and (distance > range_limit or not valid_station)):
			_ranged_goal = _ranged_position(enemy, allowed, protector, retreat)
		elif manageable:
			_ranged_goal = _ranged_position(enemy, allowed, protector, false, true)
	if _ranged_goal.is_finite():
		if not retreat and not manageable:
			_ranged_goal = Vector2.INF
			return false
		if move_to(_ranged_goal, delta) == actor.NavigationResult.MOVING:
			return true
		_ranged_goal = Vector2.INF
	if retreat and distance <= actor.melee_reach():
		return actor.try_melee_contact(enemy)
	if not manageable or distance > range_limit or not valid_station:
		return false
	if actor.has_destination or not actor.velocity.is_zero_approx():
		actor._stop_movement()
	return actor.try_fire_defense_bolt(enemy)


func _ranged_position(enemy: Node2D, allowed: Callable, protector: Node2D, retreat: bool, cover_only := false) -> Vector2:
	var origin: Vector2 = actor.global_position
	var threat := enemy.global_position
	var direction := threat.direction_to(origin)
	var range_limit: float = actor.defense_weapon_range
	var preferred := range_limit * catalog.preferred_fraction
	var candidates := PackedVector2Array()
	if is_instance_valid(protector) and actor.defense.visible(actor, protector, catalog.initiative_radius):
		candidates.append(protector.global_position + threat.direction_to(protector.global_position) * follow_distance)
	for ally in _allied_combatants(catalog.initiative_radius):
		if not ally.defense_ranged_weapon:
			candidates.append(ally.global_position + threat.direction_to(ally.global_position) * catalog.cover_offset)
	var cover_count := candidates.size()
	if cover_only:
		for point in candidates:
			if origin.distance_to(point) <= actor.arrival_tolerance * 2.0:
				return Vector2.INF
	var distance := origin.distance_to(threat)
	var short_retreat := distance + catalog.cover_offset
	if not cover_only:
		for angle in [0.0, PI / 4, -PI / 4, PI / 2, -PI / 2]:
			if retreat:
				candidates.append(threat + direction.rotated(angle) * short_retreat)
			candidates.append(threat + direction.rotated(angle) * preferred)
	var best := Vector2.INF
	var best_score := INF
	var nav: RID = actor.navigation_agent.get_navigation_map()
	for i in candidates.size():
		var point := NavigationServer2D.map_get_closest_point(nav, candidates[i])
		var gap := point.distance_to(threat)
		if (point.distance_to(candidates[i]) > actor.arrival_tolerance or not allowed.call(point)
			or origin.distance_to(point) <= actor.arrival_tolerance or gap > range_limit
			or (retreat and gap <= distance + actor.arrival_tolerance)
			or not actor.defense._melee_line_clear(actor, point, threat)):
			continue
		var cost: float = actor.threat_reaction._safe_route_length(point, false, true)
		if not is_finite(cost):
			continue
		var score := cost + absf(gap - preferred) * 0.5
		if i < cover_count:
			score -= catalog.cover_offset
		if score < best_score:
			best = point
			best_score = score
	return best


func update_combat() -> void:
	cancel_rare_bell()
	# The zombie explicitly releases its primary opponent on death. Additional
	# civilian defenders must also leave their now-ended local encounter.
	for enemy in actor.encounter_participants.duplicate():
		if not is_instance_valid(enemy) or (actor.defense.visible(actor, enemy, contact_radius) and not enemy.is_alive()):
			actor.leave_encounter(enemy)
	if not actor.is_in_collision(): return
	if (not is_instance_valid(leader) and (catalog == null or not armed)) or actor.defense.elapsed < next_decision: return
	next_decision = actor.defense.elapsed + decision_interval
	var enemies: Array[Node2D] = []
	var incoming := 0.0
	for enemy in actor.threat_detection.nearby_threats():
		if actor.threat_detection._is_visible_target(enemy):
			enemies.append(enemy)
			incoming = maxf(incoming, enemy.attack_damage)
	var support: int = leader.known_support() if is_instance_valid(leader) and actor.defense.visible(actor, leader.actor, contact_radius) else 1
	if not enemies.is_empty() and (enemies.size() > support or actor.current_health <= incoming) and panic_occurs(courage * panic_courage_factor):
		actor.cancel_encounter()
		panic(enemies[0])

func update_escort(delta: float) -> bool:
	if not actor.is_available_for_infection(): return false
	var now: float = actor.defense.elapsed
	var decision = now >= next_decision
	if decision: next_decision = now + decision_interval
	if not is_instance_valid(leader) and mode != Mode.INDEPENDENT:
		# A freed/distant leader is absence, not supernatural news of death.
		if now - last_contact >= separation_seconds:
			release("leader contact expired")
			leader_lost = true
		elif last_leader_point.is_finite():
			move_to(last_leader_point, delta)
			return true
	var visible_leader = is_instance_valid(leader) and actor.defense.visible(actor, leader.actor, contact_radius)
	if visible_leader:
		if not leader.actor.is_alive():
			release("observed leader death")
			leader_lost = true
		else:
			last_leader_point = leader.actor.global_position
			last_contact = now
			if mode != Mode.FLEEING: separated_at = -1.0
	if is_instance_valid(leader):
		if not visible_leader and separated_at < 0: separated_at = now
		if separated_at >= 0 and now - separated_at >= separation_seconds:
			release("reunion no longer plausible")
			leader_lost = true
		elif mode == Mode.FLEEING:
			if actor.get_recognized_threat() != null or actor.threat_reaction.episode_active: return false
			if decision and visible_leader and rng.randf() < courage and actor.defense.reachable(actor, last_leader_point):
				mode = Mode.REUNION
			else: return false
		if is_instance_valid(leader) and mode != Mode.FLEEING:
			if decision and actor.get_recognized_threat() != null:
				var enemies = actor.defense.nearby(actor, actor.threat_detection.detection_radius, 2)
				var visible_count = 0
				for enemy in enemies:
					if actor.threat_detection._is_visible_target(enemy): visible_count += 1
				var support: int = leader.known_support() if visible_leader else 1
				if (visible_count > support and panic_occurs(courage * panic_courage_factor)) or (not visible_leader and panic_occurs(courage)):
					panic()
					return false
				var enemy: Node2D = actor.get_recognized_threat()
				if (visible_leader and not actor.has_civilian_ranged_weapon()
					and enemy.global_position.distance_to(last_leader_point) < contact_radius * 0.5 and actor.try_melee_contact(enemy)):
					return true
			var supported_enemy: Node2D = actor.get_recognized_threat()
			# Join the guard's engagement before melee contact; unarmed assistance stays close.
			var assistance_radius: float = contact_radius * 0.5 if armed else follow_distance
			if visible_leader and leader.state == leader.State.COMBAT and not leader.dangerous() and is_instance_valid(supported_enemy) and actor.threat_detection._is_visible_target(supported_enemy) and supported_enemy.global_position.distance_to(last_leader_point) <= assistance_radius:
				if actor.has_civilian_ranged_weapon():
					var near_leader := func(point: Vector2): return point.distance_to(last_leader_point) <= assistance_radius
					if support_ranged(supported_enemy, delta, near_leader, leader.actor): return true
				elif support_melee(supported_enemy, delta, last_leader_point, assistance_radius + actor.melee_reach()):
					return true
				elif not actor.has_civilian_ranged_weapon() and actor._uses_local_melee_route(supported_enemy):
					actor._stop_movement()
					return true
			actor.threat_reaction.cancel_response()
			if last_leader_point.is_finite():
				var forward: Vector2 = leader.actor.velocity.normalized() if visible_leader and leader.actor.velocity.length() > 1.0 else Vector2.ZERO
				if forward.is_zero_approx() and visible_leader and actor.has_civilian_ranged_weapon() and is_instance_valid(supported_enemy):
					forward = last_leader_point.direction_to(supported_enemy.global_position)
				var trailing: Vector2 = last_leader_point - forward * follow_distance
				if not forward.is_zero_approx():
					var side: float = -1.0 if leader.followers.find(self) % 2 == 0 else 1.0
					trailing += forward.orthogonal() * side * follow_distance * 0.6
					if actor.defense.reachable(actor, trailing) and actor.global_position.distance_to(trailing) > actor.arrival_tolerance:
						move_to(trailing, delta)
						return true
				if actor.global_position.distance_to(last_leader_point) > follow_distance:
					var points = actor.defense.sample_points(actor, last_leader_point, follow_distance, 2)
					if not points.is_empty(): move_to(points[0], delta)
				else:
					actor.has_destination = false
					actor.navigation_agent.velocity = Vector2.ZERO
					actor.velocity = Vector2.ZERO
					mode = Mode.FOLLOWING
			return true
	# Observe another accessible leader locally after losing the previous one.
	if leader_lost and decision:
		for other in actor.defense.nearby(actor, contact_radius):
			if other.guard_ai != null and actor.defense.visible(actor, other, contact_radius) and actor.defense.reachable(actor, other.global_position):
				if invite(other.guard_ai): return true
	if update_rare_bell(delta): return true
	if reporter.update(delta): return true
	if update_local_defense(delta): return true
	if role() != "priest" and actor.threat_reaction.episode_active: return false
	if actor.defense.alert.level < actor.defense.alert.Level.ALARM:
		if role() != "priest": return false
		# Serious first-person danger may motivate a physical alarm attempt. Priest
		# has priority; civilians defer to a locally available guard/priest.
		if actor.get_recognized_threat() == null or not is_instance_valid(actor.defense.bell): return false
		var threats = actor.defense.nearby(actor, actor.threat_detection.detection_radius, 2)
		var count = 0
		for enemy in threats:
			if actor.threat_detection._is_visible_target(enemy): count += 1
		if count < maxi(alarm_enemy_count, 1): return false
		if role() != "priest":
			for other in actor.defense.nearby(actor, contact_radius):
				if other.is_alive() and actor.defense.visible(actor, other, contact_radius) and (other.guard_ai != null or str(other.get_meta("village_role", "")) == "priest"): return false
		var point: Vector2 = actor.defense.alarm_point(actor)
		if not actor.defense.reachable(actor, point): return false
		actor.threat_reaction.cancel_response()
		if actor.defense.at_bell(actor, point):
			if not actor.defense.bell_path.is_empty(): actor._stop_movement()
			bell_elapsed = actor.defense.advance_bell_pull(actor, delta, bell_elapsed)
			if bell_elapsed >= actor.defense.bell_interaction_seconds: actor.defense.ring(actor)
		else:
			bell_elapsed = 0.0
			actor.defense.move_to_bell(actor, point, delta, move_to)
		return true
	if decision: observe_site_danger()
	# A witness/warned civilian keeps their own refuge plan even after the short
	# emergency reaction/report expires. Recruitment above can still override it.
	if actor.threat_reaction.seeking_home: return false
	if actor.threat_reaction.episode_active or actor.get_recognized_threat() != null: return false
	if role() == "priest": return false # preserve the separate peaceful PriestRoutine
	# An individual destination preference, not a spontaneous militia.
	if not safety_point.is_finite() and decision:
		safety_marker = choose_safety_marker()
		if is_instance_valid(safety_marker):
			if safety_marker == actor.private_shelter_marker():
				actor.defense.release_safety(actor)
				safety_point = Vector2.INF
				safety_marker = null
				actor.threat_reaction.seeking_home = true
				return false # The existing home controller gives this resident S and keeps it there.
			reset_idle_pause()
	if safety_point.is_finite():
		var priest = actor.defense.priest_ai
		if is_instance_valid(priest) and priest.update_member(self, delta): return true
		update_safe_activity(delta)
		return true
	# No reachable refuge: pause and retry without resuming the peaceful routine.
	actor._stop_movement()
	return true

func consider_rare_bell(target: Node2D) -> void:
	if not can_recruit() or actor.defense.alert.level >= actor.defense.alert.Level.ALARM or is_instance_valid(leader):
		return
	var id := target.get_instance_id()
	if rare_bell_pending or bell_targets.has(id):
		return
	bell_targets[id] = true
	bell_rolls += 1
	rare_bell_pending = rng.randf() < 0.02
	rare_bell_ready = false
	rare_bell_started = actor.defense.elapsed

func cancel_rare_bell() -> void:
	rare_bell_pending = false
	rare_bell_ready = false
	bell_elapsed = 0.0

func _alert_changed(_previous: int, current: int) -> void:
	if current >= actor.defense.alert.Level.ALARM:
		var traveling := rare_bell_ready
		cancel_rare_bell()
		if traveling:
			actor._stop_movement()
			actor.threat_reaction.seeking_home = true
		if reporter.report.get("kind", "") == "corpse":
			reporter.cancel()
			actor.threat_reaction.finish_guard_run()

func update_rare_bell(delta: float) -> bool:
	if not rare_bell_pending:
		return false
	if actor.defense.elapsed - rare_bell_started > reporting_seconds or actor.defense.alert.level >= actor.defense.alert.Level.ALARM:
		cancel_rare_bell()
		actor.threat_reaction.seeking_home = true
		return false
	if not rare_bell_ready:
		return false
	var point: Vector2 = actor.defense.alarm_point(actor)
	if not actor.threat_reaction._visible_threats().is_empty() or not point.is_finite() or actor.threat_reaction._safe_route_length(point, true, true) == INF:
		cancel_rare_bell()
		actor.threat_reaction.seeking_home = true
		return false
	reporter.cancel()
	if actor.defense.at_bell(actor):
		actor._stop_movement()
		bell_elapsed = actor.defense.advance_bell_pull(actor, delta, bell_elapsed)
		if bell_elapsed >= actor.defense.bell_interaction_seconds:
			actor.defense.ring(actor)
	else:
		bell_elapsed = 0.0
		if actor.defense.move_to_bell(actor, point, delta, move_to, actor.threat_reaction.fleeing_speed) == actor.NavigationResult.FAILED:
			cancel_rare_bell()
			actor.threat_reaction.seeking_home = true
	return true
