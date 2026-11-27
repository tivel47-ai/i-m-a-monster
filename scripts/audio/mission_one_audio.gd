extends Node2D
## Audio-only projection of the authored village and its current simulation.

const AUDIO = preload("res://scripts/audio/audio_manager.gd")

const REGISTRY = preload("res://scripts/audio/audio_registry.gd")
const WIND := &"ambience.wind.base"
const VILLAGE := &"ambience.village.distant"
const RIVER := &"ambience.river.flow"
const FOREST := &"ambience.forest.vegetation"
const TENSION := &"ambience.tension.dark"
const CROW := &"environment.animal.crow"
const BIRDS := &"environment.animal.birds"
const FIRE := &"environment.fire.loop"
const CHATTER := &"human.civilian.chatter"
const IDLE := &"zombie.ordinary.idle"
const PEACE := [1.0, 0.85, 0.40, 0.15, 0.05]
const DANGER := [0.0, 0.10, 0.35, 0.60, 0.80]
const SAMPLE_SECONDS := 0.20
const RIVER_RADIUS := 620.0
const FOREST_RADIUS := 360.0
const PEACE_RADIUS := 840.0
const FIRE_KEY := &"beacon"

@onready var _audio := AUDIO.service() as AUDIO

var _mission: Node2D
var _alert: Node
var _beacon: Node2D
var _river := PackedVector2Array()
var _groves := PackedVector2Array()
var _emitters: Array[Dictionary] = []
var _idle_due: Dictionary = {}
var _conversations: Array[Dictionary] = []
var _initial_civilians := 0
var _chatter_due := 0.0
var _game_clock := 0.0
var _sample_in := 0.0
var _active := false
var _draw_sources := false
var _river_source := Vector2.INF
var _forest_source := Vector2.INF
var _combat: Array[Vector2] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 102
	set_process(false)


func initialize(mission: Node2D) -> void:
	_mission = mission
	var camera := mission.get_node("Camera2D") as Camera2D
	_alert = mission.get_node("VillageAlert")
	_alert.level_changed.connect(_on_alert_level_changed)
	if is_instance_valid(_alert.bell_audio):
		_alert.bell_audio.bus = &"Alerts"
	_audio.begin_mission(mission, camera)
	_river = mission.get_node("Ground").audio_river_geometry()
	_collect_groves(mission.get_node("NavigationRegion2D/Trees"))
	var points := mission.get_node("VillagePointsOfInterest")
	for name_of_point in [&"Cemetery", &"Church"]:
		_add_emitter(CROW, points.get_node(NodePath(name_of_point)).global_position)
	for name_of_point in [&"Garden0Access", &"Garden3Access", &"FieldsWest"]:
		_add_emitter(BIRDS, points.get_node(NodePath(name_of_point)).global_position)
	for index in _groves.size():
		if index % 2 == 0:
			_add_emitter(BIRDS, _groves[index])
	_initial_civilians = mission.villagers.filter(_is_civilian).size()
	_chatter_due = _audio.random_interval(CHATTER) * 0.6
	_start_layer(WIND, &"wind")
	_start_layer(VILLAGE, &"village")
	if not _river.is_empty():
		_start_layer(RIVER, &"river", _river[0])
	_start_layer(FOREST, &"forest")
	_start_layer(TENSION, &"tension")
	var last_stand := mission.get_node_or_null("LastStand")
	if last_stand != null:
		last_stand.beacon_ignited.connect(_start_beacon)
	_active = true
	_sample()
	set_process(true)


func shutdown() -> void:
	if not _active:
		return
	_active = false
	_emitters.clear()
	_idle_due.clear()
	_conversations.clear()
	_beacon = null
	_audio.stop_mission_audio()
	set_process(false)


func _start_layer(event: StringName, key: StringName, position := Vector2.INF) -> void:
	if _audio.has_recordings(event):
		_audio.start_loop(event, key, position)


func _collect_groves(trees: Node) -> void:
	var clusters: Dictionary = {}
	for tree in trees.get_children():
		var node_name := String(tree.name)
		if not tree is Node2D or not node_name.begins_with("Grove") or not node_name.contains("Tree"):
			continue
		var group := node_name.get_slice("Tree", 0)
		var positions: Array = clusters.get(group, [])
		positions.append(tree.global_position)
		clusters[group] = positions
	for positions: Array in clusters.values():
		var center := Vector2.ZERO
		for point: Vector2 in positions:
			center += point
		_groves.append(center / positions.size())


func _add_emitter(event: StringName, position: Vector2) -> void:
	if _audio.has_recordings(event):
		_emitters.append({"event": event, "point": position,
			"due": _audio.random_interval(event), "source": -1 - _emitters.size()})


