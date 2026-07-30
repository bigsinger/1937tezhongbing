class_name LegacySpecialActionProfiles
extends RefCounted

# Evidence boundary for attack types 8/10/11.
#
# `recovered` fields below come from the original sub_456DF0 dispatch, actor
# 84/85 deployment handlers, actor 62 explosion handler and the enemy update
# paths that consume target flag +656. `unresolved_remake_default` fields are
# only playable behavior supplied by this remake; they must not be cited as
# facts about the 2001 executable.
const VALID_SOURCE_STATUSES := {
	"recovered": true,
	"unresolved_remake_default": true,
}
const SPECIAL_ATTACK_TYPES := [8, 10, 11]
const WORLD_OBJECT_ATTACK_TYPES := [8, 10]
const AI_CONTROL_ATTACK_TYPE := 11

const PROFILES := {
	8: {
		"attack_type": 8,
		"runtime_kind": "triggered_world_object",
		"original_actor_type": 84,
		"original_gfl_index": 470,
		"ammo_item_id": 43,
		"consumes_item": true,
		"trigger_faction_id": 1,
		"trigger_horizontal_radius": 32.0,
		"trigger_vertical_radius": 16.0,
		"explosion_actor_type": 62,
		"blast_damage": 128,
		"blast_horizontal_radius": 128.0,
		"blast_vertical_radius": 64.0,
		"alert_radius": 800.0,
		"special_damage_bands": [
			{
				"runtime_actor_types": [34, 86, 87, 88, 94, 95, 96, 97],
				"geometry": "ellipse",
				"horizontal_radius": 384.0,
				"vertical_radius": 192.0,
				"damage": 128,
				"original_visual_effect_type": 11,
			},
			{
				"runtime_actor_types": [66, 67, 68, 77, 93],
				"geometry": "euclidean_radius",
				"radius": 256.0,
				"exclusive_boundary": true,
				"damage": 128,
				"original_visual_effect_type": 15,
			},
		],
		"source_status": {
			"runtime_kind": "recovered",
			"original_actor_type": "recovered",
			"original_gfl_index": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"trigger_faction_id": "recovered",
			"trigger_horizontal_radius": "recovered",
			"trigger_vertical_radius": "recovered",
			"explosion_actor_type": "recovered",
			"blast_damage": "recovered",
			"blast_horizontal_radius": "recovered",
			"blast_vertical_radius": "recovered",
			"alert_radius": "recovered",
			"special_damage_bands": "recovered",
		},
	},
	10: {
		"attack_type": 10,
		"runtime_kind": "timed_world_object",
		"original_actor_type": 85,
		"original_gfl_index": 900,
		"ammo_item_id": 45,
		"consumes_item": true,
		"fuse_world_ticks": 100,
		"explosion_actor_type": 62,
		"blast_damage": 128,
		"blast_horizontal_radius": 128.0,
		"blast_vertical_radius": 64.0,
		"alert_radius": 800.0,
		"special_damage_bands": [
			{
				"runtime_actor_types": [34, 86, 87, 88, 94, 95, 96, 97],
				"geometry": "ellipse",
				"horizontal_radius": 384.0,
				"vertical_radius": 192.0,
				"damage": 128,
				"original_visual_effect_type": 11,
			},
			{
				"runtime_actor_types": [66, 67, 68, 77, 93],
				"geometry": "euclidean_radius",
				"radius": 256.0,
				"exclusive_boundary": true,
				"damage": 128,
				"original_visual_effect_type": 15,
			},
		],
		"source_status": {
			"runtime_kind": "recovered",
			"original_actor_type": "recovered",
			"original_gfl_index": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"fuse_world_ticks": "recovered",
			"explosion_actor_type": "recovered",
			"blast_damage": "recovered",
			"blast_horizontal_radius": "recovered",
			"blast_vertical_radius": "recovered",
			"alert_radius": "recovered",
			"special_damage_bands": "recovered",
		},
	},
	11: {
		"attack_type": 11,
		"runtime_kind": "ai_control_status",
		"ammo_item_id": 99,
		"consumes_item": false,
		"original_target_flag_offset": 656,
		"remake_behavior": "attention_hold",
		"pauses_idle_movement": true,
		"faces_source_actor": true,
		"release_on_source_movement": true,
		"release_on_combat_transition": true,
		"source_status": {
			"runtime_kind": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"original_target_flag_offset": "recovered",
			"remake_behavior": "recovered",
			"pauses_idle_movement": "recovered",
			"faces_source_actor": "recovered",
			"release_on_source_movement": "recovered",
			"release_on_combat_transition": "recovered",
		},
	},
}


