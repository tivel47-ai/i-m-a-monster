extends Control

signal exit_requested

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const TREE = preload("res://scripts/zombie_development_tree.gd")
const RESET_HOLD_SECONDS := 2.0
const OVERLAY_MARGIN := 16
const PANEL_IDLE := Color("130f1380")
const PANEL_HOVER := Color("3a2932eb")
const EDGE_IDLE := Color("80757792")
const EDGE_HOVER := Color("af8289")

var profile: PROGRESSION
var developer_preview := false
var draft: PROGRESSION.Draft
var keys: Dictionary
var tree: TREE
var nodes: Dictionary[String, Button] = {}
var balance: Label
var developer_controls: HBoxContainer
var subtract_virus_button: Button
var status: Label
var back_button: Button
var apply_button: Button
var reset_button: Button
var reset_fill: ProgressBar
var reset_elapsed := -1.0
var leave_dialog: ConfirmationDialog
var upgrades: VBoxContainer
var learned: VBoxContainer
var slots: Array[AbilityButton] = []


func _ready() -> void:
	theme = Theme.new()
	theme.set_font_size("font_size", "TooltipLabel", 16)
	theme.set_stylebox("panel", "TooltipPanel", DARK_THEME.surface(Color("100d10d9"), DARK_THEME.EDGE, 8))

	tree = TREE.new()
	tree.initial_reveal_finished.connect(_refresh_nodes)
	add_child(tree)
	tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in PROGRESSION.NODES:
		var button := Button.new()
		button.pressed.connect(_purchase.bind(id))
		button.gui_input.connect(_refund_input.bind(id))
		tree.add_upgrade(id, button)
		nodes[id] = button

	var sidebars := HBoxContainer.new()
	sidebars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sidebars)
	sidebars.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	sidebars.offset_left = OVERLAY_MARGIN
	sidebars.offset_right = -OVERLAY_MARGIN
	sidebars.offset_top = -230
	sidebars.offset_bottom = 86
	upgrades = _sidebar(sidebars, "Действующие улучшения", Vector2(216, 316))
	sidebars.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	learned = _sidebar(sidebars, "Активные способности", Vector2(184, 180))

	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, OVERLAY_MARGIN)
	_build_header(layout)
	layout.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_footer(layout)

	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Неприменённые изменения"
	leave_dialog.dialog_text = "При выходе неприменённые изменения будут потеряны."
	leave_dialog.ok_button_text = "Выйти"
	leave_dialog.cancel_button_text = "Остаться"
	leave_dialog.confirmed.connect(func():
		draft = profile.begin_edit()
		exit_requested.emit())
	leave_dialog.visibility_changed.connect(func():
		tree.navigation_enabled = not leave_dialog.visible
		if leave_dialog.visible:
			leave_dialog.get_cancel_button().grab_focus())
	add_child(leave_dialog)
	visibility_changed.connect(_cancel_reset_hold)


func _process(delta: float) -> void:
	if reset_elapsed < 0.0:
		return
	reset_elapsed += delta
	reset_fill.value = reset_elapsed
	if reset_elapsed >= RESET_HOLD_SECONDS:
		_cancel_reset_hold()
		_reset()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_reset_hold()


func _build_header(layout: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 16)
	header.add_child(heading)
	var title := _label(heading, "Развитие", 36, DARK_THEME.HEADING)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	status = _label(heading, "", 16, DARK_THEME.HEADING)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button = Button.new()
	reset_button.text = "Сбросить развитие"
	reset_button.tooltip_text = "Удерживайте ЛКМ 2 секунды, чтобы сбросить развитие"
	header.add_child(reset_button)
	reset_button.custom_minimum_size.y = 44
	reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_button.gui_input.connect(_reset_input)
	reset_button.mouse_exited.connect(_cancel_reset_hold)
	reset_button.button_up.connect(_cancel_reset_hold)
	reset_fill = ProgressBar.new()
	reset_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset_fill.show_percentage = false
	reset_fill.max_value = RESET_HOLD_SECONDS
	reset_fill.step = 0.0
	reset_fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	reset_fill.add_theme_stylebox_override("fill", DARK_THEME.surface(Color("a53c4a80"), Color.TRANSPARENT, 0))
	reset_button.add_child(reset_fill)
	reset_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var resources := HBoxContainer.new()
	resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources.add_theme_constant_override("separation", 16)
	header.add_child(resources)
	resources.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance = _label(resources, "", 20, Color("efc694"))
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label in [title, status, balance]:
		label.add_theme_color_override("font_outline_color", DARK_THEME.INK)
		label.add_theme_constant_override("outline_size", 6)
	developer_controls = HBoxContainer.new()
	resources.add_child(developer_controls)
	subtract_virus_button = _button(developer_controls, "−10", _adjust_virus.bind(-10))
	subtract_virus_button.tooltip_text = "Убавить Вирус на 10"
	_button(developer_controls, "+10", _adjust_virus.bind(10)).tooltip_text = "Начислить 10 Вируса"


