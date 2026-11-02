# Deterministic authoring tool, never run by gameplay. Rebuilds only Mission 1.
# Godot --headless --path . --script tools/build_simulation_village.gd
extends SceneTree

const OUTPUT := "res://scenes/village_simulation_map.tscn"
const NAVIGATION := "res://scenes/village_simulation_navigation.tres"
const ROAD := Color("71654f")
const PATH := Color("645d47")
const HOUSES := [
	["Cottage01", "small", Vector2(620, 470), Vector2(110, 82), -0.12],
	["Cottage02", "small", Vector2(890, 680), Vector2(98, 88), 0.16],
	["Cottage03", "small", Vector2(500, 810), Vector2(108, 78), -0.20],
	["Cottage04", "small", Vector2(1170, 1090), Vector2(116, 84), 0.11],
	["Cottage05", "large", Vector2(1030, 420), Vector2(166, 108), 0.08],
	["Cottage06", "large", Vector2(1760, 650), Vector2(158, 116), -0.13],
	["Cottage07", "large", Vector2(1780, 1620), Vector2(170, 104), 0.17],
	["Cottage08", "square", Vector2(860, 1110), Vector2(112, 112), -0.10],
	["Cottage09", "square", Vector2(1850, 1100), Vector2(120, 120), 0.14],
	["Cottage10", "L", Vector2(1070, 890), Vector2(170, 150), -0.08],
	["Cottage11", "L", Vector2(1360, 1490), Vector2(180, 148), 0.12],
	["Farmhouse12", "farmhouse", Vector2(680, 1600), Vector2(228, 92), -0.16],
]
const ROOFS := [Color("635645"), Color("60564f"), Color("75674b"), Color("555958")]

var village: Node2D
var region: NavigationRegion2D
var roads: Node2D
var details: Node2D
var points: Node2D
var trees: Node2D
var homes: Array[Vector2] = []
var street_lines: Array[PackedVector2Array] = []
var npc_preferences: Dictionary = {}
var activity_positions: Array[Vector2] = []

func _initialize() -> void:
	call_deferred("build")

func attach(parent: Node, child: Node, title: String) -> Node:
	child.name = title
	parent.add_child(child)
	child.owner = village
	return child

func container(parent: Node, title: String) -> Node2D:
	return attach(parent, Node2D.new(), title)

func rectangle(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])

func polygon(parent: Node, title: String, vertices: PackedVector2Array, color: Color) -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = vertices
	node.color = color
	return attach(parent, node, title)

func patch(parent: Node, title: String, center: Vector2, size: Vector2, color: Color) -> Polygon2D:
	var node := polygon(parent, title, rectangle(size), color)
	node.position = center
	return node

func stroke(parent: Node, title: String, vertices: PackedVector2Array, color: Color, width: float) -> Line2D:
	var node := Line2D.new()
	node.points = vertices
	node.width = width
	node.default_color = color
	return attach(parent, node, title)

func solid(parent: Node, title: String, center: Vector2, vertices: PackedVector2Array, color: Color, angle := 0.0) -> StaticBody2D:
	var node := StaticBody2D.new()
	node.position = center
	node.rotation = angle
	node.collision_layer = 1
	node.collision_mask = 0
	attach(parent, node, title)
	node.add_to_group("simulation_solids", true)
	polygon(node, "Footprint", vertices, color)
	var collision := CollisionPolygon2D.new()
	collision.polygon = vertices
	attach(node, collision, "CollisionPolygon2D")
	return node

func label_at(parent: Node, title: String, text: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("c7bea0"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attach(parent, label, title)

func road(title: String, anchors: Array, width := 52.0, color := ROAD, flat_ends := false, entrance := "") -> void:
	var samples := PackedVector2Array()
	# Catmull-Rom: authored junctions with gentle bends, no runtime generation.
	for i in range(anchors.size() - 1):
		var a: Vector2 = anchors[maxi(0, i - 1)]
		var b: Vector2 = anchors[i]
		var c: Vector2 = anchors[i + 1]
		var d: Vector2 = anchors[mini(anchors.size() - 1, i + 2)]
		for step in range(9):
			var t := step / 8.0
			samples.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t))
	var outlines := Geometry2D.offset_polyline(samples, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT if flat_ends else Geometry2D.END_ROUND)
	var clipped: Array[PackedVector2Array] = []
	var map_outline := PackedVector2Array([Vector2.ZERO,Vector2(3000,0),Vector2(3000,2000),Vector2(0,2000)])
	for outline in outlines: clipped.append_array(Geometry2D.intersect_polygons(outline,map_outline))
	outlines = clipped
	for i in range(outlines.size()):
		var surface := polygon(roads, title + str(i), outlines[i], color)
		surface.set_meta("centerline",samples)
		surface.set_meta("road_width",width)
		if not entrance.is_empty(): surface.set_meta("entrance",entrance)
	if title in ["MainStreet","NorthLane","ChurchLane","WestLane","SouthBypass","FarmLane","SouthSquareLane","ArtisanLink","WestCrossLane"]:
		street_lines.append(samples)

