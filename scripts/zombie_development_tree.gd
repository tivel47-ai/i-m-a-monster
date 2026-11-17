extends Control

signal initial_reveal_finished

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const INFECTION = preload("res://scripts/zombie_infection.gd")
const ART = preload("res://assets/ui/zombie_development_grave_roots.png")
const FOG = preload("res://scripts/zombie_development_fog.gdshader")
const BRANCH_ART = preload("res://assets/ui/zombie_development_tendril.png")
const NODE_IDS := [PROGRESSION.FLESH, PROGRESSION.BRUTE, PROGRESSION.HUNGER,
	PROGRESSION.TENDONS, PROGRESSION.SALIVA, PROGRESSION.GROWTHS,
	PROGRESSION.HOUND, PROGRESSION.CARRIER, PROGRESSION.FORTITUDE, PROGRESSION.SPASM]
const ASPECT := 1672.0 / 941.0
const ART_SCALE := Vector2(ASPECT, 1.0)
const CORE := Vector2(0.50, 0.474)
const NODE_POSITIONS := {
	PROGRESSION.FLESH: Vector2(0.289, 0.274),
	PROGRESSION.BRUTE: Vector2(0.163, 0.122),
	PROGRESSION.HUNGER: Vector2(0.726, 0.716),
	PROGRESSION.TENDONS: Vector2(0.86, 0.55),
	PROGRESSION.SALIVA: Vector2(0.45, 0.18),
	PROGRESSION.GROWTHS: Vector2(0.10, 0.72),
	PROGRESSION.HOUND: Vector2(0.94, 0.70),
	PROGRESSION.CARRIER: Vector2(0.65, 0.16),
	PROGRESSION.FORTITUDE: Vector2(0.30, 0.70),
	PROGRESSION.SPASM: Vector2(0.85, 0.81),
}
# Every route ends at an actual perk. The first three follow the original painting.
const ROUTES := [
	[CORE, Vector2(0.395, 0.493), Vector2(0.360, 0.468), Vector2(0.322, 0.457),
		Vector2(0.306, 0.417), Vector2(0.322, 0.347), NODE_POSITIONS[PROGRESSION.FLESH]],
	[NODE_POSITIONS[PROGRESSION.FLESH], Vector2(0.246, 0.278), Vector2(0.225, 0.253),
		Vector2(0.23, 0.211), Vector2(0.217, 0.187), Vector2(0.193, 0.175), NODE_POSITIONS[PROGRESSION.BRUTE]],
	[CORE, Vector2(0.603, 0.555), Vector2(0.636, 0.556), Vector2(0.647, 0.596),
		Vector2(0.639, 0.649), Vector2(0.675, 0.673), Vector2(0.685, 0.699), NODE_POSITIONS[PROGRESSION.HUNGER]],
	[NODE_POSITIONS[PROGRESSION.HUNGER], Vector2(0.79, 0.67), Vector2(0.80, 0.60), NODE_POSITIONS[PROGRESSION.TENDONS]],
	[NODE_POSITIONS[PROGRESSION.FLESH], Vector2(0.36, 0.26), Vector2(0.39, 0.19), NODE_POSITIONS[PROGRESSION.SALIVA]],
	[NODE_POSITIONS[PROGRESSION.BRUTE], Vector2(0.05, 0.28), Vector2(0.06, 0.58), NODE_POSITIONS[PROGRESSION.GROWTHS]],
	[NODE_POSITIONS[PROGRESSION.TENDONS], Vector2(0.91, 0.57), Vector2(0.93, 0.63), NODE_POSITIONS[PROGRESSION.HOUND]],
	[NODE_POSITIONS[PROGRESSION.SALIVA], Vector2(0.52, 0.15), Vector2(0.59, 0.17), NODE_POSITIONS[PROGRESSION.CARRIER]],
	[NODE_POSITIONS[PROGRESSION.FLESH], Vector2(0.24, 0.40), Vector2(0.25, 0.58), NODE_POSITIONS[PROGRESSION.FORTITUDE]],
	[NODE_POSITIONS[PROGRESSION.HUNGER], Vector2(0.76, 0.75), Vector2(0.80, 0.78), NODE_POSITIONS[PROGRESSION.SPASM]],
]
const REVEAL_START := [0.0, 0.55, 0.08]
const REVEAL_END := [0.60, 1.0, 0.83]
const PULSE_DURATION := 1.7
const MAX_BRANCH_SEGMENTS := 64
const GROWTH_DURATION := 0.85
const VIEW_PADDING := Vector2(112.0, 112.0)
const ZOOM_DEFAULT := 1.0
const ZOOM_MIN := 0.55
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.15

