extends Node

const CATALOG = preload("res://scripts/mission_catalog.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
const MISSION_PREVIEW = preload("res://scripts/mission_preview.gd")
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
var race_details: VBoxContainer
var race_buttons: Dictionary = {}
var race_mission_label: Label
var race_back_button: Button
var start_button: Button
var result_text: Label
var settings_status: Label
var mission_scroll: ScrollContainer
var mission_buttons: Dictionary = {}
var mission_details: VBoxContainer
var mission_title: Label
var mission_description: Label
var mission_objectives: Label
var mission_preview: Control
var choose_race_button: Button

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
	missions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text(missions, "Выберите миссию в списке, затем нажмите «Выбрать расу».", 18)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.custom_minimum_size.y = 390
	missions.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	_text(left, "Миссии", 24)
	mission_scroll = ScrollContainer.new()
	mission_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(mission_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	mission_scroll.add_child(list)
	for id in CATALOG.MISSIONS:
		var item := _button(list, CATALOG.MISSIONS[id].name, _select_mission.bind(id))
		item.toggle_mode = true
		mission_buttons[id] = item
	mission_details = VBoxContainer.new()
	mission_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_details.size_flags_stretch_ratio = 2.2
	mission_details.add_theme_constant_override("separation", 12)
	columns.add_child(mission_details)
	mission_title = _text(mission_details, "Выберите миссию", 26)
	mission_preview = MISSION_PREVIEW.new()
	mission_preview.custom_minimum_size.y = 240
	mission_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mission_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mission_details.add_child(mission_preview)
	mission_preview.hide()
	mission_description = _text(mission_details, "Справа появятся схема, описание и цели выбранной миссии.", 18)
	mission_objectives = _text(mission_details, "", 18)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	missions.add_child(footer)
	_button(footer, "Назад", func(): _show(Screen.MAIN)).custom_minimum_size.x = 180
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	choose_race_button = _button(footer, "Выбрать расу", _open_race_selection)
	choose_race_button.custom_minimum_size.x = 240
	choose_race_button.disabled = true
	var races := _page(Screen.RACES, "Выбор расы")
	races.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_mission_label = _text(races, "", 18)
	var race_columns := HBoxContainer.new()
	race_columns.add_theme_constant_override("separation", 24)
	race_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_columns.custom_minimum_size.y = 390
	races.add_child(race_columns)
	var race_left := VBoxContainer.new()
	race_left.custom_minimum_size.x = 220
	race_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_columns.add_child(race_left)
	_text(race_left, "Расы", 24)
	var race_scroll := ScrollContainer.new()
	race_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	race_left.add_child(race_scroll)
	race_list = VBoxContainer.new()
	race_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_list.add_theme_constant_override("separation", 8)
	race_scroll.add_child(race_list)
	race_preview = VBoxContainer.new()
	race_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_preview.size_flags_stretch_ratio = 1.4
	race_preview.add_theme_constant_override("separation", 16)
	race_columns.add_child(race_preview)
	race_details = VBoxContainer.new()
	race_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_details.size_flags_stretch_ratio = 1.4
	race_details.add_theme_constant_override("separation", 16)
	race_columns.add_child(race_details)
	var race_footer := HBoxContainer.new()
	race_footer.add_theme_constant_override("separation", 24)
	races.add_child(race_footer)
	race_back_button = _button(race_footer, "Назад", func(): _show(Screen.MISSIONS))
	race_back_button.custom_minimum_size.x = 180
	var race_spacer := Control.new()
	race_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_footer.add_child(race_spacer)
	start_button = _button(race_footer, "Начать миссию", _start_mission)
	start_button.custom_minimum_size.x = 240
	start_button.disabled = true
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
	for mission_id in mission_buttons:
		mission_buttons[mission_id].set_pressed_no_signal(mission_id == id)
	var definition: Dictionary = CATALOG.MISSIONS[id]
	mission_title.text = definition.name
	mission_description.text = definition.description
	mission_objectives.text = "Цель миссии\n" + definition.objectives
	mission_preview.show_mission(definition.scene)
	mission_preview.show()
	choose_race_button.disabled = false

func _open_race_selection() -> void:
	if screen != Screen.MISSIONS or not CATALOG.MISSIONS.has(selected_mission): return
	_clear_children(race_list)
	race_buttons.clear()
	for race_id in CATALOG.MISSIONS[selected_mission].races:
		var item := _button(race_list, CATALOG.RACES[race_id].name, _select_race.bind(race_id))
		item.toggle_mode = true
		race_buttons[race_id] = item
	_update_preview()
	_show(Screen.RACES)

func _select_race(id: String) -> void:
	if screen != Screen.RACES or not CATALOG.MISSIONS[selected_mission].races.has(id): return
	selected_race = id
	_update_preview()

func _update_preview() -> void:
	_clear_children(race_preview)
	_clear_children(race_details)
	race_mission_label.text = "Миссия: " + CATALOG.MISSIONS[selected_mission].name
	for race_id in race_buttons:
		race_buttons[race_id].set_pressed_no_signal(race_id == selected_race)
	_text(race_preview, "Внешний вид", 24)
	start_button.disabled = not CATALOG.RACES.has(selected_race)
	if start_button.disabled:
		_text(race_preview, "Выберите расу в списке слева.", 18)
		_text(race_details, "Описание", 24)
		_text(race_details, "Здесь появятся описание, сильные и слабые стороны выбранной расы.", 18)
		return
	var race: Dictionary = CATALOG.RACES[selected_race]
	# Render the current scene's polygon, without running unit AI in the menu.
	var source: Node2D = load(race.preview).instantiate()
	var visual := source.get_node("Polygon2D").duplicate() as Polygon2D
	source.free()
	var preview := PanelContainer.new()
	preview.custom_minimum_size.y = 200
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(center)
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(100, 150)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(portrait)
	portrait.add_child(visual)
	visual.position = Vector2(50, 100)
	visual.scale = Vector2.ONE * 4
	race_preview.add_child(preview)
	_text(race_preview, "Как играется", 24)
	_text(race_preview, race.gameplay, 18)
	_text(race_preview, "ЛКМ и рамка — выбор. ПКМ — движение. Shift+ПКМ — распределение группы.", 16)
	_text(race_details, race.name, 26)
	_text(race_details, race.description, 18)
	_text(race_details, "Сильные стороны", 22)
	_text(race_details, race.strengths, 18)
	_text(race_details, "Слабые стороны", 22)
	_text(race_details, race.weaknesses, 18)

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
