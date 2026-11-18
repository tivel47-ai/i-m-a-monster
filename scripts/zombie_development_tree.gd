extends Control

signal initial_reveal_finished

const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const INFECTION = preload("res://scripts/zombie_infection.gd")
const FOG = preload("res://scripts/zombie_development_fog.gdshader")
const FRAME = preload("res://assets/ui/zombie_style/perk_frame.png")
const CORE_ART = preload("res://assets/ui/zombie_style/infection_core.png")
const BRANCH_ART = preload("res://assets/ui/zombie_style/painted_root.png")
const BRANCH_ART_B = preload("res://assets/ui/zombie_style/painted_root_b.png")
const BRANCH_ART_LONG = preload("res://assets/ui/zombie_style/painted_root_long.png")
const ASPECT := 1672.0 / 941.0
const ART_SCALE := Vector2(ASPECT, 1.0)
const CORE := Vector2(0.50, 0.474)
# Attach inside the opaque bark, rather than stopping outside its ragged rim.
# The upper node layer hides these short overlaps and protects every emblem.
const NODE_RADIUS := 0.033
const CORE_RADIUS := Vector2(0.115, 0.067)
const GROWTH_DURATION := 0.85
const VIEW_PADDING := Vector2(112.0, 112.0)
const ZOOM_DEFAULT := 1.0
const ZOOM_MIN := 0.55
const ZOOM_MAX := 2.5
const ZOOM_STEP := 0.15
const ROOT_MASK_HEIGHT := 471.0
const ROOT_MASK_PADDING := 0.24
enum PerkView { DISTANT, BLOCKED, AVAILABLE, OWNED }

# Node layout and prerequisites come from ability definitions. No node limit.
var definitions: Dictionary = PROGRESSION.NODES
var node_ids: Array[String] = []
var camera_speed := 500.0
var navigation_enabled := true
var zoom := ZOOM_DEFAULT
var reveal_front := 0.0
var branch_growth := PackedFloat32Array()
var _view_center := Vector2(0.5, 0.5)
var _target_reveal := 0.0
var _target_growth := PackedFloat32Array()
var _outline_strength := PackedFloat32Array()
var _revealed: Dictionary = {}
var _view_states: Dictionary = {}
var _elapsed := 0.0
var _overlay: Control
var _branch_layer: Control
var _node_layer: Control
var _core_hover: Control
var _core_sprite: TextureRect
var _core_title: Label
var _material: ShaderMaterial
var _fog_material: ShaderMaterial
var _fog_layer: ColorRect
var _title_layer: Control
var _root_mask_view: SubViewport
var _root_mask_layer: Control
var _clear_brush: GradientTexture2D
var _fog_sites: ImageTexture
var _fog_front := PackedFloat32Array()
var _initial_fog_radius := 0.0
var _buttons: Dictionary[String, Button] = {}
var _frames: Dictionary[String, TextureRect] = {}
var _branches: Array[Dictionary] = []
var _branch_meshes: Array[ArrayMesh] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	node_ids.assign(definitions.keys())
	branch_growth.resize(node_ids.size())
	_target_growth.resize(node_ids.size())
	_outline_strength.resize(node_ids.size())
	_fog_front.resize(node_ids.size())
	_build_connections()
	var background := ColorRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = FOG
	_material.set_shader_parameter("aspect", ASPECT)
	background.material = _material
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = _layer(self)
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_branch_layer = _layer(_overlay)
	_branch_layer.z_index = 0
	_branch_layer.draw.connect(_draw_connections)
	_node_layer = _layer(_overlay)
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = FOG
	_fog_material.set_shader_parameter("aspect", ASPECT)
	_fog_material.set_shader_parameter("overlay_pass", true)
	_fog_layer = ColorRect.new()
	_fog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_layer.material = _fog_material
	add_child(_fog_layer)
	_fog_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Art stays above the atmosphere. Its own tint controls visibility; fog
	# must never erase a rendered connection or recolor a painted medallion.
	move_child(_fog_layer, _overlay.get_index())
	_title_layer = _layer(self)
	_create_root_mask()
	# Sibling order keeps nodes above roots while fixed UI panels stay above
	# the entire tree; a positive z_index would also lift nodes over sidebars.
	_core_sprite = _sprite(_node_layer, CORE_ART)
	_core_hover = Control.new()
	_core_hover.mouse_filter = Control.MOUSE_FILTER_PASS
	_core_hover.tooltip_text = "\n".join([
		"Инфицирование · Основная способность зомби",
		"Скрытно заражает крестьянина или ремесленника.",
		"В здании заражает одного подходящего жителя.",
		"Обращает цель в зомби через %d сек." % INFECTION.DURATION,
		"При смертельном уроне обращает сразу.",
		"На старте %d заряда. Применение тратит 1 заряд." % INFECTION.INITIAL_CHARGES,
		"+1 заряд за %d жителей, убитых вашими зомби" % INFECTION.KILLS_PER_CHARGE,
		"без обращения."])
	_node_layer.add_child(_core_hover)
	_core_title = Label.new()
	_core_title.text = "Инфицирование"
	_core_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_core_title.add_theme_color_override("font_color", Color("ede2c8"))
	_core_title.add_theme_color_override("font_outline_color", Color("141511"))
	_core_title.add_theme_constant_override("outline_size", 8)
	_core_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(_core_title)
	resized.connect(_layout)
	visibility_changed.connect(_update_processing)
	_layout()
	_update_processing()


