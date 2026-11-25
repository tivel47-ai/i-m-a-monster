extends SceneTree

const MISSION = preload("res://scenes/village_simulation_map.tscn")
const EAST_CORNER := [
	Vector2(1706, 727), Vector2(1693, 736), Vector2(1684, 749),
	Vector2(1710, 748), Vector2(1697, 771), Vector2(1720, 730),
]
const GARDEN_CORNER := [Vector2(995, 1080), Vector2(1009, 1074), Vector2(1138, 1030)]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func run() -> void:
	var mission := MISSION.instantiate() as Node2D
	root.add_child(mission)
	var defense = mission.get_node("VillageDefense")
	var formation = defense.organized
	mission.get_node("LastStand").set_physics_process(false)
	for actor in mission.villagers:
		actor.autonomous_movement_enabled = false
		actor.threat_detection.detection_enabled = false
		actor.set_physics_process(false)
	var nav := mission.get_world_2d().navigation_map
	for i in 60:
		if NavigationServer2D.map_get_iteration_id(nav) > 0:
			break
		await physics_frame
		await process_frame
	if NavigationServer2D.map_get_iteration_id(nav) == 0:
		push_error("Mission 1 navigation did not synchronize")
		quit(1)
		return

	var guards: Array = mission.villagers.filter(func(actor): return actor.guard_ai != null)
	var civilians: Array = mission.villagers.filter(func(actor):
		return actor.escort != null and actor.escort.can_recruit()
	)
	var east := [guards[0]] + civilians.slice(0, 5)
	var garden := [guards[1]] + civilians.slice(5, 7)
	var defenders := east + garden
	stage(east, EAST_CORNER)
	stage(garden, GARDEN_CORNER)
	defense.alert.set_debug_level(defense.alert.Level.ORGANIZED_DEFENSE)
	for follower in east.slice(1, 3):
		follower.escort.leader = east[0].guard_ai
		follower.escort.last_leader_point = east[0].global_position
		follower.escort.last_contact = defense.elapsed
		east[0].guard_ai.followers.append(follower.escort)
	var probe: Vector2 = formation.controller(east[1]).escort_destination()
	check(not defense.reachable(east[1], probe), "The original escort offset lands outside the walkable lane")

	var region := mission.get_node("NavigationRegion2D")
	var walls: Array[PackedVector2Array] = []
	for name in [&"Cottage06", &"Cottage04"]:
		var house := region.find_child(name, true, false) as Node2D
		walls.append(house.global_transform * house.get_node("InteractiveBuilding").layout.outline)
	var crossed_wall := false
	for i in 720:
		await physics_frame
		await process_frame
		for actor in defenders:
			for outline in walls:
				crossed_wall = crossed_wall or Geometry2D.is_point_in_polygon(actor.global_position, outline)
		if defenders.all(formation.arrived):
			break

	check(east.all(formation.arrived), "The crowded east corner and both escorts clear the house and reach church defense")
	check(garden.all(formation.arrived), "The defenders by the west garden reach church defense")
	check(not crossed_wall, "Defenders pass the corners without entering the house footprints")
	check(east[0].guard_ai.followers.is_empty(), "Both escorted residents leave the group upon arrival")
	mission.queue_free()
	await process_frame
	print("Defense corner navigation: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures else 0)


func stage(actors: Array, starts: Array) -> void:
	for i in actors.size():
		var actor = actors[i]
		actor.global_position = starts[i]
		actor.autonomous_movement_enabled = true
		actor.set_physics_process(true)
