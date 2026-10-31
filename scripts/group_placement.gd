extends Node2D

const AREA_ORDER_RADIUS := 100.0
const AREA_POSITION_SAMPLE_COUNT := 384
const AREA_GOLDEN_ANGLE := 2.399963229728653
const AREA_COLLISION_PADDING := Vector2(2.6, 2.6)
const ZOMBIE_BODY_SIZE := Vector2(13.0, 20.8)
const NAVIGATION_POSITION_TOLERANCE := 16.0
const NAVIGATION_PATH_ENDPOINT_TOLERANCE := 2.0

func _get_area_position_candidates(
	center: Vector2,
	navigation_map: RID,
	selected_units: Array[Node]
) -> Array[Vector2]:
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return []

	var excluded_rids: Array[RID] = []
	for unit in selected_units:
		if unit is CollisionObject2D:
			excluded_rids.append((unit as CollisionObject2D).get_rid())

	var collision_shape := RectangleShape2D.new()
	collision_shape.size = ZOMBIE_BODY_SIZE + AREA_COLLISION_PADDING
	var collision_query := PhysicsShapeQueryParameters2D.new()
	collision_query.shape = collision_shape
	collision_query.collision_mask = 11
	collision_query.collide_with_bodies = true
	collision_query.collide_with_areas = false
	collision_query.exclude = excluded_rids

	var candidates: Array[Vector2] = []
	for sample_index in range(AREA_POSITION_SAMPLE_COUNT):
		var radial_fraction := (
			(float(sample_index) + 0.5) / float(AREA_POSITION_SAMPLE_COUNT)
		)
		var sample_radius := AREA_ORDER_RADIUS * sqrt(radial_fraction)
		var sample_angle := AREA_GOLDEN_ANGLE * float(sample_index)
		var sample_position := center + Vector2(
			cos(sample_angle),
			sin(sample_angle)
		) * sample_radius
		var navigation_position := NavigationServer2D.map_get_closest_point(
			navigation_map,
			sample_position
		)
		if (
			sample_position.distance_to(navigation_position)
			> NAVIGATION_POSITION_TOLERANCE
			or navigation_position.distance_to(center) > AREA_ORDER_RADIUS
			or _is_too_close_to_existing_body(
				navigation_position,
				collision_query
			)
		):
			continue

		var is_duplicate := false
		for existing_candidate in candidates:
			if existing_candidate.distance_squared_to(navigation_position) < 64.0:
				is_duplicate = true
				break
		if not is_duplicate:
			candidates.append(navigation_position)

	return candidates


func _is_too_close_to_existing_body(
	position: Vector2,
	query: PhysicsShapeQueryParameters2D
) -> bool:
	query.transform = Transform2D(0.0, position)
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _get_area_preferred_position(
	center: Vector2,
	unit_index: int,
	unit_count: int
) -> Vector2:
	if unit_count == 1:
		return center

	var radial_fraction := (float(unit_index) + 0.5) / float(unit_count)
	var preferred_radius := AREA_ORDER_RADIUS * 0.9 * sqrt(radial_fraction)
	var preferred_angle := AREA_GOLDEN_ANGLE * float(unit_index)
	return center + Vector2(cos(preferred_angle), sin(preferred_angle)) * preferred_radius


func _choose_area_position(
	candidates: Array[Vector2], assigned_positions: Array[Vector2],
	start_position: Vector2, preferred_position: Vector2,
	navigation_map: RID, navigation_agent: NavigationAgent2D
) -> Array[Vector2]:
	var ordered := candidates.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(preferred_position) < b.distance_squared_to(preferred_position))
	var unreachable: Dictionary = {}
	for padding in [AREA_COLLISION_PADDING, Vector2.ZERO]:
		for candidate in ordered:
			if unreachable.has(candidate) or not _is_separated_from_assigned_positions(candidate, assigned_positions, padding):
				continue
			var path := NavigationServer2D.map_get_path(navigation_map, start_position, candidate, true, navigation_agent.navigation_layers)
			if not path.is_empty() and path[-1].distance_to(candidate) <= NAVIGATION_PATH_ENDPOINT_TOLERANCE:
				return [candidate]
			unreachable[candidate] = true
	return []


func _is_separated_from_assigned_positions(
	position: Vector2,
	assigned_positions: Array[Vector2],
	padding: Vector2
) -> bool:
	var minimum_separation := ZOMBIE_BODY_SIZE + padding
	for assigned_position in assigned_positions:
		var offset := position - assigned_position
		if (
			absf(offset.x) < minimum_separation.x
			and absf(offset.y) < minimum_separation.y
		):
			return false
	return true


