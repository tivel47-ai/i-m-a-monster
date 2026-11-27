extends SceneTree
## Run with --headless --path . --script tests/audio_foundation_validation.gd -- --require-pack

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const MAIN = preload("res://scenes/main.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const AUDIO = preload("res://scripts/audio/audio_manager.gd")
const REGISTRY = preload("res://scripts/audio/audio_registry.gd")
const SETTINGS = preload("res://scripts/game_settings.gd")
const PROFILE = preload("res://scripts/zombie_progression.gd")
const SETTINGS_FILE := "user://audio_foundation_validation.cfg"
const WIND := &"ambience.wind.base"
const CHATTER := &"human.civilian.chatter"
const FEAR := &"human.civilian.fear"
const STEP := &"movement.footstep.dirt.light"
const IDLE := &"zombie.ordinary.idle"
const ATTACK := &"zombie.ordinary.attack"
const HIT := &"combat.impact.flesh"

var _audio: AUDIO
var _mission
var _ambient
var _camera
var _alert
var _count := 0
var _failed := 0


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, label: String) -> void:
	_count += 1
	if value:
		print("PASS: ", label)
	else:
		_failed += 1
		push_error(label)


func started(event: StringName) -> int:
	return int(_audio.diagnostics().started.get(event, 0))


func target(layer: StringName) -> float:
	var gains: Vector2 = _audio.diagnostics().loops[layer]
	return gains.y


func move_camera(point: Vector2, zoom: float = 1.15) -> void:
	_camera.global_position = point
	_camera._set_zoom_level(zoom)
	_ambient._sample()


func add_mission() -> void:
	_mission = MISSION.instantiate()
	_mission.configure_progression(PROFILE.new("user://audio_foundation_progress.cfg"))
	root.add_child(_mission)
	_camera = _mission.get_node("Camera2D")
	_alert = _mission.get_node("VillageAlert")
	_ambient = _mission.mission_audio
	for actor in _mission.villagers:
		actor.set_physics_process(false)
		actor.threat_detection.set_physics_process(false)


func check_registry() -> int:
	check(REGISTRY.EVENTS.size() == 15, "15 semantic categories exist")
	var expected := 0
	var available := 0
	var unchanged := true
	var loops := 0
	var paths := {}
	for event in REGISTRY.EVENTS:
		var definition: Dictionary = REGISTRY.EVENTS[event]
		expected += int(definition.count)
		for variant in int(definition.count):
			paths[REGISTRY.path_for(definition, variant)] = true
			var stream: AudioStreamWAV = _audio._streams[event].get(variant)
			if stream == null:
				continue
			available += 1
			unchanged = unchanged and (stream.format == AudioStreamWAV.FORMAT_16_BITS
				and stream.mix_rate == 48000 and stream.stereo == (definition.bus == &"Ambience" and event != &"ambience.river.flow"))
			if definition.get("loop", false):
				loops += int(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and absf(stream.get_length() - 30.0) < 0.001)
	check(expected == 46 and paths.size() == expected, "46 unique canonical paths")
	check(available + _audio.diagnostics().missing.size() == expected, "Loaded and missing variations are accounted for")
	if "--require-pack" in OS.get_cmdline_user_args():
		check(available == 46, "Every supplied recording imports")
	if "--require-no-pack" in OS.get_cmdline_user_args():
		check(available == 0 and _audio.diagnostics().loops.is_empty()
			and is_instance_valid(_mission.mission_hud), "Mission loads with all 46 optional recordings missing")
	if available == 46:
		check(unchanged and loops == 6, "PCM16, 48 kHz, channel layout and all six 30-second loops are intact")
	return available


