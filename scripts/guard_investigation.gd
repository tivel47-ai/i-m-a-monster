extends RefCounted
## A temporary, local response before the bell. Not a village-wide stand-down.
enum Phase { NONE, CONTACT, APPROACH, SWEEP, ESCALATING }
var guard: Node
var phase: Phase = Phase.NONE
var report: Dictionary = {}
var task: Dictionary = {}
var witness: WeakRef
var contact_point: Vector2
var origin: Vector2
var peer: WeakRef
var points := PackedVector2Array()
var progress: int = 0
var look: float = 0.0
var started: float = 0.0
var sweep_started: float = 0.0
var saw_enemy: bool = false
var observed: Dictionary = {}
var defeated: Dictionary = {}
var verified_victory: bool = false
var completed_checks: int = 0
var completed_responses: int = 0
var supporting: bool = false

func _init(owner: Node) -> void:
	guard = owner

func can_receive(source: Node2D) -> bool:
	if not guard.enabled or not guard.actor.local_warning.communication_enabled or not guard.actor.autonomous_movement_enabled or not guard.actor.is_available_for_infection(): return false
	if guard.actor.defense.alert.level >= guard.actor.defense.alert.Level.ALARM: return false
	if phase != Phase.NONE:
		return phase == Phase.CONTACT and witness != null and witness.get_ref() == source
	return guard.followers.size() < 2 and guard.alliance.is_empty() and (guard.active.is_empty() or guard.active.kind not in [guard.State.RAISE_ALARM, guard.State.ASSIST])

func begin(message: Dictionary, source: Node2D) -> bool:
	if not can_receive(source) or source.escort == null or not source.escort.reporter.claim(guard): return false
	if phase != Phase.NONE: return true
	report = message.duplicate(true)
	supporting = false
	origin = report.point
	witness = weakref(source)
	contact_point = source.escort.reporter.meeting_point
	started = guard.now()
	task = guard.memory.offer(guard.State.INVESTIGATE, report, guard.now())
	if task.is_empty():
		source.escort.reporter.assigned = null
		report.clear()
		return false
	task.inspection = true
	guard.suspend()
	guard.active = task
	task.status = "active"
	phase = Phase.CONTACT
	return true

func join(other: RefCounted) -> bool:
	if phase != Phase.NONE or not guard.actor.autonomous_movement_enabled or not guard.actor.is_available_for_infection() or not guard.active.is_empty() or not guard.alliance.is_empty(): return false
	if not guard.visible_enemies.is_empty(): return false
	if not guard.actor.defense.visible(guard.actor, other.guard.actor, guard.communication_radius): return false
	var message: Dictionary = other.report.duplicate(true)
	if int(message.get("relay", 0)) >= 1: return false
	message.relay = 1
	if not guard.memory.remember(message, guard.now()) and not guard.memory.incidents.has(message.incident): return false
	task = guard.memory.offer(guard.State.INVESTIGATE, message, guard.now())
	if task.is_empty(): return false
	report = message
	supporting = true
	origin = report.point
	task.inspection = true
	task.status = "active"
	guard.active = task
	phase = Phase.APPROACH
	started = guard.now()
	peer = weakref(other.guard)
	other.peer = weakref(guard)
	guard.actor.defense.alert.report_delivered(other.guard.actor, guard.actor, message)
	return true

func sense() -> void:
	if phase == Phase.NONE: return
	for enemy in guard.visible_enemies:
		if phase == Phase.SWEEP: phase = Phase.APPROACH # fresh contact requires a fresh sweep afterwards
		saw_enemy = true
		observed[enemy.get_instance_id()] = weakref(enemy)
		report.point = enemy.global_position
	for id in observed:
		var enemy = observed[id].get_ref()
		if is_instance_valid(enemy) and guard.actor.defense.visible(guard.actor, enemy, guard.actor.threat_detection.detection_radius) and not enemy.is_alive():
			defeated[id] = true
			# A corpse is evidence only while personally visible.
			if guard.memory.incidents.has(id): guard.memory.incidents.erase(id)
	verified_victory = not observed.is_empty() and defeated.size() == observed.size()
	if phase == Phase.ESCALATING and guard.visible_enemies.is_empty() and verified_victory:
		# An actually witnessed local victory can replace this incident's bell
		# attempt with verification. Absence or a remote death cannot do this.
		phase = Phase.APPROACH
		guard.retreat_until = guard.now()
		guard.bell_elapsed = 0.0
		for pending in guard.memory.tasks.duplicate():
			if pending.kind == guard.State.RAISE_ALARM and pending.incident == report.incident:
				guard.memory.finish(pending, "canceled", "personally witnessed victory; verify area first")

func escalate() -> bool:
	if phase in [Phase.NONE, Phase.ESCALATING]: return false
	phase = Phase.ESCALATING
	task.status = "interrupted"
	return true

func start_sweep() -> void:
	points = guard.actor.defense.sample_points(guard.actor, report.point, guard.search_radius, 3)
	if supporting: points.reverse()
	progress = 0
	look = 0.0
	sweep_started = guard.now()
	phase = Phase.SWEEP
	guard.halt()

