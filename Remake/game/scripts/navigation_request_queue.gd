class_name NavigationRequestQueue
extends RefCounted

const DEFAULT_BUDGET_USEC := 2000
const DEFAULT_MAX_REQUESTS_PER_FRAME := 3

var _pending: Array[Dictionary] = []
var _next_serial := 1
var _generation := 1
var processed_requests := 0
var total_query_usec := 0
var peak_pending := 0
var coalesced_requests := 0


func enqueue(
	scene_index: int,
	start_world: Vector2,
	destination_world: Vector2,
	completion: Callable,
	priority: int = 0,
) -> int:
	if not completion.is_valid():
		return 0
	var serial := _next_serial
	_next_serial += 1
	# A player can issue several move orders before the frame budget reaches this
	# actor. Only the newest destination is meaningful; calculating superseded
	# A* paths causes latency spikes and can briefly apply an old path first.
	if scene_index >= 0:
		for index: int in range(_pending.size() - 1, -1, -1):
			var pending := _pending[index]
			if (
				int(pending.get("generation", -1)) == _generation
				and int(pending.get("scene_index", -1)) == scene_index
			):
				_pending.remove_at(index)
				coalesced_requests += 1
	_pending.append({
		"serial": serial,
		"generation": _generation,
		"scene_index": scene_index,
		"start": start_world,
		"destination": destination_world,
		"completion": completion,
		"priority": priority,
	})
	_pending.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			if int(first["priority"]) != int(second["priority"]):
				return int(first["priority"]) > int(second["priority"])
			return int(first["serial"]) < int(second["serial"])
	)
	peak_pending = maxi(peak_pending, _pending.size())
	return serial


func process_budget(
	dynamic_occupancy: Variant,
	navigation_grid: Variant,
	budget_usec: int = DEFAULT_BUDGET_USEC,
	max_requests: int = DEFAULT_MAX_REQUESTS_PER_FRAME,
) -> int:
	var started := Time.get_ticks_usec()
	var processed := 0
	while not _pending.is_empty() and processed < maxi(max_requests, 1):
		if processed > 0 and Time.get_ticks_usec() - started >= maxi(budget_usec, 1):
			break
		var request := _pending.pop_front() as Dictionary
		if int(request["generation"]) != _generation:
			continue
		var query_started := Time.get_ticks_usec()
		var path := PackedVector2Array()
		if (
			dynamic_occupancy != null
			and dynamic_occupancy.has_method("find_path_for_scene")
		):
			path = dynamic_occupancy.call(
				"find_path_for_scene",
				int(request["scene_index"]),
				request["start"] as Vector2,
				request["destination"] as Vector2,
			) as PackedVector2Array
		elif navigation_grid != null and navigation_grid.has_method("find_path"):
			path = navigation_grid.call(
				"find_path",
				request["start"] as Vector2,
				request["destination"] as Vector2,
			) as PackedVector2Array
		var elapsed := maxi(Time.get_ticks_usec() - query_started, 0)
		total_query_usec += elapsed
		processed_requests += 1
		processed += 1
		var completion := request["completion"] as Callable
		if completion.is_valid():
			completion.call(path, request.duplicate(true), elapsed)
	return processed


func cancel_all() -> void:
	_generation += 1
	_pending.clear()


func pending_count() -> int:
	return _pending.size()


func stats() -> Dictionary:
	return {
		"pending": _pending.size(),
		"processed": processed_requests,
		"total_query_usec": total_query_usec,
		"peak_pending": peak_pending,
		"coalesced": coalesced_requests,
		"generation": _generation,
	}
