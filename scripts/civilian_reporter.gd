extends RefCounted
## Firsthand messenger. Only local guards and static duty places are known.
const POST_LISTEN_SECONDS := 2.0
var escort: Node
var report: Dictionary = {}
var assigned: WeakRef
var meeting_deadline: float = -1.0
var meeting_point: Vector2 = Vector2.INF
var failed_meetings: Dictionary = {}
var delivered: int = 0
var failed: int = 0
var started: float = 0.0
var goal: Vector2 = Vector2.INF
var post_target: Vector2 = Vector2.INF
var post_arrived_at: float = -1.0

func _init(owner: Node) -> void:
	escort = owner

func can_start(incident: int) -> bool:
	var actor = escort.actor
	if not escort.report_to_guard_enabled or not escort.can_recruit() or not actor.autonomous_movement_enabled: return false
	if actor.defense == null or not actor.defense.has_guards or not actor.local_warning.communication_enabled: return false
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM or is_instance_valid(escort.leader): return false
	return incident > 0 and incident not in [delivered, failed]

func observe(message: Dictionary) -> bool:
	if not can_start(int(message.get("incident", 0))): return false
	var actor = escort.actor
	if actor.defense.elapsed - float(message.observed_at) >= escort.reporting_seconds: return false
	if not report.is_empty() and message.incident != report.incident: return false
	if report.is_empty():
		actor.threat_reaction.start_guard_run(message.point)
		started = actor.defense.elapsed
		failed_meetings.clear()
		goal = Vector2.INF
		post_target = Vector2.INF
		post_arrived_at = -1.0
	report = message.duplicate(true)
	return true

func contact_distance(guard: Node) -> float:
	if failed_meetings.has(guard.get_instance_id()): return INF
	var actor = escort.actor
	var distance: float = actor.threat_reaction._safe_route_length(guard.actor.global_position, true, true)
	return distance if distance <= escort.reporting_search_distance else INF

func assigned_guard() -> Node:
	if assigned == null or escort.actor.defense.elapsed >= meeting_deadline:
		return null
	return assigned.get_ref()

func cancel_meeting(guard: Node) -> void:
	if assigned == null or assigned.get_ref() != guard: return
	failed_meetings[guard.get_instance_id()] = true
	assigned = null
	goal = Vector2.INF

func claim(guard: Node) -> bool:
	var current = assigned_guard()
	if is_instance_valid(current):
		return current == guard
	var distance := contact_distance(guard)
	if distance == INF: return false
	var now: float = escort.actor.defense.elapsed
	var travel_time: float = distance / maxf(escort.actor.threat_reaction.fleeing_speed, 1.0)
	assigned = weakref(guard)
	meeting_deadline = now + travel_time + escort.separation_seconds
	meeting_point = guard.actor.global_position # supplied by the guard at the moment of reply
	goal = Vector2.INF
	return true

func complete(incident: int) -> void:
	delivered = incident
	cancel()

func cancel() -> void:
	report.clear()
	assigned = null
	goal = Vector2.INF

func reset(incident: int) -> void:
	if delivered == incident: delivered = 0
	if failed == incident: failed = 0
	if int(report.get("incident", 0)) == incident: report.clear()
	assigned = null
	goal = Vector2.INF

func update(delta: float) -> bool:
	var actor = escort.actor
	goal = Vector2.INF
	if report.is_empty(): return false
	var now: float = actor.defense.elapsed
	if not has_live_report():
		_abandon_search()
		return false # personal home refuge remains the fallback
	var responder = assigned_guard()
	if assigned != null and responder == null:
		var expired = assigned.get_ref()
		if is_instance_valid(expired): cancel_meeting(expired)
		else: assigned = null
	if responder == null:
		_request_visible_guard()
		responder = assigned_guard()
	if responder != null:
		if actor.defense.visible(actor, responder.actor, escort.contact_radius) and not responder.investigation.can_receive(actor):
			cancel_meeting(responder)
		elif actor.defense.visible(actor, responder.actor, responder.witness_contact_radius):
			escort.move_to(actor.global_position, delta)
			goal = meeting_point
			return true
		elif _travel_to(responder.actor.global_position if actor.defense.visible(actor, responder.actor, escort.contact_radius) else meeting_point, delta) != actor.NavigationResult.FAILED:
			return true
		else:
			cancel_meeting(responder)
		return false
	if not post_target.is_finite():
		post_target = _choose_post()
	if not post_target.is_finite():
		if actor.get_recognized_threat() != null:
			cancel()
			actor.threat_reaction.finish_guard_run(true)
		else:
			_abandon_search()
		return false
	var result := _travel_to(post_target, delta)
	if result == actor.NavigationResult.ARRIVED:
		if post_arrived_at < 0: post_arrived_at = now
		if now - post_arrived_at < POST_LISTEN_SECONDS: return true
	elif result == actor.NavigationResult.MOVING:
		return true
	_abandon_search()
	return false

func has_live_report() -> bool:
	if report.is_empty() or not can_start(int(report.incident)): return false
	var actor = escort.actor
	return actor.threat_reaction.reaction_state == actor.threat_reaction.Reaction.REPORTING and _remaining_seconds() > 0.0

func _remaining_seconds() -> float:
	var now: float = escort.actor.defense.elapsed
	return escort.reporting_seconds - maxf(now - started, now - float(report.observed_at))

func _request_visible_guard() -> void:
	var actor = escort.actor
	var nearest: Node
	var distance := INF
	for other in actor.defense.nearby(actor, escort.contact_radius):
		if other.guard_ai == null or not other.is_available_for_infection() or not actor.defense.visible(actor, other, escort.contact_radius): continue
		if not other.guard_ai.investigation.can_receive(actor): continue
		var reach: float = minf(other.guard_ai.communication_radius, other.local_warning.hearing_radius)
		if not actor.defense.visible(actor, other, other.guard_ai.recruitment_radius) and actor.global_position.distance_to(other.global_position) > reach: continue
		var candidate := contact_distance(other.guard_ai)
		if candidate < distance:
			nearest = other.guard_ai
			distance = candidate
	if nearest != null:
		if not nearest.receive_eyewitness(report, actor):
			nearest.receive_message(report, actor)

func _travel_to(point: Vector2, delta: float) -> int:
	var actor = escort.actor
	var reaction = actor.threat_reaction
	if reaction._safe_route_length(point, true, true) == INF:
		return actor.NavigationResult.FAILED
	var result: int = escort.move_to(point, delta, reaction.fleeing_speed)
	if result != actor.NavigationResult.FAILED: goal = point
	return result

func _abandon_search() -> void:
	failed = report.incident
	cancel()
	escort.actor.threat_reaction.finish_guard_run()

func _choose_post() -> Vector2:
	var actor = escort.actor
	var best := INF
	var target := Vector2.INF
	var travel_budget := maxf(_remaining_seconds() - POST_LISTEN_SECONDS, 0.0) * maxf(actor.threat_reaction.fleeing_speed, 0.0)
	for point in actor.defense.guard_posts:
		var length: float = actor.threat_reaction._safe_route_length(point, true, true)
		if length <= travel_budget and length < best:
			best = length
			target = point
	return target
