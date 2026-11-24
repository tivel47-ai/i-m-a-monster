extends Control

enum InfectionFillStage { TRACKING, TOPPING_OFF, DRAINING }

const INFECTION_ORB = preload("res://scripts/infection_orb.gdshader")
const INFECTION_ORB_ART = preload("res://assets/ui/zombie_style/infection_orb.png")
const INFECTION_ORB_SLUDGE = preload("res://assets/ui/zombie_style/infection_orb_sludge.png")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const ZOMBIE_THEME = preload("res://scripts/zombie_mission_hud_theme.gd")
const CATALOG = preload("res://scripts/mission_catalog.gd")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ZOMBIE = preload("res://scripts/zombie.gd")
const INFECTION_ORB_SIZE := 92.0

var mission: Node2D
var _zombie_skin := false
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
var _infection_key: Label
var _infection_recovery_progress := 0
var _infection_fill := 0.0
var _infection_fill_velocity := 0.0
var _infection_fill_stage := InfectionFillStage.TRACKING
var _infection_full_hold := 0.0
var virus_label: Label
var hotbar: PanelContainer
var abilities_placeholder: PanelContainer
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
var developer_ability_popup: PopupMenu
var developer_vision_toggle: CheckButton


func _ready() -> void:
	mission = get_parent().get_parent() as Node2D
	_zombie_skin = mission.dark_fantasy_hud and mission.get_meta("race_id", "") == "zombie"
	if _zombie_skin:
		theme = ZOMBIE_THEME.build()
	elif mission.dark_fantasy_hud:
		theme = DARK_THEME.build(16, 4)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_build_developer_tools()
	mission.get_node("VillageAlert").level_changed.connect(func(_previous: int, _current: int): _refresh_alert())
	refresh_metaprogression()
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
	if not _zombie_skin:
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


func _fit_top_panel(panel: PanelContainer, height: float) -> void:
	panel.anchor_bottom = 0.0
	panel.offset_bottom = panel.offset_top + height


