extends Node2D

const AUDIO = preload("res://scripts/audio/audio_manager.gd")

signal mission_finished(outcome: String, summary: Dictionary)
signal pause_requested

const TARGET_PERCENT := 80
const SELECTION_DRAG_THRESHOLD := 8.0
const PLAYER_SELECTION_LAYER := 4
const CATALOG = preload("res://scripts/mission_catalog.gd")
const GROUP_PLACEMENT = preload("res://scripts/group_placement.gd")
const MISSION_HUD = preload("res://scripts/mission_hud.gd")
const ZOMBIE_INFECTION = preload("res://scripts/zombie_infection.gd")
const ZOMBIE_PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE_MISSION_BUILD = preload("res://scripts/zombie_mission_build.gd")
const ZOMBIE_HORDE_COMMANDS = preload("res://scripts/zombie_horde_commands.gd")
const PEASANT_CONVERSION_VISUAL = preload("res://scripts/peasant_conversion_visual.gd")
var placement = GROUP_PLACEMENT.new()
var mission_hud: Control

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/zombie.tscn")
const VILLAGER_SCENE: PackedScene = preload("res://scenes/villager.tscn")
const PRIEST_GUARD_SCENE: PackedScene = preload("res://scenes/priest_guard.tscn")
const GUARD_PATROL = preload("res://scripts/guard_patrol.gd")
const UNIT_BALANCE = preload("res://scripts/mission_one_unit_balance.gd")
const PRIEST_ROUTINE = preload("res://scripts/priest_routine.gd")
const PRIEST_GUARD_ROUTES = preload("res://scripts/priest_guard_routes.gd")
@export var unit_balance_v03 := false
@export var zombie_infection_enabled := false
@export var dark_fantasy_hud := false
@export var monster_roster_enabled := false
@export var monster_command_hotkeys := false
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
var developer_vision := false
var developer_spawn := ""
var _developer_build: ZOMBIE_MISSION_BUILD
@export var building_rules := BuildingRules.new()
var buildings: Array[InteractiveBuilding] = []
var reinforcement_units: Array[Node] = []
var _guard_variants: Array[StringName] = []
var _guard_variant_rng := RandomNumberGenerator.new()
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
var _pending_resident_conversions: Dictionary = {}
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


@onready var _audio := AUDIO.service() as AUDIO
@onready var residents_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Residents
@onready var infected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Infected
@onready var killed_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Killed
@onready var uninfected_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Uninfected
@onready var progress_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Progress
@onready var status_label: Label = $CanvasLayer/MissionPanel/MissionInfo/Status
@onready var selection_rect: Panel = $CanvasLayer/SelectionRect
@onready var mission_audio = get_node_or_null("MissionAudio")


func configure_progression(profile: ZOMBIE_PROGRESSION) -> void:
	progression = profile
	mission_build = _make_ability_runtime(profile.state)
	for unit in find_children("*", "CharacterBody2D", true, false):
		if unit.is_in_group("player_units"):
			mission_build.prepare_zombie(unit, false)


func _make_ability_runtime(build: Dictionary) -> ZOMBIE_MISSION_BUILD:
	var standard := ZOMBIE_SCENE.instantiate()
	var width: float = standard.get_node("CollisionShape2D").shape.size.x
	standard.free()
	return ZOMBIE_MISSION_BUILD.new(build, width, unit_balance_v03)


func ability_runtime() -> ZOMBIE_MISSION_BUILD:
	return mission_build if mission_build != null else _developer_build


func _configure_resident_balance(resident: Node) -> void:
	if not unit_balance_v03:
		return
	if resident.get_meta("village_role", "") == "guard" and resident.guard_variant.is_empty():
		if _guard_variants.is_empty():
			_guard_variants.assign(UNIT_BALANCE.GUARD_VARIANTS.keys())
			for i in range(_guard_variants.size() - 1, 0, -1):
				var swap := _guard_variant_rng.randi_range(0, i)
				var variant := _guard_variants[i]
				_guard_variants[i] = _guard_variants[swap]
				_guard_variants[swap] = variant
		resident.guard_variant = _guard_variants.pop_back()
	resident.configure_mission_balance()