func _build_footer(layout: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(footer)
	back_button = _button(footer, "Назад", request_exit)
	back_button.custom_minimum_size = Vector2(140, 44)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hotbar := OverlayPanel.new(5)
	footer.add_child(hotbar)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	hotbar.add_child(bar)
	for index in PROGRESSION.SLOT_COUNT:
		var slot := AbilityButton.new()
		slot.editor = self
		slot.index = index
		slot.custom_minimum_size = Vector2(46, 52)
		slot.expand_icon = true
		_style_ability_button(slot, 24)
		slot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slots.append(slot)
		bar.add_child(slot)
	footer.add_spacer(false).mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_button = _button(footer, "Применить", _apply)
	apply_button.custom_minimum_size = back_button.custom_minimum_size
	apply_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _label(parent: Node, value: String, font_size: int, color := DARK_THEME.TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _sidebar(parent: Control, title: String, minimum_size: Vector2) -> VBoxContainer:
	var panel := OverlayPanel.new(12)
	panel.custom_minimum_size = minimum_size
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	panel.add_child(contents)
	_label(contents, title, 18, DARK_THEME.HEADING)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contents.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	return list


func _style_ability_button(button: Button, icon_size: int) -> void:
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_constant_override("icon_max_width", icon_size)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", DARK_THEME.surface(Color("14111480"), EDGE_IDLE, 8))


func open(saved: PROGRESSION, bindings: Dictionary, developer_mode: bool, camera_speed: float) -> void:
	_cancel_reset_hold()
	profile = saved
	keys = bindings
	developer_preview = developer_mode
	draft = profile.begin_edit()
	var animate_reveal: bool = not developer_preview and draft.build.initial_unlocked and not draft.build.reveal_seen
	if animate_reveal:
		profile.mark_reveal_seen()
		draft = profile.begin_edit()
	tree.camera_speed = camera_speed
	tree.begin(draft.build, developer_preview, animate_reveal)
	_refresh()


func request_exit() -> void:
	_cancel_reset_hold()
	if leave_dialog.visible:
		leave_dialog.hide()
	elif draft.changed():
		leave_dialog.popup_centered()
	else:
		exit_requested.emit()


func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _purchase(id: String) -> void:
	draft.purchase(id)
	_refresh()


func _refund_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		draft.refund(id)
		_refresh()
		nodes[id].accept_event()


func _reset() -> void:
	draft.reset()
	_refresh()


func _reset_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_visible_in_tree() and not reset_button.disabled and not leave_dialog.visible:
			reset_elapsed = 0.0
		else:
			_cancel_reset_hold()


func _cancel_reset_hold() -> void:
	reset_elapsed = -1.0
	if is_instance_valid(reset_fill):
		reset_fill.value = 0.0


func _adjust_virus(delta: int) -> void:
	if not developer_preview:
		return
	var virus: int = draft.build.virus
	draft.build.virus = maxi(0, virus + mini(delta, 9223372036854775807 - virus))
	if delta > 0:
		draft.build.initial_unlocked = true
	_refresh()


func _apply() -> void:
	if profile.apply(draft) != OK:
		status.text = "Не удалось сохранить развитие"
		return
	draft = profile.begin_edit()
	_refresh()


func _refresh() -> void:
	balance.text = "Вирус: %d" % draft.build.virus
	developer_controls.visible = developer_preview
	subtract_virus_button.disabled = draft.build.virus == 0
	status.text = ""
	if profile.save_error != OK:
		status.text = "Хранилище развития недоступно"
	elif draft.changed():
		status.text = "Есть неприменённые изменения"
	elif not draft.build.initial_unlocked and not developer_preview:
		status.text = "Первое начисление Вируса откроет улучшения"
	apply_button.disabled = not draft.changed()
	reset_button.disabled = draft.build.paid.is_empty()
	if reset_button.disabled:
		_cancel_reset_hold()
	tree.sync_ranks(draft.build)
	_refresh_nodes()
	_refresh_upgrades()
	_refresh_abilities()


func _refresh_nodes() -> void:
	for id in nodes:
		var spec: Dictionary = PROGRESSION.NODES[id]
		var rank := PROGRESSION.level(draft.build, id)
		var unlocked: bool = tree.upgrades_visible() and (developer_preview or draft.build.get(spec.unlock, false))
		var button := nodes[id]
		button.visible = unlocked
		button.tooltip_text = _node_tooltip(id, rank) if unlocked else ""


func _refresh_upgrades() -> void:
	_clear(upgrades)
	for id in PROGRESSION.NODES:
		var rank := PROGRESSION.level(draft.build, id)
		if rank == 0:
			continue
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("1c151b85"), Color("80757763"), 8))
		upgrades.add_child(panel)
		var row := VBoxContainer.new()
		panel.add_child(row)
		_label(row, "%s · %d/%d" % [PROGRESSION.NODES[id].title, rank, PROGRESSION.NODES[id].costs.size()], 15)
		_label(row, PROGRESSION.effect_text(id, rank), 14, DARK_THEME.MUTED)
	if upgrades.get_child_count() == 0:
		_label(upgrades, "Улучшений пока нет", 15, DARK_THEME.MUTED)