func _start_beacon(source: Node2D) -> void:
	if is_instance_valid(source) and _audio.has_recordings(FIRE):
		_beacon = source
		if _audio.start_loop(FIRE, FIRE_KEY, Vector2.INF, source):
			_audio.set_loop_target(FIRE_KEY, 1.0)


func _on_alert_level_changed(_previous: int, _current: int) -> void:
	_sample_in = 0.0


func _process(delta: float) -> void:
	if _mission.process_mode == Node.PROCESS_MODE_DISABLED:
		shutdown()
		return
	_audio.set_simulation_paused(get_tree().paused)
	_sample_in -= delta
	if not get_tree().paused:
		_game_clock += delta
	if _sample_in <= 0.0:
		_sample_in = SAMPLE_SECONDS
		_sample()
	if _draw_sources:
		queue_redraw()


func _sample() -> void:
	var listener := _audio.listener_position()
	if not listener.is_finite():
		return
	var is_paused := get_tree().paused
	var calm: Array[Node2D] = []
	var social: Array[Node2D] = []
	_combat.clear()
	var nearby_activity := 0.0
	for actor in _mission.villagers:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_alive():
			continue
		if not actor.encounter_participants.is_empty() and (actor.interior_building == null
			or actor.interior_building.audio_is_exposed(listener)):
			_combat.append(actor.global_position)
		if not _is_peaceful(actor):
			continue
		calm.append(actor)
		nearby_activity += _falloff(listener.distance_to(actor.global_position), PEACE_RADIUS)
		if not is_paused and _is_social(actor):
			social.append(actor)

	var level := clampi(_alert.level, 0, DANGER.size() - 1)
	var density := minf(nearby_activity / 7.0, 1.0)
	var population := minf(calm.size() / maxf(float(_initial_civilians) * 0.65, 1.0), 1.0)
	_audio.set_loop_target(&"wind", 0.62 if is_paused else 1.0)
	_audio.set_loop_target(&"village", 0.0 if is_paused else density * population * PEACE[level])
	_audio.set_loop_target(&"tension", DANGER[level] * (0.6 if is_paused else 1.0))
	_river_source = _closest_river_point(listener)
	_audio.set_loop_target(&"river",
		_falloff(listener.distance_to(_river_source), RIVER_RADIUS) * (0.7 if is_paused else 1.0), _river_source)
	_forest_source = _nearest_grove(listener)
	var forest_distance := listener.distance_to(_forest_source)
	var bounds: Rect2 = _mission.get_node("Camera2D").map_bounds
	var border := minf(minf(listener.x - bounds.position.x, bounds.end.x - listener.x),
		minf(listener.y - bounds.position.y, bounds.end.y - listener.y))
	var forest := maxf(_falloff(forest_distance, FOREST_RADIUS), 0.65 * _falloff(border, 320.0))
	_audio.set_loop_target(&"forest", forest * (0.7 if is_paused else 1.0))

	if not is_paused:
		_update_environment()
		_update_conversations(social)
		_update_zombies(listener)


func _falloff(distance: float, radius: float) -> float:
	return 1.0 - smoothstep(0.0, radius, distance)


func _closest_river_point(listener: Vector2) -> Vector2:
	if Geometry2D.is_point_in_polygon(listener, _river):
		return listener
	var closest := Vector2.INF
	var distance := INF
	for index in _river.size():
		var point := Geometry2D.get_closest_point_to_segment(listener, _river[index], _river[(index + 1) % _river.size()])
		var squared := listener.distance_squared_to(point)
		if squared < distance:
			closest = point
			distance = squared
	return closest


func _nearest_grove(listener: Vector2) -> Vector2:
	var nearest := Vector2.INF
	var distance := INF
	for point in _groves:
		var squared := listener.distance_squared_to(point)
		if squared < distance:
			nearest = point
			distance = squared
	return nearest


func _update_environment() -> void:
	for emitter in _emitters:
		var suppressed: bool = emitter.event == BIRDS and _near_combat(emitter.point, 230.0)
		if suppressed:
			_audio.stop_source_event(emitter.event, emitter.source)
		if _game_clock < float(emitter.due):
			continue
		emitter.due = _game_clock + _audio.random_interval(emitter.event)
		if not suppressed:
			_audio.play_at(emitter.event, emitter.point, emitter.source)


func _near_combat(point: Vector2, radius: float) -> bool:
	for contact in _combat:
		if contact.distance_squared_to(point) < radius * radius:
			return true
	return false


