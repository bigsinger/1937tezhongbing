extends SceneTree

const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const RULES: Script = preload("res://scripts/legacy_world_item_rules.gd")


class FakeNavigation:
	extends RefCounted

	var line_of_sight := true

	func has_line_of_sight(
		_unused_start: Vector2,
		_unused_end: Vector2,
		_unused_ignored: Array = [],
	) -> bool:
		return line_of_sight

	func find_path_for_scene(
		_unused_scene_index: int,
		start: Vector2,
		end: Vector2,
	) -> PackedVector2Array:
		return PackedVector2Array([start, end])

	func release_goal(_unused_scene_index: int) -> void:
		pass


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_exact_acceptance_matrix()
	_test_directional_inner_band_and_los()
	_test_first_actor_in_insertion_order()
	_test_exact_effect_counters()
	_test_snapshot_round_trip()
	if failures.is_empty():
		print("Legacy world-item tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_exact_acceptance_matrix() -> void:
	_expect(RULES.accepted_item_ids(4) == [52], "type 4 accepts only poison")
	_expect(
		RULES.accepted_item_ids(5) == [52, 33, 83, 48, 49],
		"type 5 preserves executable insertion order",
	)
	_expect(
		RULES.accepted_item_ids(6) == [52, 83, 48, 49],
		"type 6 excludes chicken",
	)
	_expect(
		RULES.accepted_item_ids(11) == [52, 83, 49],
		"type 11 excludes canned meat and chicken",
	)
	_expect(
		RULES.accepted_item_ids(15) == [52, 83, 48],
		"type 15 excludes the hypnosis doll",
	)
	_expect(RULES.accepted_item_ids(56) == [82], "dog accepts only dog bone")
	_expect(RULES.accepted_item_ids(999).is_empty(), "unknown actor accepts none")
	_expect(
		RULES.accepted_item_ids(5, 3).is_empty(),
		"non-enemy faction receives no lure list",
	)
	_expect(
		RULES.is_adjacent_navigation_cell(Vector2.ZERO, Vector2(63, 31)),
		"32x16 interaction accepts one-cell diagonal adjacency",
	)
	_expect(
		not RULES.is_adjacent_navigation_cell(Vector2.ZERO, Vector2(64, 32)),
		"32x16 interaction rejects a two-cell offset",
	)


func _test_directional_inner_band_and_los() -> void:
	var navigation := FakeNavigation.new()
	var enemy = _enemy(5, navigation)
	var near_item = _pickup(48, Vector2(100, 0), 1)
	var far_item = _pickup(48, Vector2(400, 0), 2)
	_expect(
		enemy.can_consider_legacy_world_item(near_item),
		"allowed item is visible in facing inner band",
	)
	_expect(
		not enemy.can_consider_legacy_world_item(far_item),
		"outer visibility band does not attract an enemy",
	)
	navigation.line_of_sight = false
	_expect(
		not enemy.can_consider_legacy_world_item(near_item),
		"world item attraction requires unobstructed LOS",
	)
	navigation.line_of_sight = true
	enemy.original_direction_index = 7
	_expect(
		not enemy.can_consider_legacy_world_item(near_item),
		"world item attraction follows current enemy direction",
	)
	enemy.original_direction_index = 3
	var disallowed = _pickup(82, Vector2(100, 0), 3)
	_expect(
		not enemy.can_consider_legacy_world_item(disallowed),
		"runtime-type list rejects an otherwise visible item",
	)
	enemy.free()
	near_item.free()
	far_item.free()
	disallowed.free()


func _test_first_actor_in_insertion_order() -> void:
	var navigation := FakeNavigation.new()
	var enemy = _enemy(5, navigation)
	var first = _pickup(48, Vector2(140, 0), 11)
	var second = _pickup(48, Vector2(80, 0), 12)
	enemy.set_potential_world_items([first, second])
	_expect(
		enemy.call("_first_visible_allowed_world_item") == first,
		"scanner returns first eligible actor instead of nearest actor",
	)
	enemy.free()
	first.free()
	second.free()


func _test_exact_effect_counters() -> void:
	var enemy = _enemy(5, FakeNavigation.new())
	var hypnosis: Dictionary = enemy.apply_legacy_world_item_effect(49)
	_expect(
		bool(hypnosis.get("consume_after_collection", false)),
		"hypnosis doll is force-consumed",
	)
	enemy.advance_legacy_world_item_effect_ticks(600)
	_expect(enemy.legacy_hypnosis_active, "hypnosis remains through tick 600")
	var hypnosis_finish: Dictionary = (
		enemy.advance_legacy_world_item_effect_ticks(1)
	)
	_expect(
		not enemy.legacy_hypnosis_active
		and bool(hypnosis_finish.get("hypnosis_finished", false)),
		"hypnosis clears on tick 601",
	)

	var distraction: Dictionary = enemy.apply_legacy_world_item_effect(83, 80)
	_expect(
		not bool(distraction.get("consume_after_collection", true)),
		"cigarette remains in carried inventory",
	)
	enemy.advance_legacy_world_item_effect_ticks(80)
	_expect(
		enemy.legacy_distraction_active,
		"distraction remains through its exact limit",
	)
	enemy.advance_legacy_world_item_effect_ticks(1)
	_expect(
		not enemy.legacy_distraction_active,
		"distraction clears when counter exceeds the limit",
	)

	enemy.current_hit_points = 32
	enemy.maximum_hit_points = 32
	var poison: Dictionary = enemy.apply_legacy_world_item_effect(52, 80)
	_expect(
		bool(poison.get("consume_after_collection", false)),
		"poisoned wine is force-consumed",
	)
	enemy.advance_legacy_world_item_effect_ticks(80)
	_expect(enemy.current_hit_points == 32, "poison does no damage through tick 80")
	var poison_hit: Dictionary = enemy.advance_legacy_world_item_effect_ticks(1)
	_expect(
		enemy.current_hit_points == 16
		and int(poison_hit.get("poison_damage", 0)) == 16,
		"poison applies exact 16 damage on tick 81",
	)
	_expect(
		enemy.legacy_distraction_counter == 0,
		"poison branch prevents ordinary distraction counter advance",
	)
	enemy.free()


func _test_snapshot_round_trip() -> void:
	var source = _enemy(5, FakeNavigation.new())
	source.apply_legacy_world_item_effect(83, 99)
	source.advance_legacy_world_item_effect_ticks(17)
	var state: Dictionary = source.legacy_world_item_state_snapshot()
	var restored = _enemy(5, FakeNavigation.new())
	_expect(
		restored.restore_legacy_world_item_state(state),
		"legacy item state restores",
	)
	_expect(
		restored.legacy_distraction_active
		and restored.legacy_distraction_counter == 17
		and restored.legacy_distraction_limit == 99,
		"distraction counter and sampled limit survive save/load",
	)
	source.free()
	restored.free()


func _enemy(runtime_type: int, navigation: RefCounted):
	var enemy = ENEMY_UNIT.new()
	enemy.faction_id = 1
	enemy.runtime_actor_type = runtime_type
	enemy.scene_index = 700 + runtime_type
	enemy.is_alive = true
	enemy.current_hit_points = 8
	enemy.maximum_hit_points = 8
	enemy.position = Vector2.ZERO
	enemy.original_direction_index = 3
	enemy.sense_profile = {
		"horizontal_radius": 640.0,
		"vertical_radius": 320.0,
		"near_band_ratio": 0.5,
		"requires_line_of_sight": true,
	}
	enemy.dynamic_occupancy = navigation
	return enemy


func _pickup(item_id: int, world_position: Vector2, serial: int):
	var pickup = MISSION_PICKUP.new()
	pickup.configure(
		{
			"original_inventory_kind": "backpack",
			"item_id": item_id,
			"quantity": 1,
			"quantity_mode": 0,
			"world_item_serial": serial,
		},
		world_position,
	)
	return pickup


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
