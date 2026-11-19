extends Control

const INFECTION_ORB = preload("res://scripts/infection_orb.gdshader")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE = preload("res://scripts/zombie.gd")
const INFECTION_ORB_SIZE := 92.0

var mission: Node2D
var objective_label: Label
var victory_notice: CenterContainer
var alert_label: Label
var monster_button: Button
var monster_count: Label
var _monster_roster: VBoxContainer
var _monster_rows: Dictionary[String, Label] = {}
var building_button: Button
var global_cancel_button: Button
var assault_status: Label
var infection_button: Button
var infection_orb_material: ShaderMaterial
var infection_charges: Label
var virus_label: Label
var ability_slots: Array[Button] = []
var hunger_slot_key: Label
var hunger_slot_uses: Label
var ability_keys: Dictionary[int, Label] = {}
var ability_uses: Dictionary[int, Label] = {}
var _refresh_elapsed := 0.0
var _blocks: Array[Control] = []
var developer_button: Button
var developer_panel: PanelContainer
var developer_tool_label: Label


func _ready() -> void:
	mission = get_parent().get_parent() as Node2D
	if mission.dark_fantasy_hud:
		theme = DARK_THEME.build(16, 4)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_build_developer_tools()
	_refresh()
	if mission.can_finish_mission():
		show_victory_notice()


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
	var style: StyleBoxFlat
	if mission.dark_fantasy_hud:
		style = DARK_THEME.surface(Color("100c10e6"), DARK_THEME.EDGE, 8)
	else:
		style = StyleBoxFlat.new()
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
	if mission.manual_victory_finish:
		_build_victory_notice()

	var gear := _panel(0.91, 0.0, 1.0, 0.075)
	var pause_button := Button.new()
	pause_button.text = "⚙ Пауза"
	pause_button.tooltip_text = "Открыть меню паузы"
	pause_button.pressed.connect(func(): mission.pause_requested.emit())
	gear.add_child(pause_button)
	if mission.mission_build != null:
		_build_metaprogression()

	var army := _panel(0.0, 0.86, 0.18, 1.0)
	var army_box := VBoxContainer.new()
	army.add_child(army_box)
	if mission.horde_commands != null and mission.monster_roster_enabled:
		army.anchor_top = 1.0
		army.offset_top = army.offset_bottom
		army.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_monster_roster = army_box
		monster_count = _label(army_box, "Монстры: 0", 18)
	else:
		_label(army_box, "Монстры", 18)
		if mission.horde_commands != null:
			monster_count = _label(army_box, "Зомби × 0")
		else:
			monster_button = Button.new()
			monster_button.text = "Зомби × 0"
			monster_button.tooltip_text = "Выбрать всех доступных зомби"
			monster_button.pressed.connect(_select_all_zombies)
			army_box.add_child(monster_button)

	if mission.zombie_infection != null:
		_build_infection()
	if mission.mission_build == null:
		var abilities := _panel(0.32, 0.90, 0.73, 1.0)
		_label(abilities, "Способности", 16)
	var command_top := 0.77 if mission.horde_commands != null else 0.88
	var commands := _panel(0.80, command_top, 1.0, 1.0)
	var orders := VBoxContainer.new()
	commands.add_child(orders)
	_label(orders, "Команды монстрам", 16)
	building_button = Button.new()
	building_button.text = "Штурм здания"
	building_button.tooltip_text = "Выберите зомби, затем укажите здание на карте"
	building_button.pressed.connect(mission.toggle_building_order)
	orders.add_child(building_button)
	if mission.horde_commands != null:
		building_button.toggle_mode = true
		building_button.tooltip_text = "Удерживайте ПКМ на здании и отпустите для штурма. ЛКМ при удержании отменяет подготовку, в остальное время — режим."
		global_cancel_button = Button.new()
		global_cancel_button.text = "Отменить приказ орде"
		global_cancel_button.tooltip_text = "Отменить общий приказ и убрать сообщение о штурме"
		global_cancel_button.pressed.connect(mission.cancel_global_order)
		orders.add_child(global_cancel_button)
		assault_status = _label(orders, "", 14)


