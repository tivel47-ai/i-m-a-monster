extends Control

signal initial_reveal_finished

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const ART = preload("res://assets/ui/zombie_development_grave_roots.png")
const FOG = preload("res://scripts/zombie_development_fog.gdshader")
const NODE_IDS := [PROGRESSION.FLESH, PROGRESSION.BRUTE, PROGRESSION.HUNGER]
const ASPECT := 1672.0 / 941.0
const ART_SCALE := Vector2(ASPECT, 1.0)
const CORE := Vector2(0.50, 0.474)
const NODE_POSITIONS := {
	PROGRESSION.FLESH: Vector2(0.289, 0.274),
	PROGRESSION.BRUTE: Vector2(0.163, 0.122),
	PROGRESSION.HUNGER: Vector2(0.726, 0.716),
}
# Coordinates follow the painted tendrils. Points after a node lead into the fog.
const ROUTES := [
	[CORE, Vector2(0.395, 0.493), Vector2(0.360, 0.468), Vector2(0.322, 0.457),
		Vector2(0.306, 0.417), Vector2(0.322, 0.347), NODE_POSITIONS[PROGRESSION.FLESH],
		Vector2(0.389, 0.219), Vector2(0.44, 0.193), Vector2(0.462, 0.137), Vector2(0.462, 0.084)],
	[NODE_POSITIONS[PROGRESSION.FLESH], Vector2(0.246, 0.278), Vector2(0.225, 0.253),
		Vector2(0.23, 0.211), Vector2(0.217, 0.187), Vector2(0.193, 0.175), NODE_POSITIONS[PROGRESSION.BRUTE]],
	[CORE, Vector2(0.603, 0.555), Vector2(0.636, 0.556), Vector2(0.647, 0.596),
		Vector2(0.639, 0.649), Vector2(0.675, 0.673), Vector2(0.685, 0.699), NODE_POSITIONS[PROGRESSION.HUNGER],
		Vector2(0.768, 0.770), Vector2(0.789, 0.817), Vector2(0.756, 0.886)],
]
const NODE_POINT_INDICES := [6, 6, 7]
const REVEAL_START := Vector3(0.0, 0.55, 0.08)
const REVEAL_END := Vector3(0.60, 1.0, 0.83)
const PULSE_PERIODS := Vector3(7.4, 11.3, 8.7)
const PULSE_DELAYS := Vector3(1.3, 5.2, 3.1)
const PULSE_DURATION := 1.7
const MAX_BRANCH_SEGMENTS := 26
const GROWTH_DURATION := 0.85
const VIEW_PADDING := Vector2(112.0, 112.0)
const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.15

var camera_speed := 500.0
var navigation_enabled := true
var zoom := ZOOM_MIN
var reveal_front := 0.0
var spread := Vector3.ZERO
var branch_growth := Vector3.ZERO
var _view_center := Vector2(0.5, 0.5)
var _target_reveal := 0.0
var _target_spread := Vector3.ZERO
var _target_growth := Vector3.ZERO
var _outline_strength := Vector3.ZERO
var _preview := false
var _elapsed := 0.0
var _overlay: Control
var _core_title: Label
var _material: ShaderMaterial
var _buttons: Dictionary[String, Button] = {}
var _paths: Array[Curve2D] = []
var _node_distances := PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	for index in ROUTES.size():
		var points: Array = ROUTES[index]
		var path := Curve2D.new()
		path.bake_interval = 0.02
		var distance := 0.0
		for point_index in points.size():
			var point: Vector2 = points[point_index] * ART_SCALE
			path.add_point(point)
			if point_index > 0:
				var previous: Vector2 = points[point_index - 1] * ART_SCALE
				distance += previous.distance_to(point)
			if point_index == NODE_POINT_INDICES[index]:
				_node_distances.append(distance)
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
	add_child(_overlay)

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
	spread = _target_spread
	branch_growth = _target_growth
	zoom = ZOOM_MIN
	_view_center = Vector2(0.5, 0.5)
	_update_view()
	_material.set_shader_parameter("preview", _preview)
	_update_growth_visuals()
	_update_pulses()


