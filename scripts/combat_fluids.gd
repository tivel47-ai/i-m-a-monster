extends Node

enum Fluid { BLOOD, SLIME }

const FRESH := preload("res://assets/sprites/effects/combat_pools_fresh.png")
const OLD := preload("res://assets/sprites/effects/combat_pools_old.png")
const SPREAD := preload("res://assets/sprites/effects/combat_pools_spread.png")
const SPLASHES := [
	[
		preload("res://assets/sprites/effects/combat_hit_blood.png"),
		preload("res://assets/sprites/effects/combat_hit_blood_fan.png"),
	],
	[
		preload("res://assets/sprites/effects/combat_hit_slime.png"),
		preload("res://assets/sprites/effects/combat_hit_slime_glob.png"),
	],
]
const POOL_SHADER := preload("res://scripts/combat_pool.gdshader")
const MEADOW := preload("res://assets/maps/mission_01/meadow.png")
const POOL_VARIANTS := 5
const SPLASH_FRAMES := 24
const SPLASH_TIME := 0.35
const SPLASH_ORIGIN := Vector2(49.0, 39.0)
const SPLASH_FEET := Vector2(42.0, 79.0)
const FIRST_LANDING_TIME := SPLASH_TIME * 9.0 / SPLASH_FRAMES
const HIT_CHANCE := 0.25
const DEATH_HIT_CHANCE := 0.20
const TRACE_CHANCE := 0.10
const MAX_TRACES := 96
const TEXEL_SCALE := 0.252
const AGING_STEP := 0.08

var _random := RandomNumberGenerator.new()
var _pools: Array[Pool] = []
var _splashes: Array[Flight] = []
var _traces: Array[Sprite2D] = []
var _corpse_bounds: Dictionary = {}
var _pool_material := ShaderMaterial.new()
var _ground: Polygon2D


class Pool:
	var sprite: Sprite2D
	var material: ShaderMaterial
	var elapsed := 0.0
	var spread_time: float
	var old_time: float
	var last_aging_update := 0.0


class Flight:
	var sprite: Sprite2D
	var trace: Sprite2D
	var feet: Vector2
	var launch_offset: Vector2
	var elapsed := 0.0


static func for_actor(actor: Node) -> Node:
	var ancestor := actor.get_parent()
	while ancestor != null:
		if ancestor.has_node("CombatFluids"):
			return ancestor.get_node("CombatFluids")
		ancestor = ancestor.get_parent()
	return null


func _ready() -> void:
	_ground = get_parent().get_node("Ground")
	_pool_material.shader = POOL_SHADER
	_pool_material.set_shader_parameter("old_atlas", OLD)
	_pool_material.set_shader_parameter("spread_atlas", SPREAD)
	_pool_material.set_shader_parameter("meadow", MEADOW)
	set_process(false)


func hit(actor: Node2D, fluid: Fluid, direction: Vector2, lethal: bool, height: float) -> void:
	var chance := DEATH_HIT_CHANCE if lethal else HIT_CHANCE
	if _random.randf() >= chance:
		return
	if direction.is_zero_approx():
		direction = Vector2.from_angle(_random.randf_range(-PI, PI))
	var variants: Array = SPLASHES[fluid]
	var texture: Texture2D = variants[_random.randi_range(0, variants.size() - 1)]
	var sprite := _splash_sprite(texture, 0)
	sprite.z_index = 3
	var building := actor.get("interior_building") as InteractiveBuilding
	if is_instance_valid(building):
		building.layout.airborne_effect_layer().add_child(sprite)
	else:
		add_child(sprite)
	var flight := Flight.new()
	flight.sprite = sprite
	flight.feet = actor.global_position + Vector2(0.0, 5.5)
	var scale_factor := TEXEL_SCALE * clampf(height / 28.0, 0.64, 1.2)
	var mirror := -1.0 if direction.x < 0.0 else 1.0
	sprite.global_transform = Transform2D(
		direction.angle(), Vector2(scale_factor, scale_factor * mirror), 0.0, flight.feet)
	if not lethal and _random.randf() < TRACE_CHANCE:
		flight.trace = _add_trace(actor, sprite)
	# Match the target's hit point at launch, then align both rows before any drop lands.
	flight.launch_offset = (
		Vector2(0.0, -height * 0.57)
		- sprite.global_transform.basis_xform(SPLASH_ORIGIN - SPLASH_FEET))
	sprite.global_position += flight.launch_offset
	_splashes.append(flight)
	set_process(true)


