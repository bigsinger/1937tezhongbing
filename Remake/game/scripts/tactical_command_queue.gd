class_name TacticalCommandQueue
extends RefCounted

signal plan_changed(snapshot: Dictionary)
signal command_finished(result: Dictionary)

const SCHEMA_VERSION := 1
const FAILURE_SKIP := "skip"
const FAILURE_WAIT := "wait"
const FAILURE_ABORT := "abort_queue"
const SUPPORTED_KINDS: Array[String] = [
	"move",
	"stance",
	"attack",
	"force_attack",
	"pickup",
	"open_door",
	"drop_lure",
	"bury",
	"special_item",
	"wait",
]

var planning_active := false
var _sequence := 0
var _planned: Dictionary = {}
var _runtime: Dictionary = {}
var _history: Array[Dictionary] = []


func begin_planning() -> bool:
	if planning_active:
		return false
	planning_active = true
	_emit_changed()
	return true


func cancel_planning(clear_plan: bool = false) -> void:
	planning_active = false
	if clear_plan:
		_planned.clear()
	_emit_changed()


func enqueue(
	actor_id: int,
	kind: String,
	payload: Dictionary = {},
	estimated_ticks: int = 1,
	precondition: Dictionary = {},
	timeout_ticks: int = 600,
	failure_policy: String = FAILURE_SKIP,
) -> Dictionary:
	var normalized := kind.strip_edges().to_lower()
	if not planning_active:
		return {"accepted": false, "reason": "not_planning"}
	if actor_id < 0 or normalized not in SUPPORTED_KINDS:
		return {"accepted": false, "reason": "unsupported_command"}
	_sequence += 1
	var command := {
		"sequence": _sequence,
		"actor_id": actor_id,
		"kind": normalized,
		"payload": payload.duplicate(true),
		"estimated_ticks": maxi(estimated_ticks, 1),
		"precondition": precondition.duplicate(true),
		"timeout_ticks": maxi(timeout_ticks, 1),
		"failure_policy": (
			failure_policy
			if failure_policy in [FAILURE_SKIP, FAILURE_WAIT, FAILURE_ABORT]
			else FAILURE_SKIP
		),
	}
	var queue := _planned.get(actor_id, []) as Array
	queue.append(command)
	_planned[actor_id] = queue
	_emit_changed()
	var result := command.duplicate(true)
	result["accepted"] = true
	return result


func undo(actor_id: int = -1) -> bool:
	var selected_actor := actor_id
	if selected_actor < 0:
		var newest_sequence := -1
		for raw_actor: Variant in _planned.keys():
			var queue := _planned[raw_actor] as Array
			if not queue.is_empty() and int((queue[-1] as Dictionary)["sequence"]) > newest_sequence:
				newest_sequence = int((queue[-1] as Dictionary)["sequence"])
				selected_actor = int(raw_actor)
	if not _planned.has(selected_actor):
		return false
	var selected_queue := _planned[selected_actor] as Array
	if selected_queue.is_empty():
		return false
	selected_queue.pop_back()
	if selected_queue.is_empty():
		_planned.erase(selected_actor)
	_emit_changed()
	return true


func clear_planned(actor_id: int = -1) -> void:
	if actor_id < 0:
		_planned.clear()
	else:
		_planned.erase(actor_id)
	_emit_changed()


func release_payload() -> Dictionary:
	var payload := {"schema_version": SCHEMA_VERSION, "queues": _queues_to_json(_planned)}
	planning_active = false
	_planned.clear()
	_emit_changed()
	return payload


