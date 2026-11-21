# Godot --headless --path . --script tests/mission_hud_validation.gd
extends SceneTree

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE_PREVIEW = preload("res://scripts/zombie_race_preview.gd")
const ART = ZOMBIE_PREVIEW.ART

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
	ART._appearance_rng.seed = 490
	var opening_appearance: int = ART.random_appearance()
	var reopening_appearance: int = ART.random_appearance()
	ART._appearance_rng.seed = 490
	app._open_race_selection()
	app._select_race("zombie")
	var race_labels: Array[Node] = app.race_preview.find_children("*", "Label", true, false)
	check(race_labels.any(func(label): return "всей орде" in label.text)
		and not race_labels.any(func(label): return "рамка" in label.text),
		"Zombie race screen describes horde movement without a selection hint")
	var previews: Array[Node] = app.race_preview.find_children("*", "Sprite2D", true, false)
	check(previews.size() == 1, "Race preview shows one ordinary zombie")
	check(previews.size() == 1 and previews[0].appearance == opening_appearance,
		"Race preview uses the random appearance chosen on entry")
	app._select_race("zombie")
	previews = app.race_preview.find_children("*", "Sprite2D", true, false)
	check(previews.size() == 1 and previews[0].appearance == opening_appearance,
		"Re-selecting the race keeps this visit's appearance")
	app._show(app.Screen.MISSIONS)
	app._open_race_selection()
	previews = app.race_preview.find_children("*", "Sprite2D", true, false)
	check(previews.size() == 1 and previews[0].appearance == reopening_appearance,
		"Reopening the race screen takes a new random roll")
	var preview := previews[0] as ZOMBIE_PREVIEW
	check(preview.texture == ART.VIEWS[reopening_appearance][0], "Preview uses the matching animation atlas")
	var idle := preview.region_rect
	var start_x := preview.position.x
	preview._process(ZOMBIE_PREVIEW.IDLE_TIME + 0.4)
	var walk := preview.region_rect
	check(walk != idle and preview.position.x > start_x and get_nodes_in_group("player_units").is_empty(),
		"Race preview walks using the ordinary zombie atlas without spawning a unit")
	preview._process(ZOMBIE_PREVIEW.WALK_TIME - 0.4 + ZOMBIE_PREVIEW.RUSH_TIME + 0.16)
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
	var forms := ["", "", "", "", "", PROGRESSION.BRUTE, PROGRESSION.HOUND, PROGRESSION.CARRIER]
	var ordinary_appearances := [2, 1, 0, 3, 3]
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
		if index < ordinary_appearances.size():
			for value in 1000:
				ART._appearance_rng.seed = value
				if ART.random_appearance() == ordinary_appearances[index]:
					ART._appearance_rng.seed = value
					break
		resident.player_infection_timer.timeout.emit()
	var units: Array[Node] = mission._owned_zombies()
	check(units.size() == forms.size() and hud.monster_count.text == "Монстры: 8", "Conversions update the total")
	if units.size() != forms.size():
		return
	for index in ordinary_appearances.size():
		check(units[index].ordinary_appearance == ordinary_appearances[index]
			and units[index].zombie_form.is_empty() and units[index].max_health == units[0].max_health,
			"Conversion chooses an ordinary appearance without changing form or health")
	var rows := {}
	for row in roster.get_children().slice(1):
		var name: String = row.get_child(1).text
		var icon: TextureRect = row.get_child(0)
		if name in ["Зомби", "Громила"]:
			var atlas: Texture2D = units[5].get_node("BruteVisual").texture if name == "Громила" \
				else ART.TURN[ART.Appearance.PLAIN]
			var portrait := icon.texture as AtlasTexture
			check(portrait != null and portrait.atlas == atlas and portrait.region.has_area(),
				"Sprite portrait uses the representative atlas for the unit type: " + name)
		else:
			check(icon.texture == null and icon.draw.get_connections().size() == 1,
				"Creature without sprites draws a fallback icon: " + name)
		rows[name] = row.get_child(2).text
	check(rows == {"Зомби": "× 5", "Громила": "× 1", "Бегун": "× 1", "Носитель": "× 1"},
		"Roster keeps all appearances in their single ordinary type row")
	await frames()
	var full_rect := panel.get_global_rect()
	check(full_rect.position.y < empty_rect.position.y and is_equal_approx(full_rect.end.y, empty_rect.end.y)
		and full_rect.end.x < hud.infection_button.get_global_rect().position.x,
		"Full roster expands upwards and stays clear of Infection")
	var carrier: Node = units.back()
	carrier.interior_building = mission.buildings[0]
	mission.horde_commands.assault_quantity = 1
	hud.refresh_units()
	check(not carrier.can_receive_player_orders() and hud.monster_count.text == "Монстры: 8",
		"Interior units count while preparing an assault")
	carrier.take_damage(1000.0)
	hud.refresh_units()
	check(hud.monster_count.text == "Монстры: 7" and roster.get_child(-1).get_child(2).text == "× 0",
		"Losing the last unit leaves a zero on its discovered row")
	units[0].take_damage(1000.0)
	hud.refresh_units()
	check(hud.monster_count.text == "Монстры: 6" and roster.get_child(1).get_child(2).text == "× 4"
		and roster.get_child_count() == 5, "Losing an ordinary skin only updates the common type count")
	mission.pause_requested.emit()
	app._restart_mission()
	await frames()
	hud = app.mission.mission_hud
	check(hud.monster_count.text == "Монстры: 0" and hud.monster_count.get_parent().get_child_count() == 1,
		"Restart clears discovered rows for the new attempt")
	await check_ordinary_visuals()
	await check_developer_humans()