func _fit_bottom_panel(panel: PanelContainer) -> void:
	panel.anchor_top = 1.0
	panel.offset_top = panel.offset_bottom
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


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

	var alert := _panel(0.32, 0.0, 0.68 if _zombie_skin else 0.73, 0.065)
	alert_label = _label(alert, "", 15)
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _zombie_skin:
		_fit_top_panel(objective, 0)
		_fit_top_panel(alert, 47)
		ZOMBIE_THEME.add_growth(objective, ZOMBIE_THEME.Growth.OBJECTIVE_CORNER, Vector2.RIGHT, Vector2(16, 31), 94)
		ZOMBIE_THEME.add_growth(objective, ZOMBIE_THEME.Growth.OBJECTIVE_BASE, Vector2.DOWN, Vector2(32, 3), 84)
		ZOMBIE_THEME.add_growth(alert, ZOMBIE_THEME.Growth.ALERT_LEFT, Vector2(0, 0.5), Vector2(-20, 14), 124)
		ZOMBIE_THEME.add_growth(alert, ZOMBIE_THEME.Growth.ALERT_RIGHT, Vector2(1, 0.5), Vector2(20, 15), 124)
	if mission.manual_victory_finish:
		_build_victory_notice()

	var pause_edge := 0.89 if _zombie_skin else 0.91
	var gear := _panel(pause_edge, 0.0, 1.0, 0.075)
	var pause_button := Button.new()
	pause_button.text = "⚙ Пауза"
	pause_button.tooltip_text = "Открыть меню паузы"
	pause_button.pressed.connect(func(): mission.pause_requested.emit())
	gear.add_child(pause_button)
	if _zombie_skin:
		_fit_top_panel(gear, 54)
	if mission.mission_build != null:
		var virus := _panel(0.74, 0.0, pause_edge, 0.075)
		virus_label = _label(virus, "", 16)
		virus_label.mouse_filter = Control.MOUSE_FILTER_PASS
		if _zombie_skin:
			_fit_top_panel(virus, 54)

	var army := _panel(0.0, 0.86, 0.18, 1.0)
	var army_box := VBoxContainer.new()
	army.add_child(army_box)
	if mission.horde_commands != null and mission.monster_roster_enabled:
		_fit_bottom_panel(army)
		if _zombie_skin:
			ZOMBIE_THEME.add_growth(army, ZOMBIE_THEME.Growth.ROSTER, Vector2.ZERO, Vector2(38, -8), 90)
			ZOMBIE_THEME.add_growth(army, ZOMBIE_THEME.Growth.OBJECTIVE_CORNER, Vector2(1, 0.5), Vector2(6, -2), 70)
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
		abilities_placeholder = _panel(0.32, 0.90, 0.73, 1.0)
		_label(abilities_placeholder, "Способности", 16)
		if _zombie_skin:
			_fit_bottom_panel(abilities_placeholder)
	_build_hotbar()
	var command_top := 0.77 if mission.horde_commands != null else 0.88
	var commands := _panel(0.80, command_top, 1.0, 1.0)
	if _zombie_skin:
		_fit_bottom_panel(commands)
		ZOMBIE_THEME.add_growth(commands, ZOMBIE_THEME.Growth.COMMANDS, Vector2.ZERO, Vector2(25, 0), 90)
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
	if not _zombie_skin:
		panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("100c10ed"), DARK_THEME.ACCENT, 14, 8))
	victory_notice.add_child(panel)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)
	var title := _label(text, "Победа! Цель миссии выполнена", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not _zombie_skin:
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


func _build_hotbar() -> void:
	hotbar = _panel(0.30 if _zombie_skin else 0.32, 0.90, 0.775 if _zombie_skin else 0.79, 1.0)
	var bar := HBoxContainer.new()
	if _zombie_skin:
		_fit_bottom_panel(hotbar)
		ZOMBIE_THEME.add_growth(hotbar, ZOMBIE_THEME.Growth.HOTBAR_LEFT, Vector2.DOWN, Vector2(22, -34), 108)
		ZOMBIE_THEME.add_growth(hotbar, ZOMBIE_THEME.Growth.HOTBAR_RIGHT, Vector2.ONE, Vector2(15, -33), 112)
		var layout := HBoxContainer.new()
		layout.add_theme_constant_override("separation", 12)
		hotbar.add_child(layout)
		var caption := _label(layout, "Способности")
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout.add_child(bar)
	else:
		hotbar.add_child(bar)
	for index in PROGRESSION.SLOT_COUNT:
		var slot := Button.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.y = 36
		slot.add_theme_font_size_override("font_size", 14)
		slot.focus_mode = Control.FOCUS_NONE
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.expand_icon = true
		slot.add_theme_constant_override("icon_max_width", 28)
		slot.toggle_mode = true
		slot.pressed.connect(func():
			mission.toggle_racial_targeting(mission.ability_runtime().build.slots[index]))
		ability_slots.append(slot)
		var key_parent: Control = slot
		if _zombie_skin:
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", 1)
			bar.add_child(column)
			column.add_child(slot)
			key_parent = column
		else:
			bar.add_child(slot)
		var key_label := _label(key_parent, "", 12 if _zombie_skin else 11)
		if _zombie_skin:
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
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


func refresh_metaprogression() -> void:
	if _infection_key != null:
		var key := _binding_label("race_ability", "F")
		_infection_key.text = key
		var keycap := _infection_key.get_parent() as PanelContainer
		keycap.custom_minimum_size.x = clampf(18.0 + 6.0 * key.length(), 24.0, 44.0)
		infection_button.tooltip_text = "Инфицирование · %s\nЛКМ по жителю или зданию · ПКМ отменяет наведение" % key
	if virus_label != null:
		virus_label.text = "Вирус: %d" % mission.progression.state.virus
		virus_label.tooltip_text = "Ошибка сохранения профиля" if mission.progression.save_error != OK else ""
	var runtime = mission.ability_runtime()
	hotbar.visible = runtime != null
	if abilities_placeholder != null:
		abilities_placeholder.visible = runtime == null
	hunger_slot_key = null
	hunger_slot_uses = null
	if runtime == null:
		return
	for index in ability_slots.size():
		var slot := ability_slots[index]
		var key := _binding_label("ability_slot_%d" % (index + 1), str((index + 1) % 10))
		var ability: String = runtime.build.slots[index]
		if ability.is_empty():
			slot.text = "" if _zombie_skin else key
			slot.icon = null
			slot.disabled = true
			slot.tooltip_text = ""
			slot.set_pressed_no_signal(false)
			ability_keys[index].text = key if _zombie_skin else ""
			ability_uses[index].text = ""
			continue
		slot.text = ""
		var definition: Dictionary = PROGRESSION.NODES[ability]
		slot.icon = definition.icon
		ability_keys[index].text = key
		var uses: int = runtime.uses_for(ability)
		ability_uses[index].text = str(uses)
		slot.disabled = uses == 0
		slot.tooltip_text = "%s · %s\n%s" % [definition.title, key,
			PROGRESSION.effect_text(ability, runtime.abilities[ability].rank)]
		slot.set_pressed_no_signal(runtime.targeting and runtime.active_ability == ability)
		if ability == PROGRESSION.HUNGER:
			hunger_slot_key = ability_keys[index]
			hunger_slot_uses = ability_uses[index]


func _binding_label(action: String, fallback: String) -> String:
	if InputMap.has_action(action):
		var events := InputMap.action_get_events(action)
		if not events.is_empty() and events[0] is InputEventKey:
			return OS.get_keycode_string(events[0].physical_keycode)
	return fallback


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

	var orb := TextureRect.new()
	orb.texture = INFECTION_ORB_ART
	orb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	orb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	orb.size = Vector2.ONE * INFECTION_ORB_SIZE
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	infection_orb_material = ShaderMaterial.new()
	infection_orb_material.shader = INFECTION_ORB
	infection_orb_material.set_shader_parameter("sludge_texture", INFECTION_ORB_SLUDGE)
	infection_orb_material.set_shader_parameter("fill_level", _infection_fill)
	orb.material = infection_orb_material
	infection_button.add_child(orb)
	if _zombie_skin:
		ZOMBIE_THEME.add_orb_cradle(infection_button)

	infection_charges = _label(infection_button, "", 16)
	infection_charges.position.y = INFECTION_ORB_SIZE - 1
	infection_charges.size.x = INFECTION_ORB_SIZE
	infection_charges.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	infection_charges.add_theme_color_override("font_color", Color("e3efcd"))
	infection_charges.add_theme_color_override("font_outline_color", Color("142417"))
	infection_charges.add_theme_constant_override("outline_size", 6)
	if _zombie_skin:
		var keycap := PanelContainer.new()
		keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		keycap.position = Vector2(63, INFECTION_ORB_SIZE)
		keycap.add_theme_stylebox_override("panel", ZOMBIE_THEME.keycap())
		infection_button.add_child(keycap)
		_infection_key = _label(keycap, "", 12)
		_infection_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_infection_key.autowrap_mode = TextServer.AUTOWRAP_OFF
		_infection_key.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

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
	var progress: int = ability.recovery_progress
	if progress < _infection_recovery_progress:
		_infection_fill_stage = InfectionFillStage.TOPPING_OFF
		_infection_full_hold = 0.42
	_infection_recovery_progress = progress
	infection_charges.text = str(ability.charges)
	infection_button.disabled = ability.charges == 0
	infection_button.set_pressed_no_signal(ability.targeting)
	infection_orb_material.set_shader_parameter("available", not infection_button.disabled)
	infection_orb_material.set_shader_parameter("targeting", ability.targeting)


func _animate_infection_fill(delta: float) -> void:
	var target: float = float(_infection_recovery_progress) / mission.ZOMBIE_INFECTION.KILLS_PER_CHARGE
	if _infection_fill_stage == InfectionFillStage.TOPPING_OFF:
		target = 1.0
		if _infection_fill == 1.0:
			_infection_full_hold -= delta
			if _infection_full_hold <= 0.0:
				_infection_fill_stage = InfectionFillStage.DRAINING
			return
	elif _infection_fill_stage == InfectionFillStage.DRAINING:
		target = 0.0

	if _infection_fill == target and _infection_fill_velocity == 0.0:
		return
	# Critical damping keeps the surface moving smoothly when kills change its destination.
	var response := 5.7 if _infection_fill_stage == InfectionFillStage.DRAINING else 4.6
	var displacement := _infection_fill - target
	var tangent := _infection_fill_velocity + response * displacement
	var decay := exp(-response * delta)
	_infection_fill = target + (displacement + tangent * delta) * decay
	_infection_fill_velocity = (_infection_fill_velocity - response * tangent * delta) * decay
	if absf(_infection_fill - target) <= 0.003 and absf(_infection_fill_velocity) <= 0.018:
		_infection_fill = target
		_infection_fill_velocity = 0.0
		if _infection_fill_stage == InfectionFillStage.DRAINING:
			_infection_fill_stage = InfectionFillStage.TRACKING
	infection_orb_material.set_shader_parameter("fill_level", clampf(_infection_fill, 0.0, 1.0))


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
	developer_panel = _panel(0.76, 0.0, 1.0, 0.0)
	developer_panel.offset_top = 115
	developer_panel.offset_bottom = 115
	developer_panel.visible = false
	var box := VBoxContainer.new()
	developer_panel.add_child(box)
	_label(box, "Режим разработки", 17)
	_add_spawn_menu(box, "Создать монстра", CATALOG.monster_types())
	_add_spawn_menu(box, "Создать человека", CATALOG.HUMAN_TYPES)
	developer_tool_label = _label(box, "Выберите инструмент", 13)
	var stop := Button.new()
	stop.text = "Отменить создание"
	stop.pressed.connect(func(): _choose_developer_tool(""))
	box.add_child(stop)
	_add_ability_menu(box)
	var refill := Button.new()
	refill.text = "Восстановить заряды"
	refill.pressed.connect(mission.developer_restore_charges)
	box.add_child(refill)
	developer_vision_toggle = CheckButton.new()
	developer_vision_toggle.text = "Показать обзор юнитов"
	developer_vision_toggle.visible = mission.get_meta("directional_unit_vision", false)
	developer_vision_toggle.toggled.connect(mission.set_developer_vision)
	box.add_child(developer_vision_toggle)
	_label(box, "Этап оповещения", 14)
	var alert: Node = mission.get_node("VillageAlert")
	var stages := OptionButton.new()
	for index in alert.LEVEL_LABELS.size():
		if index < alert.Level.LAST_STAND or mission.has_node("LastStand"):
			stages.add_item(alert.LEVEL_LABELS[index])
	if mission.has_node("LastStand"):
		stages.set_item_disabled(alert.Level.LAST_STAND, alert.level != alert.Level.LAST_STAND)
	stages.select(alert.level)
	stages.item_selected.connect(func(index: int):
		if mission.developer_mode:
			alert.set_debug_level(index))
	alert.level_changed.connect(func(_previous: int, current: int):
		stages.select(current)
		if current == alert.Level.LAST_STAND: stages.set_item_disabled(current, false))
	box.add_child(stages)
	developer_button.pressed.connect(func():
		developer_panel.visible = not developer_panel.visible
		if not developer_panel.visible:
			developer_ability_popup.hide()
			_choose_developer_tool(""))


func _developer_menu(parent: VBoxContainer, title: String) -> PopupMenu:
	var button := MenuButton.new()
	button.text = title
	button.flat = false
	parent.add_child(button)
	return button.get_popup()


func _add_spawn_menu(parent: VBoxContainer, title: String, types: Dictionary) -> void:
	var popup := _developer_menu(parent, title)
	var ids := types.keys()
	for id in ids:
		popup.add_item(types[id])
	popup.id_pressed.connect(func(index: int): _choose_developer_tool(ids[index]))


func _add_ability_menu(parent: VBoxContainer) -> void:
	var races := _developer_menu(parent, "Добавить способность")
	var race_ids := CATALOG.RACES.keys()
	for race in race_ids:
		races.add_item(CATALOG.RACES[race].name)
	developer_ability_popup = PopupMenu.new()
	races.get_parent().add_child(developer_ability_popup)
	races.id_pressed.connect(func(index: int):
		_show_developer_abilities.call_deferred(race_ids[index], races.position))
	developer_ability_popup.id_pressed.connect(_select_developer_ability)


func _show_developer_abilities(race: String, popup_position: Vector2i) -> void:
	if not developer_panel.visible:
		return
	var popup := developer_ability_popup
	popup.clear()
	for id: String in CATALOG.RACES[race].active_perks:
		var definition: Dictionary = PROGRESSION.NODES[id]
		popup.add_icon_item(definition.icon, definition.title)
		var index := popup.item_count - 1
		popup.set_item_icon_max_width(index, 24)
		popup.set_item_metadata(index, [race, id])
	popup.popup(Rect2i(popup_position, popup.get_contents_minimum_size()))


func _select_developer_ability(index: int) -> void:
	var item: Array = developer_ability_popup.get_item_metadata(index)
	var id: String = item[1]
	if mission.developer_add_ability(item[0], id):
		_choose_developer_tool("")
		developer_tool_label.text = "Добавлено: %s" % PROGRESSION.NODES[id].title
	elif mission.ability_runtime() != null and id in mission.ability_runtime().build.slots:
		developer_tool_label.text = "Способность уже на панели"
	else:
		developer_tool_label.text = "Нет свободных слотов"


func set_developer_mode(enabled: bool) -> void:
	developer_button.visible = enabled
	developer_panel.visible = false
	developer_ability_popup.hide()
	developer_vision_toggle.set_pressed_no_signal(mission.developer_vision)
	if not enabled: _choose_developer_tool("")
	if _zombie_skin:
		mission.get_node("VillageAlert").set_debug_overlay_suppressed(not enabled)
	refresh_metaprogression()

func _choose_developer_tool(kind: String) -> void:
	if not kind.is_empty():
		if not mission.developer_mode:
			return
		mission.cancel_selection()
		mission.cancel_order_preview()
		mission.cancel_infection_targeting()
		mission.cancel_hunger_targeting()
	mission.developer_spawn = kind
	refresh_developer_tool()

func refresh_developer_tool(placement_failed := false) -> void:
	if placement_failed:
		developer_tool_label.text = "Выберите доступное место на карте"
		return
	var kind: String = mission.developer_spawn
	var unit_name: String = CATALOG.HUMAN_TYPES.get(kind,
		CATALOG.monster_types().get(kind, ""))
	developer_tool_label.text = "%s · ЛКМ на карте, ПКМ — отмена" % unit_name if not unit_name.is_empty() else "Выберите инструмент"


func _process(delta: float) -> void:
	if infection_orb_material != null:
		_animate_infection_fill(delta)
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	if not is_instance_valid(mission): return
	_refresh_objective()
	_refresh_alert()
	refresh_units()


func _refresh_alert() -> void:
	var alert: Node = mission.get_node("VillageAlert")
	alert_label.text = "Деревня: %s" % alert.LEVEL_LABELS[alert.level]
	if alert.level == alert.Level.ALARM:
		alert_label.text += "  •  Опасность %.0f / %.0f" % [alert.danger, alert.danger_threshold]


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
			_add_monster_row(form, unit)
	monster_count.text = "Монстры: %d" % units.size()
	for form in _monster_rows:
		_monster_rows[form].text = "× %d" % counts.get(form, 0)


func _add_monster_row(form: String, unit: ZOMBIE) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_roster.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(27, 27)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.texture = unit.get_roster_portrait()
	row.add_child(icon)
	if icon.texture == null:
		var polygon := unit.zombie_visual.polygon
		var color := unit.zombie_visual.color
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
	if _zombie_skin:
		assault_status.visible = not assault_status.text.is_empty()


func _available_zombies() -> Array[Node]:
	return mission._available_command_units()


func _select_all_zombies() -> void:
	mission._apply_selection(_available_zombies())


func is_pointer_over_ui(point: Vector2) -> bool:
	for block in _blocks:
		if block.visible and block.get_global_rect().has_point(point): return true
	return false
