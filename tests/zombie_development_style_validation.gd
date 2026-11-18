extends SceneTree

const P = preload("res://scripts/zombie_progression.gd")
const MAIN = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual style validation requires a graphical run with --rendering-method gl_compatibility (no --headless)")
		quit(1)
		return
	call_deferred("run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)


func settle() -> void:
	for frame in 5:
		await process_frame


func capture(label: String) -> void:
	if "--capture-style" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zombie_modular_%s.png" % label)


func run() -> void:
	root.size = Vector2i(1280, 720)
	var app := MAIN.instantiate()
	# The fixture never writes or reads the player's progression profile.
	app.set_meta("progression_path", "user://zombie_style_%d.cfg" % OS.get_process_id())
	root.add_child(app)
	app.progression.state.initial_unlocked = true
	app.progression.state.reveal_seen = true
	app.progression.state.virus = 5000
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._update_preview()
	app._open_development()
	var editor = app.development
	await settle()
	var improvements: ScrollContainer = editor.upgrades.get_parent()
	var abilities: ScrollContainer = editor.learned.get_parent()
	check(not improvements.get_v_scroll_bar().visible and not abilities.get_v_scroll_bar().visible,
		"Empty panels have no scrollbar")
	editor.draft.purchase(P.HUNGER)
	editor._refresh()
	await settle()
	check(not improvements.get_v_scroll_bar().visible and not abilities.get_v_scroll_bar().visible,
		"One upgrade and one learned ability have no scrollbar")
	await capture("single_1280")
	for id in P.NODES:
		while P.level(editor.draft.build, id) < P.NODES[id].costs.size():
			editor.draft.purchase(id)
	for index in 3:
		editor.draft.assign([P.HUNGER, P.FORTITUDE, P.SPASM][index], index)
	editor._refresh()
	editor.tree.begin(editor.draft.build, false, false)
	await settle()
	check(editor.learned.columns == 2 and editor.learned.get_child_count() == 3,
		"Learned abilities use a two-column grid")
	var first: Button = editor.learned.get_child(0)
	var second: Button = editor.learned.get_child(1)
	var third: Button = editor.learned.get_child(2)
	check(is_equal_approx(first.position.y, second.position.y) and second.position.x > first.position.x
		and third.position.y >= first.position.y + first.size.y and is_equal_approx(first.position.x, third.position.x),
		"Abilities fill rows left to right, two per row")
	check(first.size.x < abilities.size.x * 0.55 and first.size.y >= 104,
		"Ability cards use compact half-panel width and readable icons")
	check(not abilities.get_v_scroll_bar().visible, "All three current abilities fit without a scrollbar")
	for card in editor.learned.get_children():
		check(card.icon == P.NODES[card.ability].icon and editor.slots[editor.draft.build.slots.find(card.ability)].icon == card.icon,
			"Learned card and hotbar share the definition's icon: " + card.ability)
	for id in editor.tree.node_ids:
		check(editor.nodes[id].icon == P.NODES[id].icon, "Tree shares the definition's icon: " + id)
	check(editor.tree._node_layer.get_index() > editor.tree._branch_layer.get_index()
		and editor.tree._node_layer.z_index == 0,
		"All medallions, including the original three, render above connections")
	for branch in editor.tree._branches:
		var path: Curve2D = branch.path
		var target: Vector2 = editor.tree.definitions[branch.to].tree_position * editor.tree.ART_SCALE
		var origin: Vector2 = editor.tree.CORE if branch.from.is_empty() else editor.tree.definitions[branch.from].tree_position
		var radius: Vector2 = editor.tree.CORE_RADIUS if branch.from.is_empty() else Vector2.ONE * editor.tree.NODE_RADIUS
		check(absf(((path.sample_baked(branch.start) - origin * editor.tree.ART_SCALE) / radius).length() - 1.0) < 0.04
			and absf(path.sample_baked(branch.end).distance_to(target) - editor.tree.NODE_RADIUS) < 0.002
			and editor.tree.NODE_RADIUS < 0.175 * 0.30,
			"Connection ends overlap solid bark under the upper node layer: " + branch.to)
	for texture in [editor.tree.BRANCH_ART, editor.tree.BRANCH_ART_B, editor.tree.BRANCH_ART_LONG]:
		check(continuous_stem(texture.get_image()), "Painted root has an opaque connected stem from end to end: " + texture.resource_path)
	check(unfolded_meshes(editor.tree._branch_meshes), "Painted roots have no folded or degenerate triangles")
	var conflicts: Array[String] = await painted_layout_conflicts(editor.tree)
	check(conflicts.is_empty(), "Painted roots do not cross outside shared nodes: " + ", ".join(conflicts))
	await stable_rank_geometry(editor.tree, editor.draft.build)
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await settle()
		var left: Control = improvements.get_parent().get_parent()
		var right: Control = abilities.get_parent().get_parent()
		check(left.size.y > editor.size.y * 0.70 and right.size.y == left.size.y
			and left.get_global_rect().position.y > editor.reset_button.get_global_rect().end.y
			and left.get_global_rect().end.y < editor.back_button.get_global_rect().position.y,
			"Tall panels stay between header and footer at %s" % dimensions)
		for id in editor.nodes:
			var node: Control = editor.nodes[id]
			check(node.get_global_rect().position.x > left.get_global_rect().end.x
				and node.get_global_rect().end.x < right.get_global_rect().position.x,
				"Perk is clear of side panels at %s: %s" % [dimensions, id])
		await capture("full_%d" % dimensions.x)
	editor.tree.zoom = 2.5
	editor.tree._update_view()
	await settle()
	await capture("zoom_250")
	check(unfolded_meshes(editor.tree._branch_meshes), "Zoom preserves the root meshes without folds")
	editor.tree.zoom = 1.8
	editor.tree._view_center = Vector2(0.64, 0.58)
	editor.tree._update_view()
	await settle()
	await capture("roots_detail")
	editor.tree.zoom = 1.0
	editor.tree._view_center = Vector2(0.5, 0.5)
	editor.tree._update_view()
	root.size = Vector2i(1280, 720)
	await settle()
	check(improvements.get_v_scroll_bar().visible, "Ten upgrade descriptions scroll when they exceed the panel")
	# Future-sized content validates overflow without inventing more game abilities.
	for index in 16:
		editor.learned.add_child(first.duplicate())
	await settle()
	check(abilities.get_v_scroll_bar().visible, "Ability grid shows a scrollbar only when its rows overflow")
	abilities.scroll_vertical = 10000
	await settle()
	check(abilities.scroll_vertical > 0, "Overflowing ability rows can be scrolled")
	await capture("overflow_1280")
	editor._refresh()
	await settle()
	check(not abilities.get_v_scroll_bar().visible and abilities.scroll_vertical == 0,
		"Scrollbar and old offset disappear when the ability grid fits again")
	await scalability()
	app.queue_free()
	await process_frame
	print("Zombie development style: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func continuous_stem(image: Image) -> bool:
	# Connectivity catches cutout holes even when every column has some ink.
	var pending: Array[Vector2i] = []
	var visited := PackedByteArray()
	visited.resize(image.get_width() * image.get_height())
	for y in image.get_height():
		if image.get_pixel(0, y).a >= 0.65:
			pending.append(Vector2i(0, y))
			visited[y * image.get_width()] = 1
	var front := 0
	while front < pending.size():
		var point := pending[front]
		front += 1
		if point.x == image.get_width() - 1:
			return true
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = point + direction
			if next.x < 0 or next.y < 0 or next.x >= image.get_width() or next.y >= image.get_height():
				continue
			var index: int = next.y * image.get_width() + next.x
			if visited[index] == 0 and image.get_pixelv(next).a >= 0.65:
				visited[index] = 1
				pending.append(next)
	return false


func draw_patch(layer: Control, mesh: ArrayMesh, texture: Texture2D, factor: float) -> void:
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * factor)
	layer.draw_mesh(mesh, texture)


func painted_layout_conflicts(tree) -> Array[String]:
	# Render the actual textured meshes independently. Centre-line checks miss
	# crossings caused by the original painted bends and the root's width.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1672, 941)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var owners := PackedInt32Array()
	owners.resize(viewport.size.x * viewport.size.y)
	owners.fill(-1)
	var conflicts: Array[String] = []
	var reported := {}
	for index in tree._branches.size():
		var branch: Dictionary = tree._branches[index]
		var layer := Control.new()
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		viewport.add_child(layer)
		layer.draw.connect(draw_patch.bind(layer, tree._branch_meshes[index], branch.texture, 941.0 / tree._overlay.size.y))
		layer.queue_redraw()
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var data := image.get_data()
		var used := image.get_used_rect()
		for y in range(used.position.y, used.end.y):
			for x in range(used.position.x, used.end.x):
				var pixel := y * viewport.size.x + x
				if data[pixel * 4 + 3] < 115:
					continue
				var previous := owners[pixel]
				if previous == -1:
					owners[pixel] = index
					continue
				if previous == index:
					continue
				var other: Dictionary = tree._branches[previous]
				var shared := false
				for endpoint: String in [branch.from, branch.to]:
					if endpoint != other.from and endpoint != other.to:
						continue
					var center: Vector2 = tree.CORE if endpoint.is_empty() else tree.definitions[endpoint].tree_position
					center *= Vector2(1672, 941)
					var radius := Vector2(0.21, 0.15) * 941.0 if endpoint.is_empty() else Vector2.ONE * 78.0
					if ((Vector2(x, y) - center) / radius).length() < 1.0:
						shared = true
				if not shared:
					var pair := "%s / %s" % [other.to, branch.to]
					if not reported.has(pair):
						reported[pair] = true
						conflicts.append("%s at (%d, %d)" % [pair, x, y])
		layer.queue_free()
		await process_frame
	viewport.queue_free()
	await process_frame
	return conflicts


func mesh_geometry(tree) -> Array:
	var result := []
	for mesh: ArrayMesh in tree._branch_meshes:
		var arrays := mesh.surface_get_arrays(0)
		result.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_TEX_UV], arrays[Mesh.ARRAY_INDEX]])
	return result


