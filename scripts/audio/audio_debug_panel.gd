extends PanelContainer

const AUDIO = preload("res://scripts/audio/audio_manager.gd")

const REGISTRY = preload("res://scripts/audio/audio_registry.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")

var _audio: AUDIO
var _event: OptionButton
var _variant: OptionButton
var _bus: OptionButton
var _muted: CheckButton
var _solo: CheckButton
var _status: Label
var _timer: Timer
var _mission_audio: Node
var _alert: Node
var _mutes: Dictionary = {}
var _solo_bus: StringName


func configure(mission_audio: Node, alert: Node) -> void:
	_audio = AUDIO.service() as AUDIO
	_mission_audio = mission_audio
	_alert = alert
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var title := Label.new()
	title.text = "Диагностика звука"
	box.add_child(title)
	_event = OptionButton.new()
	_event.fit_to_longest_item = false
	_event.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for id: StringName in REGISTRY.EVENTS:
		_event.add_item(id)
		_event.set_item_metadata(_event.item_count - 1, id)
	box.add_child(_event)
	_variant = OptionButton.new()
	_variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var audition_row := HBoxContainer.new()
	box.add_child(audition_row)
	audition_row.add_child(_variant)
	var play := Button.new()
	play.text = "Прослушать"
	play.pressed.connect(func():
		_audio.stop_audition()
		_audio.audition(_selected_event(), _variant.selected - 1)
		_refresh())
	audition_row.add_child(play)
	_event.item_selected.connect(func(_selected: int): _refresh_variants())
	_refresh_variants()

	var mix := HBoxContainer.new()
	box.add_child(mix)
	_bus = OptionButton.new()
	_bus.fit_to_longest_item = false
	_bus.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for bus: StringName in SETTINGS.AUDIO_LABELS:
		_bus.add_item(SETTINGS.AUDIO_LABELS[bus])
		_bus.set_item_metadata(_bus.item_count - 1, bus)
	mix.add_child(_bus)
	_muted = CheckButton.new()
	_muted.text = "Без звука"
	_muted.tooltip_text = "Временно выключить выбранный канал"
	_muted.toggled.connect(func(enabled: bool):
		_mutes[_selected_bus()] = enabled
		_audio.set_debug_mute(_selected_bus(), enabled))
	mix.add_child(_muted)
	_solo = CheckButton.new()
	_solo.text = "Соло"
	_solo.toggled.connect(func(enabled: bool):
		_solo_bus = _selected_bus() if enabled else &""
		_audio.set_debug_solo(_solo_bus))
	mix.add_child(_solo)
	_bus.item_selected.connect(func(_selected: int): _refresh_mix())
	_refresh_mix()

	var sources := CheckButton.new()
	sources.text = "Показать источники и радиусы"
	sources.toggled.connect(_mission_audio.set_debug_sources)
	box.add_child(sources)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", DARK_THEME.HINT_SIZE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_refresh()
			_timer.start()
		else:
			_timer.stop()
			sources.set_pressed_no_signal(false)
			_mission_audio.set_debug_sources(false)
			_audio.stop_audition()
			_audio.clear_debug_mix()
			_mutes.clear()
			_solo_bus = &""
			_refresh_mix())


func _selected_event() -> StringName:
	return _event.get_selected_metadata()


func _selected_bus() -> StringName:
	return _bus.get_selected_metadata()


func _refresh_variants() -> void:
	_variant.clear()
	_variant.add_item("Случайный вариант")
	for index in int(REGISTRY.EVENTS[_selected_event()].count):
		_variant.add_item("Вариант %d" % (index + 1))


func _refresh_mix() -> void:
	_muted.set_pressed_no_signal(_mutes.get(_selected_bus(), false))
	_solo.disabled = _selected_bus() == &"Master"
	_solo.set_pressed_no_signal(_selected_bus() == _solo_bus)


func _refresh() -> void:
	var data := _audio.diagnostics()
	var listener := _audio.listener_position()
	var categories := PackedStringArray()
	for bus in data.categories:
		categories.append("%s %d" % [bus, data.categories[bus]])
	var loops := PackedStringArray()
	for key in data.loops:
		var gains: Vector2 = data.loops[key]
		loops.append("%s %d→%d%%" % [key, roundi(gains.x * 100.0), roundi(gains.y * 100.0)])
	var rejected := PackedStringArray()
	for reason in data.rejected:
		rejected.append("%s %d" % [reason, data.rejected[reason]])
	_status.text = (
		"Камера (%d, %d) · ×%.2f · %s\n" % [
			roundi(listener.x), roundi(listener.y), _audio.listener_zoom(), _alert.LEVEL_LABELS[_alert.level]]
		+ "Голоса %d/%d · петли %d/%d\n" % [
			data.voices, AUDIO.ONE_SHOTS + AUDIO.FADING_VOICES, data.loops.size(), AUDIO.LOOP_LIMIT]
		+ "%s\n%s\n" % [", ".join(categories), ", ".join(loops)]
		+ "Последнее · %s\nОтклонено · %s\nОтсутствует записей %d · неизвестных событий %d" % [
			data.last, data.rejection, data.missing.size(), data.unknown.size()]
	)
	var details := PackedStringArray()
	details.append_array(rejected)
	details.append_array(data.unknown)
	details.append_array(data.missing)
	_status.tooltip_text = "\n".join(details)
	_status.mouse_filter = Control.MOUSE_FILTER_STOP

