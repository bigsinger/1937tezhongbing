class_name OriginalInitialItemInventory
extends RefCounted

const CATALOG_PATH := "res://data/original_initial_item_inventory.json"
const SUPPORTED_LEVEL_IDS := [
	"m000", "m001", "m002", "m003", "m004", "m005",
	"m006", "m007", "m008", "m009", "m010", "m011",
]

static var _catalog_cache: Dictionary = {}
static var _scene_cache: Dictionary = {}


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
	if not validate_catalog(catalog):
		return {}
	_catalog_cache = catalog
	_build_scene_cache()
	return _catalog_cache


static func validate_catalog(catalog: Dictionary) -> bool:
	if (
		int(catalog.get("schema_version", 0)) != 1
		or str(catalog.get("catalog_id", ""))
			!= "original-initial-item-inventory-v1"
	):
		return false
	var levels_value: Variant = catalog.get("levels")
	var item_catalog_value: Variant = catalog.get("item_catalog")
	var modes_value: Variant = catalog.get("allowed_quantity_modes")
	if (
		not levels_value is Dictionary
		or not item_catalog_value is Dictionary
		or not modes_value is Dictionary
	):
		return false
	var actor_count := 0
	var entry_count := 0
	var empty_actor_count := 0
	var player_count := 0
	var player_entry_count := 0
	var empty_player_count := 0
	var seen_scene_keys: Dictionary = {}
	for level_id: String in SUPPORTED_LEVEL_IDS:
		var level_value: Variant = (levels_value as Dictionary).get(level_id)
		if not level_value is Dictionary:
			return false
		for actor_value: Variant in (level_value as Dictionary).get("actors", []):
			if not actor_value is Dictionary:
				return false
			var actor := actor_value as Dictionary
			var scene_index := int(actor.get("scene_index", -1))
			var scene_key := "%s/%d" % [level_id, scene_index]
			if (
				scene_index < 0
				or seen_scene_keys.has(scene_key)
				or str(actor.get("display_name", "")).is_empty()
			):
				return false
			seen_scene_keys[scene_key] = true
			var expected_index := 0
			var seen_items: Dictionary = {}
			for item_value: Variant in actor.get("items", []):
				if not item_value is Dictionary:
					return false
				var item := item_value as Dictionary
				var item_id := int(item.get("item_id", 0))
				var mode := int(item.get("quantity_mode", -1))
				var allowed_value: Variant = (
					modes_value as Dictionary
				).get(str(item_id))
				var mode_is_allowed := false
				if allowed_value is Array:
					for allowed_mode_value: Variant in allowed_value as Array:
						if int(allowed_mode_value) == mode:
							mode_is_allowed = true
							break
				if (
					int(item.get("inventory_index", -1)) != expected_index
					or int(item.get("quantity", -1)) < 0
					or seen_items.has(item_id)
					or not allowed_value is Array
					or not mode_is_allowed
					or not (item_catalog_value as Dictionary).has(str(item_id))
				):
					return false
				seen_items[item_id] = true
				expected_index += 1
				entry_count += 1
				if bool(actor.get("is_player_at_capture", false)):
					player_entry_count += 1
			if expected_index == 0:
				empty_actor_count += 1
				if bool(actor.get("is_player_at_capture", false)):
					empty_player_count += 1
			if bool(actor.get("is_player_at_capture", false)):
				player_count += 1
			actor_count += 1
	var summary := catalog.get("summary", {}) as Dictionary
	return (
		actor_count == 660
		and entry_count == 539
		and empty_actor_count == 316
		and player_count == 27
		and player_entry_count == 74
		and empty_player_count == 1
		and int(summary.get("level_count", 0)) == 12
		and int(summary.get("exact_actor_count", 0)) == actor_count
		and int(summary.get("inventory_entry_count", 0)) == entry_count
		and int(summary.get("empty_actor_count", 0)) == empty_actor_count
		and int(summary.get("player_count", 0)) == player_count
		and int(summary.get("player_inventory_entry_count", 0))
			== player_entry_count
		and int(summary.get("empty_player_count", 0)) == empty_player_count
	)


static func loadout_for_scene(level_id: String, scene_index: int) -> Dictionary:
	if load_catalog().is_empty() or scene_index < 0:
		return {}
	var level_cache: Variant = _scene_cache.get(level_id)
	if not level_cache is Dictionary:
		return {}
	var value: Variant = (level_cache as Dictionary).get(scene_index)
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func loadout_for_actor(
	level_id: String,
	scene_index: int,
	display_name: String,
) -> Dictionary:
	var exact := loadout_for_scene(level_id, scene_index)
	if not exact.is_empty():
		return exact
	# Only synthetic/no-asset test scenes may use an unambiguous name fallback.
	var catalog := load_catalog()
	var levels := catalog.get("levels", {}) as Dictionary
	var level_value: Variant = levels.get(level_id)
	if not level_value is Dictionary or display_name.is_empty():
		return {}
	var result: Dictionary = {}
	for actor_value: Variant in (level_value as Dictionary).get("actors", []):
		if (
			actor_value is Dictionary
			and str((actor_value as Dictionary).get("display_name", ""))
				== display_name
		):
			if not result.is_empty():
				return {}
			result = (actor_value as Dictionary).duplicate(true)
	return result


static func item_profile(item_id: int) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	var value: Variant = (
		catalog.get("item_catalog", {}) as Dictionary
	).get(str(item_id))
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func item_display_name(item_id: int) -> String:
	return str(item_profile(item_id).get("display_name", "Item %d" % item_id))


static func allowed_quantity_modes(item_id: int) -> Array[int]:
	var result: Array[int] = []
	var catalog := load_catalog()
	if catalog.is_empty():
		return result
	var value: Variant = (
		catalog.get("allowed_quantity_modes", {}) as Dictionary
	).get(str(item_id))
	if value is Array:
		for mode_value: Variant in value as Array:
			result.append(int(mode_value))
	return result


static func _build_scene_cache() -> void:
	_scene_cache.clear()
	var levels := _catalog_cache.get("levels", {}) as Dictionary
	for level_id: String in SUPPORTED_LEVEL_IDS:
		var level_cache: Dictionary = {}
		var level_value: Variant = levels.get(level_id)
		if level_value is Dictionary:
			for actor_value: Variant in (level_value as Dictionary).get("actors", []):
				if actor_value is Dictionary:
					var actor := actor_value as Dictionary
					level_cache[int(actor.get("scene_index", -1))] = actor
		_scene_cache[level_id] = level_cache