func stable_rank_geometry(tree, full_build: Dictionary) -> void:
	var build := full_build.duplicate(true)
	for id in build.paid:
		build.paid[id] = [1]
	tree.begin(build, false, false)
	await settle()
	var original := mesh_geometry(tree)
	for rank in [3, 5, 1]:
		for id in build.paid:
			build.paid[id] = Array(full_build.paid[id]).slice(0, mini(rank, full_build.paid[id].size()))
		tree.sync_ranks(build)
		await settle()
		check(mesh_geometry(tree) == original, "Root vertices, UVs and detail stay identical at rank %d" % rank)
	tree.begin(full_build, false, false)
	await settle()


func unfolded_meshes(meshes: Array[ArrayMesh]) -> bool:
	for mesh in meshes:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var sign_area := 0.0
		for triangle in range(0, indices.size(), 3):
			var a := Vector2(vertices[indices[triangle]].x, vertices[indices[triangle]].y)
			var b := Vector2(vertices[indices[triangle + 1]].x, vertices[indices[triangle + 1]].y)
			var c := Vector2(vertices[indices[triangle + 2]].x, vertices[indices[triangle + 2]].y)
			var area := (b - a).cross(c - a)
			if absf(area) < 0.0001 or (sign_area != 0.0 and area * sign_area < 0.0):
				return false
			sign_area = area
	return true


