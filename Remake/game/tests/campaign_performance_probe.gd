extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_INPUT_BINDINGS: Script = preload(
	"res://scripts/game_input_bindings.gd"
)
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const RUNTIME_FRAME_CLASSIFIER: Script = preload(
	"res://scripts/runtime_frame_classifier.gd"
)

const LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]
const DEFAULT_DURATION_SECONDS := 48.0
const DEFAULT_PASSES := 1
const DEFAULT_MAX_P95_MS := 20.0
const DEFAULT_MAX_PER_LEVEL_P95_MS := 20.0
const DEFAULT_MAX_P99_MS := 25.0
const DEFAULT_MAX_PROCESS_P95_MS := 20.0
const DEFAULT_MAX_PHYSICS_P95_MS := 20.0
const DEFAULT_MAX_UI_ACTION_MS := 25.0
const DEFAULT_MAX_COLD_LEVEL_LOAD_MS := 6000.0
const DEFAULT_MAX_WARM_LEVEL_LOAD_MS := 3500.0
## Per-level P99 is a release-strength assertion only after enough rendered
## frames have been observed. A short 12-level smoke profile has roughly
## 180 samples per mission, where one intentional menu-opening frame can move
## P99 by several milliseconds. Aggregate P99, per-level P95 and >50 ms spike
## checks still apply to every profile.
const DEFAULT_MINIMUM_PER_LEVEL_P99_SAMPLES := 600
const DEFAULT_MAX_OVER_50_PER_LEVEL := 0
const DEFAULT_MAX_SECOND_PASS_GROWTH_MIB := 128.0
const MAX_STORED_SAMPLES_PER_LEVEL := 20_000
const MEASUREMENT_FRAME_CAP := 60
const OUTPUT_PREFIX := "--output="

var duration_seconds := DEFAULT_DURATION_SECONDS
var pass_count := DEFAULT_PASSES
var maximum_p95_ms := DEFAULT_MAX_P95_MS
var maximum_per_level_p95_ms := DEFAULT_MAX_PER_LEVEL_P95_MS
var maximum_p99_ms := DEFAULT_MAX_P99_MS
var maximum_process_p95_ms := DEFAULT_MAX_PROCESS_P95_MS
var maximum_physics_p95_ms := DEFAULT_MAX_PHYSICS_P95_MS
var maximum_ui_action_ms := DEFAULT_MAX_UI_ACTION_MS
var maximum_cold_level_load_ms := DEFAULT_MAX_COLD_LEVEL_LOAD_MS
var maximum_warm_level_load_ms := DEFAULT_MAX_WARM_LEVEL_LOAD_MS
var minimum_per_level_p99_samples := (
	DEFAULT_MINIMUM_PER_LEVEL_P99_SAMPLES
)
var maximum_over_50_per_level := DEFAULT_MAX_OVER_50_PER_LEVEL
var maximum_second_pass_growth_mib := DEFAULT_MAX_SECOND_PASS_GROWTH_MIB
var output_path := ""
var profile_id := "twelve-level-windowed-short"
var selected_level_ids: Array[String] = LEVEL_IDS.duplicate()

var failures: Array[String] = []
var check_count := 0
var viewport_input_events := 0
var modal_dismissals := 0
var level_samples: Dictionary = {}
var level_sample_totals: Dictionary = {}
var level_visits: Array[Dictionary] = []
var level_peak_draw_calls: Dictionary = {}
var level_peak_objects_drawn: Dictionary = {}
var level_peak_object_count: Dictionary = {}
var level_peak_static_memory: Dictionary = {}
var level_process_samples: Dictionary = {}
var level_physics_samples: Dictionary = {}
var level_process_sample_totals: Dictionary = {}
var level_physics_sample_totals: Dictionary = {}
var level_host_scheduler_stalls: Dictionary = {}
var level_unexplained_over_50: Dictionary = {}
var pass_memory_bytes: Array[int] = []
var isolated_save_directory := ""
var slow_frames: Array[Dictionary] = []
var last_nearby_select_ms := 0.0
var last_nearby_click_ms := 0.0
var first_action_latencies_ms: Dictionary = {}
var previous_max_fps := 0
var previous_vsync_mode := DisplayServer.VSYNC_ENABLED
var stability_mode := false
var soak_save_count := 0
var soak_load_count := 0
var last_stability_progress_usec := 0
var actor_physics_profile_enabled := false
var diagnostic_hide_world := false
var diagnostic_disable_reservations := false


func _init() -> void:
	_parse_arguments(OS.get_cmdline_user_args())
	call_deferred("_run")


