extends SceneTree

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const GAME_SETTINGS: Script = preload("res://scripts/game_settings.gd")
const FIELD_PICKUP: Script = preload("res://scripts/field_pickup.gd")
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
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


class MockGame:
	extends Node2D

	var current_mission: Dictionary = {"id": "m003"}
	var current_mission_state: RefCounted
	var mission_runtime: Node
	var level_camera: Camera2D
	var units: Array[Node2D] = []
	var selected_units: Array[Node2D] = []
	var enemies: Array[Node2D] = []
	var escorts: Array[Node2D] = []
	var field_pickups: Array[Node2D] = []
	var explosive_props: Array[Node2D] = []
	var mission_pickups: Array[Node2D] = []
	var deployed_mines: Array[Node2D] = []
	var projectile_world: Node2D
	var activated_mission_scenes: Dictionary = {}
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
	_test_save_round_trip_and_recovery(failures)
	_test_save_migration_and_slot_safety(failures)
	_test_mid_mission_capture_and_apply(failures)
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
	var path := test_root + "/settings.json"
	var settings = GAME_SETTINGS.new()
	var missing: Dictionary = settings.load_from_disk(path)
	_expect(not bool(missing["ok"]), "missing settings report degradation", failures)
	_expect(bool(missing["used_default"]), "missing settings use safe defaults", failures)
	_expect(settings.display_settings()["mode"] == "fullscreen", "default display is fullscreen", failures)
	_expect(settings.display_settings()["resolution_policy"] == "desktop", "fullscreen follows desktop resolution", failures)
	_expect(settings.hint_enabled("controls"), "control hints default on", failures)

	settings.set_audio_volume("master", 0.35)
	settings.set_audio_volume("sfx", 0.55)
	settings.set_display_mode("windowed")
	settings.set_resolution_policy("custom")
	settings.set_window_size(Vector2i(1600, 900))
	settings.set_hint_enabled("interactions", false)
	settings.set_interface_enabled("subtitles", false)
	settings.set_interface_enabled("edge_scroll", false)
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
	_expect(int(migrated.values["schema_version"]) == 1, "legacy settings migrate to v1", failures)
	_expect(is_equal_approx(migrated.audio_volume("master"), 0.42), "legacy volume migrates", failures)
	_expect(migrated.display_settings()["mode"] == "windowed", "legacy fullscreen flag migrates", failures)
	_expect(not migrated.hint_enabled("objectives"), "legacy hint flag migrates", failures)

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

	var future_path := test_root + "/future-settings.json"
	_write_json(future_path, {"schema_version": 99, "audio": {}})
	var future = GAME_SETTINGS.new()
	var future_result: Dictionary = future.load_from_disk(future_path)
	_expect(not bool(future_result["ok"]), "unknown future settings version is rejected", failures)
	_expect(bool(future_result["used_default"]), "future settings safely degrade to defaults", failures)


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
	session["elapsed_seconds"] = 48.5
	(session["squad"] as Array)[0]["current_hit_points"] = 5
	var second: Dictionary = store.save_slot("slot_1", session, campaign)
	_expect(bool(second["ok"]), "second mid-mission save succeeds", failures)
	_expect(int((second["data"] as Dictionary)["revision"]) == 2, "save revision increments", failures)
	var loaded: Dictionary = store.load_slot("slot_1")
	var loaded_session := (loaded["data"] as Dictionary)["session"] as Dictionary
	_expect(bool(loaded["ok"]) and loaded["source"] == "primary", "save loads from primary", failures)
	_expect(is_equal_approx(float(loaded_session["elapsed_seconds"]), 48.5), "elapsed mission time persists", failures)
	_expect(int((loaded_session["squad"] as Array)[0]["current_hit_points"]) == 5, "actor health persists", failures)
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
	_expect(not GAME_SAVE_STORE.is_valid_slot_id("../escape"), "slot path traversal is rejected", failures)
	_expect(not bool(store.save_slot("../escape", _sample_session())["ok"]), "unsafe slot cannot be written", failures)
	_expect(GAME_SAVE_STORE.is_valid_slot_id("quick-save_1"), "safe slot ID is accepted", failures)
	var legacy_path: String = str(store.slot_path("legacy"))
	_write_json(legacy_path, {"level_id": "m002", "elapsed_seconds": 13.0})
	var legacy: Dictionary = store.load_slot("legacy")
	_expect(bool(legacy["ok"]), "v0 level save migrates", failures)
	_expect(int((legacy["data"] as Dictionary)["schema_version"]) == 1, "v0 save receives current schema", failures)
	_expect(
		str(((legacy["data"] as Dictionary)["session"] as Dictionary)["level_id"]) == "m002",
		"v0 level ID survives migration",
		failures,
	)
	var future_path: String = str(store.slot_path("future"))
	_write_json(future_path, {"schema_version": 77, "game_id": "1937-remake"})
	_expect(not bool(store.load_slot("future")["ok"]), "future save version is rejected", failures)


