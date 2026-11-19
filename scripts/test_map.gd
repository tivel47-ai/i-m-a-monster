extends Node2D

signal mission_finished(outcome: String, summary: Dictionary)
signal pause_requested

const TARGET_PERCENT := 80
const SELECTION_DRAG_THRESHOLD := 8.0
const PLAYER_SELECTION_LAYER := 4
const GROUP_PLACEMENT = preload("res://scripts/group_placement.gd")
const MISSION_HUD = preload("res://scripts/mission_hud.gd")
const ZOMBIE_INFECTION = preload("res://scripts/zombie_infection.gd")
const ZOMBIE_PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE_MISSION_BUILD = preload("res://scripts/zombie_mission_build.gd")
const ZOMBIE_HORDE_COMMANDS = preload("res://scripts/zombie_horde_commands.gd")
var placement = GROUP_PLACEMENT.new()
var mission_hud: Control

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")
const VILLAGER_SCENE: PackedScene = preload("res://scenes/villager.tscn")
const GUARD_PATROL = preload("res://scripts/guard_patrol.gd")
@export var developer_guard_spawn_enabled := false
@export var zombie_infection_enabled := false
@export var dark_fantasy_hud := false
@export var standalone_race_id := ""
@export var manual_victory_finish := false
@export_range(0.01, 5.0, 0.01, "or_greater") var assault_increment_seconds := 0.35
var horde_commands: ZOMBIE_HORDE_COMMANDS
var zombie_infection: ZOMBIE_INFECTION
var progression: ZOMBIE_PROGRESSION
var mission_build: ZOMBIE_MISSION_BUILD
var tactical_pause := false
var menu_paused := false
var developer_mode := false
var developer_spawn := ""
@export var building_rules := BuildingRules.new()
var buildings: Array[InteractiveBuilding] = []
var shelter_buildings: Dictionary = {}
var choosing_building := false
var consume_assault_cancel_release := false
var marked_command_targets: Dictionary = {}

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

@export var command_initial_radius: float = 24.0
@export var command_max_radius: float = 180.0
@export var command_growth_speed: float = 200.0
var command_overlay := Node2D.new()
var command_active := false
var command_radius := 24.0
var command_center := Vector2.ZERO
var command_screen_position := Vector2.ZERO


@onready var residents_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Residents
@onready var infected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Infected
@onready var killed_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Killed
@onready var uninfected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Uninfected
@onready var progress_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Progress
@onready var status_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Status
@onready var selection_rect: Panel = $CanvasLayer/SelectionRect


func configure_progression(profile: ZOMBIE_PROGRESSION) -> void:
	progression = profile
	var standard := ZOMBIE_SCENE.instantiate()
	var width: float = standard.get_node("CollisionShape2D").shape.size.x
	standard.free()
	mission_build = ZOMBIE_MISSION_BUILD.new(profile.state, width)
	for unit in find_children("*", "CharacterBody2D", true, false):
		if unit.is_in_group("player_units"):
			mission_build.prepare_zombie(unit, false)


func _ready() -> void:
	developer_mode = bool(get_meta("developer_mode", false))
	var race_id: String = get_meta("race_id", standalone_race_id)
	if race_id == "zombie":
		horde_commands = ZOMBIE_HORDE_COMMANDS.new(self)
		if zombie_infection_enabled:
			zombie_infection = ZOMBIE_INFECTION.new()
	add_child(command_overlay)
	command_overlay.z_index = 100
	command_overlay.draw.connect(_draw_command_overlay)
	add_child(placement)
	for resident in find_children("*", "", true, false):
		if not resident.has_method("is_converted"):
			continue
		villagers.append(resident)
		resident.immediate_combat_conversion = zombie_infection_enabled
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
	$VillageAlert.initialize(villagers)
	var defense = get_node_or_null("VillageDefense")
	if defense == null:
		defense = preload("res://scripts/village_defense.gd").new()
		defense.name = "VillageDefense"
		add_child(defense)
	defense.initialize(villagers, $VillageAlert)
	if not get_meta("baking_exterior_navigation", false):
		_setup_buildings()
	_refresh_mission_progress()
	mission_hud = MISSION_HUD.new()
	$CanvasLayer.add_child(mission_hud)
	$CanvasLayer/MissionPanel.hide()
	mission_hud.set_developer_mode(developer_mode)


