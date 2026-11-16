extends Node

const CATALOG = preload("res://scripts/mission_catalog.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
const MISSION_PREVIEW = preload("res://scripts/mission_preview.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const MENU_BACKGROUND = preload("res://assets/ui/undead_menu_background.png")
const WORDMARK = preload("res://assets/ui/monster_wordmark.png")
enum Screen { MAIN, SETTINGS, MISSIONS, RACES, GAMEPLAY, PAUSE, CONFIRM_LEAVE, RESULTS, DEVELOPMENT }
var screen: Screen = Screen.MAIN
var selected_mission := ""
var selected_race := ""
var mission: Node2D
var settings = SETTINGS.new()
var pages: Dictionary = {}
var ui: Control
var menu_background: TextureRect
var race_list: VBoxContainer
var race_preview: VBoxContainer
var race_details: VBoxContainer
var race_buttons: Dictionary = {}
var race_mission_label: Label
var race_back_button: Button
var start_button: Button
var development_button: Button
var development_title: Label
var development_tree: Control
var development_items: Dictionary[String, Button] = {}
var development_branches: Array = []
var applied_development: Dictionary[String, PackedStringArray] = {}
var development_status: Label
var reset_development_button: Button
var apply_development_button: Button
var result_text: Label
var settings_status: Label
var settings_draft: RefCounted
var settings_panels: Array[Control] = []
var settings_sections: Array[Button] = []
var settings_key_buttons: Dictionary[String, Button] = {}
var settings_capture := ""
var settings_fullscreen: CheckButton
var settings_speed: HSlider
var settings_speed_label: Label
var settings_return_screen: Screen = Screen.MAIN
var mission_scroll: ScrollContainer
var mission_buttons: Dictionary = {}
var mission_details: VBoxContainer
var mission_title: Label
var mission_description: Label
var mission_objectives: Label
var mission_preview: Control
var choose_race_button: Button
var developer_mode := false
var developer_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_settings()
	_build_ui()
	_show(Screen.MAIN)

func _input(event: InputEvent) -> void:
	if screen == Screen.SETTINGS and not settings_capture.is_empty() and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			_capture_settings_key(event)
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		if screen == Screen.GAMEPLAY and is_instance_valid(mission) and mission.cancel_order_preview():
			return
		match screen:
			Screen.SETTINGS: _show(settings_return_screen)
			Screen.MISSIONS: _show(Screen.MAIN)
			Screen.RACES: _show(Screen.MISSIONS)
			Screen.DEVELOPMENT: _show(Screen.RACES)
			Screen.GAMEPLAY: _pause()
			Screen.PAUSE: _resume()
			Screen.CONFIRM_LEAVE: _show(Screen.PAUSE)

func _show(next: Screen) -> void:
	if screen == Screen.SETTINGS and next != Screen.SETTINGS:
		_end_settings_capture()
		settings_draft = null
	var returning_from_development := screen == Screen.DEVELOPMENT and next == Screen.RACES
	screen = next
	for key in pages:
		pages[key].visible = key == screen
	ui.visible = screen != Screen.GAMEPLAY
	menu_background.modulate = Color.WHITE if screen == Screen.MAIN else Color(0.42, 0.42, 0.42)
	if is_instance_valid(developer_button): developer_button.visible = screen == Screen.MAIN
	if ui.visible:
		_focus_page(screen, development_button if returning_from_development else null)

func _focus_page(page: Screen, preferred_button: Button) -> void:
	# Wait for container layout before focus tries to reveal the first button.
	await get_tree().process_frame
	if screen == page:
		if is_instance_valid(preferred_button):
			preferred_button.grab_focus()
		else:
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

func _page(id: Screen, title: String, centered := false) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	ui.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 40
	scroll.offset_top = 24
	scroll.offset_right = -40
	scroll.offset_bottom = -170 if id == Screen.MAIN else -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content: Control = scroll
	if centered:
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
		content = center
	if id != Screen.MAIN:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel",
			DARK_THEME.surface(Color("100c10ed"), DARK_THEME.EDGE, 24))
		content.add_child(panel)
		content = panel
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	content.add_child(box)
	if id != Screen.MAIN:
		var heading := _text(box, title, 36)
		heading.add_theme_color_override("font_color", DARK_THEME.HEADING)
		if centered:
			box.custom_minimum_size.x = 460
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var rule := ColorRect.new()
		rule.color = Color("52252e")
		rule.custom_minimum_size.y = 1
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rule)
	pages[id] = scroll
	return box

