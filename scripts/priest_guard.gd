extends Node
## Dedicated protectors: never registered as report recipients or civilian recruits.
enum State { PATROL, JOINING, ESCORT, CHURCH_DEFENSE }
@export var priest_path: NodePath = NodePath("../../Priest30")
@export var patrol_points: PackedVector2Array = []
@export var territory: PackedVector2Array = PackedVector2Array([Vector2(1300,180),Vector2(1515,180),Vector2(1515,65),Vector2(2050,65),Vector2(2080,455),Vector2(1605,490),Vector2(1605,690),Vector2(1320,650)])
@export var church_position: Vector2 = Vector2(1420,557)
@export var slot: int = 0
@export var tactical_speed: float = 65.0
@export var protection_radius: float = 75.0
@export var joining_distance: float = 55.0
var state: State = State.PATROL
var permanent: bool = false
var joined: bool = false
var patrol_index: int = 0
var movement_goal: Vector2 = Vector2.INF
var recognized: Array[Node2D] = []
var escort_heading: Vector2 = Vector2.UP
@onready var actor = get_parent()
@onready var priest = get_node_or_null(priest_path)

func _ready() -> void:
	actor.threat_recognized.connect(observe)
	actor.encounter_started.connect(observe)
	actor.died.connect(func(_body): leave_group())
	actor.converted.connect(func(_body): leave_group())

func observe(enemy: Node2D) -> void:
	permanent = true
	if is_instance_valid(enemy) and not recognized.has(enemy): recognized.append(enemy)

func observe_corpse() -> void:
	permanent = true

func priest_alive() -> bool:
	return is_instance_valid(priest) and priest.is_alive()

func inside_territory(point: Vector2) -> bool:
	if is_instance_valid(priest) and priest.priest_routine != null:
		for path in priest.priest_routine.chapel_zone_paths + priest.priest_routine.cemetery_zone_paths:
			var zone = priest.priest_routine.get_node_or_null(path)
			if zone != null and zone.contains_world_point(point): return true
	return Geometry2D.is_point_in_polygon(point, territory)

func leave_group() -> void:
	joined = false
	if is_instance_valid(priest) and priest.priest_routine != null:
		priest.priest_routine.protectors.erase(actor)

func join_group() -> void:
	joined = true
	if priest.priest_routine != null and not priest.priest_routine.protectors.has(actor):
		priest.priest_routine.protectors.append(actor)

func halt() -> void:
	actor._stop_movement()
	movement_goal = Vector2.INF

func move_to(point: Vector2, speed: float, delta: float) -> int:
	if not actor.defense.reachable(actor, point):
		halt()
		return actor.NavigationResult.FAILED
	if not actor.has_destination or movement_goal.distance_to(point) > 8.0:
		actor._stop_movement()
		actor._set_peaceful_destination(point)
		movement_goal = point
	var result = actor._advance_navigation(movement_goal, speed, delta)
	if result != actor.NavigationResult.MOVING: halt()
	return result

func update_ai(delta: float) -> bool:
	if not actor.is_alive() or actor.infection_state == actor.InfectionState.TRANSFORMING:
		leave_group()
		return false
	if NavigationServer2D.map_get_iteration_id(actor.navigation_agent.get_navigation_map()) == 0: return true
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM: permanent = true
	var organized = actor.defense.organized
	var defending = organized != null and organized.active()
	if defending:
		organized.check_arrival(actor)
		church_position = organized.center
	var alive := priest_alive()
	var anchor: Vector2 = priest.global_position if alive else church_position
	var previous_state := state
	if not alive:
		leave_group()
		permanent = true
		state = State.CHURCH_DEFENSE
	elif permanent or not inside_territory(priest.global_position):
		if actor.global_position.distance_to(anchor) <= joining_distance: join_group()
		state = State.ESCORT if joined else State.JOINING
	else:
		leave_group()
		state = State.PATROL
	if state != previous_state:
		halt()
		if state == State.PATROL and not patrol_points.is_empty():
			patrol_index = 0
			for i in range(1, patrol_points.size()):
				if actor.global_position.distance_squared_to(patrol_points[i]) < actor.global_position.distance_squared_to(patrol_points[patrol_index]):
					patrol_index = i
	# Retain only live, personally recognized targets still in sight.
	recognized = recognized.filter(func(enemy): return is_instance_valid(enemy) and actor.threat_detection._is_visible_target(enemy))
	for enemy in actor.encounter_participants.duplicate():
		if not is_instance_valid(enemy) or not enemy.is_alive() or actor.global_position.distance_to(enemy.global_position) > enemy.INFECTION_DISTANCE + actor.arrival_tolerance:
			actor.leave_encounter(enemy)
	if actor.is_in_collision():
		if defending: organized.controller(actor).immediate_until = actor.defense.elapsed + organized.decision_interval * 2.0
		# Fight while physically engaged; never cancel melee to evade incoming damage.
		halt()
		return true
	var target: Node2D
	for enemy in recognized:
		if actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
			enemy.engage_defender(actor)
			if actor.is_in_collision():
				halt()
				return true
		if (joined or state == State.CHURCH_DEFENSE) and actor.global_position.distance_to(anchor) <= protection_radius and enemy.global_position.distance_to(anchor) <= protection_radius:
			if target == null or enemy.global_position.distance_to(anchor) < target.global_position.distance_to(anchor): target = enemy
	if target != null:
		if defending:
			var behavior = organized.controller(actor)
			behavior.target = target
			if behavior.shoot(target): return true
		move_to(target.global_position, tactical_speed, delta)
		return true
	if state == State.PATROL:
		if patrol_points.is_empty():
			halt()
		elif move_to(patrol_points[patrol_index], actor.move_speed, delta) == actor.NavigationResult.ARRIVED:
			patrol_index = (patrol_index + 1) % patrol_points.size()
		return true
	# Trail the actual travel direction; fixed southern slots would block a
	# southbound priest and repeatedly invalidate his normal navigation.
	if alive and priest.velocity.length_squared() > 4.0:
		escort_heading = priest.velocity.normalized()
	var offset := -escort_heading * 32.0 + escort_heading.orthogonal() * (-22 if slot == 0 else 22)
	if not alive: offset = Vector2(-22 if slot == 0 else 22,22)
	var goal: Vector2 = anchor + offset
	if defending and organized.arrived(actor) and (not alive or organized.arrived(priest)):
		var place: Vector2 = organized.position_for(actor, anchor, protection_radius * 0.8)
		if place.is_finite(): goal = place
	var nav: RID = actor.navigation_agent.get_navigation_map()
	goal = NavigationServer2D.map_get_closest_point(nav, goal)
	if not actor.defense.reachable(actor, goal): goal = anchor
	if actor.global_position.distance_to(goal) <= 10.0:
		halt()
	else:
		move_to(goal, tactical_speed, delta)
	return true