var camera_speed := 500.0
var navigation_enabled := true
var zoom := ZOOM_DEFAULT
var reveal_front := 0.0
var spread := PackedFloat32Array()
var branch_growth := PackedFloat32Array()
var _view_center := Vector2(0.5, 0.5)
var _target_reveal := 0.0
var _target_spread := PackedFloat32Array()
var _target_growth := PackedFloat32Array()
var _outline_strength := PackedFloat32Array()
var _revealed: Dictionary = {}
var _preview := false
var _elapsed := 0.0
var _overlay: Control
var _core_hover: Control
var _core_title: Label
var _material: ShaderMaterial
var _buttons: Dictionary[String, Button] = {}
var _paths: Array[Curve2D] = []
var _node_distances := PackedFloat32Array()
var _branch_meshes: Array[ArrayMesh] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	spread.resize(NODE_IDS.size())
	branch_growth.resize(NODE_IDS.size())
	_target_spread.resize(NODE_IDS.size())
	_target_growth.resize(NODE_IDS.size())
	_outline_strength.resize(NODE_IDS.size())
	for index in ROUTES.size():
		var points: Array = ROUTES[index]
		var path := Curve2D.new()
		path.bake_interval = 0.003
		for point_index in points.size():
			var point: Vector2 = points[point_index] * ART_SCALE
			path.add_point(point)
		# Round the new connections; avoid angular, wire-like corners.
		if index >= 3:
			for point_index in range(1, points.size() - 1):
				var before: Vector2 = points[point_index - 1] * ART_SCALE
				var after: Vector2 = points[point_index + 1] * ART_SCALE
				var tangent := (after - before) * 0.18
				path.set_point_in(point_index, -tangent)
				path.set_point_out(point_index, tangent)
		_node_distances.append(path.get_baked_length())
		_paths.append(path)

	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = FOG
	_material.set_shader_parameter("aspect", ASPECT)
	art.material = _material
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_overlay)
	_overlay.draw.connect(_draw_extensions)

	_core_hover = Control.new()
	_core_hover.mouse_filter = Control.MOUSE_FILTER_PASS
	var description := [
		"Инфицирование · Основная способность зомби",
		"Скрытно заражает крестьянина или ремесленника.",
		"В здании заражает одного подходящего жителя.",
		"Обращает цель в зомби через %d сек." % INFECTION.DURATION,
		"При смертельном уроне обращает сразу.",
		"На старте %d заряда. Применение тратит 1 заряд." % INFECTION.INITIAL_CHARGES,
		"+1 заряд за %d жителей, убитых вашими зомби" % INFECTION.KILLS_PER_CHARGE,
		"без обращения.",
	]
	_core_hover.tooltip_text = "\n".join(description)
	_overlay.add_child(_core_hover)

	_core_title = Label.new()
	_core_title.text = "Инфицирование"
	_core_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_core_title.add_theme_color_override("font_color", Color("ede2c8"))
	_core_title.add_theme_color_override("font_outline_color", Color("141511"))
	_core_title.add_theme_constant_override("outline_size", 8)
	_core_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_core_title)
	resized.connect(_layout)
	visibility_changed.connect(_update_processing)
	_layout()
	_update_growth_visuals()
	_update_pulses()
	_update_processing()


func add_upgrade(id: String, button: Button) -> void:
	_buttons[id] = button
	if NODE_IDS.find(id) >= 3:
		button.icon = PROGRESSION.NODES[id].icon
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		button.add_theme_stylebox_override(state, empty)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.22, 0.26, 0.14, 0.23)
	focus.border_color = Color("8a905f")
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(5)
	button.add_theme_stylebox_override("focus", focus)
	_overlay.add_child(button)
	_layout()


func begin(build: Dictionary, preview: bool, animate_reveal: bool) -> void:
	_preview = preview
	_target_reveal = 1.0 if build.initial_unlocked else 0.0
	reveal_front = 0.0 if animate_reveal else _target_reveal
	sync_ranks(build)
	spread = _target_spread.duplicate()
	branch_growth = _target_growth.duplicate()
	zoom = ZOOM_DEFAULT
	_view_center = Vector2(0.5, 0.5)
	_update_view()
	_material.set_shader_parameter("preview", _preview)
	_update_growth_visuals()
	_update_pulses()


func sync_ranks(build: Dictionary) -> void:
	for index in NODE_IDS.size():
		var id: String = NODE_IDS[index]
		var rank := PROGRESSION.level(build, id)
		_revealed[id] = PROGRESSION.is_revealed(build, id)
		_target_spread[index] = float(rank) / PROGRESSION.NODES[id].costs.size()
		_target_growth[index] = 1.0 if rank > 0 else 0.0
		_outline_strength[index] = 1.0 if PROGRESSION.Draft.requirements_met(build, id) else 0.20
	_update_growth_visuals()