func _setup_buildings() -> void:
	var markers := get_node_or_null("VillagePointsOfInterest")
	var region := get_node_or_null("NavigationRegion2D")
	if region == null or markers == null:
		return
	var test_homes := {"HouseNW": "ResidentialStreet", "HouseNE": "HomeNorthApproach",
		"HouseSE": "HomeSouthApproach"}
	var markers_by_building := {"Church": "Church", "GuardPost": "GuardYard", "Tavern": "Tavern",
		"Blacksmith": "SmithYard", "Carpenter": "Carpenter", "Weaver": "Weaver",
		"Storage": "Storage", "Barn": "Barn"}
	for child in region.find_children("*", "StaticBody2D", true, false):
		var body := child as StaticBody2D
		var door := body.get_node_or_null("Door") as Polygon2D
		var test_building := body.get_parent().name == &"Solids" and (
			str(body.name).begins_with("House") or body.name in [&"Workshop", &"Storage", &"Shed"])
		if door == null and not test_building:
			continue
		var marker_name: String = test_homes.get(body.name, "") if test_building else markers_by_building.get(body.name, "")
		if body.is_in_group("simulation_houses"):
			marker_name = "Home%d" % str(body.name).right(2).to_int()
		var marker := markers.get_node_or_null(NodePath(marker_name)) as Marker2D if not marker_name.is_empty() else null
		var hint := Vector2(0, 50)
		if door != null:
			hint = door.position + door.offset
		elif marker != null:
			hint = body.to_local(marker.global_position)
		var building := InteractiveBuilding.new()
		building.name = "InteractiveBuilding"
		body.add_child(building)
		if building.configure(self, building_rules, body, hint):
			buildings.append(building)
			if marker != null:
				shelter_buildings[marker] = building
		else:
			building.queue_free()
	var camera := get_node_or_null("Camera2D")
	if camera != null and camera.has_signal("zoom_changed"):
		camera.zoom_changed.connect(_on_building_zoom_changed)
		_on_building_zoom_changed(camera.zoom_fraction())


func _on_building_zoom_changed(fraction: float) -> void:
	for building in buildings:
		building.show_interior(fraction >= building_rules.reveal_at_zoom_fraction)


func emit_break_in_noise(building: InteractiveBuilding, origin: Vector2, approach: Vector2) -> void:
	for resident in villagers:
		if is_instance_valid(resident):
			resident.local_warning.hear_break_in(building.get_instance_id(), origin, approach)


func toggle_building_order() -> void:
	if choosing_building:
		cancel_order_preview()
	elif is_gameplay_active() and not buildings.is_empty() and (
		horde_commands != null or not _command_units().is_empty()
	):
		cancel_infection_targeting()
		cancel_hunger_targeting()
		cancel_selection()
		command_active = false
		developer_spawn = ""
		choosing_building = true
		if horde_commands != null:
			horde_commands.assault_feedback = ""
		mission_hud.refresh_developer_tool()
		mission_hud.refresh_units()


func cancel_order_preview() -> bool:
	if not command_active and not choosing_building:
		return false
	if choosing_building and horde_commands != null:
		horde_commands.assault_feedback = ""
	command_active = false
	choosing_building = false
	if horde_commands != null:
		horde_commands.reset_assault()
	command_overlay.queue_redraw()
	if is_instance_valid(mission_hud):
		mission_hud.refresh_units()
	return true


func _pick_assault_building(world_position: Vector2) -> void:
	var building := _building_at(world_position)
	if building == null:
		return
	for unit in _command_units():
		unit.issue_player_building_order(building)
	cancel_order_preview()


