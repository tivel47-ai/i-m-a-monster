extends Node2D

const TARGET_PERCENT := 80
const SELECTION_DRAG_THRESHOLD := 8.0
const PLAYER_SELECTION_LAYER := 4
const AREA_ORDER_RADIUS := 100.0
const AREA_POSITION_SAMPLE_COUNT := 384
const AREA_GOLDEN_ANGLE := 2.399963229728653
const AREA_COLLISION_PADDING := Vector2(4.0, 4.0)
const NAVIGATION_POSITION_TOLERANCE := 16.0
const NAVIGATION_PATH_ENDPOINT_TOLERANCE := 2.0
const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")

enum MissionState {
	ACTIVE,
	WON,
}

var villagers: Array[Node] = []
var converted_resident_ids: Dictionary = {}
var dead_resident_ids: Dictionary = {}
var total_residents: int = 0
var infected_residents: int = 0
var killed_residents: int = 0
var mission_state: MissionState = MissionState.ACTIVE
var selection_in_progress: bool = false
var marquee_active: bool = false
var selection_start_screen: Vector2
var selection_current_screen: Vector2

@onready var residents_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Residents
@onready var infected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Infected
@onready var killed_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Killed
@onready var uninfected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Uninfected
@onready var progress_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Progress
@onready var status_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Status
@onready var selection_rect: Panel = $CanvasLayer/SelectionRect


func _ready() -> void:
	for resident in find_children("*", "", true, false):
		if not resident.has_method("is_converted"):
			continue
		villagers.append(resident)
		if not resident.has_signal("converted"):
			push_error("Mission resident is missing the converted signal: %s" % resident.get_path())
		else:
			var converted_error := resident.connect("converted", _on_resident_converted)
			if converted_error != OK:
				push_error("Could not connect resident conversion signal: %s" % error_string(converted_error))

		if not resident.has_signal("died"):
			push_error("Mission resident is missing the died signal: %s" % resident.get_path())
		else:
			var died_error := resident.connect("died", _on_resident_died)
			if died_error != OK:
				push_error("Could not connect resident death signal: %s" % error_string(died_error))

		if resident.call("is_converted"):
			converted_resident_ids[resident.get_instance_id()] = true
		elif resident.has_method("is_dead") and resident.call("is_dead"):
			dead_resident_ids[resident.get_instance_id()] = true

	total_residents = villagers.size()
	_refresh_mission_progress()


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		var destination := _screen_to_world(event.position)
		if event.shift_pressed:
			_issue_area_move_order(destination)
		else:
			for unit in get_tree().get_nodes_in_group("player_units"):
				if unit.is_selected:
					unit.issue_player_move_order(destination)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selection_in_progress = true
			marquee_active = false
			selection_start_screen = event.position
			selection_current_screen = event.position
			selection_rect.hide()
		elif selection_in_progress:
			selection_current_screen = event.position
			_update_marquee_state()
			if marquee_active:
				call_deferred(
					"_select_units_in_marquee",
					selection_start_screen,
					selection_current_screen
				)
			else:
				call_deferred("_select_unit_at_screen_position", selection_current_screen)

			selection_in_progress = false
			marquee_active = false
			selection_rect.hide()
	elif event is InputEventMouseMotion and selection_in_progress:
		selection_current_screen = event.position
		_update_marquee_state()


func _update_marquee_state() -> void:
	if not marquee_active:
		marquee_active = (
			selection_start_screen.distance_to(selection_current_screen)
			> SELECTION_DRAG_THRESHOLD
		)

	if not marquee_active:
		return

	var top_left := Vector2(
		minf(selection_start_screen.x, selection_current_screen.x),
		minf(selection_start_screen.y, selection_current_screen.y)
	)
	var bottom_right := Vector2(
		maxf(selection_start_screen.x, selection_current_screen.x),
		maxf(selection_start_screen.y, selection_current_screen.y)
	)
	selection_rect.position = top_left
	selection_rect.size = bottom_right - top_left
	selection_rect.show()


func _select_unit_at_screen_position(screen_position: Vector2) -> void:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = _screen_to_world(screen_position)
	query.collision_mask = PLAYER_SELECTION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var selected_units: Array[Node] = []
	for result in get_world_2d().direct_space_state.intersect_point(query):
		var unit := _get_player_unit(result["collider"])
		if unit != null:
			selected_units.append(unit)
			break

	_apply_selection(selected_units)


