class_name ProjectileProfiles
extends RefCounted

const SCHEMA_VERSION := 1
const CATALOG_PATH := "res://data/projectile_profiles.json"
const PROJECTILE_ATTACK_TYPES := {6: true, 7: true, 9: true}
const VALID_MOTIONS := {"linear": true, "arc": true}
const REQUIRED_SOURCE_FIELDS := ["delivery", "speed", "arc_height", "collision_radius"]
const VALID_SOURCE_STATUSES := {
	"recovered_world_object_path": true,
	"unresolved_remake_default": true,
}

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
	if String(catalog.get("source_status", "")).is_empty():
		return false
	var projectiles_value: Variant = catalog.get("projectiles")
	if not projectiles_value is Dictionary:
		return false
	var projectiles := projectiles_value as Dictionary
	if projectiles.size() != PROJECTILE_ATTACK_TYPES.size():
		return false
	var seen_attack_types: Dictionary = {}
	for action_key_value: Variant in projectiles:
		if not action_key_value is String or String(action_key_value).is_empty():
			return false
		var profile_value: Variant = projectiles[action_key_value]
		if not profile_value is Dictionary or not _is_valid_profile(profile_value as Dictionary):
			return false
		var attack_type := int((profile_value as Dictionary)["attack_type"])
		if seen_attack_types.has(attack_type):
			return false
		seen_attack_types[attack_type] = true
	for attack_type: int in PROJECTILE_ATTACK_TYPES:
		if not seen_attack_types.has(attack_type):
			return false
	return true


static func profile_for_attack_type(attack_type: int) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	for action_key_value: Variant in (catalog["projectiles"] as Dictionary):
		var profile := (catalog["projectiles"] as Dictionary)[action_key_value] as Dictionary
		if int(profile["attack_type"]) == attack_type:
			var result := profile.duplicate(true)
			result["action_key"] = String(action_key_value)
			return result
	return {}


static func is_projectile_attack(attack_type: int) -> bool:
	return PROJECTILE_ATTACK_TYPES.has(attack_type)


static func _is_valid_profile(profile: Dictionary) -> bool:
	var attack_type := int(profile.get("attack_type", 0))
	if not PROJECTILE_ATTACK_TYPES.has(attack_type):
		return false
	if not VALID_MOTIONS.has(String(profile.get("motion", ""))):
		return false
	if float(profile.get("speed", 0.0)) <= 0.0:
		return false
	if float(profile.get("arc_height", -1.0)) < 0.0:
		return false
	if float(profile.get("collision_radius", 0.0)) <= 0.0:
		return false
	if float(profile.get("detonation_delay_seconds", -1.0)) < 0.0:
		return false
	var horizontal_radius := float(profile.get("blast_horizontal_radius", -1.0))
	var vertical_radius := float(profile.get("blast_vertical_radius", -1.0))
	if horizontal_radius < 0.0 or vertical_radius < 0.0:
		return false
	if (horizontal_radius == 0.0) != (vertical_radius == 0.0):
		return false
	if not profile.get("friendly_fire") is bool:
		return false
	var source_value: Variant = profile.get("source_status")
	if not source_value is Dictionary:
		return false
	var source := source_value as Dictionary
	for field: String in REQUIRED_SOURCE_FIELDS:
		if not VALID_SOURCE_STATUSES.has(String(source.get(field, ""))):
			return false
	if horizontal_radius > 0.0:
		for field: String in [
			"detonation_delay_seconds",
			"blast_horizontal_radius",
			"blast_vertical_radius",
			"friendly_fire",
		]:
			if not VALID_SOURCE_STATUSES.has(String(source.get(field, ""))):
				return false
	return true
