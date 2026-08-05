class_name ApplicationFocusPolicy
extends RefCounted

var owns_pause := false
var previous_paused := false


func on_focus_lost(
	enabled: bool,
	current_paused: bool,
	interactive_runtime: bool = true,
) -> Dictionary:
	if not enabled or not interactive_runtime or owns_pause:
		return {"apply": false, "paused": current_paused}
	previous_paused = current_paused
	owns_pause = true
	return {"apply": true, "paused": true}


func on_focus_gained(current_paused: bool) -> Dictionary:
	if not owns_pause:
		return {"apply": false, "paused": current_paused}
	var restored_paused := previous_paused
	owns_pause = false
	previous_paused = false
	return {"apply": true, "paused": restored_paused}


func reset() -> void:
	owns_pause = false
	previous_paused = false


func snapshot() -> Dictionary:
	return {
		"owns_pause": owns_pause,
		"previous_paused": previous_paused,
	}
