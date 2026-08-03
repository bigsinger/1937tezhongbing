extends SceneTree

const LEGACY_CRT_RANDOM_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const ORIGINAL_STARTUP_CATALOG: Script = preload(
	"res://scripts/original_crt_random_startup_catalog.gd"
)
const ORIGINAL_RUNTIME_STATE: Script = preload(
	"res://scripts/original_crt_random_runtime_state.gd"
)
const ORIGINAL_LOCAL_SEARCH_TIMING: Script = preload(
	"res://scripts/original_crt_random_local_search_timing.gd"
)
const ORIGINAL_ACTOR_EVENT_TIMING: Script = preload(
	"res://scripts/original_crt_random_actor_event_timing.gd"
)
const AI_IDLE_RANDOM_RULES: Script = preload(
	"res://scripts/legacy_enemy_ai_rules.gd"
)
const LEGACY_AMBIENT_PARTICLE_FIELD: Script = preload(
	"res://scripts/legacy_ambient_particle_field.gd"
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
	_test_parity_hash_trace()
	_test_first_gameplay_actor_side_effects()
	_test_twelve_level_runtime_state_and_pursuit()
	_test_recurring_secondary_search_runtime()
	_test_original_local_search_timing()
	_test_original_actor_event_timing()
	_test_recovered_shared_counter_cadence()
	_test_original_ambient_particle_stream()
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


func _test_parity_hash_trace() -> void:
	var baseline_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://data/original_crt_random_recurring_timing.json"
		)
	)
	_expect(
		baseline_value is Dictionary,
		"recurring parity baseline is readable by the runtime",
	)
	if not baseline_value is Dictionary:
		return
	var levels_value: Variant = (baseline_value as Dictionary).get(
		"levels",
		[],
	)
	if not levels_value is Array or (levels_value as Array).is_empty():
		_expect(false, "recurring parity baseline exposes m000")
		return
	var first_round: Dictionary = (
		((levels_value as Array)[0] as Dictionary).get("rounds", [])[0]
	)
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	var began := bool(game.begin_legacy_crt_random_parity_trace())
	var replayed := bool(game.call(
		"_replay_original_first_gameplay_random_update",
		"m000",
		false,
	))
	var snapshot: Dictionary = game.legacy_crt_random_parity_snapshot(true)
	_expect(
		began
		and replayed
		and int(snapshot.get("draw_count", 0)) == 59
		and int(snapshot.get("actor_draw_count", 0)) == 58
		and int(snapshot.get("final_draw_index", 0)) == 8548
		and int(snapshot.get("call_site_counts", {}).get(
			"0x0005C81C",
			0,
		)) == 54,
		"parity trace records exact draw, actor and call-site counts",
	)
	var hashes_match := true
	for hash_name: String in [
		"ordered_call_site_actor_sha256",
		"ordered_call_site_actor_value_sha256",
		"actor_order_sha256",
		"actor_value_sha256",
	]:
		hashes_match = (
			hashes_match
			and str(snapshot.get(hash_name, ""))
				== str(first_round.get(hash_name, ""))
		)
	_expect(
		hashes_match,
		"runtime parity hashes use the committed little-endian trace encoding",
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

	var candidate_outcome: Dictionary = {}
	for outcome: Dictionary in (
		ORIGINAL_STARTUP_CATALOG.first_gameplay_update_outcomes(
			"m000"
		)
	):
		if int(outcome.get("runtime_index", -1)) == 125:
			candidate_outcome = outcome
			break
	var candidate_game = MAIN_SCRIPT.new()
	candidate_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	candidate_game.legacy_crt_random_trace_enabled = true
	var candidate_actor = SQUAD_UNIT_SCRIPT.new()
	candidate_actor.scene_index = 1621
	candidate_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 33],
		"original_runtime_profile": {"runtime_index": 125},
	})
	candidate_actor.bind_original_crt_random_source(
		candidate_game,
		"m000",
	)
	var candidate_records: Array[Dictionary] = [{
		"runtime_index": 125,
		"call_site_rva": "0x00055216",
		"value": 16139,
	}]
	var candidate_applied: bool = (
		candidate_actor
		. apply_original_first_gameplay_update_outcome(
			candidate_outcome,
			candidate_records,
		)
	)
	candidate_actor.call(
		"_advance_original_crt_actor_random_tick",
		1.0 / 60.0,
	)
	_expect(
		candidate_applied
		and candidate_actor
			.original_crt_primary_candidate_scan_enabled
		and candidate_actor
			.original_crt_primary_candidate_scan_serial == 2
		and candidate_actor
			.original_crt_primary_candidate_scan_passed
		and candidate_game.legacy_crt_random_draw_index == 8490
		and candidate_game.legacy_crt_random_trace.size() == 1
		and int(candidate_game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x00055216,
		"primary candidate scan continues every recovered 60 Hz actor tick",
	)
	candidate_actor.free()
	candidate_game.free()

	# Runtime types 18 and 26 enter the secondary-search routine through a
	# second native dispatch path.  The first-update catalog proves the exact
	# actors which use that path, so keep that evidence-driven enablement under
	# a standalone test that also runs in CI without original assets.
	var indirect_secondary_specs: Array[Dictionary] = [
		{
			"level_id": "m005",
			"runtime_index": 120,
			"scene_index": 742,
			"runtime_type": 18,
		},
		{
			"level_id": "m006",
			"runtime_index": 69,
			"scene_index": 1464,
			"runtime_type": 26,
		},
	]
	for spec: Dictionary in indirect_secondary_specs:
		var level_id := str(spec.get("level_id", ""))
		var runtime_index := int(spec.get("runtime_index", -1))
		var indirect_outcome: Dictionary = {}
		for outcome: Dictionary in (
			ORIGINAL_STARTUP_CATALOG.first_gameplay_update_outcomes(
				level_id
			)
		):
			if int(outcome.get("runtime_index", -1)) == runtime_index:
				indirect_outcome = outcome
				break
		var expected_sites_value: Variant = indirect_outcome.get(
			"call_site_rvas",
			[],
		)
		var indirect_records: Array[Dictionary] = []
		if expected_sites_value is Array:
			for record: Dictionary in (
				ORIGINAL_STARTUP_CATALOG.first_gameplay_update_records(
					level_id
				)
			):
				if (
					int(record.get("runtime_index", -1))
						== runtime_index
					and (expected_sites_value as Array).has(
						str(record.get("call_site_rva", ""))
					)
				):
					indirect_records.append(record)
		var indirect_actor = SQUAD_UNIT_SCRIPT.new()
		indirect_actor.scene_index = int(spec.get("scene_index", -1))
		indirect_actor.configure_runtime_actor_type({
			"database_header_values": [
				0,
				0,
				int(spec.get("runtime_type", -1)),
			],
			"original_runtime_profile": {
				"runtime_index": runtime_index,
			},
		})
		var indirect_applied: bool = (
			indirect_actor
			. apply_original_first_gameplay_update_outcome(
				indirect_outcome,
				indirect_records,
			)
		)
		_expect(
			indirect_applied
			and indirect_actor.original_secondary_search_enabled
			and indirect_actor.original_secondary_search_gate_serial == 1
			and indirect_actor.original_secondary_search_last_gate_value >= 0,
			(
				"runtime type %d keeps its catalog-proven indirect secondary "
				+ "search dispatch"
			) % int(spec.get("runtime_type", -1)),
		)
		indirect_actor.free()

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


func _test_twelve_level_runtime_state_and_pursuit() -> void:
	var catalog: Dictionary = ORIGINAL_RUNTIME_STATE.load_catalog()
	var levels_value: Variant = catalog.get("levels", [])
	_expect(
		levels_value is Array and (levels_value as Array).size() == 12,
		"runtime-state catalog exposes exactly the 12 formal MOD levels",
	)
	var actor_total := 0
	var pursuit_link_total := 0
	if levels_value is Array:
		for level_value: Variant in levels_value as Array:
			if not level_value is Dictionary:
				continue
			var level := level_value as Dictionary
			var actors_value: Variant = level.get("actors", [])
			if actors_value is Array:
				actor_total += (actors_value as Array).size()
			var pursuit_value: Variant = level.get("pursuit", {})
			if pursuit_value is Dictionary:
				var links_value: Variant = (
					(pursuit_value as Dictionary).get("links", [])
				)
				if links_value is Array:
					pursuit_link_total += (links_value as Array).size()
	_expect(
		actor_total == 772 and pursuit_link_total == 140,
		"runtime-state catalog retains all 772 actors and 140 pursuit links",
	)

	var expected_m000_chain := {
		104: 107,
		107: 106,
		106: 105,
		105: 103,
		119: 118,
		121: 124,
		124: 122,
		122: 123,
		123: 120,
	}
	var chain_matches := true
	for runtime_index: Variant in expected_m000_chain:
		chain_matches = (
			chain_matches
			and ORIGINAL_RUNTIME_STATE.pursuit_target_runtime_index(
				"m000",
				int(runtime_index),
			) == int(expected_m000_chain[runtime_index])
			and ORIGINAL_RUNTIME_STATE.pursuit_call_site_rva(
				"m000",
				int(runtime_index),
			) == 0x0005D47E
		)
	_expect(
		chain_matches,
		"m000 retains every recovered native pursuit-chain edge",
	)

	var follower_profile: Dictionary = ORIGINAL_RUNTIME_STATE.actor_profile(
		"m000",
		119,
	)
	var entry_value: Variant = follower_profile.get("entry", {})
	_expect(
		int(follower_profile.get("scene_index", -1)) == 1615
		and int(follower_profile.get("runtime_type", -1)) == 12
		and entry_value is Dictionary
		and int((entry_value as Dictionary).get(
			"pursuit_runtime_index",
			-1,
		)) == 118,
		"m000 actor 119 maps scene 1615 to its exact type-56 leader",
	)

	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_random_trace_enabled = true
	var counter_actor = SQUAD_UNIT_SCRIPT.new()
	counter_actor.scene_index = 1415
	counter_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 0},
	})
	counter_actor.bind_original_crt_random_source(game, "m000")
	_expect(
		counter_actor.original_ai_idle_tick_counter == 137
		and counter_actor.original_ai_idle_tick_limit == 162
		and counter_actor.original_route_update_active,
		"actor binding restores the captured shared counter and route phase",
	)
	counter_actor.free()
	var target = SQUAD_UNIT_SCRIPT.new()
	target.scene_index = 1614
	target.configure_runtime_actor_type({
		"database_header_values": [0, 0, 56],
		"original_runtime_profile": {"runtime_index": 118},
	})
	target.bind_original_crt_random_source(game, "m000")
	target.position = Vector2(300.0, 0.0)
	var follower = SQUAD_UNIT_SCRIPT.new()
	follower.scene_index = 1615
	follower.configure_runtime_actor_type({
		"database_header_values": [0, 0, 12],
		"original_runtime_profile": {"runtime_index": 119},
	})
	follower.bind_original_crt_random_source(game, "m000")
	follower.position = Vector2.ZERO
	var linked: bool = follower.bind_original_pursuit_target(target)
	var advanced: bool = bool(
		follower.call("_advance_original_pursuit_once")
	)
	_expect(
		linked
		and advanced
		and follower.original_pursuit_serial == 1
		and follower.original_pursuit_target_runtime_index == 118
		and follower.original_pursuit_call_site_rva == 0x0005D47E
		and follower.process_physics_priority == 1119,
		"runtime actor 119 consumes one ordered native pursuit update",
	)
	_expect(
		game.legacy_crt_random_trace.size() == 1
		and int(game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005D47E,
		"pursuit update records its recovered native call site",
	)

	follower.original_pursuit_delay_counter = 4
	follower.original_pursuit_elapsed = 0.0125
	follower.original_pursuit_last_command_variant = 1
	var snapshot: Dictionary = (
		follower.original_crt_random_timing_snapshot()
	)
	var restored = SQUAD_UNIT_SCRIPT.new()
	restored.scene_index = 1615
	restored.configure_runtime_actor_type({
		"database_header_values": [0, 0, 12],
		"original_runtime_profile": {"runtime_index": 119},
	})
	restored.bind_original_crt_random_source(game, "m000")
	restored.bind_original_pursuit_target(target)
	var restored_ok: bool = restored.restore_original_crt_random_timing(
		snapshot
	)
	_expect(
		restored_ok
		and restored.original_pursuit_delay_counter == 4
		and is_equal_approx(
			restored.original_pursuit_elapsed,
			0.0125,
		)
		and restored.original_pursuit_serial == 1
		and restored.original_pursuit_last_command_variant == 1,
		"save/load restores the recovered pursuit scheduler phase",
	)
	restored.free()
	follower.free()
	target.free()
	game.free()


func _test_original_local_search_timing() -> void:
	var catalog: Dictionary = ORIGINAL_LOCAL_SEARCH_TIMING.load_catalog()
	var levels_value: Variant = catalog.get("levels", [])
	var event_total := 0
	if levels_value is Array:
		for level_value: Variant in levels_value as Array:
			if level_value is Dictionary:
				event_total += int(
					(level_value as Dictionary).get("event_count", 0)
				)
	var event: Dictionary = (
		ORIGINAL_LOCAL_SEARCH_TIMING.event_for_actor_round(
		"m000",
		24,
		126,
		)
	)
	var event_values: Array[int] = []
	for value: Variant in event.get("values", []) as Array:
		event_values.append(int(value))
	_expect(
		levels_value is Array
		and (levels_value as Array).size() == 12
		and event_total == 107
		and int(event.get("world_x", -1)) == 251
		and int(event.get("world_y", -1)) == 933
		and int(event.get("shared_counter_before", -1)) == 61
		and int(event.get("shared_limit_before", -1)) == 61
		and event_values == [18727, 8672, 5707, 21496, 17942],
		"twelve-level catalog exposes all 107 proven local-search events",
	)
	_expect(
		ORIGINAL_LOCAL_SEARCH_TIMING.level_event_count("m007") == 56
		and ORIGINAL_LOCAL_SEARCH_TIMING.event_for_actor_round(
			"m001",
			24,
			126,
		).is_empty(),
		"local-search catalog preserves levels with and without events",
	)

	var diverged_game = MAIN_SCRIPT.new()
	diverged_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	diverged_game.legacy_crt_recurring_round_index = 24
	diverged_game.legacy_crt_random_trace_enabled = true
	diverged_game.invalidate_original_recurring_evidence("player_input")
	var diverged_actor = SQUAD_UNIT_SCRIPT.new()
	diverged_actor.scene_index = 1622
	diverged_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 33],
		"original_runtime_profile": {"runtime_index": 126},
	})
	diverged_actor.bind_original_crt_random_source(diverged_game, "m000")
	diverged_actor.position = Vector2(260.0, 933.0)
	diverged_actor.original_ai_idle_tick_counter = 61
	diverged_actor.original_ai_idle_tick_limit = 61
	_expect(
		not bool(diverged_actor.call(
			"_advance_original_recurring_local_search"
		))
		and diverged_game.legacy_crt_random_trace.is_empty(),
		"player input disables quiet-state replay before gameplay can diverge",
	)
	diverged_actor.free()
	diverged_game.free()
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_recurring_round_index = 24
	game.legacy_crt_random_trace_enabled = true
	var actor = SQUAD_UNIT_SCRIPT.new()
	actor.scene_index = 1622
	actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 33],
		"original_runtime_profile": {"runtime_index": 126},
	})
	actor.bind_original_crt_random_source(game, "m000")
	actor.position = Vector2(251.0, 933.0)
	actor.original_ai_idle_tick_counter = 61
	actor.original_ai_idle_tick_limit = 61
	var predicted_state: int = game.legacy_crt_random_state
	var predicted_values: Array[int] = []
	for _site_rva: int in actor.ORIGINAL_LOCAL_SEARCH_CALL_SITES:
		predicted_state = LEGACY_CRT_RANDOM_CATALOG.next_state(
			predicted_state
		)
		predicted_values.append(
			LEGACY_CRT_RANDOM_CATALOG.random_value(predicted_state)
		)
	var predicted_sample: Dictionary = (
		AI_IDLE_RANDOM_RULES.local_search_point_from_values(
			predicted_values,
			actor.position,
			actor.call("_original_secondary_search_world_bounds") as Rect2,
		)
	)
	var predicted_goal: Vector2 = predicted_sample.get(
		"point",
		actor.position,
	) as Vector2
	var predicted_limit := int(predicted_sample.get("next_wait_limit", 0))
	var applied := bool(
		actor.call("_advance_original_recurring_local_search")
	)
	var actual_sites := PackedInt32Array()
	for record: Dictionary in game.legacy_crt_random_trace:
		actual_sites.append(int(record.get("call_site_rva", 0)))
	_expect(
		applied
		and actual_sites == PackedInt32Array([
			0x0005D08F,
			0x0005D09D,
			0x0005D0B4,
			0x0005D0CB,
			0x0005D15F,
		])
		and actor.original_local_search_serial == 1
		and actor.original_local_search_last_round_index == 24
		and actor.original_local_search_last_goal == predicted_goal
		and actor.original_ai_idle_tick_counter == 0
		and actor.original_ai_idle_tick_limit == predicted_limit
		and actor.original_local_search_next_wait_limit == predicted_limit
		and not actor.original_local_search_values_match
		and not actor.original_route_update_active,
		"generic runtime consumes and applies one exact five-call search event",
	)
	actor.original_local_search_last_physics_frame = -1
	_expect(
		not bool(actor.call("_advance_original_recurring_local_search"))
		and game.legacy_crt_random_trace.size() == 5,
		"the same actor and round cannot consume a local-search event twice",
	)

	var snapshot: Dictionary = actor.original_crt_random_timing_snapshot()
	var restored = SQUAD_UNIT_SCRIPT.new()
	restored.scene_index = 1622
	restored.configure_runtime_actor_type({
		"database_header_values": [0, 0, 33],
		"original_runtime_profile": {"runtime_index": 126},
	})
	restored.bind_original_crt_random_source(game, "m000")
	var restored_ok: bool = restored.restore_original_crt_random_timing(
		snapshot
	)
	_expect(
		restored_ok
		and restored.original_local_search_serial == 1
		and restored.original_local_search_last_round_index == 24
		and restored.original_local_search_last_goal == predicted_goal
		and restored.original_local_search_next_wait_limit == predicted_limit,
		"local-search evidence phase survives save and restore",
	)
	restored.free()
	actor.free()
	game.free()