func _enter_tree() -> void:
	if not unit_balance_v03:
		return
	for unit in find_children("*", "CharacterBody2D", true, false):
		if unit.has_method("configure_mission_balance"):
			_configure_resident_balance(unit)
		elif mission_build == null and unit.is_in_group("player_units"):
			ZOMBIE_MISSION_BUILD.apply_form(unit, unit.zombie_form, true)


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
		var last_stand := get_node_or_null("LastStand")
		if last_stand != null:
			last_stand.initialize(self, defense)
		if mission_audio != null:
			mission_audio.initialize(self)
	_refresh_mission_progress()
	mission_hud = MISSION_HUD.new()
	$CanvasLayer.add_child(mission_hud)
	if $Camera2D.use_zoom_bindings:
		$Camera2D.zoom_pointer_over_ui = mission_hud.is_pointer_over_ui
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
	for resident in combat_residents():
		if not is_instance_valid(resident) or not resident.is_alive() or is_instance_valid(resident.interior_building):
			continue
		if resident.contains_visual_point(world_position):
			if zombie_infection.infect(resident):
				mission_hud.refresh_infection()
			return
	var building := _building_at(world_position)
	if building != null and zombie_infection.infect_occupant(building):
		mission_hud.refresh_infection()


func toggle_hunger_targeting() -> void:
	toggle_racial_targeting(ZOMBIE_PROGRESSION.HUNGER)


func toggle_racial_targeting(id: String) -> void:
	var runtime := ability_runtime()
	if menu_paused or not is_gameplay_active() or runtime == null or runtime.uses_for(id) == 0:
		return
	var activate := not runtime.targeting or runtime.active_ability != id
	cancel_infection_targeting()
	cancel_selection()
	cancel_order_preview()
	developer_spawn = ""
	mission_hud.refresh_developer_tool()
	runtime.active_ability = id
	runtime.targeting = activate
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()


func cancel_hunger_targeting() -> bool:
	var runtime := ability_runtime()
	if runtime == null or not runtime.targeting:
		return false
	runtime.targeting = false
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()
	return true


func toggle_tactical_pause() -> void:
	var runtime := ability_runtime()
	if menu_paused or runtime == null or not is_gameplay_active():
		return
	tactical_pause = not tactical_pause
	if not tactical_pause:
		runtime.execute_queue(self)
	_update_pause_state()


func set_menu_paused(active: bool) -> void:
	menu_paused = active
	if active:
		mission_hud.close_audio_debug()
	_update_pause_state()


func _update_pause_state() -> void:
	# Keep the world pausable and let only the camera and HUD process on tactical pause.
	var controls_mode := Node.PROCESS_MODE_ALWAYS if tactical_pause and not menu_paused else Node.PROCESS_MODE_INHERIT
	$Camera2D.process_mode = controls_mode
	mission_hud.process_mode = controls_mode
	get_tree().paused = tactical_pause or menu_paused
	if mission_audio != null:
		_audio.set_simulation_paused(get_tree().paused)
	mission_hud.refresh_metaprogression()
	command_overlay.queue_redraw()


func _handle_hunger_input(event: InputEvent) -> bool:
	var runtime := ability_runtime()
	if runtime == null or menu_paused or not is_gameplay_active():
		return false
	for index in runtime.build.slots.size():
		var id: String = runtime.build.slots[index]
		if id.is_empty():
			continue
		var action := "ability_slot_%d" % (index + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action, false, true):
			toggle_racial_targeting(id)
			return true
	if not runtime.targeting:
		return false
	if event is InputEventMouseMotion:
		command_overlay.queue_redraw()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return cancel_hunger_targeting()
		if event.button_index == MOUSE_BUTTON_LEFT and not mission_hud.is_pointer_over_ui(event.position):
			runtime.confirm(_screen_to_world(event.position), tactical_pause, self)
			mission_hud.refresh_metaprogression()
			command_overlay.queue_redraw()
			return true
	return false


func set_developer_mode(enabled: bool) -> void:
	developer_mode = enabled
	if not enabled:
		developer_spawn = ""
		set_developer_vision(false)
		var runtime := ability_runtime()
		if runtime != null:
			runtime.clear_developer_abilities()
		if _developer_build != null:
			_developer_build = null
			if tactical_pause:
				tactical_pause = false
				_update_pause_state()
		command_overlay.queue_redraw()
	if is_instance_valid(mission_hud): mission_hud.set_developer_mode(enabled)


