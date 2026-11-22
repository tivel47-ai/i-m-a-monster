extends SceneTree

const MISSION := preload("res://scenes/village_simulation_map.tscn")
const ZOMBIE := preload("res://scenes/zombie.tscn")
const BUILD := preload("res://scripts/zombie_mission_build.gd")
const PROGRESSION := preload("res://scripts/zombie_progression.gd")
const FLUIDS := preload("res://scripts/combat_fluids.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mission := MISSION.instantiate()
	root.add_child(mission)
	var fluids := mission.get_node("CombatFluids") as FLUIDS
	var exterior := mission.get_node("Ground/CombatFluidDecals")
	var peasant: Node2D = _role(mission, "peasant")
	var artisan: Node2D = _role(mission, "artisan")
	var priest: Node2D = _role(mission, "priest")
	var guard: Node2D = _role(mission, "guard")
	var infected: Node2D = _role(mission, "peasant", peasant)
	var roles: Array[StringName] = [&"archer"]
	var archer: Node2D = mission.spawn_reinforcement_wave(
		roles, PackedVector2Array([Vector2(340, 1000)]), null)[0]
	var ordinary := _monster(mission, "", Vector2(440, 1000))
	var brute := _monster(mission, PROGRESSION.BRUTE, Vector2(480, 1000))
	var hound := _monster(mission, PROGRESSION.HOUND, Vector2(520, 1000))
	var carrier := _monster(mission, PROGRESSION.CARRIER, Vector2(560, 1000))
	var interior: InteractiveBuilding = mission.buildings[0]
	priest.interior_building = interior
	priest.global_position = interior.layout.interior()

	fluids._random.seed = _splash_seed(FLUIDS.HIT_CHANCE)
	peasant.take_damage(1.0, ordinary)
	_check(fluids._splashes.size() == 1 and exterior.get_child_count() == 1,
		"Nonlethal damage can create one blood splash and one rare ground trace")
	var sprite: Sprite2D = fluids._splashes[0].sprite
	_check(sprite.z_index > peasant.z_index and sprite.hframes == 21 and sprite.frame_coords.y < 3,
		"Blood splash uses the correct 21-frame clip above the target")
	fluids._process(0.16)
	_check(sprite.frame_coords.x in range(8, 12), "Splash advances through intermediate frames")
	fluids._process(0.20)
	_check(fluids._splashes.is_empty(), "Airborne splash ends after the short clip")
	fluids._random.seed = _splash_seed(FLUIDS.HIT_CHANCE)
	hound.take_damage(1.0, Vector2.DOWN)
	_check(fluids._splashes.size() == 1 and fluids._splashes[0].sprite.frame_coords.y >= 3
		and is_equal_approx(fluids._splashes[0].sprite.rotation, PI * 0.5),
		"Monster damage selects a slime clip and follows the hit direction")
	fluids._process(0.36)

	var footprint_count := exterior.get_child_count()
	_check(infected.apply_player_infection(10.0), "Peasant accepts Infection before lethal damage")
	infected.take_damage(1000.0, ordinary)
	_check(infected.is_converted() and exterior.get_child_count() == footprint_count
		and fluids._splashes.is_empty(), "Instant conversion leaves no death pool or splash")
	fluids._random.seed = _splash_seed(FLUIDS.DEATH_HIT_CHANCE)
	guard.take_damage(1000.0, ordinary)
	_check(fluids._splashes.size() == 1 and exterior.get_child_count() == footprint_count,
		"Lethal damage rolls one splash and leaves no trace or early pool")
	for actor in [peasant, artisan, ordinary, brute]:
		actor.take_damage(1000.0)
	_check(exterior.get_child_count() == footprint_count, "All existing fall clips delay their pools")
	archer.take_damage(1000.0)
	priest.take_damage(1000.0)
	hound.take_damage(1000.0)
	carrier.take_damage(1000.0)
	await process_frame
	_check(exterior.get_child_count() == footprint_count + 3,
		"The archer, Runner and Carrier leave pools with their static death markers")
	_check(interior.layout.combat_fluid_layer().get_child_count() == 1,
		"The priest creates a floor-clipped pool in the correct interior")

	for _frame in 66:
		await physics_frame
	_check(exterior.get_child_count() == footprint_count + 8,
		"Every outdoor casualty leaves exactly one pool")

	var blood := 0
	var slime := 0
	for child in exterior.get_children():
		if child.material == null:
			continue
		if child.frame_coords.y == FLUIDS.Fluid.BLOOD:
			blood += 1
		else:
			slime += 1
	_check(blood == 4 and slime == 4, "Both factions use the intended texture rows")
	for pool in fluids._pools:
		var expected := Vector2(2.0, 4.0) if pool.sprite.frame_coords.y == FLUIDS.Fluid.BLOOD else Vector2(4.0, 6.0)
		_check(pool.spread_time >= expected.x and pool.spread_time <= expected.y,
			"Material has its approved spreading duration")
	fluids._process(200.0)
	_check(fluids._pools.is_empty() and exterior.get_child_count() == footprint_count + 8,
		"Mature deposits stop updating and stay on the ground")

	print("Combat fluids: %d/%d checks passed." % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _role(mission: Node, role: String, except: Node = null) -> Node2D:
	for actor in mission.villagers:
		if actor != except and actor.get_meta("village_role", "") == role:
			return actor
	return null


func _monster(mission: Node, form: String, location: Vector2) -> Node2D:
	var actor := ZOMBIE.instantiate()
	actor.position = location
	BUILD.apply_form(actor, form)
	mission.add_child(actor)
	return actor


func _splash_seed(chance: float) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(2048):
		rng.seed = candidate
		if rng.randf() >= chance:
			continue
		rng.randi_range(0, FLUIDS.SPLASH_VARIANTS - 1)
		if rng.randf() < FLUIDS.TRACE_CHANCE:
			return candidate
	return -1


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
