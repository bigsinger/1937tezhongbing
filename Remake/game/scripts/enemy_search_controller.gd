class_name EnemySearchController
extends RefCounted

const ROLES: Array[String] = ["lead", "left", "right", "rear_block"]


func build_assignments(
	last_known_position: Vector2,
	approach_direction: Vector2,
	actor_ids: Array[int],
	radius: float = 96.0,
) -> Array[Dictionary]:
	var forward := approach_direction.normalized()
	if forward.is_zero_approx():
		forward = Vector2.RIGHT
	var side := forward.orthogonal()
	var result: Array[Dictionary] = []
	for index: int in range(actor_ids.size()):
		var role := ROLES[mini(index, ROLES.size() - 1)]
		var offset := Vector2.ZERO
		match role:
			"lead": offset = forward * radius * 0.45
			"left": offset = side * radius * 0.65
			"right": offset = -side * radius * 0.65
			"rear_block":
				var rear_index := maxi(index - 3, 0)
				var side_sign := -1.0 if posmod(rear_index, 2) == 0 else 1.0
				var ring := float(rear_index / 2)
				offset = (
					-forward * radius * (0.55 + ring * 0.35)
					+ side * side_sign * radius * (0.22 + ring * 0.12)
				)
		result.append({"actor_id": actor_ids[index], "role": role, "position": last_known_position + offset})
	return result


static func build_order(
	last_known_position: Vector2,
	source_position: Vector2,
	target_velocity: Vector2,
	recipient_index: int,
	recipient_count: int,
	wide_flank: bool,
) -> Dictionary:
	var forward := target_velocity.normalized()
	if forward.is_zero_approx():
		forward = (last_known_position - source_position).normalized()
	if forward.is_zero_approx():
		forward = Vector2.RIGHT
	var side := forward.orthogonal()
	var role := "lead"
	var offset := forward * 48.0
	var spacing := 80.0 if wide_flank else 40.0
	match recipient_index:
		0:
			role = "lead"
		1:
			role = "left_flank"
			offset = side * spacing - forward * 12.0
		2:
			role = "right_flank"
			offset = -side * spacing - forward * 12.0
		_:
			role = "rear_block"
			var side_sign := -1.0 if posmod(recipient_index, 2) == 0 else 1.0
			offset = (
				-forward * (48.0 + float(recipient_index - 3) * 24.0)
				+ side * side_sign * spacing * 0.5
			)
	if maxi(recipient_count, 1) == 1:
		role = "lead"
		offset = Vector2.ZERO
	var preferred := last_known_position + offset
	var candidates: Array[Vector2] = [preferred]
	var compact := last_known_position + offset * 0.5
	if not compact.is_equal_approx(preferred):
		candidates.append(compact)
	if not last_known_position.is_equal_approx(candidates[-1]):
		candidates.append(last_known_position)
	return {
		"role": role,
		"candidates": candidates,
		"last_known_position": last_known_position,
	}
