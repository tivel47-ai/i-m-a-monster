extends SceneTree

const MISSION_SCENE := "res://scenes/village_simulation_map.tscn"

func _initialize() -> void:
	call_deferred("_rebake")

func _rebake() -> void:
	var scene := load(MISSION_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load Mission 1.")
		quit(1)
		return

	var mission := scene.instantiate()
	var region := mission.get_node_or_null("NavigationRegion2D") as NavigationRegion2D
	if region == null or region.navigation_polygon == null:
		mission.free()
		push_error("Mission 1 has no navigation polygon.")
		quit(1)
		return

	var resource_path := region.navigation_polygon.resource_path
	var resource_uid := ResourceLoader.get_resource_uid(resource_path)
	var navigation := region.navigation_polygon.duplicate() as NavigationPolygon
	region.navigation_polygon = navigation
	# Only the navigation subtree needs to enter the tree for baking.
	region.owner = null
	mission.remove_child(region)
	root.add_child(region)
	region.bake_navigation_polygon(false)
	region.free()
	mission.free()

	if navigation.get_polygon_count() == 0:
		push_error("Mission 1 bake produced no polygons.")
		quit(1)
		return

	var error := ResourceSaver.save(navigation, resource_path)
	if error == OK and resource_uid != ResourceUID.INVALID_ID:
		error = ResourceSaver.set_uid(resource_path, resource_uid)
	if error != OK:
		push_error("Could not save Mission 1 navigation: " + error_string(error))
		quit(1)
		return

	print("Mission 1 navigation saved: ", navigation.get_polygon_count(), " polygons.")
	quit()
