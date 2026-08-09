extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_INPUT_BINDINGS: Script = preload(
	"res://scripts/game_input_bindings.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Headless SceneTree windows may start at a tiny implementation-defined size.
	# Use the shipped viewport so CanvasLayer anchors and real GUI hit testing
	# exercise the same coordinates as a windowed player session.
	root.size = Vector2i(1280, 720)
	await process_frame
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
	main.runtime_settings["ruleset_mode"] = "classic"
	main.runtime_settings["difficulty_mode"] = "normal"
	main.runtime_settings["control_scheme"] = "classic"
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	main.switch_level(0, false, false)
	_disable_autonomous_world(main)

	_expect(
		not main.units.is_empty() and not main.escorts.is_empty(),
		"m000 exposes a player and rescue targets to the input gate",
	)
	if main.units.is_empty() or main.escorts.is_empty():
		_finish(main)
		return

	var player: Node2D = main.units[0]
	var player_spawn := player.position
	_expect(
		main.selected_units.size() == 1
			and main.selected_units[0] == player
			and bool(player.get("selected")),
		"m000 starts with its first commandable actor selected for immediate mouse movement",
	)
	var player_occupancy := (
		main.dynamic_occupancy.actors.get(
			int(player.get("scene_index")),
			{},
		) as Dictionary
	)
	_expect(
		bool(player.get("use_compact_navigation_footprint"))
			and player_occupancy.get("movement_offsets", []) == [Vector2i.ZERO],
		"m000 human navigation keeps one stable foot cell instead of changing with each animation frame",
	)
	main.clear_selection()
	main.level_camera.position = main.world_size * 0.5
	_push_key(KEY_F4, true)
	await process_frame
	_expect(
		main.selected_units.size() == 1
			and main.selected_units[0] == player
			and bool(player.get("selected")),
		"an actual F4 press selects m000 Qiangzi in his fixed character slot",
	)
	var expected_camera: Vector2 = main.LEVEL_VIEW.clamp_camera_center(
		player.position,
		main._gameplay_viewport_size(),
		main.level_camera.zoom.x,
		main.world_size,
	)
	_expect(
		main.level_camera.position.is_equal_approx(expected_camera),
		"keyboard actor selection recenters the level camera",
	)
	main.level_camera.force_update_scroll()
	await process_frame
	var safe_screen_rect: Rect2 = main.game_shell.gameplay_screen_rect(
		main.get_viewport_rect().size,
	)
	var camera_target_screen: Vector2 = (
		main.get_global_transform_with_canvas() * main.level_camera.position
	)
	_expect(
		camera_target_screen.distance_to(safe_screen_rect.get_center()) <= 1.0,
		(
			"camera targets are visually centred above the HUD instead of behind it "
			+ "(target=%s safe_center=%s offset=%s)"
		) % [
			str(camera_target_screen),
			str(safe_screen_rect.get_center()),
			str(main.level_camera.offset),
		],
	)

	var requested_destination := player.position + Vector2(128.0, 64.0)
	var route: PackedVector2Array = main.navigation_grid.find_path(
		player.position,
		requested_destination,
	)
	_expect(not route.is_empty(), "m000 has a nearby walkable mouse destination")
	if not route.is_empty():
		var destination := route[-1]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.pressed = true
		click.position = (
			main.get_global_transform_with_canvas() * destination
		)
		click.global_position = click.position
		# The synthetic event is already expressed in this viewport's local
		# coordinates. `true` prevents Viewport from treating it as an embedded
		# host-window coordinate and applying the stretch transform a second time.
		root.push_input(click, true)
		await process_frame
		_expect(
			(player.get("movement_path") as PackedVector2Array).size() > 0
				and (player.get("target_position") as Vector2).distance_to(destination)
					<= 24.0,
			(
				"an actual left-button press reaches the formation A* command path "
				+ "(path=%d target=%s expected=%s)"
				% [
					(player.get("movement_path") as PackedVector2Array).size(),
					str(player.get("target_position")),
					str(destination),
				]
			),
		)
		var modern_start := player.position
		main.runtime_settings["ruleset_mode"] = "modern"
		main._configure_actor_simulation_clock()
		main.simulation_coordinator.advance_exact_ticks(12)
		_expect(
			player.position.distance_to(modern_start) > 0.5,
			"the modern fixed-tick runtime turns the real mouse order into actor movement",
		)
		main.runtime_settings["ruleset_mode"] = "classic"
		main._configure_actor_simulation_clock()
		var click_release := InputEventMouseButton.new()
		click_release.button_index = MOUSE_BUTTON_LEFT
		click_release.button_mask = 0
		click_release.pressed = false
		click_release.position = click.position
		click_release.global_position = click.position
		root.push_input(click_release, true)
		await process_frame

	# The first grove surrounds the m000 spawn approach. Traverse out through
	# that vegetation cluster and return on the real Layer 3/dynamic grid; this
	# catches the old direction-frame footprint growth that trapped the player.
	player.call("cancel_path")
	player.set("original_crt_random_source", null)
	var grove_route: PackedVector2Array = main.dynamic_occupancy.find_path_for_scene(
		int(player.get("scene_index")),
		player.position,
		Vector2(672.0, 320.0),
	)
	var grove_outbound_complete := false
	if not grove_route.is_empty():
		player.call("issue_path", grove_route)
		grove_outbound_complete = _advance_unit_route(player, main.dynamic_occupancy, 600)
	var grove_return_complete := false
	if grove_outbound_complete:
		var grove_return: PackedVector2Array = main.dynamic_occupancy.find_path_for_scene(
			int(player.get("scene_index")),
			player.position,
			player_spawn,
		)
		if not grove_return.is_empty():
			player.call("issue_path", grove_return)
			grove_return_complete = _advance_unit_route(
				player,
				main.dynamic_occupancy,
				600,
			)
	_expect(
		grove_outbound_complete
			and grove_return_complete
			and player.position.distance_to(player_spawn) <= 1.0,
		(
			"m000 player traverses the first grove and returns without becoming "
			+ "trapped (out=%s return=%s position=%s spawn=%s route=%d)"
		) % [
			grove_outbound_complete,
			grove_return_complete,
			str(player.position),
			str(player_spawn),
			grove_route.size(),
		],
	)

	_push_key(KEY_M, true)
	await process_frame
	_expect(
		not main.game_shell.is_tactical_map_visible(),
		"the original M press phase does not open the minimap",
	)
	_push_key(KEY_M, false)
	await process_frame
	_expect(
		main.game_shell.is_tactical_map_visible(),
		"the original M release phase opens the live minimap",
	)
	player.call("cancel_path")
	var map_view: Control = main.game_shell._map_view
	var map_rect: Rect2 = map_view.call("_map_rect")
	var requested_world_position: Vector2 = (
		(main.world_size as Vector2) * Vector2(0.72, 0.98)
	)
	var requested_map_position: Vector2 = map_view.call(
		"_world_to_map",
		requested_world_position,
		map_rect,
	)
	var observed_map_button_events: Array[Dictionary] = []
	map_view.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				observed_map_button_events.append({
					"pressed": (event as InputEventMouseButton).pressed,
					"position": (event as InputEventMouseButton).position,
				})
	)
	main.camera_pan_velocity = Vector2(120.0, 120.0)
	var map_screen_position := (
		map_view.get_global_rect().position + requested_map_position
	)
	var map_motion := InputEventMouseMotion.new()
	map_motion.position = map_screen_position
	map_motion.global_position = map_screen_position
	root.push_input(map_motion, true)
	await process_frame
	var map_click := InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.button_mask = MOUSE_BUTTON_MASK_LEFT
	map_click.pressed = true
	map_click.position = map_screen_position
	map_click.global_position = map_click.position
	root.push_input(map_click, true)
	await process_frame
	var map_release := InputEventMouseButton.new()
	map_release.button_index = MOUSE_BUTTON_LEFT
	map_release.button_mask = 0
	map_release.pressed = false
	map_release.position = map_click.position
	map_release.global_position = map_release.position
	root.push_input(map_release, true)
	await process_frame
	var expected_map_camera: Vector2 = main.LEVEL_VIEW.clamp_camera_center(
		requested_world_position,
		main._gameplay_viewport_size(),
		main.level_camera.zoom.x,
		main.world_size,
	)
	main.level_camera.force_update_scroll()
	await process_frame
	camera_target_screen = (
		main.get_global_transform_with_canvas() * main.level_camera.position
	)
	_expect(
		main.level_camera.position.is_equal_approx(expected_map_camera)
			and main.camera_pan_velocity.is_zero_approx()
			and (player.get("movement_path") as PackedVector2Array).is_empty()
			and observed_map_button_events.size() == 2
			and camera_target_screen.distance_to(safe_screen_rect.get_center()) <= 1.0,
		(
			"an actual viewport-dispatched minimap click moves only the camera and "
			+ "cancels stale edge velocity "
			+ "(actual=%s expected=%s velocity=%s path=%d map_rect=%s global=%s "
			+ "events=%s)"
		)
			% [
				str(main.level_camera.position),
				str(expected_map_camera),
				str(main.camera_pan_velocity),
				(player.get("movement_path") as PackedVector2Array).size(),
				str(map_rect),
				str(map_view.get_global_rect()),
				str(observed_map_button_events),
			],
	)
	var minimap_button := (
		main.game_shell._original_hud_action_buttons["minimap"]
		as TextureButton
	)
	var observed_minimap_events: Array[Dictionary] = []
	minimap_button.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				observed_minimap_events.append({
					"pressed": (event as InputEventMouseButton).pressed,
					"position": (event as InputEventMouseButton).position,
				})
	)
	var minimap_button_position := minimap_button.get_global_rect().get_center()
	var minimap_motion := InputEventMouseMotion.new()
	minimap_motion.position = minimap_button_position
	minimap_motion.global_position = minimap_button_position
	root.push_input(minimap_motion, true)
	await process_frame
	var hovered_minimap_control: Control = root.gui_get_hovered_control()
	var minimap_press := InputEventMouseButton.new()
	minimap_press.button_index = MOUSE_BUTTON_LEFT
	minimap_press.button_mask = MOUSE_BUTTON_MASK_LEFT
	minimap_press.pressed = true
	minimap_press.position = minimap_button_position
	minimap_press.global_position = minimap_button_position
	root.push_input(minimap_press, true)
	await process_frame
	var minimap_release := InputEventMouseButton.new()
	minimap_release.button_index = MOUSE_BUTTON_LEFT
	minimap_release.button_mask = 0
	minimap_release.pressed = false
	minimap_release.position = minimap_button_position
	minimap_release.global_position = minimap_button_position
	root.push_input(minimap_release, true)
	await process_frame
	_expect(
		not main.game_shell.is_tactical_map_visible()
			and (player.get("movement_path") as PackedVector2Array).is_empty()
			and hovered_minimap_control == minimap_button
			and observed_minimap_events.size() == 2,
		"the bottom minimap button works and never submits a world movement order "
			+ "(visible=%s path=%d button=%s hovered=%s events=%s)"
				% [
					main.game_shell.is_tactical_map_visible(),
					(player.get("movement_path") as PackedVector2Array).size(),
					str(minimap_button.get_global_rect()),
					str(hovered_minimap_control.get_path()) if hovered_minimap_control != null else "<none>",
					str(observed_minimap_events),
				],
	)

	var rescue_target: Node2D
	for escort_value: Variant in main.escorts:
		var escort := escort_value as Node2D
		if int(escort.get("scene_index")) == 1427:
			rescue_target = escort
			break
	_expect(rescue_target != null, "m000 scene 1427 is a real rescue actor")
	if rescue_target != null:
		player.position = rescue_target.position
		player.call("cancel_path")
		_push_key(KEY_E, true)
		await process_frame
		_expect(
			bool(rescue_target.get("rescued_state"))
				and main.current_mission_state.is_objective_complete(
					"rescue_pengxin"
				),
			"an actual E press rescues scene 1427 and advances the mission",
		)

	# Original F2..F6 bindings are permanent character identities.  m001 is
	# deliberately sparse (Lao Zhao, Qiangzi and Gu Ming only), so compact-array
	# selection would incorrectly make F5 choose Lao Zhao.
	main.switch_level(1, false, false)
	_disable_autonomous_world(main)
	main.legacy_crt_random_trace_enabled = true
	main.legacy_crt_random_trace.clear()
	var gu_ming: Node2D
	for unit_value: Variant in main.units:
		var level_unit := unit_value as Node2D
		if int(level_unit.get("scene_index")) == 1994:
			gu_ming = level_unit
			break
	main.clear_selection()
	_push_key(KEY_F5, true)
	await process_frame
	_expect(
		gu_ming != null
			and main.selected_units.size() == 1
			and main.selected_units[0] == gu_ming
			and _trace_contains_call_site(
				main,
				0x0005D6D6,
			),
		(
			"m001 actual F5 press selects fixed Gu Ming scene 1994 despite "
			+ "missing slots and consumes his original selection variant"
		),
	)

	main.switch_level(2, false, false)
	_disable_autonomous_world(main)
	main.legacy_crt_random_trace_enabled = true
	main.legacy_crt_random_trace.clear()
	var lao_zhao: Node2D
	var distant_guard: Node2D
	for unit_value: Variant in main.units:
		var level_unit := unit_value as Node2D
		if int(level_unit.get("scene_index")) == 886:
			lao_zhao = level_unit
	for enemy_value: Variant in main.enemies:
		var level_enemy := enemy_value as Node2D
		if int(level_enemy.get("scene_index")) == 840:
			distant_guard = level_enemy
	main.clear_selection()
	_push_key(KEY_F2, true)
	await process_frame
	_push_key(KEY_5, true)
	await process_frame
	_expect(
		lao_zhao != null
			and distant_guard != null
			and main.selected_units == [lao_zhao]
			and int(
				(lao_zhao.get("weapon_profile") as Dictionary).get(
					"attack_type", 0
				)
			) == 1,
		"m002 real F2 and digit 5 input select Lao Zhao and his pistol",
	)
	_expect(
		lao_zhao != null
			and _trace_contains_call_site(
				main,
				0x0005D64F,
			),
		"m002 actual F2 selection consumes Lao Zhao's original voice variant",
	)
	if lao_zhao != null and distant_guard != null:
		main.level_camera.position = distant_guard.position
		main.clamp_level_camera()
		var forced_click := InputEventMouseButton.new()
		forced_click.button_index = MOUSE_BUTTON_LEFT
		forced_click.pressed = true
		forced_click.ctrl_pressed = true
		forced_click.position = (
			main.get_global_transform_with_canvas() * distant_guard.position
		)
		root.push_input(forced_click, true)
		await process_frame
		_expect(
			lao_zhao.get("combat_target") == distant_guard
				and bool(lao_zhao.get("combat_target_forced"))
				and int(
					lao_zhao.get("original_pending_acknowledgement_count")
				) == 1,
			(
				"Ctrl-modified viewport click reaches the original forced-target "
				+ "command path and queues one acknowledgement"
			),
		)

	_finish(main)