func _run() -> void:
	_expect(
		DisplayServer.get_name() != "headless" or stability_mode,
		"campaign performance probe requires a real window unless stability mode is active",
	)
	_expect(duration_seconds >= 24.0, "sample duration covers every formal mission")
	_expect(pass_count >= 1, "performance pass count is positive")
	for level_id: String in selected_level_ids:
		level_samples[level_id] = []
		level_sample_totals[level_id] = 0
		level_process_samples[level_id] = []
		level_physics_samples[level_id] = []
		level_process_sample_totals[level_id] = 0
		level_physics_sample_totals[level_id] = 0
		level_host_scheduler_stalls[level_id] = 0
		level_unexplained_over_50[level_id] = 0
		level_peak_draw_calls[level_id] = 0.0
		level_peak_objects_drawn[level_id] = 0.0
		level_peak_object_count[level_id] = 0.0
		level_peak_static_memory[level_id] = 0.0
	previous_max_fps = Engine.max_fps
	previous_vsync_mode = DisplayServer.window_get_vsync_mode()
	# Match the shipped product policy and the versioned 1920x1080 baseline.
	# An uncapped Compatibility-renderer window can starve Godot's fixed physics
	# scheduler on Windows, which batches catch-up ticks into apparent 400 ms
	# stalls. That measures an unsupported benchmark configuration rather than
	# the game players receive (settings schema 8 defaults to a 60 FPS cap).
	Engine.max_fps = MEASUREMENT_FRAME_CAP
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	main.qa_simulation_only_world_visuals = stability_mode
	_expect(
		bool(main.qa_simulation_only_world_visuals) == stability_mode,
		"static-world visual policy matches the selected QA lane",
	)
	if diagnostic_hide_world:
		# Diagnostic-only lane used to distinguish simulation cost from deferred
		# CanvasItem sorting/render submission. It is never enabled by release gates.
		main.visible = false
	_write_probe_progress("main_ready", {})
	_dismiss_all_media(main)
	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	paused = false
	main.runtime_settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	# The release performance budget targets the modern execution policy. The
	# classic ruleset remains covered by deterministic parity tests, while its
	# intentionally lockstep enemy sensing is not a representative modern frame
	# scheduler workload.
	main.runtime_settings["ruleset_mode"] = "modern"
	main.runtime_settings["difficulty_mode"] = "normal"
	main.runtime_settings["show_briefings"] = false
	isolated_save_directory = (
		"user://qa-campaign-performance/%d-%d"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	main.save_store = GAME_SAVE_STORE.new(isolated_save_directory)
	main.game_settings = null
	main.campaign_progress = GAME_SAVE_STORE.default_campaign()

	var sample_started_usec := Time.get_ticks_usec()
	var per_visit_seconds := (
		duration_seconds / float(pass_count * selected_level_ids.size())
	)
	for pass_index: int in range(pass_count):
		for level_id: String in selected_level_ids:
			_write_probe_progress(
				"visit_start",
				{"pass_index": pass_index, "level_id": level_id},
			)
			await _sample_level_visit(
				main,
				LEVEL_IDS.find(level_id),
				pass_index,
				per_visit_seconds,
			)
			_write_probe_progress(
				"visit_complete",
				{"pass_index": pass_index, "level_id": level_id},
			)
			if stability_mode:
				_write_probe_progress(
					"save_roundtrip_start",
					{"pass_index": pass_index, "level_id": level_id},
				)
				_exercise_stability_save_roundtrip(main, pass_index, level_id)
				_write_probe_progress(
					"save_roundtrip_complete",
					{"pass_index": pass_index, "level_id": level_id},
				)
				await process_frame
		pass_memory_bytes.append(OS.get_static_memory_usage())

	var sampled_wall_seconds := (
		float(Time.get_ticks_usec() - sample_started_usec) / 1_000_000.0
	)
	var levels: Array[Dictionary] = []
	var aggregate_samples: Array[float] = []
	for level_id: String in selected_level_ids:
		var samples := level_samples[level_id] as Array
		aggregate_samples.append_array(samples)
		var metrics := _frame_metrics(samples)
		var process_metrics := _frame_metrics(level_process_samples[level_id])
		var physics_metrics := _frame_metrics(level_physics_samples[level_id])
		var visits: Array[Dictionary] = []
		var moved_enemy_max := 0
		var input_event_count := 0
		for visit: Dictionary in level_visits:
			if str(visit["level_id"]) != level_id:
				continue
			visits.append(visit)
			moved_enemy_max = maxi(moved_enemy_max, int(visit["moved_enemy_count"]))
			input_event_count += int(visit["viewport_input_events"])
			_expect(
				int(visit["moved_enemy_count"]) > 0
					or int(visit["enemy_count"]) == 0,
				"%s visit %d has live AI movement" % [
					level_id,
					int(visit["pass_index"]) + 1,
				],
			)
			var maximum_load_ms := (
				maximum_cold_level_load_ms
				if int(visit["pass_index"]) == 0
				else maximum_warm_level_load_ms
			)
			_expect(
				float(visit["load_ms"]) <= maximum_load_ms,
				"%s pass %d level reconstruction exceeds %.1f ms" % [
					level_id,
					int(visit["pass_index"]) + 1,
					maximum_load_ms,
				],
			)
		var minimum_expected_samples := maxi(
			30,
			floori(
				maxf(
					per_visit_seconds - _warmup_seconds(per_visit_seconds),
					0.5,
				)
				* float(pass_count)
				* 30.0
			),
		)
		_expect(
			int(metrics["sample_count"]) >= minimum_expected_samples,
			"%s has enough steady rendered-frame samples" % level_id,
		)
		_expect(
			float(metrics["p95_ms"]) <= maximum_per_level_p95_ms,
			"%s P95 exceeds %.3f ms" % [
				level_id,
				maximum_per_level_p95_ms,
			],
		)
		_expect(
			float(process_metrics["p95_ms"]) <= maximum_process_p95_ms,
			"%s process P95 exceeds %.3f ms" % [
				level_id,
				maximum_process_p95_ms,
			],
		)
		_expect(
			float(physics_metrics["p95_ms"]) <= maximum_physics_p95_ms,
			"%s physics P95 exceeds %.3f ms" % [
				level_id,
				maximum_physics_p95_ms,
			],
		)
		if int(metrics["sample_count"]) >= minimum_per_level_p99_samples:
			_expect(
				float(metrics["p99_ms"]) <= maximum_p99_ms,
				"%s P99 exceeds %.3f ms" % [level_id, maximum_p99_ms],
			)
		_expect(
			int(level_unexplained_over_50[level_id])
				<= maximum_over_50_per_level,
			"%s has no unexplained >50 ms steady-frame spikes" % level_id,
		)
		levels.append(
			{
				"level_id": level_id,
				"metrics": metrics,
				"observed_frame_samples": int(level_sample_totals[level_id]),
				"peak_draw_calls": float(level_peak_draw_calls[level_id]),
				"peak_objects_drawn": float(level_peak_objects_drawn[level_id]),
				"peak_object_count": float(level_peak_object_count[level_id]),
				"peak_static_memory_bytes": float(level_peak_static_memory[level_id]),
				"process_metrics": process_metrics,
				"physics_metrics": physics_metrics,
				"host_scheduler_stalls": int(
					level_host_scheduler_stalls[level_id]
				),
				"unexplained_frames_over_50_ms": int(
					level_unexplained_over_50[level_id]
				),
				"moved_enemy_max": moved_enemy_max,
				"viewport_input_events": input_event_count,
				"visits": visits,
			}
		)

	var second_pass_growth_bytes := 0
	if pass_memory_bytes.size() >= 2:
		second_pass_growth_bytes = (
			pass_memory_bytes[-1] - pass_memory_bytes[-2]
		)
		_expect(
			float(second_pass_growth_bytes) / (1024.0 * 1024.0)
				<= maximum_second_pass_growth_mib,
			"second twelve-level pass has bounded static-memory growth",
		)
	_expect(
		viewport_input_events >= pass_count * selected_level_ids.size() * 6,
		"probe submits a substantial target-viewport input workload",
	)
	var aggregate_metrics := _frame_metrics(aggregate_samples)
	_expect(
		float(aggregate_metrics["p95_ms"]) <= maximum_p95_ms,
		"aggregate P95 exceeds %.3f ms" % maximum_p95_ms,
	)
	_expect(
		float(aggregate_metrics["p99_ms"]) <= maximum_p99_ms,
		"aggregate P99 exceeds %.3f ms" % maximum_p99_ms,
	)
	for action_name: String in [
		"weapons_W", "items_A", "sight_S_enemy_click", "stance_C",
	]:
		_expect(
			first_action_latencies_ms.has(action_name)
				and float(first_action_latencies_ms[action_name]) <= maximum_ui_action_ms,
			"%s first interaction exceeds %.3f ms" % [
				action_name, maximum_ui_action_ms,
			],
		)

	var report := {
		"schema_version": 2,
		"profile_id": profile_id,
		"content_profile": "repository-mod-12-level-20260729",
		"levels": levels,
		"level_ids": selected_level_ids,
		"pass_count": pass_count,
		"requested_sample_seconds": duration_seconds,
		"sampled_wall_seconds": sampled_wall_seconds,
		"per_visit_seconds": per_visit_seconds,
		"aggregate_metrics": aggregate_metrics,
		"first_action_latencies_ms": first_action_latencies_ms,
		"thresholds": {
			"maximum_p95_ms": maximum_p95_ms,
			"maximum_per_level_p95_ms": maximum_per_level_p95_ms,
			"maximum_p99_ms": maximum_p99_ms,
			"maximum_process_p95_ms": maximum_process_p95_ms,
			"maximum_physics_p95_ms": maximum_physics_p95_ms,
			"maximum_ui_action_ms": maximum_ui_action_ms,
			"maximum_cold_level_load_ms": maximum_cold_level_load_ms,
			"maximum_warm_level_load_ms": maximum_warm_level_load_ms,
			"minimum_per_level_p99_samples": (
				minimum_per_level_p99_samples
			),
			"maximum_over_50_per_level": maximum_over_50_per_level,
			"maximum_second_pass_growth_mib": maximum_second_pass_growth_mib,
		},
		"viewport_input_events": viewport_input_events,
		"global_pointer_control": false,
		"stability_mode": stability_mode,
		"stability_io": {
			"save_count": soak_save_count,
			"load_count": soak_load_count,
		},
		"modal_dismissals": modal_dismissals,
		"memory": {
			"pass_end_bytes": pass_memory_bytes,
			"second_pass_growth_bytes": second_pass_growth_bytes,
			"static_peak_bytes": OS.get_static_memory_peak_usage(),
		},
		"runtime": {
			"frame_cap_during_measurement": MEASUREMENT_FRAME_CAP,
			"vsync_during_measurement": "disabled",
			"simulation_only_world_visuals": bool(
				main.qa_simulation_only_world_visuals
			),
			"display_backend": DisplayServer.get_name(),
			"godot_version": str(Engine.get_version_info().get("string", "")),
			"os_name": OS.get_name(),
			"os_version": OS.get_version(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"video_adapter": RenderingServer.get_video_adapter_name(),
			"viewport_width": int(root.size.x),
			"viewport_height": int(root.size.y),
			"window_mode": int(DisplayServer.window_get_mode()),
			"window_width": DisplayServer.window_get_size().x,
			"window_height": DisplayServer.window_get_size().y,
			"screen_width": DisplayServer.screen_get_size().x,
			"screen_height": DisplayServer.screen_get_size().y,
			"screen_dpi": DisplayServer.screen_get_dpi(),
			"screen_scale": DisplayServer.screen_get_scale(),
		},
		"slow_frames": slow_frames,
		"checks": check_count,
		"failures": failures,
	}
	if not output_path.is_empty():
		_write_report(output_path, report)

	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	paused = false
	root.remove_child(main)
	main.free()
	await process_frame
	Engine.max_fps = previous_max_fps
	DisplayServer.window_set_vsync_mode(previous_vsync_mode)
	_cleanup_isolated_save_directory()

	print("CAMPAIGN_PERFORMANCE_RESULT %s" % JSON.stringify(report))
	if failures.is_empty():
		print(
			(
				"Twelve-level campaign performance passed "
				+ "(%d checks, %d samples, %.1f seconds, "
				+ "P95 %.3f / P99 %.3f ms, no global pointer control)."
			)
			% [
				check_count,
				aggregate_samples.size(),
				duration_seconds,
				float(report["aggregate_metrics"]["p95_ms"]),
				float(report["aggregate_metrics"]["p99_ms"]),
			]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _sample_level_visit(
	main: Node,
	level_index: int,
	pass_index: int,
	visit_seconds: float,
) -> void:
	var level_id := LEVEL_IDS[level_index]
	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	paused = false
	var load_started_usec := Time.get_ticks_usec()
	main.switch_level(level_index, false, true)
	var load_ms := float(Time.get_ticks_usec() - load_started_usec) / 1000.0
	if diagnostic_disable_reservations:
		main.movement_reservation_service = null
		for actor: Node2D in main._all_active_runtime_actors():
			if actor.has_method("configure_movement_reservation_service"):
				actor.call("configure_movement_reservation_service", null)
	_dismiss_all_media(main)
	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	paused = false
	_protect_story_actors(main)
	_configure_actor_physics_profiling(main, actor_physics_profile_enabled)
	var first_render_started_usec := Time.get_ticks_usec()
	await process_frame
	if not stability_mode:
		_expect(
			await _wait_for_render_frame(),
			"%s pass %d produced a bounded render frame" % [
				level_id,
				pass_index + 1,
			],
		)
	var first_render_ms := (
		float(Time.get_ticks_usec() - first_render_started_usec) / 1000.0
	)
	var render_sync_started_usec := Time.get_ticks_usec()
	if not stability_mode:
		RenderingServer.force_sync()
	var render_sync_ms := (
		float(Time.get_ticks_usec() - render_sync_started_usec) / 1000.0
	)
	var initial_enemy_positions: Dictionary = {}
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		initial_enemy_positions[int(enemy.get("scene_index"))] = enemy.position

	var input_events_before := viewport_input_events
	_tap_key(KEY_F2)
	var simulation_phase_before := _simulation_phase_usec(main)
	var simulation_system_before := _simulation_system_usec(main)
	var visit_started_usec := Time.get_ticks_usec()
	var previous_frame_usec := visit_started_usec
	var previous_elapsed_seconds := 0.0
	var warmup_seconds := _warmup_seconds(visit_seconds)
	var next_input_seconds := 0.20
	var input_serial := pass_index * 1000 + level_index * 100
	var last_action_label := "level_warmup"
	var last_action_elapsed_seconds := -1.0
	var last_action_dispatch_ms := 0.0
	var previous_path_query_count := int(main.dynamic_occupancy.path_query_count)
	var previous_path_query_usec := int(
		main.dynamic_occupancy.path_query_elapsed_usec
	)
	var previous_static_memory_bytes := OS.get_static_memory_usage()
	var previous_physics_frame := Engine.get_physics_frames()
	var previous_tactical_cache := _tactical_cache_totals(main)
	var next_diagnostic_sample_seconds := 0.0
	while (
		float(Time.get_ticks_usec() - visit_started_usec) / 1_000_000.0
		< visit_seconds
	):
		await process_frame
		var current_frame_usec := Time.get_ticks_usec()
		var elapsed_seconds := (
			float(current_frame_usec - visit_started_usec) / 1_000_000.0
		)
		var frame_interval_ms := (
			float(current_frame_usec - previous_frame_usec) / 1000.0
		)
		var current_path_query_count := int(
			main.dynamic_occupancy.path_query_count
		)
		var current_path_query_usec := int(
			main.dynamic_occupancy.path_query_elapsed_usec
		)
		# Frame intervals and engine timing monitors remain sampled every rendered
		# frame. Expensive attribution-only counters are intentionally 10 Hz: the
		# old probe walked every enemy twice per frame and performed a Windows
		# process-memory query at 60 Hz, adding an O(actor-count) workload to the
		# product it was supposed to measure.
		var current_static_memory_bytes := previous_static_memory_bytes
		var current_physics_frame := Engine.get_physics_frames()
		var current_tactical_cache := previous_tactical_cache
		# RuntimePerformanceMonitor samples the exact current Main and coordinator
		# boundaries. Engine TIME_PROCESS monitors refresh coarsely on Windows;
		# treating a held value as 60 distinct observations fabricates a P95 spike.
		var process_ms := (
			float(main.performance_monitor.last_main_cpu_usec) / 1000.0
			if main.performance_monitor != null
			else 0.0
		)
		var physics_process_ms := (
			float(main.performance_monitor.last_physics_usec) / 1000.0
			if main.performance_monitor != null
			else 0.0
		)
		var physics_frames_advanced := (
			current_physics_frame - previous_physics_frame
		)
		var frame_path_query_ms := (
			float(current_path_query_usec - previous_path_query_usec) / 1000.0
		)
		if elapsed_seconds + 0.000001 >= next_diagnostic_sample_seconds:
			current_static_memory_bytes = OS.get_static_memory_usage()
			current_tactical_cache = _tactical_cache_totals(main)
			next_diagnostic_sample_seconds += 0.10
		if previous_elapsed_seconds >= warmup_seconds:
			_record_bounded_sample(
				level_samples,
				level_sample_totals,
				level_id,
				frame_interval_ms,
			)
			level_peak_draw_calls[level_id] = maxf(
				float(level_peak_draw_calls[level_id]),
				Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
				),
			)
			level_peak_objects_drawn[level_id] = maxf(
				float(level_peak_objects_drawn[level_id]),
				Performance.get_monitor(
					Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
				),
			)
			level_peak_object_count[level_id] = maxf(
				float(level_peak_object_count[level_id]),
				Performance.get_monitor(Performance.OBJECT_COUNT),
			)
			level_peak_static_memory[level_id] = maxf(
				float(level_peak_static_memory[level_id]),
				Performance.get_monitor(Performance.MEMORY_STATIC),
			)
			_record_bounded_sample(
				level_process_samples,
				level_process_sample_totals,
				level_id,
				process_ms,
			)
			_record_bounded_sample(
				level_physics_samples,
				level_physics_sample_totals,
				level_id,
				physics_process_ms,
			)
			if frame_interval_ms > 50.0:
				if RUNTIME_FRAME_CLASSIFIER.is_host_scheduler_preemption(
					frame_interval_ms,
					process_ms,
					physics_process_ms,
					frame_path_query_ms,
					physics_frames_advanced,
				):
					level_host_scheduler_stalls[level_id] = int(
						level_host_scheduler_stalls[level_id]
					) + 1
				else:
					level_unexplained_over_50[level_id] = int(
						level_unexplained_over_50[level_id]
					) + 1
			if frame_interval_ms > 25.0 and slow_frames.size() < 256:
				slow_frames.append(
					{
						"level_id": level_id,
						"pass_index": pass_index,
						"elapsed_seconds": elapsed_seconds,
						"frame_interval_ms": frame_interval_ms,
						"last_action": last_action_label,
						"seconds_since_action": (
							elapsed_seconds - last_action_elapsed_seconds
							if last_action_elapsed_seconds >= 0.0
							else -1.0
						),
						"last_action_dispatch_ms": (
							last_action_dispatch_ms
						),
						"last_nearby_select_ms": last_nearby_select_ms,
						"last_nearby_click_ms": last_nearby_click_ms,
						"formation_move_total_ms": (
							float(main.last_formation_move_total_usec)
							/ 1000.0
						),
						"formation_move_audio_ms": (
							float(main.last_formation_move_audio_usec)
							/ 1000.0
						),
						"formation_move_path_ms": (
							float(main.last_formation_move_path_usec)
							/ 1000.0
						),
						"formation_move_event_ms": (
							float(main.last_formation_move_event_usec)
							/ 1000.0
						),
						"navigation_incremental_source_updates": int(
							main.navigation_grid
							.incremental_source_update_count
						),
						"navigation_incremental_source_ms": (
							float(
								main.navigation_grid
								.incremental_source_update_usec
							)
							/ 1000.0
						),
						"footprint_clearance_incremental_ms": (
							float(
								main.dynamic_occupancy
								.footprint_clearance_incremental_usec
							)
							/ 1000.0
						),
						"process_ms": process_ms,
						"physics_process_ms": physics_process_ms,
						"path_queries": (
							current_path_query_count
							- previous_path_query_count
						),
						"path_query_ms": frame_path_query_ms,
						"last_path_query_scene_index": int(
							main.dynamic_occupancy
							.last_path_query_scene_index
						),
						"last_path_query_ms": (
							float(
								main.dynamic_occupancy
								.last_path_query_elapsed_usec
							)
							/ 1000.0
						),
						"static_memory_delta_bytes": (
							current_static_memory_bytes
							- previous_static_memory_bytes
						),
						"physics_frames_advanced": physics_frames_advanced,
						"host_scheduler_preemption": (
							RUNTIME_FRAME_CLASSIFIER
							.is_host_scheduler_preemption(
								frame_interval_ms,
								process_ms,
								physics_process_ms,
								frame_path_query_ms,
								physics_frames_advanced,
							)
						),
						"tactical_range_rebuilds": (
							current_tactical_cache.x
							- previous_tactical_cache.x
						),
						"tactical_range_rebuild_ms": (
							float(
								current_tactical_cache.y
								- previous_tactical_cache.y
							)
							/ 1000.0
						),
					}
				)
		previous_frame_usec = current_frame_usec
		previous_elapsed_seconds = elapsed_seconds
		previous_path_query_count = current_path_query_count
		previous_path_query_usec = current_path_query_usec
		previous_static_memory_bytes = current_static_memory_bytes
		previous_physics_frame = current_physics_frame
		previous_tactical_cache = current_tactical_cache
		if elapsed_seconds >= next_input_seconds:
			var action_started_usec := Time.get_ticks_usec()
			last_action_label = _submit_workload_action(main, input_serial)
			last_action_dispatch_ms = (
				float(Time.get_ticks_usec() - action_started_usec) / 1000.0
			)
			if not first_action_latencies_ms.has(last_action_label):
				first_action_latencies_ms[last_action_label] = last_action_dispatch_ms
			last_action_elapsed_seconds = elapsed_seconds
			input_serial += 1
			next_input_seconds += 0.55
		_dismiss_all_media(main)
		if paused:
			# Automated runs have no user-driven second click to unwind modal UI.
			# Exercise the open path, then immediately restore the live simulation
			# before awaiting the next frame. This applies to both the rendered
			# performance lane and the headless soak: otherwise a visit that ends
			# after the first Escape can make the following AI sample look frozen.
			if main.game_shell != null:
				main.game_shell.close_for_state_change()
			paused = false
		if (
			Time.get_ticks_usec() - last_stability_progress_usec
				>= 5_000_000
		):
			_write_probe_progress(
				"visit_running",
				{
					"level_id": level_id,
					"pass_index": pass_index,
					"elapsed_seconds": elapsed_seconds,
					"last_action": last_action_label,
					"paused": paused,
				},
			)
		if (
			main.current_mission_state != null
			and main.current_mission_state.is_failed()
		):
			failures.append("%s entered an unexpected failure menu" % level_id)
			break

	var moved_enemy_count := 0
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		var scene_index := int(enemy.get("scene_index"))
		if (
			initial_enemy_positions.has(scene_index)
			and enemy.position.distance_to(
				initial_enemy_positions[scene_index] as Vector2
			) > 0.5
		):
			moved_enemy_count += 1
	level_visits.append(
		{
			"level_id": level_id,
			"pass_index": pass_index,
			"load_ms": load_ms,
			"level_load_phase_ms": _usec_dictionary_to_ms(
				main.last_level_load_phase_usec
			),
			"imported_level_phase_ms": _usec_dictionary_to_ms(
				main.last_imported_level_phase_usec
			),
			"squad_spawn_phase_ms": _usec_dictionary_to_ms(
				main.last_squad_spawn_phase_usec
			),
			"first_render_ms": first_render_ms,
			"render_sync_ms": render_sync_ms,
			"warmup_seconds": warmup_seconds,
			"enemy_count": main.enemies.size(),
			"moved_enemy_count": moved_enemy_count,
			"entity_count": main.imported_entity_count,
			"viewport_input_events": viewport_input_events - input_events_before,
			"memory_bytes": OS.get_static_memory_usage(),
			"slow_path_profiles": _slow_path_profiles(
				main.dynamic_occupancy.path_query_profiles
			),
			"path_query_count": int(
				main.dynamic_occupancy.path_query_count
			),
			"path_query_elapsed_ms": (
				float(main.dynamic_occupancy.path_query_elapsed_usec)
				/ 1000.0
			),
			"prewarmed_path_build_count": int(
				main.dynamic_occupancy.prewarmed_path_build_count
			),
			"prewarmed_path_hit_count": int(
				main.dynamic_occupancy.prewarmed_path_hit_count
			),
			"prewarmed_path_suffix_hit_count": int(
				main.dynamic_occupancy.prewarmed_path_suffix_hit_count
			),
			"runtime_evidence_path_build_count": int(
				main.dynamic_occupancy.runtime_evidence_path_build_count
			),
			"runtime_evidence_path_hit_count": int(
				main.dynamic_occupancy.runtime_evidence_path_hit_count
			),
			"runtime_evidence_translated_hit_count": int(
				main.dynamic_occupancy
					.runtime_evidence_translated_hit_count
			),
			"runtime_evidence_translation_rejections": (
				main.dynamic_occupancy
					.runtime_evidence_translation_rejections.duplicate(true)
			),
			"dense_path_fallback_count": int(
				main.dynamic_occupancy.dense_path_fallback_count
			),
			"dynamic_unreachable_precheck_count": int(
				main.navigation_grid.dynamic_unreachable_precheck_count
			),
			"packed_footprint_unreachable_precheck_count": int(
				main.navigation_grid
					.packed_footprint_unreachable_precheck_count
			),
			"footprint_clearance_precompute_ms": (
				float(
					main.dynamic_occupancy
					.footprint_clearance_precompute_usec
				)
				/ 1000.0
			),
			"footprint_clearance_metrics": (
				main.dynamic_occupancy.footprint_clearance_metrics()
			),
			"static_component_redirect_count": int(
				main.navigation_grid.static_component_redirect_count
			),
			"static_component_cache_hit_count": int(
				main.navigation_grid.static_component_cache_hit_count
			),
			"navigation_incremental_source_update_count": int(
				main.navigation_grid.incremental_source_update_count
			),
			"navigation_incremental_source_update_ms": (
				float(
					main.navigation_grid.incremental_source_update_usec
				)
				/ 1000.0
			),
			"footprint_clearance_incremental_ms": (
				float(
					main.dynamic_occupancy
					.footprint_clearance_incremental_usec
				)
				/ 1000.0
			),
			"tactical_range_cache_rebuild_count": (
				_tactical_cache_totals(main).x
			),
			"tactical_range_cache_rebuild_ms": (
				float(_tactical_cache_totals(main).y) / 1000.0
			),
			"actor_physics_profile": _actor_physics_profile(main),
			"main_process_profile": (
				main.call("debug_main_process_profile_snapshot")
				if actor_physics_profile_enabled
				and main.has_method("debug_main_process_profile_snapshot")
				else {}
			),
			"simulation_phase_ms": _simulation_phase_delta_ms(
				simulation_phase_before,
				_simulation_phase_usec(main),
			),
			"simulation_system_ms": _simulation_phase_delta_ms(
				simulation_system_before,
				_simulation_system_usec(main),
			),
		}
	)


func _submit_workload_action(main: Node, serial: int) -> String:
	var action_index := posmod(serial, 16)
	match action_index:
		0:
			_tap_key(KEY_F2)
			return "select_F2"
		1, 2:
			_tap_key(KEY_R)
			return "run_walk_R"
		3, 4:
			_tap_key(KEY_C)
			return "stance_C"
		5, 6:
			_tap_key(KEY_M)
			return "tactical_map_M"
		7:
			_issue_nearby_move(main)
			return "nearby_move_click"
		8:
			_observe_nearest_enemy(main)
			return "sight_S_enemy_click"
		9, 10:
			_tap_key(KEY_W)
			return "weapons_W"
		11, 12:
			_tap_key(KEY_A)
			return "items_A"
		13, 14:
			_tap_key(KEY_ESCAPE)
			return "pause_Escape"
		15:
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			wheel.position = root.size * 0.5
			root.push_input(wheel, true)
			viewport_input_events += 1
			return "camera_wheel"
	return "noop"


func _issue_nearby_move(main: Node) -> void:
	if main.units.is_empty() or main.navigation_grid == null:
		return
	var player := main.units[0] as Node2D
	var select_started_usec := Time.get_ticks_usec()
	_tap_key(KEY_F2)
	last_nearby_select_ms = (
		float(Time.get_ticks_usec() - select_started_usec) / 1000.0
	)
	last_nearby_click_ms = 0.0
	var start_cell: Vector2i = main.navigation_grid.world_to_cell(
		player.position
	)
	for offset: Vector2i in [
		Vector2i(4, 0),
		Vector2i(0, 4),
		Vector2i(-4, 0),
		Vector2i(0, -4),
	]:
		var candidate_cell := start_cell + offset
		if (
			main.navigation_grid.is_valid_cell(candidate_cell)
			and not main.navigation_grid.is_movement_blocked(
				candidate_cell
			)
		):
			# The probe only chooses a plausible nearby click. Main's normal
			# formation order is the sole path planner, exactly as with human
			# input, and its DynamicOccupancyGrid query is fully instrumented.
			var click_started_usec := Time.get_ticks_usec()
			_click_world(
				main,
				main.navigation_grid.cell_to_world(candidate_cell),
			)
			last_nearby_click_ms = (
				float(Time.get_ticks_usec() - click_started_usec)
				/ 1000.0
			)
			return


func _observe_nearest_enemy(main: Node) -> void:
	if main.units.is_empty():
		return
	var player := main.units[0] as Node2D
	var nearest_enemy: Node2D
	var nearest_distance_squared := INF
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		if not bool(enemy.get("is_alive")):
			continue
		var distance_squared := enemy.position.distance_squared_to(player.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy
	if nearest_enemy == null:
		return
	main.level_camera.position = main.LEVEL_VIEW.clamp_camera_center(
		nearest_enemy.position,
		main.get_viewport_rect().size,
		main.level_camera.zoom.x,
		main.world_size,
	)
	main.level_camera.reset_smoothing()
	_tap_key(KEY_S)
	_click_world(main, nearest_enemy.position)


func _tap_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	root.push_input(press)
	viewport_input_events += 1
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)
	viewport_input_events += 1


func _click_world(main: Node, world_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = main.get_global_transform_with_canvas() * world_position
	root.push_input(press, true)
	viewport_input_events += 1
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	viewport_input_events += 1


func _protect_story_actors(main: Node) -> void:
	for actor_value: Variant in (
		main.units + main.escorts
	):
		var actor := actor_value as Node
		actor.set("maximum_hit_points", 1_000_000)
		actor.set("current_hit_points", 1_000_000)


func _configure_actor_physics_profiling(main: Node, enabled: bool) -> void:
	if main.has_method("set_debug_main_process_profiling_enabled"):
		main.call("set_debug_main_process_profiling_enabled", enabled)
	if main.simulation_coordinator != null:
		main.simulation_coordinator.set_profiling_enabled(enabled)
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		if actor != null and actor.has_method("set_debug_physics_profiling_enabled"):
			actor.call("set_debug_physics_profiling_enabled", enabled)


func _actor_physics_profile(main: Node) -> Dictionary:
	if not actor_physics_profile_enabled:
		return {}
	var sections: Dictionary = {}
	var actor_profiles: Array[Dictionary] = []
	var actor_count := 0
	var enemy_instance_ids: Dictionary = {}
	for enemy_value: Variant in main.enemies:
		if enemy_value is Node:
			enemy_instance_ids[(enemy_value as Node).get_instance_id()] = true
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		if actor == null or not actor.has_method("debug_physics_profile_snapshot"):
			continue
		actor_count += 1
		var is_enemy := enemy_instance_ids.has(actor.get_instance_id())
		var profile := actor.call("debug_physics_profile_snapshot") as Dictionary
		var actor_total_usec := 0
		var actor_maximum_usec := 0
		for raw_section: Variant in profile.keys():
			var section := str(raw_section)
			var actor_section := profile[raw_section] as Dictionary
			var aggregate_value: Variant = sections.get(section, {})
			var aggregate := (
				aggregate_value as Dictionary
				if aggregate_value is Dictionary
				else {}
			)
			aggregate["count"] = int(aggregate.get("count", 0)) + int(
				actor_section.get("count", 0)
			)
			aggregate["total_usec"] = int(aggregate.get("total_usec", 0)) + int(
				actor_section.get("total_usec", 0)
			)
			aggregate["maximum_usec"] = maxi(
				int(aggregate.get("maximum_usec", 0)),
				int(actor_section.get("maximum_usec", 0)),
			)
			sections[section] = aggregate
			if section == "actor_total":
				# The coordinator's diagnostic lane measures one non-overlapping
				# authoritative total. Prefer it over legacy sectional probes so the
				# ranking cannot double-count nested enemy/ambient work.
				actor_total_usec = int(actor_section.get("total_usec", 0))
				actor_maximum_usec = int(actor_section.get("maximum_usec", 0))
			elif (
				not profile.has("actor_total")
				and section in ["enemy_logic", "ambient_logic", "total"]
			):
				actor_total_usec += int(actor_section.get("total_usec", 0))
				actor_maximum_usec = maxi(
					actor_maximum_usec,
					int(actor_section.get("maximum_usec", 0)),
				)
		actor_profiles.append({
			"scene_index": int(actor.get("scene_index")),
			"class_name": actor.get_class(),
			"runtime_actor_type": int(actor.get("runtime_actor_type")),
			"compact_navigation": bool(actor.get("use_compact_navigation_footprint")),
			"behavior_state": (
				int(actor.get("behavior_state"))
				if is_enemy
				else -1
			),
			"combat_action": int(actor.get("combat_action")),
			"movement_path_index": int(actor.get("movement_path_index")),
			"movement_path_size": (
				(actor.get("movement_path") as PackedVector2Array).size()
				if actor.get("movement_path") is PackedVector2Array
				else 0
			),
			"blocked_elapsed": float(actor.get("blocked_elapsed")),
			"was_moving": bool(actor.get("was_moving")),
			"soft_dynamic_occupancy": bool(actor.get("use_soft_dynamic_occupancy")),
			"target_scene_index": (
				int((actor.get("current_target") as Node).get("scene_index"))
				if is_enemy
				and actor.get("current_target") is Node
				and is_instance_valid(actor.get("current_target"))
				else -1
			),
			"position": [float((actor as Node2D).position.x), float((actor as Node2D).position.y)] if actor is Node2D else [],
			"total_usec": actor_total_usec,
			"maximum_usec": actor_maximum_usec,
			"sections": profile,
		})
	for section_value: Variant in sections.values():
		var section := section_value as Dictionary
		section["average_usec"] = (
			float(section.get("total_usec", 0))
			/ maxf(float(section.get("count", 0)), 1.0)
		)
	actor_profiles.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["total_usec"]) != int(right["total_usec"]):
				return int(left["total_usec"]) > int(right["total_usec"])
			return int(left["scene_index"]) < int(right["scene_index"])
	)
	if actor_profiles.size() > 16:
		actor_profiles.resize(16)
	return {
		"actor_count": actor_count,
		"sections": sections,
		"top_actors_by_total": actor_profiles,
	}


func _simulation_phase_usec(main: Node) -> Dictionary:
	if main.simulation_coordinator == null:
		return {}
	var stats := main.simulation_coordinator.stats() as Dictionary
	var phase_value: Variant = stats.get("phase_usec", {})
	return (
		(phase_value as Dictionary).duplicate(true)
		if phase_value is Dictionary
		else {}
	)


func _simulation_system_usec(main: Node) -> Dictionary:
	if main.simulation_coordinator == null:
		return {}
	var stats := main.simulation_coordinator.stats() as Dictionary
	var system_value: Variant = stats.get("system_usec", {})
	return (
		(system_value as Dictionary).duplicate(true)
		if system_value is Dictionary
		else {}
	)


func _simulation_phase_delta_ms(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for phase_value: Variant in after.keys():
		var phase := str(phase_value)
		result[phase] = (
			float(int(after[phase_value]) - int(before.get(phase, 0)))
			/ 1000.0
		)
	return result


func _exercise_stability_save_roundtrip(
	main: Node,
	pass_index: int,
	level_id: String,
) -> void:
	var slot_id := "qa_soak_%d_%s" % [pass_index % 2, level_id]
	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	var saved: Dictionary = main.save_store.save_slot(
		slot_id,
		session,
		main.campaign_progress,
	)
	_expect(bool(saved.get("ok", false)), "%s stability save succeeds" % level_id)
	if not bool(saved.get("ok", false)):
		return
	soak_save_count += 1
	var loaded: Dictionary = main.save_store.load_slot(slot_id)
	_expect(bool(loaded.get("ok", false)), "%s stability load succeeds" % level_id)
	if not bool(loaded.get("ok", false)):
		return
	soak_load_count += 1
	var document := loaded.get("data", {}) as Dictionary
	var restored: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		main,
		document.get("session", {}) as Dictionary,
	)
	_expect(
		bool(restored.get("ok", false)),
		"%s stability state restore succeeds" % level_id,
	)
	_protect_story_actors(main)


func _tactical_cache_totals(main: Node) -> Vector2i:
	var rebuild_count := 0
	var rebuild_usec := 0
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node
		rebuild_count += int(enemy.get("tactical_range_cache_rebuild_count"))
		rebuild_usec += int(enemy.get("tactical_range_cache_rebuild_usec"))
	return Vector2i(rebuild_count, rebuild_usec)


func _dismiss_all_media(main: Node) -> void:
	if main.media_director == null:
		return
	for _attempt: int in range(16):
		if not bool(main.media_director.is_modal_active()):
			return
		if not str(main.media_director.active_movie).is_empty():
			main.media_director.stop_movie(true)
		elif not str(main.media_director.dialogue_sequence_id).is_empty():
			main.media_director.stop_dialogue(true)
		elif not str(main.media_director.active_briefing).is_empty():
			main.media_director.dismiss_briefing()
		elif bool(main.media_director.active_ending):
			main.media_director.dismiss_ending()
		else:
			return
		modal_dismissals += 1


func _usec_dictionary_to_ms(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in values:
		result[str(key)] = float(values[key]) / 1000.0
	return result


func _warmup_seconds(visit_seconds: float) -> float:
	return minf(2.0, maxf(1.0, visit_seconds * 0.20))


func _record_bounded_sample(
	storage: Dictionary,
	totals: Dictionary,
	level_id: String,
	value: float,
) -> void:
	var samples := storage[level_id] as Array
	var observed := int(totals.get(level_id, 0))
	if samples.size() < MAX_STORED_SAMPLES_PER_LEVEL:
		samples.append(value)
	else:
		# A rolling reservoir keeps the most recent representative window. It
		# prevents the QA harness itself from looking like a gameplay leak during
		# 30–60 minute runs while retaining far more than the P99 sample gate.
		samples[observed % MAX_STORED_SAMPLES_PER_LEVEL] = value
	totals[level_id] = observed + 1


func _frame_metrics(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {
			"sample_count": 0,
			"average_ms": 0.0,
			"p50_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"maximum_ms": 0.0,
			"frames_over_25_ms": 0,
			"frames_over_50_ms": 0,
		}
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var total := 0.0
	var over_25 := 0
	var over_50 := 0
	for sample_value: Variant in sorted_samples:
		var sample := float(sample_value)
		total += sample
		if sample > 25.0:
			over_25 += 1
		if sample > 50.0:
			over_50 += 1
	return {
		"sample_count": sorted_samples.size(),
		"average_ms": total / float(sorted_samples.size()),
		"p50_ms": _percentile(sorted_samples, 0.50),
		"p95_ms": _percentile(sorted_samples, 0.95),
		"p99_ms": _percentile(sorted_samples, 0.99),
		"maximum_ms": float(sorted_samples[-1]),
		"frames_over_25_ms": over_25,
		"frames_over_50_ms": over_50,
	}


func _slow_path_profiles(profiles: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile_value: Variant in profiles.values():
		result.append((profile_value as Dictionary).duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["maximum_usec"]) != int(right["maximum_usec"]):
				return int(left["maximum_usec"]) > int(right["maximum_usec"])
			return int(left["scene_index"]) < int(right["scene_index"])
	)
	if result.size() > 12:
		result.resize(12)
	return result


func _percentile(sorted_samples: Array, fraction: float) -> float:
	var index := ceili(float(sorted_samples.size()) * fraction) - 1
	return float(sorted_samples[clampi(index, 0, sorted_samples.size() - 1)])


func _parse_arguments(arguments: PackedStringArray) -> void:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_PREFIX):
			output_path = argument.trim_prefix(OUTPUT_PREFIX).simplify_path()
		elif argument.begins_with("--duration-seconds="):
			duration_seconds = maxf(
				float(argument.trim_prefix("--duration-seconds=")),
				1.0,
			)
		elif argument.begins_with("--passes="):
			pass_count = maxi(int(argument.trim_prefix("--passes=")), 1)
		elif argument.begins_with("--max-p95-ms="):
			maximum_p95_ms = maxf(
				float(argument.trim_prefix("--max-p95-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-per-level-p95-ms="):
			maximum_per_level_p95_ms = maxf(
				float(argument.trim_prefix("--max-per-level-p95-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-p99-ms="):
			maximum_p99_ms = maxf(
				float(argument.trim_prefix("--max-p99-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-process-p95-ms="):
			maximum_process_p95_ms = maxf(
				float(argument.trim_prefix("--max-process-p95-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-physics-p95-ms="):
			maximum_physics_p95_ms = maxf(
				float(argument.trim_prefix("--max-physics-p95-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-ui-action-ms="):
			maximum_ui_action_ms = maxf(
				float(argument.trim_prefix("--max-ui-action-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-cold-level-load-ms="):
			maximum_cold_level_load_ms = maxf(
				float(argument.trim_prefix("--max-cold-level-load-ms=")),
				1.0,
			)
		elif argument.begins_with("--max-warm-level-load-ms="):
			maximum_warm_level_load_ms = maxf(
				float(argument.trim_prefix("--max-warm-level-load-ms=")),
				1.0,
			)
		elif argument.begins_with("--min-per-level-p99-samples="):
			minimum_per_level_p99_samples = maxi(
				int(
					argument.trim_prefix(
						"--min-per-level-p99-samples="
					)
				),
				1,
			)
		elif argument.begins_with("--max-over-50-per-level="):
			maximum_over_50_per_level = maxi(
				int(argument.trim_prefix("--max-over-50-per-level=")),
				0,
			)
		elif argument.begins_with("--max-second-pass-growth-mib="):
			maximum_second_pass_growth_mib = maxf(
				float(argument.trim_prefix("--max-second-pass-growth-mib=")),
				0.0,
			)
		elif argument.begins_with("--profile-id="):
			profile_id = argument.trim_prefix("--profile-id=")
		elif argument.begins_with("--levels="):
			var requested_levels: Array[String] = []
			for raw_level_id: String in (
				argument.trim_prefix("--levels=").split(",", false)
			):
				var level_id := raw_level_id.strip_edges().to_lower()
				if level_id in LEVEL_IDS and level_id not in requested_levels:
					requested_levels.append(level_id)
			if not requested_levels.is_empty():
				selected_level_ids = requested_levels
		elif argument == "--stability-mode":
			stability_mode = true
		elif argument == "--profile-actor-physics":
			actor_physics_profile_enabled = true
		elif argument == "--diagnostic-hide-world":
			diagnostic_hide_world = true
		elif argument == "--diagnostic-disable-reservations":
			diagnostic_disable_reservations = true


func _write_report(path: String, report: Dictionary) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		path.get_base_dir()
	)
	if directory_error != OK:
		failures.append("performance output directory could not be created")
		return
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		failures.append("performance report could not be opened")
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()


func _wait_for_render_frame(max_process_frames: int = 120) -> bool:
	# A Windows compositor may stop emitting frame_post_draw for a mostly
	# off-screen or occluded benchmark window. Force a draw and bound the wait so
	# QA reports a failed render contract instead of hanging forever.
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


func _write_probe_progress(stage: String, payload: Dictionary) -> void:
	if output_path.is_empty():
		return
	last_stability_progress_usec = Time.get_ticks_usec()
	var progress_path := output_path.get_base_dir().path_join(
		"stability-progress.json" if stability_mode else "performance-progress.json"
	)
	var progress := {
		"schema_version": 1,
		"stage": stage,
		"ticks_usec": last_stability_progress_usec,
		"payload": payload,
	}
	var file := FileAccess.open(progress_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(progress, "\t") + "\n")
		file.close()


func _cleanup_isolated_save_directory() -> void:
	var absolute_directory := ProjectSettings.globalize_path(
		isolated_save_directory
	)
	var expected_root := ProjectSettings.globalize_path(
		"user://qa-campaign-performance"
	)
	if (
		absolute_directory.is_empty()
		or expected_root.is_empty()
		or absolute_directory.get_base_dir().simplify_path()
			!= expected_root.simplify_path()
	):
		failures.append("isolated performance save cleanup left its QA root")
		return
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			DirAccess.remove_absolute(absolute_directory.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_directory)


func _expect(condition: bool, description: String) -> void:
	check_count += 1
	if not condition:
		failures.append(description)
