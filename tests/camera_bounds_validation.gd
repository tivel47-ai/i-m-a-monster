# Godot --headless --path . --script tests/camera_bounds_validation.gd --fixed-fps 60
extends "res://tests/camera_zoom_validation.gd"


func check_view(label: String) -> void:
	# Inspect actual rendered canvas corners, independently of the clamp formula.
	var rect := root.get_visible_rect()
	var inverse := root.canvas_transform.affine_inverse()
	var valid := true
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var world: Vector2 = inverse * corner
		valid = valid and camera.map_bounds.grow(0.001).has_point(world)
	check(valid, "All viewport corners inside visual map: " + label)


func run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	map = main.get_node("test_map")
	camera = map.get_node("Camera2D")
	await frames(5)
	camera.set_process(false)
	check(camera.map_bounds == Rect2(0, 0, 1280, 720), "Default map bounds describe visual ground, not navigation")
	check_view("startup")
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		key(code, true)
		camera._process(1.0)
		key(code, false)
	check(camera.position.is_equal_approx(Vector2(640, 360)), "Full-map view cannot pan beyond any edge")

	for level in [1.5, 2.0]:
		camera.position = Vector2(640, 360)
		camera._set_zoom_level(level)
		for code in [KEY_A, KEY_D, KEY_W, KEY_S]:
			key(code, true)
			camera._process(10.0)
			check_view("held key %s, zoom %s" % [code, level])
			var stopped := camera.position
			for index in range(5):
				camera._process(0.1)
			check(camera.position.is_equal_approx(stopped), "Held movement at edge remains stable")
			key(code, false)
			var opposite := {KEY_A: KEY_D, KEY_D: KEY_A, KEY_W: KEY_S, KEY_S: KEY_W}
			key(opposite[code], true)
			camera._process(0.01)
			key(opposite[code], false)
			check(camera.position.distance_to(stopped) > 4.99, "Movement away from edge resumes immediately")
		camera.position = Vector2(640, 360)
		camera._set_zoom_level(level)
		key(KEY_A, true)
		camera._process(10.0)
		key(KEY_A, false)
		var before := camera.position
		key(KEY_W, true)
		camera._process(0.05)
		key(KEY_W, false)
		check(is_equal_approx(camera.position.x, before.x) and is_equal_approx(camera.position.y, before.y - 25.0), "Parallel movement along left edge keeps speed")
		for horizontal in [KEY_A, KEY_D]:
			for vertical in [KEY_W, KEY_S]:
				key(horizontal, true)
				key(vertical, true)
				camera._process(10.0)
				for index in range(12):
					wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(20, 20))
					camera._process(0.01)
					check_view("diagonal into corner while zooming out")
				key(horizontal, false)
				key(vertical, false)
				wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(1260, 700))
				check_view("zoom in from corner")
				camera._set_zoom_level(level)

	# Interior zoom retains its center; near an edge it moves only as far as needed.
	camera.position = Vector2(640, 360)
	camera._set_zoom_level(2.0)
	var center := center_world()
	wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(10, 10))
	check(center_world().is_equal_approx(center), "Interior zoom keeps viewport center independent of cursor")
	camera.position = Vector2(-10000, -10000)
	camera._set_zoom_level(2.0)
	for cursor in [Vector2(10, 10), Vector2(1260, 700)]:
		camera.position = Vector2(-10000, -10000)
		camera._set_zoom_level(2.0)
		wheel(MOUSE_BUTTON_WHEEL_DOWN, cursor)
		check_view("nearest valid position after edge zoom out")
		var corner_world := root.canvas_transform.affine_inverse() * Vector2.ZERO
		check(corner_world.length() <= 0.001, "Zoom-out edge correction is nearest and cursor-independent")

	for size in [Vector2i(1280, 720), Vector2i(1920, 720), Vector2i(1280, 1000), Vector2i(4000, 500), Vector2i(500, 2000)]:
		for requested_zoom in [1.0, 2.0]:
			camera._set_zoom_level(requested_zoom)
			root.size = size
			# size_changed must correct the view without waiting for a process frame.
			check_view("immediately after resize to %s" % size)
			await frames(2)
			check_view("after resize frames %s" % size)
			for index in range(30):
				wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(10, 10))
			check_view("minimum effective zoom %s" % size)
			var minimum := camera.zoom.x
			wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(10, 10))
			check(is_equal_approx(camera.zoom.x, minimum), "Repeated zoom out stops at effective minimum")
			for index in range(30):
				wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(10, 10))
			check(is_equal_approx(camera.zoom.x, maxf(2.0, minimum)), "Maximum stays 2 unless fitting viewport requires more")
			check_view("maximum effective zoom %s" % size)

	root.size = Vector2i(1280, 720)
	await frames(2)
	camera._set_zoom_level(1.0)
	check(camera.zoom.is_equal_approx(Vector2.ONE), "Normal window restores configured zoom range")
	# A future larger map with nonzero world origin, and an optional camera offset.
	var original_bounds: Rect2 = camera.map_bounds
	camera.map_bounds = Rect2(-300, 150, 2560, 1440)
	camera.offset = Vector2(23, -17)
	for position in [Vector2(-10000, -10000), Vector2(10000, 10000)]:
		camera.position = position
		camera._set_zoom_level(1.0)
		check_view("larger shifted map with camera offset")
	camera.offset = Vector2.ZERO
	camera.map_bounds = original_bounds

	# Freeze AI only in the fixture, preserving physics queries and real map navigation.
	var units := get_nodes_in_group("player_units")
	for unit in units + map.villagers:
		unit.set_physics_process(false)
	var areas := [
		[Vector2(640, 360), Vector2(640, 360)],
		[Vector2(-10000, 360), Vector2(320, 360)],
		[Vector2(10000, 360), Vector2(960, 360)],
		[Vector2(640, -10000), Vector2(620, 130)],
		[Vector2(640, 10000), Vector2(620, 590)],
	]
	for level in [1.0, 2.0]:
		for area in areas:
			camera.position = area[0]
			camera._set_zoom_level(level)
			for index in range(units.size()):
				units[index].position = area[1] + Vector2([-60, 0, 100][index], 0)
			await frames(3)
			var label := " / center %s / zoom %s" % [camera.position, level]
			var click := screen(units[0].global_position)
			check(root.get_visible_rect().has_point(click), "Input test zombie is visible" + label)
			mouse(MOUSE_BUTTON_LEFT, true, click)
			mouse(MOUSE_BUTTON_LEFT, false, click)
			await frames(2)
			check(units[0].is_selected and not units[1].is_selected, "Single selection" + label)
			var target: Vector2 = area[1] + Vector2(-20, 0)
			mouse(MOUSE_BUTTON_RIGHT, true, screen(target))
			mouse(MOUSE_BUTTON_RIGHT, false, screen(target))
			check(units[0].target_position.is_equal_approx(target), "RMB world destination" + label)
			var start := screen(units[0].global_position - Vector2(20, 30))
			var end := screen(units[1].global_position + Vector2(20, 30))
			mouse(MOUSE_BUTTON_LEFT, true, start)
			mouse(MOUSE_BUTTON_LEFT, false, end)
			await frames(2)
			check(units[0].is_selected and units[1].is_selected and not units[2].is_selected, "Marquee selection" + label)
			mouse(MOUSE_BUTTON_RIGHT, true, screen(target), true)
			mouse(MOUSE_BUTTON_RIGHT, false, screen(target), true)
			check(units[0].has_player_order and units[1].has_player_order and not units[0].target_position.is_equal_approx(units[1].target_position), "Shift RMB distinct group targets" + label)

	# Drag while pressing into the lower edge and zooming out, then change zoom
	# once more before deferred selection executes.
	var start := screen(units[0].global_position - Vector2(20, 30))
	mouse(MOUSE_BUTTON_LEFT, true, start)
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_stretch_transform() * screen(units[1].global_position + Vector2(20, 30))
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	camera.set_process(true)
	key(KEY_S, true)
	wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(10, 10))
	await frames(5)
	key(KEY_S, false)
	camera.set_process(false)
	check_view("real frame processing against edge during drag and zoom")
	check(map.selection_rect.visible and map.selection_rect.position.is_equal_approx(start), "Screen marquee stays anchored during edge clamp")
	var end := screen(units[1].global_position + Vector2(20, 30))
	mouse(MOUSE_BUTTON_LEFT, false, end)
	wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(1260, 700))
	await frames(2)
	check(units[0].is_selected and units[1].is_selected and not units[2].is_selected, "Edge drag selects release-time region despite later camera correction")

	main.queue_free()
	await frames(2)
	print("Camera bounds validation failures: ", failures)
	quit(1 if failures else 0)