func set_developer_vision(enabled: bool) -> void:
	developer_vision = enabled and developer_mode and get_meta("directional_unit_vision", false)
	command_overlay.queue_redraw()


func developer_add_ability(race: String, id: String) -> bool:
	if not developer_mode or menu_paused or not is_gameplay_active() or not CATALOG.RACES.has(race):
		return false
	if not id in CATALOG.RACES[race].active_perks:
		return false
	if ability_runtime() == null:
		_developer_build = _make_ability_runtime(ZOMBIE_PROGRESSION._fresh_state())
	if not ability_runtime().add_developer_ability(id):
		return false
	mission_hud.refresh_metaprogression()
	return true


func developer_restore_charges() -> void:
	if not developer_mode or menu_paused or not is_gameplay_active():
		return
	var runtime := ability_runtime()
	if runtime != null:
		runtime.restore_charges()
	if zombie_infection != null:
		zombie_infection.restore_charges()
		mission_hud.refresh_infection()
	mission_hud.refresh_metaprogression()


func developer_place(kind: String, world_position: Vector2) -> bool:
	if not developer_mode or menu_paused or not is_gameplay_active(): return false
	var navigation_map := get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(navigation_map) == 0: return false
	var position_on_map := NavigationServer2D.map_get_closest_point(navigation_map, world_position)
	if position_on_map.distance_to(world_position) > 24.0: return false
	for building in buildings:
		if building.contains(position_on_map): return false
	if CATALOG.ZOMBIE_TYPES.has(kind):
		var zombie := ZOMBIE_SCENE.instantiate()
		zombie.position = to_local(position_on_map)
		ZOMBIE_MISSION_BUILD.apply_form(zombie, "" if kind == "zombie" else kind, unit_balance_v03)
		add_child(zombie)
		if horde_commands != null:
			horde_commands.inherit(zombie)
		mission_hud.refresh_units()
		return true
	if not CATALOG.HUMAN_TYPES.has(kind):
		return false
	_developer_place_human(kind, position_on_map)
	return true


func _developer_place_human(kind: String, point: Vector2) -> void:
	var resident := (PRIEST_GUARD_SCENE if kind == "priest_guard" else VILLAGER_SCENE).instantiate()
	resident.set_meta("village_role", kind)
	resident.points_of_interest_path = NodePath("../VillagePointsOfInterest")
	if kind == "priest_guard":
		_setup_developer_priest_guard(resident, point)
	else:
		_setup_developer_resident(resident, kind)
	resident.position = to_local(point)
	resident.immediate_combat_conversion = zombie_infection_enabled
	_configure_resident_balance(resident)
	add_child(resident, true)
	villagers.append(resident)
	resident.converted.connect(_on_resident_converted)
	resident.died.connect(_on_resident_died)
	total_residents += 1
	var added_residents: Array[Node] = [resident]
	$VillageAlert.initialize(added_residents)
	$VillageDefense.register_resident(resident)
	_refresh_mission_progress()


func _setup_developer_resident(resident: Node, kind: String) -> void:
	match kind:
		"peasant":
			resident.civilian_profile = "Peasant"
			resident.get_node("Polygon2D").color = Color("#b7ad87")
		"artisan":
			resident.civilian_profile = "Craftsman"
			resident.get_node("Polygon2D").color = Color("#583e22")
			var site := "SmithYard" if has_node("VillagePointsOfInterest/SmithYard") else "WorkshopApproach"
			resident.work_point_path = NodePath("../VillagePointsOfInterest/" + site)
		"guard":
			resident.home_point_path = NodePath("../VillagePointsOfInterest/GuardYard")
			resident.get_node("Polygon2D").color = Color("#4aa4c5")
			var patrol := GUARD_PATROL.new()
			patrol.name = "GuardPatrol"
			patrol.route_path = NodePath("../../GuardPatrolRoutes/WestCircuit")
			patrol.post_access_path = NodePath("../../GuardPatrolRoutes/PostAccess")
			patrol.post_zone_path = NodePath("../../ActivityZones/HomeGuardPost")
			patrol.post_center_path = NodePath("../../NavigationRegion2D/Buildings/Public/GuardPost")
			resident.add_child(patrol)
		"priest":
			resident.get_node("Polygon2D").color = Color("#f1efeb")
			if not has_node("ActivityZones/HomeChapel"):
				return
			resident.home_point_path = NodePath("../VillagePointsOfInterest/Church")
			var routine := PRIEST_ROUTINE.new()
			routine.name = "PriestRoutine"
			routine.chapel_zone_paths = [NodePath("../../ActivityZones/HomeChapel"), NodePath("../../ActivityZones/WorkChurch"),
				NodePath("../../ActivityZones/SocialChurch"), NodePath("../../ActivityZones/WalkChurch")]
			routine.cemetery_zone_paths = [NodePath("../../ActivityZones/WorkCemetery"), NodePath("../../ActivityZones/WalkCemetery")]
			routine.public_zone_paths = [NodePath("../../ActivityZones/SocialSquare")]
			var zones: Array[NodePath] = [
				NodePath("../ActivityZones/HomeChapel"), NodePath("../ActivityZones/WorkChurch"),
				NodePath("../ActivityZones/SocialChurch"), NodePath("../ActivityZones/WalkChurch"),
				NodePath("../ActivityZones/WorkCemetery"), NodePath("../ActivityZones/WalkCemetery"),
				NodePath("../ActivityZones/SocialSquare")]
			resident.activity_zone_paths = zones
			resident.marker_activity_fallback_enabled = false
			resident.add_child(routine)