func _build_victory_notice() -> void:
	victory_notice = CenterContainer.new()
	victory_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(victory_notice)
	victory_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	victory_notice.offset_top = 64
	victory_notice.offset_bottom = 64
	victory_notice.hide()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100c10ed"), DARK_THEME.ACCENT, 14, 8))
	victory_notice.add_child(panel)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)
	var title := _label(text, "Победа! Цель миссии выполнена", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", DARK_THEME.HEADING)
	var hint := _label(text, "Завершить миссию можно в меню паузы")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_victory_notice() -> void:
	_refresh_objective()
	victory_notice.show()
	var fade := create_tween()
	fade.tween_interval(4.0)
	fade.tween_property(victory_notice, "modulate:a", 0.0, 0.4)
	fade.tween_callback(victory_notice.hide)


func _build_metaprogression() -> void:
	var virus := _panel(0.74, 0.0, 0.91, 0.075)
	virus_label = _label(virus, "", 16)
	var abilities := _panel(0.32, 0.90, 0.79, 1.0)
	var bar := HBoxContainer.new()
	abilities.add_child(bar)
	for index in PROGRESSION.SLOT_COUNT:
		var slot := Button.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.y = 36
		slot.add_theme_font_size_override("font_size", 14)
		slot.focus_mode = Control.FOCUS_NONE
		ability_slots.append(slot)
		bar.add_child(slot)
		var id: String = mission.mission_build.build.slots[index]
		if not id.is_empty():
			slot.icon = PROGRESSION.NODES[id].icon
			slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.expand_icon = true
			slot.add_theme_constant_override("icon_max_width", 28)
			slot.pressed.connect(mission.toggle_racial_targeting.bind(id))
			slot.toggle_mode = true
			var key_label := _label(slot, "", 11)
			key_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			key_label.offset_left = 4
			key_label.offset_right = -4
			key_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			key_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var uses_label := _label(slot, "", 13)
			uses_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			uses_label.offset_right = -4
			uses_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			uses_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			ability_keys[index] = key_label
			ability_uses[index] = uses_label
			if id == PROGRESSION.HUNGER:
				hunger_slot_key = key_label
				hunger_slot_uses = uses_label
	refresh_metaprogression()


func refresh_metaprogression() -> void:
	if not is_instance_valid(virus_label):
		return
	var runtime = mission.mission_build
	virus_label.text = "Вирус: %d" % mission.progression.state.virus
	virus_label.tooltip_text = "Ошибка сохранения профиля" if mission.progression.save_error != OK else ""
	virus_label.mouse_filter = Control.MOUSE_FILTER_PASS
	for index in ability_slots.size():
		var slot := ability_slots[index]
		var action := "ability_slot_%d" % (index + 1)
		var key := str((index + 1) % 10)
		if InputMap.has_action(action):
			var events := InputMap.action_get_events(action)
			if not events.is_empty() and events[0] is InputEventKey:
				key = OS.get_keycode_string(events[0].physical_keycode)
		var ability: String = runtime.build.slots[index]
		if ability.is_empty():
			slot.text = key
			slot.disabled = true
			continue
		ability_keys[index].text = key
		ability_uses[index].text = str(runtime.uses_for(ability))
		slot.disabled = runtime.uses_for(ability) == 0
		slot.tooltip_text = "%s · %s\n%s" % [PROGRESSION.NODES[ability].title, key,
			PROGRESSION.effect_text(ability, PROGRESSION.level(runtime.build, ability))]
		slot.set_pressed_no_signal(runtime.targeting and runtime.active_ability == ability)


func _build_infection() -> void:
	infection_button = Button.new()
	infection_button.focus_mode = Control.FOCUS_NONE
	infection_button.name = "InfectionButton"
	infection_button.toggle_mode = true
	infection_button.anchor_left = 0.25
	infection_button.anchor_right = 0.25
	infection_button.anchor_top = 1.0
	infection_button.anchor_bottom = 1.0
	infection_button.offset_left = -INFECTION_ORB_SIZE * 0.5
	infection_button.offset_right = INFECTION_ORB_SIZE * 0.5
	infection_button.offset_top = -122
	infection_button.offset_bottom = -8
	infection_button.tooltip_text = "Инфицирование\nЛКМ по жителю или зданию · ПКМ отменяет наведение"
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		infection_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(infection_button)
	_blocks.append(infection_button)

	var orb := ColorRect.new()
	orb.size = Vector2.ONE * INFECTION_ORB_SIZE
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	infection_orb_material = ShaderMaterial.new()
	infection_orb_material.shader = INFECTION_ORB
	orb.material = infection_orb_material
	infection_button.add_child(orb)

	infection_charges = _label(infection_button, "", 16)
	infection_charges.position.y = INFECTION_ORB_SIZE - 1
	infection_charges.size.x = INFECTION_ORB_SIZE
	infection_charges.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	infection_charges.add_theme_color_override("font_color", Color("e3efcd"))
	infection_charges.add_theme_color_override("font_outline_color", Color("142417"))
	infection_charges.add_theme_constant_override("outline_size", 6)

	infection_button.pressed.connect(mission.toggle_infection_targeting)
	infection_button.mouse_entered.connect(_refresh_infection_highlight)
	infection_button.mouse_exited.connect(_refresh_infection_highlight)
	infection_button.focus_entered.connect(_refresh_infection_highlight)
	infection_button.focus_exited.connect(_refresh_infection_highlight)
	refresh_infection()


func _refresh_infection_highlight() -> void:
	infection_orb_material.set_shader_parameter("highlighted",
		infection_button.has_focus() or infection_button.is_hovered())


func refresh_infection() -> void:
	if infection_button == null:
		return
	var ability = mission.zombie_infection
	infection_charges.text = str(ability.charges)
	infection_button.disabled = ability.charges == 0
	infection_button.set_pressed_no_signal(ability.targeting)
	infection_orb_material.set_shader_parameter("fill_level",
		float(ability.recovery_progress) / mission.ZOMBIE_INFECTION.KILLS_PER_CHARGE)
	infection_orb_material.set_shader_parameter("available", not infection_button.disabled)
	infection_orb_material.set_shader_parameter("targeting", ability.targeting)


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
		mission.cancel_infection_targeting()
		mission.cancel_hunger_targeting()
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
	_refresh_objective()
	var alert: Node = mission.get_node("VillageAlert")
	var stages := ["Спокойствие", "Подозрение", "Тревога", "Организованная оборона"]
	alert_label.text = "Деревня: %s" % stages[alert.level]
	if alert.level == alert.Level.ALARM:
		alert_label.text += "  •  Опасность %.0f / %.0f" % [alert.danger, alert.danger_threshold]
	refresh_units()


func _refresh_objective() -> void:
	var counted: int = mission.infected_residents + mission.killed_residents
	var required: int = ceili(float(mission.total_residents * mission.TARGET_PERCENT) / 100.0)
	objective_label.text = "Цель: %d из %d жителей\nЗаражено: %d  Убито: %d\nПрогресс: %d / %d" % [
		required, mission.total_residents, mission.infected_residents,
		mission.killed_residents, counted, required]
	if mission.can_finish_mission():
		objective_label.text += "\nПобеда"


func refresh_units() -> void:
	if not is_instance_valid(mission):
		return
	if mission.horde_commands != null:
		if _monster_roster != null:
			_refresh_monster_roster(mission._owned_zombies())
		elif mission.horde_commands.assault_quantity == 0:
			monster_count.text = "Зомби × %d" % mission._owned_zombies().size()
		refresh_commands()
		return
	var units := _available_zombies()
	monster_button.text = "Зомби × %d" % units.size()
	monster_button.disabled = units.is_empty()
	monster_button.set_pressed_no_signal(not units.is_empty() and units.all(func(unit): return unit.is_selected))
	building_button.text = "Укажите здание" if mission.choosing_building else "Штурм здания"
	building_button.disabled = mission.buildings.is_empty() or mission._command_units().is_empty()


func _refresh_monster_roster(units: Array[Node]) -> void:
	var counts: Dictionary[String, int] = {}
	for unit in units:
		var form: String = unit.zombie_form
		counts[form] = counts.get(form, 0) + 1
		if not _monster_rows.has(form):
			_add_monster_row(form, unit.get_node("Polygon2D"))
	monster_count.text = "Монстры: %d" % units.size()
	for form in _monster_rows:
		_monster_rows[form].text = "× %d" % counts.get(form, 0)


func _add_monster_row(form: String, body: Polygon2D) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_roster.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var polygon := body.polygon
	var color := body.color
	icon.draw.connect(func():
		icon.draw_set_transform(icon.size * 0.5, 0.0, Vector2.ONE * 1.15)
		ZOMBIE.draw_form_marker(icon, form)
		icon.draw_colored_polygon(polygon, color))
	var title: String = "Зомби" if form.is_empty() else PROGRESSION.NODES[form].title
	var name_label := _label(row, title)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := _label(row, "× 0")
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	_monster_rows[form] = count


func refresh_commands() -> void:
	if mission.horde_commands == null:
		return
	var horde = mission.horde_commands
	var active: bool = mission.is_gameplay_active()
	building_button.disabled = not active or mission.buildings.is_empty()
	building_button.set_pressed_no_signal(mission.choosing_building)
	global_cancel_button.disabled = not active or (
		horde.order == horde.Order.NONE and horde.assault_feedback.is_empty())
	if horde.assault_quantity > 0:
		assault_status.text = "Подготовка: %d зомби" % horde.assault_quantity
	elif not horde.assault_feedback.is_empty():
		assault_status.text = horde.assault_feedback
	elif mission.choosing_building:
		assault_status.text = "Удерживайте ПКМ на здании"
	else:
		assault_status.text = ""


func _available_zombies() -> Array[Node]:
	return mission._available_command_units()


func _select_all_zombies() -> void:
	mission._apply_selection(_available_zombies())


func is_pointer_over_ui(point: Vector2) -> bool:
	for block in _blocks:
		if block.visible and block.get_global_rect().has_point(point): return true
	return false
