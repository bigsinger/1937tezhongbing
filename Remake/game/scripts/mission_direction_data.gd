class_name MissionDirectionData
extends RefCounted

## Validates the remake's presentation and encounter layer separately from the
## recovered objective graph. This separation is intentional: an editorial
## line must never become evidence for an original-game transcript.

const SCHEMA_VERSION := 1
const CATALOG_PATH := "res://data/mission_direction.json"
const MISSION_CATALOG_PATH := "res://data/missions.json"
const MISSION_DATA_SCRIPT: Script = preload("res://scripts/mission_data.gd")

const BEAT_SOURCE_STATUSES: Array[String] = ["recovered", "remake_editorial", "mixed"]
const EDITORIAL_SOURCE := "remake_editorial"
const CAMERA_SOURCE_STATUSES: Array[String] = [
	"recovered_scene_binding", "remake_editorial", "mixed"
]
const CAMERA_MODES: Array[String] = ["focus_binding", "follow_party"]
const CAMERA_SELECTIONS: Array[String] = ["first", "last", "all_bounds", "next_incomplete"]
const TRIGGER_EVENTS: Array[String] = [
	"mission_started",
	"objective_completed",
	"objective_progress",
	"story_anchor_reached",
	"elapsed_seconds",
	"victory",
]
const AI_DIRECTIVE_KINDS: Array[String] = [
	"set_posture",
	"coordinate_search",
	"coordinate_defense",
	"release_reinforcement",
	"cease_reinforcement",
]
const DIFFICULTY_FLOAT_FIELDS: Array[String] = [
	"enemy_health_multiplier",
	"enemy_damage_multiplier",
	"reaction_time_multiplier",
	"aim_error_multiplier",
	"patrol_speed_multiplier",
	"sense_radius_multiplier",
	"shared_alert_radius_multiplier",
]
const AI_FLOAT_FIELDS: Array[String] = [
	"alert_share_delay_seconds",
	"flank_pair_chance",
	"suppressive_fire_chance",
	"regroup_seconds",
]


static func load_catalog(
	resource_path: String = CATALOG_PATH,
	mission_resource_path: String = MISSION_CATALOG_PATH,
) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var catalog := json.data as Dictionary
	var mission_catalog: Dictionary = MISSION_DATA_SCRIPT.load_catalog(mission_resource_path)
	if mission_catalog.is_empty() or not validate_catalog(catalog, mission_catalog).is_empty():
		return {}
	return catalog


static func load_mission_plan(
	mission_id: String,
	resource_path: String = CATALOG_PATH,
	mission_resource_path: String = MISSION_CATALOG_PATH,
) -> Dictionary:
	var catalog := load_catalog(resource_path, mission_resource_path)
	for raw_plan: Variant in catalog.get("missions", []) as Array:
		var plan := raw_plan as Dictionary
		if str(plan.get("id", "")) == mission_id:
			return plan.duplicate(true) as Dictionary
	return {}


