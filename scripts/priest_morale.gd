extends RefCounted
## Coverage is spatial. Entries store only the recipient and an exit deadline.
var ai: Node
var coverage: Dictionary = {}

func _init(owner: Node) -> void:
	ai = owner

func radius() -> float:
	if not is_instance_valid(ai.actor) or ai.actor.is_queued_for_deletion() or not ai.actor.is_alive():
		return 0.0
	var alert = ai.service.alert
	if alert.level == alert.Level.ORGANIZED_DEFENSE:
		return maxf(ai.defense_morale_radius, ai.alarm_morale_radius)
	return ai.alarm_morale_radius if alert.level == alert.Level.ALARM else 0.0

func sample(resident: Node2D, extent: float) -> bool:
	var id := resident.get_instance_id()
	if resident == ai.actor or resident.defense != ai.service or resident.is_queued_for_deletion() or not resident.is_alive():
		coverage.erase(id)
		return false
	if resident.global_position.distance_squared_to(ai.actor.global_position) <= extent * extent:
		coverage[id] = INF
		return true
	var until: float = coverage.get(id, 0.0)
	if until == INF:
		until = ai.service.elapsed + maxf(ai.residual_seconds, 0.0)
		coverage[id] = until
	if ai.service.elapsed < until: return true
	coverage.erase(id)
	return false

func refresh(residents: Array[Node]) -> void:
	var extent := radius()
	if extent <= 0:
		coverage.clear()
		return
	for resident in residents:
		if is_instance_valid(resident): sample(resident, extent)
	for id in coverage.keys():
		if not is_instance_id_valid(id): coverage.erase(id)

func supports(resident: Node2D) -> bool:
	var extent := radius()
	return extent > 0 and sample(resident, extent)
