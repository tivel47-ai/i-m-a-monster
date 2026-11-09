# Godot --headless --path . --script tests/activity_assignment_validation.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var map: Node2D = load("res://scenes/village_simulation_map.tscn").instantiate()
	root.add_child(map)
	await physics_frame
	var zones: Node2D = map.get_node("ActivityZones")
	var counts := [0, 0, 0, 0]
	for zone in zones.get_children():
		counts[zone.activity] += 1
	var ok := counts == [14, 21, 9, 8]
	for actor in map.get_node("Villagers").get_children():
		var role := str(actor.get_meta("village_role", ""))
		if role not in ["peasant", "artisan"]:
			continue
		var social := []
		var work := []
		var home := []
		for path in actor.activity_zone_paths:
			var zone: ActivityZone2D = actor.get_node_or_null(path)
			ok = ok and zone != null and zone.allows_resident(actor)
			if zone == null: continue
			match zone.activity:
				0: home.append(zone.zone_id)
				1: work.append(zone.zone_id)
				2: social.append(zone.zone_id)
		ok = ok and social.size() == 3 and social.has(&"SocialSquare") and social.has(&"SocialChurch") and social.has(&"SocialTavern")
		if role == "peasant":
			ok = ok and home.size() == 1 and not work.is_empty() and actor.private_shelter_marker() == actor.get_node_or_null(actor.home_point_path)
		else:
			ok = ok and home.is_empty() and work.has(&"WorkWell") and actor.home_weight == 0.0
			ok = ok and actor.private_shelter_marker() == actor.get_node_or_null(actor.work_point_path)
	map.queue_free()
	print("Activity assignment validation: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
