class_name MovementReservationService
extends RefCounted

const PRIORITY_PLAYER_DANGER := 600
const PRIORITY_PLAYER_COMMAND := 500
const PRIORITY_COMBAT := 400
const PRIORITY_MISSION := 300
const PRIORITY_LEADER := 200
const PRIORITY_FOLLOWER := 100
const PRIORITY_PATROL := 50
const WAIT_AGE_CAP := 240
const POSITION_QUANTUM := 8.0
const CORRIDOR_BATCH_LIMIT := 3
const SORT_ACTOR_ID_MASK := 0xffffffff
const SORT_EFFECTIVE_PRIORITY_CEILING := 0x7fffffff

var _tick := 0
var _proposals: Dictionary = {}
var _decisions: Dictionary = {}
var _proposal_list: Array[Dictionary] = []
var _proposal_order_keys := PackedInt64Array()
var _ordered_proposals: Array[Dictionary] = []
var _proposal_sort_requires_fallback := false
var _decision_cache: Dictionary = {}
var _claimed_positions: Dictionary = {}
var _claimed_edges: Dictionary = {}
var _wait_age: Dictionary = {}
var _corridor_direction: Dictionary = {}
var _conflict_count := 0
var _accepted_count := 0
var _denied_count := 0
var _maximum_wait_age := 0


func begin_tick(simulation_tick: int) -> void:
	_tick = maxi(simulation_tick, 0)
	_proposals.clear()
	_decisions.clear()
	_proposal_list.clear()
	_proposal_order_keys.clear()
	_ordered_proposals.clear()
	_proposal_sort_requires_fallback = false


func propose(
	actor_id: int,
	current_position: Vector2,
	preferred_position: Vector2,
	priority: int,
	alternatives_value: Variant = null,
	bottleneck_id: String = "",
	direction: Vector2 = Vector2.ZERO,
) -> bool:
	if actor_id < 0 or _proposals.has(actor_id):
		return false
	var safe_alternatives: Array[Vector2] = []
	if alternatives_value is Array or alternatives_value is PackedVector2Array:
		for alternative_value: Variant in alternatives_value:
			if not alternative_value is Vector2:
				continue
			var alternative := alternative_value as Vector2
			if not alternative.is_equal_approx(preferred_position):
				safe_alternatives.append(alternative)
	return propose_typed(
		actor_id,
		current_position,
		preferred_position,
		priority,
		safe_alternatives,
		bottleneck_id,
		direction,
	)


func propose_typed(
	actor_id: int,
	current_position: Vector2,
	preferred_position: Vector2,
	priority: int,
	alternatives: Array[Vector2] = [],
	bottleneck_id: String = "",
	direction: Vector2 = Vector2.ZERO,
) -> bool:
	return propose_record(
		actor_id,
		{
			"current": current_position,
			"preferred": preferred_position,
			"alternatives": alternatives,
		},
		priority,
		bottleneck_id,
		direction,
	)


## Production actors retain one proposal record and two lateral candidates.
## Reusing them removes hundreds of short-lived Dictionary/Array allocations
## per second without exposing internal service-owned state to callers.
func propose_record(
	actor_id: int,
	proposal: Dictionary,
	priority: int,
	bottleneck_id: String = "",
	direction: Vector2 = Vector2.ZERO,
) -> bool:
	if actor_id < 0 or _proposals.has(actor_id):
		return false
	proposal["actor_id"] = actor_id
	proposal["priority"] = priority
	proposal["wait_age"] = int(_wait_age.get(actor_id, 0))
	proposal["bottleneck_id"] = bottleneck_id
	proposal["direction_sign"] = _direction_sign(direction)
	_proposals[actor_id] = proposal
	_proposal_list.append(proposal)
	if actor_id <= SORT_ACTOR_ID_MASK:
		# Pack descending effective priority and ascending actor id into one
		# native-sortable integer. Array.sort_custom() invoked a GDScript callback
		# hundreds of times at each 10 Hz arbitration boundary on dense missions.
		var effective_priority := clampi(
			priority + int(proposal["wait_age"]),
			0,
			SORT_EFFECTIVE_PRIORITY_CEILING,
		)
		_proposal_order_keys.append(
			(
				(SORT_EFFECTIVE_PRIORITY_CEILING - effective_priority)
				<< 32
			) | actor_id
		)
	else:
		# Extremely long-lived synthetic sessions can eventually allocate an
		# instance id wider than 32 bits. Preserve the general public API with the
		# original comparator for that rare diagnostic case.
		_proposal_sort_requires_fallback = true
	return true


