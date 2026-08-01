class_name OriginalCrtRandomStartupCatalog
extends RefCounted

const CATALOG_PATH := (
	"res://data/original_crt_random_startup_catalog.json"
)
const CATALOG_ID := "original-crt-random-startup-v3"
const CONTENT_PROFILE := "repository-mod-12-level-20260729"

static var _catalog_cache: Dictionary = {}
static var _levels_by_id: Dictionary = {}
static var _actors_by_level: Dictionary = {}
static var _gates_by_level: Dictionary = {}


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
		int(catalog.get("schema_version", 0)) != 3
		or str(catalog.get("catalog_id", "")) != CATALOG_ID
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
	var profile_value: Variant = _levels_by_id.get(level_id, {})
	if not profile_value is Dictionary:
		return {}
	return (profile_value as Dictionary).duplicate(true)


static func startup_state(level_id: String) -> int:
	var profile := level_profile(level_id)
	var state_text := str(profile.get("final_state_hex", ""))
	if not state_text.begins_with("0x"):
		return 1
	return state_text.hex_to_int()


static func startup_draw_count(level_id: String) -> int:
	return int(level_profile(level_id).get(
		"initialization_draw_count",
		0,
	))


static func first_gameplay_update_records(
	level_id: String,
) -> Array[Dictionary]:
	var profile := level_profile(level_id)
	var update_value: Variant = profile.get(
		"first_gameplay_update",
		{},
	)
	if not update_value is Dictionary:
		return []
	var records_value: Variant = (update_value as Dictionary).get(
		"records",
		[],
	)
	if not records_value is Array:
		return []
	var records: Array[Dictionary] = []
	for record_value: Variant in records_value as Array:
		if record_value is Dictionary:
			records.append(
				(record_value as Dictionary).duplicate(true)
			)
	return records


static func first_gameplay_update_outcomes(
	level_id: String,
) -> Array[Dictionary]:
	var profile := level_profile(level_id)
	var update_value: Variant = profile.get(
		"first_gameplay_update",
		{},
	)
	if not update_value is Dictionary:
		return []
	var outcomes_value: Variant = (update_value as Dictionary).get(
		"actor_outcomes",
		[],
	)
	if not outcomes_value is Array:
		return []
	var outcomes: Array[Dictionary] = []
	for outcome_value: Variant in outcomes_value as Array:
		if outcome_value is Dictionary:
			outcomes.append(
				(outcome_value as Dictionary).duplicate(true)
			)
	return outcomes


static func actor_initialization(
	level_id: String,
	runtime_index: int,
) -> Dictionary:
	_ensure_indexes()
	var actor_map_value: Variant = _actors_by_level.get(level_id, {})
	if not actor_map_value is Dictionary:
		return {}
	var entry_value: Variant = (actor_map_value as Dictionary).get(
		runtime_index,
		{},
	)
	if not entry_value is Dictionary:
		return {}
	return (entry_value as Dictionary).duplicate(true)


static func is_observation_gate_actor(
	level_id: String,
	runtime_index: int,
) -> bool:
	_ensure_indexes()
	var gate_map_value: Variant = _gates_by_level.get(level_id, {})
	if not gate_map_value is Dictionary:
		return false
	return (gate_map_value as Dictionary).has(runtime_index)


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
		var entries_value: Variant = level.get(
			"actor_initialization",
			[],
		)
		if entries_value is Array:
			for entry_value: Variant in entries_value as Array:
				if not entry_value is Dictionary:
					continue
				var entry := entry_value as Dictionary
				actor_map[int(entry.get("runtime_index", -1))] = entry
		_actors_by_level[level_id] = actor_map
		var gate_map: Dictionary = {}
		var indices_value: Variant = level.get(
			"observation_gate_actor_indices",
			[],
		)
		if indices_value is Array:
			for index_value: Variant in indices_value as Array:
				gate_map[int(index_value)] = true
		_gates_by_level[level_id] = gate_map