func sync_ranks(build: Dictionary) -> void:
	for index in NODE_IDS.size():
		var id: String = NODE_IDS[index]
		var rank := PROGRESSION.level(build, id)
		_target_spread[index] = float(rank) / PROGRESSION.NODES[id].costs.size()
		_target_growth[index] = 1.0 if rank > 0 else 0.0
		_outline_strength[index] = 1.0 if PROGRESSION.Draft.requirements_met(build, id) else 0.20


func upgrades_visible() -> bool:
	return _preview or reveal_front >= 1.0


func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var height := minf(size.y, size.x / ASPECT)
	_overlay.size = Vector2(height * ASPECT, height)
	_update_view()
	_core_title.add_theme_font_size_override("font_size", clampi(roundi(_overlay.size.x * 0.034), 19, 30))
	_core_title.position = Vector2(0.23, 0.554) * _overlay.size
	_core_title.size = Vector2(_overlay.size.x * 0.54, 0.0)
	var hitbox_size := Vector2.ONE * maxf(36.0, height * 0.16)
	for id in _buttons:
		var button := _buttons[id]
		var center: Vector2 = NODE_POSITIONS[id] * _overlay.size
		button.position = center - hitbox_size * 0.5
		button.size = hitbox_size


func _update_view() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _overlay.size.x <= 0.0 or _overlay.size.y <= 0.0:
		return
	var region := _overlay.size.max(size) + VIEW_PADDING
	var travel := (region - size / zoom) * 0.5 / _overlay.size
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
	var spread_target := _target_spread
	var next_growth := branch_growth
	for index in NODE_IDS.size():
		if _target_growth[index] == 0.0 and branch_growth[index] > 0.0 and _has_visible_child_branch(index):
			spread_target[index] = spread[index]
			continue
		next_growth[index] = move_toward(branch_growth[index], _target_growth[index], delta / GROWTH_DURATION)
	var next_spread := spread.move_toward(spread_target, delta * 1.25)
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
		var reveal := 1.0 if _preview else smoothstep(REVEAL_START[index], REVEAL_END[index], reveal_front)
		var growth := branch_growth[index] * reveal
		var node_light := smoothstep(0.68, 1.0, growth)
		node_spots.append(Vector4(node.x, node.y, reveal * _outline_strength[index], node_light))
		if growth <= 0.0:
			continue
		var to_node := _node_distances[index]
		var extension := (_paths[index].get_baked_length() - to_node) * spread[index]
		var remaining := to_node * growth + extension * node_light
		var points: Array = ROUTES[index]
		for step in range(points.size() - 1):
			if remaining <= 0.0:
				break
			var from: Vector2 = points[step] * ART_SCALE
			var to: Vector2 = points[step + 1] * ART_SCALE
			var length := from.distance_to(to)
			var tip := from.lerp(to, minf(1.0, remaining / length))
			segments.append(Vector4(from.x, from.y, tip.x, tip.y))
			var outer: bool = step >= NODE_POINT_INDICES[index]
			var radius := lerpf(0.041, 0.062, spread[index])
			segment_styles.append(Vector2(radius, 0.65 if outer else 1.0))
			remaining -= length
	_material.set_shader_parameter("node_spots", node_spots)
	_material.set_shader_parameter("branch_segment_count", segments.size())
	segments.resize(MAX_BRANCH_SEGMENTS)
	segment_styles.resize(MAX_BRANCH_SEGMENTS)
	_material.set_shader_parameter("branch_segments", segments)
	_material.set_shader_parameter("branch_styles", segment_styles)


func _update_pulses() -> void:
	var pulses := PackedVector4Array()
	var core := CORE * ART_SCALE
	var core_phase := clampf((fposmod(_elapsed + 0.6, 5.9) - 0.3) / 1.9, 0.0, 1.0)
	pulses.append(Vector4(core.x, core.y, 0.22 * sin(core_phase * PI), 0.205))
	for index in _paths.size():
		var phase := clampf(fposmod(_elapsed - PULSE_DELAYS[index], PULSE_PERIODS[index]) / PULSE_DURATION, 0.0, 1.0)
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
