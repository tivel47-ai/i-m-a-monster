extends Control

var mission: Node2D
var objective_label: Label
var alert_label: Label
var monster_button: Button
var _refresh_elapsed := 0.0
var _blocks: Array[Control] = []


func _ready() -> void:
	mission = get_parent().get_parent() as Node2D
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
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
	_label(commands, "Команды монстрам", 16)


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


func _available_zombies() -> Array[Node]:
	var units: Array[Node] = []
	for unit in get_tree().get_nodes_in_group("player_units"):
		if mission.is_ancestor_of(unit) and not unit.is_dead:
			units.append(unit)
	return units


func _select_all_zombies() -> void:
	mission._apply_selection(_available_zombies())


func is_pointer_over_ui(point: Vector2) -> bool:
	for block in _blocks:
		if block.get_global_rect().has_point(point): return true
	return false
