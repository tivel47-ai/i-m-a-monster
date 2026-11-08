extends Node

signal level_changed(previous: int, current: int)
signal score_changed(score: float)
## Traceable accepted incidents contain IDs, never threat coordinates or references.
signal incident_recorded(kind: StringName, subject_id: int, contribution: float)

enum Level { NORMAL, SUSPICION, ALARM, ORGANIZED_DEFENSE }

@export_group("Legacy score compatibility")
@export_range(1, 1000) var max_score: float = 100.0
@export var suspicion_threshold: float = 20.0
## Legacy serialized setting retained for compatibility; never activates ALARM.
@export var alarm_threshold: float = 60.0
## Legacy score fields retained for serialized resources; escalation uses confirmed evidence.
@export var recognition_points: float = 20.0
## Legacy serialized stage contributions; private events no longer add points.
@export var warning_points: float = 10.0
@export var combat_points: float = 20.0
@export var outcome_points: float = 20.0
@export_group("Deprecated compatibility settings")
@export var quiet_period: float = 90.0
@export var decay_per_second: float = 2.0
@export var hysteresis: float = 5.0
@export_group("Debug")
@export var debug_enabled: bool = false

@export_group("Provisional organized defense")
@export var danger_threshold: float = 100.0
@export var sighting_danger: float = 5.0
@export var visible_danger_per_second: float = 1.0
@export var visible_danger_cap: float = 5.0

@export var corpse_danger: float = 10.0
@export var defender_loss_danger: float = 15.0
@export var combat_danger: float = 8.0
@export_range(0, 1) var first_corpse_probability: float = 0.05
@export_range(0, 1) var corpse_probability_step: float = 0.10
var corpses: Dictionary = {}
var registered_corpses: Dictionary = {}
var corpse_decisions: Dictionary = {}
var combat_episodes: Dictionary = {}
## Seed may be assigned by validation tools after initialization.
var rng := RandomNumberGenerator.new()

var danger: float = 0.0
var guards: Array[WeakRef] = []
var score: float = 0.0
var level: Level = Level.NORMAL
var quiet_elapsed: float = 0.0
var decay_active: bool = false
var incident_counts: Dictionary = {}
var _seen: Dictionary = {}
var _registered: Dictionary = {}
var _debug_layer: CanvasLayer
var _debug_label: Label
var bell_activated: bool = false


