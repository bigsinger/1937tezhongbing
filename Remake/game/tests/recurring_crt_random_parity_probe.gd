extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const BASELINE_PATH := (
	"res://data/original_crt_random_recurring_timing.json"
)

var failures: Array[String] = []
var checks := 0
var requested_level_id := ""
var diagnostic_actor_counts := false


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			requested_level_id = argument.trim_prefix("--level=")
		elif argument == "--diagnostic-actor-counts":
			diagnostic_actor_counts = true
	call_deferred("_run")


func _run() -> void:
	var baseline_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(BASELINE_PATH)
	)
	_expect(
		baseline_value is Dictionary,
		"recurring CRT random parity baseline is readable",
	)
	if not baseline_value is Dictionary:
		_finish()
		return
	var levels_value: Variant = (baseline_value as Dictionary).get(
		"levels",
		[],
	)
	_expect(
		levels_value is Array and (levels_value as Array).size() == 12,
		"recurring CRT random parity baseline covers twelve levels",
	)
	if not levels_value is Array:
		_finish()
		return

	var exercised_levels := 0
	for level_index: int in range((levels_value as Array).size()):
		var level := (levels_value as Array)[level_index] as Dictionary
		var level_id := str(level.get("id", ""))
		if (
			not requested_level_id.is_empty()
			and requested_level_id != level_id
		):
			continue
		await _exercise_level(level_index, level)
		exercised_levels += 1
	_expect(exercised_levels > 0, "at least one requested level was exercised")
	_finish()


func _exercise_level(level_index: int, level: Dictionary) -> void:
	var level_id := str(level.get("id", ""))
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["show_briefings"] = false
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	main.runtime_settings["ruleset_mode"] = "classic"
	main.runtime_settings["difficulty_mode"] = "normal"
	var trace_started := bool(main.begin_legacy_crt_random_parity_trace())
	main.switch_level(level_index, false, false)
	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	if main.media_director != null:
		main.media_director.close_for_state_change()
	paused = false
	_expect(trace_started, "%s starts a parity hash trace" % level_id)

	var gate_indices: Array = level.get(
		"observation_gate_actor_indices",
		[],
	) as Array
	var first_gate_index := int(gate_indices[0]) if not gate_indices.is_empty() else -1
	var first_gate_actor: Node2D
	for actor_value: Variant in main.call("_all_active_runtime_actors") as Array:
		var actor := actor_value as Node2D
		if int(actor.get("original_runtime_index")) == first_gate_index:
			first_gate_actor = actor
			break
	_expect(
		first_gate_actor != null,
		"%s exposes its first observation-gate actor" % level_id,
	)
	if first_gate_actor == null:
		_dispose_main(main)
		return

	var expected_round_count := int(level.get("complete_round_count", 0))
	var physics_frame_count := 0
	while (
		int(first_gate_actor.get("original_crt_observation_gate_serial"))
		< expected_round_count
		and physics_frame_count < expected_round_count + 16
	):
		await physics_frame
		physics_frame_count += 1
	var actual_round_count := int(
		first_gate_actor.get("original_crt_observation_gate_serial")
	)
	var snapshot: Dictionary = main.legacy_crt_random_parity_snapshot(true)
	if diagnostic_actor_counts:
		_print_diagnostic_actor_counts(level_id, snapshot)
	_expect(
		actual_round_count == expected_round_count,
		(
			"%s reaches exactly %d proven complete actor rounds (actual=%d)"
			% [level_id, expected_round_count, actual_round_count]
		),
	)

	var scalar_fields: Array[String] = [
		"accepted_draw_count",
		"accepted_actor_draw_count",
		"final_draw_index",
	]
	var snapshot_fields: Array[String] = [
		"draw_count",
		"actor_draw_count",
		"final_draw_index",
	]
	for field_index: int in range(scalar_fields.size()):
		var expected_value := int(level.get(scalar_fields[field_index], -1))
		var actual_value := int(snapshot.get(snapshot_fields[field_index], -2))
		_expect(
			actual_value == expected_value,
			"%s %s matches (%d != %d)" % [
				level_id,
				snapshot_fields[field_index],
				actual_value,
				expected_value,
			],
		)
	var expected_state := str(level.get("final_state_hex", "0x0")).hex_to_int()
	_expect(
		int(snapshot.get("final_state", -1)) == expected_state,
		"%s final CRT state matches" % level_id,
	)
	for hash_name: String in [
		"ordered_call_site_actor_sha256",
		"ordered_call_site_actor_value_sha256",
		"actor_order_sha256",
		"actor_value_sha256",
	]:
		_expect(
			str(snapshot.get(hash_name, "")) == str(level.get(hash_name, "")),
			"%s %s matches" % [level_id, hash_name],
		)
	var expected_site_counts := _site_count_dictionary(
		level.get("call_site_counts", []) as Array
	)
	var actual_site_counts: Dictionary = snapshot.get(
		"call_site_counts",
		{},
	) as Dictionary
	_expect(
		actual_site_counts == expected_site_counts,
		"%s per-call-site counts match%s" % [
			level_id,
			_site_count_difference(expected_site_counts, actual_site_counts),
		],
	)
	var expected_actor_site_counts := _actor_site_count_dictionary(
		level.get("actor_call_site_counts", []) as Array
	)
	var actual_actor_site_counts: Dictionary = snapshot.get(
		"actor_call_site_counts",
		{},
	) as Dictionary
	_expect(
		actual_actor_site_counts == expected_actor_site_counts,
		"%s per-actor call-site counts match%s" % [
			level_id,
			_site_count_difference(
				expected_actor_site_counts,
				actual_actor_site_counts,
			),
		],
	)
	_dispose_main(main)
	await process_frame


