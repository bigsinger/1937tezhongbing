class_name MissionData
extends RefCounted

const SCHEMA_VERSION := 1
const CATALOG_PATH := "res://data/missions.json"
const TRIGGER_FIELDS: Array[String] = ["markers", "explosion", "exit", "spawns", "entrances"]
const CHARGE_POLICY_MODES: Array[String] = ["preplanted", "inventory_required"]
const CHARGE_POLICY_SOURCE := "remake_policy_from_recovered_map_inventory"
const MEDIA_CUE_KINDS: Array[String] = ["audio", "dialogue", "movie", "ending"]
const MEDIA_CUE_SOURCES: Array[String] = [
	"recovered_media_mapping",
	"remake_editorial",
	"mixed",
]


static func load_catalog(resource_path: String = CATALOG_PATH) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var catalog := json.data as Dictionary
	if not is_valid_catalog(catalog):
		return {}
	return catalog


static func load_mission(mission_id: String, resource_path: String = CATALOG_PATH) -> Dictionary:
	var catalog := load_catalog(resource_path)
	if catalog.is_empty():
		return {}
	for raw_mission: Variant in catalog["missions"] as Array:
		var mission := raw_mission as Dictionary
		if str(mission["id"]) == mission_id:
			return mission
	return {}


static func is_valid_catalog(catalog: Dictionary) -> bool:
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var raw_missions: Variant = catalog.get("missions")
	if not raw_missions is Array or (raw_missions as Array).is_empty():
		return false
	if int(catalog.get("mission_count", -1)) != (raw_missions as Array).size():
		return false

	var ids: Dictionary = {}
	for index in range((raw_missions as Array).size()):
		var raw_mission: Variant = (raw_missions as Array)[index]
		if not raw_mission is Dictionary:
			return false
		var mission := raw_mission as Dictionary
		var mission_id := str(mission.get("id", ""))
		if not is_safe_mission_id(mission_id) or ids.has(mission_id):
			return false
		ids[mission_id] = true
		if int(mission.get("number", 0)) != index + 1 or str(mission.get("title", "")).is_empty():
			return false
		if int(mission.get("time_limit_seconds", -1)) < 0:
			return false
		if not is_valid_trigger_inventory(mission.get("trigger_inventory")):
			return false
		if not is_valid_objectives(mission.get("objectives")):
			return false
		if not mission.get("failure_conditions") is Array:
			return false
		if mission.has("exit_party") and not is_valid_exit_party(mission):
			return false
		if mission.has("required_survivors") and not _is_unique_nonempty_string_array(
			mission["required_survivors"]
		):
			return false
		if mission.has("simultaneous_zone_rule") and not is_valid_simultaneous_zone_rule(
			mission
		):
			return false
		if mission.has("charge_policy") and not is_valid_charge_policy(mission):
			return false
		if mission.has("media_cues") and not is_valid_media_cues(mission):
			return false
	return true


static func is_safe_mission_id(mission_id: String) -> bool:
	return (
		mission_id.length() == 4
		and mission_id.begins_with("m")
		and mission_id.substr(1).is_valid_int()
	)


