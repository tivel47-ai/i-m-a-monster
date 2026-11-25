extends Node

const CATALOG = preload("res://scripts/mission_catalog.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
const MISSION_PREVIEW = preload("res://scripts/mission_preview.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const DEVELOPMENT = preload("res://scripts/zombie_development.gd")
const MENU_BACKGROUND = preload("res://assets/ui/undead_menu_background.png")
const WORDMARK = preload("res://assets/ui/monster_wordmark.png")
const RESET_HOLD_SECONDS := 2.0
const RESET_MESSAGE_WIDTH := 580
const RESET_BUTTON_HEIGHT := 44
const RESET_WARNING := "Будут сброшены результаты миссий, статистика, развитие, назначения способностей и ресурсы. Это действие необратимо.\n\nУдерживайте «Подтвердить» левой кнопкой мыши 2 секунды."
enum Screen { MAIN, SETTINGS, MISSIONS, RACES, GAMEPLAY, PAUSE, CONFIRM_LEAVE, RESULTS, DEVELOPMENT, ATTEMPT_SUMMARY }
var screen: Screen = Screen.MAIN
var selected_mission := ""
var selected_race := ""
var mission: Node2D
var settings = SETTINGS.new()
var pages: Dictionary = {}
var ui: Control
var menu_background: TextureRect
var race_list: VBoxContainer
var race_preview: Panel
var _race_preview_appearances: Array[int] = []
var race_details: VBoxContainer
var race_buttons: Dictionary = {}
var race_mission_label: Label
var race_back_button: Button
var start_button: Button
var development_button: Button
var progression: PROGRESSION
var development: DEVELOPMENT
var finish_mission_button: Button
var result_text: Label
var attempt_text: Label
var leave_text: Label
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
var mission_menu: MenuButton
var mission_details: VBoxContainer
var mission_title: Label
var mission_description: Label
var mission_objectives: Label
var mission_preview: Control
var choose_race_button: Button
var developer_mode := false
var developer_button: Button
var progress_reset_dialog: AcceptDialog
var progress_reset_message: Label
var progress_reset_confirm: Button
var progress_reset_fill: ProgressBar
var progress_reset_elapsed := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_settings()
	progression = PROGRESSION.new(get_meta("progression_path", PROGRESSION.SAVE_PATH))
	_build_ui()
	_show(Screen.MAIN)

func _input(event: InputEvent) -> void:
	if screen == Screen.SETTINGS and not settings_capture.is_empty() and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			_capture_settings_key(event)
		return
	if screen == Screen.GAMEPLAY and is_instance_valid(mission) and event is InputEventKey:
		if event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			if event.pressed and not event.echo:
				mission.toggle_tactical_pause()
			return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		if progress_reset_dialog.visible:
			progress_reset_dialog.hide()
			return
		if screen == Screen.GAMEPLAY and is_instance_valid(mission):
			if mission.cancel_hunger_targeting() or mission.cancel_order_preview():
				return
		match screen:
			Screen.SETTINGS: _show(settings_return_screen)
			Screen.MISSIONS:
				if mission_menu.get_popup().visible:
					mission_menu.get_popup().hide()
				else:
					_show(Screen.MAIN)
			Screen.RACES: _show(Screen.MISSIONS)
			Screen.DEVELOPMENT: development.request_exit()
			Screen.GAMEPLAY: _pause()
			Screen.PAUSE: _resume()
			Screen.CONFIRM_LEAVE: _show(Screen.PAUSE)
			Screen.ATTEMPT_SUMMARY: _show(Screen.MAIN)
		return
	if screen == Screen.GAMEPLAY and is_instance_valid(mission) and mission.tactical_pause:
		mission._input(event)

func _process(delta: float) -> void:
	if screen == Screen.GAMEPLAY and is_instance_valid(mission) and mission.tactical_pause:
		mission._process(delta)
	if progress_reset_elapsed < 0.0:
		return
	progress_reset_elapsed += delta
	progress_reset_fill.value = progress_reset_elapsed
	if progress_reset_elapsed >= RESET_HOLD_SECONDS:
		_cancel_progress_reset_hold()
		_confirm_progress_reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(progress_reset_fill):
		_cancel_progress_reset_hold()

func _show(next: Screen) -> void:
	if screen == Screen.SETTINGS and next != Screen.SETTINGS:
		_end_settings_capture()
		settings_draft = null
	if screen == Screen.MISSIONS and next != Screen.MISSIONS:
		mission_menu.get_popup().hide()
	var returning_from_development := screen == Screen.DEVELOPMENT and next == Screen.RACES
	if screen != Screen.RACES and next == Screen.RACES and CATALOG.MISSIONS.has(selected_mission):
		_roll_race_preview_appearances()
		_update_preview()
	screen = next
	finish_mission_button.visible = screen == Screen.PAUSE and is_instance_valid(mission) and mission.can_finish_mission()
	for key in pages:
		pages[key].visible = key == screen
	ui.visible = screen != Screen.GAMEPLAY
	menu_background.modulate = Color.WHITE if screen == Screen.MAIN else Color(0.42, 0.42, 0.42)
	if is_instance_valid(developer_button): developer_button.visible = screen == Screen.MAIN
	if ui.visible:
		var preferred_button: Button
		if screen == Screen.DEVELOPMENT:
			preferred_button = development.back_button
		elif screen == Screen.MISSIONS:
			preferred_button = mission_menu
		elif returning_from_development:
			preferred_button = development_button
		_focus_page(screen, preferred_button)

func _focus_page(page: Screen, preferred_button: Button) -> void:
	# Wait for container layout before focus tries to reveal the first button.
	await get_tree().process_frame
	if screen == page:
		if is_instance_valid(preferred_button):
			preferred_button.grab_focus()
		else:
			var buttons: Array[Node] = pages[page].find_children("*", "Button", true, false)
			for button in buttons:
				if button.is_visible_in_tree() and not button.disabled:
					button.grab_focus()
					break
		await get_tree().process_frame
	if screen == page and pages[page] is ScrollContainer:
		pages[page].scroll_vertical = 0

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = DARK_THEME.ACTION_BUTTON_SIZE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _text(parent: Node, value: String, font_size := DARK_THEME.BODY_SIZE, color := DARK_THEME.TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
		var heading := _text(box, title, DARK_THEME.TITLE_SIZE, DARK_THEME.HEADING)
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
	button.custom_minimum_size = DARK_THEME.ACTION_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", DARK_THEME.SECTION_SIZE)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui = Panel.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = DARK_THEME.build(DARK_THEME.BODY_SIZE, 8)
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
	_style_main_button(_button(main, "Сбросить прогресс", _open_progress_reset))
	_build_progress_reset_dialog()
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
	_build_mission_page()
	_build_race_page()
	_build_development_page()
	var pause := _page(Screen.PAUSE, "Пауза", true)
	_button(pause, "Продолжить", func():
		if screen == Screen.PAUSE: _resume())
	finish_mission_button = _button(pause, "Завершить миссию", _finish_mission)
	_button(pause, "Перезапустить миссию", _restart_mission)
	_button(pause, "Настройки", func():
		if screen == Screen.PAUSE: _open_settings(Screen.PAUSE))
	_button(pause, "В главное меню", func():
		if screen == Screen.PAUSE: _show(Screen.CONFIRM_LEAVE))
	var confirm := _page(Screen.CONFIRM_LEAVE, "Покинуть миссию?", true)
	leave_text = _text(confirm, "")
	_button(confirm, "Остаться", func():
		if screen == Screen.CONFIRM_LEAVE: _show(Screen.PAUSE))
	_button(confirm, "Выйти", _leave_mission)
	var results := _page(Screen.RESULTS, "Итог миссии", true)
	result_text = _text(results, "")
	_button(results, "К выбору миссии", func():
		if screen == Screen.RESULTS:
			_dispose_mission()
			_show(Screen.MISSIONS))
	var attempt := _page(Screen.ATTEMPT_SUMMARY, "Попытка завершена", true)
	attempt_text = _text(attempt, "")
	_button(attempt, "В главное меню", func(): _show(Screen.MAIN))

func _build_mission_page() -> void:
	var page := Control.new()
	ui.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages[Screen.MISSIONS] = page
	mission_preview = MISSION_PREVIEW.new()
	mission_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(mission_preview)
	mission_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	page.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var layout := VBoxContainer.new()
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	mission_title = _text(header, "", DARK_THEME.TITLE_SIZE, DARK_THEME.TEXT)
	mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_title.add_theme_constant_override("outline_size", 5)
	mission_title.add_theme_color_override("font_outline_color", DARK_THEME.INK)

	mission_menu = MenuButton.new()
	mission_menu.text = "Выбор миссии"
	mission_menu.icon = mission_menu.get_theme_icon("arrow", "OptionButton")
	mission_menu.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mission_menu.custom_minimum_size = Vector2(236, 48)
	mission_menu.focus_mode = Control.FOCUS_ALL
	mission_menu.flat = false
	header.add_child(mission_menu)
	_style_mission_button(mission_menu, true)
	var popup := mission_menu.get_popup()
	popup.add_theme_constant_override("v_separation", 12)
	popup.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("151612"), Color("5d6541"), 8))
	popup.add_theme_stylebox_override("hover", DARK_THEME.surface(Color("343923"), Color("778249"), 4))
	for id in CATALOG.MISSIONS:
		popup.add_radio_check_item(CATALOG.MISSIONS[id].name)
		popup.set_item_metadata(popup.item_count - 1, id)
	popup.about_to_popup.connect(func():
		popup.set_deferred("size", Vector2i(ceili(mission_menu.size.x), 0)))
	popup.index_pressed.connect(func(index: int): _select_mission(popup.get_item_metadata(index)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	layout.add_child(footer)
	var back := _button(footer, "Назад", func(): _show(Screen.MAIN))
	back.custom_minimum_size = Vector2(138, 48)
	back.size_flags_vertical = Control.SIZE_SHRINK_END
	_style_mission_button(back, false)

	var details_slot := VBoxContainer.new()
	details_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(details_slot)
	mission_details = VBoxContainer.new()
	mission_details.add_theme_constant_override("separation", 3)
	details_slot.add_child(mission_details)
	mission_description = _text(mission_details, "")
	_text(mission_details, "Цель миссии", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	mission_objectives = _text(mission_details, "")
	mission_details.hide()

	choose_race_button = _button(footer, "Выбрать расу", _open_race_selection)
	choose_race_button.custom_minimum_size = Vector2(210, 48)
	choose_race_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_style_mission_button(choose_race_button, true)
	choose_race_button.disabled = true

func _style_mission_button(button: Button, emphasized: bool) -> void:
	var fill := Color("252919") if emphasized else Color("191819")
	var edge := Color("87924d") if emphasized else Color("524c40")
	button.add_theme_font_size_override("font_size", DARK_THEME.SECTION_SIZE)
	button.add_theme_stylebox_override("normal", DARK_THEME.surface(fill, edge, 10))
	button.add_theme_stylebox_override("hover", DARK_THEME.surface(fill.lightened(0.13), edge.lightened(0.2), 10))
	button.add_theme_stylebox_override("pressed", DARK_THEME.surface(fill.lightened(0.19), edge, 10))
	button.add_theme_stylebox_override("hover_pressed", DARK_THEME.surface(fill.lightened(0.19), edge, 10))
	var focus := DARK_THEME.surface(Color.TRANSPARENT, Color("a7aa71"), 10)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)

func _build_race_page() -> void:
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100c10"), DARK_THEME.EDGE, 1, 0))
	ui.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	pages[Screen.RACES] = page
	var races := VBoxContainer.new()
	races.add_theme_constant_override("separation", 4)
	page.add_child(races)
	race_mission_label = _text(races, "", DARK_THEME.TITLE_SIZE, DARK_THEME.HEADING)
	race_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_mission_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	race_mission_label.custom_minimum_size.y = 44
	var divider := ColorRect.new()
	divider.color = Color("52252e")
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	races.add_child(divider)
	var race_columns := HBoxContainer.new()
	race_columns.add_theme_constant_override("separation", 0)
	race_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	races.add_child(race_columns)
	var list_panel := PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100d10"), DARK_THEME.EDGE, 12, 0))
	list_panel.custom_minimum_size.x = 208
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 2.0
	race_columns.add_child(list_panel)
	var race_left := VBoxContainer.new()
	race_left.add_theme_constant_override("separation", 16)
	list_panel.add_child(race_left)
	_text(race_left, "Выбор расы", DARK_THEME.TITLE_SIZE, DARK_THEME.HEADING)
	var race_scroll := ScrollContainer.new()
	race_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	race_left.add_child(race_scroll)
	race_list = VBoxContainer.new()
	race_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_list.add_theme_constant_override("separation", 8)
	race_scroll.add_child(race_list)
	race_preview = Panel.new()
	race_preview.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("140f13"), DARK_THEME.EDGE, 0, 0))
	race_preview.custom_minimum_size.x = 240
	race_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_preview.size_flags_stretch_ratio = 4.8
	race_preview.clip_contents = true
	race_columns.add_child(race_preview)
	var details_panel := PanelContainer.new()
	details_panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100d10"), DARK_THEME.EDGE, 18, 0))
	details_panel.custom_minimum_size.x = 266
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_stretch_ratio = 3.2
	race_columns.add_child(details_panel)
	var details_scroll := ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_panel.add_child(details_scroll)
	race_details = VBoxContainer.new()
	race_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_details.add_theme_constant_override("separation", 12)
	details_scroll.add_child(race_details)
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100d10"), DARK_THEME.EDGE, 10, 0))
	races.add_child(footer_panel)
	var race_footer := HBoxContainer.new()
	race_footer.add_theme_constant_override("separation", 24)
	footer_panel.add_child(race_footer)
	race_back_button = _button(race_footer, "Назад", func(): _show(Screen.MISSIONS))
	development_button = _button(race_footer, "Развитие", _open_development)
	development_button.disabled = true
	start_button = _button(race_footer, "Начать миссию", _start_mission)
	start_button.disabled = true
	start_button.add_theme_stylebox_override("normal", DARK_THEME.surface(Color("391820"), DARK_THEME.ACCENT, 8))
	start_button.add_theme_stylebox_override("hover", DARK_THEME.surface(Color("47202a"), Color("c75a6a"), 8))
	for button in [race_back_button, development_button, start_button]:
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", DARK_THEME.SECTION_SIZE)

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

	settings_status = _text(options, "", DARK_THEME.HINT_SIZE, DARK_THEME.MUTED)
	settings_status.custom_minimum_size.y = 26
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	options.add_child(footer)
	_button(footer, "Назад", func(): _show(settings_return_screen)).custom_minimum_size = DARK_THEME.ACTION_BUTTON_SIZE
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_button(footer, "Применить", _apply_settings).custom_minimum_size = DARK_THEME.ACTION_BUTTON_SIZE


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
	_text(box, "Нажмите на кнопку справа и выберите новую клавишу.", DARK_THEME.HINT_SIZE, DARK_THEME.MUTED)
	var actions := SETTINGS.DEFAULT_KEYS.keys()
	for index in labels.size():
		_add_settings_key_row(box, actions[index], labels[index])
	_text(box, "Команды монстрам", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	for action: String in SETTINGS.MONSTER_COMMANDS:
		_add_settings_key_row(box, action, SETTINGS.MONSTER_COMMANDS[action].title)
	_text(box, "Слоты дополнительных способностей (пока пусты)", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	for index in range(labels.size(), actions.size()):
		_add_settings_key_row(box, actions[index], "Слот %d" % (index - labels.size() + 1))


func _add_settings_key_row(box: VBoxContainer, action: String, title: String) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	_text(row, title).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := _button(row, "", _begin_settings_capture.bind(action))
	button.custom_minimum_size = Vector2(150, 40)
	settings_key_buttons[action] = button


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
	if key == KEY_NONE:
		settings_key_buttons[action].text = "Не назначена"
		return
	var display_key := key
	if not SETTINGS.MONSTER_COMMANDS.has(action) and DisplayServer.get_name() != "headless":
		display_key = DisplayServer.keyboard_get_keycode_from_physical(key)
	settings_key_buttons[action].text = OS.get_keycode_string(display_key if display_key != KEY_NONE else key)


func _capture_settings_key(event: InputEventKey) -> void:
	if event.is_action_pressed("ui_cancel"):
		_end_settings_capture()
		return
	var key := event.physical_keycode
	if key == KEY_SPACE:
		settings_status.text = "Пробел зарезервирован для тактической паузы."
		return
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


func _build_progress_reset_dialog() -> void:
	progress_reset_dialog = AcceptDialog.new()
	progress_reset_dialog.title = "Сбросить прогресс?"
	progress_reset_dialog.theme = ui.theme
	progress_reset_dialog.ok_button_text = "Отмена"
	progress_reset_dialog.add_theme_constant_override("buttons_min_height", RESET_BUTTON_HEIGHT)
	progress_reset_message = DARK_THEME.build_fixed_dialog(progress_reset_dialog, progress_reset_dialog.get_ok_button())
	progress_reset_message.custom_minimum_size.x = RESET_MESSAGE_WIDTH
	progress_reset_message.custom_maximum_size.x = RESET_MESSAGE_WIDTH
	progress_reset_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_reset_dialog.visibility_changed.connect(_cancel_progress_reset_hold)
	progress_reset_dialog.focus_exited.connect(_cancel_progress_reset_hold)
	ui.add_child(progress_reset_dialog)
	progress_reset_confirm = progress_reset_dialog.add_button("Подтвердить", false, "hold")
	progress_reset_confirm.focus_mode = Control.FOCUS_NONE
	# AcceptDialog applies its button height after calculating the initial popup position.
	progress_reset_confirm.custom_minimum_size.y = RESET_BUTTON_HEIGHT
	progress_reset_confirm.gui_input.connect(_progress_reset_input)
	progress_reset_confirm.mouse_exited.connect(_cancel_progress_reset_hold)
	progress_reset_confirm.button_up.connect(_cancel_progress_reset_hold)
	progress_reset_fill = ProgressBar.new()
	progress_reset_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_reset_fill.show_percentage = false
	progress_reset_fill.max_value = RESET_HOLD_SECONDS
	progress_reset_fill.step = 0.0
	progress_reset_fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	progress_reset_fill.add_theme_stylebox_override("fill", DARK_THEME.surface(Color("a53c4a80"), Color.TRANSPARENT, 0))
	progress_reset_confirm.add_child(progress_reset_fill)
	progress_reset_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _open_progress_reset() -> void:
	if screen != Screen.MAIN:
		return
	progress_reset_message.text = RESET_WARNING
	progress_reset_dialog.popup_centered()

func _progress_reset_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and progress_reset_dialog.visible:
			progress_reset_elapsed = 0.0
		else:
			_cancel_progress_reset_hold()

func _cancel_progress_reset_hold() -> void:
	progress_reset_elapsed = -1.0
	if is_instance_valid(progress_reset_fill):
		progress_reset_fill.value = 0.0

func _confirm_progress_reset() -> void:
	if screen != Screen.MAIN or not progress_reset_dialog.visible:
		return
	if progression.reset_progress() != OK:
		progress_reset_message.text = "Не удалось сбросить прогресс. Попробуйте ещё раз.\n\n" + RESET_WARNING
		return
	progress_reset_dialog.hide()
	selected_mission = ""
	selected_race = ""
	developer_mode = false
	_update_developer_button()
	var popup := mission_menu.get_popup()
	for index in popup.item_count:
		popup.set_item_checked(index, false)
	choose_race_button.disabled = true
	mission_title.text = ""
	mission_description.text = ""
	mission_objectives.text = ""
	mission_details.hide()
	mission_preview.clear_mission()
	result_text.text = ""
	attempt_text.text = ""
	development.draft = null
	development_button.disabled = true
	development_button.tooltip_text = ""
	start_button.disabled = true
	_focus_page(Screen.MAIN, null)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _select_mission(id: String) -> void:
	if screen != Screen.MISSIONS or not CATALOG.MISSIONS.has(id):
		return
	var popup := mission_menu.get_popup()
	popup.hide()
	if selected_mission == id:
		return
	selected_race = ""
	selected_mission = id
	for index in popup.item_count:
		popup.set_item_checked(index, popup.get_item_metadata(index) == id)
	var definition: Dictionary = CATALOG.MISSIONS[id]
	mission_title.text = definition.name
	mission_description.text = definition.description
	mission_objectives.text = definition.objectives
	mission_details.show()
	mission_preview.show_mission(definition.scene, definition.get("preview", ""))
	choose_race_button.disabled = false

func _open_race_selection() -> void:
	if screen != Screen.MISSIONS or not CATALOG.MISSIONS.has(selected_mission): return
	_clear_children(race_list)
	race_buttons.clear()
	for race_id in CATALOG.MISSIONS[selected_mission].races:
		var item := _button(race_list, CATALOG.RACES[race_id].name, _select_race.bind(race_id))
		item.custom_minimum_size = Vector2(0, 54)
		item.add_theme_font_size_override("font_size", DARK_THEME.SECTION_SIZE)
		item.toggle_mode = true
		race_buttons[race_id] = item
	_show(Screen.RACES)

func _select_race(id: String) -> void:
	if screen != Screen.RACES or not CATALOG.MISSIONS[selected_mission].races.has(id): return
	selected_race = id
	get_node("/root/RaceCursor").select_race(id)
	_update_preview()

func _roll_race_preview_appearances() -> void:
	var count := CATALOG.ORDINARY_ART.TURN.size()
	var front := CATALOG.ORDINARY_ART.random_appearance()
	if not _race_preview_appearances.is_empty() and front == _race_preview_appearances[0]:
		front = (front + randi_range(1, count - 1)) % count
	var background: Array[int] = []
	for appearance in range(count):
		if appearance != front:
			background.append(appearance)
	background.shuffle()
	_race_preview_appearances = [front, background[0], background[1]]

func _update_preview() -> void:
	_clear_children(race_preview)
	_clear_children(race_details)
	race_mission_label.text = CATALOG.MISSIONS[selected_mission].name
	for race_id in race_buttons:
		race_buttons[race_id].set_pressed_no_signal(race_id == selected_race)
	start_button.disabled = not CATALOG.RACES.has(selected_race)
	var mission_definition: Dictionary = CATALOG.MISSIONS[selected_mission]
	var has_progression: bool = mission_definition.get("zombie_progression", false)
	var unlocked: bool = selected_race == "zombie" and (developer_mode or progression.state.initial_unlocked)
	development_button.disabled = start_button.disabled or not has_progression or not unlocked
	development_button.tooltip_text = 'Чтобы разблокировать развитие, необходим ресурс "Заражение"' if selected_race == "zombie" and has_progression and not unlocked else ""
	var preview_race := selected_race
	if preview_race.is_empty() and mission_definition.races.size() == 1:
		preview_race = mission_definition.races[0]
	var race: Dictionary = CATALOG.RACES.get(preview_race, {})
	if race.has("preview"):
		var stage: Control = race.preview.new()
		stage.appearances = _race_preview_appearances
		race_preview.add_child(stage)
		stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var appearance_title := _text(race_preview, "Внешний вид", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	appearance_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	appearance_title.position.y = 16
	appearance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if race.is_empty():
		var hint := _text(race_preview, "Выберите расу в списке слева.", DARK_THEME.BODY_SIZE, DARK_THEME.MUTED)
		hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_text(race_details, "Описание", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
		_text(race_details, "Здесь появятся описание, сильные и слабые стороны выбранной расы.",
			DARK_THEME.HINT_SIZE, DARK_THEME.MUTED)
		return
	var race_title := _text(race_details, race.name, DARK_THEME.TITLE_SIZE, DARK_THEME.HEADING)
	race_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(race_details, race.description)
	_text(race_details, "Сильные стороны", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	_text(race_details, race.strengths)
	_text(race_details, "Слабые стороны", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	_text(race_details, race.weaknesses)
	_text(race_details, "Как играется", DARK_THEME.SECTION_SIZE, DARK_THEME.HEADING)
	_text(race_details, race.gameplay)

func _build_development_page() -> void:
	development = DEVELOPMENT.new()
	development.exit_requested.connect(func(): _show(Screen.RACES))
	ui.add_child(development)
	development.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	pages[Screen.DEVELOPMENT] = development


func _open_development() -> void:
	if screen != Screen.RACES or development_button.disabled:
		return
	_show(Screen.DEVELOPMENT)
	development.open(progression, settings.keys, developer_mode, settings.camera_speed)


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
	if CATALOG.MISSIONS[selected_mission].get("zombie_progression", false):
		mission.configure_progression(progression)
	mission.mission_finished.connect(_on_mission_finished)
	mission.pause_requested.connect(_pause)
	add_child(mission)
	mission.get_node("Camera2D").move_speed = settings.camera_speed
	get_tree().paused = false
	_show(Screen.GAMEPLAY)

func _pause() -> void:
	if screen != Screen.GAMEPLAY or not is_instance_valid(mission):
		return
	mission.cancel_selection()
	mission.cancel_order_preview()
	mission.set_menu_paused(true)
	leave_text.text = "Текущая попытка будет потеряна. Результат миссии не будет записан."
	if mission.mission_build != null:
		leave_text.text = "Текущая попытка завершится. Заработанный Вирус сохранится."
	_show(Screen.PAUSE)

func _resume() -> void:
	if is_instance_valid(mission):
		mission.get_node("Camera2D").move_speed = settings.camera_speed
		mission.mission_hud.refresh_metaprogression()
		mission.mission_hud.refresh_command_hotkeys()
		mission.set_menu_paused(false)
	_show(Screen.GAMEPLAY)

func _restart_mission() -> void:
	if screen != Screen.PAUSE: return
	_dispose_mission()
	_show(Screen.RACES)
	_start_mission()

func _finish_mission() -> void:
	if screen == Screen.PAUSE and is_instance_valid(mission) and mission.can_finish_mission():
		mission.finish_mission()

func _leave_mission() -> void:
	if screen != Screen.CONFIRM_LEAVE: return
	var show_summary: bool = mission.mission_build != null
	if show_summary:
		attempt_text.text = _virus_summary()
	_dispose_mission()
	_show(Screen.ATTEMPT_SUMMARY if show_summary else Screen.MAIN)


func _virus_summary() -> String:
	progression.flush()
	var summary := "Вирус за попытку: %d\nВсего Вируса: %d" % [
		mission.mission_build.virus_earned, progression.state.virus]
	if progression.save_error != OK:
		summary += "\nНе удалось записать профиль развития"
	if mission.mission_build.revealed_development:
		summary += "\nОткрыты улучшения зомби на экране «Развитие»"
	return summary

func _dispose_mission() -> void:
	progression.flush()
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
	mission.cancel_hunger_targeting()
	mission.set_menu_paused(true)
	mission.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	result_text.text = "Победа — %s\nЖителей: %d\nЗаражено: %d\nУбито: %d" % [
		CATALOG.MISSIONS[selected_mission].name, summary.total, summary.infected, summary.killed]
	if mission.mission_build != null:
		result_text.text += "\n" + _virus_summary()
	_show(Screen.RESULTS)

func _exit_tree() -> void:
	if progression != null:
		progression.flush()
	get_tree().paused = false
