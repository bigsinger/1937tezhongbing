extends Node

## Connects validated world events to a MissionState without giving world systems
## direct write access to mission progress. The runtime deliberately has no
## class_name or preload dependency so it also parses in a clean Godot cache.

signal state_changed
signal objective_completed(objective_id: String)
signal victory
signal failed(failure_id: String)

const DURABLE_EVENTS: Dictionary = {
	"entity_rescued": true,
	"item_acquired": true,
	"role_eliminated": true,
	"story_anchor_reached": true,
	"area_hostiles_cleared": true,
}
const TRANSIENT_EVENTS: Dictionary = {
	"party_at_trigger": true,
	"time_expired": true,
}
const SCENE_BOUND_EVENTS: Dictionary = {
	"entity_rescued": true,
	"item_acquired": true,
	"role_eliminated": true,
	"story_anchor_reached": true,
	"trigger_activated": true,
	"party_at_trigger": true,
}
const SCENE_REFERENCE_FIELDS: Array[String] = [
	"scene_index",
	"source_scene_index",
	"trigger_scene_index",
]
const FACT_IDENTITY_FIELDS: Array[String] = [
	"scene_index",
	"source_scene_index",
	"trigger_scene_index",
	"role_id",
	"item_role",
	"item_name",
	"display_name",
	"family_role",
	"area_role",
]
const DURABLE_TRIGGER_BINDINGS: Dictionary = {
	"explosion": true,
	"high_ground": true,
}
const EXPECTED_ANCHOR_KIND_BY_BINDING: Dictionary = {
	"explosion": "explosion_detector",
	"exit": "exit_detector",
	"high_ground": "exit_detector",
}

var mission_definition: Dictionary = {}
var imported_level: Dictionary = {}
var mission_state: RefCounted
var last_error := ""

var _configured := false
var _known_scene_indices: Dictionary = {}
var _anchor_kind_by_scene: Dictionary = {}
var _binding_kinds_by_scene: Dictionary = {}
var _binding_scenes_by_kind: Dictionary = {}
var _durable_facts: Array[Dictionary] = []
var _durable_fact_keys: Dictionary = {}
var _applied_fact_objectives: Dictionary = {}
var _reported_victory := false
var _reported_failure_id := ""


func configure(
	new_mission_definition: Dictionary,
	new_imported_level: Dictionary,
	new_mission_state: RefCounted,
) -> bool:
	_reset()
	if new_mission_definition.is_empty():
		return _reject("mission definition is empty")
	if new_imported_level.is_empty():
		return _reject("imported level is empty")
	if new_mission_state == null:
		return _reject("mission state is null")
	for required_method: String in [
		"record_event",
		"advance_time",
		"is_objective_complete",
		"is_failed",
		"is_victory",
	]:
		if not new_mission_state.has_method(required_method):
			return _reject("mission state is missing method: %s" % required_method)

	var known_scene_indices: Dictionary = {}
	var anchor_kind_by_scene: Dictionary = {}
	if not _index_level_scenes(
		new_imported_level, known_scene_indices, anchor_kind_by_scene
	):
		return false

	var binding_kinds_by_scene: Dictionary = {}
	var binding_scenes_by_kind: Dictionary = {}
	if not _index_scene_bindings(
		new_mission_definition,
		known_scene_indices,
		anchor_kind_by_scene,
		binding_kinds_by_scene,
		binding_scenes_by_kind,
	):
		return false

	mission_definition = new_mission_definition.duplicate(true) as Dictionary
	imported_level = new_imported_level
	mission_state = new_mission_state
	_known_scene_indices = known_scene_indices
	_anchor_kind_by_scene = anchor_kind_by_scene
	_binding_kinds_by_scene = binding_kinds_by_scene
	_binding_scenes_by_kind = binding_scenes_by_kind
	_reported_victory = bool(mission_state.call("is_victory"))
	if bool(mission_state.call("is_failed")):
		_reported_failure_id = str(mission_state.get("failure_id"))
	_configured = true
	last_error = ""
	return true


func is_configured() -> bool:
	return _configured


