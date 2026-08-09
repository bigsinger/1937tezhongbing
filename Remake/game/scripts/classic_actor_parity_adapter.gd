class_name ClassicActorParityAdapter
extends RefCounted

const CLASSIC_FIELDS: Array[String] = [
	"original_runtime_index",
	"original_native_actor_state",
	"original_command_goal_kind_latch",
	"original_first_gameplay_movement_path_state",
	"original_first_gameplay_movement_mode",
]


func capture(actor: Object) -> Dictionary:
	var result: Dictionary = {}
	for field: String in CLASSIC_FIELDS:
		var value: Variant = actor.get(field)
		result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func restore(actor: Object, snapshot: Dictionary) -> void:
	for field: String in CLASSIC_FIELDS:
		if snapshot.has(field):
			var value: Variant = snapshot[field]
			if field == "original_native_actor_state":
				if value is Dictionary:
					actor.set(field, (value as Dictionary).duplicate(true))
				continue
			actor.set(field, int(value))


func classic_only(ruleset_mode: String) -> bool:
	return ruleset_mode == "classic"
