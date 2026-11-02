extends Node2D

signal threat_recognized(zombie: Node2D)

enum Awareness { UNAWARE, RECOGNIZING, AWARE }

@export var detection_enabled: bool = true
@export var detection_radius: float = 150.0
@export var recognition_delay_min: float = 0.5
@export var recognition_delay_max: float = 1.0
@export var debug_enabled: bool = true:
	set(value):
		debug_enabled = value
		queue_redraw()

var awareness: Awareness = Awareness.UNAWARE
var pending_target: Node2D
var recognized_target: Node2D
var recognition_elapsed: float = 0.0
var recognition_required: float = 0.0
var recognition_random := RandomNumberGenerator.new()

@onready var villager = get_parent()


func _ready() -> void:
	recognition_random.randomize()


func _physics_process(delta: float) -> void:
	if not detection_enabled or not villager.is_available_for_infection():
		reset_awareness()
		if not villager.is_alive():
			set_physics_process(false)
		return
	if awareness == Awareness.AWARE:
		if _is_visible_target(recognized_target):
			return
		reset_awareness()
	if awareness == Awareness.RECOGNIZING and not _is_visible_target(pending_target):
		reset_awareness()
	if awareness == Awareness.UNAWARE:
		pending_target = _nearest_visible_zombie()
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


func _is_valid_zombie(target: Variant) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target is PhysicsBody2D
		and (target.collision_layer & 2) != 0
		and target.is_in_group("player_units")
		and target.has_method("is_alive")
		and target.is_alive()
	)


func _is_visible_target(target: Variant) -> bool:
	if not _is_valid_zombie(target) or detection_radius <= 0.0:
		return false
	if global_position.distance_squared_to(target.global_position) > detection_radius * detection_radius:
		return false
	# Same vision blockers as zombie LOS: solid bodies on layer 1.
	var ray := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	ray.collision_mask = 1
	ray.exclude = [villager.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _nearest_visible_zombie() -> Node2D:
	var nearest: Node2D
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("player_units"):
		if candidate is Node2D and _is_visible_target(candidate):
			var distance := global_position.distance_squared_to(candidate.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
	return nearest


func get_recognized_target() -> Node2D:
	return recognized_target if _is_valid_zombie(recognized_target) else null


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
	if not debug_enabled or awareness == Awareness.UNAWARE:
		return
	var color := Color.YELLOW if awareness == Awareness.RECOGNIZING else Color.RED
	draw_circle(Vector2(0, -22), 2.0, color)
