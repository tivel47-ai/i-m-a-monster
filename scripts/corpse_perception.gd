extends Node
## Local evidence, using the mission's non-blocking dead residents.
@export var interval: float = 0.5
var remaining: float = 0.0
var known: Dictionary = {}
var offered: Dictionary = {}
@onready var actor = get_parent()

func _ready() -> void:
	remaining = float(actor.get_instance_id() % 10) * 0.05

func _physics_process(delta: float) -> void:
	if not actor.is_available_for_infection() or not actor.threat_detection.detection_enabled:
		return
	remaining -= delta
	if remaining > 0:
		return
	remaining = maxf(interval, 0.1)
	var alert = actor.defense.alert
	for id in alert.corpses:
		var body = alert.corpses[id].get_ref()
		if not is_instance_valid(body) or body.infection_state != body.InfectionState.DEAD:
			continue
		if not actor.defense.visible(actor, body, actor.threat_detection.detection_radius):
			continue
		if not known.has(id):
			known[id] = {"kind": "corpse", "incident": id, "point": body.global_position,
				"source": actor.get_instance_id(), "observed_at": actor.defense.elapsed,
				"credibility": 1.0, "relay": 0}
		if actor.guard_ai != null:
			alert.confirm_corpse(actor, known[id])
		elif actor.escort != null and actor.escort.can_recruit() and not offered.has(id):
			if alert.level >= alert.Level.ALARM or actor.get_recognized_threat() != null or actor.threat_reaction.episode_active:
				continue
			if actor.escort.reporter.observe(known[id]):
				offered[id] = true