func publish_world_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
	var completed_ids: Array[String] = []
	if not _configured:
		_reject("mission runtime is not configured")
		return completed_ids
	if event_name.is_empty():
		_reject("event name is empty")
		return completed_ids
	if event_name == "time_expired":
		_reject("time_expired must be produced by advance_time")
		return completed_ids
	if not _validate_event_scene_bindings(event_name, payload):
		return completed_ids

	last_error = ""
	var before_signature := _state_signature()
	if _is_durable_event(event_name, payload):
		var fact_key := _fact_key(event_name, payload)
		if not _durable_fact_keys.has(fact_key):
			_durable_fact_keys[fact_key] = true
			_durable_facts.append(
				{
					"key": fact_key,
					"event_name": event_name,
					"payload": payload.duplicate(true),
				}
			)
		completed_ids = _replay_durable_facts()
	else:
		completed_ids = _record_state_event(event_name, payload)
		completed_ids.append_array(_replay_durable_facts())
	completed_ids = _unique_strings(completed_ids)
	_emit_changes(before_signature, completed_ids)
	return completed_ids


func advance_time(delta_seconds: float) -> void:
	if not _configured or delta_seconds <= 0.0:
		return
	last_error = ""
	var before_signature := _state_signature()
	mission_state.call("advance_time", delta_seconds)
	_emit_changes(before_signature, [])


func binding_kinds_for_scene(scene_index: int) -> Array[String]:
	var result: Array[String] = []
	if not _binding_kinds_by_scene.has(scene_index):
		return result
	for binding_value: Variant in _binding_kinds_by_scene[scene_index] as Array:
		result.append(str(binding_value))
	return result


func bound_scenes(binding_kind: String) -> Array[int]:
	var result: Array[int] = []
	if not _binding_scenes_by_kind.has(binding_kind):
		return result
	for scene_value: Variant in _binding_scenes_by_kind[binding_kind] as Array:
		result.append(int(scene_value))
	return result


func durable_fact_count() -> int:
	return _durable_facts.size()


func _reset() -> void:
	# imported_level intentionally keeps the caller's large parsed dictionary by
	# reference. Drop that reference instead of clearing the caller's world data.
	mission_definition = {}
	imported_level = {}
	mission_state = null
	last_error = ""
	_configured = false
	_known_scene_indices = {}
	_anchor_kind_by_scene = {}
	_binding_kinds_by_scene = {}
	_binding_scenes_by_kind = {}
	_durable_facts = []
	_durable_fact_keys = {}
	_applied_fact_objectives = {}
	_reported_victory = false
	_reported_failure_id = ""


func _index_level_scenes(
	level: Dictionary,
	known_scene_indices: Dictionary,
	anchor_kind_by_scene: Dictionary,
) -> bool:
	var raw_entities: Variant = level.get("entities")
	var raw_anchors: Variant = level.get("task_anchors", [])
	if not raw_entities is Array:
		return _reject("imported level entities must be an array")
	if not raw_anchors is Array:
		return _reject("imported level task_anchors must be an array")

	for raw_entity: Variant in raw_entities as Array:
		if not raw_entity is Dictionary:
			return _reject("imported level contains a non-dictionary entity")
		var entity := raw_entity as Dictionary
		if not _has_nonnegative_integer(entity, "scene_index"):
			return _reject("imported entity has an invalid scene_index")
		known_scene_indices[int(entity["scene_index"])] = true

	for raw_anchor: Variant in raw_anchors as Array:
		if not raw_anchor is Dictionary:
			return _reject("imported level contains a non-dictionary task anchor")
		var anchor := raw_anchor as Dictionary
		if not _has_nonnegative_integer(anchor, "scene_index"):
			return _reject("task anchor has an invalid scene_index")
		var scene_index := int(anchor["scene_index"])
		var kind := str(anchor.get("kind", ""))
		if kind.is_empty():
			return _reject("task anchor %d has no kind" % scene_index)
		known_scene_indices[scene_index] = true
		anchor_kind_by_scene[scene_index] = kind
	return true


