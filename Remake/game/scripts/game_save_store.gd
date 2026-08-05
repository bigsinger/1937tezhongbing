class_name GameSaveStore
extends RefCounted

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")
const CAMPAIGN_PROGRESS: Script = preload("res://scripts/campaign_progress.gd")

const SCHEMA_VERSION := 2
const MIN_SUPPORTED_SCHEMA_VERSION := 0
const GAME_ID := "1937-remake"
const MISSION_RULE_MODES: Array[String] = ["stable_mod", "repaired"]
const RULESET_MODES: Array[String] = ["classic", "modern"]
const DIFFICULTY_MODES: Array[String] = ["story", "normal", "hard", "custom"]
const CONTROL_SCHEMES: Array[String] = ["classic", "modern"]
const DEFAULT_DIRECTORY := "user://saves"
const VALID_SLOT_CHARACTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
const SLOT_INDEX_SCHEMA_VERSION := 1
const SLOT_INDEX_GAME_ID := "1937-remake-slot-index"
const SLOT_INDEX_FILE_NAME := ".slot-index.json"
const FINGERPRINT_HEAD_BYTES := 2048
const FINGERPRINT_TAIL_BYTES := 512

var save_directory := DEFAULT_DIRECTORY
var last_result: Dictionary = {}
var _slot_summary_cache: Dictionary = {}
var _slot_summary_cache_loaded := false
var _slot_index_refreshing := false
var _summary_fallback_load_count := 0


func _init(directory: String = DEFAULT_DIRECTORY) -> void:
	save_directory = directory.trim_suffix("/")


static func empty_session(level_id: String = "m000") -> Dictionary:
	return {
		"level_id": level_id,
		"mission_rule_mode": "stable_mod",
		"runtime_profile": {
			"ruleset_mode": "classic",
			"difficulty_mode": "normal",
			"control_scheme": "classic",
			"mission_rule_mode": "stable_mod",
			"custom_difficulty": {},
			"content_identity": "development_unmanifested",
		},
		"player_workspace": {
			"control_groups": {},
			"camera_bookmarks": {},
		},
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
		"ambient": [],
		"world": {
			"snapshot_presence": {
				"field_pickups": true,
				"explosive_props": true,
			},
			"activated_scene_indices": [],
			"collected_scene_indices": [],
			"destroyed_scene_indices": [],
			"buried_enemy_scene_indices": [],
			"remaining_field_pickup_scene_indices": [],
			"explosive_props": [],
			"mission_pickups": [],
			"field_inventory": {},
			"legacy_special_world_objects": [],
			"legacy_explosion_effects": [],
			"legacy_ai_control_effects": [],
			"legacy_burial_caches": [],
			"pending_burial_command": {},
			"projectiles": [],
		},
	}


static func default_campaign() -> Dictionary:
	return CAMPAIGN_PROGRESS.default_state()


