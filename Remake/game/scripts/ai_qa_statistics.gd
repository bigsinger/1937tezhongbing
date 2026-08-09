class_name AiQaStatistics
extends RefCounted

const SCHEMA_VERSION := 1
const EVENT_KINDS: Array[String] = [
	"alert",
	"evidence",
	"search_assignment",
	"search_repeat",
	"reservation_wait",
	"stuck_recovery",
	"player_death",
	"weapon_fire",
	"weapon_hit",
	"ammo_consumed",
	"mission_failure",
]

var _counts: Dictionary = {}
var _by_weapon: Dictionary = {}
var _death_cells: Dictionary = {}
var _failure_reasons: Dictionary = {}


func record(kind: String, payload: Dictionary = {}) -> bool:
	var normalized := kind.strip_edges().to_lower()
	if normalized not in EVENT_KINDS:
		return false
	_counts[normalized] = int(_counts.get(normalized, 0)) + 1
	if normalized in ["weapon_fire", "weapon_hit", "ammo_consumed"]:
		var weapon := str(payload.get("weapon", "unknown")).strip_edges().to_lower()
		if weapon.is_empty():
			weapon = "unknown"
		var row := _by_weapon.get(weapon, {}) as Dictionary
		row[normalized] = int(row.get(normalized, 0)) + maxi(int(payload.get("count", 1)), 0)
		_by_weapon[weapon] = row
	elif normalized == "player_death":
		var point := payload.get("position", Vector2.ZERO) as Vector2
		var cell := "%d:%d" % [floori(point.x / 64.0), floori(point.y / 64.0)]
		_death_cells[cell] = int(_death_cells.get(cell, 0)) + 1
	elif normalized == "mission_failure":
		var reason := str(payload.get("reason", "unknown")).strip_edges().to_lower()
		_failure_reasons[reason] = int(_failure_reasons.get(reason, 0)) + 1
	return true


func snapshot(extra: Dictionary = {}) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"counts": _counts.duplicate(true),
		"weapons": _by_weapon.duplicate(true),
		"player_death_cells_64px": _death_cells.duplicate(true),
		"failure_reasons": _failure_reasons.duplicate(true),
		"extra": extra.duplicate(true),
	}


func export_local(mission_id: String, extra: Dictionary = {}) -> Dictionary:
	var safe_mission := mission_id.strip_edges().to_lower()
	if safe_mission.is_empty() or not safe_mission.is_valid_identifier():
		safe_mission = "unknown"
	var root_path := ProjectSettings.globalize_path("user://qa/ai")
	var error := DirAccess.make_dir_recursive_absolute(root_path)
	if error != OK:
		return {"ok": false, "error": error}
	var file_path := root_path.path_join(
		"%s-%d.json" % [safe_mission, Time.get_unix_time_from_system()]
	)
	if file_path.get_base_dir().simplify_path() != root_path.simplify_path():
		return {"ok": false, "error": ERR_INVALID_PARAMETER}
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error()}
	file.store_string(JSON.stringify(snapshot(extra), "  ", true))
	file.close()
	return {"ok": true, "path": file_path}


func clear() -> void:
	_counts.clear()
	_by_weapon.clear()
	_death_cells.clear()
	_failure_reasons.clear()
