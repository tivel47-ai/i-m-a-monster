extends RefCounted
## Per-resident decisions. All opponents and helpers come from personal, local perception.
const PROJECTILE = preload("res://scripts/defender_projectile.gd")
const MELEE_SUPPORT_LIMIT := 2
var formation: Node
var actor: Node2D
var enemies: Array[Node2D] = []
var allies: Array[Node2D] = []
var seen_since: Dictionary = {}
var failed: Dictionary = {}
var goal: Vector2 = Vector2.INF
var travel_goal: Vector2 = Vector2.INF
var target: Node2D
var mode: String = "travel"
var immediate_until: float = 0.0
var next_decision: float = 0.0
var next_plan: float = 0.0
var next_shot: float = 0.0
var help_sector: int = -1
var help_origin: Vector2 = Vector2.INF
var dash_until: float = 0.0
var started: bool = false
var regroup_until: float = 0.0
var next_gap_check: float = 0.0
var journey_target: Vector2 = Vector2.INF
var journey_best: float = INF
var journey_progress_at: float = 0.0
var route_history: Array[Vector2] = []

func _init(owner: Node, resident: Node2D) -> void:
	formation = owner
	actor = resident

func now() -> float:
	return formation.service.elapsed

func activate() -> void:
	if started or not formation.eligible(actor): return
	started = true
	actor.threat_reaction.cancel_response()
	actor.threat_reaction.seeking_home = false
	actor.threat_reaction.sheltered_at_home = false
	if not actor.is_in_collision(): actor._stop_movement()
	if actor.escort != null:
		actor.escort.cancel_rare_bell()
		actor.escort.reporter.cancel()
		if is_instance_valid(actor.escort.leader): actor.escort.mode = actor.escort.Mode.FOLLOWING
	if actor.guard_ai != null:
		actor.guard_ai.suspend()
		actor.guard_ai.mobilizing = false
		actor.guard_ai.mobilization_goal = Vector2.INF

func failed_point(point: Vector2) -> bool:
	for key in failed:
		if now() < float(failed[key]) and point.distance_to(key) < formation.spacing * 0.7: return true
	return false

func remember_failure(point: Vector2) -> void:
	failed[point] = now() + formation.failed_route_memory
	travel_goal = Vector2.INF
	goal = Vector2.INF
	next_plan = now() + formation.decision_interval
	if mode not in ["combat", "assist", "local_rescue"]: formation.release_place(actor)

func sense() -> void:
	enemies.clear()
	allies.clear()
	if not actor.threat_detection.detection_enabled: return
	var present: Dictionary = {}
	for other in formation.service.nearby(actor, actor.threat_detection.detection_radius, 2 | 8):
		if other.is_in_group("player_units"):
			if not actor.threat_detection._is_visible_target(other): continue
			var id = other.get_instance_id()
			present[id] = true
			if not seen_since.has(id): seen_since[id] = now() + actor.threat_detection.recognition_delay_max
			var contact = actor.global_position.distance_to(other.global_position) <= other.INFECTION_DISTANCE
			var known = contact or other == actor.get_recognized_threat() or actor.encounter_participants.has(other)
			if actor.guard_ai != null: known = known or actor.guard_ai.visible_enemies.has(other)
			if known or now() >= float(seen_since[id]): enemies.append(other)
			elif formation.arrived(actor) and actor.global_position.distance_to(other.global_position) <= formation.intercept_distance:
				enemies.append(other)
		elif other.has_method("is_alive") and formation.eligible(other) and formation.service.visible(actor, other, actor.threat_detection.detection_radius): allies.append(other)
	for id in seen_since.keys():
		if not present.has(id): seen_since.erase(id)
	for point in failed.keys():
		if now() >= float(failed[point]): failed.erase(point)
	# Witnessing an attack on a nearby ally is immediate local evidence.
	for ally in allies:
		if actor.global_position.distance_to(ally.global_position) > formation.intercept_distance: continue
		for enemy in ally.encounter_participants:
			if not is_instance_valid(enemy) or enemies.has(enemy): continue
			if present.has(enemy.get_instance_id()): enemies.append(enemy)
	for enemy in enemies:
		if actor.global_position.distance_to(enemy.global_position) <= formation.intercept_distance:
			immediate_until = now() + formation.decision_interval * 2.0

func halt() -> void:
	if actor.has_destination or not actor.velocity.is_zero_approx(): actor._stop_movement()
	goal = Vector2.INF

