extends Node
## Peaceful duty only. Villager's existing threat response runs before this component.
enum State { IDLE, PATROL, LEAVING_POST, RETURNING_POST, POST }
const MAX_AT_POST := 2

@export var patrol_enabled: bool = true
@export var route_path: NodePath
@export var post_access_path: NodePath
@export var post_zone_path: NodePath
@export var post_center_path: NodePath
@export var starts_on_duty: bool = false
@export var patrol_speed: float = 45.0
@export var minimum_patrol_seconds: float = 90.0
@export var minimum_post_duration: Vector2 = Vector2(24,40)
@export var post_radius: float = 220.0
@export var suspicion_pause_factor: float = 0.6

var state: State = State.IDLE
var pause_remaining := 0.0
var duty_remaining := 0.0
var patrol_elapsed := 0.0
var patrol_seconds := 0.0
var post_seconds := 0.0
var waypoints_reached := 0
var completed_laps := 0
var post_visits := 0
var _steps := PackedVector2Array()
var _cursor := 0
var _retries := 0
var _first_update := true
@onready var actor = get_parent()

func _ready() -> void:
	add_to_group("peaceful_guard_patrols")

func _zone() -> ActivityZone2D:
	return get_node_or_null(post_zone_path) as ActivityZone2D if not post_zone_path.is_empty() else null

func _route() -> GuardPatrolRoute2D:
	return get_node_or_null(route_path) as GuardPatrolRoute2D if not route_path.is_empty() else null

func _access() -> GuardPatrolRoute2D:
	return get_node_or_null(post_access_path) as GuardPatrolRoute2D if not post_access_path.is_empty() else null

func _eligible() -> bool:
	return patrol_enabled and actor.autonomous_movement_enabled and actor.is_available_for_infection() and not actor.threat_reaction.episode_active and (actor.guard_ai == null or not actor.guard_ai.enabled or actor.guard_ai.peaceful_duty())

func _peers() -> Array[Node]:
	var peers: Array[Node]=[]
	for peer in get_tree().get_nodes_in_group("peaceful_guard_patrols"):
		if not peer.is_queued_for_deletion() and peer.actor.get_world_2d()==actor.get_world_2d() and peer._zone()==_zone() and peer._eligible(): peers.append(peer)
	return peers

func is_near_post() -> bool:
	var center := get_node_or_null(post_center_path) as Node2D if not post_center_path.is_empty() else null
	return center!=null and (actor.global_position.distance_to(center.global_position)<=maxf(post_radius,1.0) or (_zone()!=null and _zone().contains_world_point(actor.global_position)))

func _stationed() -> Node:
	for peer in _peers():
		if peer!=self and peer.state==State.POST: return peer
	return null

func _incoming() -> bool:
	for peer in _peers():
		if peer!=self and peer.state==State.RETURNING_POST: return true
	return false

func _can_return() -> bool:
	var load := 0
	for peer in _peers():
		if peer!=self and (peer.state in [State.RETURNING_POST,State.POST] or peer.is_near_post()): load+=1
	return load<MAX_AT_POST and not _incoming()

func cancel_patrol() -> void:
	state=State.IDLE
	pause_remaining=0
	duty_remaining=0
	_steps.clear()
	_cursor=0
	_retries=0

func _stop_velocity() -> void:
	actor.has_destination=false
	actor.velocity=Vector2.ZERO
	actor.navigation_agent.velocity=Vector2.ZERO

func _set_steps(points: PackedVector2Array, mode: State, cursor: int = 0) -> void:
	actor._stop_movement()
	state=mode
	_steps=points
	_cursor=cursor
	pause_remaining=0
	actor.current_activity=actor.Activity.WANDER

func _begin_patrol() -> void:
	var points := _route().world_points()
	var closest := 0
	for index in range(points.size()):
		if actor.global_position.distance_squared_to(points[index])<actor.global_position.distance_squared_to(points[closest]): closest=index
	_set_steps(points,State.PATROL,closest)
	patrol_elapsed=0

func _leave_post() -> void:
	var points := _access().world_points()
	points.reverse()
	_set_steps(points,State.LEAVING_POST)
	patrol_elapsed=0

