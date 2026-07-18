class_name ProjectileWorld
extends Node2D

signal projectile_launched(projectile: Node2D, attacker: Node2D, attack_type: int)
signal projectile_damage_applied(attacker: Node2D, victim: Node2D, attack_type: int, damage: int)
signal projectile_exploded(attacker: Node2D, world_position: Vector2, horizontal_radius: float, vertical_radius: float)

const COMBAT_PROJECTILE_SCRIPT: Script = preload("res://scripts/combat_projectile.gd")
const PROJECTILE_PROFILES: Script = preload("res://scripts/projectile_profiles.gd")

var combatants: Array[Node2D] = []


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
	if not projectile.configure(
		attacker,
		target,
		destination,
		weapon_profile,
		projectile_profile,
		combatants,
	):
		projectile.queue_free()
		return null
	projectile.damage_applied.connect(
		func(_projectile: Node2D, victim: Node2D, applied: int) -> void:
			projectile_damage_applied.emit(attacker, victim, attack_type, applied)
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
	projectile_launched.emit(projectile, attacker, attack_type)
	return projectile


func supports_attack_type(attack_type: int) -> bool:
	return PROJECTILE_PROFILES.is_projectile_attack(attack_type)
