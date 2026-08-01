extends SceneTree

const LEGACY_CRT_RANDOM_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const ORIGINAL_STARTUP_CATALOG: Script = preload(
	"res://scripts/original_crt_random_startup_catalog.gd"
)
const SQUAD_UNIT_SCRIPT: Script = preload(
	"res://scripts/squad_unit.gd"
)
const ENEMY_UNIT_SCRIPT: Script = preload(
	"res://scripts/enemy_unit.gd"
)
const NAVIGATION_GRID_DATA: Script = preload(
	"res://scripts/navigation_grid_data.gd"
)
const DYNAMIC_OCCUPANCY_GRID: Script = preload(
	"res://scripts/dynamic_occupancy_grid.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_twelve_level_catalog()
	_test_exact_startup_checkpoint_and_next_draw()
	_test_exact_first_gameplay_update_replay()
	_test_first_gameplay_actor_side_effects()
	_test_imported_actor_profile_and_gate()
	_test_dynamic_actor_constructor_sequence()
	_test_timing_snapshot_round_trip()
	_test_corrected_enemy_ai_call_site_semantics()
	if failures.is_empty():
		print("Original CRT random tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_twelve_level_catalog() -> void:
	var catalog: Dictionary = ORIGINAL_STARTUP_CATALOG.load_catalog()
	var levels_value: Variant = catalog.get("levels", [])
	_expect(
		levels_value is Array and (levels_value as Array).size() == 12,
		"startup catalog exposes exactly the 12 formal MOD levels",
	)
	var expected_draw_counts := [
		8489,
		12060,
		5552,
		6976,
		12844,
		5044,
		7840,
		11592,
		5180,
		8858,
		8476,
		7432,
	]
	var expected_first_update_counts := [
		59,
		81,
		30,
		50,
		112,
		108,
		45,
		89,
		30,
		44,
		87,
		34,
	]
	var actor_count := 0
	var gate_actor_count := 0
	var first_update_count := 0
	var first_update_music_draw_count := 0
	var first_update_outcome_count := 0
	var semantic_effect_counts := {
		"route_wait_limit": 0,
		"pursuit_command_snapshot": 0,
		"primary_candidate_scan": 0,
		"blocked_retry_destination": 0,
		"secondary_candidate_scan": 0,
		"secondary_search_destination": 0,
	}
	for level_index: int in range(12):
		var level_id := "m%03d" % level_index
		var profile: Dictionary = (
			ORIGINAL_STARTUP_CATALOG.level_profile(level_id)
		)
		_expect(
			int(profile.get("initialization_draw_count", 0))
				== int(expected_draw_counts[level_index]),
			"%s retains its captured startup draw count" % level_id,
		)
		var first_update_records: Array[Dictionary] = (
			ORIGINAL_STARTUP_CATALOG.first_gameplay_update_records(
				level_id
			)
		)
		_expect(
			first_update_records.size()
				== int(expected_first_update_counts[level_index]),
			"%s retains its complete first gameplay update" % level_id,
		)
		first_update_count += first_update_records.size()
		var outcomes: Array[Dictionary] = (
			ORIGINAL_STARTUP_CATALOG
			. first_gameplay_update_outcomes(level_id)
		)
		first_update_outcome_count += outcomes.size()
		for outcome: Dictionary in outcomes:
			var effects_value: Variant = outcome.get(
				"semantic_effects",
				[],
			)
			if not effects_value is Array:
				continue
			for effect_value: Variant in effects_value as Array:
				var effect := str(effect_value)
				if semantic_effect_counts.has(effect):
					semantic_effect_counts[effect] = (
						int(semantic_effect_counts[effect]) + 1
					)
		for record: Dictionary in first_update_records:
			if (
				int(record.get("runtime_index", -2)) == -1
				and str(record.get("call_site_rva", ""))
					== "0x00006A73"
			):
				first_update_music_draw_count += 1
		actor_count += (profile.get("actor_initialization", []) as Array).size()
		gate_actor_count += (
			profile.get("observation_gate_actor_indices", []) as Array
		).size()
	_expect(
		actor_count == 772,
		"startup catalog joins all 772 imported active actors",
	)
	_expect(
		gate_actor_count == 656,
		"startup catalog preserves all 656 observation-gate actors",
	)
	_expect(
		first_update_count == 769,
		"startup catalog preserves all 769 first-update draws",
	)
	_expect(
		first_update_music_draw_count == 12,
		"each captured first update ends with one process-global music draw",
	)
	_expect(
		first_update_outcome_count == 76,
		"startup catalog preserves all 76 actor-bound first-update outcomes",
	)
	_expect(
		int(semantic_effect_counts["route_wait_limit"]) == 3
		and int(semantic_effect_counts["pursuit_command_snapshot"]) == 36
		and int(semantic_effect_counts["primary_candidate_scan"]) == 14
		and int(semantic_effect_counts["blocked_retry_destination"]) == 3
		and int(semantic_effect_counts["secondary_candidate_scan"]) == 16
		and int(semantic_effect_counts["secondary_search_destination"]) == 4,
		"first-update outcomes retain every recovered side-effect family",
	)


func _test_exact_startup_checkpoint_and_next_draw() -> void:
	var game = MAIN_SCRIPT.new()
	var applied := bool(game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	))
	_expect(applied, "m000 startup checkpoint applies")
	_expect(
		game.legacy_crt_random_state == 0xCEBEAFA8
		and game.legacy_crt_random_draw_index == 8489,
		"m000 resumes the original process-global stream after draw 8489",
	)
	var expected_state: int = LEGACY_CRT_RANDOM_CATALOG.next_state(
		0xCEBEAFA8
	)
	var expected_value: int = LEGACY_CRT_RANDOM_CATALOG.random_value(
		expected_state
	)
	var draw: Dictionary = game.next_legacy_crt_random(0x0005C81C)
	_expect(
		int(draw.get("state", 0)) == expected_state
		and int(draw.get("value", -1)) == expected_value
		and int(draw.get("draw_index", 0)) == 8490,
		"the first gameplay draw continues the captured MSVCRT LCG exactly",
	)
	game.free()


func _test_exact_first_gameplay_update_replay() -> void:
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_random_trace_enabled = true
	var records: Array[Dictionary] = (
		ORIGINAL_STARTUP_CATALOG.first_gameplay_update_records("m000")
	)
	var expected := _draw_values(
		game.legacy_crt_random_state,
		records.size(),
	)
	var replayed := bool(game.call(
		"_replay_original_first_gameplay_random_update",
		"m000",
		false,
	))
	_expect(
		replayed
		and game.legacy_crt_random_draw_index == 8548
		and game.legacy_crt_random_state == int(expected.get("state", 0)),
		"m000 replays all 59 first-update draws from the captured checkpoint",
	)
	var exact_trace_match: bool = (
		game.legacy_crt_random_trace.size() == records.size()
	)
	for record_index: int in range(records.size()):
		if not exact_trace_match:
			break
		var record: Dictionary = records[record_index]
		var trace_record: Dictionary = (
			game.legacy_crt_random_trace[record_index]
		)
		exact_trace_match = (
			int(trace_record.get("value", -1))
				== int(record.get("value", -2))
			and int(trace_record.get("call_site_rva", 0))
				== str(
					record.get("call_site_rva", "0x0")
				).hex_to_int()
			and int(trace_record.get("draw_index", 0))
				== 8490 + record_index
		)
	_expect(
		exact_trace_match,
		"m000 replay preserves every captured value, call site and draw index",
	)
	game.free()


func _test_first_gameplay_actor_side_effects() -> void:
	var m004_outcomes: Array[Dictionary] = (
		ORIGINAL_STARTUP_CATALOG.first_gameplay_update_outcomes(
			"m004"
		)
	)
	var search_outcome: Dictionary = {}
	var blocked_outcome: Dictionary = {}
	for outcome: Dictionary in m004_outcomes:
		match int(outcome.get("runtime_index", -1)):
			69:
				blocked_outcome = outcome
			141:
				search_outcome = outcome
	_expect(
		not search_outcome.is_empty()
		and (
			search_outcome.get("semantic_effects", []) as Array
		).has("secondary_search_destination")
		and int(
			(search_outcome.get(
				"post_update_state",
				{},
			) as Dictionary).get("goal_x", 0)
		) == 3069
		and int(
			(search_outcome.get(
				"post_update_state",
				{},
			) as Dictionary).get("goal_y", 0)
		) == 445,
		"m004 actor 141 retains the exact secondary-search destination",
	)
	_expect(
		not blocked_outcome.is_empty()
		and (
			blocked_outcome.get("semantic_effects", []) as Array
		).has("blocked_retry_destination")
		and int(
			(blocked_outcome.get(
				"post_update_state",
				{},
			) as Dictionary).get("resolved_goal_x", 0)
		) == 2506
		and int(
			(blocked_outcome.get(
				"post_update_state",
				{},
			) as Dictionary).get("resolved_goal_y", 0)
		) == 1038,
		"m004 actor 69 retains the exact blocked-retry destination",
	)

	var movement := PackedInt64Array()
	movement.resize(12 * 8)
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		12,
		8,
		Vector2i(32, 16),
		movement,
	)
	navigation.prepare_astar()
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	var actor = SQUAD_UNIT_SCRIPT.new()
	var empty_groups: Array[Dictionary] = []
	actor.configure(
		"first-update-search",
		Color.WHITE,
		navigation.cell_to_world(Vector2i(2, 3)),
		null,
		empty_groups,
		empty_groups,
		141,
		occupancy,
	)
	actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 20],
		"original_runtime_profile": {"runtime_index": 141},
	})
	occupancy.finalize_registration()
	var synthetic_outcome := search_outcome.duplicate(true)
	synthetic_outcome["scene_index"] = 141
	(synthetic_outcome["post_update_state"] as Dictionary)["goal_x"] = 208
	(synthetic_outcome["post_update_state"] as Dictionary)["goal_y"] = 56
	(
		synthetic_outcome["post_update_state"] as Dictionary
	)["resolved_goal_x"] = 208
	(
		synthetic_outcome["post_update_state"] as Dictionary
	)["resolved_goal_y"] = 56
	var synthetic_records: Array[Dictionary] = []
	var synthetic_sites: Array = synthetic_outcome.get(
		"call_site_rvas",
		[],
	)
	for site_value: Variant in synthetic_sites:
		synthetic_records.append({
			"runtime_index": 141,
			"call_site_rva": str(site_value),
			"value": 1,
		})
	var applied: bool = actor.apply_original_first_gameplay_update_outcome(
		synthetic_outcome,
		synthetic_records,
	)
	_expect(
		applied
		and actor.original_first_gameplay_update_serial == 1
		and actor.original_first_gameplay_navigation_applied
		and actor.original_first_gameplay_goal == Vector2(208.0, 56.0)
		and actor.is_running
		and actor.movement_path_index < actor.movement_path.size()
		and actor.target_position == Vector2(208.0, 56.0),
		"secondary-search outcome applies its exact mode and A* destination",
	)
	actor.free()

	var route_actor = SQUAD_UNIT_SCRIPT.new()
	route_actor.scene_index = 1416
	route_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 1},
	})
	var route_outcome: Dictionary = {}
	for outcome: Dictionary in (
		ORIGINAL_STARTUP_CATALOG.first_gameplay_update_outcomes(
			"m000"
		)
	):
		if int(outcome.get("runtime_index", -1)) == 1:
			route_outcome = outcome
			break
	var route_records: Array[Dictionary] = [{
		"runtime_index": 1,
		"call_site_rva": "0x00058946",
		"value": 20042,
	}]
	_expect(
		route_actor.apply_original_first_gameplay_update_outcome(
			route_outcome,
			route_records,
		)
		and route_actor.original_ai_idle_tick_counter == 0
		and route_actor.original_ai_idle_tick_limit == 82
		and route_actor.original_first_gameplay_route_wait_limit == 82,
		"route outcome restores rand()%160+40 to the shared native counter",
	)
	route_actor.free()

	var timeline_enemy = ENEMY_UNIT_SCRIPT.new()
	var timeline: Array[Dictionary] = [
		{"elapsed_seconds": 0.0, "position": Vector2.ZERO},
		{"elapsed_seconds": 5.0, "position": Vector2.ONE},
	]
	timeline_enemy.stable_mod_patrol_timeline = timeline
	_expect(
		not timeline_enemy.call(
			"_should_apply_original_first_gameplay_navigation",
			"blocked_retry_destination",
		)
		and not timeline_enemy.call(
			"_should_apply_original_first_gameplay_navigation",
			"pursuit_command_snapshot",
		)
		and bool(timeline_enemy.call(
			"_should_apply_original_first_gameplay_navigation",
			"secondary_search_destination",
		)),
		"stable MOD patrol evidence supersedes only overlapping transient goals",
	)
	timeline_enemy.free()


