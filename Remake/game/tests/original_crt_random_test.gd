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

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_twelve_level_catalog()
	_test_exact_startup_checkpoint_and_next_draw()
	_test_exact_first_gameplay_update_replay()
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
