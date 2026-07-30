extends SceneTree

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const CAMPAIGN_PROGRESS: Script = preload("res://scripts/campaign_progress.gd")
const MAIN_RUNTIME: Script = preload("res://scripts/main.gd")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const GAME_SETTINGS: Script = preload("res://scripts/game_settings.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const SAVE_SLOT_SELECTOR: Script = preload("res://scripts/save_slot_selector.gd")
const FIELD_PICKUP: Script = preload("res://scripts/field_pickup.gd")
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const AMBIENT_UNIT: Script = preload("res://scripts/ambient_unit.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")


class MockMissionRuntime:
	extends Node

	var _durable_facts: Array[Dictionary] = []
	var _durable_fact_keys: Dictionary = {}
	var _applied_fact_objectives: Dictionary = {}
	var _reported_victory := false
	var _reported_failure_id := ""


class MockPersistentRuntime:
	extends Node

	var state: Dictionary = {}
	var restored_state: Dictionary = {}
	var restore_result := true

	func capture_state() -> Dictionary:
		return state.duplicate(true)

	func restore_state(new_state: Dictionary) -> bool:
		restored_state = new_state.duplicate(true)
		return restore_result


class MockOccupancy:
	extends RefCounted

	var actors: Dictionary = {}
	var finalize_count := 0

	func register_scene(
		scene_index: int,
		world_position: Vector2,
		_source_reference_world_position: Variant = null,
	) -> bool:
		actors[scene_index] = world_position
		return true

	func unregister_scene(scene_index: int, _keep_source_disabled: bool = true) -> void:
		actors.erase(scene_index)

	func release_goal(_scene_index: int) -> void:
		pass

	func finalize_registration() -> void:
		finalize_count += 1


class MockExplosiveProp:
	extends Node2D

	var scene_index := -1
	var hit_points := 1
	var has_exploded := false


class MockGame:
	extends Node2D

	var current_mission: Dictionary = {"id": "m003"}
	var current_mission_state: RefCounted
	var mission_runtime: Node
	var mission_direction_runtime: Node
	var mission_ai_coordinator: Node
	var level_camera: Camera2D
	var units: Array[Node2D] = []
	var selected_units: Array[Node2D] = []
	var enemies: Array[Node2D] = []
	var escorts: Array[Node2D] = []
	var ambient_units: Array[Node2D] = []
	var field_pickups: Array[Node2D] = []
	var explosive_props: Array[Node2D] = []
	var mission_pickups: Array[Node2D] = []
	var deployed_mines: Array[Node2D] = []
	var buried_enemy_scene_indices: Dictionary = {}
	var projectile_world: Node2D
	var activated_mission_scenes: Dictionary = {}
	var m010_split_ordered_names: Dictionary = {}
	var victory_presentation_completed := true
	var field_inventory: Dictionary = {}
	var dynamic_occupancy: RefCounted
	var world_entities_by_scene: Dictionary = {}


var check_count := 0
var test_root := ""


func _init() -> void:
	test_root = "user://save-settings-test-%d" % OS.get_process_id()
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_cleanup_test_root()
	_test_settings_defaults_and_round_trip(failures)
	_test_settings_migration_and_validation(failures)
	_test_original_controls_and_remapping(failures)
	_test_audio_bus_configuration(failures)
	_test_save_round_trip_and_recovery(failures)
	_test_save_migration_and_slot_safety(failures)
	_test_campaign_progression_and_disk_resume(failures)
	_test_legacy_world_snapshot_presence(failures)
	_test_mid_mission_capture_and_apply(failures)
	_test_buried_enemy_save_round_trip(failures)
	_test_placeholder_actor_identity_restore(failures)
	_cleanup_test_root()
	if failures.is_empty():
		print("Save and settings tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_settings_defaults_and_round_trip(failures: Array[String]) -> void:
	_expect(
		SAVE_SLOT_SELECTOR._format_timestamp(86400, 480) == "1970-01-02 08:00",
		"save-slot timestamps are converted from UTC to the supplied local-zone bias",
		failures,
	)
	var path := test_root + "/settings.json"
	var settings = GAME_SETTINGS.new()
	var missing: Dictionary = settings.load_from_disk(path)
	_expect(not bool(missing["ok"]), "missing settings report degradation", failures)
	_expect(bool(missing["used_default"]), "missing settings use safe defaults", failures)
	_expect(settings.display_settings()["mode"] == "fullscreen", "default display is fullscreen", failures)
	_expect(settings.display_settings()["resolution_policy"] == "desktop", "fullscreen follows desktop resolution", failures)
	_expect(settings.hint_enabled("controls"), "control hints default on", failures)
	_expect(settings.difficulty_mode() == "original", "MOD parity is the default difficulty", failures)
	_expect(
		settings.mission_rule_mode() == "stable_mod",
		"stable MOD mission control flow is the default",
		failures,
	)

	settings.set_audio_volume("master", 0.35)
	settings.set_audio_volume("sfx", 0.55)
	settings.set_display_mode("windowed")
	settings.set_resolution_policy("custom")
	settings.set_window_size(Vector2i(1600, 900))
	settings.set_hint_enabled("interactions", false)
	settings.set_interface_enabled("subtitles", false)
	settings.set_interface_enabled("edge_scroll", false)
	settings.set_difficulty_mode("hard")
	settings.set_mission_rule_mode("repaired")
	_expect(bool(settings.save_to_disk(path)["ok"]), "first settings write succeeds", failures)
	settings.set_audio_volume("master", 0.75)
	settings.set_display_mode("borderless")
	_expect(bool(settings.save_to_disk(path)["ok"]), "second settings write rotates backup", failures)

	var loaded = GAME_SETTINGS.new()
	var load_result: Dictionary = loaded.load_from_disk(path)
	_expect(bool(load_result["ok"]) and load_result["source"] == "primary", "settings load primary", failures)
	_expect(is_equal_approx(loaded.audio_volume("master"), 0.75), "latest volume persists", failures)
	_expect(loaded.display_settings()["mode"] == "borderless", "latest display mode persists", failures)
	_expect(not loaded.hint_enabled("interactions"), "hint choice persists", failures)
	_expect(not loaded.interface_enabled("subtitles"), "subtitle choice persists", failures)
	_expect(not loaded.interface_enabled("edge_scroll"), "edge-scroll choice persists", failures)
	_expect(loaded.difficulty_mode() == "hard", "difficulty choice persists", failures)
	_expect(
		loaded.mission_rule_mode() == "repaired",
		"mission rule profile persists independently from difficulty",
		failures,
	)

	_write_text(path, "{broken json")
	var recovered = GAME_SETTINGS.new()
	var recovery: Dictionary = recovered.load_from_disk(path)
	_expect(bool(recovery["ok"]) and bool(recovery["recovered"]), "corrupt settings recover backup", failures)
	_expect(recovery["source"] == "backup", "settings recovery identifies backup", failures)
	_expect(is_equal_approx(recovered.audio_volume("master"), 0.35), "backup retains prior generation", failures)
	_expect(recovered.display_settings()["mode"] == "windowed", "backup display generation is intact", failures)


func _test_settings_migration_and_validation(failures: Array[String]) -> void:
	var legacy_path := test_root + "/legacy-settings.json"
	_write_json(legacy_path, {"master_volume": 0.42, "fullscreen": false, "show_hints": false})
	var migrated = GAME_SETTINGS.new()
	var result: Dictionary = migrated.load_from_disk(legacy_path)
	_expect(bool(result["ok"]), "legacy settings shape is loadable", failures)
	_expect(int(migrated.values["schema_version"]) == 4, "legacy settings migrate to current schema", failures)
	_expect(is_equal_approx(migrated.audio_volume("master"), 0.42), "legacy volume migrates", failures)
	_expect(migrated.display_settings()["mode"] == "windowed", "legacy fullscreen flag migrates", failures)
	_expect(not migrated.hint_enabled("objectives"), "legacy hint flag migrates", failures)
	_expect(migrated.difficulty_mode() == "original", "legacy settings migrate to original parity", failures)
	_expect(
		migrated.mission_rule_mode() == "stable_mod",
		"legacy settings migrate to stable MOD mission rules",
		failures,
	)

	var malformed_path := test_root + "/normalized-settings.json"
	_write_json(
		malformed_path,
		{
			"schema_version": 1,
			"audio": {"master": 4.0, "sfx": -2.0},
			"display": {"mode": "television", "window_width": 40, "window_height": 99999},
			"hints": {"controls": "yes"},
			"interface": "invalid-but-recoverable",
		},
	)
	var normalized = GAME_SETTINGS.new()
	_expect(bool(normalized.load_from_disk(malformed_path)["ok"]), "malformed values remain recoverably loadable", failures)
	_expect(is_equal_approx(normalized.audio_volume("master"), 1.0), "volume is clamped", failures)
	_expect(is_equal_approx(normalized.audio_volume("sfx"), 0.0), "negative volume is clamped", failures)
	_expect(normalized.display_settings()["mode"] == "fullscreen", "unknown display mode falls back", failures)
	_expect(int(normalized.display_settings()["window_width"]) == 800, "window width is bounded", failures)
	_expect(int(normalized.display_settings()["window_height"]) == 4320, "window height is bounded", failures)
	_expect(normalized.hint_enabled("controls"), "wrong hint type falls back", failures)
	_expect(normalized.interface_enabled("subtitles"), "wrong interface section type falls back", failures)
	_expect(normalized.difficulty_mode() == "original", "missing gameplay settings use original parity", failures)
	_expect(
		normalized.mission_rule_mode() == "stable_mod",
		"missing mission rule settings fail closed to stable MOD",
		failures,
	)

	var schema_two_path := test_root + "/schema-two-settings.json"
	_write_json(
		schema_two_path,
		{
			"schema_version": 2,
			"audio": {},
			"display": {},
			"hints": {},
			"interface": {},
			"controls": {},
		},
	)
	var schema_two = GAME_SETTINGS.new()
	_expect(bool(schema_two.load_from_disk(schema_two_path)["ok"]), "schema-2 settings remain loadable", failures)
	_expect(schema_two.difficulty_mode() == "original", "schema-2 settings gain original difficulty", failures)
	_expect(
		schema_two.mission_rule_mode() == "stable_mod",
		"schema-2 settings gain stable MOD mission rules",
		failures,
	)
	_expect(not schema_two.set_difficulty_mode("impossible"), "unknown difficulty is rejected", failures)
	_expect(
		not schema_two.set_mission_rule_mode("impossible"),
		"unknown mission rule mode is rejected",
		failures,
	)

	var future_path := test_root + "/future-settings.json"
	_write_json(future_path, {"schema_version": 99, "audio": {}})
	var future = GAME_SETTINGS.new()
	var future_result: Dictionary = future.load_from_disk(future_path)
	_expect(not bool(future_result["ok"]), "unknown future settings version is rejected", failures)
	_expect(bool(future_result["used_default"]), "future settings safely degrade to defaults", failures)


func _test_original_controls_and_remapping(failures: Array[String]) -> void:
	var settings = GAME_SETTINGS.new()
	var controls: Dictionary = settings.controls_snapshot()
	var expected := {
		"pause": KEY_ESCAPE,
		"guide": KEY_F1,
		"select_1": KEY_F2,
		"select_2": KEY_F3,
		"select_3": KEY_F4,
		"select_4": KEY_F5,
		"select_5": KEY_F6,
		"briefing": KEY_F7,
		"toggle_run": KEY_R,
		"toggle_crawl": KEY_C,
		"weapon_inventory": KEY_W,
		"item_inventory": KEY_A,
		"sight_mode": KEY_S,
		"burial_mode": KEY_B,
		"minimap": KEY_M,
		"force_target_ctrl": KEY_CTRL,
		"force_target_up": KEY_UP,
		"weapon_1": KEY_1,
		"weapon_2": KEY_2,
		"weapon_3": KEY_3,
		"weapon_4": KEY_4,
		"weapon_5": KEY_5,
		"weapon_6": KEY_6,
		"weapon_7": KEY_7,
		"weapon_8": KEY_8,
		"weapon_9": KEY_9,
		"weapon_10": KEY_0,
	}
	for action: String in expected:
		_expect(
			int((controls[action] as Dictionary)["keycode"]) == int(expected[action]),
			"original control default: %s" % action,
			failures,
		)
	_expect(
		bool((controls["quick_save"] as Dictionary)["ctrl"]),
		"quick save modifier avoids original F5 character binding",
		failures,
	)
	_expect(
		GAME_INPUT_BINDINGS.action_is_held(
			"force_target_ctrl", controls, {KEY_CTRL: true}
		)
		and GAME_INPUT_BINDINGS.action_is_held(
			"force_target_up", controls, {str(KEY_UP): true}
		),
		"both original held force-target channels are represented by remappable bindings",
		failures,
	)
	var bare_ctrl := InputEventKey.new()
	bare_ctrl.keycode = KEY_CTRL
	bare_ctrl.ctrl_pressed = true
	var captured_ctrl: Dictionary = GAME_INPUT_BINDINGS.binding_from_event(bare_ctrl)
	_expect(
		not bool(captured_ctrl["ctrl"])
		and GAME_INPUT_BINDINGS.event_matches(
			bare_ctrl, controls["force_target_ctrl"] as Dictionary
		),
		"a modifier used as the primary key is normalized as a single key",
		failures,
	)

	var f5 := InputEventKey.new()
	f5.keycode = KEY_F5
	f5.pressed = true
	_expect(
		GAME_INPUT_BINDINGS.action_for_event(f5, controls) == "select_4",
		"plain F5 selects the fourth playable actor in the current mission roster",
		failures,
	)
	_expect(
		GAME_INPUT_BINDINGS.should_trigger_for_event("select_4", f5),
		"F2-F6 original held-state selection triggers on press",
		failures,
	)
	f5.ctrl_pressed = true
	_expect(
		GAME_INPUT_BINDINGS.action_for_event(f5, controls) == "quick_save",
		"Ctrl+F5 remains quick save",
		failures,
	)
	var map_key := InputEventKey.new()
	map_key.keycode = KEY_M
	map_key.pressed = true
	_expect(
		not GAME_INPUT_BINDINGS.should_trigger_for_event("minimap", map_key),
		"original modal/action keys do not fire on key press",
		failures,
	)
	map_key.pressed = false
	_expect(
		GAME_INPUT_BINDINGS.should_trigger_for_event("minimap", map_key),
		"original modal/action keys fire on release",
		failures,
	)
	var weapon_key := InputEventKey.new()
	weapon_key.keycode = KEY_1
	weapon_key.pressed = true
	_expect(
		GAME_INPUT_BINDINGS.should_trigger_for_event("weapon_1", weapon_key),
		"original numeric project selection fires on press",
		failures,
	)
	weapon_key.pressed = false
	_expect(
		not GAME_INPUT_BINDINGS.should_trigger_for_event("weapon_1", weapon_key),
		"original numeric project selection does not repeat on release",
		failures,
	)

	var old_map := (controls["minimap"] as Dictionary).duplicate(true)
	var old_item := (controls["item_inventory"] as Dictionary).duplicate(true)
	_expect(
		settings.set_control_binding("minimap", old_item),
		"a valid key remap succeeds",
		failures,
	)
	var remapped: Dictionary = settings.controls_snapshot()
	_expect(
		GAME_INPUT_BINDINGS.bindings_equal(remapped["minimap"], old_item),
		"requested action receives remapped key",
		failures,
	)
	_expect(
		GAME_INPUT_BINDINGS.bindings_equal(remapped["item_inventory"], old_map),
		"conflicting action is swapped instead of becoming unreachable",
		failures,
	)
	_expect(
		settings.set_control_binding(
			"force_target_up",
			{"keycode": KEY_Z, "ctrl": false, "alt": false, "shift": false, "meta": false},
		),
		"held force-target key can be remapped",
		failures,
	)
	remapped = settings.controls_snapshot()
	_expect(
		GAME_INPUT_BINDINGS.action_is_held(
			"force_target_up", remapped, {KEY_Z: true}
		)
		and not GAME_INPUT_BINDINGS.action_is_held(
			"force_target_up", remapped, {KEY_UP: true}
		),
		"held-state polling follows the remapped key instead of hard-coded Up",
		failures,
	)
	_expect(
		not settings.set_control_binding("missing_action", {"keycode": KEY_Z}),
		"unknown action cannot be remapped",
		failures,
	)
	_expect(
		not settings.set_control_binding("minimap", {"keycode": 0}),
		"invalid key cannot be assigned",
		failures,
	)
	settings.reset_controls()
	_expect(
		int((settings.controls_snapshot()["minimap"] as Dictionary)["keycode"]) == KEY_M,
		"control reset restores original mapping",
		failures,
	)


func _test_audio_bus_configuration(failures: Array[String]) -> void:
	var settings = GAME_SETTINGS.new()
	settings.set_audio_volume("master", 0.75)
	settings.set_audio_volume("music", 0.25)
	settings.set_audio_volume("sfx", 0.50)
	settings.set_audio_volume("voice", 1.0)
	settings.apply_audio_to_runtime()
	for bus_name: String in ["Music", "Sfx", "Voice"]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		_expect(bus_index >= 0, "%s audio bus exists" % bus_name, failures)
		if bus_index >= 0:
			_expect(
				AudioServer.get_bus_send(bus_index) == "Master",
				"%s audio bus routes through Master" % bus_name,
				failures,
			)
	_expect(
		is_equal_approx(
			db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))),
			0.25,
		),
		"music channel volume applies independently",
		failures,
	)
	_expect(
		is_equal_approx(
			db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Sfx"))),
			0.50,
		),
		"sound-effect channel volume applies independently",
		failures,
	)


