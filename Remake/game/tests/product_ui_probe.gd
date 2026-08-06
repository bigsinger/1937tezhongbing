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
	# Pixel-layout snapshots are a native 1.0-scale contract. Keep the product's
	# persisted accessibility preferences intact, but do not let a developer's
	# local UI/text scale make this deterministic visual probe report a layout
	# regression. Accessibility scaling is exercised explicitly later below.
	_normalize_probe_visual_preferences(main)
	await process_frame
	await process_frame
	var modern_debug_hud := main.get_node_or_null("ModernDebugHud") as CanvasLayer
	_expect(
		modern_debug_hud != null and not modern_debug_hud.visible,
		"prototype-only text HUD is hidden in the normal product path",
	)
	_expect(
		main.startup_level_selection_pending
		and main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.LEVEL_SELECTOR
		and main.game_shell._level_selector.level_buttons.size() == 12,
		"normal product startup opens the native twelve-mission selector",
	)
	_expect(await _wait_for_render_frame(), "startup level-selector frame renders")
	# The selector is opened by Main's deferred startup sequence. Let its
	# containers complete one additional layout/draw pass before snapshotting;
	# otherwise the overlay mode can already be active while the previous dark
	# frame is still resident in the root texture.
	await process_frame
	_expect(await _wait_for_render_frame(), "startup selector layout settles")
	var startup_selector_layout: Dictionary = (
		main.game_shell.original_overlay_layout_snapshot()
	)
	var startup_selector_matches := _original_selector_layout_matches_viewport(
		startup_selector_layout,
		Vector2(root.size),
	)
	if not startup_selector_matches:
		print("Startup selector layout snapshot: ", startup_selector_layout)
	_expect(
		startup_selector_matches,
		"startup selector uses all twelve matching original mission labels",
	)
	_capture("startup-level-selector.jpg")
	(main.game_shell._level_selector.level_buttons["m000"] as Button).pressed.emit()
	_expect(
		not main.startup_level_selection_pending
		and main.current_level_index == 0,
		"choosing a startup mission enters its normal level-loading path",
	)
	await _dismiss_startup_media(main)
	_expect(
		main.selected_units.is_empty(),
		"mission startup preserves the original idle portraits until player selection",
	)
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
		bool(hud_layout.get("top_visible", false))
		and _visible_hud_status_count(hud_layout) == 1,
		"m000 HUD exposes its one matching original top ammo cell",
	)
	var m000_status := (
		(hud_layout.get("status_cells", {}) as Dictionary).get("强子", {})
		as Dictionary
	)
	_expect(
		(m000_status.get("rect", Rect2()) as Rect2)
		== Rect2(53.0, 1.0, 50.0, 20.0),
		"top ammo cell keeps the recovered native-pixel anchor",
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
	var map_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		_original_map_rect_matches_viewport(map_layout, Vector2(root.size)),
		"original minimap uses its native IBLOCK size and touches the HUD/right edge",
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
	var inventory_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		_original_inventory_layout_matches_viewport(inventory_layout, Vector2(root.size)),
		"inventory uses the recovered 276x421 popup and 13/40/50/84 hit geometry",
	)
	_capture("inventory.jpg")
	main.game_shell.close_for_state_change()

	main._open_control_guide()
	paused = false
	_expect(await _wait_for_render_frame(), "F1 guide frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.HELP,
		"F1 guide opens through the product shell",
	)
	var help_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		_original_help_layout_matches_viewport(help_layout, Vector2(root.size)),
		"F1 guide preserves the original centered 640x480 pixels",
	)
	_capture("control-guide.jpg")
	main.game_shell.close_for_state_change()

	main._open_pause_menu()
	paused = false
	_expect(await _wait_for_render_frame(), "pause menu frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU,
		"Esc pause menu opens",
	)
	var pause_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		_original_pause_layout_matches_viewport(pause_layout, Vector2(root.size)),
		"Esc uses the recovered eight-button pause layout and undimmed grayscale",
	)
	_capture("pause-menu.jpg")
	main.game_shell._classic_settings_button.pressed.emit()
	paused = false
	_expect(await _wait_for_render_frame(), "modern settings overview renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.MODERN_MENU,
		"original settings entry reaches the modern product settings overview",
	)
	_capture("modern-settings.jpg")
	main.game_shell._show_history_archive_from_menu()
	paused = false
	_expect(await _wait_for_render_frame(), "history archive frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.HISTORY_ARCHIVE
			and main.game_shell._history_mission_option.item_count == 12
			and main.game_shell._history_text.text.contains("史实与艺术加工"),
		"history archive exposes all twelve educational entries",
	)
	_capture("history-archive.jpg")
	main.game_shell.close_active_overlay()
	main.game_shell._show_settings()
	# Exercise the visual state without emitting settings_changed: a screenshot
	# probe must neither persist developer-machine preferences nor let a saved
	# fullscreen mode override its requested viewport midway through the run.
	main.game_shell._high_contrast_toggle.set_pressed_no_signal(true)
	main.game_shell._text_scale_slider.set_value_no_signal(1.25)
	var accessibility_preferences: Dictionary = main.runtime_settings.duplicate(true)
	accessibility_preferences["high_contrast"] = true
	accessibility_preferences["text_scale"] = 1.25
	main.game_shell.apply_visual_preferences(accessibility_preferences)
	paused = false
	_expect(await _wait_for_render_frame(), "accessibility settings frame renders")
	_capture("accessibility-settings.jpg")
	main.game_shell.close_active_overlay()
	main.game_shell.close_active_overlay()
	main.game_shell.show_pause_menu(false)
	main.game_shell._classic_credits_button.pressed.emit()
	paused = false
	_expect(await _wait_for_render_frame(), "credits frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.CREDITS,
		"制作人员 opens the original credits composite",
	)
	var credits_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		(credits_layout.get("credits_texture_size", Vector2.ZERO) as Vector2)
		== Vector2(640.0, 480.0),
		"credits retain their original 640x480 pixels",
	)
	_capture("credits.jpg")
	_expect(main.game_shell.close_active_overlay(), "credits return to the pause menu")
	main.game_shell.close_for_state_change()

	main._open_level_selector(false)
	paused = false
	_expect(await _wait_for_render_frame(), "level-selector frame renders")
	_expect(
		main.game_shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.LEVEL_SELECTOR
		and main.game_shell._level_selector.level_buttons.size() == 12,
		"native free selector exposes exactly the twelve formal missions",
	)
	_expect(
		_original_selector_layout_matches_viewport(
			main.game_shell.original_overlay_layout_snapshot(),
			Vector2(root.size),
		),
		"pause-menu selector retains its original-label geometry",
	)
	_capture("level-selector.jpg")
	main.game_shell.close_for_state_change()

	main.game_shell.show_failure("自动验收：任务失败\n可重新开始本关或从多槽选择器读取存档。", false)
	paused = false
	_expect(await _wait_for_render_frame(), "failure menu frame renders")
	var failure_layout: Dictionary = main.game_shell.original_overlay_layout_snapshot()
	_expect(
		main.game_shell.is_failure_open()
		and _original_failure_layout_matches_viewport(
			failure_layout,
			Vector2(root.size),
		),
		"forced failure menu uses the recovered two-button geometry and grayscale",
	)
	_capture("failure-menu.jpg")
	main.game_shell.close_for_state_change()

	main.set_developer_debug_enabled(true)
	main.developer_debug_overlay.visible = true
	_expect(await _wait_for_render_frame(), "developer diagnostics frame renders")
	_expect(
		main.developer_world_debug_overlay.visible,
		"developer diagnostics enables its world perception/path layer",
	)
	_capture("developer-diagnostics.jpg")
	main.developer_debug_overlay.visible = false
	main.set_developer_debug_enabled(false)

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


