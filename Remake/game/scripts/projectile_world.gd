class_name ProjectileWorld
extends Node2D

signal projectile_launched(projectile: Node2D, attacker: Node2D, attack_type: int)
signal projectile_damage_applied(attacker: Node2D, victim: Node2D, attack_type: int, damage: int)
signal projectile_impact_created(
	attacker: Node2D,
	world_position: Vector2,
	attack_type: int,
	runtime_actor_type: int,
	original_gfl_index: int,
)
signal projectile_exploded(attacker: Node2D, world_position: Vector2, horizontal_radius: float, vertical_radius: float)
signal projectile_explosion_actor_requested(
	attacker: Node2D,
	world_position: Vector2,
	runtime_actor_type: int,
	special_bursts: Array[Dictionary],
)

const COMBAT_PROJECTILE_SCRIPT: Script = preload("res://scripts/combat_projectile.gd")
const PROJECTILE_PROFILES: Script = preload("res://scripts/projectile_profiles.gd")
const LEGACY_COMBAT_RULES: Script = preload("res://scripts/legacy_combat_rules.gd")

var combatants: Array[Node2D] = []
var navigation_grid: Variant
var dynamic_occupancy: Variant
var visual_catalog: Dictionary = {}


func configure_runtime(
	new_navigation_grid: Variant,
	new_dynamic_occupancy: Variant,
	new_visual_catalog: Dictionary = {},
) -> void:
	navigation_grid = new_navigation_grid
	dynamic_occupancy = new_dynamic_occupancy
	visual_catalog = new_visual_catalog.duplicate()


func set_combatants(new_combatants: Array[Node2D]) -> void:
	combatants = new_combatants.duplicate()


func add_combatant(combatant: Node2D) -> void:
	if combatant != null and not combatants.has(combatant):
		combatants.append(combatant)


func remove_combatant(combatant: Node2D) -> void:
	combatants.erase(combatant)


func launch_for_weapon(
	attacker: Node2D,
	target: Node2D,
	weapon_profile: Dictionary,
	target_world_position: Variant = null,
	start_world_position: Variant = null,
) -> Node2D:
	var attack_type := int(weapon_profile.get("attack_type", 0))
	var projectile_profile: Dictionary = PROJECTILE_PROFILES.profile_for_attack_type(attack_type)
	if projectile_profile.is_empty() or attacker == null:
		return null
	var destination: Vector2
	if target_world_position is Vector2:
		destination = target_world_position as Vector2
	elif target != null:
		destination = target.global_position
	else:
		return null
	var projectile: Node2D = COMBAT_PROJECTILE_SCRIPT.new()
	add_child(projectile)
	var projectile_visual := (
		visual_catalog.get(
			int(projectile_profile.get("original_gfl_index", 0)),
			{},
		) as Dictionary
	).duplicate()
	var impact_visual_value: Variant = visual_catalog.get(
		int(projectile_profile.get("impact_gfl_index", 0)),
		{},
	)
	if impact_visual_value is Dictionary:
		projectile_visual["impact_visual"] = (
			impact_visual_value as Dictionary
		).duplicate()
	if not projectile.configure(
		attacker,
		target,
		destination,
		weapon_profile,
		projectile_profile,
		combatants,
		navigation_grid,
		dynamic_occupancy,
		projectile_visual,
		start_world_position,
	):
		projectile.queue_free()
		return null
	projectile.damage_applied.connect(
		func(_projectile: Node2D, victim: Node2D, applied: int) -> void:
			projectile_damage_applied.emit(attacker, victim, attack_type, applied)
	)
	projectile.impact_created.connect(
		func(
			_projectile: Node2D,
			world_position: Vector2,
			runtime_actor_type: int,
			original_gfl_index: int,
		) -> void:
			projectile_impact_created.emit(
				attacker,
				world_position,
				attack_type,
				runtime_actor_type,
				original_gfl_index,
			)
	)
	projectile.exploded.connect(
		func(
			_projectile: Node2D,
			world_position: Vector2,
			horizontal_radius: float,
			vertical_radius: float,
		) -> void:
			projectile_exploded.emit(
				attacker, world_position, horizontal_radius, vertical_radius
			)
	)
	projectile.explosion_actor_requested.connect(
		func(
			_projectile: Node2D,
			explosion_attacker: Node2D,
			world_position: Vector2,
			runtime_actor_type: int,
			special_bursts: Array[Dictionary],
		) -> void:
			projectile_explosion_actor_requested.emit(
				explosion_attacker,
				world_position,
				runtime_actor_type,
				special_bursts,
			)
	)
	projectile_launched.emit(projectile, attacker, attack_type)
	return projectile


func launch_all_for_weapon(
	attacker: Node2D,
	target: Node2D,
	weapon_profile: Dictionary,
	target_world_position: Variant = null,
	start_world_position: Variant = null,
) -> Array[Node2D]:
	if attacker == null:
		return []
	var destination: Vector2
	var has_live_actor_target := target != null and is_instance_valid(target)
	if target_world_position is Vector2:
		destination = target_world_position as Vector2
	elif has_live_actor_target:
		destination = target.global_position
	else:
		return []
	var source_position := (
		start_world_position as Vector2
		if start_world_position is Vector2
		else attacker.global_position
	)
	var destinations: PackedVector2Array = (
		LEGACY_COMBAT_RULES.coordinate_projectile_destinations(
			int(weapon_profile.get("attack_type", 0)),
			source_position,
			destination,
			has_live_actor_target,
		)
	)
	var launched: Array[Node2D] = []
	for projectile_destination: Vector2 in destinations:
		var projectile := launch_for_weapon(
			attacker,
			target,
			weapon_profile,
			projectile_destination,
			start_world_position,
		)
		if projectile != null:
			launched.append(projectile)
	return launched


func supports_attack_type(attack_type: int) -> bool:
	return PROJECTILE_PROFILES.is_projectile_attack(attack_type)
