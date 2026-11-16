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
	var race_labels: Array[Node] = app.race_preview.find_children("*", "Label", true, false)
	check(race_labels.any(func(label): return "всей орде" in label.text)
		and not race_labels.any(func(label): return "рамка" in label.text),
		"Zombie race screen describes horde movement without a selection hint")
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
	app.queue_free()
	await frames()
	print("Mission HUD validation failures: ", failures)
	quit(1 if failures else 0)
