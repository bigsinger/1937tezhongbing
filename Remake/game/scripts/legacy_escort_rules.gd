class_name LegacyEscortRules
extends RefCounted

## Mission-specific neutral/recruit behavior recovered from the runtime-type
## dispatch in sub_454960.  These rules deliberately describe only the seven
## formal rescue actors; unrelated neutral actors keep their own AI.
const ORIGINAL_PURSUIT_CALL_SITE_RVA := 0x0005D47E

static func rule_for(level_id: String, runtime_actor_type: int) -> Dictionary:
	match "%s:%d" % [level_id, runtime_actor_type]:
		"m000:17":
			return _rule(
			["强子"], [], 128.0, "distance_strict", true, true, false,
			"sub_459490 -> sub_45D260/sub_45D330",
			)
		"m000:3":
			return _rule(
			["强子"], [], 128.0, "distance_strict", true, true, false,
			"sub_459530 -> sub_45D260/sub_45D330",
			)
		"m001:19":
			return _rule(
			["古明"], [91], 128.0, "isometric_inclusive", false, true, false,
			"sub_454D90 mission 2 disguised-Gu-Ming branch",
			)
		"m002:1":
			return _rule(
			["老赵"], [2], 128.0, "distance_strict", true, false, true,
			"sub_4590E0 -> sub_45EF90(type 2, 128)",
			)
		"m004:10":
			return _rule(
			["大牛"], [8], 128.0, "distance_strict", true, false, true,
			"sub_459290 -> sub_45EF90(type 8, 128)",
			)
		"m007:18":
			return _rule(
			["古明"], [], 128.0, "isometric_inclusive", true, true, false,
			"sub_4550A0 mission 8 reporter branch",
			)
		"m007:19":
			return _rule(
			["古明", "强子", "老赵", "铁蛋"], [], 48.0,
			"isometric_inclusive", true, true, false,
			"sub_454D90 mission 8 parent branch",
			)
		"m007:26":
			return _rule(
			["古明", "强子", "老赵", "铁蛋"], [], 48.0,
			"isometric_inclusive", true, true, false,
			"sub_454D90 mission 8 parent branch",
			)
	return {}


static func _rule(
	target_names: Array,
	target_runtime_types: Array,
	radius: float,
	proximity_kind: String,
	changes_faction: bool,
	follows_target: bool,
	becomes_commandable: bool,
	source: String,
) -> Dictionary:
	return {
		"target_names": target_names,
		"target_runtime_types": target_runtime_types,
		"radius": radius,
		"proximity_kind": proximity_kind,
		"changes_faction": changes_faction,
		"follows_target": follows_target,
		"becomes_commandable": becomes_commandable,
		"source": source,
	}


static func rescuer_is_eligible(rule: Dictionary, rescuer: Node2D) -> bool:
	if (
		rescuer == null
		or not is_instance_valid(rescuer)
		or not bool(rescuer.get("is_alive"))
	):
		return false
	var names := rule.get("target_names", []) as Array
	if not names.is_empty() and not names.has(str(rescuer.get("display_name"))):
		return false
	var runtime_types := rule.get("target_runtime_types", []) as Array
	return (
		runtime_types.is_empty()
		or runtime_types.has(int(rescuer.get("runtime_actor_type")))
	)


static func is_within_rescue_range(
	rule: Dictionary,
	escort_position: Vector2,
	rescuer_position: Vector2,
) -> bool:
	var radius := float(rule.get("radius", 0.0))
	if radius <= 0.0:
		return false
	var offset := rescuer_position - escort_position
	match str(rule.get("proximity_kind", "")):
		"distance_strict":
			return offset.length_squared() < radius * radius
		"isometric_inclusive":
			var vertical_radius := radius * 0.5
			return (
				offset.x * offset.x / (radius * radius)
					+ offset.y * offset.y / (vertical_radius * vertical_radius)
			) <= 1.0
	return false
