class_name OriginalInitialWeaponInventory
extends RefCounted

const CATALOG_PATH := "res://data/original_initial_weapon_inventory.json"
const SUPPORTED_LEVEL_IDS := [
	"m000", "m001", "m002", "m003", "m004", "m005",
	"m006", "m007", "m008", "m009", "m010", "m011",
]

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
	if not validate_catalog(catalog):
		return {}
	_catalog_cache = catalog
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
	var entry_count := 0
	for level_id: String in SUPPORTED_LEVEL_IDS:
		var level: Variant = (levels as Dictionary).get(level_id)
		if not level is Dictionary:
			return false
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
				entry_count += 1
			if expected_index == 0:
				return false
			player_count += 1
	for attack_type: int in range(1, 12):
		if not (attack_items as Dictionary).has(str(attack_type)):
			return false
	var summary := catalog.get("summary", {}) as Dictionary
	return (
		player_count == 27
		and entry_count == 83
		and int(summary.get("level_count", 0)) == 12
		and int(summary.get("player_count", 0)) == player_count
		and int(summary.get("inventory_entry_count", 0)) == entry_count
	)


static func loadout_for_scene(level_id: String, scene_index: int) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty() or scene_index < 0:
		return {}
	var levels := catalog.get("levels", {}) as Dictionary
	var level: Variant = levels.get(level_id)
	if not level is Dictionary:
		return {}
	for player_value: Variant in (level as Dictionary).get("players", []):
		if (
			player_value is Dictionary
			and int((player_value as Dictionary).get("scene_index", -1)) == scene_index
		):
			return (player_value as Dictionary).duplicate(true)
	return {}


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
