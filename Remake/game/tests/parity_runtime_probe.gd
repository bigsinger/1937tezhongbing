extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TRACE_SCRIPT: Script = preload("res://scripts/runtime_parity_trace.gd")

const OUTPUT_ARGUMENT_PREFIX := "--output-dir="
const MOVE_SPEED_ARGUMENT_PREFIX := "--move-speed="
const SCENARIO_ARGUMENT_PREFIX := "--scenario-id="
const OUTBOUND_ARGUMENT_PREFIX := "--outbound-target="
const RETURN_ARGUMENT_PREFIX := "--return-target="
const OBSERVATION_ARGUMENT_PREFIX := "--observation-seconds="
const PRIMARY_DATABASE_ENTRY_ID := 924
## Layer-3-verified, obstacle-free cell centres: (1,3) and (5,3).
## The short observation window issues the return order before the first
## command can settle, so goal replacement and facing are both observable.
const OUTBOUND_TARGET := Vector2(48.0, 56.0)
const RETURN_TARGET := Vector2(176.0, 56.0)
const OBSERVATION_SECONDS := 0.75

var output_directory := ""
var failures: Array[String] = []


func _init() -> void:
	output_directory = _parse_output_directory(OS.get_cmdline_user_args())
	call_deferred("_run_probe")


func _run_probe() -> void:
	var arguments := OS.get_cmdline_user_args()
	var scenario_id := _parse_string_argument(
		arguments,
		SCENARIO_ARGUMENT_PREFIX,
		"m000-basic-movement-v1",
	)
	var outbound_target := _parse_vector_argument(
		arguments,
		OUTBOUND_ARGUMENT_PREFIX,
		OUTBOUND_TARGET,
	)
	var return_target := _parse_vector_argument(
		arguments,
		RETURN_ARGUMENT_PREFIX,
		RETURN_TARGET,
	)
	var observation_seconds := _parse_positive_float_argument(
		arguments,
		OBSERVATION_ARGUMENT_PREFIX,
		OBSERVATION_SECONDS,
	)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var started := Time.get_ticks_usec()

	var trace = TRACE_SCRIPT.new()
	var scenario_description := (
		"Observe the audited m000 enemy patrol roster in two one-second intervals."
		if scenario_id == "m000-enemy-patrol-v1"
		else "Select 强子, issue two original-coordinate move orders, and observe facing/path replacement."
	)
	trace.configure(
		"remake",
		"m000",
		1,
		1,
		scenario_id,
		scenario_description,
	)
	if scenario_id == "m000-enemy-patrol-v1":
		await _run_enemy_patrol_probe(
			main,
			trace,
			started,
			observation_seconds,
		)
		return
	trace.capture_main("gameplay_ready", main, _elapsed_ms(started))

	var primary = _primary_unit(main)
	_expect(primary != null, "m000 primary DBL 924 actor exists")
	if primary != null:
		var calibrated_speed := _parse_move_speed(arguments)
		if calibrated_speed > 0.0:
			primary.set("move_speed", calibrated_speed)
		main.select_only(primary)
		trace.capture_main("player_selected", main, _elapsed_ms(started))

		main.issue_formation_move(outbound_target)
		_expect(
			primary.target_position.distance_to(outbound_target) <= 1.0,
			"outbound target is accepted exactly",
		)
		trace.capture_main(
			"move_outbound_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await create_timer(observation_seconds).timeout
		trace.capture_main(
			"move_outbound_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		_expect(
			primary.position.distance_to(outbound_target)
			< Vector2(241.0, 51.0).distance_to(outbound_target),
			"outbound movement approaches the target",
		)

		var outbound_position: Vector2 = primary.position
		main.issue_formation_move(return_target)
		_expect(
			primary.target_position.distance_to(return_target) <= 1.0,
			"second click replaces the active goal",
		)
		trace.capture_main(
			"move_return_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await create_timer(observation_seconds).timeout
		trace.capture_main(
			"move_return_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		_expect(
			primary.position.distance_to(return_target)
			< outbound_position.distance_to(return_target),
			"return movement approaches the replacement target",
		)

	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(trace.write_to_file(trace_path) == OK, "Remake parity trace writes")
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace.document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_enemy_patrol_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	observation_seconds: float,
) -> void:
	# Let the staggered path scheduler issue every first patrol request before
	# measuring. The reference MOD trace likewise starts only after gameplay is
	# fully resumed; commanded/observed pairs compare interval movement rather
	# than unrelated absolute startup phase.
	# The isolated MOD probe resumes the original menu, waits 4.2 seconds for
	# the gameplay capture, then observes five seconds of spawn safety before
	# its first patrol checkpoint. Reproduce that 9.2-second phase here.
	await create_timer(9.2).timeout
	var enemy_count := (main.get("enemies") as Array).size()
	_expect(enemy_count >= 46, "m000 imported enemy roster is available")
	trace.call(
		"capture_main",
		"patrol_interval_1_commanded",
		main,
		_elapsed_ms(started),
		{"scope": "audited_m000_enemy_identities"},
	)
	await create_timer(observation_seconds).timeout
	trace.call(
		"capture_main",
		"patrol_interval_1_observed",
		main,
		_elapsed_ms(started),
		{"scope": "audited_m000_enemy_identities"},
	)
	trace.call(
		"capture_main",
		"patrol_interval_2_commanded",
		main,
		_elapsed_ms(started),
		{"scope": "audited_m000_enemy_identities"},
	)
	await create_timer(observation_seconds).timeout
	trace.call(
		"capture_main",
		"patrol_interval_2_observed",
		main,
		_elapsed_ms(started),
		{"scope": "audited_m000_enemy_identities"},
	)
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-m000-enemy-patrol-v1.json"
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake patrol parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _primary_unit(main: Node) -> Node2D:
	var entities: Dictionary = main.world_entities_by_scene
	for unit: Node2D in main.units:
		var entity := entities.get(int(unit.get("scene_index")), {}) as Dictionary
		if int(entity.get("database_entry_id", 0)) == PRIMARY_DATABASE_ENTRY_ID:
			return unit
	return null


func _parse_output_directory(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX).simplify_path()
	return ""


func _parse_move_speed(arguments: PackedStringArray) -> float:
	for argument: String in arguments:
		if argument.begins_with(MOVE_SPEED_ARGUMENT_PREFIX):
			return maxf(
				argument.trim_prefix(MOVE_SPEED_ARGUMENT_PREFIX).to_float(),
				0.0,
			)
	return 0.0


func _parse_string_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: String,
) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			var parsed := argument.trim_prefix(prefix).strip_edges()
			if not parsed.is_empty():
				return parsed
	return default_value