static func migration_policy() -> Dictionary:
	return {
		"current_schema_version": SCHEMA_VERSION,
		"minimum_supported_schema_version": MIN_SUPPORTED_SCHEMA_VERSION,
		"supported_source_versions": [0, 1, SCHEMA_VERSION],
		"schema_zero_shape": "prototype root/session document",
		"migration_mode": "in_memory_then_current_schema_on_next_save",
		"future_version_policy": "reject_and_preserve_all_generations",
		"unsupported_legacy_policy": "reject_and_preserve_all_generations",
		"malformed_primary_policy": "recover_valid_backup_then_quarantine_on_next_save",
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
	var compatibility := _save_compatibility_guard(slot_id)
	if not bool(compatibility.get("ok", false)):
		last_result = compatibility.duplicate(true)
		return last_result

	var revision := 1
	_ensure_slot_summary_cache()
	var previous_summary: Variant = _slot_summary_cache.get(slot_id)
	if previous_summary is Dictionary:
		revision = int((previous_summary as Dictionary).get("revision", 0)) + 1
	var resolved_campaign := default_campaign() if campaign.is_empty() else _normalize_campaign(campaign)
	var saved_at_unix_msec := roundi(Time.get_unix_time_from_system() * 1000.0)
	var document := {
		"schema_version": SCHEMA_VERSION,
		"game_id": GAME_ID,
		"slot_id": slot_id,
		"revision": revision,
		"saved_at_unix": int(saved_at_unix_msec / 1000),
		"saved_at_unix_msec": saved_at_unix_msec,
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
		_remember_slot_summary(document, false, true)
		_persist_slot_index()
	last_result = result.duplicate(true)
	return result


func load_slot(slot_id: String) -> Dictionary:
	if not is_valid_slot_id(slot_id):
		last_result = _failure("invalid_slot", "slot ID contains unsupported characters")
		return last_result
	var compatibility := _load_compatibility_guard(slot_id)
	if not bool(compatibility.get("ok", false)):
		last_result = compatibility.duplicate(true)
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
	result["source_schema_version"] = source_version
	if _slot_summary_cache_loaded:
		_remember_slot_summary(
			migrated,
			bool(result.get("recovered", false)),
			false,
		)
		if not _slot_index_refreshing:
			_persist_slot_index()
	last_result = result.duplicate(true)
	return result


func has_slot(slot_id: String) -> bool:
	return is_valid_slot_id(slot_id) and (
		FileAccess.file_exists(slot_path(slot_id))
		or FileAccess.file_exists(slot_path(slot_id) + ".bak")
	)


func list_slots() -> Array[Dictionary]:
	_ensure_slot_summary_cache()
	var slots: Array[Dictionary] = []
	var slot_ids: Array[String] = []
	for raw_slot_id: Variant in _slot_summary_cache.keys():
		var slot_id := str(raw_slot_id)
		if is_valid_slot_id(slot_id):
			slot_ids.append(slot_id)
	slot_ids.sort()
	for slot_id: String in slot_ids:
		var raw_summary: Variant = _slot_summary_cache.get(slot_id)
		if not raw_summary is Dictionary:
			continue
		slots.append(_public_slot_summary(raw_summary as Dictionary))
	return slots


func slot_index_path() -> String:
	return "%s/%s" % [save_directory, SLOT_INDEX_FILE_NAME]


func summary_cache_stats() -> Dictionary:
	return {
		"loaded": _slot_summary_cache_loaded,
		"slot_count": _slot_summary_cache.size(),
		"fallback_document_loads": _summary_fallback_load_count,
	}


func _ensure_slot_summary_cache() -> void:
	if _slot_index_refreshing:
		return
	_slot_index_refreshing = true
	var index_dirty := false
	if not _slot_summary_cache_loaded:
		_slot_summary_cache_loaded = true
		_slot_summary_cache.clear()
		var index_result: Dictionary = ATOMIC_JSON_STORE.load_document(
			slot_index_path(),
			Callable(self, "_is_slot_index_document"),
		)
		if bool(index_result.get("ok", false)):
			var index_document := index_result.get("data", {}) as Dictionary
			for raw_summary: Variant in index_document.get("summaries", []) as Array:
				var summary := _normalize_index_summary(raw_summary as Dictionary)
				_slot_summary_cache[str(summary["slot_id"])] = summary
			index_dirty = bool(index_result.get("recovered", false))
		elif str(index_result.get("code", "missing")) != "missing":
			# The index is advisory.  A malformed index is rebuilt from the
			# authoritative save generations below rather than blocking gameplay.
			index_dirty = true

	var discovered_slot_ids := _discover_slot_ids()
	for raw_cached_slot_id: Variant in _slot_summary_cache.keys().duplicate():
		var cached_slot_id := str(raw_cached_slot_id)
		if not discovered_slot_ids.has(cached_slot_id):
			_slot_summary_cache.erase(cached_slot_id)
			index_dirty = true

	for slot_id: String in discovered_slot_ids:
		var current_fingerprint := _slot_fingerprint(slot_id)
		var cached_value: Variant = _slot_summary_cache.get(slot_id)
		if (
			cached_value is Dictionary
			and _fingerprints_match(
				(current_fingerprint as Dictionary),
				(cached_value as Dictionary).get("fingerprint", {}) as Dictionary,
			)
		):
			continue
		_summary_fallback_load_count += 1
		var load_result := load_slot(slot_id)
		if not bool(load_result.get("ok", false)):
			_slot_summary_cache.erase(slot_id)
		index_dirty = true

	_slot_index_refreshing = false
	if index_dirty:
		_persist_slot_index()


func _discover_slot_ids() -> Array[String]:
	var slot_ids: Array[String] = []
	var absolute_directory := ProjectSettings.globalize_path(save_directory)
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return slot_ids
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			var slot_id := ""
			if file_name.ends_with(".json.bak"):
				slot_id = file_name.trim_suffix(".json.bak")
			elif file_name.ends_with(".json"):
				slot_id = file_name.trim_suffix(".json")
			if is_valid_slot_id(slot_id) and not slot_ids.has(slot_id):
				slot_ids.append(slot_id)
		file_name = directory.get_next()
	directory.list_dir_end()
	slot_ids.sort()
	return slot_ids


func _remember_slot_summary(
	document: Dictionary,
	recovered: bool,
	generations_supported: bool,
) -> void:
	var slot_id := str(document.get("slot_id", ""))
	var session_value: Variant = document.get("session", {})
	if not is_valid_slot_id(slot_id) or not session_value is Dictionary:
		return
	var session := session_value as Dictionary
	_slot_summary_cache[slot_id] = {
		"slot_id": slot_id,
		"revision": int(document.get("revision", 1)),
		"saved_at_unix": int(document.get("saved_at_unix", 0)),
		"saved_at_unix_msec": int(
			document.get(
				"saved_at_unix_msec",
				int(document.get("saved_at_unix", 0)) * 1000,
			)
		),
		"level_id": str(session.get("level_id", "m000")),
		"elapsed_seconds": maxf(float(session.get("elapsed_seconds", 0.0)), 0.0),
		"recovered": recovered,
		"generations_supported": generations_supported,
		"fingerprint": _slot_fingerprint(slot_id),
	}


func _public_slot_summary(summary: Dictionary) -> Dictionary:
	return {
		"slot_id": str(summary.get("slot_id", "")),
		"revision": int(summary.get("revision", 0)),
		"saved_at_unix": int(summary.get("saved_at_unix", 0)),
		"saved_at_unix_msec": int(summary.get("saved_at_unix_msec", 0)),
		"level_id": str(summary.get("level_id", "")),
		"elapsed_seconds": float(summary.get("elapsed_seconds", 0.0)),
		"recovered": bool(summary.get("recovered", false)),
	}


func _persist_slot_index() -> Dictionary:
	if not _slot_summary_cache_loaded or _slot_index_refreshing:
		return {"ok": false, "code": "cache_unavailable"}
	var slot_ids: Array[String] = []
	for raw_slot_id: Variant in _slot_summary_cache.keys():
		var slot_id := str(raw_slot_id)
		if is_valid_slot_id(slot_id):
			slot_ids.append(slot_id)
	slot_ids.sort()
	var summaries: Array[Dictionary] = []
	for slot_id: String in slot_ids:
		var summary_value: Variant = _slot_summary_cache.get(slot_id)
		if summary_value is Dictionary:
			summaries.append((summary_value as Dictionary).duplicate(true))
	var index_document := {
		"schema_version": SLOT_INDEX_SCHEMA_VERSION,
		"game_id": SLOT_INDEX_GAME_ID,
		"summaries": summaries,
	}
	return ATOMIC_JSON_STORE.save_document(
		slot_index_path(),
		index_document,
		Callable(self, "_is_slot_index_document"),
		false,
	)


func _slot_fingerprint(slot_id: String) -> Dictionary:
	var primary_path := slot_path(slot_id)
	return {
		"primary": _file_fingerprint(primary_path),
		"backup": _file_fingerprint(primary_path + ".bak"),
	}


func _file_fingerprint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"exists": false,
			"modified_time": 0,
			"size": 0,
			"sample_hash": 0,
		}
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return {
			"exists": true,
			"modified_time": int(FileAccess.get_modified_time(path)),
			"size": -1,
			"sample_hash": -1,
		}
	var length := int(input.get_length())
	var sample := PackedByteArray()
	if length > 0:
		sample.append_array(input.get_buffer(mini(length, FINGERPRINT_HEAD_BYTES)))
	if length > FINGERPRINT_HEAD_BYTES:
		input.seek(maxi(length - FINGERPRINT_TAIL_BYTES, 0))
		sample.append_array(input.get_buffer(mini(length, FINGERPRINT_TAIL_BYTES)))
	input.close()
	return {
		"exists": true,
		"modified_time": int(FileAccess.get_modified_time(path)),
		"size": length,
		"sample_hash": int(hash(sample)),
	}


func _fingerprints_match(first: Dictionary, second: Dictionary) -> bool:
	for generation: String in ["primary", "backup"]:
		var first_value: Variant = first.get(generation, {})
		var second_value: Variant = second.get(generation, {})
		if not first_value is Dictionary or not second_value is Dictionary:
			return false
		var first_file := first_value as Dictionary
		var second_file := second_value as Dictionary
		for key: String in ["exists", "modified_time", "size", "sample_hash"]:
			if key == "exists":
				if bool(first_file.get(key, false)) != bool(second_file.get(key, false)):
					return false
			elif int(first_file.get(key, -2)) != int(second_file.get(key, -3)):
				return false
	return true


func _normalize_index_summary(summary: Dictionary) -> Dictionary:
	return {
		"slot_id": str(summary.get("slot_id", "")),
		"revision": int(summary.get("revision", 0)),
		"saved_at_unix": int(summary.get("saved_at_unix", 0)),
		"saved_at_unix_msec": int(summary.get("saved_at_unix_msec", 0)),
		"level_id": str(summary.get("level_id", "")),
		"elapsed_seconds": float(summary.get("elapsed_seconds", 0.0)),
		"recovered": bool(summary.get("recovered", false)),
		"generations_supported": bool(summary.get("generations_supported", false)),
		"fingerprint": (summary.get("fingerprint", {}) as Dictionary).duplicate(true),
	}


func _is_slot_index_document(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var document := value as Dictionary
	if (
		int(document.get("schema_version", -1)) != SLOT_INDEX_SCHEMA_VERSION
		or str(document.get("game_id", "")) != SLOT_INDEX_GAME_ID
		or not document.get("summaries") is Array
	):
		return false
	var seen_slot_ids: Dictionary = {}
	for raw_summary: Variant in document.get("summaries", []) as Array:
		if not raw_summary is Dictionary:
			return false
		var summary := raw_summary as Dictionary
		var slot_id := str(summary.get("slot_id", ""))
		if (
			not is_valid_slot_id(slot_id)
			or seen_slot_ids.has(slot_id)
			or int(summary.get("revision", 0)) < 1
			or int(summary.get("saved_at_unix", -1)) < 0
			or int(summary.get("saved_at_unix_msec", -1)) < 0
			or not is_valid_level_id(str(summary.get("level_id", "")))
			or not _is_number(summary.get("elapsed_seconds"))
			or float(summary.get("elapsed_seconds", -1.0)) < 0.0
			or not summary.get("recovered") is bool
			or not summary.get("generations_supported") is bool
			or not _is_valid_slot_fingerprint(summary.get("fingerprint"))
		):
			return false
		seen_slot_ids[slot_id] = true
	return true


func _is_valid_slot_fingerprint(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var fingerprint := value as Dictionary
	for generation: String in ["primary", "backup"]:
		var file_value: Variant = fingerprint.get(generation)
		if not file_value is Dictionary:
			return false
		var file_fingerprint := file_value as Dictionary
		if (
			not file_fingerprint.get("exists") is bool
			or not _is_number(file_fingerprint.get("modified_time"))
			or not _is_number(file_fingerprint.get("size"))
			or not _is_number(file_fingerprint.get("sample_hash"))
		):
			return false
	return true


static func slot_summary_is_newer(first: Dictionary, second: Dictionary) -> bool:
	var first_msec := int(
		first.get(
			"saved_at_unix_msec",
			int(first.get("saved_at_unix", 0)) * 1000,
		)
	)
	var second_msec := int(
		second.get(
			"saved_at_unix_msec",
			int(second.get("saved_at_unix", 0)) * 1000,
		)
	)
	if first_msec != second_msec:
		return first_msec > second_msec
	var first_revision := int(first.get("revision", 0))
	var second_revision := int(second.get("revision", 0))
	if first_revision != second_revision:
		return first_revision > second_revision
	var first_slot := str(first.get("slot_id", ""))
	var second_slot := str(second.get("slot_id", ""))
	return first_slot.naturalnocasecmp_to(second_slot) < 0


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
	return CAMPAIGN_PROGRESS.is_valid_level_id(level_id)


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
	if version == SCHEMA_VERSION:
		return _is_current_document(document)
	# Schema 1 used the same top-level envelope but did not own gameplay
	# profile identity or the player's tactical workspace.  Keep validation
	# intentionally narrow here; migration performs the complete current check.
	return (
		version == 1
		and document.get("session") is Dictionary
		and is_valid_level_id(str((document["session"] as Dictionary).get("level_id", "")))
	)


func _is_current_document(document: Dictionary) -> bool:
	if (
		int(document.get("schema_version", -1)) != SCHEMA_VERSION
		or str(document.get("game_id", "")) != GAME_ID
		or not is_valid_slot_id(str(document.get("slot_id", "")))
		or int(document.get("revision", 0)) < 1
		or int(document.get("saved_at_unix", -1)) < 0
		or (
			document.has("saved_at_unix_msec")
			and (
				not _is_number(document["saved_at_unix_msec"])
				or int(document["saved_at_unix_msec"]) < 0
			)
		)
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
	return CAMPAIGN_PROGRESS.is_valid_state(campaign)


func _is_valid_session(session: Dictionary) -> bool:
	if (
		not is_valid_level_id(str(session.get("level_id", "")))
		or (
			session.has("mission_rule_mode")
			and str(session.get("mission_rule_mode", "")) not in MISSION_RULE_MODES
		)
		or not _is_number(session.get("elapsed_seconds"))
		or float(session.get("elapsed_seconds", -1.0)) < 0.0
		or not session.get("camera") is Dictionary
		or not session.get("mission") is Dictionary
		or not session.get("squad") is Array
		or not session.get("enemies") is Array
		or not session.get("escorts") is Array
		or (session.has("ambient") and not session.get("ambient") is Array)
		or not session.get("world") is Dictionary
		or not session.get("runtime_profile") is Dictionary
		or not session.get("player_workspace") is Dictionary
	):
		return false
	var runtime_profile := session["runtime_profile"] as Dictionary
	if (
		str(runtime_profile.get("ruleset_mode", "")) not in RULESET_MODES
		or str(runtime_profile.get("difficulty_mode", "")) not in DIFFICULTY_MODES
		or str(runtime_profile.get("control_scheme", "")) not in CONTROL_SCHEMES
		or str(runtime_profile.get("mission_rule_mode", "")) not in MISSION_RULE_MODES
		or not runtime_profile.get("custom_difficulty", {}) is Dictionary
		or str(runtime_profile.get("content_identity", "")).is_empty()
	):
		return false
	var player_workspace := session["player_workspace"] as Dictionary
	if (
		not player_workspace.get("control_groups", {}) is Dictionary
		or not player_workspace.get("camera_bookmarks", {}) is Dictionary
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
	if world.has("snapshot_presence"):
		var raw_presence: Variant = world["snapshot_presence"]
		if not raw_presence is Dictionary:
			return false
		for presence_key: String in ["field_pickups", "explosive_props"]:
			if (
				(raw_presence as Dictionary).has(presence_key)
				and not (raw_presence as Dictionary)[presence_key] is bool
			):
				return false
	for key: String in [
		"activated_scene_indices",
		"collected_scene_indices",
		"destroyed_scene_indices",
	]:
		if not world.get(key) is Array:
			return false
	for optional_key: String in [
		"buried_enemy_scene_indices",
		"legacy_special_world_objects",
		"legacy_explosion_effects",
		"legacy_ai_control_effects",
		"legacy_burial_caches",
	]:
		if world.has(optional_key) and not world.get(optional_key) is Array:
			return false
	if (
		world.has("pending_burial_command")
		and not world.get("pending_burial_command") is Dictionary
	):
		return false
	if not world.get("field_inventory") is Dictionary:
		return false
	for group_name: String in ["squad", "enemies", "escorts", "ambient"]:
		for actor: Variant in session.get(group_name, []) as Array:
			if not actor is Dictionary:
				return false
	return _is_json_safe(session)


func _normalize_session(session: Dictionary) -> Dictionary:
	var normalized := empty_session(str(session.get("level_id", "m000")))
	var mission_rule_mode := str(session.get("mission_rule_mode", "stable_mod"))
	normalized["mission_rule_mode"] = (
		mission_rule_mode if mission_rule_mode in MISSION_RULE_MODES else "stable_mod"
	)
	var source_profile_value: Variant = session.get("runtime_profile", {})
	var source_profile := (
		source_profile_value as Dictionary
		if source_profile_value is Dictionary
		else {}
	)
	var normalized_profile := normalized["runtime_profile"] as Dictionary
	var ruleset_mode := str(source_profile.get("ruleset_mode", "classic"))
	var difficulty_mode := str(source_profile.get("difficulty_mode", "normal"))
	var control_scheme := str(source_profile.get("control_scheme", "classic"))
	var profile_mission_rule := str(source_profile.get(
		"mission_rule_mode",
		normalized["mission_rule_mode"],
	))
	normalized_profile["ruleset_mode"] = (
		ruleset_mode if ruleset_mode in RULESET_MODES else "classic"
	)
	normalized_profile["difficulty_mode"] = (
		difficulty_mode if difficulty_mode in DIFFICULTY_MODES else "normal"
	)
	normalized_profile["control_scheme"] = (
		control_scheme if control_scheme in CONTROL_SCHEMES else "classic"
	)
	normalized_profile["mission_rule_mode"] = (
		profile_mission_rule
		if profile_mission_rule in MISSION_RULE_MODES
		else str(normalized["mission_rule_mode"])
	)
	normalized_profile["custom_difficulty"] = (
		(source_profile.get("custom_difficulty", {}) as Dictionary).duplicate(true)
		if source_profile.get("custom_difficulty", {}) is Dictionary
		else {}
	)
	var content_identity := str(source_profile.get(
		"content_identity",
		"legacy_schema_%d" % int(session.get("save_schema_version", 1)),
	))
	normalized_profile["content_identity"] = (
		content_identity if not content_identity.is_empty() else "unknown_content"
	)
	normalized["runtime_profile"] = normalized_profile
	var source_workspace_value: Variant = session.get("player_workspace", {})
	var source_workspace := (
		source_workspace_value as Dictionary
		if source_workspace_value is Dictionary
		else {}
	)
	normalized["player_workspace"] = {
		"control_groups": (
			(source_workspace.get("control_groups", {}) as Dictionary).duplicate(true)
			if source_workspace.get("control_groups", {}) is Dictionary
			else {}
		),
		"camera_bookmarks": (
			(source_workspace.get("camera_bookmarks", {}) as Dictionary).duplicate(true)
			if source_workspace.get("camera_bookmarks", {}) is Dictionary
			else {}
		),
	}
	normalized["elapsed_seconds"] = maxf(float(session.get("elapsed_seconds", 0.0)), 0.0)
	normalized["camera"] = (session.get("camera", normalized["camera"]) as Dictionary).duplicate(true)
	normalized["mission"] = (session.get("mission", normalized["mission"]) as Dictionary).duplicate(true)
	for group_name: String in ["squad", "enemies", "escorts", "ambient"]:
		normalized[group_name] = (session.get(group_name, []) as Array).duplicate(true)
	var normalized_world := (normalized["world"] as Dictionary).duplicate(true)
	var source_world: Variant = session.get("world", {})
	if source_world is Dictionary:
		var source_world_dictionary := source_world as Dictionary
		var raw_presence: Variant = source_world_dictionary.get("snapshot_presence")
		var snapshot_presence := {
			"field_pickups": source_world_dictionary.has(
				"remaining_field_pickup_scene_indices"
			),
			"explosive_props": source_world_dictionary.has("explosive_props"),
		}
		if raw_presence is Dictionary:
			for presence_key: String in snapshot_presence:
				if (raw_presence as Dictionary).get(presence_key) is bool:
					snapshot_presence[presence_key] = bool(
						(raw_presence as Dictionary)[presence_key]
					)
		for world_key: Variant in (source_world as Dictionary).keys():
			normalized_world[world_key] = (source_world as Dictionary)[world_key]
		normalized_world["snapshot_presence"] = snapshot_presence
	normalized["world"] = normalized_world
	return normalized


func _normalize_campaign(campaign: Dictionary) -> Dictionary:
	return CAMPAIGN_PROGRESS.normalize(campaign)


func _save_compatibility_guard(slot_id: String) -> Dictionary:
	_ensure_slot_summary_cache()
	var cached_value: Variant = _slot_summary_cache.get(slot_id)
	if cached_value is Dictionary:
		var cached_summary := cached_value as Dictionary
		if (
			bool(cached_summary.get("generations_supported", false))
			and _fingerprints_match(
				_slot_fingerprint(slot_id),
				cached_summary.get("fingerprint", {}) as Dictionary,
			)
		):
			return {"ok": true, "source": "slot_index"}
	for generation: String in ["primary", "backup"]:
		var path := slot_path(slot_id) + ("" if generation == "primary" else ".bak")
		var probe := _probe_schema_generation(path)
		if str(probe.get("status", "")) in [
			"unsupported_future_version",
			"unsupported_legacy_version",
		]:
			return _unsupported_generation_failure(probe, generation)
	if cached_value is Dictionary:
		(cached_value as Dictionary)["generations_supported"] = true
		_slot_summary_cache[slot_id] = cached_value
	return {"ok": true}


func _load_compatibility_guard(slot_id: String) -> Dictionary:
	var primary_probe := _probe_schema_generation(slot_path(slot_id))
	if str(primary_probe.get("status", "")) in [
		"unsupported_future_version",
		"unsupported_legacy_version",
	]:
		return _unsupported_generation_failure(primary_probe, "primary")
	if bool(primary_probe.get("loadable", false)):
		return {"ok": true}
	var backup_probe := _probe_schema_generation(slot_path(slot_id) + ".bak")
	if str(backup_probe.get("status", "")) in [
		"unsupported_future_version",
		"unsupported_legacy_version",
	]:
		return _unsupported_generation_failure(backup_probe, "backup")
	return {"ok": true}


func _probe_schema_generation(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing", "path": path, "loadable": false}
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return {"status": "unreadable", "path": path, "loadable": false}
	var source_text := input.get_as_text()
	input.close()
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return {"status": "malformed", "path": path, "loadable": false}
	var document := parser.data as Dictionary
	if not document.has("schema_version"):
		return {
			"status": "supported",
			"path": path,
			"schema_version": 0,
			"loadable": _is_loadable_document(document),
		}
	if not _is_number(document["schema_version"]):
		return {"status": "malformed", "path": path, "loadable": false}
	var version := int(document["schema_version"])
	if version < MIN_SUPPORTED_SCHEMA_VERSION:
		return {
			"status": "unsupported_legacy_version",
			"path": path,
			"schema_version": version,
			"loadable": false,
		}
	if version > SCHEMA_VERSION:
		return {
			"status": "unsupported_future_version",
			"path": path,
			"schema_version": version,
			"loadable": false,
		}
	return {
		"status": "supported",
		"path": path,
		"schema_version": version,
		"loadable": _is_loadable_document(document),
	}


func _unsupported_generation_failure(probe: Dictionary, generation: String) -> Dictionary:
	var code := str(probe.get("status", "unsupported_save_version"))
	var version := int(probe.get("schema_version", -1))
	var result := _failure(
		code,
		(
			"save %s uses schema %d; this build supports %d..%d and preserved every file"
			% [
				generation,
				version,
				MIN_SUPPORTED_SCHEMA_VERSION,
				SCHEMA_VERSION,
			]
		),
	)
	result["schema_version"] = version
	result["generation"] = generation
	result["path"] = str(probe.get("path", ""))
	result["preserved"] = true
	return result


func _migrate_document(document: Dictionary, requested_slot_id: String) -> Dictionary:
	var source_version := int(document.get("schema_version", 0))
	if source_version == SCHEMA_VERSION:
		var normalized_document := document.duplicate(true)
		normalized_document["saved_at_unix_msec"] = int(
			document.get(
				"saved_at_unix_msec",
				int(document.get("saved_at_unix", 0)) * 1000,
			)
		)
		normalized_document["session"] = _normalize_session(
			document.get("session", {}) as Dictionary
		)
		normalized_document["campaign"] = _normalize_campaign(
			document.get("campaign", default_campaign()) as Dictionary
		)
		return normalized_document
	var raw_session: Dictionary
	if document.get("session") is Dictionary:
		raw_session = (document["session"] as Dictionary).duplicate(true)
		raw_session["save_schema_version"] = source_version
	else:
		raw_session = empty_session(str(document.get("level_id", "m000")))
		raw_session["elapsed_seconds"] = maxf(float(document.get("elapsed_seconds", 0.0)), 0.0)
		(raw_session["world"] as Dictionary)["snapshot_presence"] = {
			"field_pickups": false,
			"explosive_props": false,
		}
	return {
		"schema_version": SCHEMA_VERSION,
		"game_id": GAME_ID,
		"slot_id": requested_slot_id,
		"revision": maxi(int(document.get("revision", 1)), 1),
		"saved_at_unix": maxi(int(document.get("saved_at_unix", 0)), 0),
		"saved_at_unix_msec": maxi(
			int(document.get(
				"saved_at_unix_msec",
				maxi(int(document.get("saved_at_unix", 0)), 0) * 1000,
			)),
			0,
		),
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