func _index_scene_bindings(
	definition: Dictionary,
	known_scene_indices: Dictionary,
	anchor_kind_by_scene: Dictionary,
	binding_kinds_by_scene: Dictionary,
	binding_scenes_by_kind: Dictionary,
) -> bool:
	var raw_bindings: Variant = definition.get("scene_bindings")
	if not raw_bindings is Dictionary or (raw_bindings as Dictionary).is_empty():
		return _reject("mission scene_bindings must be a non-empty dictionary")

	for raw_binding_kind: Variant in (raw_bindings as Dictionary).keys():
		var binding_kind := str(raw_binding_kind)
		var raw_scenes: Variant = (raw_bindings as Dictionary)[raw_binding_kind]
		if binding_kind.is_empty() or not raw_scenes is Array:
			return _reject("mission scene binding must have a name and an array value")
		var scenes: Array[int] = []
		var seen_scenes: Dictionary = {}
		for raw_scene: Variant in raw_scenes as Array:
			if not _is_nonnegative_integer(raw_scene):
				return _reject("binding %s contains an invalid scene index" % binding_kind)
			var scene_index := int(raw_scene)
			if not known_scene_indices.has(scene_index):
				return _reject(
					"binding %s references missing scene %d" % [binding_kind, scene_index]
				)
			if seen_scenes.has(scene_index):
				return _reject(
					"binding %s contains duplicate scene %d" % [binding_kind, scene_index]
				)
			if EXPECTED_ANCHOR_KIND_BY_BINDING.has(binding_kind):
				var expected_kind := str(EXPECTED_ANCHOR_KIND_BY_BINDING[binding_kind])
				if str(anchor_kind_by_scene.get(scene_index, "")) != expected_kind:
					return _reject(
						(
							"binding %s scene %d is not a %s"
							% [binding_kind, scene_index, expected_kind]
						)
					)
			seen_scenes[scene_index] = true
			scenes.append(scene_index)
			if not binding_kinds_by_scene.has(scene_index):
				binding_kinds_by_scene[scene_index] = []
			(binding_kinds_by_scene[scene_index] as Array).append(binding_kind)
		binding_scenes_by_kind[binding_kind] = scenes
	return true


func _validate_event_scene_bindings(event_name: String, payload: Dictionary) -> bool:
	var referenced_scenes: Array[int] = []
	for field: String in SCENE_REFERENCE_FIELDS:
		if not payload.has(field):
			continue
		var raw_scene: Variant = payload[field]
		if not _is_nonnegative_integer(raw_scene):
			return _reject("event %s has an invalid %s" % [event_name, field])
		referenced_scenes.append(int(raw_scene))

	if SCENE_BOUND_EVENTS.has(event_name) and referenced_scenes.is_empty():
		return _reject("event %s requires a bound scene reference" % event_name)
	for scene_index: int in referenced_scenes:
		if not _known_scene_indices.has(scene_index):
			return _reject(
				"event %s references scene %d outside the loaded level"
				% [event_name, scene_index]
			)
		if not _binding_kinds_by_scene.has(scene_index):
			return _reject(
				"event %s references unbound scene %d" % [event_name, scene_index]
			)
	return true


func _is_durable_event(event_name: String, payload: Dictionary) -> bool:
	if DURABLE_EVENTS.has(event_name):
		return true
	if TRANSIENT_EVENTS.has(event_name) or event_name != "trigger_activated":
		return false
	for scene_index: int in _scene_references(payload):
		for binding_kind: String in binding_kinds_for_scene(scene_index):
			if DURABLE_TRIGGER_BINDINGS.has(binding_kind):
				return true
	return false


func _scene_references(payload: Dictionary) -> Array[int]:
	var scenes: Array[int] = []
	for field: String in SCENE_REFERENCE_FIELDS:
		if payload.has(field) and _is_nonnegative_integer(payload[field]):
			var scene_index := int(payload[field])
			if not scenes.has(scene_index):
				scenes.append(scene_index)
	return scenes


func _replay_durable_facts() -> Array[String]:
	var all_completed: Array[String] = []
	var made_progress := true
	while made_progress and not _state_is_terminal():
		made_progress = false
		for fact: Dictionary in _durable_facts:
			if _state_is_terminal():
				break
			var eligible_objectives := _eligible_objectives_for_fact(fact)
			if eligible_objectives.is_empty():
				continue
			var fact_key := str(fact["key"])
			for objective_id: String in eligible_objectives:
				_applied_fact_objectives[_fact_objective_key(fact_key, objective_id)] = true
			var completed := _record_state_event(
				str(fact["event_name"]), fact["payload"] as Dictionary
			)
			if not completed.is_empty():
				made_progress = true
				all_completed.append_array(completed)
	return _unique_strings(all_completed)


