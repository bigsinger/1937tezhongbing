class_name OriginalCrtRandomRuntimeState
extends RefCounted

const CATALOG_PATH := (
	"res://data/original_crt_random_runtime_state.json"
)
const CATALOG_ID := "original-crt-random-runtime-state-v1"
const CONTENT_PROFILE := "repository-mod-12-level-20260729"

static var _catalog_cache: Dictionary = {}
static var _levels_by_id: Dictionary = {}
static var _actors_by_level: Dictionary = {}


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
		or str(catalog.get("baseline_id", "")) != CATALOG_ID
		or str(catalog.get("content_profile", "")) != CONTENT_PROFILE
	):
		return {}
	var levels_value: Variant = catalog.get("levels", [])
	if not levels_value is Array or (levels_value as Array).size() != 12:
		return {}
	_catalog_cache = catalog
	return _catalog_cache


static func level_profile(level_id: String) -> Dictionary:
	_ensure_indexes()
	var value: Variant = _levels_by_id.get(level_id, {})
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func actor_profile(
	level_id: String,
	runtime_index: int,
) -> Dictionary:
	_ensure_indexes()
	var actor_map_value: Variant = _actors_by_level.get(level_id, {})
	if not actor_map_value is Dictionary:
		return {}
	var value: Variant = (actor_map_value as Dictionary).get(
		runtime_index,
		{},
	)
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func pursuit_target_runtime_index(
	level_id: String,
	runtime_index: int,
) -> int:
	var profile := actor_profile(level_id, runtime_index)
	var entry_value: Variant = profile.get("entry", {})
	if not entry_value is Dictionary:
		return -1
	return int(
		(entry_value as Dictionary).get(
			"pursuit_runtime_index",
			-1,
		)
	)


static func pursuit_call_site_rva(
	level_id: String,
	runtime_index: int,
) -> int:
	var level := level_profile(level_id)
	var pursuit_value: Variant = level.get("pursuit", {})
	if not pursuit_value is Dictionary:
		return 0
	var links_value: Variant = (pursuit_value as Dictionary).get(
		"links",
		[],
	)
	if not links_value is Array:
		return 0
	for link_value: Variant in links_value as Array:
		if not link_value is Dictionary:
			continue
		var link := link_value as Dictionary
		if int(link.get("runtime_index", -1)) != runtime_index:
			continue
		return str(
			link.get("call_site_rva", "0x0")
		).hex_to_int()
	return 0


static func _ensure_indexes() -> void:
	if not _levels_by_id.is_empty():
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
		_levels_by_id[level_id] = level
		var actor_map: Dictionary = {}
		var actors_value: Variant = level.get("actors", [])
		if actors_value is Array:
			for actor_value: Variant in actors_value as Array:
				if not actor_value is Dictionary:
					continue
				var actor := actor_value as Dictionary
				actor_map[int(actor.get("runtime_index", -1))] = actor
		_actors_by_level[level_id] = actor_map
