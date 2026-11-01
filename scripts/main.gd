extends Node

const CATALOG = preload("res://scripts/mission_catalog.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
enum Screen { MAIN, SETTINGS, MISSIONS, RACES, GAMEPLAY, PAUSE, CONFIRM_LEAVE, RESULTS }
var screen: Screen = Screen.MAIN
var selected_mission := ""
var selected_race := ""
var mission: Node2D
var settings = SETTINGS.new()
var pages: Dictionary = {}
var ui: Control
var race_list: VBoxContainer
var race_preview: VBoxContainer
var start_button: Button
var result_text: Label
var settings_status: Label
var mission_scroll: ScrollContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_settings()
	_build_ui()
	_show(Screen.MAIN)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		match screen:
			Screen.SETTINGS, Screen.MISSIONS: _show(Screen.MAIN)
			Screen.RACES: _show(Screen.MISSIONS)
			Screen.GAMEPLAY: _pause()
			Screen.PAUSE: _resume()
			Screen.CONFIRM_LEAVE: _show(Screen.PAUSE)

func _show(next: Screen) -> void:
	screen = next
	for key in pages:
		pages[key].visible = key == screen
	ui.visible = screen != Screen.GAMEPLAY
	if ui.visible:
		_focus_page(screen)

func _focus_page(page: Screen) -> void:
	# Wait for container layout before focus tries to reveal the first button.
	await get_tree().process_frame
	if screen == page:
		var buttons: Array[Node] = pages[page].find_children("*", "Button", true, false)
		if not buttons.is_empty():
			buttons[0].grab_focus()
		await get_tree().process_frame
	if screen == page:
		pages[page].scroll_vertical = 0

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 48)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _text(parent: Node, value: String, font_size := 22) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _page(id: Screen, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	ui.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 40
	scroll.offset_top = 24
	scroll.offset_right = -40
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	_text(box, title, 36)
	pages[id] = scroll
	return box

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui = Panel.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font_size = 22
	var background := StyleBoxFlat.new()
	background.bg_color = Color("161d18")
	theme.set_stylebox("panel", "Panel", background)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("344332") if state == "normal" else Color("4c6043")
		if state == "disabled": style.bg_color = Color("272e29")
		style.set_content_margin_all(10)
		if state == "focus":
			style.set_border_width_all(2)
			style.border_color = Color("bbcf94")
		theme.set_stylebox(state, "Button", style)
	ui.theme = theme
	var main := _page(Screen.MAIN, "I’m a Monster")
	_text(main, "Тактический прототип • первая деревня")
	_button(main, "Начать игру", func():
		if screen == Screen.MAIN: _show(Screen.MISSIONS))
	_button(main, "Настройки", func():
		if screen == Screen.MAIN: _show(Screen.SETTINGS))
	var options := _page(Screen.SETTINGS, "Настройки")
	var fullscreen := CheckButton.new()
	fullscreen.text = "Полноэкранный режим"
	fullscreen.button_pressed = settings.fullscreen
	options.add_child(fullscreen)
	fullscreen.toggled.connect(func(value: bool):
		settings.fullscreen = value
		settings.apply_display()
		_save_settings())
	_text(options, "Скорость камеры (WASD), единиц/с")
	var speed := HSlider.new()
	speed.min_value = 200
	speed.max_value = 900
	speed.step = 50
	speed.value = settings.camera_speed
	speed.custom_minimum_size.y = 40
	options.add_child(speed)
	var speed_label := _text(options, str(int(speed.value)))
	speed.value_changed.connect(func(value: float):
		settings.camera_speed = value
		speed_label.text = str(int(value))
		_save_settings())
	settings_status = _text(options, "Настройки сохраняются автоматически.", 18)
	_button(options, "Назад", func(): _show(Screen.MAIN))
	var missions := _page(Screen.MISSIONS, "Выбор миссии")
	_text(missions, "Выберите миссию на схеме.", 18)
	mission_scroll = ScrollContainer.new()
	mission_scroll.custom_minimum_size.y = 350
	missions.add_child(mission_scroll)
	var map := Control.new()
	map.custom_minimum_size = Vector2(1100, 500)
	mission_scroll.add_child(map)
	var ground := ColorRect.new()
	ground.color = Color("283729")
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(ground)
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in CATALOG.MISSIONS:
		var marker := _button(map, "◆ " + CATALOG.MISSIONS[id].name, _select_mission.bind(id))
		marker.position = CATALOG.MISSIONS[id].marker
	_button(missions, "Назад", func(): _show(Screen.MAIN))
	var races := _page(Screen.RACES, "Выбор расы")
	race_list = VBoxContainer.new()
	races.add_child(race_list)
	race_preview = VBoxContainer.new()
	races.add_child(race_preview)
	start_button = _button(races, "Начать миссию", _start_mission)
	start_button.disabled = true
	_button(races, "Назад", func(): _show(Screen.MISSIONS))
	var pause := _page(Screen.PAUSE, "Пауза")
	_text(pause, "Нажмите Esc, чтобы продолжить")
	_button(pause, "В главное меню", func():
		if screen == Screen.PAUSE: _show(Screen.CONFIRM_LEAVE))
	var confirm := _page(Screen.CONFIRM_LEAVE, "Покинуть миссию?")
	_text(confirm, "Текущая попытка будет потеряна. Результат миссии не будет записан.")
	_button(confirm, "Остаться", func():
		if screen == Screen.CONFIRM_LEAVE: _show(Screen.PAUSE))
	_button(confirm, "Выйти", _leave_mission)
	var results := _page(Screen.RESULTS, "Итог миссии")
	result_text = _text(results, "")
	_button(results, "К выбору миссии", func():
		if screen == Screen.RESULTS:
			_dispose_mission()
			_show(Screen.MISSIONS))

func _save_settings() -> void:
	settings_status.text = "Настройки сохранены." if settings.save_settings() == OK else "Не удалось сохранить настройки. Изменения действуют до закрытия игры."

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _select_mission(id: String) -> void:
	if screen != Screen.MISSIONS or not CATALOG.MISSIONS.has(id): return
	if selected_mission != id: selected_race = ""
	selected_mission = id
	_clear_children(race_list)
	for race_id in CATALOG.MISSIONS[id].races:
		_button(race_list, CATALOG.RACES[race_id].name, _select_race.bind(race_id))
	_update_preview()
	_show(Screen.RACES)

func _select_race(id: String) -> void:
	if screen != Screen.RACES or not CATALOG.MISSIONS[selected_mission].races.has(id): return
	selected_race = id
	_update_preview()

func _update_preview() -> void:
	_clear_children(race_preview)
	_text(race_preview, CATALOG.MISSIONS[selected_mission].name + "\n" + CATALOG.MISSIONS[selected_mission].description, 18)
	start_button.disabled = not CATALOG.RACES.has(selected_race)
	if start_button.disabled:
		_text(race_preview, "Выберите расу для просмотра описания.")
		return
	var race: Dictionary = CATALOG.RACES[selected_race]
	# Render the current scene's polygon, without running unit AI in the menu.
	var source: Node2D = load(race.preview).instantiate()
	var visual := source.get_node("Polygon2D").duplicate() as Polygon2D
	source.free()
	var preview := Control.new()
	preview.custom_minimum_size.y = 100
	preview.add_child(visual)
	visual.position = Vector2(70, 64)
	visual.scale = Vector2.ONE * 3
	race_preview.add_child(preview)
	_text(race_preview, race.name + "\n" + race.description)
	_text(race_preview, "Сильные стороны: " + race.strengths + "\nСлабые стороны: " + race.weaknesses, 18)
	_text(race_preview, "Управление: ЛКМ — выбор, рамка — группа; ПКМ — движение; Shift+ПКМ — распределение. WASD — камера, колесо — масштаб, Esc — пауза.", 18)

func _start_mission() -> void:
	if screen != Screen.RACES or not CATALOG.MISSIONS.has(selected_mission): return
	if not CATALOG.MISSIONS[selected_mission].races.has(selected_race): return
	# Single loading point for all mission scenes. Current content supports Zombie.
	var packed := load(CATALOG.MISSIONS[selected_mission].scene) as PackedScene
	if packed == null: return
	mission = packed.instantiate()
	mission.process_mode = Node.PROCESS_MODE_PAUSABLE
	mission.set_meta("race_id", selected_race)
	mission.mission_finished.connect(_on_mission_finished)
	add_child(mission)
	mission.get_node("Camera2D").move_speed = settings.camera_speed
	get_tree().paused = false
	_show(Screen.GAMEPLAY)

func _pause() -> void:
	mission.cancel_selection()
	get_tree().paused = true
	_show(Screen.PAUSE)

func _resume() -> void:
	get_tree().paused = false
	_show(Screen.GAMEPLAY)

func _leave_mission() -> void:
	if screen != Screen.CONFIRM_LEAVE: return
	_dispose_mission()
	_show(Screen.MAIN)

func _dispose_mission() -> void:
	if is_instance_valid(mission):
		mission.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(mission)
		mission.queue_free()
	mission = null
	get_tree().paused = false

func _on_mission_finished(outcome: String, summary: Dictionary) -> void:
	if screen not in [Screen.GAMEPLAY, Screen.PAUSE, Screen.CONFIRM_LEAVE]: return
	mission.cancel_selection()
	mission.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	result_text.text = "%s — %s\nЖителей: %d\nЗаражено: %d\nУбито: %d" % [
		"Победа" if outcome == "victory" else "Поражение",
		CATALOG.MISSIONS[selected_mission].name, summary.total, summary.infected, summary.killed]
	_show(Screen.RESULTS)

func _exit_tree() -> void:
	get_tree().paused = false
