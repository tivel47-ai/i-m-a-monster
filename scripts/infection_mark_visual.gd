extends Sprite2D

const FRAMES_TEXTURE := preload("res://assets/ui/zombie_style/infection_mark_frames.png")
const FRAME_SECONDS := 0.06
const INTRO_FRAME_COUNT := 34
const IDLE_FRAME_COUNT := 25
# Match the emblem and the health bar at the reference screenshot's scale.
const REFERENCE_PIXELS_PER_UNIT := 2.8
const CENTER_ABOVE_HEALTH_BAR := 21.0 / REFERENCE_PIXELS_PER_UNIT
const GRASS_CONTRAST := Color(1.28, 1.35, 1.22)

var frame_time := 0.0


func _ready() -> void:
	texture = FRAMES_TEXTURE
	hframes = 8
	vframes = 8
	scale = Vector2.ONE / REFERENCE_PIXELS_PER_UNIT
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	self_modulate = GRASS_CONTRAST


func _process(delta: float) -> void:
	frame_time += delta
	var next_frame := int(frame_time / FRAME_SECONDS)
	if next_frame >= INTRO_FRAME_COUNT:
		next_frame = INTRO_FRAME_COUNT + (next_frame - INTRO_FRAME_COUNT) % IDLE_FRAME_COUNT
	if frame != next_frame:
		frame = next_frame
