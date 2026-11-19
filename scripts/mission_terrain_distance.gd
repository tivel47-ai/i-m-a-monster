extends RefCounted

const TEXEL_SIZE := 2.5
const PADDING := 74.0
const STEP := 4
const DIAGONAL := 6
const LIMIT := 127


static func build(contours: Array[PackedVector2Array]) -> Dictionary:
	var bounds := Rect2(contours[0][0], Vector2.ZERO)
	for outline in contours:
		for point in outline:
			bounds = bounds.expand(point)
	bounds = bounds.grow(PADDING)
	var size := Vector2i((bounds.size / TEXEL_SIZE).ceil())
	bounds.size = Vector2(size) * TEXEL_SIZE

	var coverage := Image.create_empty(size.x, size.y, false, Image.FORMAT_L8)
	var to_texel := Transform2D(0.0, Vector2.ONE / TEXEL_SIZE, 0.0, -bounds.position / TEXEL_SIZE)
	for outline in contours:
		_rasterize(coverage, to_texel * outline)
	var occupied := coverage.get_data()
	var distance := PackedByteArray()
	distance.resize(occupied.size())
	distance.fill(LIMIT)
	_seed_edges(occupied, distance, size)
	_sweep(distance, size, false)
	_sweep(distance, size, true)

	for index in range(distance.size()):
		distance[index] = 128 + distance[index] if occupied[index] else 128 - distance[index]
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, distance)
	return {"bounds": bounds, "texture": ImageTexture.create_from_image(image)}


static func _rasterize(coverage: Image, outline: PackedVector2Array) -> void:
	# Fill scanlines at texel centers so overlaps are part of the same silhouette.
	var edges: Array[Vector4] = []
	var top := INF
	var bottom := -INF
	for index in range(outline.size()):
		var start := outline[index]
		var end := outline[(index + 1) % outline.size()]
		if is_equal_approx(start.y, end.y):
			continue
		if end.y < start.y:
			var swap := start
			start = end
			end = swap
		top = minf(top, start.y)
		bottom = maxf(bottom, end.y)
		edges.append(Vector4(start.x, start.y, end.y, (end.x - start.x) / (end.y - start.y)))
	if edges.is_empty():
		return
	for row in range(ceili(top - 0.5), ceili(bottom - 0.5)):
		var y := row + 0.5
		var crossings := PackedFloat32Array()
		for edge in edges:
			if y >= edge.y and y < edge.z:
				crossings.append(edge.x + (y - edge.y) * edge.w)
		crossings.sort()
		for index in range(0, crossings.size() - 1, 2):
			var start := ceili(crossings[index] - 0.5)
			var end := ceili(crossings[index + 1] - 0.5)
			coverage.fill_rect(Rect2i(start, row, end - start, 1), Color.WHITE)


static func _seed_edges(occupied: PackedByteArray, distance: PackedByteArray, size: Vector2i) -> void:
	# Put a seed half a texel from the boundary on both sides before propagating distances.
	for row in range(1, size.y):
		for column in range(1, size.x):
			var index := row * size.x + column
			var inside := occupied[index]
			if inside != occupied[index - 1]:
				distance[index] = 2
				distance[index - 1] = 2
			if inside != occupied[index - size.x]:
				distance[index] = 2
				distance[index - size.x] = 2


static func _sweep(distance: PackedByteArray, size: Vector2i, backward: bool) -> void:
	var direction := -1 if backward else 1
	var first_row := size.y - 2 if backward else 1
	var after_last := 0 if backward else size.y - 1
	var first_column := size.x - 2 if backward else 1
	var column_limit := 0 if backward else size.x - 1
	var previous_row := direction * size.x
	# Padding keeps the silhouettes clear of the outermost row and column.
	for row in range(first_row, after_last, direction):
		for column in range(first_column, column_limit, direction):
			var index := row * size.x + column
			var left := index - direction
			var up := index - previous_row
			var nearest := mini(distance[left], distance[up]) + STEP
			var corner := mini(distance[up - 1], distance[up + 1]) + DIAGONAL
			distance[index] = mini(distance[index], mini(nearest, corner))
