class_name EnemyTacticalFeedbackPresenter
extends RefCounted

var _last_signature := ""

func should_present(snapshot: Dictionary, observed: bool, hovered: bool, engaged: bool) -> bool:
	return observed or hovered or engaged or str(snapshot.get("awareness_state", "patrol")) not in ["patrol", "classic"]

func changed(snapshot: Dictionary) -> bool:
	var signature := "%s|%d|%d|%s" % [
		str(snapshot.get("awareness_state", "")),
		roundi(float(snapshot.get("suspicion_ratio", 0.0)) * 20.0),
		roundi(float(snapshot.get("memory_ticks_remaining", 0)) / 30.0),
		str(snapshot.get("current_visibility_band", "")),
	]
	if signature == _last_signature:
		return false
	_last_signature = signature
	return true
