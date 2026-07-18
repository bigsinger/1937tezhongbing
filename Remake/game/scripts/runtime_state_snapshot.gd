class_name RuntimeStateSnapshot
extends RefCounted

## Produces stable, content-addressed snapshots for deterministic replay checks.
## The snapshot contains simulation state only: wall-clock time, node instance IDs,
## rendering objects, and source asset paths are deliberately excluded.

const SCHEMA_VERSION := 1
const HASH_ALGORITHM := HashingContext.HASH_SHA256

const COMBATANT_FIELDS: Array[String] = [
	"scene_index",
	"display_name",
	"faction_id",
	"position",
	"target_position",
	"is_alive",
	"current_hit_points",
	"maximum_hit_points",
	"combat_action",
	"action_frame_index",
	"action_finished",
	"magazine_ammo",
	"reserve_ammo",
	"infinite_ammo",
]


static func capture(
	combatants: Array = [],
	mission_state: RefCounted = null,
	mission_runtime: Node = null,
	replay_cursor: int = -1,
) -> Dictionary:
	var combat_records: Array[Dictionary] = []
	for combatant: Variant in combatants:
		combat_records.append(_capture_combatant(combatant))
	combat_records.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return canonical_text(first) < canonical_text(second)
	)

	var snapshot := {
		"schema_version": SCHEMA_VERSION,
		"replay_cursor": replay_cursor,
		"combatants": combat_records,
		"mission": _capture_mission(mission_state, mission_runtime),
	}
	return snapshot


static func snapshot_hash(snapshot: Dictionary) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HASH_ALGORITHM) != OK:
		return ""
	if hashing.update(canonical_text(snapshot).to_utf8_buffer()) != OK:
		return ""
	return hashing.finish().hex_encode()


static func verify_replay(
	events: Array,
	context_factory: Callable,
	event_applier: Callable,
	snapshot_reader: Callable,
	context_disposer: Callable = Callable(),
) -> Dictionary:
	if (
		not context_factory.is_valid()
		or not event_applier.is_valid()
		or not snapshot_reader.is_valid()
	):
		return {
			"is_deterministic": false,
			"divergence_index": -1,
			"final_hash": "",
			"baseline_hashes": [],
			"replay_hashes": [],
			"errors": ["replay callbacks must be valid"],
		}

	var baseline := _run_replay_pass(
		events, context_factory, event_applier, snapshot_reader, context_disposer
	)
	var replay := _run_replay_pass(
		events, context_factory, event_applier, snapshot_reader, context_disposer
	)
	var baseline_hashes := baseline["hashes"] as Array
	var replay_hashes := replay["hashes"] as Array
	var divergence_index := _first_divergence(baseline_hashes, replay_hashes)
	var errors: Array[String] = []
	for raw_error: Variant in baseline["errors"] as Array:
		errors.append("baseline: %s" % str(raw_error))
	for raw_error: Variant in replay["errors"] as Array:
		errors.append("replay: %s" % str(raw_error))
	var final_hash := ""
	if not baseline_hashes.is_empty():
		final_hash = str(baseline_hashes.back())
	return {
		"is_deterministic": errors.is_empty() and divergence_index < 0,
		"divergence_index": divergence_index,
		"final_hash": final_hash,
		"baseline_hashes": baseline_hashes,
		"replay_hashes": replay_hashes,
		"errors": errors,
	}


