class_name SaveGameController
extends RefCounted

## Selects the newest checkpoint that is safe to restore in the active runtime.
## Slot summaries are an index only. Every candidate is loaded through
## GameSaveStore so primary/backup recovery, migration and validation remain
## identical to a manual load.

const CHECKPOINT_PREFIX := "checkpoint_"
const PROFILE_KEYS: Array[String] = [
	"ruleset_mode",
	"difficulty_mode",
	"mission_rule_mode",
	"content_identity",
]

var _cached_key := ""
var _cached_result: Dictionary = {}


func invalidate() -> void:
	_cached_key = ""
	_cached_result.clear()


func latest_compatible_checkpoint(
	save_store: RefCounted,
	level_id: String,
	runtime_profile: Dictionary,
) -> Dictionary:
	if save_store == null or level_id.is_empty():
		return _failure("save_store_unavailable")
	var cache_key := "%s|%s" % [level_id, JSON.stringify(runtime_profile)]
	if cache_key == _cached_key and not _cached_result.is_empty():
		return _cached_result.duplicate(true)

	var candidates: Array[Dictionary] = []
	for raw_summary: Variant in save_store.call("list_slots"):
		if not raw_summary is Dictionary:
			continue
		var summary := raw_summary as Dictionary
		if (
			str(summary.get("slot_id", "")).begins_with(CHECKPOINT_PREFIX)
			and str(summary.get("level_id", "")) == level_id
		):
			candidates.append(summary.duplicate(true))
	candidates.sort_custom(_summary_is_newer)

	var rejected: Array[Dictionary] = []
	for summary: Dictionary in candidates:
		var slot_id := str(summary.get("slot_id", ""))
		var loaded: Dictionary = save_store.call("load_slot", slot_id)
		if not bool(loaded.get("ok", false)):
			rejected.append({"slot_id": slot_id, "reason": str(loaded.get("code", "invalid"))})
			continue
		var document := loaded.get("data", {}) as Dictionary
		var session := document.get("session", {}) as Dictionary
		var saved_profile := session.get("runtime_profile", {}) as Dictionary
		var mismatch := _profile_mismatch(saved_profile, runtime_profile)
		if not mismatch.is_empty():
			rejected.append({"slot_id": slot_id, "reason": mismatch})
			continue
		var result := {
			"ok": true,
			"slot_id": slot_id,
			"recovered": bool(loaded.get("recovered", false)),
			"saved_at_unix_msec": int(summary.get("saved_at_unix_msec", 0)),
			"rejected": rejected,
		}
		_cached_key = cache_key
		_cached_result = result.duplicate(true)
		return result

	var failure := _failure("no_compatible_checkpoint")
	failure["rejected"] = rejected
	_cached_key = cache_key
	_cached_result = failure.duplicate(true)
	return failure


func _profile_mismatch(saved: Dictionary, active: Dictionary) -> String:
	for key: String in PROFILE_KEYS:
		var active_value := str(active.get(key, ""))
		if not active_value.is_empty() and str(saved.get(key, "")) != active_value:
			return "profile_mismatch:%s" % key
	return ""


func _summary_is_newer(first: Dictionary, second: Dictionary) -> bool:
	var first_time := int(first.get("saved_at_unix_msec", 0))
	var second_time := int(second.get("saved_at_unix_msec", 0))
	if first_time != second_time:
		return first_time > second_time
	var first_revision := int(first.get("revision", 0))
	var second_revision := int(second.get("revision", 0))
	if first_revision != second_revision:
		return first_revision > second_revision
	return str(first.get("slot_id", "")) < str(second.get("slot_id", ""))


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "slot_id": "", "recovered": false}