static func is_valid_trigger_inventory(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in TRIGGER_FIELDS:
		if not (value as Dictionary).has(field) or int((value as Dictionary)[field]) < 0:
			return false
	return true


static func is_valid_objectives(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var objective_ids: Dictionary = {}
	for raw_objective: Variant in value as Array:
		if not raw_objective is Dictionary:
			return false
		var objective := raw_objective as Dictionary
		var objective_id := str(objective.get("id", ""))
		if objective_id.is_empty() or objective_ids.has(objective_id):
			return false
		objective_ids[objective_id] = true
		if str(objective.get("label", "")).is_empty() or not objective.get("required") is bool:
			return false
		var condition: Variant = objective.get("condition")
		if (
			not condition is Dictionary
			or str((condition as Dictionary).get("event", "")).is_empty()
		):
			return false
		if int((condition as Dictionary).get("required_count", 0)) <= 0:
			return false
		var dependencies: Variant = objective.get("depends_on", [])
		if not dependencies is Array:
			return false

	for raw_objective: Variant in value as Array:
		var objective := raw_objective as Dictionary
		for dependency: Variant in objective.get("depends_on", []) as Array:
			if not dependency is String or not objective_ids.has(dependency as String):
				return false
			if dependency as String == str(objective["id"]):
				return false
	return true


static func is_valid_exit_party(mission: Dictionary) -> bool:
	var raw_rules: Variant = mission.get("exit_party")
	var raw_bindings: Variant = mission.get("scene_bindings")
	if (
		not raw_rules is Dictionary
		or (raw_rules as Dictionary).is_empty()
		or not raw_bindings is Dictionary
		or not (raw_bindings as Dictionary).has("exit")
	):
		return false
	var rules := raw_rules as Dictionary
	var has_requirement := false
	for field: String in ["player_names", "escort_bindings"]:
		if not rules.has(field):
			continue
		has_requirement = true
		var raw_values: Variant = rules[field]
		if not raw_values is Array or (raw_values as Array).is_empty():
			return false
		var seen: Dictionary = {}
		for raw_value: Variant in raw_values as Array:
			if not raw_value is String or str(raw_value).is_empty() or seen.has(raw_value):
				return false
			seen[raw_value] = true
			if (
				field == "escort_bindings"
				and not (raw_bindings as Dictionary).has(str(raw_value))
			):
				return false
	return has_requirement


static func is_valid_simultaneous_zone_rule(mission: Dictionary) -> bool:
	var raw_rule: Variant = mission.get("simultaneous_zone_rule")
	var raw_bindings: Variant = mission.get("scene_bindings")
	if not raw_rule is Dictionary or not raw_bindings is Dictionary:
		return false
	var rule := raw_rule as Dictionary
	var binding := str(rule.get("binding", ""))
	if (
		binding.is_empty()
		or not (raw_bindings as Dictionary).has(binding)
		or str(rule.get("event", "")).is_empty()
		or str(rule.get("zone_role", "")).is_empty()
		or float(rule.get("radius_world", 0.0)) <= 0.0
		or float(rule.get("dwell_seconds", -1.0)) < 0.0
		or not rule.get("distinct_occupants") is bool
		or not rule.get("requires_hostiles_cleared") is bool
		or str(rule.get("source_status", "")) != "recovered"
	):
		return false
	return _is_unique_nonempty_string_array(rule.get("eligible_player_names"))


static func is_valid_charge_policy(mission: Dictionary) -> bool:
	var raw_policy: Variant = mission.get("charge_policy")
	var raw_bindings: Variant = mission.get("scene_bindings")
	if not raw_policy is Dictionary or not raw_bindings is Dictionary:
		return false
	var policy := raw_policy as Dictionary
	var bindings := raw_bindings as Dictionary
	var raw_explosion_scenes: Variant = bindings.get("explosion")
	if not raw_explosion_scenes is Array or (raw_explosion_scenes as Array).is_empty():
		return false
	var mode := str(policy.get("mode", ""))
	var quantity_per_target := int(policy.get("quantity_per_target", 0))
	var map_pickup_count := int(policy.get("map_pickup_count", -1))
	var target_count := int(policy.get("target_count", 0))
	if (
		mode not in CHARGE_POLICY_MODES
		or str(policy.get("inventory_item_key", "")).is_empty()
		or quantity_per_target <= 0
		or map_pickup_count < 0
		or target_count != (raw_explosion_scenes as Array).size()
		or str(policy.get("source_status", "")) != CHARGE_POLICY_SOURCE
		or str(policy.get("evidence_note", "")).is_empty()
	):
		return false
	var trigger_inventory := mission.get("trigger_inventory", {}) as Dictionary
	if int(trigger_inventory.get("explosion", -1)) != target_count:
		return false
	return (
		mode != "inventory_required"
		or map_pickup_count >= target_count * quantity_per_target
	)


static func is_valid_media_cues(mission: Dictionary) -> bool:
	var raw_media_cues: Variant = mission.get("media_cues")
	if not raw_media_cues is Dictionary or (raw_media_cues as Dictionary).is_empty():
		return false
	var media_cues := raw_media_cues as Dictionary
	var allowed_sections := {
		"on_start": true,
		"on_objective": true,
		"on_story_anchor": true,
		"on_victory": true,
	}
	for section_value: Variant in media_cues.keys():
		if not allowed_sections.has(str(section_value)):
			return false
	if media_cues.has("on_start") and not _is_valid_media_cue(media_cues["on_start"]):
		return false
	if media_cues.has("on_victory") and not _is_valid_media_cue(media_cues["on_victory"]):
		return false

	var objective_ids: Dictionary = {}
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		objective_ids[str((raw_objective as Dictionary).get("id", ""))] = true
	if media_cues.has("on_objective"):
		var raw_objective_cues: Variant = media_cues["on_objective"]
		if not raw_objective_cues is Dictionary or (raw_objective_cues as Dictionary).is_empty():
			return false
		for objective_value: Variant in (raw_objective_cues as Dictionary).keys():
			var objective_id := str(objective_value)
			if (
				not objective_ids.has(objective_id)
				or not _is_valid_media_cue((raw_objective_cues as Dictionary)[objective_value])
			):
				return false

	if media_cues.has("on_story_anchor"):
		var raw_anchor_cues: Variant = media_cues["on_story_anchor"]
		var bindings := mission.get("scene_bindings", {}) as Dictionary
		if not raw_anchor_cues is Dictionary or (raw_anchor_cues as Dictionary).is_empty():
			return false
		for role_value: Variant in (raw_anchor_cues as Dictionary).keys():
			var role_id := str(role_value)
			if (
				not bindings.has(role_id)
				or not _is_story_anchor_objective(mission, role_id)
				or not _is_valid_media_cue((raw_anchor_cues as Dictionary)[role_value])
			):
				return false
	return true


static func _is_valid_media_cue(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var cue := value as Dictionary
	var kind := str(cue.get("kind", ""))
	if (
		kind not in MEDIA_CUE_KINDS
		or str(cue.get("source_status", "")) not in MEDIA_CUE_SOURCES
	):
		return false
	match kind:
		"audio":
			return not str(cue.get("event_key", "")).is_empty()
		"movie":
			return not str(cue.get("movie_id", "")).is_empty()
		"ending":
			return not str(cue.get("fallback_text", "")).is_empty()
		"dialogue":
			var raw_lines: Variant = cue.get("lines")
			if (
				str(cue.get("sequence_id", "")).is_empty()
				or not raw_lines is Array
				or (raw_lines as Array).is_empty()
			):
				return false
			for raw_line: Variant in raw_lines as Array:
				if not raw_line is Dictionary:
					return false
				var line := raw_line as Dictionary
				if str(line.get("text", "")).strip_edges().is_empty():
					return false
				if line.has("minimum_seconds") and float(line["minimum_seconds"]) < 0.0:
					return false
				if line.has("auto_advance") and not line["auto_advance"] is bool:
					return false
				if line.has("audio_index") and int(line["audio_index"]) < 0:
					return false
			return true
	return false


static func _is_story_anchor_objective(mission: Dictionary, role_id: String) -> bool:
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		var condition := (raw_objective as Dictionary).get("condition", {}) as Dictionary
		if (
			str(condition.get("event", "")) == "story_anchor_reached"
			and str((condition.get("where", {}) as Dictionary).get("role_id", "")) == role_id
		):
			return true
	return false


static func _is_unique_nonempty_string_array(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var seen: Dictionary = {}
	for raw_value: Variant in value as Array:
		if not raw_value is String:
			return false
		var text := str(raw_value)
		if text.is_empty() or seen.has(text):
			return false
		seen[text] = true
	return true