func cancel_global_order() -> void:
	if horde_commands == null or not is_gameplay_active():
		return
	if command_active:
		cancel_order_preview()
	horde_commands.cancel()
	mission_hud.refresh_commands()
	command_overlay.queue_redraw()


func _handle_horde_assault_input(event: InputEventMouseButton, over_ui: bool) -> bool:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and choosing_building and (horde_commands.assault_quantity > 0 or not over_ui):
			if horde_commands.assault_quantity > 0:
				horde_commands.reset_assault()
				mission_hud.refresh_commands()
				command_overlay.queue_redraw()
			else:
				cancel_order_preview()
			consume_assault_cancel_release = true
			return true
		if not event.pressed and consume_assault_cancel_release:
			consume_assault_cancel_release = false
			return true
		return not over_ui and choosing_building

	if event.button_index != MOUSE_BUTTON_RIGHT or not choosing_building:
		return false
	if event.pressed and not over_ui:
		var building := _building_at(_screen_to_world(event.position))
		if building != null:
			horde_commands.begin_assault(building)
	elif not event.pressed and horde_commands.assault_quantity > 0:
		if horde_commands.confirm_assault():
			choosing_building = false
	mission_hud.refresh_commands()
	command_overlay.queue_redraw()
	return true


func _building_at(world_position: Vector2) -> InteractiveBuilding:
	for building in buildings:
		if building.contains(world_position):
			return building
	return null


func toggle_infection_targeting() -> void:
	if menu_paused or zombie_infection == null or zombie_infection.charges == 0 or not is_gameplay_active():
		return
	if zombie_infection.targeting:
		cancel_infection_targeting()
		return
	cancel_selection()
	cancel_order_preview()
	cancel_hunger_targeting()
	developer_spawn = ""
	zombie_infection.targeting = true
	mission_hud.refresh_developer_tool()
	mission_hud.refresh_infection()


func cancel_infection_targeting() -> bool:
	if zombie_infection == null or not zombie_infection.targeting:
		return false
	zombie_infection.targeting = false
	mission_hud.refresh_infection()
	return true


func _infect_at(world_position: Vector2) -> void:
	if not is_gameplay_active() or not zombie_infection.targeting:
		return
	for resident in villagers:
		if not is_instance_valid(resident) or not resident.is_alive() or is_instance_valid(resident.interior_building):
			continue
		var visual: Polygon2D = resident.polygon
		if visual.is_visible_in_tree() and Geometry2D.is_point_in_polygon(visual.to_local(world_position) - visual.offset, visual.polygon):
			if zombie_infection.infect(resident):
				mission_hud.refresh_infection()
			return
	var building := _building_at(world_position)
	if building != null and zombie_infection.infect_occupant(building):
		mission_hud.refresh_infection()


func toggle_hunger_targeting() -> void:
	toggle_racial_targeting(ZOMBIE_PROGRESSION.HUNGER)


func toggle_racial_targeting(id: String) -> void:
	if menu_paused or not is_gameplay_active() or mission_build == null or mission_build.uses_for(id) == 0:
		return
	var activate := not mission_build.targeting or mission_build.active_ability != id
	cancel_infection_targeting()
	cancel_selection()
	cancel_order_preview()
	developer_spawn = ""
	mission_hud.refresh_developer_tool()
	mission_build.active_ability = id
	mission_build.targeting = activate
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()


func cancel_hunger_targeting() -> bool:
	if mission_build == null or not mission_build.targeting:
		return false
	mission_build.targeting = false
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()
	return true


func toggle_tactical_pause() -> void:
	if menu_paused or mission_build == null or not is_gameplay_active():
		return
	tactical_pause = not tactical_pause
	if not tactical_pause:
		mission_build.execute_queue(self)
	_update_pause_state()


func set_menu_paused(active: bool) -> void:
	menu_paused = active
	_update_pause_state()


