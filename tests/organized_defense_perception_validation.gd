extends "res://tests/organized_defense_smoke.gd"

func run() -> void:
	await fixture()
	activate()
	await frames(2)
	for resident in map.villagers: resident.global_position = Vector2(900, 900)
	var resident = civilians[0]
	var ally = civilians[1]
	var enemy = units[0]
	resident.global_position = Vector2(1360, 620)
	ally.global_position = Vector2(1360, 650)
	enemy.global_position = Vector2(1450, 620)
	var wall = StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(1400, 620)
	var collision = CollisionShape2D.new()
	var rectangle = RectangleShape2D.new()
	rectangle.size = Vector2(8, 50)
	collision.shape = rectangle
	wall.add_child(collision)
	map.add_child(wall)
	await frames(2)
	check(service.nearby(resident, 150, 2 | 8).has(enemy), "Blocked zombie is present in mixed physical query")
	check(not resident.threat_detection._is_visible_target(enemy), "Wall blocks zombie recognition")
	check(not formation.eligible(enemy), "Zombie cannot satisfy resident eligibility")
	check(not formation.eligible(wall) and not formation.eligible(null), "Other bodies and null are rejected safely")
	check(formation.eligible(resident), "Registered living resident remains eligible")
	var behavior = formation.controller(resident)
	behavior.sense()
	check(not behavior.allies.has(enemy) and not behavior.enemies.has(enemy), "Occluded zombie is neither ally nor visible enemy")
	check(behavior.allies.has(ally), "Visible resident still becomes a local ally")
	behavior.update(0.016)
	var guard = guards[0]
	guard.global_position = resident.global_position
	await frames(2)
	guard.guard_ai.sense()
	check(not guard.guard_ai.local_allies.has(enemy), "Guard sensing also excludes zombies from allies")
	wall.queue_free()
	await frames(2)
	behavior.seen_since[enemy.get_instance_id()] = service.elapsed - 1.0
	behavior.sense()
	check(behavior.enemies.has(enemy) and not behavior.allies.has(enemy), "Visible recognized zombie returns only as an enemy")
	resident.infection_state = resident.InfectionState.TRANSFORMING
	check(not formation.eligible(resident), "Transforming resident remains excluded")
	var freed: Variant = Node2D.new()
	freed.free()
	check(not formation.eligible(freed), "Freed reference is rejected before property access")
	map.queue_free()
	await frames(2)
	print("ORGANIZED_DEFENSE perception checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
