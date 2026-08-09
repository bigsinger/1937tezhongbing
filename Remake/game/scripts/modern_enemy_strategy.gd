class_name ModernEnemyStrategy
extends RefCounted

var actor_id := -1
var blackboard: RefCounted
var awareness_state := "patrol"
var suspicion_ratio := 0.0
var last_known_position := Vector2.ZERO
var memory_ticks_remaining := 0
var assigned_search_sector: Dictionary = {}
var hearing_radius := 0.0
var current_visibility_band := "none"


func configure(new_actor_id: int, evidence_blackboard: RefCounted, new_hearing_radius: float) -> void:
	actor_id = new_actor_id
	blackboard = evidence_blackboard
	hearing_radius = maxf(new_hearing_radius, 0.0)


func synchronize(
	state: String,
	suspicion: float,
	known_position: Vector2,
	memory_seconds: float,
	visibility_band: String = "none",
) -> void:
	awareness_state = state
	suspicion_ratio = clampf(suspicion, 0.0, 1.0)
	last_known_position = known_position
	memory_ticks_remaining = maxi(roundi(memory_seconds * 60.0), 0)
	current_visibility_band = visibility_band
	if blackboard != null and blackboard.has_method("search_assignment"):
		assigned_search_sector = blackboard.call("search_assignment", actor_id)


func public_snapshot() -> Dictionary:
	return {
		"awareness_state": awareness_state,
		"suspicion_ratio": suspicion_ratio,
		"last_known_position": last_known_position,
		"memory_ticks_remaining": memory_ticks_remaining,
		"assigned_search_sector": assigned_search_sector.duplicate(true),
		"hearing_radius": hearing_radius,
		"current_visibility_band": current_visibility_band,
	}
