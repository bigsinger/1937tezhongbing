class_name ModernDifficultyPolicy
extends RefCounted

## Product-level difficulty is a coherent policy, not a single accuracy knob.
## The authored mission profile remains the level-to-level baseline; this
## layer scales perception, reaction, search, cooperation and resources in a
## predictable way shared by every mission.

const PRESETS := {
	"story": {
		"enemy_hit_chance": 0.52,
		"reaction_multiplier": 1.35,
		"perception_multiplier": 0.85,
		"search_multiplier": 0.75,
		"alert_multiplier": 0.78,
		"reinforcement_multiplier": 0.50,
		"player_resource_multiplier": 1.35,
		"suspicion_multiplier": 0.72,
	},
	"normal": {
		"enemy_hit_chance": 0.70,
		"reaction_multiplier": 1.00,
		"perception_multiplier": 1.00,
		"search_multiplier": 1.00,
		"alert_multiplier": 1.00,
		"reinforcement_multiplier": 1.00,
		"player_resource_multiplier": 1.00,
		"suspicion_multiplier": 1.00,
	},
	"hard": {
		"enemy_hit_chance": 0.86,
		"reaction_multiplier": 0.78,
		"perception_multiplier": 1.15,
		"search_multiplier": 1.30,
		"alert_multiplier": 1.25,
		"reinforcement_multiplier": 1.50,
		"player_resource_multiplier": 0.86,
		"suspicion_multiplier": 1.35,
	},
}


static func compose(
	authored_profile: Dictionary,
	mode: String,
	custom: Dictionary = {},
) -> Dictionary:
	var normalized_mode := "story" if mode == "easy" else mode
	if normalized_mode not in ["story", "normal", "hard", "custom"]:
		normalized_mode = "normal"
	var policy: Dictionary = (
		_custom_policy(custom)
		if normalized_mode == "custom"
		else (PRESETS[normalized_mode] as Dictionary).duplicate(true)
	)
	var result := authored_profile.duplicate(true)
	result["source_status"] = str(
		authored_profile.get("source_status", "remake_editorial")
	)
	result["difficulty_mode"] = normalized_mode
	result["original_parity"] = false
	result["enemy_hit_chance"] = float(policy["enemy_hit_chance"])
	result["reaction_time_multiplier"] = (
		float(authored_profile.get("reaction_time_multiplier", 1.0))
		* float(policy["reaction_multiplier"])
	)
	result["sense_radius_multiplier"] = (
		float(authored_profile.get("sense_radius_multiplier", 1.0))
		* float(policy["perception_multiplier"])
	)
	result["shared_alert_radius_multiplier"] = (
		float(authored_profile.get("shared_alert_radius_multiplier", 1.0))
		* float(policy["alert_multiplier"])
	)
	result["reinforcement_budget"] = maxi(
		0,
		roundi(
			float(authored_profile.get("reinforcement_budget", 0))
			* float(policy["reinforcement_multiplier"])
		),
	)
	result["search_duration_multiplier"] = float(policy["search_multiplier"])
	result["alert_delay_multiplier"] = 1.0 / maxf(
		float(policy["alert_multiplier"]),
		0.01,
	)
	result["player_resource_multiplier"] = float(
		policy["player_resource_multiplier"]
	)
	result["suspicion_gain_multiplier"] = float(policy["suspicion_multiplier"])
	result["memory_seconds"] = 4.5 * float(policy["search_multiplier"])
	return result


static func _custom_policy(custom: Dictionary) -> Dictionary:
	return {
		"enemy_hit_chance": clampf(
			float(custom.get("enemy_accuracy", 0.70)), 0.25, 1.0
		),
		"reaction_multiplier": clampf(
			float(custom.get("reaction_multiplier", 1.0)), 0.25, 2.0
		),
		"perception_multiplier": clampf(
			float(custom.get("perception_multiplier", 1.0)), 0.25, 2.0
		),
		"search_multiplier": clampf(
			float(custom.get("search_multiplier", 1.0)), 0.25, 2.0
		),
		"alert_multiplier": clampf(
			float(custom.get("alert_multiplier", 1.0)), 0.25, 2.0
		),
		"reinforcement_multiplier": clampf(
			float(custom.get("reinforcement_multiplier", 1.0)), 0.25, 2.0
		),
		"player_resource_multiplier": clampf(
			2.0 - float(custom.get("reinforcement_multiplier", 1.0)) * 0.5,
			0.75,
			1.50,
		),
		"suspicion_multiplier": clampf(
			float(custom.get("perception_multiplier", 1.0)), 0.25, 2.0
		),
	}
