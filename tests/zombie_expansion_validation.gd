extends SceneTree

const P = preload("res://scripts/zombie_progression.gd")
const BUILD = preload("res://scripts/zombie_mission_build.gd")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const MAIN = preload("res://scenes/main.tscn")
var checks := 0
var failures := 0
var save_path := "user://zombie_expansion_%s.cfg" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
	else:
		print("PASS: ", description)


func buy(draft: P.Draft, id: String, rank: int) -> void:
	while P.level(draft.build, id) < rank:
		var before := P.level(draft.build, id)
		draft.purchase(id)
		if P.level(draft.build, id) == before:
			check(false, "Could not purchase " + id)
			break


func spawn_form(runtime: BUILD, form: String) -> Node2D:
	var found := false
	for value in 1000:
		seed(value)
		if P.choose_form(runtime.build, randf()) == form:
			seed(value)
			found = true
			break
	check(found, "Found deterministic conversion roll for " + form)
	var unit := ZOMBIE.instantiate()
	runtime.prepare_zombie(unit, true)
	root.add_child(unit)
	unit.set_physics_process(false)
	return unit


func run() -> void:
	root.size = Vector2i(1280, 720)
	var profile := P.new(save_path)
	check(P.NODES.size() == 10 and profile.state.revealed.is_empty(), "Ten purchasable nodes, no new sectors in a fresh profile")
	profile.credit_conversion()
	check(P.NODES.keys().filter(func(id): return P.is_revealed(profile.state, id)).size() == 3,
		"The first Virus still reveals exactly three original nodes")
	var draft := profile.begin_edit()
	draft.build.virus = 2000
	check(not draft.purchase_block(P.SALIVA).is_empty(), "A hidden continuation cannot be bought")
	buy(draft, P.FLESH, 1)
	check(P.is_revealed(draft.build, P.SALIVA) and not P.is_revealed(draft.build, P.FORTITUDE), "Flesh I reveals saliva, not Flesh III fortitude")
	buy(draft, P.SALIVA, 2)
	buy(draft, P.CARRIER, 1)
	draft.refund(P.FLESH)
	check(draft.build.virus == 2000 and P.level(draft.build, P.CARRIER) == 0 and P.level(draft.build, P.SALIVA) == 0,
		"Cascade refunds both new dependent nodes at full actual cost")
	check(P.is_revealed(draft.build, P.CARRIER) and P.is_revealed(draft.build, P.SALIVA), "Cascade refunds preserve revealed sectors")
	check(profile.apply(draft) == OK and P.new(save_path).state.revealed == draft.build.revealed, "Reveals survive save and reload")
	draft = profile.begin_edit()
	for id in P.NODES:
		buy(draft, id, P.NODES[id].costs.size())
	check(draft.build.virus == 619, "Full expanded tree costs 1381 Virus, with original prices unchanged")
	draft.assign(P.HUNGER, 0)
	draft.assign(P.FORTITUDE, 3)
	draft.assign(P.SPASM, 7)
	check(profile.apply(draft) == OK, "Expanded build with three active abilities saves")
	var counts := {"": 0, P.BRUTE: 0, P.HOUND: 0, P.CARRIER: 0}
	for index in 1000:
		counts[P.choose_form(profile.state, (index + 0.5) / 1000.0)] += 1
	check(counts == {"": 760, P.BRUTE: 100, P.HOUND: 80, P.CARRIER: 60}, "One shared roll has exact disjoint 76/10/8/6 shares")
	var only_brute := profile.state.duplicate(true)
	only_brute.paid.erase(P.HOUND)
	only_brute.paid.erase(P.CARRIER)
	check(P.choose_form(only_brute, 0.12).is_empty() and P.choose_form(only_brute, 0.20).is_empty()
		and P.choose_form(only_brute, 0.05) == P.BRUTE, "Unowned shares return to ordinary zombies without changing Brute")
	var runtime := BUILD.new(profile.state, 7.8)
	var ordinary := spawn_form(runtime, "")
	var brute := spawn_form(runtime, P.BRUTE)
	var hound := spawn_form(runtime, P.HOUND)
	var carrier := spawn_form(runtime, P.CARRIER)
	check(is_equal_approx(ordinary.max_health, 150.0) and is_equal_approx(ordinary.infection_chance, 0.20), "Ordinary zombie receives Flesh V and Saliva V")
	check(brute.is_brute and is_equal_approx(brute.max_health, 300.0) and is_equal_approx(brute.attack_damage, 30.0)
		and is_equal_approx(brute.infection_chance, 0.02) and is_equal_approx(brute.attack_interval, 2.0), "Brute retains original combat parameters and 2% infection")
	check(hound.zombie_form == P.HOUND and not hound.is_brute and is_equal_approx(hound.max_health, 105.0)
		and is_equal_approx(hound.move_speed, 125.0) and is_equal_approx(hound.attack_damage, 14.0)
		and is_equal_approx(hound.infection_chance, 0.20), "Hound has its approved form and passive parameters")
	check(carrier.zombie_form == P.CARRIER and not carrier.is_brute and is_equal_approx(carrier.max_health, 187.5)
		and is_equal_approx(carrier.move_speed, 80.0) and is_equal_approx(carrier.attack_damage, 10.0)
		and is_equal_approx(carrier.infection_chance, 0.30), "Carrier has its approved form and passive parameters")
	check(is_equal_approx(brute.movement_speed(), 71.5) and is_equal_approx(hound.movement_speed(), 137.5), "Tendons add speed relative to each form's base")
	check(is_equal_approx(brute.entrance_damage(), 37.5) and is_equal_approx(ordinary.entrance_damage(), 25.0)
		and ordinary.attack_damage == 20.0, "Bone growths increase entrance damage without changing resident damage")
	ordinary.apply_racial_effect(P.FORTITUDE, P.NODES[P.FORTITUDE].effects[4])
	var health_before: float = ordinary.current_health
	ordinary.take_damage(20.0)
	check(is_equal_approx(health_before - ordinary.current_health, 15.4), "Fortitude V reduces actual incoming damage by 23% without healing")
	ordinary.apply_hunger(0.33, 14.0)
	ordinary.apply_racial_effect(P.SPASM, P.NODES[P.SPASM].effects[4])
	check(is_equal_approx(ordinary.movement_speed(), 128.0) and is_equal_approx(ordinary.effective_attack_interval(), 1.0 / 1.23),
		"Hunger, tendons and spasm add speed modifiers; attack frequency uses the reciprocal interval")
	ordinary.apply_racial_effect(P.SPASM, P.NODES[P.SPASM].effects[4])
	check(is_equal_approx(ordinary.attack_frequency_bonus, 0.23) and is_equal_approx(ordinary.racial_timers[P.SPASM].time_left, 10.0), "Repeated spasm refreshes duration without stacking")
	ordinary._expire_racial_effect(P.SPASM)
	ordinary._expire_racial_effect(P.FORTITUDE)
	check(ordinary.damage_reduction == 0.0 and ordinary.effective_attack_interval() == 1.0
		and is_equal_approx(ordinary.movement_speed(), 143.0), "Expiring new buffs preserves hunger and tendons")
	for unit in [ordinary, brute, hound, carrier]:
		unit.queue_free()
	await process_frame
	profile.mark_reveal_seen()
	await integration(profile)
	check_migration(profile)
	draft = profile.begin_edit()
	draft.reset()
	check(draft.build.revealed.size() == 7 and draft.build.slots == P.empty_slots() and draft.build.virus == 2000,
		"Full tree refund clears all slots and purchases, retains all seven reveals, refunds 100%")
	check(profile.reset_progress() == OK and profile.state.revealed.is_empty(), "Full profile reset also removes sector reveals")
	DirAccess.remove_absolute(save_path)
	print("Zombie expansion: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func integration(profile: P) -> void:
	var app := MAIN.instantiate()
	app.set_meta("progression_path", save_path)
	root.add_child(app)
	app.selected_mission = "mission_1"
	app.selected_race = "zombie"
	app._show(app.Screen.RACES)
	app._update_preview()
	app._open_development()
	await process_frame
	check(app.development.nodes.values().all(func(button): return button.visible and not button.tooltip_text.is_empty()), "All purchased or revealed nodes have visible, inspectable tree controls")
	for id in [P.FORTITUDE, P.SPASM]:
		check(app.development.nodes[id].icon == P.NODES[id].icon, "New active tree emblem uses its shared definition: " + id)
	if "--capture-expansion" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zombie_expansion_tree.png")
	app.development.request_exit()
	app._start_mission()
	var mission = app.mission
	for resident in mission.villagers:
		resident.set_physics_process(false)
	var runtime: BUILD = mission.mission_build
	var unit := ZOMBIE.instantiate()
	runtime.prepare_zombie(unit, false)
	unit.position = Vector2(400, 400)
	mission.add_child(unit)
	unit.set_physics_process(false)
	var hud = mission.mission_hud
	check(runtime.abilities.size() == 3 and [0, 3, 7].all(func(index): return hud.ability_slots[index].icon == P.NODES[runtime.build.slots[index]].icon), "Mission HUD uses the shared icons of all three assigned abilities")
	mission.toggle_tactical_pause()
	for id in [P.HUNGER, P.FORTITUDE, P.SPASM]:
		mission.toggle_racial_targeting(id)
		runtime.confirm(unit.global_position, true, mission)
	check(runtime.queued_abilities == [P.HUNGER, P.FORTITUDE, P.SPASM]
		and runtime.abilities.values().all(func(ability): return ability.uses == 4)
		and unit.hunger_timer == null and unit.damage_reduction == 0.0, "Mixed paused queue reserves each independent stock without starting effects")
	mission.toggle_racial_targeting(P.SPASM)
	check(not runtime.targeting and runtime.queued_points.size() == 3, "Cancelling targeting preserves all confirmed abilities")
	mission.toggle_tactical_pause()
	check(runtime.queued_points.is_empty() and unit.hunger_timer != null
		and is_equal_approx(unit.damage_reduction, 0.23) and is_equal_approx(unit.attack_frequency_bonus, 0.23)
		and runtime.abilities.values().all(func(ability): return ability.uses == 4), "Resuming executes the mixed queue with no second charge deduction")
	if "--capture-expansion" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/zombie_expansion_hud.png")
	mission.toggle_racial_targeting(P.FORTITUDE)
	runtime.confirm(Vector2(-1000, -1000), false, mission)
	check(runtime.uses_for(P.FORTITUDE) == 3 and runtime.uses_for(P.SPASM) == 4, "Empty area spends only the selected ability's stock")
	var late := ZOMBIE.instantiate()
	runtime.prepare_zombie(late, false)
	late.position = unit.position
	mission.add_child(late)
	late.set_physics_process(false)
	check(late.damage_reduction == 0.0 and late.attack_frequency_bonus == 0.0 and late.hunger_timer == null, "Late arrivals do not inherit previously applied area buffs")
	var remaining: float = unit.racial_timers[P.FORTITUDE].time_left
	mission.toggle_tactical_pause()
	await create_timer(0.04, true).timeout
	check(unit.racial_timers[P.FORTITUDE].time_left == remaining, "Tactical pause freezes the new effect timers")
	mission.toggle_tactical_pause()
	unit.apply_racial_effect(P.FORTITUDE, {"reduction": 0.15, "duration": 0.02})
	unit.apply_racial_effect(P.SPASM, {"frequency": 0.15, "speed": -0.15, "duration": 0.02})
	await create_timer(0.08).timeout
	check(unit.damage_reduction == 0.0 and unit.attack_frequency_bonus == 0.0 and unit.hunger_timer.time_left > 0.0, "Both new effects expire through their real timers without clearing hunger")
	check_entrances(mission, runtime)
	app.queue_free()
	await process_frame
	check(P.new(save_path).state == profile.state, "Mission use does not rewrite purchases or saved build")


func check_entrances(mission: Node2D, runtime: BUILD) -> void:
	var building: InteractiveBuilding = mission.buildings[0]
	for other in mission.buildings:
		other.set_physics_process(false)
	var unit := ZOMBIE.instantiate() as CharacterBody2D
	runtime.prepare_zombie(unit, false)
	mission.add_child(unit)
	unit.set_physics_process(false)
	unit.apply_racial_effect(P.SPASM, P.NODES[P.SPASM].effects[4])
	unit.global_position = building.layout.exterior(building.layout.clearance(unit) + 1.0)
	building.door_closed = true
	building.door_hp = 100.0
	building.reinforcement = 0.0
	building._crossing = null
	building.order_assault(unit)
	building.set_physics_process(false)
	building._update_attackers(1.0 / 60.0)
	check(is_equal_approx(building.door_hp, 75.0)
		and is_equal_approx(building.attackers[unit].next_hit - building._elapsed, 1.0 / 1.23),
		"Actual exterior assault uses bone growth damage and spasm attack interval")
	building.cancel_assault(unit)
	building.door_hp = 100.0
	unit.interior_building = building
	unit.global_position = building.layout.interior(0.0, 5.0)
	building._crossing = unit
	building._crossing_out = true
	building._crossing_started = false
	building._crossing_approach = unit.global_position
	building._crossing_lane = 0.0
	building._next_exit_hit = 0.0
	building._advance_crossing(1.0 / 60.0)
	check(is_equal_approx(building.door_hp, 75.0)
		and is_equal_approx(building._next_exit_hit - building._elapsed, 1.0 / 1.23),
		"Actual inside exit attack uses the same growth damage and spasm interval")


func check_migration(profile: P) -> void:
	var legacy := P._fresh_state()
	legacy.initial_unlocked = true
	legacy.paid = {P.FLESH: [8, 16, 28], P.BRUTE: [25], P.HUNGER: [10, 20, 35]}
	legacy.slots[2] = P.HUNGER
	legacy.virus = 91
	legacy.erase("revealed")
	var config := ConfigFile.new()
	config.set_value("zombies", "version", 2)
	config.set_value("zombies", "profile", legacy)
	var path := save_path + ".legacy"
	config.save(path)
	var migrated := P.new(path)
	check(migrated.save_error == OK and migrated.state.virus == 91 and migrated.state.paid == legacy.paid
		and migrated.state.slots == legacy.slots and migrated.state.revealed.size() == 5,
		"Version 2 migration preserves wallet, purchases and slots and reveals eligible continuations")
	migrated.flush()
	check(P.new(path).state == migrated.state, "Migrated expanded profile reloads in version 3")
	DirAccess.remove_absolute(path)
