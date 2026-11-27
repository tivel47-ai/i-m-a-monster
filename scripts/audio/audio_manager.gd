extends Node
## Shared mixer and bounded playback. The mission owns the lifetime of its audio session.

const REGISTRY = preload("res://scripts/audio/audio_registry.gd")
const ONE_SHOTS := 20
const RESERVED_IMPORTANT := 4
const FADING_VOICES := 2
const LOOP_LIMIT := 8
const IMPORTANT_PRIORITY := 50
const BUS_LIMITS := {&"Environment": 5, &"HumanVoices": 5, &"MonsterVoices": 6}


class Voice:
	var player
	var event: StringName
	var source: int
	var priority: int
	var age := 0.0
	var position := Vector2.INF
	var following: WeakRef
	var interior: WeakRef
	var base_db := 0.0
	var gain := 0.0
	var target := 0.0
	var fade := 0.0
	var retiring := false
	var stop_when_silent := false
	var preview := false

	var active: bool:
		get: return not event.is_empty()


var _owner: WeakRef
var _camera: WeakRef
var _streams: Dictionary = {}
var _voices: Array[Voice] = []
var _loops: Dictionary = {}
var _last_variant: Dictionary = {}
var _event_until: Dictionary = {}
var _source_until: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _prune_at := 0.0
var _paused := false
var _last_played: StringName
var _last_rejection := ""
var _rejected: Dictionary = {}
var _started: Dictionary = {}
var _missing: PackedStringArray = []
var _unknown: PackedStringArray = []
var _preview_bus_mutes: Dictionary = {}
var _solo_bus: StringName
var _nominal_bus_db: Dictionary = {}


static func service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioManager") if tree != null else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for index in AudioServer.bus_count:
		_nominal_bus_db[AudioServer.get_bus_name(index)] = AudioServer.get_bus_volume_db(index)
	set_process(false)


func set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	var muted := is_zero_approx(linear)
	AudioServer.set_bus_volume_db(index, float(_nominal_bus_db.get(bus, 0.0)) + linear_to_db(maxf(linear, 0.0001)))
	if _preview_bus_mutes.has(bus):
		_preview_bus_mutes[bus] = muted
	else:
		AudioServer.set_bus_mute(index, muted)


func begin_mission(owner: Node, camera: Camera2D) -> void:
	stop_mission_audio()
	_owner = weakref(owner)
	_camera = weakref(camera)
	owner.tree_exiting.connect(_mission_exiting.bind(owner.get_instance_id()), CONNECT_ONE_SHOT)
	_load_registry()
	set_process(true)


func _mission_exiting(id: int) -> void:
	var owner: Node = _owner.get_ref() if _owner != null else null
	if owner != null and owner.get_instance_id() == id:
		stop_mission_audio()


func stop_mission_audio() -> void:
	for voice in _voices:
		voice.player.stop()
		voice.player.queue_free()
	for voice: Voice in _loops.values():
		voice.player.stop()
		voice.player.queue_free()
	_voices.clear()
	_loops.clear()
	_event_until.clear()
	_source_until.clear()
	_last_variant.clear()
	_rejected.clear()
	_started.clear()
	_unknown.clear()
	_last_played = &""
	_last_rejection = ""
	_owner = null
	_camera = null
	_clock = 0.0
	_prune_at = 0.0
	_paused = false
	clear_debug_mix()
	set_process(false)


func owns(node: Node) -> bool:
	var owner: Node = _owner.get_ref() if _owner != null else null
	return is_instance_valid(owner) and owner.is_ancestor_of(node)


func listener_position() -> Vector2:
	var camera: Camera2D = _camera.get_ref() if _camera != null else null
	return camera.get_screen_center_position() if is_instance_valid(camera) else Vector2.INF


func listener_zoom() -> float:
	var camera: Camera2D = _camera.get_ref() if _camera != null else null
	return camera.zoom.x if is_instance_valid(camera) else 1.0


func _zoom_detail() -> float:
	var camera = _camera.get_ref() if _camera != null else null
	return camera.zoom_fraction() if is_instance_valid(camera) and camera.has_method("zoom_fraction") else 1.0