func _test_save_round_trip_and_recovery(failures: Array[String]) -> void:
	var store = GAME_SAVE_STORE.new(test_root + "/saves")
	var session: Dictionary = _sample_session()
	var campaign := {
		"highest_unlocked_level_id": "m004",
		"completed_level_ids": ["m000", "m001", "m001"],
	}
	var first: Dictionary = store.save_slot("slot_1", session, campaign)
	_expect(bool(first["ok"]), "first mid-mission save succeeds", failures)
	_expect(int((first["data"] as Dictionary)["revision"]) == 1, "first save revision is one", failures)
	_expect(
		int((first["data"] as Dictionary)["saved_at_unix_msec"])
		>= int((first["data"] as Dictionary)["saved_at_unix"]) * 1000,
		"new saves retain millisecond ordering precision",
		failures,
	)
	session["elapsed_seconds"] = 48.5
	(session["squad"] as Array)[0]["current_hit_points"] = 5
	var second: Dictionary = store.save_slot("slot_1", session, campaign)
	_expect(bool(second["ok"]), "second mid-mission save succeeds", failures)
	_expect(int((second["data"] as Dictionary)["revision"]) == 2, "save revision increments", failures)
	var loaded: Dictionary = store.load_slot("slot_1")
	var loaded_session := (loaded["data"] as Dictionary)["session"] as Dictionary
	var loaded_presence := (
		(loaded_session["world"] as Dictionary)["snapshot_presence"] as Dictionary
	)
	_expect(bool(loaded["ok"]) and loaded["source"] == "primary", "save loads from primary", failures)
	_expect(is_equal_approx(float(loaded_session["elapsed_seconds"]), 48.5), "elapsed mission time persists", failures)
	_expect(
		str(loaded_session["mission_rule_mode"]) == "stable_mod",
		"save sessions persist their mission-rule identity",
		failures,
	)
	_expect(int((loaded_session["squad"] as Array)[0]["current_hit_points"]) == 5, "actor health persists", failures)
	_expect(
		bool(loaded_presence["field_pickups"])
		and bool(loaded_presence["explosive_props"]),
		"current world snapshots preserve explicit empty-array semantics",
		failures,
	)
	_expect(
		((loaded["data"] as Dictionary)["campaign"] as Dictionary)["completed_level_ids"] == ["m000", "m001"],
		"campaign completion list is normalized",
		failures,
	)

	_write_text(store.slot_path("slot_1"), "not json")
	var recovered: Dictionary = store.load_slot("slot_1")
	_expect(bool(recovered["ok"]) and bool(recovered["recovered"]), "corrupt save recovers previous generation", failures)
	_expect(int((recovered["data"] as Dictionary)["revision"]) == 1, "backup revision is preserved", failures)
	_expect(store.has_slot("slot_1"), "slot remains available through backup", failures)
	var listing: Array[Dictionary] = store.list_slots()
	_expect(listing.size() == 1 and bool(listing[0]["recovered"]), "slot listing reports recovery", failures)
	var listed_seconds_msec := int(listing[0]["saved_at_unix"]) * 1000
	var listed_precise_msec := int(listing[0]["saved_at_unix_msec"])
	_expect(
		listed_precise_msec >= listed_seconds_msec
		and listed_precise_msec < listed_seconds_msec + 1000,
		"backup-only slot summary exposes its millisecond timestamp",
		failures,
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.slot_path("slot_1")))
	var backup_only_listing: Array[Dictionary] = store.list_slots()
	_expect(
		backup_only_listing.size() == 1
		and str(backup_only_listing[0]["slot_id"]) == "slot_1"
		and bool(backup_only_listing[0]["recovered"]),
		"slot discovery finds an interrupted-save generation that only has .bak",
		failures,
	)