func _normalize_probe_visual_preferences(main: Node) -> void:
	var preferences: Dictionary = main.runtime_settings.duplicate(true)
	preferences["ui_scale"] = 1.0
	preferences["text_scale"] = 1.0
	preferences["high_contrast"] = false
	for key: String in ["ui_scale", "text_scale", "high_contrast"]:
		main.runtime_settings[key] = preferences[key]
		main.game_shell.settings[key] = preferences[key]
	main.game_shell._ui_scale_slider.set_value_no_signal(1.0)
	main.game_shell._text_scale_slider.set_value_no_signal(1.0)
	main.game_shell._high_contrast_toggle.set_pressed_no_signal(false)
	main.game_shell.apply_visual_preferences(preferences)


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


func _visible_hud_status_count(layout: Dictionary) -> int:
	var count := 0
	for raw_status: Variant in (layout.get("status_cells", {}) as Dictionary).values():
		if bool((raw_status as Dictionary).get("visible", false)):
			count += 1
	return count


func _original_pause_layout_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	var panel_rect := layout.get("pause_menu_rect", Rect2()) as Rect2
	var expected_rect := Rect2(
		viewport_size * 0.5 + Vector2(-305.0, -118.0),
		Vector2(132.0, 318.0),
	)
	var buttons := layout.get("pause_buttons", {}) as Dictionary
	return (
		panel_rect == expected_rect
		and buttons.size() == 8
		and bool(layout.get("desaturate_visible", false))
		and is_equal_approx(float(layout.get("desaturate_brightness", 0.0)), 1.0)
		and is_equal_approx(float(layout.get("desaturate_average_mix", 0.0)), 1.0)
		and not bool(layout.get("dim_visible", true))
	)


