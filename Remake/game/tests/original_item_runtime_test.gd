extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ORIGINAL_ITEMS: Script = preload(
	"res://scripts/original_initial_item_inventory.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	_test_m000_watermelon_and_grid(main)
	main.switch_level(10)
	await process_frame
	_test_m010_medkit_and_ammunition_box(main)
	_test_drop_enemy_pickup_and_death_loot(main)
	main.queue_free()
	if failures.is_empty():
		print("Original item runtime tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_m000_watermelon_and_grid(main: Node) -> void:
	_expect((main.units as Array).size() == 1, "m000 has one player")
	var unit := (main.units as Array)[0] as Node2D
	var backpack: Variant = unit.get("backpack_inventory")
	_expect(backpack != null, "m000 player backpack exists")
	if backpack == null:
		return
	_expect(int(backpack.call("item_count", 50)) == 2, "m000 starts with two watermelons")
	var model: Dictionary = main.call("_inventory_grid_model")
	var found_slot := false
	for group_value: Variant in model.get("groups", []):
		if not group_value is Dictionary:
			continue
		for slot_value: Variant in (group_value as Dictionary).get("slots", []):
			if (
				slot_value is Dictionary
				and str((slot_value as Dictionary).get("kind", ""))
					== "backpack_item"
				and int((slot_value as Dictionary).get("item_id", 0)) == 50
			):
				found_slot = (
					int((slot_value as Dictionary).get("quantity", 0)) == 2
				)
	_expect(found_slot, "A inventory grid exposes the exact watermelon slot")
	unit.set("current_hit_points", 1)
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				unit,
				50,
				ORIGINAL_ITEMS.item_profile(50),
			)
		),
		"watermelon use succeeds",
	)
	_expect(int(unit.get("current_hit_points")) == 5, "watermelon heals exactly four")
	_expect(int(backpack.call("item_count", 50)) == 1, "watermelon decrements")
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				unit,
				50,
				ORIGINAL_ITEMS.item_profile(50),
			)
		),
		"second watermelon use succeeds",
	)
	_expect(int(unit.get("current_hit_points")) == 8, "watermelon healing caps at eight")
	_expect(not bool(backpack.call("has_item", 50)), "last mode-0 item is removed")


func _test_m010_medkit_and_ammunition_box(main: Node) -> void:
	var strong := _actor_by_scene(main.units as Array, 1589)
	var old_zhao := _actor_by_scene(main.units as Array, 1590)
	_expect(strong != null and old_zhao != null, "m010 target players spawn")
	if strong == null or old_zhao == null:
		return
	strong.set("current_hit_points", 2)
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				strong,
				47,
				ORIGINAL_ITEMS.item_profile(47),
			)
		),
		"medkit use succeeds",
	)
	_expect(int(strong.get("current_hit_points")) == 8, "medkit sets health to eight")
	var inventory: Variant = old_zhao.get("combat_inventory")
	_expect(inventory != null, "m010 old Zhao has exact weapon inventory")
	if inventory == null:
		return
	var before_36 := int(inventory.call("ammo_item_count", 36))
	var before_43 := int(inventory.call("ammo_item_count", 43))
	var before_45 := int(inventory.call("ammo_item_count", 45))
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				old_zhao,
				46,
				ORIGINAL_ITEMS.item_profile(46),
			)
		),
		"ammunition-box use succeeds",
	)
	_expect(
		int(inventory.call("ammo_item_count", 36)) == before_36 + 10,
		"ammunition box adds ten pistol rounds",
	)
	_expect(
		int(inventory.call("ammo_item_count", 43)) == before_43 + 3,
		"ammunition box adds three mines",
	)
	_expect(
		int(inventory.call("ammo_item_count", 45)) == before_45 + 3,
		"ammunition box adds three explosive charges",
	)
	var backpack: Variant = old_zhao.get("backpack_inventory")
	_expect(
		backpack != null and not bool(backpack.call("has_item", 46)),
		"used ammunition box is removed",
	)


func _test_drop_enemy_pickup_and_death_loot(main: Node) -> void:
	var source := _actor_by_scene(main.units as Array, 1589)
	var carrier: Node2D
	for enemy_value: Variant in main.enemies as Array:
		var enemy := enemy_value as Node2D
		var inventory: Variant = enemy.get("backpack_inventory")
		if inventory != null:
			carrier = enemy
			break
	_expect(source != null and carrier != null, "drop test actors exist")
	if source == null or carrier == null:
		return
	var carrier_inventory: Variant = carrier.get("backpack_inventory")
	var before_count := int(carrier_inventory.call("item_count", 48))
	main.call("select_only", source)
	main.set("selected_backpack_item_id", 48)
	_expect(
		bool(main.call("drop_selected_item_at", carrier.position)),
		"selected actor drops exact backpack item",
	)
	_expect((main.mission_pickups as Array).size() == 1, "ground pickup is created")
	main.call("_process_enemy_ground_pickups")
	_expect((main.mission_pickups as Array).is_empty(), "enemy consumes ground pickup")
	_expect(
		int(carrier_inventory.call("item_count", 48)) == before_count + 1,
		"enemy carries the picked-up original item",
	)

	var loot_source: Node2D
	for enemy_value: Variant in main.enemies as Array:
		var enemy := enemy_value as Node2D
		var inventory: Variant = enemy.get("backpack_inventory")
		if (
			enemy != carrier
			and inventory != null
			and not (inventory.call("ordered_entries") as Array).is_empty()
		):
			loot_source = enemy
			break
	_expect(loot_source != null, "enemy with exact death loot exists")
	if loot_source == null:
		return
	var loot_inventory: Variant = loot_source.get("backpack_inventory")
	var expected_entries := loot_inventory.call("ordered_entries") as Array
	var before_pickups := (main.mission_pickups as Array).size()
	main.call("_spawn_original_inventory_drops", loot_source)
	_expect(
		(main.mission_pickups as Array).size()
			== before_pickups + expected_entries.size(),
		"death creates one ordered pickup per backpack entry",
	)
	_expect(
		(loot_inventory.call("ordered_entries") as Array).is_empty(),
		"death clears the source backpack",
	)
	for pickup_index: int in range(
		before_pickups,
		(main.mission_pickups as Array).size(),
	):
		var pickup := (main.mission_pickups as Array)[pickup_index] as Node
		var payload := pickup.get("item_payload") as Dictionary
		_expect(
			str(payload.get("original_inventory_kind", "")) == "backpack",
			"death pickup preserves original container kind",
		)


func _actor_by_scene(actors: Array, scene_index: int) -> Node2D:
	for actor_value: Variant in actors:
		if (
			actor_value is Node2D
			and int((actor_value as Node2D).get("scene_index")) == scene_index
		):
			return actor_value as Node2D
	return null


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
