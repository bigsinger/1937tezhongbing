extends RefCounted

const FALLBACK_MAP_PATH := "res://data/legacy_media_map.json"
const GENERATED_CATALOG_NAME := "legacy-media-catalog.json"

var converted_root := ""
var fallback_map: Dictionary = {}
var generated_catalog: Dictionary = {}
var cues_by_index: Dictionary = {}
var cues_by_event: Dictionary = {}


func configure(root_path: String = "") -> bool:
	converted_root = root_path.strip_edges()
	if converted_root.is_empty():
		converted_root = ProjectSettings.globalize_path("res://../LocalAssets/converted")
	converted_root = converted_root.simplify_path()
	fallback_map = _load_json(FALLBACK_MAP_PATH)
	generated_catalog = _load_json(converted_root.path_join(GENERATED_CATALOG_NAME))
	if not _valid_base_catalog(fallback_map):
		fallback_map = {}
	if not generated_catalog.is_empty() and not _valid_generated_catalog(generated_catalog):
		generated_catalog = {}
	_rebuild_audio_indexes()
	return not fallback_map.is_empty()


func briefing_metadata(level_id: String) -> Dictionary:
	return _find_level_entry("briefings", level_id)


func briefing_path(level_id: String) -> String:
	return _available_entry_path(briefing_metadata(level_id))


func objective_map_metadata(level_id: String) -> Dictionary:
	return _find_level_entry("objective_maps", level_id)


func objective_map_path(level_id: String) -> String:
	return _available_entry_path(objective_map_metadata(level_id))


func ending_metadata(target_width: int) -> Dictionary:
	var entries: Array = _merged_entries("ending_images")
	var best: Dictionary = {}
	var best_distance := 2147483647
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var width := int(entry.get("width", 0))
		if width <= 0:
			continue
		var distance: int = absi(width - target_width)
		if distance < best_distance:
			best = entry.duplicate(true)
			best_distance = distance
	return best


func ending_path(target_width: int) -> String:
	return _available_entry_path(ending_metadata(target_width))


func movie_metadata(movie_id: String) -> Dictionary:
	for value: Variant in _merged_entries("movies"):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == movie_id:
			return (value as Dictionary).duplicate(true)
	return {}


func movie_path(movie_id: String) -> String:
	return _available_entry_path(movie_metadata(movie_id))


func sound_indices(event_key: String, actor_key: String = "") -> Array[int]:
	var result: Array[int] = []
	var event_value: Variant = cues_by_event.get(event_key, {})
	if event_value is Dictionary:
		var actors := event_value as Dictionary
		if not actor_key.is_empty() and actors.has(actor_key):
			_append_unique_ints(result, actors[actor_key])
		elif actors.has("default"):
			_append_unique_ints(result, actors["default"])
		elif actor_key.is_empty():
			var actor_names: Array = actors.keys()
			actor_names.sort()
			for actor: Variant in actor_names:
				_append_unique_ints(result, actors[actor])
	if not result.is_empty():
		return result

	var audio_events: Variant = fallback_map.get("audio_events", {})
	if not audio_events is Dictionary:
		return result
	var fallback_event: Variant = (audio_events as Dictionary).get(event_key, {})
	if not fallback_event is Dictionary:
		return result
	var fallback_actors := fallback_event as Dictionary
	if not actor_key.is_empty() and fallback_actors.has(actor_key):
		_append_unique_ints(result, fallback_actors[actor_key])
	elif fallback_actors.has("default"):
		_append_unique_ints(result, fallback_actors["default"])
	elif actor_key.is_empty():
		var actor_names: Array = fallback_actors.keys()
		actor_names.sort()
		for actor: Variant in actor_names:
			_append_unique_ints(result, fallback_actors[actor])
	return result


func select_sound_index(event_key: String, actor_key: String = "", variant_seed: int = 0) -> int:
	var indices := sound_indices(event_key, actor_key)
	if indices.is_empty():
		return -1
	return indices[posmod(variant_seed, indices.size())]


