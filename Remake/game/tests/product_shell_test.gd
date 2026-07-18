extends SceneTree

const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
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
		"fullscreen": false,
		"subtitles": false,
		"show_briefings": false,
		"edge_scroll": false,
		"master_volume": 0.35,
	})
	var settings: Dictionary = shell.settings_snapshot()
	expect(
		not bool(settings["fullscreen"])
		and not bool(settings["subtitles"])
		and not bool(settings["show_briefings"])
		and not bool(settings["edge_scroll"])
		and is_equal_approx(float(settings["master_volume"]), 0.35),
		"shell settings round-trip through their controls",
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
	expect(shell.close_active_overlay(), "ordinary pause menu can close", failures)
	expect(not paused and not shell._root.visible, "closing pause restores gameplay", failures)

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
	expect(shell.close_active_overlay() and not paused, "map closes and resumes gameplay", failures)

	shell.show_inventory("队员甲｜步枪 5/20")
	expect(
		shell.overlay_mode == GAME_SHELL_SCRIPT.OverlayMode.INVENTORY
		and shell._inventory_text.text.contains("队员甲"),
		"inventory overlay presents the supplied squad state",
		failures,
	)
	shell.update_inventory("队员甲｜步枪 4/20")
	expect(shell._inventory_text.text.contains("4/20"), "inventory state refreshes in place", failures)
	shell.close_active_overlay()

	var load_requests := [0]
	var restart_requests := [0]
	shell.load_requested.connect(func() -> void: load_requests[0] += 1)
	shell.restart_requested.connect(func() -> void: restart_requests[0] += 1)
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
		load_requests[0] == 1 and shell.is_failure_open() and paused,
		"load request keeps failure mode until Main confirms restoration",
		failures,
	)
	shell._restart_button.pressed.emit()
	expect(
		restart_requests[0] == 1 and not shell.is_overlay_open() and not paused,
		"restart releases failure pause before requesting a new level",
		failures,
	)

	var main: Node = MAIN_SCENE.instantiate()
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
		and main.edge_scroll_direction_for_position(Vector2(1280.1, 360.0), viewport_size).is_zero_approx(),
		"edge scrolling combines corners and rejects points outside the window",
		failures,
	)
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
