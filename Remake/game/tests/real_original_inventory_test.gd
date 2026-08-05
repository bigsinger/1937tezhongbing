extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ORIGINAL_INVENTORY: Script = preload(
	"res://scripts/original_initial_weapon_inventory.gd"
)
const ORIGINAL_ITEMS: Script = preload(
	"res://scripts/original_initial_item_inventory.gd"
)
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const LEVEL_IDS := [
	"m000", "m001", "m002", "m003", "m004", "m005",
	"m006", "m007", "m008", "m009", "m010", "m011",
]

var failures: Array[String] = []
var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	# Initial-loadout parity is a classic-ruleset contract and must not inherit
	# a player's persisted modern AI/difficulty preferences. Reload m000 after
	# pinning the test profile so no autonomous modern tick can consume ammo.
	main.runtime_settings["show_briefings"] = false
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	main.runtime_settings["ruleset_mode"] = "classic"
	main.runtime_settings["difficulty_mode"] = "normal"
	main.switch_level(0, false, false)
	var player_count := 0
	var entry_count := 0
	var backpack_player_count := 0
	var backpack_entry_count := 0
	var empty_backpack_player_count := 0
	var exact_weapon_actor_count := 0
	var exact_weapon_entry_count := 0
	var exact_runtime_actor_count := 0
	var exact_runtime_entry_count := 0
	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := str(LEVEL_IDS[level_index])
		if level_index > 0:
			main.switch_level(level_index, false, false)
			await process_frame
		_expect(
			str(main.current_mission.get("id", "")) == level_id,
			"%s is the active imported mission" % level_id,
		)
		var expected_level := (
			ORIGINAL_INVENTORY.load_catalog()
			.get("levels", {})
			.get(level_id, {}) as Dictionary
		)
		var expected_players := expected_level.get("players", []) as Array
		var expected_controllable_scenes: Dictionary = {}
		for player_value: Variant in expected_players:
			if player_value is Dictionary:
				expected_controllable_scenes[
					int((player_value as Dictionary).get("scene_index", -1))
				] = true
		for actor_value: Variant in expected_level.get("actors", []):
			if not actor_value is Dictionary:
				continue
			var expected_actor := actor_value as Dictionary
			var expected_scene_index := int(
				expected_actor.get("scene_index", -1)
			)
			if (
				int(expected_actor.get("vwf_faction_id", 0)) == 3
				and not bool(
					main.call(
						"_is_rescue_bound_scene",
						expected_scene_index,
					)
				)
				and bool(
					main.call(
						"_is_original_squad_display_name",
						str(expected_actor.get("display_name", "")),
					)
				)
			):
				expected_controllable_scenes[
					expected_scene_index
				] = true
		_expect(
			(main.units as Array).size() == expected_controllable_scenes.size(),
			"%s spawns the exact original player count" % level_id,
		)
		for unit_value: Variant in main.units:
			var unit := unit_value as Node2D
			var expected: Dictionary = ORIGINAL_INVENTORY.loadout_for_scene(
				level_id,
				int(unit.get("scene_index")),
			)
			if expected.is_empty():
				expected = ORIGINAL_INVENTORY.loadout_for_any_actor_scene(
					level_id,
					int(unit.get("scene_index")),
				)
			_expect(
				not expected.is_empty(),
				"%s scene %d resolves an exact original loadout"
				% [level_id, int(unit.get("scene_index"))],
			)
			if expected.is_empty():
				continue
			_validate_unit(level_id, unit, expected)
			player_count += 1
			entry_count += (expected.get("items", []) as Array).size()
			var expected_backpack: Dictionary = (
				ORIGINAL_ITEMS.loadout_for_scene(
					level_id,
					int(unit.get("scene_index")),
				)
			)
			_expect(
				not expected_backpack.is_empty(),
				"%s scene %d resolves an exact original backpack"
				% [level_id, int(unit.get("scene_index"))],
			)
			if not expected_backpack.is_empty():
				_validate_backpack(level_id, unit, expected_backpack)
				backpack_player_count += 1
				var expected_backpack_items := (
					expected_backpack.get("items", []) as Array
				)
				backpack_entry_count += expected_backpack_items.size()
				if expected_backpack_items.is_empty():
					empty_backpack_player_count += 1
		for group_name: String in [
			"units", "enemies", "escorts", "ambient_units",
		]:
			for actor_value: Variant in main.get(group_name) as Array:
				var actor := actor_value as Node2D
				var expected_actor_weapons: Dictionary = (
					ORIGINAL_INVENTORY.loadout_for_any_actor_scene(
						level_id,
						int(actor.get("scene_index")),
					)
				)
				if not expected_actor_weapons.is_empty():
					_validate_unit(
						level_id,
						actor,
						expected_actor_weapons,
					)
					exact_weapon_actor_count += 1
					exact_weapon_entry_count += (
						expected_actor_weapons.get("items", []) as Array
					).size()
				var expected_actor_backpack: Dictionary = (
					ORIGINAL_ITEMS.loadout_for_scene(
						level_id,
						int(actor.get("scene_index")),
					)
				)
				if expected_actor_backpack.is_empty():
					continue
				_validate_backpack(
					level_id,
					actor,
					expected_actor_backpack,
				)
				exact_runtime_actor_count += 1
				exact_runtime_entry_count += (
					expected_actor_backpack.get("items", []) as Array
				).size()
		var model: Dictionary = main._inventory_grid_model()
		for group_value: Variant in model.get("groups", []):
			if not group_value is Dictionary:
				continue
			var group := group_value as Dictionary
			if str(group.get("mode", "")) == "weapons":
				continue
			for slot_value: Variant in group.get("slots", []):
				if (
					slot_value is Dictionary
					and int((slot_value as Dictionary).get("item_id", 0))
						in COMBAT_ITEM_IDS
				):
					failures.append(
						"%s duplicates a weapon item in the A inventory"
						% level_id
					)
	_expect(
		player_count == 28 and entry_count == 85,
		(
			"all 28 original command-slot actors and 85 ordered weapon entries "
			+ "reach gameplay"
		),
	)
	_expect(
		backpack_player_count == 28
		and backpack_entry_count == 77
		and empty_backpack_player_count == 1,
		(
			"all 28 original command-slot actors and 77 backpack entries "
			+ "reach gameplay"
		),
	)
	_expect(
		exact_weapon_actor_count == 660
		and exact_weapon_entry_count == 761,
		"all 660 exact dynamic actors and 761 weapon entries reach gameplay",
	)
	_expect(
		exact_runtime_actor_count == 660
		and exact_runtime_entry_count == 539,
		"all 660 exact dynamic actors and 539 backpack entries reach gameplay",
	)
	_test_session_backpack_round_trip(main)
	main.queue_free()
	if failures.is_empty():
		print(
			"Real original inventory tests passed (%d checks, 12 levels)."
			% check_count
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


const COMBAT_ITEM_IDS := [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 99]


func _validate_unit(
	level_id: String,
	unit: Node2D,
	expected: Dictionary,
) -> void:
	var inventory: Variant = unit.get("combat_inventory")
	var expected_items := expected.get("items", []) as Array
	if expected_items.is_empty():
		_expect(
			inventory == null
			or (inventory.call("registered_weapon_keys") as Array).is_empty(),
			"%s scene %d preserves an empty original weapon container"
			% [level_id, int(unit.get("scene_index"))],
		)
		return
	_expect(
		inventory != null and bool(inventory.call("original_parity_enabled")),
		"%s scene %d uses direct-count original parity"
		% [level_id, int(unit.get("scene_index"))],
	)
	if inventory == null:
		return
	var actual_keys: Array[String] = inventory.call("registered_weapon_keys")
	_expect(
		actual_keys.size() == expected_items.size(),
		"%s scene %d registers every captured weapon once"
		% [level_id, int(unit.get("scene_index"))],
	)
	for inventory_index: int in range(expected_items.size()):
		var expected_item := expected_items[inventory_index] as Dictionary
		var item_id := int(expected_item.get("item_id", 0))
		var attack_type: int = ORIGINAL_INVENTORY.attack_type_for_item_id(item_id)
		var action_key := ""
		for candidate_key: String in actual_keys:
			var candidate_profile: Dictionary = inventory.call(
				"weapon_profile",
				candidate_key,
			)
			if int(candidate_profile.get("attack_type", 0)) == attack_type:
				action_key = candidate_key
				break
		var state: Dictionary = inventory.call("weapon_state", action_key)
		_expect(
			not action_key.is_empty()
			and int(state.get("ammo_item_id", 0)) == item_id
			and int(state.get("quantity", -1))
				== int(expected_item.get("quantity", -2))
			and int(state.get("quantity_mode", -1))
				== int(expected_item.get("quantity_mode", -2)),
			"%s scene %d item %d matches quantity and mode"
			% [level_id, int(unit.get("scene_index")), item_id],
		)
	var active_profile: Dictionary = inventory.call("active_weapon_profile")
	_expect(
		int(active_profile.get("attack_type", 0))
			== int(expected.get("default_attack_type", 0)),
		"%s scene %d equips the original default attack"
		% [level_id, int(unit.get("scene_index"))],
	)
	var snapshot: Dictionary = unit.call("inventory_snapshot")
	_expect(
		int(snapshot.get("schema_version", 0)) == 2
		and bool(snapshot.get("original_parity", false)),
		"%s scene %d saves exact inventory schema 2"
		% [level_id, int(unit.get("scene_index"))],
	)
	_expect(
		not bool(unit.call("request_reload")),
		"%s scene %d never enters an invented reload action"
		% [level_id, int(unit.get("scene_index"))],
	)


func _validate_backpack(
	level_id: String,
	unit: Node2D,
	expected: Dictionary,
) -> void:
	var inventory: Variant = unit.get("backpack_inventory")
	_expect(
		inventory != null,
		"%s scene %d has a distinct per-actor backpack container"
		% [level_id, int(unit.get("scene_index"))],
	)
	if inventory == null:
		return
	var actual: Array[Dictionary] = inventory.call("ordered_entries")
	var expected_items := expected.get("items", []) as Array
	_expect(
		actual.size() == expected_items.size(),
		"%s scene %d backpack size matches capture"
		% [level_id, int(unit.get("scene_index"))],
	)
	for inventory_index: int in range(mini(actual.size(), expected_items.size())):
		var actual_item := actual[inventory_index]
		var expected_item := expected_items[inventory_index] as Dictionary
		_expect(
			int(actual_item.get("item_id", 0))
				== int(expected_item.get("item_id", -1))
			and int(actual_item.get("quantity", -1))
				== int(expected_item.get("quantity", -2))
			and int(actual_item.get("quantity_mode", -1))
				== int(expected_item.get("quantity_mode", -2)),
			"%s scene %d backpack index %d preserves item, quantity and mode"
			% [level_id, int(unit.get("scene_index")), inventory_index],
		)


func _test_session_backpack_round_trip(main: Node) -> void:
	if (main.units as Array).is_empty():
		_expect(false, "session test has a player")
		return
	var unit := (main.units as Array)[0] as Node2D
	var before: Dictionary = unit.call("backpack_snapshot")
	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	var records := session.get("squad", []) as Array
	_expect(not records.is_empty(), "session captures squad")
	if records.is_empty():
		return
	_expect(
		(records[0] as Dictionary).get("backpack_inventory") == before,
		"session record persists the separate backpack",
	)
	var inventory: Variant = unit.get("backpack_inventory")
	if inventory != null:
		inventory.call("clear")
	var result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		main,
		session,
	)
	_expect(bool(result.get("ok", false)), "session restore succeeds")
	_expect(
		unit.call("backpack_snapshot") == before,
		"session restore recreates backpack order, quantities and modes",
	)


func _expect(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