func _style_main_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(294, 56)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 26)
	var marker := Label.new()
	marker.text = "◆"
	marker.position = Vector2(22, 15)
	marker.add_theme_color_override("font_color", DARK_THEME.ACCENT)
	marker.add_theme_font_size_override("font_size", 18)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.hide()
	button.add_child(marker)
	button.focus_entered.connect(marker.show)
	button.focus_exited.connect(marker.hide)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui = Panel.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = DARK_THEME.build(22, 8)
	ui.add_theme_stylebox_override("panel", DARK_THEME.surface(DARK_THEME.INK, DARK_THEME.INK, 0))
	menu_background = TextureRect.new()
	menu_background.texture = MENU_BACKGROUND
	menu_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu_background)
	menu_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var main := _page(Screen.MAIN, "", true)
	var logo := TextureRect.new()
	logo.texture = WORDMARK
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(740, 245)
	logo.accessibility_name = "I’m a Monster"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(logo)
	_style_main_button(_button(main, "Начать игру", func():
		if screen == Screen.MAIN: _show(Screen.MISSIONS)))
	_style_main_button(_button(main, "Настройки", func():
		if screen == Screen.MAIN: _open_settings(Screen.MAIN)))
	developer_button = Button.new()
	developer_button.text = "🔧"
	developer_button.tooltip_text = "Включить режим разработки"
	developer_button.custom_minimum_size = Vector2(48, 48)
	developer_button.add_theme_font_size_override("font_size", 28)
	developer_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	developer_button.offset_left = -64
	developer_button.offset_top = -64
	developer_button.offset_right = -16
	developer_button.offset_bottom = -16
	ui.add_child(developer_button)
	_update_developer_button()
	developer_button.pressed.connect(func():
		developer_mode = not developer_mode
		_update_developer_button()
		if is_instance_valid(mission): mission.set_developer_mode(developer_mode))
	_build_settings_page()
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
	race_back_button.custom_minimum_size.x = 240
	var race_spacer := Control.new()
	race_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_footer.add_child(race_spacer)
	development_button = _button(race_footer, "Развитие", _open_development)
	development_button.custom_minimum_size.x = 240
	development_button.disabled = true
	var start_spacer := Control.new()
	start_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_footer.add_child(start_spacer)
	start_button = _button(race_footer, "Начать миссию", _start_mission)
	start_button.custom_minimum_size.x = 240
	start_button.disabled = true
	_build_development_page()
	var pause := _page(Screen.PAUSE, "Пауза", true)
	_button(pause, "Продолжить", func():
		if screen == Screen.PAUSE: _resume())
	_button(pause, "Перезапустить миссию", _restart_mission)
	_button(pause, "Настройки", func():
		if screen == Screen.PAUSE: _open_settings(Screen.PAUSE))
	_button(pause, "В главное меню", func():
		if screen == Screen.PAUSE: _show(Screen.CONFIRM_LEAVE))
	var confirm := _page(Screen.CONFIRM_LEAVE, "Покинуть миссию?", true)
	_text(confirm, "Текущая попытка будет потеряна. Результат миссии не будет записан.")
	_button(confirm, "Остаться", func():
		if screen == Screen.CONFIRM_LEAVE: _show(Screen.PAUSE))
	_button(confirm, "Выйти", _leave_mission)
	var results := _page(Screen.RESULTS, "Итог миссии", true)
	result_text = _text(results, "")
	_button(results, "К выбору миссии", func():
		if screen == Screen.RESULTS:
			_dispose_mission()
			_show(Screen.MISSIONS))

