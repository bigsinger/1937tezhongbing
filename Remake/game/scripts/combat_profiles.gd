class_name CombatProfiles
extends RefCounted

const SCHEMA_VERSION := 2
const CATALOG_PATH := "res://data/combat_profiles.json"
static var catalog_cache: Dictionary = {}


static func load_catalog(resource_path: String = CATALOG_PATH) -> Dictionary:
	if resource_path == CATALOG_PATH and not catalog_cache.is_empty():
		return catalog_cache
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var catalog := json.data as Dictionary
	if not is_valid_catalog(catalog):
		return {}
	if resource_path == CATALOG_PATH:
		catalog_cache = catalog
	return catalog


static func is_valid_catalog(catalog: Dictionary) -> bool:
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var senses: Variant = catalog.get("senses")
	var weapons: Variant = catalog.get("weapons")
	if not senses is Dictionary or (senses as Dictionary).is_empty():
		return false
	if not weapons is Dictionary or (weapons as Dictionary).is_empty():
		return false
	for profile: Variant in (senses as Dictionary).values():
		if not profile is Dictionary:
			return false
		var sense := profile as Dictionary
		if (
			float(sense.get("horizontal_radius", 0.0)) <= 0.0
			or float(sense.get("vertical_radius", 0.0)) <= 0.0
			or float(sense.get("near_band_ratio", 0.0)) <= 0.0
			or float(sense.get("near_band_ratio", 0.0)) > 1.0
			or not sense.get("omnidirectional") is bool
			or not sense.get("requires_line_of_sight") is bool
			or not sense.get("crawling_hidden_in_far_band") is bool
		):
			return false
	for profile: Variant in (weapons as Dictionary).values():
		if not profile is Dictionary:
			return false
		var weapon := profile as Dictionary
		if (
			int(weapon.get("attack_type", 0)) < 1
			or int(weapon.get("attack_type", 0)) > 11
			or float(weapon.get("horizontal_range", 0.0)) <= 0.0
			or float(weapon.get("vertical_range", 0.0)) <= 0.0
			or not weapon.get("requires_line_of_sight") is bool
		):
			return false
	return true


static func sense_profile(profile_id: String) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	return (catalog["senses"] as Dictionary).get(profile_id, {}) as Dictionary


static func weapon_profile(action_key: String) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	return (catalog["weapons"] as Dictionary).get(action_key, {}) as Dictionary


static func weapon_profile_for_attack_type(attack_type: int) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	for profile_value: Variant in (catalog["weapons"] as Dictionary).values():
		var profile := profile_value as Dictionary
		if int(profile.get("attack_type", 0)) == attack_type:
			return profile
	return {}
