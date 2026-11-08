extends Node
## Reasonable Defender. All tactical evidence is local; peaceful patrol stays separate.
enum State { PATROL, ALERT_PATROL, INVESTIGATE, SEARCH, COMBAT, RETREAT, ASSIST, GROUP_PATROL, RAISE_ALARM }
const MEMORY = preload("res://scripts/guard_memory.gd")
const INVESTIGATION = preload("res://scripts/guard_investigation.gd")
@export var investigation_seconds: float = 90.0
@export var verification_seconds: float = 30.0
@export var enabled: bool = true
@export var decision_interval: float = 0.35
@export var alert_recognition_factor: float = 0.75
@export var memory_seconds: float = 45.0
@export var task_capacity: int = 6
@export var commitment_seconds: float = 2.0
@export var communication_radius: float = 180.0
@export var pursuit_seconds: float = 8.0
@export var pursuit_distance: float = 260.0
@export var territory_margin: float = 180.0
@export var search_radius: float = 75.0
@export var search_seconds: float = 12.0
@export var observation_seconds: float = 1.0
@export var tactical_speed: float = 65.0
@export var retreat_distance: float = 180.0
@export var follower_distance: float = 75.0
@export var follower_wait_seconds: float = 5.0
@export var escort_speed_factor: float = 0.9
@export var recruitment_radius: float = 60.0
@export var witness_contact_radius: float = 24.0
@export var recruitment_interval: float = 4.0
@export var mobilization_seconds: float = 30.0
@export var alliance_wait_seconds: float = 6.0
@export var rendezvous_radius: float = 24.0
@export var alliance_cooldown: float = 12.0
@export var debug_enabled: bool = false
var state: State = State.PATROL
var memory = MEMORY.new()
var active: Dictionary = {}
var followers: Array[Node] = []
var alliance: Dictionary = {}
var cooperation_history: Dictionary = {}
var acknowledgements: Dictionary = {}
var cleared_incidents: Dictionary = {}
var outbox: Array[Dictionary] = []
var seen_since: Dictionary = {}
var visible_enemies: Array[Node2D] = []
var local_allies: Array[Node2D] = []
var last_seen_id: int = 0
var last_seen_point: Vector2
var last_seen_time: float = -1.0
var pursuit_started: float = 0.0
var pursuit_origin: Vector2
var pursuit_target: int = 0
var retreat_until: float = 0.0
var retreat_point: Vector2 = Vector2.INF
var movement_goal: Vector2 = Vector2.INF
var next_decision: float = 0.0
var next_recruitment: float = 0.0
var recruitment_point: Vector2 = Vector2.INF
var recruitment_until: float = 0.0
var mobilizing: bool = false
var mobilization_started: float = 0.0
var mobilization_goal: Vector2 = Vector2.INF
var mobilization_cursor: int = 0
var next_cooperation: float = 0.0
var selected_at: float = -100.0
var cohesion_started: float = -1.0
var bell_elapsed: float = 0.0
var rng = RandomNumberGenerator.new()
var investigation: RefCounted
@onready var actor = get_parent()

func _ready() -> void:
	rng.randomize()
	investigation = INVESTIGATION.new(self)
	actor.threat_recognized.connect(observe)
	actor.encounter_started.connect(observe) # physical contact is immediate evidence
	actor.defense.alert.level_changed.connect(_on_alert_changed)
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM: _on_alert_changed(0, actor.defense.alert.level)

func _on_alert_changed(previous: int, current: int) -> void:
	if current < actor.defense.alert.Level.ALARM or previous >= actor.defense.alert.Level.ALARM: return
	investigation.end("interrupted", "physical village alarm supersedes local response")
	mobilizing = true
	mobilization_started = now()
	mobilization_goal = Vector2.INF
	next_recruitment = 0.0
	if not active.is_empty() and active.kind in [State.SEARCH, State.INVESTIGATE, State.GROUP_PATROL]: suspend()

func ready_followers() -> int:
	var count = 0
	for follower in followers:
		if is_instance_valid(follower) and actor.defense.visible(actor, follower.actor, follower_distance) and follower.actor.is_available_for_infection() and follower.mode != follower.Mode.FLEEING: count += 1
	return count

func recruitment_site_safe(point: Vector2) -> bool:
	for report in memory.incidents.values():
		if now() - float(report.observed_at) <= memory_seconds and point.distance_to(report.point) <= search_radius: return false
	return true

