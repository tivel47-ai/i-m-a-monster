class_name InteractiveBuilding
extends Node2D

const PROJECTILE = preload("res://scripts/defender_projectile.gd")
const ARRIVAL := 1.5
const REPATH_SECONDS := 0.35

var rules: BuildingRules
var layout: BuildingInterior
var mission: Node2D
var door_hp: float
var door_closed := false
var reinforcement := 0.0
var reinforcement_hp := 0.0
var barricade_hp := 0.0
var damage_remaining := 0.0
var recovery_remaining := 0.0
var battle_active := false
var restoration_allowed := false
var residents: Array[Node2D] = []
var monsters: Array[Node2D] = []
var attackers: Dictionary = {}
var shelter_queue: Array[Node2D] = []
var departing: Array[Node2D] = []
var workers: Array[Node2D] = [null, null]

var _crossing: CharacterBody2D
var _crossing_out := false
var _crossing_started := false
var _crossing_lane := 0.0
var _crossing_approach := Vector2.INF
var _crossing_stalled := 0.0
var _paths: Dictionary = {}
var _rest: Dictionary = {}
var _shot_after: Dictionary = {}
var _worker_retry: Dictionary = {}
var _vacating: Dictionary = {}
var _attack_stations: Dictionary = {}
var _melee_positions: Dictionary = {}
var _foyer_positions: Dictionary = {}
var _blocked_lane: Dictionary = {}
var _elapsed := 0.0
var _next_noise := 0.0
var _roof_alpha := 1.0
var _roof_target := 1.0


func configure(owner_map: Node2D, config: BuildingRules, body: StaticBody2D, hint: Vector2) -> bool:
	mission = owner_map
	rules = config
	door_hp = rules.door_health
	layout = BuildingInterior.new()
	add_child(layout)
	if not layout.configure(body, hint):
		return false
	process_physics_priority = -10
	set_physics_process(false)
	set_process(false)
	return true