func _build_settings_page() -> void:
	var options := _page(Screen.SETTINGS, "Настройки")
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	options.add_child(columns)
	var sections := VBoxContainer.new()
	sections.custom_minimum_size.x = 200
	sections.add_theme_constant_override("separation", 8)
	columns.add_child(sections)
	var content := PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100c10ed"), DARK_THEME.EDGE, 16))
	columns.add_child(content)
	for title in ["Общее", "Графика", "Звук", "Управление"]:
		var index := settings_panels.size()
		var button := _button(sections, title, _select_settings_section.bind(index))
		button.toggle_mode = true
		settings_sections.append(button)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = 220
		content.add_child(scroll)
		settings_panels.append(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		scroll.add_child(box)
		match title:
			"Графика":
				settings_fullscreen = CheckButton.new()
				settings_fullscreen.text = "Полноэкранный режим"
				box.add_child(settings_fullscreen)
				settings_fullscreen.toggled.connect(func(value: bool):
					settings_draft.fullscreen = value
					settings_status.text = "Есть несохранённые изменения.")
			"Управление":
				_build_control_settings(box)
			_:
				_text(box, "Настройки появятся позже.")

	settings_status = _text(options, "", 18)
	settings_status.custom_minimum_size.y = 26
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	options.add_child(footer)
	_button(footer, "Назад", func(): _show(settings_return_screen)).custom_minimum_size.x = 160
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_button(footer, "Применить", _apply_settings).custom_minimum_size.x = 160


func _build_control_settings(box: VBoxContainer) -> void:
	settings_speed_label = _text(box, "")
	settings_speed = HSlider.new()
	settings_speed.min_value = 200
	settings_speed.max_value = 900
	settings_speed.step = 1
	settings_speed.custom_minimum_size.y = 36
	box.add_child(settings_speed)
	settings_speed.value_changed.connect(func(value: float):
		settings_draft.camera_speed = value
		settings_speed_label.text = "Скорость камеры: %d ед./с" % int(value)
		settings_status.text = "Есть несохранённые изменения.")
	var labels := ["Камера вверх", "Камера влево", "Камера вниз", "Камера вправо", "Основная способность расы"]
	_text(box, "Нажмите на кнопку справа и выберите новую клавишу.", 18)
	var index := 0
	for action: String in SETTINGS.DEFAULT_KEYS:
		if index == labels.size():
			_text(box, "Слоты дополнительных способностей (пока пусты)", 18)
		var row := HBoxContainer.new()
		box.add_child(row)
		var title: String = labels[index] if index < labels.size() else "Слот %d" % (index - labels.size() + 1)
		_text(row, title).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := _button(row, "", _begin_settings_capture.bind(action))
		button.custom_minimum_size = Vector2(150, 40)
		settings_key_buttons[action] = button
		index += 1


func _select_settings_section(index: int) -> void:
	_end_settings_capture()
	for i in settings_panels.size():
		settings_panels[i].visible = i == index
		settings_sections[i].set_pressed_no_signal(i == index)


func _begin_settings_capture(action: String) -> void:
	_end_settings_capture()
	settings_capture = action
	settings_key_buttons[action].text = "Нажмите клавишу…"


func _end_settings_capture() -> void:
	if not settings_capture.is_empty():
		var action := settings_capture
		settings_capture = ""
		_refresh_settings_key(action)


func _refresh_settings_key(action: String) -> void:
	var key: int = settings_draft.keys[action]
	var display_key: int = key if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(key)
	settings_key_buttons[action].text = OS.get_keycode_string(display_key if display_key != KEY_NONE else key)


func _capture_settings_key(event: InputEventKey) -> void:
	if event.is_action_pressed("ui_cancel"):
		_end_settings_capture()
		return
	var key := event.physical_keycode
	if not SETTINGS.can_bind(key) or event.alt_pressed or event.ctrl_pressed or event.shift_pressed or event.meta_pressed:
		settings_status.text = "Выберите одиночную клавишу. Esc отменяет назначение."
		return
	for action in settings_draft.keys:
		if action != settings_capture and settings_draft.keys[action] == key:
			settings_status.text = "Эта клавиша занята. Выберите другую или нажмите Esc."
			return
	settings_draft.keys[settings_capture] = key
	_end_settings_capture()
	settings_status.text = "Есть несохранённые изменения."


func _apply_settings() -> void:
	_end_settings_capture()
	if settings_draft.save_settings() != OK:
		settings_status.text = "Не удалось сохранить настройки. Попробуйте снова."
		return
	settings.fullscreen = settings_draft.fullscreen
	settings.camera_speed = settings_draft.camera_speed
	settings.keys = settings_draft.keys.duplicate()
	settings.apply()
	settings_status.text = "Настройки сохранены."


func _open_settings(origin: Screen) -> void:
	settings_return_screen = origin
	settings_capture = ""
	settings_draft = SETTINGS.new()
	settings_draft.fullscreen = settings.fullscreen
	settings_draft.camera_speed = settings.camera_speed
	settings_draft.keys = settings.keys.duplicate()
	settings_fullscreen.set_pressed_no_signal(settings_draft.fullscreen)
	settings_speed.set_value_no_signal(settings_draft.camera_speed)
	settings_speed_label.text = "Скорость камеры: %d ед./с" % int(settings_speed.value)
	for action in settings_key_buttons:
		_refresh_settings_key(action)
	settings_status.text = ""
	_select_settings_section(0)
	_show(Screen.SETTINGS)


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
	development_button.disabled = start_button.disabled
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
	_text(race_details, race.name, 26)
	_text(race_details, race.description, 18)
	_text(race_details, "Сильные стороны", 22)
	_text(race_details, race.strengths, 18)
	_text(race_details, "Слабые стороны", 22)
	_text(race_details, race.weaknesses, 18)

func _build_development_page() -> void:
	var page := _page(Screen.DEVELOPMENT, "Развитие")
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	development_title = _text(page, "", 24)
	_text(page, "Демонстрационные ветки. Выбор действует до закрытия игры и не влияет на миссию.", 18)
	development_tree = Control.new()
	development_tree.custom_minimum_size = Vector2(520, 340)
	development_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	development_tree.draw.connect(_draw_development_branches)
	development_tree.resized.connect(development_tree.queue_redraw)
	page.add_child(development_tree)
	development_status = _text(page, "", 18)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	page.add_child(footer)
	_button(footer, "Назад", func(): _show(Screen.RACES)).custom_minimum_size.x = 240
	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(left_spacer)
	reset_development_button = _button(footer, "↶", _reset_development)
	reset_development_button.tooltip_text = "Сбросить выбор"
	reset_development_button.custom_minimum_size.x = 64
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(right_spacer)
	apply_development_button = _button(footer, "Применить", _apply_development)
	apply_development_button.custom_minimum_size.x = 240

func _open_development() -> void:
	if screen != Screen.RACES or development_button.disabled: return
	var race: Dictionary = CATALOG.RACES[selected_race]
	development_title.text = race.name
	development_items.clear()
	_clear_children(development_tree)
	development_branches = race.development
	var base := PanelContainer.new()
	base.add_theme_stylebox_override("panel",
		DARK_THEME.surface(Color("2a171e"), DARK_THEME.ACCENT, 8))
	_place_development_node(base, Vector2(0.5, 0.85))
	var base_label := _text(base, "Базовая форма", 18)
	base_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var applied: PackedStringArray = applied_development.get(selected_race, PackedStringArray())
	for node in development_branches:
		var item := Button.new()
		item.text = node.name
		item.toggle_mode = true
		item.set_pressed_no_signal(node.id in applied)
		item.toggled.connect(func(_pressed: bool): _refresh_development_selection())
		item.add_theme_font_size_override("font_size", 18)
		_place_development_node(item, node.position)
		development_items[node.id] = item
	_refresh_development_selection()
	_show(Screen.DEVELOPMENT)

func _place_development_node(control: Control, position_ratio: Vector2) -> void:
	development_tree.add_child(control)
	control.anchor_left = position_ratio.x
	control.anchor_right = position_ratio.x
	control.anchor_top = position_ratio.y
	control.anchor_bottom = position_ratio.y
	control.offset_left = -96
	control.offset_right = 96
	control.offset_top = -24
	control.offset_bottom = 24

func _draw_development_branches() -> void:
	var area := Rect2(Vector2.ZERO, development_tree.size)
	development_tree.draw_rect(area, DARK_THEME.INK)
	development_tree.draw_rect(area.grow(-0.5), DARK_THEME.EDGE, false, 1.0)
	var centers := {"": Vector2(0.5, 0.85) * area.size}
	for node in development_branches:
		var start: Vector2 = centers[node.get("parent", "")]
		var end: Vector2 = node.position * area.size
		centers[node.id] = end
		var bend := Vector2(start.x, lerpf(start.y, end.y, 0.76))
		var points := PackedVector2Array()
		for step in range(17):
			var weight := step / 16.0
			points.append(start.lerp(bend, weight).lerp(bend.lerp(end, weight), weight))
		development_tree.draw_polyline(points, Color("20171b"), 8, true)
		var active := development_items[node.id].button_pressed
		development_tree.draw_polyline(points, Color("ce6373") if active else DARK_THEME.EDGE, 3, true)

func _refresh_development_selection() -> void:
	var selection := PackedStringArray()
	for node in development_branches:
		var item := development_items[node.id]
		var parent: Button = development_items.get(node.get("parent", ""))
		item.disabled = parent != null and not parent.button_pressed
		if item.disabled:
			item.set_pressed_no_signal(false)
		item.tooltip_text = "Сначала выберите «%s»" % parent.text if item.disabled else ""
		if item.button_pressed:
			selection.append(node.id)
	development_tree.queue_redraw()
	var applied: PackedStringArray = applied_development.get(selected_race, PackedStringArray())
	reset_development_button.disabled = selection.is_empty()
	apply_development_button.disabled = selection == applied
	development_status.text = "Выбрано узлов: %d" % selection.size()
	if not apply_development_button.disabled:
		development_status.text += " · Есть неприменённые изменения"

func _reset_development() -> void:
	for item in development_items.values():
		item.set_pressed_no_signal(false)
	_refresh_development_selection()

func _apply_development() -> void:
	if screen != Screen.DEVELOPMENT or apply_development_button.disabled: return
	var selection := PackedStringArray()
	for id in development_items:
		if development_items[id].button_pressed:
			selection.append(id)
	applied_development[selected_race] = selection
	_refresh_development_selection()
	development_status.text += " · Изменения применены"

func _update_developer_button() -> void:
	developer_button.tooltip_text = "Выключить режим разработки" if developer_mode else "Включить режим разработки"
	developer_button.add_theme_color_override("font_color",
		DARK_THEME.HEADING if developer_mode else DARK_THEME.MUTED)
	if developer_mode:
		developer_button.add_theme_stylebox_override("normal",
			developer_button.get_theme_stylebox("pressed"))
	else:
		developer_button.remove_theme_stylebox_override("normal")

func _start_mission() -> void:
	if screen != Screen.RACES or not CATALOG.MISSIONS.has(selected_mission): return
	if not CATALOG.MISSIONS[selected_mission].races.has(selected_race): return
	# Single loading point for all mission scenes. Current content supports Zombie.
	var packed := load(CATALOG.MISSIONS[selected_mission].scene) as PackedScene
	if packed == null: return
	mission = packed.instantiate()
	mission.set_meta("developer_mode", developer_mode)
	mission.process_mode = Node.PROCESS_MODE_PAUSABLE
	mission.set_meta("race_id", selected_race)
	mission.mission_finished.connect(_on_mission_finished)
	mission.pause_requested.connect(_pause)
	add_child(mission)
	mission.get_node("Camera2D").move_speed = settings.camera_speed
	get_tree().paused = false
	_show(Screen.GAMEPLAY)

func _pause() -> void:
	mission.cancel_selection()
	mission.cancel_order_preview()
	get_tree().paused = true
	_show(Screen.PAUSE)

func _resume() -> void:
	if is_instance_valid(mission):
		mission.get_node("Camera2D").move_speed = settings.camera_speed
	get_tree().paused = false
	_show(Screen.GAMEPLAY)

func _restart_mission() -> void:
	if screen != Screen.PAUSE: return
	_dispose_mission()
	_show(Screen.RACES)
	_start_mission()

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
	if outcome != "victory" or screen not in [Screen.GAMEPLAY, Screen.PAUSE, Screen.CONFIRM_LEAVE]: return
	mission.cancel_selection()
	mission.cancel_order_preview()
	mission.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	result_text.text = "Победа — %s\nЖителей: %d\nЗаражено: %d\nУбито: %d" % [
		CATALOG.MISSIONS[selected_mission].name, summary.total, summary.infected, summary.killed]
	_show(Screen.RESULTS)

func _exit_tree() -> void:
	get_tree().paused = false
