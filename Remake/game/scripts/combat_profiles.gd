class_name CombatProfiles
extends RefCounted

const SCHEMA_VERSION := 3
const CATALOG_PATH := "res://data/combat_profiles.json"
const REQUIRED_ALERT_KEYS := [
	"ally_death_radius",
	"attack_radius",
	"attack_extended_radius",
]
const REQUIRED_WEAPON_SOURCE_FIELDS := [
	"damage",
	"burst_count",
	"ammo_item_id",
	"ammo_per_attack",
	"hit_frame_mode",
	"alert_radius",
	"magazine_capacity",
	"starting_reserve_ammo",
	"reload_seconds",
	"recovery_seconds",
]
const VALID_SOURCE_STATUSES := {
	"recovered": true,
	"recovered_with_unresolved_override": true,
	"unresolved_remake_default": true,
}
const EXPECTED_AMMO_ITEM_IDS := {
	1: 36,
	2: 37,
	3: 38,
	4: 39,
	5: 40,
	6: 41,
	7: 42,
	8: 43,
	9: 44,
	10: 45,
	11: 99,
}
const FINITE_AMMO_ATTACK_TYPES := {
	1: true,
	2: true,
	3: true,
	6: true,
	7: true,
	9: true,
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
	var schema_version_value: Variant = catalog.get("schema_version")
	if (
		not _is_integer_number(schema_version_value)
		or int(schema_version_value) != SCHEMA_VERSION
	):
		return false
	var catalog_source_status: Variant = catalog.get("source_status")
	if not catalog_source_status is String or String(catalog_source_status).is_empty():
		return false

	var senses_value: Variant = catalog.get("senses")
	var alerts_value: Variant = catalog.get("alerts")
	var weapons_value: Variant = catalog.get("weapons")
	if not senses_value is Dictionary or (senses_value as Dictionary).is_empty():
		return false
	if not alerts_value is Dictionary or not _are_valid_alerts(alerts_value as Dictionary):
		return false
	if not weapons_value is Dictionary or (weapons_value as Dictionary).is_empty():
		return false

	for profile_value: Variant in (senses_value as Dictionary).values():
		if not profile_value is Dictionary or not _is_valid_sense(profile_value as Dictionary):
			return false

	var attack_types: Dictionary = {}
	for action_key_value: Variant in (weapons_value as Dictionary):
		if not action_key_value is String or String(action_key_value).is_empty():
			return false
		var profile_value: Variant = (weapons_value as Dictionary)[action_key_value]
		if not profile_value is Dictionary:
			return false
		var weapon := profile_value as Dictionary
		if not _is_valid_weapon(weapon):
			return false
		var attack_type := int(weapon["attack_type"])
		if attack_types.has(attack_type):
			return false
		attack_types[attack_type] = true

	if attack_types.size() != EXPECTED_AMMO_ITEM_IDS.size():
		return false
	for attack_type: int in range(1, 12):
		if not attack_types.has(attack_type):
			return false
	return true


static func sense_profile(profile_id: String) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	var profile_value: Variant = (catalog["senses"] as Dictionary).get(profile_id)
	if not profile_value is Dictionary:
		return {}
	return (profile_value as Dictionary).duplicate(true)


static func weapon_profile(action_key: String) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	var profile_value: Variant = (catalog["weapons"] as Dictionary).get(action_key)
	if not profile_value is Dictionary:
		return {}
	return _weapon_profile_result(action_key, profile_value as Dictionary)


static func weapon_profile_for_attack_type(attack_type: int) -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	var weapons := catalog["weapons"] as Dictionary
	for action_key_value: Variant in weapons:
		var profile_value: Variant = weapons[action_key_value]
		if not profile_value is Dictionary:
			continue
		var profile := profile_value as Dictionary
		if int(profile.get("attack_type", 0)) == attack_type:
			return _weapon_profile_result(String(action_key_value), profile)
	return {}


static func alerts() -> Dictionary:
	var catalog := load_catalog()
	if catalog.is_empty():
		return {}
	return (catalog["alerts"] as Dictionary).duplicate(true)


static func alert_profile(alert_id: String) -> Dictionary:
	var key := _alert_radius_key(alert_id)
	var alert_values := alerts()
	if not alert_values.has(key):
		return {}
	return {
		"alert_key": key.trim_suffix("_radius"),
		"radius": float(alert_values[key]),
	}


static func alert_radius(alert_id: String) -> float:
	var profile := alert_profile(alert_id)
	return float(profile.get("radius", 0.0))


static func _is_valid_sense(sense: Dictionary) -> bool:
	if (
		not _is_positive_number(sense.get("horizontal_radius"))
		or not _is_positive_number(sense.get("vertical_radius"))
		or not _is_number(sense.get("near_band_ratio"))
		or float(sense["near_band_ratio"]) <= 0.0
		or float(sense["near_band_ratio"]) > 1.0
		or not sense.get("omnidirectional") is bool
		or not sense.get("requires_line_of_sight") is bool
		or not sense.get("crawling_hidden_in_far_band") is bool
	):
		return false

	if sense.has("dbl_id") and (
		not _is_integer_number(sense["dbl_id"]) or int(sense["dbl_id"]) <= 0
	):
		return false
	if sense.has("scan_step_degrees") and not _is_positive_number(sense["scan_step_degrees"]):
		return false
	if sense.has("original_direction_centers_degrees"):
		if not _is_numeric_array_of_size(sense["original_direction_centers_degrees"], 8):
			return false
	if sense.has("original_direction_half_angles_degrees"):
		if not _is_numeric_array_of_size(sense["original_direction_half_angles_degrees"], 8):
			return false
	return true


static func _are_valid_alerts(alert_values: Dictionary) -> bool:
	for key: String in REQUIRED_ALERT_KEYS:
		if not alert_values.has(key) or not _is_positive_number(alert_values[key]):
			return false
	return float(alert_values["attack_extended_radius"]) >= float(alert_values["attack_radius"])


static func _is_valid_weapon(weapon: Dictionary) -> bool:
	var attack_type_value: Variant = weapon.get("attack_type")
	var animation_action_value: Variant = weapon.get("animation_action")
	var damage_value: Variant = weapon.get("damage")
	var burst_count_value: Variant = weapon.get("burst_count")
	var ammo_item_id_value: Variant = weapon.get("ammo_item_id")
	var ammo_per_attack_value: Variant = weapon.get("ammo_per_attack")
	var alert_radius_value: Variant = weapon.get("alert_radius")
	var magazine_capacity_value: Variant = weapon.get("magazine_capacity")
	var starting_reserve_ammo_value: Variant = weapon.get("starting_reserve_ammo")
	var reload_seconds_value: Variant = weapon.get("reload_seconds")
	var recovery_seconds_value: Variant = weapon.get("recovery_seconds")
	if (
		not _is_integer_number(attack_type_value)
		or int(attack_type_value) < 1
		or int(attack_type_value) > 11
		or not _is_integer_number(animation_action_value)
		or int(animation_action_value) < 0
		or int(animation_action_value) > 19
		or not _is_positive_number(weapon.get("horizontal_range"))
		or not _is_positive_number(weapon.get("vertical_range"))
		or not weapon.get("requires_line_of_sight") is bool
		or not _is_positive_number(damage_value)
		or not _is_integer_number(burst_count_value)
		or int(burst_count_value) < 1
		or not _is_integer_number(ammo_item_id_value)
		or not _is_integer_number(ammo_per_attack_value)
		or int(ammo_per_attack_value) < 1
		or weapon.get("hit_frame_mode") != "last_frame"
		or not _is_number(alert_radius_value)
		or float(alert_radius_value) < 0.0
		or not _is_integer_number(magazine_capacity_value)
		or int(magazine_capacity_value) < 0
		or not _is_integer_number(starting_reserve_ammo_value)
		or int(starting_reserve_ammo_value) < 0
		or not _is_number(reload_seconds_value)
		or float(reload_seconds_value) < 0.0
		or not _is_positive_number(recovery_seconds_value)
	):
		return false

	var attack_type := int(attack_type_value)
	if int(ammo_item_id_value) != int(EXPECTED_AMMO_ITEM_IDS.get(attack_type, 0)):
		return false
	var uses_finite_ammo := FINITE_AMMO_ATTACK_TYPES.has(attack_type)
	if uses_finite_ammo:
		if (
			int(magazine_capacity_value) < int(ammo_per_attack_value)
			or int(starting_reserve_ammo_value) <= 0
			or float(reload_seconds_value) <= 0.0
		):
			return false
	elif (
		int(magazine_capacity_value) != 0
		or int(starting_reserve_ammo_value) != 0
		or float(reload_seconds_value) != 0.0
	):
		return false
	var source_status_value: Variant = weapon.get("source_status")
	if not source_status_value is Dictionary:
		return false
	var source_status := source_status_value as Dictionary
	for field: String in REQUIRED_WEAPON_SOURCE_FIELDS:
		var status_value: Variant = source_status.get(field)
		if not status_value is String or not VALID_SOURCE_STATUSES.has(String(status_value)):
			return false
	for field: String in [
		"magazine_capacity",
		"starting_reserve_ammo",
		"reload_seconds",
		"recovery_seconds",
	]:
		if source_status[field] != "unresolved_remake_default":
			return false
	if source_status["damage"] == "unresolved_remake_default":
		var damage_notes: Variant = weapon.get("damage_notes")
		if not damage_notes is String or String(damage_notes).is_empty():
			return false
	return true


static func _weapon_profile_result(action_key: String, profile: Dictionary) -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result["action_key"] = action_key
	return result


static func _alert_radius_key(alert_id: String) -> String:
	return alert_id if alert_id.ends_with("_radius") else "%s_radius" % alert_id


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and is_equal_approx(float(value), roundf(float(value)))


static func _is_positive_number(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0


static func _is_numeric_array_of_size(value: Variant, expected_size: int) -> bool:
	if not value is Array:
		return false
	var values := value as Array
	if values.size() != expected_size:
		return false
	for item: Variant in values:
		if not _is_number(item):
			return false
	return true