func _layer(parent: Node) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer


func _sprite(parent: Node, texture: Texture2D) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sprite)
	return sprite


func _create_root_mask() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	_clear_brush = GradientTexture2D.new()
	_clear_brush.gradient = gradient
	_clear_brush.width = 128
	_clear_brush.height = 128
	_clear_brush.fill = GradientTexture2D.FILL_RADIAL
	_clear_brush.fill_from = Vector2(0.5, 0.5)
	_clear_brush.fill_to = Vector2(1.0, 0.5)
	_root_mask_view = SubViewport.new()
	_root_mask_view.size = Vector2i(ceili((ASPECT + ROOT_MASK_PADDING * 2.0) * ROOT_MASK_HEIGHT), ceili((1.0 + ROOT_MASK_PADDING * 2.0) * ROOT_MASK_HEIGHT))
	_root_mask_view.transparent_bg = true
	_root_mask_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_root_mask_view)
	_root_mask_layer = _layer(_root_mask_view)
	_root_mask_layer.draw.connect(_draw_root_clearance)
	_fog_material.set_shader_parameter("root_clearance", _root_mask_view.get_texture())
	_fog_material.set_shader_parameter("root_mask_padding", Vector2.ONE * ROOT_MASK_PADDING)
	_fog_material.set_shader_parameter("root_mask_extent", Vector2(ASPECT, 1.0) + Vector2.ONE * ROOT_MASK_PADDING * 2.0)


func _draw_root_clearance() -> void:
	var height := ROOT_MASK_HEIGHT
	var radius := height * 0.19
	for branch in _branches:
		var index: int = branch.index
		var scouting := minf(_fog_front[index], reveal_front)
		var growth := maxf(branch_growth[index], scouting)
		if growth <= 0.0:
			continue
		var path: Curve2D = branch.path
		var length: float = (branch.end - branch.start) * growth
		var steps := maxi(1, ceili(length / 0.035))
		for step in steps + 1:
			var point := path.sample_baked(branch.start + length * step / steps, true)
			var brush_radius := radius
			if definitions[branch.to].requires.is_empty() and reveal_front < 1.0:
				# Only entry nodes participate in the initial wave from the core.
				brush_radius = minf(radius, maxf(0.0, reveal_front * _initial_fog_radius - point.distance_to(CORE * ART_SCALE)) * height)
			if brush_radius <= 0.0:
				continue
			var center := (point + Vector2.ONE * ROOT_MASK_PADDING) * height
			_root_mask_layer.draw_texture_rect(_clear_brush, Rect2(center - Vector2.ONE * brush_radius, Vector2.ONE * brush_radius * 2.0), false)


