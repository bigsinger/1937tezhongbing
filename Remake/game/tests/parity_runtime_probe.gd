extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TRACE_SCRIPT: Script = preload("res://scripts/runtime_parity_trace.gd")

const OUTPUT_ARGUMENT_PREFIX := "--output-dir="
const MOVE_SPEED_ARGUMENT_PREFIX := "--move-speed="
const LEVEL_ARGUMENT_PREFIX := "--level-id="
const SCENARIO_ARGUMENT_PREFIX := "--scenario-id="
const OUTBOUND_ARGUMENT_PREFIX := "--outbound-target="
const RETURN_ARGUMENT_PREFIX := "--return-target="
const OBSERVATION_ARGUMENT_PREFIX := "--observation-seconds="
const PATROL_SETTLE_ARGUMENT_PREFIX := "--patrol-settle-seconds="
const PRIMARY_DATABASE_ENTRY_ID := 924
const MINE_PICKUP_SCENARIO_ID := "m001-mine-pickup-inventory-v1"
const PISTOL_ATTACK_SCENARIO_ID := "m000-pistol-attack-inventory-v1"
const M001_PLAYER_SCENE_INDEX := 2280
const M001_MINE_SCENE_INDEX := 2096
const M000_PLAYER_SCENE_INDEX := 1436
const M000_ATTACK_TARGET_SCENE_INDEX := 1598
const LAND_MINE_ITEM_ID := 43
const PISTOL_ITEM_ID := 36
## Layer-3-verified, obstacle-free cell centres: (1,3) and (5,3).
## The short observation window issues the return order before the first
## command can settle, so goal replacement and facing are both observable.
const OUTBOUND_TARGET := Vector2(48.0, 56.0)
const RETURN_TARGET := Vector2(176.0, 56.0)
const OBSERVATION_SECONDS := 0.75
## The reference trace records the first scene-1598 hit at the return-observed
## checkpoint and the second one at the settled checkpoint. Bound those event
## milestones by simulated physics ticks. A wall-clock SceneTreeTimer can expire
## after fewer physics ticks on a busy CI host and move an otherwise identical
## hit into the following checkpoint.
const NATURAL_CONTACT_FIRST_DAMAGE_DEADLINE_SECONDS := 6.0
const NATURAL_CONTACT_SECOND_DAMAGE_DEADLINE_SECONDS := 3.0
## Every identity-resolved stable-MOD patrol trace records its comparable
## gameplay-entry movement window from five seconds onward. Use simulation
## time so CI load cannot shift the patrol/controller phase.
const PATROL_CAPTURE_SETTLE_SECONDS := 5.0
## The natural-contact reference's contact-ready positions are the same
## gameplay-entry patrol checkpoint. The old 9.2-second value compensated for
## the pre-evidence authored-route phase; the recovered timeline reaches the
## corresponding MOD positions at exactly five simulated seconds.
const NATURAL_CONTACT_CAPTURE_SETTLE_SECONDS := 5.0
## The read-only MOD trace has a 307 ms handoff between the outbound-observed
## snapshot and the replacement command. Reproduce that physics time instead
## of relying on host-dependent process/screenshot latency.
const NATURAL_CONTACT_COMMAND_HANDOFF_SECONDS := 0.30
const FORMAL_LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]

var output_directory := ""
var failures: Array[String] = []


func _init() -> void:
	output_directory = _parse_output_directory(OS.get_cmdline_user_args())
	call_deferred("_run_probe")