func nearest_street(at: Vector2) -> Vector2:
	var nearest := at
	var distance := INF
	for line in street_lines:
		for i in range(1,line.size()):
			var candidate := Geometry2D.get_closest_point_to_segment(at,line[i-1],line[i])
			if candidate.distance_squared_to(at)<distance:
				distance = candidate.distance_squared_to(at)
				nearest = candidate
	return nearest

func entrance_path(body: StaticBody2D, title: String, street_at: Vector2, via: Array = []) -> void:
	var edge: Vector2 = body.get_node("Door").position+Vector2(0,4)
	var anchors: Array = [body.to_global(edge+Vector2(0,5)),body.to_global(edge+Vector2(0,38))]
	anchors.append_array(via)
	anchors.append(nearest_street(street_at))
	road(title,anchors,22,PATH,true,str(village.get_path_to(body)))

func marker(title: String, at: Vector2, social := false, shelter := false) -> Marker2D:
	var node := Marker2D.new()
	node.position = at
	attach(points, node, title)
	if social: node.add_to_group("civilian_social_points", true)
	if shelter: node.add_to_group("civilian_shelter_points", true)
	return node

func building(parent: Node, title: String, center: Vector2, size: Vector2, angle: float, kind: String, index := 0) -> StaticBody2D:
	var footprint := rectangle(size)
	if kind == "L":
		footprint = PackedVector2Array([Vector2(-size.x/2, -size.y/2), Vector2(size.x/2, -size.y/2), Vector2(size.x/2, -8), Vector2(8, -8), Vector2(8, size.y/2), Vector2(-size.x/2, size.y/2)])
	elif kind == "church":
		footprint = PackedVector2Array([Vector2(-46,-130), Vector2(46,-130), Vector2(46,-44), Vector2(112,-44), Vector2(112,40), Vector2(46,40), Vector2(46,130), Vector2(-46,130), Vector2(-46,40), Vector2(-112,40), Vector2(-112,-44), Vector2(-46,-44)])
	var body := solid(parent, title, center, footprint, Color("3e4039"), angle)
	body.set_meta("building_type", kind)
	var roof_color: Color = ROOFS[index % ROOFS.size()]
	if kind == "church": roof_color = Color("565e60")
	if kind == "guard": roof_color = Color("454b49")
	var inset := Geometry2D.offset_polygon(footprint, -5.0)
	if not inset.is_empty(): polygon(body, "Roof", inset[0], roof_color)
	if kind == "L":
		stroke(body, "Ridge", PackedVector2Array([Vector2(-size.x/2+18, size.y/2-12), Vector2(-size.x/2+18,-size.y/2+22), Vector2(size.x/2-12,-size.y/2+22)]), roof_color.lightened(0.18), 4)
	else:
		stroke(body, "Ridge", PackedVector2Array([Vector2(-size.x/2+10,0), Vector2(size.x/2-10,0)]), roof_color.lightened(0.20), 4)
	# The door is on the blocked footprint edge; the approach stays outside.
	var door_x := -size.x * 0.28 if kind == "L" else 0.0
	patch(body, "Door", Vector2(door_x,size.y/2-4), Vector2(16,8), Color("282c28"))
	patch(body, "Window", Vector2(-size.x*0.30,-size.y*0.24), Vector2(10,9), Color("a79765"))
	if index % 3 != 1:
		patch(body, "Chimney", Vector2(size.x*0.23,-size.y*0.25), Vector2(13,18), Color("3b3d39"))
	if kind == "church":
		patch(body, "Tower", Vector2(0,-78), Vector2(60,62), Color("6b7270"))
		stroke(body, "CrossVertical", PackedVector2Array([Vector2(0,-102),Vector2(0,-56)]), Color("cbc4a7"), 5)
		stroke(body, "CrossHorizontal", PackedVector2Array([Vector2(-15,-85),Vector2(15,-85)]), Color("cbc4a7"), 5)
	elif kind == "blacksmith":
		patch(body, "ForgeHood", Vector2(42,-20), Vector2(32,42), Color("303532"))
		patch(body, "ForgeGlow", Vector2(42,5), Vector2(24,8), Color("a47a48"))
	elif kind == "guard":
		for x in [-48,48]:
			patch(body, "WatchPlatform" + str(x), Vector2(x,-48), Vector2(26,35), Color("747365"))
	elif kind == "tavern":
		patch(body, "Sign", Vector2(28,size.y/2-15), Vector2(22,18), Color("a99a71"))
	return body

