class_name RuntimeFrameClassifier
extends RefCounted

const HOST_SCHEDULER_MINIMUM_INTERVAL_MS := 75.0
const HOST_SCHEDULER_MINIMUM_CATCHUP_TICKS := 3
const HOST_SCHEDULER_MAXIMUM_ACCOUNTED_MS := 40.0
const HOST_SCHEDULER_MAXIMUM_ACCOUNTED_RATIO := 0.35


## Distinguishes a game-owned long frame from a host scheduling preemption.
##
## When Windows suspends the process, the next rendered frame contains several
## fixed-physics catch-up ticks even though Godot reports little CPU work. That
## wall-clock interruption must remain visible in telemetry, but attributing it
## to gameplay would make a ten-minute gate nondeterministic under background
## antivirus/desktop activity. Any substantial path query keeps the frame in the
## game-owned lane, as do ordinary one/two-tick overruns.
static func is_host_scheduler_preemption(
	frame_interval_ms: float,
	process_ms: float,
	physics_process_ms: float,
	path_query_ms: float,
	physics_frames_advanced: int,
) -> bool:
	if (
		frame_interval_ms < HOST_SCHEDULER_MINIMUM_INTERVAL_MS
		or physics_frames_advanced < HOST_SCHEDULER_MINIMUM_CATCHUP_TICKS
	):
		return false
	var accounted_ms := maxf(
		maxf(process_ms, 0.0) + maxf(physics_process_ms, 0.0),
		maxf(process_ms, 0.0) + maxf(path_query_ms, 0.0),
	)
	return (
		accounted_ms <= HOST_SCHEDULER_MAXIMUM_ACCOUNTED_MS
		and accounted_ms
			<= frame_interval_ms * HOST_SCHEDULER_MAXIMUM_ACCOUNTED_RATIO
	)
