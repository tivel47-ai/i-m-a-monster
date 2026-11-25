extends RefCounted

enum Frame { GOAL, VILLAGE, VIRUS, PAUSE, COMMANDS }

const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const ROOT_FRAME: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_roots.png")
const FRAMES := {
	Frame.GOAL: [preload("res://assets/ui/zombie_style/mission_hud_decay_goal.png"),
		Vector4(9, 12, 65, 54), Vector4(44, 32, 103, 73), Vector4(13, 6, 14, 6)],
	Frame.VILLAGE: [preload("res://assets/ui/zombie_style/mission_hud_decay_village.png"),
		Vector4(116, 13, 93, 36), Vector4(173, 26, 155, 48), Vector4(14, 4, 14, 4)],
	Frame.VIRUS: [preload("res://assets/ui/zombie_style/mission_hud_decay_virus.png"),
		Vector4(28, 14, 14, 25), Vector4(61, 26, 57, 37), Vector4(12, 4, 16, 4)],
	Frame.PAUSE: [preload("res://assets/ui/zombie_style/mission_hud_decay_pause.png"),
		Vector4(13, 15, 10, 24), Vector4(48, 27, 45, 36), Vector4(9, 4, 9, 4)],
	Frame.COMMANDS: [preload("res://assets/ui/zombie_style/mission_hud_decay_commands.png"),
		Vector4(44, 41, 12, 9), Vector4(81, 67, 44, 25), Vector4(13, 6, 12, 9)],
}
const ROSTER_EMPTY: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_decay_army.png")
const ROSTER_GROWTH: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_roster_growth.png")
const ROSTER_WIDTH := 213.0
const ROSTER_TOP_PADDING := 6.0
const ROSTER_BOTTOM_PADDING := 7.0
const ROSTER_LEFT_OUTSET := 10.0
const ROSTER_BOTTOM_OUTSET := 12.0
# Atlas regions for the fixed-size frame pieces, followed by the smooth backdrop.
const ROSTER_TOP := Rect2(0, 0, 278, 113)
const ROSTER_BOTTOM := Rect2(0, 113, 278, 113)
const ROSTER_LEFT := Rect2(0, 226, 24, 31)
const ROSTER_RIGHT := Rect2(24, 226, 24, 31)
const ROSTER_BACKDROP := Rect2(52, 226, 64, 48)
const HOTBAR_FRAME: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_decay_hotbar.png")
# The outer forks and the orb opening are fixed. Only the two straight spans stretch.
const HOTBAR_CUTS := [0, 115, 344, 468, 697, 798]
const HOTBAR_OUTSET_LEFT := 69.0
const HOTBAR_OUTSET_RIGHT := 55.0
const HOTBAR_BOTTOM_IN_TEXTURE := 127.5
const ORB_CENTER_FROM_HOTBAR_BOTTOM := 65.0
const BONE := Color("ebdbb8")
const EDGE := Color("6b5b43")