func move_to(point: Vector2, delta: float, fast: bool = false) -> int:
	if not point.is_finite():
		halt()
		return actor.NavigationResult.FAILED
	if actor.global_position.distance_to(point) <= actor.arrival_tolerance:
		halt()
		return actor.NavigationResult.ARRIVED
	if not actor.has_destination or not goal.is_finite() or goal.distance_to(point) > 8.0:
		if not formation.service.reachable(actor, point):
			remember_failure(point)
			halt()
			return actor.NavigationResult.FAILED
		actor._stop_movement()
		actor._set_peaceful_destination(point)
		goal = point
	var speed = actor.move_speed
	if actor.escort != null: speed = actor.escort.movement_speed
	if actor.guard_ai != null:
		speed = actor.guard_ai.tactical_speed
		for follower in actor.guard_ai.followers:
			if is_instance_valid(follower): speed = minf(speed, follower.movement_speed * actor.guard_ai.escort_speed_factor)
	if fast and actor.guard_ai == null: speed = maxf(speed, actor.threat_reaction.fleeing_speed)
	var result = actor._advance_navigation(goal, speed, delta)
	if result == actor.NavigationResult.FAILED:
		remember_failure(goal)
		halt()
	elif result == actor.NavigationResult.ARRIVED: halt()
	return result

func home() -> Vector2:
	return formation.places.get(actor.get_instance_id(), actor.global_position)

func own_sector_coverage() -> int:
	var count = 1
	for ally in allies:
		if not formation.arrived(ally) or formation.central_role(ally): continue
		var peer = formation.controller(ally)
		if peer == null or peer.help_sector >= 0 or ally.is_in_collision(): continue
		if formation.sector(peer.home()) == formation.sector(home()) and ally.global_position.distance_to(peer.home()) <= formation.spacing: count += 1
	return count

func assistance_sector() -> int:
	var own = formation.sector(home())
	var counts = [0, 0, 0]
	for enemy in enemies:
		if not formation.inside(enemy.global_position, formation.intercept_distance): continue
		if home().distance_to(enemy.global_position) > formation.assistance_distance: continue
		counts[formation.sector(enemy.global_position)] += 1
	if counts[own] > 0:
		help_sector = -1
		return own
	if own_sector_coverage() <= 1:
		help_sector = -1
		return own
	var best = own
	for sector in range(3):
		if absi(sector - own) <= 1 and counts[sector] > counts[best]: best = sector
	if help_sector >= 0 and counts[help_sector] > 0 and counts[best] < counts[help_sector] + formation.assistance_switch_margin:
		return help_sector
	help_sector = best if best != own else -1
	return best

func target_load(enemy: Node2D) -> int:
	var count = 0
	for ally in allies:
		var peer = formation.controller(ally)
		if ally.encounter_participants.has(enemy) or (peer != null and not peer.ranged() and peer.target == enemy): count += 1
	return count

func supports_companion(enemy: Node2D) -> bool:
	for ally in allies:
		if ally.encounter_participants.has(enemy) and ally.global_position.distance_to(actor.global_position) <= formation.intercept_distance:
			return true
	return false

func choose_target(defending: bool) -> Node2D:
	var best: Node2D
	var value = INF
	var chosen_sector = assistance_sector() if defending else -1
	for enemy in enemies:
		var distance = actor.global_position.distance_to(enemy.global_position)
		if failed_point(enemy.global_position): continue
		var firing = ranged() and distance <= actor.defense_weapon_range
		var load := target_load(enemy)
		if not firing and load >= MELEE_SUPPORT_LIMIT: continue
		var supporting := supports_companion(enemy)
		if defending:
			var limit = formation.assistance_distance if help_sector >= 0 else formation.intercept_distance
			if not firing and (distance > limit or home().distance_to(enemy.global_position) > limit): continue
			if not firing and formation.sector(enemy.global_position) != chosen_sector:
				if not supporting or own_sector_coverage() <= 1: continue
		else:
			if distance > formation.intercept_distance or not supporting: continue
		var depth := enemy.global_position.distance_to(formation.center)
		if not formation.inside(enemy.global_position): depth += formation.spacing
		var score = depth + distance * 0.5 + load * formation.spacing
		if supporting: score -= formation.intercept_distance
		if score < value:
			best = enemy
			value = score
	return best

func ranged() -> bool:
	return actor.defense_ranged_weapon and (actor.guard_ai != null or actor.priest_guard != null)

