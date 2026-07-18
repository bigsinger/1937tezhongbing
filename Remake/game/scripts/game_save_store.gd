class_name GameSaveStore
extends RefCounted

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")

const SCHEMA_VERSION := 1
const GAME_ID := "1937-remake"
const DEFAULT_DIRECTORY := "user://saves"
const VALID_SLOT_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

var save_directory := DEFAULT_DIRECTORY
var last_result: Dictionary = {}


func _init(directory: String = DEFAULT_DIRECTORY) -> void:
	save_directory = directory.trim_suffix("/")


static func empty_session(level_id: String = "m000") -> Dictionary:
	return {
		"level_id": level_id,
		"elapsed_seconds": 0.0,
		"camera": {"x": 0.0, "y": 0.0, "zoom": 1.0},
		"mission": {
			"completed": {},
			"progress": {},
			"seen_values": {},
			"failure_id": "",
			"durable_facts": [],
			"applied_fact_objectives": {},
		},
		"squad": [],
		"enemies": [],
		"escorts": [],
		"world": {
			"activated_scene_indices": [],
			"collected_scene_indices": [],
			"destroyed_scene_indices": [],
			"remaining_field_pickup_scene_indices": [],
			"explosive_props": [],
			"mission_pickups": [],
			"field_inventory": {},
			"deployed_mines": [],
			"projectiles": [],
		},
	}


static func default_campaign() -> Dictionary:
	return {
		"highest_unlocked_level_id": "m000",
		"completed_level_ids": [],
	}


func save_slot(
	slot_id: String,
	session: Dictionary,
	campaign: Dictionary = {},
) -> Dictionary:
	if not is_valid_slot_id(slot_id):
		last_result = _failure("invalid_slot", "slot ID contains unsupported characters")
		return last_result
	if not _is_valid_session(session):
		last_result = _failure("invalid_session", "mid-mission session payload is incomplete or not JSON-safe")
		return last_result

	var previous := load_slot(slot_id)
	var revision := 1
	if bool(previous.get("ok", false)):
		revision = int((previous["data"] as Dictionary).get("revision", 0)) + 1
	var resolved_campaign := default_campaign() if campaign.is_empty() else _normalize_campaign(campaign)
	var document := {
		"schema_version": SCHEMA_VERSION,
		"game_id": GAME_ID,
		"slot_id": slot_id,
		"revision": revision,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"campaign": resolved_campaign,
		"session": _normalize_session(session),
	}
	var result: Dictionary = ATOMIC_JSON_STORE.save_document(
		slot_path(slot_id),
		document,
		Callable(self, "_is_loadable_document"),
		true,
	)
	if bool(result["ok"]):
		result["data"] = document.duplicate(true)
	last_result = result.duplicate(true)
	return result


func load_slot(slot_id: String) -> Dictionary:
	if not is_valid_slot_id(slot_id):
		last_result = _failure("invalid_slot", "slot ID contains unsupported characters")
		return last_result
	var result: Dictionary = ATOMIC_JSON_STORE.load_document(
		slot_path(slot_id),
		Callable(self, "_is_loadable_document"),
	)
	if not bool(result["ok"]):
		last_result = result.duplicate(true)
		return result
	var source_version := int((result["data"] as Dictionary).get("schema_version", 0))
	var migrated := _migrate_document(result["data"] as Dictionary, slot_id)
	if not _is_current_document(migrated):
		last_result = _failure("migration_failed", "loaded save could not be normalized")
		return last_result
	result["data"] = migrated
	result["migrated"] = source_version != SCHEMA_VERSION
	last_result = result.duplicate(true)
	return result


func has_slot(slot_id: String) -> bool:
	return is_valid_slot_id(slot_id) and (
		FileAccess.file_exists(slot_path(slot_id))
		or FileAccess.file_exists(slot_path(slot_id) + ".bak")
	)