func mobilize(delta: float) -> bool:
	if not mobilizing: return false
	if ready_followers() >= 2 or now() - mobilization_started >= mobilization_seconds:
		mobilizing = false
		mobilization_goal = Vector2.INF
		return false
	set_state(State.ALERT_PATROL)
	if maintain_followers(): return true
	recruit()
	if ready_followers() >= 2:
		mobilizing = false
		return false
	if recruitment_point.is_finite() and now() < recruitment_until:
		if actor.global_position.distance_to(recruitment_point) <= recruitment_radius * 0.8:
			halt(true)
			next_recruitment = now()
		else: move_to(recruitment_point, delta)
		return true
	# Known public places are map knowledge. No global scan of civilian positions.
	if not mobilization_goal.is_finite():
		var anchors: Array[Vector2] = []
		var points = actor.get_node_or_null(actor.points_of_interest_path)
		if points != null:
			for marker in points.get_children():
				if marker is Marker2D and marker.is_in_group("civilian_social_points") and territory_distance(marker.global_position) <= territory_margin and recruitment_site_safe(marker.global_position) and actor.defense.reachable(actor, marker.global_position): anchors.append(marker.global_position)
		if anchors.is_empty():
			var route = actor.guard_patrol._route()
			if route != null:
				for point in route.world_points():
					if recruitment_site_safe(point): anchors.append(point)
		if not anchors.is_empty():
			mobilization_goal = anchors[mobilization_cursor % anchors.size()]
			mobilization_cursor += 1
	if mobilization_goal.is_finite():
		var result = move_to(mobilization_goal, delta)
		if result != actor.NavigationResult.MOVING: mobilization_goal = Vector2.INF
	return true

func now() -> float:
	return actor.defense.elapsed

func _report(id: Variant, point: Vector2, count: int, help: bool = false) -> Dictionary:
	return {"incident": id, "point": point, "count": count, "help": help, "source": actor.get_instance_id(), "observed_at": now(), "credibility": 1.0, "relay": 0}

func observe(target: Node2D) -> void:
	if not enabled: return
	if not actor.threat_detection._is_visible_target(target): return
	last_seen_id = target.get_instance_id()
	actor.defense.alert.confirm_threat(actor, last_seen_id)
	if not seen_since.has(last_seen_id): next_decision = 0.0
	seen_since[last_seen_id] = now()
	last_seen_point = target.global_position
	last_seen_time = now()
	for task in memory.tasks.duplicate():
		if task.kind == State.SEARCH and task.incident == last_seen_id:
			memory.finish(task, "completed", "target personally reacquired; threat still active")
			if not active.is_empty() and active.id == task.id: active = {}
	var report = _report(last_seen_id, last_seen_point, maxi(visible_enemies.size(), 1))
	var previous: Dictionary = memory.incidents.get(last_seen_id, {})
	if not previous.is_empty():
		report.help = previous.get("help", false)
		if previous.source != actor.get_instance_id() or int(previous.get("relay", 0)) > 0:
			memory.incidents.erase(last_seen_id) # genuine personal reconfirmation
	if memory.remember(report, now()): outbox.append(report)
	elif memory.incidents.has(last_seen_id):
		# Continuing actual observation renews personal evidence, but does not
		# produce repeated assistance messages or fresh hearsay downstream.
		memory.incidents[last_seen_id].observed_at = now()

func receive_message(message: Dictionary, sender: Node2D) -> bool:
	if message.get("kind", "") == "corpse": return receive_corpse(message, sender)
	if not enabled or not actor.local_warning.communication_enabled or not actor.is_alive() or not is_instance_valid(sender) or sender == actor or sender.defense != actor.defense:
		return false
	if not sender.is_alive() or actor.global_position.distance_to(sender.global_position) > minf(communication_radius, actor.local_warning.hearing_radius): return false
	if message.get("ack", false):
		# An acknowledgement contains no enemy observation and cannot be relayed.
		if not memory.incidents.has(message.incident): return false
		acknowledgements[message.incident] = now()
		return true
	if int(message.get("relay", 0)) > 1: return false
	if not memory.valid_report(message, now()): return false
	if cleared_incidents.has(message.incident) and float(message.observed_at) <= float(cleared_incidents[message.incident]): return false
	var new_evidence: bool = memory.remember(message, now())
	if new_evidence: acknowledgements.erase(message.incident)
	var civilian_witness = sender.escort != null and sender.escort.report_to_guard_enabled and sender.escort.can_recruit() and not is_instance_valid(sender.escort.leader) and int(message.get("source", 0)) == sender.get_instance_id()
	if (message.get("witness", false) or civilian_witness) and sender.escort != null and actor.defense.alert.level < actor.defense.alert.Level.ALARM:
		var reporter = sender.escort.reporter
		var new_meeting := false
		if investigation.phase == investigation.Phase.NONE and reporter.has_live_report() and reporter.report.incident == message.incident:
			new_meeting = investigation.begin(message, sender)
		if new_evidence or new_meeting: actor.defense.alert.report_delivered(sender, actor, message)
		return new_evidence or new_meeting
	if not new_evidence: return false
	var kind = State.ASSIST if message.get("help", false) else State.INVESTIGATE
	var task = memory.offer(kind, message, now())
	if not task.is_empty() and kind == State.ASSIST and message.get("retreating", false) and message.has("caller_point"):
		# Cover an ally's reported withdrawal point instead of charging the
		# enemy position. The report is a snapshot, not a live ally tracker.
		if actor.defense.reachable(actor, message.caller_point):
			task.point = message.caller_point
			task.support_mode = "cover_withdrawal"
	if int(message.get("relay", 0)) == 0:
		var relay = message.duplicate(true)
		relay.relay = 1
		outbox.append(relay)
	actor.defense.alert.report_delivered(sender, actor, message)
	return true