func _test_original_actor_event_timing() -> void:
	var catalog: Dictionary = ORIGINAL_ACTOR_EVENT_TIMING.load_catalog()
	var levels_value: Variant = catalog.get("levels", [])
	var route_call_sites: Array[int] = [0x00058946]
	var pursuit_call_sites: Array[int] = [0x0005D47E]
	var primary_call_sites: Array[int] = [
		0x00055216,
		0x0005528C,
		0x000552A3,
		0x000552BA,
		0x000552D1,
	]
	var blocked_call_sites: Array[int] = [
		0x00055BFB,
		0x00055C0F,
		0x00055C23,
		0x00055C3A,
	]
	var secondary_call_sites: Array[int] = [
		0x0005CEA6,
		0x0005CF33,
		0x0005CF4A,
		0x0005CF61,
		0x0005CF78,
	]
	var reaction_call_sites: Array[int] = [0x0005CB2B]
	var event_total := 0
	if levels_value is Array:
		for level_value: Variant in levels_value as Array:
			if level_value is Dictionary:
				event_total += int(
					(level_value as Dictionary).get("event_count", 0)
				)
	var route_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
		"m000",
		1,
		1,
		route_call_sites,
		)
	)
	var pursuit_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
			"m000",
			1,
			119,
			pursuit_call_sites,
		)
	)
	var primary_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
			"m007",
			2,
			109,
			primary_call_sites,
		)
	)
	var blocked_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
			"m004",
			1,
			69,
			blocked_call_sites,
		)
	)
	var secondary_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
			"m004",
			1,
			141,
			secondary_call_sites,
		)
	)
	var reaction_events: Array[Dictionary] = (
		ORIGINAL_ACTOR_EVENT_TIMING.events_for_actor_round(
			"m007",
			480,
			78,
			reaction_call_sites,
		)
	)
	_expect(
		levels_value is Array
		and (levels_value as Array).size() == 12
		and event_total == 29662
		and ORIGINAL_ACTOR_EVENT_TIMING.level_complete_round_count(
			"m000"
		) == 563
		and ORIGINAL_ACTOR_EVENT_TIMING.level_event_count("m000")
			== 3073,
		"actor-event catalog covers all 29,662 conditional calls in 12 levels",
	)
	_expect(
		route_events.size() == 1
		and int(route_events[0].get("value", -1)) == 20042
		and int(route_events[0].get("shared_counter_before", -1))
			== 76
		and pursuit_events.size() == 1
		and int(pursuit_events[0].get("value", -1)) == 6990
		and int(pursuit_events[0].get("pursuit_runtime_index", -1))
			== 118,
		"catalog lookup retains exact route and pursuit actor identity",
	)
	_expect(
		primary_events.size() == 5
		and int(primary_events[0].get("call_site_rva", 0))
			== 0x00055216
		and int(primary_events[4].get("value", -1)) == 3808
		and int(primary_events[0].get("world_x", -1)) == 3996
		and blocked_events.size() == 4
		and int(blocked_events[0].get("world_x", -1)) == 2446
		and int(blocked_events[3].get("value", -1)) == 6363
		and secondary_events.size() == 5
		and int(secondary_events[0].get("value", -1)) == 23843
		and int(secondary_events[4].get("value", -1)) == 26735
		and reaction_events.size() == 1
		and int(reaction_events[0].get("value", -1)) == 29043,
		"catalog retains exact primary, blocked, secondary and reaction groups",
	)

	var lifecycle_game = MAIN_SCRIPT.new()
	lifecycle_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	_expect(
		lifecycle_game.legacy_crt_recurring_evidence_replay_active
		and lifecycle_game.legacy_crt_recurring_evidence_max_round == 563
		and lifecycle_game.original_recurring_evidence_round_index() == 0,
		"quiet evidence lane starts bounded by the complete native catalog",
	)
	lifecycle_game.legacy_crt_recurring_round_index = 1
	_expect(
		lifecycle_game.original_recurring_evidence_round_index() == 1
		and lifecycle_game.original_recurring_actor_events(
			1,
			route_call_sites,
		).size() == 1,
		"active evidence lane exposes only the current actor and round",
	)
	var passive_motion := InputEventMouseMotion.new()
	passive_motion.relative = Vector2(4.0, -2.0)
	lifecycle_game.call("_input", passive_motion)
	_expect(
		lifecycle_game.legacy_crt_recurring_evidence_replay_active,
		"pointer motion remains untouched and does not alter the evidence lane",
	)
	var player_key := InputEventKey.new()
	player_key.keycode = KEY_M
	player_key.pressed = true
	lifecycle_game.call("_input", player_key)
	_expect(
		not lifecycle_game.legacy_crt_recurring_evidence_replay_active
		and lifecycle_game.original_recurring_evidence_round_index() == 0
		and lifecycle_game.original_recurring_actor_events(
			1,
			route_call_sites,
		).is_empty()
		and lifecycle_game
			.legacy_crt_recurring_evidence_invalidation_reason
			== "player_input",
		"the first player input permanently exits the evidence lane",
	)
	lifecycle_game.free()

	var route_game = MAIN_SCRIPT.new()
	route_game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	route_game.legacy_crt_recurring_round_index = 1
	route_game.legacy_crt_random_trace_enabled = true
	var predicted_route := _draw_values(
		route_game.legacy_crt_random_state,
		1,
	)
	var route_actor = SQUAD_UNIT_SCRIPT.new()
	route_actor.scene_index = 1416
	route_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 1},
	})
	route_actor.bind_original_crt_random_source(route_game, "m000")
	route_actor.original_ai_previous_world_position = route_actor.position
	route_actor.call(
		"_advance_original_ai_shared_counter",
		1.0 / 60.0,
	)
	var predicted_route_values: Array = predicted_route.get("values", [])
	_expect(
		route_game.legacy_crt_random_trace.size() == 1
		and int(route_game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x00058946
		and route_actor.original_recurring_shared_last_round_index == 1
		and route_actor.original_recurring_actor_event_serial == 1
		and route_actor.original_ai_idle_tick_limit
			== int(predicted_route_values[0]) % 160 + 40
		and not route_actor.original_route_update_active,
		"scheduled route event consumes the live stream once and applies its result",
	)
	route_actor.free()
	route_game.free()

	var pursuit_game = MAIN_SCRIPT.new()
	pursuit_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	pursuit_game.legacy_crt_recurring_round_index = 1
	pursuit_game.legacy_crt_random_trace_enabled = true
	var pursuit_target = SQUAD_UNIT_SCRIPT.new()
	pursuit_target.scene_index = 1614
	pursuit_target.configure_runtime_actor_type({
		"database_header_values": [0, 0, 56],
		"original_runtime_profile": {"runtime_index": 118},
	})
	pursuit_target.bind_original_crt_random_source(pursuit_game, "m000")
	pursuit_target.position = Vector2(300.0, 0.0)
	var pursuit_actor = SQUAD_UNIT_SCRIPT.new()
	pursuit_actor.scene_index = 1615
	pursuit_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 12],
		"original_runtime_profile": {"runtime_index": 119},
	})
	pursuit_actor.bind_original_crt_random_source(pursuit_game, "m000")
	pursuit_actor.bind_original_pursuit_target(pursuit_target)
	var pursuit_applied := bool(pursuit_actor.call(
		"_advance_original_recurring_pursuit_events"
	))
	_expect(
		pursuit_applied
		and pursuit_game.legacy_crt_random_trace.size() == 1
		and int(pursuit_game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005D47E
		and pursuit_actor.original_recurring_pursuit_last_round_index
			== 1
		and pursuit_actor.original_recurring_actor_event_serial == 1
		and pursuit_actor.original_pursuit_serial == 1,
		"scheduled pursuit event preserves actor order and conditional call site",
	)
	var pursuit_snapshot: Dictionary = (
		pursuit_actor.original_crt_random_timing_snapshot()
	)
	var recurring_snapshot := pursuit_snapshot.get(
		"recurring_actor_events",
		{},
	) as Dictionary
	_expect(
		int(recurring_snapshot.get("pursuit_last_round_index", 0)) == 1
		and int(recurring_snapshot.get("serial", 0)) == 1,
		"save snapshot records recurring actor-event phase",
	)
	var restored_pursuit_actor = SQUAD_UNIT_SCRIPT.new()
	restored_pursuit_actor.scene_index = 1615
	restored_pursuit_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 12],
		"original_runtime_profile": {"runtime_index": 119},
	})
	restored_pursuit_actor.bind_original_crt_random_source(
		pursuit_game,
		"m000",
	)
	restored_pursuit_actor.bind_original_pursuit_target(pursuit_target)
	_expect(
		restored_pursuit_actor.restore_original_crt_random_timing(
			pursuit_snapshot
		)
		and restored_pursuit_actor
			.original_recurring_pursuit_last_round_index == 1
		and restored_pursuit_actor.original_recurring_actor_event_serial
			== 1,
		"save restore resumes recurring actor events without duplicate draws",
	)
	restored_pursuit_actor.free()
	pursuit_actor.free()
	pursuit_target.free()
	pursuit_game.free()