func check_settings() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("camera", "speed", 640.0)
	check(legacy.save(SETTINGS_FILE) == OK, "Test settings use an isolated file")
	var settings := SETTINGS.new()
	settings.load_settings(SETTINGS_FILE)
	check(settings.camera_speed == 640.0 and settings.audio_levels == SETTINGS.default_audio_levels(), "Legacy config receives default gains")
	settings.audio_levels[&"Master"] = 0.0
	settings.audio_levels[&"Combat"] = 0.5
	settings.audio_levels[&"Environment"] = 0.7
	settings.apply_audio()
	var master := AudioServer.get_bus_index(&"Master")
	var combat := AudioServer.get_bus_index(&"Combat")
	var environment := AudioServer.get_bus_index(&"Environment")
	check(AudioServer.is_bus_mute(master) and is_equal_approx(AudioServer.get_bus_volume_db(combat), -2.0 + linear_to_db(0.5)),
		"Master mutes and Combat uses linear gain over the nominal mix")
	check(is_equal_approx(AudioServer.get_bus_volume_db(environment), -4.0 + linear_to_db(0.7)), "Settings apply independently")
	check(settings.save_settings(SETTINGS_FILE) == OK, "Audio settings save")
	var loaded := SETTINGS.new()
	loaded.load_settings(SETTINGS_FILE)
	check(loaded.audio_levels == settings.audio_levels, "A new settings instance restores audio values")
	loaded.audio_levels = SETTINGS.default_audio_levels()
	loaded.apply_audio()
	check(not AudioServer.is_bus_mute(master) and is_equal_approx(AudioServer.get_bus_volume_db(combat), -2.0), "Defaults restore mixer")
	var app = MAIN.instantiate()
	root.add_child(app)
	app._open_settings(app.Screen.MAIN)
	app._select_settings_section(2)
	check(app.settings_audio_sliders.size() == 8, "Sound has eight visible settings controls")
	var old: float = app.settings.audio_levels[&"Master"]
	app.settings_audio_sliders[&"Master"].value = 0.0
	check(AudioServer.is_bus_mute(master), "A slider change previews immediately")
	app._reset_audio_settings()
	check(app.settings_audio_sliders[&"Master"].value == 1.0 and not AudioServer.is_bus_mute(master), "Sound reset previews defaults")
	app.settings_audio_sliders[&"Master"].value = 0.125
	app._show(app.Screen.MAIN)
	check(is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(maxf(old, 0.0001))), "Back restores the saved mix")
	app.free()


func check_ambience() -> void:
	check(_audio.diagnostics().loops.size() == 5 and started(WIND) == 1, "Five independent ambience layers start once")
	var river_player: Node = _audio._loops[&"river"].player
	move_camera(Vector2(1280.0, 1180.0))
	check(is_zero_approx(target(&"river")), "River falls silent across the map")
	move_camera(Vector2(2630.0, 1180.0), 2.0)
	check(target(&"river") > 0.85 and _audio._loops[&"river"].player == river_player,
		"Bridge area raises the same river loop")
	move_camera(Vector2(2630.0, 520.0), 2.0)
	check(target(&"river") > 0.85, "River remains audible upstream")
	move_camera(Vector2(420.0, 300.0), 2.0)
	var grove := target(&"forest")
	move_camera(Vector2(1500.0, 1050.0), 2.0)
	check(grove > target(&"forest"), "Grove zone increases forest detail")
	var first = _mission.get_node("Villagers/Peasant1")
	var second = _mission.get_node("Villagers/Peasant2")
	for actor in [first, second]:
		actor.autonomous_movement_enabled = true
		actor.global_position = Vector2(1500.0, 900.0)
		actor.current_activity = actor.Activity.SOCIAL
		actor.current_zone = _mission.get_node("ActivityZones/SocialSquare")
		actor.is_performing_activity = true
	second.global_position.x += 45.0
	_ambient._sample()
	var peace := target(&"village")
	check(peace > 0.0 and target(&"tension") == 0.0, "Peaceful nearby civilians drive village life")
	_ambient._chatter_due = 0.0
	var speakers: Array[Node2D] = [first]
	_ambient._update_conversations(speakers)
	check(started(CHATTER) == 0, "A lone civilian produces no conversation")
	_ambient._chatter_due = 0.0
	speakers.append(second)
	_ambient._update_conversations(speakers)
	check(started(CHATTER) == 1, "Two eligible civilians produce one conversation")
	second.autonomous_movement_enabled = false
	first.autonomous_movement_enabled = false
	_ambient._sample()
	check(_ambient._conversations.is_empty() and target(&"village") < peace, "Unavailable participants stop chatter and reduce village life")
	_alert.set_debug_level(_alert.Level.ORGANIZED_DEFENSE)
	_ambient._sample()
	check(is_equal_approx(target(&"tension"), 0.6) and started(WIND) == 1, "Alert changes tension without restarting the wind")
	check(not _alert.bell_audio.playing and _alert.bell_audio.bus == &"Alerts" and not _audio._loops.has(&"beacon"),
		"Debug alert starts neither bell nor physical beacon")
	_alert.set_debug_level(_alert.Level.NORMAL)