func recruit_locally() -> void:
	if phase == Phase.CONTACT: return
	# A peer defender is preferred; other civilians retain voluntary acceptance.
	if peer == null or not is_instance_valid(peer.get_ref()):
		for other in guard.local_allies:
			if other.guard_ai != null and other.guard_ai.investigation.join(self): break
	if guard.now() < guard.next_recruitment or not guard.visible_enemies.is_empty(): return
	guard.next_recruitment = guard.now() + guard.recruitment_interval
	for other in guard.local_allies:
		if guard.followers.size() >= 2: break
		if witness != null and witness.get_ref() == other: continue
		if other.local_warning.cleared_incidents.has(report.incident): continue
		if other.escort != null: other.escort.invite(guard, true)

func end(status: String, reason: String, reassure: bool = false) -> void:
	if phase == Phase.NONE: return
	var incident: int = report.incident
	var resolved: Array = observed.keys()
	if not resolved.has(incident): resolved.append(incident)
	if not task.is_empty():
		if not guard.active.is_empty() and guard.active.id == task.id: guard.active = {}
		guard.memory.finish(task, status, reason)
	for follower in guard.followers.duplicate():
		if not is_instance_valid(follower): continue
		if reassure and guard.actor.defense.visible(guard.actor, follower.actor, guard.communication_radius): follower.finish_investigation(incident, resolved)
		elif guard.actor.defense.alert.level < guard.actor.defense.alert.Level.ALARM: follower.release("local investigation ended")
	var source = witness.get_ref() if witness != null else null
	if is_instance_valid(source) and source.escort != null:
		source.escort.reporter.cancel_meeting(guard)
	if reassure:
		completed_responses += 1
		if resolved.has(guard.last_seen_id): guard.last_seen_id = 0
		for id in resolved:
			guard.cleared_incidents[id] = guard.now()
			guard.memory.incidents.erase(id)
		for pending in guard.memory.tasks.duplicate():
			if resolved.has(pending.incident): guard.memory.finish(pending, "canceled", "local area verification completed")
	phase = Phase.NONE
	report = {}
	task = {}
	witness = null
	peer = null
	observed.clear()
	defeated.clear()
	saw_enemy = false
	guard.halt()

func update(delta: float) -> bool:
	if phase == Phase.NONE: return false
	task.status = "active" if phase != Phase.ESCALATING else "interrupted"
	if guard.now() - started > guard.investigation_seconds:
		end("expired", "bounded local response expired")
		return false
	if phase == Phase.ESCALATING:
		guard.set_state(guard.State.RAISE_ALARM)
		var point: Vector2 = guard.actor.defense.alarm_point(guard.actor)
		if not point.is_finite():
			end("infeasible", "bell inaccessible")
			return true
		if guard.actor.global_position.distance_to(guard.actor.defense.bell.global_position) <= guard.actor.defense.bell_reach and guard.actor.defense.bell_visible(guard.actor):
			guard.halt()
			guard.bell_elapsed += delta
			if guard.bell_elapsed >= guard.actor.defense.bell_interaction_seconds: guard.actor.defense.ring(guard.actor)
		elif guard.move_to(point, delta) == guard.actor.NavigationResult.FAILED:
			end("infeasible", "bell path blocked")
		return true
	if phase == Phase.CONTACT:
		guard.set_state(guard.State.INVESTIGATE)
		var source = witness.get_ref() if witness != null else null
		if not is_instance_valid(source) or source.escort.reporter.assigned_guard() != guard:
			end("expired", "witness meeting expired")
			return true
		if guard.actor.defense.visible(guard.actor, source, guard.recruitment_radius):
			if not source.escort.reporter.report.is_empty():
				report = source.escort.reporter.report.duplicate(true)
				task.report = report.duplicate(true)
				task.point = report.point
			if source.escort.invite(guard, true, true):
				source.escort.reporter.complete(report.incident)
				phase = Phase.APPROACH
			else: end("canceled", "witness unavailable for escort")
		elif guard.move_to(contact_point, delta) == guard.actor.NavigationResult.FAILED:
			end("infeasible", "meeting point unreachable")
		return true
	recruit_locally()
	if guard.maintain_followers(): return true
	guard.set_state(guard.State.INVESTIGATE if phase == Phase.APPROACH else guard.State.SEARCH)
	guard.active = task
	if saw_enemy and phase != Phase.SWEEP: start_sweep()
	if phase == Phase.APPROACH:
		var result: int = guard.move_to(report.point, delta)
		if result == guard.actor.NavigationResult.ARRIVED: start_sweep()
		elif result == guard.actor.NavigationResult.FAILED: end("infeasible", "reported area unreachable")
	elif phase == Phase.SWEEP:
		if points.is_empty() or guard.now() - sweep_started > guard.verification_seconds:
			end("infeasible", "area verification incomplete")
			return true
		var result: int = guard.move_to(points[progress], delta)
		if result == guard.actor.NavigationResult.FAILED:
			end("infeasible", "verification path blocked")
		elif result == guard.actor.NavigationResult.ARRIVED:
			look += delta
			if look >= guard.observation_seconds:
				completed_checks += 1
				progress += 1
				look = 0.0
				if progress >= points.size(): end("completed", "nearby area physically checked after contact" if saw_enemy else "reported area physically checked; enemy not found", true)
	return true
