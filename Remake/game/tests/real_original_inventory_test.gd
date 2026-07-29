extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ORIGINAL_INVENTORY: Script = preload(
	"res://scripts/original_initial_weapon_inventory.gd"
)
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
	var player_count := 0
	var entry_count := 0
	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := str(LEVEL_IDS[level_index])
		if level_index > 0:
			main.switch_level(level_index)
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
		_expect(
			(main.units as Array).size() == expected_players.size(),
			"%s spawns the exact original player count" % level_id,
		)
		for unit_value: Variant in main.units:
			var unit := unit_value as Node2D
			var expected: Dictionary = ORIGINAL_INVENTORY.loadout_for_scene(
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
		player_count == 27 and entry_count == 83,
		"all 27 original players and 83 ordered weapon entries reach gameplay",
	)
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
	_expect(
		inventory != null and bool(inventory.call("original_parity_enabled")),
		"%s scene %d uses direct-count original parity"
		% [level_id, int(unit.get("scene_index"))],
	)
	if inventory == null:
		return
	var expected_items := expected.get("items", []) as Array
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


func _expect(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