func _eligible_objectives_for_fact(fact: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var fact_key := str(fact["key"])
	var event_name := str(fact["event_name"])
	var payload := fact["payload"] as Dictionary
	for raw_objective: Variant in mission_definition.get("objectives", []) as Array:
		if not raw_objective is Dictionary:
			continue
		var objective := raw_objective as Dictionary
		var objective_id := str(objective.get("id", ""))
		if objective_id.is_empty():
			continue
		if bool(mission_state.call("is_objective_complete", objective_id)):
			continue
		if _applied_fact_objectives.has(_fact_objective_key(fact_key, objective_id)):
			continue
		if not _objective_dependencies_complete(objective):
			continue
		var condition: Variant = objective.get("condition")
		if not condition is Dictionary:
			continue
		if str((condition as Dictionary).get("event", "")) != event_name:
			continue
		if not _payload_matches(condition as Dictionary, payload):
			continue
		result.append(objective_id)
	return result


func _objective_dependencies_complete(objective: Dictionary) -> bool:
	var dependencies: Variant = objective.get("depends_on", [])
	if not dependencies is Array:
		return false
	for dependency: Variant in dependencies as Array:
		if not bool(mission_state.call("is_objective_complete", str(dependency))):
			return false
	return true


static func _payload_matches(condition: Dictionary, payload: Dictionary) -> bool:
	var where: Variant = condition.get("where", {})
	if not where is Dictionary:
		return false
	for key: Variant in (where as Dictionary).keys():
		if not payload.has(key) or payload[key] != (where as Dictionary)[key]:
			return false
	return true


func _record_state_event(event_name: String, payload: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_result: Variant = mission_state.call("record_event", event_name, payload)
	if not raw_result is Array:
		return result
	for objective_value: Variant in raw_result as Array:
		result.append(str(objective_value))
	return result


func _emit_changes(before_signature: String, completed_ids: Array[String]) -> void:
	for objective_id: String in completed_ids:
		objective_completed.emit(objective_id)
	if before_signature != _state_signature():
		state_changed.emit()

	if bool(mission_state.call("is_failed")):
		var failure_id := str(mission_state.get("failure_id"))
		if not failure_id.is_empty() and failure_id != _reported_failure_id:
			_reported_failure_id = failure_id
			failed.emit(failure_id)
		return
	if bool(mission_state.call("is_victory")) and not _reported_victory:
		_reported_victory = true
		victory.emit()


func _state_is_terminal() -> bool:
	return (
		bool(mission_state.call("is_failed"))
		or bool(mission_state.call("is_victory"))
	)


func _state_signature() -> String:
	if mission_state == null:
		return ""
	return _canonical_value(
		{
			"completed": mission_state.get("completed"),
			"elapsed_seconds": mission_state.get("elapsed_seconds"),
			"failure_id": mission_state.get("failure_id"),
			"progress": mission_state.get("progress"),
		}
	)


func _fact_key(event_name: String, payload: Dictionary) -> String:
	# Combat context (killer, timestamp, damage roll, and so on) must not turn a
	# duplicate death or pickup callback into a second mission fact.
	var identity: Dictionary = {}
	for field: String in FACT_IDENTITY_FIELDS:
		if not payload.has(field):
			continue
		var value: Variant = payload[field]
		if field in SCENE_REFERENCE_FIELDS and _is_nonnegative_integer(value):
			identity[field] = int(value)
		else:
			identity[field] = value
	if identity.is_empty():
		identity = payload.duplicate(true) as Dictionary
	return "%s|%s" % [event_name, _canonical_value(identity)]


static func _fact_objective_key(fact_key: String, objective_id: String) -> String:
	return "%s|objective=%s" % [fact_key, objective_id]


static func _canonical_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary := value as Dictionary
		var keys: Array = dictionary.keys()
		keys.sort()
		var fields: PackedStringArray = []
		for key: Variant in keys:
			fields.append(
				"%s:%s" % [_canonical_value(key), _canonical_value(dictionary[key])]
			)
		return "{%s}" % ",".join(fields)
	if value is Array:
		var items: PackedStringArray = []
		for item: Variant in value as Array:
			items.append(_canonical_value(item))
		return "[%s]" % ",".join(items)
	return "%s:%s" % [typeof(value), str(value)]


static func _unique_strings(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for value: String in values:
		if seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result


static func _has_nonnegative_integer(source: Dictionary, field: String) -> bool:
	return source.has(field) and _is_nonnegative_integer(source[field])


static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		return float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))
	return false


func _reject(message: String) -> bool:
	last_error = message
	return false