static func canonical_text(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "bool:%s" % ("true" if bool(value) else "false")
		TYPE_INT:
			return "int:%d" % int(value)
		TYPE_FLOAT:
			return "float:%s" % String.num(float(value), 17)
		TYPE_STRING, TYPE_STRING_NAME:
			return "string:%s" % JSON.stringify(str(value))
		TYPE_VECTOR2:
			var point := value as Vector2
			return "vector2:(%s,%s)" % [
				String.num(point.x, 17),
				String.num(point.y, 17),
			]
		TYPE_VECTOR2I:
			var cell := value as Vector2i
			return "vector2i:(%d,%d)" % [cell.x, cell.y]
		TYPE_ARRAY:
			var items := PackedStringArray()
			for item: Variant in value as Array:
				items.append(canonical_text(item))
			return "array:[%s]" % ",".join(items)
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			var fields := PackedStringArray()
			var keys: Array = dictionary.keys()
			keys.sort_custom(
				func(first: Variant, second: Variant) -> bool:
					return canonical_text(first) < canonical_text(second)
			)
			for key: Variant in keys:
				fields.append(
					"%s=%s" % [canonical_text(key), canonical_text(dictionary[key])]
				)
			return "dictionary:{%s}" % ",".join(fields)
		_:
			return "variant:%d:%s" % [typeof(value), var_to_str(value)]


static func _run_replay_pass(
	events: Array,
	context_factory: Callable,
	event_applier: Callable,
	snapshot_reader: Callable,
	context_disposer: Callable,
) -> Dictionary:
	var hashes: Array[String] = []
	var errors: Array[String] = []
	var context: Variant = context_factory.call()
	if context == null:
		errors.append("context factory returned null")
		return {"hashes": hashes, "errors": errors}

	var initial: Variant = snapshot_reader.call(context, 0)
	if not initial is Dictionary:
		errors.append("snapshot reader returned a non-dictionary at cursor 0")
	else:
		hashes.append(snapshot_hash(initial as Dictionary))

	if errors.is_empty():
		for event_index: int in range(events.size()):
			var event: Variant = events[event_index]
			var apply_result: Variant = event_applier.call(context, event)
			if apply_result is bool and not bool(apply_result):
				errors.append("event %d was rejected" % event_index)
				break
			if apply_result is String and not str(apply_result).is_empty():
				errors.append("event %d: %s" % [event_index, str(apply_result)])
				break
			var snapshot: Variant = snapshot_reader.call(context, event_index + 1)
			if not snapshot is Dictionary:
				errors.append(
					"snapshot reader returned a non-dictionary at cursor %d"
					% (event_index + 1)
				)
				break
			hashes.append(snapshot_hash(snapshot as Dictionary))

	if context_disposer.is_valid():
		context_disposer.call(context)
	return {"hashes": hashes, "errors": errors}


static func _capture_combatant(combatant: Variant) -> Dictionary:
	var record: Dictionary = {}
	for field: String in COMBATANT_FIELDS:
		if _has_field(combatant, field):
			record[field] = _read_field(combatant, field)
	if _has_field(combatant, "weapon_profile"):
		var profile: Variant = _read_field(combatant, "weapon_profile")
		if profile is Dictionary:
			record["attack_type"] = int((profile as Dictionary).get("attack_type", 0))
	if combatant is Object and (combatant as Object).has_method("inventory_snapshot"):
		var inventory: Variant = (combatant as Object).call("inventory_snapshot")
		if inventory is Dictionary and not (inventory as Dictionary).is_empty():
			record["inventory"] = inventory
	if not record.has("display_name") and combatant is Node:
		record["display_name"] = str((combatant as Node).name)
	return record


static func _capture_mission(mission_state: RefCounted, mission_runtime: Node) -> Dictionary:
	if mission_state == null:
		return {}
	var mission_definition: Variant = _read_field(mission_state, "mission")
	var mission_id := ""
	if mission_definition is Dictionary:
		mission_id = str((mission_definition as Dictionary).get("id", ""))
	var result := {
		"mission_id": mission_id,
		"completed": _read_field(mission_state, "completed", {}),
		"progress": _read_field(mission_state, "progress", {}),
		"seen_values": _read_field(mission_state, "seen_values", {}),
		"elapsed_seconds": _read_field(mission_state, "elapsed_seconds", 0.0),
		"failure_id": _read_field(mission_state, "failure_id", ""),
		"victory": false,
	}
	if mission_state.has_method("is_victory"):
		result["victory"] = bool(mission_state.call("is_victory"))
	if mission_runtime != null and mission_runtime.has_method("durable_fact_count"):
		result["durable_fact_count"] = int(mission_runtime.call("durable_fact_count"))
	return result


static func _has_field(source: Variant, field: String) -> bool:
	if source is Dictionary:
		return (source as Dictionary).has(field)
	if not source is Object:
		return false
	for property: Dictionary in (source as Object).get_property_list():
		if str(property.get("name", "")) == field:
			return true
	return false


static func _read_field(source: Variant, field: String, default_value: Variant = null) -> Variant:
	if source is Dictionary:
		return (source as Dictionary).get(field, default_value)
	if _has_field(source, field):
		return (source as Object).get(field)
	return default_value


static func _first_divergence(first: Array, second: Array) -> int:
	var common_size := mini(first.size(), second.size())
	for index: int in range(common_size):
		if first[index] != second[index]:
			return index
	if first.size() != second.size():
		return common_size
	return -1