func _original_selector_layout_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	var panel_size := Vector2(820.0, 600.0)
	if (
		(layout.get("level_selector_panel_rect", Rect2()) as Rect2)
		!= Rect2((viewport_size - panel_size) * 0.5, panel_size)
	):
		return false
	var selector := layout.get("level_selector_layout", {}) as Dictionary
	var buttons := selector.get("buttons", {}) as Dictionary
	if (
		not bool(selector.get("assets_ready", false))
		or int(selector.get("grid_columns", 0)) != 3
		or buttons.size() != 12
	):
		return false
	for level_index: int in range(12):
		var button := buttons.get("m%03d" % level_index, {}) as Dictionary
		if (
			not bool(button.get("uses_original_asset", false))
			or (button.get("icon_size", Vector2.ZERO) as Vector2)
			!= Vector2(114.0, 33.0)
		):
			return false
	return true


func _original_failure_layout_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	var center := viewport_size * 0.5
	var buttons := layout.get("failure_buttons", {}) as Dictionary
	var restart := buttons.get("restart", {}) as Dictionary
	var main := buttons.get("main", {}) as Dictionary
	return (
		(layout.get("failure_title_rect", Rect2()) as Rect2)
		== Rect2(center + Vector2(-99.0, -59.0), Vector2(172.0, 50.0))
		and (layout.get("failure_title_texture_size", Vector2.ZERO) as Vector2)
		== Vector2(172.0, 50.0)
		and (restart.get("rect", Rect2()) as Rect2)
		== Rect2(center + Vector2(-158.0, -3.0), Vector2(132.0, 38.0))
		and (restart.get("texture_size", Vector2.ZERO) as Vector2)
		== Vector2(132.0, 38.0)
		and (main.get("rect", Rect2()) as Rect2)
		== Rect2(center + Vector2(-8.0, -3.0), Vector2(132.0, 38.0))
		and (main.get("texture_size", Vector2.ZERO) as Vector2)
		== Vector2(132.0, 38.0)
		and bool(layout.get("desaturate_visible", false))
		and is_equal_approx(float(layout.get("desaturate_brightness", 0.0)), 1.0)
		and is_equal_approx(float(layout.get("desaturate_average_mix", 0.0)), 1.0)
		and not bool(layout.get("dim_visible", true))
	)
func _original_inventory_layout_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	if not bool(layout.get("assets_ready", false)):
		return false
	var panel_rect := layout.get("inventory_rect", Rect2()) as Rect2
	if panel_rect != Rect2(
		Vector2(viewport_size.x - 276.0, viewport_size.y - 483.0),
		Vector2(276.0, 421.0),
	):
		return false
	var grid := layout.get("inventory_layout", {}) as Dictionary
	if (
		grid.get("grid_origin", Vector2.ZERO) != Vector2(13.0, 40.0)
		or int(grid.get("column_count", 0)) != 5
		or grid.get("cell_size", Vector2.ZERO) != Vector2(50.0, 74.0)
		or int(grid.get("row_pitch", 0)) != 84
	):
		return false
	var slots := grid.get("slots", []) as Array
	if slots.is_empty():
		return true
	var first_rect := (slots[0] as Dictionary).get("rect", Rect2()) as Rect2
	return first_rect == Rect2(13.0, 40.0, 50.0, 74.0)


func _original_map_rect_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	var texture_size := layout.get("map_texture_size", Vector2.ZERO) as Vector2
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false
	return (layout.get("map_rect", Rect2()) as Rect2) == Rect2(
		Vector2(
			viewport_size.x - texture_size.x,
			viewport_size.y - 62.0 - texture_size.y,
		),
		texture_size,
	)


func _original_help_layout_matches_viewport(
	layout: Dictionary,
	viewport_size: Vector2,
) -> bool:
	var expected_size := Vector2(640.0, 480.0)
	return (
		(layout.get("help_texture_size", Vector2.ZERO) as Vector2) == expected_size
		and (layout.get("help_rect", Rect2()) as Rect2)
		== Rect2((viewport_size - expected_size) * 0.5, expected_size)
	)


func _write_hud_layout(file_name: String, layout: Dictionary) -> void:
	var encoded := {
		"schema_version": 1,
		"viewport": {"width": root.size.x, "height": root.size.y},
		"assets_ready": bool(layout.get("assets_ready", false)),
		"visible": bool(layout.get("visible", false)),
		"top_visible": bool(layout.get("top_visible", false)),
		"height": float(layout.get("height", 0.0)),
		"bar_rect": _rect_record(layout.get("bar_rect", Rect2()) as Rect2),
		"status_cells": {},
		"portraits": {},
		"actions": {},
	}
	for actor_name: String in (layout.get("status_cells", {}) as Dictionary):
		var status := (
			(layout.get("status_cells", {}) as Dictionary)[actor_name]
			as Dictionary
		)
		encoded["status_cells"][actor_name] = {
			"visible": bool(status.get("visible", false)),
			"ammo_text": str(status.get("ammo_text", "")),
			"rect": _rect_record(status.get("rect", Rect2()) as Rect2),
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