func _test_imported_actor_profile_and_gate() -> void:
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_random_trace_enabled = true
	var actor = SQUAD_UNIT_SCRIPT.new()
	actor.scene_index = 1415
	actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 0},
	})
	var bound: bool = actor.bind_original_crt_random_source(
		game,
		"m000",
	)
	_expect(
		bound
		and actor.original_runtime_index == 0
		and actor.original_crt_observation_gate_enabled,
		"runtime actor 0 binds to its exact m000 profile and gate eligibility",
	)
	_expect(
		int(actor.original_crt_initialization_profile.get(
			"initial_idle_limit",
			-1,
		)) == 10
		and int(actor.original_crt_initialization_profile.get(
			"initial_facing_direction",
			-1,
		)) == 8
		and int(actor.original_crt_initialization_profile.get(
			"initial_ai_phase",
			-1,
		)) == 30
		and int(actor.original_crt_initialization_profile.get(
			"initial_reaction_limit",
			-1,
		)) == 48,
		"runtime actor 0 exposes the four captured constructor values",
	)
	_expect(
		actor.process_physics_priority == 0,
		"random binding does not disturb established actor physics order",
	)
	var state_before: int = game.legacy_crt_random_state
	var expected_state: int = LEGACY_CRT_RANDOM_CATALOG.next_state(
		state_before
	)
	var expected_value: int = LEGACY_CRT_RANDOM_CATALOG.random_value(
		expected_state
	)
	actor.call("_advance_original_crt_observation_gate", 0.04)
	_expect(
		game.legacy_crt_random_draw_index == 8490
		and actor.original_crt_observation_gate_serial == 1
		and actor.original_crt_observation_gate_passed
			== (expected_value % 2 > 0),
		"the actor consumes one exact global observation-gate draw at 30 Hz",
	)
	_expect(
		game.legacy_crt_random_trace.size() == 1
		and int(game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005C81C,
		"the observation gate records the recovered original call site",
	)
	actor.free()
	game.free()


func _test_dynamic_actor_constructor_sequence() -> void:
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_random_trace_enabled = true
	var expected := _draw_values(
		game.legacy_crt_random_state,
		4,
	)
	var actor = SQUAD_UNIT_SCRIPT.new()
	actor.scene_index = 9000
	actor.bind_original_crt_random_source(game, "m000", 1)
	var initialized: bool = actor.initialize_dynamic_original_crt_random()
	var values: Array = expected.get("values", [])
	_expect(
		initialized
		and game.legacy_crt_random_draw_index == 8493,
		"dynamic actor construction appends four draws to the global stream",
	)
	_expect(
		int(actor.original_crt_initialization_profile.get(
			"initial_idle_limit",
			-1,
		)) == int(values[0]) % 160
		and int(actor.original_crt_initialization_profile.get(
			"initial_facing_direction",
			-1,
		)) == mini((int(values[1]) % 9) + 1, 8)
		and int(actor.original_crt_initialization_profile.get(
			"initial_ai_phase",
			-1,
		)) == int(values[2]) % 60
		and int(actor.original_crt_initialization_profile.get(
			"initial_reaction_limit",
			-1,
		)) == (int(values[3]) % 40) + 40,
		"dynamic actor uses the four recovered constructor transforms",
	)
	var expected_sites := [
		0x00050967,
		0x00050980,
		0x0005340B,
		0x0005358B,
	]
	var sites_match: bool = game.legacy_crt_random_trace.size() == 4
	for index: int in range(game.legacy_crt_random_trace.size()):
		sites_match = (
			sites_match
			and int(game.legacy_crt_random_trace[index].get(
				"call_site_rva",
				0,
			)) == int(expected_sites[index])
		)
	_expect(
		sites_match,
		"dynamic actor constructor preserves exact original call-site order",
	)
	_expect(
		actor.process_physics_priority == 0,
		"dynamic actor binding leaves append order to the scene tree",
	)
	actor.free()
	game.free()


func _test_timing_snapshot_round_trip() -> void:
	var game = MAIN_SCRIPT.new()
	var source = SQUAD_UNIT_SCRIPT.new()
	source.scene_index = 1415
	source.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 0},
	})
	source.bind_original_crt_random_source(game, "m000")
	source.original_crt_observation_gate_elapsed = 0.0125
	source.original_crt_observation_gate_passed = true
	source.original_crt_observation_gate_serial = 7
	source.original_first_gameplay_update_serial = 1
	source.original_first_gameplay_semantic_effects.append(
		"blocked_retry_destination"
	)
	source.original_first_gameplay_call_sites = PackedInt32Array([
		0x00055BFB,
		0x00055C0F,
		0x00055C23,
		0x00055C3A,
	])
	source.original_first_gameplay_goal_kind = 1
	source.original_first_gameplay_command_variant = 0
	source.original_first_gameplay_movement_path_state = 2
	source.original_first_gameplay_movement_mode = 1
	source.original_first_gameplay_goal = Vector2(2736.0, 1144.0)
	source.original_first_gameplay_resolved_goal = Vector2(
		2506.0,
		1038.0,
	)
	source.original_first_gameplay_route_wait_limit = -1
	source.original_first_gameplay_navigation_applied = false
	var snapshot: Dictionary = source.original_crt_random_timing_snapshot()
	var restored = SQUAD_UNIT_SCRIPT.new()
	restored.scene_index = 1415
	restored.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 0},
	})
	restored.bind_original_crt_random_source(game, "m000")
	var accepted: bool = restored.restore_original_crt_random_timing(
		snapshot
	)
	_expect(
		accepted
		and is_equal_approx(
			restored.original_crt_observation_gate_elapsed,
			0.0125,
		)
		and restored.original_crt_observation_gate_passed
		and restored.original_crt_observation_gate_serial == 7,
		"save/load restores the per-actor global-stream gate phase",
	)
	_expect(
		restored.original_first_gameplay_update_serial == 1
		and restored.original_first_gameplay_semantic_effects.size() == 1
		and restored.original_first_gameplay_semantic_effects[0]
			== "blocked_retry_destination"
		and restored.original_first_gameplay_call_sites
			== PackedInt32Array([
				0x00055BFB,
				0x00055C0F,
				0x00055C23,
				0x00055C3A,
			])
		and restored.original_first_gameplay_goal_kind == 1
		and restored.original_first_gameplay_movement_path_state == 2
		and restored.original_first_gameplay_movement_mode == 1
		and restored.original_first_gameplay_goal
			== Vector2(2736.0, 1144.0)
		and restored.original_first_gameplay_resolved_goal
			== Vector2(2506.0, 1038.0)
		and not restored.original_first_gameplay_navigation_applied,
		"save/load retains the exact first-gameplay native outcome snapshot",
	)
	source.free()
	restored.free()
	game.free()