func _build_connections() -> void:
	for id in node_ids:
		var parents: Array = definitions[id].requires.keys()
		if parents.is_empty():
			parents.append("")
		for parent: String in parents:
			var origin: Vector2 = CORE if parent.is_empty() else definitions[parent].tree_position
			var target: Vector2 = definitions[id].tree_position
			var points: Array = [origin]
			points.append_array(definitions[id].get("tree_via", []))
			points.append(target)
			# Long routes need bends along their length, not one enormous straight
			# stretch of a small texture. The complete painted S-bend stays in UVs.
			var routed: Array[Vector2] = [origin * ART_SCALE]
			for segment in points.size() - 1:
				var a: Vector2 = points[segment] * ART_SCALE
				var b: Vector2 = points[segment + 1] * ART_SCALE
				var delta := b - a
				var divisions := maxi(1, ceili(delta.length() / 0.16))
				var sign_side := 1.0 if node_ids.find(id) % 2 == 0 else -1.0
				for part in range(1, divisions + 1):
					var t := float(part) / divisions
					routed.append(a.lerp(b, t) + delta.normalized().orthogonal()
						* sin(t * TAU) * minf(0.034, delta.length() * 0.14) * sign_side)
			var path := Curve2D.new()
			path.bake_interval = 0.001
			for point: Vector2 in routed:
				path.add_point(point)
			if routed.size() == 2:
				var delta := (target - origin) * ART_SCALE
				var bend := delta.orthogonal() * 0.12
				path.set_point_out(0, delta * 0.30 + bend)
				path.set_point_in(1, -delta * 0.30 - bend)
			else:
				for index in range(1, routed.size() - 1):
					var tangent: Vector2 = (routed[index + 1] - routed[index - 1]) * 0.20
					path.set_point_in(index, -tangent)
					path.set_point_out(index, tangent)
			var first := 0.0
			var last := path.get_baked_length()
			var radius := CORE_RADIUS if parent.is_empty() else Vector2.ONE * NODE_RADIUS
			while first < last and ((path.sample_baked(first) - origin * ART_SCALE) / radius).length() < 1.0:
				first += 0.001
			while last > first and path.sample_baked(last).distance_to(target * ART_SCALE) < NODE_RADIUS:
				last -= 0.001
			var texture := BRANCH_ART if node_ids.find(id) % 2 == 0 else BRANCH_ART_B
			if (last - first) * 941.0 > 460.0:
				texture = BRANCH_ART_LONG
			_branches.append({"from": parent, "to": id, "index": node_ids.find(id),
				"texture": texture,
				"path": path, "start": first, "end": last})
		if definitions[id].requires.is_empty():
			_initial_fog_radius = maxf(_initial_fog_radius,
				(CORE * ART_SCALE).distance_to(definitions[id].tree_position * ART_SCALE) + 0.30)


func add_upgrade(id: String, button: Button) -> void:
	_buttons[id] = button
	_frames[id] = _sprite(_node_layer, FRAME)
	button.icon = definitions[id].icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.22, 0.26, 0.14, 0.23)
	focus.border_color = Color("8a905f")
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(5)
	button.add_theme_stylebox_override("focus", focus)
	_node_layer.add_child(button)
	_layout()


func begin(build: Dictionary, _developer_mode: bool, animate_reveal: bool) -> void:
	# Developer mode only adds resource controls in the editor, not a second
	# set of discovery, tooltip or fog rules.
	_target_reveal = 1.0 if build.initial_unlocked else 0.0
	reveal_front = 0.0 if animate_reveal else _target_reveal
	sync_ranks(build)
	branch_growth = _target_growth.duplicate()
	for index in node_ids.size():
		_fog_front[index] = 1.0 if node_state(node_ids[index]) in [PerkView.AVAILABLE, PerkView.OWNED] else 0.0
	zoom = ZOOM_DEFAULT
	_view_center = Vector2(0.5, 0.5)
	_update_view()
	_update_growth_visuals()


func sync_ranks(build: Dictionary) -> void:
	_target_reveal = 1.0 if build.initial_unlocked else 0.0
	for index in node_ids.size():
		var id: String = node_ids[index]
		var rank: int = build.paid.get(id, []).size()
		var adjacent := false
		for parent: String in definitions[id].requires:
			adjacent = adjacent or not build.paid.get(parent, []).is_empty()
		# Saved discovery is history, not current reachability. Refunding a
		# parent immediately removes tooltips from the now distant descendants.
		_revealed[id] = rank > 0 or (build.initial_unlocked and (definitions[id].requires.is_empty() or adjacent))
		_target_growth[index] = 1.0 if rank > 0 else 0.0
		var met := true
		for parent: String in definitions[id].requires:
			if build.paid.get(parent, []).size() < definitions[id].requires[parent]:
				met = false
		_outline_strength[index] = 1.0 if met else 0.20
		var affordable: bool = rank < definitions[id].costs.size() and build.get("virus", 0) >= definitions[id].costs[rank]
		_view_states[id] = PerkView.OWNED if rank > 0 else (PerkView.DISTANT if not _revealed[id]
			else (PerkView.AVAILABLE if met and affordable else PerkView.BLOCKED))
	_update_growth_visuals()


