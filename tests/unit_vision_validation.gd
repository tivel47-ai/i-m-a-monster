extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const ZOMBIE = preload("res://scenes/zombie.tscn")
const FORMS = preload("res://scripts/zombie_mission_build.gd")
const ALERT = preload("res://scripts/village_alert.gd")
const REAR_RADII := {
	ALERT.Level.NORMAL: 0.0,
	ALERT.Level.SUSPICION: 250.0 / 3.0,
	ALERT.Level.ALARM: 125.0,
	ALERT.Level.ORGANIZED_DEFENSE: 250.0,
	ALERT.Level.LAST_STAND: 250.0,
}

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var mission := MISSION.instantiate()
	mission.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(mission)
	var alert := mission.get_node("VillageAlert") as ALERT
	var residents: Array[Node] = mission.villagers.duplicate()
	var reinforcement: Node2D = mission._spawn_reinforcement(&"crossbow", Vector2.ZERO, null)
	residents.append(reinforcement)
	var monsters: Array[Node2D] = []
	for form in ["", "brute", "hound", "carrier"]:
		var monster := ZOMBIE.instantiate()
		FORMS.apply_form(monster, form, true)
		mission.add_child(monster)
		monsters.append(monster)
		var aggro_shape: CircleShape2D = monster.get_node("AggroArea/CollisionShape2D").shape
		check(aggro_shape.radius == 200.0, "Aggro candidate radius for %s" % monster.zombie_form)

	for level in REAR_RADII:
		alert.level = level
		var stage: String = ALERT.LEVEL_LABELS[level]
		for actor in residents:
			var rear_radius: float = 250.0 if actor.get_meta("village_role", "") == "priest" else REAR_RADII[level]
			check_range(actor, stage, 250.0, rear_radius)
		for monster in monsters:
			check_range(monster, stage, 200.0, 200.0)

	# Moving the alert back to calm takes effect on actors already in the scene.
	alert.level = ALERT.Level.NORMAL
	check_range(reinforcement, "Reset to calm", 250.0, 0.0)
	mission.free()
	print("Unit vision validation: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func check_range(actor: Node2D, stage: String, front: float, rear: float) -> void:
	var vision = actor.unit_vision
	var context := "%s / %s" % [actor.name, stage]
	check(vision != null, "%s: vision is attached" % context)
	if vision == null:
		return
	vision.face_for_pose(Vector2.RIGHT)
	var center := actor.global_position
	check(vision.contains(center + Vector2(front, 0.0))
		and vision.contains(center + Vector2(0.0, front))
		and vision.contains(center - Vector2(0.0, front))
		and not vision.contains(center + Vector2(front + 1.0, 0.0)), "%s: front and side limits" % context)
	if rear > 0.0:
		check(vision.contains(center - Vector2(rear, 0.0)), "%s: rear boundary is included" % context)
	check(not vision.contains(center - Vector2(rear + 1.0, 0.0)), "%s: rear limit" % context)
	vision.face_for_pose(Vector2.LEFT)
	check(vision.contains(center - Vector2(front, 0.0))
		and not vision.contains(center + Vector2(rear + 1.0, 0.0)), "%s: turning swaps front and rear" % context)


func check(result: bool, description: String) -> void:
	checks += 1
	if not result:
		failures += 1
		push_error(description)