func node_visible(id: String) -> bool:
	return _preview or (upgrades_visible() and _revealed.get(id, false))


func upgrades_visible() -> bool:
	return _preview or reveal_front >= 1.0


func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Fit the complete graph between the fixed sidebars on entry. Panning/zooming
	# still uses the full canvas, while panels stay in place above it.
	var height := minf(maxf(180.0, size.y - 176.0), maxf(320.0, size.x - 544.0) / ASPECT)
	_overlay.size = Vector2(height * ASPECT, height)
	_update_view()
	_core_hover.position = Vector2(0.36, 0.34) * _overlay.size
	_core_hover.size = Vector2(0.28, 0.29) * _overlay.size
	_core_title.add_theme_font_size_override("font_size", clampi(roundi(_overlay.size.x * 0.034), 19, 30))
	_core_title.position = Vector2(0.23, 0.554) * _overlay.size
	_core_title.size = Vector2(_overlay.size.x * 0.54, 0.0)
	for id in _buttons:
		var button := _buttons[id]
		var hitbox_size := Vector2.ONE * maxf(36.0, height * 0.175)
		var center: Vector2 = NODE_POSITIONS[id] * _overlay.size
		button.position = center - hitbox_size * 0.5
		button.size = hitbox_size
		if NODE_IDS.find(id) >= 3:
			button.add_theme_constant_override("icon_max_width", roundi(hitbox_size.x))


func _update_view() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _overlay.size.x <= 0.0 or _overlay.size.y <= 0.0:
		return
	var region := _overlay.size.max(size) + VIEW_PADDING * 2.0
	var travel := (region - size / zoom).max(Vector2.ZERO) * 0.5 / _overlay.size
	var middle := Vector2(0.5, 0.5)
	_view_center = _view_center.clamp(middle - travel, middle + travel)
	var scaled_size := _overlay.size * zoom
	_overlay.scale = Vector2.ONE * zoom
	_overlay.position = (size * 0.5 - _view_center * scaled_size).round()
	_material.set_shader_parameter("content_scale", scaled_size / size)
	_material.set_shader_parameter("content_origin", _overlay.position / size)


func _gui_input(event: InputEvent) -> void:
	if not navigation_enabled or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom = minf(ZOOM_MAX, zoom + ZOOM_STEP)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom = maxf(ZOOM_MIN, zoom - ZOOM_STEP)
	else:
		return
	_update_view()
	accept_event()


func _update_processing() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	if navigation_enabled and _overlay.size.x > 0.0 and _overlay.size.y > 0.0:
		var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		if direction != Vector2.ZERO:
			_view_center += direction * camera_speed * delta / _overlay.size
			_update_view()
	_elapsed += delta
	var was_visible := upgrades_visible()
	var next_front := move_toward(reveal_front, _target_reveal, delta / 1.3)
	var spread_target := _target_spread.duplicate()
	var next_growth := branch_growth.duplicate()
	var next_spread := spread.duplicate()
	for index in NODE_IDS.size():
		if _target_growth[index] == 0.0 and branch_growth[index] > 0.0 and _has_visible_child_branch(index):
			spread_target[index] = spread[index]
			continue
		next_growth[index] = move_toward(branch_growth[index], _target_growth[index], delta / GROWTH_DURATION)
	for index in NODE_IDS.size():
		next_spread[index] = move_toward(spread[index], spread_target[index], delta * 1.25)
	if next_front != reveal_front or next_spread != spread or next_growth != branch_growth:
		reveal_front = next_front
		spread = next_spread
		branch_growth = next_growth
		_update_growth_visuals()
		if not was_visible and upgrades_visible():
			initial_reveal_finished.emit()
	_update_pulses()


func _has_visible_child_branch(index: int) -> bool:
	var node: Vector2 = NODE_POSITIONS[NODE_IDS[index]]
	for child_index in ROUTES.size():
		if branch_growth[child_index] > 0.0 and ROUTES[child_index][0] == node:
			return true
	return false