func _run_probe() -> void:
	var arguments := OS.get_cmdline_user_args()
	var level_id := _parse_level_id(arguments)
	var level_index := FORMAL_LEVEL_IDS.find(level_id)
	var scenario_id := _parse_string_argument(
		arguments,
		SCENARIO_ARGUMENT_PREFIX,
		(
			"m000-basic-movement-v1"
			if level_id == "m000"
			else _enemy_patrol_scenario_id(level_id)
		),
	)
	var outbound_target := _parse_vector_argument(
		arguments,
		OUTBOUND_ARGUMENT_PREFIX,
		OUTBOUND_TARGET,
	)
	var return_target := _parse_vector_argument(
		arguments,
		RETURN_ARGUMENT_PREFIX,
		RETURN_TARGET,
	)
	var observation_seconds := _parse_positive_float_argument(
		arguments,
		OBSERVATION_ARGUMENT_PREFIX,
		OBSERVATION_SECONDS,
	)
	var patrol_settle_seconds := _parse_positive_float_argument(
		arguments,
		PATROL_SETTLE_ARGUMENT_PREFIX,
		PATROL_CAPTURE_SETTLE_SECONDS,
	)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	if int(main.get("current_level_index")) != level_index:
		main.call("switch_level", level_index, false, false)
		await process_frame
	var started := Time.get_ticks_usec()

	var trace = TRACE_SCRIPT.new()
	var scenario_description := _scenario_description(scenario_id, level_id)
	trace.configure(
		"remake",
		level_id,
		level_index + 1,
		level_index + 1,
		scenario_id,
		scenario_description,
	)
	if scenario_id == MINE_PICKUP_SCENARIO_ID:
		await _run_mine_pickup_probe(main, trace, started)
		return
	if scenario_id == PISTOL_ATTACK_SCENARIO_ID:
		await _run_pistol_attack_probe(main, trace, started)
		return
	if scenario_id == _enemy_patrol_scenario_id(level_id):
		await _run_enemy_patrol_probe(
			main,
			trace,
			started,
			observation_seconds,
			level_id,
			patrol_settle_seconds,
		)
		return
	if scenario_id == "m000-natural-contact-v1":
		await _run_natural_contact_probe(
			main,
			trace,
			started,
			outbound_target,
			return_target,
			observation_seconds,
		)
		return
	trace.capture_main("gameplay_ready", main, _elapsed_ms(started))

	var primary = _primary_unit(main)
	_expect(primary != null, "m000 primary DBL 924 actor exists")
	if primary != null:
		var calibrated_speed := _parse_move_speed(arguments)
		if calibrated_speed > 0.0:
			primary.set("move_speed", calibrated_speed)
		main.select_only(primary)
		trace.capture_main("player_selected", main, _elapsed_ms(started))

		main.issue_formation_move(outbound_target)
		_expect(
			primary.target_position.distance_to(outbound_target) <= 1.0,
			"outbound target is accepted exactly",
		)
		trace.capture_main(
			"move_outbound_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(observation_seconds)
		trace.capture_main(
			"move_outbound_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		_expect(
			primary.position.distance_to(outbound_target)
			< Vector2(241.0, 51.0).distance_to(outbound_target),
			"outbound movement approaches the target",
		)

		var outbound_position: Vector2 = primary.position
		main.issue_formation_move(return_target)
		_expect(
			primary.target_position.distance_to(return_target) <= 1.0,
			"second click replaces the active goal",
		)
		trace.capture_main(
			"move_return_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(observation_seconds)
		trace.capture_main(
			"move_return_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		_expect(
			primary.position.distance_to(return_target)
			< outbound_position.distance_to(return_target),
			"return movement approaches the replacement target",
		)

	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(trace.write_to_file(trace_path) == OK, "Remake parity trace writes")
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace.document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_mine_pickup_probe(
	main: Node,
	trace: RefCounted,
	started: int,
) -> void:
	var collector := _player_for_scene(main, M001_PLAYER_SCENE_INDEX)
	var pickup := _field_pickup_for_scene(main, M001_MINE_SCENE_INDEX)
	_expect(collector != null, "m001 scene 2280 player exists")
	_expect(pickup != null, "m001 scene 2096 mine pickup exists")
	if collector != null and pickup != null:
		main.call("select_only", collector)
		var before_quantity := _inventory_quantity(
			collector,
			"weapon_entries",
			LAND_MINE_ITEM_ID,
		)
		trace.call(
			"capture_main",
			"before_pickup",
			main,
			_elapsed_ms(started),
		)
		var order_issued := bool(
			main.call("issue_original_pickup_order", pickup)
		)
		_expect(order_issued, "m001 mine click submits the original pickup order")
		var quantity_changed := await _wait_for_inventory_quantity(
			collector,
			"weapon_entries",
			LAND_MINE_ITEM_ID,
			before_quantity + 1,
			10.0,
		)
		_expect(
			quantity_changed,
			"m001 original mine pickup adds exactly one item 43",
		)
		trace.call(
			"capture_main",
			"after_pickup",
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(
				collector,
				"weapon_entries",
				LAND_MINE_ITEM_ID,
			) == before_quantity + 1,
			"m001 mine quantity delta remains exact at capture",
		)
	await _finish_inventory_probe(
		main,
		trace,
		MINE_PICKUP_SCENARIO_ID,
	)


func _run_pistol_attack_probe(
	main: Node,
	trace: RefCounted,
	started: int,
) -> void:
	var attacker := _player_for_scene(main, M000_PLAYER_SCENE_INDEX)
	var target := _enemy_for_scene(main, M000_ATTACK_TARGET_SCENE_INDEX)
	_expect(attacker != null, "m000 scene 1436 player exists")
	_expect(target != null, "m000 scene 1598 attack target exists")
	if attacker != null and target != null:
		main.call("select_only", attacker)
		_expect(
			bool(attacker.call("equip_attack_type", 1)),
			"m000 scene 1436 equips the original pistol",
		)
		var before_quantity := _inventory_quantity(
			attacker,
			"weapon_entries",
			PISTOL_ITEM_ID,
		)
		trace.call(
			"capture_main",
			"before_attack",
			main,
			_elapsed_ms(started),
		)
		main.call("issue_attack_order", target, false)
		var quantity_changed := await _wait_for_inventory_quantity(
			attacker,
			"weapon_entries",
			PISTOL_ITEM_ID,
			before_quantity - 1,
			12.0,
		)
		_expect(
			quantity_changed,
			"m000 pistol attack consumes exactly one direct-count round",
		)
		attacker.call("clear_combat_target")
		attacker.call("cancel_path")
		trace.call(
			"capture_main",
			"after_attack",
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(
				attacker,
				"weapon_entries",
				PISTOL_ITEM_ID,
			) == before_quantity - 1,
			"m000 pistol quantity delta remains exact at capture",
		)
	await _finish_inventory_probe(
		main,
		trace,
		PISTOL_ATTACK_SCENARIO_ID,
	)


func _finish_inventory_probe(
	main: Node,
	trace: RefCounted,
	scenario_id: String,
) -> void:
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake inventory parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_enemy_patrol_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	observation_seconds: float,
	level_id: String,
	settle_seconds: float,
) -> void:
	# Let the staggered path scheduler issue every first patrol request before
	# measuring. The reference MOD trace likewise starts only after gameplay is
	# fully resumed; commanded/observed pairs compare interval movement rather
	# than unrelated absolute startup phase.
	# The isolated MOD probe resumes the original menu, waits 4.2 seconds for
	# the gameplay capture, then observes five seconds of spawn safety. The
	# frame sweep above identifies the matching post-ready simulation phase.
	await _wait_physics_seconds(settle_seconds)
	var enemy_count := (main.get("enemies") as Array).size()
	_expect(enemy_count > 0, "%s imported enemy roster is available" % level_id)
	var trace_scope := "audited_%s_enemy_identities" % level_id
	trace.call(
		"capture_main",
		"patrol_interval_1_commanded",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	await _wait_physics_seconds(observation_seconds)
	trace.call(
		"capture_main",
		"patrol_interval_1_observed",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	trace.call(
		"capture_main",
		"patrol_interval_2_commanded",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	await _wait_physics_seconds(observation_seconds)
	trace.call(
		"capture_main",
		"patrol_interval_2_observed",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(_enemy_patrol_scenario_id(level_id))
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake patrol parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_natural_contact_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	outbound_target: Vector2,
	return_target: Vector2,
	observation_seconds: float,
) -> void:
	# Match the stable MOD probe's gameplay-resume and spawn-safety phase.
	await _wait_physics_seconds(NATURAL_CONTACT_CAPTURE_SETTLE_SECONDS)
	var primary = _primary_unit(main)
	trace.call(
		"capture_main",
		"contact_ready",
		main,
		_elapsed_ms(started),
		{
			"scope": "audited_m000_resolved_actor_identities",
			"ambient_entity_count": (main.get("ambient_entities") as Array).size(),
			"ambient_unit_count": (main.get("ambient_units") as Array).size(),
			"outbound_navigation": _navigation_target_tags(
				main, primary, outbound_target
			) if primary != null else {},
			"return_navigation": _navigation_target_tags(
				main, primary, return_target
			) if primary != null else {},
		},
	)
	_expect(primary != null, "m000 primary DBL 924 actor exists")
	if primary != null:
		main.select_only(primary)
		trace.call(
			"capture_main",
			"player_selected",
			main,
			_elapsed_ms(started),
		)
		main.issue_formation_move(outbound_target)
		_expect(
			primary.target_position.distance_to(outbound_target) <= 1.0,
			"natural-contact outbound target is accepted",
		)
		trace.call(
			"capture_main",
			"move_outbound_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(observation_seconds)
		trace.call(
			"capture_main",
			"move_outbound_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(
			NATURAL_CONTACT_COMMAND_HANDOFF_SECONDS
		)
		main.issue_formation_move(return_target)
		_expect(
			primary.target_position.distance_to(return_target) <= 1.0,
			"natural-contact replacement target is accepted",
		)
		trace.call(
			"capture_main",
			"move_return_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var first_damage_observed := await _wait_for_damage_event_count(
			primary,
			1,
			maxf(
				observation_seconds,
				NATURAL_CONTACT_FIRST_DAMAGE_DEADLINE_SECONDS,
			),
		)
		_expect(
			first_damage_observed,
			"scene 1598 delivers the first recovered rifle hit before the contact deadline",
		)
		trace.call(
			"capture_main",
			"move_return_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var second_damage_observed := await _wait_for_damage_event_count(
			primary,
			2,
			NATURAL_CONTACT_SECOND_DAMAGE_DEADLINE_SECONDS,
		)
		_expect(
			second_damage_observed,
			"scene 1598 delivers the second recovered rifle hit before the settled deadline",
		)
		trace.call(
			"capture_main",
			"contact_settled",
			main,
			_elapsed_ms(started),
			{"scope": "audited_m000_resolved_actor_identities"},
		)
		var contacts := 0
		for enemy: Node2D in main.enemies:
			if (
				enemy.get("current_target") == primary
				and int(enemy.get("behavior_state")) in [1, 2]
			):
				contacts += 1
		_expect(
			contacts > 0,
			"natural movement produces at least one live enemy contact",
		)
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-m000-natural-contact-v1.json"
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake natural-contact parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _primary_unit(main: Node) -> Node2D:
	var entities: Dictionary = main.world_entities_by_scene
	for unit: Node2D in main.units:
		var entity := entities.get(int(unit.get("scene_index")), {}) as Dictionary
		if int(entity.get("database_entry_id", 0)) == PRIMARY_DATABASE_ENTRY_ID:
			return unit
	return null


func _player_for_scene(main: Node, scene_index: int) -> Node2D:
	for unit: Node2D in main.get("units") as Array:
		if int(unit.get("scene_index")) == scene_index:
			return unit
	return null


func _enemy_for_scene(main: Node, scene_index: int) -> Node2D:
	for enemy: Node2D in main.get("enemies") as Array:
		if int(enemy.get("scene_index")) == scene_index:
			return enemy
	return null


func _field_pickup_for_scene(main: Node, scene_index: int) -> Node2D:
	for pickup: Node2D in main.get("field_pickups") as Array:
		if int(pickup.get("scene_index")) == scene_index:
			return pickup
	return null


func _inventory_quantity(
	actor: Node2D,
	container_key: String,
	item_id: int,
) -> int:
	if actor == null or not actor.has_method("parity_inventory_snapshot"):
		return 0
	var inventory := actor.call("parity_inventory_snapshot") as Dictionary
	for entry_value: Variant in inventory.get(container_key, []) as Array:
		var entry := entry_value as Dictionary
		if int(entry.get("item_id", 0)) == item_id:
			return int(entry.get("quantity", 0))
	return 0


func _wait_for_inventory_quantity(
	actor: Node2D,
	container_key: String,
	item_id: int,
	expected_quantity: int,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if (
			_inventory_quantity(actor, container_key, item_id)
			== expected_quantity
		):
			return true
		await physics_frame
	return (
		_inventory_quantity(actor, container_key, item_id)
		== expected_quantity
	)


func _scenario_description(scenario_id: String, level_id: String) -> String:
	if scenario_id == MINE_PICKUP_SCENARIO_ID:
		return (
			"Select controllable scene 2280 and collect the real "
			+ "scene-2096 mine through the original automatic approach path; "
			+ "capture both inventory containers before and after."
		)
	if scenario_id == PISTOL_ATTACK_SCENARIO_ID:
		return (
			"Select scene 1436, equip the original pistol and attack live "
			+ "scene 1598; capture the direct ammunition count before and after."
		)
	if scenario_id == _enemy_patrol_scenario_id(level_id):
		return (
			"Observe the audited %s enemy patrol roster in two one-second intervals."
			% level_id
		)
	if scenario_id == "m000-natural-contact-v1":
		return (
			"Move 强子 into natural enemy contact and observe audited "
			+ "AI target-state transitions."
		)
	return (
		"Select 强子, issue two original-coordinate move orders, "
		+ "and observe facing/path replacement."
	)


func _parse_output_directory(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX).simplify_path()
	return ""


func _parse_level_id(arguments: PackedStringArray) -> String:
	var level_id := _parse_string_argument(
		arguments,
		LEVEL_ARGUMENT_PREFIX,
		"m000",
	).to_lower()
	if FORMAL_LEVEL_IDS.has(level_id):
		return level_id
	failures.append("level argument must identify one of m000 through m011")
	return "m000"


func _enemy_patrol_scenario_id(level_id: String) -> String:
	return "%s-enemy-patrol-v1" % level_id


func _parse_move_speed(arguments: PackedStringArray) -> float:
	for argument: String in arguments:
		if argument.begins_with(MOVE_SPEED_ARGUMENT_PREFIX):
			return maxf(
				argument.trim_prefix(MOVE_SPEED_ARGUMENT_PREFIX).to_float(),
				0.0,
			)
	return 0.0


func _parse_string_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: String,
) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			var parsed := argument.trim_prefix(prefix).strip_edges()
			if not parsed.is_empty():
				return parsed
	return default_value


func _parse_vector_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: Vector2,
) -> Vector2:
	var value := _parse_string_argument(arguments, prefix, "")
	var components := value.split(",", false)
	if components.size() != 2:
		return default_value
	if not components[0].is_valid_float() or not components[1].is_valid_float():
		return default_value
	return Vector2(components[0].to_float(), components[1].to_float())


func _parse_positive_float_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: float,
) -> float:
	var value := _parse_string_argument(arguments, prefix, "")
	if not value.is_valid_float():
		return default_value
	return maxf(value.to_float(), 0.05)


func _safe_file_component(value: String) -> String:
	var safe := ""
	for index: int in range(value.length()):
		var character := value.substr(index, 1)
		if (
			character >= "a" and character <= "z"
			or character >= "A" and character <= "Z"
			or character >= "0" and character <= "9"
			or character == "-"
			or character == "_"
		):
			safe += character
		else:
			safe += "-"
	return safe


func _elapsed_ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _wait_for_damage_event_count(
	unit: Node2D,
	minimum_event_count: int,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if int(unit.get("damage_event_count")) >= minimum_event_count:
			return true
		await physics_frame
	return int(unit.get("damage_event_count")) >= minimum_event_count


func _wait_physics_seconds(duration_seconds: float) -> void:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		roundi(maxf(duration_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		await physics_frame


func _movement_tags(unit: Node2D, main: Node) -> Dictionary:
	var points: Array = []
	for point: Vector2 in unit.get("movement_path") as PackedVector2Array:
		points.append([point.x, point.y])
	var raw_points: Array = []
	var requested_target: Vector2 = unit.get("target_position")
	for point: Vector2 in main.navigation_grid.find_path(
		unit.position, requested_target, true
	):
		raw_points.append([point.x, point.y])
	var nearby_owners: Dictionary = {}
	for y: int in range(8, 15):
		nearby_owners["7,%d" % y] = int(
			main.dynamic_occupancy.runtime_movement_owner(Vector2i(7, y))
		)
	var movement_offsets: Array = []
	if main.dynamic_occupancy.actors.has(int(unit.get("scene_index"))):
		var actor_state := (
			main.dynamic_occupancy.actors[int(unit.get("scene_index"))] as Dictionary
		)
		for offset: Vector2i in actor_state.get("movement_offsets", []) as Array[Vector2i]:
			movement_offsets.append([offset.x, offset.y])
	return {
		"move_speed": float(unit.get("move_speed")),
		"movement_path_index": int(unit.get("movement_path_index")),
		"movement_offsets": movement_offsets,
		"path": points,
		"raw_layer3_path": raw_points,
		"nearby_runtime_owners": nearby_owners,
	}


func _navigation_target_tags(main: Node, unit: Node2D, target: Vector2) -> Dictionary:
	if (
		main == null
		or main.get("navigation_grid") == null
		or main.get("dynamic_occupancy") == null
		or unit == null
	):
		return {}
	var navigation: RefCounted = main.get("navigation_grid")
	var occupancy: RefCounted = main.get("dynamic_occupancy")
	var target_cell: Vector2i = navigation.call("world_to_cell", target)
	var movement_owner := -1
	if occupancy.has_method("runtime_movement_owner"):
		movement_owner = int(occupancy.call("runtime_movement_owner", target_cell))
	var goal_owner := -1
	var goal_owners: Dictionary = occupancy.get("goal_owners") as Dictionary
	if goal_owners.has(target_cell):
		goal_owner = int(goal_owners[target_cell])
	var source_movement := -1
	var source_sight := -1
	if navigation.has_method("source_value"):
		source_movement = int(navigation.call("source_value", 3, target_cell))
		source_sight = int(navigation.call("source_value", 2, target_cell))
	var actor_cell := Vector2i(-1, -1)
	if occupancy.has_method("actor_cell"):
		actor_cell = occupancy.call("actor_cell", int(unit.get("scene_index")))
	return {
		"requested_world": [target.x, target.y],
		"target_cell": [target_cell.x, target_cell.y],
		"source_movement": source_movement,
		"source_sight": source_sight,
		"runtime_movement_owner": movement_owner,
		"goal_owner": goal_owner,
		"actor_cell": [actor_cell.x, actor_cell.y],
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