func _test_save_migration_and_slot_safety(failures: Array[String]) -> void:
	var store = GAME_SAVE_STORE.new(test_root + "/migration-saves")
	var policy: Dictionary = GAME_SAVE_STORE.migration_policy()
	_expect(
		int(policy["minimum_supported_schema_version"]) == 0
		and int(policy["current_schema_version"]) == 1
		and str(policy["future_version_policy"])
		== "reject_and_preserve_all_generations",
		"save migration policy exposes its supported window and fail-closed future policy",
		failures,
	)
	_expect(not GAME_SAVE_STORE.is_valid_slot_id("../escape"), "slot path traversal is rejected", failures)
	_expect(not bool(store.save_slot("../escape", _sample_session())["ok"]), "unsafe slot cannot be written", failures)
	_expect(GAME_SAVE_STORE.is_valid_slot_id("quick-save_1"), "safe slot ID is accepted", failures)
	_expect(
		GAME_SAVE_STORE.slot_summary_is_newer(
			{
				"slot_id": "slot_2",
				"saved_at_unix": 20,
				"saved_at_unix_msec": 20999,
				"revision": 1,
			},
			{
				"slot_id": "slot_1",
				"saved_at_unix": 20,
				"saved_at_unix_msec": 20001,
				"revision": 99,
			},
		),
		"latest-slot ordering uses millisecond precision before revision",
		failures,
	)
	_expect(
		GAME_SAVE_STORE.slot_summary_is_newer(
			{"slot_id": "slot_2", "saved_at_unix_msec": 20000, "revision": 3},
			{"slot_id": "slot_1", "saved_at_unix_msec": 20000, "revision": 2},
		),
		"latest-slot ordering uses revision when timestamps tie",
		failures,
	)
	_expect(
		GAME_SAVE_STORE.slot_summary_is_newer(
			{"slot_id": "slot_1", "saved_at_unix_msec": 20000, "revision": 2},
			{"slot_id": "slot_2", "saved_at_unix_msec": 20000, "revision": 2},
		),
		"latest-slot ordering has a stable slot-ID tie-breaker",
		failures,
	)
	_expect(
		GAME_SAVE_STORE.slot_summary_is_newer(
			{"slot_id": "legacy_new", "saved_at_unix": 21, "revision": 1},
			{"slot_id": "legacy_old", "saved_at_unix": 20, "revision": 99},
		),
		"latest-slot ordering retains a seconds fallback for legacy summaries",
		failures,
	)
	var legacy_path: String = str(store.slot_path("legacy"))
	_write_json(legacy_path, {"level_id": "m002", "elapsed_seconds": 13.0})
	var legacy: Dictionary = store.load_slot("legacy")
	_expect(bool(legacy["ok"]), "v0 level save migrates", failures)
	_expect(bool(legacy["migrated"]), "v0 load is explicitly reported as migrated", failures)
	_expect(int((legacy["data"] as Dictionary)["schema_version"]) == 1, "v0 save receives current schema", failures)
	_expect(
		str(((legacy["data"] as Dictionary)["session"] as Dictionary)["level_id"]) == "m002",
		"v0 level ID survives migration",
		failures,
	)
	var legacy_presence := (
		(
			((legacy["data"] as Dictionary)["session"] as Dictionary)["world"]
			as Dictionary
		)["snapshot_presence"] as Dictionary
	)
	_expect(
		not bool(legacy_presence["field_pickups"])
		and not bool(legacy_presence["explosive_props"]),
		"v0 saves mark unavailable world collections as absent instead of empty",
		failures,
	)

	var old_current_session := _sample_session()
	var old_current_world := old_current_session["world"] as Dictionary
	old_current_world.erase("snapshot_presence")
	old_current_world.erase("remaining_field_pickup_scene_indices")
	old_current_world.erase("explosive_props")
	var old_current_path: String = str(store.slot_path("old_current"))
	_write_json(
		old_current_path,
		{
			"schema_version": 1,
			"game_id": "1937-remake",
			"slot_id": "old_current",
			"revision": 1,
			"saved_at_unix": 1,
			"campaign": GAME_SAVE_STORE.default_campaign(),
			"session": old_current_session,
		},
	)
	var old_current: Dictionary = store.load_slot("old_current")
	var old_current_presence := (
		(
			(
				((old_current["data"] as Dictionary)["session"] as Dictionary)["world"]
				as Dictionary
			)["snapshot_presence"]
		) as Dictionary
	)
	_expect(bool(old_current["ok"]), "older schema-1 world snapshot remains loadable", failures)
	_expect(
		int((old_current["data"] as Dictionary)["saved_at_unix_msec"]) == 1000,
		"older schema-1 timestamps migrate from seconds to milliseconds",
		failures,
	)
	_expect(
		not bool(old_current_presence["field_pickups"])
		and not bool(old_current_presence["explosive_props"]),
		"schema-1 saves distinguish missing world collections from explicit empty arrays",
		failures,
	)
	var future_path: String = str(store.slot_path("future"))
	var future_text := "{\"schema_version\":77,\"game_id\":\"1937-remake\",\"opaque\":\"keep-me\"}"
	_write_text(future_path, future_text)
	var future_load: Dictionary = store.load_slot("future")
	_expect(
		not bool(future_load["ok"])
		and str(future_load["code"]) == "unsupported_future_version"
		and bool(future_load["preserved"]),
		"future save version is rejected with an explicit preservation result",
		failures,
	)
	_expect(
		_read_text(future_path) == future_text,
		"loading a future save leaves its bytes unchanged",
		failures,
	)
	var future_save: Dictionary = store.save_slot("future", _sample_session())
	_expect(
		not bool(future_save["ok"])
		and str(future_save["code"]) == "unsupported_future_version",
		"an older build cannot overwrite a future primary generation",
		failures,
	)
	_expect(
		_read_text(future_path) == future_text
		and not FileAccess.file_exists(future_path + ".corrupt")
		and not FileAccess.file_exists(future_path + ".tmp"),
		"future primary is neither quarantined nor partially replaced",
		failures,
	)
	var future_backup_path := str(store.slot_path("future_backup")) + ".bak"
	_write_text(future_backup_path, future_text)
	var future_backup_load: Dictionary = store.load_slot("future_backup")
	_expect(
		not bool(future_backup_load["ok"])
		and str(future_backup_load["generation"]) == "backup",
		"a future backup generation is also fail-closed when primary is absent",
		failures,
	)
	_expect(
		not bool(store.save_slot("future_backup", _sample_session())["ok"])
		and _read_text(future_backup_path) == future_text,
		"saving cannot erase an unsupported future backup",
		failures,
	)
	var unsupported_legacy_path := str(store.slot_path("unsupported_legacy"))
	var unsupported_legacy_text := "{\"schema_version\":-1,\"opaque\":\"keep-old\"}"
	_write_text(unsupported_legacy_path, unsupported_legacy_text)
	var unsupported_legacy: Dictionary = store.load_slot("unsupported_legacy")
	_expect(
		not bool(unsupported_legacy["ok"])
		and str(unsupported_legacy["code"]) == "unsupported_legacy_version"
		and _read_text(unsupported_legacy_path) == unsupported_legacy_text,
		"schema versions older than the supported window are rejected without mutation",
		failures,
	)


