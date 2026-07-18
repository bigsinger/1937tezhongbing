class_name MissionData
extends RefCounted

const SCHEMA_VERSION := 1
const CATALOG_PATH := "res://data/missions.json"
const TRIGGER_FIELDS: Array[String] = ["markers", "explosion", "exit", "spawns", "entrances"]


static func load_catalog(resource_path: String = CATALOG_PATH) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var catalog := json.data as Dictionary
	if not is_valid_catalog(catalog):
		return {}
	return catalog


static func load_mission(mission_id: String, resource_path: String = CATALOG_PATH) -> Dictionary:
	var catalog := load_catalog(resource_path)
	if catalog.is_empty():
		return {}
	for raw_mission: Variant in catalog["missions"] as Array:
		var mission := raw_mission as Dictionary
		if str(mission["id"]) == mission_id:
			return mission
	return {}


static func is_valid_catalog(catalog: Dictionary) -> bool:
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var raw_missions: Variant = catalog.get("missions")
	if not raw_missions is Array or (raw_missions as Array).is_empty():
		return false
	if int(catalog.get("mission_count", -1)) != (raw_missions as Array).size():
		return false

	var ids: Dictionary = {}
	for index in range((raw_missions as Array).size()):
		var raw_mission: Variant = (raw_missions as Array)[index]
		if not raw_mission is Dictionary:
			return false
		var mission := raw_mission as Dictionary
		var mission_id := str(mission.get("id", ""))
		if not is_safe_mission_id(mission_id) or ids.has(mission_id):
			return false
		ids[mission_id] = true
		if int(mission.get("number", 0)) != index + 1 or str(mission.get("title", "")).is_empty():
			return false
		if int(mission.get("time_limit_seconds", -1)) < 0:
			return false
		if not is_valid_trigger_inventory(mission.get("trigger_inventory")):
			return false
		if not is_valid_objectives(mission.get("objectives")):
			return false
		if not mission.get("failure_conditions") is Array:
			return false
	return true


static func is_safe_mission_id(mission_id: String) -> bool:
	return (
		mission_id.length() == 4
		and mission_id.begins_with("m")
		and mission_id.substr(1).is_valid_int()
	)


static func is_valid_trigger_inventory(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in TRIGGER_FIELDS:
		if not (value as Dictionary).has(field) or int((value as Dictionary)[field]) < 0:
			return false
	return true


static func is_valid_objectives(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var objective_ids: Dictionary = {}
	for raw_objective: Variant in value as Array:
		if not raw_objective is Dictionary:
			return false
		var objective := raw_objective as Dictionary
		var objective_id := str(objective.get("id", ""))
		if objective_id.is_empty() or objective_ids.has(objective_id):
			return false
		objective_ids[objective_id] = true
		if str(objective.get("label", "")).is_empty() or not objective.get("required") is bool:
			return false
		var condition: Variant = objective.get("condition")
		if (
			not condition is Dictionary
			or str((condition as Dictionary).get("event", "")).is_empty()
		):
			return false
		if int((condition as Dictionary).get("required_count", 0)) <= 0:
			return false
		var dependencies: Variant = objective.get("depends_on", [])
		if not dependencies is Array:
			return false

	for raw_objective: Variant in value as Array:
		var objective := raw_objective as Dictionary
		for dependency: Variant in objective.get("depends_on", []) as Array:
			if not dependency is String or not objective_ids.has(dependency as String):
				return false
			if dependency as String == str(objective["id"]):
				return false
	return true
