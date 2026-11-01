extends RefCounted

const PATH := "user://settings.cfg"
var fullscreen := false
var camera_speed := 500.0

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		fullscreen = config.get_value("display", "fullscreen", false) == true
		var speed = config.get_value("camera", "speed", 500.0)
		if (speed is float or speed is int) and is_finite(float(speed)):
			camera_speed = clampf(float(speed), 200.0, 900.0)
	apply_display()

func apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("camera", "speed", camera_speed)
	return config.save(PATH)