func _test_campaign_progression_and_disk_resume(failures: Array[String]) -> void:
	var progress: Dictionary = CAMPAIGN_PROGRESS.default_state()
	_expect(
		CAMPAIGN_PROGRESS.is_unlocked(progress, "m000")
		and not CAMPAIGN_PROGRESS.is_unlocked(progress, "m001"),
		"a fresh sequential campaign starts at mission one",
		failures,
	)
	var store = GAME_SAVE_STORE.new(test_root + "/campaign-saves")
	var product_runtime: Node2D = MAIN_RUNTIME.new()
	product_runtime.campaign_progress = CAMPAIGN_PROGRESS.default_state()
	for level_index: int in range(CAMPAIGN_PROGRESS.FORMAL_LEVEL_IDS.size()):
		var level_id: String = CAMPAIGN_PROGRESS.FORMAL_LEVEL_IDS[level_index]
		progress = CAMPAIGN_PROGRESS.record_victory(progress, level_id)
		product_runtime.current_mission = {"id": level_id}
		product_runtime._update_campaign_progress_for_victory()
		var expected_highest_index := mini(
			level_index + 1,
			CAMPAIGN_PROGRESS.FORMAL_LEVEL_IDS.size() - 1,
		)
		_expect(
			str(progress["highest_unlocked_level_id"])
			== CAMPAIGN_PROGRESS.FORMAL_LEVEL_IDS[expected_highest_index],
			"victory advances the sequential unlock frontier for %s" % level_id,
			failures,
		)
		_expect(
			product_runtime.campaign_progress == progress,
			"the product victory entry uses the canonical campaign transition for %s"
				% level_id,
			failures,
		)
		_expect(
			CAMPAIGN_PROGRESS.completion_count(progress) == level_index + 1,
			"victory records one unique completion for %s" % level_id,
			failures,
		)
		var session: Dictionary = GAME_SAVE_STORE.empty_session(level_id)
		var write_result: Dictionary = store.save_slot("campaign", session, progress)
		var disk_result: Dictionary = store.load_slot("campaign")
		_expect(
			bool(write_result["ok"])
			and bool(disk_result["ok"])
			and (
				(disk_result["data"] as Dictionary)["campaign"] as Dictionary
			) == progress,
			"campaign frontier survives a physical disk round trip after %s" % level_id,
			failures,
		)
	var final_state: Dictionary = progress.duplicate(true)
	progress = CAMPAIGN_PROGRESS.record_victory(progress, "m011")
	_expect(
		progress == final_state,
		"replaying the final mission neither duplicates completion nor wraps the frontier",
		failures,
	)
	var out_of_order: Dictionary = CAMPAIGN_PROGRESS.record_victory(
		CAMPAIGN_PROGRESS.default_state(),
		"m010",
	)
	_expect(
		str(out_of_order["highest_unlocked_level_id"]) == "m011"
		and (out_of_order["completed_level_ids"] as Array) == ["m010"],
		"free/developer selection can record a real out-of-order victory without fake earlier completions",
		failures,
	)
	var non_regressing: Dictionary = CAMPAIGN_PROGRESS.record_victory(
		{
			"highest_unlocked_level_id": "m010",
			"completed_level_ids": ["m009"],
		},
		"m002",
	)
	_expect(
		str(non_regressing["highest_unlocked_level_id"]) == "m010"
		and (non_regressing["completed_level_ids"] as Array) == ["m002", "m009"],
		"replaying an earlier mission never regresses a higher unlock frontier",
		failures,
	)
	var repaired_inconsistent: Dictionary = CAMPAIGN_PROGRESS.normalize(
		{
			"highest_unlocked_level_id": "m000",
			"completed_level_ids": ["m003", "m003"],
		}
	)
	_expect(
		str(repaired_inconsistent["highest_unlocked_level_id"]) == "m004"
		and (repaired_inconsistent["completed_level_ids"] as Array) == ["m003"],
		"normalization deduplicates completion and repairs an impossible unlock frontier",
		failures,
	)
	_expect(
		CAMPAIGN_PROGRESS.record_victory(progress, "m999") == progress,
		"unknown or withdrawn mission IDs cannot mutate campaign state",
		failures,
	)
	product_runtime.free()


