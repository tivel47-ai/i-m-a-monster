@tool
class_name GuardPatrolRoute2D
extends Line2D
## Ordered road waypoints, independent of activity polygons and the navigation mesh.
@export var observation_indices: PackedInt32Array = PackedInt32Array()
@export var observation_pause: Vector2 = Vector2(2, 4)
@export var debug_enabled: bool = false:
	set(value):
		debug_enabled=value
		queue_redraw()

func _init() -> void:
	default_color=Color.TRANSPARENT

func _enter_tree() -> void:
	if Engine.is_editor_hint(): EditorInterface.get_selection().selection_changed.connect(queue_redraw)

func _exit_tree() -> void:
	if Engine.is_editor_hint(): EditorInterface.get_selection().selection_changed.disconnect(queue_redraw)

func _draw() -> void:
	if not debug_enabled and not (Engine.is_editor_hint() and EditorInterface.get_selection().get_selected_nodes().has(self)): return
	if points.size()<2: return
	draw_polyline(points,Color(0.95,0.7,0.2,0.8),2.0,true)
	for index in observation_indices:
		if index>=0 and index<points.size(): draw_circle(points[index],5,Color(1,0.75,0.25))

func world_points() -> PackedVector2Array:
	return global_transform*points