func _test_mid_mission_capture_and_apply(failures: Array[String]) -> void:
	var source_game := _make_mock_game(true)
	root.add_child(source_game)
	var session: Dictionary = GAME_SESSION_STATE.capture(source_game)
	_expect(str(session["level_id"]) == "m003", "capture records current formal level", failures)
	_expect(is_equal_approx(float(session["elapsed_seconds"]), 17.25), "capture records mission clock", failures)
	var captured_seen := ((session["mission"] as Dictionary)["seen_values"] as Dictionary)["secure"] as Array
	_expect(captured_seen == [2637], "numeric seen values are encoded as an array", failures)
	var inventory := ((session["squad"] as Array)[0]["inventory"] as Dictionary)["items"] as Dictionary
	_expect(inventory.has("36") and inventory.has("43"), "numeric inventory keys are JSON strings", failures)
	_expect((session["world"] as Dictionary)["activated_scene_indices"] == [2637], "activated scenes persist", failures)
	var store = GAME_SAVE_STORE.new(test_root + "/capture-saves")
	_expect(bool(store.save_slot("midgame", session)["ok"]), "captured runtime satisfies save schema", failures)
	var disk_session := ((store.load_slot("midgame")["data"] as Dictionary)["session"] as Dictionary)

	var target_game := _make_mock_game(false)
	root.add_child(target_game)
	var apply_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(target_game, disk_session)
	_expect(bool(apply_result["ok"]), "mid-mission snapshot applies after level load", failures)
	var target_unit := target_game.units[0]
	_expect(target_unit.position.is_equal_approx(Vector2(321.0, 654.0)), "actor position restores", failures)
	_expect(int(target_unit.current_hit_points) == 6, "actor health restores", failures)
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
	_expect(target_unit.ammo_item_count(43) == 2, "integer-key deployable inventory restores", failures)
	_expect(target_unit.ammo_item_count(36) == 35, "integer-key ammunition inventory restores", failures)
	var restored_seen := target_game.current_mission_state.seen_values["secure"] as Dictionary
	_expect(restored_seen.has(2637) and not restored_seen.has("2637"), "seen value regains numeric key type", failures)
	_expect(target_game.mission_runtime._durable_facts.size() == 1, "durable mission facts restore", failures)
	_expect(target_game.activated_mission_scenes.has(2637), "activated mission scene restores", failures)
	_expect(int(target_game.field_inventory["explosives"]) == 3, "squad field inventory restores", failures)
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
	game.dynamic_occupancy = MockOccupancy.new()
	var unit = SQUAD_UNIT.new()
	var empty_groups: Array[Dictionary] = []
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
		},
		null,
		empty_groups,
		empty_groups,
		game.dynamic_occupancy,
	)
	game.enemies.append(enemy)
	game.add_child(enemy)
	if populated:
		unit.position = Vector2(321.0, 654.0)
		unit.selected = true
		game.selected_units = [unit]
		enemy.current_target = unit
		enemy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
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
