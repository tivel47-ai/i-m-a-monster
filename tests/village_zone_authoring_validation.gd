# Godot --headless --path . --script tests/village_zone_authoring_validation.gd
extends SceneTree

var failures := 0
const MAP := "res://scenes/village_simulation_map.tscn"
const FIXTURE := "res://.godot/stage3_preferences.tscn"
const REBUILT := "res://.godot/stage3_rebuilt.tscn"
const REPEATED := "res://.godot/stage3_repeated.tscn"

func _initialize() -> void:
	call_deferred("run")

func check(valid: bool, message: String) -> void:
	if valid: print("PASS: ",message)
	else:
		failures+=1
		push_error(message)

func exports(node: Node) -> Dictionary:
	var values := {}
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_EDITOR:
			values[property.name]=node.get(property.name)
	return values

func collect_geometry(node: Node, values: Dictionary, path: String) -> void:
	var entry := {"class":node.get_class()}
	if node is Node2D: entry.transform=node.transform
	if node is CanvasItem:
		entry.visible=node.visible
		entry.modulate=node.modulate
	if node is Polygon2D:
		entry.polygon=node.polygon
		entry.color=node.color
	if node is Line2D:
		entry.points=node.points
		entry.width=node.width
		entry.color=node.default_color
	if node is Label:
		entry.position=node.position
		entry.text=node.text
	if node is CollisionObject2D:
		entry.layer=node.collision_layer
		entry.mask=node.collision_mask
	if node is CollisionPolygon2D: entry.collision_polygon=node.polygon
	if node is CollisionShape2D:
		entry.shape_class=node.shape.get_class()
		entry.shape_bounds=node.shape.get_rect()
	if node is NavigationRegion2D:
		entry.vertices=node.navigation_polygon.vertices
		var polygons: Array[PackedInt32Array]=[]
		for index in range(node.navigation_polygon.get_polygon_count()): polygons.append(node.navigation_polygon.get_polygon(index))
		entry.navigation_polygons=polygons
	values[path]=entry
	for child in node.get_children(): collect_geometry(child,values,path+"/"+str(child.name))

func geography(scene: Node) -> Dictionary:
	var values := {}
	for branch in ["Ground","GroundVariation","Roads","Environment","NavigationRegion2D"]:
		collect_geometry(scene.get_node(branch),values,branch)
	return values

func preferences(scene: Node) -> Dictionary:
	var values := {"residents":{},"zones":{},"patrol_routes":{},"alert":exports(scene.get_node("VillageAlert"))}
	for actor in scene.get_node("Villagers").get_children():
		var entry := {"exports":exports(actor),"color":actor.get_node("Polygon2D").color,"components":{}}
		for component in ["ThreatDetection","ThreatReaction","LocalWarning","GuardPatrol"]:
			if actor.has_node(component): entry.components[component]=exports(actor.get_node(component))
		values.residents[str(actor.name)]=entry
	for zone in scene.get_node("ActivityZones").get_children():
		var entry := exports(zone)
		for key in ["polygon","position","rotation","scale","offset"]: entry[key]=zone.get(key)
		values.zones[str(zone.name)]=entry
	if scene.has_node("GuardPatrolRoutes"):
		for route in scene.get_node("GuardPatrolRoutes").get_children():
			var entry:=exports(route)
			for key in ["points","position","rotation","scale"]: entry[key]=route.get(key)
			values.patrol_routes[str(route.name)]=entry
	return values

func dispose(scene: Node) -> void:
	scene.placement.free()
	scene.free()

func rebuild(source: String, output_path: String, log_name: String) -> int:
	var output: Array=[]
	var args := PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tools/build_simulation_village.gd","--log-file",ProjectSettings.globalize_path("res://.godot/"+log_name),"--","--output="+output_path,"--preferences-source="+source])
	var status := OS.execute(OS.get_executable_path(),args,output,true)
	if status!=0: print(output)
	return status

