extends SceneTree

const TREE = preload("res://scripts/zombie_development_tree.gd")
const P = preload("res://scripts/zombie_progression.gd")
var checks := 0
var failures := 0
var tree
var mask_view: SubViewport


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fog validation requires --rendering-method gl_compatibility, without --headless")
		quit(1)
		return
	call_deferred("run")


func check(value: bool, description: String) -> void:
	checks += 1
	if value:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)


func render_mask() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return mask_view.get_texture().get_image()


func opacity(image: Image, point: Vector2) -> float:
	var screen: Vector2 = tree._overlay.position + point * tree._overlay.size * tree.zoom
	var pixel := Vector2i(screen * Vector2(mask_view.size) / Vector2(root.size))
	return image.get_pixelv(pixel.clamp(Vector2i.ZERO, mask_view.size - Vector2i.ONE)).a


func clear_pixels(image: Image) -> int:
	var result := 0
	var data := image.get_data()
	for offset in range(3, data.size(), 4):
		if data[offset] < 75:
			result += 1
	return result


func freeze_time(value: float) -> void:
	tree._material.set_shader_parameter("mist_time", value)
	tree._fog_material.set_shader_parameter("mist_time", value)


func capture(label: String) -> void:
	if "--capture-fog" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zombie_fog_%s.png" % label)


