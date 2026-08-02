class_name OriginalCrtRandomLocalSearchTiming
extends RefCounted

const CATALOG_PATH := (
	"res://data/original_crt_random_local_search_timing.json"
)
const CATALOG_ID := "original-crt-random-local-search-timing-v1"
const CONTENT_PROFILE := "repository-mod-12-level-20260729"

static var _catalog_cache: Dictionary = {}
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
		int(catalog.get("schema_version", 0)) != 1
		or str(catalog.get("catalog_id", "")) != CATALOG_ID
		or str(catalog.get("content_profile", "")) != CONTENT_PROFILE
	):
		return {}
	var levels_value: Variant = catalog.get("levels", [])
	if not levels_value is Array or (levels_value as Array).size() != 12:
		return {}
	_catalog_cache = catalog
	return _catalog_cache


static func event_for_actor_round(
	level_id: String,
	round_index: int,
	runtime_index: int,
) -> Dictionary:
	_ensure_indexes()
	var level_value: Variant = _events_by_level_round_actor.get(
		level_id,
		{},
	)
	if not level_value is Dictionary:
		return {}
	var round_value: Variant = (level_value as Dictionary).get(
		round_index,
		{},
	)
	if not round_value is Dictionary:
		return {}
	var event_value: Variant = (round_value as Dictionary).get(
		runtime_index,
		{},
	)
	return (
		(event_value as Dictionary).duplicate(true)
		if event_value is Dictionary
		else {}
	)


static func level_event_count(level_id: String) -> int:
	var levels_value: Variant = load_catalog().get("levels", [])
	if not levels_value is Array:
		return 0
	for level_value: Variant in levels_value as Array:
		if not level_value is Dictionary:
			continue
		var level := level_value as Dictionary
		if str(level.get("id", "")) == level_id:
			return int(level.get("event_count", 0))
	return 0


static func _ensure_indexes() -> void:
	if not _events_by_level_round_actor.is_empty():
		return
	var levels_value: Variant = load_catalog().get("levels", [])
	if not levels_value is Array:
		return
	for level_value: Variant in levels_value as Array:
		if not level_value is Dictionary:
			continue
		var level := level_value as Dictionary
		var level_id := str(level.get("id", ""))
		if level_id.is_empty():
			continue
		var rounds: Dictionary = {}
		var events_value: Variant = level.get("events", [])
		if events_value is Array:
			for event_value: Variant in events_value as Array:
				if not event_value is Dictionary:
					continue
				var event := event_value as Dictionary
				var round_index := int(event.get("round_index", 0))
				var runtime_index := int(event.get("runtime_index", -1))
				if round_index <= 0 or runtime_index < 0:
					continue
				var actor_map_value: Variant = rounds.get(
					round_index,
					{},
				)
				var actor_map: Dictionary = (
					actor_map_value as Dictionary
					if actor_map_value is Dictionary
					else {}
				)
				actor_map[runtime_index] = event
				rounds[round_index] = actor_map
		_events_by_level_round_actor[level_id] = rounds