func node_visible(id: String) -> bool:
	return upgrades_visible() and _revealed.get(id, false)


func node_state(id: String) -> PerkView:
	return _view_states.get(id, PerkView.DISTANT)


func upgrades_visible() -> bool:
	return reveal_front >= 1.0


func _layout() -> void:
	if not is_instance_valid(_overlay) or size.x <= 0.0 or size.y <= 0.0:
		return
	var height := minf(maxf(180.0, size.y - 176.0), maxf(320.0, size.x - 544.0) / ASPECT)
	_overlay.size = Vector2(height * ASPECT, height)
	_branch_layer.size = _overlay.size
	_node_layer.size = _overlay.size
	_core_sprite.size = Vector2(0.468, 0.356) * height
	_core_sprite.position = CORE * _overlay.size - _core_sprite.size * 0.5
	_core_hover.position = _core_sprite.position
	_core_hover.size = _core_sprite.size
	_core_title.add_theme_font_size_override("font_size", clampi(roundi(_overlay.size.x * 0.034), 19, 30))
	_core_title.position = Vector2(0.23, 0.554) * _overlay.size
	_core_title.size = Vector2(_overlay.size.x * 0.54, 0.0)
	for id in _buttons:
		var center: Vector2 = definitions[id].tree_position * _overlay.size
		var diameter := maxf(36.0, height * 0.175)
		_frames[id].size = Vector2.ONE * diameter
		_frames[id].position = center - _frames[id].size * 0.5
		_buttons[id].size = _frames[id].size
		_buttons[id].position = _frames[id].position
		_buttons[id].add_theme_constant_override("icon_max_width", roundi(diameter * 0.62))
	_update_view()
	_branch_layer.queue_redraw()


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
	_title_layer.position = _overlay.position
	_title_layer.scale = _overlay.scale
	_material.set_shader_parameter("content_scale", scaled_size / size)
	_material.set_shader_parameter("content_origin", _overlay.position / size)
	_fog_material.set_shader_parameter("content_scale", scaled_size / size)
	_fog_material.set_shader_parameter("content_origin", _overlay.position / size)
	_branch_layer.queue_redraw()


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
	var next_growth := branch_growth.duplicate()
	var fog_changed := false
	for index in node_ids.size():
		var clear_target := 1.0 if node_state(node_ids[index]) in [PerkView.AVAILABLE, PerkView.OWNED] else 0.0
		var next_fog := move_toward(_fog_front[index], clear_target, delta / 1.2)
		fog_changed = fog_changed or next_fog != _fog_front[index]
		_fog_front[index] = next_fog
		if _target_growth[index] == 0.0 and branch_growth[index] > 0.0 and _has_visible_child_branch(index):
			continue
		next_growth[index] = move_toward(branch_growth[index], _target_growth[index], delta / GROWTH_DURATION)
	if next_front != reveal_front or next_growth != branch_growth or fog_changed:
		reveal_front = next_front
		branch_growth = next_growth
		_update_growth_visuals()
		if not was_visible and upgrades_visible():
			initial_reveal_finished.emit()
	_update_pulses()
	_material.set_shader_parameter("mist_time", _elapsed)
	_fog_material.set_shader_parameter("mist_time", _elapsed)


func _has_visible_child_branch(index: int) -> bool:
	for branch in _branches:
		if branch.from == node_ids[index] and branch_growth[branch.index] > 0.0:
			return true
	return false


