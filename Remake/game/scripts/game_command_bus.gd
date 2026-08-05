class_name GameCommandBus
extends RefCounted

signal command_issued(command: Dictionary)
signal event_emitted(event: Dictionary)

const MAX_HISTORY := 256

var _sequence := 0
var _handlers: Dictionary = {}
var _history: Array[Dictionary] = []


func register_handler(command_name: String, handler: Callable) -> bool:
	var normalized := _normalize_name(command_name)
	if normalized.is_empty() or not handler.is_valid():
		return false
	_handlers[normalized] = handler
	return true


func unregister_handler(command_name: String) -> bool:
	return _handlers.erase(_normalize_name(command_name))


func issue(
	command_name: String,
	payload: Dictionary = {},
	source: String = "gameplay",
) -> Dictionary:
	var normalized := _normalize_name(command_name)
	if normalized.is_empty():
		return {"accepted": false, "reason": "empty_command"}
	_sequence += 1
	var command := {
		"sequence": _sequence,
		"name": normalized,
		"source": source.strip_edges().to_lower(),
		"elapsed_msec": Time.get_ticks_msec(),
		"payload": payload.duplicate(true),
		"accepted": true,
	}
	_history.append(command)
	_trim_history()
	command_issued.emit(command)
	var handler_value: Variant = _handlers.get(normalized)
	if handler_value is Callable and (handler_value as Callable).is_valid():
		command["result"] = (handler_value as Callable).call(payload)
	return command


func emit_event(
	event_name: String,
	payload: Dictionary = {},
	source: String = "simulation",
) -> Dictionary:
	var normalized := _normalize_name(event_name)
	if normalized.is_empty():
		return {}
	_sequence += 1
	var event := {
		"sequence": _sequence,
		"name": normalized,
		"source": source.strip_edges().to_lower(),
		"elapsed_msec": Time.get_ticks_msec(),
		"payload": payload.duplicate(true),
	}
	_history.append(event)
	_trim_history()
	event_emitted.emit(event)
	return event


func history(limit: int = MAX_HISTORY) -> Array[Dictionary]:
	var safe_limit := clampi(limit, 0, MAX_HISTORY)
	var start := maxi(_history.size() - safe_limit, 0)
	var result: Array[Dictionary] = []
	for index: int in range(start, _history.size()):
		result.append(_history[index].duplicate(true))
	return result


func clear() -> void:
	_history.clear()


func stats() -> Dictionary:
	return {
		"sequence": _sequence,
		"history_count": _history.size(),
		"handler_count": _handlers.size(),
	}


func _trim_history() -> void:
	while _history.size() > MAX_HISTORY:
		_history.pop_front()


static func _normalize_name(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_")
