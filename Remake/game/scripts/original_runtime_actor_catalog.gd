class_name OriginalRuntimeActorCatalog
extends RefCounted

const CATALOG_PATH := "res://data/original_runtime_actor_catalog.json"

static var _catalog_cache: Dictionary = {}


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
	var summary := catalog.get("summary", {}) as Dictionary
	if (
		int(catalog.get("schema_version", 0)) != 1
		or str(catalog.get("catalog_id", ""))
			!= "original-runtime-actor-catalog-v1"
		or int(summary.get("level_count", 0)) != 12
		or int(summary.get("resolved_actor_count", 0)) != 772
	):
		return {}
	_catalog_cache = catalog
	return _catalog_cache


static func actor_for_scene(level_id: String, scene_index: int) -> Dictionary:
	var catalog := load_catalog()
	var levels := catalog.get("levels", {}) as Dictionary
	var level: Variant = levels.get(level_id)
	if not level is Dictionary:
		return {}
	var actors := (level as Dictionary).get("actors", {}) as Dictionary
	var actor: Variant = actors.get(str(scene_index))
	return (actor as Dictionary).duplicate(true) if actor is Dictionary else {}


static func runtime_faction_id(
	level_id: String,
	scene_index: int,
	authored_faction_id: int,
) -> int:
	var actor := actor_for_scene(level_id, scene_index)
	return (
		int(actor.get("runtime_faction_id", authored_faction_id))
		if not actor.is_empty()
		else authored_faction_id
	)


static func runtime_type(level_id: String, scene_index: int) -> int:
	return int(actor_for_scene(level_id, scene_index).get("runtime_type", 0))