func run() -> void:
	var scene: Node2D=load(MAP).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var original_geometry := geography(scene)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="):
			var baseline: Node2D=load(argument.trim_prefix("--baseline=")).instantiate()
			var before := geography(baseline)
			var changed: Array[String]=[]
			for path in original_geometry:
				if not before.has(path) or before[path]!=original_geometry[path]: changed.append(path)
			check(before.size()==original_geometry.size() and changed.is_empty(),"All pre-migration buildings, roads, crops, fences, river, bridge, collisions and navigation are unchanged: "+str(changed))
			var preserved := true
			for old_actor in baseline.get_node("Villagers").get_children():
				var new_actor: Node = scene.get_node("Villagers/"+str(old_actor.name))
				var old_exports := exports(old_actor)
				var new_exports := exports(new_actor)
				for key in ["home_point_path","work_point_path","points_of_interest_path","activity_zone_paths","marker_activity_fallback_enabled","preferred_district","district_zone_preference","nearby_zone_distance"]:
					old_exports.erase(key)
					new_exports.erase(key)
				preserved = preserved and old_exports==new_exports and old_actor.get_node("Polygon2D").color==new_actor.get_node("Polygon2D").color
				for component in ["ThreatDetection","ThreatReaction","LocalWarning"]:
					preserved = preserved and exports(old_actor.get_node(component))==exports(new_actor.get_node(component))
			check(preserved,"Migration preserves all pre-existing resident tuning and all three component configurations")
			var old_camera: Camera2D=baseline.get_node("Camera2D")
			var new_camera: Camera2D=scene.get_node("Camera2D")
			check(exports(old_camera)==exports(new_camera) and old_camera.position==new_camera.position and old_camera.zoom==new_camera.zoom
				and exports(baseline.get_node("VillageAlert"))==exports(scene.get_node("VillageAlert")), "Migration retains pre-existing camera and informational alert settings")
			dispose(baseline)
	var actor=scene.get_node("Villagers/Peasant1")
	actor.move_speed=58.0
	actor.home_duration=Vector2(15,19)
	actor.work_weight=41.0
	actor.home_local_rules=Vector3(0.7,1.8,0.5)
	actor.preferred_district=&"farm"
	actor.nearby_zone_distance=500
	actor.district_zone_preference=4.7
	actor.activity_zone_paths.reverse()
	scene.get_node("Villagers/Peasant2").activity_zone_paths.clear()
	actor.get_node("Polygon2D").color=Color(0.2,0.5,0.7)
	actor.get_node("ThreatDetection").detection_radius=177
	actor.get_node("ThreatDetection").recognition_delay_min=0.77
	actor.get_node("ThreatReaction").fleeing_speed=99
	actor.get_node("ThreatReaction").warning_duration=1.3
	actor.get_node("ThreatReaction").debug_enabled=true
	actor.get_node("LocalWarning").hearing_radius=201
	scene.get_node("VillageAlert").quiet_period=21
	var zone: ActivityZone2D=scene.get_node("ActivityZones/SocialSquare")
	zone.local_pause_duration=Vector2(4,9)
	zone.local_move_speed=27
	zone.debug_enabled=true
	var edited := zone.polygon.duplicate()
	edited[0]+=Vector2(3,2)
	zone.polygon=edited
	zone.position+=Vector2(2,1)
	if scene.has_node("GuardPatrolRoutes"):
		scene.get_node("Villagers/Guard25/GuardPatrol").patrol_speed=42
		scene.get_node("GuardPatrolRoutes/NorthCircuit").observation_pause=Vector2(3,6)
	var expected_preferences := preferences(scene)
	var packed := PackedScene.new()
	var saved := packed.pack(scene)
	if saved==OK: saved=ResourceSaver.save(packed,FIXTURE)
	check(saved==OK,"Customized root, detection, reaction, warning, alert and zone settings are saved to a temporary fixture")
	dispose(scene)
	check(rebuild(FIXTURE,REBUILT,"stage3_authoring_build1.log")==0,"Generator rebuilds migration to a temporary scene")
	var rebuilt: Node2D=load(REBUILT).instantiate()
	check(geography(rebuilt)==original_geometry,"Rebuilding preserves all authored visual/collision/navigation geography")
	var actual := preferences(rebuilt)
	if actual!=expected_preferences: preference_diff(expected_preferences,actual,"")
	check(actual==expected_preferences,"All 30 resident exports/colors/component settings, explicit assignments, edited zone polygons and alert preferences survive rebuilding")
	check(not rebuilt.has_node("ResidentRoutes") and rebuilt.get_node("ActivityZones").get_child_count()==59,"Rebuild retains zones instead of restoring 150 obsolete personal markers")
	dispose(rebuilt)
	check(rebuild(REBUILT,REPEATED,"stage3_authoring_build2.log")==0,"Second reconstruction succeeds with the same saved assignments")
	var repeated: Node2D=load(REPEATED).instantiate()
	check(preferences(repeated)==expected_preferences and geography(repeated)==original_geometry,"Repeated reconstruction is deterministic in geometry, assignments and Inspector preferences")
	dispose(repeated)
	print("Village zone authoring validation failures: ",failures)
	quit(1 if failures else 0)


func preference_diff(expected: Variant, actual: Variant, path: String) -> void:
	if expected is Dictionary and actual is Dictionary:
		for key in expected:
			if not actual.has(key): print("MISSING PREFERENCE ",path,"/",key)
			elif expected[key]!=actual[key]: preference_diff(expected[key],actual[key],path+"/"+str(key))
	else:
		print("PREFERENCE DIFF ",path," expected=",expected," actual=",actual)