func _update_pause_state() -> void:
	# Keep the world pausable and let only the camera and HUD process on tactical pause.
	var controls_mode := Node.PROCESS_MODE_ALWAYS if tactical_pause and not menu_paused else Node.PROCESS_MODE_INHERIT
	$Camera2D.process_mode = controls_mode
	mission_hud.process_mode = controls_mode
	get_tree().paused = tactical_pause or menu_paused
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()


func _handle_hunger_input(event: InputEvent) -> bool:
	if mission_build == null or menu_paused or not is_gameplay_active():
		return false
	for index in mission_build.build.slots.size():
		var id: String = mission_build.build.slots[index]
		if id.is_empty():
			continue
		var action := "ability_slot_%d" % (index + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action, false, true):
			toggle_racial_targeting(id)
			return true
	if not mission_build.targeting:
		return false
	if event is InputEventMouseMotion:
		command_overlay.queue_redraw()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return cancel_hunger_targeting()
		if event.button_index == MOUSE_BUTTON_LEFT and not mission_hud.is_pointer_over_ui(event.position):
			mission_build.confirm(_screen_to_world(event.position), tactical_pause, self)
			mission_hud.refresh_metaprogression()
			command_overlay.queue_redraw()
			return true
	return false


func set_developer_mode(enabled: bool) -> void:
	developer_mode = enabled
	if not enabled: developer_spawn = ""
	if is_instance_valid(mission_hud): mission_hud.set_developer_mode(enabled)

func developer_place(kind: String, world_position: Vector2) -> void:
	if not developer_mode or not is_gameplay_active(): return
	var navigation_map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0: return
	var position_on_map := NavigationServer2D.map_get_closest_point(navigation_map, world_position)
	if position_on_map.distance_to(world_position) > 24.0: return
	for building in buildings:
		if building.contains(position_on_map): return
	if kind == "zombie":
		var zombie := ZOMBIE_SCENE.instantiate()
		zombie.position = to_local(position_on_map)
		if mission_build != null:
			mission_build.prepare_zombie(zombie, false)
		add_child(zombie)
		if horde_commands != null:
			horde_commands.inherit(zombie)
	elif kind == "resident" or (kind == "guard" and developer_guard_spawn_enabled):
		var resident := VILLAGER_SCENE.instantiate()
		if kind == "guard":
			resident.name = "DeveloperGuard"
			resident.set_meta("village_role", "guard")
			resident.home_point_path = NodePath("../VillagePointsOfInterest/GuardYard")
			resident.get_node("Polygon2D").color = Color("#4aa4c5")
			var patrol := GUARD_PATROL.new()
			patrol.name = "GuardPatrol"
			patrol.route_path = NodePath("../../GuardPatrolRoutes/WestCircuit")
			patrol.post_access_path = NodePath("../../GuardPatrolRoutes/PostAccess")
			patrol.post_zone_path = NodePath("../../ActivityZones/HomeGuardPost")
			patrol.post_center_path = NodePath("../../NavigationRegion2D/Buildings/Public/GuardPost")
			resident.add_child(patrol)
		resident.position = to_local(position_on_map)
		resident.immediate_combat_conversion = zombie_infection_enabled
		add_child(resident)
		villagers.append(resident)
		resident.converted.connect(_on_resident_converted)
		resident.died.connect(_on_resident_died)
		total_residents += 1
		var added_residents: Array[Node] = [resident]
		$VillageAlert.initialize(added_residents)
		$VillageDefense.register_resident(resident)
		_refresh_mission_progress()


