extends Control

var mission: Node2D
var objective_label: Label
var alert_label: Label
var monster_button: Button
var building_button: Button
var _refresh_elapsed := 0.0
var _blocks: Array[Control] = []
var developer_button: Button
var developer_panel: PanelContainer
var developer_tool_label: Label


func _ready() -> void:
	mission = get_parent().get_parent() as Node2D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_build_developer_tools()
	_refresh()


func _panel(left: float, top: float, right: float, bottom: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = left
	panel.anchor_top = top
	panel.anchor_right = right
	panel.anchor_bottom = bottom
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = -8
	panel.offset_bottom = -8
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.10, 0.85)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_blocks.append(panel)
	return panel


func _label(parent: Node, value: String, size := 16) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _build() -> void:
	var objective := _panel(0.0, 0.0, 0.20, 0.13)
	objective_label = _label(objective, "", 14)

	var alert := _panel(0.32, 0.0, 0.73, 0.065)
	alert_label = _label(alert, "", 15)
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var gear := _panel(0.91, 0.0, 1.0, 0.075)
	var pause_button := Button.new()
	pause_button.text = "⚙ Пауза"
	pause_button.tooltip_text = "Открыть меню паузы"
	pause_button.pressed.connect(func(): mission.pause_requested.emit())
	gear.add_child(pause_button)

	var army := _panel(0.0, 0.86, 0.18, 1.0)
	var army_box := VBoxContainer.new()
	army.add_child(army_box)
	_label(army_box, "Монстры", 18)
	monster_button = Button.new()
	monster_button.text = "Зомби × 0"
	monster_button.tooltip_text = "Выбрать всех доступных зомби"
	monster_button.pressed.connect(_select_all_zombies)
	army_box.add_child(monster_button)

	var abilities := _panel(0.32, 0.90, 0.73, 1.0)
	_label(abilities, "Способности", 16)
	var commands := _panel(0.80, 0.88, 1.0, 1.0)
	var orders := VBoxContainer.new()
	commands.add_child(orders)
	_label(orders, "Команды монстрам", 16)
	building_button = Button.new()
	building_button.text = "Штурм здания"
	building_button.tooltip_text = "Выберите зомби, затем укажите здание на карте"
	building_button.pressed.connect(mission.toggle_building_order)
	orders.add_child(building_button)

func _build_developer_tools() -> void:
	developer_button = Button.new()
	developer_button.text = "Инструменты"
	developer_button.anchor_left = 1.0
	developer_button.anchor_right = 1.0
	developer_button.offset_left = -160
	developer_button.offset_right = -8
	developer_button.offset_top = 70
	developer_button.offset_bottom = 105
	developer_button.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(developer_button)
	_blocks.append(developer_button)
	developer_panel = _panel(0.78, 0.16, 1.0, 0.55)
	developer_panel.visible = false
	var box := VBoxContainer.new()
	developer_panel.add_child(box)
	_label(box, "Режим разработки", 17)
	var resident := Button.new()
	resident.text = "Создать жителя"
	resident.pressed.connect(func(): _choose_developer_tool("resident"))
	box.add_child(resident)
	var zombie := Button.new()
	zombie.text = "Создать зомби"
	zombie.pressed.connect(func(): _choose_developer_tool("zombie"))
	box.add_child(zombie)
	if mission.developer_guard_spawn_enabled:
		var guard := Button.new()
		guard.text = "Создать стражника"
		guard.pressed.connect(func(): _choose_developer_tool("guard"))
		box.add_child(guard)
	developer_tool_label = _label(box, "Щёлкните по карте для создания", 13)
	var stop := Button.new()
	stop.text = "Отменить создание"
	stop.pressed.connect(func(): _choose_developer_tool(""))
	box.add_child(stop)
	_label(box, "Этап оповещения", 14)
	var stages := OptionButton.new()
	for stage in ["Спокойствие", "Подозрение", "Тревога", "Организованная оборона"]:
		stages.add_item(stage)
	stages.select(mission.get_node("VillageAlert").level)
	stages.item_selected.connect(func(index: int):
		if mission.developer_mode:
			mission.get_node("VillageAlert").set_debug_level(index))
	mission.get_node("VillageAlert").level_changed.connect(func(_previous: int, current: int): stages.select(current))
	box.add_child(stages)
	developer_button.pressed.connect(func():
		developer_panel.visible = not developer_panel.visible
		if not developer_panel.visible: _choose_developer_tool(""))

func set_developer_mode(enabled: bool) -> void:
	developer_button.visible = enabled
	developer_panel.visible = false
	if not enabled: _choose_developer_tool("")

func _choose_developer_tool(kind: String) -> void:
	if not kind.is_empty():
		mission.cancel_order_preview()
	mission.developer_spawn = kind
	refresh_developer_tool()

func refresh_developer_tool() -> void:
	var names := {"resident": "житель", "zombie": "зомби", "guard": "стражник"}
	var tool_name: String = names.get(mission.developer_spawn, "")
	developer_tool_label.text = "Инструмент: %s (ПКМ — отмена)" % tool_name if not tool_name.is_empty() else "Выберите инструмент"


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(mission): return
	var counted: int = mission.infected_residents + mission.killed_residents
	var required: int = ceili(float(mission.total_residents * mission.TARGET_PERCENT) / 100.0)
	objective_label.text = "Цель: %d из %d жителей\nЗаражено: %d  Убито: %d\nПрогресс: %d / %d" % [
		required, mission.total_residents, mission.infected_residents,
		mission.killed_residents, counted, required]
	var alert: Node = mission.get_node("VillageAlert")
	var stages := ["Спокойствие", "Подозрение", "Тревога", "Организованная оборона"]
	alert_label.text = "Деревня: %s" % stages[alert.level]
	if alert.level == alert.Level.ALARM:
		alert_label.text += "  •  Опасность %.0f / %.0f" % [alert.danger, alert.danger_threshold]
	refresh_units()


func refresh_units() -> void:
	if not is_instance_valid(mission) or not is_instance_valid(monster_button): return
	var units := _available_zombies()
	monster_button.text = "Зомби × %d" % units.size()
	monster_button.disabled = units.is_empty()
	monster_button.set_pressed_no_signal(not units.is_empty() and units.all(func(unit): return unit.is_selected))
	building_button.text = "Укажите здание" if mission.choosing_building else "Штурм здания"
	building_button.disabled = mission.buildings.is_empty() or mission._command_units().is_empty()


func _available_zombies() -> Array[Node]:
	var units: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if mission.is_ancestor_of(unit) and unit.can_receive_player_orders():
			units.append(unit)
	return units


func _select_all_zombies() -> void:
	mission._apply_selection(_available_zombies())


func is_pointer_over_ui(point: Vector2) -> bool:
	for block in _blocks:
		if block.visible and block.get_global_rect().has_point(point): return true
	return false