func _begin_return(direct: bool = false) -> bool:
	if not _can_return(): return false
	var zone := _zone()
	var sample := zone.sample_destination(actor,actor._zone_reservations(zone),null,actor.arrival_tolerance+1,actor.arrival_tolerance+1)
	if sample.is_empty(): return false
	var points := PackedVector2Array() if direct else _access().world_points()
	points.append(sample[0])
	_set_steps(points,State.RETURNING_POST)
	actor.current_zone=zone
	actor._using_zone=true
	actor.current_activity=actor.Activity.HOME
	return true

func _arrive_post() -> void:
	var previous := _stationed()
	state=State.POST
	_stop_velocity()
	actor.is_performing_activity=true
	actor.current_activity=actor.Activity.HOME
	var minimum := maxf(minimum_post_duration.x,1.0)
	duty_remaining=randf_range(minimum,maxf(minimum_post_duration.y,minimum))
	actor.wait_remaining=duty_remaining
	actor._begin_local_pause()
	post_visits+=1
	if previous!=null: previous._leave_post()

func update_patrol(delta: float) -> bool:
	if not patrol_enabled or _zone()==null or _route()==null or _access()==null or _route().points.size()<2:
		if state!=State.IDLE: actor._stop_movement()
		return false
	if state==State.IDLE:
		if pause_remaining>0:
			pause_remaining=maxf(pause_remaining-delta,0.0)
			return true
		if _first_update and starts_on_duty and _stationed()==null:
			if _begin_return(is_near_post()):
				_first_update=false
				return true
			# Region synchronization may lag the map iteration at startup.
			# Keep the initial sentry nearby and retry instead of sending everyone away.
			_stop_velocity()
			pause_remaining=1.0
			return true
		_first_update=false
		if is_near_post(): _leave_post()
		else: _begin_patrol()
	if state==State.POST:
		post_seconds+=delta
		duty_remaining=maxf(duty_remaining-delta,0.0)
		actor.wait_remaining=duty_remaining
		# Remain on duty until the relief actually arrives; reuse calm yard movement.
		actor._advance_local_zone_cycle(delta)
		return true
	if state==State.PATROL:
		patrol_seconds+=delta
		patrol_elapsed+=delta
		if _stationed()==null and not _incoming() and _can_return():
			var nearest: Node=self
			for peer in _peers():
				if peer.state!=State.PATROL: continue
				if peer.actor.global_position.distance_squared_to(_zone().global_position)<nearest.actor.global_position.distance_squared_to(_zone().global_position): nearest=peer
			# Follow the remaining road circuit to its access junction before returning.
			if nearest==self and _cursor==0 and _begin_return(): return true
	pause_remaining=maxf(pause_remaining-delta,0.0)
	if pause_remaining>0: return true
	if _steps.is_empty():
		actor._stop_movement()
		return true
	if not actor.has_destination: actor._set_peaceful_destination(_steps[_cursor])
	var status: int=actor._advance_navigation(actor.destination,minf(patrol_speed,actor.move_speed),delta)
	if status==actor.NavigationResult.MOVING: return true
	_stop_velocity()
	if status==actor.NavigationResult.FAILED:
		_retries+=1
		pause_remaining=1.0
		if _retries<3: return true
		if state==State.RETURNING_POST:
			# Failed travel is not arrival: release the relief claim and keep the sentry.
			_begin_patrol()
			return true
	else:
		waypoints_reached+=1
		_retries=0
	if state==State.PATROL and _route().observation_indices.has(_cursor):
		var interval := _route().observation_pause
		pause_remaining=randf_range(maxf(interval.x,0.0),maxf(interval.y,interval.x))
		if actor.defense != null and actor.defense.alert.level == actor.defense.alert.Level.SUSPICION:
			pause_remaining *= maxf(suspicion_pause_factor, 0.0)
	_cursor+=1
	if _cursor<_steps.size(): return true
	if state==State.RETURNING_POST:
		_arrive_post()
	elif state==State.LEAVING_POST:
		_begin_patrol()
	else:
		completed_laps+=1
		var incumbent := _stationed()
		if patrol_elapsed>=maxf(minimum_patrol_seconds,0.0) and (incumbent==null or incumbent.duty_remaining==0) and _begin_return(): return true
		_cursor=0
	return true