func _test_recovered_shared_counter_cadence() -> void:
	var route_game = MAIN_SCRIPT.new()
	route_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	route_game.legacy_crt_random_trace_enabled = true
	var route_expected: Dictionary = _draw_values(
		route_game.legacy_crt_random_state,
		1,
	)
	var route_actor = SQUAD_UNIT_SCRIPT.new()
	route_actor.scene_index = 1415
	route_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 0},
	})
	route_actor.bind_original_crt_random_source(route_game, "m000")
	route_actor.position = Vector2(100.0, 100.0)
	route_actor.original_ai_previous_world_position = route_actor.position
	route_actor.original_ai_idle_tick_counter = 8
	route_actor.original_ai_idle_tick_limit = 10
	route_actor.original_route_update_active = true
	route_actor.call(
		"_advance_original_ai_shared_counter",
		1.0 / 60.0,
	)
	var route_values: Array = route_expected.get("values", [])
	_expect(
		route_actor.original_ai_idle_tick_counter == 0
		and route_actor.original_ai_idle_tick_limit
			== int(route_values[0]) % 160 + 40
		and not route_actor.original_route_update_active
		and route_actor.original_ai_route_reset_serial == 1
		and route_actor.original_ai_stationary_reset_serial == 0,
		"a stationary route actor advances the native shared counter twice",
	)
	_expect(
		route_game.legacy_crt_random_trace.size() == 1
		and int(route_game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x00058946,
		"the second shared-counter increment uses the native route call site",
	)
	route_actor.free()
	route_game.free()

	var stationary_game = MAIN_SCRIPT.new()
	stationary_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	stationary_game.legacy_crt_random_trace_enabled = true
	var stationary_actor = SQUAD_UNIT_SCRIPT.new()
	stationary_actor.scene_index = 1415
	stationary_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 0},
	})
	stationary_actor.bind_original_crt_random_source(
		stationary_game,
		"m000",
	)
	stationary_actor.position = Vector2(100.0, 100.0)
	stationary_actor.original_ai_previous_world_position = (
		stationary_actor.position
	)
	stationary_actor.original_ai_idle_tick_counter = 9
	stationary_actor.original_ai_idle_tick_limit = 10
	stationary_actor.original_route_update_active = false
	stationary_actor.call(
		"_advance_original_ai_shared_counter",
		1.0 / 60.0,
	)
	_expect(
		stationary_actor.original_ai_idle_tick_counter == 0
		and stationary_actor.original_ai_stationary_reset_serial == 1
		and stationary_game.legacy_crt_random_trace.size() == 1
		and int(stationary_game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x00056105,
		"a stationary non-route actor uses the native stationary call site",
	)
	stationary_actor.free()
	stationary_game.free()

	var moving_game = MAIN_SCRIPT.new()
	moving_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	)
	moving_game.legacy_crt_random_trace_enabled = true
	var moving_actor = SQUAD_UNIT_SCRIPT.new()
	moving_actor.scene_index = 1415
	moving_actor.configure_runtime_actor_type({
		"database_header_values": [0, 0, 5],
		"original_runtime_profile": {"runtime_index": 0},
	})
	moving_actor.bind_original_crt_random_source(moving_game, "m000")
	moving_actor.position = Vector2(100.0, 100.0)
	moving_actor.original_ai_previous_world_position = Vector2(
		98.0,
		100.0,
	)
	moving_actor.original_ai_idle_tick_counter = 8
	moving_actor.original_ai_idle_tick_limit = 10
	moving_actor.original_route_update_active = true
	moving_actor.call(
		"_advance_original_ai_shared_counter",
		1.0 / 60.0,
	)
	_expect(
		moving_actor.original_ai_idle_tick_counter == 9
		and moving_actor.original_route_update_active
		and moving_game.legacy_crt_random_trace.is_empty(),
		"a moving route actor advances the shared counter only once",
	)
	moving_actor.free()
	moving_game.free()