func receive_eyewitness(message: Dictionary, sender: Node2D) -> bool:
	if message.get("kind", "") == "corpse": return receive_corpse(message, sender)
	if sender.escort == null or sender.defense != actor.defense or not sender.is_available_for_infection(): return false
	if not sender.local_warning.communication_enabled or not actor.local_warning.communication_enabled: return false
	if not message.has("point") or not message.has("incident") or not message.has("observed_at"): return false
	if int(message.incident) <= 0 or not sender.local_warning._valid_position(message.point) or float(message.observed_at) > now() + 0.1: return false
	if not actor.defense.visible(actor, sender, recruitment_radius) or now() - float(message.observed_at) > memory_seconds: return false
	if not investigation.begin(message, sender): return false
	memory.remember(message, now())
	actor.defense.alert.report_delivered(sender, actor, message)
	return true

func sense() -> void:
	visible_enemies.clear()
	local_allies.clear()
	if not actor.threat_detection.detection_enabled: return
	var candidates = actor.defense.nearby(actor, actor.threat_detection.detection_radius, 2 | 8)
	var present: Dictionary = {}
	for other in candidates:
		if other.is_in_group("player_units"):
			if not actor.threat_detection._is_visible_target(other): continue
			var id: int = other.get_instance_id()
			present[id] = true
			if not seen_since.has(id):
				var factor = alert_recognition_factor if actor.defense.alert.level >= actor.defense.alert.Level.SUSPICION else 1.0
				seen_since[id] = now() + rng.randf_range(actor.threat_detection.recognition_delay_min, actor.threat_detection.recognition_delay_max) * maxf(factor, 0.0)
			if now() >= float(seen_since[id]) or actor.get_recognized_threat() == other:
				visible_enemies.append(other)
		elif other.has_method("is_alive") and other.is_alive() and actor.defense.visible(actor, other, actor.threat_detection.detection_radius):
			local_allies.append(other)
	for id in seen_since.keys():
		if not present.has(id): seen_since.erase(id)
	for enemy in visible_enemies: observe(enemy)
	actor.defense.alert.observe_combat(actor, actor)
	for ally in local_allies:
		actor.defense.alert.observe_combat(actor, ally)
	# A target's death is only resolved when directly visible at this location.
	for other in candidates:
		if other.has_method("is_alive") and not other.is_alive() and actor.defense.visible(actor, other, actor.threat_detection.detection_radius):
			for task in memory.tasks.duplicate():
				if task.incident == other.get_instance_id(): memory.finish(task, "completed", "personally observed death")

func dangerous() -> bool:
	var defenders = known_support()
	var incoming = 0.0
	for enemy in visible_enemies: incoming += float(enemy.attack_damage)
	return visible_enemies.size() > defenders or (incoming > 0 and actor.current_health <= incoming * maxf(actor.attack_interval, 1.0))

func known_support() -> int:
	var defenders := 1
	for ally in local_allies:
		if not is_instance_valid(ally) or not ally.is_alive(): continue
		if ally.guard_ai != null or (ally.escort != null and ally.escort.leader == self and ally.escort.armed):
			# Injured companions remain group members but aren't treated as a
			# fresh defender simply because they are physically present.
			var incoming := 0.0
			for enemy in visible_enemies: incoming = maxf(incoming, enemy.attack_damage)
			if ally.current_health > incoming: defenders += 1
	return defenders

func set_state(value: State) -> void:
	if state == value: return
	if debug_enabled: print(actor.name, " GUARD ", State.keys()[state], " -> ", State.keys()[value])
	if value not in [State.PATROL, State.ALERT_PATROL]:
		actor._stop_movement()
		movement_goal = Vector2.INF
	state = value

func peaceful_duty() -> bool:
	return state in [State.PATROL, State.ALERT_PATROL] and active.is_empty() and alliance.is_empty() and visible_enemies.is_empty() and actor.defense.alert.level < actor.defense.alert.Level.ALARM

func suspend() -> void:
	if not active.is_empty() and memory.tasks.has(active): active.status = "interrupted"
	if not alliance.is_empty(): alliance.task.status = "interrupted"
	active = {}