func check_ordinary_visuals() -> void:
	var mission: Node = app.mission
	mission.set_developer_mode(true)
	for frame in 6:
		await physics_frame
	var menu: PopupMenu
	for button in mission.mission_hud.developer_panel.find_children("*", "MenuButton", true, false):
		if button.text == "Создать монстра":
			menu = button.get_popup()
			break
	check(menu != null, "Developer HUD has the monster placement menu")
	if menu == null:
		return
	var types := {"Зомби": "zombie", "Громила": PROGRESSION.BRUTE,
		"Бегун": PROGRESSION.HOUND, "Носитель": PROGRESSION.CARRIER}
	var labels: Array[String] = []
	for index in menu.item_count:
		labels.append(menu.get_item_text(index))
	check(labels == types.keys(), "Developer menu offers exactly the four monster types")
	if labels != types.keys():
		return
	for index in range(1, menu.item_count):
		menu.id_pressed.emit(menu.get_item_id(index))
		var kind: String = mission.developer_spawn
		var placed: bool = mission.developer_place(kind, Vector2(350 + 26 * index, 940))
		check(placed and mission._owned_zombies().back().zombie_form == types[labels[index]]
			and mission._owned_zombies().back().ordinary_appearance == -1,
			"Developer placement keeps the selected special type: " + labels[index])
	var unit_count: int = mission._owned_zombies().size()
	for legacy_kind in ["zombie_plain", "zombie_necrosis", "zombie_wounded", "zombie_bloom"]:
		check(not mission.developer_place(legacy_kind, Vector2(350, 960))
			and mission._owned_zombies().size() == unit_count, "A skin cannot be placed as a type")
	menu.id_pressed.emit(menu.get_item_id(0))
	check(mission.developer_spawn == "zombie" and mission.mission_hud.developer_tool_label.text.begins_with("Зомби ·"),
		"The ordinary placement tool only identifies the type")
	var ordinary_stats := []
	for index in ART.TURN.size():
		var point := Vector2(350 + 26 * index, 960)
		for value in 1000:
			ART._appearance_rng.seed = value
			if ART.random_appearance() == index:
				ART._appearance_rng.seed = value
				break
		var placed: bool = mission.developer_place(mission.developer_spawn, point)
		check(placed, "Developer can repeatedly place the ordinary zombie with one tool")
		if not placed:
			continue
		var unit: Node2D = mission._owned_zombies().back()
		var visual := unit.get_node("OrdinaryZombieVisual") as Sprite2D
		var stats := [unit.max_health, unit.move_speed, unit.attack_damage, unit.attack_interval, unit.infection_chance]
		if ordinary_stats.is_empty():
			ordinary_stats = stats
		check(unit.zombie_form.is_empty() and stats == ordinary_stats and unit.ordinary_appearance == index
			and visual.appearance == index and visual.texture == ART.TURN[index],
			"Placement rolls an appearance while retaining all ordinary combat stats")
		unit.global_position += Vector2.ONE.normalized()
		visual._physics_process(1.0 / 60.0)
		check(visual.region_rect.position.y == ART.Clip.WALK * ART.CELL.y,
			"Ordinary displacement uses the shamble row")
		unit.global_position += Vector2.ONE.normalized() * 2.0
		visual._physics_process(1.0 / 60.0)
		check(visual.region_rect.position.y == ART.Clip.RUSH * ART.CELL.y,
			"Accelerated displacement uses the rush row")
		visual._next_attack = 0
		for attack in ART.WINDUP_TIMES.size():
			unit.play_attack_visual(unit.global_position + Vector2(-20.0, -20.0))
			var view: Texture2D = ART.VIEWS[index][1 if index == 0 else 2]
			var row := ART.Clip.SWIPE + attack
			check(visual.texture == view and visual.flip_h == (index == 0)
				and visual.region_rect.position == Vector2(ART.CONTACT_FRAME, row) * ART.CELL,
				"Resolved attack shows the matching contact pose and preserves asymmetric facing")
		visual._advance_clip(1.0)
		unit.take_damage(1.0)
		check(visual.region_rect.position.y == ART.Clip.HURT * ART.CELL.y,
			"Nonlethal damage starts the hurt clip")
		visual._death_row = ART.Clip.DEATH_FORWARD + index % 2
		unit.take_damage(1000.0)
		visual._advance_clip(1.0)
		check(visual.region_rect.position == Vector2(ART.FRAME_COUNT - 1, visual._death_row) * ART.CELL
			and not visual.is_physics_processing(),
			"Death interrupts hurt and holds its final pose")
		for sector in 4:
			visual._direction = sector * 2 + 1
			visual._show_cycle(ART.Clip.WALK, 0)
			var tint: Color = ART.VIEW_TINTS[index][sector] if ART.VIEW_TINTS.has(index) else Color.WHITE
			check(visual.self_modulate == tint, "Every movement sector applies its own palette correction")
			visual._show_cycle(ART.Clip.WALK, 1)
			check(visual.self_modulate == tint, "A direction's palette stays constant within the animation")
			visual._show_turn()
			check(visual.self_modulate == Color.WHITE, "Turntable uses its reference colors")


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