func check_developer_tools() -> void:
	var hud = _mission.mission_hud
	check(not hud.developer_button.visible and not hud.developer_audio_panel.visible, "Audio diagnostics are hidden in ordinary play")
	_mission.set_developer_mode(true)
	hud.developer_button.pressed.emit()
	for button in hud.developer_panel.find_children("*", "Button", true, false):
		if button.text == "Диагностика звука":
			button.pressed.emit()
			break
	check(hud.developer_audio_panel.is_visible_in_tree(), "Diagnostics open from the existing developer toolbar")
	var dog := &"environment.animal.dog"
	_audio.audition(dog, 2)
	check(started(dog) == 1 and _audio._last_variant[dog] == 2, "A specific reserved variation can be auditioned")
	var combat := AudioServer.get_bus_index(&"Combat")
	_audio.set_debug_mute(&"Combat", true)
	_audio.set_debug_solo(&"Combat")
	check(AudioServer.is_bus_mute(combat) and AudioServer.is_bus_solo(combat), "Developer mixing can mute and solo a channel")
	hud.close_audio_debug()
	check(not AudioServer.is_bus_mute(combat) and not AudioServer.is_bus_solo(combat), "Closing diagnostics restores the mix")
	_mission.set_developer_mode(false)


func check_spatial_and_actions() -> void:
	move_camera(Vector2(1500.0, 930.0))
	var listener := _audio.listener_position()
	check(listener.is_equal_approx(_camera.get_screen_center_position()), "Listener uses the effective camera center")
	var footstep: Dictionary = REGISTRY.EVENTS[STEP]
	var point := listener + Vector2(130.0, 0.0)
	var far := _audio._audibility(footstep, point)
	check(_audio._audibility(footstep, listener) > far, "Spatial selection attenuates distant sources")
	move_camera(Vector2(1500.0, 930.0), 2.0)
	check(_audio._audibility(footstep, point) > far, "Zoom favors detail at the same world distance")
	check(not _audio.play_at(HIT, listener + Vector2(690.0, 0.0)), "An inaudible hit is rejected")
	check(_mission.get_node("Ground").audio_surface(Vector2(1540.0, 950.0)) == &"dirt", "Square has a compatible dirt surface")
	check(_mission.get_node("Ground").audio_surface(Vector2(2740.0, 1180.0)) == &"wood", "Bridge deck takes precedence over roads and water")
	var civilian = _mission.get_node("Villagers/Peasant1")
	civilian.global_position = Vector2(1540.0, 950.0)
	civilian.velocity = Vector2.RIGHT * 50.0
	civilian._audio_step_distance = 17.0
	civilian._move_with_audio_steps()
	check(started(STEP) == 1, "Actual light locomotion on dirt dispatches a footstep")
	civilian.velocity = Vector2.ZERO
	civilian._move_with_audio_steps()
	check(started(STEP) == 1, "Standing still dispatches no step")

	var ordinary = spawn_zombie(civilian.global_position + Vector2(14.0, 0.0))
	var special = spawn_zombie(civilian.global_position + Vector2(0.0, 45.0))
	special.zombie_form = PROFILE.CARRIER
	_ambient._update_zombies(listener)
	check(_ambient._idle_due.has(ordinary.get_instance_id()) and not _ambient._idle_due.has(special.get_instance_id()),
		"Only ordinary zombies enter the idle schedule")
	_ambient._idle_due[ordinary.get_instance_id()] = 0.0
	_ambient._update_zombies(listener)
	check(started(IDLE) == 1, "A scheduled eligible ordinary zombie has an idle voice")

	civilian.autonomous_movement_enabled = true
	civilian.unit_vision.face(Vector2.RIGHT)
	civilian.threat_reaction.hesitation_probability = 1.0
	civilian.threat_reaction.recognize_threat(ordinary)
	civilian.threat_reaction.recognize_threat(ordinary)
	check(started(FEAR) == 1, "A real first-hand fear episode plays once")
	var contact: bool = civilian.begin_encounter(Color.WHITE, ordinary)
	ordinary.aggro_target = civilian
	ordinary.infection_chance = 0.0
	var health: float = civilian.current_health
	ordinary._on_encounter_attack_timer_timeout()
	check(contact and civilian.current_health < health and started(HIT) == 1, "An executed melee contact accounts for one real impact")
	civilian.receive_zombie_attack(2.0, 0.0, ordinary, true)
	check(started(HIT) == 1, "Splash damage does not duplicate the primary impact")
	var hits := started(HIT)
	ordinary.take_damage(1.0, Vector2.RIGHT)
	check(started(HIT) == hits, "Non-melee damage does not dispatch the flesh impact")
	var vocals := started(ATTACK)
	special.present_melee_execution(civilian.global_position)
	ordinary.play_attack_visual(civilian.global_position)
	check(started(ATTACK) == vocals, "Special-form attacks and presentation-only animations do not dispatch ordinary vocals")
	_audio._rng.seed = 55
	for index in 10:
		_audio._clock += 2.0
		ordinary.present_melee_execution(civilian.global_position)
	check(started(ATTACK) > vocals, "Executed ordinary melee can dispatch an attack voice")
	check(not _audio.play_attached(IDLE, ordinary), "Idle voice cannot overlap the same ordinary zombie's attack voice")
	ordinary.free()
	special.free()


