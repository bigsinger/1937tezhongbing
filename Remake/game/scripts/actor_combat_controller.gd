class_name ActorCombatController
extends RefCounted

const PISTOL_HIT_CHANCE := 0.80
const RIFLE_HIT_CHANCE := 0.90
const MELEE_HIT_CHANCE := 1.0


static func player_hit_chance(attack_type: int) -> float:
	match attack_type:
		1:
			return PISTOL_HIT_CHANCE
		2:
			return RIFLE_HIT_CHANCE
		4, 5:
			return MELEE_HIT_CHANCE
		_:
			return 1.0


static func deterministic_accuracy_sample(
	actor_scene_index: int,
	attack_serial: int,
	attack_type: int,
) -> float:
	var sample := posmod(
		actor_scene_index * 1103515245
		+ attack_serial * 12345
		+ attack_type * 265443576,
		10000,
	)
	return float(sample) / 10000.0


static func player_attack_will_hit(
	actor_scene_index: int,
	attack_serial: int,
	attack_type: int,
) -> bool:
	return deterministic_accuracy_sample(
		actor_scene_index,
		attack_serial,
		attack_type,
	) < player_hit_chance(attack_type)


static func target_in_range(
	actor_position: Vector2,
	target_position: Vector2,
	attack_range: float,
) -> bool:
	return actor_position.distance_squared_to(target_position) <= attack_range * attack_range
