extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DENSE_LEVEL_INDEX := 4
const SAMPLE_PHYSICS_FRAMES := 120
const MIN_PATH_QUERIES := 20
const MAX_PATH_QUERIES := 500
const MAX_PATH_TIME_MS := 2000.0
const PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX := 2719
const PACKED_FOOTPRINT_REGRESSION_START := Vector2i(43, 27)
const PACKED_FOOTPRINT_REGRESSION_DESTINATION := Vector2i(46, 17)
const MAX_PACKED_FOOTPRINT_REGRESSION_MS := 50.0
const PACKED_FOOTPRINT_REGRESSION_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 2),
	Vector2i(0, 0),
	Vector2i(0, 1),
	Vector2i(0, 2),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(2, -1),
	Vector2i(2, 0),
]


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var started := Time.get_ticks_usec()
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	var ready_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var failures: Array[String] = []
	if main.current_level_index != DENSE_LEVEL_INDEX:
		failures.append("navigation stress test must run with --level=m004")
	if not main.terrain_loaded:
		failures.append("m004 converted terrain did not load")
	if main.dynamic_occupancy == null or main.dynamic_occupancy.actors.size() < 50:
		failures.append("m004 dynamic actors did not register")
	var packed_regression_ms := 0.0
	var packed_regression_visited_count := 0
	if (
		main.dynamic_occupancy != null
		and main.dynamic_occupancy.actors.has(
			PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX
		)
	):
		var packed_precheck_before := int(
			main.navigation_grid
				.packed_footprint_unreachable_precheck_count
		)
		var regression_actor := (
			main.dynamic_occupancy.actors[
				PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX
			] as Dictionary
		)
		var original_regression_offsets := (
			regression_actor["movement_offsets"] as Array[Vector2i]
		)
		regression_actor["movement_offsets"] = (
			PACKED_FOOTPRINT_REGRESSION_OFFSETS.duplicate()
		)
		main.dynamic_occupancy.actors[
			PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX
		] = regression_actor
		var packed_regression_started := Time.get_ticks_usec()
		var packed_regression_path: PackedVector2Array = (
			main.dynamic_occupancy.preview_path_for_scene(
				PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX,
				main.navigation_grid.cell_to_world(
					PACKED_FOOTPRINT_REGRESSION_START
				),
				main.navigation_grid.cell_to_world(
					PACKED_FOOTPRINT_REGRESSION_DESTINATION
				),
			)
		)
		packed_regression_ms = (
			float(Time.get_ticks_usec() - packed_regression_started) / 1000.0
		)
		packed_regression_visited_count = int(
			main.navigation_grid.last_packed_reachability_visited_count
		)
		regression_actor["movement_offsets"] = original_regression_offsets
		main.dynamic_occupancy.actors[
			PACKED_FOOTPRINT_REGRESSION_SCENE_INDEX
		] = regression_actor
		if not packed_regression_path.is_empty():
			failures.append(
				"m004 blocked carriage regression route unexpectedly became reachable"
			)
		if (
			int(
				main.navigation_grid
					.packed_footprint_unreachable_precheck_count
			)
			!= packed_precheck_before + 1
		):
			failures.append(
				"m004 blocked carriage regression did not use the exact packed-footprint precheck"
			)
		if packed_regression_ms > MAX_PACKED_FOOTPRINT_REGRESSION_MS:
			failures.append(
				"m004 carriage regression consumed %.1f ms (limit %.1f ms)"
				% [
					packed_regression_ms,
					MAX_PACKED_FOOTPRINT_REGRESSION_MS,
				]
			)
	else:
		failures.append("m004 carriage regression actor 2719 is missing")
	var initial_enemy_positions: Dictionary = {}
	for enemy in main.enemies:
		initial_enemy_positions[enemy.scene_index] = enemy.position

	var physics_started := Engine.get_physics_frames()
	while Engine.get_physics_frames() - physics_started < SAMPLE_PHYSICS_FRAMES:
		await physics_frame

	var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var path_queries := 0
	var path_ms := 0.0
	if main.dynamic_occupancy != null:
		path_queries = main.dynamic_occupancy.path_query_count
		path_ms = float(main.dynamic_occupancy.path_query_elapsed_usec) / 1000.0
	if path_queries < MIN_PATH_QUERIES:
		failures.append(
			"m004 issued only %d path queries; patrol activity may not be running" % path_queries
		)
	if path_queries > MAX_PATH_QUERIES:
		failures.append(
			"m004 issued %d path queries in %d physics frames (limit %d)"
			% [path_queries, SAMPLE_PHYSICS_FRAMES, MAX_PATH_QUERIES]
		)
	if path_ms > MAX_PATH_TIME_MS:
		failures.append(
			"m004 path queries consumed %.1f ms (limit %.1f ms)"
			% [path_ms, MAX_PATH_TIME_MS]
		)
	var moved_enemy_count := 0
	for enemy in main.enemies:
		if (
			initial_enemy_positions.has(enemy.scene_index)
			and enemy.position.distance_squared_to(initial_enemy_positions[enemy.scene_index]) > 4.0
		):
			moved_enemy_count += 1
	if moved_enemy_count == 0:
		failures.append("m004 patrol actors did not move during the stress sample")

	print(
		"Dense navigation stress: ready %.1f ms, total %.1f ms, packed regression %.1f ms / %d visited, %d paths / %.1f ms, %d actors, %d enemies moved."
		% [
			ready_ms,
			total_ms,
			packed_regression_ms,
			packed_regression_visited_count,
			path_queries,
			path_ms,
			main.dynamic_occupancy.actors.size() if main.dynamic_occupancy != null else 0,
			moved_enemy_count,
		]
	)
	main.free()
	if failures.is_empty():
		print("Dense navigation stress test passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
