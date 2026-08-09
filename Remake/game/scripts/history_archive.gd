class_name HistoryArchive
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "res://data/history_archive.json"
const ENGLISH_PATH := "res://data/history_archive_en.json"
const LOCALIZATION_SERVICE_SCRIPT: Script = preload("res://scripts/localization_service.gd")

var entries: Dictionary = {}
var last_error := ""


func load_catalog(path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	entries.clear()
	if (
		path == DEFAULT_PATH
		and TranslationServer.get_locale().to_lower().begins_with("en")
		and FileAccess.file_exists(ENGLISH_PATH)
	):
		path = ENGLISH_PATH
	if not FileAccess.file_exists(path):
		last_error = _text("ERROR_HISTORY_MISSING_FORMAT") % path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		last_error = _text("ERROR_HISTORY_NOT_OBJECT")
		return false
	var document := parsed as Dictionary
	if int(document.get("schema_version", 0)) != SCHEMA_VERSION:
		last_error = _text("ERROR_HISTORY_UNSUPPORTED_VERSION")
		return false
	var raw_entries: Variant = document.get("missions", [])
	if not raw_entries is Array:
		last_error = _text("ERROR_HISTORY_MISSIONS_ARRAY")
		return false
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			last_error = _text("ERROR_HISTORY_INVALID_ENTRY")
			entries.clear()
			return false
		var entry := _normalize_entry(raw_entry as Dictionary)
		var mission_id := str(entry.get("id", ""))
		if mission_id.is_empty() or entries.has(mission_id):
			last_error = _text("ERROR_HISTORY_DUPLICATE_ID")
			entries.clear()
			return false
		entries[mission_id] = entry
	return not entries.is_empty()


func entry_for(mission_id: String) -> Dictionary:
	return (entries.get(mission_id, {}) as Dictionary).duplicate(true)


func ordered_entries(level_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mission_id: String in level_ids:
		var entry := entry_for(mission_id)
		if not entry.is_empty():
			result.append(entry)
	return result


func formatted_entry(mission_id: String) -> String:
	var entry := entry_for(mission_id)
	if entry.is_empty():
		return _text("UI_NO_HISTORY_ENTRY")
	var lines: Array[String] = []
	lines.append("[font_size=26][color=#ead99b][b]%s[/b][/color][/font_size]" % str(entry["title"]))
	lines.append("[color=#a8c8a0]%s[/color]" % str(entry["period"]))
	lines.append("")
	lines.append("[b]%s[/b]\n%s" % [_text("HISTORY_CONTEXT"), str(entry["historical_context"])])
	lines.append("")
	lines.append("[b]%s[/b]\n%s" % [_text("HISTORY_OBJECTIVE_CONTEXT"), str(entry["objective_context"])])
	lines.append("")
	lines.append("[b]%s[/b]\n%s" % [_text("HISTORY_FACT_VS_FICTION"), str(entry["fact_vs_fiction"])])
	_append_terms(lines, _text("HISTORY_PEOPLE"), entry.get("people", []) as Array)
	_append_terms(lines, _text("HISTORY_PLACES"), entry.get("places", []) as Array)
	_append_terms(lines, _text("HISTORY_WEAPONS"), entry.get("weapons", []) as Array)
	_append_terms(lines, _text("HISTORY_EVENTS"), entry.get("events", []) as Array)
	lines.append("")
	lines.append("[b]%s[/b]\n%s" % [_text("HISTORY_OPTIONAL_CHALLENGE"), str(entry["optional_challenge"])])
	lines.append("")
	lines.append("[color=#b8b8aa]%s[/color]" % _text("HISTORY_DISCLAIMER"))
	return "\n".join(lines)


func build_debrief(mission_id: String, statistics: Dictionary) -> String:
	var entry := entry_for(mission_id)
	var elapsed_seconds := maxi(int(statistics.get("elapsed_msec", 0)) / 1000, 0)
	var minutes := elapsed_seconds / 60
	var seconds := elapsed_seconds % 60
	var attacks := maxi(int(statistics.get("attacks", 0)), 0)
	var hits := maxi(int(statistics.get("hits", 0)), 0)
	var accuracy := 0.0 if attacks == 0 else 100.0 * float(hits) / float(attacks)
	var lines: Array[String] = [
		"[font_size=24][color=#ead99b][b]%s[/b][/color][/font_size]" % _text("UI_MISSION_DEBRIEF"),
		_text("HISTORY_DEBRIEF_STATS") % [
			minutes,
			seconds,
			int(statistics.get("commands", 0)),
			attacks,
			hits,
			accuracy,
		],
		_text("HISTORY_DEBRIEF_COUNTS") % [
			int(statistics.get("enemies_eliminated", 0)),
			int(statistics.get("pickups", 0)),
			int(statistics.get("alarms", 0)),
			int(statistics.get("checkpoint_loads", 0)),
		],
	]
	if not entry.is_empty():
		var challenge := str(entry.get("optional_challenge", ""))
		var challenge_result := _evaluate_challenge(entry, statistics)
		lines.append(_text("HISTORY_CHALLENGE_RESULT") % [challenge, challenge_result])
		lines.append("")
		lines.append("[b]%s[/b]\n%s" % [_text("HISTORY_FACT_VS_FICTION"), str(entry.get("fact_vs_fiction", ""))])
	return "\n".join(lines)


func validate_required_missions(level_ids: Array[String]) -> Array[String]:
	var failures: Array[String] = []
	for mission_id: String in level_ids:
		if not entries.has(mission_id):
			failures.append(_text("ERROR_HISTORY_REQUIRED_FORMAT") % mission_id)
			continue
		var entry := entries[mission_id] as Dictionary
		for field: String in [
			"title", "period", "historical_context", "objective_context",
			"fact_vs_fiction", "optional_challenge",
		]:
			if str(entry.get(field, "")).strip_edges().is_empty():
				failures.append(
					_text("ERROR_HISTORY_FIELD_FORMAT") % [mission_id, field]
				)
		for collection: String in ["people", "places", "weapons", "events"]:
			if (entry.get(collection, []) as Array).is_empty():
				failures.append(
					_text("ERROR_HISTORY_TERM_FORMAT") % [mission_id, collection]
				)
	return failures


static func _normalize_entry(raw_entry: Dictionary) -> Dictionary:
	var result := {
		"id": str(raw_entry.get("id", "")).strip_edges().to_lower(),
		"title": str(raw_entry.get("title", "")).strip_edges(),
		"period": str(raw_entry.get("period", "")).strip_edges(),
		"historical_context": str(raw_entry.get("historical_context", "")).strip_edges(),
		"objective_context": str(raw_entry.get("objective_context", "")).strip_edges(),
		"fact_vs_fiction": str(raw_entry.get("fact_vs_fiction", "")).strip_edges(),
		"optional_challenge": str(raw_entry.get("optional_challenge", "")).strip_edges(),
		"challenge": (raw_entry.get("challenge", {}) as Dictionary).duplicate(true),
	}
	for collection: String in ["people", "places", "weapons", "events"]:
		var terms: Array[Dictionary] = []
		for raw_term: Variant in raw_entry.get(collection, []) as Array:
			if raw_term is Dictionary:
				var term := raw_term as Dictionary
				terms.append({
					"name": str(term.get("name", "")).strip_edges(),
					"note": str(term.get("note", "")).strip_edges(),
				})
		result[collection] = terms
	return result


static func _append_terms(lines: Array[String], heading: String, terms: Array) -> void:
	if terms.is_empty():
		return
	lines.append("")
	lines.append("[b]%s[/b]" % heading)
	for raw_term: Variant in terms:
		var term := raw_term as Dictionary
		lines.append(_text("HISTORY_TERM_FORMAT") % [
			str(term.get("name", "")),
			str(term.get("note", "")),
		])


static func _evaluate_challenge(entry: Dictionary, statistics: Dictionary) -> String:
	var challenge := entry.get("challenge", {}) as Dictionary
	var passed := true
	if challenge.has("max_alarms"):
		passed = passed and int(statistics.get("alarms", 0)) <= int(challenge["max_alarms"])
	if challenge.has("max_elapsed_seconds"):
		passed = passed and int(statistics.get("elapsed_msec", 0)) <= int(challenge["max_elapsed_seconds"]) * 1000
	if challenge.has("min_accuracy"):
		var attacks := maxi(int(statistics.get("attacks", 0)), 1)
		passed = passed and float(statistics.get("hits", 0)) / float(attacks) >= float(challenge["min_accuracy"])
	if challenge.has("max_player_losses"):
		passed = passed and int(statistics.get("player_losses", 0)) <= int(challenge["max_player_losses"])
	return (
		_text("HISTORY_CHALLENGE_PASSED")
		if passed
		else _text("HISTORY_CHALLENGE_RETRY")
	)


static func _text(key: String) -> String:
	return LOCALIZATION_SERVICE_SCRIPT.translate_key(key)
