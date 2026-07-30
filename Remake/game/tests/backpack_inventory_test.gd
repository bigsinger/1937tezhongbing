extends SceneTree

const BACKPACK_INVENTORY: Script = preload("res://scripts/backpack_inventory.gd")
const ORIGINAL_ITEMS: Script = preload(
	"res://scripts/original_initial_item_inventory.gd"
)

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_quantity_modes_and_order()
	_test_snapshot_round_trip()
	_test_real_catalog()
	if _failures.is_empty():
		print("Backpack inventory tests passed (%d checks)." % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _test_quantity_modes_and_order() -> void:
	var inventory = BACKPACK_INVENTORY.new()
	_expect(inventory.register_original_item(50, 2, 0), "register mode-0 item")
	_expect(inventory.register_original_item(83, 1, 1), "register durable item")
	_expect(inventory.register_original_item(33, 1, 1), "preserve original order")
	_expect(not inventory.register_original_item(50, 1, 0), "reject duplicate item")
	_expect(inventory.consume(50), "consume first watermelon")
	_expect(inventory.item_count(50) == 1, "mode 0 decrements")
	_expect(inventory.consume(50), "consume last watermelon")
	_expect(not inventory.has_item(50), "mode 0 removes at zero")
	_expect(inventory.consume(83), "normal durable use succeeds")
	_expect(inventory.item_count(83) == 1, "mode 1 normal use is durable")
	_expect(inventory.consume(83, true), "forced durable use succeeds")
	_expect(not inventory.has_item(83), "forced mode 1 removes at zero")
	var order: Array[Dictionary] = inventory.ordered_entries()
	_expect(order.size() == 1 and int(order[0].item_id) == 33, "remaining order")
	_expect(inventory.register_original_item(49, 1, 1), "register drop item")
	var dropped: Dictionary = inventory.take_for_drop(49)
	_expect(int(dropped.get("item_id", 0)) == 49, "drop returns exact item")
	_expect(not inventory.has_item(49), "drop forces removal")


func _test_snapshot_round_trip() -> void:
	var source = BACKPACK_INVENTORY.new()
	_expect(source.register_original_item(47, 1, 0), "snapshot medkit")
	_expect(source.register_original_item(52, 1, 1), "snapshot poison wine")
	var restored = BACKPACK_INVENTORY.new()
	_expect(restored.restore_snapshot(source.snapshot()), "restore snapshot")
	_expect(
		restored.ordered_entries() == source.ordered_entries(),
		"snapshot preserves order and modes",
	)
	_expect(
		not restored.restore_snapshot({"schema_version": 99, "entries": []}),
		"reject unsupported snapshot",
	)


func _test_real_catalog() -> void:
	var catalog: Dictionary = ORIGINAL_ITEMS.load_catalog()
	_expect(not catalog.is_empty(), "load exact original catalog")
	var summary := catalog.get("summary", {}) as Dictionary
	_expect(int(summary.get("level_count", 0)) == 12, "catalog has twelve levels")
	_expect(int(summary.get("exact_actor_count", 0)) == 660, "catalog actor total")
	_expect(int(summary.get("inventory_entry_count", 0)) == 539, "catalog entry total")
	_expect(int(summary.get("player_count", 0)) == 27, "catalog player total")
	_expect(
		int(summary.get("player_inventory_entry_count", 0)) == 74,
		"catalog player entry total",
	)
	var loadout: Dictionary = ORIGINAL_ITEMS.loadout_for_scene("m000", 1436)
	var items := loadout.get("items", []) as Array
	_expect(items.size() == 1, "m000 player has one ordered item kind")
	_expect(int((items[0] as Dictionary).get("item_id", 0)) == 50, "m000 item is watermelon")
	_expect(int((items[0] as Dictionary).get("quantity", 0)) == 2, "m000 has two watermelons")
	_expect(
		ORIGINAL_ITEMS.item_display_name(47) == "医药箱",
		"original medkit name",
	)
	var medkit: Dictionary = ORIGINAL_ITEMS.item_profile(47)
	_expect(str((medkit.get("effect", {}) as Dictionary).get("kind", "")) == "set_hit_points", "medkit exact effect")
	_expect(int((medkit.get("effect", {}) as Dictionary).get("value", 0)) == 8, "medkit restores to eight")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