func resolve() -> Dictionary:
	return _resolve_internal().duplicate(true)


## Main consumes all decisions synchronously before begin_tick() clears them.
## Returning the owned view avoids a deep copy of every candidate/decision at
## 15 Hz; external tools and tests retain the defensive-copy resolve() API.
func resolve_view() -> Dictionary:
	return _resolve_internal()


func _resolve_internal() -> Dictionary:
	_ordered_proposals.clear()
	if _proposal_sort_requires_fallback:
		_proposal_list.sort_custom(_proposal_precedes)
		_ordered_proposals.append_array(_proposal_list)
	else:
		_proposal_order_keys.sort()
		for packed_key: int in _proposal_order_keys:
			var ordered_actor_id := int(packed_key & SORT_ACTOR_ID_MASK)
			var proposal_value: Variant = _proposals.get(ordered_actor_id)
			if proposal_value is Dictionary:
				_ordered_proposals.append(proposal_value as Dictionary)
	_claimed_positions.clear()
	_claimed_edges.clear()
	for proposal: Dictionary in _ordered_proposals:
		var actor_id := int(proposal["actor_id"])
		var alternatives := proposal["alternatives"] as Array[Vector2]
		var current_position := proposal["current"] as Vector2
		var current_position_key := _position_key(current_position)
		var accepted_position := current_position
		var granted := false
		if _corridor_direction_allows(proposal):
			for candidate_index: int in range(alternatives.size() + 1):
				var candidate := (
					proposal["preferred"] as Vector2
					if candidate_index == 0
					else alternatives[candidate_index - 1]
				)
				var position_key := _position_key(candidate)
				# Current and candidate quantization is shared by both directed
				# edges. The former generic helper quantized the same endpoints five
				# times per candidate, dominating dense 10 Hz arbitration windows.
				var forward_edge := Vector4i(
					current_position_key.x,
					current_position_key.y,
					position_key.x,
					position_key.y,
				)
				var reverse_edge := Vector4i(
					position_key.x,
					position_key.y,
					current_position_key.x,
					current_position_key.y,
				)
				if (
					_claimed_positions.has(position_key)
					or _claimed_edges.has(reverse_edge)
				):
					continue
				_claimed_positions[position_key] = actor_id
				_claimed_edges[forward_edge] = actor_id
				accepted_position = candidate
				granted = true
				break
		if granted:
			_wait_age[actor_id] = 0
			_accepted_count += 1
			_accept_corridor_direction(proposal)
		else:
			var age := mini(int(_wait_age.get(actor_id, 0)) + 1, WAIT_AGE_CAP)
			_wait_age[actor_id] = age
			_maximum_wait_age = maxi(_maximum_wait_age, age)
			_denied_count += 1
			_conflict_count += 1
		var decision_value: Variant = _decision_cache.get(actor_id)
		var decision: Dictionary = (
			decision_value as Dictionary
			if decision_value is Dictionary
			else {}
		)
		decision["granted"] = granted
		decision["position"] = accepted_position
		decision["wait_age"] = int(_wait_age[actor_id])
		decision["tick"] = _tick
		_decision_cache[actor_id] = decision
		_decisions[actor_id] = decision
	_release_idle_corridors()
	return _decisions


func decision(actor_id: int) -> Dictionary:
	var value: Variant = _decisions.get(actor_id)
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {"granted": true, "tick": _tick, "wait_age": 0}
	)


func remove_actor(actor_id: int) -> void:
	_proposals.erase(actor_id)
	_decisions.erase(actor_id)
	_decision_cache.erase(actor_id)
	_wait_age.erase(actor_id)


func clear() -> void:
	_tick = 0
	_proposals.clear()
	_decisions.clear()
	_proposal_list.clear()
	_proposal_order_keys.clear()
	_ordered_proposals.clear()
	_proposal_sort_requires_fallback = false
	_decision_cache.clear()
	_claimed_positions.clear()
	_claimed_edges.clear()
	_wait_age.clear()
	_corridor_direction.clear()
	_conflict_count = 0
	_accepted_count = 0
	_denied_count = 0
	_maximum_wait_age = 0


