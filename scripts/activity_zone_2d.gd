@tool
class_name ActivityZone2D
extends Polygon2D
## Non-physical activity territory. Sampling never assigns an agent target.
## Query methods must be called from the main thread after physics/nav sync.

enum Activity { HOME, WORK, SOCIAL, WANDER }

@export_group("Assignment")
@export var zone_enabled: bool = true
@export var activity: Activity = Activity.HOME
@export var zone_id: StringName
@export var district_id: StringName
@export var location_path: NodePath
## Empty lists allow everyone; when both are set, both restrictions must match.
@export var allowed_residents: Array[NodePath] = []
@export var allowed_roles: PackedStringArray = []

@export_group("Future peaceful movement")
## (0, 0) means use the resident's activity duration. Data only in Stage 1.
@export var duration_override: Vector2 = Vector2.ZERO
@export_range(0, 100, 0.5) var local_move_speed: float = 30.0
@export_range(0, 200, 1) var local_move_radius: float = 40.0
@export var local_pause_duration: Vector2 = Vector2(3, 7)
@export_range(0, 1, 0.05) var local_move_probability: float = 0.5

@export_group("Destination validation")
@export_range(1, 64, 1) var sampling_attempts: int = 24
@export_flags_2d_physics var obstacle_mask: int = 1
@export_flags_2d_physics var occupied_body_mask: int = 8
## World-space clearance from occupied bodies and reserved destination centers.
@export_range(0, 64, 0.5) var minimum_separation: float = 12.0

@export_group("Debug")
@export var debug_enabled: bool = false:
	set(value):
		debug_enabled = value
		queue_redraw()

const NAVIGATION_TOLERANCE := 1.0
var _cached_polygon := PackedVector2Array()
var _triangles := PackedInt32Array()
var _areas := PackedFloat64Array()
var _total_area := 0.0
var _random := RandomNumberGenerator.new()


func _init() -> void:
	# Keep the native polygon handles, but draw the territory only on demand.
	color = Color.TRANSPARENT
	_random.randomize()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.connect(_refresh_editor)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.disconnect(_refresh_editor)


func _refresh_editor() -> void:
	queue_redraw()
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not has_valid_polygon():
		warnings.append("Use a simple, non-degenerate polygon with at least three distinct vertices; holes are unsupported.")
	if color.a > 0.0 or texture != null:
		warnings.append("Keep Color transparent and Texture empty; the zone uses its own optional debug drawing.")
	return warnings


func _draw() -> void:
	var selected := Engine.is_editor_hint() and EditorInterface.get_selection().get_selected_nodes().has(self)
	if not (debug_enabled or selected) or not has_valid_polygon():
		return
	draw_set_transform(offset)
	draw_colored_polygon(polygon, Color(0.25, 0.8, 0.65, 0.14))
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline, Color(0.25, 0.8, 0.65, 0.9), 1.5, true)


func has_valid_polygon() -> bool:
	_refresh_geometry()
	return not _triangles.is_empty() and offset.is_finite() and global_transform.is_finite() and absf(global_transform.determinant()) > 0.000001


func contains_world_point(point: Vector2) -> bool:
	return point.is_finite() and has_valid_polygon() and Geometry2D.is_point_in_polygon(to_local(point) - offset, polygon)


func allows_resident(resident: Node2D) -> bool:
	if not zone_enabled or not is_instance_valid(resident) or resident.is_queued_for_deletion():
		return false
	if not allowed_roles.is_empty() and not allowed_roles.has(str(resident.get_meta("village_role", ""))):
		return false
	if allowed_residents.is_empty():
		return true
	for path in allowed_residents:
		if not path.is_empty() and get_node_or_null(path) == resident:
			return true
	return false


## Empty or one world-space point, including concave polygons. No nav/physics query.
func sample_polygon_point(random: RandomNumberGenerator = null) -> Array[Vector2]:
	if not has_valid_polygon():
		return []
	var rng := random if random != null else _random
	var roll := rng.randf() * _total_area
	var triangle := _areas.size() - 1
	for index in range(_areas.size()):
		if roll < _areas[index]:
			triangle = index
			break
	var a := polygon[_triangles[triangle * 3]]
	var b := polygon[_triangles[triangle * 3 + 1]]
	var c := polygon[_triangles[triangle * 3 + 2]]
	var u := sqrt(rng.randf())
	var v := rng.randf()
	return [to_global(offset + (1.0 - u) * a + u * (1.0 - v) * b + u * v * c)]


