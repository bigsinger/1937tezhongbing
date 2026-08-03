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
const ORIGINAL_CELL_SIZE := Vector2i(32, 16)
const MACHINE_GUN_LIVE_TARGET_SPREAD_DEGREES := [0, -1, 1]
const MACHINE_GUN_COORDINATE_SPREAD_DEGREES := [0, -2, 2]
# sub_457B40/sub_41D6A0 commit on entry to the final authored SPR frame and
# immediately restore the idle serial. RuntimeActorV1 has no separate attack
# recovery timer.
const HAS_INDEPENDENT_ATTACK_RECOVERY_DELAY := false
const ATTACK_COMMITS_ON_FINAL_FRAME_ENTRY := true
const ATTACK_RETURNS_IDLE_ON_COMMIT_UPDATE := true


static func attack_commit_animation_ticks(
	frame_count: int,
	frame_hold_ticks: int,
) -> int:
	if frame_count <= 1:
		return 0
	return (frame_count - 1) * maxi(frame_hold_ticks, 1)


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


static func navigation_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(ORIGINAL_CELL_SIZE.x)),
		floori(world_position.y / float(ORIGINAL_CELL_SIZE.y)),
	)


static func attack_target_cell_coincides(
	attacker_world_position: Vector2,
	target_world_position: Vector2,
) -> bool:
	# sub_45F000 compares RuntimeActorV1 +0x108/+0x110 and accepts one
	# navigation cell of separation on each axis.
	var attacker_cell := navigation_cell(attacker_world_position)
	var target_cell := navigation_cell(target_world_position)
	return (
		absi(attacker_cell.x - target_cell.x) <= 1
		and absi(attacker_cell.y - target_cell.y) <= 1
	)


static func coordinate_projectile_destinations(
	attack_type: int,
	source_world_position: Vector2,
	target_world_position: Vector2,
	has_live_actor_target: bool = true,
) -> PackedVector2Array:
	if coordinate_projectile_count(attack_type) <= 0:
		return PackedVector2Array()
	if attack_type != 3:
		return PackedVector2Array([target_world_position])
	var result := PackedVector2Array()
	var offsets: Array = (
		MACHINE_GUN_LIVE_TARGET_SPREAD_DEGREES
		if has_live_actor_target
		else MACHINE_GUN_COORDINATE_SPREAD_DEGREES
	)
	var original_distance := int(
		source_world_position.distance_to(target_world_position)
	)
	var original_angle := fposmod(
		rad_to_deg(
			atan2(
				source_world_position.y - target_world_position.y,
				source_world_position.x - target_world_position.x,
			)
		),
		360.0,
	)
	for offset_degrees: int in offsets:
		if offset_degrees == 0:
			result.append(target_world_position)
		else:
			result.append(
				_original_endpoint_from_angle(
					original_angle + float(offset_degrees),
					original_distance,
					source_world_position,
				)
			)
	return result


static func _original_endpoint_from_angle(
	angle_degrees: float,
	distance: int,
	source_world_position: Vector2,
) -> Vector2:
	# sub_45DD50 converts degrees to radians, truncates both products through
	# __ftol, and applies the original 0.5 vertical isometric scale.
	var angle_radians := deg_to_rad(angle_degrees)
	return Vector2(
		int(source_world_position.x)
			- int(cos(angle_radians) * float(distance)),
		int(source_world_position.y)
			- int(sin(angle_radians) * float(distance) * 0.5),
	)
