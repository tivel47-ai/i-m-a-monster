# Run: Godot --headless --path . --script tests/regression.gd --fixed-fps 60
extends SceneTree

var failures := 0
var map: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	map = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	for resident in map.villagers:
		# Keep command/combat fixtures stationary; civilian movement has its own suite.
		resident.autonomous_movement_enabled = false
		resident.position = Vector2(1100, 600)
	var units = get_nodes_in_group("player_units")
	for i in range(units.size()):
		units[i].position = Vector2(150 + i * 60, 130)
	await frames(5)
	var zombie = units[0]
	var panel: PanelContainer = map.get_node("CanvasLayer/MissionPanel")
	check(panel.size.x <= 251 and panel.size.y <= 90, "Mission panel remains compact: %s" % panel.size)
	check(map.status_label.get_theme_font_size("font_size") == 8, "Mission text uses half-size font")
	var original_status: String = map.status_label.text
	map.status_label.text = original_status.repeat(4)
	await frames(3)
	check(panel.size.x <= 251 and map.status_label.get_line_count() > 2,
		"Long objective wraps without widening panel")
	check(map.status_label.size.y >= map.status_label.get_minimum_size().y,
		"Long objective has sufficient height")
	map.status_label.text = original_status
	await frames(3)
	check(panel.size.y <= 90, "Panel shrinks again after long objective is replaced")
	check(not zombie._can_yield_to(Vector2(330, 245)), "Reject yield inside house")
	check(not zombie._can_yield_to(Vector2(-100, -100)), "Reject yield outside navigation")
	zombie.position = Vector2(330, 165)
	await frames(3)
	zombie._receive_crowd_push(Vector2.RIGHT, Vector2(290, 165), units[1])
	check(zombie.crowd_is_displaced and zombie._can_yield_to(zombie.navigation_agent.target_position), "Yield chooses a reachable free side beside wall")
	await frames(300)
	check(not zombie.crowd_is_displaced, "Yield completes and restores idle position")
	zombie.position = Vector2(150, 130)
	await frames(3)
	zombie.issue_player_move_order(Vector2(-100, 200))
	await frames(600)
	check(not zombie.has_player_order and not zombie.last_move_reached, "Unreachable destination reports failure")
	zombie.issue_player_move_order(Vector2(240, 350))
	await frames(600)
	check(not zombie.has_player_order and zombie.last_move_reached, "Reachable destination reports success")
	zombie.move_speed = 0.0
	zombie.issue_player_move_order(Vector2(400, 100))
	await frames(240)
	check(not zombie.has_player_order and not zombie.last_move_reached, "Stalled movement terminates without false success")
	zombie.move_speed = 100.0
	for unit in units:
		unit.set_selected(true)
	map._issue_point_move_order(Vector2(430, 360))
	var destinations: Array[Vector2] = []
	for unit in units:
		check(not destinations.has(unit.target_position), "Group receives distinct destinations")
		destinations.append(unit.target_position)
	await frames(900)
	for unit in units:
		check(not unit.has_player_order and unit.last_move_reached, "Group member arrives")
	# Deferred selection must use the release-time transform, even if camera moves.
	var transform := Transform2D(0.0, Vector2(100, 50))
	var screen_position: Vector2 = zombie.global_position - transform.origin
	root.canvas_transform = Transform2D(0.0, Vector2(-500, -200))
	map._select_unit_at_screen_position(screen_position, transform)
	check(zombie.is_selected, "Click uses captured camera transform")
	map._select_units_in_marquee(screen_position - Vector2(20, 30), screen_position + Vector2(20, 30), transform)
	check(zombie.is_selected, "Marquee uses captured camera transform")
	root.canvas_transform = Transform2D.IDENTITY
	var resident = map.villagers[0]
	zombie.position = resident.position + Vector2(-24, 0)
	await frames(3)
	zombie.aggro_target = resident
	resident.begin_encounter(Color.GREEN, zombie)
	zombie.infection_chance = 0.0
	zombie._start_encounter_attack_timer()
	var original_health: float = zombie.current_health
	await frames(70)
	check(resident.current_health < resident.max_health and zombie.current_health < original_health, "Attack timers deal mutual damage")
	resident.receive_zombie_attack(20.0, 1.0, zombie)
	zombie.issue_player_move_order(Vector2(300, 300))
	resident.take_damage(1000.0)
	await frames(180)
	check(map.infected_residents == 1 and map.killed_residents == 0, "Transformation survives lethal damage and cancelled encounter")
	var converted = get_nodes_in_group("player_units")[-1]
	check(converted.get_node("CollisionShape2D").shape.size.is_equal_approx(Vector2(13, 20.8))
		and is_equal_approx(converted.get_node("NavigationAgent2D").radius, 12.35),
		"Converted zombie uses reduced body and avoidance radius")
	var other = map.villagers[1]
	other.take_damage(1000.0)
	other.take_damage(1000.0)
	check(map.killed_residents == 1, "Death counted once")
	map.queue_free()
	await frames(2)
	for direction in [Vector2.LEFT, Vector2.UP, Vector2(-1, -1).normalized()]:
		await check_melee_approach(direction)
	print("Regression failures: ", failures)
	quit(1 if failures else 0)


func check_melee_approach(direction: Vector2) -> void:
	map = load("res://scenes/test_map.tscn").instantiate()
	root.add_child(map)
	for unit in get_nodes_in_group("player_units"):
		unit.queue_free()
	for resident in map.villagers:
		resident.queue_free()
	await frames(2)
	var resident = load("res://scenes/villager.tscn").instantiate()
	resident.position = Vector2(800, 390)
	map.add_child(resident)
	var zombie = load("res://scenes/zombie.tscn").instantiate()
	zombie.position = resident.position + direction * 30.0
	map.add_child(zombie)
	await frames(3)
	check(not resident.is_in_collision(), "No melee from old interaction distance: %s" % direction)
	await frames(45)
	check(resident.is_encounter_owner(zombie), "Pursuit reaches melee range: %s" % direction)
	var offset: Vector2 = zombie.position - resident.position
	check(offset.length() <= 20.8, "Melee starts inside reduced range: %s" % direction)
	var half_extents: Vector2 = (zombie.get_node("CollisionShape2D").shape.size
		+ resident.get_node("CollisionShape2D").shape.size) * 0.5
	check(absf(offset.x) > half_extents.x + 0.5 or absf(offset.y) > half_extents.y + 0.5,
		"Melee preserves a visible gap between bodies: %s" % direction)
	map.queue_free()
	await frames(2)