func _test_legacy_world_snapshot_presence(failures: Array[String]) -> void:
	var legacy_game := _make_mock_game(false)
	root.add_child(legacy_game)
	var legacy_prop := MockExplosiveProp.new()
	legacy_prop.scene_index = 3100
	legacy_prop.hit_points = 7
	legacy_game.explosive_props.append(legacy_prop)
	legacy_game.add_child(legacy_prop)
	var legacy_session: Dictionary = GAME_SAVE_STORE.empty_session("m003")
	var legacy_world := legacy_session["world"] as Dictionary
	legacy_world["snapshot_presence"] = {
		"field_pickups": false,
		"explosive_props": false,
	}
	var legacy_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		legacy_game, legacy_session
	)
	_expect(
		bool(legacy_result["ok"])
		and legacy_game.field_pickups.size() == 1
		and legacy_game.field_pickups[0].scene_index == 2099,
		"legacy saves without a pickup snapshot preserve the freshly loaded level pickups",
		failures,
	)
	_expect(
		legacy_game.explosive_props.size() == 1
		and legacy_game.explosive_props[0] == legacy_prop
		and legacy_prop.hit_points == 7,
		"legacy saves without a prop snapshot preserve fresh props and their hit points",
		failures,
	)

	var explicit_game := _make_mock_game(false)
	root.add_child(explicit_game)
	var explicit_prop := MockExplosiveProp.new()
	explicit_prop.scene_index = 3100
	explicit_prop.hit_points = 7
	explicit_game.explosive_props.append(explicit_prop)
	explicit_game.add_child(explicit_prop)
	var explicit_session: Dictionary = GAME_SAVE_STORE.empty_session("m003")
	var explicit_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		explicit_game, explicit_session
	)
	_expect(
		bool(explicit_result["ok"])
		and explicit_game.field_pickups.is_empty()
		and explicit_game.explosive_props.is_empty(),
		"an explicit empty world snapshot still removes consumed pickups and destroyed props",
		failures,
	)
	legacy_game.queue_free()
	explicit_game.queue_free()


