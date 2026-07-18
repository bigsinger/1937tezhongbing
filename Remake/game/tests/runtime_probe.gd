extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT_ARGUMENT_PREFIX := "--output-dir="
const SAMPLE_FRAME_COUNT := 360
const CAMERA_PAN_SECONDS := 0.75
const UNIT_MOVE_TIMEOUT_SECONDS := 6.5
const RECOVERED_ACTIONS: Array[String] = [
	"stand",
	"stand_action",
	"walk",
	"run",
	"death",
	"pistol_attack",
	"crawl",
	"rifle_attack",
	"machine_gun_attack",
	"grenade_attack",
	"dagger_attack",
]

var failures: Array[String] = []
var frame_intervals_ms: Array[float] = []
var check_count := 0
var output_directory := ""
var peak_draw_calls := 0.0
var peak_objects_drawn := 0.0


func _init() -> void:
	output_directory = parse_output_directory(OS.get_cmdline_user_args())
	call_deferred("run_probe")


func run_probe() -> void:
	var scene_load_started := Time.get_ticks_usec()
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	var scene_ready_ms := elapsed_ms(scene_load_started)

	var first_frame_started := Time.get_ticks_usec()
	await process_frame
	await RenderingServer.frame_post_draw
	var first_rendered_frame_ms := elapsed_ms(first_frame_started)

	expect(main.terrain_loaded, "real m000 terrain loads", failures)
	expect(main.world_size == Vector2(4960.0, 2240.0), "real terrain dimensions match", failures)
	expect(main.navigation_grid != null, "real m000 navigation grid loads", failures)
	if main.navigation_grid != null:
		expect(
			main.navigation_grid.dimensions == Vector2i(155, 140),
			"m000 navigation dimensions match its VWF grid",
			failures,
		)
		expect(
			main.navigation_grid.cell_size == Vector2i(32, 16),
			"m000 navigation uses the recovered 32x16 world cells",
			failures,
		)
	expect(
		str(main.current_mission.get("title", "")) == "营救行动",
		"m000 recovered mission graph loads",
		failures
	)
	expect(
		main.current_mission_state.display_lines().size() == 4,
		"mission panel exposes the title and three objectives",
		failures
	)
	expect(
		main.imported_entity_count + main.playable_entities.size() == 1630,
		"all m000 entity records become scenery or playable units",
		failures
	)
	expect(not main.units.is_empty(), "m000 exposes at least one controllable squad unit", failures)
	expect(main.enemies.size() == 54, "all 54 m000 enemy actors are live AI units", failures)
	var patrolling_enemy_count := 0
	for enemy in main.enemies:
		if enemy.patrol_enabled:
			patrolling_enemy_count += 1
	expect(
		patrolling_enemy_count == 43,
		"all 43 non-empty m000 enemy patrol routes are active",
		failures,
	)
	expect(
		main.dynamic_occupancy != null
		and main.dynamic_occupancy.actors.size() == main.units.size() + main.enemies.size(),
		"the squad and every enemy share one dynamic occupancy overlay",
		failures,
	)
	expect(
		main.units[0].movement_groups.size() == 8,
		"the controllable unit loads eight decoded movement directions",
		failures
	)
	expect(
		str(main.units[0].movement_groups[0]["action_key"]) == "run",
		"movement uses the decoded running action instead of a positional group guess",
		failures
	)
	expect(
		main.units[0].sprite_texture is AtlasTexture,
		"movement frames use a shared direction atlas",
		failures
	)
	var first_entity := main.playable_entities[main.units[0].display_name] as Dictionary
	var recovered_group_count := 0
	var recovered_frame_count := 0
	var recovered_actions: Dictionary = {}
	for action_key: String in RECOVERED_ACTIONS:
		var groups: Array[Dictionary] = main.load_entity_action_groups(first_entity, action_key)
		recovered_actions[action_key] = groups
		recovered_group_count += groups.size()
		for group: Dictionary in groups:
			recovered_frame_count += (group["frames"] as Array[Texture2D]).size()
	expect(
		recovered_group_count == 88,
		"the controllable sprite loads all 11 recovered actions in eight directions",
		failures,
	)
	expect(
		recovered_frame_count == 480,
		"the controllable sprite exposes all 480 recovered action frames",
		failures,
	)
	expect(
		(
			int((recovered_actions["run"] as Array[Dictionary])[0]["frame_hold_ticks"]) == 1
			and int((recovered_actions["walk"] as Array[Dictionary])[0]["frame_hold_ticks"]) == 2
			and int((recovered_actions["crawl"] as Array[Dictionary])[0]["frame_hold_ticks"]) == 3
		),
		"run, walk, and crawl preserve their recovered 1/2/3 tick frame holds",
		failures,
	)
	expect(main.level_camera != null, "level camera is active", failures)
	var initial_unit_positions: Array[Vector2] = []
	for unit in main.units:
		initial_unit_positions.append(unit.position)
	var initial_enemy_positions: Dictionary = {}
	for enemy in main.enemies:
		initial_enemy_positions[enemy.scene_index] = enemy.position
	var source_movement_before: PackedInt64Array = (
		(main.navigation_grid.layers[3] as PackedInt64Array).duplicate()
	)
	var source_sight_before: PackedInt64Array = (
		(main.navigation_grid.layers[2] as PackedInt64Array).duplicate()
	)

	var camera_start: Vector2 = main.level_camera.position
	Input.action_press("ui_right")
	await create_timer(CAMERA_PAN_SECONDS).timeout
	Input.action_release("ui_right")
	var camera_pan_distance: float = main.level_camera.position.x - camera_start.x
	expect(camera_pan_distance > 200.0, "keyboard camera pan advances at runtime", failures)

	var zoom_before: float = main.level_camera.zoom.x
	var zoom_event := InputEventMouseButton.new()
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	zoom_event.pressed = true
	zoom_event.position = root.size * 0.5
	main._unhandled_input(zoom_event)
	var zoom_after: float = main.level_camera.zoom.x
	expect(zoom_after < zoom_before, "mouse wheel zoom changes the camera", failures)

	var drag_start: Vector2 = main.level_camera.position
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_MIDDLE
	drag_press.pressed = true
	drag_press.position = root.size * 0.5
	main._unhandled_input(drag_press)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = Vector2(90.0, 45.0)
	drag_motion.position = root.size * 0.5 + drag_motion.relative
	main._unhandled_input(drag_motion)
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_MIDDLE
	drag_release.pressed = false
	main._unhandled_input(drag_release)
	expect(
		main.level_camera.position.distance_to(drag_start) > 40.0,
		"middle-button drag moves the camera",
		failures
	)

	main.level_camera.position = Vector2(-1000.0, -1000.0)
	main.clamp_level_camera()
	expect(
		main.level_camera.position.x + 0.01 >= root.size.x / (2.0 * zoom_after),
		"camera clamps to the terrain left edge",
		failures
	)
	expect(
		main.level_camera.position.y + 0.01 >= root.size.y / (2.0 * zoom_after),
		"camera clamps to the terrain top edge",
		failures
	)

	main.clear_selection()
	for unit in main.units:
		main.handle_selection(unit.position, true)
	expect(
		main.selected_units.size() == main.units.size(),
		"multi-selection selects the full squad",
		failures
	)
	main.issue_formation_move(Vector2(650.0, 620.0))
	for unit in main.units:
		expect(
			not unit.movement_path.is_empty(), "A* emits a waypoint path for the squad", failures
		)
		expect(
			path_is_clear(main.navigation_grid, unit.position, unit.movement_path),
			"the emitted squad path does not cross a real Layer 3 obstacle",
			failures,
		)
	var movement_started := Time.get_ticks_usec()
	var saw_animated_frame := false
	while not squad_arrived(main) and elapsed_seconds(movement_started) < UNIT_MOVE_TIMEOUT_SECONDS:
		await process_frame
		for unit in main.units:
			if unit.animation_frame_index != 0:
				saw_animated_frame = true
	var unit_move_ms := elapsed_ms(movement_started)
	expect(squad_arrived(main), "the full squad reaches its formation targets", failures)
	expect(saw_animated_frame, "movement advances imported SPR animation frames", failures)
	for unit in main.units:
		expect(
			unit.z_index == clampi(int(unit.position.y) + 1, -4096, 4095),
			"unit z-order follows y",
			failures
		)

	main.level_camera.zoom = Vector2.ONE
	main.level_camera.position = Vector2(root.size.x * 0.5, main.world_size.y * 0.5)
	main.clamp_level_camera()
	var scan_start_x: float = main.level_camera.position.x
	Input.action_press("ui_right")
	await sample_rendered_frames(SAMPLE_FRAME_COUNT)
	Input.action_release("ui_right")
	var scan_distance: float = main.level_camera.position.x - scan_start_x
	expect(scan_distance > 3300.0, "sustained camera scan crosses most of m000", failures)
	var moved_enemy_count := 0
	for enemy in main.enemies:
		if (
			initial_enemy_positions.has(enemy.scene_index)
			and enemy.position.distance_squared_to(initial_enemy_positions[enemy.scene_index]) > 4.0
		):
			moved_enemy_count += 1
	expect(moved_enemy_count > 0, "enemy patrol AI advances on real m000 routes", failures)
	expect(
		(
			(main.navigation_grid.layers[3] as PackedInt64Array) == source_movement_before
			and (main.navigation_grid.layers[2] as PackedInt64Array) == source_sight_before
		),
		"runtime movement never mutates the imported Layer 2 or Layer 3 snapshots",
		failures,
	)
	var frame_metrics := calculate_frame_metrics(frame_intervals_ms)
	var fps_now := Performance.get_monitor(Performance.TIME_FPS)
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects_drawn := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)

	var reset_event := InputEventKey.new()
	reset_event.keycode = KEY_R
	reset_event.pressed = true
	main._unhandled_input(reset_event)
	expect(main.selected_units.size() == 1, "R reset restores the initial selection", failures)
	expect(
		main.units.size() == initial_unit_positions.size(), "R reset restores squad size", failures
	)
	for index in range(main.units.size()):
		expect(
			main.units[index].position == initial_unit_positions[index],
			"R reset restores an original unit position",
			failures
		)
	main.level_camera.position = Vector2(root.size.x * 0.5, root.size.y * 0.5)
	main.clamp_level_camera()
	main.level_camera.reset_smoothing()

	var screenshot_path := ""
	var report_path := ""
	if not output_directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		expect(directory_error == OK, "probe output directory is writable", failures)
		if directory_error == OK:
			await process_frame
			await RenderingServer.frame_post_draw
			screenshot_path = output_directory.path_join("runtime-probe.png")
			var screenshot := root.get_texture().get_image()
			expect(screenshot.save_png(screenshot_path) == OK, "runtime screenshot saves", failures)
			report_path = output_directory.path_join("runtime-probe.json")

	var report := {
		"schema_version": 1,
		"godot_version": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_current_rendering_method(),
		"scene_ready_ms": scene_ready_ms,
		"first_rendered_frame_ms": first_rendered_frame_ms,
		"camera_pan_distance": camera_pan_distance,
		"camera_scan_distance": scan_distance,
		"unit_move_ms": unit_move_ms,
		"sample_frames": frame_intervals_ms.size(),
		"frame_interval_ms": frame_metrics,
		"reported_fps": fps_now,
		"draw_calls": draw_calls,
		"objects_drawn": objects_drawn,
		"peak_draw_calls": peak_draw_calls,
		"peak_objects_drawn": peak_objects_drawn,
		"terrain_size": [int(main.world_size.x), int(main.world_size.y)],
		"entity_count": main.imported_entity_count,
		"playable_entity_count": main.playable_entities.size(),
		"squad_size": main.units.size(),
		"enemy_count": main.enemies.size(),
		"patrolling_enemy_count": patrolling_enemy_count,
		"moved_enemy_count": moved_enemy_count,
		"checks": check_count,
		"failures": failures,
		"screenshot": screenshot_path,
	}
	if not report_path.is_empty():
		write_report(report_path, report)

	print("RUNTIME_PROBE_RESULT %s" % JSON.stringify(report))
	if failures.is_empty():
		print("Godot real-resource runtime probe passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func sample_rendered_frames(frame_count: int) -> void:
	frame_intervals_ms.clear()
	peak_draw_calls = 0.0
	peak_objects_drawn = 0.0
	var previous_tick := Time.get_ticks_usec()
	for index in range(frame_count + 12):
		await process_frame
		var current_tick := Time.get_ticks_usec()
		if index >= 12:
			frame_intervals_ms.append(float(current_tick - previous_tick) / 1000.0)
			peak_draw_calls = maxf(
				peak_draw_calls,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			)
			peak_objects_drawn = maxf(
				peak_objects_drawn,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			)
		previous_tick = current_tick


func calculate_frame_metrics(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"average": 0.0, "p95": 0.0, "p99": 0.0, "maximum": 0.0}
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var total := 0.0
	var frames_over_20_ms := 0
	var frames_over_25_ms := 0
	for sample in sorted_samples:
		total += sample
		if sample > 20.0:
			frames_over_20_ms += 1
		if sample > 25.0:
			frames_over_25_ms += 1
	return {
		"average": total / sorted_samples.size(),
		"p95": percentile(sorted_samples, 0.95),
		"p99": percentile(sorted_samples, 0.99),
		"maximum": sorted_samples[-1],
		"frames_over_20_ms": frames_over_20_ms,
		"frames_over_25_ms": frames_over_25_ms,
	}


func percentile(sorted_samples: Array[float], fraction: float) -> float:
	var index := ceili(float(sorted_samples.size()) * fraction) - 1
	return sorted_samples[clampi(index, 0, sorted_samples.size() - 1)]


func squad_arrived(main) -> bool:
	for unit in main.units:
		if unit.position.distance_squared_to(unit.target_position) > 1.0:
			return false
	return true


func path_is_clear(
	navigation: NavigationGridData,
	world_start: Vector2,
	path: PackedVector2Array,
) -> bool:
	if navigation == null:
		return false
	var segment_start := world_start
	for segment_end: Vector2 in path:
		var steps := maxi(ceili(segment_start.distance_to(segment_end) / 4.0), 1)
		for step in range(steps + 1):
			var sample := segment_start.lerp(segment_end, float(step) / float(steps))
			if navigation.is_movement_blocked(
				navigation.world_to_cell(sample), navigation.ignored_scene_indices
			):
				return false
		segment_start = segment_end
	return true


func elapsed_ms(start_tick: int) -> float:
	return float(Time.get_ticks_usec() - start_tick) / 1000.0


func elapsed_seconds(start_tick: int) -> float:
	return float(Time.get_ticks_usec() - start_tick) / 1000000.0


func parse_output_directory(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX).simplify_path()
	return ""


func write_report(path: String, report: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("runtime report opens for writing")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")


func expect(value: bool, description: String, output_failures: Array[String]) -> void:
	check_count += 1
	if not value:
		output_failures.append(description)
