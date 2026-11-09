# Godot --headless --path . --script tests/mission_hud_validation.gd
extends SceneTree

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
	app._start_mission()
	await frames()
	var first: Node = app.mission
	var hud: Control = first.mission_hud
	check(hud.monster_button.text == "Зомби × 3", "HUD counts available zombies")
	check("Цель:" in hud.objective_label.text and str(first.total_residents) in hud.objective_label.text, "HUD shows mission goal")
	var army_panel: Control = hud.monster_button.get_parent().get_parent()
	check(army_panel.get_global_rect().position.y > root.size.y * 0.8, "Monster list sits in the lower left")
	check("Спокойствие" in hud.alert_label.text, "HUD shows village stage")
	hud.monster_button.pressed.emit()
	var all_selected := true
	for unit in get_nodes_in_group("player_units"):
		all_selected = all_selected and unit.is_selected
	check(all_selected, "Species row selects all available zombies")
	var empty_selection: Array[Node] = []
	first._apply_selection(empty_selection)
	check(not get_nodes_in_group("player_units")[0].is_selected, "Regular selection replaces species selection")
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
	check(app.mission.mission_hud.monster_button.text == "Зомби × 3", "Restart creates fresh HUD")
	app.queue_free()
	await frames()
	print("Mission HUD validation failures: ", failures)
	quit(1 if failures else 0)
