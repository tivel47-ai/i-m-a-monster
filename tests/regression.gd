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
		resident.position = Vector2(1100, 600)
	var units = get_nodes_in_group("player_units")
	for i in range(units.size()):
		units[i].position = Vector2(150 + i * 60, 200)
	await frames(5)
	var zombie = units[0]
	check(not zombie._can_yield_to(Vector2(840, 360)), "Reject yield inside obstacle")
	check(not zombie._can_yield_to(Vector2(-100, -100)), "Reject yield outside navigation")
	zombie.position = Vector2(840, 210)
	await frames(3)
	zombie._receive_crowd_push(Vector2.RIGHT, Vector2(800, 210), units[1])
	check(zombie.crowd_is_displaced and zombie._can_yield_to(zombie.navigation_agent.target_position), "Yield chooses a reachable free side beside wall")
	await frames(300)
	check(not zombie.crowd_is_displaced, "Yield completes and restores idle position")
	zombie.position = Vector2(150, 200)
	await frames(3)
	zombie.issue_player_move_order(Vector2(-100, 200))
	await frames(600)
	check(not zombie.has_player_order and not zombie.last_move_reached, "Unreachable destination reports failure")
	zombie.issue_player_move_order(Vector2(200, 100))
	await frames(600)
	check(not zombie.has_player_order and zombie.last_move_reached, "Reachable destination reports success")
	zombie.move_speed = 0.0
	zombie.issue_player_move_order(Vector2(400, 100))
	await frames(240)
	check(not zombie.has_player_order and not zombie.last_move_reached, "Stalled movement terminates without false success")
	zombie.move_speed = 100.0
	for unit in units:
		unit.set_selected(true)
	map._issue_point_move_order(Vector2(400, 300))
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
	var other = map.villagers[1]
	other.take_damage(1000.0)
	other.take_damage(1000.0)
	check(map.killed_residents == 1, "Death counted once")
	map.queue_free()
	await frames(2)
	print("Regression failures: ", failures)
	quit(1 if failures else 0)