func _test_original_ambient_particle_stream() -> void:
	var game = MAIN_SCRIPT.new()
	game.call("_apply_original_crt_random_startup_checkpoint", "m002")
	var first_update_ok: bool = bool(game.call(
		"_replay_original_first_gameplay_random_update",
		"m002",
		false,
	))
	game.legacy_crt_random_trace_enabled = true
	game.legacy_crt_random_trace.clear()
	var field = LEGACY_AMBIENT_PARTICLE_FIELD.new()
	var configured: bool = field.configure(game, "m002")
	var advanced: bool = bool(field.call("_advance_original_update"))
	var counts: Dictionary = {}
	for draw: Dictionary in game.legacy_crt_random_trace:
		var call_site := int(draw.get("call_site_rva", 0))
		counts[call_site] = int(counts.get(call_site, 0)) + 1
	var secondary_respawns := int(counts.get(0x00060374, 0))
	_expect(
		first_update_ok
		and configured
		and advanced
		and int(counts.get(0x0005FF45, 0)) == 1
		and int(counts.get(0x0005FF65, 0)) == 0,
		"m002 starts one original ambient-field update after actor processing",
	)
	_expect(
		int(counts.get(0x0005FD2C, 0)) == 150
		and int(counts.get(0x0005FD41, 0)) == 150
		and int(counts.get(0x0005FD54, 0)) == 150
		and int(counts.get(0x0005FD6A, 0)) == 150
		and int(counts.get(0x0005FD7F, 0)) == 150
		and int(counts.get(0x0005FDA8, 0)) == 150
		and int(counts.get(0x0005FDDB, 0)) == 20
		and int(counts.get(0x0005FDEE, 0)) == 20
		and int(counts.get(0x0005FE02, 0)) == 20
		and int(counts.get(0x0005FE19, 0)) == 20,
		"first active weather frame resets the exact 150+20 native arrays",
	)
	_expect(
		int(counts.get(0x000600F0, 0)) == 2
		and int(counts.get(0x00060105, 0)) == 2
		and int(counts.get(0x000601D6, 0)) == 18
		and int(counts.get(0x000601E5, 0)) == 18
		and int(counts.get(0x00060202, 0)) == 18
		and int(counts.get(0x0006026D, 0)) == 18
		and int(counts.get(0x00060291, 0)) == 18
		and int(counts.get(0x000602A7, 0)) == 18
		and int(counts.get(0x000602BC, 0)) == 18
		and int(counts.get(0x000602D1, 0)) == 18
		and int(counts.get(0x000602FA, 0)) == 18
		and secondary_respawns in [0, 1, 2]
		and int(counts.get(0x00060396, 0)) == secondary_respawns
		and int(counts.get(0x000603AD, 0)) == secondary_respawns
		and int(counts.get(0x000603C4, 0)) == secondary_respawns,
		"80-degree field update preserves native visibility and respawn order",
	)
	var snapshot: Dictionary = field.runtime_snapshot()
	for particle_value: Variant in (
		snapshot.get("primary_particles", []) as Array
	):
		var particle := particle_value as Dictionary
		var position := particle.get("position", Vector2.ZERO) as Vector2
		particle["position"] = {"x": position.x, "y": position.y}
	for particle_value: Variant in (
		snapshot.get("secondary_particles", []) as Array
	):
		var particle := particle_value as Dictionary
		var position := particle.get("position", Vector2.ZERO) as Vector2
		particle["position"] = {"x": position.x, "y": position.y}
	var restored = LEGACY_AMBIENT_PARTICLE_FIELD.new()
	restored.configure(game, "m002")
	_expect(
		restored.restore_runtime_snapshot(snapshot)
		and restored.update_serial == field.update_serial
		and restored.weather_phase == 1
		and restored.runtime_snapshot() == field.runtime_snapshot(),
		"ambient weather state is deterministic and save/load complete",
	)
	var fast_game = MAIN_SCRIPT.new()
	fast_game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m002",
	)
	fast_game.call(
		"_replay_original_first_gameplay_random_update",
		"m002",
		false,
	)
	var fast_field = LEGACY_AMBIENT_PARTICLE_FIELD.new()
	fast_field.configure(fast_game, "m002")
	_expect(
		fast_field.call("_advance_original_update")
		and (
			fast_game.legacy_crt_random_state
			== game.legacy_crt_random_state
		)
		and (
			fast_game.legacy_crt_random_draw_index
			== game.legacy_crt_random_draw_index
		)
		and fast_field.runtime_snapshot() == field.runtime_snapshot(),
		"ordinary-play particle fast path is bit-identical to traced native order",
	)
	fast_field.free()
	fast_game.free()
	restored.free()
	field.free()
	game.free()


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
		actor.process_physics_priority == 1000,
		"runtime actor 0 receives the first recovered actor physics priority",
	)
	var state_before: int = game.legacy_crt_random_state
	var expected_state: int = LEGACY_CRT_RANDOM_CATALOG.next_state(
		state_before
	)
	var expected_value: int = LEGACY_CRT_RANDOM_CATALOG.random_value(
		expected_state
	)
	actor.call("_advance_original_crt_observation_gate", 0.02)
	_expect(
		game.legacy_crt_random_draw_index == 8490
		and actor.original_crt_observation_gate_serial == 1
		and actor.original_crt_observation_gate_passed
			== (expected_value % 2 > 0),
		"the actor consumes one exact global observation-gate draw at 60 Hz",
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
		actor.process_physics_priority == 2_000_000,
		"dynamic actors append after the recovered runtime-index priorities",
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
	source.original_crt_primary_candidate_scan_enabled = true
	source.original_crt_primary_candidate_scan_elapsed = 0.00625
	source.original_crt_primary_candidate_scan_passed = true
	source.original_crt_primary_candidate_scan_serial = 9
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
		restored.original_crt_primary_candidate_scan_enabled
		and is_equal_approx(
			restored.original_crt_primary_candidate_scan_elapsed,
			0.00625,
		)
		and restored.original_crt_primary_candidate_scan_passed
		and restored.original_crt_primary_candidate_scan_serial == 9,
		"save/load restores the 60 Hz primary candidate-scan phase",
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


func _test_recurring_secondary_search_runtime() -> void:
	var game = MAIN_SCRIPT.new()
	game.world_size = Vector2(1000.0, 500.0)
	game.legacy_crt_random_trace_enabled = true
	var source = SQUAD_UNIT_SCRIPT.new()
	source.position = Vector2(100.0, 100.0)
	source.scene_index = 700
	source.configure_runtime_actor_type({
		"database_header_values": [0, 0, 29],
		"original_runtime_profile": {"runtime_index": 20},
	})
	source.bind_original_crt_random_source(game, "m004", 0)
	var later_candidate = SQUAD_UNIT_SCRIPT.new()
	later_candidate.position = Vector2(110.0, 100.0)
	later_candidate.scene_index = 701
	later_candidate.faction_id = 1
	later_candidate.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 9},
	})
	var first_candidate = SQUAD_UNIT_SCRIPT.new()
	first_candidate.position = Vector2(120.0, 100.0)
	first_candidate.scene_index = 702
	first_candidate.faction_id = 1
	first_candidate.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 5},
	})
	game.units.append(source)
	game.units.append(later_candidate)
	game.units.append(first_candidate)
	_expect(
		game.first_original_secondary_search_candidate(
			source,
			128.0,
		) == first_candidate,
		"secondary candidate scan preserves native runtime-index insertion order",
	)
	var cache_rebuild_serial: int = (
		game.original_runtime_actor_order_cache_rebuild_serial
	)
	_expect(
		game.first_original_secondary_search_candidate(
			source,
			128.0,
		) == first_candidate
		and game.original_runtime_actor_order_cache_rebuild_serial
			== cache_rebuild_serial,
		"unchanged actor collections reuse the sorted runtime-order cache",
	)
	var dynamic_candidate = SQUAD_UNIT_SCRIPT.new()
	dynamic_candidate.position = Vector2(115.0, 100.0)
	dynamic_candidate.scene_index = 703
	dynamic_candidate.faction_id = 1
	dynamic_candidate.configure_runtime_actor_type({
		"database_header_values": [0, 0, 6],
		"original_runtime_profile": {"runtime_index": 3},
	})
	game.units.append(dynamic_candidate)
	_expect(
		game.first_original_secondary_search_candidate(
			source,
			128.0,
		) == dynamic_candidate
		and game.original_runtime_actor_order_cache.size() == 4
		and game.original_runtime_actor_order_cache_rebuild_serial
			== cache_rebuild_serial + 1,
		"dynamic actor insertion invalidates and rebuilds the order cache",
	)
	dynamic_candidate.faction_id = 2

	game.legacy_crt_random_state = 3
	game.legacy_crt_random_draw_index = 0
	game.legacy_crt_random_trace.clear()
	source.call("_advance_original_secondary_search_once")
	_expect(
		source.original_secondary_search_gate_serial == 1
		and source.original_secondary_search_last_gate_value % 2 == 0
		and source.original_secondary_search_trigger_serial == 0
		and not source.original_secondary_search_contact_state
		and game.legacy_crt_random_trace.size() == 1
		and int(game.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005CEA6,
		"even secondary gate consumes only the exact candidate-scan draw",
	)

	first_candidate.faction_id = 2
	later_candidate.faction_id = 2
	game.legacy_crt_random_state = 1
	game.legacy_crt_random_draw_index = 0
	game.legacy_crt_random_trace.clear()
	source.call("_advance_original_secondary_search_once")
	_expect(
		source.original_secondary_search_gate_serial == 2
		and source.original_secondary_search_last_gate_value % 2 == 1
		and source.original_secondary_search_trigger_serial == 0
		and game.legacy_crt_random_trace.size() == 1,
		"odd gate without a nearby faction-1 actor consumes no destination draws",
	)

	first_candidate.faction_id = 1
	game.legacy_crt_random_state = 1
	game.legacy_crt_random_draw_index = 0
	game.legacy_crt_random_trace.clear()
	source.call("_advance_original_secondary_search_once")
	var expected_sites := PackedInt32Array([
		0x0005CEA6,
		0x0005CF33,
		0x0005CF4A,
		0x0005CF61,
		0x0005CF78,
	])
	var actual_sites := PackedInt32Array()
	for record: Dictionary in game.legacy_crt_random_trace:
		actual_sites.append(int(record.get("call_site_rva", 0)))
	_expect(
		actual_sites == expected_sites
		and source.original_secondary_search_contact_state
		and source.original_secondary_search_trigger_serial == 1
		and source.original_secondary_search_last_candidate_runtime_index
			== 5
		and source.original_secondary_search_last_goal
			== Vector2(199.0, 6.0)
		and not source.original_secondary_search_last_navigation_applied,
		"odd gate applies the four exact sub_45CE90 destination draws",
	)

	var draws_after_trigger: int = game.legacy_crt_random_draw_index
	source.call("_advance_original_secondary_search_once")
	_expect(
		not source.original_secondary_search_contact_state
		and game.legacy_crt_random_draw_index == draws_after_trigger,
		"first idle tick after a secondary route clears contact without a gate",
	)
	source.movement_path = PackedVector2Array([
		source.position + Vector2(32.0, 0.0),
	])
	source.movement_path_index = 0
	source.original_secondary_search_contact_state = true
	source.call("_advance_original_secondary_search_once")
	_expect(
		source.original_secondary_search_contact_state
		and game.legacy_crt_random_draw_index == draws_after_trigger,
		"active secondary route suppresses all candidate random calls",
	)
	source.movement_path.clear()
	source.movement_path_index = 0
	source.call("_advance_original_secondary_search_once")
	_expect(
		not source.original_secondary_search_contact_state
		and game.legacy_crt_random_draw_index == draws_after_trigger,
		"route completion clears contact on its own native update",
	)
	source.call("_advance_original_secondary_search_once")
	_expect(
		game.legacy_crt_random_draw_index == draws_after_trigger + 1,
		"candidate gating resumes on the update after contact is cleared",
	)

	source.original_secondary_search_elapsed = 0.0125
	source.original_secondary_search_contact_state = true
	source.original_secondary_search_gate_serial = 11
	source.original_secondary_search_trigger_serial = 4
	source.original_secondary_search_last_gate_value = 10141
	source.original_secondary_search_last_candidate_runtime_index = 5
	source.original_secondary_search_last_goal = Vector2(321.0, 123.0)
	source.original_secondary_search_last_navigation_applied = true
	var snapshot: Dictionary = (
		source.original_crt_random_timing_snapshot()
	)
	var restored = SQUAD_UNIT_SCRIPT.new()
	restored.scene_index = 700
	restored.configure_runtime_actor_type({
		"database_header_values": [0, 0, 29],
		"original_runtime_profile": {"runtime_index": 20},
	})
	restored.bind_original_crt_random_source(game, "m004", 0)
	_expect(
		restored.restore_original_crt_random_timing(snapshot)
		and is_equal_approx(
			restored.original_secondary_search_elapsed,
			0.0125,
		)
		and restored.original_secondary_search_contact_state
		and restored.original_secondary_search_gate_serial == 11
		and restored.original_secondary_search_trigger_serial == 4
		and restored.original_secondary_search_last_gate_value == 10141
		and restored.original_secondary_search_last_candidate_runtime_index
			== 5
		and restored.original_secondary_search_last_goal
			== Vector2(321.0, 123.0)
		and restored.original_secondary_search_last_navigation_applied,
		"secondary-search phase and active contact survive save/load",
	)
	restored.free()
	source.free()
	later_candidate.free()
	first_candidate.free()
	dynamic_candidate.free()
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
