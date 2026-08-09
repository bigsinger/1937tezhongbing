class_name CommandReplay
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_COMMANDS := 16384
const MAX_HASHES := 4096

var header: Dictionary = {}
var commands: Array[Dictionary] = []
var hashes: Array[Dictionary] = []
var recording := false
var _record_serial := 0


func begin(new_header: Dictionary) -> bool:
	for required: String in [
		"runtime_version",
		"ruleset_mode",
		"difficulty_mode",
		"content_identity",
		"initial_checkpoint",
	]:
		if str(new_header.get(required, "")).is_empty():
			return false
	header = new_header.duplicate(true)
	header["schema_version"] = SCHEMA_VERSION
	commands.clear()
	hashes.clear()
	_record_serial = 0
	recording = true
	return true


func observe_scheduled(command: Dictionary) -> void:
	if not recording or commands.size() >= MAX_COMMANDS:
		return
	var sanitized := _sanitize_command(command)
	_record_serial += 1
	sanitized["record_order"] = _record_serial
	sanitized["stream"] = "scheduled"
	commands.append(sanitized)


func observe_runtime_command(command: Dictionary, simulation_tick: int) -> void:
	if not recording or commands.size() >= MAX_COMMANDS:
		return
	_record_serial += 1
	commands.append({
		"sequence": int(command.get("sequence", 0)),
		"execute_tick": maxi(simulation_tick, 0),
		"actor_id": int(command.get("actor_id", -1)),
		"name": str(command.get("name", "")),
		"source": str(command.get("source", "gameplay")),
		"payload": _canonicalize(command.get("payload", {})),
		"precondition": {},
		"timeout_tick": -1,
		"failure_policy": "skip",
		"stream": "runtime",
		"record_order": _record_serial,
	})


func observe_runtime_event(event: Dictionary, simulation_tick: int) -> void:
	# Mission/world events are part of the deterministic logical stream.  We
	# deliberately record their normalized payload rather than any input-device
	# coordinates or Node references so the same document can run headlessly.
	if not recording or commands.size() >= MAX_COMMANDS:
		return
	var event_name := str(event.get("name", event.get("event_name", "")))
	if event_name.is_empty():
		return
	_record_serial += 1
	commands.append({
		"sequence": int(event.get("sequence", 0)),
		"execute_tick": maxi(simulation_tick, 0),
		"actor_id": int(event.get("actor_id", -1)),
		"name": "event:%s" % event_name,
		"source": str(event.get("source", "runtime_event")),
		"payload": _canonicalize(event.get("payload", {})),
		"precondition": {},
		"timeout_tick": -1,
		"failure_policy": "skip",
		"stream": "event",
		"record_order": _record_serial,
	})


func record_hash(tick: int, state: Variant) -> String:
	# Canonicalize once. The former implementation rebuilt the state for the
	# overall digest and then calculated an independent SHA-256 for every leaf
	# field. On a dense mission this retained about 750 KiB every 0.5 seconds and
	# blocked one physics tick for hundreds of milliseconds.
	var canonical: Variant = _canonicalize(state)
	var digest := JSON.stringify(canonical, "", true).sha256_text()
	if recording and hashes.size() < MAX_HASHES:
		hashes.append({
			"tick": tick,
			"sha256": digest,
			# A nested canonical diagnostic tree retains exact field-level
			# divergence without duplicating long paths or hashing each scalar.
			"fingerprints": canonical,
		})
	return digest


func finish() -> Dictionary:
	recording = false
	return document()


func document() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"header": header.duplicate(true),
		"commands": _ordered_commands(),
		"hashes": hashes.duplicate(true),
	}


func validate_for_playback(document_value: Dictionary, active_header: Dictionary) -> Dictionary:
	if int(document_value.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"ok": false, "reason": "schema_mismatch"}
	var replay_header := document_value.get("header", {}) as Dictionary
	for key: String in [
		"runtime_version",
		"ruleset_mode",
		"difficulty_mode",
		"content_identity",
		"initial_checkpoint",
	]:
		if str(replay_header.get(key, "")) != str(active_header.get(key, "")):
			return {"ok": false, "reason": "%s_mismatch" % key}
	if int(replay_header.get("random_state", -1)) != int(active_header.get("random_state", -2)):
		return {"ok": false, "reason": "random_state_mismatch"}
	var command_value: Variant = document_value.get("commands", [])
	if not command_value is Array or (command_value as Array).size() > MAX_COMMANDS:
		return {"ok": false, "reason": "invalid_commands"}
	var hash_value: Variant = document_value.get("hashes", [])
	if not hash_value is Array or (hash_value as Array).size() > MAX_HASHES:
		return {"ok": false, "reason": "invalid_hashes"}
	var previous_tick := -1
	for raw_command: Variant in command_value as Array:
		if not raw_command is Dictionary:
			return {"ok": false, "reason": "invalid_command_record"}
		var command := raw_command as Dictionary
		var execute_tick := int(command.get("execute_tick", -1))
		if execute_tick < 0 or str(command.get("name", "")).is_empty():
			return {"ok": false, "reason": "invalid_command_record"}
		if execute_tick < previous_tick:
			return {"ok": false, "reason": "unsorted_commands"}
		previous_tick = execute_tick
	return {"ok": true, "command_count": (command_value as Array).size()}


func first_hash_divergence(expected: Array, actual: Array) -> Dictionary:
	var count := mini(expected.size(), actual.size())
	for index: int in range(count):
		var left := expected[index] as Dictionary
		var right := actual[index] as Dictionary
		if int(left.get("tick", -1)) != int(right.get("tick", -1)) or str(left.get("sha256", "")) != str(right.get("sha256", "")):
			var result := {"diverged": true, "index": index, "expected": left, "actual": right}
			result.merge(_fingerprint_divergence(left, right), true)
			result["recent_commands"] = recent_commands_before_tick(int(right.get("tick", left.get("tick", -1))))
			return result
	if expected.size() != actual.size():
		return {"diverged": true, "index": count, "reason": "length_mismatch"}
	return {"diverged": false}


