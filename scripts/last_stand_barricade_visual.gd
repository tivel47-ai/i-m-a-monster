extends Node2D
## Layered wattle and fieldstone, projected from the section's ground footprint.

enum Build { EMPTY, FOOTING, FRAME, PARTIAL, COMPLETE }
enum Damage { INTACT, CHIPPED, BROKEN, FAILING, COLLAPSED }

const FRAME_RATIO := 0.4
const PARTIAL_RATIO := 0.7
const BAY_COUNT := 3
const ROD_COUNT := 5
const WOOD_OUTLINE := Color("#30251c")
const WOOD := Color("#5c4b3b")
const WOOD_GRAIN := Color("#8a735a")
const SPLINTER := Color("#a68b65")
const STONE_SHADOW := Color("#302d27")
const STONE_FACE := Color("#575248")
const STONE_TOP := Color("#777063")

var length := 80.0
var depth := 10.0
var _build := Build.EMPTY
var _damage := Damage.INTACT
var _axis := Vector2.RIGHT
var _front := Vector2.DOWN


func update_condition(built_ratio: float, integrity: float) -> void:
	var build := Build.FOOTING
	if built_ratio >= 1.0:
		build = Build.COMPLETE
	elif built_ratio >= PARTIAL_RATIO:
		build = Build.PARTIAL
	elif built_ratio >= FRAME_RATIO:
		build = Build.FRAME

	var damage := Damage.INTACT
	if integrity <= 0.0:
		damage = Damage.COLLAPSED
	elif integrity <= FRAME_RATIO:
		damage = Damage.FAILING
	elif integrity <= PARTIAL_RATIO:
		damage = Damage.BROKEN
	elif integrity < 1.0:
		damage = Damage.CHIPPED

	if _build == build and _damage == damage:
		return
	_build = build
	_damage = damage
	queue_redraw()


func _draw() -> void:
	if _build == Build.EMPTY or length <= 0.0:
		return
	# The section rotates on the ground. Height stays vertical on screen,
	# including the two sections that run directly away from the camera.
	draw_set_transform(Vector2.ZERO, -global_rotation)
	_axis = Vector2.from_angle(global_rotation)
	if _axis.x < -0.001 or (absf(_axis.x) <= 0.001 and _axis.y < 0.0):
		_axis = -_axis
	_front = _axis.orthogonal()
	if _front.y < -0.001:
		_front = -_front

	var end := maxf(0.0, length * 0.5 - 3.1)
	var bay_width := 2.0 * end / BAY_COUNT
	if _damage == Damage.COLLAPSED:
		_draw_stones(end, true)
		_draw_debris(end, bay_width)
		return

	_draw_contact_shadow(end)
	var bay_order := range(BAY_COUNT) if _axis.y >= 0.0 else range(BAY_COUNT - 1, -1, -1)
	for bay: int in bay_order:
		_draw_weave(bay, -end + bay * bay_width, bay_width)

	for edge in [0, BAY_COUNT]:
		var x := -end + float(edge) * bay_width
		var outer := -1.0 if edge == 0 else 1.0
		_draw_wood(PackedVector2Array([
			_project(x + outer * 1.6, depth * 0.37, 0.0),
			_project(x - outer * 5.2, 0.35, 10.7),
		]), 2.5, 0.83, false)

	for post in BAY_COUNT + 1:
		if _build == Build.FOOTING and post in [1, 2]:
			continue
		var x := -end + post * bay_width
		var height := 14.3 + sin(float(post) * 3.7) * 1.05
		var lean := sin(float(post) * 1.8) * 1.1
		var split := _damage >= Damage.BROKEN and post == 2
		if split:
			height *= 0.70 if _damage == Damage.BROKEN else 0.40
			lean += 2.3
		var nicked := _damage == Damage.CHIPPED and _build < Build.PARTIAL and post == BAY_COUNT
		_draw_wood(PackedVector2Array([
			_project(x, 0.8, 0.0),
			_project(x + lean * 0.35, 0.8, height * 0.50),
			_project(x + lean, 0.6, height),
		]), 2.8 if post in [0, BAY_COUNT] else 2.2, 1.0, split or nicked)
	_draw_stones(end, false)
	if _damage >= Damage.BROKEN:
		_draw_debris(end, bay_width)


