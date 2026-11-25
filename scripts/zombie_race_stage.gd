extends Control

const ZOMBIE_PREVIEW = preload("res://scripts/zombie_race_preview.gd")
const CEMETERY_PATH := "res://assets/ui/zombie_race_cemetery_v2.png"
const PORTRAIT_DIR := "res://assets/ui/zombie_race/"
# The order matches ordinary zombie appearance IDs. Joints are in the rest drawing.
const PORTRAITS := [
	{"name": "plain", "height": 462.0, "ground": Vector2(271, 475), "hip": Vector2(273, 243), "neck": Vector2(297, 93)},
	{"name": "necrosis", "height": 467.0, "ground": Vector2(260, 483), "hip": Vector2(265, 248), "neck": Vector2(289, 96)},
	{"name": "wounded", "height": 486.0, "ground": Vector2(249, 500), "hip": Vector2(270, 272), "neck": Vector2(294, 104)},
	{"name": "bloom", "height": 482.0, "ground": Vector2(268, 497), "hip": Vector2(275, 264), "neck": Vector2(303, 97)},
]

# These points mark open ground in the cemetery texture, from back to front.
const FOOT_POSITIONS := [Vector2(0.78, 0.57), Vector2(0.22, 0.64), Vector2(0.50, 0.80)]
const RELATIVE_HEIGHTS := [0.32, 0.42, 1.0]

var appearances: Array[int] = []
var _actors: Array[ZOMBIE_PREVIEW] = []
var _cemetery_size: Vector2
var _shadow_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := TextureRect.new()
	backdrop.texture = load(CEMETERY_PATH)
	_cemetery_size = backdrop.texture.get_size()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shadow_gradient := Gradient.new()
	shadow_gradient.offsets = PackedFloat32Array([0.0, 0.32, 0.66, 1.0])
	shadow_gradient.colors = PackedColorArray([
		Color(0.07, 0.04, 0.05, 0.81), Color(0.09, 0.05, 0.05, 0.62),
		Color(0.11, 0.07, 0.06, 0.23), Color(0.11, 0.07, 0.06, 0.0),
	])
	_shadow_texture = GradientTexture2D.new()
	_shadow_texture.gradient = shadow_gradient
	_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	_shadow_texture.fill_from = Vector2(0.5, 0.5)
	_shadow_texture.fill_to = Vector2(1.0, 0.5)
	_shadow_texture.width = 128
	_shadow_texture.height = 64

	_add_actor("Distant", appearances[2], 12.1, 0.90, Color("b8a5a9"), 0.16, true)
	_add_actor("Near", appearances[1], 5.4, 0.95, Color("c4afa7"), 0.06)
	_add_actor("Foreground", appearances[0], 0.0, 1.0, Color("dfccbd"), 0.0)
	resized.connect(_layout_actors)
	_layout_actors()


func _add_actor(actor_name: String, appearance: int, phase: float, pace: float, tint: Color, haze: float, mirrored := false) -> void:
	var actor := ZOMBIE_PREVIEW.new()
	actor.name = actor_name
	actor.appearance = appearance
	actor.modulate = tint
	var portrait: Dictionary = PORTRAITS[appearance]
	var atlas := load(PORTRAIT_DIR + portrait.name + ".png") as Texture2D
	actor.set_portrait(atlas, portrait.ground, portrait.hip, portrait.neck, portrait.height, phase, pace, haze, mirrored)
	_actors.append(actor)
	add_child(actor)
	var facing := -1.0 if mirrored else 1.0
	_add_shadow(actor, Vector2(0.045, -0.020), Vector2(0.39, 0.12))
	_add_shadow(actor, Vector2(-0.035 * facing, 0.0), Vector2(0.16, 0.036))
	_add_shadow(actor, Vector2(0.094 * facing, -0.060), Vector2(0.17, 0.038))


func _add_shadow(actor: ZOMBIE_PREVIEW, center: Vector2, extent: Vector2) -> void:
	var shadow := TextureRect.new()
	shadow.texture = _shadow_texture
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	actor.add_child(shadow)
	shadow.position = (center - extent * 0.5) * actor.portrait_height
	shadow.size = extent * actor.portrait_height


func _layout_actors() -> void:
	var portrait_height := minf(size.y * 0.64, size.x * 0.77)
	var art_scale := maxf(size.x / _cemetery_size.x, size.y / _cemetery_size.y)
	var drawn_size := _cemetery_size * art_scale
	var background_origin := (size - drawn_size) * 0.5
	for index in _actors.size():
		var actor := _actors[index]
		actor.scale = Vector2.ONE * portrait_height * RELATIVE_HEIGHTS[index] / actor.portrait_height
		actor.position = background_origin + FOOT_POSITIONS[index] * drawn_size