## Empty means wait/retry or select another zone; never returns an unsafe fallback.
## Reservations are caller-owned snapshots, not persistent claims on this zone.
func sample_destination(resident: CharacterBody2D, reserved_positions: PackedVector2Array = PackedVector2Array(), random: RandomNumberGenerator = null) -> Array[Vector2]:
	if not _can_query(resident):
		return []
	for attempt in range(clampi(sampling_attempts, 1, 64)):
		var sample := sample_polygon_point(random)
		if sample.is_empty():
			return []
		if is_destination_valid(sample[0], resident, reserved_positions):
			return sample
	return []


func is_destination_valid(point: Vector2, resident: CharacterBody2D, reserved_positions: PackedVector2Array = PackedVector2Array()) -> bool:
	if not contains_world_point(point) or not _can_query(resident):
		return false
	var separation := maxf(minimum_separation, 0.0)
	for reserved in reserved_positions:
		if reserved.is_finite() and point.distance_to(reserved) < separation:
			return false
	var agent := resident.get_node("NavigationAgent2D") as NavigationAgent2D
	var navigation_map := agent.get_navigation_map()
	if NavigationServer2D.map_get_closest_point(navigation_map, point).distance_to(point) > NAVIGATION_TOLERANCE:
		return false
	# Preserve the body's rotation/scale AND the collision child's local offset.
	var body_transform := resident.global_transform
	body_transform.origin = point
	var shape_node := resident.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_node.shape
	query.transform = body_transform * resident.global_transform.affine_inverse() * shape_node.global_transform
	query.collision_mask = obstacle_mask | occupied_body_mask
	query.exclude = [resident.get_rid()]
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	if separation > 0.0 and occupied_body_mask != 0:
		var clearance := CircleShape2D.new()
		clearance.radius = separation
		query.shape = clearance
		query.transform = Transform2D(0.0, point)
		query.collision_mask = occupied_body_mask
		if not space.intersect_shape(query, 1).is_empty():
			return false
	var path := NavigationServer2D.map_get_path(navigation_map, resident.global_position, point, true, agent.navigation_layers)
	# Check both ends: navigation otherwise silently projects an off-mesh origin.
	return not path.is_empty() and path[0].distance_to(resident.global_position) <= NAVIGATION_TOLERANCE and path[-1].distance_to(point) <= NAVIGATION_TOLERANCE


func _can_query(resident: CharacterBody2D) -> bool:
	if not is_inside_tree() or not allows_resident(resident) or not resident.is_inside_tree():
		return false
	if resident.get_world_2d() != get_world_2d() or not resident.global_transform.is_finite() or absf(resident.global_transform.determinant()) <= 0.000001:
		return false
	var shape := resident.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var agent := resident.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if shape == null or shape.shape == null or shape.disabled or not shape.global_transform.is_finite() or absf(shape.global_transform.determinant()) <= 0.000001 or agent == null:
		return false
	var navigation_map := agent.get_navigation_map()
	return navigation_map.is_valid() and NavigationServer2D.map_is_active(navigation_map) and NavigationServer2D.map_get_iteration_id(navigation_map) > 0


func _refresh_geometry() -> void:
	if _cached_polygon == polygon:
		return
	_cached_polygon = polygon.duplicate()
	_triangles.clear()
	_areas.clear()
	_total_area = 0.0
	if polygon.size() < 3:
		return
	for i in range(polygon.size()):
		if not polygon[i].is_finite():
			return
		for j in range(i + 1, polygon.size()):
			if polygon[i].is_equal_approx(polygon[j]):
				return
		var previous := polygon[(i + polygon.size() - 1) % polygon.size()] - polygon[i]
		var following := polygon[(i + 1) % polygon.size()] - polygon[i]
		if is_zero_approx(previous.cross(following)) and previous.dot(following) > 0.0:
			return
		# Reject crossings and non-adjacent touching edges before triangulation.
		for j in range(i + 2, polygon.size()):
			if i == 0 and j == polygon.size() - 1:
				continue
			if _edges_touch(polygon[i], polygon[(i + 1) % polygon.size()], polygon[j], polygon[(j + 1) % polygon.size()]):
				return
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for index in range(0, triangles.size(), 3):
		var a := polygon[triangles[index]]
		var b := polygon[triangles[index + 1]]
		var c := polygon[triangles[index + 2]]
		_total_area += absf((b - a).cross(c - a)) * 0.5
		_areas.append(_total_area)
	if _total_area > 0.000001:
		_triangles = triangles


func _edges_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return true
	# The intersection helper returns null for collinear overlapping edges.
	return Geometry2D.get_closest_point_to_segment(a, c, d).is_equal_approx(a) or Geometry2D.get_closest_point_to_segment(b, c, d).is_equal_approx(b) or Geometry2D.get_closest_point_to_segment(c, a, b).is_equal_approx(c) or Geometry2D.get_closest_point_to_segment(d, a, b).is_equal_approx(d)
