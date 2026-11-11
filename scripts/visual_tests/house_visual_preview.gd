extends Node2D

# Preview only. No changes to the instanced map's collision or navigation.
@export var show_house_sprite := true

const COTTAGE_PATH := "NavigationRegion2D/Buildings/Residential/Cottage05"
const SPRITE_OFFSET := Vector2(-30, -26)

@onready var village: Node2D = $VillageSimulationMap
@onready var preview_sprite: Sprite2D = $HousePreview

var placeholder_visibility: Dictionary = {}


func _ready() -> void:
	var cottage: StaticBody2D = village.get_node(COTTAGE_PATH)
	for child in cottage.get_children():
		if child is CanvasItem:
			placeholder_visibility[child] = child.visible

	preview_sprite.reparent(cottage, false)
	preview_sprite.position = SPRITE_OFFSET
	_set_preview_enabled(show_house_sprite)

	# Focus the existing camera on the test building for visual inspection.
	var camera: Camera2D = village.get_node("Camera2D")
	camera.position = cottage.position + Vector2(0, 100)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		show_house_sprite = not show_house_sprite
		_set_preview_enabled(show_house_sprite)


func _set_preview_enabled(enabled: bool) -> void:
	preview_sprite.visible = enabled
	for item: CanvasItem in placeholder_visibility:
		item.visible = false if enabled else placeholder_visibility[item]
