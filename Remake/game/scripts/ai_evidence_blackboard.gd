class_name AiEvidenceBlackboard
extends RefCounted

const SCHEMA_VERSION := 1
const EVIDENCE_TYPES: Array[String] = [
	"sighting",
	"gunshot",
	"footstep",
	"corpse",
	"door_opened",
	"discarded_item",
	"explosion",
]
const DEFAULT_LIFETIME_TICKS := 60 * 20
const MAX_EVIDENCE := 512

var _next_id := 1
var _tick := 0
var _records: Dictionary = {}
var _known_by_actor: Dictionary = {}
var _search_assignments: Dictionary = {}
var _observed_cells: Dictionary = {}
var _repeat_search_count := 0


func publish(
	type: String,
	world_position: Vector2,
	occurrence_tick: int,
	confidence: float,
	source_faction: int,
	source_actor_id: int,
	propagation: String,
	recipients: Array[int] = [],
	lifetime_ticks: int = DEFAULT_LIFETIME_TICKS,
) -> Dictionary:
	var normalized := type.strip_edges().to_lower()
	if normalized not in EVIDENCE_TYPES or confidence <= 0.0:
		return {"accepted": false, "reason": "invalid_evidence"}
	var evidence_id := _next_id
	_next_id += 1
	var record := {
		"evidence_id": evidence_id,
		"type": normalized,
		"x": world_position.x,
		"y": world_position.y,
		"occurrence_tick": maxi(occurrence_tick, 0),
		"confidence": clampf(confidence, 0.0, 1.0),
		"source_faction": source_faction,
		"source_actor_id": source_actor_id,
		"propagation": propagation.strip_edges().to_lower(),
		"expires_tick": maxi(occurrence_tick, 0) + maxi(lifetime_ticks, 1),
	}
	_records[evidence_id] = record
	for actor_id: int in recipients:
		grant(actor_id, evidence_id)
	_trim_records()
	return {"accepted": true, "evidence_id": evidence_id, "record": record.duplicate(true)}


func grant(actor_id: int, evidence_id: int) -> bool:
	if actor_id < 0 or not _records.has(evidence_id):
		return false
	var known := _known_by_actor.get(actor_id, {}) as Dictionary
	known[evidence_id] = true
	_known_by_actor[actor_id] = known
	return true


func refresh(
	evidence_id: int,
	world_position: Vector2,
	occurrence_tick: int,
	confidence: float,
	lifetime_ticks: int = DEFAULT_LIFETIME_TICKS,
) -> bool:
	if not _records.has(evidence_id) or confidence <= 0.0:
		return false
	var record := _records[evidence_id] as Dictionary
	record["x"] = world_position.x
	record["y"] = world_position.y
	record["occurrence_tick"] = maxi(occurrence_tick, _tick)
	record["confidence"] = clampf(confidence, 0.0, 1.0)
	record["expires_tick"] = int(record["occurrence_tick"]) + maxi(lifetime_ticks, 1)
	_records[evidence_id] = record
	return true


func share(source_actor_id: int, recipient_actor_ids: Array[int], evidence_id: int, propagation: String) -> int:
	if not actor_knows(source_actor_id, evidence_id):
		return 0
	var delivered := 0
	for actor_id: int in recipient_actor_ids:
		if grant(actor_id, evidence_id):
			delivered += 1
	if _records.has(evidence_id):
		(_records[evidence_id] as Dictionary)["propagation"] = propagation
	return delivered


func actor_knows(actor_id: int, evidence_id: int) -> bool:
	var known_value: Variant = _known_by_actor.get(actor_id)
	return known_value is Dictionary and bool((known_value as Dictionary).get(evidence_id, false))


func evidence_for_actor(actor_id: int, minimum_confidence: float = 0.05) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known := _known_by_actor.get(actor_id, {}) as Dictionary
	for raw_id: Variant in known.keys():
		var record_value: Variant = _records.get(int(raw_id))
		if not record_value is Dictionary:
			continue
		var record := (record_value as Dictionary).duplicate(true)
		var ratio := _confidence_at(record, _tick)
		if ratio < minimum_confidence:
			continue
		record["current_confidence"] = ratio
		result.append(record)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_confidence := float(left.get("current_confidence", 0.0))
			var right_confidence := float(right.get("current_confidence", 0.0))
			if not is_equal_approx(left_confidence, right_confidence):
				return left_confidence > right_confidence
			return int(left.get("occurrence_tick", 0)) > int(right.get("occurrence_tick", 0))
	)
	return result


func latest_for_actor(actor_id: int) -> Dictionary:
	var records := evidence_for_actor(actor_id)
	return records[0].duplicate(true) if not records.is_empty() else {}


func advance_to_tick(simulation_tick: int) -> int:
	_tick = maxi(simulation_tick, _tick)
	var removed := 0
	for raw_id: Variant in _records.keys().duplicate():
		if _tick >= int((_records[raw_id] as Dictionary).get("expires_tick", 0)):
			_remove_evidence(int(raw_id))
			removed += 1
	return removed


