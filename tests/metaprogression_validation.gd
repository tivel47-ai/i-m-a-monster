# Godot --headless --path . --script res://tests/metaprogression_validation.gd --fixed-fps 60
extends SceneTree

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const BUILD = preload("res://scripts/zombie_mission_build.gd")
const MAIN = preload("res://scenes/main.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const FLESH := PROGRESSION.FLESH
const BRUTE := PROGRESSION.BRUTE
const HUNGER := PROGRESSION.HUNGER

var save_path := "user://metaprogression_validation_%s.cfg" % OS.get_process_id()
var app: Node
var mission: Node2D
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func initial_branches(values: PackedFloat32Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func _open_app() -> void:
	app = MAIN.instantiate()
	app.set_meta("progression_path", save_path)
	root.add_child(app)


func _enter_mission() -> void:
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._update_preview()
	app._start_mission()
	mission = app.mission
	for resident in mission.villagers:
		resident.set_physics_process(false)


func _spawn_zombie(point: Vector2) -> Node2D:
	var zombie := ZOMBIE.instantiate() as CharacterBody2D
	zombie.position = mission.to_local(point)
	mission.mission_build.prepare_zombie(zombie, false)
	mission.add_child(zombie)
	zombie.set_physics_process(false)
	return zombie


func _living_peasants() -> Array:
	return mission.villagers.filter(func(resident):
		return is_instance_valid(resident) and resident.is_alive() and resident.get_meta("village_role", "") == "peasant")


func _strike(resident: Node2D, zombie: Node2D, damage: float, chance: float) -> void:
	resident.begin_encounter(Color.GREEN, zombie)
	resident.receive_zombie_attack(damage, chance, zombie)


func _leave() -> void:
	app._pause()
	app._show(app.Screen.CONFIRM_LEAVE)
	app._leave_mission()


func run() -> void:
	root.size = Vector2i(1280, 720)
	_open_app()
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._update_preview()
	check(app.development_button.disabled, "Fresh profile keeps development locked until the first Virus")
	app._open_development()
	app.development.open(app.progression, app.settings.keys, false, app.settings.camera_speed)
	check(app.screen == app.Screen.RACES and not app.development.tree.upgrades_visible()
		and app.development.nodes.values().all(func(node): return not node.visible and node.tooltip_text.is_empty())
		and not app.progression.state.reveal_seen, "Before Virus, fog hides every purchasable node and its input")
	app.development.request_exit()
	app.developer_mode = true
	app._update_preview()
	app._open_development()
	check(app.screen == app.Screen.DEVELOPMENT and not app.development.tree.upgrades_visible()
		and app.development.nodes.values().all(func(node): return not node.visible and node.tooltip_text.is_empty())
		and not app.progression.state.initial_unlocked and not app.progression.state.reveal_seen,
		"Developer mode opens the editor with ordinary discovery rules and no persistent unlock changes")
	var editor = app.development
	await process_frame
	check(root.gui_get_focus_owner() == editor.back_button,
		"Opening development focuses Back instead of highlighting a tree node")
	check(editor.developer_controls.visible and editor.subtract_virus_button.disabled,
		"Developer balance controls are visible and cannot subtract from zero")
	editor.developer_controls.get_child(1).pressed.emit()
	editor._purchase(FLESH)
	editor.subtract_virus_button.pressed.emit()
	check(editor.draft.build.virus == 0 and PROGRESSION.level(editor.draft.build, FLESH) == 1
		and editor.draft.build.initial_unlocked and not app.progression.state.initial_unlocked,
		"Developer credit enables purchases in the draft and debit clamps to zero")
	editor.request_exit()
	editor.leave_dialog.get_ok_button().pressed.emit()
	check(app.screen == app.Screen.RACES and app.progression.state.virus == 0
		and not app.progression.state.initial_unlocked, "Exiting discards developer credits and purchases")
	app.developer_mode = false
	await _first_run()
	await _edit_build()
	await _exercise_mission_build()
	await _check_reopen_and_refunds()
	_check_legacy_profile()
	_check_progress_reset()
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(save_path)
	print("Metaprogression: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _finish_conversion_clip(resident: Node) -> void:
	var clip := resident.get_node_or_null("PeasantConversionVisual")
	if clip != null:
		clip._physics_process(clip.DURATION)


func _first_run() -> void:
	_enter_mission()
	check(app.progression.state.virus == 0 and not app.progression.state.initial_unlocked,
		"Purchasable development remains locked on mission launch with a fresh profile")
	check(mission.zombie_infection.charges == 3 and mission.mission_hud.ability_slots.size() == 10
		and mission.mission_build.available_uses == 0, "Only the dedicated core ability starts usable")
	var hidden = app.progression.begin_edit()
	hidden.build.virus = 100
	hidden.purchase(FLESH)
	check(PROGRESSION.level(hidden.build, FLESH) == 0, "Hidden node cannot be purchased")
	var actors := _living_peasants()
	var direct: Node2D = actors[0]
	var natural: Node2D = actors[1]
	var zombie := _spawn_zombie(Vector2(170, 900))
	mission.zombie_infection.infect(direct)
	_strike(direct, zombie, 1000.0, 1.0)
	check(direct.is_converted() and app.progression.state.virus == 0 and not app.progression.state.initial_unlocked,
		"Direct Infection remains ineligible for both Virus and development")
	_strike(natural, zombie, 1.0, 1.0)
	check(app.progression.state.virus == 0 and not natural.is_converted(), "Combat infection alone awards nothing")
	natural._on_transformation_timer_timeout()
	mission._on_resident_converted(natural)
	natural._on_transformation_timer_timeout()
	check(app.progression.state.virus == 0, "Virus is deferred until the conversion clip finishes")
	_finish_conversion_clip(natural)
	check(app.progression.state.virus == 1 and mission.mission_build.virus_earned == 1
		and mission.mission_hud.virus_label.text == "Вирус: 1", "Completed conversion awards once and updates HUD immediately")
	check(get_nodes_in_group("player_units").all(func(unit): return not unit.is_brute), "No Brute before purchase")
	_leave()
	check(app.screen == app.Screen.ATTEMPT_SUMMARY and "за попытку: 1" in app.attempt_text.text
		and "Открыты улучшения" in app.attempt_text.text and app.progression.state.initial_unlocked,
		"First Virus reveals the upgrades before victory and voluntary exit reports it")
	check(PROGRESSION.new(save_path).state.virus == 1, "Conversion credit is already on disk")
	await process_frame
	_enter_mission()
	actors = _living_peasants()
	zombie = _spawn_zombie(Vector2(170, 900))
	_strike(actors[0], zombie, 1000.0, 1.0)
	check(actors[0].is_converted() and app.progression.state.virus == 1,
		"Lethal combat infection starts conversion at once on a replay")
	_finish_conversion_clip(actors[0])
	check(app.progression.state.virus == 2, "Lethal combat infection awards Virus after the clip")
	for resident in mission.villagers:
		if mission.mission_state != mission.MissionState.WON and resident.is_alive():
			resident.take_damage(1000.0)
	app._pause()
	app._finish_mission()
	await process_frame
	check(app.screen == app.Screen.RESULTS and app.progression.state.initial_unlocked
		and "Открыты улучшения" not in app.result_text.text and "Всего Вируса: 2" in app.result_text.text
		and app.progression.state.virus == 2, "Victory displays Virus without another unlock or reward")
	app._dispose_mission()
	app._show(app.Screen.RACES)


func _edit_build() -> void:
	app.progression.state.virus = 100
	app._open_development()
	var editor = app.development
	check(editor.nodes.size() == 10 and not editor.tree.upgrades_visible() and app.progression.state.reveal_seen,
		"First visit after Virus starts the one-time fog animation")
	await create_timer(1.4).timeout
	check(editor.tree.upgrades_visible() and editor.nodes.values().filter(func(node): return node.visible).size() == 2,
		"Initial discovery exposes only the two entry nodes")
	await _tree_camera_and_growth()
	check(not editor.draft.purchase_block(BRUTE).is_empty(), "Missing Flesh II is reported")
	editor._purchase(BRUTE)
	editor._purchase(FLESH)
	editor._purchase(FLESH)
	editor._purchase(BRUTE)
	check(editor.draft.build.virus == 51 and PROGRESSION.level(editor.draft.build, BRUTE) == 1
		and PROGRESSION.level(app.progression.state, BRUTE) == 0, "Pending Flesh II allows pending Brute at 49 total Virus")
	for i in 3:
		editor._purchase(HUNGER)
	check(editor.draft.build.virus == 21 and PROGRESSION.level(editor.draft.build, HUNGER) == 2,
		"Level prices and insufficient Virus are enforced")
	editor.slots[1]._drop_data(Vector2.ZERO, {"editor": editor, "id": HUNGER, "index": -1})
	editor.slots[2]._drop_data(Vector2.ZERO, {"editor": editor, "id": HUNGER, "index": 1})
	check(editor.draft.build.slots[1].is_empty() and editor.draft.build.slots[2] == HUNGER,
		"Hotbar move creates one assignment and preserves other slots")
	editor.request_exit()
	check(editor.leave_dialog.visible and editor.leave_dialog.ok_button_text == "Выйти"
		and editor.leave_dialog.cancel_button_text == "Остаться" and not editor.developer_controls.visible,
		"Normal editing shows the two exit choices without developer controls")
	editor.leave_dialog.get_cancel_button().pressed.emit()
	check(app.screen == app.Screen.DEVELOPMENT and editor.draft.build.virus == 21,
		"Staying leaves the current draft intact")
	editor.request_exit()
	editor.leave_dialog.get_ok_button().pressed.emit()
	check(app.screen == app.Screen.RACES and app.progression.state.virus == 100,
		"Exit without saving discards the provisional changes")
	app._open_development()
	check(editor.tree.upgrades_visible() and initial_branches(editor.tree.branch_growth) == Vector3.ZERO,
		"A second visit skips the first reveal and discards unapplied fog growth")
	for id in [FLESH, FLESH, BRUTE, HUNGER, HUNGER, HUNGER]:
		if id == HUNGER and PROGRESSION.level(editor.draft.build, HUNGER) == 2:
			# Fixture funds for a third tactical use.
			editor.draft.build.virus += 50
		editor._purchase(id)
	await process_frame
	await process_frame
	check(editor.tree.branch_growth[0] > 0.0 and editor.tree.branch_growth[1] > 0.0 and editor.tree.branch_growth[2] > 0.0,
		"First purchases grow their connections toward the nodes")
	var learned: Button = editor.learned.get_child(0)
	var slot: Button = editor.slots[2]
	var tree_rect: Rect2 = editor.tree.get_global_rect()
	var upgrades_panel := editor.upgrades.get_parent().get_parent().get_parent() as PanelContainer
	var learned_panel := editor.learned.get_parent().get_parent().get_parent() as PanelContainer
	var hotbar := slot.get_parent().get_parent() as PanelContainer
	var reset_rect: Rect2 = editor.reset_button.get_global_rect()
	check(tree_rect == editor.get_global_rect()
		and tree_rect.encloses(upgrades_panel.get_global_rect())
		and tree_rect.encloses(learned_panel.get_global_rect())
		and tree_rect.encloses(hotbar.get_global_rect())
		and upgrades_panel.get_global_rect().end.x < learned_panel.get_global_rect().position.x
		and reset_rect.end.y < upgrades_panel.get_global_rect().position.y
		and is_equal_approx(reset_rect.get_center().x, tree_rect.get_center().x)
		and is_equal_approx(hotbar.get_global_rect().get_center().y, editor.back_button.get_global_rect().get_center().y),
		"The reset is centered above the tree and the hotbar sits between the footer buttons")
	var upgrades_top := upgrades_panel.get_global_rect().position.y
	check(upgrades_top < tree_rect.position.y + tree_rect.size.y / 3.0
		and is_equal_approx(upgrades_top, learned_panel.get_global_rect().position.y)
		and slot.size.is_equal_approx(Vector2(46, 52)),
		"The sidebars start higher together and the slots use the compact size (%s)" % slot.size)
	var blank := tree_rect.get_center() + Vector2(0, 145)
	var hover_targets := {upgrades_panel: editor.upgrades.get_child(0), learned_panel: learned, hotbar: slot}
	_mouse_motion(blank, Vector2.ZERO, false)
	await create_timer(0.03).timeout
	for panel: PanelContainer in hover_targets:
		var idle := panel.get_theme_stylebox("panel") as StyleBoxFlat
		var target: Control = hover_targets[panel]
		_mouse_motion(target.get_global_rect().get_center(), Vector2.ZERO, false)
		await create_timer(0.03).timeout
		var hover := panel.get_theme_stylebox("panel") as StyleBoxFlat
		_mouse_motion(blank, Vector2.ZERO, false)
		await create_timer(0.03).timeout
		check(idle.bg_color.a < hover.bg_color.a and panel.get_theme_stylebox("panel") == idle,
			"Overlay brightens over a child and becomes translucent when the pointer leaves")
	var emblem: Texture2D = learned.icon
	check(editor.upgrades.get_child_count() == 3 and slot.icon == null and emblem != null
		and emblem == PROGRESSION.NODES[HUNGER].icon and editor.nodes[HUNGER].icon == emblem,
		"The learned ability uses the same independent symbol as its tree node")
	_drag(learned.get_global_rect().get_center(), slot.get_global_rect().get_center())
	check(editor.draft.build.slots[2] == HUNGER and slot.icon == emblem,
		"A GUI drag from learned abilities assigns its icon to the hovered slot")
	_drag(slot.get_global_rect().get_center(), blank)
	check(editor.draft.build.slots[2].is_empty() and PROGRESSION.level(editor.draft.build, HUNGER) == 3,
		"A GUI drag to empty space unassigns without unlearning")
	await process_frame
	learned = editor.learned.get_child(0)
	_drag(learned.get_global_rect().get_center(), slot.get_global_rect().get_center())
	editor._apply()
	editor.request_exit()
	var saved = PROGRESSION.new(save_path)
	check(app.screen == app.Screen.RACES and saved.state.virus == 36 and saved.state.slots[2] == HUNGER
		and PROGRESSION.level(saved.state, BRUTE) == 1, "Apply persists balance, form, levels and assignments together")


func _tree_camera_and_growth() -> void:
	var editor = app.development
	var tree = editor.tree
	var flesh: Button = editor.nodes[FLESH]
	var center_before: Vector2 = tree._view_center
	var sidebar_before: Rect2 = editor.upgrades.get_global_rect()
	var hotspot := flesh.get_global_rect().get_center()
	check(editor.nodes.values().filter(func(node): return node.visible).all(func(node): return node.text.is_empty() and not node.tooltip_text.is_empty())
		and "8 Вируса" in flesh.tooltip_text and editor.nodes[BRUTE].tooltip_text.is_empty(),
		"Entry nodes have descriptive tooltips; distant Brute has no tooltip")
	var tooltip_style := editor.theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	var tooltip_offset: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/tooltip_position_offset")
	check(editor.theme.get_font_size("font_size", "TooltipLabel") == DARK_THEME.HINT_SIZE
		and tooltip_style.bg_color.a < 1.0 and tooltip_offset.y >= 40.0,
		"Development tooltips use compact text, translucent panels and a cursor-sized offset")
	check(tree._frames[FLESH].modulate.a > tree._frames[BRUTE].modulate.a
		and tree._frames[BRUTE].modulate.a > 0.0
		and tree._buttons[FLESH].self_modulate.a == 0.0 and tree._buttons[BRUTE].self_modulate.a == 0.0,
		"Available and distant perks have distinct silhouettes without lit emblems")
	check(initial_branches(tree.branch_growth) == Vector3.ZERO and tree.active_branch_count() == 0,
		"Revealed perks start with no grown branches")
	_mouse_motion(hotspot, Vector2.ZERO, false)
	_mouse_button(hotspot, true, MOUSE_BUTTON_WHEEL_UP)
	_mouse_button(hotspot, false, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(tree.zoom, 1.15) and tree._view_center == center_before,
		"Wheel over a perk zooms around the center of the tree")
	_mouse_button(sidebar_before.get_center(), true, MOUSE_BUTTON_WHEEL_UP)
	_mouse_button(sidebar_before.get_center(), false, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(tree.zoom, 1.15), "Wheel over a sidebar leaves the tree zoom alone")
	_key_event(KEY_A, true)
	await create_timer(0.08).timeout
	_key_event(KEY_A, false)
	check(tree._view_center.x < center_before.x and tree._view_center.y == center_before.y
		and editor.upgrades.get_global_rect() == sidebar_before,
		"Physical A pans the tree without moving the sidebar")
	_click_control(flesh)
	check(PROGRESSION.level(editor.draft.build, FLESH) == 1,
		"The transformed perk remains clickable after pan and zoom")
	await create_timer(0.26).timeout
	var segments: int = tree.active_branch_count()
	check(tree.branch_growth[0] > 0.0 and tree.branch_growth[0] < 1.0 and segments > 0
		and tree.branch_growth[1] == 0.0 and tree.branch_growth[2] == 0.0,
		"Only the purchased branch grows from its starting point")
	await create_timer(0.68).timeout
	check(initial_branches(tree.branch_growth) == Vector3(1.0, 0.0, 0.0), "The branch reaches its perk")
	_click_control(flesh, MOUSE_BUTTON_RIGHT)
	await create_timer(0.92).timeout
	check(initial_branches(tree.branch_growth) == Vector3.ZERO and editor.draft.build.virus == 100
		and tree.active_branch_count() == 0,
		"Right click after zoom refunds the level and retracts its whole branch")
	var canvas_center: Vector2 = tree.get_global_rect().get_center()
	for i in 15:
		_mouse_button(canvas_center, true, MOUSE_BUTTON_WHEEL_UP)
		_mouse_button(canvas_center, false, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(tree.zoom, 2.5), "Wheel up stops at the maximum tree zoom")
	for i in 15:
		_mouse_button(canvas_center, true, MOUSE_BUTTON_WHEEL_DOWN)
		_mouse_button(canvas_center, false, MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(tree.zoom, 0.55) and tree._view_center == center_before,
		"Wheel down stops at the wider view and centers the tree when it fits")
	_click_control(flesh)
	check(PROGRESSION.level(editor.draft.build, FLESH) == 1,
		"Nodes remain clickable at minimum zoom")
	_click_control(flesh, MOUSE_BUTTON_RIGHT)


func _exercise_mission_build() -> void:
	_enter_mission()
	var runtime = mission.mission_build
	var camera := mission.get_node("Camera2D") as Camera2D
	camera.global_position = Vector2(230, 900)
	camera.force_update_scroll()
	await process_frame
	var hud = mission.mission_hud
	check(not hud.infection_button.get_global_rect().intersects(hud.ability_slots[0].get_global_rect()),
		"The core ability and optional slots occupy separate space")
	var hunger_button: Button = hud.ability_slots[2]
	check(hunger_button.icon != null and hunger_button.icon == app.development.slots[2].icon
		and hunger_button.text.is_empty() and hud.hunger_slot_key.text == "3" and hud.hunger_slot_uses.text == "3"
		and "Зов голода" in hunger_button.tooltip_text and hud.ability_slots[0].icon == null,
		"The assigned HUD slot reuses the development icon and shows only the binding and remaining uses")
	var ordinary := _spawn_zombie(Vector2(230, 900))
	var form_seed := 0
	for i in 128:
		seed(i)
		if randf() < 0.10:
			form_seed = i
			break
	var actors := _living_peasants()
	var direct: Node2D = actors[6]
	direct.global_position = Vector2(235, 900)
	mission.zombie_infection.infect(direct)
	var existing := get_nodes_in_group("player_units")
	seed(form_seed)
	direct.take_damage(1000.0)
	mission._on_resident_converted(direct)
	var born := get_nodes_in_group("player_units").filter(func(unit): return unit not in existing)
	check(born.size() == 1 and born[0].is_brute, "Direct infection rolls Brute once in the real conversion callback")
	var brute: Node2D = born[0]
	brute.set_physics_process(false)
	var combat: Node2D = actors[7]
	combat.global_position = Vector2(550, 900)
	_strike(combat, ordinary, 1.0, 1.0)
	existing = get_nodes_in_group("player_units")
	seed(form_seed)
	combat._on_transformation_timer_timeout()
	born = get_nodes_in_group("player_units").filter(func(unit): return unit not in existing)
	check(born.size() == 1 and born[0].is_brute, "The same conversion roll gives the same form for combat infection")
	check(is_instance_valid(brute) and brute.is_brute and is_equal_approx(brute.current_health, 396.0)
		and is_equal_approx(brute.move_speed, 38.0) and brute.attack_damage == 42.0
		and brute.attack_interval == 2.4 and brute.infection_chance == 0.02
		and is_equal_approx(ordinary.current_health, 198.0), "Converted Brute and ordinary zombie get form-specific stats and additive Flesh II")
	check(runtime.available_uses == 3 and runtime.hunger_slot == 2
		and is_equal_approx(runtime.hunger_radius, 3.6 * 7.8), "Mission reads the committed slot, rank and world-space radius")
	_click_control(hud.infection_button)
	_key(KEY_SPACE)
	check(paused and mission.tactical_pause and mission.zombie_infection.targeting,
		"Space pauses after an orb click without activating or toggling the orb")
	var start_position := camera.global_position
	var start_zoom := camera.zoom.x
	_key_event(KEY_D, true)
	for i in 6:
		await process_frame
	_key_event(KEY_D, false)
	_mouse_button(Vector2(640, 360), true, MOUSE_BUTTON_WHEEL_UP)
	check(camera.global_position.x > start_position.x and camera.zoom.x > start_zoom,
		"The camera pans and zooms during tactical pause")
	var paused_target: Node2D = actors[8]
	paused_target.global_position = Vector2(370, 900)
	var charges: int = mission.zombie_infection.charges
	_click_world(paused_target.global_position)
	check(mission.zombie_infection.charges == charges - 1 and paused_target.player_infection_timer != null,
		"A map click can apply Infection during tactical pause")
	_key(KEY_F)
	var unit_position := ordinary.global_position
	var destination := Vector2(320, 900)
	var order_screen := root.get_canvas_transform() * destination
	ordinary.set_physics_process(true)
	_mouse_button(order_screen, true, MOUSE_BUTTON_RIGHT)
	for i in 5:
		await process_frame
	check(mission.command_active and mission.command_radius > mission.command_initial_radius,
		"Holding RMB expands the order circle during tactical pause")
	_mouse_button(order_screen, false, MOUSE_BUTTON_RIGHT)
	check(mission.horde_commands.order == mission.horde_commands.Order.MOVE and ordinary.has_target,
		"RMB assigns a movement destination during tactical pause")
	for i in 5:
		await physics_frame
	check(ordinary.global_position == unit_position and not ordinary.can_process()
		and paused_target.player_infection_timer.time_left == 10.0,
		"Tactical pause freezes unit movement and the newly started Infection timer")
	_click_control(hud.global_cancel_button)
	check(mission.horde_commands.order == mission.horde_commands.Order.NONE,
		"The HUD can cancel an assigned order during tactical pause")
	ordinary.set_physics_process(false)
	_click_world(paused_target.global_position, MOUSE_BUTTON_RIGHT)
	check(mission.horde_commands.order == mission.horde_commands.Order.ATTACK and paused_target in ordinary.priority_targets,
		"RMB on a resident assigns a priority attack during tactical pause")
	_click_control(hud.global_cancel_button)
	_click_control(hud.building_button)
	var house_position := Vector2(500, 810)
	var house: InteractiveBuilding = mission._building_at(house_position)
	_click_world(house_position, MOUSE_BUTTON_RIGHT)
	check(house.attackers.size() == 1 and not mission.choosing_building,
		"The HUD and RMB can assign a building assault during tactical pause")
	var assaulter: Node2D = house.attackers.keys().front()
	var before_crossing := assaulter.global_position
	assaulter.global_position = house.layout.to_global(house.layout.entrance)
	house._crossing = assaulter
	house._crossing_started = true
	var threshold_position := assaulter.global_position
	_click_world(destination, MOUSE_BUTTON_RIGHT)
	check(assaulter.global_position == threshold_position and house._vacating.has(assaulter),
		"An order canceling a crossing defers the doorway displacement until the world resumes")
	assaulter.global_position = before_crossing
	_click_control(hud.global_cancel_button)
	_key(KEY_3)
	_click_world(ordinary.global_position)
	_click_world(Vector2(350, 900))
	check(paused and runtime.queued_points.size() == 2 and runtime.available_uses == 1
		and ordinary.hunger_timer == null and hud.hunger_slot_uses.text == "1",
		"Two paused clicks reserve two uses and leave targets unbuffed")
	_key(KEY_ESCAPE)
	check(not runtime.targeting and runtime.queued_points.size() == 2, "Esc cancels only unfinished targeting")
	_key(KEY_3)
	_click_control(mission.mission_hud.infection_button)
	check(mission.zombie_infection.targeting and not runtime.targeting and runtime.queued_points.size() == 2,
		"Switching to Infection in the HUD preserves previously reserved uses")
	_click_control(hud.ability_slots[2])
	check(runtime.targeting, "An optional ability slot can start targeting during tactical pause")
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE)
	check(app.screen == app.Screen.PAUSE and not camera.can_process() and not hud.can_process(),
		"The Esc menu blocks both camera input and mission HUD during tactical pause")
	_key(KEY_ESCAPE)
	_click_control(hud.ability_slots[2])
	check(paused and runtime.queued_points.size() == 2, "Leaving the Esc menu preserves the tactical pause")
	_key(KEY_SPACE)
	check(not paused and runtime.targeting and runtime.available_uses == 1 and runtime.queued_points.is_empty()
		and is_equal_approx(ordinary.movement_speed(), 74.82) and is_equal_approx(brute.movement_speed(), 49.02),
		"Resume executes both reservations without another debit and keeps unfinished targeting")
	ordinary.speed_modifiers["test_slow"] = -0.20
	check(is_equal_approx(ordinary.movement_speed(), 63.22), "Independent speed modifiers add")
	var late := _spawn_zombie(Vector2(230, 900))
	check(late.hunger_timer == null, "Late arrival gains no aura")
	ordinary.global_position = Vector2(255, 900)
	check(ordinary.hunger_timer.time_left > 0.0, "Leaving the radius keeps the individual buff")
	Engine.time_scale = 0.5
	var remaining: float = ordinary.hunger_timer.time_left
	for i in 60:
		await process_frame
	check(absf(remaining - ordinary.hunger_timer.time_left - 0.5) < 0.04, "Half speed consumes half a second of duration in 60 ticks")
	Engine.time_scale = 1.0
	mission.toggle_tactical_pause()
	remaining = ordinary.hunger_timer.time_left
	for i in 5:
		await process_frame
	check(remaining == ordinary.hunger_timer.time_left, "Tactical pause freezes buff timers")
	mission.toggle_tactical_pause()
	_click_world(ordinary.global_position)
	check(runtime.available_uses == 0 and not runtime.targeting and is_equal_approx(ordinary.hunger_timer.time_left, 12.0)
		and is_equal_approx(ordinary.movement_speed(), 63.22), "Running cast refreshes duration without stacking and spends final use")
	check(hunger_button.disabled and hunger_button.icon != null and hud.hunger_slot_uses.text == "0",
		"The icon stays visible and the slot becomes inactive after the last use")
	await _check_brute_hit(brute)
	var balance: int = app.progression.state.virus
	app._pause()
	app._restart_mission()
	mission = app.mission
	check(mission.mission_build.available_uses == 3 and mission.mission_build.virus_earned == 0
		and app.progression.state.virus == balance and Engine.time_scale == 1.0, "Restart restores uses and preserves the balance")
	_leave()
	await process_frame


func _check_brute_hit(brute: Node2D) -> void:
	var actors := _living_peasants()
	var primary: Node2D = actors[0]
	var splash_a: Node2D = actors[1]
	var splash_b: Node2D = actors[2]
	var outside: Node2D = actors[3]
	brute.global_position = Vector2(410, 900)
	primary.global_position = Vector2(422, 900)
	splash_a.global_position = Vector2(422, 910)
	splash_b.global_position = Vector2(422, 890)
	outside.global_position = Vector2(422, 928)
	for actor in [primary, splash_a, splash_b, outside]:
		actor.current_health = 100.0
	brute.infection_chance = 0.0
	primary.begin_encounter(Color.GREEN, brute)
	brute._brute_hit(primary)
	check(primary.current_health == 58.0 and is_equal_approx(splash_a.current_health, 83.2)
		and is_equal_approx(splash_b.current_health, 83.2) and outside.current_health == 100.0, "Primary and multiple splash targets receive their own damage exactly once")
	check(primary.global_position.x > 422.0 and splash_a.global_position == Vector2(422, 910)
		and splash_b.global_position == Vector2(422, 890), "Only the primary target is knocked back")
	var wall := StaticBody2D.new()
	wall.position = mission.to_local(Vector2(428.0, 900.0))
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1.0, 6.0)
	collider.shape = shape
	wall.add_child(collider)
	mission.add_child(wall)
	primary.global_position = Vector2(422, 900)
	await physics_frame
	await physics_frame
	brute._brute_hit(primary)
	check(primary.global_position.x < 424.0, "Knockback stops against a physical wall")
	wall.queue_free()
	await process_frame
	brute.infection_chance = 1.0
	primary.current_health = 1.0
	var before: int = app.progression.state.virus
	primary.global_position = Vector2(422, 900)
	splash_a.global_position = Vector2(422, 910)
	splash_b.global_position = Vector2(422, 890)
	brute._brute_hit(primary)
	_finish_conversion_clip(primary)
	check(primary.is_converted() and splash_a.infected_by_player_zombie and splash_b.infected_by_player_zombie
		and app.progression.state.virus == before + 1, "Brute shares infection and lethal-conversion accounting with standard attacks")


func _check_reopen_and_refunds() -> void:
	var stored: int = app.progression.state.virus
	app.queue_free()
	await process_frame
	_open_app()
	check(app.progression.state.virus == stored and app.progression.state.slots[2] == HUNGER,
		"Reopening application scene reloads the profile")
	var profile = app.progression
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._update_preview()
	app._open_development()
	await process_frame
	await process_frame
	var editor = app.development
	var draft = editor.draft
	check(initial_branches(editor.tree.branch_growth) == Vector3.ONE and is_equal_approx(editor.tree.zoom, 1.0),
		"Reopening restores purchased branches at the full-tree zoom")
	check(editor.reset_button.text == "Сбросить развитие" and not editor.tree.is_ancestor_of(editor.reset_button),
		"The development screen has a single reset outside the moving tree")
	_click_control(editor.nodes[FLESH], MOUSE_BUTTON_RIGHT)
	check(PROGRESSION.level(draft.build, FLESH) == 1 and PROGRESSION.level(draft.build, BRUTE) == 0
		and draft.build.virus == stored + 41, "RMB refunds one Flesh level and cascades the Brute refund")
	editor.request_exit()
	editor.leave_dialog.get_ok_button().pressed.emit()
	app._open_development()
	draft = editor.draft
	_click_control(editor.reset_button)
	check(not draft.changed(), "A short click leaves the development build intact")
	editor.reset_button.grab_focus()
	_key(KEY_ENTER)
	editor._process(2.0)
	check(not draft.changed(), "Keyboard activation does not bypass the LMB hold")
	var reset_position: Vector2 = editor.reset_button.get_global_rect().get_center()
	_mouse_motion(reset_position, Vector2.ZERO, false)
	_mouse_button(reset_position, true)
	editor._process(1.9)
	check(not draft.changed() and editor.reset_fill.value > 0.0,
		"The development reset fills while held and waits for two seconds")
	_mouse_button(reset_position, false)
	editor._process(2.0)
	check(not draft.changed() and editor.reset_fill.value == 0.0,
		"Releasing LMB early cancels the development reset")
	_mouse_button(reset_position, true)
	_mouse_motion(reset_position + Vector2(0, 100), Vector2(0, 100), true)
	editor._process(2.0)
	check(not draft.changed() and editor.reset_fill.value == 0.0,
		"Leaving the development reset button cancels the hold")
	_mouse_button(reset_position + Vector2(0, 100), false)
	_mouse_motion(reset_position, Vector2.ZERO, false)
	_mouse_button(reset_position, true)
	editor.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	editor._process(2.0)
	check(not draft.changed() and editor.reset_fill.value == 0.0,
		"Losing application focus cancels the development reset")
	_mouse_button(reset_position, false)
	_mouse_button(reset_position, true)
	editor.hide()
	editor.show()
	editor._process(2.0)
	check(not draft.changed() and editor.reset_fill.value == 0.0,
		"Hiding development cancels the hold before the screen reopens")
	_mouse_button(reset_position, false)
	_mouse_motion(reset_position, Vector2.ZERO, false)
	_mouse_button(reset_position, true)
	editor._process(2.0)
	_mouse_button(reset_position, false)
	editor._process(2.0)
	check(draft.build.virus == stored + 114 and draft.build.initial_unlocked and draft.build.slots[2].is_empty(),
		"A full hold returns original costs once, clears assignments and preserves reveal")
	await create_timer(0.25).timeout
	var growth := initial_branches(editor.tree.branch_growth)
	check(growth.y > 0.0 and growth.y < 1.0 and growth.x == 1.0 and growth.z < 1.0,
		"Brute and the independent Hunger branch retract while the route to Flesh holds")
	await create_timer(0.75).timeout
	growth = initial_branches(editor.tree.branch_growth)
	check(growth.y == 0.0 and growth.x > 0.0 and growth.x < 1.0 and growth.z == 0.0,
		"The route from Flesh to the core retracts after its Brute branch is gone")
	await create_timer(0.85).timeout
	check(initial_branches(editor.tree.branch_growth) == Vector3.ZERO
		and editor.tree.active_branch_count() == 0,
		"Once the ordered retreat ends all grown branches are gone")
	check(profile.apply(draft) == OK and PROGRESSION.new(save_path).state == profile.state,
		"Refunded build and earned balance reload exactly")
	draft = profile.begin_edit()
	draft.build.virus = 1000000000
	for id in [FLESH, HUNGER]:
		for cost in PROGRESSION.NODES[id].costs:
			draft.purchase(id)
	check(draft.build.virus == 1000000000 - 162 - 200 and profile.apply(draft) == OK,
		"All prices sum correctly and high Virus balances persist without a gameplay cap")


func _check_progress_reset() -> void:
	app._show(app.Screen.MAIN)
	app.developer_mode = true
	app.attempt_text.text = "previous attempt"
	app.result_text.text = "previous result"
	var settings = app.settings
	var earlier = app.progression.begin_edit()
	app._open_progress_reset()
	var dialog: AcceptDialog = app.progress_reset_dialog
	var confirm: Button = app.progress_reset_confirm
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	confirm.gui_input.emit(event)
	app._process(1.9)
	check(dialog.visible and app.progress_reset_fill.value > 0.0
		and app.progression.state == earlier.original, "The fill advances without resetting before two seconds")
	event.pressed = false
	confirm.gui_input.emit(event)
	app._process(2.0)
	check(dialog.visible and app.progress_reset_fill.value == 0.0 and app.progression.state == earlier.original,
		"Releasing early cancels the hold")
	event.pressed = true
	confirm.gui_input.emit(event)
	confirm.mouse_exited.emit()
	app._process(2.0)
	check(dialog.visible and app.progression.state == earlier.original, "Leaving the button cancels the hold")
	dialog.get_ok_button().pressed.emit()
	check(not dialog.visible and app.progression.state == earlier.original, "Cancel leaves the profile intact")
	app._open_progress_reset()
	confirm.gui_input.emit(event)
	app._process(2.0)
	var fresh := PROGRESSION.new(save_path).state
	check(not dialog.visible and fresh == app.progression.state and fresh.virus == 0 and fresh.paid.is_empty()
		and fresh.slots == PROGRESSION.empty_slots() and not fresh.initial_unlocked and not fresh.reveal_seen
		and app.progression.apply(earlier) == ERR_BUSY, "A full hold persists a fresh profile and invalidates old drafts")
	check(app.selected_mission.is_empty() and app.selected_race.is_empty() and not app.developer_mode
		and app.attempt_text.text.is_empty() and app.result_text.text.is_empty() and app.settings == settings,
		"A full reset clears session progress and preserves separate game settings")


func _check_legacy_profile() -> void:
	var legacy_path := save_path + ".legacy"
	var config := ConfigFile.new()
	config.set_value("zombies", "version", 1)
	config.set_value("zombies", "profile", {
		"virus": 2, "paid": {}, "slots": PROGRESSION.empty_slots(),
		"first_victory": false, "reveal_seen": false,
	})
	var written := config.save(legacy_path)
	var migrated := PROGRESSION.new(legacy_path)
	migrated.flush()
	check(written == OK and migrated.state.initial_unlocked and migrated.state.virus == 2
		and PROGRESSION.new(legacy_path).state == migrated.state,
		"Legacy Virus earned before a victory opens the tree after migration")
	config.set_value("zombies", "profile", {
		"virus": 0, "paid": {FLESH: [8]}, "slots": PROGRESSION.empty_slots(),
		"first_victory": true, "reveal_seen": true,
	})
	written = config.save(legacy_path)
	migrated = PROGRESSION.new(legacy_path)
	check(written == OK and migrated.state.initial_unlocked and migrated.state.reveal_seen
		and PROGRESSION.level(migrated.state, FLESH) == 1,
		"Migration preserves purchased levels and prior reveal even with zero remaining Virus")
	DirAccess.remove_absolute(legacy_path)


func _key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key(code: Key) -> void:
	_key_event(code, true)
	_key_event(code, false)


func _click_world(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var position := root.get_canvas_transform() * point
	for pressed in [true, false]:
		_mouse_button(position, pressed, button)


func _click_control(control: Control, button := MOUSE_BUTTON_LEFT) -> void:
	var position := control.get_global_rect().get_center()
	_mouse_motion(position, Vector2.ZERO, false)
	for pressed in [true, false]:
		_mouse_button(position, pressed, button)


func _mouse_button(position: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.global_position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse_motion(from, Vector2.ZERO, false)
	_mouse_button(from, true)
	_mouse_motion(from + Vector2(15, 0), Vector2(15, 0), true)
	_mouse_motion(to, to - from - Vector2(15, 0), true)
	_mouse_button(to, false)


func _mouse_motion(position: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
