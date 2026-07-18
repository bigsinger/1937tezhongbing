class_name WorldDepth
extends RefCounted

## The recovered renderer used four queues: fixed background, Y-sorted world,
## fixed foreground and topmost. Godot has one finite CanvasItem z range, so
## known 0..4162 baselines are compressed into its middle band while the outer
## bands reproduce the original queue order.
const TERRAIN_Z := -4096
const BACKGROUND_Z := -3500
const NORMAL_MIN_Z := -3000
const NORMAL_MAX_Z := 3000
const FOREGROUND_Z := 3500
const TOPMOST_Z := 4000
const KNOWN_DEPTH_SCALE := 0.70


static func normal_z(world_baseline_y: float, bias: int = 0) -> int:
	return clampi(
		roundi(world_baseline_y * KNOWN_DEPTH_SCALE) + bias,
		NORMAL_MIN_Z,
		NORMAL_MAX_Z,
	)


static func imported_z(queue_id: int, reference_y: float) -> int:
	match queue_id:
		1:
			return BACKGROUND_Z
		2:
			return FOREGROUND_Z
		3:
			return TOPMOST_Z
		_:
			return normal_z(reference_y)