func scalability() -> void:
	var tree = load("res://scripts/zombie_development_tree.gd").new()
	var definitions := P.NODES.duplicate(true)
	var build := {"initial_unlocked": true, "paid": {}, "revealed": PackedStringArray()}
	for index in 6:
		var id := "style_probe_%d" % index
		definitions[id] = {"tree_position": Vector2(0.22 + index * 0.11, 0.91),
			"requires": {P.FLESH: 1}, "costs": [1], "icon": P.NODES[P.FLESH].icon}
	definitions["style_probe_5"].requires[P.HUNGER] = 1
	for id: String in definitions:
		build.paid[id] = [1]
		build.revealed.append(id)
	tree.definitions = definitions
	tree.size = Vector2(1280, 720)
	root.add_child(tree)
	for id: String in definitions:
		tree.add_upgrade(id, Button.new())
	tree.begin(build, false, false)
	await settle()
	check(tree.node_ids.size() == 16 and tree.active_branch_count() == 17,
		"Sixteen nodes and multiple prerequisites render without changing shaders or artwork")
	check(tree._frames.values().all(func(frame): return frame.texture == tree.FRAME),
		"Original, new and future nodes all use the same extracted painted frame")
	check(tree._branch_meshes.size() == 17,
		"Every prerequisite produces exactly one real connection, with no decorative branches")
	tree.set_process(false)
	for id: String in definitions:
		build.paid.erase(id)
	tree.sync_ranks(build)
	for step in 8:
		tree._process(1.0)
	await settle()
	check(tree.active_branch_count() == 0 and tree.branch_growth.count(0.0) == 16,
		"Cascade retraction reaches zero even in the expanded graph")
	tree.queue_free()
	await process_frame
