class_name CampaignProgress
extends RefCounted

## Canonical campaign completion state for the twelve formal missions.
##
## The stable MOD launcher deliberately exposes all twelve missions through
## its SDK route table.  That free-selection path is separate from this state:
## merely starting a mission never records completion.  Product victories use
## record_victory(), while command-line/developer level selection remains free.

const FORMAL_LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]


static func default_state() -> Dictionary:
	return {
		"highest_unlocked_level_id": FORMAL_LEVEL_IDS[0],
		"completed_level_ids": [],
	}


static func is_valid_level_id(level_id: String) -> bool:
	return FORMAL_LEVEL_IDS.has(level_id)


static func is_valid_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state := value as Dictionary
	if not is_valid_level_id(str(state.get("highest_unlocked_level_id", ""))):
		return false
	var completed_value: Variant = state.get("completed_level_ids", [])
	if not completed_value is Array:
		return false
	for level_value: Variant in completed_value as Array:
		if not is_valid_level_id(str(level_value)):
			return false
	return true


static func normalize(value: Variant) -> Dictionary:
	if not is_valid_state(value):
		return default_state()
	var state := value as Dictionary
	var completed: Array[String] = []
	var highest_index := FORMAL_LEVEL_IDS.find(
		str(state.get("highest_unlocked_level_id", FORMAL_LEVEL_IDS[0]))
	)
	highest_index = maxi(highest_index, 0)
	for level_value: Variant in state.get("completed_level_ids", []) as Array:
		var level_id := str(level_value)
		if not completed.has(level_id):
			completed.append(level_id)
		var completed_index := FORMAL_LEVEL_IDS.find(level_id)
		if completed_index >= 0:
			highest_index = maxi(
				highest_index,
				mini(completed_index + 1, FORMAL_LEVEL_IDS.size() - 1),
			)
	completed.sort_custom(
		func(first: String, second: String) -> bool:
			return FORMAL_LEVEL_IDS.find(first) < FORMAL_LEVEL_IDS.find(second)
	)
	return {
		"highest_unlocked_level_id": FORMAL_LEVEL_IDS[highest_index],
		"completed_level_ids": completed,
	}


static func record_victory(value: Variant, level_id: String) -> Dictionary:
	var state := normalize(value)
	if not is_valid_level_id(level_id):
		return state
	var completed := state["completed_level_ids"] as Array
	if not completed.has(level_id):
		completed.append(level_id)
	var completed_index := FORMAL_LEVEL_IDS.find(level_id)
	var highest_index := FORMAL_LEVEL_IDS.find(
		str(state["highest_unlocked_level_id"])
	)
	state["highest_unlocked_level_id"] = FORMAL_LEVEL_IDS[
		maxi(
			highest_index,
			mini(completed_index + 1, FORMAL_LEVEL_IDS.size() - 1),
		)
	]
	state["completed_level_ids"] = completed
	return normalize(state)


static func is_unlocked(value: Variant, level_id: String) -> bool:
	if not is_valid_level_id(level_id):
		return false
	var state := normalize(value)
	return (
		FORMAL_LEVEL_IDS.find(level_id)
		<= FORMAL_LEVEL_IDS.find(str(state["highest_unlocked_level_id"]))
	)


static func completion_count(value: Variant) -> int:
	return (normalize(value)["completed_level_ids"] as Array).size()
