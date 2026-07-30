extends SceneTree

const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const MAIN: Script = preload("res://scripts/main.gd")
const RULES: Script = preload("res://scripts/legacy_enemy_ai_rules.gd")


class FakeNavigation:
	extends RefCounted

	var dimensions := Vector2i(100, 100)
	var cell_size := Vector2i(32, 16)
	var last_path_endpoint := Vector2.ZERO
	var path_request_count := 0

	func find_path_for_scene(
		_unused_scene_index: int,
		start: Vector2,
		end: Vector2,
	) -> PackedVector2Array:
		last_path_endpoint = end
		path_request_count += 1
		return PackedVector2Array([start, end])

	func release_goal(_unused_scene_index: int) -> void:
		pass


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_exact_alert_geometry_and_eligibility()
	_test_coordinate_search_lifecycle_and_snapshot()
	_test_original_coordinate_broadcast()
	if failures.is_empty():
		print("Legacy enemy-AI tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_exact_alert_geometry_and_eligibility() -> void:
	_expect(
		RULES.is_within_alert_ellipse(
			Vector2.ZERO,
			Vector2(639.0, 0.0),
			640.0,
		),
		"coordinate alert includes the horizontal interior",
	)
	_expect(
		not RULES.is_within_alert_ellipse(
			Vector2.ZERO,
			Vector2(640.0, 0.0),
			640.0,
		),
		"coordinate alert excludes the strict horizontal boundary",
	)
	_expect(
		RULES.is_within_alert_ellipse(
			Vector2.ZERO,
			Vector2(0.0, 319.0),
			640.0,
		),
		"coordinate alert includes the vertical interior",
	)
	_expect(
		not RULES.is_within_alert_ellipse(
			Vector2.ZERO,
			Vector2(0.0, 320.0),
			640.0,
		),
		"coordinate alert excludes the strict vertical boundary",
	)
	_expect(
		RULES.is_within_alert_ellipse(
			Vector2.ZERO,
			Vector2(320.0, 320.0),
			640.0,
		),
		"coordinate alert uses sub_45A7C0's parametric directional boundary",
	)
	_expect(
		RULES.alert_recipient_is_eligible(1, 6, true, false),
		"living faction-1 actor without contact accepts coordinate alert",
	)
	_expect(
		not RULES.alert_recipient_is_eligible(1, 91, true, false)
		and not RULES.alert_recipient_is_eligible(2, 6, true, false)
		and not RULES.alert_recipient_is_eligible(1, 6, false, false)
		and not RULES.alert_recipient_is_eligible(1, 6, true, true),
		"type-91, other-faction, dead and live-contact actors are excluded",
	)
	_expect(
		not RULES.counter_has_completed(40, 40)
		and RULES.counter_has_completed(41, 40),
		"reaction and search counters use the recovered strict greater-than transition",
	)

	var minimum_reaction := 1000
	var maximum_reaction := -1
	var minimum_wait := 1000
	var maximum_wait := -1
	var state := 0x1937
	for sample_index in range(512):
		var reaction: Dictionary = RULES.reaction_limit_from_state(
			state + sample_index
		)
		minimum_reaction = mini(
			minimum_reaction,
			int(reaction.get("limit", -1)),
		)
		maximum_reaction = maxi(
			maximum_reaction,
			int(reaction.get("limit", -1)),
		)
		var search: Dictionary = RULES.local_search_point_from_state(
			int(reaction.get("state", 1)),
			Vector2(500.0, 500.0),
			Rect2(Vector2.ZERO, Vector2(3200.0, 1600.0)),
		)
		var point := search.get("point", Vector2.ZERO) as Vector2
		var offset := point - Vector2(500.0, 500.0)
		_expect(
			absf(offset.x) <= 31.0 and absf(offset.y) <= 15.0,
			"local-search point remains inside the recovered ±31×±15 offset",
		)
		minimum_wait = mini(
			minimum_wait,
			int(search.get("next_wait_limit", -1)),
		)
		maximum_wait = maxi(
			maximum_wait,
			int(search.get("next_wait_limit", -1)),
		)
	_expect(
		minimum_reaction >= 40 and maximum_reaction <= 79,
		"reaction random limit remains in 40..79",
	)
	_expect(
		minimum_wait >= 40 and maximum_wait <= 199,
		"local-search random wait remains in 40..199",
	)
	var edge_sample: Dictionary = RULES.local_search_point_from_state(
		1,
		Vector2.ZERO,
		Rect2(Vector2.ZERO, Vector2(3200.0, 1600.0)),
	)
	var edge_point := edge_sample.get("point", Vector2.ZERO) as Vector2
	_expect(
		edge_point.x >= 16.0 and edge_point.y >= 16.0,
		"local-search point is clamped sixteen pixels inside the world",
	)


func _test_coordinate_search_lifecycle_and_snapshot() -> void:
	var navigation := FakeNavigation.new()
	var enemy = _enemy(10, Vector2(500.0, 500.0), navigation)
	var alert_position := Vector2(620.0, 460.0)
	_expect(
		enemy.receive_original_coordinate_alert(alert_position),
		"eligible enemy accepts an original coordinate alert",
	)
	_expect(
		enemy.current_target == null
		and enemy.behavior_state == ENEMY_UNIT.BehaviorState.SEARCH
		and enemy.legacy_search_active
		and enemy.last_known_target_position == alert_position
		and navigation.last_path_endpoint == alert_position,
		"coordinate alert preserves no live target and routes to the supplied coordinate",
	)
	enemy.cancel_path()
	enemy.legacy_search_wait_limit = 2
	enemy.legacy_search_wait_counter = 2
	enemy.call(
		"_update_legacy_coordinate_search",
		ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS * 1.01,
	)
	_expect(
		enemy.legacy_search_point_index == 1
		and navigation.path_request_count == 2,
		"strict counter completion issues the first local-search point",
	)
	_expect(
		absf(navigation.last_path_endpoint.x - enemy.position.x) <= 31.0
		and absf(navigation.last_path_endpoint.y - enemy.position.y) <= 15.0,
		"issued local-search route uses recovered isometric offset",
	)

	var snapshot: Dictionary = enemy.legacy_enemy_ai_state_snapshot()
	var restored = _enemy(11, enemy.position, navigation)
	restored.behavior_state = ENEMY_UNIT.BehaviorState.SEARCH
	restored.last_known_target_position = enemy.last_known_target_position
	_expect(
		restored.restore_legacy_enemy_ai_state(snapshot)
		and restored.legacy_search_point_index == 1
		and restored.legacy_search_active,
		"local-search counter, point and random state restore from save data",
	)
	var requests_before_resume := navigation.path_request_count
	_expect(
		restored.resume_restored_legacy_search()
		and navigation.path_request_count == requests_before_resume + 1,
		"restored local search resumes its pending coordinate route",
	)

	for unused_index in range(4):
		enemy.cancel_path()
		enemy.legacy_search_wait_counter = enemy.legacy_search_wait_limit
		enemy.call(
			"_update_legacy_coordinate_search",
			ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS * 1.01,
		)
	_expect(
		enemy.legacy_search_point_index == RULES.SEARCH_POINT_COUNT
		and not enemy.legacy_search_active
		and enemy.legacy_search_finishing,
		"fifth local-search coordinate ends generation but keeps its route alive",
	)
	enemy.cancel_path()
	enemy.call("_update_legacy_coordinate_search", 0.0)
	_expect(
		enemy.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
		and not enemy.legacy_search_finishing,
		"enemy returns to patrol only after the fifth route completes",
	)

	var busy = _enemy(12, Vector2.ZERO, navigation)
	busy.current_target = enemy
	busy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
	_expect(
		not busy.receive_original_coordinate_alert(Vector2(100.0, 50.0))
		and busy.current_target == enemy
		and busy.behavior_state == ENEMY_UNIT.BehaviorState.CHASE,
		"unlost live contact is not replaced by a coordinate alert",
	)
	enemy.free()
	restored.free()
	busy.free()


func _test_original_coordinate_broadcast() -> void:
	var navigation := FakeNavigation.new()
	var source = _enemy(20, Vector2(1000.0, 500.0), navigation)
	source.faction_id = 3
	var horizontal_inside = _enemy(
		21,
		source.position + Vector2(639.0, 0.0),
		navigation,
	)
	var horizontal_boundary = _enemy(
		22,
		source.position + Vector2(640.0, 0.0),
		navigation,
	)
	var vertical_inside = _enemy(
		23,
		source.position + Vector2(0.0, 319.0),
		navigation,
	)
	var vertical_boundary = _enemy(
		24,
		source.position + Vector2(0.0, 320.0),
		navigation,
	)
	var excluded_type = _enemy(
		25,
		source.position + Vector2(20.0, 0.0),
		navigation,
	)
	excluded_type.runtime_actor_type = 91
	var dead = _enemy(
		26,
		source.position + Vector2(40.0, 0.0),
		navigation,
	)
	dead.is_alive = false
	var busy = _enemy(
		27,
		source.position + Vector2(60.0, 0.0),
		navigation,
	)
	busy.current_target = source
	busy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
	var recipients: Array = [
		horizontal_inside,
		horizontal_boundary,
		vertical_inside,
		vertical_boundary,
		excluded_type,
		dead,
		busy,
	]
	var main = MAIN.new()
	for recipient: ENEMY_UNIT in recipients:
		main.enemies.append(recipient)
	var alerted_count: int = main.call(
		"_queue_or_broadcast_alert",
		source,
		null,
		source.position,
		640.0,
		true,
	)
	_expect(
		alerted_count == 2
		and horizontal_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.SEARCH
		and vertical_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.SEARCH,
		"original gunshot broadcast selects only strict-ellipse eligible recipients",
	)
	_expect(
		horizontal_inside.current_target == null
		and vertical_inside.current_target == null
		and horizontal_inside.last_known_target_position == source.position
		and vertical_inside.last_known_target_position == source.position,
		"broadcast writes the source coordinate without assigning a target pointer",
	)
	_expect(
		horizontal_boundary.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL
		and vertical_boundary.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL
		and excluded_type.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL
		and dead.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
		and busy.behavior_state == ENEMY_UNIT.BehaviorState.CHASE,
		"boundary, type-91, dead and live-contact actors keep their prior state",
	)
	main.free()
	source.free()
	for recipient: ENEMY_UNIT in recipients:
		recipient.free()


func _enemy(
	scene_index: int,
	world_position: Vector2,
	navigation: RefCounted,
):
	var enemy = ENEMY_UNIT.new()
	enemy.faction_id = 1
	enemy.runtime_actor_type = 6
	enemy.scene_index = scene_index
	enemy.is_alive = true
	enemy.current_hit_points = 8
	enemy.maximum_hit_points = 8
	enemy.position = world_position
	enemy.dynamic_occupancy = navigation
	enemy.legacy_search_random_state = maxi(scene_index * 1937, 1)
	return enemy


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
