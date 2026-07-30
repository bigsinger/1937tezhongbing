extends SceneTree

const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const RULES: Script = preload("res://scripts/legacy_corpse_discovery_rules.gd")


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
var discovery_signal_count := 0


func _init() -> void:
	_test_outer_band_los_and_candidate_flags()
	_test_insertion_order_single_claim_and_priority()
	_test_reaction_counter_and_snapshot()
	_test_reinforcement_constants()
	if failures.is_empty():
		print("Legacy corpse-discovery tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_outer_band_los_and_candidate_flags() -> void:
	var navigation := FakeNavigation.new()
	var observer = _enemy(10, Vector2.ZERO, true, navigation)
	var corpse = _enemy(11, Vector2(400, 0), false, navigation)
	_expect(
		observer.can_discover_legacy_corpse(corpse),
		"dead faction-1 actor in directional outer band is discoverable",
	)
	corpse.position = Vector2(100, 0)
	_expect(
		not observer.can_discover_legacy_corpse(corpse),
		"inner visibility band is not the corpse-discovery band",
	)
	corpse.position = Vector2(400, 0)
	navigation.line_of_sight = false
	_expect(
		not observer.can_discover_legacy_corpse(corpse),
		"corpse discovery requires unobstructed LOS",
	)
	navigation.line_of_sight = true
	observer.original_direction_index = 7
	_expect(
		not observer.can_discover_legacy_corpse(corpse),
		"corpse scan follows the observer's current direction",
	)
	observer.original_direction_index = 3
	corpse.legacy_corpse_discovered = true
	_expect(
		not observer.can_discover_legacy_corpse(corpse),
		"claimed corpse cannot be discovered twice",
	)
	corpse.legacy_corpse_discovered = false
	corpse.legacy_corpse_buried = true
	_expect(
		not observer.can_discover_legacy_corpse(corpse),
		"buried corpse is excluded",
	)
	observer.free()
	corpse.free()


func _test_insertion_order_single_claim_and_priority() -> void:
	var navigation := FakeNavigation.new()
	var observer = _enemy(20, Vector2.ZERO, true, navigation)
	var other_observer = _enemy(21, Vector2.ZERO, true, navigation)
	var first = _enemy(22, Vector2(420, 0), false, navigation)
	var nearer_second = _enemy(23, Vector2(350, 0), false, navigation)
	observer.set_potential_corpses([first, nearer_second])
	other_observer.set_potential_corpses([first, nearer_second])
	_expect(
		observer.call("_first_visible_legacy_corpse") == first,
		"corpse scanner preserves world insertion order instead of nearest",
	)
	observer.legacy_corpse_discovery_triggered.connect(_on_discovery_signal)
	_expect(
		observer.call("_begin_legacy_corpse_discovery", first),
		"first observer enters recovered corpse contact state",
	)
	_expect(
		first.legacy_corpse_discovered
		and observer.behavior_state
			== ENEMY_UNIT.BehaviorState.CORPSE_DISCOVERY,
		"discovery atomically claims corpse and enters state 3 equivalent",
	)
	_expect(
		discovery_signal_count == 1,
		"corpse discovery raises exactly one reinforcement request",
	)
	_expect(
		not other_observer.can_discover_legacy_corpse(first),
		"second observer loses the already claimed corpse",
	)

	var priority_observer = _enemy(24, Vector2.ZERO, true, navigation)
	var priority_corpse = _enemy(25, Vector2(400, 0), false, navigation)
	var item = _pickup(48, Vector2(100, 0))
	priority_observer.runtime_actor_type = 5
	priority_observer.set_potential_corpses([priority_corpse])
	priority_observer.set_potential_world_items([item])
	priority_observer.call("_update_detection")
	_expect(
		priority_observer.legacy_corpse_target == priority_corpse
		and priority_observer.legacy_world_item_target == null,
		"corpse discovery has priority over an eligible world item",
	)
	observer.free()
	other_observer.free()
	first.free()
	nearer_second.free()
	priority_observer.free()
	priority_corpse.free()
	item.free()


func _test_reaction_counter_and_snapshot() -> void:
	var navigation := FakeNavigation.new()
	var observer = _enemy(30, Vector2.ZERO, true, navigation)
	var corpse = _enemy(31, Vector2(400, 0), false, navigation)
	observer.call("_begin_legacy_corpse_discovery", corpse)
	# The recovered reaction counter starts only after the observer arrives.
	observer.cancel_path()
	observer.legacy_corpse_reaction_limit = 40
	observer.call(
		"_update_legacy_corpse_discovery",
		40.0 * ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS,
	)
	_expect(
		observer.behavior_state
			== ENEMY_UNIT.BehaviorState.CORPSE_DISCOVERY,
		"corpse reaction remains active through its exact limit",
	)
	observer.call(
		"_update_legacy_corpse_discovery",
		ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS * 1.01,
	)
	_expect(
		observer.behavior_state == ENEMY_UNIT.BehaviorState.SEARCH
		and observer.legacy_search_active
		and observer.last_known_target_position == corpse.position,
		"corpse reaction enters recovered five-point coordinate search when counter exceeds the limit",
	)
	observer.legacy_corpse_discovered = true
	observer.legacy_corpse_buried = false
	observer.legacy_reinforcement_spawned = true
	observer.legacy_reinforcement_source_marker_scene_index = 1505
	observer.legacy_reinforcement_serial = 2
	var state: Dictionary = observer.legacy_corpse_state_snapshot()
	var restored = _enemy(32, Vector2.ZERO, true, navigation)
	_expect(
		restored.restore_legacy_corpse_state(state),
		"corpse/reinforcement state restores",
	)
	_expect(
		restored.legacy_corpse_discovered
		and restored.legacy_reinforcement_spawned
		and restored.legacy_reinforcement_source_marker_scene_index == 1505
		and restored.legacy_reinforcement_serial == 2,
		"claim and dynamic reinforcement identity survive save/load",
	)
	observer.free()
	corpse.free()
	restored.free()


func _test_reinforcement_constants() -> void:
	_expect(
		RULES.REQUIRED_VISIBILITY_BAND == 2,
		"recovered corpse visibility band is fixed to 2",
	)
	_expect(
		RULES.REINFORCEMENT_MARKER_ACTOR_TYPE == 93
		and RULES.REINFORCEMENT_ACTOR_TYPE == 6
		and RULES.REINFORCEMENT_COUNT == 2,
		"corpse alarm uses type-93 marker and two type-6 soldiers",
	)
	var sampled: Dictionary = RULES.reaction_limit_from_state(0x1937)
	_expect(
		int(sampled.get("limit", 0)) in range(40, 80),
		"MSVC random corpse reaction limit remains in 40..79",
	)


func _on_discovery_signal(
	_unused_observer: ENEMY_UNIT,
	_unused_corpse: ENEMY_UNIT,
) -> void:
	discovery_signal_count += 1


func _enemy(
	scene_index: int,
	world_position: Vector2,
	alive: bool,
	navigation: RefCounted,
):
	var enemy = ENEMY_UNIT.new()
	enemy.faction_id = 1
	enemy.runtime_actor_type = 6
	enemy.scene_index = scene_index
	enemy.is_alive = alive
	enemy.current_hit_points = 8 if alive else 0
	enemy.maximum_hit_points = 8
	enemy.position = world_position
	enemy.original_direction_index = 3
	enemy.sense_profile = {
		"horizontal_radius": 640.0,
		"vertical_radius": 320.0,
		"near_band_ratio": 0.5,
		"requires_line_of_sight": true,
	}
	enemy.dynamic_occupancy = navigation
	return enemy


func _pickup(item_id: int, world_position: Vector2):
	var pickup = MISSION_PICKUP.new()
	pickup.configure(
		{
			"original_inventory_kind": "backpack",
			"item_id": item_id,
			"quantity": 1,
			"quantity_mode": 0,
			"world_item_serial": 1,
		},
		world_position,
	)
	return pickup


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