func _disable_autonomous_world(main: Node) -> void:
	# The frame-input contract is about key/mouse routing, not the independently
	# ticking ambient-particle simulation.  That field can consume more than 500
	# original CRT rand() draws per physics frame; on a loaded CI worker it could
	# evict the just-recorded actor voice draw from the bounded diagnostic trace
	# before the following assertion, making the test timing-dependent.
	if main.legacy_ambient_particle_field != null:
		main.legacy_ambient_particle_field.set_process(false)
		main.legacy_ambient_particle_field.set_physics_process(false)
	if main.mission_direction_runtime != null:
		main.mission_direction_runtime.free()
		main.mission_direction_runtime = null
	if main.mission_ai_coordinator != null:
		main.mission_ai_coordinator.free()
		main.mission_ai_coordinator = null
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		actor.set_process(false)
		actor.set_physics_process(false)


func _push_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	root.push_input(event)


func _advance_unit_route(
	unit: Node2D,
	occupancy: RefCounted,
	maximum_ticks: int,
) -> bool:
	for _tick: int in range(maximum_ticks):
		occupancy.set("accepted_moves_physics_frame", -1)
		unit.call("_physics_process", 1.0 / 60.0)
		var path := unit.get("movement_path") as PackedVector2Array
		if int(unit.get("movement_path_index")) >= path.size():
			return true
	return false


func _trace_contains_call_site(
	main: Node,
	call_site_rva: int,
) -> bool:
	for draw_value: Variant in main.legacy_crt_random_trace:
		if not draw_value is Dictionary:
			continue
		var draw := draw_value as Dictionary
		if int(draw.get("call_site_rva", 0)) == call_site_rva:
			return true
	return false


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _finish(main: Node) -> void:
	root.remove_child(main)
	main.free()
	if failures.is_empty():
		print(
			"Real frame-input world test passed (%d checks, no global pointer control)."
				% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