func recent_commands_before_tick(tick: int, limit: int = 8) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(commands.size() - 1, -1, -1):
		if int(commands[index].get("execute_tick", -1)) > tick:
			continue
		result.push_front(commands[index].duplicate(true))
		if result.size() >= maxi(limit, 0):
			break
	return result


static func state_fingerprints(value: Variant) -> Dictionary:
	var canonical: Variant = _canonicalize(value)
	return canonical if canonical is Dictionary else {"value": canonical}


static func state_hash(value: Variant) -> String:
	var canonical := JSON.stringify(_canonicalize(value), "", true)
	return canonical.sha256_text()


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array[String] = []
		for raw_key: Variant in source.keys():
			keys.append(str(raw_key))
		keys.sort()
		var result: Dictionary = {}
		for key: String in keys:
			result[key] = _canonicalize(source.get(key))
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_canonicalize(item))
		return result
	if value is Vector2:
		return {"x": (value as Vector2).x, "y": (value as Vector2).y}
	return value


static func _fingerprint_divergence(expected: Dictionary, actual: Dictionary) -> Dictionary:
	var expected_fields: Dictionary = expected.get("fingerprints", {}) as Dictionary
	var actual_fields: Dictionary = actual.get("fingerprints", {}) as Dictionary
	# Schema-1 replay documents created before the compact tree used flat
	# `root.* -> sha256` entries. Keep that reader path for compatibility.
	if _is_flat_fingerprint_map(expected_fields) or _is_flat_fingerprint_map(actual_fields):
		return _flat_fingerprint_divergence(expected_fields, actual_fields)
	var path := _first_nested_difference(
		expected_fields,
		actual_fields,
		"root",
	)
	return _divergence_metadata(path)


static func _is_flat_fingerprint_map(value: Dictionary) -> bool:
	for raw_key: Variant in value.keys():
		if str(raw_key).begins_with("root.") or str(raw_key).begins_with("root["):
			return true
	return false


static func _flat_fingerprint_divergence(
	expected_fields: Dictionary,
	actual_fields: Dictionary,
) -> Dictionary:
	var paths: Array[String] = []
	for raw_path: Variant in expected_fields.keys():
		paths.append(str(raw_path))
	for raw_path: Variant in actual_fields.keys():
		if not paths.has(str(raw_path)):
			paths.append(str(raw_path))
	paths.sort()
	for path: String in paths:
		if str(expected_fields.get(path, "")) == str(actual_fields.get(path, "")):
			continue
		return _divergence_metadata(path)
	return _divergence_metadata("unknown")


static func _first_nested_difference(
	expected: Variant,
	actual: Variant,
	path: String,
) -> String:
	if typeof(expected) != typeof(actual):
		return path
	if expected is Dictionary:
		var keys: Array[String] = []
		for raw_key: Variant in (expected as Dictionary).keys():
			keys.append(str(raw_key))
		for raw_key: Variant in (actual as Dictionary).keys():
			var key := str(raw_key)
			if not keys.has(key):
				keys.append(key)
		keys.sort()
		for key: String in keys:
			if not (expected as Dictionary).has(key) or not (actual as Dictionary).has(key):
				return "%s.%s" % [path, key]
			var nested := _first_nested_difference(
				(expected as Dictionary)[key],
				(actual as Dictionary)[key],
				"%s.%s" % [path, key],
			)
			if not nested.is_empty():
				return nested
		return ""
	if expected is Array:
		if (expected as Array).size() != (actual as Array).size():
			return path
		for index: int in range((expected as Array).size()):
			var nested := _first_nested_difference(
				(expected as Array)[index],
				(actual as Array)[index],
				"%s[%d]" % [path, index],
			)
			if not nested.is_empty():
				return nested
		return ""
	return "" if expected == actual else path


static func _divergence_metadata(path: String) -> Dictionary:
	if path.is_empty():
		path = "unknown"
	var actor_id := -1
	var dot_actor_marker := path.find(".actors.")
	if dot_actor_marker >= 0:
		var suffix := path.substr(dot_actor_marker + 8)
		actor_id = int(suffix.get_slice(".", 0).get_slice("[", 0))
	else:
		var bracket_actor_marker := path.find("actors[")
		if bracket_actor_marker >= 0:
			var suffix := path.substr(bracket_actor_marker + 7)
			actor_id = int(suffix.get_slice("]", 0))
	return {
		"system": path.get_slice(".", 1),
		"actor": actor_id,
		"field": path,
	}


func _sanitize_command(command: Dictionary) -> Dictionary:
	return {
		"sequence": int(command.get("sequence", 0)),
		"execute_tick": int(command.get("execute_tick", 0)),
		"actor_id": int(command.get("actor_id", -1)),
		"name": str(command.get("name", "")),
		"source": str(command.get("source", "")),
		"payload": _canonicalize(command.get("payload", {})),
		"precondition": _canonicalize(command.get("precondition", {})),
		"timeout_tick": int(command.get("timeout_tick", -1)),
		"failure_policy": str(command.get("failure_policy", "skip")),
	}


func _ordered_commands() -> Array[Dictionary]:
	var result: Array[Dictionary] = commands.duplicate(true)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_tick := int(left.get("execute_tick", 0))
			var right_tick := int(right.get("execute_tick", 0))
			if left_tick != right_tick:
				return left_tick < right_tick
			return int(left.get("record_order", 0)) < int(right.get("record_order", 0))
	)
	return result
