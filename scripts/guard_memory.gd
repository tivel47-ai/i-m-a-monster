extends RefCounted
## Local evidence and bounded work. No live enemy references are stored here.
var incidents: Dictionary = {}
var tasks: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []
var capacity: int = 6
var lifetime: float = 45.0
var material_distance: float = 24.0
var serial: int = 0
var received_reports: Dictionary = {}
var published_sightings: Dictionary = {}

func valid_report(report: Dictionary, now: float) -> bool:
	if not report.has("incident") or not report.has("point") or not report.has("observed_at"):
		return false
	return report.point is Vector2 and report.point.is_finite() and now - float(report.observed_at) <= lifetime and float(report.observed_at) <= now + 0.1

func accept_delivery(report: Dictionary) -> bool:
	# Different routes can deliver the same original observation. Check the
	# source's last delivery before comparing it with the merged incident.
	var key := "%s:%s:%s" % [report.incident, report.get("source", 0), report.get("help", false)]
	var observed_at := float(report.observed_at)
	if observed_at <= float(received_reports.get(key, -INF)):
		return false
	received_reports[key] = observed_at
	return true

func _material_change(report: Dictionary, previous: Dictionary) -> bool:
	return (
		int(report.get("count", 1)) != int(previous.get("count", 1))
		or report.point.distance_to(previous.point) > material_distance
		or bool(report.get("help", false)) != bool(previous.get("help", false))
		or bool(report.get("retreating", false)) != bool(previous.get("retreating", false))
		or report.get("caller_point", report.point).distance_to(previous.get("caller_point", previous.point)) > material_distance
	)

func remember(report: Dictionary, now: float) -> bool:
	return _remember_in(incidents, report, now)

func remember_published_sighting(report: Dictionary, now: float) -> bool:
	return _remember_in(published_sightings, report, now)

func _remember_in(records: Dictionary, report: Dictionary, now: float) -> bool:
	if not valid_report(report, now): return false
	var id = report.incident
	var previous: Dictionary = records.get(id, {})
	if not previous.is_empty():
		# Delivery/repetition never renews the original evidence or declined work.
		var newer = float(report.observed_at) >= float(previous.observed_at)
		if not newer or not _material_change(report, previous):
			return false
	records[id] = report.duplicate(true)
	return true

func offer(kind: int, report: Dictionary, now: float) -> Dictionary:
	for task in tasks:
		if task.kind == kind and task.incident == report.incident:
			task.report = report.duplicate(true)
			task.point = report.point
			return task
	if tasks.size() >= maxi(capacity, 1):
		# Keep active/urgent work; replace the oldest pending low-severity task only.
		var victim: Dictionary = {}
		for task in tasks:
			if task.status != "active" and (victim.is_empty() or float(task.report.get("count", 1)) < float(victim.report.get("count", 1))):
				victim = task
		if victim.is_empty() or int(victim.report.get("count", 1)) > int(report.get("count", 1)):
			return {}
		finish(victim, "canceled", "capacity")
	serial += 1
	var task = {"id": serial, "kind": kind, "incident": report.incident, "report": report.duplicate(true), "point": report.point, "created_at": now, "status": "pending", "progress": 0, "elapsed": 0.0}
	tasks.append(task)
	return task

func finish(task: Dictionary, status: String, reason: String) -> void:
	if task.is_empty(): return
	task.status = status
	outcomes.append({"id": task.id, "incident": task.incident, "kind": task.kind, "status": status, "reason": reason})
	if outcomes.size() > 16: outcomes.pop_front()
	tasks.erase(task)

func expire(now: float) -> void:
	for task in tasks.duplicate():
		if task.get("inspection", false): continue # bounded by the response controller
		if now - float(task.report.observed_at) > lifetime:
			finish(task, "expired", "stale evidence")
	for id in incidents.keys():
		if now - float(incidents[id].observed_at) > lifetime: incidents.erase(id)
	for id in published_sightings.keys():
		if now - float(published_sightings[id].observed_at) > lifetime:
			published_sightings.erase(id)
	for key in received_reports.keys():
		if now - float(received_reports[key]) > lifetime:
			received_reports.erase(key)
