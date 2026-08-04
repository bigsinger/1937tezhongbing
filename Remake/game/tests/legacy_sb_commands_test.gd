extends SceneTree

const MAIN: Script = preload("res://scripts/main.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const OBSERVATION_BEACON: Script = preload(
	"res://scripts/legacy_observation_beacon.gd"
)
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")


class MockNavigation:
	extends RefCounted

	var line_of_sight := true

	func has_line_of_sight(
		_observer: Vector2,
		_target: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return line_of_sight


var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_observation_target_filter_and_line_of_sight(failures)
	_test_observation_marker_is_singleton_and_one_shot(failures)
	_test_original_burial_grid_range(failures)
	_test_burial_tick_limit_cache_and_inventory_copy(failures)
	_test_sb_save_contract(failures)
	if failures.is_empty():
		print("Original S/B command tests passed (%d checks)." % check_count)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_observation_target_filter_and_line_of_sight(
	failures: Array[String],
) -> void:
	var navigation := MockNavigation.new()
	var enemy := _make_enemy(101, Vector2.ZERO)
	enemy.original_direction_index = 3
	enemy.sense_profile = {
		"horizontal_radius": 200.0,
		"vertical_radius": 100.0,
		"near_band_ratio": 0.5,
		"requires_line_of_sight": true,
	}
	var beacon: Node2D = OBSERVATION_BEACON.new()
	var observers: Array[Node2D] = [enemy]
	beacon.call(
		"configure",
		Vector2(100.0, 0.0),
		navigation,
		observers,
		null,
		1,
	)
	beacon.call("force_poll_result_for_tests", 1)
	_expect(
		beacon.call("advance_world_ticks", 1) == enemy
		and bool(beacon.get("consumed")),
		"S marker accepts a living faction-1 enemy inside its current fan and LOS",
		failures,
	)

	var blocked: Node2D = OBSERVATION_BEACON.new()
	navigation.line_of_sight = false
	blocked.call(
		"configure",
		Vector2(100.0, 0.0),
		navigation,
		observers,
		null,
		1,
	)
	blocked.call("force_poll_result_for_tests", 1)
	_expect(
		blocked.call("advance_world_ticks", 1) == null
		and not bool(blocked.get("consumed")),
		"S marker does not pass through a recovered navigation sight obstruction",
		failures,
	)
	navigation.line_of_sight = true
	enemy.faction_id = 3
	_expect(
		not bool(blocked.call("can_be_observed_by", enemy)),
		"S marker rejects actors outside original faction 1",
		failures,
	)
	enemy.faction_id = 1
	enemy.is_alive = false
	_expect(
		not bool(blocked.call("can_be_observed_by", enemy)),
		"S marker rejects dead enemies",
		failures,
	)
	beacon.free()
	blocked.free()
	enemy.free()


func _test_observation_marker_is_singleton_and_one_shot(
	failures: Array[String],
) -> void:
	var game: Node2D = MAIN.new()
	game.legacy_crt_random_trace_enabled = true
	var enemy := _make_enemy(102, Vector2(96.0, 0.0))
	enemy.original_direction_index = 3
	enemy.sense_profile = {
		"horizontal_radius": 200.0,
		"vertical_radius": 100.0,
		"near_band_ratio": 0.5,
		"requires_line_of_sight": false,
	}
	game.add_child(enemy)
	game.enemies.append(enemy)
	var first: Node2D = game.call(
		"_place_or_move_sight_beacon", Vector2(80.0, 0.0)
	)
	var second: Node2D = game.call(
		"_place_or_move_sight_beacon", Vector2(112.0, 0.0)
	)
	_expect(
		first == second
		and second.position == Vector2(112.0, 0.0)
		and game.legacy_crt_random_trace.size() == 4,
		"S creates actor 90 once through the four-draw factory, then moves it in place",
		failures,
	)
	second.call("force_poll_result_for_tests", 1)
	second.call("advance_world_ticks", 1)
	var marker_sites: Array[int] = []
	for draw: Dictionary in game.legacy_crt_random_trace:
		marker_sites.append(int(draw.get("call_site_rva", 0)))
	_expect(
		game.sight_beacon == null
		and game.sight_observation_target == enemy
		and enemy.selected
		and enemy.tactical_ranges_visible
		and marker_sites == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"the first valid observer consumes actor 90 through the exact four-draw destructor",
		failures,
	)
	game.free()


func _test_original_burial_grid_range(failures: Array[String]) -> void:
	_expect(
		MAIN.is_original_burial_range(Vector2(0.0, 0.0), Vector2(63.0, 31.0)),
		"B range accepts actors no more than one recovered 32x16 cell apart",
		failures,
	)
	_expect(
		not MAIN.is_original_burial_range(
			Vector2(0.0, 0.0),
			Vector2(64.0, 32.0),
		),
		"B range rejects a two-cell separation on both recovered axes",
		failures,
	)


func _test_burial_tick_limit_cache_and_inventory_copy(
	failures: Array[String],
) -> void:
	var game: Node2D = MAIN.new()
	game.legacy_crt_random_trace_enabled = true
	var worker: Node2D = SQUAD_UNIT.new()
	worker.scene_index = 11
	worker.position = Vector2.ZERO
	worker.is_alive = true
	var corpse := _make_enemy(212, Vector2(40.0, 8.0))
	corpse.is_alive = false
	corpse.current_hit_points = 0
	var pistol: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(1)
	var no_attack_groups: Array[Dictionary] = []
	_expect(
		corpse.register_original_inventory_weapon(
			pistol,
			no_attack_groups,
			6,
			2,
			true,
		),
		"burial fixture has an original weapon container",
		failures,
	)
	_expect(
		corpse.add_backpack_item(46, 2, 0) == 2,
		"burial fixture has an original item container",
		failures,
	)
	game.add_child(worker)
	game.add_child(corpse)
	game.units.append(worker)
	game.enemies.append(corpse)
	game.selected_units.append(worker)
	_expect(
		bool(game.call("_try_bury_at", corpse.position))
		and game.burial_worker == worker
		and game.burial_target == corpse
		and int(worker.get("original_pending_acknowledgement_count")) == 1,
		"an accepted B command queues one deferred worker acknowledgement",
		failures,
	)
	for unused_tick: int in range(100):
		game.call("_advance_burial_command_world_tick")
	_expect(
		corpse.visible
		and game.burial_progress_ticks == 100
		and game.legacy_burial_caches.is_empty(),
		"B keeps the corpse through counter value 100",
		failures,
	)
	game.call("_advance_burial_command_world_tick")
	var burial_sites: Array[int] = []
	for draw: Dictionary in game.legacy_crt_random_trace:
		burial_sites.append(int(draw.get("call_site_rva", 0)))
	_expect(
		not corpse.visible
		and game.buried_enemy_scene_indices.has(212)
		and game.legacy_burial_caches.size() == 1
		and worker.original_command_goal_kind_latch == 4
		and burial_sites == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"B creates actor 78 before retiring the corpse with the exact eight-draw order",
		failures,
	)
	var cache: Node2D = game.legacy_burial_caches[0]
	_expect(
		int(cache.get("original_actor_type")) == 78
		and int(cache.get("original_gfl_index")) == 64,
		"B completion creates recovered actor 78 using GFL 64",
		failures,
	)
	var cache_snapshot := cache.call("snapshot") as Dictionary
	_expect(
		not (cache_snapshot["weapon_inventory"] as Dictionary).is_empty()
		and not (cache_snapshot["backpack_inventory"] as Dictionary).is_empty(),
		"actor 78 independently copies both corpse inventory containers",
		failures,
	)
	var transfer := cache.call("transfer_all_to", worker) as Dictionary
	_expect(
		int(transfer.get("weapon_entries", 0)) == 1
		and int(transfer.get("backpack_entries", 0)) == 1
		and worker.ammo_item_count(36) == 6
		and worker.backpack_inventory.item_count(46) == 2,
		"the selected squad member can recover both copied containers from actor 78",
		failures,
	)
	worker.issue_move(Vector2(96.0, 32.0))
	_expect(
		worker.original_command_goal_kind_latch == 0,
		"the next movement command overwrites the original retained B goal kind",
		failures,
	)
	game.free()


func _test_sb_save_contract(failures: Array[String]) -> void:
	var game: Node2D = MAIN.new()
	game.current_mission = {"id": "m000"}
	var worker: Node2D = SQUAD_UNIT.new()
	worker.scene_index = 31
	worker.display_name = "worker"
	worker.position = Vector2.ZERO
	var corpse := _make_enemy(32, Vector2(40.0, 8.0))
	corpse.display_name = "corpse"
	corpse.is_alive = false
	corpse.current_hit_points = 0
	game.add_child(worker)
	game.add_child(corpse)
	game.units.append(worker)
	game.enemies.append(corpse)
	game.burial_worker = worker
	game.burial_target = corpse
	game.burial_progress_ticks = 37
	game.burial_action_started = true
	worker.original_command_goal_kind_latch = 4
	game.call("_place_or_move_sight_beacon", Vector2(120.0, 0.0))
	game.call(
		"_spawn_legacy_burial_cache",
		Vector2(72.0, 24.0),
		900,
		{
			"schema_version": 2,
			"original_parity": true,
			"active_action_key": "",
			"items": {},
			"weapons": {},
		},
		{"schema_version": 1, "entries": []},
	)
	var session: Dictionary = GAME_SESSION_STATE.capture(game)
	var world := session["world"] as Dictionary
	var squad_record := (session["squad"] as Array)[0] as Dictionary
	var pending := world["pending_burial_command"] as Dictionary
	_expect(
		int(pending.get("worker_scene_index", -1)) == 31
		and int(pending.get("target_scene_index", -1)) == 32
		and int(pending.get("progress_ticks", -1)) == 37
		and bool(pending.get("action_started", false)),
		"save data preserves the in-progress original B command counters and identities",
		failures,
	)
	_expect(
		int(squad_record.get("original_command_goal_kind_latch", 0)) == 4,
		"save data preserves the original B command-kind latch",
		failures,
	)
	_expect(
		not world.has("sight_beacon")
		and not world.has("sight_observation_marker")
		and not world.has("sight_observation_target"),
		"ephemeral actor 90 and its triggered observation state are never persisted",
		failures,
	)
	var restored_game: Node2D = MAIN.new()
	var restored_worker: Node2D = SQUAD_UNIT.new()
	restored_worker.scene_index = 31
	restored_worker.display_name = "worker"
	var restored_corpse := _make_enemy(32, Vector2(40.0, 8.0))
	restored_corpse.display_name = "corpse"
	restored_corpse.is_alive = false
	restored_game.add_child(restored_worker)
	restored_game.add_child(restored_corpse)
	restored_game.units.append(restored_worker)
	restored_game.enemies.append(restored_corpse)
	var warnings: Array[String] = []
	GAME_SESSION_STATE.call("_restore_world", restored_game, world, warnings)
	_expect(
		warnings.is_empty()
		and restored_game.legacy_burial_caches.size() == 1
		and int(
			restored_game.legacy_burial_caches[0].get(
				"source_enemy_scene_index"
			)
		) == 900
		and restored_game.burial_worker == restored_worker
		and restored_game.burial_target == restored_corpse
		and restored_game.burial_progress_ticks == 37
		and restored_game.burial_action_started
		and restored_worker.original_command_goal_kind_latch == 4
		and restored_game.sight_beacon == null,
		"load rebuilds actor 78 and resumes B exactly while leaving actor 90 absent",
		failures,
	)
	var save_store = GAME_SAVE_STORE.new(
		"user://legacy-sb-command-test-%d" % OS.get_process_id()
	)
	var valid_session: bool = save_store.call("_is_valid_session", session)
	_expect(
		valid_session,
		"the expanded S/B world snapshot remains a valid product save",
		failures,
	)
	restored_game.free()
	game.free()


func _make_enemy(scene_index: int, world_position: Vector2) -> Node2D:
	var enemy: Node2D = ENEMY_UNIT.new()
	enemy.scene_index = scene_index
	enemy.position = world_position
	enemy.faction_id = 1
	enemy.is_alive = true
	return enemy


func _expect(
	condition: bool,
	message: String,
	failures: Array[String],
) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
