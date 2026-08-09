class_name ActorAnimationController
extends RefCounted

const BASE_SPRITE_TICK_SECONDS := 0.085
const MOVEMENT_MIN_FRAME_SECONDS := 1.0 / 18.0
const MOVEMENT_MAX_FRAME_SECONDS := 0.14
const ORIGINAL_MOVEMENT_TICKS_PER_SECOND := 60.0


static func action_frame_seconds(group: Dictionary) -> float:
	return BASE_SPRITE_TICK_SECONDS * maxi(int(group.get("frame_hold_ticks", 1)), 1)


static func movement_frame_seconds(group: Dictionary, speed: float) -> float:
	var hold_ticks := maxi(int(group.get("frame_hold_ticks", 1)), 1)
	var secondary_value: Variant = group.get("secondary_triplet", [])
	var stride := Vector2.ZERO
	if secondary_value is Array and (secondary_value as Array).size() >= 3:
		stride = Vector2(
			absf(float((secondary_value as Array)[0])),
			absf(float((secondary_value as Array)[2])),
		)
	var safe_speed := maxf(speed, 0.001)
	var seconds := (
		stride.length() * float(hold_ticks) / safe_speed
		if not stride.is_zero_approx()
		else float(hold_ticks) / ORIGINAL_MOVEMENT_TICKS_PER_SECOND
	)
	return clampf(seconds, MOVEMENT_MIN_FRAME_SECONDS, MOVEMENT_MAX_FRAME_SECONDS)


static func advance_frame(
	frame_index: int,
	elapsed: float,
	delta: float,
	frame_seconds: float,
	frame_count: int,
) -> Dictionary:
	var safe_count := maxi(frame_count, 1)
	var safe_seconds := maxf(frame_seconds, 0.001)
	var next_elapsed := elapsed + maxf(delta, 0.0)
	var next_index := clampi(frame_index, 0, safe_count - 1)
	var changed := false
	while next_elapsed >= safe_seconds:
		next_elapsed -= safe_seconds
		next_index = (next_index + 1) % safe_count
		changed = true
	return {"index": next_index, "elapsed": next_elapsed, "changed": changed}


static func snapshot(frame_index: int, elapsed: float, group_index: int) -> Dictionary:
	return {
		"frame_index": maxi(frame_index, 0),
		"elapsed": maxf(elapsed, 0.0),
		"group_index": clampi(group_index, 0, 7),
	}
