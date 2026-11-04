extends Node

signal level_changed(previous: int, current: int)
signal score_changed(score: float)
## Traceable accepted incidents contain IDs, never threat coordinates or references.
signal incident_recorded(kind: StringName, subject_id: int, contribution: float)

enum Level { NORMAL, SUSPICION, ALARM, ORGANIZED_DEFENSE }

@export_group("Provisional escalation")
@export_range(1, 1000) var max_score: float = 100.0
@export var suspicion_threshold: float = 20.0
## Legacy serialized setting retained for compatibility; never activates ALARM.
@export var alarm_threshold: float = 60.0
## Contribution of a genuinely delivered local incident, once per original ID.
@export var recognition_points: float = 20.0
## Legacy serialized stage contributions; private events no longer add points.
@export var warning_points: float = 10.0
@export var combat_points: float = 20.0
@export var outcome_points: float = 20.0
@export_group("Provisional decay")
@export var quiet_period: float = 90.0
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
var _registered: Dictionary = {}
var _debug_layer: CanvasLayer
var _debug_label: Label
var bell_activated: bool = false


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


func report_delivered(source: Node2D, recipient: Node2D, report: Dictionary) -> void:
	# Called AFTER the local recipient accepted the message. Personal perception,
	# combat, an unheard shout and an unwitnessed death are not village knowledge.
	if not is_instance_valid(source) or not is_instance_valid(recipient) or source == recipient: return
	if not _registered.has(source.get_instance_id()) or not _registered.has(recipient.get_instance_id()): return
	if not source.is_alive() or not recipient.is_alive() or source.defense != recipient.defense: return
	if report.get("ack", false) or int(report.get("incident", 0)) <= 0: return
	if source.global_position.distance_to(recipient.global_position) > recipient.local_warning.hearing_radius: return
	_record(&"communicated", int(report.incident), recognition_points)


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
	if level == Level.ORGANIZED_DEFENSE: return # reserved external transition, never selected here
	var maximum := maxf(max_score, 1.0)
	var suspicion := clampf(suspicion_threshold, 0.001, maximum)
	var margin := maxf(hysteresis, 0.0)
	var previous := level
	if bell_activated:
		level = Level.ALARM
	elif score >= suspicion:
		level = Level.SUSPICION
	elif level != Level.NORMAL and score > maxf(suspicion - margin, 0.0):
		level = Level.SUSPICION
	else:
		level = Level.NORMAL
	if previous != level:
		level_changed.emit(previous, level)


func activate_bell(actor: Node2D) -> bool:
	# Only the mission's physical interaction endpoint is accepted.
	var defense = get_parent().get_node_or_null("VillageDefense")
	if defense == null or not can_process() or not actor.is_available_for_infection() or actor.defense != defense or not is_instance_valid(defense.bell): return false
	if actor.global_position.distance_to(defense.bell.global_position) > defense.bell_reach or not defense.bell_visible(actor): return false
	bell_activated = true
	_refresh_level()
	_update_debug()
	return true


func _update_debug() -> void:
	if not is_instance_valid(_debug_label):
		return
	_debug_layer.visible = debug_enabled
	if debug_enabled:
		_debug_label.text = "Village Alert: %s\nAlert Score: %.1f / %.0f\nDecay: %s" % [
			Level.keys()[level], score, maxf(max_score, 1.0), "active" if decay_active else "waiting"]