func field(title: String, vertices: PackedVector2Array, vertical: bool, color := Color("60563a")) -> void:
	var plot := polygon(details, title, vertices, color)
	plot.add_to_group("simulation_fields", true)
	var bounds := Rect2(vertices[0], Vector2.ZERO)
	for vertex in vertices: bounds = bounds.expand(vertex)
	var start := bounds.position.x if vertical else bounds.position.y
	var end := bounds.end.x if vertical else bounds.end.y
	for row in range(int(start)+10, int(end)-5, 14):
		var strip := rectangle(Vector2(4,bounds.size.y+10) if vertical else Vector2(bounds.size.x+10,4))
		var shift := Vector2(row,bounds.get_center().y) if vertical else Vector2(bounds.get_center().x,row)
		for i in range(strip.size()): strip[i] += shift
		var clipped := Geometry2D.intersect_polygons(vertices,strip)
		for i in range(clipped.size()): polygon(plot,"Crop"+str(row)+"_"+str(i),clipped[i],Color("8a8051"))

func tree_at(title: String, at: Vector2, radius: float) -> void:
	var outline := PackedVector2Array()
	for i in range(10):
		outline.append(Vector2.from_angle(TAU*i/10.0) * radius * (1.0 if i%2==0 else 0.87))
	var body := solid(trees,title,at,outline,Color("283b2e"))
	var crown := PackedVector2Array()
	for vertex in outline: crown.append(vertex * 0.78)
	polygon(body,"Crown",crown,Color("354a32"))
	patch(body,"Trunk",Vector2(0,3),Vector2(6,10),Color("4a4334"))

func fence_line(parent: Node2D, title: String, anchors: Array, enclosure: Node2D) -> void:
	var boundary := container(parent,title)
	enclosure.add_to_group("simulation_enclosures",true)
	for i in range(anchors.size()-1):
		var a: Vector2 = anchors[i]
		var b: Vector2 = anchors[i+1]
		var length := a.distance_to(b)
		var fence := solid(boundary,"Section"+str(i),(a+b)*0.5,rectangle(Vector2(length,7)),Color("73674d"),a.angle_to_point(b))
		fence.add_to_group("simulation_fences",true)
		fence.set_meta("enclosure",str(village.get_path_to(enclosure)))
		fence.set_meta("ends",PackedVector2Array([a,b]))
		var posts := maxi(2,ceili(length/36.0)+1)
		for post in range(posts):
			var x := lerpf(-length*0.5+3,length*0.5-3,float(post)/(posts-1))
			patch(fence,"Post"+str(post),Vector2(x,0),Vector2(6,7),Color("938264"))

func build_fences() -> void:
	var fences := container(region,"Fences")
	# Each barrier follows a named plot. Open sides and 96-unit gates keep
	# entrances and the existing 26-unit navigation clearance usable.
	fence_line(fences,"Garden0RoadEdge",[Vector2(474,452),Vector2(474,538),Vector2(552,538)],details.get_node("Garden0"))
	fence_line(fences,"Garden3Boundary",[Vector2(1102,1072),Vector2(1024,1072),Vector2(1024,1158)],details.get_node("Garden3"))
	fence_line(fences,"Garden7Boundary",[Vector2(792,1092),Vector2(714,1092),Vector2(714,1178)],details.get_node("Garden7"))
	marker("Garden0Access",Vector2(510,442))
	marker("Garden3Access",Vector2(1075,1178))
	marker("Garden7Access",Vector2(760,1200))

	var west: Node2D = details.get_node("WestField")
	fence_line(fences,"WestFieldBoundary",[Vector2(361,1462),Vector2(361,1374),Vector2(124,1374),Vector2(124,1711),Vector2(361,1711),Vector2(361,1558)],west)
	marker("WestFieldGate",Vector2(361,1510))
	var vegetables: Node2D = details.get_node("Vegetables")
	fence_line(fences,"VegetableWest",[Vector2(314,1946),Vector2(314,1794),Vector2(440,1794)],vegetables)
	fence_line(fences,"VegetableEast",[Vector2(536,1794),Vector2(686,1794),Vector2(686,1946)],vegetables)
	fence_line(fences,"VegetableSouth",[Vector2(314,1946),Vector2(686,1946)],vegetables)
	marker("VegetableGate",Vector2(488,1788))
	fence_line(fences,"SouthFieldBoundary",[Vector2(770,1790),Vector2(755,1960),Vector2(1150,1960),Vector2(1150,1890)],details.get_node("SouthField"))
	marker("SouthFieldGate",Vector2(980,1780))

	var cemetery := container(details,"CemeteryYard")
	cemetery.set_meta("boundary",PackedVector2Array([Vector2(1525,65),Vector2(2050,65),Vector2(2080,420),Vector2(1940,455),Vector2(1525,455)]))
	fence_line(fences,"CemeteryWest",[Vector2(1525,285),Vector2(1525,65),Vector2(1740,65)],cemetery)
	fence_line(fences,"CemeteryNorthEast",[Vector2(1740,65),Vector2(2050,65),Vector2(2050,270),Vector2(2080,420)],cemetery)
	marker("CemeteryGate",Vector2(1540,480))