func _setup_developer_priest_guard(resident: Node, point: Vector2) -> void:
	if not unit_balance_v03:
		resident.max_health = 150.0
		resident.attack_damage = 20.0
	resident.home_point_path = NodePath("../VillagePointsOfInterest/Church")
	var zones: Array[NodePath] = [NodePath("../ActivityZones/SocialChurch")]
	resident.activity_zone_paths = zones
	var controller := resident.get_node("PriestGuard")
	var closest := INF
	for candidate in villagers:
		if not is_instance_valid(candidate) or not candidate.is_alive() or candidate.get_meta("village_role", "") != "priest":
			continue
		var distance: float = point.distance_squared_to(candidate.global_position)
		if distance < closest:
			closest = distance
			controller.priest_path = NodePath("../../" + str(get_path_to(candidate)))
	var church := get_node_or_null("VillagePointsOfInterest/Church") as Node2D
	controller.church_position = church.global_position if church != null else point
	if church != null:
		controller.patrol_points = PRIEST_GUARD_ROUTES.route_for(self, controller.slot)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and monster_command_hotkeys and not menu_paused and is_gameplay_active():
		if mission_hud.handle_command_hotkey(event):
			get_viewport().set_input_as_handled()
			return
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
			if event.pressed:
				var placed := developer_place(developer_spawn, _screen_to_world(event.position))
				mission_hud.refresh_developer_tool(not placed)
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
	var runtime := ability_runtime()
	if developer_vision or (runtime != null and runtime.targeting):
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
	if mission_audio != null:
		mission_audio.shutdown()
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
	if not is_instance_valid(resident) or not resident.is_converted():
		return
	var original := villagers.has(resident)
	if not original and not reinforcement_units.has(resident):
		return
	var resident_id := resident.get_instance_id()
	if (converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id)
		or _pending_resident_conversions.has(resident_id)):
		return

	var form := mission_build.roll_conversion_form() if mission_build != null else ""
	var peasant := resident.get_node_or_null("PeasantVisual") as PEASANT_CONVERSION_VISUAL.PEASANT
	var plays_conversion: bool = (
		form.is_empty() and peasant != null and get_meta(&"peasant_conversion_sprites", false))
	var spawn_position: Vector2 = resident.global_position
	if is_instance_valid(resident.building_task):
		spawn_position = resident.building_task.prepare_resident_conversion(resident, plays_conversion)
	if plays_conversion:
		var clip := PEASANT_CONVERSION_VISUAL.new()
		clip.name = "PeasantConversionVisual"
		clip.appearance = PEASANT_CONVERSION_VISUAL.ZOMBIE_ART.random_appearance()
		clip.faces_west = peasant.vision_direction() > 4
		clip.position = resident.to_local(spawn_position)
		_pending_resident_conversions[resident_id] = true
		resident.set_physics_process(false)
		clip.finished.connect(_spawn_converted_resident.bind(
			resident, spawn_position, form, clip.appearance, clip.idle_direction()), CONNECT_ONE_SHOT)
		resident.add_child(clip)
		return
	_spawn_converted_resident(resident, spawn_position, form)