func assign_search_sector(
	actor_id: int,
	role: String,
	center: Vector2,
	radius: float,
	evidence_id: int,
) -> Dictionary:
	var cell_key := "%d:%d" % [roundi(center.x / 32.0), roundi(center.y / 32.0)]
	if _observed_cells.has(cell_key):
		_repeat_search_count += 1
	_observed_cells[cell_key] = int(_observed_cells.get(cell_key, 0)) + 1
	var assignment := {
		"actor_id": actor_id,
		"role": role,
		"center_x": center.x,
		"center_y": center.y,
		"radius": maxf(radius, 0.0),
		"evidence_id": evidence_id,
		"assigned_tick": _tick,
	}
	_search_assignments[actor_id] = assignment
	return assignment.duplicate(true)


func clear_search_assignment(actor_id: int) -> void:
	_search_assignments.erase(actor_id)


func search_assignment(actor_id: int) -> Dictionary:
	var value: Variant = _search_assignments.get(actor_id)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func statistics() -> Dictionary:
	var total_visits := 0
	for count: Variant in _observed_cells.values():
		total_visits += int(count)
	return {
		"evidence_count": _records.size(),
		"informed_actor_count": _known_by_actor.size(),
		"active_search_assignments": _search_assignments.size(),
		"search_cells_covered": _observed_cells.size(),
		"search_cell_visits": total_visits,
		"repeat_search_count": _repeat_search_count,
		"repeat_search_ratio": (
			float(_repeat_search_count) / float(total_visits)
			if total_visits > 0 else 0.0
		),
	}


func capture_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": _tick,
		"next_id": _next_id,
		"records": _dictionary_string_keys(_records),
		"known_by_actor": _nested_dictionary_string_keys(_known_by_actor),
		"search_assignments": _dictionary_string_keys(_search_assignments),
		"observed_cells": _observed_cells.duplicate(true),
		"repeat_search_count": _repeat_search_count,
	}


func restore_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	for required: String in ["records", "known_by_actor", "search_assignments"]:
		if not state.get(required, {}) is Dictionary:
			return false
	_tick = maxi(int(state.get("tick", 0)), 0)
	_next_id = maxi(int(state.get("next_id", 1)), 1)
	_records = _dictionary_int_keys(state.get("records", {}) as Dictionary)
	_known_by_actor.clear()
	for raw_actor: Variant in (state.get("known_by_actor", {}) as Dictionary).keys():
		var known_value: Variant = (state.get("known_by_actor", {}) as Dictionary)[raw_actor]
		if known_value is Dictionary:
			_known_by_actor[int(raw_actor)] = _dictionary_int_keys(known_value as Dictionary)
	_search_assignments = _dictionary_int_keys(state.get("search_assignments", {}) as Dictionary)
	_observed_cells = (state.get("observed_cells", {}) as Dictionary).duplicate(true)
	_repeat_search_count = maxi(int(state.get("repeat_search_count", 0)), 0)
	return true


func clear() -> void:
	_next_id = 1
	_tick = 0
	_records.clear()
	_known_by_actor.clear()
	_search_assignments.clear()
	_observed_cells.clear()
	_repeat_search_count = 0


func _confidence_at(record: Dictionary, tick: int) -> float:
	var start := int(record.get("occurrence_tick", 0))
	var end := maxi(int(record.get("expires_tick", start + 1)), start + 1)
	var lifetime_ratio := clampf(1.0 - float(maxi(tick - start, 0)) / float(end - start), 0.0, 1.0)
	return float(record.get("confidence", 0.0)) * lifetime_ratio


func _trim_records() -> void:
	while _records.size() > MAX_EVIDENCE:
		var oldest_id := -1
		var oldest_tick := 0x7fffffff
		for raw_id: Variant in _records.keys():
			var occurrence := int((_records[raw_id] as Dictionary).get("occurrence_tick", 0))
			if occurrence < oldest_tick:
				oldest_tick = occurrence
				oldest_id = int(raw_id)
		_remove_evidence(oldest_id)


func _remove_evidence(evidence_id: int) -> void:
	_records.erase(evidence_id)
	for known_value: Variant in _known_by_actor.values():
		(known_value as Dictionary).erase(evidence_id)
	for raw_actor: Variant in _search_assignments.keys().duplicate():
		if int((_search_assignments[raw_actor] as Dictionary).get("evidence_id", -1)) == evidence_id:
			_search_assignments.erase(raw_actor)


func _dictionary_string_keys(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in value.keys():
		result[str(raw_key)] = (value[raw_key] as Dictionary).duplicate(true)
	return result


func _nested_dictionary_string_keys(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in value.keys():
		var nested: Dictionary = {}
		for raw_nested: Variant in (value[raw_key] as Dictionary).keys():
			nested[str(raw_nested)] = bool((value[raw_key] as Dictionary)[raw_nested])
		result[str(raw_key)] = nested
	return result


func _dictionary_int_keys(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in value.keys():
		result[int(raw_key)] = value[raw_key]
	return result