func build() -> void:
	read_npc_preferences()
	village = Node2D.new()
	village.name = "VillageSimulationMap"
	village.set_meta("map_size", Vector2(3000,2000))
	patch(village,"Ground",Vector2(1500,1000),Vector2(3000,2000),Color("48513a"))
	var ground := container(village,"GroundVariation")
	# Sparse, seeded ground patches have no collision and never regenerate in play.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261102
	for i in range(90):
		var at := Vector2(rng.randf_range(40,2960),rng.randf_range(40,1960))
		var shape := rectangle(Vector2(rng.randf_range(25,85),rng.randf_range(12,45)))
		var node := polygon(ground,"Grass"+str(i),shape,Color("4d563c") if i%2 else Color("444e37"))
		node.position = at
		node.rotation = rng.randf_range(-0.4,0.4)
	roads = container(village,"Roads")
	details = container(village,"Environment")
	region = NavigationRegion2D.new()
	attach(village,region,"NavigationRegion2D")
	var buildings := container(region,"Buildings")
	var residential := container(buildings,"Residential")
	var public_buildings := container(buildings,"Public")
	var workshops := container(buildings,"Workshops")
	var agricultural := container(buildings,"Agricultural")
	trees = container(region,"Trees")
	points = container(village,"VillagePointsOfInterest")

	road("MainStreet",[Vector2(0,960),Vector2(400,1010),Vector2(650,940),Vector2(790,960),Vector2(1020,730),Vector2(1220,730),Vector2(1470,880),Vector2(1790,900),Vector2(1980,820),Vector2(2160,890),Vector2(2370,970),Vector2(2550,970),Vector2(2590,1100),Vector2(2650,1180),Vector2(2740,1180),Vector2(2910,1180)],66)
	road("NorthLane",[Vector2(790,960),Vector2(790,650),Vector2(850,560),Vector2(1150,560),Vector2(1400,580),Vector2(1560,560),Vector2(1810,490),Vector2(2070,480),Vector2(2350,540),Vector2(2550,650),Vector2(2560,820),Vector2(2550,970)],46)
	road("ChurchLane",[Vector2(1470,880),Vector2(1480,700),Vector2(1400,580),Vector2(1420,550)],44)
	road("WestLane",[Vector2(400,1010),Vector2(390,650),Vector2(500,570),Vector2(850,580)],36)
	road("SouthBypass",[Vector2(400,1010),Vector2(430,1270),Vector2(840,1360),Vector2(1080,1300),Vector2(1430,1230),Vector2(1730,1290),Vector2(2060,1320),Vector2(2300,1350),Vector2(2480,1230),Vector2(2600,1110)],52)
	road("FarmLane",[Vector2(430,1270),Vector2(410,1450),Vector2(420,1570),Vector2(480,1660),Vector2(650,1745),Vector2(850,1760),Vector2(1190,1730),Vector2(1540,1760),Vector2(1900,1740),Vector2(2110,1690),Vector2(2160,1460),Vector2(2300,1350)],42)
	road("SouthSquareLane",[Vector2(1500,960),Vector2(1550,1150),Vector2(1430,1230),Vector2(1210,1390),Vector2(1190,1730)],48)
	road("ArtisanLink",[Vector2(1980,820),Vector2(1980,1000),Vector2(2060,1200),Vector2(2060,1320)],40)
	road("WestCrossLane",[Vector2(650,940),Vector2(640,1110),Vector2(690,1280),Vector2(840,1360)],32)
	polygon(roads,"Square",PackedVector2Array([Vector2(1310,815),Vector2(1420,765),Vector2(1620,800),Vector2(1690,925),Vector2(1580,1035),Vector2(1380,1020),Vector2(1300,910)]),Color("77705c"))
	var home_links := [Vector2(600,570),Vector2(790,800),Vector2(400,1010),Vector2(1210,1235),Vector2(1040,555),Vector2(1790,900),Vector2(1830,1740),Vector2(840,1360),Vector2(2060,1200),Vector2(790,960),Vector2(1210,1550),Vector2(650,1745)]
	for i in range(HOUSES.size()):
		var data: Array = HOUSES[i]
		var house := building(residential,data[0],data[2],data[3],data[4],data[1],i)
		house.add_to_group("simulation_houses",true)
		var x: float = -data[3].x*0.28 if data[1]=="L" else 0.0
		var approach: Vector2 = data[2] + Vector2(x,data[3].y/2+42).rotated(data[4])
		homes.append(approach)
		marker("Home"+str(i+1),approach,false,true)
		entrance_path(house,"HomePath"+str(i+1),home_links[i])
		if i in [0,3,7]:
			var center: Vector2 = data[2]+Vector2(-100,25)
			field("Garden"+str(i),PackedVector2Array([center+Vector2(-32,-29),center+Vector2(32,-29),center+Vector2(29,29),center+Vector2(-32,29)]),i%2==0,Color("505039"))
		if i in [1,6,11]:
			building(agricultural,"HomeShed"+str(i),data[2]+(Vector2(-180,30) if i==1 else Vector2(-145,-35)),Vector2(48,46),data[4],"shed",i)

	building(public_buildings,"Church",Vector2(1420,380),Vector2(224,260),0,"church")
	label_at(details,"ChurchLabel","Часовня",Vector2(1375,215))
	road("CemeteryAccess",[Vector2(1420,557),Vector2(1510,520),Vector2(1560,420)],23,PATH)
	road("CemeteryWest",[Vector2(1560,420),Vector2(1560,120)],23,PATH)
	road("CemeteryNorth",[Vector2(1560,120),Vector2(1880,120),Vector2(1970,300)],23,PATH)
	road("CemeteryEast",[Vector2(1970,300),Vector2(1900,420),Vector2(1560,420)],23,PATH)
	for i in range(8):
		var at := Vector2(1615+(i%4)*85+(i%2)*7,165+(i/4)*105)
		var grave := solid(public_buildings,"Grave"+str(i),at,rectangle(Vector2(14,20)),Color("7b7e70"),(i%3-1)*0.12)
		stroke(grave,"Cross",PackedVector2Array([Vector2(-4,-3),Vector2(4,-3)]),Color("434a43"),2)
	marker("Church",Vector2(1420,557),true)
	road("ChapelEntrance",[Vector2(1420,511),Vector2(1420,557)],24,PATH,true)
	marker("Cemetery",Vector2(1730,355))
	var well := solid(public_buildings,"Well",Vector2(1430,868),rectangle(Vector2(42,40)),Color("929280"))
	patch(well,"Water",Vector2.ZERO,Vector2(26,24),Color("2c4245"))
	stroke(well,"Beam",PackedVector2Array([Vector2(-22,-5),Vector2(22,-5)]),Color("534731"),6)
	var bell := solid(public_buildings,"AlarmBell",Vector2(1620,850),rectangle(Vector2(32,42)),Color("534a38"))
	patch(bell,"LeftPost",Vector2(-12,0),Vector2(6,38),Color("a08e68"))
	patch(bell,"RightPost",Vector2(12,0),Vector2(6,38),Color("a08e68"))
	polygon(bell,"Bell",PackedVector2Array([Vector2(-7,-10),Vector2(7,-10),Vector2(11,8),Vector2(-11,8)]),Color("b0a070"))
	label_at(details,"BellLabel","Колокол",Vector2(1590,805))
	marker("Square",Vector2(1520,947),true)
	marker("Well",Vector2(1410,940),true)
	marker("Bell",Vector2(1615,915),true)

	field("WestField",PackedVector2Array([Vector2(140,1410),Vector2(315,1390),Vector2(345,1660),Vector2(155,1695)]),true)
	field("EastField",PackedVector2Array([Vector2(830,1450),Vector2(1000,1430),Vector2(1065,1660),Vector2(865,1670)]),false)
	field("SouthField",PackedVector2Array([Vector2(850,1810),Vector2(1040,1802),Vector2(1045,1860),Vector2(1108,1870),Vector2(1130,1940),Vector2(790,1930)]),true)
	field("Vegetables",PackedVector2Array([Vector2(330,1810),Vector2(670,1810),Vector2(670,1930),Vector2(330,1930)]),false,Color("505039"))
	var barn := building(agricultural,"Barn",Vector2(545,1200),Vector2(140,100),-0.10,"barn",2)
	entrance_path(barn,"BarnPath",Vector2(560,1320))
	building(agricultural,"FieldStore",Vector2(1100,1810),Vector2(72,54),0.16,"shed",1)
	marker("FieldsWest",Vector2(270,1510))
	marker("FieldsEast",Vector2(940,1540))
	marker("FieldsSouth",Vector2(930,1850))
	marker("Barn",Vector2(550,1300))
	marker("FarmLane",Vector2(800,1750))
	marker("Vegetables",Vector2(488,1870))
	road("FieldWestPath",[Vector2(340,1510),nearest_street(Vector2(410,1510))],24,PATH,true)
	road("FieldEastPath",[Vector2(1045,1565),Vector2(1100,1570),nearest_street(Vector2(1195,1560))],24,PATH,true)
	road("FieldSouthPath",[Vector2(980,1799),nearest_street(Vector2(980,1740))],22,PATH,true)
	road("VegetablePath",[Vector2(488,1802),nearest_street(Vector2(488,1788))],22,PATH,true)
	label_at(details,"FieldLabel","Поля",Vector2(225,1340))

	var smith := building(workshops,"Blacksmith",Vector2(2250,680),Vector2(180,130),-0.12,"blacksmith",1)
	var carpenter := building(workshops,"Carpenter",Vector2(2420,795),Vector2(145,110),0.12,"workshop",2)
	var weaver := building(workshops,"Weaver",Vector2(2175,1090),Vector2(130,102),-0.17,"workshop",0)
	var storage := building(workshops,"Storage",Vector2(2440,1090),Vector2(120,80),0.08,"storage",3)
	patch(details,"WorkYard",Vector2(2260,815),Vector2(155,110),Color("5a5543"))
	var anvil := solid(workshops,"Anvil",Vector2(2295,795),rectangle(Vector2(26,16)),Color("727772"))
	patch(anvil,"Neck",Vector2.ZERO,Vector2(12,10),Color("444a45"))
	solid(workshops,"Timber",Vector2(2470,875),rectangle(Vector2(60,22)),Color("746344"),0.08)
	marker("SmithYard",Vector2(2230,805))
	marker("Carpenter",Vector2(2400,910))
	marker("Weaver",Vector2(2180,1190))
	marker("Storage",Vector2(2435,1180))
	label_at(details,"SmithLabel","Кузница",Vector2(2205,580))
	entrance_path(smith,"SmithPath",Vector2(2250,940))
	entrance_path(carpenter,"WorkshopPath",Vector2(2400,970))
	entrance_path(weaver,"WeaverPath",Vector2(2060,1200))
	entrance_path(storage,"StoragePath",Vector2(2480,1230))

	var tavern := building(public_buildings,"Tavern",Vector2(1740,1420),Vector2(180,130),-0.08,"tavern",0)
	var guard_post := building(public_buildings,"GuardPost",Vector2(2310,1510),Vector2(130,150),0.06,"guard",3)
	label_at(details,"TavernLabel","Таверна",Vector2(1690,1500))
	label_at(details,"GuardLabel","Пост стражи",Vector2(2250,1605))
	marker("Tavern",Vector2(1715,1300),true)
	marker("GuardYard",Vector2(2230,1640))
	marker("GuardRoad",Vector2(2300,1380))
	marker("NorthRoad",Vector2(1900,550))
	marker("WestRoad",Vector2(650,940))
	marker("SouthRoad",Vector2(1540,1760))
	entrance_path(tavern,"TavernApproach",Vector2(1630,1290),[Vector2(1600,1530),Vector2(1590,1360)])
	entrance_path(guard_post,"GuardDoorPath",Vector2(2140,1620),[Vector2(2290,1640)])

	build_river()
	# Large trees use the same visible outline for collision and sight occlusion.
	var groves := [Vector2(240,250),Vector2(580,185),Vector2(1090,155),Vector2(2100,175),Vector2(2370,285),Vector2(200,1110),Vector2(1330,1860),Vector2(2030,1840),Vector2(2500,1750)]
	for g in range(groves.size()):
		for j in range(3 if g in [6,7] else 5):
			var at: Vector2 = groves[g]+Vector2((j%3-1)*125+(g%2)*9,(j/3)*120)+Vector2(rng.randf_range(-7,7),rng.randf_range(-7,7))
			if g==3 and j==3: at += Vector2(35,70) # Clear the cemetery path and fence.
			tree_at("Grove"+str(g)+"Tree"+str(j),at,22+(g+j)%5)
	tree_at("FarBankOak",Vector2(2900,500),18)
	tree_at("FarBankAsh",Vector2(2900,1450),18)
	for i in range(12):
		var at := Vector2(320+i*184,1850-(i%3)*29)
		if i<3: at = [Vector2(250,1785),Vector2(260,1910),Vector2(720,1920)][i]
		if i<3 or i>5: patch(details,"Bush"+str(i),at,Vector2(24,17),Color("354831"))
	build_fences()
	var bounds := container(region,"Boundaries")
	for entry in [[Vector2(1500,6),Vector2(3000,12)],[Vector2(1500,1994),Vector2(3000,12)],[Vector2(6,1000),Vector2(12,1976)],[Vector2(2994,1000),Vector2(12,1976)]]:
		solid(bounds,"Edge"+str(bounds.get_child_count()),entry[0],rectangle(entry[1]),Color("323d30"))
	# Reuse the existing HUD and camera configuration, leaving the source intact.
	var source := load("res://scenes/test_map.tscn").instantiate() as Node2D
	var hud := source.get_node("CanvasLayer").duplicate()
	attach(village,hud,"CanvasLayer")
	assign_owners(hud)
	var alert := load("res://scenes/village_alert.tscn").instantiate()
	attach(village, alert, "VillageAlert")
	var camera := source.get_node("Camera2D").duplicate() as Camera2D
	attach(village,camera,"Camera2D")
	camera.position = Vector2(650,1000)
	camera.map_bounds = Rect2(0,0,3000,2000)
	camera.min_zoom = 0.45
	camera.zoom = Vector2.ONE
	source.placement.free() # Source was inspected off-tree, so _ready never owns it.
	source.free()
	# Bake only static layer-1 descendants, using the established clearance.
	var navigation := NavigationPolygon.new()
	navigation.agent_radius = 26.0
	navigation.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation.parsed_collision_mask = 1
	navigation.add_outline(PackedVector2Array([Vector2(12,12),Vector2(2988,12),Vector2(2988,1988),Vector2(12,1988)]))
	region.navigation_polygon = navigation
	# No map _ready/AI needs to execute during authoring.
	root.add_child(village)
	region.bake_navigation_polygon(false)
	if navigation.get_polygon_count()==0:
		push_error("Mission 1 navigation bake failed")
		quit(1)
		return
	populate()
	var error := ResourceSaver.save(navigation,NAVIGATION)
	navigation.take_over_path(NAVIGATION)
	village.set_script(load("res://scripts/test_map.gd"))
	var packed := PackedScene.new()
	if error == OK: error = packed.pack(village)
	if error == OK: error = ResourceSaver.save(packed,OUTPUT)
	print("Mission 1 build: ",error_string(error),"; navigation polygons: ",navigation.get_polygon_count())
	village.placement.free()
	village.set_script(null)
	village.queue_free()
	quit(0 if error==OK else 1)

