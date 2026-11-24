extends Node2D

signal threat_recognized(zombie: Node2D)

enum Awareness { UNAWARE, RECOGNIZING, AWARE }

@export var detection_enabled: bool = true
@export var detection_radius: float = 150.0:
	get:
		if is_instance_valid(villager) and villager.unit_vision != null:
			return villager.unit_vision.radius
		return detection_radius * radius_multiplier
@export var recognition_delay_min: float = 0.5
@export var recognition_delay_max: float = 1.0
@export var debug_enabled: bool = true:
	set(value):
		debug_enabled = value
		queue_redraw()

var awareness: Awareness = Awareness.UNAWARE
var radius_multiplier := 1.0
var pending_target: Node2D
var recognized_target: Node2D
var recognition_elapsed: float = 0.0
var recognition_required: float = 0.0
var recognition_random := RandomNumberGenerator.new()
var fortified_elapsed := 0.0
const FORTIFIED_SAMPLE_STEPS := 6

@onready var villager = get_parent()


func _ready() -> void:
	recognition_random.randomize()


func _physics_process(delta: float) -> void:
	if not detection_enabled or not villager.is_available_for_infection() or is_instance_valid(villager.interior_building):
		fortified_elapsed = 0.0
		reset_awareness()
		if not villager.is_alive():
			set_physics_process(false)
		return
	var fortified: Node
	if is_instance_valid(villager.defense) and is_instance_valid(villager.defense.last_stand) and villager.defense.organized.active():
		fortified = villager.defense.organized
		fortified_elapsed += delta
		if (Engine.get_physics_frames() + get_instance_id()) % FORTIFIED_SAMPLE_STEPS != 0: return
		delta = fortified_elapsed
		fortified_elapsed = 0.0
	else:
		fortified_elapsed = 0.0
	if awareness == Awareness.AWARE:
		if _is_visible_target(recognized_target):
			_record_alarm_sighting()
			return
		reset_awareness()
	if awareness == Awareness.RECOGNIZING and not _is_visible_target(pending_target):
		reset_awareness()
	if awareness == Awareness.UNAWARE:
		pending_target = _nearest_visible_zombie(fortified)
		if pending_target == null:
			return
		var minimum := maxf(recognition_delay_min, 0.0)
		recognition_required = recognition_random.randf_range(minimum, maxf(recognition_delay_max, minimum))
		awareness = Awareness.RECOGNIZING
		queue_redraw()
		# Start timing at this observation, without crediting the preceding frame.
		if recognition_required > 0.0:
			return
	else:
		recognition_elapsed += maxf(delta, 0.0)
	if recognition_elapsed + 0.000001 >= recognition_required:
		recognized_target = pending_target
		pending_target = null
		awareness = Awareness.AWARE
		queue_redraw()
		threat_recognized.emit(recognized_target)
		_record_alarm_sighting()


func _record_alarm_sighting() -> void:
	if villager.defense != null:
		var alert = villager.defense.alert
		if alert.level == alert.Level.ALARM:
			alert.observe_monster(villager, recognized_target)


func _is_valid_zombie(target: Variant) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target is PhysicsBody2D
		and (target.collision_layer & 2) != 0
		and target.is_in_group("player_units")
		and target.interior_building == villager.interior_building
		and target.has_method("is_alive")
		and target.is_alive()
	)


func _is_visible_target(target: Variant) -> bool:
	return _is_valid_zombie(target) and can_see(target)


func can_see(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	if villager.unit_vision != null:
		if villager.interior_building != target.get("interior_building") or not villager.unit_vision.contains(target.global_position):
			return false
	elif detection_radius <= 0.0 or global_position.distance_squared_to(target.global_position) > detection_radius * detection_radius:
		return false
	return _line_clear(target)


func _line_clear(target: Node2D) -> bool:
	# Same vision blockers as zombie LOS: solid bodies on layer 1.
	var ray := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	ray.collision_mask = 1
	ray.exclude = [villager.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func has_melee_contact(target: Variant) -> bool:
	return (_is_valid_zombie(target)
		and global_position.distance_to(target.global_position) <= target.INFECTION_DISTANCE + villager.arrival_tolerance
		and (can_see(target) if villager.unit_vision == null else _line_clear(target)))


func _nearest_visible_zombie(formation: Node = null) -> Node2D:
	var nearest: Node2D
	var nearest_distance := INF
	var candidates: Array[Node2D] = formation.exterior_monsters() if is_instance_valid(formation) else nearby_threats()
	for candidate in candidates:
		if candidate is Node2D and _is_visible_target(candidate):
			var distance := global_position.distance_squared_to(candidate.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
	return nearest


func nearby_threats() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if detection_radius <= 0: return result
	var shape := CircleShape2D.new()
	shape.radius = detection_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 2
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 64):
		if hit.collider is Node2D and _is_valid_zombie(hit.collider): result.append(hit.collider)
	return result


func get_recognized_target() -> Node2D:
	if not _is_valid_zombie(recognized_target):
		return null
	if villager.unit_vision != null and not villager.unit_vision.contains(recognized_target.global_position):
		return null
	return recognized_target


func reset_awareness() -> void:
	if awareness == Awareness.UNAWARE and pending_target == null and recognized_target == null:
		return
	awareness = Awareness.UNAWARE
	pending_target = null
	recognized_target = null
	recognition_elapsed = 0.0
	recognition_required = 0.0
	queue_redraw()


func _draw() -> void:
	if is_instance_valid(villager.interior_building): return
	if not debug_enabled or awareness == Awareness.UNAWARE:
		return
	var color := Color.YELLOW if awareness == Awareness.RECOGNIZING else Color.RED
	draw_circle(Vector2(0, -22 + villager.visual_ui_offset_y), 2.0, color)
