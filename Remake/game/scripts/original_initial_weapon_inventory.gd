class_name OriginalInitialWeaponInventory
extends RefCounted

const CATALOG_PATH := "res://data/original_initial_weapon_inventory.json"
const SUPPORTED_LEVEL_IDS := [
	"m000", "m001", "m002", "m003", "m004", "m005",
	"m006", "m007", "m008", "m009", "m010", "m011",
]

static var _catalog_cache: Dictionary = {}
static var _actor_scene_cache: Dictionary = {}
static var _player_scene_cache: Dictionary = {}


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
		or str(catalog.get("catalog_id", "")) != "original-initial-weapon-inventory-v1"
	):
		return false
	var levels: Variant = catalog.get("levels")
	var quantity_modes: Variant = catalog.get("quantity_modes")
	var attack_items: Variant = catalog.get("attack_type_to_item_id")
	if (
		not levels is Dictionary
		or not quantity_modes is Dictionary
		or not attack_items is Dictionary
	):
		return false
	var player_count := 0
	var player_entry_count := 0
	var actor_count := 0
	var actor_entry_count := 0
	var empty_actor_count := 0
	for level_id: String in SUPPORTED_LEVEL_IDS:
		var level: Variant = (levels as Dictionary).get(level_id)
		if not level is Dictionary:
			return false
		var actor_scenes: Dictionary = {}
		for actor_value: Variant in (level as Dictionary).get("actors", []):
			if not actor_value is Dictionary:
				return false
			var actor := actor_value as Dictionary
			var actor_scene_index := int(actor.get("scene_index", -1))
			if (
				actor_scene_index < 0
				or actor_scenes.has(actor_scene_index)
				or str(actor.get("display_name", "")).is_empty()
			):
				return false
			actor_scenes[actor_scene_index] = actor
			var actor_expected_index := 0
			for item_value: Variant in actor.get("items", []):
				if not item_value is Dictionary:
					return false
				var item := item_value as Dictionary
				var item_id := int(item.get("item_id", 0))
				if (
					int(item.get("inventory_index", -1)) != actor_expected_index
					or int(item.get("quantity", -1)) < 0
					or not (quantity_modes as Dictionary).has(str(item_id))
					or int(item.get("quantity_mode", -1))
						!= int((quantity_modes as Dictionary)[str(item_id)])
				):
					return false
				actor_expected_index += 1
				actor_entry_count += 1
			if actor_expected_index == 0:
				empty_actor_count += 1
			actor_count += 1
		var seen_scenes: Dictionary = {}
		for player_value: Variant in (level as Dictionary).get("players", []):
			if not player_value is Dictionary:
				return false
			var player := player_value as Dictionary
			var scene_index := int(player.get("scene_index", -1))
			if (
				scene_index < 0
				or seen_scenes.has(scene_index)
				or str(player.get("display_name", "")).is_empty()
				or not actor_scenes.has(scene_index)
				or not bool(
					(actor_scenes[scene_index] as Dictionary).get(
						"is_player_at_capture",
						false,
					)
				)
			):
				return false
			seen_scenes[scene_index] = true
			var expected_index := 0
			for item_value: Variant in player.get("items", []):
				if not item_value is Dictionary:
					return false
				var item := item_value as Dictionary
				var item_id := int(item.get("item_id", 0))
				if (
					int(item.get("inventory_index", -1)) != expected_index
					or int(item.get("quantity", -1)) < 0
					or not (quantity_modes as Dictionary).has(str(item_id))
					or int(item.get("quantity_mode", -1))
						!= int((quantity_modes as Dictionary)[str(item_id)])
				):
					return false
				expected_index += 1
				player_entry_count += 1
			if expected_index == 0:
				return false
			player_count += 1
	for attack_type: int in range(1, 12):
		if not (attack_items as Dictionary).has(str(attack_type)):
			return false
	var summary := catalog.get("summary", {}) as Dictionary
	return (
		actor_count == 660
		and actor_entry_count == 761
		and empty_actor_count == 67
		and player_count == 27
		and player_entry_count == 83
		and int(summary.get("level_count", 0)) == 12
		and int(summary.get("exact_actor_count", 0)) == actor_count
		and int(summary.get("inventory_entry_count", 0)) == actor_entry_count
		and int(summary.get("empty_actor_count", 0)) == empty_actor_count
		and int(summary.get("player_count", 0)) == player_count
		and int(summary.get("player_inventory_entry_count", 0))
			== player_entry_count
	)