func assign_owners(parent: Node) -> void:
	for child in parent.get_children():
		child.owner = village
		assign_owners(child)

func read_npc_preferences() -> void:
	# Preserve Inspector tweaks made after the first build, including debug flags.
	if not ResourceLoader.exists(OUTPUT): return
	var previous: Node2D = load(OUTPUT).instantiate()
	for npc in previous.get_node("Villagers").get_children():
		var preferences := {"color":npc.get_node("Polygon2D").color,"exports":{},"debug":{}}
		for property in npc.get_property_list():
			var property_name: String = property.name
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE and not property_name.ends_with("_path"):
				preferences.exports[property_name] = npc.get(property_name)
		for component in ["ThreatDetection","ThreatReaction","LocalWarning"]:
			preferences.debug[component] = npc.get_node(component).debug_enabled
		npc_preferences[str(npc.name)] = preferences
	previous.placement.free()
	previous.free()

func activity_spot(parent: Node2D, title: String, base: Vector2, social := false, shelter := false) -> Marker2D:
	var mesh := region.navigation_polygon
	var vertices := mesh.vertices
	# Resolve only at authoring time. Static navmesh supplies 26-unit clearance;
	# all personal endpoints are separated by at least 36 units across the map.
	for attempt in range(1024):
		var at := base+Vector2.from_angle(attempt*2.3999632297)*sqrt(float(attempt))*10.0
		var available := true
		for other in activity_positions:
			if other.distance_to(at)<36.0:
				available = false
				break
		if not available: continue
		var on_mesh := false
		for i in range(mesh.get_polygon_count()):
			var outline := PackedVector2Array()
			for index in mesh.get_polygon(i): outline.append(vertices[index])
			if Geometry2D.is_point_in_polygon(at,outline):
				on_mesh = true
				break
		if not on_mesh: continue
		activity_positions.append(at)
		var point := Marker2D.new()
		point.position = at
		attach(parent,point,title)
		if social: point.add_to_group("civilian_social_points",true)
		if shelter: point.add_to_group("civilian_shelter_points",true)
		return point
	push_error("No clear activity slot near "+str(base))
	quit(1)
	return null

