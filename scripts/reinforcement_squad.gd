extends Node2D
## One offensive squad with a navigation waypoint independent of its soldiers.

const BALANCE = preload("res://scripts/mission_one_unit_balance.gd")
const SPAWN_SPACING := 25.0
const REGROUP_RADIUS := 45.0
const ARRIVAL_RADIUS := 32.0

enum Mode { MARCH, COMBAT, REGROUP }

@export var entry_points: PackedVector2Array
@export var church_approach: Vector2
@export var patrol_points: PackedVector2Array
@export var base_count := 11
@export var count_variation := 2
@export var crossbow_fraction := 0.25
@export var spear_fraction_of_melee := 0.45
@export var pursuit_limit := 240.0
@export var lag_limit := 120.0
@export var wait_seconds := 6.0
@export var decision_interval := 0.35
@export var march_speed := 43.0
@export var march_lookahead := 28.0
@export var march_turn_rate := 3.5

var last_stand: Node
var soldiers: Array[Node2D] = []
var rng := RandomNumberGenerator.new()
var guard_variants: Array[StringName] = []
var mode := Mode.MARCH
var next_decision := 0.0
var patrol_index := -1
var waypoint := Vector2.INF
var heading := Vector2.DOWN
var path := PackedVector2Array()
var path_index := 0
var encounter_origin := Vector2.INF
var regroup_point := Vector2.INF
var target: Node2D
var target_point := Vector2.INF
var ignored_targets: Dictionary = {}
var late_since: Dictionary = {}
var isolated: Dictionary = {}
var goals: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)


func initialize(owner: Node) -> void:
	last_stand = owner
	rng.randomize()


func try_arrive() -> bool:
	if waypoint.is_finite() or entry_points.is_empty():
		return false
	if guard_variants.is_empty():
		var variation := maxi(count_variation, 0)
		var count := maxi(BALANCE.GUARD_VARIANTS.size(), base_count + rng.randi_range(-variation, variation))
		var crossbows := clampi(roundi(count * crossbow_fraction), 1, mini(floori(count / 3.0), count - 3))
		var melee := count - crossbows
		var spears := clampi(roundi(melee * spear_fraction_of_melee), 1, melee - 2)
		var shields := roundi((melee - spears) * 0.5)
		var amounts := {BALANCE.SPEAR: spears, BALANCE.SHIELD: shields,
			BALANCE.SWORD: melee - spears - shields, BALANCE.CROSSBOW: crossbows}
		for variant in amounts:
			for i in amounts[variant]:
				guard_variants.append(variant)
	var nav := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(nav) == 0:
		return false
	var available: Array[PackedVector2Array] = []
	for entry in entry_points:
		var positions := _spawn_positions(nav, to_global(entry))
		if not positions.is_empty():
			available.append(positions)
	if available.is_empty():
		return false
	var selected: PackedVector2Array = available[rng.randi_range(0, available.size() - 1)]
	waypoint = selected[0].lerp(selected[mini(3, selected.size() - 1)], 0.5)
	heading = waypoint.direction_to(to_global(church_approach))
	soldiers = last_stand.mission.spawn_reinforcement_wave(guard_variants, selected, self)
	set_physics_process(true)
	return true


func _spawn_positions(nav: RID, entry: Vector2) -> PackedVector2Array:
	var start_path := NavigationServer2D.map_get_path(nav, entry, to_global(church_approach), true)
	if start_path.size() < 2 or start_path[0].distance_to(entry) > 0.5 or start_path[-1].distance_to(to_global(church_approach)) > 0.5:
		return PackedVector2Array()
	var forward := entry.direction_to(start_path[1])
	var footprint := CircleShape2D.new()
	footprint.radius = 11.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = footprint
	query.collision_mask = 1 | 2 | 8 | 16 | 32
	var positions := PackedVector2Array()
	for i in guard_variants.size():
		var column := i % 4
		var row := floori(i / 4.0)
		var point := entry + forward.orthogonal() * (column - 1.5) * SPAWN_SPACING - forward * row * SPAWN_SPACING
		if NavigationServer2D.map_get_closest_point(nav, point).distance_to(point) > 0.5:
			return PackedVector2Array()
		query.transform = Transform2D(0.0, point)
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return PackedVector2Array()
		positions.append(point)
	for point in positions:
		var path_to_entry := NavigationServer2D.map_get_path(nav, point, entry, true)
		if path_to_entry.is_empty() or path_to_entry[-1].distance_to(entry) > 0.5:
			return PackedVector2Array()
	return positions


func _physics_process(delta: float) -> void:
	var now: float = last_stand.defense.elapsed
	if now >= next_decision:
		next_decision = now + decision_interval
		_make_decisions(now)
	if mode == Mode.MARCH and not soldiers.is_empty():
		_advance_waypoint(delta)


