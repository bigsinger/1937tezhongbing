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
	await process_frame
	_expect(
		main.startup_level_selection_pending
		and main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.LEVEL_SELECTOR
		and main.game_shell._level_selector.level_buttons.size() == 12,
		"normal product startup opens the native twelve-mission selector",
	)
	_expect(await _wait_for_render_frame(), "startup level-selector frame renders")
	_capture("startup-level-selector.jpg")
	(main.game_shell._level_selector.level_buttons["m000"] as Button).pressed.emit()
	_expect(
		not main.startup_level_selection_pending
		and main.current_level_index == 0,
		"choosing a startup mission enters its normal level-loading path",
	)
	await _dismiss_startup_media(main)
	_expect(await _wait_for_render_frame(), "initial product frame renders")
	var hud_layout: Dictionary = main.game_shell.original_hud_layout_snapshot()
	_expect(bool(hud_layout.get("assets_ready", false)), "original HUD assets load")
	_expect(bool(hud_layout.get("visible", false)), "original bottom HUD is visible")
	_expect(
		_hud_layout_matches_viewport(hud_layout, Vector2(root.size)),
		"original bottom HUD spans the viewport and keeps its 62-pixel height",
	)
	_expect(
		_visible_hud_portrait_count(hud_layout) == 1,
		"m000 HUD exposes its one original playable actor",
	)
	_expect(
		(hud_layout.get("actions", {}) as Dictionary).size() == 3,
		"original observation, map and system buttons are present",
	)
	_capture("gameplay-hud.jpg")
	_write_hud_layout("gameplay-hud-layout.json", hud_layout)

	main._open_tactical_map()
	paused = false
	_expect(await _wait_for_render_frame(), "tactical map frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE
		and main.game_shell.is_tactical_map_visible(),
		"M tactical map opens as a live non-pausing HUD window",
	)
	_expect(
		bool(
			((main.game_shell.original_hud_layout_snapshot().get(
				"actions", {}
			) as Dictionary).get("minimap", {}) as Dictionary).get(
				"pressed", false
			)
		),
		"map HUD button mirrors the M-key map state",
	)
	_capture("tactical-map.jpg")
	main.game_shell.close_for_state_change()

	main._open_inventory()
	paused = false
	_expect(await _wait_for_render_frame(), "inventory frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY,
		"A/W inventory opens",
	)
	_capture("inventory.jpg")
	main.game_shell.close_for_state_change()

	main._open_pause_menu()
	paused = false
	_expect(await _wait_for_render_frame(), "pause menu frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU,
		"Esc pause menu opens",
	)
	_capture("pause-menu.jpg")
	main.game_shell.close_for_state_change()

	main._open_level_selector(false)
	paused = false
	_expect(await _wait_for_render_frame(), "level-selector frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.LEVEL_SELECTOR
		and main.game_shell._level_selector.level_buttons.size() == 12,
		"native free selector exposes exactly the twelve formal missions",
	)
	_capture("level-selector.jpg")
	main.game_shell.close_for_state_change()

	main.game_shell.show_failure("自动验收：任务失败\n可重新开始本关或从多槽选择器读取存档。", false)
	paused = false
	_expect(await _wait_for_render_frame(), "failure menu frame renders")
	_expect(main.game_shell.is_failure_open(), "forced failure menu opens")
	_capture("failure-menu.jpg")
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


func _wait_for_render_frame(max_process_frames: int = 180) -> bool:
	# Dummy/headless renderers may never emit frame_post_draw. Bound the wait so
	# a misconfigured visual-probe invocation fails instead of hanging CI/QA.
	var completed := [false]
	var on_draw := func() -> void: completed[0] = true
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	RenderingServer.force_draw(false)
	for _frame: int in range(max_process_frames):
		await process_frame
		if bool(completed[0]):
			return true
	if RenderingServer.frame_post_draw.is_connected(on_draw):
		RenderingServer.frame_post_draw.disconnect(on_draw)
	return false


func _capture(file_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := output_directory.path_join(file_name)
	_expect(image != null and not image.is_empty(), "%s image is available" % file_name)
	if image != null and not image.is_empty():
		if image.get_width() > 960:
			var resized_height := maxi(
				1,
				roundi(float(image.get_height()) * 960.0 / float(image.get_width())),
			)
			image.resize(960, resized_height, Image.INTERPOLATE_LANCZOS)
		_expect(image.save_jpg(path, 0.62) == OK, "%s compressed screenshot saves" % file_name)


func _hud_layout_matches_viewport(layout: Dictionary, viewport_size: Vector2) -> bool:
	var bar_rect := layout.get("bar_rect", Rect2()) as Rect2
	return (
		is_equal_approx(bar_rect.position.x, 0.0)
		and is_equal_approx(bar_rect.position.y, viewport_size.y - 62.0)
		and is_equal_approx(bar_rect.size.x, viewport_size.x)
		and is_equal_approx(bar_rect.size.y, 62.0)
	)


func _visible_hud_portrait_count(layout: Dictionary) -> int:
	var count := 0
	for raw_portrait: Variant in (layout.get("portraits", {}) as Dictionary).values():
		if bool((raw_portrait as Dictionary).get("visible", false)):
			count += 1
	return count


func _write_hud_layout(file_name: String, layout: Dictionary) -> void:
	var encoded := {
		"schema_version": 1,
		"viewport": {"width": root.size.x, "height": root.size.y},
		"assets_ready": bool(layout.get("assets_ready", false)),
		"visible": bool(layout.get("visible", false)),
		"height": float(layout.get("height", 0.0)),
		"bar_rect": _rect_record(layout.get("bar_rect", Rect2()) as Rect2),
		"portraits": {},
		"actions": {},
	}
	for actor_name: String in (layout.get("portraits", {}) as Dictionary):
		var portrait := (
			(layout.get("portraits", {}) as Dictionary)[actor_name]
			as Dictionary
		)
		encoded["portraits"][actor_name] = {
			"visible": bool(portrait.get("visible", false)),
			"rect": _rect_record(portrait.get("rect", Rect2()) as Rect2),
		}
	for action: String in (layout.get("actions", {}) as Dictionary):
		var action_state := (
			(layout.get("actions", {}) as Dictionary)[action]
			as Dictionary
		)
		encoded["actions"][action] = {
			"visible": bool(action_state.get("visible", false)),
			"pressed": bool(action_state.get("pressed", false)),
			"rect": _rect_record(action_state.get("rect", Rect2()) as Rect2),
		}
	var path := output_directory.path_join(file_name)
	var output := FileAccess.open(path, FileAccess.WRITE)
	_expect(output != null, "%s opens for writing" % file_name)
	if output != null:
		output.store_string(JSON.stringify(encoded, "  ") + "\n")
		output.close()


func _rect_record(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _output_directory(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX)
	return ""
