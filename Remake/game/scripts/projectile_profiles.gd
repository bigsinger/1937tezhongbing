class_name ProjectileProfiles
extends RefCounted

const SCHEMA_VERSION := 3
const CATALOG_PATH := "res://data/projectile_profiles.json"
const PROJECTILE_ATTACK_TYPES := {1: true, 2: true, 3: true, 6: true, 7: true, 9: true}
const VALID_MOTIONS := {
	"linear_bresenham": true,
	"original_path_parabola": true,
}
const VALID_COLLISION_SEMANTICS := {
	"layer3_actor_then_layer2_obstruction": true,
	"ignore_actor_and_layer2_until_destination": true,
}
const VALID_SOURCE_STATUSES := {
	"recovered": true,
	"recovered_first_match": true,
	"recovered_no_sprite_actor": true,
	"recovered_with_runtime_actor_override": true,
}
const COMMON_SOURCE_FIELDS := [
	"original_effect_type",
	"delivery_mode",
	"motion",
	"world_step_pixels",
	"runtime_actor_type",
	"original_gfl_index",
	"direct_damage",
	"collision_semantics",
	"impact_effect_type",
	"impact_actor_type",
	"impact_gfl_index",
	"friendly_fire",
]
const EXPLOSION_SOURCE_FIELDS := [
	"explosion_actor_type",
	"explosion_gfl_index",
	"blast_damage",
	"blast_horizontal_radius",
	"blast_vertical_radius",
	"alert_radius",
]

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
	var delivery_mode := int(profile.get("delivery_mode", 0))
	if delivery_mode not in [0, 1, 3, 4]:
		return false
	if not VALID_MOTIONS.has(String(profile.get("motion", ""))):
		return false
	if int(profile.get("world_step_pixels", 0)) <= 0:
		return false
	if int(profile.get("runtime_actor_type", -1)) < 0:
		return false
	if int(profile.get("original_gfl_index", -1)) < 0:
		return false
	if int(profile.get("direct_damage", -1)) < 0:
		return false
	if not VALID_COLLISION_SEMANTICS.has(
		String(profile.get("collision_semantics", ""))
	):
		return false
	if not profile.get("friendly_fire") is bool:
		return false
	var source_value: Variant = profile.get("source_status")
	if not source_value is Dictionary:
		return false
	var source := source_value as Dictionary
	for field: String in COMMON_SOURCE_FIELDS:
		if not VALID_SOURCE_STATUSES.has(String(source.get(field, ""))):
			return false
	var explosion_actor_type := int(profile.get("explosion_actor_type", 0))
	var horizontal_radius := float(profile.get("blast_horizontal_radius", -1.0))
	var vertical_radius := float(profile.get("blast_vertical_radius", -1.0))
	var effect_type := int(profile.get("original_effect_type", 0))
	var impact_effect_type := int(profile.get("impact_effect_type", 0))
	var impact_actor_type := int(profile.get("impact_actor_type", 0))
	var impact_gfl_index := int(profile.get("impact_gfl_index", 0))
	if delivery_mode == 1:
		if (
			attack_type != 9
			or effect_type != 2
			or String(profile["motion"]) != "original_path_parabola"
			or String(profile["collision_semantics"])
				!= "ignore_actor_and_layer2_until_destination"
			or explosion_actor_type != 61
			or int(profile.get("explosion_gfl_index", 0)) != 19
			or impact_effect_type != 4
			or impact_actor_type != 61
			or impact_gfl_index != 19
			or int(profile.get("blast_damage", 0)) != 128
			or horizontal_radius != 128.0
			or vertical_radius != 64.0
			or float(profile.get("alert_radius", 0.0)) != 800.0
		):
			return false
		for field: String in EXPLOSION_SOURCE_FIELDS:
			if not VALID_SOURCE_STATUSES.has(String(source.get(field, ""))):
				return false
		return true
	var is_ordinary_bullet := attack_type in [1, 2, 3]
	if is_ordinary_bullet:
		return (
			effect_type == 1
			and delivery_mode == 0
			and int(profile["world_step_pixels"]) == 64
			and int(profile["runtime_actor_type"]) == 0
			and int(profile["original_gfl_index"]) == 0
			and int(profile["direct_damage"]) == 2
			and explosion_actor_type == 0
			and String(profile["motion"]) == "linear_bresenham"
			and String(profile["collision_semantics"])
				== "layer3_actor_then_layer2_obstruction"
			and impact_effect_type == 8
			and impact_actor_type == 60
			and impact_gfl_index == 306
			and horizontal_radius == 0.0
			and vertical_radius == 0.0
		)
	return (
		explosion_actor_type == 0
		and String(profile["motion"]) == "linear_bresenham"
		and String(profile["collision_semantics"])
			== "layer3_actor_then_layer2_obstruction"
		and impact_effect_type == 8
		and impact_actor_type == 60
		and impact_gfl_index == 306
		and horizontal_radius == 0.0
		and vertical_radius == 0.0
		and (
			(attack_type == 6 and effect_type == 13 and delivery_mode == 3 and int(profile["world_step_pixels"]) == 16 and int(profile["runtime_actor_type"]) == 80 and int(profile["original_gfl_index"]) == 251 and int(profile["direct_damage"]) == 8)
			or
			(attack_type == 7 and effect_type == 14 and delivery_mode == 4 and int(profile["world_step_pixels"]) == 5 and int(profile["runtime_actor_type"]) == 81 and int(profile["original_gfl_index"]) == 635 and int(profile["direct_damage"]) == 1)
		)
	)
