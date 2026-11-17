extends VBoxContainer

signal exit_requested

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const POSITIONS := {
	PROGRESSION.FLESH: Vector2(0.27, 0.28),
	PROGRESSION.BRUTE: Vector2(0.27, 0.72),
	PROGRESSION.HUNGER: Vector2(0.73, 0.50),
}

var profile: PROGRESSION
var developer_preview := false
var draft: PROGRESSION.Draft
var keys: Dictionary
var tree: Control
var fog: ColorRect
var nodes: Dictionary[String, Button] = {}
var balance: Label
var status: Label
var apply_button: Button
var reset_button: Button
var leave_dialog: ConfirmationDialog
var upgrades: VBoxContainer
var learned: VBoxContainer
var slots: Array[AbilityButton] = []


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	add_child(header)
	status = _label(header, "", 16, DARK_THEME.HEADING)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balance = _label(header, "", 20, Color("efc694"))
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	add_child(columns)
	upgrades = _sidebar(columns, "Действующие улучшения", 216.0)
	tree = Control.new()
	tree.custom_minimum_size.y = 250
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.mouse_filter = Control.MOUSE_FILTER_PASS
	tree.draw.connect(_draw_tree)
	tree.resized.connect(tree.queue_redraw)
	columns.add_child(tree)
	learned = _sidebar(columns, "Активные способности", 184.0)
	for id in PROGRESSION.NODES:
		var button := _button(tree, "", _purchase.bind(id))
		button.anchor_left = POSITIONS[id].x - 0.19
		button.anchor_right = POSITIONS[id].x + 0.19
		button.anchor_top = POSITIONS[id].y
		button.anchor_bottom = POSITIONS[id].y
		button.offset_top = -32
		button.offset_bottom = 32
		button.grow_vertical = Control.GROW_DIRECTION_BOTH
		button.add_theme_font_size_override("font_size", 18)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.gui_input.connect(_refund_input.bind(id))
		nodes[id] = button
	fog = ColorRect.new()
	fog.color = Color("251d27d9")
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.add_child(fog)
	var lock_text := _label(fog, "Развитие откроется после первого начисления Вируса в Миссии №1", 18)
	lock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_text.offset_left = 16
	lock_text.offset_right = -16

	var hotbar_center := CenterContainer.new()
	add_child(hotbar_center)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	hotbar_center.add_child(bar)
	for index in PROGRESSION.SLOT_COUNT:
		var slot := AbilityButton.new()
		slot.editor = self
		slot.index = index
		slot.custom_minimum_size = Vector2(56, 64)
		slot.expand_icon = true
		_style_ability_button(slot, 26)
		slot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slots.append(slot)
		bar.add_child(slot)
	var footer := HBoxContainer.new()
	add_child(footer)
	var back_button := _button(footer, "Назад", request_exit)
	back_button.custom_minimum_size = Vector2(140, 44)
	footer.add_spacer(false)
	reset_button = _button(footer, "Сбросить развитие", _reset)
	footer.add_spacer(false)
	apply_button = _button(footer, "Применить", _apply.bind(false))
	apply_button.custom_minimum_size = back_button.custom_minimum_size
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.title = "Неприменённые изменения"
	leave_dialog.dialog_text = "Сохранить покупки и назначения перед выходом?"
	leave_dialog.ok_button_text = "Применить и выйти"
	leave_dialog.cancel_button_text = "Вернуться"
	leave_dialog.add_button("Выйти без сохранения", false, "discard")
	leave_dialog.confirmed.connect(_apply.bind(true))
	leave_dialog.custom_action.connect(func(_action: StringName):
		leave_dialog.hide()
		exit_requested.emit())
	add_child(leave_dialog)


func _label(parent: Node, value: String, font_size: int, color := DARK_THEME.TEXT) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _sidebar(parent: Control, title: String, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("130f13"), DARK_THEME.EDGE, 12))
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


func open(saved: PROGRESSION, bindings: Dictionary, developer_mode: bool) -> void:
	profile = saved
	keys = bindings
	developer_preview = developer_mode
	draft = profile.begin_edit()
	_refresh()
	var revealed: bool = draft.build.initial_unlocked
	fog.visible = not developer_preview and (not revealed or not draft.build.reveal_seen)
	fog.mouse_filter = Control.MOUSE_FILTER_STOP if not revealed else Control.MOUSE_FILTER_IGNORE
	fog.modulate.a = 1.0
	fog.get_child(0).visible = not revealed
	if not developer_preview and revealed and not draft.build.reveal_seen:
		profile.mark_reveal_seen()
		draft = profile.begin_edit()
		var tween := create_tween()
		tween.tween_property(fog, "modulate:a", 0.0, 0.75)
		tween.tween_callback(fog.hide)


func request_exit() -> void:
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


func _draw_tree() -> void:
	tree.draw_rect(Rect2(Vector2.ZERO, tree.size), DARK_THEME.INK)
	tree.draw_rect(Rect2(Vector2.ONE, tree.size - 2.0 * Vector2.ONE), DARK_THEME.EDGE, false)
	var from: Vector2 = POSITIONS[PROGRESSION.FLESH] * tree.size
	var to: Vector2 = POSITIONS[PROGRESSION.BRUTE] * tree.size
	tree.draw_line(from, to, DARK_THEME.ACCENT, 2.0, true)


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


func _apply(exit_after: bool) -> void:
	if profile.apply(draft) != OK:
		status.text = "Не удалось сохранить развитие"
		return
	draft = profile.begin_edit()
	_refresh()
	if exit_after:
		exit_requested.emit()


func _refresh() -> void:
	balance.text = "Вирус: %d" % draft.build.virus
	status.text = ""
	if profile.save_error != OK:
		status.text = "Хранилище развития недоступно"
	elif draft.changed():
		status.text = "Есть неприменённые изменения"
	apply_button.disabled = not draft.changed()
	reset_button.disabled = draft.build.paid.is_empty()
	for id in nodes:
		var spec: Dictionary = PROGRESSION.NODES[id]
		var rank := PROGRESSION.level(draft.build, id)
		var unlocked: bool = developer_preview or draft.build.get(spec.unlock, false)
		var button := nodes[id]
		button.visible = unlocked
		button.text = "%s\n%d/%d" % [spec.title, rank, spec.costs.size()] if unlocked else ""
		if unlocked and rank < spec.costs.size():
			button.text += "  ·  %d Вируса" % spec.costs[rank]
		button.tooltip_text = _node_tooltip(id, rank) if unlocked else ""
		button.modulate = Color("f4c889") if rank != PROGRESSION.level(draft.original, id) else Color.WHITE
	_refresh_upgrades()
	_refresh_abilities()


func _refresh_upgrades() -> void:
	_clear(upgrades)
	for id in PROGRESSION.NODES:
		var rank := PROGRESSION.level(draft.build, id)
		if rank == 0:
			continue
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_theme_stylebox_override("panel", DARK_THEME.surface(Color("1c151b"), Color("392d35"), 8))
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
		button.tooltip_text = PROGRESSION.effect_text(id, PROGRESSION.level(draft.build, id)) + "\nПеретащите в слот под древом"
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
