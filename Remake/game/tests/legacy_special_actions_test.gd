extends SceneTree

const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const ENEMY_UNIT_SCRIPT: Script = preload("res://scripts/enemy_unit.gd")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")
const SPECIAL_CONTROL_SCRIPT: Script = preload("res://scripts/legacy_ai_control_effect.gd")
const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const SPECIAL_WORLD_OBJECT_SCRIPT: Script = preload("res://scripts/legacy_special_world_object.gd")


class MockActor:
	extends Node2D

	var faction_id := 0
	var hit_points := 10
	var scene_index := -1

	func configure(
		new_faction_id: int,
		world_position: Vector2,
		new_scene_index: int,
	) -> void:
		faction_id = new_faction_id
		position = world_position
		scene_index = new_scene_index

	func is_combat_alive() -> bool:
		return hit_points > 0

	func take_damage(amount: int, _attacker: Node2D = null) -> int:
		var applied := mini(maxi(amount, 0), hit_points)
		hit_points -= applied
		return applied


class ClearSight:
	extends RefCounted

	func has_line_of_sight(
		_observer_position: Vector2,
		_target_position: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return true


class SignalSink:
	extends RefCounted

	var trigger_count := 0
	var explosion_count := 0
	var resolve_count := 0
	var release_count := 0
	var last_target: Node2D
	var last_damage := 0
	var last_radii := Vector2.ZERO
	var special_request_count := 0
	var last_attack_type := 0

	func on_triggered(_world_object: Node2D, target: Node2D) -> void:
		trigger_count += 1
		last_target = target

	func on_explosion(
		_world_object: Node2D,
		_instigator: Node2D,
		_world_position: Vector2,
		damage: int,
		horizontal_radius: float,
		vertical_radius: float,
		_source_faction_id: int,
	) -> void:
		explosion_count += 1
		last_damage = damage
		last_radii = Vector2(horizontal_radius, vertical_radius)

	func on_resolved(_world_object: Node2D) -> void:
		resolve_count += 1

	func on_released(_effect: Node, target: Node2D) -> void:
		release_count += 1
		last_target = target

	func on_special_action(_attacker: Node2D, target: Node2D, profile: Dictionary) -> void:
		special_request_count += 1
		last_target = target
		last_attack_type = int(profile.get("attack_type", 0))


var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_evidence_profiles(failures)
	_test_type_8_triggered_object_without_assets(failures)
	_test_type_10_hundred_tick_object_without_assets(failures)
	_test_type_11_reversible_control_without_assets(failures)
	_test_recovered_consumption_rules(failures)
	_test_squad_routes_special_actions_without_direct_damage(failures)
	_test_special_item_cost_commits_at_valid_hit_frame(failures)
	_test_main_special_action_lifecycle_without_assets(failures)
	_test_special_action_save_restore_lifecycle(failures)
	if failures.is_empty():
		print("Legacy special-action tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_evidence_profiles(failures: Array[String]) -> void:
	for attack_type: int in SPECIAL_PROFILES.SPECIAL_ATTACK_TYPES:
		var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(attack_type)
		_expect(SPECIAL_PROFILES.is_valid_profile(profile), "type %d evidence profile validates" % attack_type, failures)
		_expect(int(profile.get("attack_type", 0)) == attack_type, "type %d profile round-trips" % attack_type, failures)
	var type_8: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(8)
	_expect(
		int(type_8.get("original_actor_type", 0)) == 84
		and int(type_8.get("original_gfl_index", 0)) == 470
		and int(type_8.get("ammo_item_id", 0)) == 43,
		"type 8 preserves recovered actor 84, GFL 470, and item 43",
		failures,
	)
	_expect(
		float(type_8.get("trigger_horizontal_radius", 0.0)) == 32.0
		and float(type_8.get("trigger_vertical_radius", 0.0)) == 16.0
		and int(type_8.get("trigger_faction_id", 0)) == 1,
		"type 8 preserves the recovered living faction-1 32x16 trigger",
		failures,
	)
	var type_10: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(10)
	_expect(
		int(type_10.get("original_actor_type", 0)) == 85
		and int(type_10.get("original_gfl_index", 0)) == 900
		and int(type_10.get("ammo_item_id", 0)) == 45
		and int(type_10.get("fuse_world_ticks", 0)) == 100,
		"type 10 preserves recovered actor 85, GFL 900, item 45, and 100 ticks",
		failures,
	)
	var type_11: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(11)
	_expect(
		int(type_11.get("original_target_flag_offset", 0)) == 656
		and int(type_11.get("ammo_item_id", 0)) == 99
		and not bool(type_11.get("consumes_item", true)),
		"type 11 preserves target offset +656 and the no-item-99-consumption path",
		failures,
	)
	var type_11_sources := type_11.get("source_status", {}) as Dictionary
	_expect(
		String(type_11_sources.get("remake_behavior", "")) == "unresolved_remake_default"
		and String(type_11_sources.get("duration_world_ticks", "")) == "unresolved_remake_default",
		"type 11 AI meaning and lifetime remain explicitly labelled remake defaults",
		failures,
	)
	var mislabeled_type_11 := type_11.duplicate(true)
	(mislabeled_type_11["source_status"] as Dictionary)["remake_behavior"] = "recovered"
	_expect(
		not SPECIAL_PROFILES.is_valid_profile(mislabeled_type_11),
		"evidence profiles reject an unresolved type 11 behavior relabelled as recovered",
		failures,
	)


func _test_type_8_triggered_object_without_assets(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var owner := _actor(3, Vector2.ZERO, 100, arena)
	var friendly := _actor(3, Vector2(4.0, 0.0), 101, arena)
	var neutral := _actor(2, Vector2(4.0, 0.0), 102, arena)
	var dead_enemy := _actor(1, Vector2(4.0, 0.0), 103, arena)
	dead_enemy.hit_points = 0
	var enemy := _actor(1, Vector2(64.0, 0.0), 104, arena)
	var world_object = SPECIAL_WORLD_OBJECT_SCRIPT.new()
	arena.add_child(world_object)
	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(8)
	_expect(
		world_object.configure(profile, Vector2.ZERO, owner, 3, null),
		"type 8 world object configures without an original texture",
		failures,
	)
	_expect(not world_object.has_original_texture(), "type 8 exposes its asset-free fallback", failures)
	var targets: Array[Node2D] = [owner, friendly, neutral, dead_enemy, enemy]
	world_object.set_potential_targets(targets)
	var sink := SignalSink.new()
	world_object.triggered.connect(sink.on_triggered)
	world_object.explosion_requested.connect(sink.on_explosion)
	world_object.resolved.connect(sink.on_resolved)
	world_object.advance_world_ticks(1)
	_expect(world_object.is_active(), "type 8 ignores friendly, neutral, dead, and distant actors", failures)
	enemy.position = Vector2(28.0, 6.0)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.is_resolved() and sink.trigger_count == 1 and sink.last_target == enemy,
		"type 8 triggers once when a living faction-1 actor enters its ellipse",
		failures,
	)
	_expect(
		sink.explosion_count == 1 and sink.resolve_count == 1,
		"type 8 completes one triggered-to-explosion-to-resolved lifecycle",
		failures,
	)
	_expect(
		sink.last_damage == int(profile["blast_damage"])
		and sink.last_radii == Vector2(float(profile["blast_horizontal_radius"]), float(profile["blast_vertical_radius"])),
		"type 8 emits its explicitly defaulted blast payload",
		failures,
	)
	world_object.advance_world_ticks(1)
	_expect(sink.explosion_count == 1, "resolved type 8 object cannot detonate twice", failures)
	var snapshot: Dictionary = world_object.snapshot()
	_expect(
		int(snapshot.get("attack_type", 0)) == 8
		and int(snapshot.get("owner_scene_index", -1)) == 100
		and int(snapshot.get("trigger_scene_index", -1)) == 104,
		"type 8 snapshot retains owner, trigger, and runtime identity",
		failures,
	)
	arena.queue_free()


func _test_type_10_hundred_tick_object_without_assets(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var owner := _actor(3, Vector2.ZERO, 200, arena)
	var world_object = SPECIAL_WORLD_OBJECT_SCRIPT.new()
	arena.add_child(world_object)
	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(10)
	_expect(
		world_object.configure(profile, Vector2(80.0, 40.0), owner, 3, null),
		"type 10 world object configures without an original texture",
		failures,
	)
	var sink := SignalSink.new()
	world_object.triggered.connect(sink.on_triggered)
	world_object.explosion_requested.connect(sink.on_explosion)
	world_object.resolved.connect(sink.on_resolved)
	world_object.advance_world_ticks(99)
	_expect(world_object.is_active() and sink.explosion_count == 0, "type 10 stays active through tick 99", failures)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.is_resolved()
		and world_object.age_world_ticks == 100
		and sink.trigger_count == 1
		and sink.explosion_count == 1
		and sink.resolve_count == 1,
		"type 10 detonates and resolves exactly on world tick 100",
		failures,
	)
	world_object.advance_world_ticks(200)
	_expect(sink.explosion_count == 1, "resolved type 10 object cannot detonate twice", failures)

	var disarmed_object = SPECIAL_WORLD_OBJECT_SCRIPT.new()
	arena.add_child(disarmed_object)
	_expect(
		disarmed_object.configure(profile, Vector2(120.0, 40.0), owner, 3, null)
		and disarmed_object.disarm()
		and disarmed_object.is_resolved(),
		"type 10 supports an explicit active-to-disarmed terminal path",
		failures,
	)
	_expect(not disarmed_object.disarm(), "type 10 cannot be disarmed twice", failures)
	arena.queue_free()


func _test_type_11_reversible_control_without_assets(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _actor(3, Vector2.ZERO, 300, arena)
	var enemy = ENEMY_UNIT_SCRIPT.new()
	enemy.scene_index = 301
	enemy.faction_id = 1
	enemy.current_hit_points = 8
	enemy.maximum_hit_points = 8
	enemy.is_alive = true
	arena.add_child(enemy)
	var hit_points_before: int = enemy.current_hit_points
	var effect = SPECIAL_CONTROL_SCRIPT.new()
	arena.add_child(effect)
	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(11)
	var sink := SignalSink.new()
	effect.released.connect(sink.on_released)
	_expect(
		effect.configure(profile, source, enemy),
		"type 11 control state applies without any original asset",
		failures,
	)
	_expect(
		effect.is_active() and enemy.is_special_controlled(),
		"type 11 establishes a reversible controlled state on the target AI",
		failures,
	)
	_expect(enemy.current_hit_points == hit_points_before, "type 11 applies no ordinary direct damage", failures)
	effect.advance_world_ticks(effect.duration_world_ticks - 1)
	_expect(effect.is_active() and enemy.is_special_controlled(), "type 11 remains active before its explicit remake duration", failures)
	effect.advance_world_ticks(1)
	_expect(
		not effect.is_active()
		and not enemy.is_special_controlled()
		and sink.release_count == 1
		and sink.last_target == enemy,
		"type 11 expires once and releases the target AI",
		failures,
	)
	_expect(not effect.release(), "released type 11 state is idempotent", failures)
	arena.queue_free()


func _test_recovered_consumption_rules(failures: Array[String]) -> void:
	var inventory = COMBAT_INVENTORY_SCRIPT.new()
	var type_8_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(8)
	var type_10_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(10)
	var type_11_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(11)
	_expect(inventory.register_weapon("type_8", type_8_profile), "type 8 combat action registers", failures)
	_expect(inventory.register_weapon("type_10", type_10_profile), "type 10 combat action registers", failures)
	_expect(inventory.register_weapon("type_11", type_11_profile), "type 11 combat action registers", failures)
	inventory.add_item(43, 1)
	inventory.add_item(45, 1)
	inventory.add_item(99, 2)
	_expect(
		inventory.consume_attack("type_8") and inventory.ammo_item_count(43) == 0,
		"type 8 consumes recovered item 43",
		failures,
	)
	_expect(
		inventory.consume_attack("type_10") and inventory.ammo_item_count(45) == 0,
		"type 10 consumes recovered item 45",
		failures,
	)
	_expect(
		inventory.consume_attack("type_11") and inventory.ammo_item_count(99) == 2,
		"type 11 succeeds without consuming item 99",
		failures,
	)


func _test_squad_routes_special_actions_without_direct_damage(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var unit = SQUAD_UNIT_SCRIPT.new()
	unit.faction_id = 3
	unit.scene_index = 400
	unit.dynamic_occupancy = ClearSight.new()
	unit.infinite_ammo = true
	arena.add_child(unit)
	var target := _actor(1, Vector2(8.0, 0.0), 401, arena)
	target.hit_points = 30
	var sink := SignalSink.new()
	unit.special_action_requested.connect(sink.on_special_action)
	for attack_type: int in [8, 10, 11]:
		unit.weapon_profile = COMBAT_PROFILES.weapon_profile_for_attack_type(attack_type)
		unit.pending_hit_target = target
		unit.pending_hit_resolved = false
		unit.call("_resolve_pending_hit")
		_expect(
			sink.special_request_count == ([8, 10, 11] as Array).find(attack_type) + 1
			and sink.last_target == target
			and sink.last_attack_type == attack_type,
			"squad hit frame routes type %d to the special-action signal" % attack_type,
			failures,
		)
	_expect(target.hit_points == 30, "types 8/10/11 bypass the ordinary direct-damage path", failures)
	arena.queue_free()


func _test_special_item_cost_commits_at_valid_hit_frame(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var texture_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	texture_image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(texture_image)
	var frames: Array[Texture2D] = [texture, texture]
	var attack_groups: Array[Dictionary] = []
	for unused_direction: int in range(8):
		attack_groups.append({
			"frames": frames,
			"anchor": Vector2.ONE,
			"frame_hold_ticks": 1,
		})
	var empty_groups: Array[Dictionary] = []
	var unit = SQUAD_UNIT_SCRIPT.new()
	unit.configure(
		"special operator",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		ClearSight.new(),
	)
	unit.configure_combat(
		3,
		20,
		COMBAT_PROFILES.weapon_profile("pistol_attack"),
		empty_groups,
		empty_groups,
		false,
	)
	unit.register_inventory_weapon(
		COMBAT_PROFILES.weapon_profile_for_attack_type(8),
		attack_groups,
		false,
		true,
	)
	unit.add_ammo_item(43, 1)
	arena.add_child(unit)
	var target := _actor(1, Vector2(8.0, 0.0), 701, arena)
	var sink := SignalSink.new()
	unit.special_action_requested.connect(sink.on_special_action)
	_expect(
		unit.issue_attack(target, true) and unit.try_start_attack(target, true),
		"type 8 can begin a recovered multi-frame deployment action",
		failures,
	)
	_expect(
		unit.ammo_item_count(43) == 1 and sink.special_request_count == 0,
		"type-8 item 43 remains owned until the authoritative hit frame",
		failures,
	)
	unit.take_damage(1, target)
	_expect(
		unit.ammo_item_count(43) == 1 and sink.special_request_count == 0,
		"interrupting the deployment animation does not lose item 43 or create an object",
		failures,
	)

	var second_unit = SQUAD_UNIT_SCRIPT.new()
	second_unit.configure(
		"second special operator",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		ClearSight.new(),
	)
	second_unit.configure_combat(
		3,
		20,
		COMBAT_PROFILES.weapon_profile("pistol_attack"),
		empty_groups,
		empty_groups,
		false,
	)
	second_unit.register_inventory_weapon(
		COMBAT_PROFILES.weapon_profile_for_attack_type(8),
		attack_groups,
		false,
		true,
	)
	second_unit.add_ammo_item(43, 1)
	arena.add_child(second_unit)
	second_unit.special_action_requested.connect(sink.on_special_action)
	var invalidated_target := _actor(1, Vector2(8.0, 0.0), 703, arena)
	_expect(
		second_unit.issue_attack(invalidated_target, true)
		and second_unit.try_start_attack(invalidated_target, true),
		"a second type-8 animation starts before target invalidation",
		failures,
	)
	invalidated_target.hit_points = 0
	second_unit.call("_advance_combat_action", 1.0)
	_expect(
		second_unit.ammo_item_count(43) == 1 and sink.special_request_count == 0,
		"an invalid target at the hit frame neither consumes item 43 nor dispatches the special action",
		failures,
	)
	arena.queue_free()


func _test_main_special_action_lifecycle_without_assets(failures: Array[String]) -> void:
	# Keep Main outside the SceneTree so _ready() does not load converted data.
	# Its child graph and signal wiring still exercise the complete no-asset path.
	var game = MAIN_SCRIPT.new()
	game.converted_root = ""
	var attacker := MockActor.new()
	attacker.configure(3, Vector2.ZERO, 500)
	game.add_child(attacker)
	var enemy = ENEMY_UNIT_SCRIPT.new()
	enemy.scene_index = 501
	enemy.faction_id = 1
	enemy.current_hit_points = 30
	enemy.maximum_hit_points = 30
	enemy.is_alive = true
	enemy.position = Vector2(8.0, 0.0)
	game.add_child(enemy)
	game.enemies.append(enemy)

	game.field_inventory["explosives"] = 1
	game.call(
		"_on_legacy_special_action_requested",
		attacker,
		enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(8),
	)
	_expect(
		game.legacy_special_world_objects.size() == 1
		and not bool(game.legacy_special_world_objects[0].call("has_original_texture")),
		"Main creates a type 8 fallback world object when converted assets are absent",
		failures,
	)
	game.legacy_special_world_objects[0].call("advance_world_ticks", 1)
	_expect(enemy.current_hit_points == 22, "Main receives the type 8 explosion request and applies its blast", failures)

	game.call(
		"_on_legacy_special_action_requested",
		attacker,
		enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(10),
	)
	var timed_object: Node2D = game.legacy_special_world_objects[-1]
	_expect(
		int(game.field_inventory.get("explosives", 0)) == 0,
		"Main keeps shared mission explosives synchronized when type 10 consumes item 45",
		failures,
	)
	timed_object.call("advance_world_ticks", 99)
	_expect(enemy.current_hit_points == 22, "Main type 10 object remains harmless through tick 99", failures)
	timed_object.call("advance_world_ticks", 1)
	_expect(enemy.current_hit_points == 14, "Main type 10 object applies its blast on tick 100", failures)

	var hp_before_control: int = enemy.current_hit_points
	game.call(
		"_on_legacy_special_action_requested",
		attacker,
		enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(11),
	)
	_expect(
		game.legacy_ai_control_effects.size() == 1 and enemy.is_special_controlled(),
		"Main creates and owns one type 11 target status",
		failures,
	)
	game.call(
		"_on_legacy_special_action_requested",
		attacker,
		enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(11),
	)
	_expect(game.legacy_ai_control_effects.size() == 1, "reapplying type 11 refreshes instead of stacking control locks", failures)
	var effect: Node = game.legacy_ai_control_effects[0]
	effect.call("advance_world_ticks", int(effect.get("duration_world_ticks")))
	_expect(
		game.legacy_ai_control_effects.is_empty()
		and not enemy.is_special_controlled()
		and enemy.current_hit_points == hp_before_control,
		"Main removes the expired type 11 status without direct damage",
		failures,
	)
	game.free()


func _test_special_action_save_restore_lifecycle(failures: Array[String]) -> void:
	var source_game = MAIN_SCRIPT.new()
	source_game.converted_root = ""
	var source_unit = SQUAD_UNIT_SCRIPT.new()
	source_unit.display_name = "special source"
	source_unit.scene_index = 600
	source_unit.faction_id = 3
	source_game.add_child(source_unit)
	source_game.units.append(source_unit)
	var source_enemy = ENEMY_UNIT_SCRIPT.new()
	source_enemy.display_name = "special target"
	source_enemy.scene_index = 601
	source_enemy.faction_id = 1
	source_enemy.current_hit_points = 30
	source_enemy.maximum_hit_points = 30
	source_game.add_child(source_enemy)
	source_game.enemies.append(source_enemy)
	source_game.call(
		"_on_legacy_special_action_requested",
		source_unit,
		source_enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(10),
	)
	source_game.legacy_special_world_objects[0].call("advance_world_ticks", 37)
	source_game.call(
		"_on_legacy_special_action_requested",
		source_unit,
		source_enemy,
		COMBAT_PROFILES.weapon_profile_for_attack_type(11),
	)
	source_game.legacy_ai_control_effects[0].call("advance_world_ticks", 23)
	var world: Dictionary = GAME_SESSION_STATE.call("_capture_world", source_game)
	_expect(
		(world.get("legacy_special_world_objects", []) as Array).size() == 1
		and int(((world["legacy_special_world_objects"] as Array)[0] as Dictionary).get("age_world_ticks", 0)) == 37,
		"session capture preserves an active type 10 object's tick state",
		failures,
	)
	_expect(
		(world.get("legacy_ai_control_effects", []) as Array).size() == 1
		and int(((world["legacy_ai_control_effects"] as Array)[0] as Dictionary).get("elapsed_world_ticks", 0)) == 23,
		"session capture preserves an active type 11 status timer",
		failures,
	)

	var target_game = MAIN_SCRIPT.new()
	target_game.converted_root = ""
	var target_unit = SQUAD_UNIT_SCRIPT.new()
	target_unit.display_name = "special source"
	target_unit.scene_index = 600
	target_unit.faction_id = 3
	target_game.add_child(target_unit)
	target_game.units.append(target_unit)
	var target_enemy = ENEMY_UNIT_SCRIPT.new()
	target_enemy.display_name = "special target"
	target_enemy.scene_index = 601
	target_enemy.faction_id = 1
	target_enemy.current_hit_points = 30
	target_enemy.maximum_hit_points = 30
	target_game.add_child(target_enemy)
	target_game.enemies.append(target_enemy)
	var warnings: Array[String] = []
	GAME_SESSION_STATE.call("_restore_world", target_game, world, warnings)
	_expect(warnings.is_empty(), "special-action world state restores without warnings", failures)
	_expect(
		target_game.legacy_special_world_objects.size() == 1
		and int(target_game.legacy_special_world_objects[0].get("attack_type")) == 10
		and int(target_game.legacy_special_world_objects[0].get("age_world_ticks")) == 37,
		"type 10 object resumes at its saved world tick",
		failures,
	)
	_expect(
		target_game.legacy_ai_control_effects.size() == 1
		and int(target_game.legacy_ai_control_effects[0].get("elapsed_world_ticks")) == 23
		and target_enemy.is_special_controlled(),
		"type 11 status resumes on its saved target with its saved timer",
		failures,
	)
	source_game.free()
	target_game.free()


func _actor(
	faction: int,
	world_position: Vector2,
	scene_index: int,
	parent: Node,
) -> MockActor:
	var actor := MockActor.new()
	actor.configure(faction, world_position, scene_index)
	parent.add_child(actor)
	return actor


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(label)
