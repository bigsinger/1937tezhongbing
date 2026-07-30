class_name LegacyCombatRules
extends RefCounted

## Exact ordinary-combat branches recovered from M1937.exe sub_456DF0 and
## sub_458700. Runtime actor type belongs to the attacker for weapon damage
## overrides and to the recipient for the low-damage immunity gate.

const LOW_DAMAGE_IMMUNE_ACTOR_TYPES := {
	34: true,
	86: true,
	87: true,
	88: true,
	94: true,
	95: true,
	96: true,
	97: true,
}
const LOW_DAMAGE_IMMUNITY_THRESHOLD := 32


static func direct_actor_damage(
	attack_type: int,
	attacker_runtime_actor_type: int,
	fallback_damage: int,
) -> int:
	match attack_type:
		1, 3:
			return 2
		2:
			return 16 if attacker_runtime_actor_type == 1 else 2
		4:
			return 1 if attacker_runtime_actor_type == 56 else 8
		5:
			return 16
		6:
			return 8
		7:
			return 1
	return maxi(fallback_damage, 0)


static func direct_actor_hit_count(attack_type: int) -> int:
	# Machine-gun attack type 3 creates three spread projectiles only for a
	# coordinate/non-adjacent target path. A resolved actor target receives one
	# call to sub_458700, exactly like pistol and rifle targets.
	return 1 if attack_type >= 1 and attack_type <= 7 else 0


static func coordinate_projectile_count(attack_type: int) -> int:
	return 3 if attack_type == 3 else (1 if attack_type in [1, 2, 6, 7, 9] else 0)


static func accepted_actor_damage(runtime_actor_type: int, requested_damage: int) -> int:
	var damage := maxi(requested_damage, 0)
	if (
		damage < LOW_DAMAGE_IMMUNITY_THRESHOLD
		and LOW_DAMAGE_IMMUNE_ACTOR_TYPES.has(runtime_actor_type)
	):
		return 0
	return damage