static func loadout_for_scene(level_id: String, scene_index: int) -> Dictionary:
	if load_catalog().is_empty() or scene_index < 0:
		return {}
	var level_cache: Variant = _player_scene_cache.get(level_id)
	if not level_cache is Dictionary:
		return {}
	var value: Variant = (level_cache as Dictionary).get(scene_index)
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func loadout_for_any_actor_scene(
	level_id: String,
	scene_index: int,
) -> Dictionary:
	if load_catalog().is_empty() or scene_index < 0:
		return {}
	var level_cache: Variant = _actor_scene_cache.get(level_id)
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
	# Scene identity is authoritative. The name fallback exists only for
	# synthetic/no-asset test scenes and refuses ambiguity.
	var catalog := load_catalog()
	var levels := catalog.get("levels", {}) as Dictionary
	var level: Variant = levels.get(level_id)
	if not level is Dictionary or display_name.is_empty():
		return {}
	var result: Dictionary = {}
	for player_value: Variant in (level as Dictionary).get("players", []):
		if (
			player_value is Dictionary
			and str((player_value as Dictionary).get("display_name", ""))
				== display_name
		):
			if not result.is_empty():
				return {}
			result = (player_value as Dictionary).duplicate(true)
	return result


static func loadout_for_any_actor(
	level_id: String,
	scene_index: int,
	display_name: String,
) -> Dictionary:
	var exact := loadout_for_any_actor_scene(level_id, scene_index)
	if not exact.is_empty():
		return exact
	var catalog := load_catalog()
	var levels := catalog.get("levels", {}) as Dictionary
	var level: Variant = levels.get(level_id)
	if not level is Dictionary or display_name.is_empty():
		return {}
	var result: Dictionary = {}
	for actor_value: Variant in (level as Dictionary).get("actors", []):
		if (
			actor_value is Dictionary
			and str((actor_value as Dictionary).get("display_name", ""))
				== display_name
		):
			if not result.is_empty():
				return {}
			result = (actor_value as Dictionary).duplicate(true)
	return result


static func item_id_for_attack_type(attack_type: int) -> int:
	var catalog := load_catalog()
	var mapping := catalog.get("attack_type_to_item_id", {}) as Dictionary
	return int(mapping.get(str(attack_type), 0))


static func attack_type_for_item_id(item_id: int) -> int:
	var catalog := load_catalog()
	var mapping := catalog.get("attack_type_to_item_id", {}) as Dictionary
	for attack_key: Variant in mapping.keys():
		if int(mapping[attack_key]) == item_id:
			return int(str(attack_key))
	return 0


static func quantity_mode_for_item_id(item_id: int) -> int:
	var catalog := load_catalog()
	var mapping := catalog.get("quantity_modes", {}) as Dictionary
	return int(mapping.get(str(item_id), -1))


static func _build_scene_cache() -> void:
	_actor_scene_cache.clear()
	_player_scene_cache.clear()
	var levels := _catalog_cache.get("levels", {}) as Dictionary
	for level_id: String in SUPPORTED_LEVEL_IDS:
		var actor_cache: Dictionary = {}
		var player_cache: Dictionary = {}
		var level_value: Variant = levels.get(level_id)
		if level_value is Dictionary:
			for actor_value: Variant in (level_value as Dictionary).get(
				"actors",
				[],
			):
				if actor_value is Dictionary:
					var actor := actor_value as Dictionary
					actor_cache[int(actor.get("scene_index", -1))] = actor
			for player_value: Variant in (level_value as Dictionary).get(
				"players",
				[],
			):
				if player_value is Dictionary:
					var player := player_value as Dictionary
					player_cache[int(player.get("scene_index", -1))] = player
		_actor_scene_cache[level_id] = actor_cache
		_player_scene_cache[level_id] = player_cache