func run() -> void:
	root.size = Vector2i(1280, 720)
	tree = TREE.new()
	tree.theme = preload("res://scripts/dark_fantasy_theme.gd").build(22, 8)
	tree.size = Vector2(root.size)
	root.add_child(tree)
	for id: String in P.NODES:
		tree.add_upgrade(id, Button.new())
	tree.set_process(false)
	var build := P._fresh_state()
	build.initial_unlocked = true
	build.virus = 5000
	var draft := P.Draft.new(build, 0)
	tree.begin(draft.build, false, true)
	mask_view = SubViewport.new()
	mask_view.size = Vector2i(640, 360)
	mask_view.transparent_bg = true
	mask_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mask_view)
	var fog := ColorRect.new()
	fog.size = Vector2(mask_view.size)
	fog.material = tree._fog_material
	mask_view.add_child(fog)
	freeze_time(0.0)
	var before := await render_mask()
	check(opacity(before, tree.CORE) < 0.05, "The infection core stays visible before the first reveal")
	check(opacity(before, P.NODES[P.FLESH].tree_position) > 0.90
		and opacity(before, P.NODES[P.BRUTE].tree_position) > 0.90,
		"Death fog initially covers the outer perk territories")
	check(not tree.upgrades_visible(), "First reveal keeps perk input locked until its wave finishes")
	await capture("initial_0")
	tree._process(0.65)
	freeze_time(0.0)
	var halfway := await render_mask()
	check(clear_pixels(halfway) > clear_pixels(before), "The open area grows outward from the core")
	check(opacity(halfway, P.NODES[P.FLESH].tree_position.lerp(tree.CORE, 0.25)) < 0.15
		and opacity(halfway, P.NODES[P.BRUTE].tree_position) > 0.70,
		"The wave reaches nearby Flesh before distant Brute")
	await capture("initial_half")
	tree._process(0.65)
	freeze_time(0.0)
	var opened := await render_mask()
	check(clear_pixels(opened) > clear_pixels(halfway) and tree.upgrades_visible(),
		"The initial reveal finishes with a larger opening and enabled nodes")
	check(opacity(opened, P.NODES[P.FLESH].tree_position) < 0.05
		and opacity(opened, P.NODES[P.BRUTE].tree_position) > 0.90
		and opacity(opened, P.NODES[P.HUNGER].tree_position) < 0.05,
		"Only entry silhouettes emerge; the second-tier Brute stays faint in mist")
	check(opacity(opened, P.NODES[P.SALIVA].tree_position) > 0.90 and not tree.node_visible(P.SALIVA),
		"The unopened continuation stays veiled and cannot be clicked")
	check(tree.node_state(P.FLESH) == tree.PerkView.AVAILABLE and tree.node_state(P.BRUTE) == tree.PerkView.DISTANT
		and not tree.node_visible(P.BRUTE) and not tree.node_visible(P.TENDONS),
		"Second-tier perks on both branches are faint and uninspectable until a parent is learned")
	check(tree.node_state(P.CARRIER) == tree.PerkView.DISTANT
		and tree._frames[P.CARRIER].get_parent() == tree._node_layer and not tree.node_visible(P.CARRIER),
		"Every distant perk has a consistent faint hint above the fog, without an input control")
	await capture("initial_open")
	draft.purchase(P.FLESH)
	tree.sync_ranks(draft.build)
	check(tree.node_state(P.SALIVA) == tree.PerkView.AVAILABLE
		and tree.node_state(P.FORTITUDE) == tree.PerkView.BLOCKED and tree.node_visible(P.FORTITUDE)
		and tree.node_state(P.BRUTE) == tree.PerkView.BLOCKED and tree.node_visible(P.BRUTE)
		and tree.node_state(P.CARRIER) == tree.PerkView.DISTANT,
		"Flesh I exposes available Saliva and gray Fortitude, while the next tier remains a faint hint")
	check(not P.is_revealed(draft.build, P.FORTITUDE) and not draft.purchase_block(P.FORTITUDE).is_empty(),
		"Inspecting a gray adjacent perk does not bypass its purchase requirements")
	freeze_time(0.0)
	var purchased := await render_mask()
	check(opacity(purchased, P.NODES[P.SALIVA].tree_position) > 0.90,
		"A purchase starts a new clearing wave instead of instantly removing the fog")
	tree._process(0.72)
	freeze_time(0.0)
	var spreading := await render_mask()
	var near_side: Vector2 = P.NODES[P.SALIVA].tree_position + Vector2(0.0, 0.07)
	var far_side: Vector2 = P.NODES[P.SALIVA].tree_position - Vector2(0.0, 0.07)
	check(opacity(spreading, near_side) + 0.4 < opacity(spreading, far_side),
		"The next territory opens from its infected parent toward its far edge")
	await capture("purchase_half")
	tree._process(0.6)
	freeze_time(0.0)
	var expanded := await render_mask()
	check(opacity(expanded, P.NODES[P.SALIVA].tree_position) < 0.05
		and clear_pixels(expanded) > clear_pixels(opened),
		"Infection reveals the new silhouette and expands the clear territory")
	check(opacity(expanded, P.NODES[P.FORTITUDE].tree_position) > 0.90
		and tree.node_visible(P.FORTITUDE),
		"The gray adjacent silhouette remains in mist while its tooltip is available")
	await check_ground_contrast(expanded)
	await capture("purchase_open")
	await check_root_coverage(expanded)
	freeze_time(2.0)
	var swaying := await render_mask()
	var moving_edge := 0
	var old_data := expanded.get_data()
	var new_data := swaying.get_data()
	for offset in range(3, old_data.size(), 4):
		if old_data[offset] > 10 and old_data[offset] < 240 and abs(int(old_data[offset]) - int(new_data[offset])) > 12:
			moving_edge += 1
	check(moving_edge > 300, "The boundary itself billows over time, with moving translucent wisps")
	draft.refund(P.FLESH)
	tree.sync_ranks(draft.build)
	tree._process(1.5)
	freeze_time(0.0)
	var refunded := await render_mask()
	check(opacity(refunded, P.NODES[P.SALIVA].tree_position) > 0.90 and not tree.node_visible(P.SALIVA)
		and tree.node_state(P.SALIVA) == tree.PerkView.DISTANT,
		"Refunding the parent restores fog and removes the descendant's tooltip despite saved discovery")
	tree.begin(draft.build, false, false)
	freeze_time(0.0)
	var reopened := await render_mask()
	check(opacity(reopened, P.NODES[P.SALIVA].tree_position) > 0.90 and tree.reveal_front == 1.0,
		"Reopening keeps refunded descendants distant without replaying the initial reveal")
	tree.zoom = 1.8
	tree._view_center = Vector2(0.46, 0.39)
	tree._update_view()
	var moved := await render_mask()
	check(opacity(moved, tree.CORE) < 0.05 and opacity(moved, P.NODES[P.FLESH].tree_position) < 0.05,
		"Fog holes follow the tree when the camera moves and zooms")
	for id: String in P.NODES:
		while P.level(draft.build, id) < P.NODES[id].costs.size():
			draft.purchase(id)
	tree.begin(draft.build, false, false)
	freeze_time(2.0)
	var full_mask := await render_mask()
	await check_root_coverage(full_mask)
	await capture("all_roots_clear")
	var regular_mask := full_mask
	tree.begin(draft.build, true, false)
	freeze_time(2.0)
	var developer_mask := await render_mask()
	check(tree._fog_layer.visible and regular_mask.get_data() == developer_mask.get_data(),
		"Developer mode renders exactly the same fog as ordinary mode")
	check(tree._fog_layer.get_index() < tree._overlay.get_index()
		and tree._frames[P.BRUTE].material == null,
		"Atmosphere cannot cover roots; silhouettes retain their original painted texture without a replacement shader")
	if "--record-fog" in OS.get_cmdline_user_args():
		await record_sequence()
	mask_view.queue_free()
	tree.queue_free()
	await process_frame
	await check_editor_modes_and_refunds()
	print("Zombie development fog: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check_ground_contrast(mask: Image) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.resize(mask.get_width(), mask.get_height())
	var clear_sum := 0.0
	var fog_sum := 0.0
	var clear_count := 0
	var fog_count := 0
	for y in range(0, mask.get_height(), 2):
		for x in range(0, mask.get_width(), 2):
			var color := frame.get_pixel(x, y)
			var light := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			var alpha := mask.get_pixel(x, y).a
			if alpha < 0.05:
				clear_sum += light
				clear_count += 1
			elif alpha > 0.90:
				fog_sum += light
				fog_count += 1
	var difference := fog_sum / maxi(1, fog_count) - clear_sum / maxi(1, clear_count)
	check(difference > 0.045, "Exposed ground visibly differs from the foggy region (luminance difference %.3f)" % difference)


func draw_roots(layer: Control) -> void:
	var ratio := Vector2(mask_view.size) / Vector2(root.size)
	layer.draw_set_transform(tree._overlay.position * ratio, 0.0, ratio * tree.zoom)
	var mesh_index := 0
	for branch in tree._branches:
		var growth: float = tree.branch_growth[branch.index]
		if growth >= 1.0:
			layer.draw_mesh(tree._branch_meshes[mesh_index], branch.texture)
		mesh_index += 1


func check_root_coverage(mask: Image) -> void:
	var viewport := SubViewport.new()
	viewport.size = mask_view.size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := Control.new()
	viewport.add_child(layer)
	layer.draw.connect(draw_roots.bind(layer))
	layer.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var roots := viewport.get_texture().get_image()
	var covered := 0
	var pixels := 0
	for y in roots.get_height():
		for x in roots.get_width():
			if roots.get_pixel(x, y).a < 0.70:
				continue
			pixels += 1
			if mask.get_pixel(x, y).a > 0.08:
				covered += 1
	check(pixels > 50 and covered == 0, "Grown roots remain clear of fog in this build (%d / %d obscured pixels)" % [covered, pixels])
	viewport.queue_free()
	await process_frame


func record_sequence() -> void:
	var build := P._fresh_state()
	build.initial_unlocked = true
	build.virus = 5000
	var draft := P.Draft.new(build, 0)
	tree.begin(draft.build, false, true)
	for index in 48:
		if index == 18:
			draft.purchase(P.FLESH)
			tree.sync_ranks(draft.build)
		tree._process(0.10)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zombie_fog_sequence_%02d.png" % index)


func settle_editor(editor, seconds: float) -> void:
	# Advance the real editor in small steps, including growth and retraction.
	for step in ceili(seconds / 0.1):
		editor.tree._process(0.1)
		await process_frame
	for step in 4:
		await process_frame


func check_editor_modes_and_refunds() -> void:
	var app = preload("res://scenes/main.tscn").instantiate()
	app.set_meta("progression_path", "user://zombie_fog_editor_%d.cfg" % OS.get_process_id())
	root.add_child(app)
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app.developer_mode = true
	app._show(app.Screen.RACES)
	app._update_preview()
	app._open_development()
	var editor = app.development
	editor.tree.set_process(false)
	check(editor.developer_controls.visible and editor.tree._fog_layer.visible
		and not editor.nodes[P.FLESH].visible,
		"Fresh developer profile has resource controls and ordinary fog, with no false clickable previews")
	editor._adjust_virus(10)
	check(editor.tree._target_reveal == 1.0 and editor.tree.reveal_front == 0.0,
		"First developer credit starts the initial discovery wave")
	await settle_editor(editor, 1.5)
	check(editor.nodes[P.FLESH].visible and editor.nodes[P.HUNGER].visible
		and not editor.nodes[P.BRUTE].visible and editor.nodes[P.BRUTE].tooltip_text.is_empty()
		and not editor.nodes[P.TENDONS].visible,
		"First credit reveals only the two entry perks in developer mode")
	editor.draft.build.virus = 0
	editor._refresh()
	await settle_editor(editor, 1.5)
	check(editor.tree.node_state(P.FLESH) == editor.tree.PerkView.BLOCKED
		and editor.tree.node_state(P.HUNGER) == editor.tree.PerkView.BLOCKED
		and editor.tree.node_state(P.BRUTE) == editor.tree.PerkView.DISTANT
		and editor.tree.node_state(P.TENDONS) == editor.tree.PerkView.DISTANT
		and editor.nodes[P.BRUTE].tooltip_text.is_empty(),
		"At zero Virus both entry nodes are gray and both second-tier nodes are faint without tooltips")
	await capture("editor_zero_budget")
	editor.draft.build.virus = 8
	editor._refresh()
	await settle_editor(editor, 1.5)
	check(editor.tree.node_state(P.FLESH) == editor.tree.PerkView.AVAILABLE
		and editor.tree.node_state(P.HUNGER) == editor.tree.PerkView.BLOCKED
		and editor.tree._fog_front[editor.tree.node_ids.find(P.FLESH)] == 1.0
		and editor.tree._fog_front[editor.tree.node_ids.find(P.HUNGER)] == 0.0,
		"At eight Virus only affordable Flesh is dark and clears fog; Hunger stays gray")
	await capture("editor_eight_budget")
	editor.draft.build.virus = 10
	editor._refresh()
	editor._purchase(P.FLESH)
	await settle_editor(editor, 1.5)
	check(P.level(editor.draft.build, P.FLESH) == 1
		and editor.nodes[P.SALIVA].visible and editor.nodes[P.FORTITUDE].visible
		and editor.nodes[P.BRUTE].visible and "ур. 2" in editor.nodes[P.BRUTE].tooltip_text
		and not editor.nodes[P.GROWTHS].visible,
		"Developer purchases use real prices and expose only adjacent perks")
	await capture("editor_developer")
	# Give this isolated draft a budget, then open the long routed branch.
	editor._adjust_virus(200)
	editor._purchase(P.FLESH)
	editor._purchase(P.BRUTE)
	await settle_editor(editor, 1.5)
	var route: Dictionary
	for branch in editor.tree._branches:
		if branch.to == P.GROWTHS:
			route = branch
	var midpoint: Vector2 = route.path.sample_baked((route.start + route.end) * 0.5, true)
	var mask_point := Vector2i((midpoint + Vector2.ONE * editor.tree.ROOT_MASK_PADDING) * editor.tree.ROOT_MASK_HEIGHT)
	await RenderingServer.frame_post_draw
	check(editor.tree._root_mask_view.get_texture().get_image().get_pixelv(mask_point).a > 0.98
		and editor.nodes[P.GROWTHS].visible,
		"The real menu clears the long routed connection even before buying its visible target")
	await capture("editor_long_route")
	# Refund during a newly started wave, not just after static full-build setup.
	editor._purchase(P.SALIVA)
	editor._purchase(P.SALIVA)
	editor.tree._process(0.3)
	editor._refund_input(_right_click(), P.BRUTE)
	check(not editor.nodes[P.GROWTHS].visible and editor.nodes[P.GROWTHS].tooltip_text.is_empty(),
		"Refund removes the distant target's real Button and tooltip immediately")
	editor._refund_input(_right_click(), P.FLESH)
	editor._refund_input(_right_click(), P.FLESH)
	var old_front: float = editor.tree._fog_front[editor.tree.node_ids.find(P.CARRIER)]
	editor.tree._process(0.1)
	check(old_front > 0.0 and editor.tree._fog_front[editor.tree.node_ids.find(P.CARRIER)] < old_front
		and not editor.nodes[P.CARRIER].visible and editor.nodes[P.CARRIER].tooltip_text.is_empty(),
		"Cancelling a parent reverses an in-flight reveal instead of continuing it")
	await settle_editor(editor, 3.0)
	check(editor.tree.active_branch_count() == 0 and editor.tree._fog_front[editor.tree.node_ids.find(P.GROWTHS)] == 0.0
		and not editor.nodes[P.GROWTHS].visible and not editor.nodes[P.SALIVA].visible,
		"Cascaded refund removes grown paths and all extra discovery corridors")
	await capture("editor_refunded")
	# Saved discovery must not resurrect paths when switching modes or reopening.
	app.progression.state = editor.draft.build.duplicate(true)
	app.developer_mode = false
	app._show(app.Screen.RACES)
	app._open_development()
	editor.tree.set_process(false)
	var normal_states: Dictionary = editor.tree._view_states.duplicate()
	check(not editor.developer_controls.visible and not editor.nodes[P.GROWTHS].visible
		and editor.nodes[P.GROWTHS].tooltip_text.is_empty(),
		"Reopening ordinary mode ignores historical discovery of a now distant perk")
	app.developer_mode = true
	app._show(app.Screen.RACES)
	app._open_development()
	editor.tree.set_process(false)
	check(normal_states == editor.tree._view_states and editor.tree._fog_layer.visible,
		"Switching developer mode preserves all four visibility states and fog")
	app.queue_free()
	await process_frame


func _right_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event
