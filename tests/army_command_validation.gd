extends SceneTree

var failures := 0
var map: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else: print("PASS: ", message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func rmb(pressed: bool, point: Vector2, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.position = root.get_canvas_transform() * point
	event.shift_pressed = shift
	map._input(event)

func run() -> void:
	map = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	map.set_process(false)
	var units := get_nodes_in_group("player_units")
	for unit in units:
		unit.set_selected(false)
		unit.move_speed = 0.0
	for resident in map.villagers:
		resident.autonomous_movement_enabled = false
		resident.set_physics_process(false)
		resident.position = Vector2(1100, 600)
	await frames(5)
	rmb(true, Vector2(240, 350))
	check(not map.command_active, "No selection: no preview")
	units[0].set_selected(true)
	rmb(false, Vector2(240, 350))
	check(not units[0].has_player_order, "Selection after unarmed press cannot issue command")
	rmb(true, Vector2(240, 350))
	check(map.command_active and not units[0].has_player_order, "Press previews without dispatch")
	map._update_command_preview(0.25)
	check(is_equal_approx(map.command_radius, map.command_initial_radius + 0.25 * map.command_growth_speed), "Linear world radius growth")
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_stretch_transform() * root.get_canvas_transform() * Vector2(430, 360)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	map._update_command_preview(0.0)
	check(map.command_center.is_equal_approx(Vector2(430, 360)), "Preview follows current cursor")
	map._update_command_preview(100.0)
	check(map.command_radius == 180.0, "Radius capped")
	rmb(false, Vector2(430, 360))
	check(units[0].has_player_order and units[0].target_position.distance_to(Vector2(430, 360)) <= 180.0, "Release uses final area")
	var previous: Vector2 = units[0].target_position
	rmb(true, Vector2(240, 350))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	map._input(escape)
	rmb(false, Vector2(240, 350))
	check(units[0].target_position == previous, "Escape preserves existing order")
	rmb(true, Vector2(240, 350))
	map._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	rmb(false, Vector2(240, 350))
	check(units[0].target_position == previous, "Focus loss cancels preview")
	rmb(true, Vector2(240, 350), true)
	check(map.command_radius == 24.0, "Shift has no separate command")
	rmb(false, Vector2(240, 350), true)
	check(units[0].target_position.distance_to(Vector2(240, 350)) <= 24.0, "Quick release still distributes in small area")
	var target = map.villagers[0]
	var second = map.villagers[1]
	target.position = Vector2(700, 360)
	second.position = Vector2(730, 360)
	units[0].position = Vector2(150, 360)
	units[1].set_selected(true)
	map._issue_command(Vector2(715, 360), 40.0)
	check(units[0].priority_targets.size() == 2 and units[1].priority_targets.size() == 2, "Every captured target retained by each recipient")
	check(units[0].aggro_target != units[1].aggro_target, "Initial attackers distributed across targets")
	check(units[0].aggro_target == target and units[0].has_target, "Explicit target acquired beyond normal detection")
	check(units[0].navigation_agent.target_position.distance_to(target.position) < 30.0, "Navigation aims at target")
	target.position += Vector2(50, 0)
	units[0]._update_aggro_target(0.1)
	check(units[0].aggro_destination_origin == target.position, "Attack follows moving target")
	target.take_damage(10000.0)
	units[0]._update_aggro_target(0.1)
	check(units[0].priority_targets.size() == 1 and units[0].aggro_target == second, "Death retargets surviving designated enemy")
	units[0].issue_player_area_move_order(Vector2(240, 350))
	check(units[0].priority_targets.is_empty(), "New movement clears only recipient's designation")
	check(not units[1].priority_targets.is_empty(), "Other attack recipients retain designation")
	units[0].aggro_candidates.assign([second])
	units[0]._update_aggro_target(1.0)
	check(units[0].has_player_order and units[0].aggro_target == null, "Movement ignores nearby automatic aggression")
	second.position = Vector2(430, 360)
	units[1].position = second.position + Vector2(-30, 0)
	units[1].infection_chance = 0.0
	units[1].move_speed = 100.0
	await frames(2)
	var remaining: Array[Node2D] = [second]
	units[1].issue_player_attack_order(remaining)
	await frames(300)
	check(second.current_health < second.max_health, "Priority attack executes actual melee damage")
	check(units[1].priority_targets.has(second), "Priority persists during combat")
	second.take_damage(10000.0)
	units[1]._update_aggro_target(0.1)
	check(units[1].priority_targets.is_empty() and not units[1].has_target, "All targets gone completes attack")
	map.queue_free()
	await frames(2)
	print("Army command failures: ", failures)
	quit(1 if failures else 0)
