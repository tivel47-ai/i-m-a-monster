extends Node2D

const TARGET_PERCENT := 80
const SELECTION_DRAG_THRESHOLD := 8.0
const PLAYER_SELECTION_LAYER := 4

enum MissionState {
	ACTIVE,
	WON,
}

var villagers: Array[Node] = []
var total_residents: int = 0
var infected_residents: int = 0
var mission_state: MissionState = MissionState.ACTIVE
var selection_in_progress: bool = false
var marquee_active: bool = false
var selection_start_screen: Vector2
var selection_current_screen: Vector2

@onready var residents_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Residents
@onready var infected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Infected
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
			continue

		var error := resident.connect("converted", _on_resident_converted)
		if error != OK:
			push_error("Could not connect resident conversion signal: %s" % error_string(error))

	total_residents = villagers.size()
	_refresh_mission_progress()


func _input(event: InputEvent) -> void:
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
	if not villagers.has(resident):
		return

	_refresh_mission_progress()


func _refresh_mission_progress() -> void:
	infected_residents = 0
	for resident in villagers:
		if is_instance_valid(resident) and resident.call("is_converted"):
			infected_residents += 1

	var uninfected_residents := total_residents - infected_residents
	var progress_percent := 0
	var required_infections := 0
	if total_residents > 0:
		progress_percent = roundi(float(infected_residents * 100) / total_residents)
		required_infections = ceili(float(total_residents * TARGET_PERCENT) / 100.0)

	residents_label.text = "Жители: %d / %d" % [infected_residents, total_residents]
	infected_label.text = "Заражено: %d" % infected_residents
	uninfected_label.text = "Незаражено: %d" % uninfected_residents
	progress_label.text = "Прогресс: %d%%" % progress_percent

	if total_residents == 0:
		status_label.text = "Цель невозможна: жителей нет."
	elif mission_state == MissionState.WON:
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	elif infected_residents >= required_infections:
		mission_state = MissionState.WON
		status_label.text = "ПОБЕДА! Цель миссии выполнена"
	else:
		status_label.text = "Цель: заразить %d%% жителей (%d осталось)" % [
			TARGET_PERCENT,
			maxi(required_infections - infected_residents, 0)
		]
