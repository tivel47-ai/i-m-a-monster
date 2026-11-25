extends RefCounted

enum Growth { OBJECTIVE_CORNER, OBJECTIVE_BASE, ALERT_LEFT, ALERT_RIGHT, ROSTER, HOTBAR_LEFT, HOTBAR_RIGHT, COMMANDS }

const DARK_THEME = preload("res://scripts/dark_fantasy_theme.gd")
const ROOT_FRAME: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_roots.png")
const ROOT_GROWTH: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_necrotic_roots.png")
const ORB_CRADLE: Texture2D = preload("res://assets/ui/zombie_style/mission_hud_necrotic_cradle.png")
const GROWTH_COLUMNS := 4
const GROWTH_CELL := Vector2i(192, 160)
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


static func add_growth(panel: Control, piece: Growth, anchor: Vector2, offset: Vector2, width: float) -> void:
	var texture := AtlasTexture.new()
	texture.atlas = ROOT_GROWTH
	@warning_ignore("integer_division")
	var cell := Vector2i(piece % GROWTH_COLUMNS, piece / GROWTH_COLUMNS)
	texture.region = Rect2(cell * GROWTH_CELL, GROWTH_CELL)
	texture.filter_clip = true
	var behind_panel := piece in [Growth.OBJECTIVE_CORNER, Growth.OBJECTIVE_BASE, Growth.ROSTER, Growth.COMMANDS]
	_mount_roots(panel, texture, Growth.keys()[piece].to_pascal_case(), anchor, offset, width, behind_panel)


static func add_orb_cradle(button: Button) -> void:
	var roots := _mount_roots(button, ORB_CRADLE, "OrbCradle", Vector2(0.5, 1.0), Vector2(0, -54), 136, false)
	# The cradle hugs the glass. The HUD adds the charge counter and keycap above it.
	button.move_child(roots, -1)


static func _mount_roots(control: Control, texture: Texture2D, label: String,
		anchor: Vector2, offset: Vector2, width: float, behind_panel: bool) -> Sprite2D:
	# A Sprite2D follows the control without adding a minimum size or a mouse target.
	var roots := Sprite2D.new()
	roots.name = label
	roots.texture = texture
	roots.scale = Vector2.ONE * (width / texture.get_width())
	roots.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	roots.show_behind_parent = behind_panel
	control.add_child(roots)
	# Roots placed over the frame still draw below the panel's labels and buttons.
	control.move_child(roots, 0)
	var align := func(): roots.position = control.size * anchor + offset
	control.resized.connect(align)
	align.call()
	return roots