func _test_corrected_enemy_ai_call_site_semantics() -> void:
	var expected := {
		0x0005C998: "idle_no_contact_reaction_limit_rand_mod_40_plus_40",
		0x0005CB2B: "tracked_target_reaction_limit_rand_mod_40_plus_40",
		0x0005CB60: "corpse_investigation_animation_gate_rand_mod_3",
		0x0005CB9C: "corpse_reaction_limit_rand_mod_40_plus_40",
		0x0005CC69: "item_investigation_reaction_limit_rand_mod_40_plus_20",
		0x0005CCCD: "tracked_target_face_or_continue_gate_rand_mod_20_less_than_10",
		0x0005CD01: "tracked_target_reaction_limit_rand_mod_20_plus_20",
	}
	var all_match := true
	for call_site: Variant in expected:
		var metadata: Dictionary = (
			LEGACY_CRT_RANDOM_CATALOG.metadata_for_rva(int(call_site))
		)
		all_match = (
			all_match
			and str(metadata.get("purpose", "")) == str(expected[call_site])
		)
	_expect(
		all_match,
		"sub_45C710 metadata matches the seven verified quotient/remainder operands",
	)


func _draw_values(initial_state: int, count: int) -> Dictionary:
	var state := initial_state
	var values: Array[int] = []
	for _draw_index: int in range(count):
		state = LEGACY_CRT_RANDOM_CATALOG.next_state(state)
		values.append(LEGACY_CRT_RANDOM_CATALOG.random_value(state))
	return {
		"state": state,
		"values": values,
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
