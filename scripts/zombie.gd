extends Node2D

@export var move_speed: float = 100.0

var is_selected: bool = false
var target_position: Vector2
var has_target: bool = false

@onready var input_area: Area2D = $Area2D


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _draw() -> void:
	if is_selected:
		draw_arc(
			Vector2.ZERO,
			24.0,
			0.0,
			TAU,
			32,
			Color.YELLOW,
			2.0
		)


func _ready() -> void:
	input_area.input_pickable = true
	input_area.input_event.connect(_on_input_event)


func _unhandled_input(event: InputEvent) -> void:
	if not is_selected:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			target_position = get_global_mouse_position()
			has_target = true


func _physics_process(delta: float) -> void:
	if not has_target:
		return

	global_position = global_position.move_toward(
		target_position,
		move_speed * delta
	)
	if global_position.is_equal_approx(target_position):
		has_target = false


func _on_input_event(
	_viewport: Viewport,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			set_selected(not is_selected)