func _spawn_converted_resident(resident: Node, spawn_position: Vector2, form: String,
	appearance := -1, idle_direction := -1) -> void:
	var resident_id := resident.get_instance_id()
	_pending_resident_conversions.erase(resident_id)
	converted_resident_ids[resident_id] = true
	if not villagers.has(resident):
		reinforcement_units.erase(resident)
	var new_zombie := ZOMBIE_SCENE.instantiate()
	new_zombie.position = to_local(spawn_position)
	new_zombie.ordinary_appearance = appearance
	new_zombie.conversion_idle_direction = idle_direction
	if mission_build != null:
		mission_build.prepare_zombie(new_zombie, true, form)
	elif unit_balance_v03:
		ZOMBIE_MISSION_BUILD.apply_form(new_zombie, "", true)
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
	if not is_instance_valid(resident):
		return
	var original := villagers.has(resident)
	if not original and not reinforcement_units.has(resident):
		return
	var resident_id := resident.get_instance_id()
	if converted_resident_ids.has(resident_id) or dead_resident_ids.has(resident_id):
		return

	dead_resident_ids[resident_id] = true
	if not original:
		reinforcement_units.erase(resident)
	if zombie_infection != null and resident.killed_by_player_monster:
		zombie_infection.record_non_converting_kill()
		mission_hud.refresh_infection()
	_refresh_mission_progress()


func primary_objective_completed() -> bool:
	return mission_state == MissionState.WON


func combat_residents() -> Array[Node]:
	return villagers + reinforcement_units


func spawn_reinforcement_wave(variants: Array[StringName], positions: PackedVector2Array, squad: Node) -> Array[Node2D]:
	var arrived: Array[Node2D] = []
	for i in variants.size():
		arrived.append(_spawn_reinforcement(variants[i], positions[i], squad))
	total_residents += arrived.size()
	_refresh_mission_progress()
	return arrived


func _spawn_reinforcement(variant: StringName, point: Vector2, squad: Node) -> Node2D:
	var soldier := VILLAGER_SCENE.instantiate()
	soldier.name = "Guard"
	soldier.set_meta("village_role", "guard")
	soldier.guard_variant = variant
	soldier.position = to_local(point)
	soldier.defense = $VillageDefense
	soldier.reinforcement_squad = squad
	soldier.immediate_combat_conversion = zombie_infection_enabled
	_configure_resident_balance(soldier)
	add_child(soldier, true)
	soldier.remove_from_group("civilian_warning_receivers")
	var guard := preload("res://scripts/guard_ai.gd").new()
	guard.name = "GuardAI"
	soldier.add_child(guard)
	soldier.guard_ai = guard
	soldier.converted.connect(_on_resident_converted)
	soldier.died.connect(_on_resident_died)
	reinforcement_units.append(soldier)
	return soldier


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


func _owned_zombies() -> Array[Node]:
	var result: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if is_ancestor_of(unit) and not unit.is_queued_for_deletion() and unit.is_alive():
			result.append(unit)
	return result


func _command_targets(center: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for resident in combat_residents():
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
	if developer_vision:
		_draw_vision_group(&"activity_zone_residents", Color(0.3, 0.95, 0.36, 0.57))
		_draw_vision_group(&"player_units", Color(1.0, 0.24, 0.22, 0.7))
	var runtime := ability_runtime()
	if runtime != null:
		for index in runtime.queued_points.size():
			var point: Vector2 = runtime.queued_points[index]
			command_overlay.draw_circle(command_overlay.to_local(point), runtime.radius_for(runtime.queued_abilities[index]), Color("d2a76350"))
		if runtime.targeting and not menu_paused:
			command_overlay.draw_circle(command_overlay.get_local_mouse_position(), runtime.radius_for(runtime.active_ability), Color("d2a76340"))
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


func _draw_vision_group(group: StringName, color: Color) -> void:
	for actor in get_tree().get_nodes_in_group(group):
		if is_ancestor_of(actor) and actor.is_alive() and actor.is_visible_in_tree() and actor.unit_vision != null:
			actor.unit_vision.draw_outline(command_overlay, color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		consume_assault_cancel_release = false
		cancel_order_preview()
