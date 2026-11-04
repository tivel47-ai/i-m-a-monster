extends Node
## Optional civilian alarm behavior; the ordinary routine remains the fallback.
enum Mode { INDEPENDENT, FOLLOWING, FLEEING, REUNION }
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
var leader: Node
var mode: Mode = Mode.INDEPENDENT
var armed: bool = false
var weapon: StringName = &""
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
var reported_danger: Dictionary = {}
var leader_lost: bool = false
var rng = RandomNumberGenerator.new()
@onready var actor = get_parent()

func _ready() -> void:
	rng.randomize()

func role() -> String:
	return str(actor.get_meta("village_role", "artisan" if actor.civilian_profile == "Craftsman" else "peasant"))

func can_recruit() -> bool:
	return role() in ["peasant", "artisan"] and actor.is_available_for_infection()

func arm() -> void:
	if not can_recruit() or armed: return
	armed = true
	var weapons = peasant_weapons if role() == "peasant" else artisan_weapons
	if weapons.is_empty(): weapons = [&"club"]
	weapon = weapons[rng.randi_range(0, weapons.size() - 1)]
	actor.set_meta("civilian_weapon", weapon)
	# Equipment identity only; existing attack attributes/timers remain unchanged.

func invite(guard: Node) -> bool:
	var now: float = actor.defense.elapsed
	if not guard.actor.is_available_for_infection(): return false
	if not can_recruit() or is_instance_valid(leader) or now < next_invitation or guard.followers.size() >= 2: return false
	if actor.defense.alert.level < actor.defense.alert.Level.ALARM or not actor.defense.visible(actor, guard.actor, guard.recruitment_radius): return false
	next_invitation = now + refusal_seconds
	var danger = 0.0 if actor.get_recognized_threat() == null else perceived_risk_penalty
	if rng.randf() > clampf(courage + guard_courage_bonus - danger, 0.0, 1.0): return false
	leader = guard
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
	equipment_rolls += 1
	if rng.randf() < arming_probability: arm()
	actor.threat_reaction.cancel_response()
	actor._stop_movement()
	return true

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
	if not is_instance_valid(sender) or not sender.is_alive() or sender.defense != actor.defense or actor.global_position.distance_to(sender.global_position) > actor.local_warning.hearing_radius: return false
	if not actor.is_alive() or not actor.local_warning.communication_enabled or message.get("ack", false): return false
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
	var candidates: Array[Node2D] = []
	var home = actor.get_node_or_null(actor.home_point_path)
	if home is Node2D: candidates.append(home)
	if role() == "artisan":
		var workshop = actor.get_node_or_null(actor.work_point_path)
		if workshop is Node2D: candidates.append(workshop)
	if actor.defense.elapsed >= prefer_private_until:
		var points = actor.get_node_or_null(actor.points_of_interest_path)
		if points != null:
			for marker in points.get_children():
				if marker is Marker2D and marker.is_in_group("civilian_social_points"): candidates.append(marker)
	while not candidates.is_empty():
		var marker = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
		if not site_is_unsafe(marker) and actor.defense.reachable(actor, marker.global_position): return marker
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
	if separated_at < 0: separated_at = actor.defense.elapsed
	mode = Mode.FLEEING
	actor.threat_reaction.cancel_response()
	var target: Node2D = contact if is_instance_valid(contact) else actor.get_recognized_threat()
	if target != null: actor.threat_reaction.recognize_threat(target)
	if target != null: actor.threat_reaction._enter_reaction(actor.threat_reaction.Reaction.FLEEING)

func update_combat() -> void:
	if not is_instance_valid(leader) or actor.defense.elapsed < next_decision: return
	next_decision = actor.defense.elapsed + decision_interval
	var enemies: Array[Node2D] = []
	var incoming := 0.0
	for enemy in actor.threat_detection.nearby_threats():
		if actor.threat_detection._is_visible_target(enemy):
			enemies.append(enemy)
			incoming = maxf(incoming, enemy.attack_damage)
	var support: int = leader.known_support() if actor.defense.visible(actor, leader.actor, contact_radius) else 1
	if not enemies.is_empty() and (enemies.size() > support or actor.current_health <= incoming) and rng.randf() > courage * panic_courage_factor:
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
				if (visible_count > support and rng.randf() > courage * panic_courage_factor) or (not visible_leader and rng.randf() > courage):
					panic()
					return false
				var enemy: Node2D = actor.get_recognized_threat()
				if visible_leader and enemy.global_position.distance_to(last_leader_point) < contact_radius * 0.5 and actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
					enemy.engage_defender(actor)
					return true
			actor.threat_reaction.cancel_response()
			if last_leader_point.is_finite():
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
	if actor.defense.alert.level < actor.defense.alert.Level.ALARM:
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
		if actor.global_position.distance_to(point) <= actor.defense.bell_reach:
			bell_elapsed += delta
			if bell_elapsed >= actor.defense.bell_interaction_seconds: actor.defense.ring(actor)
		else:
			bell_elapsed = 0.0
			move_to(point, delta)
		return true
	if decision: observe_site_danger()
	if actor.threat_reaction.episode_active or actor.get_recognized_threat() != null: return false
	if role() == "priest": return false # preserve the separate peaceful PriestRoutine
	# An individual destination preference, not a spontaneous militia.
	if not safety_point.is_finite() and decision:
		safety_marker = choose_safety_marker()
		if is_instance_valid(safety_marker):
			safety_point = actor.defense.reserve_safety(actor, safety_marker, rng)
			reset_idle_pause()
	if safety_point.is_finite():
		update_safe_activity(delta)
		return true
	if actor.defense.elapsed < prefer_private_until:
		# No accessible private shelter: wait/reassess after the emergency flight,
		# rather than falling through to an ordinary SOCIAL destination.
		actor.has_destination = false
		actor.navigation_agent.velocity = Vector2.ZERO
		actor.velocity = Vector2.ZERO
		return true
	return false
