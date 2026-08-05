extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const BASELINE_PATH := (
	"res://data/original_crt_random_input_branch_timing.json"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(BASELINE_PATH)
	)
	_expect(
		baseline_value is Dictionary,
		"input-branch CRT random baseline is readable",
	)
	if not baseline_value is Dictionary:
		_finish()
		return
	var branches: Array = (baseline_value as Dictionary).get(
		"branches",
		[],
	) as Array
	_expect(
		branches.size() == 1,
		"one bounded original movement branch is available",
	)
	if branches.size() != 1:
		_finish()
		return
	await _exercise_branch(branches[0] as Dictionary)
	_finish()


func _exercise_branch(branch: Dictionary) -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["show_briefings"] = false
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	main.runtime_settings["ruleset_mode"] = "classic"
	main.runtime_settings["difficulty_mode"] = "normal"
	main.legacy_crt_random_trace_enabled = true
	var trace_started := bool(main.begin_legacy_crt_random_parity_trace())
	main.switch_level(0, false, false)
	var branch_started := bool(main.begin_legacy_crt_input_branch(
		str(branch.get("id", ""))
	))
	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	if main.media_director != null:
		main.media_director.close_for_state_change()
	paused = false
	_expect(trace_started, "m000 movement branch starts a parity hash trace")
	_expect(branch_started, "m000 movement branch selects its bounded event catalog")

	var first_gate_index := int(
		(branch.get("observation_gate_actor_indices", []) as Array)[0]
	)
	var first_gate_actor: Node2D
	var player_actor: SquadUnit
	for actor_value: Variant in main.call("_all_active_runtime_actors") as Array:
		var actor := actor_value as Node2D
		var runtime_index := int(actor.get("original_runtime_index"))
		if runtime_index == first_gate_index:
			first_gate_actor = actor
		if runtime_index == 18 and actor is SquadUnit:
			player_actor = actor as SquadUnit
	_expect(
		first_gate_actor != null and player_actor != null,
		"m000 exposes gate actor 0 and command actor 18",
	)
	if first_gate_actor == null or player_actor == null:
		_dispose_main(main)
		return

	main.selected_units.clear()
	main.selected_units.append(player_actor)
	player_actor.set_selected(true)
	var input_events: Array = branch.get("input_events", []) as Array
	var input_event_index := 0
	var expected_round_count := int(branch.get("complete_round_count", 0))
	var physics_frame_count := 0
	while (
		int(first_gate_actor.get("original_crt_observation_gate_serial"))
		< expected_round_count
		and physics_frame_count < expected_round_count + 16
	):
		var completed_rounds := int(
			first_gate_actor.get("original_crt_observation_gate_serial")
		)
		if input_event_index < input_events.size():
			var input_event := input_events[input_event_index] as Dictionary
			if completed_rounds + 1 == int(input_event.get("round_index", -1)):
				main.issue_formation_move(Vector2(
					float(input_event.get("destination_x", 0)),
					float(input_event.get("destination_y", 0)),
				))
				input_event_index += 1
		await physics_frame
		physics_frame_count += 1

	var actual_round_count := int(
		first_gate_actor.get("original_crt_observation_gate_serial")
	)
	var snapshot: Dictionary = main.legacy_crt_random_parity_snapshot(true)
	_expect(
		actual_round_count == expected_round_count,
		"m000 movement branch reaches 413 complete actor rounds",
	)
	_expect(
		input_event_index == input_events.size()
		and player_actor.original_acknowledgement_serial == 2
		and player_actor.original_pending_acknowledgement_count == 0,
		"both commands consume exactly one acknowledgement in actor 18's slot",
	)
	for field_name: String in [
		"accepted_draw_count",
		"accepted_actor_draw_count",
		"final_draw_index",
	]:
		var snapshot_name := (
			field_name.trim_prefix("accepted_")
			if field_name.begins_with("accepted_")
			else field_name
		)
		_expect(
			int(snapshot.get(snapshot_name, -1))
				== int(branch.get(field_name, -2)),
			"m000 movement branch %s matches (%d/%d)" % [
				snapshot_name,
				int(snapshot.get(snapshot_name, -1)),
				int(branch.get(field_name, -2)),
			],
		)
	_expect(
		int(snapshot.get("final_state", -1))
			== str(branch.get("final_state_hex", "0x0")).hex_to_int(),
		"m000 movement branch final CRT state matches",
	)
	for hash_name: String in [
		"ordered_call_site_actor_sha256",
		"ordered_call_site_actor_value_sha256",
		"actor_order_sha256",
		"actor_value_sha256",
	]:
		_expect(
			str(snapshot.get(hash_name, "")) == str(branch.get(hash_name, "")),
			"m000 movement branch %s matches" % hash_name,
		)
	var expected_site_counts := _site_count_dictionary(
		branch.get("call_site_counts", []) as Array
	)
	var actual_site_counts: Dictionary = snapshot.get(
		"call_site_counts",
		{},
	) as Dictionary
	_expect(
		actual_site_counts == expected_site_counts,
		"m000 movement branch per-call-site counts match%s" %
			_site_count_difference(expected_site_counts, actual_site_counts),
	)
	_expect(
		player_actor.position.distance_to(Vector2(176.0, 56.0)) <= 1.0,
		"m000 player completes the captured outbound/return route",
	)
	_dispose_main(main)
	await process_frame


func _site_count_dictionary(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		result[str(row.get("call_site_rva", ""))] = int(row.get("count", 0))
	return result


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
		differences.append(" %s=%d/%d" % [key, actual_count, expected_count])
		if differences.size() >= 10:
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
			"Input-branch CRT random runtime parity passed (%d checks)."
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