func _select_units_in_marquee(start_screen: Vector2, end_screen: Vector2) -> void:
	var world_corners := PackedVector2Array([
		_screen_to_world(start_screen),
		_screen_to_world(Vector2(end_screen.x, start_screen.y)),
		_screen_to_world(end_screen),
		_screen_to_world(Vector2(start_screen.x, end_screen.y)),
	])
	var world_center := Vector2.ZERO
	for corner in world_corners:
		world_center += corner
	world_center /= world_corners.size()

	var selection_shape := ConvexPolygonShape2D.new()
	var local_corners := PackedVector2Array()
	for corner in world_corners:
		local_corners.append(corner - world_center)
	selection_shape.points = Geometry2D.convex_hull(local_corners)

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = selection_shape
	query.transform = Transform2D(0.0, world_center)
	query.collision_mask = PLAYER_SELECTION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var selected_units: Array[Node] = []
	for result in get_world_2d().direct_space_state.intersect_shape(query, 1024):
		var unit := _get_player_unit(result["collider"])
		if unit != null and not selected_units.has(unit):
			selected_units.append(unit)

	_apply_selection(selected_units)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func _issue_area_move_order(center: Vector2) -> void:
	var selected_units: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if (
			unit.is_selected
			and not unit.is_dead
			and unit.has_method("issue_player_area_move_order")
		):
			selected_units.append(unit)

	if selected_units.is_empty():
		return

	var navigation_agent := (
		selected_units[0].get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	)
	if navigation_agent == null:
		push_error("Selected zombie is missing its NavigationAgent2D.")
		for unit in selected_units:
			unit.call("issue_player_area_hold_order")
		return

	var navigation_map := navigation_agent.get_navigation_map()
	var candidates := _get_area_position_candidates(
		center,
		navigation_map,
		selected_units
	)
	var assigned_positions: Array[Vector2] = []
	for unit_index in range(selected_units.size()):
		var unit := selected_units[unit_index]
		var unit_navigation_agent := (
			unit.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
		)
		if unit_navigation_agent == null:
			push_error("Selected zombie is missing its NavigationAgent2D.")
			unit.call("issue_player_area_hold_order")
			continue

		var preferred_position := _get_area_preferred_position(
			center,
			unit_index,
			selected_units.size()
		)
		var destination := _choose_area_position(
			candidates,
			assigned_positions,
			unit.global_position,
			preferred_position,
			navigation_map,
			unit_navigation_agent
		)
		if destination.is_empty():
			unit.call("issue_player_area_hold_order")
			continue

		var assigned_position: Vector2 = destination[0]
		assigned_positions.append(assigned_position)
		unit.call("issue_player_area_move_order", assigned_position)


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
	collision_shape.size = Vector2(20.0, 32.0) + AREA_COLLISION_PADDING
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
	candidates: Array[Vector2],
	assigned_positions: Array[Vector2],
	start_position: Vector2,
	preferred_position: Vector2,
	navigation_map: RID,
	navigation_agent: NavigationAgent2D
) -> Array[Vector2]:
	var navigation_candidates: Array[Vector2] = []
	for candidate in candidates:
		var path := NavigationServer2D.map_get_path(
			navigation_map,
			start_position,
			candidate,
			true,
			navigation_agent.navigation_layers
		)
		if (
			not path.is_empty()
			and path[path.size() - 1].distance_to(candidate)
			<= NAVIGATION_PATH_ENDPOINT_TOLERANCE
		):
			navigation_candidates.append(candidate)

	for padding in [AREA_COLLISION_PADDING, Vector2.ZERO]:
		var best_candidate: Vector2
		var best_distance_squared := INF
		var found_candidate := false
		for candidate in navigation_candidates:
			if not _is_separated_from_assigned_positions(
				candidate,
				assigned_positions,
				padding
			):
				continue

			var distance_squared := candidate.distance_squared_to(preferred_position)
			if distance_squared < best_distance_squared:
				best_candidate = candidate
				best_distance_squared = distance_squared
				found_candidate = true

		if found_candidate:
			return [best_candidate]

	return []


func _is_separated_from_assigned_positions(
	position: Vector2,
	assigned_positions: Array[Vector2],
	padding: Vector2
) -> bool:
	var minimum_separation := Vector2(20.0, 32.0) + padding
	for assigned_position in assigned_positions:
		var offset := position - assigned_position
		if (
			absf(offset.x) < minimum_separation.x
			and absf(offset.y) < minimum_separation.y
		):
			return false
	return true


func _get_player_unit(collider: Object) -> Node:
	if not collider is Node:
		return null

	var candidate := collider as Node
	while candidate != null and not candidate.is_in_group("player_units"):
		candidate = candidate.get_parent()
	return candidate


func _apply_selection(selected_units: Array[Node]) -> void:
	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit.has_method("set_selected"):
			unit.call("set_selected", selected_units.has(unit))


func _on_resident_converted(resident: Node) -> void:
	if not is_instance_valid(resident) or not villagers.has(resident):
		return

	var resident_id := resident.get_instance_id()
	if converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id):
		return

	converted_resident_ids[resident_id] = true
	_refresh_mission_progress()

	var new_zombie := ZOMBIE_SCENE.instantiate()
	new_zombie.position = to_local(resident.global_position)
	add_child(new_zombie)
	new_zombie.get_node("Polygon2D").color = resident.get_node("Polygon2D").color
	resident.queue_free()


func _on_resident_died(resident: Node) -> void:
	if not is_instance_valid(resident) or not villagers.has(resident):
		return

	var resident_id := resident.get_instance_id()
	if converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id):
		return

	dead_resident_ids[resident_id] = true
	_refresh_mission_progress()


func _refresh_mission_progress() -> void:
	infected_residents = converted_resident_ids.size()
	killed_residents = dead_resident_ids.size()
	var completed_residents := infected_residents + killed_residents

	var unaccounted_residents := total_residents - completed_residents
	var progress_percent := 0
	var required_residents := 0
	if total_residents > 0:
		progress_percent = roundi(float(completed_residents * 100) / total_residents)
		required_residents = ceili(float(total_residents * TARGET_PERCENT) / 100.0)

	residents_label.text = "Заражено/убито: %d / %d" % [completed_residents, total_residents]
	infected_label.text = "Заражено: %d" % infected_residents
	killed_label.text = "Убито: %d" % killed_residents
	uninfected_label.text = "Осталось: %d" % unaccounted_residents
	progress_label.text = "Прогресс: %d%%" % progress_percent

	if total_residents == 0:
		status_label.text = "Цель невозможна: жителей нет."
	elif mission_state == MissionState.WON:
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	elif completed_residents >= required_residents:
		mission_state = MissionState.WON
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	else:
		status_label.text = "Цель: заразить или уничтожить %d%% жителей (%d осталось)" % [
			TARGET_PERCENT,
			maxi(required_residents - completed_residents, 0)
		]
