class_name WorldPickupCatalog
extends RefCounted

const SCHEMA_VERSION := 3
const CATALOG_PATH := "res://data/world_pickups.json"
const EXPECTED_ENTITY_IDS := [982, 983, 984, 986, 987, 988, 990, 993, 998, 999, 1003]
const PICKUP_BEHAVIOR := "field_pickup"
const EXPLOSIVE_BEHAVIOR := "explosive_prop"
const ORIGINAL_INVENTORY_GRANT_KIND := "original_inventory_item"
const EXPECTED_PICKUP_GRANTS := {
	982: {"item_id": 38, "container": "weapon", "quantity_mode": 2},
	983: {"item_id": 46, "container": "backpack", "quantity_mode": 0},
	984: {"item_id": 43, "container": "weapon", "quantity_mode": 0},
	986: {"item_id": 44, "container": "weapon", "quantity_mode": 0},
	987: {"item_id": 36, "container": "weapon", "quantity_mode": 2},
	988: {"item_id": 41, "container": "weapon", "quantity_mode": 0},
	990: {"item_id": 54, "container": "backpack", "quantity_mode": 0},
	993: {"item_id": 51, "container": "backpack", "quantity_mode": 0},
	998: {"item_id": 45, "container": "weapon", "quantity_mode": 0},
	999: {"item_id": 47, "container": "backpack", "quantity_mode": 0},
}
const RECOVERED_ITEM_STATUS := "recovered_dbl_header_2"
const RECOVERED_CONTAINER_STATUS := "recovered_sub_45AE10"
const RECOVERED_QUANTITY_STATUS := "recovered_sub_453F70"
const RECOVERED_INTERACTION_STATUS := (
	"recovered_sub_456AB0_adjacent_navigation_cells"
)

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
	# The original product path for item 43 is attack type 8 -> actor 84.
	# A separate seconds-based LandMine profile was an early Remake invention
	# and must not silently return as catalog data.
	return not catalog.has("deployables")


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
	if (
		String(source.get("interaction_radius", ""))
		!= RECOVERED_INTERACTION_STATUS
	):
		return false
	var database_entry_id := int(profile.get("database_entry_id", 0))
	var expected_value: Variant = EXPECTED_PICKUP_GRANTS.get(database_entry_id)
	if not expected_value is Dictionary:
		return false
	var expected := expected_value as Dictionary
	var grant_value: Variant = profile.get("grant")
	if not grant_value is Dictionary:
		return false
	var grant := grant_value as Dictionary
	return (
		String(grant.get("kind", "")) == ORIGINAL_INVENTORY_GRANT_KIND
		and int(grant.get("item_id", 0)) == int(expected["item_id"])
		and String(grant.get("container", "")) == String(expected["container"])
		and int(grant.get("quantity", 0)) == 1
		and int(grant.get("quantity_mode", -1))
			== int(expected["quantity_mode"])
		and String(source.get("item_id", "")) == RECOVERED_ITEM_STATUS
		and String(source.get("container", "")) == RECOVERED_CONTAINER_STATUS
		and String(source.get("quantity_mode", "")) == RECOVERED_CONTAINER_STATUS
		and String(source.get("grant_quantity", ""))
			== RECOVERED_QUANTITY_STATUS
	)


static func _is_valid_explosive_profile(profile: Dictionary, source: Dictionary) -> bool:
	return (
		int(profile.get("runtime_actor_type", 0)) == 53
		and int(profile.get("initial_hit_points", 0)) == 8
		and int(profile.get("detonation_hit_points_sentinel", 0)) == 8
		and int(profile.get("resolved_action_index", -1)) == 1
		and int(profile.get("effect_dispatch_type", 0)) == 5
		and int(profile.get("explosion_actor_type", 0)) == 62
		and String(source.get("runtime_actor_type", ""))
			== RECOVERED_ITEM_STATUS
		and String(source.get("behavior", ""))
			== "recovered_sub_454960_case_53"
		and String(source.get("initial_hit_points", ""))
			== "recovered_35_vwf_actor_states"
		and String(source.get("detonation_hit_points_sentinel", ""))
			== "recovered_sub_4551B0"
		and String(source.get("resolved_action_index", ""))
			== "recovered_sub_4551B0_sub_4527E0"
		and String(source.get("effect_dispatch_type", ""))
			== "recovered_sub_4551B0"
		and String(source.get("explosion_actor_type", ""))
			== "recovered_sub_4656C0_case_5"
		and String(source.get("explosion_profile", ""))
			== "recovered_sub_4554A0"
	)
