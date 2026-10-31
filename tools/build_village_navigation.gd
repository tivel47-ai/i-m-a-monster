# Run after editing map colliders:
# Godot --headless --path . --script tools/build_village_navigation.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	var scene := load("res://scenes/test_map.tscn") as PackedScene
	var map := scene.instantiate()
	root.add_child(map)
	var region := map.get_node("NavigationRegion2D") as NavigationRegion2D
	var polygon := NavigationPolygon.new()
	# The body is 20 x 32 (corner radius 18.87). Allow extra corner clearance
	# for the existing agent's 6 px path waypoint tolerance.
	polygon.agent_radius = 26.0
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.parsed_collision_mask = 1
	polygon.add_outline(PackedVector2Array([
		Vector2(24, 24), Vector2(1256, 24),
		Vector2(1256, 696), Vector2(24, 696),
	]))
	region.navigation_polygon = polygon
	# Only descendants of the region are parsed. Units, fields and labels
	# are outside it; all solid graybox geometry is inside it.
	region.bake_navigation_polygon(false)
	if polygon.get_polygon_count() == 0:
		push_error("Village navigation bake produced no polygons.")
		quit(1)
		return
	var error := ResourceSaver.save(polygon, "res://scenes/village_navigation.tres")
	print("Village navigation bake: ", error_string(error),
		"; polygons: ", polygon.get_polygon_count())
	map.queue_free()
	quit(0 if error == OK else 1)
