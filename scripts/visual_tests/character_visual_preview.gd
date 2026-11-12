extends Node2D

# Isolated visual comparison; the instanced gameplay scene is not edited.
@export var character_path: NodePath
@export var sprite_offset := Vector2.ZERO
@export var show_sprite := true
@export var initial_camera_zoom := 2.0

@onready var village: Node2D = $VillageSimulationMap
@onready var preview_sprite: Sprite2D = $CharacterPreview

var placeholder: Polygon2D
var original_placeholder_visible := true


func _ready() -> void:
	var character := village.get_node_or_null(character_path) as CharacterBody2D
	if character == null:
		push_error("Character visual preview target is missing: %s" % character_path)
		preview_sprite.hide()
		return

	placeholder = character.get_node_or_null("Polygon2D") as Polygon2D
	if placeholder == null:
		push_error("Character visual preview placeholder is missing: %s" % character_path)
		preview_sprite.hide()
		return

	original_placeholder_visible = placeholder.visible
	preview_sprite.reparent(character, false)
	preview_sprite.position = sprite_offset
	_set_preview_enabled(show_sprite)

	# Preview framing only; the camera controller script is unchanged.
	var camera := village.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * initial_camera_zoom
	camera.global_position = character.global_position


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		show_sprite = not show_sprite
		_set_preview_enabled(show_sprite)


func _set_preview_enabled(enabled: bool) -> void:
	if placeholder == null:
		return
	preview_sprite.visible = enabled
	placeholder.visible = original_placeholder_visible and not enabled
