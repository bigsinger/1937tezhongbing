class_name ClassicEnemyStrategy
extends RefCounted

var awareness_state := "classic"
var suspicion_ratio := 0.0
var last_known_position := Vector2.ZERO
var memory_ticks_remaining := 0
var hearing_radius := 0.0
var current_visibility_band := "legacy"


func synchronize(
	state: String,
	suspicion: float,
	known_position: Vector2,
	memory_seconds: float,
	visibility_band: String = "none",
) -> void:
	# This is a read-only presentation mirror. It never feeds decisions back to
	# the recovered classic AI state machine.
	awareness_state = state
	suspicion_ratio = clampf(suspicion, 0.0, 1.0)
	last_known_position = known_position
	memory_ticks_remaining = maxi(roundi(memory_seconds * 60.0), 0)
	current_visibility_band = visibility_band


func configure_hearing(radius: float) -> void:
	hearing_radius = maxf(radius, 0.0)


func public_snapshot() -> Dictionary:
	return {
		"awareness_state": awareness_state,
		"suspicion_ratio": suspicion_ratio,
		"last_known_position": last_known_position,
		"memory_ticks_remaining": memory_ticks_remaining,
		"assigned_search_sector": {},
		"hearing_radius": hearing_radius,
		"current_visibility_band": current_visibility_band,
	}