func build_river() -> void:
	var river := container(region,"River")
	# Full river reaches both map edges. Only the bridge gap is walkable.
	var centers := [Vector2(2725,-30),Vector2(2660,200),Vector2(2715,460),Vector2(2650,720),Vector2(2710,960),Vector2(2740,1120),Vector2(2740,1240),Vector2(2705,1430),Vector2(2770,1680),Vector2(2700,2030)]
	var outline := PackedVector2Array()
	for at in centers: outline.append(at+Vector2(-43,0))
	for i in range(centers.size()-1,-1,-1): outline.append(centers[i]+Vector2(43,0))
	var map_outline := PackedVector2Array([Vector2.ZERO,Vector2(3000,0),Vector2(3000,2000),Vector2(0,2000)])
	polygon(roads,"RiverBanks",Geometry2D.intersect_polygons(Geometry2D.offset_polygon(outline,13)[0],map_outline)[0],Color("60634c"))
	polygon(roads,"RiverWater",Geometry2D.intersect_polygons(outline,map_outline)[0],Color("304b50"))
	for i in range(centers.size()-1):
		var a: Vector2 = centers[i]
		var b: Vector2 = centers[i+1]
		if i==5: continue # 120-unit bridge deck; bake leaves 68-unit clear lane.
		var vertices := PackedVector2Array([a+Vector2(-43,0),a+Vector2(43,0),b+Vector2(43,0),b+Vector2(-43,0)])
		# Water has physical/nav exclusion without duplicating the visual fill.
		var water := solid(river,"DeepWater"+str(i),Vector2.ZERO,vertices,Color("304b50"))
		water.get_node("Footprint").hide()
	var bridge := container(roads,"WoodenBridge")
	patch(bridge,"Deck",Vector2(2740,1180),Vector2(158,120),Color("796c4e"))
	for x in range(2663,2820,12):
		patch(bridge,"Plank"+str(x),Vector2(x,1180),Vector2(3,116),Color("524b39"))
	var rails := container(river,"BridgeRails")
	for y in [1121,1239]:
		solid(rails,"Rail"+str(y),Vector2(2740,y),rectangle(Vector2(158,6)),Color("a08b61"))
	marker("BridgeWest",Vector2(2600,1180))
	marker("BridgeEast",Vector2(2880,1180))
	marker("FarBank",Vector2(2890,900))
	var shed := building(river,"RiverStore",Vector2(2890,670),Vector2(48,50),0,"shed",2)
	road("FarBankTrail",[Vector2(2910,1180),Vector2(2880,1040),Vector2(2890,900),Vector2(2890,696)],28,PATH,true,str(village.get_path_to(shed)))
	label_at(details,"RiverStoreLabel","Речной склад",Vector2(2840,615))
	label_at(details,"BridgeLabel","Мост",Vector2(2715,1265))