func activate_released_plan(payload: Dictionary, start_tick: int) -> bool:
	if int(payload.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var queues_value: Variant = payload.get("queues", {})
	if not queues_value is Dictionary:
		return false
	var restored := _queues_from_json(queues_value as Dictionary)
	for raw_actor: Variant in restored.keys():
		var actor_id := int(raw_actor)
		_runtime[actor_id] = {
			"commands": (restored[actor_id] as Array).duplicate(true),
			"cursor": 0,
			"status": "pending",
			"started_tick": start_tick,
		}
	return true


func advance_tick(
	simulation_tick: int,
	executor: Callable,
	completion_check: Callable,
	precondition_check: Callable,
) -> int:
	var completed := 0
	var actor_ids: Array[int] = []
	for raw_actor: Variant in _runtime.keys():
		actor_ids.append(int(raw_actor))
	actor_ids.sort()
	for actor_id: int in actor_ids:
		var state := _runtime.get(actor_id, {}) as Dictionary
		var commands := state.get("commands", []) as Array
		var cursor := int(state.get("cursor", 0))
		if cursor >= commands.size():
			_runtime.erase(actor_id)
			continue
		var command := commands[cursor] as Dictionary
		if str(command.get("kind", "")) == "wait":
			var remaining := int(state.get("wait_remaining", command.get("estimated_ticks", 1))) - 1
			state["wait_remaining"] = remaining
			if remaining <= 0:
				_finish_current(actor_id, state, command, simulation_tick, "completed")
				completed += 1
			continue
		var status := str(state.get("status", "pending"))
		if status == "pending":
			var precondition: Variant = precondition_check.call(command.duplicate(true))
			if not _result_accepted(precondition):
				if str(command.get("failure_policy", FAILURE_SKIP)) == FAILURE_WAIT:
					if _timed_out(state, command, simulation_tick):
						_finish_current(actor_id, state, command, simulation_tick, "timeout")
						completed += 1
					continue
				if str(command.get("failure_policy", FAILURE_SKIP)) == FAILURE_ABORT:
					_abort_queue(actor_id, command, simulation_tick, "precondition_failed")
				else:
					_finish_current(actor_id, state, command, simulation_tick, "skipped")
				completed += 1
				continue
			var execution: Variant = executor.call(command.duplicate(true))
			if not _result_accepted(execution):
				if str(command.get("failure_policy", FAILURE_SKIP)) == FAILURE_WAIT and not _timed_out(state, command, simulation_tick):
					continue
				_finish_current(actor_id, state, command, simulation_tick, "rejected")
				completed += 1
				continue
			state["status"] = "running"
			state["started_tick"] = simulation_tick
			if execution is Dictionary and bool((execution as Dictionary).get("complete", false)):
				_finish_current(actor_id, state, command, simulation_tick, "completed")
				completed += 1
			continue
		var complete: Variant = completion_check.call(command.duplicate(true))
		if _result_accepted(complete):
			_finish_current(actor_id, state, command, simulation_tick, "completed")
			completed += 1
		elif _timed_out(state, command, simulation_tick):
			_finish_current(actor_id, state, command, simulation_tick, "timeout")
			completed += 1
	return completed


func snapshot() -> Dictionary:
	return {
		"planning_active": planning_active,
		"planned": _queues_to_json(_planned),
		"runtime": _runtime_to_json(),
		"sequence": _sequence,
		"planned_count": _command_count(_planned),
		"runtime_count": _runtime_command_count(),
	}


func capture_state() -> Dictionary:
	var result := snapshot()
	result["schema_version"] = SCHEMA_VERSION
	result["history"] = _history.duplicate(true)
	return result


func restore_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var planned_value: Variant = state.get("planned", {})
	var runtime_value: Variant = state.get("runtime", {})
	if not planned_value is Dictionary or not runtime_value is Dictionary:
		return false
	_planned = _queues_from_json(planned_value as Dictionary)
	_runtime.clear()
	for raw_key: Variant in (runtime_value as Dictionary).keys():
		var raw_state: Variant = (runtime_value as Dictionary)[raw_key]
		if not raw_state is Dictionary:
			return false
		var restored_state := (raw_state as Dictionary).duplicate(true)
		var commands_value: Variant = restored_state.get("commands", [])
		if not commands_value is Array:
			return false
		restored_state["commands"] = (commands_value as Array).duplicate(true)
		_runtime[int(raw_key)] = restored_state
	planning_active = bool(state.get("planning_active", false))
	_sequence = maxi(int(state.get("sequence", 0)), 0)
	var history_value: Variant = state.get("history", [])
	if not history_value is Array:
		return false
	_history.clear()
	for raw_history: Variant in history_value as Array:
		if not raw_history is Dictionary:
			return false
		_history.append((raw_history as Dictionary).duplicate(true))
	_emit_changed()
	return true


func clear_all() -> void:
	planning_active = false
	_planned.clear()
	_runtime.clear()
	_history.clear()
	_sequence = 0
	_emit_changed()


func _finish_current(actor_id: int, state: Dictionary, command: Dictionary, tick: int, outcome: String) -> void:
	var result := command.duplicate(true)
	result["completed_tick"] = tick
	result["outcome"] = outcome
	_history.append(result)
	if _history.size() > 512:
		_history.pop_front()
	state["cursor"] = int(state.get("cursor", 0)) + 1
	state["status"] = "pending"
	state.erase("wait_remaining")
	_runtime[actor_id] = state
	command_finished.emit(result.duplicate(true))


func _abort_queue(actor_id: int, command: Dictionary, tick: int, reason: String) -> void:
	var result := command.duplicate(true)
	result["completed_tick"] = tick
	result["outcome"] = reason
	_history.append(result)
	_runtime.erase(actor_id)
	command_finished.emit(result.duplicate(true))


func _timed_out(state: Dictionary, command: Dictionary, tick: int) -> bool:
	return tick - int(state.get("started_tick", tick)) >= int(command.get("timeout_ticks", 600))


func _result_accepted(value: Variant) -> bool:
	if value is Dictionary:
		return bool((value as Dictionary).get("accepted", (value as Dictionary).get("ok", false)))
	return bool(value)


func _queues_to_json(queues: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_actor: Variant in queues.keys():
		result[str(int(raw_actor))] = (queues[raw_actor] as Array).duplicate(true)
	return result


func _queues_from_json(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_actor: Variant in value.keys():
		var queue_value: Variant = value[raw_actor]
		if queue_value is Array:
			result[int(raw_actor)] = (queue_value as Array).duplicate(true)
	return result


func _runtime_to_json() -> Dictionary:
	var result: Dictionary = {}
	for raw_actor: Variant in _runtime.keys():
		result[str(int(raw_actor))] = (_runtime[raw_actor] as Dictionary).duplicate(true)
	return result


func _command_count(queues: Dictionary) -> int:
	var count := 0
	for queue_value: Variant in queues.values():
		count += (queue_value as Array).size()
	return count


func _runtime_command_count() -> int:
	var count := 0
	for state_value: Variant in _runtime.values():
		var state := state_value as Dictionary
		count += maxi((state.get("commands", []) as Array).size() - int(state.get("cursor", 0)), 0)
	return count


func _emit_changed() -> void:
	plan_changed.emit(snapshot())
