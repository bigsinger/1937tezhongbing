class_name BurialCommandController
extends RefCounted

# Original S/B interaction coordinates use the recovered logical 32x16 cell,
# independently of the wider visual/navigation footprint used by some actors.
const GRID_SIZE := Vector2i(32, 16)

var target: Node2D
var worker: Node2D
var progress_ticks := 0
var action_started := false
var counter_limit := 100


func begin(new_worker: Node2D, new_target: Node2D, limit: int = 100) -> bool:
	cancel()
	if new_worker == null or new_target == null:
		return false
	worker = new_worker
	target = new_target
	counter_limit = maxi(limit, 1)
	return true


func advance() -> Dictionary:
	if not is_valid():
		cancel()
		return {"state": "cancelled"}
	if not in_range(worker.position, target.position):
		if action_started:
			action_started = false
			progress_ticks = 0
		return {"state": "approach", "progress": 0.0}
	if not action_started:
		action_started = true
		progress_ticks = 0
	progress_ticks += 1
	var ratio := clampf(float(progress_ticks) / float(counter_limit), 0.0, 1.0)
	return {
		"state": "complete" if progress_ticks > counter_limit else "working",
		"progress": ratio,
		"progress_ticks": progress_ticks,
	}


func cancel() -> void:
	target = null
	worker = null
	progress_ticks = 0
	action_started = false


func is_valid() -> bool:
	return (
		target != null and worker != null
		and is_instance_valid(target) and is_instance_valid(worker)
		and bool(worker.get("is_alive"))
		and not bool(target.get("is_alive"))
	)


func snapshot() -> Dictionary:
	return {
		"target_scene_index": int(target.get("scene_index")) if target != null else -1,
		"worker_scene_index": int(worker.get("scene_index")) if worker != null else -1,
		"progress_ticks": progress_ticks,
		"action_started": action_started,
		"counter_limit": counter_limit,
	}


static func in_range(worker_position: Vector2, target_position: Vector2) -> bool:
	var worker_cell := Vector2i(
		floori(worker_position.x / float(GRID_SIZE.x)),
		floori(worker_position.y / float(GRID_SIZE.y)),
	)
	var target_cell := Vector2i(
		floori(target_position.x / float(GRID_SIZE.x)),
		floori(target_position.y / float(GRID_SIZE.y)),
	)
	return (
		absi(worker_cell.x - target_cell.x) <= 1
		and absi(worker_cell.y - target_cell.y) <= 1
	)