func _load_registry() -> void:
	if not _streams.is_empty():
		return
	for id in REGISTRY.EVENTS:
		var definition: Dictionary = REGISTRY.EVENTS[id]
		var variants: Dictionary = {}
		for index in int(definition.count):
			var path := REGISTRY.path_for(definition, index)
			if not ResourceLoader.exists(path, "AudioStream"):
				_missing.append(path)
				continue
			var stream := load(path) as AudioStream
			if stream == null:
				_missing.append(path)
				continue
			if definition.get("loop", false):
				stream = _configure_loop(stream)
			variants[index] = stream
		_streams[id] = variants


func _configure_loop(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav := stream.duplicate() as AudioStreamWAV
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return wav
	if (stream is AudioStreamOggVorbis or stream is AudioStreamMP3) and not stream.loop:
		var repeated = stream.duplicate()
		repeated.loop = true
		return repeated
	return stream


func has_recordings(event: StringName) -> bool:
	return not _streams.get(event, {}).is_empty()


func random_interval(event: StringName) -> float:
	var interval: Vector2 = REGISTRY.EVENTS[event].interval
	return _rng.randf_range(interval.x, interval.y)


func play_global(event: StringName) -> bool:
	return _play(event, Vector2.INF, 0, null, null)


func play_at(event: StringName, position: Vector2, source := 0, interior: Node2D = null) -> bool:
	return _play(event, position, source, null, interior)


func play_attached(event: StringName, actor: Node2D, interior: Node2D = null) -> bool:
	if not owns(actor):
		return false
	return _play(event, actor.global_position, actor.get_instance_id(), actor, interior)


func _reject(event: StringName, reason: String) -> bool:
	_rejected[reason] = int(_rejected.get(reason, 0)) + 1
	_last_rejection = "%s · %s" % [reason, event]
	return false


func _play(event: StringName, position: Vector2, source: int, following: Node2D,
		interior: Node2D, variant := -1, preview := false) -> bool:
	if _owner == null or (_paused and not preview):
		return false
	if not REGISTRY.EVENTS.has(event):
		if _unknown.size() < 20 and not _unknown.has(event):
			_unknown.append(event)
		return _reject(event, "Неизвестное событие")
	var definition: Dictionary = REGISTRY.EVENTS[event]
	if definition.get("loop", false):
		return _reject(event, "Ожидался короткий звук")
	if not has_recordings(event):
		return _reject(event, "Нет записей")
	var spatial := position.is_finite()
	var score := _audibility(definition, position)
	if spatial and score <= 0.0:
		return _reject(event, "Вне зоны слышимости")

	var source_deadlines: Dictionary = _source_until.get(event, {})
	if not preview and (float(_event_until.get(event, 0.0)) > _clock or
		(source != 0 and float(source_deadlines.get(source, 0.0)) > _clock)):
		return _reject(event, "Интервал повтора")
	if not preview and definition.has("probability") and _rng.randf() >= float(definition.probability):
		return _reject(event, "Вероятность")
	var priority := int(definition.priority) + (100 if preview else 0)
	var previous: Voice
	if not preview and source != 0 and definition.has("source_group"):
		previous = _source_voice(source, definition.source_group)
		if previous != null and previous.priority >= priority:
			return _reject(event, "Источник уже звучит")

	var chosen := _select_variant(event, variant)
	if chosen == -1:
		return _reject(event, "Вариант отсутствует")
	var slot := _reserve_voice(event, definition, priority, score, spatial)
	if slot == null:
		return _reject(event, "Лимит голосов")
	if previous != null:
		_retire(previous)

	_start_voice(slot, event, chosen, position, following, interior, preview)
	slot.source = source
	slot.priority = priority
	slot.age = 0.0
	slot.gain = 1.0
	slot.player.volume_db = _voice_db(slot, definition)
	var offsets: Array = definition.get("offsets", [])
	slot.player.play(float(offsets[chosen]) if chosen < offsets.size() else 0.0)
	_last_played = event
	_started[event] = int(_started.get(event, 0)) + 1
	_last_variant[event] = chosen
	if not preview:
		if definition.has("cooldown"):
			_event_until[event] = _clock + float(definition.cooldown)
		if source != 0 and definition.has("source_cooldown"):
			source_deadlines[source] = _clock + float(definition.source_cooldown)
			_source_until[event] = source_deadlines
	return true


func _source_voice(source: int, group: StringName) -> Voice:
	for voice in _voices:
		if voice.active and voice.source == source and not voice.retiring \
			and REGISTRY.EVENTS[voice.event].get("source_group", &"") == group:
			return voice
	return null


func _select_variant(event: StringName, forced: int) -> int:
	var variants: Dictionary = _streams.get(event, {})
	if forced >= 0:
		return forced if variants.has(forced) else -1
	var choices := variants.keys()
	if choices.size() > 1:
		choices.erase(_last_variant.get(event, -1))
	return int(choices[_rng.randi_range(0, choices.size() - 1)]) if not choices.is_empty() else -1


func _audibility(definition: Dictionary, position: Vector2) -> float:
	if not position.is_finite():
		return 1.0
	var distance := listener_position().distance_to(position)
	var remaining := clampf(1.0 - distance / float(definition.get("distance", 800.0)), 0.0, 1.0)
	return pow(remaining, float(definition.get("attenuation", 1.35))) * db_to_linear(
		lerpf(float(definition.get("detail", 0.0)), 0.0, _zoom_detail()))


func _reserve_voice(event: StringName, definition: Dictionary, priority: int,
		score: float, spatial: bool) -> Voice:
	var active := 0
	var bus_count := 0
	var event_count := 0
	var fading := 0
	var idle: Voice
	for voice in _voices:
		if not voice.active:
			if idle == null or (voice.player is AudioStreamPlayer2D) == spatial:
				idle = voice
			continue
		if voice.retiring:
			fading += 1
			continue
		active += 1
		if voice.player.bus == definition.bus:
			bus_count += 1
		if voice.event == event:
			event_count += 1
	var event_full := event_count >= int(definition.limit)
	var bus_full := bus_count >= int(BUS_LIMITS.get(definition.bus, ONE_SHOTS))
	var global_full := active >= ONE_SHOTS
	if priority < IMPORTANT_PRIORITY and active >= ONE_SHOTS - RESERVED_IMPORTANT and not event_full and not bus_full:
		return null
	if event_full or bus_full or global_full:
		if fading >= FADING_VOICES:
			return null
		var weakest: Voice
		var weakest_score := priority + 24.0 * score
		for voice in _voices:
			if not voice.active or voice.retiring or (event_full and voice.event != event) 				or (bus_full and voice.player.bus != definition.bus):
				continue
			var rank := voice.priority + 24.0 * _audibility(REGISTRY.EVENTS[voice.event], voice.position) - minf(voice.age, 3.0)
			if rank < weakest_score:
				weakest_score = rank
				weakest = voice
		if weakest == null:
			return null
		weakest.retiring = true
	if idle == null:
		idle = Voice.new()
		_voices.append(idle)
	_ensure_player(idle, spatial)
	return idle


func _ensure_player(voice: Voice, spatial: bool) -> void:
	if voice.player != null and (voice.player is AudioStreamPlayer2D) == spatial:
		return
	if voice.player != null:
		voice.player.queue_free()
	voice.player = AudioStreamPlayer2D.new() if spatial else AudioStreamPlayer.new()
	add_child(voice.player)


func _start_voice(voice: Voice, event: StringName, variant: int, position: Vector2,
		following: Node2D, interior: Node2D, preview: bool) -> void:
	var definition: Dictionary = REGISTRY.EVENTS[event]
	voice.event = event
	voice.position = position
	voice.following = weakref(following) if is_instance_valid(following) else null
	voice.interior = weakref(interior) if is_instance_valid(interior) else null
	voice.retiring = false
	voice.stop_when_silent = false
	voice.preview = preview
	# Pausable players follow the tree even when a 2D start is pending until its first physics tick.
	voice.player.process_mode = Node.PROCESS_MODE_ALWAYS if _runs_during_pause(voice) else Node.PROCESS_MODE_PAUSABLE
	voice.player.stream = _streams[event][variant]
	voice.player.bus = definition.bus
	voice.base_db = float(definition.db)
	voice.player.pitch_scale = 1.0
	if not definition.get("loop", false):
		var pitch: Vector2 = definition.get("pitch", Vector2(0.96, 1.04))
		voice.player.pitch_scale = _rng.randf_range(pitch.x, pitch.y)
		voice.base_db += _rng.randf_range(-1.5, 1.5)
	if voice.player is AudioStreamPlayer2D:
		voice.player.global_position = position
		voice.player.max_distance = float(definition.get("distance", 800.0))
		voice.player.attenuation = float(definition.get("attenuation", 1.35))
		voice.player.panning_strength = float(definition.get("pan", 0.8))
		voice.player.area_mask = 0


func start_loop(event: StringName, key: StringName, position := Vector2.INF,
		source: Node2D = null, preview := false, variant := -1) -> bool:
	if _owner == null or _loops.has(key):
		return false
	if _loops.size() >= LOOP_LIMIT:
		return _reject(event, "Лимит петель")
	if not REGISTRY.EVENTS.has(event) or not REGISTRY.EVENTS[event].get("loop", false):
		return _reject(event, "Ожидалась петля")
	if _paused and not preview and not REGISTRY.EVENTS[event].get("background", false):
		return false
	var selected := _select_variant(event, variant)
	if selected < 0:
		return _reject(event, "Нет записи петли")
	var voice := Voice.new()
	if source != null:
		if not owns(source):
			return false
		position = source.global_position
	_ensure_player(voice, position.is_finite())
	_start_voice(voice, event, selected, position, source, null, preview)
	voice.fade = float(REGISTRY.EVENTS[event].fade)
	voice.player.volume_db = -80.0
	voice.player.play()
	_loops[key] = voice
	_last_played = event
	_started[event] = int(_started.get(event, 0)) + 1
	return true


func set_loop_target(key: StringName, gain: float, position := Vector2.INF) -> void:
	var voice: Voice = _loops.get(key)
	if voice != null:
		voice.target = clampf(gain, 0.0, 1.0)
		if position.is_finite() and voice.player is AudioStreamPlayer2D:
			voice.position = position
			voice.player.global_position = position


func stop_loop(key: StringName, fade_seconds := 0.25) -> void:
	var voice: Voice = _loops.get(key)
	if voice == null:
		return
	if fade_seconds <= 0.0:
		_release_loop(key, voice)
	else:
		voice.target = 0.0
		voice.fade = fade_seconds / 4.0
		voice.stop_when_silent = true


func _release_loop(key: StringName, voice: Voice) -> void:
	voice.player.stop()
	voice.player.queue_free()
	_loops.erase(key)


func stop_source_event(event: StringName, source: int) -> void:
	for voice in _voices:
		if voice.event == event and voice.source == source:
			_retire(voice)


func _retire(voice: Voice) -> void:
	if voice.retiring:
		return
	var count := 0
	for other in _voices:
		if other.retiring:
			count += 1
	if count >= FADING_VOICES:
		_release(voice)
	else:
		voice.retiring = true


func _release(voice: Voice) -> void:
	voice.player.stop()
	voice.player.stream = null
	voice.event = &""
	voice.following = null
	voice.interior = null
	voice.retiring = false
	voice.preview = false


func _runs_during_pause(voice: Voice) -> bool:
	return voice.preview or REGISTRY.EVENTS[voice.event].get("background", false)


func set_simulation_paused(paused: bool) -> void:
	_paused = paused


func _voice_db(voice: Voice, definition: Dictionary) -> float:
	var detail := lerpf(float(definition.get("detail", 0.0)), 0.0, _zoom_detail()) if voice.position.is_finite() else 0.0
	var interior_db := 0.0
	if voice.interior != null:
		var building = voice.interior.get_ref()
		if is_instance_valid(building) and building.has_method("audio_is_exposed"):
			interior_db = 0.0 if building.audio_is_exposed(listener_position()) else -8.0
	return voice.base_db + detail + interior_db + linear_to_db(maxf(voice.gain, 0.0001))


func _update_attached(voice: Voice) -> bool:
	if voice.following == null:
		return true
	var source: Node2D = voice.following.get_ref()
	if not is_instance_valid(source) or not owns(source) or source.is_queued_for_deletion():
		return false
	voice.position = source.global_position
	voice.player.global_position = voice.position
	return true


func _process(delta: float) -> void:
	if not _paused:
		_clock += delta
		if _clock >= _prune_at:
			_prune_at = _clock + 5.0
			for deadlines: Dictionary in _source_until.values():
				for source in deadlines.keys():
					if deadlines[source] <= _clock:
						deadlines.erase(source)
	for voice in _voices:
		if not voice.active:
			continue
		if not voice.player.playing:
			_release(voice)
			continue
		if not _update_attached(voice):
			_retire(voice)
			if not voice.active:
				continue
		elif voice.following != null:
			var actor = voice.following.get_ref()
			if actor.has_method("is_alive") and not actor.is_alive():
				_retire(voice)
				if not voice.active:
					continue
		if _paused and not _runs_during_pause(voice):
			if voice.retiring:
				_release(voice)
			continue
		voice.age += delta
		if voice.retiring:
			voice.gain = move_toward(voice.gain, 0.0, delta / 0.045)
			if voice.gain <= 0.0:
				_release(voice)
				continue
		voice.player.volume_db = _voice_db(voice, REGISTRY.EVENTS[voice.event])
	for key in _loops.keys():
		var voice: Voice = _loops[key]
		if not _update_attached(voice):
			_release_loop(key, voice)
			continue
		if _paused and not _runs_during_pause(voice):
			continue
		voice.gain = lerpf(voice.gain, voice.target, 1.0 - exp(-delta / maxf(0.001, voice.fade)))
		if voice.stop_when_silent and voice.gain < 0.001:
			_release_loop(key, voice)
			continue
		voice.player.volume_db = _voice_db(voice, REGISTRY.EVENTS[voice.event])


func audition(event: StringName, variant: int) -> void:
	var definition: Dictionary = REGISTRY.EVENTS[event]
	if not definition.get("loop", false):
		_play(event, Vector2.INF, 0, null, null, variant, true)
		return
	var preview_id := &"developer_preview"
	stop_loop(preview_id, 0.0)
	if start_loop(event, preview_id, Vector2.INF, null, true, variant):
		set_loop_target(preview_id, 1.0)
		var preview: Voice = _loops[preview_id]
		preview.fade = 0.15
		get_tree().create_timer(3.0).timeout.connect(func():
			if _loops.get(preview_id) == preview:
				stop_loop(preview_id))


func stop_audition() -> void:
	stop_loop(&"developer_preview", 0.0)
	for voice in _voices:
		if voice.active and voice.preview:
			_retire(voice)


func set_debug_mute(bus: StringName, enabled: bool) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	if enabled and not _preview_bus_mutes.has(bus):
		_preview_bus_mutes[bus] = AudioServer.is_bus_mute(index)
		AudioServer.set_bus_mute(index, true)
	elif not enabled and _preview_bus_mutes.has(bus):
		AudioServer.set_bus_mute(index, _preview_bus_mutes[bus])
		_preview_bus_mutes.erase(bus)


func set_debug_solo(bus: StringName) -> void:
	if not _solo_bus.is_empty():
		AudioServer.set_bus_solo(AudioServer.get_bus_index(_solo_bus), false)
	_solo_bus = bus
	if not _solo_bus.is_empty():
		AudioServer.set_bus_solo(AudioServer.get_bus_index(_solo_bus), true)


func clear_debug_mix() -> void:
	for bus in _preview_bus_mutes.keys():
		set_debug_mute(bus, false)
	set_debug_solo(&"")


func diagnostics() -> Dictionary:
	var categories := {}
	var voices := 0
	for voice in _voices:
		if voice.active:
			voices += 1
			categories[voice.player.bus] = int(categories.get(voice.player.bus, 0)) + 1
	var loops := {}
	for key in _loops:
		var loop: Voice = _loops[key]
		loops[key] = Vector2(loop.gain, loop.target)
		categories[loop.player.bus] = int(categories.get(loop.player.bus, 0)) + 1
	return {"voices": voices, "categories": categories, "loops": loops, "missing": _missing.duplicate(),
		"unknown": _unknown.duplicate(), "last": _last_played, "rejection": _last_rejection,
		"rejected": _rejected.duplicate(), "started": _started.duplicate()}


func active_source_positions() -> PackedVector2Array:
	var positions := PackedVector2Array()
	for voice in _voices:
		if voice.active and voice.position.is_finite():
			positions.append(voice.position)
	return positions