func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var absolute_directory := ProjectSettings.globalize_path(save_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return slots
	var slot_ids: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			var slot_id := ""
			if file_name.ends_with(".json"):
				slot_id = file_name.trim_suffix(".json")
			elif file_name.ends_with(".json.bak"):
				slot_id = file_name.trim_suffix(".json.bak")
			if is_valid_slot_id(slot_id) and not slot_ids.has(slot_id):
				slot_ids.append(slot_id)
		file_name = directory.get_next()
	directory.list_dir_end()
	slot_ids.sort()
	for slot_id: String in slot_ids:
		var result := load_slot(slot_id)
		if not bool(result.get("ok", false)):
			continue
		var document := result["data"] as Dictionary
		var session := document["session"] as Dictionary
		slots.append(
			{
				"slot_id": slot_id,
				"revision": int(document["revision"]),
				"saved_at_unix": int(document["saved_at_unix"]),
				"level_id": str(session["level_id"]),
				"elapsed_seconds": float(session["elapsed_seconds"]),
				"recovered": bool(result.get("recovered", false)),
			}
		)
	return slots


func slot_path(slot_id: String) -> String:
	if not is_valid_slot_id(slot_id):
		return ""
	return "%s/%s.json" % [save_directory, slot_id]


static func is_valid_slot_id(slot_id: String) -> bool:
	if slot_id.is_empty() or slot_id.length() > 32:
		return false
	for index: int in range(slot_id.length()):
		if not VALID_SLOT_CHARACTERS.contains(slot_id.substr(index, 1)):
			return false
	return true


static func is_valid_level_id(level_id: String) -> bool:
	if level_id.length() != 4 or not level_id.begins_with("m"):
		return false
	var numeric := level_id.substr(1)
	return numeric.is_valid_int() and int(numeric) >= 0 and int(numeric) <= 11


func _is_loadable_document(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var document := value as Dictionary
	if not document.has("schema_version"):
		# v0 was an internal prototype shape with level/session fields at root.
		return document.has("level_id") and is_valid_level_id(str(document["level_id"]))
	if not _is_number(document["schema_version"]):
		return false
	var version := int(document["schema_version"])
	if version == 0:
		return document.has("level_id") or document.has("session")
	return version == SCHEMA_VERSION and _is_current_document(document)


func _is_current_document(document: Dictionary) -> bool:
	if (
		int(document.get("schema_version", -1)) != SCHEMA_VERSION
		or str(document.get("game_id", "")) != GAME_ID
		or not is_valid_slot_id(str(document.get("slot_id", "")))
		or int(document.get("revision", 0)) < 1
		or int(document.get("saved_at_unix", -1)) < 0
		or not document.get("campaign") is Dictionary
		or not document.get("session") is Dictionary
	):
		return false
	return (
		_is_valid_campaign(document["campaign"] as Dictionary)
		and _is_valid_session(document["session"] as Dictionary)
		and _is_json_safe(document)
	)


func _is_valid_campaign(campaign: Dictionary) -> bool:
	if not is_valid_level_id(str(campaign.get("highest_unlocked_level_id", ""))):
		return false
	if not campaign.get("completed_level_ids", []) is Array:
		return false
	for level_value: Variant in campaign.get("completed_level_ids", []) as Array:
		if not is_valid_level_id(str(level_value)):
			return false
	return true


func _is_valid_session(session: Dictionary) -> bool:
	if (
		not is_valid_level_id(str(session.get("level_id", "")))
		or not _is_number(session.get("elapsed_seconds"))
		or float(session.get("elapsed_seconds", -1.0)) < 0.0
		or not session.get("camera") is Dictionary
		or not session.get("mission") is Dictionary
		or not session.get("squad") is Array
		or not session.get("enemies") is Array
		or not session.get("escorts") is Array
		or not session.get("world") is Dictionary
	):
		return false
	var camera := session["camera"] as Dictionary
	if not _dictionary_has_numbers(camera, ["x", "y", "zoom"]) or float(camera["zoom"]) <= 0.0:
		return false
	var mission := session["mission"] as Dictionary
	for key: String in ["completed", "progress", "seen_values"]:
		if not mission.get(key) is Dictionary:
			return false
	if not mission.get("durable_facts", []) is Array:
		return false
	var world := session["world"] as Dictionary
	for key: String in ["activated_scene_indices", "collected_scene_indices", "destroyed_scene_indices", "deployed_mines"]:
		if not world.get(key) is Array:
			return false
	if not world.get("field_inventory") is Dictionary:
		return false
	for group_name: String in ["squad", "enemies", "escorts"]:
		for actor: Variant in session[group_name] as Array:
			if not actor is Dictionary:
				return false
	return _is_json_safe(session)


func _normalize_session(session: Dictionary) -> Dictionary:
	var normalized := empty_session(str(session.get("level_id", "m000")))
	normalized["elapsed_seconds"] = maxf(float(session.get("elapsed_seconds", 0.0)), 0.0)
	normalized["camera"] = (session.get("camera", normalized["camera"]) as Dictionary).duplicate(true)
	normalized["mission"] = (session.get("mission", normalized["mission"]) as Dictionary).duplicate(true)
	for group_name: String in ["squad", "enemies", "escorts"]:
		normalized[group_name] = (session.get(group_name, []) as Array).duplicate(true)
	normalized["world"] = (session.get("world", normalized["world"]) as Dictionary).duplicate(true)
	return normalized


func _normalize_campaign(campaign: Dictionary) -> Dictionary:
	if not _is_valid_campaign(campaign):
		return default_campaign()
	var completed: Array[String] = []
	for value: Variant in campaign.get("completed_level_ids", []) as Array:
		var level_id := str(value)
		if not completed.has(level_id):
			completed.append(level_id)
	completed.sort()
	return {
		"highest_unlocked_level_id": str(campaign["highest_unlocked_level_id"]),
		"completed_level_ids": completed,
	}


func _migrate_document(document: Dictionary, requested_slot_id: String) -> Dictionary:
	var source_version := int(document.get("schema_version", 0))
	if source_version == SCHEMA_VERSION:
		return document.duplicate(true)
	var raw_session: Dictionary
	if document.get("session") is Dictionary:
		raw_session = (document["session"] as Dictionary).duplicate(true)
	else:
		raw_session = empty_session(str(document.get("level_id", "m000")))
		raw_session["elapsed_seconds"] = maxf(float(document.get("elapsed_seconds", 0.0)), 0.0)
	return {
		"schema_version": SCHEMA_VERSION,
		"game_id": GAME_ID,
		"slot_id": requested_slot_id,
		"revision": maxi(int(document.get("revision", 1)), 1),
		"saved_at_unix": maxi(int(document.get("saved_at_unix", 0)), 0),
		"campaign": _normalize_campaign(document.get("campaign", default_campaign()) as Dictionary),
		"session": _normalize_session(raw_session),
	}


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _dictionary_has_numbers(dictionary: Dictionary, keys: Array[String]) -> bool:
	for key: String in keys:
		if not dictionary.has(key) or not _is_number(dictionary[key]):
			return false
	return true


static func _is_json_safe(value: Variant) -> bool:
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for child: Variant in value as Array:
			if not _is_json_safe(child):
				return false
		return true
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if not key is String or not _is_json_safe((value as Dictionary)[key]):
				return false
		return true
	return false


static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"data": {},
		"source": "none",
		"recovered": false,
	}
