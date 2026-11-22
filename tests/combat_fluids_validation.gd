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
	var escort: Node2D = _role(mission, "priest_guard")
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

	_check(FLUIDS.HIT_CHANCE == 0.25 and FLUIDS.DEATH_HIT_CHANCE == 0.20
		and FLUIDS.TRACE_CHANCE == 0.10 and FLUIDS.SPLASH_TIME == 0.35,
		"Hit, lethal-hit and conditional trace chances and clip length are unchanged")
	fluids._random.seed = _hit_roll_seed(0.25, 1.0)
	peasant.take_damage(1.0, ordinary)
	_check(fluids._splashes.is_empty() and exterior.get_child_count() == 0,
		"A failed roll on actual damage creates neither splash nor trace")
	fluids._random.seed = _splash_seed(FLUIDS.HIT_CHANCE, 0, true)
	peasant.take_damage(1.0, ordinary)
	_check(fluids._splashes.size() == 1 and exterior.get_child_count() == 1,
		"Nonlethal damage can create one blood splash with a rare ground trace")
	var sprite: Sprite2D = fluids._splashes[0].sprite
	var trace: Sprite2D = exterior.get_child(0)
	_check(sprite.z_index > peasant.z_index and sprite.hframes == 24 and sprite.vframes == 2
		and sprite.frame_coords == Vector2i(0, 0) and sprite.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.BLOOD][0],
		"Blood uses the first 24-frame clip above the target")
	_check(trace.texture == sprite.texture and trace.frame_coords == Vector2i(0, 1)
		and not _frame_has_ink(trace), "A reserved ground trace begins transparent")
	fluids._process(0.16)
	_check(sprite.frame_coords.x == 10 and trace.frame_coords.x == 10 and not _frame_has_ink(trace),
		"Both rows advance together and the first blood variant is still airborne at frame 10")
	fluids._process(0.02)
	_check(_frame_has_ink(trace) and sprite.global_transform.is_equal_approx(trace.global_transform),
		"Drop contact reveals the trace with the same transform as the falling splash")
	fluids._process(0.20)
	_check(fluids._splashes.is_empty() and trace.frame_coords == Vector2i(23, 1)
		and _frame_has_ink(trace), "A skipped last tick still leaves the final ground frame")
	fluids._random.seed = _splash_seed(FLUIDS.HIT_CHANCE, 0, true)
	hound.take_damage(1.0, Vector2.DOWN)
	_check(fluids._splashes.size() == 1
		and fluids._splashes[0].sprite.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.SLIME][0]
		and is_equal_approx(fluids._splashes[0].sprite.rotation, PI * 0.5),
		"Runner damage selects the first slime clip and follows the hit direction")
	fluids._process(0.36)
	var slime_trace: Sprite2D = exterior.get_child(1)
	_check(slime_trace.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.SLIME][0]
		and slime_trace.frame_coords == Vector2i(23, 1) and _frame_has_ink(slime_trace),
		"The matching slime trace settles on the exterior ground")

	var footprint_count := exterior.get_child_count()
	var no_trace_seed := _splash_seed(FLUIDS.HIT_CHANCE, 1, false)
	for actor in [artisan, priest, guard, escort, archer]:
		fluids._random.seed = no_trace_seed
		actor.take_damage(1.0, ordinary)
		_check(fluids._splashes.size() == 1 and fluids._splashes[0].trace == null
			and fluids._splashes[0].sprite.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.BLOOD][1],
			"%s can play the second blood variant without creating a trace" % actor.name)
		fluids._process(0.36)
	for actor in [ordinary, brute, carrier]:
		fluids._random.seed = no_trace_seed
		actor.take_damage(1.0, Vector2.LEFT)
		_check(fluids._splashes.size() == 1 and fluids._splashes[0].trace == null
			and fluids._splashes[0].sprite.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.SLIME][1],
			"%s can play the second slime variant without creating a trace" % actor.name)
		fluids._process(0.36)
	_check(exterior.get_child_count() == footprint_count,
		"Successful splashes that fail the conditional trace roll leave the ground unchanged")

	fluids._random.seed = _splash_seed(FLUIDS.HIT_CHANCE, 1, true)
	priest.take_damage(1.0, ordinary)
	var floor := interior.layout.combat_fluid_layer()
	var floor_trace: Sprite2D = fluids._splashes[0].trace
	_check(is_instance_valid(floor_trace) and floor_trace.get_parent() == floor,
		"Interior hit traces use the floor-clipped layer")
	fluids._process(0.36)
	_check(_frame_has_ink(floor_trace), "The interior trace reaches its final frame")

	_check(infected.apply_player_infection(10.0), "Peasant accepts Infection before lethal damage")
	infected.take_damage(1000.0, ordinary)
	_check(infected.is_converted() and exterior.get_child_count() == footprint_count
		and fluids._splashes.is_empty(), "Instant conversion leaves no death pool or splash")
	fluids._random.seed = _splash_seed(FLUIDS.DEATH_HIT_CHANCE, 1, true)
	guard.take_damage(1000.0, ordinary)
	_check(fluids._splashes.size() == 1 and fluids._splashes[0].trace == null
		and fluids._splashes[0].sprite.texture == FLUIDS.SPLASHES[FLUIDS.Fluid.BLOOD][1]
		and exterior.get_child_count() == footprint_count,
		"Lethal damage can play a new splash without a trace or early pool")
	fluids._process(0.36)
	fluids._random.seed = _hit_roll_seed(0.20, 0.25)
	brute.take_damage(1000.0, Vector2.RIGHT)
	_check(fluids._splashes.is_empty(), "A roll between 20% and 25% fails on a lethal hit")
	for actor in [peasant, artisan, ordinary]:
		actor.take_damage(1000.0)
	_check(exterior.get_child_count() == footprint_count, "All existing fall clips delay their pools")
	archer.take_damage(1000.0)
	priest.take_damage(1000.0)
	hound.take_damage(1000.0)
	carrier.take_damage(1000.0)
	await process_frame
	_check(exterior.get_child_count() == footprint_count + 3,
		"The archer, Runner and Carrier leave pools with their static death markers")
	_check(floor.get_child_count() == 1, "The priest's fall also delays the interior pool")

	for _frame in 66:
		await physics_frame
	_check(exterior.get_child_count() == footprint_count + 8,
		"Every outdoor casualty leaves exactly one pool")
	_check(floor.get_child_count() == 2 and floor.get_child(1).material != null,
		"The priest creates a separate floor-clipped pool after the fall")

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


func _splash_seed(chance: float, variant: int, trace: bool) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(2048):
		rng.seed = candidate
		if rng.randf() >= chance:
			continue
		if rng.randi_range(0, FLUIDS.SPLASHES[FLUIDS.Fluid.BLOOD].size() - 1) != variant:
			continue
		if (rng.randf() < FLUIDS.TRACE_CHANCE) == trace:
			return candidate
	return -1


func _hit_roll_seed(low: float, high: float) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(2048):
		rng.seed = candidate
		var roll := rng.randf()
		if roll >= low and roll < high:
			return candidate
	return -1


func _frame_has_ink(sprite: Sprite2D) -> bool:
	var image := sprite.texture.get_image()
	var size := image.get_size() / Vector2i(sprite.hframes, sprite.vframes)
	return image.get_region(Rect2i(sprite.frame_coords * size, size)).get_used_rect().has_area()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
