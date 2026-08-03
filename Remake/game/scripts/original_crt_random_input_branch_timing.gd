class_name OriginalCrtRandomInputBranchTiming
extends RefCounted

const CATALOG_PATH := (
	"res://data/original_crt_random_input_branch_timing.json"
)
const BASELINE_ID := "original-crt-random-input-branch-timing-v1"
const CONTENT_PROFILE := "repository-mod-12-level-20260729"
const EVENT_FIELD_COUNT := 4
const LOCAL_SEARCH_CALL_SITES: Array[int] = [
	0x0005D08F,
	0x0005D09D,
	0x0005D0B4,
	0x0005D0CB,
	0x0005D15F,
]

static var _catalog_cache: Dictionary = {}
static var _branch_profiles: Dictionary = {}
static var _events_by_branch_round_actor: Dictionary = {}
static var _local_search_by_branch_round_actor: Dictionary = {}


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
		or str(catalog.get("baseline_id", "")) != BASELINE_ID
		or str(catalog.get("content_profile", "")) != CONTENT_PROFILE
	):
		return {}
	var branches_value: Variant = catalog.get("branches", [])
	if not branches_value is Array or (branches_value as Array).size() != 1:
		return {}
	_catalog_cache = catalog
	return _catalog_cache


static func branch_profile(branch_id: String) -> Dictionary:
	_ensure_branch_profiles()
	var profile_value: Variant = _branch_profiles.get(branch_id, {})
	return (
		(profile_value as Dictionary).duplicate(true)
		if profile_value is Dictionary
		else {}
	)


static func events_for_actor_round(
	branch_id: String,
	round_index: int,
	runtime_index: int,
	accepted_call_sites: Array[int] = [],
) -> Array[Dictionary]:
	_ensure_branch_index(branch_id)
	var result: Array[Dictionary] = []
	var branch_value: Variant = _events_by_branch_round_actor.get(
		branch_id,
		{},
	)
	if not branch_value is Dictionary:
		return result
	var round_value: Variant = (branch_value as Dictionary).get(
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


static func local_search_event_for_actor_round(
	branch_id: String,
	round_index: int,
	runtime_index: int,
) -> Dictionary:
	_ensure_branch_index(branch_id)
	var branch_value: Variant = _local_search_by_branch_round_actor.get(
		branch_id,
		{},
	)
	if not branch_value is Dictionary:
		return {}
	var round_value: Variant = (branch_value as Dictionary).get(
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


static func input_events(branch_id: String) -> Array[Dictionary]:
	var profile := branch_profile(branch_id)
	var result: Array[Dictionary] = []
	var events_value: Variant = profile.get("input_events", [])
	if not events_value is Array:
		return result
	for event_value: Variant in events_value as Array:
		if event_value is Dictionary:
			result.append((event_value as Dictionary).duplicate(true))
	return result


static func _ensure_branch_profiles() -> void:
	if not _branch_profiles.is_empty():
		return
	var branches_value: Variant = load_catalog().get("branches", [])
	if not branches_value is Array:
		return
	for branch_value: Variant in branches_value as Array:
		if not branch_value is Dictionary:
			continue
		var branch := branch_value as Dictionary
		var branch_id := str(branch.get("id", ""))
		if not branch_id.is_empty():
			_branch_profiles[branch_id] = branch


static func _ensure_branch_index(branch_id: String) -> void:
	if _events_by_branch_round_actor.has(branch_id):
		return
	_ensure_branch_profiles()
	var profile_value: Variant = _branch_profiles.get(branch_id, {})
	var rounds: Dictionary = {}
	var local_search_rounds: Dictionary = {}
	if not profile_value is Dictionary:
		_events_by_branch_round_actor[branch_id] = rounds
		_local_search_by_branch_round_actor[branch_id] = local_search_rounds
		return
	var events_value: Variant = (profile_value as Dictionary).get(
		"actor_events",
		[],
	)
	if events_value is Array:
		for row_value: Variant in events_value as Array:
			if not row_value is Array:
				continue
			var event := _event_from_row(row_value as Array)
			if event.is_empty():
				continue
			var round_index := int(event.get("round_index", 0))
			var runtime_index := int(event.get("runtime_index", -1))
			var actor_map: Dictionary = rounds.get(round_index, {}) as Dictionary
			var actor_events: Array = actor_map.get(runtime_index, []) as Array
			actor_events.append(event)
			actor_map[runtime_index] = actor_events
			rounds[round_index] = actor_map
	for round_key: Variant in rounds.keys():
		var round_index := int(round_key)
		var actor_map := rounds[round_key] as Dictionary
		for actor_key: Variant in actor_map.keys():
			var runtime_index := int(actor_key)
			var local_events: Array[Dictionary] = []
			for event_value: Variant in actor_map[actor_key] as Array:
				var event := event_value as Dictionary
				if int(event.get("call_site_rva", 0)) in LOCAL_SEARCH_CALL_SITES:
					local_events.append(event)
			if local_events.is_empty():
				continue
			if local_events.size() != LOCAL_SEARCH_CALL_SITES.size():
				continue
			var values: Array[int] = []
			var complete := true
			for event_index: int in range(local_events.size()):
				if (
					int(local_events[event_index].get("call_site_rva", 0))
					!= LOCAL_SEARCH_CALL_SITES[event_index]
				):
					complete = false
					break
				values.append(int(local_events[event_index].get("value", -1)))
			if not complete:
				continue
			var local_actor_map: Dictionary = local_search_rounds.get(
				round_index,
				{},
			) as Dictionary
			local_actor_map[runtime_index] = {
				"round_index": round_index,
				"runtime_index": runtime_index,
				"values": values,
			}
			local_search_rounds[round_index] = local_actor_map
	_events_by_branch_round_actor[branch_id] = rounds
	_local_search_by_branch_round_actor[branch_id] = local_search_rounds


static func _event_from_row(row: Array) -> Dictionary:
	if row.size() != EVENT_FIELD_COUNT:
		return {}
	return {
		"round_index": int(row[0]),
		"runtime_index": int(row[1]),
		"call_site_rva": int(row[2]),
		"value": int(row[3]),
	}
