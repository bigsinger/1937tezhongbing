class_name MissionState
extends RefCounted

var mission: Dictionary = {}
var completed: Dictionary = {}
var progress: Dictionary = {}
var seen_values: Dictionary = {}
var elapsed_seconds := 0.0
var failure_id := ""


func _init(definition: Dictionary = {}) -> void:
	mission = definition
	if mission.is_empty():
		return
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		var objective := raw_objective as Dictionary
		var objective_id := str(objective["id"])
		completed[objective_id] = false
		progress[objective_id] = 0
		seen_values[objective_id] = {}


func record_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
	var newly_completed: Array[String] = []
	if mission.is_empty() or is_failed() or is_victory():
		return newly_completed

	for raw_failure: Variant in mission.get("failure_conditions", []) as Array:
		if not raw_failure is Dictionary:
			continue
		var failure := raw_failure as Dictionary
		if str(failure.get("event", "")) != event_name:
			continue
		var unless_objective := str(failure.get("unless_objective_complete", ""))
		if not unless_objective.is_empty() and is_objective_complete(unless_objective):
			continue
		failure_id = str(failure.get("id", event_name))
		return newly_completed

	for raw_objective: Variant in mission.get("objectives", []) as Array:
		var objective := raw_objective as Dictionary
		var objective_id := str(objective["id"])
		if is_objective_complete(objective_id) or not dependencies_complete(objective):
			continue
		var condition := objective["condition"] as Dictionary
		if str(condition["event"]) != event_name or not payload_matches(condition, payload):
			continue
		if is_duplicate_event(objective_id, condition, payload):
			continue
		progress[objective_id] = int(progress[objective_id]) + 1
		if int(progress[objective_id]) >= int(condition["required_count"]):
			completed[objective_id] = true
			newly_completed.append(objective_id)
	return newly_completed


func advance_time(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or mission.is_empty() or is_failed() or is_victory():
		return
	elapsed_seconds += delta_seconds
	var limit := float(mission.get("time_limit_seconds", 0))
	if limit > 0.0 and elapsed_seconds >= limit:
		record_event("time_expired")


func is_objective_complete(objective_id: String) -> bool:
	return bool(completed.get(objective_id, false))


func dependencies_complete(objective: Dictionary) -> bool:
	for dependency: Variant in objective.get("depends_on", []) as Array:
		if not is_objective_complete(str(dependency)):
			return false
	return true


func payload_matches(condition: Dictionary, payload: Dictionary) -> bool:
	var where: Variant = condition.get("where", {})
	if not where is Dictionary:
		return false
	for key: Variant in (where as Dictionary).keys():
		if not payload.has(key) or payload[key] != (where as Dictionary)[key]:
			return false
	return true


func is_duplicate_event(objective_id: String, condition: Dictionary, payload: Dictionary) -> bool:
	var unique_key := str(condition.get("unique_by", ""))
	if unique_key.is_empty():
		return false
	if not payload.has(unique_key):
		return true
	var objective_seen := seen_values[objective_id] as Dictionary
	var value: Variant = payload[unique_key]
	if objective_seen.has(value):
		return true
	objective_seen[value] = true
	return false


func is_failed() -> bool:
	return not failure_id.is_empty()


func is_victory() -> bool:
	if mission.is_empty() or is_failed():
		return false
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		var objective := raw_objective as Dictionary
		if bool(objective["required"]) and not is_objective_complete(str(objective["id"])):
			return false
	return true


func display_lines() -> Array[String]:
	var lines: Array[String] = []
	if mission.is_empty():
		return lines
	lines.append("任务 %02d · %s" % [int(mission["number"]), str(mission["title"])])
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		var objective := raw_objective as Dictionary
		var mark := "✓" if is_objective_complete(str(objective["id"])) else "□"
		lines.append("%s %s" % [mark, str(objective["label"])])
	return lines
