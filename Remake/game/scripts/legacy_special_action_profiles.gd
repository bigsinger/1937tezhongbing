class_name LegacySpecialActionProfiles
extends RefCounted

# Evidence boundary for attack types 8/10/11.
#
# `recovered` fields below come from the original sub_456DF0 dispatch and the
# actor 84/85 update handlers.  `unresolved_remake_default` fields are only the
# playable behavior supplied by this remake; they must not be cited as facts
# about the 2001 executable.
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
		# Final damage and blast geometry have not yet been recovered.
		"blast_damage": 8,
		"blast_horizontal_radius": 32.0,
		"blast_vertical_radius": 16.0,
		"resolved_visual_ticks": 8,
		"source_status": {
			"runtime_kind": "recovered",
			"original_actor_type": "recovered",
			"original_gfl_index": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"trigger_faction_id": "recovered",
			"trigger_horizontal_radius": "recovered",
			"trigger_vertical_radius": "recovered",
			"blast_damage": "unresolved_remake_default",
			"blast_horizontal_radius": "unresolved_remake_default",
			"blast_vertical_radius": "unresolved_remake_default",
			"resolved_visual_ticks": "unresolved_remake_default",
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
		# Final damage and blast geometry have not yet been recovered.
		"blast_damage": 8,
		"blast_horizontal_radius": 64.0,
		"blast_vertical_radius": 32.0,
		"resolved_visual_ticks": 8,
		"source_status": {
			"runtime_kind": "recovered",
			"original_actor_type": "recovered",
			"original_gfl_index": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"fuse_world_ticks": "recovered",
			"blast_damage": "unresolved_remake_default",
			"blast_horizontal_radius": "unresolved_remake_default",
			"blast_vertical_radius": "unresolved_remake_default",
			"resolved_visual_ticks": "unresolved_remake_default",
		},
	},
	11: {
		"attack_type": 11,
		"runtime_kind": "ai_control_status",
		"ammo_item_id": 99,
		"consumes_item": false,
		"original_target_flag_offset": 656,
		# The original sets and later clears this target flag, but the exact
		# semantics and lifetime remain unresolved.  Temporarily suppressing the
		# target AI for 180 world ticks is the remake's explicit playable rule.
		"remake_behavior": "suppress_ai",
		"duration_world_ticks": 180,
		"source_status": {
			"runtime_kind": "recovered",
			"ammo_item_id": "recovered",
			"consumes_item": "recovered",
			"original_target_flag_offset": "recovered",
			"remake_behavior": "unresolved_remake_default",
			"duration_world_ticks": "unresolved_remake_default",
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
			or int(profile.get("blast_damage", 0)) <= 0
			or float(profile.get("blast_horizontal_radius", 0.0)) <= 0.0
			or float(profile.get("blast_vertical_radius", 0.0)) <= 0.0
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
		and int(profile.get("duration_world_ticks", 0)) > 0
	)
