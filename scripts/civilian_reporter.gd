extends RefCounted
## Firsthand messenger. Only local guards and static duty places are known.
var escort: Node
var report: Dictionary = {}
var assigned: WeakRef
var assigned_at: float = -1.0
var delivered: int = 0
var failed: int = 0
var started: float = 0.0
var goal: Vector2 = Vector2.INF
var visited: Array[Vector2] = []

func _init(owner: Node) -> void:
	escort = owner

func observe(message: Dictionary) -> bool:
	var actor = escort.actor
	if not escort.report_to_guard_enabled or not escort.can_recruit() or not actor.autonomous_movement_enabled: return false
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM or is_instance_valid(escort.leader): return false
	if int(message.incident) in [delivered, failed]: return false
	if report.is_empty():
		started = actor.defense.elapsed
		visited.clear()
		goal = Vector2.INF
	report = message.duplicate(true)
	return true

func claim(guard: Node) -> bool:
	var current = assigned.get_ref() if assigned != null else null
	if is_instance_valid(current) and current != guard and escort.actor.defense.elapsed - assigned_at < escort.separation_seconds: return false
	assigned = weakref(guard)
	assigned_at = escort.actor.defense.elapsed
	return true

func complete(incident: int) -> void:
	delivered = incident
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
	if not escort.report_to_guard_enabled or not actor.local_warning.communication_enabled or report.is_empty() or is_instance_valid(escort.leader): return false
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM:
		report.clear()
		assigned = null
		goal = Vector2.INF
		return false
	var now: float = actor.defense.elapsed
	if now - float(report.observed_at) > escort.reporting_seconds or now - started > escort.reporting_seconds:
		failed = report.incident
		report.clear()
		assigned = null
		return false # personal home refuge remains the fallback
	var reaction = actor.threat_reaction
	if reaction.reaction_state in [reaction.Reaction.WARNING, reaction.Reaction.FROZEN]: return false
	var nearest: Node
	var distance := INF
	for other in actor.defense.nearby(actor, escort.contact_radius):
		if other.guard_ai == null or not other.is_available_for_infection() or not actor.defense.visible(actor, other, escort.contact_radius): continue
		if not other.guard_ai.investigation.can_receive(actor): continue
		var candidate: float = actor.global_position.distance_to(other.global_position)
		if candidate < distance:
			nearest = other.guard_ai
			distance = candidate
	if nearest != null:
		goal = nearest.actor.global_position # visible snapshot only
		if distance <= nearest.recruitment_radius:
			if nearest.receive_eyewitness(report, actor): return true
	if goal.is_finite() and actor.global_position.distance_to(goal) <= actor.arrival_tolerance:
		visited.append(goal)
		goal = Vector2.INF
	# A heard/seen guard can meet the witness; its position is never read remotely.
	if not goal.is_finite():
		var best := INF
		for point in actor.defense.guard_contact_points:
			if visited.has(point) or not actor.defense.reachable(actor, point): continue
			if not reaction._route_is_safe(point): continue
			var candidate: float = actor.global_position.distance_to(point)
			if candidate < best:
				best = candidate
				goal = point
	if not goal.is_finite(): return false
	if not reaction._route_is_safe(goal):
		if nearest == null: visited.append(goal)
		goal = Vector2.INF
		return false
	reaction.cancel_response()
	var result: int = escort.move_to(goal, delta, reaction.fleeing_speed)
	if result != actor.NavigationResult.MOVING:
		visited.append(goal)
		goal = Vector2.INF
	return true
