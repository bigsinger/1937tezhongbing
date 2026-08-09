class_name EnemyDutyController
extends RefCounted

var anchor := Vector2.ZERO
var patrol_index := 0
var active := false

func capture(position: Vector2, index: int) -> void:
	anchor = position
	patrol_index = maxi(index, 0)
	active = true

func clear() -> void:
	active = false

func snapshot() -> Dictionary:
	return {"active": active, "x": anchor.x, "y": anchor.y, "patrol_index": patrol_index}

func restore(state: Dictionary) -> bool:
	if state.is_empty():
		clear()
		return false
	active = bool(state.get("active", false))
	anchor = Vector2(
		float(state.get("x", 0.0)),
		float(state.get("y", 0.0)),
	)
	patrol_index = maxi(int(state.get("patrol_index", 0)), 0)
	return true
