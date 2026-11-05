extends RefCounted
## Local evidence and bounded work. No live enemy references are stored here.
var incidents: Dictionary = {}
var tasks: Array[Dictionary] = []
var outcomes: Array[Dictionary] = []
var capacity: int = 6
var lifetime: float = 45.0
var material_distance: float = 24.0
var serial: int = 0

func valid_report(report: Dictionary, now: float) -> bool:
	if not report.has("incident") or not report.has("point") or not report.has("observed_at"):
		return false
	return report.point is Vector2 and report.point.is_finite() and now - float(report.observed_at) <= lifetime and float(report.observed_at) <= now + 0.1

func remember(report: Dictionary, now: float) -> bool:
	if not valid_report(report, now): return false
	var id = report.incident
	var previous: Dictionary = incidents.get(id, {})
	if not previous.is_empty():
		# Delivery/repetition never renews the original evidence or declined work.
		var newer = float(report.observed_at) >= float(previous.observed_at)
		var material = int(report.get("count", 1)) != int(previous.get("count", 1)) or report.point.distance_to(previous.point) > material_distance or bool(report.get("help", false)) != bool(previous.get("help", false))
		material = material or bool(report.get("retreating", false)) != bool(previous.get("retreating", false)) or report.get("caller_point", report.point).distance_to(previous.get("caller_point", previous.point)) > material_distance
		if not newer or not material:
			return false
	incidents[id] = report.duplicate(true)
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