func _refresh_abilities() -> void:
	_clear(learned)
	for id in PROGRESSION.NODES:
		if not PROGRESSION.NODES[id].get("optional", false) or PROGRESSION.level(draft.build, id) == 0:
			continue
		var button := AbilityButton.new()
		_style_ability_button(button, 42)
		button.editor = self
		button.ability = id
		button.icon = PROGRESSION.NODES[id].get("icon")
		var assigned: int = draft.build.slots.find(id)
		button.text = PROGRESSION.NODES[id].title
		if assigned >= 0:
			button.text += " · " + _key(assigned)
			button.modulate.a = 0.65
		button.tooltip_text = PROGRESSION.effect_text(id, PROGRESSION.level(draft.build, id)) + "\nПеретащите в слот хотбара"
		learned.add_child(button)
	if learned.get_child_count() == 0:
		_label(learned, "Изучите способность в древе", 15, DARK_THEME.MUTED)
	for slot in slots:
		slot.ability = draft.build.slots[slot.index]
		slot.icon = null
		slot.text = _key(slot.index)
		slot.tooltip_text = "Пустой слот · %s" % slot.text
		if not slot.ability.is_empty():
			slot.icon = PROGRESSION.NODES[slot.ability].get("icon")
			slot.tooltip_text = "%s\n%s\nПКМ: снять назначение" % [PROGRESSION.NODES[slot.ability].title,
				PROGRESSION.effect_text(slot.ability, PROGRESSION.level(draft.build, slot.ability))]
		slot.modulate = Color("f4c889") if slot.ability != draft.original.slots[slot.index] else Color.WHITE


func _clear(list: Control) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _node_tooltip(id: String, rank: int) -> String:
	var spec: Dictionary = PROGRESSION.NODES[id]
	var lines := PackedStringArray([spec.title, "Уровень %d из %d" % [rank, spec.costs.size()]])
	if rank > 0:
		lines.append(PROGRESSION.effect_text(id, rank))
	if rank < spec.costs.size():
		lines.append("Следующий уровень · %d Вируса" % spec.costs[rank])
		lines.append(PROGRESSION.effect_text(id, rank + 1))
	var block := draft.purchase_block(id, developer_preview)
	if not block.is_empty():
		lines.append(block)
	lines.append("ЛКМ: купить · ПКМ: вернуть уровень")
	return "\n".join(lines)


func _key(index: int) -> String:
	return OS.get_keycode_string(keys["ability_slot_%d" % (index + 1)])


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return data is Dictionary and data.get("editor") == self and data.get("index", -1) >= 0 and not hovered is BaseButton


func _drop_data(_position: Vector2, data: Variant) -> void:
	draft.unassign(data.index)
	_refresh()


class OverlayPanel extends PanelContainer:
	var idle: StyleBoxFlat
	var hover: StyleBoxFlat

	func _init(padding: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		idle = DARK_THEME.surface(PANEL_IDLE, EDGE_IDLE, padding)
		hover = DARK_THEME.surface(PANEL_HOVER, EDGE_HOVER, padding)
		add_theme_stylebox_override("panel", idle)

	func _process(_delta: float) -> void:
		if not is_visible_in_tree():
			return
		var hovered := get_viewport().gui_get_hovered_control()
		var highlighted := hovered != null and (hovered == self or is_ancestor_of(hovered))
		var style := hover if highlighted else idle
		if get_theme_stylebox("panel") != style:
			add_theme_stylebox_override("panel", style)


class AbilityButton extends Button:
	var editor
	var index := -1
	var ability := ""

	func _get_drag_data(_position: Vector2) -> Variant:
		if ability.is_empty():
			return null
		var preview := Button.new()
		preview.text = PROGRESSION.NODES[ability].title
		preview.icon = icon
		preview.add_theme_constant_override("icon_max_width", 26)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_drag_preview(preview)
		return {"editor": editor, "index": index, "id": ability}

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return index >= 0 and data is Dictionary and data.get("editor") == editor

	func _drop_data(_position: Vector2, data: Variant) -> void:
		editor.draft.assign(data.id, index, data.index)
		editor._refresh()

	func _gui_input(event: InputEvent) -> void:
		if index >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			editor.draft.unassign(index)
			editor._refresh()
			accept_event()
