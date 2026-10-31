# Godot --headless --path . --script tests/camera_zoom_validation.gd --fixed-fps 60
extends "res://tests/camera_validation.gd"


func mouse(button: MouseButton, pressed: bool, position: Vector2, shift := false) -> void:
	# Parsed OS events are in window pixels, before Godot applies stretch.
	super.mouse(button, pressed, root.get_stretch_transform() * position, shift)


func wheel(button: MouseButton, cursor: Vector2) -> void:
	mouse(button, true, cursor)
	mouse(button, false, cursor)


func center_world() -> Vector2:
	return root.canvas_transform.affine_inverse() * root.get_visible_rect().get_center()


func run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	map = main.get_node("test_map")
	camera = map.get_node("Camera2D")
	await frames(5)
	camera.set_process(false)
	check(root.canvas_transform.is_equal_approx(Transform2D.IDENTITY), "Initial view unchanged at 1280 x 720")
	# Isolate center-based zoom from the intentional Stage 3 edge corrections.
	camera.map_bounds = Rect2(-10000, -10000, 20000, 20000)
	var units := get_nodes_in_group("player_units")
	for unit in units + map.villagers:
		unit.set_physics_process(false)
	units[0].position = Vector2(440, 360)
	units[1].position = Vector2(500, 360)
	units[2].position = Vector2(620, 360)
	await frames(3)
	camera.position = Vector2(500, 360)
	camera.force_update_scroll()
	var origin := camera.position
	var center := center_world()
	for cursor in [Vector2(10, 10), Vector2(1270, 710), Vector2(640, 360)]:
		wheel(MOUSE_BUTTON_WHEEL_UP, cursor)
		check(is_equal_approx(camera.zoom.x, 1.15) and camera.zoom.is_equal_approx(Vector2.ONE * 1.15), "Wheel up applies uniform discrete step of 0.15")
		check(center_world().is_equal_approx(center) and camera.position.is_equal_approx(origin), "Zoom stays at viewport center independent of cursor")
		wheel(MOUSE_BUTTON_WHEEL_DOWN, cursor)
		check(camera.zoom.is_equal_approx(Vector2.ONE), "Wheel down reverses step")
	for index in range(50):
		wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(10, 10))
	check(camera.zoom.is_equal_approx(Vector2.ONE * camera.max_zoom), "Repeated wheel up stops at maximum")
	for index in range(50):
		wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(1270, 710))
	check(camera.zoom.is_equal_approx(Vector2.ONE * camera.min_zoom), "Repeated wheel down stops at minimum")
	check(camera.position.is_equal_approx(origin) and center_world().is_equal_approx(center), "Repeated zoom does not drift")

	for diagonal in [false, true]:
		key(KEY_W, true)
		if diagonal:
			key(KEY_D, true)
		var before := camera.position
		wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(1270, 10))
		check(camera.position.is_equal_approx(before), "Zoom with held WASD does not jump")
		camera._process(0.1)
		wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(10, 710))
		camera._process(0.1)
		var direction := Vector2(1, -1).normalized() if diagonal else Vector2.UP
		check(camera.position.is_equal_approx(before + direction * camera.move_speed * 0.2), "WASD keeps world speed and normalized diagonal across zoom")
		key(KEY_W, false)
		key(KEY_D, false)
		before = camera.position
		wheel(MOUSE_BUTTON_WHEEL_UP, Vector2.ZERO)
		camera._process(0.1)
		check(camera.position.is_equal_approx(before), "Releasing WASD stops while zooming")

	# Exercise real frame callbacks together with wheel input.
	camera.set_process(true)
	key(KEY_W, true)
	var before := camera.position
	wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(10, 10))
	await frames(5)
	key(KEY_W, false)
	camera.set_process(false)
	check(camera.position.y < before.y and is_equal_approx(camera.position.x, before.x), "W and wheel work during frame processing")

	for window_size in [Vector2i(1280, 720), Vector2i(1600, 1000)]:
		root.size = window_size
		await frames(2)
		for level in [camera.min_zoom, 1.5, camera.max_zoom]:
			camera.position = Vector2(500, 360)
			camera._set_zoom_level(level)
			var label := " at zoom %s / window %s" % [level, window_size]
			check(center_world().is_equal_approx(camera.global_position), "Viewport center follows camera" + label)
			var click := screen(units[0].global_position)
			check(root.get_visible_rect().has_point(click), "Selection test unit is visible" + label)
			mouse(MOUSE_BUTTON_LEFT, true, click)
			mouse(MOUSE_BUTTON_LEFT, false, click)
			await frames(2)
			check(units[0].is_selected and not units[1].is_selected, "Single LMB selection" + label)
			var destination := Vector2(550, 360)
			mouse(MOUSE_BUTTON_RIGHT, true, screen(destination))
			mouse(MOUSE_BUTTON_RIGHT, false, screen(destination))
			check(units[0].target_position.is_equal_approx(destination), "RMB world destination" + label)
			var start := screen(Vector2(420, 330))
			var end := screen(Vector2(520, 390))
			mouse(MOUSE_BUTTON_LEFT, true, start)
			var motion := InputEventMouseMotion.new()
			motion.position = root.get_stretch_transform() * end
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			check(map.selection_rect.visible and map.selection_rect.position.is_equal_approx(start) and map.selection_rect.size.is_equal_approx(end - start), "Visual marquee matches viewport coordinates" + label)
			mouse(MOUSE_BUTTON_LEFT, false, end)
			await frames(2)
			check(units[0].is_selected and units[1].is_selected and not units[2].is_selected, "Marquee selects visible units" + label)
			mouse(MOUSE_BUTTON_RIGHT, true, screen(Vector2(500, 360)), true)
			mouse(MOUSE_BUTTON_RIGHT, false, screen(Vector2(500, 360)), true)
			check(units[0].has_player_order and units[1].has_player_order and not units[0].target_position.is_equal_approx(units[1].target_position), "Shift RMB distinct group destinations" + label)

	root.size = Vector2i(1280, 720)
	await frames(2)
	camera.position = Vector2(500, 360)
	camera._set_zoom_level(1.0)
	var start := screen(Vector2(400, 330))
	mouse(MOUSE_BUTTON_LEFT, true, start)
	var motion := InputEventMouseMotion.new()
	motion.position = screen(Vector2(520, 390))
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	key(KEY_D, true)
	camera._process(0.02)
	key(KEY_D, false)
	wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(20, 20))
	check(map.selection_rect.position.is_equal_approx(start), "Marquee screen anchor survives pan and zoom during drag")
	var end := screen(Vector2(520, 390))
	mouse(MOUSE_BUTTON_LEFT, false, end)
	# Zoom again before deferred selection: release-time transform must be used.
	wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(1260, 700))
	await frames(2)
	check(units[0].is_selected and units[1].is_selected and not units[2].is_selected, "Marquee uses release-time world region after pan and zoom during drag")
	main.queue_free()
	await frames(2)
	print("Camera zoom validation failures: ", failures)
	quit(1 if failures else 0)
