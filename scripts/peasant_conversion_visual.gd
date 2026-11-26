extends Sprite2D

signal finished

const PEASANT = preload("res://scripts/peasant_visual.gd")
const ZOMBIE_ART = preload("res://assets/sprites/characters/ordinary_zombie/frames.gd")
const TRANSITION_ATLAS = preload("res://assets/sprites/characters/peasant/conversion.png")
const FRAME_COUNT := 24
const FRAMES_PER_SECOND := 11.0
const DURATION := FRAME_COUNT / FRAMES_PER_SECOND
const ATLAS_COLUMNS := 8
const VARIANT_START := 16
const VARIANT_FRAMES := 7
const NON_BASE_APPEARANCES := 3
const FIRST_VARIANT_CELL := FRAME_COUNT - 2
const SOUTHEAST := 1
const SOUTHWEST := 7

var appearance: int = ZOMBIE_ART.Appearance.PLAIN
var faces_west := false
var _elapsed := 0.0
var _frame := -1


func idle_direction() -> int:
	return SOUTHWEST if faces_west else SOUTHEAST


func _ready() -> void:
	centered = false
	region_enabled = true
	region_filter_clip_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	scale = Vector2.ONE * (PEASANT.WORLD_HEIGHT / PEASANT.FRAME_HEIGHT)
	position.y += PEASANT.FEET_Y
	offset = -PEASANT.ANCHOR
	_show_frame(0)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var frame := mini(int(_elapsed * FRAMES_PER_SECOND), FRAME_COUNT - 1)
	if frame != _frame:
		_show_frame(frame)
	if _elapsed >= DURATION:
		set_physics_process(false)
		finished.emit()


func _show_frame(frame: int) -> void:
	_frame = frame
	if frame == 0:
		# The peasant turntable has a separately drawn pose for each of these diagonals.
		_display(PEASANT.ATLAS, Vector2(6, 1) if faces_west else Vector2(2, 0), false)
	elif frame == FRAME_COUNT - 1:
		var views: Array = ZOMBIE_ART.VIEWS[appearance]
		var mirror := faces_west and views.size() == 2
		_display(views[3 if faces_west and not mirror else 0], Vector2.ZERO, mirror)
	elif frame >= VARIANT_START and appearance != ZOMBIE_ART.Appearance.PLAIN:
		var variant_row := appearance - 1 + (NON_BASE_APPEARANCES if faces_west else 0)
		var cell := FIRST_VARIANT_CELL + variant_row * VARIANT_FRAMES + frame - VARIANT_START
		_display_transition(cell, false)
	else:
		_display_transition(frame - 1, faces_west)


func _display_transition(cell: int, mirror: bool) -> void:
	@warning_ignore("integer_division")
	var row := cell / ATLAS_COLUMNS
	_display(TRANSITION_ATLAS, Vector2(cell % ATLAS_COLUMNS, row), mirror)


func _display(atlas: Texture2D, cell: Vector2, mirror: bool) -> void:
	texture = atlas
	region_rect = Rect2(cell * PEASANT.CELL, PEASANT.CELL)
	flip_h = mirror
