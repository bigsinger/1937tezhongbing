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


class UnavailableWorldItem:
	extends Node2D

	var original_actor_type := 19
	var world_item_serial := 1937

	func is_available_original_world_item() -> bool:
		return false


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_exact_alert_geometry_and_eligibility()
	_test_coordinate_search_lifecycle_and_snapshot()
	_test_original_coordinate_broadcast()
	_test_remaining_original_update_random_branches()
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
	var enabled_secondary_types: Array[int] = []
	for runtime_type: int in range(100):
		if RULES.secondary_search_runtime_type_enabled(runtime_type):
			enabled_secondary_types.append(runtime_type)
	_expect(
		enabled_secondary_types == [16, 20, 25, 27, 28, 29],
		"sub_454960 dispatches exactly six runtime types to secondary search",
	)
	_expect(
		RULES.secondary_search_candidate_is_eligible(1, true)
		and not RULES.secondary_search_candidate_is_eligible(2, true)
		and not RULES.secondary_search_candidate_is_eligible(1, false),
		"secondary search accepts only living faction-1 actors",
	)
	_expect(
		RULES.is_within_secondary_search_radius(
			Vector2.ZERO,
			Vector2(127.0, 0.0),
		)
		and not RULES.is_within_secondary_search_radius(
			Vector2.ZERO,
			Vector2(128.0, 0.0),
		),
		"sub_45DCE0 uses a strict 128-pixel candidate boundary",
	)
	var secondary_bounds := Rect2(
		Vector2.ZERO,
		Vector2(1000.0, 500.0),
	)
	var secondary_positive_values: Array[int] = [0, 0, 0, 0]
	var secondary_negative_values: Array[int] = [0, 0, 1, 1]
	_expect(
		RULES.secondary_search_point_from_values(
			secondary_positive_values,
			Vector2(100.0, 100.0),
			secondary_bounds,
		) == Vector2(164.0, 132.0)
		and RULES.secondary_search_point_from_values(
			secondary_negative_values,
			Vector2(100.0, 100.0),
			secondary_bounds,
		) == Vector2(36.0, 68.0),
		"secondary destination uses recovered +64/+32 magnitudes and sign draws",
	)
	_expect(
		RULES.secondary_search_point_from_values(
			secondary_negative_values,
			Vector2(70.0, 50.0),
			secondary_bounds,
		) == Vector2(6.0, 18.0)
		and RULES.secondary_search_point_from_values(
			secondary_negative_values,
			Vector2(10.0, 10.0),
			secondary_bounds,
		) == Vector2(16.0, 16.0)
		and RULES.secondary_search_point_from_values(
			secondary_positive_values,
			Vector2(950.0, 480.0),
			secondary_bounds,
		) == Vector2(984.0, 484.0),
		"secondary destination clamps only after crossing a world edge",
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
	var command_serial_before_alert: int = enemy.original_actor_command_serial
	_expect(
		enemy.receive_original_coordinate_alert(alert_position),
		"eligible enemy accepts an original coordinate alert",
	)
	_expect(
		enemy.pending_original_coordinate_alert_active
		and enemy.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
		and not enemy.legacy_search_active
		and navigation.path_request_count == 0,
		"coordinate alert remains pending until the recipient command pass",
	)
	_expect(
		bool(enemy.call(
			"_consume_pending_original_coordinate_alert",
			command_serial_before_alert,
		))
		and enemy.current_target == null
		and enemy.behavior_state == ENEMY_UNIT.BehaviorState.SEARCH
		and enemy.legacy_search_active
		and enemy.last_known_target_position == alert_position
		and navigation.last_path_endpoint == alert_position,
		"recipient command pass preserves no live target and routes to the supplied coordinate",
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
	var pending = _enemy(13, Vector2(300.0, 200.0), navigation)
	var pending_position := Vector2(420.0, 260.0)
	var pending_serial: int = pending.original_actor_command_serial
	pending.receive_original_coordinate_alert(pending_position)
	var pending_snapshot: Dictionary = pending.legacy_enemy_ai_state_snapshot()
	var restored_pending = _enemy(14, pending.position, navigation)
	_expect(
		restored_pending.restore_legacy_enemy_ai_state(pending_snapshot)
		and restored_pending.pending_original_coordinate_alert_active
		and restored_pending.pending_original_coordinate_alert_position
			== pending_position
		and bool(restored_pending.call(
			"_consume_pending_original_coordinate_alert",
			pending_serial,
		))
		and restored_pending.behavior_state
			== ENEMY_UNIT.BehaviorState.SEARCH,
		"in-flight native coordinate command survives save/load and resumes once",
	)
	enemy.free()
	restored.free()
	busy.free()
	pending.free()
	restored_pending.free()


func _test_original_coordinate_broadcast() -> void:
	var navigation := FakeNavigation.new()
	var source = _enemy(20, Vector2(1000.0, 500.0), navigation)
	source.faction_id = 3
	var horizontal_inside = _enemy(
		21,
		source.position + Vector2(639.0, 0.0),
		navigation,
	)
	horizontal_inside.legacy_search_wait_limit = 55
	horizontal_inside.legacy_search_wait_counter = 7
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
	vertical_inside.legacy_search_wait_limit = 61
	vertical_inside.legacy_search_wait_counter = 9
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
	main.legacy_crt_random_trace_enabled = true
	source.original_ai_idle_tick_counter = 12
	source.original_ai_idle_tick_limit = 40
	source.special_control_lock_count = 2
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
		and horizontal_inside.pending_original_coordinate_alert_active
		and vertical_inside.pending_original_coordinate_alert_active
		and horizontal_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL
		and vertical_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL,
		"original gunshot broadcast queues only strict-ellipse eligible recipients",
	)
	var horizontal_command_serial: int = (
		horizontal_inside.original_actor_command_serial
	)
	var vertical_command_serial: int = (
		vertical_inside.original_actor_command_serial
	)
	_expect(
		bool(horizontal_inside.call(
			"_consume_pending_original_coordinate_alert",
			horizontal_command_serial,
		))
		and bool(vertical_inside.call(
			"_consume_pending_original_coordinate_alert",
			vertical_command_serial,
		))
		and horizontal_inside.current_target == null
		and vertical_inside.current_target == null
		and horizontal_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.SEARCH
		and vertical_inside.behavior_state
			== ENEMY_UNIT.BehaviorState.SEARCH
		and horizontal_inside.last_known_target_position == source.position
		and vertical_inside.last_known_target_position == source.position,
		"recipient command pass consumes source coordinates without assigning target pointers",
	)
	var reaction_sites_match: bool = (
		main.legacy_crt_random_trace.size() == 2
	)
	for record: Dictionary in main.legacy_crt_random_trace:
		reaction_sites_match = (
			reaction_sites_match
			and int(record.get("call_site_rva", 0)) == 0x0005DF71
		)
	_expect(
		reaction_sites_match
		and main.legacy_crt_random_draw_index == 2
		and source.original_ai_idle_tick_counter == 0
		and source.original_ai_idle_tick_limit == 67
		and source.legacy_search_wait_counter == 0
		and source.legacy_search_wait_limit == 67
		and is_equal_approx(
			source.attack_recheck_seconds,
			67.0 * ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS,
		)
		and is_zero_approx(source.attack_recheck_elapsed)
		and source.special_control_lock_count == 0,
		"each accepted recipient consumes and schedules its source-side 40..79 reaction draw",
	)
	_expect(
		horizontal_inside.legacy_search_wait_limit == 55
		and horizontal_inside.legacy_search_wait_counter == 7
		and vertical_inside.legacy_search_wait_limit == 61
		and vertical_inside.legacy_search_wait_counter == 9,
		"coordinate alert does not invent a recipient-side reaction draw",
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
	var route_wins = _enemy(
		28,
		source.position + Vector2(80.0, 0.0),
		navigation,
	)
	var route_serial_before_alert: int = (
		route_wins.original_actor_command_serial
	)
	_expect(
		route_wins.receive_original_coordinate_alert(source.position),
		"patroller accepts an external coordinate command before its update",
	)
	route_wins.issue_path(PackedVector2Array([
		route_wins.position + Vector2(160.0, 80.0),
	]))
	_expect(
		not bool(route_wins.call(
			"_consume_pending_original_coordinate_alert",
			route_serial_before_alert,
		))
		and route_wins.behavior_state
			== ENEMY_UNIT.BehaviorState.PATROL
		and route_wins.target_position
			== route_wins.position + Vector2(160.0, 80.0),
		"newer authored patrol command wins same-tick alert arbitration",
	)
	main.free()
	source.free()
	route_wins.free()
	for recipient: ENEMY_UNIT in recipients:
		recipient.free()


func _test_remaining_original_update_random_branches() -> void:
	var navigation := FakeNavigation.new()

	var face_stream = MAIN.new()
	face_stream.legacy_crt_random_trace_enabled = true
	var face_enemy = _enemy(30, Vector2.ZERO, navigation)
	var face_target = _enemy(31, Vector2(100.0, 0.0), navigation)
	get_root().add_child(face_target)
	face_enemy.original_crt_random_source = face_stream
	face_enemy.original_runtime_index = 30
	face_enemy.current_target = face_target
	face_enemy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
	face_enemy.call(
		"_advance_original_tracked_target_face_gate",
		ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS * 3.01,
	)
	_expect(
		face_enemy.legacy_tracked_face_gate_serial == 3
		and face_enemy.legacy_tracked_face_gate_last_value == 6334
		and not face_enemy.legacy_tracked_face_gate_last_passed,
		"tracked-target facing gate consumes the exact 50-percent native sequence",
	)
	var face_sites_match: bool = (
		face_stream.legacy_crt_random_trace.size() == 3
	)
	for record: Dictionary in face_stream.legacy_crt_random_trace:
		face_sites_match = (
			face_sites_match
			and int(record.get("call_site_rva", 0)) == 0x0005CCCD
		)
	_expect(
		face_sites_match,
		"tracked-target facing draws remain attributed to native site 0x5CCCD",
	)
	var face_snapshot: Dictionary = face_enemy.legacy_enemy_ai_state_snapshot()
	var restored_face = _enemy(32, Vector2.ZERO, navigation)
	_expect(
		restored_face.restore_legacy_enemy_ai_state(face_snapshot)
		and restored_face.legacy_tracked_face_gate_serial == 3
		and restored_face.legacy_tracked_face_gate_last_value == 6334,
		"tracked-target facing cadence survives save restoration",
	)

	var search_stream = MAIN.new()
	search_stream.legacy_crt_random_trace_enabled = true
	var finished_search = _enemy(33, Vector2.ZERO, navigation)
	finished_search.original_crt_random_source = search_stream
	finished_search.original_runtime_index = 33
	finished_search.behavior_state = ENEMY_UNIT.BehaviorState.SEARCH
	finished_search.legacy_search_active = false
	finished_search.legacy_search_finishing = true
	finished_search.call("_update_legacy_coordinate_search", 0.0)
	_expect(
		finished_search.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
		and finished_search.legacy_idle_search_completion_serial == 1
		and finished_search.legacy_search_wait_counter == 0
		and finished_search.legacy_search_wait_limit == 41
		and search_stream.legacy_crt_random_trace.size() == 1
		and int(search_stream.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005C998,
		"fifth local-search completion consumes 0x5C998 and stores its next 40..79 delay",
	)

	var item_stream = MAIN.new()
	item_stream.legacy_crt_random_trace_enabled = true
	var item_enemy = _enemy(34, Vector2.ZERO, navigation)
	var unavailable_item := UnavailableWorldItem.new()
	item_enemy.original_crt_random_source = item_stream
	item_enemy.original_runtime_index = 34
	item_enemy.behavior_state = ENEMY_UNIT.BehaviorState.WORLD_ITEM
	item_enemy.legacy_world_item_target = unavailable_item
	item_enemy.legacy_search_wait_counter = 40
	item_enemy.legacy_search_wait_limit = 40
	item_enemy.call(
		"_update_legacy_world_item_investigation",
		ENEMY_UNIT.ORIGINAL_ATTACK_REACTION_TICK_SECONDS * 1.01,
	)
	_expect(
		item_enemy.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
		and item_enemy.legacy_world_item_abandon_serial == 1
		and not item_enemy.legacy_world_item_abandoning
		and item_enemy.legacy_search_wait_counter == 0
		and item_enemy.legacy_search_wait_limit == 21
		and item_stream.legacy_crt_random_trace.size() == 1
		and int(item_stream.legacy_crt_random_trace[0].get(
			"call_site_rva",
			0,
		)) == 0x0005CC69,
		"unavailable bait waits through the shared counter before consuming the native 20..59 return delay",
	)
	var item_snapshot: Dictionary = item_enemy.legacy_world_item_state_snapshot()
	var restored_item = _enemy(35, Vector2.ZERO, navigation)
	_expect(
		restored_item.restore_legacy_world_item_state(item_snapshot)
		and restored_item.legacy_world_item_abandon_serial == 1,
		"world-item abandonment serial survives save restoration",
	)

	face_stream.free()
	face_enemy.free()
	face_target.free()
	restored_face.free()
	search_stream.free()
	finished_search.free()
	item_stream.free()
	item_enemy.free()
	unavailable_item.free()
	restored_item.free()


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
