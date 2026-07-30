extends SceneTree

const AMMO_PICKUP_SCRIPT: Script = preload("res://scripts/ammo_pickup.gd")
const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const COMBAT_PROJECTILE_SCRIPT: Script = preload("res://scripts/combat_projectile.gd")
const LEGACY_EXPLOSION_RULES: Script = preload("res://scripts/legacy_explosion_rules.gd")
const LEGACY_PROJECTILE_RULES: Script = preload("res://scripts/legacy_projectile_rules.gd")
const PROJECTILE_PROFILES: Script = preload("res://scripts/projectile_profiles.gd")
const PROJECTILE_WORLD_SCRIPT: Script = preload("res://scripts/projectile_world.gd")
const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")


class ClearSight:
	extends RefCounted

	func has_line_of_sight(
		_observer_position: Vector2,
		_target_position: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return true


class MockCombatant:
	extends Node2D

	var faction_id := 0
	var hit_points := 0
	var scene_index := -1
	var runtime_actor_type := 1
	var damage_events: Array[int] = []
	var projectile_launch_offset := Vector2.ZERO
	var projectile_vertical_baseline := 0.0

	func configure(
		new_faction: int,
		new_hit_points: int,
		world_position: Vector2,
		new_scene_index: int,
		new_runtime_actor_type: int = 1,
	) -> void:
		faction_id = new_faction
		hit_points = new_hit_points
		position = world_position
		scene_index = new_scene_index
		runtime_actor_type = new_runtime_actor_type

	func is_combat_alive() -> bool:
		return hit_points > 0

	func take_damage(amount: int, _attacker: Node2D = null) -> int:
		var applied := mini(maxi(amount, 0), hit_points)
		hit_points -= applied
		if applied > 0:
			damage_events.append(applied)
		return applied

	func legacy_projectile_launch_offset() -> Vector2:
		return projectile_launch_offset

	func legacy_projectile_vertical_baseline() -> float:
		return projectile_vertical_baseline


class BlockingNavigation:
	extends RefCounted

	var blocked_cells: Dictionary = {}

	func world_to_cell(world_position: Vector2) -> Vector2i:
		return LEGACY_PROJECTILE_RULES.world_cell(world_position)

	func cell_to_world(cell: Vector2i) -> Vector2:
		return Vector2(
			(float(cell.x) + 0.5) * 32.0,
			(float(cell.y) + 0.5) * 16.0,
		)

	func is_line_of_sight_blocked(
		cell: Vector2i,
		_ignored: Dictionary = {},
	) -> bool:
		return blocked_cells.has(cell)


var check_count := 0
var next_scene_index := 1000


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_projectile_profiles(failures)
	_test_recovered_projectile_math(failures)
	_test_inventory_and_pickup(failures)
	_test_direct_projectile(failures)
	_test_grenade_blast(failures)
	_test_projectile_snapshot_restore(failures)
	_test_projectile_world(failures)
	_test_squad_inventory_and_projectile_integration(failures)
	if failures.is_empty():
		print("Projectile and inventory tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_projectile_profiles(failures: Array[String]) -> void:
	var catalog: Dictionary = PROJECTILE_PROFILES.load_catalog()
	_expect(not catalog.is_empty(), "projectile catalog validates", failures)
	for attack_type: int in [6, 7, 9]:
		var profile: Dictionary = PROJECTILE_PROFILES.profile_for_attack_type(attack_type)
		_expect(int(profile.get("attack_type", 0)) == attack_type, "projectile attack type %d resolves" % attack_type, failures)
		_expect(PROJECTILE_PROFILES.is_projectile_attack(attack_type), "projectile attack type %d is classified" % attack_type, failures)
	_expect(not PROJECTILE_PROFILES.is_projectile_attack(1), "pistol remains direct-hit delivery", failures)
	var grenade: Dictionary = PROJECTILE_PROFILES.profile_for_attack_type(9)
	_expect(
		int(grenade.get("delivery_mode", 0)) == 1
		and int(grenade.get("world_step_pixels", 0)) == 8
		and int(grenade.get("runtime_actor_type", 0)) == 57
		and int(grenade.get("original_gfl_index", 0)) == 528,
		"grenade preserves recovered mode 1, step 8, actor 57 and GFL 528",
		failures,
	)
	_expect(
		int(grenade.get("explosion_actor_type", 0)) == 61
		and int(grenade.get("explosion_gfl_index", 0)) == 19
		and int(grenade.get("blast_damage", 0)) == 128,
		"grenade endpoint creates recovered actor 61/GFL 19 with 128 damage",
		failures,
	)
	_expect(bool(grenade.get("friendly_fire", false)), "grenade recovered friendly fire is enabled", failures)
	_expect(
		String((grenade.get("source_status", {}) as Dictionary).get("friendly_fire", ""))
		== "recovered",
		"grenade friendly-fire rule is evidence-backed",
		failures,
	)


func _test_recovered_projectile_math(failures: Array[String]) -> void:
	var path: PackedVector2Array = (
		LEGACY_PROJECTILE_RULES.build_inclusive_bresenham_path(
		Vector2.ZERO,
		Vector2(5.0, 2.0),
		)
	)
	_expect(
		Array(path) == [
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(2.0, 1.0),
			Vector2(3.0, 1.0),
			Vector2(4.0, 2.0),
			Vector2(5.0, 2.0),
		],
		"inclusive Bresenham path matches sub_463290",
		failures,
	)
	_expect(
		LEGACY_PROJECTILE_RULES.path_resolution_world_ticks(101, 16) == 8
		and LEGACY_PROJECTILE_RULES.path_resolution_world_ticks(101, 5) == 21
		and LEGACY_PROJECTILE_RULES.path_resolution_world_ticks(201, 8) == 26,
		"endpoint is processed one world tick after the final clamped advance",
		failures,
	)
	var coefficient: float = (
		LEGACY_PROJECTILE_RULES.original_arc_coefficient(201, 8)
	)
	_expect(
		is_equal_approx(coefficient, 0.32)
		and LEGACY_PROJECTILE_RULES.original_arc_height(8, 12, coefficient)
			== 50.0,
		"grenade parabola uses step/(path_count/step) and __ftol truncation",
		failures,
	)
	var actor_61: Dictionary = LEGACY_EXPLOSION_RULES.profile_for_actor(61)
	_expect(
		int(actor_61.get("original_gfl_index", 0)) == 19
		and int(actor_61.get("blast_damage", 0)) == 128
		and float(actor_61.get("alert_radius", 0.0)) == 800.0,
		"actor 61 shares the recovered explosion handler payload",
		failures,
	)
	var sprite_groups: Array[Dictionary] = []
	for unused_direction: int in range(8):
		sprite_groups.append({
			"primary_triplet": [17, 0, 150],
			"tertiary_triplet": [4, 2, 2],
		})
	var actor = SQUAD_UNIT_SCRIPT.new()
	actor.movement_groups = sprite_groups
	actor.was_moving = true
	_expect(
		actor.legacy_projectile_launch_offset() == Vector2(-13.0, 0.0)
		and actor.legacy_projectile_vertical_baseline() == 148.0,
		"SPR primary/tertiary triplets reproduce actor +0x50-+0x44 and visual Z",
		failures,
	)
	actor.free()


func _test_inventory_and_pickup(failures: Array[String]) -> void:
	var inventory = COMBAT_INVENTORY_SCRIPT.new()
	_expect(COMBAT_INVENTORY_SCRIPT.SUPPORTED_AMMO_ITEM_IDS.size() == 11, "all 36-45 and 99 ammo item IDs are supported", failures)
	for item_id: int in range(36, 46):
		_expect(COMBAT_INVENTORY_SCRIPT.supports_ammo_item(item_id), "ammo item %d is supported" % item_id, failures)
	_expect(COMBAT_INVENTORY_SCRIPT.supports_ammo_item(99), "ammo item 99 is supported", failures)
	_expect(not COMBAT_INVENTORY_SCRIPT.supports_ammo_item(35), "unrelated item IDs are rejected", failures)

	var pistol: Dictionary = COMBAT_PROFILES.weapon_profile("pistol_attack")
	var rifle: Dictionary = COMBAT_PROFILES.weapon_profile("rifle_attack")
	_expect(inventory.register_weapon("pistol_attack", pistol, true), "pistol registers from combat profile", failures)
	_expect(inventory.register_weapon("rifle_attack", rifle, true), "rifle registers from combat profile", failures)
	_expect(inventory.active_weapon_key() == "pistol_attack", "first registered weapon becomes active", failures)
	_expect(int(inventory.weapon_state("pistol_attack").get("magazine", -1)) == 8, "default pistol magazine is loaded", failures)
	_expect(inventory.ammo_item_count(36) == 32, "pistol reserve uses item 36", failures)
	_expect(inventory.ammo_item_count(37) == 25, "rifle reserve uses item 37", failures)
	for unused_shot: int in range(8):
		_expect(inventory.consume_active_attack(), "loaded pistol shot consumes one round", failures)
	_expect(not inventory.consume_active_attack(), "empty pistol cannot fire", failures)
	_expect(inventory.needs_reload(), "empty pistol requests reload when reserve exists", failures)
	_expect(inventory.reload_active_weapon() == 8, "pistol reload transfers one magazine", failures)
	_expect(inventory.ammo_item_count(36) == 24, "pistol reload removes item 36 rounds", failures)
	_expect(inventory.equip_weapon("rifle_attack"), "registered rifle can be equipped", failures)
	_expect(inventory.active_weapon_key() == "rifle_attack", "weapon switching updates active key", failures)
	_expect(inventory.add_item(44, 3) == 3 and inventory.ammo_item_count(44) == 3, "grenade ammunition is stored by item 44", failures)
	_expect(inventory.add_item(99, 2) == 2 and inventory.ammo_item_count(99) == 2, "special ammunition is stored by item 99", failures)
	var mine: Dictionary = COMBAT_PROFILES.weapon_profile("active_action")
	_expect(inventory.register_weapon("active_action", mine), "mine world-object action registers", failures)
	_expect(inventory.add_item(43, 2) == 2, "mine pickup stores item 43", failures)
	_expect(inventory.equip_weapon("active_action"), "mine action can be equipped", failures)
	_expect(
		inventory.consume_active_attack() and inventory.ammo_item_count(43) == 1,
		"zero-capacity mine action consumes its mapped world item directly",
		failures,
	)
	_expect(inventory.add_item(12, 9) == 0, "unsupported pickup does not enter combat inventory", failures)

	var pickup = AMMO_PICKUP_SCRIPT.new()
	_expect(pickup.configure(37, 5, Vector2(10.0, 20.0), "rifle rounds"), "ammo pickup configures", failures)
	_expect(pickup.collect_into(inventory) == 5, "ammo pickup transfers into inventory", failures)
	_expect(inventory.ammo_item_count(37) == 30, "pickup increments the matching ammo item", failures)
	_expect(pickup.collect_into(inventory) == 0, "ammo pickup cannot be collected twice", failures)
	_expect(int(inventory.full_snapshot().get("schema_version", 0)) == 2, "inventory snapshot is versioned", failures)
	pickup.free()


func _test_direct_projectile(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 20, Vector2.ZERO, arena)
	source.projectile_launch_offset = Vector2(-13.0, 0.0)
	source.projectile_vertical_baseline = 148.0
	var friendly := _combatant(3, 20, Vector2(50.0, 0.0), arena)
	var enemy := _combatant(1, 20, Vector2(100.0, 0.0), arena)
	var projectile = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(projectile)
	var candidates: Array[Node2D] = [friendly, enemy]
	_expect(
		projectile.configure(
			source,
			enemy,
			enemy.global_position,
			COMBAT_PROFILES.weapon_profile("dart_attack"),
			PROJECTILE_PROFILES.profile_for_attack_type(6),
			candidates,
		),
		"dart projectile configures",
		failures,
	)
	_expect(
		projectile.start_world_position == Vector2(-13.0, 0.0)
		and projectile.visual_height == 148.0,
		"direct projectile uses the recovered SPR launch X and visual Z offsets",
		failures,
	)
	projectile.advance_simulation(0.25)
	_expect(projectile.is_resolved(), "dart resolves after reaching target", failures)
	_expect(
		friendly.hit_points == 12,
		"dart hits the first valid layer-3 actor regardless of faction",
		failures,
	)
	_expect(enemy.hit_points == 20, "a nearer actor shields the intended target", failures)

	var sling = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(sling)
	friendly.position = Vector2(50.0, 40.0)
	var sling_profile: Dictionary = PROJECTILE_PROFILES.profile_for_attack_type(7)
	var sling_candidates: Array[Node2D] = [enemy]
	_expect(
		sling.configure(
			source,
			enemy,
			enemy.global_position,
			COMBAT_PROFILES.weapon_profile("slingshot_attack"),
			sling_profile,
			sling_candidates,
		),
		"slingshot projectile configures",
		failures,
	)
	sling.advance_world_ticks(2)
	_expect(
		sling.visual_height == 148.0 and sling.path_index == 10,
		"slingshot keeps recovered visual Z while advancing five pixels per world tick",
		failures,
	)
	var blocker := BlockingNavigation.new()
	blocker.blocked_cells[Vector2i(1, 0)] = true
	var blocked_dart = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(blocked_dart)
	var no_middle_candidates: Array[Node2D] = [source, enemy]
	_expect(
		blocked_dart.configure(
			source,
			enemy,
			enemy.global_position,
			COMBAT_PROFILES.weapon_profile("dart_attack"),
			PROJECTILE_PROFILES.profile_for_attack_type(6),
			no_middle_candidates,
			blocker,
		),
		"blocked dart configures against an L2 grid",
		failures,
	)
	blocked_dart.advance_simulation(0.25)
	_expect(
		blocked_dart.is_resolved() and enemy.hit_points == 20,
		"mode 3 stops at the first layer-2 obstruction",
		failures,
	)
	arena.queue_free()


func _test_grenade_blast(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 300, Vector2.ZERO, arena)
	var enemy := _combatant(1, 300, Vector2(200.0, 0.0), arena)
	var friendly := _combatant(3, 300, Vector2(230.0, 20.0), arena)
	var outside_horizontal := _combatant(1, 300, Vector2(340.0, 0.0), arena)
	var outside_vertical := _combatant(1, 300, Vector2(200.0, 70.0), arena)
	var projectile = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(projectile)
	var candidates: Array[Node2D] = [source, enemy, friendly, outside_horizontal, outside_vertical]
	_expect(
		projectile.configure(
			source,
			enemy,
			Vector2(200.0, 0.0),
			COMBAT_PROFILES.weapon_profile("grenade_attack"),
			PROJECTILE_PROFILES.profile_for_attack_type(9),
			candidates,
		),
		"grenade projectile configures",
		failures,
	)
	projectile.advance_world_ticks(13)
	_expect(projectile.visual_height > 0.0 and not projectile.is_resolved(), "grenade has an in-flight arc", failures)
	projectile.advance_world_ticks(12)
	_expect(
		not projectile.is_resolved() and projectile.path_index == projectile.path_points.size() - 1,
		"grenade reaches the endpoint without an invented landing delay",
		failures,
	)
	projectile.advance_world_ticks(1)
	_expect(projectile.is_resolved(), "endpoint world tick creates actor 61 immediately", failures)
	_expect(enemy.hit_points == 172, "grenade applies recovered 128 enemy damage", failures)
	_expect(friendly.hit_points == 172, "grenade applies recovered friendly fire", failures)
	_expect(source.hit_points == 300, "thrower outside blast ellipse is unharmed", failures)
	_expect(outside_horizontal.hit_points == 300, "horizontal blast bound is enforced", failures)
	_expect(outside_vertical.hit_points == 300, "vertical blast bound is enforced", failures)
	var blocked_grenade = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(blocked_grenade)
	var blocker := BlockingNavigation.new()
	blocker.blocked_cells[Vector2i(2, 0)] = true
	var no_grenade_candidates: Array[Node2D] = []
	_expect(
		blocked_grenade.configure(
			source,
			enemy,
			Vector2(200.0, 0.0),
			COMBAT_PROFILES.weapon_profile("grenade_attack"),
			PROJECTILE_PROFILES.profile_for_attack_type(9),
			no_grenade_candidates,
			blocker,
		),
		"grenade configures across a blocked L2 cell",
		failures,
	)
	blocked_grenade.advance_world_ticks(26)
	_expect(
		blocked_grenade.is_resolved(),
		"mode 1 ignores actors and L2 obstruction until destination",
		failures,
	)
	arena.queue_free()


func _test_projectile_world(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 20, Vector2.ZERO, arena)
	var enemy := _combatant(1, 20, Vector2(80.0, 0.0), arena)
	var world = PROJECTILE_WORLD_SCRIPT.new()
	arena.add_child(world)
	var candidates: Array[Node2D] = [source, enemy]
	world.set_combatants(candidates)
	_expect(world.supports_attack_type(6), "projectile world accepts darts", failures)
	_expect(not world.supports_attack_type(2), "projectile world leaves rifles on direct-hit path", failures)
	var projectile = world.launch_for_weapon(
		source, enemy, COMBAT_PROFILES.weapon_profile("dart_attack")
	)
	_expect(projectile != null, "projectile world launches configured projectile", failures)
	projectile.advance_world_ticks(6)
	_expect(enemy.hit_points == 12, "projectile world launch reaches combat damage path", failures)
	_expect(
		world.launch_for_weapon(source, enemy, COMBAT_PROFILES.weapon_profile("rifle_attack")) == null,
		"direct-hit weapon does not create a projectile",
		failures,
	)
	arena.queue_free()


func _test_projectile_snapshot_restore(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 300, Vector2.ZERO, arena)
	var target := _combatant(1, 300, Vector2(200.0, 0.0), arena)
	var candidates: Array[Node2D] = [source, target]
	var original = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(original)
	var weapon: Dictionary = COMBAT_PROFILES.weapon_profile("grenade_attack")
	var profile: Dictionary = PROJECTILE_PROFILES.profile_for_attack_type(9)
	_expect(
		original.configure(
			source,
			target,
			target.global_position,
			weapon,
			profile,
			candidates,
		),
		"snapshot source grenade configures",
		failures,
	)
	original.advance_world_ticks(9)
	var snapshot := original.snapshot_runtime_state() as Dictionary
	var restored = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(restored)
	_expect(
		restored.configure(
			source,
			target,
			target.global_position,
			weapon,
			profile,
			candidates,
			null,
			null,
			{},
			original.start_world_position,
		)
		and restored.restore_runtime_state(snapshot),
		"schema-2 projectile state restores onto the same fixed path",
		failures,
	)
	_expect(
		restored.path_index == original.path_index
		and restored.arc_tick == original.arc_tick
		and restored.global_position == original.global_position
		and restored.visual_height == original.visual_height,
		"save/load preserves exact path index, arc tick, position and height",
		failures,
	)
	original.advance_world_ticks(17)
	restored.advance_world_ticks(17)
	_expect(
		original.is_resolved()
		and restored.is_resolved()
		and target.hit_points == 44,
		"restored and uninterrupted grenades resolve on the same endpoint tick",
		failures,
	)
	arena.queue_free()


func _test_squad_inventory_and_projectile_integration(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var clear_sight := ClearSight.new()
	var empty_groups: Array[Dictionary] = []
	var attacker = SQUAD_UNIT_SCRIPT.new()
	attacker.configure(
		"inventory player",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	attacker.configure_combat(
		3,
		20,
		COMBAT_PROFILES.weapon_profile("pistol_attack"),
		empty_groups,
		empty_groups,
		false,
	)
	var target = SQUAD_UNIT_SCRIPT.new()
	target.configure(
		"target",
		Color.WHITE,
		Vector2(100.0, 0.0),
		null,
		empty_groups,
		empty_groups,
		-1,
		clear_sight,
	)
	target.configure_combat(1, 20, {}, empty_groups, empty_groups, true)
	attacker.runtime_actor_type = 1
	target.runtime_actor_type = 1
	arena.add_child(attacker)
	arena.add_child(target)
	_expect(
		int((attacker.inventory_snapshot().get("items", {}) as Dictionary).get(36, 0)) == 32,
		"SquadUnit exposes CombatInventory as its authoritative pistol reserve",
		failures,
	)
	var dart_profile: Dictionary = COMBAT_PROFILES.weapon_profile("dart_attack")
	_expect(
		attacker.register_inventory_weapon(dart_profile, empty_groups, true, true),
		"SquadUnit can register and equip a recovered pickup weapon",
		failures,
	)
	_expect(
		int(attacker.weapon_profile.get("attack_type", 0)) == 6
		and attacker.magazine_ammo == 8
		and attacker.reserve_ammo == 24,
		"weapon switching synchronizes the active profile and UI ammunition mirror",
		failures,
	)
	var world = PROJECTILE_WORLD_SCRIPT.new()
	arena.add_child(world)
	var combatants: Array[Node2D] = [attacker, target]
	world.set_combatants(combatants)
	var launched: Array[Node2D] = []
	world.projectile_launched.connect(
		func(projectile: Node2D, _source: Node2D, _attack_type: int) -> void:
			launched.append(projectile)
	)
	attacker.projectile_requested.connect(
		func(source: Node2D, victim: Node2D, profile: Dictionary) -> void:
			world.launch_for_weapon(source, victim, profile)
	)
	_expect(attacker.try_start_attack(target), "SquadUnit commits a dart attack", failures)
	_expect(
		launched.size() == 1 and target.current_hit_points == 20,
		"the final attack frame launches a world projectile instead of applying instant damage",
		failures,
	)
	launched[0].advance_world_ticks(8)
	_expect(
		target.current_hit_points == 12,
		"the launched SquadUnit dart reaches the shared damage path",
		failures,
	)
	_expect(
		attacker.magazine_ammo == 7
		and int((attacker.inventory_snapshot().get("weapons", {}) as Dictionary)["dart_attack"]["magazine"]) == 7,
		"SquadUnit ammunition mirror cannot diverge from its backpack after firing",
		failures,
	)
	arena.queue_free()


func _combatant(
	faction: int,
	hit_points: int,
	world_position: Vector2,
	parent: Node,
) -> MockCombatant:
	var result := MockCombatant.new()
	next_scene_index += 1
	result.configure(
		faction,
		hit_points,
		world_position,
		next_scene_index,
	)
	parent.add_child(result)
	return result


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(label)
