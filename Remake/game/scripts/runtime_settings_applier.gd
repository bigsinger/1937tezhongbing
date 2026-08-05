class_name RuntimeSettingsApplier
extends RefCounted

## Applies process-global runtime settings. Presentation nodes still own their
## local accessibility state, but Main no longer needs to know audio-bus or
## desktop-window implementation details.


func apply_global(settings: Dictionary, preserve_command_line_display: bool) -> void:
	Engine.max_fps = clampi(int(settings.get("max_fps", 60)), 0, 360)
	_apply_audio(settings)
	if not preserve_command_line_display:
		_apply_display(settings)


func _apply_audio(settings: Dictionary) -> void:
	_ensure_audio_buses()
	var muted := bool(settings.get("muted", false))
	for channel: String in ["master", "music", "sfx", "voice"]:
		var bus_name := channel.capitalize()
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		var volume := clampf(
			float(settings.get("%s_volume" % channel, 1.0)), 0.0, 1.0
		)
		AudioServer.set_bus_mute(
			bus_index,
			volume <= 0.0001 or (channel == "master" and muted),
		)
		AudioServer.set_bus_volume_db(
			bus_index, linear_to_db(maxf(volume, 0.0001))
		)


func _apply_display(settings: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var requested_screen := int(settings.get("monitor_index", -1))
	if requested_screen >= 0 and requested_screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(requested_screen)
	var display_mode := str(settings.get(
		"display_mode",
		"fullscreen" if bool(settings.get("fullscreen", false)) else "windowed",
	))
	if display_mode not in ["windowed", "fullscreen", "borderless"]:
		display_mode = "windowed"
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS, display_mode == "borderless"
	)
	if display_mode == "fullscreen":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif display_mode == "borderless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var window_size := Vector2i(
			clampi(int(settings.get("window_width", 1280)), 800, 7680),
			clampi(int(settings.get("window_height", 720)), 600, 4320),
		)
		if str(settings.get("resolution_policy", "desktop")) == "desktop":
			var usable := DisplayServer.screen_get_usable_rect(
				DisplayServer.window_get_current_screen()
			)
			window_size = Vector2i(
				maxi(800, floori(float(usable.size.x) * 0.85)),
				maxi(600, floori(float(usable.size.y) * 0.85)),
			)
		DisplayServer.window_set_size(window_size)
		var screen := DisplayServer.window_get_current_screen()
		var screen_position := DisplayServer.screen_get_position(screen)
		var screen_size := DisplayServer.screen_get_size(screen)
		DisplayServer.window_set_position(
			screen_position + (screen_size - window_size) / 2
		)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED
		if bool(settings.get("vsync", true))
		else DisplayServer.VSYNC_DISABLED
	)


static func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Sfx", "Voice"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, "Master")