func _test_mid_mission_capture_and_apply(failures: Array[String]) -> void:
	var source_game := _make_mock_game(true)
	root.add_child(source_game)
	source_game.m010_split_ordered_names = {"老赵": true, "强子": true}
	source_game.victory_presentation_completed = false
	var session: Dictionary = GAME_SESSION_STATE.capture(source_game)
	_expect(str(session["level_id"]) == "m003", "capture records current formal level", failures)
	_expect(is_equal_approx(float(session["elapsed_seconds"]), 17.25), "capture records mission clock", failures)
	var captured_seen := ((session["mission"] as Dictionary)["seen_values"] as Dictionary)["secure"] as Array
	_expect(captured_seen == [2637], "numeric seen values are encoded as an array", failures)
	var inventory := ((session["squad"] as Array)[0]["inventory"] as Dictionary)["items"] as Dictionary
	_expect(inventory.has("36") and inventory.has("43"), "numeric inventory keys are JSON strings", failures)
	_expect((session["world"] as Dictionary)["activated_scene_indices"] == [2637], "activated scenes persist", failures)
	_expect(
		(session["world"] as Dictionary)["snapshot_presence"]
		== {"field_pickups": true, "explosive_props": true},
		"current captures explicitly mark destructive world collections as present",
		failures,
	)
	_expect(
		(session["world"] as Dictionary)["m010_split_ordered_names"]
		== {"老赵": true, "强子": true},
		"partial m010 split-order tutorial progress is captured",
		failures,
	)
	_expect(
		(session["ambient"] as Array).size() == 1
		and int((session["ambient"] as Array)[0]["scene_index"]) == 300
		and int(
			((session["ambient"] as Array)[0]["ambient"] as Dictionary)[
				"patrol_index"
			]
		) == 1,
		"live ambient actors and their patrol phase are captured",
		failures,
	)
	var captured_enemy_idle := (
		(session["enemies"] as Array)[0].get(
			"original_ai_idle_animation",
			{},
		) as Dictionary
	)
	_expect(
		(
			int(captured_enemy_idle.get("tick_limit", 0)) == 90
			and int(captured_enemy_idle.get("tick_counter", 0)) == 45
			and bool(captured_enemy_idle.get("action_active", false))
			and int(captured_enemy_idle.get("frame_index", 0)) == 3
			and int(captured_enemy_idle.get("random_state", 0)) == 123456
		),
		"AI stand_action counter, frame phase, and deterministic random state are captured",
		failures,
	)
	var captured_stable_patrol := (
		(
			((session["enemies"] as Array)[0]["ai"] as Dictionary).get(
				"stable_mod_patrol",
				{},
			)
		) as Dictionary
	)
	_expect(
		(
			is_equal_approx(
				float(captured_stable_patrol.get("elapsed", 0.0)),
				6.4,
			)
			and int(captured_stable_patrol.get("target_index", -1)) == 3
			and bool(captured_stable_patrol.get("segment_issued", false))
		),
		"stable-MOD patrol timeline phase is captured independently of its transient path",
		failures,
	)
	_expect(
		not bool((session["world"] as Dictionary)["victory_presentation_completed"]),
		"an interrupted victory presentation remains distinguishable in the snapshot",
		failures,
	)
	_expect(
		int(((session["world"] as Dictionary)["mission_direction"] as Dictionary).get("beat_serial", 0)) == 7,
		"mission direction runtime state is captured with the world",
		failures,
	)
	_expect(
		int(((session["world"] as Dictionary)["mission_ai_coordinator"] as Dictionary).get("reinforcement_budget_remaining", -1)) == 2,
		"mission AI durable state is captured with the world",
		failures,
	)
	var store = GAME_SAVE_STORE.new(test_root + "/capture-saves")
	_expect(bool(store.save_slot("midgame", session)["ok"]), "captured runtime satisfies save schema", failures)
	var disk_session := ((store.load_slot("midgame")["data"] as Dictionary)["session"] as Dictionary)

	var target_game := _make_mock_game(false)
	root.add_child(target_game)
	var apply_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(target_game, disk_session)
	_expect(
		bool(apply_result["ok"])
		and bool(apply_result["mission_direction_restored"]),
		"mid-mission snapshot applies and reports a restored director state",
		failures,
	)
	var target_unit := target_game.units[0]
	_expect(target_unit.position.is_equal_approx(Vector2(321.0, 654.0)), "actor position restores", failures)
	_expect(int(target_unit.current_hit_points) == 6, "actor health restores", failures)
	_expect(
		is_equal_approx(float(target_unit.move_speed), 177.0),
		"actor movement speed survives mode reapplication during save restore",
		failures,
	)
	_expect(
		target_unit.selected and target_game.selected_units == [target_unit],
		"selected squad membership restores without stale spawn selection",
		failures,
	)
	_expect(
		target_game.enemies.size() == 1
		and target_game.enemies[0].current_target == target_unit
		and target_game.enemies[0].behavior_state == ENEMY_UNIT.BehaviorState.CHASE,
		"enemy pursuit target and behavior restore together",
		failures,
	)
	_expect(
		(
			is_equal_approx(float(target_game.enemies[0].patrol_wait_remaining), 1.25)
			and bool(target_game.enemies[0].patrol_path_in_flight)
		),
		"enemy patrol endpoint hold and active-leg state survive a mid-mission save",
		failures,
	)
	_expect(
		(
			int(target_game.enemies[0].original_ai_idle_tick_limit) == 90
			and int(target_game.enemies[0].original_ai_idle_tick_counter) == 45
			and bool(target_game.enemies[0].original_ai_idle_action_active)
			and int(target_game.enemies[0].original_ai_idle_frame_index) == 3
			and is_equal_approx(
				float(target_game.enemies[0].original_ai_idle_frame_elapsed),
				0.04,
			)
			and int(target_game.enemies[0].original_ai_idle_random_state) == 123456
		),
		"AI stand_action phase survives a mid-mission save",
		failures,
	)
	_expect(
		(
			is_equal_approx(
				float(target_game.enemies[0].stable_mod_patrol_elapsed),
				6.4,
			)
			and int(target_game.enemies[0].stable_mod_patrol_target_index) == 3
			and not bool(
				target_game.enemies[0].stable_mod_patrol_segment_issued
			)
			and not bool(
				target_game.enemies[0].stable_mod_patrol_segment_prepared
			)
			and target_game.enemies[0].movement_path.is_empty()
		),
		"stable-MOD patrol restores its phase and reconstructs no stale in-flight path",
		failures,
	)
	_expect(
		target_game.ambient_units.size() == 1
		and target_game.ambient_units[0].position.is_equal_approx(
			Vector2(222.0, 333.0)
		)
		and int(target_game.ambient_units[0].faction_id) == 2
		and int(target_game.ambient_units[0].patrol_index) == 1
		and is_equal_approx(
			float(target_game.ambient_units[0].patrol_wait_remaining),
			0.75,
		)
		and bool(target_game.ambient_units[0].patrol_path_in_flight),
		"ambient position, faction, and patrol state survive a mid-mission save",
		failures,
	)
	_expect(target_unit.ammo_item_count(43) == 2, "integer-key deployable inventory restores", failures)
	_expect(target_unit.ammo_item_count(36) == 35, "integer-key ammunition inventory restores", failures)
	var restored_seen := target_game.current_mission_state.seen_values["secure"] as Dictionary
	_expect(restored_seen.has(2637) and not restored_seen.has("2637"), "seen value regains numeric key type", failures)
	_expect(target_game.mission_runtime._durable_facts.size() == 1, "durable mission facts restore", failures)
	_expect(target_game.activated_mission_scenes.has(2637), "activated mission scene restores", failures)
	_expect(int(target_game.field_inventory["explosives"]) == 3, "squad field inventory restores", failures)
	_expect(
		target_game.m010_split_ordered_names == {"老赵": true, "强子": true},
		"partial m010 split-order tutorial progress restores",
		failures,
	)
	_expect(
		not target_game.victory_presentation_completed,
		"an interrupted victory presentation restores for product-level replay",
		failures,
	)
	_expect(
		int((target_game.mission_direction_runtime as MockPersistentRuntime).restored_state.get("beat_serial", 0)) == 7,
		"mission direction state restores after level reconstruction",
		failures,
	)
	_expect(
		int((target_game.mission_ai_coordinator as MockPersistentRuntime).restored_state.get("reinforcement_budget_remaining", -1)) == 2,
		"mission AI state restores after level reconstruction",
		failures,
	)
	var rejected_target := _make_mock_game(false)
	root.add_child(rejected_target)
	(rejected_target.mission_direction_runtime as MockPersistentRuntime).restore_result = false
	var rejected_apply: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		rejected_target, disk_session
	)
	_expect(
		not bool(rejected_apply["mission_direction_restored"])
		and (rejected_apply["warnings"] as Array).has(
			"mission direction state could not be restored"
		),
		"a rejected non-empty director snapshot is surfaced for Main fallback start",
		failures,
	)
	_expect(target_game.field_pickups.is_empty(), "consumed field pickup does not respawn", failures)
	_expect(
		(target_game.dynamic_occupancy as MockOccupancy).actors[100] == Vector2(321.0, 654.0),
		"restored actor footprint moves from spawn to loaded position",
		failures,
	)
	_expect(
		(target_game.dynamic_occupancy as MockOccupancy).finalize_count == 1,
		"restored occupancy is finalized once",
		failures,
	)
	_expect(target_game.mission_pickups.size() == 1, "uncollected officer drop is recreated", failures)
	var restored_drop := target_game.mission_pickups[0]
	_expect(restored_drop.position.is_equal_approx(Vector2(444.0, 555.0)), "officer drop position restores", failures)
	_expect(
		int((restored_drop.item_payload as Dictionary)["source_scene_index"]) == 2637,
		"officer drop keeps its source scene and cannot soft-lock the mission",
		failures,
	)
	source_game.queue_free()
	target_game.queue_free()
	rejected_target.queue_free()