func _make_decisions(now: float) -> void:
	goals.clear()
	for index in range(soldiers.size() - 1, -1, -1):
		var soldier := soldiers[index]
		if not last_stand.living_resident(soldier):
			late_since.erase(soldier)
			isolated.erase(soldier)
			soldiers.remove_at(index)
	if soldiers.is_empty():
		set_physics_process(false)
		return
	var detected: Dictionary = {}
	for soldier in soldiers:
		if not soldier.is_available_for_infection() and not soldier.is_in_collision():
			continue
		soldier.guard_ai.sense()
		for enemy in soldier.guard_ai.visible_enemies:
			detected[enemy] = enemy.global_position
	for enemy in ignored_targets.keys():
		if not detected.has(enemy):
			ignored_targets.erase(enemy)
	if mode == Mode.COMBAT:
		if detected.has(target) and encounter_origin.distance_to(detected[target]) > pursuit_limit:
			ignored_targets[target] = true
			_begin_regroup()
		elif detected.has(target):
			target_point = detected[target]
		else:
			target = _select_target(detected, encounter_origin, pursuit_limit)
			if target == null:
				_begin_regroup()
			else:
				target_point = detected[target]
	elif mode == Mode.MARCH:
		target = _select_target(detected, waypoint, pursuit_limit)
		if target != null:
			mode = Mode.COMBAT
			encounter_origin = waypoint
			target_point = detected[target]
			return
	if mode == Mode.COMBAT:
		return
	var center := regroup_point if mode == Mode.REGROUP else waypoint
	var all_ready := _update_cohesion(center, now)
	if mode == Mode.REGROUP and all_ready:
		mode = Mode.MARCH
		waypoint = regroup_point
		path.clear()
	if mode == Mode.MARCH and path.is_empty():
		_plan_route()
	_assign_goals(regroup_point if mode == Mode.REGROUP else waypoint)


func _select_target(detected: Dictionary, origin: Vector2, limit: float) -> Node2D:
	var nearest: Node2D
	var distance := limit
	for enemy in detected:
		var gap := origin.distance_to(detected[enemy])
		if gap < distance and not ignored_targets.has(enemy):
			nearest = enemy
			distance = gap
	return nearest


func _begin_regroup() -> void:
	mode = Mode.REGROUP
	regroup_point = encounter_origin
	target = null
	target_point = Vector2.INF
	late_since.clear()


func _update_cohesion(center: Vector2, now: float) -> bool:
	var limit := REGROUP_RADIUS if mode == Mode.REGROUP else lag_limit
	var ready := true
	var leader_distance := INF
	var closest: Node2D
	for soldier in soldiers:
		var distance := soldier.global_position.distance_to(center)
		if distance < leader_distance:
			leader_distance = distance
			closest = soldier
		if distance <= limit:
			isolated.erase(soldier)
			late_since.erase(soldier)
		elif not isolated.has(soldier):
			if not late_since.has(soldier):
				late_since[soldier] = now
			if now - float(late_since[soldier]) >= wait_seconds:
				isolated[soldier] = true
			else:
				ready = false
	# A displaced squad always retains at least one active participant.
	if isolated.size() == soldiers.size():
		isolated.erase(closest)
		late_since.erase(closest)
		# Re-anchor the march to reachable ground when even the closest member
		# is cut off. Other soldiers remain alive and keep trying to rejoin.
		if mode == Mode.MARCH:
			waypoint = closest.global_position
			path.clear()
		else:
			regroup_point = closest.global_position
	return ready


func _plan_route() -> void:
	var goal := to_global(church_approach) if patrol_index < 0 else to_global(patrol_points[patrol_index])
	path = NavigationServer2D.map_get_path(get_world_2d().navigation_map, waypoint, goal, true)
	if not path.is_empty() and path[-1].distance_to(goal) > 0.5:
		path.clear()
	path_index = 0


func _waiting_for_squad() -> bool:
	for soldier in late_since:
		if not isolated.has(soldier): return true
	return false


func _advance_waypoint(delta: float) -> void:
	if _waiting_for_squad():
		return
	if path.is_empty() or path_index >= path.size():
		return
	var remaining := delta * march_speed
	var direction := Vector2.ZERO
	while path_index < path.size():
		var point := path[path_index]
		var distance := waypoint.distance_to(point)
		if distance > 0.01:
			direction = waypoint.direction_to(point)
		if distance > remaining:
			waypoint = waypoint.move_toward(point, remaining)
			break
		waypoint = point
		remaining -= distance
		path_index += 1
	if not direction.is_zero_approx():
		heading = heading.rotated(clampf(heading.angle_to(direction), -march_turn_rate * delta, march_turn_rate * delta))
	if path_index == path.size() and soldiers.any(func(soldier): return last_stand.living_resident(soldier) and soldier.global_position.distance_to(waypoint) <= ARRIVAL_RADIUS):
		_finish_leg()
	elif path_index == path.size():
		# Wait at the physical checkpoint until a soldier reaches it.
		path_index -= 1


func _finish_leg() -> void:
	if patrol_points.is_empty():
		return
	patrol_index = (patrol_index + 1) % patrol_points.size()
	path.clear()


