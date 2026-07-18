extends SceneTree

const EXPLOSIVE_PROP_SCRIPT: Script = preload("res://scripts/explosive_prop.gd")
const FIELD_PICKUP_SCRIPT: Script = preload("res://scripts/field_pickup.gd")
const LAND_MINE_SCRIPT: Script = preload("res://scripts/land_mine.gd")
const WORLD_PICKUP_CATALOG: Script = preload("res://scripts/world_pickup_catalog.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const MAIN_INPUT_HARNESS: Script = preload("res://tests/main_input_harness.gd")
const NAVIGATION_GRID_DATA_SCRIPT: Script = preload("res://scripts/navigation_grid_data.gd")
const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")


class ClearSight:
	extends RefCounted

	func has_line_of_sight(
		_observer_position: Vector2,
		_target_position: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return true


class MockActor:
	extends Node2D

	var faction_id := 0
	var hit_points := 10

	func configure(new_faction_id: int, world_position: Vector2) -> void:
		faction_id = new_faction_id
		position = world_position

	func is_combat_alive() -> bool:
		return hit_points > 0


class SignalSink:
	extends RefCounted

	var collection_count := 0
	var last_collection: Dictionary = {}
	var prop_damage_count := 0
	var prop_explosion_count := 0
	var mine_armed_count := 0
	var mine_triggered_count := 0
	var mine_explosion_count := 0
	var mine_disarmed_count := 0
	var last_explosion_damage := 0
	var last_explosion_radii := Vector2.ZERO
	var last_trigger_target: Node2D

	func on_collected(_pickup: Node2D, _collector: Node, payload: Dictionary) -> void:
		collection_count += 1
		last_collection = payload.duplicate(true)

	func on_prop_damage(
		_prop: Node2D,
		_amount: int,
		_remaining_hit_points: int,
		_attacker: Node2D,
	) -> void:
		prop_damage_count += 1

	func on_prop_explosion(
		_prop: Node2D,
		_instigator: Node2D,
		_world_position: Vector2,
		damage: int,
		horizontal_radius: float,
		vertical_radius: float,
		_source_faction_id: int,
	) -> void:
		prop_explosion_count += 1
		last_explosion_damage = damage
		last_explosion_radii = Vector2(horizontal_radius, vertical_radius)

	func on_mine_armed(_mine: Node2D) -> void:
		mine_armed_count += 1

	func on_mine_triggered(_mine: Node2D, target: Node2D) -> void:
		mine_triggered_count += 1
		last_trigger_target = target

	func on_mine_explosion(
		_mine: Node2D,
		_instigator: Node2D,
		_world_position: Vector2,
		damage: int,
		horizontal_radius: float,
		vertical_radius: float,
		_source_faction_id: int,
	) -> void:
		mine_explosion_count += 1
		last_explosion_damage = damage
		last_explosion_radii = Vector2(horizontal_radius, vertical_radius)

	func on_mine_disarmed(_mine: Node2D) -> void:
		mine_disarmed_count += 1


class MockMissionRuntime:
	extends Node

	var last_error := ""
	var publish_count := 0
	var reject_next := false
	var last_event_name := ""
	var last_payload: Dictionary = {}

	func is_configured() -> bool:
		return true

	func publish_world_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
		publish_count += 1
		last_event_name = event_name
		last_payload = payload.duplicate(true)
		var completed: Array[String] = []
		if reject_next:
			reject_next = false
			last_error = "synthetic rejection"
			return completed
		last_error = ""
		return completed


var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_catalog(failures)
	_test_field_pickup_without_original_assets(failures)
	_test_explosive_prop_without_original_assets(failures)
	_test_land_mine_arming_and_hostile_trigger(failures)
	_test_main_inventory_and_explosion_integration(failures)
	_test_special_world_deployment_product_entry(failures)
	_test_mission_charge_policy_catalog(failures)
	_test_charge_policy_activation_and_uniform_ghost(failures)
	await _test_real_charge_policy_evidence(failures)
	if failures.is_empty():
		print("World interactable tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_catalog(failures: Array[String]) -> void:
	var catalog: Dictionary = WORLD_PICKUP_CATALOG.load_catalog()
	_expect(not catalog.is_empty(), "world pickup catalog validates", failures)
	_expect(int(catalog.get("entity_count", 0)) == 11, "catalog contains eleven original entity identities", failures)
	for database_entry_id: int in WORLD_PICKUP_CATALOG.EXPECTED_ENTITY_IDS:
		var profile: Dictionary = WORLD_PICKUP_CATALOG.profile_for_database_entry_id(database_entry_id)
		_expect(
			int(profile.get("database_entry_id", 0)) == database_entry_id,
			"database entry %d resolves" % database_entry_id,
			failures,
		)
		_expect(
			not String(profile.get("original_display_name", "")).is_empty(),
			"database entry %d retains its recovered display name" % database_entry_id,
			failures,
		)
	_expect(WORLD_PICKUP_CATALOG.is_field_pickup(982), "machine gun entity is a field pickup", failures)
	_expect(WORLD_PICKUP_CATALOG.is_field_pickup(999), "medical kit entity is a field pickup", failures)
	_expect(WORLD_PICKUP_CATALOG.is_explosive_prop(1003), "gasoline barrel is an explosive prop", failures)
	_expect(not WORLD_PICKUP_CATALOG.supports_database_entry_id(1002), "unlisted scenery is not intercepted", failures)
	var mine_profile: Dictionary = WORLD_PICKUP_CATALOG.deployable_profile("land_mine")
	_expect(not mine_profile.is_empty(), "land-mine runtime profile resolves", failures)
	_expect(int(mine_profile.get("ammo_item_id", 0)) == 43, "land mine uses recovered item 43 mapping", failures)
	var mine_sources := mine_profile.get("source_status", {}) as Dictionary
	for default_field: String in [
		"arm_delay_seconds",
		"trigger_horizontal_radius",
		"trigger_vertical_radius",
		"detonation_delay_seconds",
		"blast_damage",
		"blast_horizontal_radius",
		"blast_vertical_radius",
	]:
		_expect(
			String(mine_sources.get(default_field, "")) == "unresolved_remake_default",
			"land-mine %s is marked as an unresolved remake default" % default_field,
			failures,
		)
	var invalid_catalog := catalog.duplicate(true)
	var invalid_entities := invalid_catalog["entities"] as Dictionary
	var invalid_pickup := invalid_entities["982"] as Dictionary
	var invalid_sources := invalid_pickup["source_status"] as Dictionary
	invalid_sources.erase("grant_quantity")
	_expect(
		not WORLD_PICKUP_CATALOG.is_valid_catalog(invalid_catalog),
		"catalog rejects an unlabelled default quantity",
		failures,
	)


func _test_field_pickup_without_original_assets(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var collector := _actor(3, Vector2(110.0, 200.0), arena)
	var pickup = FIELD_PICKUP_SCRIPT.new()
	arena.add_child(pickup)
	var profile: Dictionary = WORLD_PICKUP_CATALOG.profile_for_database_entry_id(982)
	_expect(
		pickup.configure(profile, {"scene_index": 41, "x": 100, "y": 200}, null),
		"field pickup configures without an original texture",
		failures,
	)
	_expect(not pickup.has_original_texture(), "fallback pickup has no original texture dependency", failures)
	_expect(pickup.scene_index == 41 and pickup.position == Vector2(100.0, 200.0), "field metadata sets identity and position", failures)
	var far_collector := _actor(3, Vector2(200.0, 200.0), arena)
	_expect(pickup.collect(far_collector).is_empty(), "collector outside interaction range is rejected", failures)
	var sink := SignalSink.new()
	pickup.collected.connect(sink.on_collected)
	var payload: Dictionary = pickup.collect(collector)
	_expect(not payload.is_empty(), "nearby collector receives pickup payload", failures)
	_expect(String((payload["grant"] as Dictionary).get("action_key", "")) == "machine_gun_attack", "weapon grant remains data-driven", failures)
	_expect(int(payload.get("database_entry_id", 0)) == 982, "collection payload retains original database ID", failures)
	_expect(sink.collection_count == 1 and sink.last_collection == payload, "pickup emits one complete collection event", failures)
	_expect(pickup.collect(collector).is_empty(), "field pickup cannot be collected twice", failures)
	arena.queue_free()


func _test_explosive_prop_without_original_assets(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var attacker := _actor(3, Vector2.ZERO, arena)
	var prop = EXPLOSIVE_PROP_SCRIPT.new()
	arena.add_child(prop)
	var profile: Dictionary = WORLD_PICKUP_CATALOG.profile_for_database_entry_id(1003)
	_expect(
		prop.configure(profile, {"scene_index": 72, "x": 64, "y": 96}, null),
		"explosive prop configures without an original texture",
		failures,
	)
	_expect(not prop.has_original_texture(), "barrel fallback has no original texture dependency", failures)
	_expect(prop.is_combat_alive() and prop.hit_points == 8, "barrel starts with its explicit remake-default HP", failures)
	var sink := SignalSink.new()
	prop.damage_taken.connect(sink.on_prop_damage)
	prop.explosion_requested.connect(sink.on_prop_explosion)
	_expect(prop.take_damage(3, attacker) == 3, "barrel accepts partial damage", failures)
	_expect(prop.hit_points == 5 and sink.prop_explosion_count == 0, "partial damage does not detonate barrel", failures)
	_expect(prop.take_damage(20, attacker) == 5, "lethal barrel damage is capped at remaining HP", failures)
	_expect(not prop.is_combat_alive() and prop.has_exploded, "lethal damage resolves the barrel", failures)
	_expect(sink.prop_damage_count == 2 and sink.prop_explosion_count == 1, "barrel emits one explosion request after two hits", failures)
	_expect(sink.last_explosion_damage == 16 and sink.last_explosion_radii == Vector2(128.0, 64.0), "barrel explosion request carries data-driven damage and ellipse", failures)
	_expect(prop.take_damage(1, attacker) == 0 and not prop.request_explosion(attacker), "barrel detonation is idempotent", failures)
	var payload: Dictionary = prop.explosion_payload()
	_expect(int(payload.get("database_entry_id", 0)) == 1003 and int(payload.get("scene_index", -1)) == 72, "barrel explosion payload retains imported identity", failures)
	arena.queue_free()


func _test_land_mine_arming_and_hostile_trigger(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var owner := _actor(3, Vector2.ZERO, arena)
	var ally := _actor(3, Vector2(8.0, 0.0), arena)
	var neutral := _actor(0, Vector2(4.0, 0.0), arena)
	var enemy := _actor(1, Vector2(100.0, 0.0), arena)
	var mine = LAND_MINE_SCRIPT.new()
	arena.add_child(mine)
	var profile: Dictionary = WORLD_PICKUP_CATALOG.deployable_profile("land_mine")
	_expect(mine.configure(profile, Vector2.ZERO, owner, 3), "land mine is placed in an arming state", failures)
	var targets: Array[Node2D] = [owner, ally, neutral, enemy]
	mine.set_potential_targets(targets)
	var sink := SignalSink.new()
	mine.armed.connect(sink.on_mine_armed)
	mine.triggered.connect(sink.on_mine_triggered)
	mine.explosion_requested.connect(sink.on_mine_explosion)
	mine.advance_simulation(float(profile["arm_delay_seconds"]) - 0.01)
	_expect(not mine.is_armed() and sink.mine_armed_count == 0, "mine cannot trigger before its arming delay", failures)
	enemy.position = Vector2(30.0, 0.0)
	mine.advance_simulation(0.01)
	_expect(sink.mine_armed_count == 1, "mine emits one armed event when delay elapses", failures)
	_expect(sink.mine_triggered_count == 1 and sink.last_trigger_target == enemy, "armed mine ignores ally and neutral then selects hostile entrant", failures)
	_expect(sink.mine_explosion_count == 0, "triggered mine observes its detonation delay", failures)
	mine.advance_simulation(float(profile["detonation_delay_seconds"]) - 0.01)
	_expect(sink.mine_explosion_count == 0, "mine remains pending until the complete detonation delay", failures)
	mine.advance_simulation(0.02)
	_expect(sink.mine_explosion_count == 1 and mine.is_resolved(), "mine emits one explosion request and resolves", failures)
	_expect(sink.last_explosion_damage == 16 and sink.last_explosion_radii == Vector2(128.0, 64.0), "mine request carries data-driven damage and ellipse", failures)

	var second_mine = LAND_MINE_SCRIPT.new()
	arena.add_child(second_mine)
	_expect(second_mine.configure(profile, Vector2(200.0, 200.0), owner, 3), "second mine configures for disarm path", failures)
	var safe_targets: Array[Node2D] = [ally, neutral]
	second_mine.set_potential_targets(safe_targets)
	var second_sink := SignalSink.new()
	second_mine.disarmed.connect(second_sink.on_mine_disarmed)
	second_mine.advance_simulation(float(profile["arm_delay_seconds"]) + 1.0)
	_expect(second_mine.is_armed(), "friendly and neutral actors do not trigger an armed mine", failures)
	_expect(second_mine.disarm() and second_sink.mine_disarmed_count == 1, "armed mine supports explicit disarming", failures)
	_expect(not second_mine.disarm(), "mine cannot be disarmed twice", failures)
	arena.queue_free()


func _test_main_inventory_and_explosion_integration(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var clear_sight := ClearSight.new()
	var empty_groups: Array[Dictionary] = []
	var collector = SQUAD_UNIT_SCRIPT.new()
	collector.configure(
		"collector",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	collector.configure_combat(
		3,
		20,
		COMBAT_PROFILES.weapon_profile("pistol_attack"),
		empty_groups,
		empty_groups,
		false,
	)
	arena.add_child(collector)
	var main = MAIN_SCRIPT.new()
	main.units.append(collector)
	main._apply_field_pickup(
		{
			"original_display_name": "可拾取机枪",
			"scene_index": 1,
			"grant": {"kind": "weapon", "action_key": "machine_gun_attack", "quantity": 1},
		},
		collector,
	)
	_expect(
		collector.has_inventory_weapon("machine_gun_attack")
		and int(collector.weapon_profile.get("attack_type", 0)) == 3
		and collector.magazine_ammo == 30,
		"main converts a machine-gun entity payload into an equipped backpack weapon",
		failures,
	)
	main._apply_field_pickup(
		{
			"original_display_name": "可拾取手榴弹",
			"scene_index": 2,
			"grant": {
				"kind": "ammunition",
				"action_key": "grenade_attack",
				"item_id": 44,
				"quantity": 3,
			},
		},
		collector,
	)
	_expect(
		collector.has_inventory_weapon("grenade_attack")
		and collector.ammo_item_count(44) == 3,
		"main unlocks the grenade action and stores item-44 ammunition",
		failures,
	)
	main._apply_field_pickup(
		{
			"original_display_name": "可拾取地雷",
			"scene_index": 3,
			"grant": {"kind": "deployable", "item_id": 43, "quantity": 1},
		},
		collector,
	)
	_expect(
		collector.ammo_item_count(43) == 1
		and collector.has_inventory_weapon("active_action"),
		"mine pickup stores item 43 and exposes the recovered type-8 action",
		failures,
	)
	main._apply_field_pickup(
		{
			"original_display_name": "放在地上的炸药",
			"scene_index": 5,
			"grant": {"kind": "mission_item", "item_key": "explosives", "quantity": 1},
		},
		collector,
	)
	_expect(
		int(main.field_inventory.get("explosives", 0)) == 1
		and collector.ammo_item_count(45) == 1
		and collector.has_inventory_weapon("active_action_alt"),
		"explosives pickup keeps task inventory and exposes the recovered type-10 action",
		failures,
	)
	main.current_mission = {"id": "m011"}
	_expect(
		main._grant_editorial_type_11_loadout()
		and collector.has_inventory_weapon("special_attack")
		and collector.ammo_item_count(99) == 1,
		"m011 exposes the labelled reusable item-99 bridge for the type-11 lifecycle",
		failures,
	)
	var bridge_bystander = SQUAD_UNIT_SCRIPT.new()
	bridge_bystander.configure(
		"bridge bystander",
		Color.WHITE,
		Vector2(10.0, 0.0),
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	bridge_bystander.configure_combat(3, 8, {}, empty_groups, empty_groups, true)
	arena.add_child(bridge_bystander)
	main.units.push_front(bridge_bystander)
	_expect(
		main._grant_editorial_type_11_loadout()
		and collector.ammo_item_count(99) == 1
		and not bridge_bystander.has_inventory_weapon("special_attack")
		and bridge_bystander.ammo_item_count(99) == 0,
		"reapplying the m011 compatibility bridge reuses the saved holder without duplicating item 99",
		failures,
	)
	main.units.erase(bridge_bystander)
	bridge_bystander.queue_free()
	var friendly_target = SQUAD_UNIT_SCRIPT.new()
	friendly_target.configure(
		"friendly target",
		Color.WHITE,
		Vector2(20.0, 0.0),
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	friendly_target.configure_combat(3, 8, {}, empty_groups, empty_groups, true)
	arena.add_child(friendly_target)
	_expect(
		not collector.can_attack_target(friendly_target)
		and collector.can_attack_target(friendly_target, true)
		and collector.issue_attack(friendly_target, true)
		and collector.combat_target_forced,
		"held Ctrl/Up force-target orders can deliberately target a non-hostile actor",
		failures,
	)
	collector.clear_combat_target()
	collector.current_hit_points = 4
	main._apply_field_pickup(
		{
			"original_display_name": "放在地上的草药",
			"scene_index": 4,
			"grant": {"kind": "healing", "quantity": 1, "healing_hit_points": 8},
		},
		collector,
	)
	_expect(
		collector.current_hit_points == 12,
		"main applies the explicit remake-default healing payload",
		failures,
	)

	var prop = EXPLOSIVE_PROP_SCRIPT.new()
	var prop_profile: Dictionary = WORLD_PICKUP_CATALOG.profile_for_database_entry_id(1003)
	_expect(
		prop.configure(prop_profile, {"scene_index": 9, "x": 60, "y": 0}),
		"integration barrel configures",
		failures,
	)
	arena.add_child(prop)
	main.explosive_props.append(prop)
	_expect(
		collector.can_attack_target(prop),
		"player targeting explicitly accepts a neutral explosive world object",
		failures,
	)
	collector.current_hit_points = 20
	main._on_world_explosion_requested(
		prop, collector, Vector2.ZERO, 16, 128.0, 64.0, 0
	)
	_expect(
		collector.current_hit_points == 4,
		"world-object explosion reaches the shared actual-damage path",
		failures,
	)
	main.units.clear()
	main.explosive_props.clear()
	main.free()
	arena.queue_free()


func _test_special_world_deployment_product_entry(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var main = MAIN_INPUT_HARNESS.new()
	arena.add_child(main)
	var clear_sight := ClearSight.new()
	var empty_groups: Array[Dictionary] = []
	var unit = SQUAD_UNIT_SCRIPT.new()
	unit.configure(
		"deployment operator",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	unit.configure_combat(
		3,
		20,
		COMBAT_PROFILES.weapon_profile("pistol_attack"),
		empty_groups,
		empty_groups,
		false,
	)
	main.add_child(unit)
	main.units.append(unit)
	main.selected_units.append(unit)
	unit.set_selected(true)
	main._connect_combatant(unit)

	var mine_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(8)
	_expect(
		unit.register_inventory_weapon(mine_profile, empty_groups, false, true),
		"type-8 deployable can be equipped through the player inventory",
		failures,
	)
	_expect(unit.add_ammo_item(43, 1) == 1, "type-8 test operator receives one recovered mine item", failures)
	var deployment_point := Vector2(8.0, 0.0)
	_expect(
		main._try_issue_legacy_world_object_deployment(deployment_point),
		"an empty-world left click enters the type-8 deployment command path",
		failures,
	)
	_expect(
		main.legacy_deployment_targets.size() == 1
		and unit.combat_target == main.legacy_deployment_targets[0]
		and unit.combat_target_forced,
		"the product command retains its deployment target until the hit frame",
		failures,
	)
	unit._physics_process(0.01)
	_expect(unit.ammo_item_count(43) == 0, "the deployment attack consumes one item-43 charge", failures)
	_expect(main.legacy_deployment_targets.is_empty(), "the transient command target is retired after the hit frame", failures)
	_expect(
		main.legacy_special_world_objects.size() == 1
		and int(main.legacy_special_world_objects[0].get("attack_type")) == 8
		and main.legacy_special_world_objects[0].position == deployment_point,
		"the hit frame creates the authoritative type-8 world object at the clicked point",
		failures,
	)

	unit.add_ammo_item(43, 3)
	unit.dynamic_occupancy = null
	_expect(
		main._try_issue_legacy_world_object_deployment(Vector2(100.0, 0.0))
		and main.legacy_deployment_targets.size() == 1,
		"a second deployment command may wait while the operator approaches",
		failures,
	)
	unit._physics_process(0.01)
	_expect(not unit.movement_path.is_empty(), "the pending deployment may create an approach path", failures)
	main._equip_selected_attack_type(1)
	_expect(
		main.legacy_deployment_targets.is_empty()
		and unit.movement_path.is_empty()
		and unit.combat_target == null
		and unit.ammo_item_count(43) == 3,
		"switching weapons cancels the pending target, approach path, and reserved goal without consuming it",
		failures,
	)
	main._equip_selected_attack_type(8)
	_expect(
		main._try_issue_legacy_world_object_deployment(Vector2(12.0, 0.0))
		and main.legacy_deployment_targets.size() == 1,
		"the deployable can be selected again after cancellation",
		failures,
	)
	var superseded_target: Node2D = main.legacy_deployment_targets[0]
	_expect(
		main._try_issue_legacy_world_object_deployment(Vector2(16.0, 0.0))
		and main.legacy_deployment_targets.size() == 1
		and main.legacy_deployment_targets[0] != superseded_target
		and unit.ammo_item_count(43) == 3,
		"a new deployment replaces the operator's old pending target without consuming it",
		failures,
	)
	main.issue_formation_move(Vector2(24.0, 0.0))
	_expect(
		main.legacy_deployment_targets.is_empty() and unit.ammo_item_count(43) == 3,
		"a movement order cancels the pending deployment without leaking or consuming ammunition",
		failures,
	)

	var blocked_navigation = NAVIGATION_GRID_DATA_SCRIPT.new()
	blocked_navigation.dimensions = Vector2i(3, 3)
	blocked_navigation.cell_size = Vector2i(20, 20)
	var blocked_cells := PackedInt64Array()
	blocked_cells.resize(9)
	blocked_cells.fill(1)
	blocked_navigation.layers[blocked_navigation.MOVEMENT_LAYER_ID] = blocked_cells
	blocked_navigation.prepare_astar()
	main.navigation_grid = blocked_navigation
	_expect(
		main._try_issue_legacy_world_object_deployment(Vector2(50.0, 50.0))
		and main.legacy_deployment_targets.is_empty()
		and unit.ammo_item_count(43) == 3,
		"an unreachable deployment point is rejected without a target leak or ammunition loss",
		failures,
	)
	main.navigation_grid = null
	_expect(
		main._try_issue_legacy_world_object_deployment(Vector2(20.0, 0.0))
		and main.legacy_deployment_targets.size() == 1,
		"a valid pending deployment can be issued before the operator dies",
		failures,
	)
	unit.take_damage(unit.maximum_hit_points, null)
	_expect(
		main.legacy_deployment_targets.is_empty() and unit.ammo_item_count(43) == 3,
		"operator death cancels the pending deployment without consuming ammunition",
		failures,
	)
	arena.queue_free()


func _test_mission_charge_policy_catalog(failures: Array[String]) -> void:
	var catalog: Dictionary = MISSION_DATA.load_catalog()
	_expect(not catalog.is_empty(), "mission catalog validates charge policies", failures)
	var expected := {
		"m001": ["preplanted", 1, 2],
		"m002": ["inventory_required", 1, 1],
		"m003": ["inventory_required", 6, 5],
		"m004": ["preplanted", 0, 2],
		"m008": ["inventory_required", 4, 4],
		"m009": ["inventory_required", 9, 4],
		"m011": ["preplanted", 4, 6],
	}
	for mission_value: Variant in expected.keys():
		var mission_id := str(mission_value)
		var mission: Dictionary = MISSION_DATA.load_mission(mission_id)
		var policy := mission.get("charge_policy", {}) as Dictionary
		var expected_values := expected[mission_id] as Array
		_expect(
			MISSION_DATA.is_valid_charge_policy(mission),
			"%s charge policy validates" % mission_id,
			failures,
		)
		_expect(
			str(policy.get("mode", "")) == str(expected_values[0])
			and int(policy.get("map_pickup_count", -1)) == int(expected_values[1])
			and int(policy.get("target_count", -1)) == int(expected_values[2]),
			"%s charge policy preserves its evidence counts and mode" % mission_id,
			failures,
		)

	var invalid_mode_catalog := catalog.duplicate(true)
	var invalid_mode_mission := (invalid_mode_catalog["missions"] as Array)[2] as Dictionary
	(invalid_mode_mission["charge_policy"] as Dictionary)["mode"] = "sometimes_free"
	_expect(
		not MISSION_DATA.is_valid_catalog(invalid_mode_catalog),
		"mission catalog rejects an ambiguous charge mode",
		failures,
	)
	var insufficient_catalog := catalog.duplicate(true)
	var insufficient_mission := (insufficient_catalog["missions"] as Array)[2] as Dictionary
	(insufficient_mission["charge_policy"] as Dictionary)["map_pickup_count"] = 0
	_expect(
		not MISSION_DATA.is_valid_catalog(insufficient_catalog),
		"inventory-required policy rejects insufficient map inventory",
		failures,
	)
	var mismatched_target_catalog := catalog.duplicate(true)
	var mismatched_target_mission := (
		(mismatched_target_catalog["missions"] as Array)[1] as Dictionary
	)
	(mismatched_target_mission["charge_policy"] as Dictionary)["target_count"] = 1
	_expect(
		not MISSION_DATA.is_valid_catalog(mismatched_target_catalog),
		"charge policy target count must match its explosion scene binding",
		failures,
	)


func _test_charge_policy_activation_and_uniform_ghost(failures: Array[String]) -> void:
	var main = MAIN_SCRIPT.new()
	var runtime := MockMissionRuntime.new()
	main.mission_runtime = runtime
	main.current_mission = {
		"scene_bindings": {"explosion": [42]},
		"charge_policy": {
			"mode": "inventory_required",
			"inventory_item_key": "explosives",
			"quantity_per_target": 1,
		},
	}
	_expect(
		not main._activate_bound_scene("explosion", 42)
		and runtime.publish_count == 0
		and not main.activated_mission_scenes.has(42),
		"inventory-required charge cannot activate for free",
		failures,
	)
	main.field_inventory["explosives"] = 2
	_expect(
		main._activate_bound_scene("explosion", 42)
		and runtime.publish_count == 1
		and int(main.field_inventory["explosives"]) == 1
		and main.activated_mission_scenes.has(42),
		"accepted inventory-required charge consumes exactly one item after publish",
		failures,
	)
	_expect(
		main._activate_bound_scene("explosion", 42)
		and runtime.publish_count == 1
		and int(main.field_inventory["explosives"]) == 1,
		"repeated activation is idempotent and never double-consumes",
		failures,
	)

	main.current_mission = {
		"scene_bindings": {"explosion": [43]},
		"charge_policy": {
			"mode": "preplanted",
			"inventory_item_key": "explosives",
			"quantity_per_target": 1,
		},
	}
	main.field_inventory["explosives"] = 5
	_expect(
		main._activate_bound_scene("explosion", 43)
		and runtime.publish_count == 2
		and int(main.field_inventory["explosives"]) == 5,
		"preplanted charge succeeds without touching backpack explosives",
		failures,
	)

	main.current_mission = {"scene_bindings": {"explosion": [44]}}
	main.field_inventory.erase("explosives")
	_expect(
		main._activate_bound_scene("explosion", 44)
		and runtime.publish_count == 3
		and not main.field_inventory.has("explosives"),
		"omitted optional policy defaults to explicit non-consuming preplanted behavior",
		failures,
	)

	main.current_mission = {
		"scene_bindings": {"explosion": [45]},
		"charge_policy": {
			"mode": "inventory_required",
			"inventory_item_key": "explosives",
			"quantity_per_target": 1,
		},
	}
	main.field_inventory["explosives"] = 1
	runtime.reject_next = true
	_expect(
		not main._activate_bound_scene("explosion", 45)
		and int(main.field_inventory["explosives"]) == 1
		and not main.activated_mission_scenes.has(45),
		"rejected mission event never consumes required inventory",
		failures,
	)

	main.current_mission = {
		"scene_bindings": {"uniform_crate": [2099]},
		"pickup_bindings": {"uniform_crate": {"item_name": "日军军服"}},
	}
	var collector = SQUAD_UNIT_SCRIPT.new()
	collector.display_name = "古明"
	var publish_before_uniform := runtime.publish_count
	main._apply_field_pickup(
		{
			"original_display_name": "放在地上的军服箱子",
			"scene_index": 2099,
			"grant": {"kind": "mission_item", "item_key": "uniform", "quantity": 1},
		},
		collector,
	)
	_expect(
		main.activated_mission_scenes.has(2099)
		and int(main.field_inventory.get("uniform", 0)) == 1
		and runtime.publish_count == publish_before_uniform + 1,
		"m001 field uniform pickup activates scene 2099 exactly once",
		failures,
	)
	_expect(
		main._activate_bound_scene("uniform_crate", 2099)
		and runtime.publish_count == publish_before_uniform + 1,
		"m001 scene 2099 cannot reappear as a ghost mission interaction",
		failures,
	)
	collector.free()
	runtime.free()
	main.mission_runtime = null
	main.free()


func _test_real_charge_policy_evidence(failures: Array[String]) -> void:
	const LEVEL_ROOT := "res://../LocalAssets/converted/levels"
	if not FileAccess.file_exists(LEVEL_ROOT.path_join("m001/level.json")):
		print("Real charge-policy evidence test skipped: LocalAssets are unavailable.")
		return
	for mission_id: String in ["m001", "m002", "m003", "m004", "m008", "m009", "m011"]:
		var path := LEVEL_ROOT.path_join("%s/level.json" % mission_id)
		var level := _load_json_dictionary(path)
		var pickup_count := 0
		for raw_entity: Variant in level.get("entities", []) as Array:
			if int((raw_entity as Dictionary).get("database_entry_id", 0)) == 998:
				pickup_count += 1
		var mission: Dictionary = MISSION_DATA.load_mission(mission_id)
		var policy := mission.get("charge_policy", {}) as Dictionary
		var explosion_scenes := (
			(mission.get("scene_bindings", {}) as Dictionary).get("explosion", []) as Array
		)
		var target_count := explosion_scenes.size()
		_expect(
			pickup_count == int(policy.get("map_pickup_count", -1))
			and target_count == int(policy.get("target_count", -1)),
			"%s policy evidence matches real DBL 998 and target counts" % mission_id,
			failures,
		)
		var mode := str(policy.get("mode", ""))
		_expect(
			(
				mode == "inventory_required" and pickup_count >= target_count
				or mode == "preplanted" and pickup_count < target_count
			),
			"%s selects an honest charge mode from real resource evidence" % mission_id,
			failures,
		)

	var m001_level := _load_json_dictionary(LEVEL_ROOT.path_join("m001/level.json"))
	var real_uniform_entity: Dictionary = {}
	for raw_entity: Variant in m001_level.get("entities", []) as Array:
		var entity := raw_entity as Dictionary
		if int(entity.get("scene_index", -1)) == 2099:
			real_uniform_entity = entity
			break
	_expect(
		int(real_uniform_entity.get("database_entry_id", 0)) == 990,
		"m001 real scene 2099 is the recovered field uniform box",
		failures,
	)

	var real_main = MAIN_SCRIPT.new()
	root.add_child(real_main)
	await process_frame
	# This test owns world-interaction semantics, not audio decoding. Point its
	# director at a guaranteed-missing root so short UI cues cannot leave an
	# AudioServer playback object racing process shutdown.
	if real_main.media_director != null:
		real_main.media_director.call(
			"configure", ProjectSettings.globalize_path("user://missing-world-test-media")
		)
	real_main.switch_level(1)
	await process_frame
	var real_uniform_pickup: Node2D = null
	for pickup: Node2D in real_main.field_pickups:
		if int(pickup.get("scene_index")) == 2099:
			real_uniform_pickup = pickup
			break
	_expect(
		real_uniform_pickup != null and not real_main.units.is_empty(),
		"m001 real runtime exposes scene 2099 as a field pickup",
		failures,
	)
	if real_uniform_pickup != null and not real_main.units.is_empty():
		var field_count_before: int = real_main.field_pickups.size()
		var collector = real_main.units[0]
		real_main.select_only(collector)
		collector.position = real_uniform_pickup.position
		real_main.interact_with_mission_world()
		await process_frame
		_expect(
			real_main.field_pickups.size() == field_count_before - 1
			and int(real_main.field_inventory.get("uniform", 0)) == 1
			and real_main.activated_mission_scenes.has(2099),
			"m001 real E interaction consumes scene 2099 and suppresses its ghost binding",
			failures,
		)
	# The real media fixture may have started a short UI/voice WAV during the E
	# interaction. Stop and detach streams before freeing so AudioServer does not
	# retain playback references past this short-lived headless test process.
	if real_main.media_director != null:
		var voice_player: AudioStreamPlayer = real_main.media_director.get("audio_player")
		if voice_player != null:
			voice_player.stop()
			voice_player.stream = null
		var raw_sfx_players: Variant = real_main.media_director.get("sfx_players")
		if raw_sfx_players is Array:
			for raw_player: Variant in raw_sfx_players as Array:
				var sfx_player := raw_player as AudioStreamPlayer
				if sfx_player != null:
					sfx_player.stop()
					sfx_player.stream = null
	root.remove_child(real_main)
	real_main.free()
	await process_frame


func _load_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data as Dictionary


func _actor(faction: int, world_position: Vector2, parent: Node) -> MockActor:
	var actor := MockActor.new()
	actor.configure(faction, world_position)
	parent.add_child(actor)
	return actor


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(label)