func _project(x: float, across: float, height: float) -> Vector2:
	return _axis * x + _front * across + Vector2.UP * height


func _draw_contact_shadow(end: float) -> void:
	var width := depth * 0.39
	var near := _front * 0.8
	draw_colored_polygon(PackedVector2Array([
		_project(-end - 1.8, -width * 0.44, 0.0), _project(-end * 0.70, -width, 0.0),
		_project(end * 0.74, -width * 0.90, 0.0), _project(end + 1.8, -width * 0.46, 0.0),
		_project(end + 0.9, width * 0.75, 0.0), _project(end * 0.68, width, 0.0),
		_project(-end * 0.77, width * 0.94, 0.0), _project(-end - 1.5, width * 0.68, 0.0),
	]), Color(0.055, 0.045, 0.033, 0.30))
	draw_line(-_axis * end + near, _axis * end + near, Color(0.06, 0.048, 0.036, 0.24), width * 0.84)


func _draw_weave(bay: int, start: float, width: float) -> void:
	if _build < Build.PARTIAL or (_build == Build.PARTIAL and bay == 1):
		return
	# Stable bends and bark tones keep existing rods in place when a bay is filled.
	var rng := RandomNumberGenerator.new()
	rng.seed = 35743 + bay * 259
	var affected_bay := 1 if _build == Build.COMPLETE else 2
	for rod in ROD_COUNT:
		var points := PackedVector2Array()
		var base_height := 3.6 + 2.02 * rod + rng.randf_range(-0.32, 0.32)
		var diameter := rng.randf_range(2.28, 3.04)
		var tone := rng.randf_range(0.80, 1.12)
		for segment in 7:
			var fraction := segment / 6.0
			var bend := rng.randf_range(-0.62, 0.62) + sin(segment * 1.36 + rod * 1.71) * 0.72
			var across := cos(segment * 1.42 + rod * 2.28) * 1.4 + 0.2
			points.append(_project(start + 0.5 + fraction * (width - 1.0), across, base_height + bend))

		if _damage == Damage.FAILING and bay == affected_bay and rod >= 2:
			continue
		var broken := _damage >= Damage.BROKEN and bay == affected_bay
		if broken and (rod >= 2 or _damage == Damage.FAILING):
			var stub := points.slice(0, 3)
			stub[2] += Vector2.DOWN * (1.1 + float(rod) * 0.25)
			_draw_wood(stub, diameter, tone, true)
			if _damage == Damage.BROKEN:
				stub = points.slice(4, 7)
				stub.reverse()
				stub[2] += Vector2.DOWN * 1.4
				_draw_wood(stub, diameter, tone * 0.94, true)
		else:
			_draw_wood(points, diameter, tone, false)
			if _damage == Damage.CHIPPED and bay == affected_bay and rod == ROD_COUNT - 1:
				var chip := points[3]
				draw_line(chip + Vector2(-0.8, 0.9), chip + Vector2(1.1, -1.1), SPLINTER, 1.0)


func _draw_wood(points: PackedVector2Array, diameter: float, tone: float, broken_tip: bool) -> void:
	draw_polyline(points, WOOD_OUTLINE, diameter + 0.65, true)
	draw_polyline(points, WOOD.darkened(1.0 - minf(tone, 1.0)), diameter - 0.15, true)
	var grain := PackedVector2Array()
	for point in points:
		grain.append(point + Vector2(-0.26, -diameter * 0.27))
	draw_polyline(grain, WOOD_GRAIN * Color(tone, tone, tone, 0.79), 0.77, true)
	for segment in points.size() - 1:
		var start := points[segment]
		var end := points[segment + 1]
		var bark := Color(0.135, 0.100, 0.071, 0.63)
		var offset := Vector2(0.3, diameter * (0.17 if segment % 2 == 0 else 0.26))
		draw_line(start.lerp(end, 0.17) + offset, start.lerp(end, 0.68) + offset, bark, 0.64, true)
	var cap := points[-1]
	if broken_tip:
		draw_colored_polygon(PackedVector2Array([
			cap + Vector2(-0.8, 1.0), cap + Vector2(-0.4, -0.75),
			cap + Vector2(0.7, -1.9), cap + Vector2(0.8, 0.7),
		]), SPLINTER)
	else:
		draw_circle(cap, diameter * 0.34, WOOD_GRAIN * Color(tone, tone, tone, 0.86), true, -1.0, true)