func _input(event: InputEvent) -> void:
	if _handle_hunger_input(event):
		get_viewport().set_input_as_handled()
		return
	if zombie_infection != null and InputMap.has_action("race_ability") and event.is_action_pressed("race_ability", false, true):
		toggle_infection_targeting()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if cancel_infection_targeting():
			get_viewport().set_input_as_handled()
			return
	var over_ui: bool = event is InputEventMouse and is_instance_valid(mission_hud) and mission_hud.is_pointer_over_ui(event.position)
	if horde_commands != null and event is InputEventMouseButton and _handle_horde_assault_input(event, over_ui):
		get_viewport().set_input_as_handled()
		return
	if over_ui:
		if selection_in_progress:
			_finish_selection(selection_current_screen)
		if horde_commands != null and command_active and event is InputEventMouseButton and (
			event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed
		):
			cancel_order_preview()
		return
	if zombie_infection != null and zombie_infection.targeting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_infect_at(_screen_to_world(event.position))
		get_viewport().set_input_as_handled()
		return
	if choosing_building and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pick_assault_building(_screen_to_world(event.position))
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_order_preview()
			get_viewport().set_input_as_handled()
			return
	if developer_mode and developer_spawn != "" and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: developer_place(developer_spawn, _screen_to_world(event.position))
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			developer_spawn = ""
			if is_instance_valid(mission_hud): mission_hud.refresh_developer_tool()
			get_viewport().set_input_as_handled()
			return
	if command_active and event is InputEventMouseMotion:
		command_screen_position = event.position
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if event.pressed:
			command_active = is_gameplay_active() and (
				horde_commands != null or not _command_units().is_empty())
			command_radius = command_initial_radius
			command_screen_position = event.position
			command_center = _screen_to_world(event.position)
		elif command_active:
			command_active = false
			_issue_command(_screen_to_world(event.position), command_radius)
		command_overlay.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and cancel_order_preview():
		get_viewport().set_input_as_handled()
		return

	if horde_commands != null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selection_in_progress = true
			marquee_active = false
			selection_start_screen = event.position
			selection_current_screen = event.position
			selection_rect.hide()
		elif selection_in_progress:
			_finish_selection(event.position)
	elif event is InputEventMouseMotion and selection_in_progress:
		selection_current_screen = event.position
		_update_marquee_state()

func _finish_selection(screen_position: Vector2) -> void:
	selection_current_screen = screen_position
	_update_marquee_state()
	var screen_to_world := get_viewport().get_canvas_transform().affine_inverse()
	if marquee_active:
		call_deferred("_select_units_in_marquee", selection_start_screen, selection_current_screen, screen_to_world)
	else:
		call_deferred("_select_unit_at_screen_position", selection_current_screen, screen_to_world)
	selection_in_progress = false
	marquee_active = false
	selection_rect.hide()


func cancel_selection() -> void:
	selection_in_progress = false
	marquee_active = false
	selection_rect.hide()


func _process(delta: float) -> void:
	if mission_build != null and mission_build.targeting:
		command_overlay.queue_redraw()
	if horde_commands != null and horde_commands.assault_quantity > 0:
		if horde_commands.update_assault(delta, maxf(assault_increment_seconds, 0.01)):
			mission_hud.refresh_commands()
		return
	if horde_commands != null and horde_commands.refresh_attack_order():
		mission_hud.refresh_commands()
	_update_command_preview(delta)
	if horde_commands == null and choosing_building and _command_units().is_empty():
		cancel_order_preview()


func is_gameplay_active() -> bool:
	return process_mode != Node.PROCESS_MODE_DISABLED and (
		mission_state == MissionState.ACTIVE or manual_victory_finish)


func can_finish_mission() -> bool:
	return manual_victory_finish and mission_state == MissionState.WON


func finish_mission() -> void:
	if not is_inside_tree() or mission_state != MissionState.WON:
		return
	mission_finished.emit("victory", {
		"total": total_residents, "infected": infected_residents, "killed": killed_residents,
	})


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


func _select_unit_at_screen_position(screen_position: Vector2, screen_to_world: Transform2D) -> void:
	if not can_process():
		return
	var query := PhysicsPointQueryParameters2D.new()
	query.position = screen_to_world * screen_position
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