func _splash_sprite(texture: Texture2D, row: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.hframes = SPLASH_FRAMES
	sprite.vframes = 2
	sprite.frame_coords = Vector2i(0, row)
	sprite.centered = false
	sprite.offset = -SPLASH_FEET
	return sprite


func settled(actor: Node2D, fluid: Fluid, pose: Sprite2D = null) -> void:
	var location := actor.global_position + Vector2(0.0, 4.0)
	var size_factor := 1.0
	if is_instance_valid(pose):
		var bounds := _pose_bounds(pose)
		if bounds.has_area():
			location = bounds.get_center()
			size_factor = clampf(maxf(bounds.size.x, bounds.size.y * 1.5) / 25.0, 0.88, 1.34)
	var layer := _ground_layer(actor)
	if layer == null:
		return
	var sprite := _pool_sprite(fluid)
	sprite.scale = Vector2.ONE * (TEXEL_SCALE * size_factor * _random.randf_range(0.91, 1.09))
	sprite.flip_h = _random.randf() < 0.5
	var material := _pool_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("progress", 0.0)
	material.set_shader_parameter("aging", 0.0)
	if not is_instance_valid(actor.get("interior_building")) and _ground.is_combat_fluid_meadow(location):
		material.set_shader_parameter("grass", 1.0)
	sprite.material = material
	layer.add_child(sprite)
	sprite.global_position = location.snapped(Vector2.ONE * TEXEL_SCALE)
	var pool := Pool.new()
	pool.sprite = sprite
	pool.material = material
	pool.spread_time = _random.randf_range(2.0, 4.0) if fluid == Fluid.BLOOD else _random.randf_range(4.0, 6.0)
	pool.old_time = _random.randf_range(60.0, 120.0) if fluid == Fluid.BLOOD else _random.randf_range(90.0, 180.0)
	_pools.append(pool)
	set_process(true)


func _pool_sprite(fluid: Fluid) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = FRESH
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.hframes = POOL_VARIANTS
	sprite.vframes = 2
	sprite.frame_coords = Vector2i(_random.randi_range(0, POOL_VARIANTS - 1), fluid)
	return sprite


func _ground_layer(actor: Node2D) -> Node2D:
	var building := actor.get("interior_building") as InteractiveBuilding
	if is_instance_valid(building):
		return building.layout.combat_fluid_layer()
	return _ground.get_node_or_null("CombatFluidDecals")


func _add_trace(actor: Node2D, splash: Sprite2D) -> Sprite2D:
	var layer := _ground_layer(actor)
	if layer == null:
		return null
	var trace := _splash_sprite(splash.texture, 1)
	trace.modulate.a = 0.84
	layer.add_child(trace)
	trace.global_transform = splash.global_transform
	_traces.append(trace)
	if _traces.size() > MAX_TRACES:
		var oldest: Sprite2D = _traces.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	return trace


func _pose_bounds(pose: Sprite2D) -> Rect2:
	var key := [pose.texture.get_instance_id(), pose.region_rect]
	if not _corpse_bounds.has(key):
		var image := pose.texture.get_image()
		var bounds := Rect2i()
		if image != null and not image.is_empty():
			bounds = image.get_region(Rect2i(pose.region_rect)).get_used_rect()
		_corpse_bounds[key] = bounds
	var opaque: Rect2i = _corpse_bounds[key]
	if not opaque.has_area():
		return Rect2()
	var local := pose.get_rect()
	var start := Vector2(opaque.position)
	if pose.flip_h:
		start.x = local.size.x - opaque.end.x
	if pose.flip_v:
		start.y = local.size.y - opaque.end.y
	return pose.global_transform * Rect2(local.position + start, Vector2(opaque.size))


func _process(delta: float) -> void:
	for i in range(_pools.size() - 1, -1, -1):
		var pool := _pools[i]
		if not is_instance_valid(pool.sprite):
			_pools.remove_at(i)
			continue
		var was_spreading := pool.elapsed < pool.spread_time
		pool.elapsed += delta
		if was_spreading:
			pool.material.set_shader_parameter("progress", minf(pool.elapsed / pool.spread_time, 1.0))
		if pool.elapsed < pool.spread_time:
			continue
		if pool.elapsed < pool.old_time and pool.elapsed - pool.last_aging_update < AGING_STEP:
			continue
		pool.last_aging_update = pool.elapsed
		var age := clampf((pool.elapsed - pool.spread_time) / (pool.old_time - pool.spread_time), 0.0, 1.0)
		pool.material.set_shader_parameter("aging", age)
		if age == 1.0:
			_pools.remove_at(i)
	for i in range(_splashes.size() - 1, -1, -1):
		var flight := _splashes[i]
		flight.elapsed += delta
		var frame := mini(int(flight.elapsed / SPLASH_TIME * SPLASH_FRAMES), SPLASH_FRAMES - 1)
		if is_instance_valid(flight.trace):
			flight.trace.frame_coords.x = frame
		if flight.elapsed >= SPLASH_TIME:
			flight.sprite.queue_free()
			_splashes.remove_at(i)
		else:
			flight.sprite.frame_coords.x = frame
			var launch_weight := 1.0 - minf(flight.elapsed / FIRST_LANDING_TIME, 1.0)
			flight.sprite.global_position = flight.feet + flight.launch_offset * launch_weight
	if _pools.is_empty() and _splashes.is_empty():
		set_process(false)
