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
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
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
		main.get_viewport_rect().size,
		main.level_camera.zoom.x,
		main.world_size,
	)
	_expect(
		main.level_camera.position.is_equal_approx(expected_camera),
		"keyboard actor selection recenters the level camera",
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
		click.pressed = true
		click.position = (
			main.get_global_transform_with_canvas() * destination
		)
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
	_push_key(KEY_M, true)
	await process_frame
	_push_key(KEY_M, false)
	await process_frame
	_expect(
		not main.game_shell.is_tactical_map_visible(),
		"a second complete M transition closes the minimap",
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
			and main.selected_units[0] == gu_ming,
		"m001 actual F5 press selects fixed Gu Ming scene 1994 despite missing slots",
	)

	main.switch_level(2, false, false)
	_disable_autonomous_world(main)
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
				and bool(lao_zhao.get("combat_target_forced")),
			"Ctrl-modified viewport click reaches the original forced-target command path",
		)

	_finish(main)


func _disable_autonomous_world(main: Node) -> void:
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