func sound_metadata(gfl_index: int) -> Dictionary:
	var value: Variant = cues_by_index.get(gfl_index, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func sound_path(gfl_index: int) -> String:
	var metadata := sound_metadata(gfl_index)
	var relative_path := str(metadata.get("relative_path", "audio/%04d.wav" % gfl_index))
	return _available_relative_path(relative_path)


func sound_caption(gfl_index: int) -> String:
	return str(sound_metadata(gfl_index).get("caption", ""))


func has_generated_catalog() -> bool:
	return not generated_catalog.is_empty()


func available_summary() -> Dictionary:
	var briefing_count := 0
	for value: Variant in _merged_entries("briefings"):
		if value is Dictionary and not _available_entry_path(value as Dictionary).is_empty():
			briefing_count += 1
	var sound_count := 0
	for index: Variant in cues_by_index:
		if not sound_path(int(index)).is_empty():
			sound_count += 1
	var movie_count := 0
	for value: Variant in _merged_entries("movies"):
		if value is Dictionary and not _available_entry_path(value as Dictionary).is_empty():
			movie_count += 1
	return {
		"generated_catalog": has_generated_catalog(),
		"briefings": briefing_count,
		"audio_cues": sound_count,
		"movies": movie_count,
	}


static func validate_dialogue_lines(lines: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for index: int in range(lines.size()):
		var value: Variant = lines[index]
		if not value is Dictionary:
			errors.append("line %d is not a dictionary" % index)
			continue
		var line := value as Dictionary
		if str(line.get("text", "")).strip_edges().is_empty():
			errors.append("line %d has no text" % index)
		if line.has("audio_index") and int(line["audio_index"]) < 0:
			errors.append("line %d has an invalid audio_index" % index)
		if line.has("minimum_seconds") and float(line["minimum_seconds"]) < 0.0:
			errors.append("line %d has a negative minimum_seconds" % index)
	return errors


func _find_level_entry(collection_name: String, level_id: String) -> Dictionary:
	for value: Variant in _merged_entries(collection_name):
		if value is Dictionary and str((value as Dictionary).get("level_id", "")) == level_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _merged_entries(collection_name: String) -> Array:
	var generated: Variant = generated_catalog.get(collection_name, [])
	if generated is Array and not (generated as Array).is_empty():
		return generated as Array
	var fallback: Variant = fallback_map.get(collection_name, [])
	return fallback as Array if fallback is Array else []


func _available_entry_path(entry: Dictionary) -> String:
	return _available_relative_path(str(entry.get("relative_path", entry.get("transcoded_relative_path", ""))))


func _available_relative_path(relative_path: String) -> String:
	var path := _contained_path(relative_path)
	return path if not path.is_empty() and FileAccess.file_exists(path) else ""


func _contained_path(relative_path: String) -> String:
	if relative_path.is_empty() or relative_path.is_absolute_path():
		return ""
	var normalized := relative_path.replace("\\", "/")
	if normalized.split("/").has(".."):
		return ""
	var root := converted_root.replace("\\", "/").trim_suffix("/")
	var candidate := root.path_join(normalized).simplify_path().replace("\\", "/")
	if not candidate.to_lower().begins_with((root + "/").to_lower()):
		return ""
	return candidate


func _rebuild_audio_indexes() -> void:
	cues_by_index.clear()
	cues_by_event.clear()
	var values: Variant = generated_catalog.get("audio_cues", [])
	if values is Array:
		for value: Variant in values:
			if not value is Dictionary:
				continue
			var cue := value as Dictionary
			var index := int(cue.get("gfl_index", -1))
			var event_key := str(cue.get("event_key", ""))
			var actor_key := str(cue.get("actor_key", ""))
			if index < 0 or event_key.is_empty():
				continue
			cues_by_index[index] = cue.duplicate(true)
			var event_actors: Dictionary = cues_by_event.get(event_key, {})
			var actor_bucket := actor_key if not actor_key.is_empty() else "default"
			var indices: Array = event_actors.get(actor_bucket, [])
			indices.append(index)
			event_actors[actor_bucket] = indices
			cues_by_event[event_key] = event_actors


func _append_unique_ints(target: Array[int], value: Variant) -> void:
	if not value is Array:
		return
	for raw: Variant in value as Array:
		var number := int(raw)
		if number >= 0 and not target.has(number):
			target.append(number)


func _valid_base_catalog(value: Dictionary) -> bool:
	return int(value.get("schema_version", 0)) == 1 and value.get("briefings", null) is Array


func _valid_generated_catalog(value: Dictionary) -> bool:
	return (
		int(value.get("schema_version", 0)) == 1
		and value.get("briefings", null) is Array
		and value.get("audio_cues", null) is Array
	)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)