func _test_buried_enemy_save_round_trip(failures: Array[String]) -> void:
	var source_game := _make_mock_game(true)
	root.add_child(source_game)
	var source_enemy := source_game.enemies[0]
	source_enemy.is_alive = false
	source_enemy.current_hit_points = 0
	source_enemy.death_emitted = true
	source_enemy.visible = false
	source_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	source_game.buried_enemy_scene_indices[int(source_enemy.scene_index)] = true
	var session: Dictionary = GAME_SESSION_STATE.capture(source_game)
	_expect(
		(session["world"] as Dictionary)["buried_enemy_scene_indices"] == [200],
		"buried enemy scene identity is serialized explicitly",
		failures,
	)

	var target_game := _make_mock_game(false)
	root.add_child(target_game)
	var target_enemy := target_game.enemies[0]
	_expect(target_enemy.is_alive and target_enemy.visible, "fresh level starts with the enemy present", failures)
	var result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(target_game, session)
	_expect(
		bool(result["ok"])
		and not target_enemy.is_alive
		and not target_enemy.visible
		and target_enemy.process_mode == Node.PROCESS_MODE_DISABLED
		and target_game.buried_enemy_scene_indices.has(200),
		"loading a save keeps a buried corpse hidden instead of resurrecting the enemy",
		failures,
	)
	source_game.queue_free()
	target_game.queue_free()


func _test_placeholder_actor_identity_restore(failures: Array[String]) -> void:
	var source_game := _make_mock_game(true)
	root.add_child(source_game)
	var source_alpha := source_game.units[0]
	source_alpha.scene_index = -1
	source_alpha.display_name = "placeholder_alpha"
	source_alpha.position = Vector2(111.0, 222.0)
	source_alpha.current_hit_points = 2
	var source_bravo := _add_placeholder_unit(
		source_game, "placeholder_bravo", Vector2(333.0, 444.0)
	)
	source_bravo.current_hit_points = 7
	var source_enemy := source_game.enemies[0]
	source_enemy.scene_index = -1
	source_enemy.display_name = "placeholder_enemy"
	source_enemy.current_target = source_bravo
	source_enemy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
	(source_game.dynamic_occupancy as MockOccupancy).actors.clear()
	var session: Dictionary = GAME_SESSION_STATE.capture(source_game)
	(session["world"] as Dictionary)["deployed_mines"] = [
		{
			"x": 12.0,
			"y": 34.0,
			"owner_scene_index": -1,
			"owner_display_name": "",
			"faction_id": 3,
			"state": 1,
		}
	]

	var target_game := _make_mock_game(false)
	root.add_child(target_game)
	var target_alpha := target_game.units[0]
	target_alpha.scene_index = -1
	target_alpha.display_name = "placeholder_alpha"
	var target_bravo := _add_placeholder_unit(
		target_game, "placeholder_bravo", Vector2(20.0, 30.0)
	)
	var target_enemy := target_game.enemies[0]
	target_enemy.scene_index = -1
	target_enemy.display_name = "placeholder_enemy"
	(target_game.dynamic_occupancy as MockOccupancy).actors.clear()
	var apply_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(target_game, session)
	_expect(bool(apply_result["ok"]), "placeholder snapshot applies", failures)
	_expect(
		target_alpha.position.is_equal_approx(Vector2(111.0, 222.0))
		and int(target_alpha.current_hit_points) == 2,
		"negative scene ID restores the first squad member by name",
		failures,
	)
	_expect(
		target_bravo.position.is_equal_approx(Vector2(333.0, 444.0))
		and int(target_bravo.current_hit_points) == 7,
		"negative scene ID restores the second squad member independently",
		failures,
	)
	_expect(target_alpha != target_bravo, "placeholder actors never collapse onto one instance", failures)
	_expect(
		target_enemy.current_target == target_bravo
		and target_enemy.behavior_state == ENEMY_UNIT.BehaviorState.CHASE,
		"placeholder enemy target restores through stable display identity",
		failures,
	)
	_expect(
		target_game.deployed_mines.size() == 1
		and target_game.deployed_mines[0].owner_actor == null,
		"an unresolved negative owner ID remains unbound instead of selecting the first actor",
		failures,
	)
	source_game.queue_free()
	target_game.queue_free()


func _sample_session() -> Dictionary:
	var session: Dictionary = GAME_SAVE_STORE.empty_session("m004")
	session["elapsed_seconds"] = 27.5
	(session["mission"] as Dictionary)["completed"] = {"infiltrate": true}
	(session["mission"] as Dictionary)["progress"] = {"secure": 1}
	(session["mission"] as Dictionary)["seen_values"] = {"secure": [2637]}
	(session["mission"] as Dictionary)["durable_facts"] = [
		{"key": "item|2637", "event_name": "item_acquired", "payload": {"scene_index": 2637}}
	]
	session["squad"] = [
		{
			"display_name": "老赵",
			"scene_index": 100,
			"x": 100.0,
			"y": 200.0,
			"current_hit_points": 8,
			"maximum_hit_points": 8,
			"is_alive": true,
			"inventory": {"schema_version": 1, "items": {"36": 24}, "weapons": {}, "active_action_key": ""},
		}
	]
	(session["world"] as Dictionary)["activated_scene_indices"] = [2637]
	(session["world"] as Dictionary)["remaining_field_pickup_scene_indices"] = [2100, 2101]
	(session["world"] as Dictionary)["field_inventory"] = {"explosives": 2}
	return session


