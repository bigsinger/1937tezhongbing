extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const DENSE_LEVEL_INDEX := 4
const SAMPLE_PHYSICS_FRAMES := 120
const MIN_PATH_QUERIES := 20
const MAX_PATH_QUERIES := 500
const MAX_PATH_TIME_MS := 2000.0


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
		"Dense navigation stress: ready %.1f ms, total %.1f ms, %d paths / %.1f ms, %d actors, %d enemies moved."
		% [
			ready_ms,
			total_ms,
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