static func validate_catalog(catalog: Dictionary, mission_catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(catalog.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("mission direction schema_version must be %d" % SCHEMA_VERSION)
		return errors
	var provenance: Variant = catalog.get("provenance")
	if not provenance is Dictionary:
		errors.append("mission direction provenance is missing")
	elif bool((provenance as Dictionary).get("original_dialogue_claimed", true)):
		errors.append("unverified original dialogue must not be claimed")

	var raw_plans: Variant = catalog.get("missions")
	var raw_missions: Variant = mission_catalog.get("missions")
	if not raw_plans is Array or not raw_missions is Array:
		errors.append("mission direction and mission catalogs must contain arrays")
		return errors
	if int(catalog.get("mission_count", -1)) != (raw_plans as Array).size():
		errors.append("mission direction mission_count does not match its array")
	if (raw_plans as Array).size() != (raw_missions as Array).size():
		errors.append("mission direction must cover every recovered mission")
		return errors

	var mission_by_id: Dictionary = {}
	for raw_mission: Variant in raw_missions as Array:
		if raw_mission is Dictionary:
			mission_by_id[str((raw_mission as Dictionary).get("id", ""))] = raw_mission
	var seen_plan_ids: Dictionary = {}
	for index: int in range((raw_plans as Array).size()):
		var raw_plan: Variant = (raw_plans as Array)[index]
		if not raw_plan is Dictionary:
			errors.append("mission direction entry %d is not an object" % index)
			continue
		var plan := raw_plan as Dictionary
		var mission_id := str(plan.get("id", ""))
		if mission_id.is_empty() or seen_plan_ids.has(mission_id):
			errors.append("mission direction entry %d has an empty or duplicate id" % index)
			continue
		seen_plan_ids[mission_id] = true
		if not mission_by_id.has(mission_id):
			errors.append("%s does not exist in missions.json" % mission_id)
			continue
		var mission := mission_by_id[mission_id] as Dictionary
		if str(plan.get("title", "")) != str(mission.get("title", "")):
			errors.append("%s title does not match missions.json" % mission_id)
		_validate_plan(plan, mission, errors)
	return errors


static func _validate_plan(
	plan: Dictionary,
	mission: Dictionary,
	errors: PackedStringArray,
) -> void:
	var mission_id := str(plan.get("id", ""))
	_validate_difficulty(mission_id, plan.get("difficulty"), errors)
	_validate_ai_cooperation(mission_id, plan.get("ai_cooperation"), errors)

	var raw_beats: Variant = plan.get("beats")
	if not raw_beats is Array or (raw_beats as Array).size() < 3:
		errors.append("%s must define at least three direction beats" % mission_id)
		return
	var objective_ids: Dictionary = {}
	for raw_objective: Variant in mission.get("objectives", []) as Array:
		objective_ids[str((raw_objective as Dictionary).get("id", ""))] = true
	var bindings := mission.get("scene_bindings", {}) as Dictionary
	var beat_ids: Dictionary = {}
	var tutorial_ids: Dictionary = {}
	var required_tutorial_ids: Array[String] = []
	var coverage := {"dialogue": false, "camera": false, "tutorial": false, "ai": false}
	var has_start := false
	var has_victory := false

	for raw_beat: Variant in raw_beats as Array:
		if not raw_beat is Dictionary:
			errors.append("%s contains a non-object direction beat" % mission_id)
			continue
		var beat := raw_beat as Dictionary
		var beat_id := str(beat.get("id", ""))
		var context := "%s/%s" % [mission_id, beat_id]
		if beat_id.is_empty() or beat_ids.has(beat_id):
			errors.append("%s has an empty or duplicate beat id" % mission_id)
			continue
		beat_ids[beat_id] = true
		if str(beat.get("source_status", "")) not in BEAT_SOURCE_STATUSES:
			errors.append("%s has an invalid source_status" % context)
		var trigger_event := _validate_trigger(context, beat.get("trigger"), objective_ids, bindings, errors)
		has_start = has_start or trigger_event == "mission_started"
		has_victory = has_victory or trigger_event == "victory"
		if beat.has("dialogue"):
			coverage["dialogue"] = true
			_validate_dialogue(context, beat["dialogue"], errors)
		if beat.has("camera"):
			coverage["camera"] = true
			_validate_camera(context, beat["camera"], bindings, errors)
		if beat.has("tutorial"):
			coverage["tutorial"] = true
			var tutorial_id := _validate_tutorial(context, beat["tutorial"], errors)
			if not tutorial_id.is_empty():
				if tutorial_ids.has(tutorial_id):
					errors.append("%s repeats tutorial id %s" % [mission_id, tutorial_id])
				tutorial_ids[tutorial_id] = true
		if beat.has("ai_directive"):
			coverage["ai"] = true
			_validate_ai_directive(context, beat["ai_directive"], errors)
		var raw_requirements: Variant = beat.get("requires_tutorials", [])
		if not raw_requirements is Array:
			errors.append("%s requires_tutorials must be an array" % context)
		else:
			for raw_requirement: Variant in raw_requirements as Array:
				if not raw_requirement is String or str(raw_requirement).is_empty():
					errors.append("%s has an invalid tutorial requirement" % context)
				else:
					required_tutorial_ids.append(str(raw_requirement))

	if not has_start or not has_victory:
		errors.append("%s must include mission_started and victory beats" % mission_id)
	for category: String in coverage:
		if not bool(coverage[category]):
			errors.append("%s has no %s coverage" % [mission_id, category])
	for tutorial_id: String in required_tutorial_ids:
		if not tutorial_ids.has(tutorial_id):
			errors.append("%s requires unknown tutorial %s" % [mission_id, tutorial_id])


static func _validate_difficulty(
	mission_id: String,
	raw_profile: Variant,
	errors: PackedStringArray,
) -> void:
	if not raw_profile is Dictionary:
		errors.append("%s has no difficulty profile" % mission_id)
		return
	var profile := raw_profile as Dictionary
	if str(profile.get("source_status", "")) != EDITORIAL_SOURCE:
		errors.append("%s difficulty must be labelled remake_editorial" % mission_id)
	for field: String in DIFFICULTY_FLOAT_FIELDS:
		if not _is_number(profile.get(field)) or float(profile[field]) < 0.25 or float(profile[field]) > 3.0:
			errors.append("%s difficulty %s is outside 0.25..3.0" % [mission_id, field])
	for field: String in ["reinforcement_budget", "max_simultaneous_attackers"]:
		if not _is_nonnegative_integer(profile.get(field)):
			errors.append("%s difficulty %s must be a nonnegative integer" % [mission_id, field])
	if int(profile.get("max_simultaneous_attackers", 0)) <= 0:
		errors.append("%s must allow at least one simultaneous attacker" % mission_id)


static func _validate_ai_cooperation(
	mission_id: String,
	raw_profile: Variant,
	errors: PackedStringArray,
) -> void:
	if not raw_profile is Dictionary:
		errors.append("%s has no AI cooperation profile" % mission_id)
		return
	var profile := raw_profile as Dictionary
	if str(profile.get("source_status", "")) != EDITORIAL_SOURCE:
		errors.append("%s AI cooperation must be labelled remake_editorial" % mission_id)
	for field: String in AI_FLOAT_FIELDS:
		if not _is_number(profile.get(field)) or float(profile[field]) < 0.0:
			errors.append("%s AI %s must be a nonnegative number" % [mission_id, field])
	for field: String in ["flank_pair_chance", "suppressive_fire_chance"]:
		if float(profile.get(field, -1.0)) > 1.0:
			errors.append("%s AI %s must not exceed 1.0" % [mission_id, field])
	if not _is_nonnegative_integer(profile.get("search_group_size")) or int(profile.get("search_group_size", 0)) <= 0:
		errors.append("%s AI search_group_size must be a positive integer" % mission_id)
	if str(profile.get("reinforcement_trigger", "")).is_empty():
		errors.append("%s AI reinforcement_trigger is empty" % mission_id)
	if not _is_unique_nonempty_string_array(profile.get("tags")):
		errors.append("%s AI tags must be unique nonempty strings" % mission_id)


static func _validate_trigger(
	context: String,
	raw_trigger: Variant,
	objective_ids: Dictionary,
	bindings: Dictionary,
	errors: PackedStringArray,
) -> String:
	if not raw_trigger is Dictionary:
		errors.append("%s has no trigger" % context)
		return ""
	var trigger := raw_trigger as Dictionary
	var event_name := str(trigger.get("event", ""))
	if event_name not in TRIGGER_EVENTS:
		errors.append("%s uses unknown trigger event %s" % [context, event_name])
		return event_name
	var where: Variant = trigger.get("where", {})
	if not where is Dictionary:
		errors.append("%s trigger where must be an object" % context)
		return event_name
	if event_name in ["objective_completed", "objective_progress"]:
		var objective_id := str((where as Dictionary).get("objective_id", ""))
		if not objective_ids.has(objective_id):
			errors.append("%s trigger references unknown objective %s" % [context, objective_id])
	if event_name == "objective_progress" and (
		not _is_nonnegative_integer((where as Dictionary).get("count"))
		or int((where as Dictionary).get("count", 0)) <= 0
	):
		errors.append("%s objective_progress must have a positive count" % context)
	if event_name == "story_anchor_reached":
		var role_id := str((where as Dictionary).get("role_id", ""))
		if not bindings.has(role_id):
			errors.append("%s trigger references unknown story binding %s" % [context, role_id])
	if event_name == "elapsed_seconds" and (
		not _is_number(trigger.get("at_seconds")) or float(trigger.get("at_seconds", 0.0)) <= 0.0
	):
		errors.append("%s elapsed trigger needs positive at_seconds" % context)
	return event_name


static func _validate_dialogue(
	context: String,
	raw_dialogue: Variant,
	errors: PackedStringArray,
) -> void:
	if not raw_dialogue is Dictionary:
		errors.append("%s dialogue must be an object" % context)
		return
	var dialogue := raw_dialogue as Dictionary
	if str(dialogue.get("source_status", "")) != EDITORIAL_SOURCE:
		errors.append("%s unverified dialogue must be labelled remake_editorial" % context)
	if str(dialogue.get("sequence_id", "")).is_empty():
		errors.append("%s dialogue has no sequence_id" % context)
	if not _is_number(dialogue.get("line_gap_seconds")) or float(dialogue.get("line_gap_seconds", -1.0)) < 0.0:
		errors.append("%s dialogue line_gap_seconds is invalid" % context)
	var raw_lines: Variant = dialogue.get("lines")
	if not raw_lines is Array or (raw_lines as Array).is_empty():
		errors.append("%s dialogue has no lines" % context)
		return
	for raw_line: Variant in raw_lines as Array:
		if not raw_line is Dictionary:
			errors.append("%s dialogue contains a non-object line" % context)
			continue
		var line := raw_line as Dictionary
		if str(line.get("text", "")).strip_edges().is_empty():
			errors.append("%s dialogue contains an empty line" % context)
		if not _is_number(line.get("minimum_seconds")) or float(line.get("minimum_seconds", -1.0)) < 0.0:
			errors.append("%s dialogue minimum_seconds is invalid" % context)
		if not line.get("auto_advance") is bool:
			errors.append("%s dialogue auto_advance must be boolean" % context)


static func _validate_camera(
	context: String,
	raw_camera: Variant,
	bindings: Dictionary,
	errors: PackedStringArray,
) -> void:
	if not raw_camera is Dictionary:
		errors.append("%s camera must be an object" % context)
		return
	var camera := raw_camera as Dictionary
	var mode := str(camera.get("mode", ""))
	if mode not in CAMERA_MODES:
		errors.append("%s camera mode is invalid" % context)
	if str(camera.get("source_status", "")) not in CAMERA_SOURCE_STATUSES:
		errors.append("%s camera source_status is invalid" % context)
	if not _is_number(camera.get("duration_seconds")) or float(camera.get("duration_seconds", 0.0)) <= 0.0:
		errors.append("%s camera duration must be positive" % context)
	if not _is_number(camera.get("zoom")) or float(camera.get("zoom", 0.0)) < 0.25 or float(camera.get("zoom", 0.0)) > 4.0:
		errors.append("%s camera zoom is outside 0.25..4.0" % context)
	if mode == "focus_binding":
		var binding := str(camera.get("binding", ""))
		if not bindings.has(binding):
			errors.append("%s camera references unknown binding %s" % [context, binding])
		if str(camera.get("source_status", "")) == "remake_editorial":
			errors.append("%s binding-derived camera must disclose recovered scene binding" % context)
	if camera.has("selection") and str(camera["selection"]) not in CAMERA_SELECTIONS:
		errors.append("%s camera selection is invalid" % context)


static func _validate_tutorial(
	context: String,
	raw_tutorial: Variant,
	errors: PackedStringArray,
) -> String:
	if not raw_tutorial is Dictionary:
		errors.append("%s tutorial must be an object" % context)
		return ""
	var tutorial := raw_tutorial as Dictionary
	var tutorial_id := str(tutorial.get("id", ""))
	if tutorial_id.is_empty() or str(tutorial.get("text", "")).strip_edges().is_empty():
		errors.append("%s tutorial id/text is empty" % context)
	if str(tutorial.get("source_status", "")) != EDITORIAL_SOURCE:
		errors.append("%s tutorial must be labelled remake_editorial" % context)
	var gate_mode := str(tutorial.get("gate_mode", ""))
	if gate_mode not in ["observe_action", "acknowledge"]:
		errors.append("%s tutorial gate_mode is invalid" % context)
	if gate_mode == "observe_action" and str(tutorial.get("completion_action", "")).is_empty():
		errors.append("%s observed tutorial has no completion_action" % context)
	if not tutorial.get("blocking") is bool:
		errors.append("%s tutorial blocking must be boolean" % context)
	return tutorial_id


static func _validate_ai_directive(
	context: String,
	raw_directive: Variant,
	errors: PackedStringArray,
) -> void:
	if not raw_directive is Dictionary:
		errors.append("%s AI directive must be an object" % context)
		return
	var directive := raw_directive as Dictionary
	if str(directive.get("kind", "")) not in AI_DIRECTIVE_KINDS:
		errors.append("%s AI directive kind is invalid" % context)
	if not directive.has("value"):
		errors.append("%s AI directive has no value" % context)
	if str(directive.get("source_status", "")) != EDITORIAL_SOURCE:
		errors.append("%s AI directive must be labelled remake_editorial" % context)


static func difficulty_for_mode(profile: Dictionary, mode: String) -> Dictionary:
	var result := profile.duplicate(true) as Dictionary
	var factor := 1.0
	match mode:
		"easy":
			factor = 0.85
		"hard":
			factor = 1.15
		"normal":
			factor = 1.0
		_:
			return {}
	result["enemy_health_multiplier"] = float(profile.get("enemy_health_multiplier", 1.0)) * factor
	result["enemy_damage_multiplier"] = float(profile.get("enemy_damage_multiplier", 1.0)) * factor
	result["patrol_speed_multiplier"] = float(profile.get("patrol_speed_multiplier", 1.0)) * lerpf(1.0, factor, 0.45)
	result["sense_radius_multiplier"] = float(profile.get("sense_radius_multiplier", 1.0)) * lerpf(1.0, factor, 0.40)
	result["shared_alert_radius_multiplier"] = float(profile.get("shared_alert_radius_multiplier", 1.0)) * lerpf(1.0, factor, 0.60)
	# Higher reaction-time and aim-error multipliers make enemies less lethal, so
	# their global difficulty scaling is deliberately inverted.
	result["reaction_time_multiplier"] = float(profile.get("reaction_time_multiplier", 1.0)) / factor
	result["aim_error_multiplier"] = float(profile.get("aim_error_multiplier", 1.0)) / factor
	var budget := int(profile.get("reinforcement_budget", 0))
	result["reinforcement_budget"] = maxi(0, roundi(float(budget) * factor))
	result["difficulty_mode"] = mode
	return result


static func apply_enemy_scalars(
	base_health: int,
	base_damage: float,
	base_reaction_seconds: float,
	profile: Dictionary,
) -> Dictionary:
	return {
		"health": maxi(1, roundi(float(base_health) * float(profile.get("enemy_health_multiplier", 1.0)))),
		"damage": maxf(0.0, base_damage * float(profile.get("enemy_damage_multiplier", 1.0))),
		"reaction_seconds": maxf(0.01, base_reaction_seconds * float(profile.get("reaction_time_multiplier", 1.0))),
		"aim_error_multiplier": maxf(0.0, float(profile.get("aim_error_multiplier", 1.0))),
		"patrol_speed_multiplier": maxf(0.0, float(profile.get("patrol_speed_multiplier", 1.0))),
		"sense_radius_multiplier": maxf(0.0, float(profile.get("sense_radius_multiplier", 1.0))),
		"shared_alert_radius_multiplier": maxf(0.0, float(profile.get("shared_alert_radius_multiplier", 1.0))),
	}


static func _is_unique_nonempty_string_array(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty():
		return false
	var seen: Dictionary = {}
	for raw_value: Variant in value as Array:
		if not raw_value is String or str(raw_value).is_empty() or seen.has(raw_value):
			return false
		seen[raw_value] = true
	return true


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		return float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))
	return false