func _make_mock_game(populated: bool) -> MockGame:
	var game := MockGame.new()
	var definition := {
		"id": "m003",
		"objectives": [
			{
				"id": "secure",
				"label": "secure",
				"required": true,
				"condition": {"event": "item_acquired", "required_count": 2, "unique_by": "scene_index"},
				"depends_on": [],
			}
		],
		"failure_conditions": [],
	}
	game.current_mission_state = MISSION_STATE.new(definition)
	game.mission_runtime = MockMissionRuntime.new()
	game.add_child(game.mission_runtime)
	game.mission_direction_runtime = MockPersistentRuntime.new()
	(game.mission_direction_runtime as MockPersistentRuntime).state = {
		"schema_version": 1,
		"beat_serial": 7 if populated else 0,
	}
	game.add_child(game.mission_direction_runtime)
	game.mission_ai_coordinator = MockPersistentRuntime.new()
	(game.mission_ai_coordinator as MockPersistentRuntime).state = {
		"schema_version": 1,
		"reinforcement_budget_remaining": 2 if populated else 0,
	}
	game.add_child(game.mission_ai_coordinator)
	game.dynamic_occupancy = MockOccupancy.new()
	var unit = SQUAD_UNIT.new()
	var empty_groups: Array[Dictionary] = []
	var ai_idle_groups: Array[Dictionary] = []
	for group_index: int in range(8):
		ai_idle_groups.append(
			{
				"group_index": group_index,
				"frames": [] as Array[Texture2D],
				"anchor": Vector2.ZERO,
				"frame_hold_ticks": 1,
			}
		)
	unit.configure(
		"老赵",
		Color.WHITE,
		Vector2(20.0, 30.0),
		null,
		empty_groups,
		empty_groups,
		100,
		game.dynamic_occupancy,
		Vector2(20.0, 30.0),
	)
	unit.configure_combat(3, 8, COMBAT_PROFILES.weapon_profile("pistol_attack"))
	game.units.append(unit)
	game.add_child(unit)
	var enemy = ENEMY_UNIT.new()
	enemy.configure_enemy(
		{
			"display_name": "追兵",
			"scene_index": 200,
			"x": 500,
			"y": 500,
			"reference_x": 500,
			"reference_y": 500,
			"direction_index": 1,
			"faction_id": 1,
			"current_hit_points": 8,
			"default_attack_type": 2,
			"patrol_waypoints": [],
			"patrol_enabled": false,
			"original_runtime_profile": {
				"observed": {
					"position": [500, 500],
					"facing_direction": 1,
				},
				"patrol_timeline": [
					{"elapsed_ms": 0, "position": [500, 500], "facing_direction": 1},
					{"elapsed_ms": 5000, "position": [564, 500], "facing_direction": 3},
					{"elapsed_ms": 6000, "position": [500, 500], "facing_direction": 7},
					{"elapsed_ms": 7000, "position": [500, 484], "facing_direction": 1},
					{"elapsed_ms": 12000, "position": [500, 500], "facing_direction": 5},
				],
			},
		},
		null,
		empty_groups,
		empty_groups,
		game.dynamic_occupancy,
	)
	enemy.configure_original_ai_idle_animation(ai_idle_groups)
	game.enemies.append(enemy)
	game.add_child(enemy)
	var ambient = AMBIENT_UNIT.new()
	ambient.configure_ambient(
		{
			"display_name": "d鸡",
			"scene_index": 300,
			"x": 240,
			"y": 936,
			"reference_x": 251,
			"reference_y": 933,
			"direction_index": 1,
			"faction_id": 2,
			"current_hit_points": 8,
			"database_header_values": [0, 1, 33, 2, 32],
			"patrol_waypoints": [{"x": 7, "y": 58}, {"x": 4, "y": 60}],
			"patrol_current_waypoint_index": 0,
			"patrol_enabled": true,
		},
		null,
		empty_groups,
		empty_groups,
		empty_groups,
		game.dynamic_occupancy,
	)
	ambient.configure_original_ai_idle_animation(ai_idle_groups)
	game.ambient_units.append(ambient)
	game.add_child(ambient)
	if populated:
		unit.position = Vector2(321.0, 654.0)
		unit.move_speed = 177.0
		unit.selected = true
		game.selected_units = [unit]
		enemy.current_target = unit
		enemy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
		enemy.patrol_wait_remaining = 1.25
		enemy.patrol_path_in_flight = true
		enemy.original_ai_idle_tick_limit = 90
		enemy.original_ai_idle_tick_counter = 45
		enemy.original_ai_idle_action_active = true
		enemy.original_ai_idle_frame_index = 3
		enemy.original_ai_idle_frame_elapsed = 0.04
		enemy.original_ai_idle_random_state = 123456
		enemy.stable_mod_patrol_elapsed = 6.4
		enemy.stable_mod_patrol_target_index = 3
		enemy.stable_mod_patrol_segment_issued = true
		enemy.stable_mod_patrol_segment_prepared = true
		enemy.issue_path(PackedVector2Array([Vector2(520, 500)]))
		ambient.position = Vector2(222.0, 333.0)
		ambient.patrol_index = 1
		ambient.patrol_wait_remaining = 0.75
		ambient.patrol_path_in_flight = true
		unit.current_hit_points = 6
		unit.add_ammo_item(36, 3)
		unit.add_ammo_item(43, 2)
		game.current_mission_state.elapsed_seconds = 17.25
		game.current_mission_state.progress["secure"] = 1
		game.current_mission_state.seen_values["secure"] = {2637: true}
		game.mission_runtime._durable_facts.append(
			{
				"key": "item_acquired|scene=2637",
				"event_name": "item_acquired",
				"payload": {"scene_index": 2637},
			}
		)
		game.mission_runtime._applied_fact_objectives = {"item_acquired|scene=2637|objective=secure": true}
		game.activated_mission_scenes = {2637: true}
		game.field_inventory = {"explosives": 3}
		var drop: Node2D = MISSION_PICKUP.new()
		drop.configure(
			{
				"item_role": "secret_document",
				"item_name": "绝密文件",
				"source_scene_index": 2637,
			},
			Vector2(444.0, 555.0),
		)
		game.mission_pickups.append(drop)
		game.add_child(drop)
	else:
		var field_pickup: Node2D = FIELD_PICKUP.new()
		field_pickup.configure(
			{
				"behavior": "field_pickup",
				"database_entry_id": 990,
				"key": "uniform",
				"original_display_name": "军服",
				"interaction_radius": 48.0,
				"grant": {"kind": "mission_item", "item_key": "uniform", "quantity": 1},
			},
			{"scene_index": 2099, "x": 80.0, "y": 90.0},
		)
		game.field_pickups.append(field_pickup)
		game.add_child(field_pickup)
	return game


func _add_placeholder_unit(game: MockGame, display_name: String, position: Vector2) -> Node2D:
	var unit = SQUAD_UNIT.new()
	var empty_groups: Array[Dictionary] = []
	unit.configure(
		display_name,
		Color.WHITE,
		position,
		null,
		empty_groups,
		empty_groups,
		-1,
		game.dynamic_occupancy,
		position,
	)
	unit.configure_combat(3, 8, COMBAT_PROFILES.weapon_profile("pistol_attack"))
	game.units.append(unit)
	game.add_child(unit)
	return unit


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var value := file.get_as_text()
	file.close()
	return value


func _cleanup_test_root() -> void:
	var absolute_root := ProjectSettings.globalize_path(test_root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return
	_remove_tree(absolute_root)


func _remove_tree(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := absolute_path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
