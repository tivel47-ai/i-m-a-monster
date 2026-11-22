# Godot --headless --path . --script tests/guard_pursuit_validation.gd --fixed-fps 60
extends "res://tests/guard_ai_validation.gd"

const ZOMBIE_SCENE = preload("res://scenes/zombie.tscn")
const ZOMBIE_BUILD = preload("res://scripts/zombie_mission_build.gd")
const SMITHY_ROAD := Vector2(2365, 600)


func run() -> void:
	await follows_after_melee()
	await stops_after_pursuit_limit()
	map.queue_free()
	await frames(3)
	print("Guard pursuit validation failures: ", failures)
	quit(1 if failures else 0)


func follows_after_melee() -> void:
	await fixture()
	var guard = map.get_node("Villagers/Guard27").guard_ai
	var actor: Node2D = guard.actor
	actor.position = SMITHY_ROAD
	var brute = ZOMBIE_SCENE.instantiate()
	ZOMBIE_BUILD.apply_form(brute, "brute")
	# Keep both fighters alive long enough to exceed the pursuit limit.
	brute.attack_damage = 1.0
	brute.infection_chance = 0.0
	brute.position = SMITHY_ROAD + Vector2(45.0, 0.0)
	map.add_child(brute)
	brute.current_health = 1000.0
	brute.set_physics_process(false)
	enable(guard)
	await frames(120)
	check(actor.is_encounter_owner(brute) and guard.pursuit_target == brute.get_instance_id(),
		"Guard approaches the Brute and enters melee on the road by the smithy")
	await frames(ceili(guard.pursuit_seconds * 60.0))
	check(actor.is_encounter_owner(brute) and brute.current_health < 1000.0,
		"Guard lands hits and remains in combat past the pursuit time limit")
	var before: Vector2 = actor.position
	var destination := Vector2(2460, 550)
	brute.issue_player_move_order(destination)
	brute.set_physics_process(true)
	await frames(120)
	check(brute.position.distance_to(destination) < 8.0, "Brute carries out the player's move order")
	check(actor.position.distance_to(before) > 30.0, "Guard follows the personally visible Brute after melee")
	var health: float = brute.current_health
	await frames(100)
	check(brute.current_health < health, "Guard closes the gap and hits the Brute again")


func stops_after_pursuit_limit() -> void:
	await fixture()
	var guard = map.get_node("Villagers/Guard27").guard_ai
	guard.actor.position = SMITHY_ROAD
	guard.pursuit_seconds = 0.75
	guard.tactical_speed = 10.0
	var enemy = ZOMBIE_SCENE.instantiate()
	enemy.position = SMITHY_ROAD + Vector2(75.0, 0.0)
	map.add_child(enemy)
	enemy.set_physics_process(false)
	enable(guard)
	await frames(120)
	var stopped_at: Vector2 = guard.actor.position
	check(stopped_at.x > SMITHY_ROAD.x + 3.0, "Guard starts a chase before the time limit")
	await frames(60)
	check(guard.state == guard.State.ALERT_PATROL and guard.visible_enemies.has(enemy)
		and guard.actor.position.distance_to(stopped_at) < 0.1,
		"Guard stops continuous pursuit at the time limit while still seeing the target")
