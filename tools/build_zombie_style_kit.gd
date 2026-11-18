extends SceneTree

# Deterministic extraction of the approved painting. No generative service.
# Run: Godot --headless --path . --script tools/build_zombie_style_kit.gd
const SOURCE := "res://assets/ui/zombie_development_grave_roots.png"
const LEGACY_SYMBOLS := "res://assets/ui/zombie_perk_medallions.png"
const OUTPUT := "res://assets/ui/zombie_style/"
const SYMBOLS := ["grasping_tendons", "infectious_saliva", "bone_growths", "hound",
	"carrier", "dead_fortitude", "hungry_spasm"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var symbol_source := ""
	var symbol_output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--symbol-source="):
			symbol_source = argument.trim_prefix("--symbol-source=")
		if argument.begins_with("--symbol-output="):
			symbol_output = argument.trim_prefix("--symbol-output=")
	if not symbol_source.is_empty() or not symbol_output.is_empty():
		if symbol_source.is_empty() or not symbol_output.begins_with(OUTPUT) or not symbol_output.ends_with(".png"):
			push_error("Supply --symbol-source and --symbol-output=res://assets/ui/zombie_style/<id>.png")
			quit(1)
			return
		var symbol := read_image(symbol_source)
		if symbol.is_empty():
			quit(1)
			return
		quit(0 if emblem(symbol).save_png(symbol_output) == OK else 1)
		return
	var source := read_image(SOURCE)
	var frame_polygon := PackedVector2Array([
		Vector2(483, 189), Vector2(496, 205), Vector2(520, 197), Vector2(527, 213),
		Vector2(550, 209), Vector2(541, 232), Vector2(562, 245), Vector2(550, 262),
		Vector2(554, 283), Vector2(536, 286), Vector2(541, 308), Vector2(520, 304),
		Vector2(510, 326), Vector2(491, 316), Vector2(477, 330), Vector2(463, 315),
		Vector2(439, 323), Vector2(438, 302), Vector2(417, 300), Vector2(426, 280),
		Vector2(405, 276), Vector2(417, 259), Vector2(403, 245), Vector2(425, 236),
		Vector2(419, 216), Vector2(440, 221), Vector2(451, 199), Vector2(468, 209)])
	var frame := cutout(source, Rect2i(399, 174, 168, 168), frame_polygon, Vector2(483, 258), Vector2(54, 54))
	# Clone unmarked dark bark into the former claw emblem, keeping the painted rim.
	for y in frame.get_height():
		for x in frame.get_width():
			var radius := Vector2(x - 84, y - 84).length()
			if radius < 43.0:
				var bark := source.get_pixel(442 + posmod(x, 14), 274 + posmod(y, 15))
				var dark := Color(bark.r * 0.60, bark.g * 0.60, bark.b * 0.60, 1.0)
				var color := frame.get_pixel(x, y).lerp(dark, 1.0 - smoothstep(33.0, 43.0, radius))
				frame.set_pixel(x, y, color)
	frame.save_png(OUTPUT + "perk_frame.png")

	# The polygon follows the central mass only, excluding every outgoing root.
	var core_polygon := PackedVector2Array([
		Vector2(725, 354), Vector2(749, 329), Vector2(774, 317), Vector2(795, 334),
		Vector2(821, 337), Vector2(846, 331), Vector2(875, 351), Vector2(908, 349),
		Vector2(939, 373), Vector2(959, 389), Vector2(985, 404), Vector2(1000, 434),
		Vector2(1026, 448), Vector2(1021, 476), Vector2(1038, 501), Vector2(1024, 526),
		Vector2(1037, 547), Vector2(1004, 567), Vector2(983, 590), Vector2(950, 584),
		Vector2(922, 606), Vector2(886, 601), Vector2(858, 627), Vector2(824, 606),
		Vector2(789, 611), Vector2(760, 593), Vector2(730, 594), Vector2(716, 571),
		Vector2(687, 570), Vector2(685, 546), Vector2(655, 533), Vector2(670, 505),
		Vector2(647, 491), Vector2(668, 465), Vector2(658, 442), Vector2(681, 423),
		Vector2(684, 395), Vector2(710, 399), Vector2(704, 371)])
	cutout(source, Rect2i(625, 305, 440, 335), core_polygon, Vector2(838, 467), Vector2(139, 112)).save_png(OUTPUT + "infection_core.png")

	# Preserve complete painted bends in two dimensions. Straightening a tiny
	# slice destroys the woven bark and stretches it into a blurred rope.
	painted_root(source, PackedVector2Array([
		Vector2(525, 308), Vector2(537, 329), Vector2(534, 348), Vector2(519, 371),
		Vector2(513, 392), Vector2(524, 413), Vector2(549, 431), Vector2(578, 440),
		Vector2(606, 442), Vector2(635, 453), Vector2(662, 465)]), "painted_root.png")
	painted_root(source, PackedVector2Array([
		Vector2(1049, 532), Vector2(1070, 540), Vector2(1080, 555), Vector2(1077, 574),
		Vector2(1065, 596), Vector2(1063, 613), Vector2(1079, 628), Vector2(1103, 636),
		Vector2(1130, 638), Vector2(1150, 650), Vector2(1168, 666)]), "painted_root_b.png")
	painted_root(source, PackedVector2Array([
		Vector2(640, 530), Vector2(600, 526), Vector2(565, 532), Vector2(533, 526),
		Vector2(499, 527), Vector2(473, 534), Vector2(449, 549), Vector2(424, 566),
		Vector2(398, 581), Vector2(369, 592), Vector2(338, 594), Vector2(301, 592),
		Vector2(266, 593), Vector2(237, 612)]), "painted_root_long.png")

	# First three symbols retain their original shape; all symbols share one bone palette.
	emblem(source.get_region(Rect2i(453, 221, 63, 76))).save_png(OUTPUT + "tough_flesh.png")
	emblem(source.get_region(Rect2i(228, 74, 88, 88))).save_png(OUTPUT + "brute.png")
	emblem(source.get_region(Rect2i(1183, 635, 64, 84))).save_png(OUTPUT + "call_of_hunger.png")
	# Recover just the symbols from the previous attempt, discarding its foreign rims.
	var legacy := read_image(LEGACY_SYMBOLS)
	var cell := Vector2(legacy.get_width() / 4.0, legacy.get_height() / 2.0)
	for index in SYMBOLS.size():
		var origin := Vector2(index % 4, index / 4) * cell
		var region := Rect2i(Vector2i(origin + cell * 0.16), Vector2i(cell * 0.68))
		emblem(legacy.get_region(region)).save_png(OUTPUT + SYMBOLS[index] + ".png")
	print("Extracted original core, shared frame, three painted roots and ten independent symbols into ", OUTPUT)
	quit()


func sample(image: Image, point: Vector2) -> Color:
	var base := Vector2i(point.floor())
	var fraction := point - Vector2(base)
	var a := image.get_pixel(clampi(base.x, 0, image.get_width() - 1), clampi(base.y, 0, image.get_height() - 1))
	var b := image.get_pixel(clampi(base.x + 1, 0, image.get_width() - 1), clampi(base.y, 0, image.get_height() - 1))
	var c := image.get_pixel(clampi(base.x, 0, image.get_width() - 1), clampi(base.y + 1, 0, image.get_height() - 1))
	var d := image.get_pixel(clampi(base.x + 1, 0, image.get_width() - 1), clampi(base.y + 1, 0, image.get_height() - 1))
	return a.lerp(b, fraction.x).lerp(c.lerp(d, fraction.x), fraction.y)


func painted_root(source: Image, points: PackedVector2Array, filename: String) -> void:
	var axis := (points[-1] - points[0]).normalized()
	var side := axis.orthogonal()
	var length := points[0].distance_to(points[-1])
	var patch := Image.create(ceili(length) + 1, 224, false, Image.FORMAT_RGBA8)
	var path := Curve2D.new()
	path.bake_interval = 0.5
	for point in points:
		path.add_point(point)
	for index in range(1, points.size() - 1):
		var tangent := (points[index + 1] - points[index - 1]) * 0.17
		path.set_point_in(index, -tangent)
		path.set_point_out(index, tangent)
	for x in patch.get_width():
		for y in patch.get_height():
			var point := points[0] + axis * (length * x / (patch.get_width() - 1.0)) + side * (y - 111.5)
			var distance := point.distance_to(path.get_closest_point(point))
			if distance >= 32.0:
				continue
			var color := sample(source, point)
			# Remove green mist while retaining brown bark, bone highlights and
			# dark crevices. The source web's real apertures stay transparent.
			var ink := maxf(1.0 - smoothstep(0.006, 0.028, color.g - color.r), 1.0 - smoothstep(0.10, 0.16, color.g))
			color.a = ink * (1.0 - smoothstep(20.0, 32.0, distance))
			if filename == "painted_root_long.png":
				# This distant bough is tinted by the original green mist. Its
				# traced solid stem must not be mistaken for that background.
				color.a = maxf(color.a, 1.0 - smoothstep(6.0, 10.0, distance))
				color.r *= 0.96
				color.g *= 0.91
				color.b *= 0.84
			patch.set_pixel(x, y, color)
	patch.save_png(OUTPUT + filename)


func read_image(path: String) -> Image:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Could not read style source: " + path)
	return image


func cutout(source: Image, region: Rect2i, polygon: PackedVector2Array, center: Vector2, solid_radius: Vector2) -> Image:
	var result := Image.create(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	var background := Color(0.26, 0.30, 0.275)
	for y in region.size.y:
		for x in region.size.x:
			var point := Vector2(region.position) + Vector2(x, y)
			if not Geometry2D.is_point_in_polygon(point, polygon):
				continue
			var edge := INF
			for index in polygon.size():
				edge = minf(edge, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])))
			var color := sample(source, point)
			var contrast := Vector3(color.r - background.r, color.g - background.g, color.b - background.b).length()
			var inner := 1.0 - smoothstep(0.85, 1.10, ((point - center) / solid_radius).length())
			var ink := maxf(1.0 - smoothstep(0.008, 0.036, color.g - color.r), 1.0 - smoothstep(0.13, 0.24, color.g))
			var feather := 10.0 if region.size.x > 200 else 4.0
			color.a = smoothstep(0.0, feather, edge) * maxf(inner, smoothstep(0.04, 0.15, contrast) * ink)
			result.set_pixel(x, y, color)
	return result


func emblem(source: Image) -> Image:
	var result := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var region := source.duplicate() as Image
	var fit := Vector2(source.get_width(), source.get_height()) * (112.0 / maxi(source.get_width(), source.get_height()))
	region.resize(maxi(1, roundi(fit.x)), maxi(1, roundi(fit.y)), Image.INTERPOLATE_LANCZOS)
	var offset := (Vector2i(128, 128) - region.get_size()) / 2
	for y in region.get_height():
		for x in region.get_width():
			var raw := region.get_pixel(x, y)
			var alpha := smoothstep(0.24, 0.38, raw.g) * raw.a
			var light := clampf((raw.g - 0.20) / 0.60, 0.0, 1.0)
			var color := Color("292a22").lerp(Color("e1d9b8"), light)
			color.a = alpha
			result.set_pixel(x + offset.x, y + offset.y, color)
	return result
