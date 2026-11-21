# Godot --headless --path . --script tests/menu_validation.gd --fixed-fps 60
extends SceneTree

var failures := 0
var app: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func esc(echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func click(title: String) -> void:
	for button in app.pages[app.screen].find_children("*", "Button", true, false):
		if button.text == title:
			button.pressed.emit()
			return
	check(false, "Button exists: " + title)

func pointer_click(title: String, parent: Control = null) -> void:
	if parent == null:
		parent = app.pages[app.screen]
	for button in parent.find_children("*", "Button", true, false):
		if button.text != title: continue
		var point: Vector2 = button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		Input.parse_input_event(motion)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = point
			event.global_position = point
			Input.parse_input_event(event)
			Input.flush_buffered_events()
		return
	check(false, "Pointer target exists: " + title)

func launch() -> void:
	click("Начать игру")
	click("Тестовая карта")
	click("Выбрать расу")
	click("Зомби")
	click("Начать миссию")
	await frames(5)

func run() -> void:
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames()
	check(app.screen == app.Screen.MAIN and app.mission == null and not paused, "Boot opens menu without running gameplay")
	pointer_click("Настройки")
	check(app.screen == app.Screen.SETTINGS, "Settings button opens settings")
	await frames()
	click("Назад")
	check(app.screen == app.Screen.MAIN, "Settings Back returns to main")
	click("Настройки")
	esc()
	check(app.screen == app.Screen.MAIN, "Settings Esc returns to main")
	click("Начать игру")
	esc()
	check(app.screen == app.Screen.MAIN, "Mission selection Esc returns to main")
	click("Начать игру")
	await frames()
	check(app.choose_race_button.disabled, "Choose Race disabled before mission selection")
	check(app.mission_buttons.keys() == ["village", "mission_1"] and app.mission_buttons.village.text == "Тестовая карта", "Test map stays first, followed by Mission 1")
	app._open_race_selection()
	check(app.screen == app.Screen.MISSIONS, "Cannot advance without selecting mission")
	app.mission_scroll.scroll_horizontal = 100
	app.mission_scroll.scroll_vertical = 80
	var scroll := Vector2i(app.mission_scroll.scroll_horizontal, app.mission_scroll.scroll_vertical)
	pointer_click("Тестовая карта")
	check(app.screen == app.Screen.MISSIONS and app.mission == null, "Selecting a mission stays on mission screen")
	check(not app.choose_race_button.disabled and app.mission_buttons.village.button_pressed, "Selection enables next action and highlights list item")
	check(app.mission_title.text == "Тестовая карта" and "80%" in app.mission_objectives.text, "Right panel shows selected mission and objective")
	check(app.mission_preview.visible and not app.mission_preview.shapes.is_empty() and get_nodes_in_group("player_units").is_empty(), "Preview draws geometry without starting gameplay")
	await frames()
	check(app.mission_scroll.get_global_rect().end.x < app.mission_details.get_global_rect().position.x, "Mission list is left of details")
	check(app.choose_race_button.get_global_rect().position.x > app.mission_scroll.get_global_rect().end.x, "Choose Race button is on the right")
	click("Выбрать расу")
	check(app.screen == app.Screen.RACES, "Choose Race explicitly opens race selection")
	check(app.start_button.disabled, "Start disabled before selecting a valid race")
	app._start_mission()
	check(app.screen == app.Screen.RACES and app.mission == null, "Race screen cannot launch before selecting race")
	await frames()
	pointer_click("Зомби")
	check(not app.start_button.disabled and app.mission == null, "Race updates preview without launching")
	await frames()
	check(app.race_list.get_global_rect().end.x < app.race_preview.get_global_rect().position.x and app.race_preview.get_global_rect().end.x < app.race_details.get_global_rect().position.x, "Race list, appearance and details form three columns")
	check(app.race_buttons.zombie.button_pressed, "Selected race is highlighted")
	check(app.race_preview.find_children("*", "Sprite2D", true, false).size() == 1 and get_nodes_in_group("player_units").is_empty(), "Portrait shows one ordinary zombie without running units")
	var details := ""
	for label in app.race_details.find_children("*", "Label", true, false): details += label.text
	check("Зомби" in details and "Сильные стороны" in details and "Слабые стороны" in details, "Description and strengths/weaknesses appear on the right")
	check(app.race_back_button.position.x < app.start_button.position.x and app.race_back_button.global_position.y == app.start_button.global_position.y, "Back and Start occupy left and right ends of footer")
	click("Зомби")
	check(app.race_preview.find_children("*", "Sprite2D", true, false).size() == 1, "Repeated selection replaces the portrait without duplicates")
	click("Назад")
	check(app.screen == app.Screen.MISSIONS and app.selected_race == "zombie", "Race Back preserves selection")
	click("Выбрать расу")
	check(app.race_buttons.zombie.button_pressed and not app.start_button.disabled, "Returning restores race highlight and launch availability")
	esc()
	await frames()
	check(app.selected_mission == "village" and scroll == Vector2i(app.mission_scroll.scroll_horizontal, app.mission_scroll.scroll_vertical), "Race Back retains mission and list position")
	click("Тестовая карта")
	click("Выбрать расу")
	click("Начать миссию")
	var first: Node = app.mission
	app._start_mission()
	await frames(5)
	check(first == app.mission and get_nodes_in_group("player_units").size() == 3, "Rapid launch cannot duplicate mission")
	check(app.mission.get_meta("race_id") == "zombie" and app.mission.get_node("Camera2D").move_speed == app.settings.camera_speed, "Loader passes race and camera setting")
	var unit: Node2D = get_nodes_in_group("player_units")[0]
	unit.set_selected(true)
	app.mission.command_active = true
	esc()
	check(not app.mission.command_active and not paused and app.screen == app.Screen.GAMEPLAY, "Esc cancels command preview before opening pause")
	unit.issue_player_move_order(Vector2(160, 420))
	await frames(5)
	esc()
	check(paused and app.screen == app.Screen.PAUSE, "Esc pauses scene tree")
	var position := unit.position
	var residents := []
	for resident in app.mission.villagers: residents.append(resident.position)
	var timer: Timer = unit.get_node("EncounterAttackTimer")
	timer.start(4)
	var remaining := timer.time_left
	var order: Vector2 = unit.target_position
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	mouse.position = Vector2(700, 600)
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	await frames(20)
	check(unit.position == position and timer.time_left == remaining and unit.target_position == order, "Pause freezes movement/timer and blocks orders")
	var unchanged := true
	for i in range(residents.size()): unchanged = unchanged and app.mission.villagers[i].position == residents[i]
	check(unchanged, "Pause freezes civilian AI movement")
	esc(true)
	check(paused, "Held Esc echo does not toggle pause")
	esc()
	check(not paused and first == app.mission, "Esc resumes same mission")
	await frames(5)
	check(unit.position != position, "Movement continues after resume")
	esc()
	click("В главное меню")
	click("Остаться")
	check(paused and app.screen == app.Screen.PAUSE and app.mission == first, "Stay keeps attempt paused")
	click("В главное меню")
	esc()
	check(paused and app.screen == app.Screen.PAUSE, "Confirmation Esc stays paused")
	click("В главное меню")
	click("Выйти")
	app._leave_mission()
	await frames()
	check(not paused and app.mission == null and app.screen == app.Screen.MAIN and get_nodes_in_group("player_units").is_empty(), "Leave removes attempt without results and resets pause")
	await launch()
	for resident in app.mission.villagers.duplicate():
		app.mission._on_resident_died(resident)
	esc()
	check(paused, "Pause can coincide with deferred mission completion")
	await frames()
	check(app.screen == app.Screen.RESULTS and "Победа" in app.result_text.text and "Убито: 4" in app.result_text.text, "Existing mission objective opens victory with real counters")
	check(app.mission.process_mode == Node.PROCESS_MODE_DISABLED and not paused, "Completed gameplay stops and clears coinciding pause")
	click("К выбору миссии")
	await frames()
	check(app.screen == app.Screen.MISSIONS and not paused, "Results returns to mission selection")
	click("Тестовая карта")
	click("Выбрать расу")
	click("Начать миссию")
	await frames(5)
	for zombie in get_nodes_in_group("player_units"): zombie._die()
	await frames()
	check(app.screen == app.Screen.GAMEPLAY and not paused, "Loss of all zombies leaves the test attempt active")
	esc()
	click("Перезапустить миссию")
	await frames()
	check(app.screen == app.Screen.GAMEPLAY and get_nodes_in_group("player_units").size() == 3, "Pause menu restarts after total army loss")
	esc()
	click("В главное меню")
	click("Выйти")
	await frames()
	check(not paused and app.mission == null, "Voluntary exit cleans up without results")
	click("Начать игру")
	click("Миссия №1")
	check(app.selected_mission == "mission_1" and app.selected_race == "" and app.mission_preview.map_rect == Rect2(0,0,3000,2000), "New mission resets race and previews the complete map bounds")
	var map_image: Texture2D = app.mission_preview.preview_texture
	check(map_image != null and map_image.resource_path == "res://assets/maps/mission_01_preview.png"
		and app.mission_preview.shapes.is_empty() and app.mission == null,
		"Mission 1 uses the rendered map image without starting gameplay")
	click("Тестовая карта")
	check(app.mission_preview.preview_texture == null and not app.mission_preview.shapes.is_empty(),
		"Switching maps clears the rendered image and restores the test map geometry")
	click("Миссия №1")
	click("Выбрать расу")
	click("Зомби")
	click("Начать миссию")
	await frames(5)
	check(app.mission.total_residents == 44 and get_nodes_in_group("player_units").is_empty(), "Mission 1 launches through the shared menu loader without zombies")
	esc()
	var new_positions := []
	for resident in app.mission.villagers: new_positions.append(resident.position)
	await frames(10)
	var new_frozen := true
	for i in range(app.mission.villagers.size()): new_frozen = new_frozen and app.mission.villagers[i].position == new_positions[i]
	check(paused and new_frozen, "Mission 1 pauses all residents through existing menu")
	check(not app.finish_mission_button.is_visible_in_tree(), "Finish Mission is hidden at the start of the attempt")
	esc()
	for i in range(35): app.mission._on_resident_died(app.mission.villagers[i])
	esc()
	app._finish_mission()
	check(app.screen == app.Screen.PAUSE and not app.finish_mission_button.is_visible_in_tree(),
		"Finish Mission stays unavailable below the victory threshold")
	esc()
	app.mission._on_resident_died(app.mission.villagers[35])
	esc()
	await frames()
	check(app.screen == app.Screen.PAUSE and app.finish_mission_button.is_visible_in_tree() and paused,
		"Esc opens pause with Finish Mission at 36 of 44")
	click("Продолжить")
	check(app.screen == app.Screen.GAMEPLAY and not paused and app.mission.mission_hud.victory_notice.visible
		and "Победа" in app.mission.mission_hud.objective_label.text, "Victory appears in the HUD and allows resuming")
	esc()
	click("Перезапустить миссию")
	await frames()
	esc()
	check(not app.finish_mission_button.is_visible_in_tree(), "Restart clears victory and hides Finish Mission")
	esc()
	for i in range(37): app.mission._on_resident_died(app.mission.villagers[i])
	pointer_click("⚙ Пауза", app.mission.mission_hud)
	await frames()
	check(paused and app.finish_mission_button.is_visible_in_tree(), "HUD gear exposes Finish Mission after victory")
	pointer_click("Завершить миссию")
	check(app.screen == app.Screen.RESULTS and "Миссия №1" in app.result_text.text and "Жителей: 44" in app.result_text.text
		and "Убито: 37" in app.result_text.text and "Вирус за попытку:" in app.result_text.text,
		"Finish Mission shows current victory totals and Virus summary")
	check(app.mission.process_mode == Node.PROCESS_MODE_DISABLED and not paused, "Manual finish stops gameplay and releases tree pause")
	click("К выбору миссии")
	await frames()
	check(app.mission == null and get_nodes_in_group("player_units").is_empty(), "New map cleans up fully for mission switching and restart")
	# Verify persistence without replacing an existing user's preferences.
	var path: String = app.settings.PATH
	var existed := FileAccess.file_exists(path)
	var previous := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	app.settings.camera_speed = 650
	check(app.settings.save_settings() == OK, "Settings save succeeds")
	var reloaded = load("res://scripts/game_settings.gd").new()
	reloaded.load_settings()
	check(reloaded.camera_speed == 650, "Settings survive reload")
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(previous)
			file.close()
		else:
			check(false, "Settings backup can be restored")
	else: DirAccess.remove_absolute(path)
	app.queue_free()
	await frames()
	print("Menu validation failures: ", failures)
	quit(1 if failures else 0)