static func build() -> Theme:
	var theme := DARK_THEME.build(DARK_THEME.COMPACT_SIZE, 4)
	var frame := StyleBoxTexture.new()
	frame.texture = ROOT_FRAME
	frame.texture_margin_left = 19
	frame.texture_margin_right = 19
	frame.texture_margin_top = 15
	frame.texture_margin_bottom = 15
	frame.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	frame.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	frame.set_content_margin(SIDE_LEFT, 14)
	frame.set_content_margin(SIDE_RIGHT, 14)
	frame.set_content_margin(SIDE_TOP, 14)
	frame.set_content_margin(SIDE_BOTTOM, 14)
	theme.set_stylebox("panel", "PanelContainer", frame)

	theme.set_stylebox("normal", "Button", DARK_THEME.surface(Color("201b15"), EDGE, 4))
	theme.set_stylebox("hover", "Button", DARK_THEME.surface(Color("322b1c"), Color("97845f"), 4))
	theme.set_stylebox("pressed", "Button", DARK_THEME.surface(Color("343823"), Color("a09163"), 4))
	theme.set_stylebox("hover_pressed", "Button", DARK_THEME.surface(Color("42472b"), Color("b1a171"), 4))
	theme.set_stylebox("disabled", "Button", DARK_THEME.surface(Color("15130f"), Color("3d3529"), 4))
	var focus := DARK_THEME.surface(Color.TRANSPARENT, Color("c1af7e"), 4)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	for state in ["font_color", "font_hover_color", "font_focus_color",
			"font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "Button", BONE)
	theme.set_color("font_disabled_color", "Button", Color("988973"))
	theme.set_color("font_color", "Label", BONE)
	theme.set_stylebox("panel", "TooltipPanel", DARK_THEME.surface(Color("14100c"), EDGE, 6))
	return theme


static func keycap() -> StyleBoxFlat:
	return DARK_THEME.surface(Color("17140e"), EDGE, 2)


static func style_pause_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_color_override("font_hover_color", Color("fff0cd"))
	button.add_theme_color_override("font_focus_color", Color("ffdb92"))
	button.add_theme_color_override("font_pressed_color", Color("d9b47c"))
	button.add_theme_color_override("font_hover_pressed_color", Color("d9b47c"))


static func apply_frame(panel: PanelContainer, piece: Frame) -> void:
	var definition: Array = FRAMES[piece]
	var frame := StyleBoxTexture.new()
	frame.texture = definition[0]
	var outset: Vector4 = definition[1]
	var slice: Vector4 = definition[2]
	var padding: Vector4 = definition[3]
	# Store each complete border, including its branches, as a single nine-patch.
	# The outsets draw outside the input rectangle without creating mouse targets.
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_expand_margin(side, outset[side])
		frame.set_texture_margin(side, slice[side])
		frame.set_content_margin(side, padding[side])
	panel.add_theme_stylebox_override("panel", frame)


static func apply_roster_frame(panel: PanelContainer, title: Label) -> void:
	panel.anchor_right = panel.anchor_left
	panel.offset_right = panel.offset_left + ROSTER_WIDTH
	title.custom_minimum_size.y = 22.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var padding := StyleBoxEmpty.new()
	padding.set_content_margin(SIDE_LEFT, 14)
	padding.set_content_margin(SIDE_TOP, ROSTER_TOP_PADDING)
	padding.set_content_margin(SIDE_RIGHT, 16)
	padding.set_content_margin(SIDE_BOTTOM, ROSTER_BOTTOM_PADDING)
	panel.add_theme_stylebox_override("panel", padding)
	panel.draw.connect(_draw_roster_frame.bind(panel, title))
	panel.resized.connect(panel.queue_redraw)


static func _draw_roster_frame(panel: PanelContainer, title: Label) -> void:
	var empty_height := title.get_combined_minimum_size().y + ROSTER_TOP_PADDING + ROSTER_BOTTOM_PADDING
	var extension := panel.size.y - empty_height
	var origin := Vector2(-ROSTER_LEFT_OUTSET, panel.size.y + ROSTER_BOTTOM_OUTSET - ROSTER_TOP.size.y)
	if extension <= 0.0:
		panel.draw_texture(ROSTER_EMPTY, origin)
		return

	# The upper-left branch travels with the top. The lower-right branch stays at the base.
	panel.draw_texture_rect_region(ROSTER_GROWTH,
		Rect2(origin + Vector2(16, 71 - extension), Vector2(207, 26 + extension)), ROSTER_BACKDROP)
	var edge_top := origin.y + 77.0 - extension
	var tile_bottom := origin.y + 87.0
	while tile_bottom > edge_top:
		var tile_top := maxf(edge_top, tile_bottom - ROSTER_LEFT.size.y)
		var tile_size := Vector2(ROSTER_LEFT.size.x, tile_bottom - tile_top)
		panel.draw_texture_rect_region(ROSTER_GROWTH,
			Rect2(Vector2(origin.x + 4, tile_top), tile_size),
			Rect2(Vector2(ROSTER_LEFT.position.x, ROSTER_LEFT.end.y - tile_size.y), tile_size))
		panel.draw_texture_rect_region(ROSTER_GROWTH,
			Rect2(Vector2(origin.x + 210, tile_top), tile_size),
			Rect2(Vector2(ROSTER_RIGHT.position.x, ROSTER_RIGHT.end.y - tile_size.y), tile_size))
		tile_bottom = tile_top
	panel.draw_texture_rect_region(ROSTER_GROWTH,
		Rect2(origin - Vector2(0, extension), ROSTER_TOP.size), ROSTER_TOP)
	panel.draw_texture_rect_region(ROSTER_GROWTH, Rect2(origin, ROSTER_BOTTOM.size), ROSTER_BOTTOM)


static func apply_hotbar_frame(panel: PanelContainer) -> void:
	var padding := StyleBoxEmpty.new()
	padding.set_content_margin(SIDE_LEFT, 19)
	padding.set_content_margin(SIDE_RIGHT, 19)
	padding.set_content_margin(SIDE_TOP, 4)
	padding.set_content_margin(SIDE_BOTTOM, 6)
	panel.add_theme_stylebox_override("panel", padding)
	panel.draw.connect(_draw_hotbar_frame.bind(panel))
	panel.resized.connect(panel.queue_redraw)


static func _draw_hotbar_frame(panel: PanelContainer) -> void:
	var height := float(HOTBAR_FRAME.get_height())
	var top := panel.size.y - HOTBAR_BOTTOM_IN_TEXTURE
	var left := -HOTBAR_OUTSET_LEFT
	var right := panel.size.x + HOTBAR_OUTSET_RIGHT
	var center_left := panel.size.x * 0.5 - (HOTBAR_CUTS[3] - HOTBAR_CUTS[2]) * 0.5
	var center_right := center_left + HOTBAR_CUTS[3] - HOTBAR_CUTS[2]
	var edges := [left, left + HOTBAR_CUTS[1], center_left, center_right,
		right - (HOTBAR_CUTS[5] - HOTBAR_CUTS[4]), right]
	for index in HOTBAR_CUTS.size() - 1:
		var source := Rect2(HOTBAR_CUTS[index], 0, HOTBAR_CUTS[index + 1] - HOTBAR_CUTS[index], height)
		var dest := Rect2(edges[index], top, edges[index + 1] - edges[index], height)
		panel.draw_texture_rect_region(HOTBAR_FRAME, dest, source)