func halt(preserve_goal: bool = false) -> void:
	actor.has_destination = false
	actor.velocity = Vector2.ZERO
	actor.navigation_agent.velocity = Vector2.ZERO
	if not preserve_goal: movement_goal = Vector2.INF

func move_to(point: Vector2, delta: float) -> int:
	if actor.global_position.distance_to(point) <= actor.arrival_tolerance:
		halt()
		return actor.NavigationResult.ARRIVED
	if not movement_goal.is_finite() or movement_goal.distance_to(point) > 8.0 or not actor.has_destination:
		if not actor.defense.reachable(actor, point): return actor.NavigationResult.FAILED
		actor._stop_movement()
		actor._set_peaceful_destination(point)
		movement_goal = point
	var speed = tactical_speed
	for follower in followers:
		if is_instance_valid(follower) and follower.mode != follower.Mode.FLEEING:
			speed = minf(speed, follower.movement_speed * escort_speed_factor)
	return actor._advance_navigation(point, speed, delta)

func finish(status: String, reason: String) -> void:
	memory.finish(active, status, reason)
	active = {}
	halt()
	bell_elapsed = 0.0

func offer_alarm(report: Dictionary) -> void:
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM or not is_instance_valid(actor.defense.bell): return
	var task = memory.offer(State.RAISE_ALARM, report, now())
	if not task.is_empty(): task.point = actor.defense.alarm_point(actor)

func call_help() -> void:
	if visible_enemies.is_empty(): return
	var report = _report(last_seen_id, last_seen_point, visible_enemies.size(), true)
	report.retreating = dangerous()
	report.caller_point = actor.global_position
	# Only materially changed observations go onto the wire.
	if memory.remember(report, now()): outbox.append(report)

func score(task: Dictionary) -> float:
	var distance: float = actor.global_position.distance_to(task.point)
	if not actor.defense.reachable(actor, task.point): return -INF
	var urgency = float(task.report.get("count", 1)) * float(task.report.get("credibility", 0.5))
	var value = urgency * 3.0 - distance / maxf(tactical_speed, 1.0)
	if task.kind == State.RAISE_ALARM: value += urgency * 2.0 + memory.incidents.size()
	elif task.kind == State.ASSIST:
		value += 5.0
		if acknowledgements.has(task.incident) and now() - float(acknowledgements[task.incident]) < memory_seconds: value -= 5.0
		if urgency > known_support(): value -= 10.0
	elif task.kind == State.SEARCH: value += 1.0
	return value

func choose_task() -> void:
	if not active.is_empty() and not memory.tasks.has(active): active = {}
	var best = active if active.is_empty() or active.kind != State.GROUP_PATROL else {}
	var best_score = score(best) if not best.is_empty() else -INF
	for task in memory.tasks.duplicate():
		if task.get("inspection", false): continue
		if task.kind == State.GROUP_PATROL: continue # executed via locally agreed objective
		if actor.defense.alert.level >= actor.defense.alert.Level.ALARM and ready_followers() == 0 and task.kind in [State.SEARCH, State.INVESTIGATE]:
			if not active.is_empty() and active.id == task.id:
				task.status = "interrupted"
				active = {}
				best = {}
				best_score = -INF
			continue # no voluntary lone search after the village has been alerted
		if task.kind == State.ASSIST and acknowledgements.has(task.incident) and int(task.report.get("count", 1)) <= known_support():
			memory.finish(task, "canceled", "locally acknowledged support is sufficient")
			continue
		var safe_cover = task.get("support_mode", "") == "cover_withdrawal" and task.point.distance_to(task.report.point) > search_radius
		if task.kind == State.ASSIST and float(task.report.get("count", 1)) > known_support() and not safe_cover:
			memory.finish(task, "canceled", "intervention too dangerous with known support")
			continue
		if task.kind == State.RAISE_ALARM and actor.defense.alert.level >= actor.defense.alert.Level.ALARM:
			memory.finish(task, "canceled", "bell already sounded")
			continue
		var value = score(task)
		if value == -INF:
			memory.finish(task, "infeasible", "no accessible route")
			continue
		if value > best_score + (1.0 if not best.is_empty() else 0.0):
			best = task
			best_score = value
	if best.is_empty():
		active = {}
		return
	if not active.is_empty() and best.id != active.id and now() - selected_at < commitment_seconds: return
	if active.is_empty() or best.id != active.id:
		suspend()
		active = best
		active.status = "active"
		selected_at = now()
		movement_goal = Vector2.INF
		if active.kind == State.ASSIST:
			actor.defense.broadcast(actor, {"ack": true, "incident": active.incident}, communication_radius)

