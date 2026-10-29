extends Node2D

const TARGET_PERCENT := 80
const SELECTION_DRAG_THRESHOLD := 8.0
const PLAYER_SELECTION_LAYER := 4
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
