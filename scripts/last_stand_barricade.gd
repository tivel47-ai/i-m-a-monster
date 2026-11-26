extends StaticBody2D
## A planned section remains in the mission after destruction for readiness accounting.

signal health_changed

enum State { NOT_STARTED, EXISTING, DESTROYED }
enum Side { LEFT, LOWER, RIGHT }

const MONSTER_OBSTACLE := 32
const VISUAL_END_INSET := 3.5

@export var side: Side
@export_range(1.0, 1000.0) var max_hp := 240.0
@export var length := 80.0
@export var thickness := 10.0
@export_enum("Local +Y", "Local -Y") var defender_side := 0

var state := State.NOT_STARTED
var hp := 0.0
var work_points := PackedVector2Array()
var occupants: Dictionary = {}
var footprint := RectangleShape2D.new()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	# Collision overlaps at the joins so units and melee traces cannot slip
	# through the visible seams while both sections stand.
	footprint.size = Vector2(length + 2.0, thickness)
	var collision := CollisionShape2D.new()
	collision.shape = footprint
	add_child(collision)


func prepare_work_points(nav: RID, origin: Vector2, spacing: float, clearance: float) -> void:
	var step := maxf(spacing, clearance * 2.0)
	var count := maxi(1, floori(length / step))
	var shape := CircleShape2D.new()
	shape.radius = clearance
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for i in count:
		var x := (i - (count - 1) * 0.5) * step
		var y := (thickness * 0.5 + clearance + 4.0) * (1.0 if defender_side == 0 else -1.0)
		var point := to_global(Vector2(x, y))
		if NavigationServer2D.map_get_closest_point(nav, point).distance_to(point) > 0.5:
			continue
		var path := NavigationServer2D.map_get_path(nav, origin, point, true)
		if path.is_empty() or path[-1].distance_to(point) > 0.5:
			continue
		query.transform = Transform2D(0.0, point)
		if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			work_points.append(point)


func needs_work() -> bool:
	return state != State.DESTROYED and hp < max_hp


func overlaps(point: Vector2, padding: float) -> bool:
	var size := footprint.size
	return Rect2(-size * 0.5, size).grow(padding).has_point(to_local(point))


func build(amount: float) -> bool:
	if not needs_work() or amount <= 0.0:
		return false
	if state == State.NOT_STARTED:
		# Wait for the occupied footprint to clear before adding a solid body.
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = footprint
		query.transform = global_transform
		query.collision_mask = 2
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
		state = State.EXISTING
		collision_layer = MONSTER_OBSTACLE
	hp = minf(hp + amount, max_hp)
	health_changed.emit()
	queue_redraw()
	return true


func take_damage(amount: float) -> void:
	if state != State.EXISTING or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	if hp == 0.0:
		state = State.DESTROYED
		collision_layer = 0
		occupants.clear()
	health_changed.emit()
	queue_redraw()


func _draw() -> void:
	if state != State.EXISTING:
		return
	var visible_length := length - VISUAL_END_INSET * 2.0
	var left := -visible_length * 0.5
	var bottom := thickness * 0.5
	draw_rect(Rect2(left, -bottom + 1.0, visible_length, thickness - 2.0), Color("#392a21"))
	var stakes := maxi(1, roundi(visible_length / 7.0))
	for i in stakes:
		var x := left + (i + 0.5) * visible_length / stakes
		var tip := -bottom + float(i % 3)
		draw_line(Vector2(x - 1.5, bottom - 1.0), Vector2(x + 1.0, tip), Color("#674733"), 4.0)
		draw_line(Vector2(x - 2.5, bottom - 1.0), Vector2(x, tip), Color("#ad845a"), 1.0)
	for fraction: float in [0.23, 0.77]:
		var x := left + visible_length * fraction
		draw_line(Vector2(x - 3.0, -bottom + 1.0), Vector2(x + 3.0, bottom - 1.0), Color("#97714f"), 2.5)
	var bar := Rect2(Vector2(left, bottom + 4.0), Vector2(visible_length, 2.0))
	draw_rect(bar, Color("#281a15"))
	bar.size.x *= hp / max_hp
	draw_rect(bar, Color("#b5a16a"))