func start_search() -> void:
	if last_seen_id == 0 or now() - last_seen_time > memory_seconds: return
	for task in memory.tasks:
		if task.kind == State.SEARCH: return # one temporary area only
	var report: Dictionary = memory.incidents.get(last_seen_id, {})
	if report.is_empty(): return
	var task = memory.offer(State.SEARCH, report, now())
	if task.is_empty(): return
	task.points = actor.defense.sample_points(actor, last_seen_point, search_radius)
	task.look = 0.0
	last_seen_id = 0

func territory_distance(point: Vector2) -> float:
	var route = actor.guard_patrol._route()
	if route == null: return 0.0
	var distance = INF
	var points: PackedVector2Array = route.world_points()
	for index in range(points.size()):
		var closest = Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
		distance = minf(distance, point.distance_to(closest))
	return distance

func retreat_destination() -> Vector2:
	var choices = actor.defense.sample_points(actor, actor.global_position, retreat_distance, 8)
	for ally in local_allies:
		if ally.guard_ai != null and actor.defense.reachable(actor, ally.global_position): choices.append(ally.global_position)
	var post = actor.guard_patrol.get_node_or_null(actor.guard_patrol.post_center_path)
	if post != null and actor.defense.reachable(actor, post.global_position): choices.append(post.global_position)
	var best = Vector2.INF
	var best_value = -INF
	for point in choices:
		var value = -actor.global_position.distance_to(point) * 0.2
		for enemy in visible_enemies:
			value += point.distance_to(enemy.global_position)
			var ray = PhysicsRayQueryParameters2D.create(point, enemy.global_position, 1, [actor.get_rid()])
			if not actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): value += retreat_distance
		for ally in local_allies:
			if ally.guard_ai != null: value -= point.distance_to(ally.global_position) * 0.2
		if value > best_value:
			best = point
			best_value = value
	return best

func maintain_followers() -> bool:
	var missing = false
	# Never pass freed objects to has/erase on a typed Array.
	for index in range(followers.size() - 1, -1, -1):
		if not is_instance_valid(followers[index]): followers.remove_at(index)
	for follower in followers.duplicate():
		# No remote death knowledge: only inspect a follower while actually visible.
		if actor.defense.visible(actor, follower.actor, communication_radius):
			if not follower.actor.is_alive():
				follower.release("observed death")
				continue
		if follower.mode == follower.Mode.FLEEING:
			if not active.is_empty() and active.kind == State.ASSIST: missing = true
			continue
		if not actor.defense.visible(actor, follower.actor, follower_distance): missing = true
	if not missing:
		cohesion_started = -1.0
		return false
	if cohesion_started < 0: cohesion_started = now()
	if now() - cohesion_started < follower_wait_seconds:
		halt(true) # waiting must not discard the territorial destination every frame
		return true
	if not active.is_empty() and active.kind == State.ASSIST:
		finish("canceled", "whole group cannot reunite for assistance")
	# Still-current membership stays reserved until its own separation rule ends.
	return false

func recruit() -> void:
	if now() < next_recruitment or actor.defense.alert.level < actor.defense.alert.Level.ALARM: return
	next_recruitment = now() + recruitment_interval
	recruitment_point = Vector2.INF
	if followers.size() >= 2: return
	if dangerous() or not visible_enemies.is_empty(): return
	var closest = INF
	for other in actor.defense.nearby(actor, communication_radius):
		if followers.size() >= 2: break
		if other.escort == null or not other.escort.can_recruit() or is_instance_valid(other.escort.leader) or now() < other.escort.next_invitation: continue
		if not actor.defense.visible(actor, other, communication_radius): continue
		var distance = actor.global_position.distance_to(other.global_position)
		if distance <= recruitment_radius:
			other.escort.invite(self)
		elif distance < closest and territory_distance(other.global_position) <= territory_margin and recruitment_site_safe(other.global_position) and actor.defense.reachable(actor, other.global_position):
			closest = distance
			recruitment_point = other.global_position # local snapshot, not a remote civilian tracker
			recruitment_until = now() + recruitment_interval
	if followers.size() >= 2: recruitment_point = Vector2.INF