func shoot(enemy: Node2D) -> bool:
	if not ranged() or not actor.threat_detection._is_visible_target(enemy): return false
	if actor.global_position.distance_to(enemy.global_position) > actor.defense_weapon_range: return false
	halt()
	if now() >= next_shot:
		next_shot = now() + maxf(actor.attack_interval, 0.01)
		var bolt = PROJECTILE.new()
		bolt.position = actor.global_position
		bolt.direction = actor.global_position.direction_to(enemy.global_position)
		bolt.damage = actor.attack_damage
		bolt.speed = actor.defense_projectile_speed
		bolt.remaining = actor.defense_weapon_range
		formation.service.get_parent().add_child(bolt)
	return true

func approach_point(enemy: Node2D) -> Vector2:
	var direction := enemy.global_position.direction_to(actor.global_position)
	var reach: float = enemy.INFECTION_DISTANCE - actor.arrival_tolerance - 1.0
	var best := Vector2.INF
	var best_score := INF
	for angle in [0.0, -PI / 3, PI / 3, -2 * PI / 3, 2 * PI / 3]:
		var point: Vector2 = enemy.global_position + direction.rotated(angle) * reach
		var limit: float = formation.assistance_distance if help_sector >= 0 else formation.intercept_distance
		if formation.arrived(actor) and point.distance_to(home()) > limit: continue
		if failed_point(point) or not formation.service.reachable(actor, point): continue
		var score := actor.global_position.distance_to(point)
		for ally in allies:
			score += maxf(formation.spacing - point.distance_to(ally.global_position), 0.0) * 3.0
		if score < best_score:
			best = point
			best_score = score
	return best

func engage(enemy: Node2D, delta: float) -> void:
	target = enemy
	mode = "assist" if help_sector >= 0 else "combat"
	if shoot(enemy): return
	if ranged() and formation.arrived(actor):
		target = null
		halt() # A moving target cannot pull a ranged defender out of its position.
		return
	if actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
		enemy.engage_defender(actor)
		halt()
	else:
		var approach := goal
		if not approach.is_finite() or approach.distance_to(enemy.global_position) > enemy.INFECTION_DISTANCE - actor.arrival_tolerance:
			approach = approach_point(enemy)
		if move_to(approach, delta, formation.arrived(actor)) == actor.NavigationResult.FAILED:
			failed[enemy.global_position] = now() + formation.decision_interval
			help_sector = -1
			target = null

func safe_path(point: Vector2) -> bool:
	var path = actor._validated_path_to(point, actor.navigation_agent.get_navigation_map())
	if path.is_empty(): return actor.global_position.distance_to(point) <= actor.arrival_tolerance
	var previous = actor.global_position
	for waypoint in path:
		for enemy in enemies:
			var closest = Geometry2D.get_closest_point_to_segment(enemy.global_position, previous, waypoint)
			var clearance = maxf(enemy.INFECTION_DISTANCE + actor.navigation_agent.radius, actor.threat_reaction.threat_clearance)
			# A trapped actor may move AWAY from an adjacent threat, never through it.
			if closest.distance_to(enemy.global_position) < clearance and waypoint.distance_to(enemy.global_position) <= previous.distance_to(enemy.global_position) + 1.0: return false
		previous = waypoint
	return true

