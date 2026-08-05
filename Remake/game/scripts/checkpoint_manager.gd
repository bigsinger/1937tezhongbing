class_name CheckpointManager
extends RefCounted

const SLOT_PREFIX := "checkpoint_"
const DEFAULT_SLOT_COUNT := 3
const DEFAULT_MINIMUM_INTERVAL_SECONDS := 4.0

var slot_count := DEFAULT_SLOT_COUNT
var minimum_interval_seconds := DEFAULT_MINIMUM_INTERVAL_SECONDS
var next_slot_index := 1
var last_saved_msec := -1
var last_reason := ""


func _init(
	new_slot_count: int = DEFAULT_SLOT_COUNT,
	new_minimum_interval_seconds: float = DEFAULT_MINIMUM_INTERVAL_SECONDS,
) -> void:
	slot_count = clampi(new_slot_count, 2, 10)
	minimum_interval_seconds = maxf(new_minimum_interval_seconds, 0.0)


func can_save(force: bool = false) -> bool:
	if force or last_saved_msec < 0:
		return true
	return (
		Time.get_ticks_msec() - last_saved_msec
		>= roundi(minimum_interval_seconds * 1000.0)
	)


func reserve_slot(reason: String, force: bool = false) -> String:
	if not can_save(force):
		return ""
	var slot_id := "%s%d" % [SLOT_PREFIX, next_slot_index]
	next_slot_index = next_slot_index % slot_count + 1
	last_saved_msec = Time.get_ticks_msec()
	last_reason = reason
	return slot_id


func restore_from_summaries(summaries: Array[Dictionary]) -> void:
	var newest_time := -1
	var newest_index := 0
	for summary: Dictionary in summaries:
		var slot_id := str(summary.get("slot_id", ""))
		if not slot_id.begins_with(SLOT_PREFIX):
			continue
		var index := int(slot_id.trim_prefix(SLOT_PREFIX))
		if index < 1 or index > slot_count:
			continue
		var saved_time := int(summary.get("saved_at_unix_msec", 0))
		if saved_time > newest_time:
			newest_time = saved_time
			newest_index = index
	if newest_index > 0:
		next_slot_index = newest_index % slot_count + 1


func snapshot() -> Dictionary:
	return {
		"slot_count": slot_count,
		"next_slot_index": next_slot_index,
		"last_saved_msec": last_saved_msec,
		"last_reason": last_reason,
	}
