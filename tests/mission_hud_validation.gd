# Godot --headless --path . --script tests/mission_hud_validation.gd
extends SceneTree

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE_PREVIEW = preload("res://scripts/zombie_race_preview.gd")

var failures := 0
var app: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func frames() -> void:
	await process_frame
	await physics_frame


func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app._show(app.Screen.MISSIONS)
	app._select_mission("village")
	app._open_race_selection()
	app._select_race("zombie")
	var race_labels: Array[Node] = app.race_preview.find_children("*", "Label", true, false)
	check(race_labels.any(func(label): return "всей орде" in label.text)
		and not race_labels.any(func(label): return "рамка" in label.text),
		"Zombie race screen describes horde movement without a selection hint")
	var preview := app.race_preview.find_children("*", "Sprite2D", true, false)[0] as ZOMBIE_PREVIEW
	var idle := preview.region_rect
	var start_x := preview.position.x
	preview._process(ZOMBIE_PREVIEW.IDLE_TIME + 0.4)
	var walk := preview.region_rect
	check(walk != idle and preview.position.x > start_x and get_nodes_in_group("player_units").is_empty(),
		"Race preview walks using the ordinary zombie atlas without spawning a unit")
	preview._process(ZOMBIE_PREVIEW.WALK_TIME - 0.4 + 0.16)
	check(preview.region_rect != walk and preview.region_rect != idle,
		"Race preview advances from walking to attack frames")
	preview._process(ZOMBIE_PREVIEW.PASS_TIME * 2.0 - preview._elapsed + 0.01)
	check(preview.region_rect == idle and is_equal_approx(preview.position.x, start_x),
		"Race preview loops back to the starting pose")
	app._start_mission()
	await frames()
	var first: Node = app.mission
	var hud: Control = first.mission_hud
	check(hud.monster_count.text == "Зомби × 3", "HUD counts living zombies")
	check("Цель:" in hud.objective_label.text and str(first.total_residents) in hud.objective_label.text, "HUD shows mission goal")
	var army_panel: Control = hud.monster_count.get_parent().get_parent()
	check(army_panel.get_global_rect().position.y > root.size.y * 0.8, "Monster list sits in the lower left")
	check("Спокойствие" in hud.alert_label.text, "HUD shows village stage")
	check(hud.monster_button == null and hud.global_cancel_button.disabled,
		"Zombie count is informational and cancellation starts disabled")
	first.pause_requested.emit()
	check(paused and app.screen == app.Screen.PAUSE, "HUD gear opens pause")
	var pause_page: Control = app.pages[app.Screen.PAUSE]
	for button in pause_page.find_children("*", "Button", true, false):
		if button.text == "Настройки": button.pressed.emit()
	check(app.screen == app.Screen.SETTINGS and paused, "Settings opens from pause")
	app._show(app.settings_return_screen)
	check(app.screen == app.Screen.PAUSE and paused, "Settings returns to pause")
	app._restart_mission()
	await frames()
	check(app.mission != first and not paused and app.screen == app.Screen.GAMEPLAY, "Restart creates fresh attempt")
	check(app.selected_mission == "village" and app.selected_race == "zombie", "Restart retains mission and race")
	check(app.mission.mission_hud.monster_count.text == "Зомби × 3"
		and app.mission.mission_hud.global_cancel_button.disabled, "Restart creates fresh HUD")
	await check_monster_roster()
	app.queue_free()
	await frames()
	print("Mission HUD validation failures: ", failures)
	quit(1 if failures else 0)


