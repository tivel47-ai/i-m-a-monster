extends Node
## Selects peaceful territories and pacing; Villager owns all travel, clocks and interruptions.
enum Territory { CHAPEL, CEMETERY, PUBLIC }

@export var routine_enabled: bool = true
@export var chapel_zone_paths: Array[NodePath] = []
@export var cemetery_zone_paths: Array[NodePath] = []
@export var public_zone_paths: Array[NodePath] = []
@export var chapel_duration: Vector2 = Vector2(60, 90)
@export var cemetery_duration: Vector2 = Vector2(40, 65)
@export var public_duration: Vector2 = Vector2(15, 25)
## Completed cemetery visits between public outings; interrupts do not advance the routine.
@export var cemetery_visits_per_public: Vector2i = Vector2i(2, 3)
@export var chapel_local_rules: Vector3 = Vector3(0.65, 2.0, 0.6)
@export var cemetery_local_rules: Vector3 = Vector3(0.9, 2.0, 0.9)
@export var primary_local_speed: float = 22.0

var territory: Territory = Territory.CHAPEL
var completed_activities: int = 0
var completed_cemetery_visits: int = 0
var completed_public_visits: int = 0
var _visits_since_public: int = 0
var _next_public: int = 2

func _ready() -> void:
	_schedule_public()

func _schedule_public() -> void:
	var minimum := maxi(cemetery_visits_per_public.x, 1)
	_next_public = randi_range(minimum, maxi(cemetery_visits_per_public.y, minimum))

func _has_zone(paths: Array[NodePath], zone: ActivityZone2D) -> bool:
	for path in paths:
		if not path.is_empty() and get_node_or_null(path) == zone: return true
	return false

func zone_territory(zone: ActivityZone2D) -> int:
	if not is_instance_valid(zone): return -1
	if _has_zone(chapel_zone_paths, zone): return Territory.CHAPEL
	if _has_zone(cemetery_zone_paths, zone): return Territory.CEMETERY
	if _has_zone(public_zone_paths, zone): return Territory.PUBLIC
	return -1

func filter_options(options: Array[Dictionary]) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for option in options:
		var candidates: Array[Dictionary] = []
		for candidate in option.points:
			if zone_territory(candidate.zone) == territory: candidates.append(candidate)
		if not candidates.is_empty():
			var allowed := option.duplicate()
			allowed.points = candidates
			filtered.append(allowed)
	# An unavailable assigned territory waits safely; no unrelated fallback or skipped visit.
	return filtered

func activity_duration(zone: ActivityZone2D, fallback: Vector2) -> Vector2:
	match zone_territory(zone):
		Territory.CHAPEL: return chapel_duration
		Territory.CEMETERY: return cemetery_duration
		Territory.PUBLIC: return public_duration
	return fallback

func local_rules(zone: ActivityZone2D, fallback: Vector3) -> Vector3:
	match zone_territory(zone):
		Territory.CHAPEL: return chapel_local_rules
		Territory.CEMETERY: return cemetery_local_rules
	return fallback

func activity_completed(zone: ActivityZone2D) -> void:
	var finished := zone_territory(zone)
	if finished < 0: return
	completed_activities += 1
	match finished:
		Territory.CHAPEL:
			territory = Territory.PUBLIC if _visits_since_public >= _next_public and not public_zone_paths.is_empty() else Territory.CEMETERY
		Territory.CEMETERY:
			completed_cemetery_visits += 1
			_visits_since_public += 1
			territory = Territory.CHAPEL
		Territory.PUBLIC:
			completed_public_visits += 1
			_visits_since_public = 0
			_schedule_public()
			territory = Territory.CHAPEL