func propose_cooperation(peer: Node, report: Dictionary) -> bool:
	if peer == self or not alliance.is_empty() or not peer.alliance.is_empty() or now() < next_cooperation or peer.now() < peer.next_cooperation: return false
	if actor.defense.alert.level < actor.defense.alert.Level.ALARM or not actor.defense.visible(actor, peer.actor, communication_radius): return false
	if not actor.is_available_for_infection() or not peer.actor.is_available_for_infection(): return false
	if cooperation_history.has(report.incident) and float(cooperation_history[report.incident]) >= float(report.observed_at): return false
	if peer.cooperation_history.has(report.incident) and float(peer.cooperation_history[report.incident]) >= float(report.observed_at): return false
	# A waypoint proposal cannot smuggle a second inherited relay.
	if not peer.memory.incidents.has(report.incident):
		var outgoing = report.duplicate(true)
		if outgoing.source != actor.get_instance_id():
			if int(outgoing.get("relay", 0)) >= 1: return false
			outgoing.relay = 1
		if not peer.receive_message(outgoing, actor): return false
	var points = actor.defense.sample_points(actor, report.point, search_radius, 8)
	var selected = Vector2.INF
	for point in points:
		if territory_distance(point) > territory_margin or peer.territory_distance(point) > peer.territory_margin: continue
		if not actor.defense.reachable(peer.actor, point): continue
		var followers_can_reach = true
		for escort in followers + peer.followers:
			if is_instance_valid(escort) and not actor.defense.reachable(escort.actor, point): followers_can_reach = false
		if followers_can_reach:
			selected = point
			break
	if not selected.is_finite(): return false
	if not peer.accept_cooperation(self, report, selected): return false
	var task = memory.offer(State.GROUP_PATROL, report, now())
	if task.is_empty():
		peer.end_cooperation("canceled", false)
		return false
	task.point = selected
	alliance = {"peer": weakref(peer), "point": selected, "incident": report.incident, "observed_at": report.observed_at, "arrived_at": -1.0, "agreed_at": now(), "task": task}
	return true

func accept_cooperation(peer: Node, report: Dictionary, point: Vector2) -> bool:
	if not alliance.is_empty() or now() < next_cooperation or not actor.defense.visible(actor, peer.actor, communication_radius) or not actor.defense.reachable(actor, point): return false
	if not visible_enemies.is_empty() or (not active.is_empty() and active.kind in [State.ASSIST, State.RAISE_ALARM]): return false
	var task = memory.offer(State.GROUP_PATROL, report, now())
	if task.is_empty(): return false
	task.point = point
	alliance = {"peer": weakref(peer), "point": point, "incident": report.incident, "observed_at": report.observed_at, "arrived_at": -1.0, "agreed_at": now(), "task": task}
	return true

func end_cooperation(status: String, notify: bool = true) -> void:
	if alliance.is_empty(): return
	var peer = alliance.peer.get_ref()
	cooperation_history[alliance.incident] = alliance.observed_at
	if not active.is_empty() and active.id == alliance.task.id: active = {}
	memory.finish(alliance.task, status, "joint objective; threat unresolved")
	memory.outcomes.append({"status": status, "incident": alliance.incident, "reason": "cooperation ended", "kind": State.GROUP_PATROL})
	if memory.outcomes.size() > 16: memory.outcomes.pop_front()
	alliance = {}
	next_cooperation = now() + alliance_cooldown
	if notify and is_instance_valid(peer) and actor.defense.visible(actor, peer.actor, communication_radius): peer.end_cooperation(status, false)

func execute_alliance(delta: float) -> bool:
	if alliance.is_empty(): return false
	if now() - float(alliance.agreed_at) > memory_seconds:
		end_cooperation("expired")
		return false
	set_state(State.GROUP_PATROL)
	alliance.status = "active"
	active = alliance.task
	active.status = "active"
	var result = actor.NavigationResult.ARRIVED if actor.global_position.distance_to(alliance.point) <= rendezvous_radius else move_to(alliance.point, delta)
	if result == actor.NavigationResult.FAILED:
		end_cooperation("infeasible")
	elif result == actor.NavigationResult.ARRIVED:
		halt()
		if float(alliance.arrived_at) < 0: alliance.arrived_at = now()
		var peer = alliance.peer.get_ref()
		# Completion acknowledgement is exchanged only when physically together.
		if is_instance_valid(peer) and actor.defense.visible(actor, peer.actor, communication_radius) and not peer.actor.is_alive():
			end_cooperation("infeasible")
		elif is_instance_valid(peer) and actor.defense.visible(actor, peer.actor, communication_radius) and peer.actor.global_position.distance_to(alliance.point) <= peer.rendezvous_radius:
			end_cooperation("completed")
		elif now() - float(alliance.arrived_at) >= alliance_wait_seconds: end_cooperation("interrupted")
	return true