static func profile_for_attack_type(attack_type: int) -> Dictionary:
	var value: Variant = PROFILES.get(attack_type)
	if not value is Dictionary:
		return {}
	return (value as Dictionary).duplicate(true)


static func is_special_attack(attack_type: int) -> bool:
	return attack_type in SPECIAL_ATTACK_TYPES


static func is_world_object_attack(attack_type: int) -> bool:
	return attack_type in WORLD_OBJECT_ATTACK_TYPES


static func is_valid_profile(profile: Dictionary) -> bool:
	var attack_type := int(profile.get("attack_type", 0))
	if attack_type not in SPECIAL_ATTACK_TYPES:
		return false
	var canonical := profile_for_attack_type(attack_type)
	if canonical.is_empty():
		return false
	var source_value: Variant = profile.get("source_status")
	if not source_value is Dictionary:
		return false
	var source_status := source_value as Dictionary
	var canonical_source := canonical.get("source_status", {}) as Dictionary
	for canonical_field: Variant in canonical_source.keys():
		if (
			not source_status.has(canonical_field)
			or source_status[canonical_field] != canonical_source[canonical_field]
		):
			return false
	for raw_status: Variant in source_status.values():
		if not raw_status is String or not VALID_SOURCE_STATUSES.has(String(raw_status)):
			return false
	if not (
		int(profile.get("ammo_item_id", 0)) == int(canonical["ammo_item_id"])
		and String(profile.get("runtime_kind", "")) == String(canonical["runtime_kind"])
		and bool(profile.get("consumes_item", true)) == bool(canonical["consumes_item"])
	):
		return false
	if is_world_object_attack(attack_type):
		if (
			int(profile.get("original_actor_type", 0)) != int(canonical["original_actor_type"])
			or int(profile.get("original_gfl_index", 0)) != int(canonical["original_gfl_index"])
			or int(profile.get("explosion_actor_type", 0)) != int(canonical["explosion_actor_type"])
			or int(profile.get("blast_damage", 0)) <= 0
			or float(profile.get("blast_horizontal_radius", 0.0)) <= 0.0
			or float(profile.get("blast_vertical_radius", 0.0)) <= 0.0
			or float(profile.get("alert_radius", 0.0)) <= 0.0
			or profile.get("special_damage_bands") != canonical["special_damage_bands"]
		):
			return false
	if attack_type == 8:
		return (
			int(profile.get("trigger_faction_id", 0)) == int(canonical["trigger_faction_id"])
			and float(profile.get("trigger_horizontal_radius", 0.0)) == float(canonical["trigger_horizontal_radius"])
			and float(profile.get("trigger_vertical_radius", 0.0)) == float(canonical["trigger_vertical_radius"])
		)
	if attack_type == 10:
		return int(profile.get("fuse_world_ticks", 0)) == int(canonical["fuse_world_ticks"])
	return (
		int(profile.get("original_target_flag_offset", 0))
			== int(canonical["original_target_flag_offset"])
		and String(profile.get("remake_behavior", "")) == String(canonical["remake_behavior"])
		and bool(profile.get("pauses_idle_movement", false))
			== bool(canonical["pauses_idle_movement"])
		and bool(profile.get("faces_source_actor", false))
			== bool(canonical["faces_source_actor"])
		and bool(profile.get("release_on_source_movement", false))
			== bool(canonical["release_on_source_movement"])
		and bool(profile.get("release_on_combat_transition", false))
			== bool(canonical["release_on_combat_transition"])
	)