func _site_count_dictionary(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		result[str(row.get("call_site_rva", ""))] = int(row.get("count", 0))
	return result


func _actor_site_count_dictionary(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var key := "%d:%s" % [
			int(row.get("runtime_index", -1)),
			str(row.get("call_site_rva", "")),
		]
		result[key] = int(row.get("count", 0))
	return result


func _print_diagnostic_actor_counts(
	level_id: String,
	snapshot: Dictionary,
) -> void:
	var source: Dictionary = snapshot.get(
		"actor_call_site_counts",
		{},
	) as Dictionary
	var selected: Dictionary = {}
	for key_value: Variant in source.keys():
		var key := str(key_value)
		if (
			key.ends_with(":0x00056105")
			or key.ends_with(":0x00058946")
			or key.ends_with(":0x0005D47E")
			or key.ends_with(":0x0005D394")
			or key.ends_with(":0x0005D08F")
			or key.ends_with(":0x0005D09D")
			or key.ends_with(":0x0005D0B4")
			or key.ends_with(":0x0005D0CB")
			or key.ends_with(":0x0005D15F")
		):
			selected[key] = int(source[key])
	print(
		"CRT_ACTOR_COUNTS %s %s"
		% [level_id, JSON.stringify(selected)]
	)


func _site_count_difference(expected: Dictionary, actual: Dictionary) -> String:
	var keys: Array = expected.keys()
	for key_value: Variant in actual.keys():
		if not keys.has(key_value):
			keys.append(key_value)
	keys.sort()
	var differences: Array[String] = []
	for key_value: Variant in keys:
		var key := str(key_value)
		var expected_count := int(expected.get(key, 0))
		var actual_count := int(actual.get(key, 0))
		if expected_count == actual_count:
			continue
		differences.append(
			" %s=%d/%d" % [key, actual_count, expected_count]
		)
		if differences.size() >= 8:
			break
	return "".join(differences)


func _dispose_main(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	root.remove_child(main)
	main.free()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _finish() -> void:
	if failures.is_empty():
		print(
			"Recurring CRT random runtime parity passed (%d checks)."
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
