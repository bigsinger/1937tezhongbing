class_name ActorMovementController
extends RefCounted

const PROGRESS_EPSILON := 2.0

var last_distance := INF
var no_progress_ticks := 0
var last_path_index := -1


func reset() -> void:
	last_distance = INF
	no_progress_ticks = 0
	last_path_index = -1


func observe_progress(path_index: int, distance: float) -> Dictionary:
	var progressed := (
		path_index > last_path_index
		or not is_finite(last_distance)
		or distance + PROGRESS_EPSILON < last_distance
	)
	if progressed:
		no_progress_ticks = 0
	else:
		no_progress_ticks += 1
	last_path_index = path_index
	last_distance = distance
	return {
		"progressed": progressed,
		"no_progress_ticks": no_progress_ticks,
		"path_index": path_index,
		"distance": distance,
	}


func proposed_position(
	position: Vector2,
	waypoint: Vector2,
	max_distance: float,
) -> Vector2:
	# Preserve Node2D's scalar move_toward semantics.  The controller owns the
	# proposal calculation, while the authoritative occupancy service still
	# decides whether the actor may commit it.
	return position.move_toward(waypoint, maxf(max_distance, 0.0))


func snapshot() -> Dictionary:
	return {
		"last_distance": last_distance if is_finite(last_distance) else -1.0,
		"no_progress_ticks": no_progress_ticks,
		"last_path_index": last_path_index,
	}