func _assign_goals(center: Vector2) -> void:
	var nav := get_world_2d().navigation_map
	var lookahead := 0.0
	if mode == Mode.MARCH and not _waiting_for_squad() and not path.is_empty():
		lookahead = minf(march_lookahead, waypoint.distance_to(path[-1]))
	for i in soldiers.size():
		var actor := soldiers[i]
		if mode == Mode.MARCH and not path.is_empty():
			var depth := 22.0 - floori(i / 3.0) * 25.0 + lookahead
			if actor.defense_ranged_weapon: depth -= 8.0
			var on_route := _point_along_route(depth)
			var tangent := _point_along_route(depth - 10.0).direction_to(_point_along_route(depth + 10.0))
			if tangent.is_zero_approx(): tangent = heading
			var lane := tangent.orthogonal() * (i % 3 - 1) * 18.0
			var desired := on_route + lane
			var projected := NavigationServer2D.map_get_closest_point(nav, desired)
			if projected.distance_to(desired) > 4.0:
				# Narrow corners compress lateral spacing while each row
				# continues along the same route at its own distance.
				projected = NavigationServer2D.map_get_closest_point(nav, on_route + lane * 0.45)
			goals[actor] = projected
		else:
			var offset := heading.orthogonal() * (i % 4 - 1.5) * 19.0 + heading * (floori(i / 4.0) - 1.5) * 17.0
			goals[actor] = NavigationServer2D.map_get_closest_point(nav, center + offset)


func _point_along_route(offset: float) -> Vector2:
	var position := waypoint
	var remaining := absf(offset)
	var step := 1 if offset >= 0.0 else -1
	var index := path_index if step > 0 else path_index - 1
	while index >= 0 and index < path.size():
		var point := path[index]
		var distance := position.distance_to(point)
		if distance >= remaining:
			return position.move_toward(point, remaining)
		remaining -= distance
		position = point
		index += step
	# A trailing rank can still be outside the start of the route.
	return position - heading * remaining if step < 0 else position


func update_soldier(guard: Node, delta: float) -> bool:
	var actor: Node2D = guard.actor
	var crossbow: RefCounted = guard.crossbow
	for enemy in actor.encounter_participants.duplicate():
		if not actor.threat_detection.has_melee_contact(enemy):
			actor.leave_encounter(enemy)
	if get_tree().get_first_node_in_group("player_units") != null:
		for enemy in actor.threat_detection.nearby_threats():
			if enemy.global_position.distance_to(actor.global_position) <= enemy.INFECTION_DISTANCE and actor.threat_detection._is_visible_target(enemy):
				enemy.engage_defender(actor)
	if actor.is_in_collision():
		if crossbow != null:
			crossbow.note_contact(guard.now())
			crossbow.interrupt()
		guard.halt()
		return true
	var ready_target: bool = is_instance_valid(target) and target.is_alive()
	if mode == Mode.COMBAT and (crossbow != null or ready_target):
		var limit: float = actor.guard_pursuit_limit(pursuit_limit)
		if crossbow != null:
			var within_encounter := func(point: Vector2) -> bool:
				return encounter_origin.distance_to(point) <= limit
			var local: Array[Node2D] = guard.visible_enemies.filter(func(enemy):
				return is_instance_valid(enemy) and enemy.is_alive()
			)
			var current_target: Node2D
			if ready_target and within_encounter.call(target.global_position) and actor.threat_detection._is_visible_target(target):
				current_target = target
				if not local.has(target): local.append(target)
			var companions: Array[Node2D] = guard.local_allies.filter(func(ally):
				return is_instance_valid(ally) and ally.reinforcement_squad == self and not isolated.has(ally)
			)
			if guard.crossbow_disengage(delta, local, companions, [&"squad", get_instance_id()], within_encounter):
				return true
			if current_target == null:
				for enemy in local:
					if actor.threat_detection._is_visible_target(enemy) and within_encounter.call(enemy.global_position):
						current_target = enemy
						break
			if current_target != null:
				if not guard.engage_target(current_target, delta, encounter_origin, limit):
					guard.halt()
				return true
			if guard.now() - crossbow.settled_at < decision_interval:
				guard.halt()
				return true
		if encounter_origin.distance_to(target_point) > limit:
			guard.move_to(encounter_origin, delta)
		elif ready_target and actor.threat_detection._is_visible_target(target) and encounter_origin.distance_to(target.global_position) <= limit:
			guard.engage_target(target, delta, encounter_origin, limit)
		else:
			guard.move_to(target_point, delta)
	else:
		var point: Vector2 = goals.get(actor, waypoint)
		if crossbow != null:
			crossbow.interrupt()
			if mode == Mode.MARCH:
				if guard.visible_enemies.is_empty():
					crossbow.end_if_quiet(guard.now(), point)
				else:
					crossbow.note_contact(guard.now())
		var pace := -1.0
		if mode == Mode.MARCH and not _waiting_for_squad():
			pace = clampf(march_speed + (actor.global_position.distance_to(point) - march_lookahead) * 1.4, march_speed * 0.5, guard.movement_speed())
		if guard.move_to(point, delta, pace) == actor.NavigationResult.FAILED:
			guard.halt()
	return true