func capture_state() -> Dictionary:
	return {
		"schema_version": 1,
		"tick": _tick,
		"wait_age": _wait_age.duplicate(true),
		"corridor_direction": _corridor_direction.duplicate(true),
	}


func restore_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != 1:
		return false
	var wait_value: Variant = state.get("wait_age", {})
	var corridor_value: Variant = state.get("corridor_direction", {})
	if not wait_value is Dictionary or not corridor_value is Dictionary:
		return false
	_tick = maxi(int(state.get("tick", 0)), 0)
	_wait_age.clear()
	for raw_key: Variant in (wait_value as Dictionary).keys():
		_wait_age[int(raw_key)] = clampi(
			int((wait_value as Dictionary)[raw_key]),
			0,
			WAIT_AGE_CAP,
		)
	_corridor_direction = (corridor_value as Dictionary).duplicate(true)
	_proposals.clear()
	_decisions.clear()
	_proposal_list.clear()
	_proposal_order_keys.clear()
	_ordered_proposals.clear()
	_proposal_sort_requires_fallback = false
	_claimed_positions.clear()
	_claimed_edges.clear()
	return true


func stats() -> Dictionary:
	return {
		"tick": _tick,
		"proposal_count": _proposals.size(),
		"accepted": _accepted_count,
		"denied": _denied_count,
		"conflicts": _conflict_count,
		"maximum_wait_age": _maximum_wait_age,
		"tracked_waiters": _wait_age.size(),
		"active_corridors": _corridor_direction.size(),
	}


func conflict_count() -> int:
	return _conflict_count


func _corridor_direction_allows(proposal: Dictionary) -> bool:
	var bottleneck_id := str(proposal["bottleneck_id"])
	var direction_sign := int(proposal["direction_sign"])
	if bottleneck_id.is_empty() or direction_sign == 0:
		return true
	var state_value: Variant = _corridor_direction.get(bottleneck_id, {})
	if not state_value is Dictionary:
		return true
	var current := int((state_value as Dictionary).get("direction", 0))
	return current == 0 or current == direction_sign


func _accept_corridor_direction(proposal: Dictionary) -> void:
	var bottleneck_id := str(proposal["bottleneck_id"])
	var direction_sign := int(proposal["direction_sign"])
	if not bottleneck_id.is_empty() and direction_sign != 0:
		var state_value: Variant = _corridor_direction.get(bottleneck_id, {})
		var state := state_value as Dictionary if state_value is Dictionary else {}
		if int(state.get("direction", 0)) != direction_sign:
			state = {"direction": direction_sign, "served": 0}
		state["served"] = int(state.get("served", 0)) + 1
		if int(state["served"]) >= CORRIDOR_BATCH_LIMIT:
			_corridor_direction.erase(bottleneck_id)
		else:
			_corridor_direction[bottleneck_id] = state


func _release_idle_corridors() -> void:
	if _corridor_direction.is_empty():
		return
	var active: Dictionary = {}
	for proposal: Dictionary in _proposal_list:
		var bottleneck_id := str(proposal["bottleneck_id"])
		if not bottleneck_id.is_empty():
			active[bottleneck_id] = true
	for raw_id: Variant in _corridor_direction.keys():
		if not active.has(str(raw_id)):
			_corridor_direction.erase(raw_id)


static func _proposal_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_effective := int(left["priority"]) + int(left["wait_age"])
	var right_effective := int(right["priority"]) + int(right["wait_age"])
	if left_effective != right_effective:
		return left_effective > right_effective
	return int(left["actor_id"]) < int(right["actor_id"])


static func _position_key(position: Vector2) -> Vector2i:
	return Vector2i(
		roundi(position.x / POSITION_QUANTUM),
		roundi(position.y / POSITION_QUANTUM),
	)


static func _edge_key(from: Vector2, to: Vector2) -> Vector4i:
	var from_key := _position_key(from)
	var to_key := _position_key(to)
	return Vector4i(from_key.x, from_key.y, to_key.x, to_key.y)


static func _direction_sign(direction: Vector2) -> int:
	if direction.is_zero_approx():
		return 0
	if absf(direction.x) >= absf(direction.y):
		return 1 if direction.x >= 0.0 else -1
	return 2 if direction.y >= 0.0 else -2
