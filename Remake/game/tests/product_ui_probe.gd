extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const OUTPUT_ARGUMENT_PREFIX := "--output-dir="

var failures: Array[String] = []
var output_directory := ""
var checks := 0


func _init() -> void:
	output_directory = _output_directory(OS.get_cmdline_user_args())
	call_deferred("_run")


func _run() -> void:
	if output_directory.is_empty():
		push_error("product UI probe requires --output-dir=<absolute path>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_directory)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await _dismiss_startup_media(main)
	await process_frame
	await RenderingServer.frame_post_draw

	main._open_tactical_map()
	paused = false
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.TACTICAL_MAP,
		"M tactical map opens",
	)
	_capture("tactical-map.png")
	main.game_shell.close_for_state_change()

	main._open_inventory()
	paused = false
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY,
		"B/I inventory opens",
	)
	_capture("inventory.png")
	main.game_shell.close_for_state_change()

	main._open_pause_menu()
	paused = false
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU,
		"Esc pause menu opens",
	)
	_capture("pause-menu.png")
	main.game_shell.close_for_state_change()

	main.game_shell.show_failure("自动验收：任务失败\n可重新开始本关或读取最近存档。", false)
	paused = false
	await process_frame
	await RenderingServer.frame_post_draw
	_expect(main.game_shell.is_failure_open(), "forced failure menu opens")
	_capture("failure-menu.png")
	main.game_shell.close_for_state_change()

	root.remove_child(main)
	main.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("Product UI probe passed (%d checks). Output: %s" % [checks, output_directory])
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _dismiss_startup_media(main: Node) -> void:
	# Closing the briefing can synchronously start the mission's tutorial
	# dialogue. Drain each modal layer so the screenshots exercise the shell,
	# while retaining the normal startup sequence used by the playable build.
	for _attempt: int in range(16):
		var director: Variant = main.get("media_director")
		if director == null or not bool(director.call("is_modal_active")):
			return
		if not str(director.get("active_movie")).is_empty():
			director.call("stop_movie", true)
		elif not str(director.get("dialogue_sequence_id")).is_empty():
			director.call("stop_dialogue", true)
		elif not str(director.get("active_briefing")).is_empty():
			director.call("dismiss_briefing")
		elif bool(director.get("active_ending")):
			director.call("dismiss_ending")
		await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := output_directory.path_join(file_name)
	_expect(image != null and not image.is_empty(), "%s image is available" % file_name)
	if image != null and not image.is_empty():
		_expect(image.save_png(path) == OK, "%s screenshot saves" % file_name)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _output_directory(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX)
	return ""
