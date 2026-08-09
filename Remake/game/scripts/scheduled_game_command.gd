class_name ScheduledGameCommand
extends RefCounted

const FAILURE_SKIP := "skip"
const FAILURE_WAIT := "wait"
const FAILURE_ABORT_QUEUE := "abort_queue"
const FAILURE_POLICIES: Array[String] = [
	FAILURE_SKIP,
	FAILURE_WAIT,
	FAILURE_ABORT_QUEUE,
]

var sequence := 0
var execute_tick := 0
var actor_id := -1
var name := ""
var source := "gameplay"
var payload: Dictionary = {}
var precondition: Dictionary = {}
var timeout_tick := -1
var failure_policy := FAILURE_SKIP


static func create(
	new_sequence: int,
	new_execute_tick: int,
	new_name: String,
	new_payload: Dictionary = {},
	new_source: String = "gameplay",
	new_actor_id: int = -1,
	new_precondition: Dictionary = {},
	new_timeout_tick: int = -1,
	new_failure_policy: String = FAILURE_SKIP,
) -> ScheduledGameCommand:
	var command := ScheduledGameCommand.new()
	command.sequence = maxi(new_sequence, 0)
	command.execute_tick = maxi(new_execute_tick, 0)
	command.name = normalize_name(new_name)
	command.source = normalize_name(new_source)
	command.actor_id = new_actor_id
	command.payload = new_payload.duplicate(true)
	command.precondition = new_precondition.duplicate(true)
	command.timeout_tick = new_timeout_tick
	command.failure_policy = (
		new_failure_policy
		if new_failure_policy in FAILURE_POLICIES
		else FAILURE_SKIP
	)
	return command


func is_valid() -> bool:
	return sequence > 0 and execute_tick >= 0 and not name.is_empty()


func to_dictionary() -> Dictionary:
	return {
		"sequence": sequence,
		"execute_tick": execute_tick,
		"actor_id": actor_id,
		"name": name,
		"source": source,
		"payload": payload.duplicate(true),
		"precondition": precondition.duplicate(true),
		"timeout_tick": timeout_tick,
		"failure_policy": failure_policy,
	}


static func from_dictionary(value: Dictionary) -> ScheduledGameCommand:
	return create(
		int(value.get("sequence", 0)),
		int(value.get("execute_tick", -1)),
		str(value.get("name", "")),
		value.get("payload", {}) as Dictionary,
		str(value.get("source", "gameplay")),
		int(value.get("actor_id", -1)),
		value.get("precondition", {}) as Dictionary,
		int(value.get("timeout_tick", -1)),
		str(value.get("failure_policy", FAILURE_SKIP)),
	)


static func normalize_name(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_")
