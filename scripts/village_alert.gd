extends Node

signal level_changed(previous: int, current: int)
signal score_changed(score: float)
## Traceable accepted incidents contain IDs, never threat coordinates or references.
signal incident_recorded(kind: StringName, subject_id: int, contribution: float)

enum Level { NORMAL, SUSPICION, ALARM, ORGANIZED_DEFENSE }

@export_group("Provisional escalation")
@export_range(1, 1000) var max_score: float = 100.0
@export var suspicion_threshold: float = 20.0
@export var alarm_threshold: float = 60.0
@export var recognition_points: float = 20.0
@export var warning_points: float = 10.0
@export var combat_points: float = 20.0
@export var outcome_points: float = 20.0
@export_group("Provisional decay")
@export var quiet_period: float = 15.0
@export var decay_per_second: float = 2.0
@export var hysteresis: float = 5.0
@export_group("Debug")
@export var debug_enabled: bool = false

var score: float = 0.0
var level: Level = Level.NORMAL
var quiet_elapsed: float = 0.0
var decay_active: bool = false
var incident_counts: Dictionary = {}
var _seen: Dictionary = {}
var _combatants: Dictionary = {}
var _registered: Dictionary = {}
var _debug_layer: CanvasLayer
var _debug_label: Label


func _ready() -> void:
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
		resident.threat_recognized.connect(_on_recognition.bind(resident))
		resident.warning_attempted.connect(_on_warning)
		resident.encounter_started.connect(_on_combat.bind(resident))
		resident.died.connect(_on_outcome)
		resident.converted.connect(_on_outcome)


func _on_recognition(zombie: Node2D, resident: Node2D) -> void:
	if not resident.is_available_for_infection() or not _valid_zombie(zombie):
		return
	_record(&"recognition", zombie.get_instance_id(), recognition_points)


func _on_warning(resident: Node2D, point: Vector2) -> void:
	var reaction = resident.threat_reaction
	if not resident.is_available_for_infection() or reaction.report_based or not reaction.episode_active or not reaction.warning_sent:
		return
	if reaction.threat_id <= 0 or not resident.local_warning._valid_position(point):
		return
	_record(&"warning", reaction.threat_id, warning_points)


func _on_combat(zombie: Node2D, resident: Node2D) -> void:
	if not _valid_zombie(zombie) or not resident.is_encounter_owner(zombie):
		return
	var id := resident.get_instance_id()
	_combatants[id] = true
	_record(&"combat", id, combat_points)


func _on_outcome(resident: Node) -> void:
	var id := resident.get_instance_id()
	# An unrelated death is not evidence of a hostile encounter.
	if _combatants.has(id) and (resident.is_dead() or resident.is_converted()):
		_record(&"outcome", id, outcome_points)


func _valid_zombie(target: Variant) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_in_group("player_units") and get_parent().is_ancestor_of(target) and target.has_method("is_alive") and target.is_alive()


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


func _physics_process(delta: float) -> void:
	var step := maxf(delta, 0.0)
	var delay := maxf(quiet_period, 0.0)
	var previous := quiet_elapsed
	quiet_elapsed += step
	# Only credit the fraction of a frame that lies beyond the quiet period.
	var decay_seconds := maxf(quiet_elapsed - delay, 0.0) - maxf(previous - delay, 0.0)
	decay_active = score > 0.0 and decay_per_second > 0.0 and decay_seconds > 0.0
	if decay_active:
		score = maxf(score - decay_seconds * decay_per_second, 0.0)
		_refresh_level()
		score_changed.emit(score)
		if score == 0.0:
			decay_active = false
	_update_debug()


func _refresh_level() -> void:
	var maximum := maxf(max_score, 1.0)
	var suspicion := clampf(suspicion_threshold, 0.001, maximum)
	var alarm := clampf(alarm_threshold, suspicion, maximum)
	var margin := maxf(hysteresis, 0.0)
	var previous := level
	if score >= alarm:
		level = Level.ALARM
	elif level == Level.ALARM and score > maxf(alarm - margin, 0.0):
		level = Level.ALARM
	elif score >= suspicion:
		level = Level.SUSPICION
	elif level != Level.NORMAL and score > maxf(suspicion - margin, 0.0):
		level = Level.SUSPICION
	else:
		level = Level.NORMAL
	if previous != level:
		level_changed.emit(previous, level)


func _update_debug() -> void:
	if not is_instance_valid(_debug_label):
		return
	_debug_layer.visible = debug_enabled
	if debug_enabled:
		_debug_label.text = "Village Alert: %s\nAlert Score: %.1f / %.0f\nDecay: %s" % [
			Level.keys()[level], score, maxf(max_score, 1.0), "active" if decay_active else "waiting"]
