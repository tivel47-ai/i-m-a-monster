extends SceneTree

const GUARD_VISUAL := preload("res://scripts/guard_visual.gd")


func _initialize() -> void:
	_validate_spear_palette.call_deferred()


func _validate_spear_palette() -> void:
	var actor := Node2D.new()
	var timer := Timer.new()
	timer.name = "EncounterAttackTimer"
	actor.add_child(timer)
	var visual := GUARD_VISUAL.new()
	visual.appearance = GUARD_VISUAL.SPEAR
	actor.add_child(visual)
	root.add_child(actor)
	visual.set_physics_process(false)
	var atlas := visual.texture.get_image()
	var failures := 0
	for direction in range(8):
		visual._direction = direction
		visual._show_frame(0, GUARD_VISUAL.DIRECTIONAL_IDLE_ROW)
		var idle_region := Rect2i(visual.region_rect)
		var idle_flip := visual.flip_h
		visual._show_frame(0, GUARD_VISUAL.DIRECTIONAL_ATTACK_ROW)
		var attack_region := Rect2i(visual.region_rect)
		var idle := atlas.get_region(idle_region)
		var windup := atlas.get_region(attack_region)
		if visual.flip_h != idle_flip or not _same_centered_pose(idle, windup):
			failures += 1
			push_error("Spearman stance flashes at the start of windup in direction %d" % direction)
	print("Spearman stance to windup palette: %d/8 directions passed." % (8 - failures))
	actor.free()
	quit(1 if failures else 0)


func _same_centered_pose(idle: Image, windup: Image) -> bool:
	var offset := (windup.get_width() - idle.get_width()) >> 1
	for y in range(windup.get_height()):
		for x in range(windup.get_width()):
			var expected := Color.TRANSPARENT
			if x >= offset and x < offset + idle.get_width():
				expected = idle.get_pixel(x - offset, y)
			var actual := windup.get_pixel(x, y)
			if actual.a != expected.a or (actual.a > 0.0 and actual != expected):
				return false
	return true
