extends RefCounted

const ACTION_BUTTON_SIZE := Vector2(240, 48)

const TITLE_SIZE := 34
const SECTION_SIZE := 22
const BODY_SIZE := 19
const COMPACT_SIZE := 16
const HINT_SIZE := 15
const KEY_SIZE := 13

const INK := Color("090809")
const TEXT := Color("e9dfcc")
const MUTED := Color("bfb2a3")
const HEADING := Color("d3a187")
const EDGE := Color("50454a")
const ACCENT := Color("a53c4a")


static func surface(fill: Color, border: Color, padding: float, radius := 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


static func build(font_size: int, padding: float) -> Theme:
	var theme := Theme.new()
	theme.default_font_size = font_size
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", surface(Color("100d10"), EDGE, 12))

	var focus := surface(Color.TRANSPARENT, ACCENT, padding)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "Button", surface(Color("141114"), EDGE, padding))
	theme.set_stylebox("hover", "Button", surface(Color("27191e"), Color("89616a"), padding))
	theme.set_stylebox("pressed", "Button", surface(Color("391820"), ACCENT, padding))
	theme.set_stylebox("hover_pressed", "Button", surface(Color("47202a"), Color("c75a6a"), padding))
	theme.set_stylebox("disabled", "Button", surface(Color("110e10"), Color("332b30"), padding))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_hover_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color("9b8b90"))

	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_stylebox("slider", "HSlider", surface(Color("181217"), EDGE, 4))
	theme.set_stylebox("grabber_area", "HSlider", surface(Color("662832"), ACCENT, 4))
	theme.set_stylebox("grabber_area_highlight", "HSlider", surface(ACCENT, Color("ca7381"), 4))
	theme.set_stylebox("scroll", "VScrollBar", surface(INK, Color("342930"), 4))
	theme.set_stylebox("grabber", "VScrollBar", surface(Color("492830"), EDGE, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", surface(Color("702e3b"), ACCENT, 4))
	theme.set_stylebox("grabber_pressed", "VScrollBar", surface(ACCENT, Color("ca7381"), 4))

	theme.set_stylebox("panel", "PopupMenu", surface(INK, EDGE, 6))
	theme.set_stylebox("hover", "PopupMenu", surface(Color("391820"), ACCENT, 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", surface(INK, EDGE, 6))
	style_tooltip(theme)
	return theme


static func style_tooltip(theme: Theme) -> void:
	theme.set_font_size("font_size", "TooltipLabel", HINT_SIZE)
	theme.set_color("font_color", "TooltipLabel", MUTED)


static func build_fixed_dialog(dialog: AcceptDialog, cancel_button: Button) -> Label:
	dialog.borderless = true
	dialog.unresizable = true
	dialog.get_label().hide()

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	dialog.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 32
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	var title := Label.new()
	title.text = dialog.title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", HEADING)
	title.add_theme_font_size_override("font_size", SECTION_SIZE)
	header.add_child(title)
	var close := Button.new()
	close.icon = dialog.get_theme_icon("close", "Window")
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.custom_minimum_size = Vector2(32, 32)
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.accessibility_name = "Закрыть"
	close.pressed.connect(cancel_button.pressed.emit)
	header.add_child(close)

	var message := Label.new()
	content.add_child(message)
	return message