func travel(destination: Vector2, delta: float) -> void:
	mode = "travel"
	if not journey_target.is_finite() or journey_target.distance_to(destination) > formation.spacing:
		journey_target = destination
		travel_goal = Vector2.INF
		next_plan = 0.0
		journey_best = actor.global_position.distance_to(destination)
		journey_progress_at = now()
		route_history.clear()
	var distance = actor.global_position.distance_to(destination)
	if distance < journey_best - actor.arrival_tolerance:
		journey_best = distance
		journey_progress_at = now()
	elif distance > actor.arrival_tolerance and now() - journey_progress_at >= formation.failed_route_memory:
		for point in route_history: failed[point] = now() + formation.failed_route_memory
		route_history.clear()
		journey_progress_at = now()
		travel_goal = Vector2.INF
		next_plan = 0.0
	if travel_goal.is_finite() and now() < next_plan:
		var result = move_to(travel_goal, delta, now() < dash_until)
		if result != actor.NavigationResult.MOVING: travel_goal = Vector2.INF
		return
	if now() < next_plan:
		halt()
		return
	next_plan = now() + formation.decision_interval * 2.0
	travel_goal = Vector2.INF
	var options: Array[Vector2] = [destination]
	# Side paths are considered before a fight/dash, using only personally seen enemies.
	var toward = actor.global_position.direction_to(destination)
	for angle in [0.0, -PI / 3, PI / 3, -PI / 2, PI / 2, PI]:
		for reach in [formation.intercept_distance, formation.assistance_distance]:
			var point = actor.global_position + toward.rotated(angle) * reach
			var snapped = NavigationServer2D.map_get_closest_point(actor.navigation_agent.get_navigation_map(), point)
			if snapped.distance_to(point) < actor.arrival_tolerance: options.append(snapped)
	var best_score = INF
	for point in options:
		if failed_point(point) or not formation.service.reachable(actor, point) or not safe_path(point): continue
		var score = point.distance_to(destination) + point.distance_to(actor.global_position) * 0.2
		if score < best_score:
			best_score = score
			travel_goal = point
	if travel_goal.is_finite():
		if not route_history.has(travel_goal): route_history.append(travel_goal)
		move_to(travel_goal, delta)
		return
	# Guard B2 evaluates actual local support/health; civilians use nearby allies/equipment.
	var can_fight = actor.priest_routine == null and not enemies.is_empty()
	if actor.guard_ai != null: can_fight = can_fight and not actor.guard_ai.dangerous()
	else: can_fight = can_fight and enemies.size() <= allies.size() + (2 if actor.escort != null and actor.escort.armed else 1)
	if can_fight:
		var nearest: Node2D
		for enemy in enemies:
			if actor.global_position.distance_to(enemy.global_position) <= formation.intercept_distance and (nearest == null or actor.global_position.distance_to(enemy.global_position) < actor.global_position.distance_to(nearest.global_position)): nearest = enemy
		if nearest != null:
			engage(nearest, delta)
			return
	# Physical dash past a locally observed blockade. Failed endpoints are temporarily excluded.
	var clearance_best = -INF
	for point in options:
		if failed_point(point) or not formation.service.reachable(actor, point): continue
		if point.distance_to(destination) >= actor.global_position.distance_to(destination): continue
		var clearance = INF
		for enemy in enemies:
			clearance = minf(clearance, Geometry2D.get_closest_point_to_segment(enemy.global_position, actor.global_position, point).distance_to(enemy.global_position))
		if clearance > actor.navigation_agent.radius * 2.0 and clearance > clearance_best:
			travel_goal = point
			clearance_best = clearance
	if travel_goal.is_finite():
		dash_until = now() + formation.decision_interval * 2.0
		mode = "dash"
		move_to(travel_goal, delta, true)
	else:
		mode = "reassess"
		halt() # Next local observation always revisits this decision; no indefinite waiting state.

func escort_destination() -> Vector2:
	var escort = actor.escort
	if escort == null or not is_instance_valid(escort.leader): return Vector2.INF
	var leader = escort.leader
	if formation.service.visible(actor, leader.actor, escort.contact_radius):
		if not formation.eligible(leader.actor):
			escort.release("personally observed unavailable leader")
			return Vector2.INF
		escort.last_contact = now()
		escort.last_leader_point = leader.actor.global_position
		# The guard's forward side lets followers enter the arrival area while the guard waits.
		return leader.actor.global_position + leader.actor.global_position.direction_to(formation.center) * escort.follow_distance
	if now() - escort.last_contact >= escort.separation_seconds:
		escort.release("local escort contact expired")
		return Vector2.INF
	return escort.last_leader_point

func escort_wait(delta: float) -> bool:
	if actor.guard_ai == null: return false
	var guard = actor.guard_ai
	for index in range(guard.followers.size() - 1, -1, -1):
		if not is_instance_valid(guard.followers[index]): guard.followers.remove_at(index)
	for follower in guard.followers.duplicate():
		if not formation.service.visible(actor, follower.actor, guard.communication_radius): continue
		if not formation.eligible(follower.actor):
			follower.release("observed casualty during church escort")
			continue
		if follower.actor.is_in_collision():
			for enemy in enemies:
				if follower.actor.encounter_participants.has(enemy) and actor.global_position.distance_to(enemy.global_position) <= formation.intercept_distance:
					engage(enemy, delta)
					return true
	if formation.arrived(actor) and not guard.followers.is_empty():
		mode = "escort_arrival"
		travel(formation.center, delta)
		return true
	if guard.maintain_followers():
		mode = "escort_wait"
		return true
	return false

