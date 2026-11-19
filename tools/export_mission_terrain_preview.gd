extends SceneTree

const MISSION_PATH := "res://scenes/village_simulation_map.tscn"
const PREVIEW_PATH := "res://assets/maps/mission_01_terrain.png"
const PREVIEW_SIZE := Vector2i(1536, 1024)


func _initialize() -> void:
	call_deferred("_export_preview")


func _export_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The terrain preview needs a graphical renderer.")
		quit(1)
		return

	var arguments := OS.get_cmdline_user_args()
	var destination := PREVIEW_PATH if arguments.is_empty() else arguments[0]
	var scene := load(MISSION_PATH) as PackedScene
	var mission := scene.instantiate() as Node2D
	var map_size: Vector2 = mission.get_meta("map_size")
	var camera := mission.get_node("Camera2D") as Camera2D
	camera.enabled = false

	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.world_2d = World2D.new()
	viewport.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(viewport)
	viewport.add_child(mission)
	viewport.canvas_transform = Transform2D(0.0, Vector2(PREVIEW_SIZE) / map_size, 0.0, Vector2.ZERO)

	# Only terrain belongs in the texture. Godot and the menu draw structures independently.
	for child in mission.get_children():
		if child.name != &"Ground" and child is CanvasItem:
			child.hide()
	for layer in mission.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var result := image.save_png(destination)
	if result != OK:
		push_error("Could not save terrain preview to %s (%s)." % [destination, error_string(result)])
		quit(1)
		return
	print("Exported Mission 1 terrain preview to ", destination)
	quit()