func _update_growth_visuals() -> void:
	for index in node_ids.size():
		var id: String = node_ids[index]
		if not _buttons.has(id):
			continue
		_frames[id].visible = reveal_front > 0.0
		var light := smoothstep(0.68, 1.0, branch_growth[index])
		var state := node_state(id)
		# Retain the accepted painted texture and original dark/veiled tint.
		# Only the third, distant state adds a weaker version of that silhouette.
		var alpha := 0.10 if state == PerkView.DISTANT else (0.75 if state in [PerkView.AVAILABLE, PerkView.OWNED] else 0.40)
		var silhouette := Color(0.14, 0.17, 0.13, alpha * smoothstep(0.0, 1.0, reveal_front))
		_frames[id].modulate = silhouette.lerp(Color.WHITE, light)
		_buttons[id].self_modulate = Color(1.0, 1.0, 1.0, light)
	if is_instance_valid(_branch_layer):
		_branch_layer.queue_redraw()
	if is_instance_valid(_fog_material):
		_update_fog_sites()
		_root_mask_layer.queue_redraw()
		_root_mask_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_fog_sites() -> void:
	var image := Image.create(maxi(1, _branches.size()), 2, false, Image.FORMAT_RGBAF)
	for site in _branches.size():
		var branch := _branches[site]
		var index: int = branch.index
		var initial: bool = definitions[branch.to].requires.is_empty()
		var source: Vector2 = CORE if initial or branch.from.is_empty() else definitions[branch.from].tree_position
		var target: Vector2 = definitions[branch.to].tree_position
		source *= ART_SCALE
		target *= ART_SCALE
		var radius := 0.16 + 0.05 * branch_growth[index]
		var wave := minf(reveal_front * _initial_fog_radius, _fog_front[index] * (_initial_fog_radius + 0.08)) if initial else _fog_front[index] * (source.distance_to(target) + radius + 0.08)
		image.set_pixel(site, 0, Color(source.x, source.y, target.x, target.y))
		image.set_pixel(site, 1, Color(wave, radius, 0.0, 1.0 if _fog_front[index] > 0.0 else 0.0))
	if _fog_sites == null:
		_fog_sites = ImageTexture.create_from_image(image)
		_fog_material.set_shader_parameter("reveal_sites", _fog_sites)
	else:
		_fog_sites.update(image)
	_fog_material.set_shader_parameter("reveal_count", _branches.size())


func active_branch_count() -> int:
	var count := 0
	for branch in _branches:
		if branch_growth[branch.index] > 0.0:
			count += 1
	return count


func _draw_connections() -> void:
	_branch_meshes.clear()
	for branch in _branches:
		var index: int = branch.index
		var growth := branch_growth[index]
		var path: Curve2D = branch.path
		# Every real dependency has a faint full-length route, including distant
		# tiers. Inspectability only controls node input and fog clearing.
		var strength := 1.0 if growth > 0.0 else 0.13 * reveal_front
		if strength == 0.0 or branch.end <= branch.start:
			continue
		var fraction := growth if growth > 0.0 else 1.0
		var length: float = (branch.end - branch.start) * fraction
		var height := _overlay.size.y
		var texture: Texture2D = branch.texture
		# Preserve the original transverse scale. A long route must not become
		# an equally wide, blurry ribbon. Native painted bends remain intact.
		# Rank changes never resize or resample a grown root.
		var half_width := texture.get_height() * 0.5 * height / 941.0
		# A 2D painted patch needs parallel transverse rows. Rotating each row
		# with the tangent folds its original S-bend over itself at tight turns.
		var side := (path.sample_baked(branch.end) - path.sample_baked(branch.start)).normalized().orthogonal() * half_width
		var steps := maxi(2, ceili(length * height / 2.0))
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for step in steps + 1:
			var along := float(step) / steps
			var distance: float = branch.start + length * along
			var center := path.sample_baked(distance, true) * height
			for edge in [-1.0, 1.0]:
				var point: Vector2 = center + side * edge
				vertices.append(Vector3(point.x, point.y, 0.0))
				uvs.append(Vector2(along * fraction, (edge + 1.0) * 0.5))
			if step > 0:
				var base := step * 2
				indices.append_array(PackedInt32Array([base - 2, base - 1, base, base - 1, base + 1, base]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_branch_meshes.append(mesh)
		_branch_layer.draw_mesh(mesh, texture, Transform2D.IDENTITY, Color(1.0, 1.0, 1.0, strength))


func _update_pulses() -> void:
	var light := 0.98 + sin(_elapsed * 1.05) * 0.02
	_core_sprite.self_modulate = Color(light, light, light, 1.0)
	for index in node_ids.size():
		var id: String = node_ids[index]
		if _frames.has(id) and branch_growth[index] >= 1.0:
			var node_light := 0.98 + sin(_elapsed * 1.1 - index * 1.3) * 0.02
			_frames[id].self_modulate = Color(node_light, node_light, node_light, 1.0)
