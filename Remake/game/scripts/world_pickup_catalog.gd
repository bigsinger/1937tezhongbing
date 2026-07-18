class_name WorldPickupCatalog
extends RefCounted

const SCHEMA_VERSION := 1
const CATALOG_PATH := "res://data/world_pickups.json"
const EXPECTED_ENTITY_IDS := [982, 983, 984, 986, 987, 988, 990, 993, 998, 999, 1003]
const PICKUP_BEHAVIOR := "field_pickup"
const EXPLOSIVE_BEHAVIOR := "explosive_prop"
const VALID_GRANT_KINDS := {
	"weapon": true,
	"ammunition": true,
	"active_weapon_ammunition": true,
	"deployable": true,
	"mission_item": true,
	"healing": true,
}
const DEFAULT_STATUS := "unresolved_remake_default"

static var _catalog_cache: Dictionary = {}


static func load_catalog(resource_path: String = CATALOG_PATH) -> Dictionary:
	if resource_path == CATALOG_PATH and not _catalog_cache.is_empty():
		return _catalog_cache
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
		_catalog_cache = catalog
	return catalog


static func is_valid_catalog(catalog: Dictionary) -> bool:
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	if String(catalog.get("source_status", "")).is_empty():
		return false
	var entities_value: Variant = catalog.get("entities")
	if not entities_value is Dictionary:
		return false
	var entities := entities_value as Dictionary
	if int(catalog.get("entity_count", -1)) != EXPECTED_ENTITY_IDS.size():
		return false
	if entities.size() != EXPECTED_ENTITY_IDS.size():
		return false
	for database_entry_id: int in EXPECTED_ENTITY_IDS:
		var profile_value: Variant = entities.get(str(database_entry_id))
		if not profile_value is Dictionary:
			return false
		if not _is_valid_entity_profile(profile_value as Dictionary, database_entry_id):
			return false
	var deployables_value: Variant = catalog.get("deployables")
	if not deployables_value is Dictionary:
		return false
	var deployables := deployables_value as Dictionary
	if deployables.size() != 1 or not deployables.get("land_mine") is Dictionary:
		return false
	return _is_valid_land_mine_profile(deployables["land_mine"] as Dictionary)


static func profile_for_database_entry_id(
	database_entry_id: int,
	resource_path: String = CATALOG_PATH,
) -> Dictionary:
	var catalog := load_catalog(resource_path)
	if catalog.is_empty():
		return {}
	var profile_value: Variant = (catalog["entities"] as Dictionary).get(str(database_entry_id))
	if not profile_value is Dictionary:
		return {}
	return (profile_value as Dictionary).duplicate(true)


static func deployable_profile(
	deployable_key: String,
	resource_path: String = CATALOG_PATH,
) -> Dictionary:
	var catalog := load_catalog(resource_path)
	if catalog.is_empty():
		return {}
	var profile_value: Variant = (catalog["deployables"] as Dictionary).get(deployable_key)
	if not profile_value is Dictionary:
		return {}
	return (profile_value as Dictionary).duplicate(true)


static func supports_database_entry_id(database_entry_id: int) -> bool:
	return database_entry_id in EXPECTED_ENTITY_IDS


static func is_field_pickup(database_entry_id: int) -> bool:
	return String(profile_for_database_entry_id(database_entry_id).get("behavior", "")) == PICKUP_BEHAVIOR


static func is_explosive_prop(database_entry_id: int) -> bool:
	return String(profile_for_database_entry_id(database_entry_id).get("behavior", "")) == EXPLOSIVE_BEHAVIOR


static func _is_valid_entity_profile(profile: Dictionary, expected_id: int) -> bool:
	if int(profile.get("database_entry_id", 0)) != expected_id:
		return false
	if (
		String(profile.get("key", "")).is_empty()
		or String(profile.get("original_display_name", "")).is_empty()
	):
		return false
	var behavior := String(profile.get("behavior", ""))
	if behavior not in [PICKUP_BEHAVIOR, EXPLOSIVE_BEHAVIOR]:
		return false
	var source_value: Variant = profile.get("source_status")
	if not source_value is Dictionary:
		return false
	var source := source_value as Dictionary
	if String(source.get("identity", "")).is_empty() or String(source.get("behavior", "")).is_empty():
		return false
	if behavior == PICKUP_BEHAVIOR:
		return _is_valid_pickup_profile(profile, source)
	return _is_valid_explosive_profile(profile, source)


static func _is_valid_pickup_profile(profile: Dictionary, source: Dictionary) -> bool:
	if float(profile.get("interaction_radius", 0.0)) <= 0.0:
		return false
	if String(source.get("interaction_radius", "")) != DEFAULT_STATUS:
		return false
	var grant_value: Variant = profile.get("grant")
	if not grant_value is Dictionary:
		return false
	var grant := grant_value as Dictionary
	var grant_kind := String(grant.get("kind", ""))
	if not VALID_GRANT_KINDS.has(grant_kind):
		return false
	if int(grant.get("quantity", 0)) <= 0:
		return false
	if String(source.get("grant_kind", "")).is_empty():
		return false
	if String(source.get("grant_quantity", "")) != DEFAULT_STATUS:
		return false
	match grant_kind:
		"weapon":
			return not String(grant.get("action_key", "")).is_empty()
		"ammunition":
			return (
				int(grant.get("item_id", 0)) > 0
				and not String(grant.get("action_key", "")).is_empty()
			)
		"active_weapon_ammunition":
			return true
		"deployable":
			return (
				int(grant.get("item_id", 0)) > 0
				and not String(grant.get("deployable_key", "")).is_empty()
			)
		"mission_item":
			return not String(grant.get("item_key", "")).is_empty()
		"healing":
			return (
				int(grant.get("healing_hit_points", 0)) > 0
				and String(source.get("healing_hit_points", "")) == DEFAULT_STATUS
			)
	return false


static func _is_valid_explosive_profile(profile: Dictionary, source: Dictionary) -> bool:
	var positive_fields := [
		"hit_points",
		"blast_damage",
		"blast_horizontal_radius",
		"blast_vertical_radius",
		"destroyed_visual_seconds",
	]
	for field: String in positive_fields:
		if float(profile.get(field, 0.0)) <= 0.0:
			return false
		if String(source.get(field, "")) != DEFAULT_STATUS:
			return false
	return true


static func _is_valid_land_mine_profile(profile: Dictionary) -> bool:
	if String(profile.get("key", "")) != "land_mine":
		return false
	if int(profile.get("source_pickup_database_entry_id", 0)) != 984:
		return false
	if int(profile.get("ammo_item_id", 0)) != 43:
		return false
	var source_value: Variant = profile.get("source_status")
	if not source_value is Dictionary:
		return false
	var source := source_value as Dictionary
	for identity_field: String in ["identity", "ammo_item_id"]:
		if String(source.get(identity_field, "")).is_empty():
			return false
	var positive_fields := [
		"arm_delay_seconds",
		"trigger_horizontal_radius",
		"trigger_vertical_radius",
		"detonation_delay_seconds",
		"blast_damage",
		"blast_horizontal_radius",
		"blast_vertical_radius",
		"resolved_visual_seconds",
	]
	for field: String in positive_fields:
		if float(profile.get(field, 0.0)) <= 0.0:
			return false
		if String(source.get(field, "")) != DEFAULT_STATUS:
			return false
	return true