func _parse_vector_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: Vector2,
) -> Vector2:
	var value := _parse_string_argument(arguments, prefix, "")
	var components := value.split(",", false)
	if components.size() != 2:
		return default_value
	if not components[0].is_valid_float() or not components[1].is_valid_float():
		return default_value
	return Vector2(components[0].to_float(), components[1].to_float())


func _parse_positive_float_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: float,
) -> float:
	var value := _parse_string_argument(arguments, prefix, "")
	if not value.is_valid_float():
		return default_value
	return maxf(value.to_float(), 0.05)


func _safe_file_component(value: String) -> String:
	var safe := ""
	for index: int in range(value.length()):
		var character := value.substr(index, 1)
		if (
			character >= "a" and character <= "z"
			or character >= "A" and character <= "Z"
			or character >= "0" and character <= "9"
			or character == "-"
			or character == "_"
		):
			safe += character
		else:
			safe += "-"
	return safe


func _elapsed_ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _movement_tags(unit: Node2D, main: Node) -> Dictionary:
	var points: Array = []
	for point: Vector2 in unit.get("movement_path") as PackedVector2Array:
		points.append([point.x, point.y])
	var raw_points: Array = []
	var requested_target: Vector2 = unit.get("target_position")
	for point: Vector2 in main.navigation_grid.find_path(
		unit.position, requested_target, true
	):
		raw_points.append([point.x, point.y])
	var nearby_owners: Dictionary = {}
	for y: int in range(8, 15):
		nearby_owners["7,%d" % y] = int(
			main.dynamic_occupancy.runtime_movement_owner(Vector2i(7, y))
		)
	var movement_offsets: Array = []
	if main.dynamic_occupancy.actors.has(int(unit.get("scene_index"))):
		var actor_state := (
			main.dynamic_occupancy.actors[int(unit.get("scene_index"))] as Dictionary
		)
		for offset: Vector2i in actor_state.get("movement_offsets", []) as Array[Vector2i]:
			movement_offsets.append([offset.x, offset.y])
	return {
		"move_speed": float(unit.get("move_speed")),
		"movement_path_index": int(unit.get("movement_path_index")),
		"movement_offsets": movement_offsets,
		"path": points,
		"raw_layer3_path": raw_points,
		"nearby_runtime_owners": nearby_owners,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
