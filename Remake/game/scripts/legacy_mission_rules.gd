class_name LegacyMissionRules
extends RefCounted

const SOURCE_STATUS := "recovered_stable_mod_control_flow"
const TARGET_HIT_POINTS_NONPOSITIVE := "target_hit_points_nonpositive"
const TIMED_EXPLOSIVE_WITHIN_RADIUS := "timed_explosive_within_radius"

# Source-backed subsets of sub_404BB0/sub_405410.  These rules describe
# world-state predicates which the generic objective graph cannot infer from a
# context-key interaction alone.  Scene identities remain in missions.json;
# this table fixes the native types, geometry, live actor restrictions and
# holder rules shared by every scene bound to the named role.
const RULES := {
	"m001": {
		"mission_number": 2,
		"target": {
			"binding": "explosion",
			"runtime_actor_type": 98,
			"completion": TARGET_HIT_POINTS_NONPOSITIVE,
		},
		"exit": {
			"binding": "exit",
			"runtime_actor_type": 100,
			"radius_world": 128.0,
			"exclusive_boundary": false,
			"player_names": ["古明"],
			"player_runtime_types": {"古明": [91]},
			"escort_bindings": ["driver"],
		},
	},
	"m002": {
		"mission_number": 3,
		"target": {
			"binding": "explosion",
			"runtime_actor_type": 98,
			"completion": TARGET_HIT_POINTS_NONPOSITIVE,
		},
		"exit": {
			"binding": "exit",
			"runtime_actor_type": 100,
			"radius_world": 128.0,
			"exclusive_boundary": true,
			"player_names": ["老赵"],
			"escort_bindings": ["rescued"],
		},
	},
	"m003": {
		"mission_number": 4,
		"target": {
			"binding": "explosion",
			"runtime_actor_type": 98,
			"completion": TIMED_EXPLOSIVE_WITHIN_RADIUS,
			"required_runtime_actor_type": 85,
			"radius_world": 128.0,
			"exclusive_boundary": true,
		},
		"exit": {
			"binding": "exit",
			"runtime_actor_type": 100,
			"radius_world": 128.0,
			"exclusive_boundary": false,
			"player_names": ["老赵", "强子", "古明", "大牛"],
		},
	},
	"m004": {
		"mission_number": 5,
		"target": {
			"binding": "explosion",
			"runtime_actor_type": 98,
			"completion": TARGET_HIT_POINTS_NONPOSITIVE,
		},
		"item_holders": {"m004_plan_document": ["古明", "大牛"]},
	},
	"m006": {
		"mission_number": 7,
		"required_dead_bindings": ["m006_sun_damazi", "m006_kato"],
		"item_holders": {"m006_name_list": ["强子"]},
	},
	"m008": {
		"mission_number": 9,
		"target": {
			"binding": "explosion",
			"runtime_actor_type": 98,
			"completion": TIMED_EXPLOSIVE_WITHIN_RADIUS,
			"required_runtime_actor_type": 85,
			"radius_world": 128.0,
			"exclusive_boundary": true,
		},
		"exit": {
			"binding": "exit",
			"runtime_actor_type": 100,
			"radius_world": 128.0,
			"exclusive_boundary": true,
			"player_names": ["老赵", "大牛"],
		},
	},
}


static func rule_for(level_id: String) -> Dictionary:
	var raw_rule: Variant = RULES.get(level_id, {})
	if not raw_rule is Dictionary or (raw_rule as Dictionary).is_empty():
		return {}
	var result := (raw_rule as Dictionary).duplicate(true)
	result["source_status"] = SOURCE_STATUS
	return result


static func target_rule_for(level_id: String) -> Dictionary:
	var rule := rule_for(level_id)
	var raw_target: Variant = rule.get("target", {})
	return (raw_target as Dictionary).duplicate(true) if raw_target is Dictionary else {}


static func exit_rule_for(level_id: String) -> Dictionary:
	var rule := rule_for(level_id)
	var raw_exit: Variant = rule.get("exit", {})
	return (raw_exit as Dictionary).duplicate(true) if raw_exit is Dictionary else {}


static func item_holder_is_eligible(
	level_id: String,
	item_role: String,
	display_name: String,
) -> bool:
	var rule := rule_for(level_id)
	var raw_holders: Variant = rule.get("item_holders", {})
	if not raw_holders is Dictionary or not (raw_holders as Dictionary).has(item_role):
		return true
	var raw_names: Variant = (raw_holders as Dictionary)[item_role]
	return raw_names is Array and (raw_names as Array).has(display_name)


static func distance_matches(
	left: Vector2,
	right: Vector2,
	radius_world: float,
	exclusive_boundary: bool,
) -> bool:
	if radius_world <= 0.0:
		return false
	var distance_squared := left.distance_squared_to(right)
	var radius_squared := radius_world * radius_world
	return (
		distance_squared < radius_squared
		if exclusive_boundary
		else distance_squared <= radius_squared
	)


static func explosion_covers_target(
	explosion_position: Vector2,
	target_position: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
) -> bool:
	if horizontal_radius <= 0.0 or vertical_radius <= 0.0:
		return false
	var offset := target_position - explosion_position
	return (
		offset.x * offset.x / (horizontal_radius * horizontal_radius)
		+ offset.y * offset.y / (vertical_radius * vertical_radius)
	) <= 1.0


static func explosion_destroys_target(
	current_hit_points: int,
	damage: int,
) -> bool:
	return current_hit_points > 0 and damage >= current_hit_points


static func is_valid_rule(level_id: String, rule: Dictionary) -> bool:
	if (
		level_id.is_empty()
		or int(rule.get("mission_number", 0)) <= 0
		or str(rule.get("source_status", "")) != SOURCE_STATUS
		or rule.is_empty()
	):
		return false
	var raw_target: Variant = rule.get("target", {})
	if raw_target is Dictionary and not (raw_target as Dictionary).is_empty():
		var target := raw_target as Dictionary
		var completion := str(target.get("completion", ""))
		if (
			str(target.get("binding", "")).is_empty()
			or int(target.get("runtime_actor_type", 0)) != 98
			or completion not in [
				TARGET_HIT_POINTS_NONPOSITIVE,
				TIMED_EXPLOSIVE_WITHIN_RADIUS,
			]
		):
			return false
		if completion == TIMED_EXPLOSIVE_WITHIN_RADIUS and (
			int(target.get("required_runtime_actor_type", 0)) != 85
			or float(target.get("radius_world", 0.0)) <= 0.0
			or not target.get("exclusive_boundary") is bool
		):
			return false
	var raw_exit: Variant = rule.get("exit", {})
	if raw_exit is Dictionary and not (raw_exit as Dictionary).is_empty():
		var exit := raw_exit as Dictionary
		if (
			str(exit.get("binding", "")).is_empty()
			or int(exit.get("runtime_actor_type", 0)) != 100
			or float(exit.get("radius_world", 0.0)) <= 0.0
			or not exit.get("exclusive_boundary") is bool
			or not exit.get("player_names") is Array
			or (exit.get("player_names") as Array).is_empty()
		):
			return false
	return true