func spawn_zombie(point: Vector2) -> Node2D:
	var zombie := ZOMBIE.instantiate() as Node2D
	zombie.position = point
	_mission.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.get_node("AggroArea").set_deferred("monitoring", false)
	return zombie


func check_budget_pause_and_lifecycle() -> void:
	var listener := _audio.listener_position()
	for index in 80:
		_audio.play_at(STEP, listener + Vector2.from_angle(index) * float(index * 2), index + 100)
	check(_audio.diagnostics().voices <= AUDIO.ONE_SHOTS + AUDIO.FADING_VOICES, "Burst playback stays within the voice budget")
	check(int(_audio.diagnostics().categories.get(&"Footsteps", 0)) <= 8 + AUDIO.FADING_VOICES, "Footstep event caps limit a mass burst")
	var last_variant: int = _audio._last_variant[HIT]
	check(_audio.play_at(HIT, listener) and _audio._last_variant[HIT] != last_variant,
		"A new important impact plays under load with a different recording")
	var last: Node = _mission.get_node("LastStand")
	var operator: Node2D = _mission.get_node("Villagers/Priest30")
	operator.interior_building = last.church
	last.operator = operator
	last.signal_remaining = 2.0
	last.signal_started_frame = -1
	last._update_signal(1.0)
	check(not _audio._loops.has(&"beacon"), "An unfinished beacon is silent")
	last._update_signal(1.0)
	check(_audio._loops.has(&"beacon") and last.beacon_lit, "Completed physical ignition starts the fire")
	var fire_player: Node = _audio._loops[&"beacon"].player
	var wind_player: Node = _audio._loops[&"wind"].player
	_mission.toggle_tactical_pause()
	check(paused and not fire_player.can_process() and wind_player.can_process(),
		"Tactical pause blocks even a positional sound requested just before the pause")
	var old_clock: float = _ambient._game_clock
	var old_hits := started(HIT)
	check(not _audio.play_at(HIT, listener), "Paused simulation rejects new gameplay sounds")
	for index in 4:
		await process_frame
	check(_ambient._game_clock == old_clock and started(HIT) == old_hits, "Pause accumulates no gameplay work")
	_mission.toggle_tactical_pause()
	check(not paused and fire_player.can_process() and started(HIT) == old_hits, "Resume produces no backlog")
	await physics_frame
	await physics_frame
	_mission.toggle_tactical_pause()
	check(fire_player.stream_paused and not wind_player.stream_paused, "Native tactical pause freezes the active physical stream")
	_mission.toggle_tactical_pause()
	last.beacon_fire.free()
	for index in 3:
		await process_frame
	check(not _audio._loops.has(&"beacon"), "Removing the fire source stops its loop")
	_mission.free()
	check(_audio.diagnostics().loops.is_empty() and _audio.diagnostics().voices == 0, "Mission exit releases all playback")
	add_mission()
	check(_audio.diagnostics().loops.size() == 5 and started(WIND) == 1, "Restart opens a fresh set of loops")
	_mission.mission_state = _mission.MissionState.WON
	check(_audio.diagnostics().loops.size() == 5 and _mission.is_gameplay_active(), "Completing the objective preserves ambience while play continues")
	_mission.finish_mission()
	check(_audio.diagnostics().loops.is_empty(), "Ending the mission stops ambience on the result screen")


func run() -> void:
	_audio = AUDIO.service() as AUDIO
	check_settings()
	add_mission()
	for index in 5:
		await process_frame
	var available := check_registry()
	if available == 46:
		check_ambience()
		check_developer_tools()
		check_spatial_and_actions()
		await check_budget_pause_and_lifecycle()
	_mission.free()
	var backup: Dictionary = _audio._streams[WIND]
	_audio._streams[WIND] = {}
	add_mission()
	check(not _audio._loops.has(&"wind") and is_instance_valid(_mission.mission_hud),
		"The mission initializes with an unavailable wind recording")
	_audio._streams[WIND] = backup
	_mission.free()
	print("Audio foundation: %d/%d" % [_count - _failed, _count])
	quit(1 if _failed else 0)

