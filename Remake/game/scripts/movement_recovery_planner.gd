class_name MovementRecoveryPlanner
extends RefCounted

const DEFAULT_REPLAN_DISTANCE := 28.0
const ENDPOINT_TOLERANCE := 20.0
## A hard-stuck actor used to evaluate all eight neighbours and run two A*
## queries for each viable one. Several blocked actors could therefore produce
## a burst of 80+ queries in one physics frame. Static clearance and goal
## distance provide a cheap deterministic ranking; only the best three cells
## need an actual escape + continuation query.
const MAX_CANDIDATE_ROUTES := 3


static func chase_replan_required(
	current_goal: Vector2,
	new_goal: Vector2,
	path_active: bool,
	threshold: float = DEFAULT_REPLAN_DISTANCE,
) -> bool:
	if not path_active or current_goal.x == INF or current_goal.y == INF:
		return true
	return current_goal.distance_squared_to(new_goal) >= threshold * threshold


## Builds a deterministic, non-teleporting escape route around the currently
## blocked waypoint.  Candidate cells with more static clearance win, while
## scene-index parity prevents two face-to-face actors from choosing the same
## side.  Queries are bounded to the eight neighbouring cells and happen only
## after the progress watchdog declares a hard stall.
static func recovery_path(
	dynamic_occupancy: Variant,
	scene_index: int,
	world_start: Vector2,
	world_goal: Vector2,
	blocked_waypoint: Vector2,
) -> PackedVector2Array:
	if (
		dynamic_occupancy == null
		or scene_index < 0
		or not dynamic_occupancy.has_method("preview_path_for_scene")
	):
		return PackedVector2Array()
	var navigation: Variant = dynamic_occupancy.get("navigation")
	if (
		navigation == null
		or not navigation.has_method("world_to_cell")
		or not navigation.has_method("cell_to_world")
		or not navigation.has_method("is_valid_cell")
		or not navigation.has_method("is_movement_blocked")
	):
		return PackedVector2Array()
	var start_cell: Vector2i = navigation.call("world_to_cell", world_start)
	var blocked_cell: Vector2i = navigation.call("world_to_cell", blocked_waypoint)
	var desired := world_goal - world_start
	var preferred := Vector2i(1, 0)
	if not desired.is_zero_approx():
		var normalized := desired.normalized()
		preferred = Vector2i(signi(roundi(normalized.x)), signi(roundi(normalized.y)))
		if preferred == Vector2i.ZERO:
			preferred = Vector2i(1, 0)
	var side := Vector2i(-preferred.y, preferred.x)
	var ordered: Array[Vector2i] = [
		side,
		-side,
		preferred + side,
		preferred - side,
		preferred,
		-preferred + side,
		-preferred - side,
		-preferred,
	]
	if posmod(scene_index, 2) == 1:
		ordered[0] = -side
		ordered[1] = side
		ordered[2] = preferred - side
		ordered[3] = preferred + side
	var candidates: Array[Dictionary] = []
	for ordinal: int in range(ordered.size()):
		var candidate_cell := start_cell + ordered[ordinal]
		if (
			candidate_cell == blocked_cell
			or not bool(navigation.call("is_valid_cell", candidate_cell))
			or bool(navigation.call("is_movement_blocked", candidate_cell))
		):
			continue
		var candidate_world: Vector2 = navigation.call("cell_to_world", candidate_cell)
		var clearance := _static_clearance(navigation, candidate_cell)
		candidates.append({
			"cell": candidate_cell,
			"world": candidate_world,
			"ordinal": ordinal,
			"score": (
				candidate_world.distance_to(world_goal)
				+ float(ordinal) * 0.25
				- float(clearance) * 5.0
			),
		})
	# Selection-sort only the tiny local candidate set. Avoiding a closure here
	# keeps this recovery path allocation-light on older compatibility renderers.
	for left: int in range(candidates.size()):
		var best_index := left
		for right: int in range(left + 1, candidates.size()):
			var right_score := float(candidates[right].get("score", INF))
			var best_score := float(candidates[best_index].get("score", INF))
			if (
				right_score < best_score
				or (
					is_equal_approx(right_score, best_score)
					and int(candidates[right].get("ordinal", 0))
						< int(candidates[best_index].get("ordinal", 0))
				)
			):
				best_index = right
		if best_index != left:
			var swap := candidates[left]
			candidates[left] = candidates[best_index]
			candidates[best_index] = swap
	var route_limit := mini(candidates.size(), MAX_CANDIDATE_ROUTES)
	for candidate_index: int in range(route_limit):
		var candidate := candidates[candidate_index]
		var candidate_world := candidate.get("world", world_start) as Vector2
		var escape: PackedVector2Array = dynamic_occupancy.call(
			"preview_path_for_scene",
			scene_index,
			world_start,
			candidate_world,
		)
		if escape.is_empty() or escape[-1].distance_to(candidate_world) > ENDPOINT_TOLERANCE:
			continue
		var continuation: PackedVector2Array = dynamic_occupancy.call(
			"preview_path_for_scene",
			scene_index,
			candidate_world,
			world_goal,
		)
		if continuation.is_empty():
			continue
		var combined := escape.duplicate()
		for point: Vector2 in continuation:
			if combined.is_empty() or not combined[-1].is_equal_approx(point):
				combined.append(point)
		return combined
	return PackedVector2Array()


static func _static_clearance(navigation: Variant, center: Vector2i) -> int:
	var clear := 0
	for y_offset: int in range(-1, 2):
		for x_offset: int in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			var cell := center + Vector2i(x_offset, y_offset)
			if (
				bool(navigation.call("is_valid_cell", cell))
				and not bool(navigation.call("is_movement_blocked", cell))
			):
				clear += 1
	return clear
