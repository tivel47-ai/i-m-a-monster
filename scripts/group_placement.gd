extends Node2D

const AREA_POSITION_SAMPLE_COUNT := 384
const AREA_GOLDEN_ANGLE := 2.399963229728653
const AREA_COLLISION_PADDING := Vector2(2.6, 2.6)
const ZOMBIE_BODY_SIZE := Vector2(7.8, 15.6)
const NAVIGATION_POSITION_TOLERANCE := 16.0
const NAVIGATION_PATH_ENDPOINT_TOLERANCE := 2.0
const HORDE_BAND_WIDTH := 36.0
const HORDE_SAMPLE_AREA := 90.0
# Two avoidance radii plus room for stopping short of the target.
const HORDE_POSITION_SPACING := 28.0

func _get_area_position_candidates(
	center: Vector2,
	navigation_map: RID,
	selected_units: Array[Node], radius: float = 100.0
) -> Array[Vector2]:
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return []

	var collision_query := _area_collision_query(selected_units, 11)

	var candidates: Array[Vector2] = []
	for sample_index in range(AREA_POSITION_SAMPLE_COUNT):
		var radial_fraction := (
			(float(sample_index) + 0.5) / float(AREA_POSITION_SAMPLE_COUNT)
		)
		var sample_radius := radius * sqrt(radial_fraction)
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
			or navigation_position.distance_to(center) > radius
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


func assign_horde_positions(
	center: Vector2, radius: float, units: Array[Node], reserved: Array[Vector2],
	start_outside := false
) -> Dictionary:
	var assigned: Dictionary = {}
	if units.is_empty():
		return assigned
	var navigation_map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0:
		return assigned

	var collision_query := _area_collision_query(units, 27)
	var remaining := units.duplicate()
	remaining.sort_custom(func(a: Node2D, b: Node2D):
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	var inner := radius if start_outside else 0.0
	var outer := inner + HORDE_BAND_WIDTH if start_outside else radius
	# Bound the search even if the circle is outside the map or the mesh is disconnected.
	var search_limit := radius + 96.0 + sqrt(float(units.size() + reserved.size())) * 36.0
	while not remaining.is_empty() and outer <= search_limit:
		var candidates := _sample_horde_band(center, inner, outer, navigation_map, collision_query)
		if inner == 0.0:
			candidates.shuffle()
			# In a roomy circle, anchor the scatter with a spot at its center.
			if radius >= HORDE_POSITION_SPACING * sqrt(float(units.size() + reserved.size())) * 0.65:
				var center_on_mesh := NavigationServer2D.map_get_closest_point(navigation_map, center)
				if center_on_mesh.is_equal_approx(center) and not _is_too_close_to_existing_body(center, collision_query):
					candidates.append(center)
		elif start_outside:
			var start: Vector2 = remaining[0].global_position
			candidates.sort_custom(func(a: Vector2, b: Vector2):
				return a.distance_squared_to(start) > b.distance_squared_to(start))
		else:
			# The samples run from the inner edge of the band outward.
			candidates.reverse()
		for unit in remaining.duplicate():
			for index in range(candidates.size() - 1, -1, -1):
				var point := candidates[index]
				if reserved.any(func(occupied):
					return point.distance_squared_to(occupied) < HORDE_POSITION_SPACING * HORDE_POSITION_SPACING
				):
					candidates.remove_at(index)
					continue
				if not _has_path(navigation_map, unit.global_position, point, unit.navigation_agent):
					continue
				candidates.remove_at(index)
				reserved.append(point)
				assigned[unit] = point
				remaining.erase(unit)
				break
		inner = outer
		outer += HORDE_BAND_WIDTH
	return assigned


func _sample_horde_band(
	center: Vector2, inner: float, outer: float, navigation_map: RID,
	collision_query: PhysicsShapeQueryParameters2D
) -> Array[Vector2]:
	var samples := maxi(24, ceili(PI * (outer * outer - inner * inner) / HORDE_SAMPLE_AREA))
	var rotation := randf_range(0.0, TAU)
	var candidates: Array[Vector2] = []
	for index in range(samples):
		var fraction := (float(index) + randf()) / float(samples)
		var distance := sqrt(lerpf(inner * inner, outer * outer, fraction))
		var angle := index * AREA_GOLDEN_ANGLE + rotation + randf_range(-0.12, 0.12)
		var raw := center + Vector2.from_angle(angle) * distance
		var point := NavigationServer2D.map_get_closest_point(navigation_map, raw)
		var radius := point.distance_to(center)
		if radius < inner or radius > outer or raw.distance_to(point) > NAVIGATION_POSITION_TOLERANCE:
			continue
		if not _is_too_close_to_existing_body(point, collision_query):
			candidates.append(point)
	return candidates


func _area_collision_query(units: Array[Node], collision_mask: int) -> PhysicsShapeQueryParameters2D:
	var excluded_rids: Array[RID] = []
	for unit in units:
		if unit is CollisionObject2D:
			excluded_rids.append((unit as CollisionObject2D).get_rid())
	var shape := RectangleShape2D.new()
	shape.size = ZOMBIE_BODY_SIZE + AREA_COLLISION_PADDING
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = excluded_rids
	return query


func _is_too_close_to_existing_body(
	position: Vector2,
	query: PhysicsShapeQueryParameters2D
) -> bool:
	query.transform = Transform2D(0.0, position)
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _get_area_preferred_position(
	center: Vector2,
	unit_index: int,
	unit_count: int, radius: float = 100.0
) -> Vector2:
	if unit_count == 1:
		return center

	var radial_fraction := (float(unit_index) + 0.5) / float(unit_count)
	var preferred_radius := radius * 0.9 * sqrt(radial_fraction)
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
			if _has_path(navigation_map, start_position, candidate, navigation_agent):
				return [candidate]
			unreachable[candidate] = true
	return []


func _has_path(navigation_map: RID, start: Vector2, goal: Vector2, agent: NavigationAgent2D) -> bool:
	var path := NavigationServer2D.map_get_path(navigation_map, start, goal, true, agent.navigation_layers)
	return not path.is_empty() and path[-1].distance_to(goal) <= NAVIGATION_PATH_ENDPOINT_TOLERANCE


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


