extends SceneTree

const AMMO_PICKUP_SCRIPT: Script = preload("res://scripts/ammo_pickup.gd")
const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const COMBAT_PROJECTILE_SCRIPT: Script = preload("res://scripts/combat_projectile.gd")
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
	var damage_events: Array[int] = []

	func configure(new_faction: int, new_hit_points: int, world_position: Vector2) -> void:
		faction_id = new_faction
		hit_points = new_hit_points
		position = world_position

	func is_combat_alive() -> bool:
		return hit_points > 0

	func take_damage(amount: int, _attacker: Node2D = null) -> int:
		var applied := mini(maxi(amount, 0), hit_points)
		hit_points -= applied
		if applied > 0:
			damage_events.append(applied)
		return applied


var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_projectile_profiles(failures)
	_test_inventory_and_pickup(failures)
	_test_direct_projectile(failures)
	_test_grenade_blast(failures)
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
	_expect(float(grenade.get("blast_horizontal_radius", 0.0)) > 0.0, "grenade has a blast radius", failures)
	_expect(bool(grenade.get("friendly_fire", false)), "grenade explicitly enables friendly fire", failures)
	_expect(
		String((grenade.get("source_status", {}) as Dictionary).get("friendly_fire", ""))
		== "unresolved_remake_default",
		"unrecovered grenade friendly-fire rule is marked as a remake default",
		failures,
	)


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
	_expect(int(inventory.full_snapshot().get("schema_version", 0)) == 1, "inventory snapshot is versioned", failures)
	pickup.free()


func _test_direct_projectile(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 20, Vector2.ZERO, arena)
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
	projectile.advance_simulation(0.25)
	_expect(projectile.is_resolved(), "dart resolves after reaching target", failures)
	_expect(friendly.hit_points == 20, "dart ignores a friendly actor in its path", failures)
	_expect(enemy.hit_points == 12, "dart applies recovered eight damage on impact", failures)

	var sling = COMBAT_PROJECTILE_SCRIPT.new()
	arena.add_child(sling)
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
	sling.advance_simulation(sling.flight_duration * 0.5)
	_expect(sling.visual_height > 0.0, "slingshot follows a visible arc", failures)
	arena.queue_free()


func _test_grenade_blast(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := _combatant(3, 30, Vector2.ZERO, arena)
	var enemy := _combatant(1, 30, Vector2(200.0, 0.0), arena)
	var friendly := _combatant(3, 30, Vector2(230.0, 20.0), arena)
	var outside_horizontal := _combatant(1, 30, Vector2(340.0, 0.0), arena)
	var outside_vertical := _combatant(1, 30, Vector2(200.0, 70.0), arena)
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
	projectile.advance_simulation(projectile.flight_duration * 0.5)
	_expect(projectile.visual_height > 0.0 and not projectile.is_resolved(), "grenade has an in-flight arc", failures)
	projectile.advance_simulation(projectile.flight_duration * 0.5 + 0.36)
	_expect(projectile.is_resolved(), "landed grenade detonates after its delay", failures)
	_expect(enemy.hit_points == 14, "grenade damages an enemy inside blast ellipse", failures)
	_expect(friendly.hit_points == 14, "grenade friendly fire damages an ally inside blast ellipse", failures)
	_expect(source.hit_points == 30, "thrower outside blast ellipse is unharmed", failures)
	_expect(outside_horizontal.hit_points == 30, "horizontal blast bound is enforced", failures)
	_expect(outside_vertical.hit_points == 30, "vertical blast bound is enforced", failures)
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
	projectile.advance_simulation(0.25)
	_expect(enemy.hit_points == 12, "projectile world launch reaches combat damage path", failures)
	_expect(
		world.launch_for_weapon(source, enemy, COMBAT_PROFILES.weapon_profile("rifle_attack")) == null,
		"direct-hit weapon does not create a projectile",
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
	launched[0].advance_simulation(0.25)
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
	result.configure(faction, hit_points, world_position)
	parent.add_child(result)
	return result


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(label)