func populate() -> void:
	var residents := container(village,"Villagers")
	var routes := container(village,"ResidentRoutes")
	var spawn_points := [Vector2(590,580),Vector2(790,760),Vector2(440,930),Vector2(1180,1180),Vector2(1040,555),Vector2(1860,805),Vector2(1875,1740),Vector2(790,1220),Vector2(1980,1190),Vector2(1190,1010),Vector2(1230,1550),Vector2(750,1710),Vector2(260,1510),Vector2(940,1540),Vector2(950,1850),Vector2(550,1430),Vector2(800,1750),Vector2(1510,955),Vector2(1410,940),Vector2(2230,805),Vector2(2420,910),Vector2(2180,1190),Vector2(2435,1180),Vector2(2130,860),Vector2(2160,1480),Vector2(2300,1380),Vector2(2060,1320),Vector2(1900,550),Vector2(1630,960),Vector2(1420,557)]
	var peasant_jobs := ["Home1","Home2","Home3","Barn","Home5","Well","SouthRoad","Barn","Home9","Home10","Home11","FarmLane","FieldsWest","FieldsEast","FieldsSouth","Barn","Vegetables","Square","Bell"]
	var peasant_districts := ["northwest","northwest","northwest","farm","northwest","center","south","farm","artisan","northwest","south","farm","farm","farm","farm","farm","farm","center","center"]
	var home_districts := ["northwest","northwest","northwest","center","northwest","center","south","farm","artisan","northwest","south","farm"]
	var meeting_places := {"northwest":Vector2(700,610),"center":Vector2(1510,985),"farm":Vector2(740,1460),"artisan":Vector2(2260,850),"south":Vector2(1510,1620),"guard":Vector2(2260,1640),"church":Vector2(1590,500)}
	var artisan_jobs := ["SmithYard","Carpenter","Weaver","Storage","SmithYard"]
	var guard_jobs := ["GuardYard","GuardRoad","Square","NorthRoad","GuardRoad"]
	for i in range(30):
		var npc := load("res://scenes/villager.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as CharacterBody2D
		var role := "peasant" if i<19 else ("artisan" if i<24 else ("guard" if i<29 else "priest"))
		attach(residents,npc,role.capitalize()+str(i+1))
		village.set_editable_instance(npc,true)
		npc.position = spawn_points[i]
		npc.set_meta("village_role",role)
		var job: String
		var district: String
		if i<19:
			npc.civilian_profile = "Peasant"
			job = peasant_jobs[i]
			district = peasant_districts[i]
		elif i<24:
			npc.civilian_profile = "Craftsman"
			job = artisan_jobs[i-19]
			district = "artisan"
		else:
			# These roles have no dedicated AI yet; reuse normal activities.
			npc.civilian_profile = "Villager"
			job = guard_jobs[i-24] if i<29 else "Church"
			district = "guard" if i<29 else "church"
			npc.home_weight = 15
			npc.work_weight = 65
			npc.social_weight = 15
			npc.wander_weight = 5
		var route := container(routes,"Route%02d"%(i+1))
		var home_base: Vector2 = homes[i%12]
		activity_spot(route,"Home",home_base,false,true)
		activity_spot(route,"Work",points.get_node(job).position)
		activity_spot(route,"SocialA",meeting_places[district],true)
		activity_spot(route,"SocialB",meeting_places[home_districts[i%12]],true)
		activity_spot(route,"Walk",nearest_street(home_base))
		npc.points_of_interest_path = NodePath("../../ResidentRoutes/"+str(route.name))
		npc.home_point_path = NodePath(str(npc.points_of_interest_path)+"/Home")
		npc.work_point_path = NodePath(str(npc.points_of_interest_path)+"/Work")
		npc.set_meta("activity_district",district)
		npc.get_node("Polygon2D").color = {"peasant":Color("b7ad87"),"artisan":Color("a68764"),"guard":Color("879ca0"),"priest":Color("c4bcac")}[role]
		npc.get_node("ThreatDetection").debug_enabled = false
		npc.get_node("ThreatReaction").debug_enabled = false
		if npc_preferences.has(str(npc.name)):
			var preferences: Dictionary = npc_preferences[str(npc.name)]
			for property_name in preferences.exports: npc.set(property_name,preferences.exports[property_name])
			npc.get_node("Polygon2D").color = preferences.color
			for component in preferences.debug: npc.get_node(component).debug_enabled = preferences.debug[component]
	var zombies := container(village,"Zombies")
	for i in range(3):
		var zombie := load("res://scenes/zombie.tscn").instantiate() as CharacterBody2D
		attach(zombies,zombie,"Zombie"+str(i+1))
		zombie.position = Vector2(170,900+i*45)