func rescue_target() -> Node2D:
	if own_sector_coverage() <= 1: return null
	for enemy in enemies:
		if formation.inside(enemy.global_position, enemy.INFECTION_DISTANCE): return null
	for ally in allies:
		if not formation.arrived(ally) or formation.inside(ally.global_position) or not ally.is_in_collision(): continue
		if home().distance_to(ally.global_position) > formation.assistance_distance: continue
		for enemy in enemies:
			if ally.encounter_participants.has(enemy) and target_load(enemy) < MELEE_SUPPORT_LIMIT and actor.global_position.distance_to(enemy.global_position) <= formation.intercept_distance:
				for other in enemies:
					if other != enemy and actor.global_position.distance_to(other.global_position) <= formation.intercept_distance: return null
				return enemy
	return null

func update(delta: float) -> bool:
	activate()
	if NavigationServer2D.map_get_iteration_id(actor.navigation_agent.get_navigation_map()) == 0: return true
	var decision = now() >= next_decision
	if decision:
		next_decision = now() + formation.decision_interval
		sense()
	enemies = enemies.filter(func(enemy): return is_instance_valid(enemy) and actor.threat_detection._is_visible_target(enemy))
	allies = allies.filter(func(ally): return formation.eligible(ally) and formation.service.visible(actor, ally, actor.threat_detection.detection_radius))
	for enemy in actor.encounter_participants.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_alive() or not formation.service.visible(actor, enemy, enemy.INFECTION_DISTANCE + actor.arrival_tolerance): actor.leave_encounter(enemy)
	# Contact is immediate evidence even before the recognition delay elapses.
	for enemy in actor.threat_detection.nearby_threats():
		if actor.threat_detection._is_visible_target(enemy) and actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
			immediate_until = now() + formation.decision_interval * 2.0
			if actor.priest_routine == null: enemy.engage_defender(actor)
	if actor.is_in_collision():
		if dash_until > now() and travel_goal.is_finite(): remember_failure(travel_goal)
		dash_until = 0.0
		mode = "hold_contact"
		help_sector = -1
		halt()
		return true
	if is_instance_valid(target) and not actor.threat_detection._is_visible_target(target): target = null
	var defending = formation.arrived(actor) and (formation.places.has(actor.get_instance_id()) or formation.inside(actor.global_position, formation.intercept_distance))
	if defending and not formation.places.has(actor.get_instance_id()): formation.position_for(actor)
	if actor.priest_routine == null:
		if decision or not is_instance_valid(target): target = choose_target(defending)
		if target != null:
			# Never let a moving target drag the defender beyond its original local area.
			var limit = formation.assistance_distance if help_sector >= 0 else formation.intercept_distance
			if (defending and (ranged() or target.global_position.distance_to(home()) <= limit)) or (not defending and actor.global_position.distance_to(target.global_position) <= formation.intercept_distance):
				engage(target, delta)
				return true
			target = null
	if escort_wait(delta): return true
	if not formation.arrived(actor):
		var escorted_goal = escort_destination()
		travel(escorted_goal if escorted_goal.is_finite() else formation.center, delta)
		return true
	if actor.priest_routine != null:
		# Once arrived, move only to the assigned place in the common geometry.
		var priest_place: Vector2 = formation.position_for(actor)
		mode = "position"
		if priest_place.is_finite() and safe_path(priest_place): move_to(priest_place, delta)
		else: halt()
		return true
	if not defending:
		# Rejoin physically before reserving an interior place from a distant position.
		formation.release_place(actor)
		travel(formation.center, delta)
		return true
	if defending and actor.priest_routine == null:
		var rescue = rescue_target()
		if rescue != null:
			engage(rescue, delta)
			mode = "local_rescue"
			return true
	help_sector = -1
	var point = formation.position_for(actor)
	# A free rear defender can fill a safe gap; transfers require local calm.
	if decision and now() >= next_gap_check:
		next_gap_check = now() + formation.decision_interval
		if point.is_finite() and actor.global_position.distance_to(point) <= actor.arrival_tolerance:
			var previous: Vector2 = point
			point = formation.position_for(actor, Vector2.INF, INF, true, enemies.is_empty())
			if point != previous: next_gap_check = now() + formation.contraction_delay
	if point.is_finite():
		mode = "return" if not formation.inside(actor.global_position) else "position"
		if safe_path(point): move_to(point, delta)
		else: halt()
	else:
		# Never funnel a full arrival crowd onto the same center coordinate.
		var separate = actor.global_position
		for ally in allies:
			if actor.global_position.distance_to(ally.global_position) < formation.spacing:
				separate += ally.global_position.direction_to(actor.global_position) * formation.spacing
		if separate != actor.global_position and formation.service.reachable(actor, separate): travel(separate, delta)
		else: halt()
	return true
