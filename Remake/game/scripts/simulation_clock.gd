class_name SimulationClock
extends RefCounted

const TICK_RATE := 60
const FIXED_DELTA := 1.0 / float(TICK_RATE)
const MAX_CATCH_UP_TICKS := 8
const EPSILON_SECONDS := 0.000000001

var tick := 0
var paused := false
var accumulator_seconds := 0.0
var dropped_time_seconds := 0.0


func add_time(delta_seconds: float, catch_up_limit: int = MAX_CATCH_UP_TICKS) -> int:
	if paused or delta_seconds <= 0.0:
		return 0
	accumulator_seconds += delta_seconds
	var available := floori(
		(accumulator_seconds + EPSILON_SECONDS) / FIXED_DELTA
	)
	if available <= 0:
		return 0
	var consumed := mini(available, maxi(catch_up_limit, 1))
	accumulator_seconds = maxf(
		accumulator_seconds - float(consumed) * FIXED_DELTA,
		0.0,
	)
	if available > consumed:
		var dropped_ticks := available - consumed
		dropped_time_seconds += float(dropped_ticks) * FIXED_DELTA
		accumulator_seconds = fmod(accumulator_seconds, FIXED_DELTA)
	tick += consumed
	return consumed


func step_exact(count: int = 1) -> int:
	if paused or count <= 0:
		return 0
	tick += count
	return count


func seconds_to_ticks(seconds: float) -> int:
	return maxi(0, roundi(maxf(seconds, 0.0) * float(TICK_RATE)))


func ticks_to_seconds(ticks: int) -> float:
	return float(maxi(ticks, 0)) * FIXED_DELTA


func set_paused(value: bool) -> void:
	paused = value


func reset(new_tick: int = 0) -> void:
	tick = maxi(new_tick, 0)
	accumulator_seconds = 0.0
	dropped_time_seconds = 0.0


func capture_state() -> Dictionary:
	return {
		"schema_version": 1,
		"tick_rate": TICK_RATE,
		"tick": tick,
		"paused": paused,
		"accumulator_seconds": accumulator_seconds,
		"dropped_time_seconds": dropped_time_seconds,
	}


func restore_state(state: Dictionary) -> bool:
	if (
		int(state.get("schema_version", 0)) != 1
		or int(state.get("tick_rate", 0)) != TICK_RATE
		or int(state.get("tick", -1)) < 0
	):
		return false
	tick = int(state["tick"])
	paused = bool(state.get("paused", false))
	accumulator_seconds = clampf(
		float(state.get("accumulator_seconds", 0.0)),
		0.0,
		FIXED_DELTA,
	)
	dropped_time_seconds = maxf(
		float(state.get("dropped_time_seconds", 0.0)),
		0.0,
	)
	return true
