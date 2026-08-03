extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ORIGINAL_ITEMS: Script = preload(
	"res://scripts/original_initial_item_inventory.gd"
)
const LEGACY_WORLD_ITEM_RULES: Script = preload(
	"res://scripts/legacy_world_item_rules.gd"
)
const LEGACY_DISGUISE_RULES: Script = preload(
	"res://scripts/legacy_disguise_rules.gd"
)
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
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
	main.switch_level(1)
	await process_frame
	await _test_m001_gu_ming_disguise(main)
	main.switch_level(10)
	await process_frame
	_test_m010_medkit_and_ammunition_box(main)
	await _test_drop_enemy_pickup_and_death_loot(main)
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


func _test_m001_gu_ming_disguise(main: Node) -> void:
	var gu_ming := _actor_by_scene(main.units as Array, 1994)
	_expect(gu_ming != null, "m001 Gu Ming scene 1994 spawns")
	if gu_ming == null:
		return
	var backpack: Variant = gu_ming.get("backpack_inventory")
	_expect(backpack != null, "m001 Gu Ming backpack exists")
	if backpack == null:
		return
	if not bool(backpack.call("has_item", 54)):
		_expect(
			int(gu_ming.call("add_backpack_item", 54, 1, 0)) == 1,
			"test grants the recovered m001 uniform pickup to Gu Ming",
		)
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				gu_ming,
				54,
				ORIGINAL_ITEMS.item_profile(54),
			)
		),
		"Gu Ming begins the uniform action",
	)
	for unused_tick: int in range(
		LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT
	):
		gu_ming.call(
			"advance_original_disguise_transition",
			LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
		)
	_expect(
		int(gu_ming.get("runtime_actor_type")) == 10
		and int(gu_ming.get("disguise_transition_tick_counter")) == 100
		and bool(backpack.call("has_item", 54)),
		"real-asset transition has no early effect at tick 100",
	)
	gu_ming.call(
		"advance_original_disguise_transition",
		LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
	)
	var combat_inventory: Variant = gu_ming.get("combat_inventory")
	_expect(
		int(gu_ming.get("runtime_actor_type")) == 91
		and int(gu_ming.get("faction_id")) == 1
		and not bool(backpack.call("has_item", 54))
		and bool(backpack.call("has_item", 92))
		and combat_inventory != null
		and int(combat_inventory.call("ammo_item_count", 99)) == 1,
		"real m001 transition installs type 91, faction disguise, clothing 92 and item 99",
	)
	_expect(
		gu_ming.get("sprite_texture") != null
		and (gu_ming.get("crawl_groups") as Array).is_empty(),
		"GFL 272 visual is loaded and correctly has no crawl action",
	)
	var living_enemy: Node2D
	for enemy_value: Variant in main.enemies as Array:
		if bool((enemy_value as Node2D).get("is_alive")):
			living_enemy = enemy_value as Node2D
			break
	main.call("select_only", gu_ming)
	main.call("issue_attack_order", living_enemy, false)
	_expect(
		living_enemy != null
		and gu_ming.get("combat_target") == living_enemy
		and bool(gu_ming.get("combat_target_forced")),
		"disguised faction-1 Gu Ming can still receive a normal player attack order",
	)
	gu_ming.call("clear_combat_target")
	living_enemy.position = gu_ming.position - Vector2(16.0, 0.0)
	living_enemy.set("original_direction_index", 3)
	living_enemy.set("current_target", null)
	living_enemy.set("behavior_state", 0)
	main.call(
		"_on_original_disguise_attack_committed",
		gu_ming,
		living_enemy,
		1,
	)
	_expect(
		int(gu_ming.get("faction_id")) == 3
		and bool(
			living_enemy.get(
				"pending_original_coordinate_alert_active"
			)
		)
		and (
			living_enemy.get(
				"pending_original_coordinate_alert_position"
			) as Vector2
		) == living_enemy.position,
		"an actual directional/LOS observer exposes Gu Ming and queues the attacked coordinate",
	)
	for unused_tick: int in range(17):
		gu_ming.call(
			"advance_original_disguise_recovery",
			LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
			false,
		)
	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	var saved_record: Dictionary = {}
	for record_value: Variant in session.get("squad", []) as Array:
		if (
			record_value is Dictionary
			and int((record_value as Dictionary).get("scene_index", -1))
				== 1994
		):
			saved_record = record_value as Dictionary
			break
	_expect(
		int(saved_record.get("runtime_actor_type", 0)) == 91
		and int(
			(
				saved_record.get("original_disguise", {}) as Dictionary
			).get("recovery_tick_counter", 0)
		) == 17,
		"save captures runtime actor replacement and disguise recovery counter",
	)
	main.switch_level(1)
	await process_frame
	var restore_result: Dictionary = (
		GAME_SESSION_STATE.apply_after_level_loaded(main, session)
	)
	var restored := _actor_by_scene(main.units as Array, 1994)
	_expect(
		bool(restore_result.get("ok", false))
		and restored != null
		and int(restored.get("runtime_actor_type")) == 91
		and int(restored.get("faction_id")) == 3
		and int(restored.get("disguise_recovery_tick_counter")) == 17
		and restored.get("sprite_texture") != null,
		"load restores exposed GFL 272 Gu Ming and pending recovery exactly",
	)
	if restored == null:
		return
	var restored_backpack: Variant = restored.get("backpack_inventory")
	_expect(
		bool(
			main.call(
				"_use_original_backpack_item",
				restored,
				92,
				ORIGINAL_ITEMS.item_profile(92),
			)
		),
		"restored Gu Ming begins changing back to civilian clothes",
	)
	for unused_tick: int in range(
		LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT + 1
	):
		restored.call(
			"advance_original_disguise_transition",
			LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
		)
	var restored_combat_inventory: Variant = restored.get("combat_inventory")
	_expect(
		int(restored.get("runtime_actor_type")) == 10
		and int(restored.get("faction_id")) == 3
		and bool(restored_backpack.call("has_item", 54))
		and not bool(restored_backpack.call("has_item", 92))
		and int(restored_combat_inventory.call("ammo_item_count", 99)) == 0,
		"civilian-clothing action restores type 10/faction 3 and removes item 99",
	)


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
		if (
			inventory != null
			and LEGACY_WORLD_ITEM_RULES.accepts_item(
				int(enemy.get("runtime_actor_type")),
				48,
				int(enemy.get("faction_id")),
			)
		):
			carrier = enemy
			break
	_expect(source != null and carrier != null, "drop test actors exist")
	if source == null or carrier == null:
		return
	var carrier_inventory: Variant = carrier.get("backpack_inventory")
	var before_count := int(carrier_inventory.call("item_count", 48))
	var source_inventory: Variant = source.get("backpack_inventory")
	var before_source_count := int(source_inventory.call("item_count", 48))
	var before_behavior := int(carrier.get("behavior_state"))
	var before_pickup_count := (main.mission_pickups as Array).size()
	main.call("select_only", source)
	main.set("selected_backpack_item_id", 48)
	_expect(
		bool(main.call("drop_selected_item_at", carrier.position)),
		"selected actor accepts exact backpack-item placement order",
	)
	_expect(
		(main.mission_pickups as Array).size() == before_pickup_count,
		"ground pickup is not created before the actor arrives",
	)
	_expect(
		int(source_inventory.call("item_count", 48)) == before_source_count,
		"ordered item stays in the source backpack while pathing",
	)
	var pending_session: Dictionary = GAME_SESSION_STATE.capture(main)
	var pending_record := (
		(pending_session.get("world", {}) as Dictionary).get(
			"pending_item_drop_command",
			{},
		) as Dictionary
	)
	_expect(
		int(pending_record.get("actor_scene_index", -1)) == 1589
		and int(pending_record.get("item_id", 0)) == 48,
		"save captures the original pending item-drop command",
	)
	main.switch_level(10)
	await process_frame
	var restore_result: Dictionary = (
		GAME_SESSION_STATE.apply_after_level_loaded(main, pending_session)
	)
	source = _actor_by_scene(main.units as Array, 1589)
	carrier = null
	for enemy_value: Variant in main.enemies as Array:
		var enemy := enemy_value as Node2D
		var inventory: Variant = enemy.get("backpack_inventory")
		if (
			inventory != null
			and LEGACY_WORLD_ITEM_RULES.accepts_item(
				int(enemy.get("runtime_actor_type")),
				48,
				int(enemy.get("faction_id")),
			)
		):
			carrier = enemy
			break
	source_inventory = source.get("backpack_inventory")
	carrier_inventory = carrier.get("backpack_inventory")
	_expect(
		bool(restore_result.get("ok", false))
		and main.get("original_drop_order_actor") == source
		and int(main.get("original_drop_order_item_id")) == 48,
		"load restores the actor route and exact pending item identity",
	)
	var drop_destination := main.get(
		"original_drop_order_destination"
	) as Vector2
	main.legacy_crt_random_trace_enabled = true
	main.legacy_crt_random_trace.clear()
	source.position = drop_destination
	source.call("cancel_path")
	main.call("_advance_original_drop_order")
	var drop_sites: Array[int] = []
	for draw: Dictionary in main.legacy_crt_random_trace:
		drop_sites.append(int(draw.get("call_site_rva", 0)))
	_expect(
		(main.mission_pickups as Array).size() == before_pickup_count + 1,
		"ground pickup is created when the actor reaches the destination",
	)
	_expect(
		int(source_inventory.call("item_count", 48)) == before_source_count - 1,
		"arrival consumes exactly one source backpack item",
	)
	_expect(
		int(carrier.get("behavior_state")) == before_behavior,
		"drop does not broadcast a synthetic 640-pixel hearing alert",
	)
	var dropped_pickup := (
		main.mission_pickups as Array
	)[before_pickup_count] as Node2D
	_expect(
		bool(dropped_pickup.get("original_dynamic_actor_lifecycle"))
		and bool(dropped_pickup.get("original_factory_random_consumed"))
		and drop_sites == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x0005BBBC,
		],
		"manual drop creates the item actor through the exact five-draw factory",
	)
	_expect(
		bool(
			carrier.call(
				"_begin_legacy_world_item_investigation",
				dropped_pickup,
			)
		),
		"eligible enemy begins original world-item route",
	)
	main.legacy_crt_random_trace.clear()
	carrier.call("_update_legacy_world_item_investigation", 0.0)
	var pickup_sites: Array[int] = []
	for draw: Dictionary in main.legacy_crt_random_trace:
		pickup_sites.append(int(draw.get("call_site_rva", 0)))
	_expect(
		(main.mission_pickups as Array).is_empty()
		and pickup_sites == [
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"enemy pickup retires the world-item actor through the exact four-draw destructor without retaining a freed reference",
	)
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
	var expected_item_entries := loot_inventory.call("ordered_entries") as Array
	var expected_weapon_entries := (
		loot_source.call("parity_inventory_snapshot").get(
			"weapon_entries",
			[],
		) as Array
	)
	var expected_entries: Array[Dictionary] = []
	for item_entry_value: Variant in expected_item_entries:
		var item_entry := (item_entry_value as Dictionary).duplicate(true)
		item_entry["original_inventory_kind"] = "backpack"
		expected_entries.append(item_entry)
	for weapon_entry_value: Variant in expected_weapon_entries:
		var weapon_entry := (weapon_entry_value as Dictionary).duplicate(true)
		weapon_entry["original_inventory_kind"] = "weapon"
		expected_entries.append(weapon_entry)
	var before_pickups := (main.mission_pickups as Array).size()
	main.call("_spawn_original_inventory_drops", loot_source)
	_expect(
		(main.mission_pickups as Array).size()
			== before_pickups + expected_entries.size(),
		"death creates one ordered pickup per original container entry",
	)
	_expect(
		(loot_inventory.call("ordered_entries") as Array).is_empty(),
		"death clears the source backpack",
	)
	_expect(
		(
			loot_source.call("parity_inventory_snapshot").get(
				"weapon_entries",
				[],
			) as Array
		).is_empty(),
		"death clears the source weapon container",
	)
	for expected_index: int in range(expected_entries.size()):
		var pickup := (
			main.mission_pickups as Array
		)[before_pickups + expected_index] as Node
		var payload := pickup.get("item_payload") as Dictionary
		var expected := expected_entries[expected_index]
		_expect(
			str(payload.get("original_inventory_kind", ""))
				== str(expected.get("original_inventory_kind", "")),
			"death pickup preserves original container kind",
		)
		_expect(
			int(payload.get("item_id", 0)) == int(expected.get("item_id", 0)),
			"death pickup preserves original item ID and order",
		)
		_expect(
			int(payload.get("quantity", -1))
				== int(expected.get("quantity", -2)),
			"death pickup preserves original quantity",
		)
		_expect(
			int(payload.get("quantity_mode", -1))
				== int(expected.get("quantity_mode", -2)),
			"death pickup preserves original quantity mode",
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
