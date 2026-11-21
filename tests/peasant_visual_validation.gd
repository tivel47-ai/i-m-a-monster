extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const VILLAGER = preload("res://scenes/villager.tscn")
const VISUAL = preload("res://scripts/peasant_visual.gd")
const PROGRESSION = preload("res://scripts/zombie_progression.gd")
const BELL_CIVILIANS = preload("res://assets/sprites/characters/bell_pull/civilians.png")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mission := MISSION.instantiate()
	mission.set_meta("developer_mode", true)
	root.add_child(mission)
	for frame in 8:
		await physics_frame
	var craftspeople: Array = mission.villagers.filter(func(actor): return actor.civilian_profile == "Craftsman")
	_check(craftspeople.size() == 5, "Mission 1 keeps all five craftspeople")
	await _check_profile(mission, "Peasant", "PeasantVisual", "peasant", Vector2(350, 1000))
	await _check_profile(mission, "Craftsman", "ArtisanVisual", "artisan", Vector2(500, 1000))
	_check_artisan_bell_transition(mission)
	var outside_mission := VILLAGER.instantiate()
	outside_mission.civilian_profile = "Craftsman"
	root.add_child(outside_mission)
	_check(not outside_mission.has_node("ArtisanVisual") and outside_mission.polygon.is_visible_in_tree(),
		"The craftsman keeps the prototype body on maps without the graphics flag")
	print("Civilian visual validation: %d/%d passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _check_profile(mission: Node, profile: String, visual_name: String, kind: String, point: Vector2) -> void:
	var residents: Array = mission.villagers.filter(func(actor): return actor.civilian_profile == profile)
	_check(not residents.is_empty() and residents.all(func(actor): return actor.has_node(visual_name)),
		"Mission 1 loads the sprite for " + profile)
	if not mission.developer_place(kind, point):
		_check(false, "Developer placement failed for " + profile)
		return
	var actor: Node2D = mission.villagers.back()
	var sprite := actor.get_node_or_null(visual_name) as VISUAL
	_check(sprite != null and not actor.polygon.visible, "Developer placement uses the same sprite")
	if sprite == null:
		return
	_check((sprite.texture == VISUAL.ATLAS) == (profile == "Peasant"), "Profile uses its own atlas")
	_check(actor.get_node("CollisionShape2D").shape.size == Vector2(7.8, 15.6)
		and is_equal_approx(sprite.scale.y * VISUAL.FRAME_HEIGHT, VISUAL.WORLD_HEIGHT)
		and sprite.position.y == VISUAL.FEET_Y, "Sprite scale, feet anchor and collider agree")
	_check_atlas(sprite.texture)

	actor.set_physics_process(false)
	actor.navigation_agent.avoidance_enabled = false
	mission.mission_build = mission._make_ability_runtime(PROGRESSION._fresh_state())
	mission.toggle_tactical_pause()
	var paused_frame := sprite.region_rect
	await create_timer(0.24).timeout
	_check(paused and sprite.region_rect == paused_frame, "Tactical pause stops pose changes")
	mission.toggle_tactical_pause()
	sprite.set_physics_process(false)
	for step in [2, 27]:
		sprite._idle_time = step * VISUAL.IDLE_FRAME_TIME + 0.01
		sprite._show_idle()
		_check(_cell(sprite).y == VISUAL.IDLE_ROW + int(step >= 24), "Idle plays each authored sequence")

	var headings := {}
	for direction in 16:
		var movement := Vector2.from_angle(PI / 2.0 - direction * VISUAL.TURN_STEP)
		for frame in 8:
			actor.global_position += movement
			sprite._physics_process(0.04)
		_check(sprite._direction == direction and sprite._motion == VISUAL.Motion.WALK,
			"Turntable reaches walking direction %d" % direction)
		sprite._show_turn()
		headings[_cell(sprite)] = true
	_check(headings.size() == 16, "Each heading uses a different turn pose")
	for running in [false, true]:
		var used := {}
		var frames := VISUAL.RUN_FRAMES if running else VISUAL.WALK_FRAMES
		sprite._motion = VISUAL.Motion.RUN if running else VISUAL.Motion.WALK
		for step in frames:
			sprite._stride = (float(step) + 0.3) / frames
			sprite._show_locomotion()
			used[_cell(sprite)] = true
		_check(used.size() == frames, "Locomotion uses its full stride cycle")
	actor.threat_reaction.reaction_state = actor.threat_reaction.Reaction.FLEEING
	actor.global_position += Vector2(2, 2)
	sprite._physics_process(0.04)
	_check(sprite._motion == VISUAL.Motion.RUN, "Fleeing selects the run cycle")
	actor.threat_reaction.cancel_response()

	var opponent: Node2D = ZOMBIE.instantiate()
	opponent.max_health = 300.0
	opponent.position = actor.position + Vector2(12, -12)
	mission.add_child(opponent)
	opponent.set_physics_process(false)
	_check(actor.begin_encounter(Color.GREEN, opponent), profile + " enters a real encounter")
	var timer: Timer = actor.encounter_attack_timer
	timer.start(0.12)
	timer.wait_time = actor.attack_interval
	sprite._physics_process(0.4)
	for frame in 8:
		sprite._physics_process(0.04)
	var strike_rows := {}
	var health_before: float = opponent.current_health
	var aim_pose := _cell(sprite)
	_check(aim_pose.x < VISUAL.CONTACT_FRAME and aim_pose.y >= VISUAL.ACTION_ROW + VISUAL.ACTION_ROWS_PER_VIEW
		and opponent.current_health == health_before, "Rear-view windup plays before damage")
	for attack in VISUAL.ATTACK_COUNT:
		health_before = opponent.current_health
		timer.timeout.emit()
		var contact := _cell(sprite)
		_check(contact.x == VISUAL.CONTACT_FRAME and opponent.current_health == health_before - actor.attack_damage,
			"Encounter timeout applies one hit on the contact frame")
		strike_rows[contact.y] = true
		actor.take_damage(1.0)
		_check(sprite._clip == VISUAL.Clip.ATTACK and _cell(sprite) == contact, "Recoil cannot interrupt contact")
		sprite._physics_process(0.4)
	_check(strike_rows.size() == 3, "All three unarmed variants play in succession")
	actor.cancel_encounter()
	actor.take_damage(1.0)
	sprite._physics_process(0.15)
	_check(sprite._clip == VISUAL.Clip.HURT and _cell(sprite).x == 3, "A nonlethal hit animates recoil")

	var final_poses := {}
	for variant in 2:
		var falling: Node2D = actor
		if variant == 1:
			falling = VILLAGER.instantiate()
			falling.civilian_profile = profile
			falling.position = point + Vector2(35, 3)
			mission.add_child(falling)
		var body := falling.get_node(visual_name) as VISUAL
		body._death_variant = variant
		falling.take_damage(1000.0)
		body._physics_process(0.35)
		_check(falling.is_dead() and body._clip == VISUAL.Clip.DEATH and body.is_visible_in_tree()
			and not falling.death_marker_a.visible and _cell(body).x in range(1, 7),
			"Fatal damage starts a visible falling sequence")
		body._physics_process(0.6)
		final_poses[_cell(body)] = true
		_check(_cell(body).x == VISUAL.ACTION_FRAMES - 1 and not body.is_physics_processing(),
			"Final pose is retained after the fall")
	_check(final_poses.size() == 2, "The two deaths have different final poses")


func _check_artisan_bell_transition(mission: Node) -> void:
	for infected in [false, true]:
		var actor := VILLAGER.instantiate()
		actor.civilian_profile = "Craftsman"
		actor.set_meta("village_role", "artisan")
		mission.add_child(actor)
		var sprite := actor.get_node("ArtisanVisual") as VISUAL
		actor.show_bell_pose(BELL_CIVILIANS, Rect2(0, 160, 128, 160), Vector2(72, 136))
		var bell_pose := actor.get_node("BellPullPose") as Sprite2D
		_check(bell_pose.visible and not sprite.visible, "Craftsman switches to the rope pose")
		if infected:
			actor.apply_player_infection(10.0)
		actor.take_damage(actor.max_health)
		if infected:
			_check(not bell_pose.visible and not sprite.visible and actor.infection_state == actor.InfectionState.CONVERTED,
				"Conversion hides both the rope pose and the craftsman sprite")
		else:
			_check(not bell_pose.visible and sprite.visible and sprite._clip == VISUAL.Clip.DEATH,
				"Fatal damage replaces the rope pose with the falling sequence")
		actor.queue_free()


func _check_atlas(atlas: Texture2D) -> void:
	var image := atlas.get_image()
	var size := Vector2i(VISUAL.CELL)
	var counts := [8, 8, 8, 8, 12, 10, 12, 10, 12, 10, 12, 10, 12, 10,
		8, 8, 8, 6, 8, 8, 8, 8, 8, 6, 8, 8]
	_check(image.get_size() == Vector2i(12, counts.size()) * size and image.has_mipmaps(),
		"The atlas dimensions, layout and mipmaps are loaded")
	var count := 0
	var safe := true
	for row in counts.size():
		for column in counts[row]:
			var frame := image.get_region(Rect2i(Vector2i(column, row) * size, size))
			var used := frame.get_used_rect()
			var top_world := VISUAL.FEET_Y + (used.position.y - VISUAL.ANCHOR.y) * VISUAL.WORLD_HEIGHT / VISUAL.FRAME_HEIGHT
			safe = safe and used.has_area() and used.position.x >= 2 and used.end.x <= size.x - 2
			safe = safe and used.end.y <= VISUAL.ANCHOR.y and top_world > VISUAL.COMBAT_HEALTH_BAR_Y + 2.6
			count += 1
	_check(safe and count == 234, "All 234 atlas cells contain a padded silhouette clear of the health bar")


func _cell(sprite: Sprite2D) -> Vector2i:
	return Vector2i(sprite.region_rect.position / VISUAL.CELL)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