func contains(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(layout.to_local(point), layout.outline)


func show_interior(reveal: bool) -> void:
	_roof_target = 0.0 if reveal else 1.0
	set_process(_roof_alpha != _roof_target)


func _process(delta: float) -> void:
	_roof_alpha = move_toward(_roof_alpha, _roof_target, delta * rules.roof_fade_speed)
	for part in layout.roof:
		part.modulate.a = _roof_alpha
	if _roof_alpha == _roof_target:
		set_process(false)


func shelter_approach(side: float = 0.0) -> Vector2:
	var exterior_map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(exterior_map) == 0:
		return Vector2.INF
	var point := layout.exterior(BuildingInterior.EXTERIOR_OFFSET, side)
	var projected := NavigationServer2D.map_get_closest_point(exterior_map, point)
	return projected if projected.distance_to(point) <= 9.0 else Vector2.INF


func request_shelter(resident: CharacterBody2D) -> bool:
	if not resident.is_available_for_infection() or resident.building_task != null or not monsters.is_empty():
		return false
	if door_hp == 0.0 and (reinforcement_hp > 0.0 or barricade_hp > 0.0):
		return false
	if not shelter_approach().is_finite() or _entrance_threatened():
		return false
	resident.building_task = self
	resident._stop_movement()
	shelter_queue.append(resident)
	set_physics_process(true)
	return true


func request_resident_exit(resident: Node2D) -> void:
	if not battle_active and not restoration_allowed and residents.has(resident) and not departing.has(resident):
		departing.append(resident)


func order_assault(zombie: CharacterBody2D) -> void:
	zombie.building_task = self
	attackers[zombie] = {"next_hit": _elapsed}
	set_physics_process(true)


func cancel_assault(zombie: CharacterBody2D) -> void:
	if not attackers.has(zombie):
		return
	attackers.erase(zombie)
	_attack_stations.erase(zombie)
	_blocked_lane.erase(zombie)
	_paths.erase(zombie)
	if _crossing == zombie:
		if zombie.is_alive() and not _displace_outside(zombie):
			_vacating[zombie] = true
		_end_crossing()
	if zombie.building_task == self:
		zombie.building_task = null


func adopt_conversion(resident: Node2D, zombie: CharacterBody2D) -> void:
	residents.erase(resident)
	departing.erase(resident)
	_clear_actor(resident)
	_enter_monster(zombie)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	damage_remaining = maxf(damage_remaining - delta, 0.0)
	recovery_remaining = maxf(recovery_remaining - delta, 0.0)
	_remove_unavailable()
	_prune_encounters()
	_resolve_battle()
	_choose_crossing()
	if is_instance_valid(_crossing):
		_advance_crossing(delta)
	# The crossing is resolved first so a fully entered body always starts the
	# battle before a worker can add the first point of barricade HP.
	_update_attackers(delta)
	if battle_active:
		_update_battle(delta)
	else:
		_update_residents(delta)
	if residents.is_empty() and monsters.is_empty() and attackers.is_empty() and shelter_queue.is_empty() and _vacating.is_empty() and damage_remaining <= 0.0:
		set_physics_process(false)


func _remove_unavailable() -> void:
	for actor in _vacating.keys():
		if not is_instance_valid(actor) or not actor.is_alive() or _displace_outside(actor):
			if is_instance_valid(actor):
				actor.remove_collision_exception_with(layout.threshold)
			_vacating.erase(actor)
			_refresh_entrance()
	for actor in attackers.keys():
		if not is_instance_valid(actor):
			attackers.erase(actor)
			_clear_actor(actor)
		elif not actor.is_alive():
			cancel_assault(actor)
	for actors in [residents, monsters, departing]:
		for actor in actors.duplicate():
			if not is_instance_valid(actor) or not actor.is_alive():
				actors.erase(actor)
				_clear_actor(actor)
	for resident in shelter_queue.duplicate():
		if is_instance_valid(resident) and resident.is_available_for_infection():
			continue
		shelter_queue.erase(resident)
		_clear_actor(resident)
		if is_instance_valid(resident):
			resident.building_task = null
			if _crossing == resident and resident.is_alive() and not _displace_outside(resident):
				_vacating[resident] = true
		if _crossing == resident:
			_end_crossing()
	if _crossing != null and (not is_instance_valid(_crossing) or not _crossing.is_alive()):
		_end_crossing()


func _clear_actor(actor: Variant) -> void:
	_paths.erase(actor)
	_rest.erase(actor)
	_shot_after.erase(actor)
	_worker_retry.erase(actor)
	_attack_stations.erase(actor)
	_melee_positions.erase(actor)
	_foyer_positions.erase(actor)
	_blocked_lane.erase(actor)
	for i in workers.size():
		if workers[i] == actor:
			workers[i] = null


func _prune_encounters() -> void:
	for resident in residents:
		for zombie in resident.encounter_participants.duplicate():
			if not is_instance_valid(zombie) or not zombie.is_alive() or zombie.interior_building != self or (
				resident.global_position.distance_to(zombie.global_position) > zombie.INFECTION_DISTANCE
				or not _line_clear(resident, zombie)):
				resident.leave_encounter(zombie)


func _resolve_battle() -> void:
	if not battle_active:
		return
	if residents.is_empty():
		battle_active = false
		for attacker in attackers.keys():
			var vacate := layout.depth(attacker) < BuildingInterior.EXTERIOR_OFFSET
			cancel_assault(attacker)
			if vacate:
				attacker.issue_player_area_move_order(_queue_point(attacker, 1, 25.0))
		for zombie in monsters:
			if not departing.has(zombie):
				departing.append(zombie)
	elif monsters.is_empty():
		battle_active = false
		restoration_allowed = true
		recovery_remaining = rules.recovery_seconds


func _choose_crossing() -> void:
	if is_instance_valid(_crossing) or not _vacating.is_empty():
		return
	if not battle_active:
		var nearest: Node2D
		var distance := INF
		for actor in departing:
			if actor.is_in_group("player_units") or not _entrance_threatened():
				var distance_to_door: float = actor.global_position.distance_squared_to(layout.interior())
				if distance_to_door < distance:
					nearest = actor
					distance = distance_to_door
		if nearest != null:
			_begin_crossing(nearest, true)
			return
	if not _blocked() and not attackers.is_empty():
		var nearest: CharacterBody2D
		var distance := INF
		for zombie in attackers:
			if _exterior_combat(zombie):
				continue
			var distance_to_door: float = zombie.global_position.distance_squared_to(layout.exterior())
			if distance_to_door < distance:
				nearest = zombie
				distance = distance_to_door
		if nearest != null:
			_begin_crossing(nearest, false)
	elif monsters.is_empty() and not shelter_queue.is_empty() and not _entrance_threatened():
		if door_hp > 0.0 or not _blocked():
			_begin_crossing(shelter_queue[0], false)


func _begin_crossing(actor: CharacterBody2D, exits: bool) -> void:
	_crossing = actor
	_crossing_out = exits
	_crossing_started = false
	_crossing_stalled = 0.0
	_crossing_approach = Vector2.INF
	_choose_lane(actor)


func _choose_lane(actor: CharacterBody2D) -> void:
	var flank := minf(16.0, layout.half_width - layout.side_clearance(actor) - 2.0)
	var clearance := layout.clearance(actor) + rules.crossing_clearance
	var inside_depth := maxf(BuildingInterior.PORTAL_OFFSET, layout.entry_clearance(actor) + 1.0)
	var best := INF
	var body := actor.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body.shape
	query.collision_mask = 2 | 8
	query.exclude = [actor.get_rid()]
	for side: float in [0.0, -flank, flank]:
		var inside := layout.interior(side, inside_depth)
		var outside := shelter_approach(side)
		if not outside.is_finite() or NavigationServer2D.map_get_closest_point(layout.map, inside).distance_to(inside) > 2.0:
			continue
		var approach := inside if _crossing_out else outside
		var score := actor.global_position.distance_to(approach) + absf(side) * 0.25
		var previous: Dictionary = _blocked_lane.get(actor, {})
		if not previous.is_empty() and _elapsed < float(previous.until) and side == float(previous.side):
			score += 250.0
		for point: Vector2 in [layout.interior(side, layout.entry_clearance(actor)),
			layout.exterior(0.0, side), layout.exterior(clearance + 1.0, side)]:
			query.transform = Transform2D(0.0, point)
			if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				score += 150.0
		if score < best:
			best = score
			_crossing_lane = side
			_crossing_approach = approach


func _end_crossing() -> void:
	if is_instance_valid(_crossing):
		if not _vacating.has(_crossing):
			_crossing.remove_collision_exception_with(layout.threshold)
		_paths.erase(_crossing)
	_crossing = null
	_crossing_started = false
	_refresh_entrance()


func _advance_crossing(delta: float) -> void:
	var actor := _crossing
	var zombie := actor.is_in_group("player_units")
	if zombie and not _crossing_out and _blocked():
		_end_crossing()
		return
	if zombie and not _crossing_out and _exterior_combat(actor):
		return
	var speed: float = actor.move_speed if zombie else actor.threat_reaction.fleeing_speed
	if not _crossing_started:
		if not zombie and (battle_active or _entrance_threatened()):
			_end_crossing()
			return
		if not _crossing_approach.is_finite() or _stalled(actor):
			_paths.erase(actor)
			_choose_lane(actor)
		if not _crossing_approach.is_finite():
			return
		var lined_up := (zombie and not _crossing_out and layout.depth(actor) > 0.0
			and layout.depth(actor) < BuildingInterior.EXTERIOR_OFFSET
			and absf(_lateral(actor.global_position) - _crossing_lane) < 3.0)
		if not lined_up and not _walk(actor, _crossing_approach, speed, delta, _crossing_out):
			return
		_crossing_started = true
		actor.add_collision_exception_with(layout.threshold)
		_refresh_entrance()
	var clearance := layout.clearance(actor) + rules.crossing_clearance
	var inside_depth := maxf(BuildingInterior.PORTAL_OFFSET, layout.entry_clearance(actor) + 1.0)
	var destination := layout.exterior(clearance + 1.0, _crossing_lane) if _crossing_out else layout.interior(_crossing_lane, inside_depth)
	var before := actor.global_position
	_step(actor, destination, speed, delta)
	if actor.global_position.distance_squared_to(before) < 0.0025:
		_crossing_stalled += delta
	else:
		_crossing_stalled = 0.0
	var depth := layout.depth(actor)
	if _crossing_out and depth >= clearance:
		residents.erase(actor)
		monsters.erase(actor)
		departing.erase(actor)
		_clear_actor(actor)
		actor.interior_building = null
		actor.building_task = null
		if zombie:
			actor.issue_player_area_move_order(_queue_point(actor, 1, -25.0 if departing.size() % 2 == 0 else 25.0))
		elif residents.is_empty():
			door_closed = false
		_end_crossing()
	elif not _crossing_out and depth <= -layout.entry_clearance(actor) and contains(actor.global_position):
		if zombie:
			attackers.erase(actor)
			_attack_stations.erase(actor)
			_blocked_lane.erase(actor)
			_enter_monster(actor)
		else:
			shelter_queue.erase(actor)
			residents.append(actor)
			actor.interior_building = self
			actor.threat_reaction.cancel_response()
			actor.threat_detection.reset_awareness()
			door_closed = door_hp > 0.0
			_assign_rest(actor)
		_end_crossing()
	elif _crossing_stalled >= 0.6 and zombie:
		_blocked_lane[actor] = {"side": _crossing_lane, "until": _elapsed + 2.0}
		if not _crossing_out and _displace_outside(actor):
			_end_crossing()
		else:
			_choose_lane(actor)
			_crossing_stalled = 0.0


func _enter_monster(zombie: CharacterBody2D) -> void:
	zombie.building_task = self
	zombie.interior_building = self
	zombie.set_selected(false)
	monsters.append(zombie)
	_assign_rest(zombie)
	if not residents.is_empty():
		battle_active = true
		recovery_remaining = 0.0
		workers = [null, null]
	else:
		departing.append(zombie)
	set_physics_process(true)


func _blocked() -> bool:
	if door_hp > 0.0:
		var civilian_crossing := _crossing_started and is_instance_valid(_crossing) and not _crossing.is_in_group("player_units")
		return door_closed and not civilian_crossing and _vacating.is_empty()
	return reinforcement_hp > 0.0 or barricade_hp > 0.0


func _refresh_entrance() -> void:
	var color := Color("69492f")
	if door_hp == 0.0:
		color = Color("a08858") if reinforcement_hp > 0.0 else Color("88694b")
	elif reinforcement > 0.0:
		color = color.lerp(Color("ad9066"), reinforcement)
	layout.set_blocked(_blocked(), color)
	if reinforcement_hp > 0.0:
		layout.set_barricade_health(reinforcement_hp, rules.reinforcement_health)
	else:
		layout.set_barricade_health(barricade_hp, rules.barricade_health)


func _update_attackers(delta: float) -> void:
	if attackers.is_empty():
		return
	var blocked := _blocked()
	var available: Array[Node2D] = []
	for zombie in attackers.keys():
		if zombie != _crossing and not _exterior_combat(zombie):
			available.append(zombie)
	_assign_attack_stations(available, blocked)
	var waiting: Array[Vector2] = []
	for zombie in available:
		if _attack_stations.has(zombie):
			var order: Dictionary = attackers[zombie]
			var side: float = _attack_stations[zombie]
			var clearance := layout.clearance(zombie) + 1.0
			var point := layout.exterior(clearance, side)
			var staged: bool = absf(_lateral(zombie.global_position) - side) < 5.0 and layout.depth(zombie) <= BuildingInterior.EXTERIOR_OFFSET + 2.0
			if staged or _walk(zombie, shelter_approach(side), zombie.move_speed, delta, false, 2.0):
				_step(zombie, point, zombie.move_speed, delta, true)
			if _elapsed >= float(order.next_hit) and zombie.global_position.distance_to(point) <= 6.0:
				order.next_hit = _elapsed + maxf(zombie.attack_interval, 0.01)
				_damage_entrance(zombie.attack_damage)
				if not _blocked():
					return
		else:
			var point := _waiting_point(zombie, waiting)
			if point.is_finite():
				waiting.append(point)
				_walk(zombie, point, zombie.move_speed, delta, false)
			else:
				zombie.velocity = Vector2.ZERO


func _assign_attack_stations(available: Array[Node2D], blocked: bool) -> void:
	if not blocked:
		_attack_stations.clear()
		return
	var sides := [0.0, -19.0, 19.0] if layout.half_width >= 25.0 else [0.0]
	for zombie in _attack_stations.keys():
		if not available.has(zombie):
			_attack_stations.erase(zombie)
		else:
			sides.erase(_attack_stations[zombie])
	while not sides.is_empty():
		var best: Node2D = null
		var best_side := 0.0
		var distance := INF
		for zombie in available:
			if _attack_stations.has(zombie):
				continue
			for side in sides:
				var point := shelter_approach(side)
				var cost := zombie.global_position.distance_squared_to(point)
				if cost < distance:
					distance = cost
					best = zombie
					best_side = side
		if best == null:
			break
		_attack_stations[best] = best_side
		sides.erase(best_side)


func _waiting_point(actor: Node2D, occupied: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var distance := INF
	for row in range(1, 3 + occupied.size() / 4):
		for side in [-31.0, 31.0, -58.0, 58.0]:
			var point := _queue_point(actor, row, side)
			if absf(_lateral(point)) < 25.0 or layout.depth_at(point) < 42.0:
				continue
			if occupied.any(func(other): return point.distance_squared_to(other) < 24.0 * 24.0):
				continue
			var cost := actor.global_position.distance_squared_to(point)
			if cost < distance:
				distance = cost
				best = point
		if best.is_finite():
			break
	return best


func _lateral(point: Vector2) -> float:
	return (layout.to_local(point) - layout.entrance).dot(layout.across)


func _queue_point(actor: Node2D, row: int, side: float) -> Vector2:
	var raw := layout.exterior(32.0 + row * 27.0, side)
	var nav := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(nav) == 0:
		return actor.global_position
	return NavigationServer2D.map_get_closest_point(nav, raw)


func _exterior_combat(zombie: CharacterBody2D) -> bool:
	var defender: Node2D = zombie.aggro_target
	if not is_instance_valid(defender) or not defender.is_encounter_owner(zombie):
		return (_attack_stations.has(zombie) and layout.depth(zombie) <= 26.0
			and zombie.engage_close_exterior_resident())
	if zombie.global_position.distance_to(defender.global_position) > zombie.INFECTION_DISTANCE or not zombie._has_line_of_sight(defender):
		defender.leave_encounter(zombie)
		return false
	zombie.velocity = Vector2.ZERO
	return true


func _damage_entrance(amount: float) -> void:
	if amount <= 0.0 or not _blocked():
		return
	if door_hp > 0.0:
		door_hp = maxf(door_hp - amount * (1.0 - reinforcement * rules.reinforced_damage_reduction), 0.0)
		if door_hp == 0.0 and reinforcement < 1.0:
			reinforcement = 0.0
			reinforcement_hp = 0.0
	elif reinforcement_hp > 0.0:
		reinforcement_hp = maxf(reinforcement_hp - amount, 0.0)
	else:
		barricade_hp = maxf(barricade_hp - amount, 0.0)
	if door_hp == 0.0 and reinforcement_hp == 0.0 and barricade_hp == 0.0:
		# Survivors can rebuild even if the attackers are driven off outdoors.
		restoration_allowed = true
	damage_remaining = rules.damage_cooldown
	_refresh_entrance()
	if _elapsed >= _next_noise:
		_next_noise = _elapsed + 0.8
		mission.emit_break_in_noise(self, layout.exterior(0.0), shelter_approach())


func _entrance_threatened() -> bool:
	var entrance := layout.exterior(BuildingInterior.WALL_WIDTH + 1.0)
	for zombie in get_tree().get_nodes_in_group("player_units"):
		if not mission.is_ancestor_of(zombie) or is_instance_valid(zombie.interior_building) or layout.depth(zombie) <= 0.0:
			continue
		if zombie.global_position.distance_to(entrance) > zombie.INFECTION_DISTANCE + 4.0:
			continue
		var ray := PhysicsRayQueryParameters2D.create(entrance, zombie.global_position, 1)
		if get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			return true
	return false


func _update_residents(delta: float) -> void:
	var reinforcing := door_hp > 0.0 and door_closed and reinforcement < 1.0
	var rebuilding := (
		restoration_allowed and door_hp == 0.0 and reinforcement_hp == 0.0
		and barricade_hp < rules.barricade_health and damage_remaining <= 0.0 and _vacating.is_empty()
		and (barricade_hp == 0.0 or not _entrance_threatened())
	)
	var working := recovery_remaining <= 0.0 and (reinforcing or rebuilding)
	_assign_workers(working)
	var at_work := 0
	for i in workers.size():
		var actor := workers[i]
		if not is_instance_valid(actor) or actor == _crossing:
			continue
		var goal := layout.to_global(layout.repair_points[i])
		if _walk(actor, goal, actor.move_speed, delta, true):
			at_work += 1
		elif _stalled(actor):
			workers[i] = null
			_worker_retry[actor] = _elapsed + 2.0
	for resident in residents:
		if resident == _crossing or not resident.is_available_for_infection():
			continue
		if not workers.has(resident):
			if recovery_remaining <= 0.0 and resident.current_health < resident.max_health:
				resident.current_health = minf(resident.current_health + rules.healing_per_second * delta, resident.max_health)
				resident.queue_redraw()
			_idle_inside(resident, delta)
	if at_work == 0:
		return
	var efficiency := 1.0 + (rules.second_worker_efficiency if at_work == 2 else 0.0)
	if reinforcing:
		var intensity := 0
		for zombie in attackers:
			if _elapsed < float(attackers[zombie].next_hit):
				intensity += 1
		var slowdown := minf(intensity * rules.slowdown_per_attacker, rules.maximum_slowdown)
		reinforcement = minf(reinforcement + delta * (1.0 - slowdown) / rules.reinforcement_seconds, 1.0)
		reinforcement_hp = reinforcement * rules.reinforcement_health
		_refresh_entrance()
	elif rebuilding and rules.build_per_second > 0.0:
		if barricade_hp == 0.0 and is_instance_valid(_crossing):
			if _crossing_started:
				var displaced := layout.depth(_crossing) < layout.clearance(_crossing) + rules.crossing_clearance
				if _crossing_out or not _displace_outside(_crossing):
					return
				if displaced and attackers.has(_crossing):
					attackers[_crossing].next_hit = _elapsed + rules.crossing_attack_delay
			_end_crossing()
		barricade_hp = minf(barricade_hp + delta * rules.build_per_second * efficiency, rules.barricade_health)
		_refresh_entrance()


func _assign_workers(working: bool) -> void:
	for i in workers.size():
		var current := workers[i]
		if not working or not is_instance_valid(current) or not current.is_available_for_infection() or departing.has(current):
			workers[i] = null
		if not working or workers[i] != null:
			continue
		var best := INF
		var goal := layout.to_global(layout.repair_points[i])
		for resident in residents:
			if workers.has(resident) or departing.has(resident) or not resident.is_available_for_infection() or _elapsed < float(_worker_retry.get(resident, 0.0)):
				continue
			var distance: float = resident.global_position.distance_squared_to(goal)
			if distance < best and not _path(resident.global_position, goal, layout.map, 4.0).is_empty():
				best = distance
				workers[i] = resident


func _displace_outside(actor: CharacterBody2D) -> bool:
	if not _crossing_started and not _vacating.has(actor):
		return true
	var missing := layout.clearance(actor) + rules.crossing_clearance - layout.depth(actor)
	if missing <= 0.0:
		return true
	var direction := layout.to_global(layout.outward) - layout.global_position
	actor.move_and_collide(direction * missing)
	return layout.depth(actor) >= layout.clearance(actor) + rules.crossing_clearance - 0.05


func _update_battle(delta: float) -> void:
	for zombie in monsters:
		if zombie == _crossing:
			continue
		var target: Node2D = _nearest_reachable(zombie, residents, true)
		if target != zombie.aggro_target:
			if is_instance_valid(zombie.aggro_target):
				zombie.aggro_target.leave_encounter(zombie)
			zombie.aggro_target = target
		if target == null:
			_melee_positions.erase(zombie)
			_idle_inside(zombie, delta)
		elif zombie.engage_defender(target):
			_melee_positions.erase(zombie)
			_foyer_positions.erase(zombie)
			if attackers.is_empty():
				_shift_melee_contact(zombie, target, delta)
		elif _make_room_for_entry(zombie, delta):
			_melee_positions.erase(zombie)
		elif not _advance_to_melee(zombie, target, delta) and layout.depth(zombie) > -34.0:
			_idle_inside(zombie, delta)
	for resident in residents:
		if not resident.is_available_for_infection() or resident.priest_routine != null:
			_melee_positions.erase(resident)
			continue
		var target: Node2D = _nearest_reachable(resident, monsters)
		if target == null:
			_melee_positions.erase(resident)
			continue
		if resident.defense_ranged_weapon and (resident.guard_ai != null or resident.priest_guard != null) and resident.global_position.distance_to(target.global_position) <= resident.defense_weapon_range and _line_clear(resident, target):
			_melee_positions.erase(resident)
			_shoot(resident, target)
		elif not target.engage_defender(resident):
			_advance_to_melee(resident, target, delta)
		else:
			_melee_positions.erase(resident)


func _make_room_for_entry(zombie: CharacterBody2D, delta: float) -> bool:
	if attackers.is_empty() or _crossing_out:
		_foyer_positions.erase(zombie)
		return false
	var previous: Vector2 = _foyer_positions.get(zombie, Vector2.INF)
	if previous.is_finite() and not _stalled(zombie):
		_walk(zombie, previous, zombie.move_speed, delta, true)
		return true
	_foyer_positions.erase(zombie)
	if not _crossing_started or not is_instance_valid(_crossing) or layout.depth(zombie) < -27.0 or layout.depth(_crossing) > 8.0:
		return false
	var best := Vector2.INF
	var distance := INF
	for depth in [20.0, 26.0, 34.0, 42.0]:
		for side in [-42.0, 42.0, -32.0, 32.0, 0.0]:
			var raw := layout.interior(side, depth)
			var point := NavigationServer2D.map_get_closest_point(layout.map, raw)
			var cost := zombie.global_position.distance_squared_to(point)
			if cost >= distance or layout.depth_at(point) > -18.0:
				continue
			if layout.depth_at(point) > -32.0 and absf(_lateral(point) - _crossing_lane) < 20.0:
				continue
			if point.distance_to(previous) < 4.0:
				continue
			if _foyer_positions.values().any(func(other): return point.distance_to(other) < 18.0):
				continue
			var route := _path(zombie.global_position, point, layout.map, 1.0)
			if _can_stand(zombie, point) and not route.is_empty() and _can_start_route(zombie, route):
				best = point
				distance = cost
	if not best.is_finite():
		return false
	_foyer_positions[zombie] = best
	_walk(zombie, best, zombie.move_speed, delta, true)
	return true


func _shift_melee_contact(zombie: CharacterBody2D, target: Node2D, delta: float) -> void:
	var blocked: Array[Node2D] = []
	for ally in monsters:
		if ally != zombie and ally.aggro_target == target and not target.is_encounter_owner(ally) and _stalled(ally):
			if zombie.global_position.distance_to(ally.global_position) < 28.0:
				blocked.append(ally)
	if blocked.is_empty():
		return
	var direction := target.global_position.direction_to(zombie.global_position)
	var best := zombie.global_position
	var clearance := _distance_from_blocked_allies(best, blocked)
	for angle in [-PI / 18, PI / 18, -PI / 9, PI / 9, -PI / 6, PI / 6, -PI / 4, PI / 4, -PI / 3, PI / 3]:
		var point: Vector2 = target.global_position + direction.rotated(angle) * (zombie.INFECTION_DISTANCE - 0.4)
		var candidate := _distance_from_blocked_allies(point, blocked)
		if candidate <= clearance + 2.0 or not contains(point):
			continue
		if not zombie.test_move(zombie.global_transform, point - zombie.global_position) and _melee_position_clear(zombie, target, point, zombie.INFECTION_DISTANCE):
			best = point
			clearance = candidate
	if best != zombie.global_position:
		_step(zombie, best, zombie.move_speed, delta)


func _distance_from_blocked_allies(point: Vector2, allies: Array[Node2D]) -> float:
	var distance := INF
	for ally in allies:
		distance = minf(distance, point.distance_to(ally.global_position))
	return distance


func _advance_to_melee(actor: CharacterBody2D, target: Node2D, delta: float) -> bool:
	var reach: float = actor.INFECTION_DISTANCE if actor.is_in_group("player_units") else target.INFECTION_DISTANCE
	var previous: Vector2 = _melee_positions.get(actor, Vector2.INF)
	var stalled := _stalled(actor)
	if previous.is_finite() and _melee_position_clear(actor, target, previous, reach - 0.5) and not stalled:
		_walk(actor, previous, actor.move_speed, delta, true, 1.0)
		return true
	_melee_positions.erase(actor)
	if stalled:
		_paths.erase(actor)
	var direction := target.global_position.direction_to(actor.global_position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var best := Vector2.INF
	var distance := INF
	for i in 16:
		var raw := target.global_position + direction.rotated(float(i) * TAU / 16.0) * (reach - 1.0)
		var point := NavigationServer2D.map_get_closest_point(layout.map, raw)
		var cost := actor.global_position.distance_squared_to(point)
		if cost >= distance or (stalled and point.distance_to(previous) < 3.0) or not _melee_position_clear(actor, target, point, reach - 0.5):
			continue
		var route := _path(actor.global_position, point, layout.map, 1.0)
		if route.is_empty():
			continue
		if not _can_start_route(actor, route):
			cost += 1600.0
		if cost < distance:
			best = point
			distance = cost
	if not best.is_finite():
		actor.velocity = Vector2.ZERO
		return false
	_melee_positions[actor] = best
	_walk(actor, best, actor.move_speed, delta, true, 1.0)
	return true


func _melee_position_clear(actor: CharacterBody2D, target: Node2D, point: Vector2, reach: float) -> bool:
	if point.distance_to(target.global_position) > reach:
		return false
	var ray := PhysicsRayQueryParameters2D.create(point, target.global_position, 1)
	if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
		return false
	var shape: RectangleShape2D = actor.get_node("CollisionShape2D").shape
	for other in _melee_positions:
		if other == actor:
			continue
		var difference: Vector2 = point - _melee_positions[other]
		if absf(difference.x) < shape.size.x + 0.5 and absf(difference.y) < shape.size.y + 0.5:
			return false
	return _can_stand(actor, point)


func _can_stand(actor: CharacterBody2D, point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = actor.get_node("CollisionShape2D").shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1 | 2 | 8
	query.exclude = [actor.get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _can_start_route(actor: CharacterBody2D, route: PackedVector2Array) -> bool:
	for point in route:
		var motion := (point - actor.global_position).limit_length(8.0)
		if motion.length_squared() > 4.0:
			return not actor.test_move(actor.global_transform, motion)
	return true


func _nearest_reachable(actor: Node2D, candidates: Array[Node2D], living_residents := false) -> Node2D:
	var target: Node2D = null
	var best := INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate.is_alive():
			continue
		if living_residents and (candidate.current_health <= 0.0 or not (candidate.is_available_for_infection() or candidate.can_join_encounter())):
			continue
		var distance := actor.global_position.distance_squared_to(candidate.global_position)
		if distance < best and (_line_clear(actor, candidate) or not _path(actor.global_position, candidate.global_position, layout.map, BuildingInterior.NAV_CLEARANCE).is_empty()):
			best = distance
			target = candidate
	return target


func _line_clear(actor: Node2D, target: Node2D) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(actor.global_position, target.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _shoot(actor: Node2D, target: Node2D) -> void:
	if _elapsed < float(_shot_after.get(actor, 0.0)):
		return
	_shot_after[actor] = _elapsed + maxf(actor.attack_interval, 0.01)
	var bolt := PROJECTILE.new()
	bolt.position = mission.to_local(actor.global_position)
	bolt.direction = actor.global_position.direction_to(target.global_position)
	bolt.damage = actor.attack_damage
	bolt.speed = actor.defense_projectile_speed
	bolt.remaining = actor.defense_weapon_range
	bolt.interior_building = self
	mission.add_child(bolt)


func _assign_rest(actor: Node2D) -> void:
	for local in layout.rest_points:
		var point := layout.to_global(local)
		if not _rest.values().has(point):
			_rest[actor] = point
			return
	_rest[actor] = actor.global_position


func _idle_inside(actor: CharacterBody2D, delta: float) -> void:
	if actor != _crossing and _rest.has(actor):
		_walk(actor, _rest[actor], actor.move_speed, delta, true, 2.0)


func _walk(actor: CharacterBody2D, goal: Vector2, speed: float, delta: float, inside: bool, tolerance := ARRIVAL) -> bool:
	if actor.global_position.distance_to(goal) <= tolerance:
		actor.velocity = Vector2.ZERO
		return true
	var nav := layout.map if inside else get_world_2d().navigation_map
	var route: Dictionary = _paths.get(actor, {})
	if route.is_empty() or route.nav != nav or route.goal.distance_to(goal) > 5.0 or _elapsed >= float(route.retry):
		var points := _path(actor.global_position, goal, nav, 5.0)
		var stall_since: float = _elapsed
		var progress := actor.global_position.distance_to(goal)
		if not route.is_empty() and route.nav == nav and route.goal.distance_to(goal) <= 5.0:
			stall_since = route.stall_since
			if progress < float(route.progress) - 2.0:
				stall_since = _elapsed
			else:
				progress = route.progress
		route = {"nav": nav, "goal": goal, "points": points, "index": 0,
			"retry": _elapsed + REPATH_SECONDS, "progress": progress, "stall_since": stall_since}
		_paths[actor] = route
	var points: PackedVector2Array = route.points
	var i: int = route.index
	if i == 0 and points.size() > 1 and actor.global_position.distance_to(points[0]) < BuildingInterior.NAV_CLEARANCE:
		var rejoin := (points[1] - actor.global_position).limit_length(8.0)
		if not actor.test_move(actor.global_transform, rejoin):
			i = 1
	while i < points.size() and actor.global_position.distance_to(points[i]) <= tolerance:
		i += 1
	route.index = i
	if i < points.size():
		_step(actor, points[i], speed, delta, true)
	else:
		actor.velocity = Vector2.ZERO
	return false


func _stalled(actor: Node2D) -> bool:
	return _paths.has(actor) and _elapsed - float(_paths[actor].stall_since) >= 2.0


func _path(from: Vector2, to: Vector2, nav: RID, tolerance: float) -> PackedVector2Array:
	if NavigationServer2D.map_get_iteration_id(nav) == 0:
		return PackedVector2Array()
	var path := NavigationServer2D.map_get_path(nav, from, to, true)
	if path.is_empty() or path[-1].distance_to(to) > tolerance:
		return PackedVector2Array()
	return path


func _step(actor: CharacterBody2D, goal: Vector2, speed: float, delta: float, bypass_units := false) -> void:
	var motion := (goal - actor.global_position).limit_length(speed * delta)
	if bypass_units and not motion.is_zero_approx():
		var collision := KinematicCollision2D.new()
		if actor.test_move(actor.global_transform, motion, collision) and collision.get_collider() is CharacterBody2D:
			var blocker := collision.get_collider() as CharacterBody2D
			var side := signf(motion.cross(actor.global_position - blocker.global_position))
			if side == 0.0:
				side = 1.0 if actor.get_instance_id() % 2 == 0 else -1.0
			for angle: float in [side * PI / 3.0, -side * PI / 3.0, side * PI / 2.0, -side * PI / 2.0]:
				var detour := motion.rotated(angle)
				if not actor.test_move(actor.global_transform, detour):
					motion = detour
					break
	actor.velocity = motion / delta
	actor.move_and_slide()
