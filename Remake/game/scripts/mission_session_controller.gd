class_name MissionSessionController
extends RefCounted

var mission_runtime: Object
var mission_state: Object
var ai_observer: Callable
var direction_observer: Callable


func configure(
	runtime: Object,
	state: Object,
	ai_event_observer: Callable = Callable(),
	direction_event_observer: Callable = Callable(),
) -> void:
	mission_runtime = runtime
	mission_state = state
	ai_observer = ai_event_observer
	direction_observer = direction_event_observer


func publish(event_name: String, payload: Dictionary = {}) -> Dictionary:
	if mission_runtime == null or not bool(mission_runtime.call("is_configured")):
		return {
			"accepted": false,
			"error": "mission_runtime_unavailable",
			"completed": [],
			"progress_changes": {},
		}
	var before: Dictionary = {}
	if mission_state != null:
		before = (mission_state.get("progress") as Dictionary).duplicate(true)
	var completed := mission_runtime.call("publish_world_event", event_name, payload) as Array
	var error := str(mission_runtime.get("last_error"))
	if error.is_empty() and ai_observer.is_valid():
		ai_observer.call(event_name, payload)
	var progress_changes: Dictionary = {}
	if mission_state != null:
		var after := mission_state.get("progress") as Dictionary
		for objective_value: Variant in after.keys():
			var objective_id := str(objective_value)
			var count := int(after.get(objective_id, 0))
			if count != int(before.get(objective_id, 0)):
				progress_changes[objective_id] = count
				if direction_observer.is_valid():
					direction_observer.call(
						"objective_progress",
						{"objective_id": objective_id, "count": count},
					)
	return {
		"accepted": error.is_empty(),
		"error": error,
		"completed": completed,
		"progress_changes": progress_changes,
	}


func snapshot() -> Dictionary:
	return {
		"configured": mission_runtime != null,
		"mission_state_available": mission_state != null,
	}


func is_configured_for(runtime: Object, state: Object) -> bool:
	return mission_runtime == runtime and mission_state == state