func _select_units_in_marquee(start_screen: Vector2, end_screen: Vector2, screen_to_world: Transform2D) -> void:
	if not can_process():
		return
	var world_corners := PackedVector2Array([
		screen_to_world * start_screen,
		screen_to_world * Vector2(end_screen.x, start_screen.y),
		screen_to_world * end_screen,
		screen_to_world * Vector2(start_screen.x, end_screen.y),
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


func _issue_area_move_order(center: Vector2, radius: float = 100.0) -> void:
	var selected_units := _command_units()
	if horde_commands != null:
		horde_commands.issue_move(center, radius, selected_units)
		mission_hud.refresh_commands()
		return

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
	var candidates: Array[Vector2] = placement._get_area_position_candidates(
		center,
		navigation_map,
		selected_units, radius
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

		var preferred_position: Vector2 = placement._get_area_preferred_position(
			center,
			unit_index,
			selected_units.size(), radius
		)
		var destination: Array[Vector2] = placement._choose_area_position(
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


func _get_player_unit(collider: Object) -> Node:
	if not collider is Node:
		return null

	var candidate := collider as Node
	while candidate != null and not candidate.is_in_group("player_units"):
		candidate = candidate.get_parent()
	return candidate if candidate != null and is_ancestor_of(candidate) and candidate.can_receive_player_orders() else null


func _apply_selection(selected_units: Array[Node]) -> void:
	if horde_commands != null:
		return
	for unit in get_tree().get_nodes_in_group("player_units"):
		if is_ancestor_of(unit) and unit.has_method("set_selected"):
			unit.call("set_selected", selected_units.has(unit))
	if is_instance_valid(mission_hud):
		mission_hud.refresh_units()


func _on_resident_converted(resident: Node) -> void:
	if not is_instance_valid(resident) or not villagers.has(resident) or not resident.is_converted():
		return

	var resident_id := resident.get_instance_id()
	if converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id):
		return

	converted_resident_ids[resident_id] = true

	var spawn_position: Vector2 = resident.global_position
	if is_instance_valid(resident.building_task):
		spawn_position = resident.building_task.prepare_resident_conversion(resident)
	var new_zombie := ZOMBIE_SCENE.instantiate()
	new_zombie.position = to_local(spawn_position)
	if mission_build != null:
		mission_build.prepare_zombie(new_zombie, true)
	add_child(new_zombie)
	if resident.infection_source != resident.InfectionSource.PLAYER_ABILITY:
		new_zombie.get_node("Polygon2D").color = resident.get_node("Polygon2D").color
	if is_instance_valid(resident.interior_building):
		resident.interior_building.adopt_conversion(resident, new_zombie)
	elif horde_commands != null:
		horde_commands.inherit(new_zombie)
	resident.queue_free()
	if mission_build != null and resident.infected_by_player_zombie:
		mission_build.virus_earned += 1
		if progression.credit_conversion():
			mission_build.revealed_development = true
		mission_hud.refresh_metaprogression()
	_refresh_mission_progress()
	if is_instance_valid(mission_hud):
		mission_hud.refresh_units()


func _on_resident_died(resident: Node) -> void:
	if not is_instance_valid(resident) or not villagers.has(resident):
		return

	var resident_id := resident.get_instance_id()
	if converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id):
		return

	dead_resident_ids[resident_id] = true
	if zombie_infection != null and resident.killed_by_player_monster:
		zombie_infection.record_non_converting_kill()
		mission_hud.refresh_infection()
	_refresh_mission_progress()


func track_building_exit_clearance(zombie: Node) -> void:
	if horde_commands == null:
		return
	zombie.clearing_building_exit = true
	zombie.move_order_finished.connect(
		_on_building_exit_cleared.bind(zombie), CONNECT_ONE_SHOT | CONNECT_DEFERRED)


func _on_building_exit_cleared(_reached: bool, zombie: Node) -> void:
	if not is_instance_valid(zombie):
		return
	zombie.clearing_building_exit = false
	if is_gameplay_active():
		horde_commands.inherit(zombie)
	mission_hud.refresh_units()


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
		if manual_victory_finish:
			if is_instance_valid(mission_hud):
				mission_hud.show_victory_notice()
		else:
			finish_mission.call_deferred()
	else:
		status_label.text = "Цель: заразить или уничтожить %d%% жителей (%d осталось)" % [
			TARGET_PERCENT,
			maxi(required_residents - completed_residents, 0)
		]


func _command_units() -> Array[Node]:
	var units := _available_command_units()
	if horde_commands != null:
		return units
	return units.filter(func(unit): return unit.is_selected)


func _available_command_units() -> Array[Node]:
	var result: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if is_ancestor_of(unit) and not unit.is_queued_for_deletion() and unit.can_receive_player_orders():
			result.append(unit)
	return result


func _owned_zombie_count() -> int:
	var count := 0
	for unit in get_tree().get_nodes_in_group("player_units"):
		if is_ancestor_of(unit) and not unit.is_queued_for_deletion() and unit.is_alive():
			count += 1
	return count


func _command_targets(center: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for resident in villagers:
		if is_instance_valid(resident) and resident.is_alive() and not is_instance_valid(resident.interior_building) and resident.global_position.distance_to(center) <= radius:
			result.append(resident)
	return result

func _issue_command(center: Vector2, radius: float) -> void:
	var targets := _command_targets(center, radius)
	if targets.is_empty(): _issue_area_move_order(center, radius)
	else:
		var units := _command_units()
		if horde_commands != null:
			horde_commands.issue_attack(targets, units)
			mission_hud.refresh_commands()
		else:
			for i in range(units.size()):
				units[i].issue_player_attack_order(targets, i % targets.size())

func _update_command_preview(delta: float) -> void:
	if command_active:
		if horde_commands == null and _command_units().is_empty(): command_active = false
		else:
			command_center = _screen_to_world(command_screen_position)
			command_radius = minf(command_radius + command_growth_speed * delta, command_max_radius)
	command_overlay.queue_redraw()

func _draw_command_overlay() -> void:
	if mission_build != null:
		for index in mission_build.queued_points.size():
			var point: Vector2 = mission_build.queued_points[index]
			command_overlay.draw_circle(command_overlay.to_local(point), mission_build.radius_for(mission_build.queued_abilities[index]), Color("d2a76350"))
		if mission_build.targeting and not menu_paused:
			command_overlay.draw_circle(command_overlay.get_local_mouse_position(), mission_build.radius_for(mission_build.active_ability), Color("d2a76340"))
	if choosing_building:
		var building := horde_commands.assault_building if horde_commands != null else null
		if not is_instance_valid(building):
			building = _building_at(get_global_mouse_position())
		if is_instance_valid(building):
			var perimeter := PackedVector2Array()
			for vertex in building.layout.outline:
				perimeter.append(to_local(building.layout.to_global(vertex)))
			perimeter.append(perimeter[0])
			command_overlay.draw_polyline(perimeter, Color("ecbd7c"), 2.0, true)
	if command_active:
		var color := Color(0.2, 0.8, 1.0, 0.8) if _command_targets(command_center, command_radius).is_empty() else Color(1.0, 0.2, 0.2, 0.8)
		command_overlay.draw_circle(to_local(command_center), command_radius, Color(color, 0.12))
		command_overlay.draw_arc(to_local(command_center), command_radius, 0, TAU, 96, color, 2.0)
	if horde_commands == null or horde_commands.assault_quantity == 0:
		marked_command_targets.clear()
		if horde_commands == null or horde_commands.order == horde_commands.Order.ATTACK:
			for unit in get_tree().get_nodes_in_group("player_units"):
				if is_ancestor_of(unit) and not unit.is_dead:
					for target in unit.priority_targets:
						if is_instance_valid(target):
							marked_command_targets[target] = true
	for target in marked_command_targets:
		if is_instance_valid(target) and target.is_alive() and not is_instance_valid(target.interior_building):
			command_overlay.draw_circle(to_local(target.global_position + Vector2(0, -25)), 3.0, Color.RED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		consume_assault_cancel_release = false
		cancel_order_preview()