func _is_civilian(actor: Node) -> bool:
	return is_instance_valid(actor) and actor.get_meta("village_role", &"peasant") in [&"peasant", &"artisan"]


func _is_peaceful(actor: Node2D) -> bool:
	return (_is_civilian(actor) and actor.autonomous_movement_enabled and actor.is_available_for_infection()
		and not is_instance_valid(actor.interior_building) and not is_instance_valid(actor.building_task)
		and not actor.has_tactical_controller() and not actor.threat_reaction.episode_active
		and not actor.threat_reaction.seeking_home and actor.get_recognized_threat() == null
		and actor.current_activity != actor.Activity.NONE)


func _is_social(actor: Node2D) -> bool:
	return actor.current_activity == actor.Activity.SOCIAL and is_instance_valid(actor.current_zone)


func _update_conversations(social: Array[Node2D]) -> void:
	var occupied := {}
	for index in range(_conversations.size() - 1, -1, -1):
		var clip := _conversations[index]
		var first: Node2D = clip.first.get_ref()
		var second: Node2D = clip.second.get_ref()
		if _game_clock >= float(clip.end):
			_conversations.remove_at(index)
		elif (not social.has(first) or not social.has(second) or first.current_zone != second.current_zone
			or first.global_position.distance_squared_to(second.global_position) > 100.0 * 100.0):
			_audio.stop_source_event(CHATTER, clip.source)
			_conversations.remove_at(index)
		else:
			occupied[first] = true
			occupied[second] = true
	if _game_clock < _chatter_due or not _audio.has_recordings(CHATTER):
		return
	_chatter_due = _game_clock + 2.0
	var listener := _audio.listener_position()
	for first in social:
		if (occupied.has(first) or first.global_position.distance_squared_to(listener) >= 380.0 * 380.0
			or _near_combat(first.global_position, 120.0)):
			continue
		for second in social:
			if (second == first or occupied.has(second) or second.current_zone != first.current_zone
				or first.global_position.distance_squared_to(second.global_position) > 80.0 * 80.0
				or not (first.is_performing_activity or second.is_performing_activity)):
				continue
			if _audio.play_attached(CHATTER, first):
				_conversations.append({"first": weakref(first), "second": weakref(second),
					"source": first.get_instance_id(), "end": _game_clock + 8.0})
				_chatter_due = _game_clock + _audio.random_interval(CHATTER)
			return


func _update_zombies(listener: Vector2) -> void:
	if not _audio.has_recordings(IDLE):
		return
	var seen := {}
	for unit in get_tree().get_nodes_in_group("player_units"):
		if (not unit.has_method("play_attack_visual") or not _mission.is_ancestor_of(unit)
			or not unit.is_alive() or unit.is_brute or not unit.zombie_form.is_empty()
			or listener.distance_squared_to(unit.global_position) >= 360.0 * 360.0):
			continue
		var id := unit.get_instance_id()
		seen[id] = true
		if not _idle_due.has(id):
			_idle_due[id] = _game_clock + _audio.random_interval(IDLE)
			continue
		if _game_clock >= float(_idle_due[id]):
			_idle_due[id] = _game_clock + _audio.random_interval(IDLE)
			if not is_instance_valid(unit.aggro_target):
				_audio.play_attached(IDLE, unit, unit.interior_building)
	for id in _idle_due.keys():
		if not seen.has(id):
			_idle_due.erase(id)


func set_debug_sources(enabled: bool) -> void:
	_draw_sources = enabled
	queue_redraw()


func _draw() -> void:
	if not _draw_sources:
		return
	var listener := _audio.listener_position()
	if listener.is_finite():
		draw_circle(to_local(listener), 12.0, Color("#ffe6ba"))
	if _river_source.is_finite():
		draw_arc(to_local(_river_source), RIVER_RADIUS, 0.0, TAU, 64, Color("#7aaed499"), 2.0, true)
	if _forest_source.is_finite():
		draw_arc(to_local(_forest_source), FOREST_RADIUS, 0.0, TAU, 64, Color("#8cba7599"), 2.0, true)
	for emitter in _emitters:
		_draw_emitter(emitter.event, emitter.point)
	if is_instance_valid(_beacon):
		_draw_emitter(FIRE, _beacon.global_position)
	for point in _audio.active_source_positions():
		draw_circle(to_local(point), 4.0, Color("#fff2bf"))


func _draw_emitter(event: StringName, point: Vector2) -> void:
	var local := to_local(point)
	var radius := float(REGISTRY.EVENTS[event].distance)
	draw_circle(local, 6.0, Color("#e5af65"))
	draw_arc(local, radius, 0.0, TAU, 48, Color("#e5af6566"), 1.5, true)