func _draw_stones(end: float, collapsed: bool) -> void:
	var count := maxi(3, roundi(length / 6.7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3419
	for index in count:
		var fraction := (index + 0.5) / count
		var x := lerpf(-end, end, fraction) + rng.randf_range(-0.9, 0.9)
		var across := rng.randf_range(depth * 0.13, depth * 0.36)
		var width := rng.randf_range(5.5, 8.5)
		var height := rng.randf_range(3.2, 5.8)
		var tone := rng.randf_range(0.82, 1.12)
		if _build == Build.FOOTING and index % 3 == 1:
			continue
		if collapsed:
			if fraction > 0.33 and fraction < 0.66:
				continue
			across *= 1.25
			height *= 0.64
		_draw_stone(_project(x, across, 0.0), width, height, tone)


func _draw_stone(base: Vector2, width: float, height: float, tone: float) -> void:
	var left := base + Vector2(-width * 0.51, -height * 0.27)
	var slope := base + Vector2(-width * 0.37, -height * 0.74)
	var ridge := base + Vector2(width * (tone - 1.04), -height)
	var crown := base + Vector2(width * 0.23, -height * 0.95)
	var shoulder := base + Vector2(width * 0.42, -height * 0.67)
	var right := base + Vector2(width * 0.51, -height * 0.32)
	var foot := base + Vector2(width * 0.23, 0.43)
	var heel := base + Vector2(-width * 0.28, 0.30)
	var seam := base + Vector2(-width * 0.08, -height * 0.48)
	draw_colored_polygon(PackedVector2Array([
		left, slope, ridge, crown, shoulder, right, foot, heel,
	]), STONE_SHADOW)
	var tint := Color(tone, tone, tone)
	draw_colored_polygon(PackedVector2Array([left, slope, ridge, crown, shoulder, seam]), STONE_TOP * tint)
	draw_colored_polygon(PackedVector2Array([
		left.lerp(heel, 0.45), seam, shoulder, right, foot.lerp(seam, 0.17), heel.lerp(seam, 0.10),
	]), STONE_FACE * tint)
	draw_line(slope.lerp(ridge, 0.59), ridge.lerp(crown, 0.63), STONE_TOP.lightened(0.12) * tint, 0.6, true)
	draw_line(seam.lerp(slope, 0.27), seam.lerp(shoulder, 0.35), STONE_FACE.lightened(0.08) * tint, 0.5, true)


func _draw_debris(end: float, bay_width: float) -> void:
	var spread := bay_width * (0.88 if _damage == Damage.COLLAPSED else 0.48)
	var center := 0.0 if _build == Build.COMPLETE else end - bay_width * 0.5
	var count := 5 if _damage == Damage.COLLAPSED else 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 8661
	for piece in count:
		var x := clampf(center + rng.randf_range(-spread, spread), -end + 2.4, end - 2.4)
		var across := rng.randf_range(-depth * 0.42, depth * 0.26)
		var reach := rng.randf_range(2.0, 4.9)
		var tip := clampf(x + (reach if piece % 2 == 0 else -reach), -end, end)
		_draw_wood(PackedVector2Array([
			_project(x, across, 0.4),
			_project(tip, clampf(across + rng.randf_range(-2.7, 2.7), -depth * 0.47, depth * 0.47), 1.0),
		]), 1.6 + rng.randf() * 0.65, 0.90, true)
