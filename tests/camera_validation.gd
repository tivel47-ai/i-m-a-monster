# Godot --headless --path . --script tests/camera_validation.gd --fixed-fps 60
extends SceneTree

var failures := 0
var map: Node2D
var camera: Camera2D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)


func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(button: MouseButton, pressed: bool, position: Vector2, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func screen(world: Vector2) -> Vector2:
	return root.get_canvas_transform() * world


func run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	map = main.get_node("test_map")
	camera = map.get_node("Camera2D")
	await frames(5)
	check(camera.is_current(), "Gameplay camera is active")
	check(root.canvas_transform.is_equal_approx(Transform2D.IDENTITY), "Initial view preserves original coordinates")
	# Isolate unrestricted Stage 1 movement; real map limits have their own suite.
	camera.map_bounds = Rect2(-10000, -10000, 20000, 20000)
	camera.set_process(false)
	var codes := [KEY_W, KEY_A, KEY_S, KEY_D]
	var actions := ["camera_up", "camera_left", "camera_down", "camera_right"]
	var directions := [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
	for index in range(codes.size()):
		check(InputMap.has_action(actions[index]), "Input action exists: " + actions[index])
		camera.position = Vector2.ZERO
		key(codes[index], true)
		camera._process(0.2)
		camera._process(0.3)
		check(camera.position.is_equal_approx(directions[index] * 250.0), "Held physical key moves continuously: " + actions[index])
		key(codes[index], false)
		var stopped := camera.position
		camera._process(1.0)
		check(camera.position.is_equal_approx(stopped), "Release stops immediately: " + actions[index])

	camera.position = Vector2.ZERO
	key(KEY_W, true)
	key(KEY_D, true)
	camera._process(1.0)
	check(camera.position.is_equal_approx(Vector2(1, -1).normalized() * 500.0), "Diagonal has cardinal speed")
	key(KEY_D, false)
	key(KEY_S, true)
	var stopped := camera.position
	camera._process(1.0)
	check(camera.position.is_equal_approx(stopped), "W + S cancel")
	key(KEY_A, true)
	key(KEY_D, true)
	camera._process(1.0)
	check(camera.position.is_equal_approx(stopped), "All opposing keys cancel")
	key(KEY_W, false)
	key(KEY_S, false)
	camera._process(1.0)
	check(camera.position.is_equal_approx(stopped), "A + D cancel")
	key(KEY_A, false)
	key(KEY_D, false)
	for scale in [0.5, 1.0, 2.0]:
		camera.zoom = Vector2.ONE * scale
		camera.position = Vector2.ZERO
		key(KEY_D, true)
		camera._process(1.0)
		key(KEY_D, false)
		check(camera.position.is_equal_approx(Vector2(500, 0)), "World speed independent of test zoom: " + str(scale))
	camera.zoom = Vector2.ONE
	camera.position = Vector2.ZERO
	camera.set_process(true)
	key(KEY_D, true)
	await frames(5)
	key(KEY_D, false)
	check(camera.position.x > 0.0, "Frame processing moves camera without selected units")
	camera.set_process(false)

	# Keep units still so input compatibility assertions do not depend on AI timing.
	var units := get_nodes_in_group("player_units")
	for unit in units + map.villagers:
		unit.set_physics_process(false)
	for index in range(units.size()):
		units[index].position = Vector2(130 + index * 60, 360)
	await frames(3)
	camera.position = Vector2(70, 40)
	camera.force_update_scroll()
	var click := screen(units[0].global_position)
	mouse(MOUSE_BUTTON_LEFT, true, click)
	mouse(MOUSE_BUTTON_LEFT, false, click)
	# Simulate the camera advancing before deferred selection executes.
	camera.position += Vector2(10, 0)
	camera.force_update_scroll()
	await frames(2)
	check(units[0].is_selected and not units[1].is_selected, "LMB selects correct zombie using release-time transform")
	var destination := Vector2(240, 350)
	mouse(MOUSE_BUTTON_RIGHT, true, screen(destination))
	mouse(MOUSE_BUTTON_RIGHT, false, screen(destination))
	check(units[0].target_position.is_equal_approx(destination) and units[0].has_player_order, "RMB uses world destination after pan")

	var start := screen(Vector2(100, 330))
	mouse(MOUSE_BUTTON_LEFT, true, start)
	key(KEY_D, true)
	camera._process(0.02)
	key(KEY_D, false)
	camera.force_update_scroll()
	var end := screen(Vector2(215, 390))
	var motion := InputEventMouseMotion.new()
	motion.position = end
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	check(map.selection_rect.visible and map.selection_rect.position.is_equal_approx(start), "Marquee stays anchored to screen during camera movement")
	mouse(MOUSE_BUTTON_LEFT, false, end)
	await frames(2)
	check(units[0].is_selected and units[1].is_selected and not units[2].is_selected, "Marquee selects release-time visible world region after pan during drag")
	check(not map.selection_rect.visible, "Marquee hides on release")

	mouse(MOUSE_BUTTON_RIGHT, true, screen(Vector2(400, 360)), true)
	mouse(MOUSE_BUTTON_RIGHT, false, screen(Vector2(400, 360)), true)
	check(units[0].has_player_order and units[1].has_player_order and not units[0].target_position.is_equal_approx(units[1].target_position), "Shift + RMB assigns distinct group destinations after pan")
	main.queue_free()
	await frames(2)
	print("Camera validation failures: ", failures)
	quit(1 if failures else 0)