func update_ai(delta: float) -> bool:
	if not enabled or not actor.autonomous_movement_enabled: return false
	if not actor.is_alive() or actor.infection_state == actor.InfectionState.TRANSFORMING: return false
	if NavigationServer2D.map_get_iteration_id(actor.navigation_agent.get_navigation_map()) == 0: return true
	if actor.defense.organized != null and actor.defense.organized.active():
		if now() >= next_decision:
			next_decision = now() + decision_interval
			memory.expire(now())
			sense()
			for message in outbox: actor.defense.broadcast(actor, message, communication_radius)
			outbox.clear()
		# The same local B2 evidence is used by travel decisions. No old ALARM
		# task may override church defense or repeatedly cancel physical combat.
		return actor.defense.organized.update_actor(actor, delta)
	memory.capacity = task_capacity
	memory.lifetime = memory_seconds
	var decision = now() >= next_decision
	if decision:
		next_decision = now() + decision_interval
		memory.expire(now())
		if investigation.phase != investigation.Phase.NONE and now() - investigation.started > investigation_seconds:
			investigation.end("expired", "bounded local response expired during interruption")
		if not alliance.is_empty() and now() - float(alliance.agreed_at) > memory_seconds:
			end_cooperation("expired") # even an ongoing emergency cannot preserve obsolete work forever
		for id in cooperation_history.keys():
			if now() - float(cooperation_history[id]) > memory_seconds: cooperation_history.erase(id)
		for id in acknowledgements.keys():
			if now() - float(acknowledgements[id]) > memory_seconds: acknowledgements.erase(id)
		sense()
		investigation.sense()
		investigation.start_pending_corpse()
		if investigation.phase == investigation.Phase.APPROACH: investigation.recruit_locally()
		for message in outbox: actor.defense.broadcast(actor, message, communication_radius)
		outbox.clear()
		if visible_enemies.is_empty() and last_seen_id != 0 and investigation.phase == investigation.Phase.NONE: start_search()
		if not visible_enemies.is_empty() and dangerous():
			var first_escalation: bool = investigation.escalate()
			call_help()
			offer_alarm(_report(last_seen_id, last_seen_point, visible_enemies.size()))
			# Once physically caught, defend with the real combat timers. Repeated
			# cancellation every decision tick made a wounded guard unhittable.
			if not actor.is_in_collision() and now() >= retreat_until and state not in [State.RETREAT, State.RAISE_ALARM] and (investigation.phase != investigation.Phase.ESCALATING or first_escalation):
				retreat_point = retreat_destination()
				retreat_until = now() + commitment_seconds
				suspend()
				set_state(State.RETREAT)
	# Reject stale live references after each frame, before any position access.
	visible_enemies = visible_enemies.filter(func(enemy): return is_instance_valid(enemy) and actor.threat_detection._is_visible_target(enemy))
	for enemy in visible_enemies:
		if actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
			enemy.engage_defender(actor) # self-defense also applies at pursuit/retreat limits
	if actor.is_in_collision():
		suspend()
		if not alliance.is_empty(): alliance.status = "interrupted"
		# Contact ends when the opponent physically leaves melee, including a
		# player-ordered zombie; no frozen, remote encounter damage.
		for enemy in actor.encounter_participants.duplicate():
			if not is_instance_valid(enemy) or not actor.threat_detection._is_visible_target(enemy) or actor.global_position.distance_to(enemy.global_position) > enemy.INFECTION_DISTANCE + actor.arrival_tolerance:
				actor.leave_encounter(enemy)
		set_state(State.COMBAT)
		# Forced encounter uses actual combat timers; do not freeze the task memory.
		if actor.is_in_collision(): return true
	if state == State.RETREAT and now() < retreat_until:
		if retreat_point.is_finite(): move_to(retreat_point, delta)
		else: halt() # trapped: retain self-defense through the existing encounter hooks
		return true
	if investigation.phase == investigation.Phase.ESCALATING: return investigation.update(delta)
	# A reachable bell takes precedence over renewed pursuit of a superior enemy.
	if not visible_enemies.is_empty() and dangerous() and actor.defense.alert.level < actor.defense.alert.Level.ALARM:
		var alarm_point: Vector2 = actor.defense.alarm_point(actor)
		if alarm_point.is_finite():
			set_state(State.RAISE_ALARM)
			if actor.global_position.distance_to(actor.defense.bell.global_position) <= actor.defense.bell_reach and actor.defense.bell_visible(actor):
				halt()
				bell_elapsed += delta
				if bell_elapsed >= actor.defense.bell_interaction_seconds: actor.defense.ring(actor)
			else:
				bell_elapsed = 0.0
				move_to(alarm_point, delta)
		else:
			set_state(State.RETREAT)
			if retreat_point.is_finite(): move_to(retreat_point, delta)
			else: halt()
		return true
	var imminent = false
	for enemy in visible_enemies:
		if actor.global_position.distance_to(enemy.global_position) <= search_radius: imminent = true
	if not imminent and mobilize(delta): return true
	if not visible_enemies.is_empty():
		if not alliance.is_empty(): alliance.status = "interrupted"
		suspend()
		var enemy: Node2D = visible_enemies[0]
		if pursuit_target != enemy.get_instance_id():
			pursuit_target = enemy.get_instance_id()
			pursuit_started = now()
			pursuit_origin = actor.global_position
		var local_inspection = investigation.phase != investigation.Phase.NONE and enemy.global_position.distance_to(investigation.origin) <= search_radius * 2.0 and now() - investigation.started <= investigation_seconds
		if (now() - pursuit_started > pursuit_seconds and not local_inspection) or pursuit_origin.distance_to(enemy.global_position) > pursuit_distance or (territory_distance(enemy.global_position) > territory_margin and not local_inspection):
			set_state(State.ALERT_PATROL)
			actor._stop_movement()
			halt() # cautious observation at pursuit boundary, not an endless chase
			return true
		set_state(State.COMBAT)
		if actor.global_position.distance_to(enemy.global_position) <= enemy.INFECTION_DISTANCE:
			enemy.engage_defender(actor)
		else: move_to(enemy.global_position, delta)
		return true
	if investigation.update(delta): return true
	if decision: choose_task()
	if not active.is_empty() and not memory.tasks.has(active): active = {}
	if maintain_followers(): return true
	if not active.is_empty():
		if active.kind == State.GROUP_PATROL: return execute_alliance(delta)
		set_state(active.kind as State)
		active.elapsed += delta
		if active.kind == State.SEARCH:
			if active.points.is_empty(): finish("infeasible", "no accessible search points")
			elif active.elapsed >= search_seconds: finish("completed", "search time elapsed; threat unresolved")
			else:
				var result = move_to(active.points[active.progress], delta)
				if result == actor.NavigationResult.FAILED: finish("infeasible", "search path blocked")
				elif result == actor.NavigationResult.ARRIVED:
					active.look += delta
					if active.look >= observation_seconds:
						active.progress += 1
						active.look = 0.0
						if active.progress >= active.points.size(): finish("completed", "accessible search checked; threat unresolved")
		elif active.kind == State.RAISE_ALARM:
			if actor.defense.alert.level >= actor.defense.alert.Level.ALARM: finish("canceled", "bell already sounded")
			elif actor.global_position.distance_to(actor.defense.bell.global_position) <= actor.defense.bell_reach and actor.defense.bell_visible(actor):
				halt()
				bell_elapsed += delta
				if bell_elapsed >= actor.defense.bell_interaction_seconds:
					if actor.defense.ring(actor): finish("completed", "physical bell interaction")
					else: finish("infeasible", "bell interaction blocked")
			else:
				bell_elapsed = 0.0
				if move_to(active.point, delta) == actor.NavigationResult.FAILED: finish("infeasible", "bell unreachable")
		else:
			var result = move_to(active.point, delta)
			if result == actor.NavigationResult.FAILED: finish("infeasible", "incident unreachable")
			elif result == actor.NavigationResult.ARRIVED:
				active.progress += delta
				if active.progress >= observation_seconds: finish("completed", "reported area inspected; threat unresolved")
		return true
	if not alliance.is_empty(): return execute_alliance(delta)
	if decision:
		recruit()
		if actor.defense.alert.level >= actor.defense.alert.Level.ALARM and now() >= next_cooperation:
			for ally in local_allies:
				if ally.guard_ai == null: continue
				for report in memory.incidents.values():
					if propose_cooperation(ally.guard_ai, report): return true
	# At ALARM stay on assigned territory, dynamically inspect accessible local points.
	if actor.defense.alert.level >= actor.defense.alert.Level.ALARM:
		set_state(State.ALERT_PATROL)
		if recruitment_point.is_finite() and now() < recruitment_until and followers.size() < 2:
			if actor.global_position.distance_to(recruitment_point) > recruitment_radius * 0.8:
				move_to(recruitment_point, delta)
			else:
				halt()
				next_recruitment = now() # invite at the next local decision tick
			return true
		if not movement_goal.is_finite():
			var route = actor.guard_patrol._route()
			if route != null:
				var points = route.world_points()
				var center: Vector2 = points[rng.randi_range(0, points.size() - 1)]
				var options = actor.defense.sample_points(actor, center, search_radius)
				if not options.is_empty(): movement_goal = options[0]
		if movement_goal.is_finite():
			if move_to(movement_goal, delta) != actor.NavigationResult.MOVING: movement_goal = Vector2.INF
		return true
	set_state(State.ALERT_PATROL if actor.defense.alert.level == actor.defense.alert.Level.SUSPICION else State.PATROL)
	return false # established road patrol and physical post relief remain authoritative

func receive_corpse(message: Dictionary, sender: Node2D) -> bool:
	if not enabled or not actor.is_available_for_infection() or not is_instance_valid(sender) or sender == actor:
		return false
	if not actor.local_warning.communication_enabled or not sender.local_warning.communication_enabled:
		return false
	if not actor.defense.visible(actor, sender, witness_contact_radius):
		return false
	if not actor.defense.alert.valid_corpse_report(sender, message):
		return false
	if actor.guard_patrol != null:
		actor.guard_patrol.release_for_incident()
	actor.defense.alert.confirm_corpse(actor, message, sender)
	return true
