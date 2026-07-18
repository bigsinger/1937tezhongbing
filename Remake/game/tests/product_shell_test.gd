extends SceneTree

const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var shell: CanvasLayer = GAME_SHELL_SCRIPT.new()
	root.add_child(shell)
	await process_frame

	shell.set_settings({
		"fullscreen": true,
		"display_mode": "borderless",
		"muted": true,
		"resolution_policy": "custom",
		"window_width": 1600,
		"window_height": 900,
		"vsync": false,
		"subtitles": false,
		"show_briefings": false,
		"edge_scroll": false,
		"master_volume": 0.35,
		"music_volume": 0.25,
		"sfx_volume": 0.55,
		"voice_volume": 0.75,
		"controls": GAME_INPUT_BINDINGS.default_bindings(),
	})
	var settings: Dictionary = shell.settings_snapshot()
	expect(
		bool(settings["fullscreen"])
		and str(settings["display_mode"]) == "borderless"
		and bool(settings["muted"])
		and str(settings["resolution_policy"]) == "custom"
		and int(settings["window_width"]) == 1600
		and int(settings["window_height"]) == 900
		and not bool(settings["vsync"])
		and not bool(settings["subtitles"])
		and not bool(settings["show_briefings"])
		and not bool(settings["edge_scroll"])
		and is_equal_approx(float(settings["master_volume"]), 0.35)
		and is_equal_approx(float(settings["music_volume"]), 0.25)
		and is_equal_approx(float(settings["sfx_volume"]), 0.55)
		and is_equal_approx(float(settings["voice_volume"]), 0.75),
		"shell settings round-trip without losing borderless or muted state",
		failures,
	)
	(shell._audio_sliders["music"] as HSlider).value = 0.30
	var updated_settings: Dictionary = shell.settings_snapshot()
	expect(
		str(updated_settings["display_mode"]) == "borderless"
		and bool(updated_settings["muted"])
		and str(updated_settings["resolution_policy"]) == "custom"
		and int(updated_settings["window_width"]) == 1600
		and int(updated_settings["window_height"]) == 900
		and not bool(updated_settings["vsync"])
		and is_equal_approx(float(updated_settings["music_volume"]), 0.30),
		"editing an unrelated slider preserves borderless and muted settings",
		failures,
	)

	expect(not paused, "product shell test starts unpaused", failures)
	shell.show_pause_menu(false, "测试暂停")
	expect(
		paused
		and shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU
		and shell._root.visible,
		"pause menu owns a gameplay pause",
		failures,
	)
	expect(shell._load_button.disabled, "pause menu disables load without a save", failures)
	shell._show_settings()
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.SETTINGS
		and shell._audio_sliders.size() == 4
		and shell._muted_toggle.button_pressed
		and shell._control_buttons.size() == GAME_INPUT_BINDINGS.action_ids().size(),
		"settings expose mute, four audio channels, and every remappable command",
		failures,
	)
	shell._on_rebind_pressed("minimap")
	var remap_event := InputEventKey.new()
	remap_event.keycode = KEY_Z
	remap_event.pressed = true
	shell._unhandled_input(remap_event)
	expect(
		int(((shell.settings_snapshot()["controls"] as Dictionary)["minimap"] as Dictionary)["keycode"]) == KEY_Z,
		"key capture changes the requested command",
		failures,
	)
	shell._return_from_settings()
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU and paused,
		"settings return to the owning game menu",
		failures,
	)
	var escape_press := InputEventKey.new()
	escape_press.keycode = KEY_ESCAPE
	escape_press.pressed = true
	shell._unhandled_input(escape_press)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU and paused,
		"original Esc action waits for key release",
		failures,
	)
	var escape_release := InputEventKey.new()
	escape_release.keycode = KEY_ESCAPE
	escape_release.pressed = false
	shell._unhandled_input(escape_release)
	expect(not paused and not shell._root.visible, "released Esc closes pause and restores gameplay", failures)
	shell.show_pause_menu(false, "右键返回测试")
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	root.push_input(right_release)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE and not paused,
		"released right mouse button performs the original menu back/cancel action",
		failures,
	)
	var next_level_requests := [0]
	shell.next_level_requested.connect(func() -> void: next_level_requests[0] += 1)
	shell.show_victory(true, true)
	expect(
		paused
		and shell._menu_title.text == "任务完成"
		and shell._next_level_button.visible,
		"a completed non-final mission exposes the next-level campaign action",
		failures,
	)
	shell._next_level_button.pressed.emit()
	expect(
		next_level_requests[0] == 1 and not shell.is_overlay_open() and not paused,
		"the next-level action releases the pause before requesting the transition",
		failures,
	)
	shell.show_victory(true, false)
	expect(
		shell._menu_title.text == "战役完成" and not shell._next_level_button.visible,
		"the twelfth mission ends the campaign without wrapping back to level one",
		failures,
	)
	shell._resume_button.pressed.emit()

	shell.show_control_guide()
	var guide_press := InputEventKey.new()
	guide_press.keycode = KEY_F1
	guide_press.pressed = true
	shell._unhandled_input(guide_press)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.HELP,
		"original F1 action waits for key release",
		failures,
	)
	var guide_release := InputEventKey.new()
	guide_release.keycode = KEY_F1
	guide_release.pressed = false
	shell._unhandled_input(guide_release)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE and not paused,
		"released F1 closes the control guide",
		failures,
	)

	paused = true
	shell.show_inventory("[b]外部暂停背包[/b]")
	expect(paused, "inventory stays paused on an externally paused baseline", failures)
	expect(shell.close_active_overlay(), "inventory overlay closes", failures)
	expect(paused, "closing inventory restores the external pause", failures)
	paused = false

	var map_clicks: Array[Vector2] = []
	var actor_markers: Array[Dictionary] = [
		{"position": Vector2(250.0, 125.0), "color": Color.BLUE},
	]
	var mission_markers: Array[Dictionary] = [
		{"position": Vector2(750.0, 375.0), "color": Color.YELLOW},
	]
	shell.map_position_requested.connect(
		func(world_position: Vector2) -> void: map_clicks.append(world_position)
	)
	shell.show_tactical_map(
		null,
		Vector2(1000.0, 500.0),
		actor_markers,
		mission_markers,
		Rect2(400.0, 200.0, 200.0, 100.0),
	)
	expect(
		not paused and shell.is_tactical_map_visible() and not shell.is_overlay_open(),
		"right-bottom minimap stays live without pausing gameplay",
		failures,
	)
	expect(
		is_equal_approx(shell._map_panel.offset_right, 0.0)
		and is_equal_approx(shell._map_panel.offset_bottom, -62.0),
		"minimap is flush right and sits directly above the recovered 62px HUD",
		failures,
	)
	var moved_markers: Array[Dictionary] = [
		{"position": Vector2(300.0, 150.0), "color": Color.RED},
	]
	shell.update_tactical_map(moved_markers, mission_markers, Rect2(420.0, 210.0, 200.0, 100.0))
	expect(
		(shell._map_view.actor_markers[0] as Dictionary)["position"] == Vector2(300.0, 150.0),
		"minimap actor dots refresh while the game runs",
		failures,
	)
	shell._map_view.size = Vector2(800.0, 400.0)
	var map_rect: Rect2 = shell._map_view._map_rect()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map_rect.get_center()
	shell._map_view._gui_input(click)
	expect(
		map_clicks.size() == 1
		and map_clicks[0].is_equal_approx(Vector2(500.0, 250.0)),
		"clicking the tactical-map center requests the world center",
		failures,
	)
	var original_map_image := Image.create(336, 166, false, Image.FORMAT_RGBA8)
	original_map_image.fill(Color(0.18, 0.24, 0.16))
	var original_map_texture := ImageTexture.create_from_image(original_map_image)
	shell.show_tactical_map(
		original_map_texture,
		Vector2(4960.0, 2240.0),
		actor_markers,
		mission_markers,
		Rect2(0.0, 0.0, 640.0, 480.0),
	)
	shell._map_view.size = Vector2(672.0, 332.0)
	var texture_rect: Rect2 = shell._map_view._texture_rect()
	var content_rect: Rect2 = shell._map_view._map_rect()
	expect(
		is_equal_approx(texture_rect.size.aspect(), 336.0 / 166.0),
		"the recovered minimap texture keeps its original aspect ratio",
		failures,
	)
	expect(
		is_equal_approx(content_rect.size.aspect(), 4960.0 / 2240.0)
		and shell._map_view._world_to_map(Vector2.ZERO, content_rect).is_equal_approx(content_rect.position)
		and shell._map_view._world_to_map(Vector2(4960.0, 2240.0), content_rect).is_equal_approx(content_rect.end),
		"world markers map to the recovered image content inside its 13px border",
		failures,
	)
	for sample_world_position: Vector2 in [
		Vector2.ZERO,
		Vector2(1200.0, 700.0),
		Vector2(4960.0, 2240.0),
	]:
		var mapped: Vector2 = shell._map_view._world_to_map(sample_world_position, content_rect)
		expect(
			shell._map_view._map_to_world(mapped, content_rect).is_equal_approx(sample_world_position),
			"minimap marker/click conversion round-trips %s" % sample_world_position,
			failures,
		)
	var border_click := InputEventMouseButton.new()
	border_click.button_index = MOUSE_BUTTON_LEFT
	border_click.pressed = true
	border_click.position = texture_rect.position + Vector2.ONE
	shell._map_view._gui_input(border_click)
	expect(map_clicks.size() == 1, "the decorative 13px minimap border is not treated as world terrain", failures)
	shell.hide_tactical_map()
	expect(not shell.is_tactical_map_visible() and not paused, "minimap hides without changing pause state", failures)

	var icon_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	icon_image.fill(Color(0.85, 0.68, 0.24))
	var slot_icon := ImageTexture.create_from_image(icon_image)
	var inventory_model := {
		"actor_name": "队员甲",
		"groups": [
			{
				"title": "武器",
				"mode": "weapons",
				"slots": [
					{"kind": "weapon", "label": "步枪", "quantity": 25, "enabled": true},
				],
			},
			{
				"title": "弹药",
				"mode": "items",
				"slots": [
					{
						"kind": "ammunition",
						"label": "步枪弹",
						"quantity": 25,
						"enabled": false,
						"icon": slot_icon,
					},
				],
			},
			{
				"title": "主动物品",
				"mode": "items",
				"slots": [
					{
						"kind": "active_item",
						"label": "地雷",
						"quantity": 2,
						"enabled": true,
						"icon": slot_icon,
					},
				],
			},
			{
				"title": "任务物资",
				"mode": "items",
				"slots": [
					{"kind": "mission_item", "label": "军服", "quantity": 1, "enabled": true},
				],
			},
		],
	}
	shell.show_inventory(inventory_model, "items")
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY
		and shell._inventory_view.visible_slot_count() == 3
		and shell._inventory_view.mode == "items",
		"inventory preserves the four-category model and presents its item categories",
		failures,
	)
	expect(
		is_equal_approx(shell._inventory_panel.offset_left, -276.0)
		and is_equal_approx(shell._inventory_panel.offset_right, 0.0)
		and is_equal_approx(shell._inventory_panel.offset_top, -483.0)
		and is_equal_approx(shell._inventory_panel.offset_bottom, -62.0),
		"inventory uses the original 276x421 right-side popup above the 62px HUD",
		failures,
	)
	expect(
		int(shell._inventory_view.ORIGINAL_ROW_PITCH) == 84
		and shell._inventory_view.COLUMN_COUNT == 5,
		"inventory grid keeps five columns and the recovered 84px row pitch",
		failures,
	)
	var item_buttons: Array[Button] = shell._inventory_view._slot_buttons
	expect(
		item_buttons.size() == 3
		and item_buttons[0].icon == slot_icon
		and item_buttons[1].icon == slot_icon
		and root.gui_get_focus_owner() == item_buttons[1],
		"inventory renders optional icons and keyboard focus skips disabled cells",
		failures,
	)
	var undocumented_i := InputEventKey.new()
	undocumented_i.keycode = KEY_I
	undocumented_i.pressed = true
	shell._unhandled_input(undocumented_i)
	undocumented_i.pressed = false
	shell._unhandled_input(undocumented_i)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY,
		"undocumented hard-coded I no longer bypasses the remappable original inventory keys",
		failures,
	)
	var weapon_press := InputEventKey.new()
	weapon_press.keycode = KEY_W
	weapon_press.pressed = true
	shell._unhandled_input(weapon_press)
	expect(shell._inventory_view.mode == "items", "W does not switch the inventory on key press", failures)
	var weapon_release := InputEventKey.new()
	weapon_release.keycode = KEY_W
	weapon_release.pressed = false
	shell._unhandled_input(weapon_release)
	expect(
		shell._inventory_view.visible_slot_count() == 1
		and shell._inventory_view.mode == "weapons",
		"released W switches item inventory to the weapon category",
		failures,
	)
	shell._unhandled_input(weapon_release)
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE and not paused,
		"releasing the active inventory key closes it and restores gameplay",
		failures,
	)

	shell.show_inventory(inventory_model, "items")
	var item_press := InputEventKey.new()
	item_press.keycode = KEY_A
	item_press.pressed = true
	shell._unhandled_input(item_press)
	expect(shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY, "A waits for release before closing items", failures)
	var item_release := InputEventKey.new()
	item_release.keycode = KEY_A
	item_release.pressed = false
	shell._unhandled_input(item_release)
	expect(shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE and not paused, "released A closes item inventory", failures)

	var activated_slots: Array[Dictionary] = []
	shell.inventory_slot_requested.connect(
		func(slot: Dictionary) -> void: activated_slots.append(slot.duplicate(true))
	)
	shell.show_inventory(inventory_model, "items")
	item_buttons = shell._inventory_view._slot_buttons
	item_buttons[1].pressed.emit()
	expect(
		activated_slots.size() == 1
		and str(activated_slots[0].get("kind", "")) == "active_item"
		and shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.NONE
		and not paused,
		"activating an enabled cell emits its payload, closes the popup and restores gameplay",
		failures,
	)

	var save_slot_requests: Array[String] = []
	shell.save_slot_requested.connect(
		func(slot_id: String) -> void: save_slot_requests.append(slot_id)
	)
	var save_slot_summaries: Array[Dictionary] = [
		{
			"slot_id": "slot_1",
			"saved_at_unix": 1_700_000_000,
			"level_id": "m002",
			"elapsed_seconds": 65.0,
			"revision": 1,
			"recovered": false,
		}
	]
	shell.set_save_slots(save_slot_summaries)
	shell.show_pause_menu(true)
	shell._on_save_pressed()
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.SLOT_SELECTOR
		and shell._slot_selector.slot_buttons.size() == 10,
		"save menu exposes the original ten manual slots",
		failures,
	)
	(shell._slot_selector.slot_buttons["slot_1"] as Button).pressed.emit()
	expect(save_slot_requests.is_empty(), "occupied save slot requires overwrite confirmation", failures)
	(shell._slot_selector.slot_buttons["slot_1"] as Button).pressed.emit()
	expect(
		save_slot_requests == ["slot_1"]
		and shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.PAUSE_MENU,
		"confirmed manual slot emits its stable slot ID and returns to the menu",
		failures,
	)
	shell.close_active_overlay()

	var load_requests := [0]
	var restart_requests := [0]
	shell.load_slot_requested.connect(func(_slot_id: String) -> void: load_requests[0] += 1)
	shell.restart_requested.connect(func() -> void: restart_requests[0] += 1)
	var load_slot_summaries: Array[Dictionary] = [
		{
			"slot_id": "quick",
			"saved_at_unix": 1_700_000_000,
			"level_id": "m003",
			"elapsed_seconds": 125.0,
			"revision": 2,
			"recovered": false,
		}
	]
	shell.set_save_slots(load_slot_summaries)
	shell.show_failure("测试失败", true)
	expect(
		paused
		and shell.is_failure_open()
		and shell._failure_desaturate.visible
		and not shell._save_button.visible,
		"failure mode desaturates, pauses, and removes saving",
		failures,
	)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell._unhandled_input(escape)
	expect(shell.is_failure_open() and paused, "Escape cannot bypass forced failure mode", failures)
	shell._on_load_pressed()
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.SLOT_SELECTOR
		and shell._failure_desaturate.visible
		and shell._slot_selector.slot_buttons.has("quick"),
		"failure load opens a multi-slot selector over the grayscale world",
		failures,
	)
	(shell._slot_selector.slot_buttons["quick"] as Button).pressed.emit()
	expect(
		load_requests[0] == 1 and shell.is_failure_open() and paused,
		"chosen load slot keeps failure mode until Main confirms restoration",
		failures,
	)
	shell._return_from_slot_selector()
	shell._restart_button.pressed.emit()
	expect(
		restart_requests[0] == 1 and not shell.is_overlay_open() and not paused,
		"restart releases failure pause before requesting a new level",
		failures,
	)

	var main: Node = MAIN_SCENE.instantiate()
	main.runtime_settings = {
		"fullscreen": true,
		"display_mode": "borderless",
		"muted": true,
		"resolution_policy": "custom",
		"window_width": 1600,
		"window_height": 900,
		"vsync": false,
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"voice_volume": 1.0,
		"controls": GAME_INPUT_BINDINGS.default_bindings(),
	}
	main._on_shell_settings_changed({"music_volume": 0.55})
	var main_settings: Dictionary = main.runtime_settings
	var master_bus := AudioServer.get_bus_index("Master")
	expect(
		str(main_settings["display_mode"]) == "borderless"
		and bool(main_settings["muted"])
		and str(main_settings["resolution_policy"]) == "custom"
		and int(main_settings["window_width"]) == 1600
		and int(main_settings["window_height"]) == 900
		and not bool(main_settings["vsync"])
		and is_equal_approx(float(main_settings["music_volume"]), 0.55)
		and master_bus >= 0
		and AudioServer.is_bus_mute(master_bus),
		"Main applies mute while preserving hidden display settings during unrelated edits",
		failures,
	)
	main._apply_runtime_settings({
		"muted": false,
		"master_volume": 1.0,
		"music_volume": 1.0,
		"sfx_volume": 1.0,
		"voice_volume": 1.0,
	})
	var obsolete_camera_tween := root.create_tween()
	obsolete_camera_tween.tween_interval(10.0)
	main.direction_camera_tween = obsolete_camera_tween
	main._cancel_direction_camera_tween()
	expect(
		main.direction_camera_tween == null and not obsolete_camera_tween.is_valid(),
		"a new director camera request or level switch cancels the previous camera tween",
		failures,
	)
	main.current_mission = {
		"scene_bindings": {"high_ground": [1, 2, 3, 4]},
		"objectives": [],
	}
	expect(
		main._binding_has_world_marker("high_ground")
		and not main._binding_is_interactive("high_ground"),
		"m010 high-ground zones are visible markers without misleading E interactions",
		failures,
	)
	var viewport_size := Vector2(1280.0, 720.0)
	expect(
		main.edge_scroll_direction_for_position(Vector2(640.0, 360.0), viewport_size).is_zero_approx(),
		"mouse at screen center does not scroll",
		failures,
	)
	expect(
		main.edge_scroll_direction_for_position(Vector2(0.0, 360.0), viewport_size) == Vector2.LEFT
		and main.edge_scroll_direction_for_position(Vector2(1279.0, 360.0), viewport_size) == Vector2.RIGHT
		and main.edge_scroll_direction_for_position(Vector2(640.0, 0.0), viewport_size) == Vector2.UP
		and main.edge_scroll_direction_for_position(Vector2(640.0, 719.0), viewport_size) == Vector2.DOWN,
		"all four screen edges request the matching camera direction",
		failures,
	)
	expect(
		main.edge_scroll_direction_for_position(Vector2(0.0, 0.0), viewport_size) == Vector2(-1.0, -1.0)
		and main.edge_scroll_direction_for_position(Vector2(1.0, 360.0), viewport_size).is_zero_approx()
		and main.edge_scroll_direction_for_position(Vector2(1278.0, 360.0), viewport_size).is_zero_approx()
		and main.edge_scroll_direction_for_position(Vector2(1280.0, 360.0), viewport_size).is_zero_approx(),
		"one-pixel edge scrolling is symmetric, combines corners, and rejects the exclusive viewport bound",
		failures,
	)
	expect(
		main.imported_entity_z_index({
			"y": 173,
			"reference_y": 173,
			"database_header_values": [1, 0, 0, 0],
		}) == main.BACKGROUND_ENTITY_Z_INDEX,
		"flat DBL ground and shadow decals stay behind moving actors",
		failures,
	)
	expect(
		main.imported_entity_z_index({
			"y": 200,
			"reference_y": 236,
			"database_header_values": [0, 0, 0, 0],
		}) == WORLD_DEPTH.normal_z(236.0),
		"ordinary world props remain depth-sorted by their recovered reference baseline",
		failures,
	)
	expect(
		main.imported_entity_z_index({
			"reference_y": 10,
			"database_header_values": [2, 0, 0, 0],
		}) == WORLD_DEPTH.FOREGROUND_Z
		and main.imported_entity_z_index({
			"reference_y": 0,
			"database_header_values": [3, 0, 0, 0],
		}) == WORLD_DEPTH.TOPMOST_Z,
		"recovered queue 2/3 objects stay above every Y-sorted actor",
		failures,
	)
	var movement_groups: Array[Dictionary] = []
	for direction_index: int in range(8):
		movement_groups.append({
			"frames": [] as Array[Texture2D],
			"anchor": Vector2.ZERO,
			"frame_hold_ticks": 1,
		})
	var movement_unit = SQUAD_UNIT.new()
	movement_unit.configure("测试队员", Color.WHITE, Vector2.ZERO)
	movement_unit.configure_movement_modes(
		movement_groups,
		movement_groups.duplicate(true),
		movement_groups.duplicate(true),
	)
	expect(
		movement_unit.movement_mode_name() == "run"
		and is_equal_approx(movement_unit.move_speed, SQUAD_UNIT.RUN_SPEED),
		"R/C movement state starts in original run mode",
		failures,
	)
	movement_unit.set_running(false)
	expect(
		movement_unit.movement_mode_name() == "walk"
		and is_equal_approx(movement_unit.move_speed, SQUAD_UNIT.WALK_SPEED),
		"R switches selected actors to walk speed and animation set",
		failures,
	)
	movement_unit.set_crawling(true)
	expect(
		movement_unit.movement_mode_name() == "crawl"
		and is_equal_approx(movement_unit.move_speed, SQUAD_UNIT.CRAWL_SPEED),
		"C switches selected actors to crawl speed and animation set",
		failures,
	)
	movement_unit.free()
	main.free()

	root.remove_child(shell)
	shell.free()
	paused = false
	await process_frame

	if failures.is_empty():
		print("Product shell tests passed (%d checks)." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