func check_monster_roster() -> void:
	app._dispose_mission()
	app._show(app.Screen.MISSIONS)
	app._select_mission("mission_1")
	app._open_race_selection()
	app._select_race("zombie")
	app._start_mission()
	await frames()
	var mission: Node = app.mission
	var hud: Control = mission.mission_hud
	var roster: VBoxContainer = hud.monster_count.get_parent()
	var panel: PanelContainer = roster.get_parent()
	var empty_rect := panel.get_global_rect()
	for form in PROGRESSION.FORMS:
		mission.mission_build.build.paid[form] = [PROGRESSION.NODES[form].costs[0]]
	hud.refresh_units()
	check(hud.monster_count.text == "Монстры: 0" and roster.get_child_count() == 1,
		"Unlocked forms stay hidden until the player acquires a unit")

	var residents: Array = mission.villagers.filter(func(unit): return unit.get_meta("village_role", "") == "peasant")
	var forms := ["", "", PROGRESSION.BRUTE, PROGRESSION.HOUND, PROGRESSION.CARRIER]
	if residents.size() < forms.size():
		check(false, "Mission has enough peasants to test all forms")
		return
	for index in forms.size():
		var resident: Node = residents[index]
		check(resident.apply_player_infection(10.0), "Resident receives the initial infection")
		check(hud.monster_count.text == "Монстры: %d" % index, "Pending conversion does not count")
		for value in 1000:
			seed(value)
			if PROGRESSION.choose_form(mission.mission_build.build, randf()) == forms[index]:
				seed(value)
				break
		resident.player_infection_timer.timeout.emit()
	var units: Array[Node] = mission._owned_zombies()
	check(units.size() == 5 and hud.monster_count.text == "Монстры: 5", "Conversions update the total")
	if units.is_empty():
		return
	var rows := {}
	for row in roster.get_children().slice(1):
		var name: String = row.get_child(1).text
		var icon: TextureRect = row.get_child(0)
		if name in ["Зомби", "Громила"]:
			var visual: Sprite2D = units[0].get_node("OrdinaryZombieVisual") if name == "Зомби" else units[2].get_node("BruteVisual")
			var portrait := icon.texture as AtlasTexture
			check(portrait != null and portrait.atlas == visual.texture and portrait.region.has_area(),
				"Sprite portrait reuses the mission unit's atlas: " + name)
		else:
			check(icon.texture == null and icon.draw.get_connections().size() == 1,
				"Creature without sprites draws a fallback icon: " + name)
		rows[name] = row.get_child(2).text
	check(rows == {"Зомби": "× 2", "Громила": "× 1", "Гончий": "× 1", "Носитель": "× 1"},
		"Roster groups living monsters by form")
	await frames()
	var full_rect := panel.get_global_rect()
	check(full_rect.position.y < empty_rect.position.y and is_equal_approx(full_rect.end.y, empty_rect.end.y)
		and full_rect.end.x < hud.infection_button.get_global_rect().position.x,
		"Full roster expands upwards and stays clear of Infection")
	var carrier: Node = units.back()
	carrier.interior_building = mission.buildings[0]
	mission.horde_commands.assault_quantity = 1
	hud.refresh_units()
	check(not carrier.can_receive_player_orders() and hud.monster_count.text == "Монстры: 5",
		"Interior units count while preparing an assault")
	carrier.take_damage(1000.0)
	hud.refresh_units()
	check(hud.monster_count.text == "Монстры: 4" and roster.get_child(-1).get_child(2).text == "× 0",
		"Losing the last unit leaves a zero on its discovered row")
	mission.pause_requested.emit()
	app._restart_mission()
	await frames()
	hud = app.mission.mission_hud
	check(hud.monster_count.text == "Монстры: 0" and hud.monster_count.get_parent().get_child_count() == 1,
		"Restart clears discovered rows for the new attempt")
	await check_developer_humans()


func check_developer_humans() -> void:
	var mission: Node = app.mission
	mission.set_developer_mode(true)
	for frame in 6:
		await physics_frame
	var menu: PopupMenu
	for button in mission.mission_hud.developer_panel.find_children("*", "MenuButton", true, false):
		if button.text == "Создать человека":
			menu = button.get_popup()
			break
	check(menu != null, "Developer HUD has the human placement menu")
	if menu == null:
		return
	var roles := {
		"Крестьянин": "peasant", "Ремесленник": "artisan", "Стражник": "guard",
		"Священник": "priest", "Охранник священника": "priest_guard",
	}
	var labels: Array[String] = []
	for index in menu.item_count:
		labels.append(menu.get_item_text(index))
	check(labels == roles.keys(), "Developer menu offers exactly the five human roles")
	var point := Vector2(350, 1000)
	var total: int = mission.total_residents
	check(not mission.developer_place("resident", point) and mission.total_residents == total,
		"Legacy generic resident no longer spawns or affects population")
	for index in menu.item_count:
		var role: String = roles.get(menu.get_item_text(index), "")
		menu.id_pressed.emit(menu.get_item_id(index))
		var placed: bool = mission.developer_place(mission.developer_spawn, point + Vector2(26 * index, 0))
		check(placed and mission.villagers.back().get_meta("village_role", "") == role,
			"Developer menu places the selected human role: " + role)
