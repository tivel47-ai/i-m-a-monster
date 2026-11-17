extends SceneTree

const P = preload("res://scripts/zombie_progression.gd")
const MAIN = preload("res://scenes/main.tscn")
var failures := 0
var checks := 0


func _initialize() -> void:
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
		root.get_texture().get_image().save_png("res://.godot/zombie_style_%s.png" % label)


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
	for index in editor.tree.NODE_IDS.size():
		var id: String = editor.tree.NODE_IDS[index]
		check(editor.tree.ROUTES[index][-1] == editor.tree.NODE_POSITIONS[id], "Branch ends at its perk: " + id)
		if index >= 3:
			check(editor.nodes[id].icon == P.NODES[id].icon, "Tree shares the painted icon: " + id)
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
	app.queue_free()
	await process_frame
	print("Zombie development style: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
