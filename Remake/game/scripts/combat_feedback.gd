class_name CombatFeedback
extends RefCounted


static func preview(
	attacker: Node2D,
	target: Node2D,
	dynamic_occupancy: Variant = null,
) -> Dictionary:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return {"visible": false, "reason": "invalid_target"}
	var profile_value: Variant = attacker.get("weapon_profile")
	if not profile_value is Dictionary or (profile_value as Dictionary).is_empty():
		return {"visible": true, "ready": false, "reason": "no_weapon"}
	var profile := profile_value as Dictionary
	var offset := target.global_position - attacker.global_position
	var horizontal_range := maxf(float(profile.get("horizontal_range", 1.0)), 1.0)
	var vertical_range := maxf(float(profile.get("vertical_range", 1.0)), 1.0)
	var normalized_distance := (
		offset.x * offset.x / (horizontal_range * horizontal_range)
		+ offset.y * offset.y / (vertical_range * vertical_range)
	)
	var in_range := normalized_distance <= 1.0
	var ammo_per_attack := maxi(int(profile.get("ammo_per_attack", 0)), 0)
	var infinite_ammo := bool(attacker.get("infinite_ammo"))
	var current_ammo := int(attacker.get("magazine_ammo"))
	var has_ammo := infinite_ammo or ammo_per_attack <= 0 or current_ammo >= ammo_per_attack
	var line_of_sight := true
	if (
		bool(profile.get("requires_line_of_sight", true))
		and dynamic_occupancy != null
		and dynamic_occupancy.has_method("has_line_of_sight")
	):
		var ignored: Array = []
		for actor: Node2D in [attacker, target]:
			var scene_index := int(actor.get("scene_index"))
			if scene_index >= 0:
				ignored.append(scene_index)
		line_of_sight = bool(dynamic_occupancy.call(
			"has_line_of_sight",
			attacker.global_position,
			target.global_position,
			ignored,
		))
	var attack_type := int(profile.get("attack_type", 0))
	var hit_chance := player_hit_chance(attack_type)
	var reason := "ready"
	if not has_ammo:
		reason = "insufficient_ammo"
	elif not in_range:
		reason = "out_of_range"
	elif not line_of_sight:
		reason = "obstructed"
	return {
		"visible": true,
		"ready": has_ammo and in_range and line_of_sight,
		"reason": reason,
		"attack_type": attack_type,
		"horizontal_range": horizontal_range,
		"vertical_range": vertical_range,
		"distance": offset.length(),
		"in_range": in_range,
		"line_of_sight": line_of_sight,
		"has_ammo": has_ammo,
		"ammo": current_ammo,
		"hit_chance": hit_chance,
		"alert_radius": maxf(float(profile.get("alert_radius", 0.0)), 0.0),
	}


static func player_hit_chance(attack_type: int) -> float:
	match attack_type:
		1:
			return 0.80
		2:
			return 0.90
		4, 5:
			return 1.0
		_:
			return 1.0


static func display_text(preview_data: Dictionary, weapon_name: String) -> String:
	if not bool(preview_data.get("visible", false)):
		return ""
	var reason_labels := {
		"ready": _text("COMBAT_READY"),
		"out_of_range": _text("COMBAT_OUT_OF_RANGE"),
		"obstructed": _text("COMBAT_OBSTRUCTED"),
		"insufficient_ammo": _text("COMBAT_INSUFFICIENT_AMMO"),
		"no_weapon": _text("COMBAT_NO_WEAPON"),
	}
	return _text("COMBAT_PREVIEW_FORMAT") % [
		weapon_name,
		roundi(float(preview_data.get("hit_chance", 0.0)) * 100.0),
		float(preview_data.get("distance", 0.0)),
		float(preview_data.get("horizontal_range", 0.0)),
		float(preview_data.get("alert_radius", 0.0)),
		str(
			reason_labels.get(
				str(preview_data.get("reason", "")),
				_text("COMBAT_UNAVAILABLE"),
			)
		),
	]


static func _text(key: String) -> String:
	return str(TranslationServer.translate(StringName(key)))
