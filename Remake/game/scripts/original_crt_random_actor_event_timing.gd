class_name OriginalCrtRandomActorEventTiming
extends RefCounted

const CATALOG_PATH := (
	"res://data/original_crt_random_actor_event_timing.json"
)
const CATALOG_ID := "original-crt-random-actor-event-timing-v2"
const CONTENT_PROFILE := "repository-mod-12-level-20260729"
const EVENT_FIELD_COUNT := 20
const SHARED_COUNTER_CALL_SITES: Array[int] = [
	0x00056105,
	0x0005614F,
	0x00058946,
]
const PURSUIT_CALL_SITES: Array[int] = [
	0x0005D394,
	0x0005D47E,
]

static var _catalog_cache: Dictionary = {}
static var _level_profiles: Dictionary = {}
static var _events_by_level_round_actor: Dictionary = {}


static func load_catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var catalog := parsed as Dictionary
	if (
		int(catalog.get("schema_version", 0)) != 2
		or str(catalog.get("catalog_id", "")) != CATALOG_ID
		or str(catalog.get("content_profile", "")) != CONTENT_PROFILE
	):
		return {}
	var levels_value: Variant = catalog.get("levels", [])
	if not levels_value is Array or (levels_value as Array).size() != 12:
		return {}
	_catalog_cache = catalog
	return _catalog_cache


static func level_complete_round_count(level_id: String) -> int:
	_ensure_level_profiles()
	var profile_value: Variant = _level_profiles.get(level_id, {})
	return (
		int((profile_value as Dictionary).get("complete_round_count", 0))
		if profile_value is Dictionary
		else 0
	)


static func level_event_count(level_id: String) -> int:
	_ensure_level_profiles()
	var profile_value: Variant = _level_profiles.get(level_id, {})
	return (
		int((profile_value as Dictionary).get("event_count", 0))
		if profile_value is Dictionary
		else 0
	)


static func events_for_actor_round(
	level_id: String,
	round_index: int,
	runtime_index: int,
	accepted_call_sites: Array[int] = [],
) -> Array[Dictionary]:
	_ensure_level_index(level_id)
	var result: Array[Dictionary] = []
	var level_value: Variant = _events_by_level_round_actor.get(
		level_id,
		{},
	)
	if not level_value is Dictionary:
		return result
	var round_value: Variant = (level_value as Dictionary).get(
		round_index,
		{},
	)
	if not round_value is Dictionary:
		return result
	var events_value: Variant = (round_value as Dictionary).get(
		runtime_index,
		[],
	)
	if not events_value is Array:
		return result
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if (
			not accepted_call_sites.is_empty()
			and int(event.get("call_site_rva", 0))
				not in accepted_call_sites
		):
			continue
		result.append(event.duplicate(true))
	return result


static func _ensure_level_profiles() -> void:
	if not _level_profiles.is_empty():
		return
	var levels_value: Variant = load_catalog().get("levels", [])
	if not levels_value is Array:
		return
	for level_value: Variant in levels_value as Array:
		if not level_value is Dictionary:
			continue
		var level := level_value as Dictionary
		var level_id := str(level.get("id", ""))
		if not level_id.is_empty():
			_level_profiles[level_id] = level


static func _ensure_level_index(level_id: String) -> void:
	if _events_by_level_round_actor.has(level_id):
		return
	_ensure_level_profiles()
	var profile_value: Variant = _level_profiles.get(level_id, {})
	var rounds: Dictionary = {}
	if not profile_value is Dictionary:
		_events_by_level_round_actor[level_id] = rounds
		return
	var events_value: Variant = (profile_value as Dictionary).get(
		"events",
		[],
	)
	if events_value is Array:
		for row_value: Variant in events_value as Array:
			if not row_value is Array:
				continue
			var row := row_value as Array
			var event := _event_from_row(row)
			if event.is_empty():
				continue
			var round_index := int(event.get("round_index", 0))
			var runtime_index := int(event.get("runtime_index", -1))
			var actor_map_value: Variant = rounds.get(round_index, {})
			var actor_map: Dictionary = (
				actor_map_value as Dictionary
				if actor_map_value is Dictionary
				else {}
			)
			var actor_events_value: Variant = actor_map.get(
				runtime_index,
				[],
			)
			var actor_events: Array = (
				actor_events_value as Array
				if actor_events_value is Array
				else []
			)
			actor_events.append(event)
			actor_map[runtime_index] = actor_events
			rounds[round_index] = actor_map
	_events_by_level_round_actor[level_id] = rounds


static func _event_from_row(row: Array) -> Dictionary:
	if row.size() != EVENT_FIELD_COUNT:
		return {}
	return {
		"round_index": int(row[0]),
		"runtime_index": int(row[1]),
		"call_site_rva": int(row[2]),
		"value": int(row[3]),
		"world_x": int(row[4]),
		"world_y": int(row[5]),
		"previous_world_x": int(row[6]),
		"previous_world_y": int(row[7]),
		"shared_counter_before": int(row[8]),
		"shared_limit_before": int(row[9]),
		"route_update_active": int(row[10]),
		"movement_path_state": int(row[11]),
		"movement_active": int(row[12]),
		"goal_kind": int(row[13]),
		"goal_x": int(row[14]),
		"goal_y": int(row[15]),
		"command_variant": int(row[16]),
		"pursuit_runtime_index": int(row[17]),
		"pursuit_delay_counter": int(row[18]),
		"target_runtime_index": int(row[19]),
	}
