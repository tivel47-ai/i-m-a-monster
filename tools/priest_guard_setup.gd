extends RefCounted

const ROUTES = preload("res://scripts/priest_guard_routes.gd")

static func install(map: Node2D) -> void:
	for i in range(2):
		var title := "PriestGuard" + str(i + 1)
		var route := ROUTES.route_for(map, i)
		if map.has_node("Villagers/" + title):
			var existing = map.get_node("Villagers/" + title).get_node_or_null("PriestGuard")
			if existing != null and existing.patrol_points.is_empty(): existing.patrol_points = route
			continue
		var actor = load("res://scenes/priest_guard.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		actor.name = title
		actor.get_node("PriestGuard").slot = i
		actor.get_node("PriestGuard").patrol_points = route
		map.get_node("Villagers").add_child(actor)
		actor.owner = map
		actor.position = Vector2(1440,557) if i == 0 else Vector2(1350,580)
		map.set_editable_instance(actor,true)