func _update_growth_visuals() -> void:
	var node_spots := PackedVector4Array()
	var segments := PackedVector4Array()
	var segment_styles := PackedVector2Array()
	for index in NODE_IDS.size():
		var node: Vector2 = NODE_POSITIONS[NODE_IDS[index]] * ART_SCALE
		var reveal := 1.0 if _preview else (smoothstep(REVEAL_START[index], REVEAL_END[index], reveal_front) if index < 3 else float(_revealed.get(NODE_IDS[index], false)))
		var growth := branch_growth[index] * reveal
		var node_light := smoothstep(0.68, 1.0, growth)
		node_spots.append(Vector4(node.x, node.y, reveal * _outline_strength[index], node_light))
		if growth <= 0.0:
			continue
		# Only the original connections reveal the painting. New routes have
		# their own transparent art and must not uncover unrelated painted roots.
		if index >= 3:
			continue
		var remaining := _node_distances[index] * growth
		var points: Array = ROUTES[index]
		for step in range(points.size() - 1):
			if remaining <= 0.0:
				break
			var from: Vector2 = points[step] * ART_SCALE
			var to: Vector2 = points[step + 1] * ART_SCALE
			var length := from.distance_to(to)
			var tip := from.lerp(to, minf(1.0, remaining / length))
			segments.append(Vector4(from.x, from.y, tip.x, tip.y))
			var radius := lerpf(0.041, 0.062, spread[index])
			segment_styles.append(Vector2(radius, 1.0))
			remaining -= length
	_material.set_shader_parameter("node_spots", node_spots)
	_material.set_shader_parameter("branch_segment_count", segments.size())
	segments.resize(MAX_BRANCH_SEGMENTS)
	segment_styles.resize(MAX_BRANCH_SEGMENTS)
	_material.set_shader_parameter("branch_segments", segments)
	_material.set_shader_parameter("branch_styles", segment_styles)
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()
	for index in range(3, NODE_IDS.size()):
		var id: String = NODE_IDS[index]
		if _buttons.has(id):
			_buttons[id].modulate = Color.WHITE if branch_growth[index] >= 0.95 else Color(0.12, 0.14, 0.10, 0.85 if _outline_strength[index] == 1.0 else 0.45)


func _draw_extensions() -> void:
	# Bend a painted transparent root along each dependency, below its medallion.
	# Canvas drawing retains RIDs; keep their resources alive until the next draw.
	_branch_meshes.clear()
	for index in range(3, NODE_IDS.size()):
		var length := _node_distances[index]
		var growth := branch_growth[index]
		var shown := node_visible(NODE_IDS[index])
		var strength := 1.0 if growth > 0.0 else (0.18 if shown else 0.035)
		var fraction := growth if growth > 0.0 else 1.0
		var half_width := _overlay.size.y * lerpf(0.065, 0.08, spread[index])
		# Preserve the source root's proportions on short links instead of
		# squeezing its full length into a small, zigzagging connection.
		var texture_length := half_width * 2.0 / 0.6 * BRANCH_ART.get_width() / BRANCH_ART.get_height()
		texture_length = maxf(texture_length, length * _overlay.size.y)
		var mesh := ArrayMesh.new()
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for step in 65:
			var along := float(step) / 64.0 * fraction
			var distance := length * along
			var center := _paths[index].sample_baked(distance) / ART_SCALE * _overlay.size
			var before := _paths[index].sample_baked(maxf(0.0, distance - 0.003))
			var after := _paths[index].sample_baked(minf(length, distance + 0.003))
			var side := (after - before).normalized().orthogonal() * half_width
			for edge in [-1.0, 1.0]:
				var point: Vector2 = center + side * edge
				vertices.append(Vector3(point.x, point.y, 0.0))
				uvs.append(Vector2(distance * _overlay.size.y / texture_length, 0.5 + edge * 0.3))
			if step > 0:
				var base := step * 2
				indices.append_array(PackedInt32Array([base - 2, base - 1, base, base - 1, base + 1, base]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_branch_meshes.append(mesh)
		_overlay.draw_mesh(mesh, BRANCH_ART, Transform2D.IDENTITY, Color(0.75, 0.82, 0.75, strength))


func _update_pulses() -> void:
	var pulses := PackedVector4Array()
	var core := CORE * ART_SCALE
	var core_phase := clampf((fposmod(_elapsed + 0.6, 5.9) - 0.3) / 1.9, 0.0, 1.0)
	pulses.append(Vector4(core.x, core.y, 0.22 * sin(core_phase * PI), 0.205))
	for index in _paths.size():
		var phase := clampf(fposmod(_elapsed - 1.3 - index * 1.8, 7.4 + index * 0.7) / PULSE_DURATION, 0.0, 1.0)
		var distance := minf(1.0, phase / 0.72) * _node_distances[index]
		var energy := (0.21 + 0.12 * spread[index]) * sin(phase * PI) if upgrades_visible() and branch_growth[index] >= 1.0 else 0.0
		var radius := lerpf(0.060, 0.115, smoothstep(0.56, 0.82, phase))
		if branch_growth[index] < 1.0 and _target_growth[index] > 0.0 and upgrades_visible():
			distance = _node_distances[index] * branch_growth[index]
			energy = 0.34 * sin(branch_growth[index] * PI)
			radius = 0.07
		var point := _paths[index].sample_baked(distance)
		pulses.append(Vector4(point.x, point.y, energy, radius))
	_material.set_shader_parameter("pulses", pulses)