func _ready() -> void:
	rng.randomize()
	# Inherit the mission's PAUSABLE / DISABLED lifecycle, not the menu's ALWAYS.
	_debug_layer = CanvasLayer.new()
	add_child(_debug_layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(8, 100)
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_layer.add_child(_debug_label)
	_update_debug()


func initialize(residents: Array[Node]) -> void:
	# Called once by the owning mission after its population has been collected.
	for resident in residents:
		var id := resident.get_instance_id()
		if _registered.has(id) or not get_parent().is_ancestor_of(resident):
			continue
		_registered[id] = true
		resident.died.connect(_resident_died)
		resident.encounter_started.connect(_combat_started.bind(resident))
		if resident.infection_state == resident.InfectionState.DEAD:
			_resident_died(resident)


func report_delivered(source: Node2D, recipient: Node2D, report: Dictionary) -> void:
	# Called after local acceptance. Civilian-only exchanges do not escalate.
	if not is_instance_valid(source) or not is_instance_valid(recipient) or source == recipient: return
	if not _registered.has(source.get_instance_id()) or not _registered.has(recipient.get_instance_id()): return
	if recipient.guard_ai == null: return
	if not source.is_alive() or not recipient.is_alive() or source.defense != recipient.defense: return
	if report.get("ack", false) or int(report.get("incident", 0)) <= 0: return
	if source.global_position.distance_to(recipient.global_position) > recipient.local_warning.hearing_radius: return
	if report.get("kind", "") == "corpse":
		if valid_corpse_report(source, report):
			confirm_corpse(recipient, report, source)
		return
	confirm_threat(recipient, int(report.incident))


func _record(kind: StringName, subject_id: int, points: float) -> void:
	# Mission-lifetime keys: observers/deliveries/reacquisition cannot farm points.
	var key := "%s:%d" % [kind, subject_id]
	if _seen.has(key) or points <= 0.0 or not can_process():
		return
	_seen[key] = true
	incident_counts[kind] = int(incident_counts.get(kind, 0)) + 1
	quiet_elapsed = 0.0
	decay_active = false
	score = clampf(score + points, 0.0, maxf(max_score, 1.0))
	_refresh_level()
	score_changed.emit(score)
	incident_recorded.emit(kind, subject_id, points)
	_update_debug()


func confirm_threat(guard: Node2D, incident: int) -> void:
	if not can_process() or not is_instance_valid(guard) or guard.guard_ai == null or not guard.is_alive():
		return
	if not _registered.has(guard.get_instance_id()) or incident <= 0:
		return
	var known := false
	for reference in guards:
		if reference.get_ref() == guard:
			known = true
			break
	if not known:
		guards.append(weakref(guard))
	advance_level(Level.SUSPICION)
	_record_monster(incident)


func observe_monster(observer: Node2D, enemy: Node2D) -> void:
	# Direct recognition is sufficient after the bell, independent of reporting.
	if not _can_record_direct_sighting(observer) or not is_instance_valid(enemy):
		return
	var incident := enemy.get_instance_id()
	if _seen.has("monster:%d" % incident) or not observer.threat_detection._is_visible_target(enemy):
		return
	_record_monster(incident)


func _can_record_direct_sighting(observer: Node2D) -> bool:
	return level == Level.ALARM and can_process() and is_instance_valid(observer) \
		and _registered.has(observer.get_instance_id()) and observer.is_available_for_infection() \
		and observer.threat_detection.detection_enabled


func _record_monster(incident: int) -> void:
	var key := "monster:%d" % incident
	if _seen.has(key):
		return
	_seen[key] = true
	if level >= Level.ALARM:
		add_danger(sighting_danger)
	incident_recorded.emit(&"monster", incident, sighting_danger if bell_activated else 0.0)


func add_danger(amount: float) -> void:
	if not can_process() or level != Level.ALARM:
		return
	danger += maxf(amount, 0.0)
	if danger >= maxf(danger_threshold, 0.001):
		advance_level(Level.ORGANIZED_DEFENSE)


func advance_level(next: Level) -> void:
	if next >= Level.ALARM and not bell_activated:
		return
	if next == Level.ORGANIZED_DEFENSE and danger < maxf(danger_threshold, 0.001):
		return
	if next <= level:
		return
	var previous := level
	level = next
	level_changed.emit(previous, level)
	_update_debug()


func _physics_process(delta: float) -> void:
	if level == Level.ALARM:
		var visible: Dictionary = {}
		for reference in guards:
			var guard = reference.get_ref()
			if not is_instance_valid(guard) or not guard.is_alive() or guard.infection_state == guard.InfectionState.TRANSFORMING or not guard.guard_ai.enabled or not guard.threat_detection.detection_enabled:
				continue
			for enemy in guard.guard_ai.visible_enemies:
				if is_instance_valid(enemy) and guard.threat_detection._is_visible_target(enemy):
					visible[enemy.get_instance_id()] = true
		add_danger(minf(visible.size() * maxf(visible_danger_per_second, 0.0), maxf(visible_danger_cap, 0.0)) * maxf(delta, 0.0))
	_update_debug()


func _refresh_level() -> void:
	# Legacy score callers cannot change global alert state.
	if bell_activated:
		advance_level(Level.ALARM)

func activate_bell(actor: Node2D) -> bool:
	# Only the mission's physical interaction endpoint is accepted.
	if bell_activated: return false
	var defense = get_parent().get_node_or_null("VillageDefense")
	if defense == null or not can_process() or not actor.is_available_for_infection() or actor.defense != defense or not is_instance_valid(defense.bell): return false
	if actor.global_position.distance_to(defense.bell.global_position) > defense.bell_reach or not defense.bell_visible(actor): return false
	danger = 0.0
	bell_activated = true
	_refresh_level()
	_update_debug()
	return true


func _update_debug() -> void:
	if not is_instance_valid(_debug_label):
		return
	_debug_layer.visible = debug_enabled
	if debug_enabled:
		_debug_label.text = "Village Alert: %s\nDefense danger: %.1f / %.0f\nGlobal decay: %s" % [
			Level.keys()[level], danger, danger_threshold, "disabled"]

func _resident_died(resident: Node2D) -> void:
	corpses[resident.get_instance_id()] = weakref(resident)

func _combat_started(enemy: Node2D, resident: Node2D) -> void:
	var id := resident.get_instance_id()
	var episode: int = int(combat_episodes.get(id, 0)) + 1
	combat_episodes[id] = episode
	for observer in get_parent().villagers:
		if not is_instance_valid(observer) or observer.guard_ai == null or not observer.guard_ai.enabled or not observer.is_alive() or observer.infection_state == observer.InfectionState.TRANSFORMING:
			continue
		if observer.threat_detection.detection_enabled and observer.threat_detection._is_visible_target(enemy) and observer.defense.visible(observer, resident, observer.threat_detection.detection_radius):
			confirm_threat(observer, enemy.get_instance_id())
			record_danger("combat:%d:%d" % [id, episode], &"combat", id, combat_danger)

func record_danger(key: String, kind: StringName, id: int, amount: float) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	incident_counts[kind] = int(incident_counts.get(kind, 0)) + 1
	if level >= Level.ALARM:
		add_danger(amount)
	incident_recorded.emit(kind, id, amount if bell_activated else 0.0)

func valid_corpse_report(source: Node2D, message: Dictionary) -> bool:
	if not is_instance_valid(source) or not source.is_available_for_infection():
		return false
	var id := int(message.get("incident", 0))
	if message.get("kind", "") != "corpse" or not corpses.has(id):
		return false
	var perception = source.get_node_or_null("CorpsePerception")
	if perception == null or not perception.known.has(id):
		return false
	return message == perception.known[id] and source.defense.alert == self

func confirm_corpse(guard: Node2D, message: Dictionary, source: Node2D = null) -> void:
	if not can_process() or not is_instance_valid(guard) or guard.guard_ai == null or not guard.guard_ai.enabled or not guard.is_available_for_infection():
		return
	if source == null:
		source = guard
	if not valid_corpse_report(source, message):
		return
	var id := int(message.get("incident", 0))
	if not _registered.has(guard.get_instance_id()) or not corpses.has(id):
		return
	advance_level(Level.SUSPICION)
	if _register_corpse(id) and level < Level.ALARM:
		corpse_decisions[id] = false
		guard.guard_ai.investigation.queue_corpse(message)


func observe_corpse(observer: Node2D, message: Dictionary) -> void:
	if not _can_record_direct_sighting(observer) or not valid_corpse_report(observer, message):
		return
	var id := int(message.incident)
	if registered_corpses.has(id):
		return
	var body = corpses[id].get_ref()
	if is_instance_valid(body) and body.infection_state == body.InfectionState.DEAD \
		and observer.defense.visible(observer, body, observer.threat_detection.detection_radius):
		_register_corpse(id)


func _register_corpse(id: int) -> bool:
	if registered_corpses.has(id):
		return false
	registered_corpses[id] = true
	var body = corpses[id].get_ref()
	var loss: bool = is_instance_valid(body) and body.guard_ai != null
	record_danger("death:%d" % id, &"defender_loss" if loss else &"corpse", id, defender_loss_danger if loss else corpse_danger)
	return true

func corpse_probability() -> float:
	return clampf(first_corpse_probability + maxf(registered_corpses.size() - 1, 0) * corpse_probability_step, 0.0, 1.0)

func decide_corpse_alarm(ids: Array) -> bool:
	if level >= Level.ALARM:
		return false
	for id in ids:
		if not corpse_decisions.has(id) or corpse_decisions[id]:
			continue
		corpse_decisions[id] = true
		if rng.randf() < corpse_probability():
			return true
	return false

func observe_combat(observer: Node2D, resident: Node2D) -> void:
	if not resident.is_in_collision() or not observer.threat_detection.detection_enabled:
		return
	var id := resident.get_instance_id()
	if not combat_episodes.has(id):
		return
	for enemy in resident.encounter_participants:
		if is_instance_valid(enemy) and observer.threat_detection._is_visible_target(enemy):
			confirm_threat(observer, enemy.get_instance_id())
			record_danger("combat:%d:%d" % [id, int(combat_episodes[id])], &"combat", id, combat_danger)
			return
