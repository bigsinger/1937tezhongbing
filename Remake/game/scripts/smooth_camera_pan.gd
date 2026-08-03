class_name SmoothCameraPan
extends RefCounted

## Frame-rate-independent edge-pan controller.  It never captures, warps or
## confines the OS pointer; only the viewport-local position is sampled.

const DEFAULT_EDGE_MARGIN := 32.0
const ACCELERATION_RESPONSE := 11.0
const DECELERATION_RESPONSE := 15.0


static func edge_intent(
	mouse_position: Vector2,
	viewport_size: Vector2,
	margin: float = DEFAULT_EDGE_MARGIN,
) -> Vector2:
	if (
		viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or mouse_position.x < 0.0
		or mouse_position.y < 0.0
		or mouse_position.x >= viewport_size.x
		or mouse_position.y >= viewport_size.y
	):
		return Vector2.ZERO
	var safe_margin := clampf(
		margin,
		1.0,
		maxf(1.0, minf(viewport_size.x, viewport_size.y) * 0.25),
	)
	var intent := Vector2.ZERO
	if mouse_position.x < safe_margin:
		intent.x = -(1.0 - mouse_position.x / safe_margin)
	elif mouse_position.x > viewport_size.x - safe_margin:
		intent.x = (
			mouse_position.x - (viewport_size.x - safe_margin)
		) / safe_margin
	if mouse_position.y < safe_margin:
		intent.y = -(1.0 - mouse_position.y / safe_margin)
	elif mouse_position.y > viewport_size.y - safe_margin:
		intent.y = (
			mouse_position.y - (viewport_size.y - safe_margin)
		) / safe_margin
	# Smooth the spatial ramp itself so the inner edge of the activation band
	# has zero slope and does not produce a one-frame camera nudge.
	intent.x = signf(intent.x) * _smoothstep(absf(intent.x))
	intent.y = signf(intent.y) * _smoothstep(absf(intent.y))
	if intent.length_squared() > 1.0:
		intent = intent.normalized()
	return intent


static func advance_velocity(
	current_velocity: Vector2,
	target_velocity: Vector2,
	delta: float,
	reduce_motion: bool = false,
) -> Vector2:
	if reduce_motion:
		return target_velocity
	var response := (
		DECELERATION_RESPONSE
		if target_velocity.is_zero_approx()
		else ACCELERATION_RESPONSE
	)
	var blend := 1.0 - exp(-response * maxf(delta, 0.0))
	var next_velocity := current_velocity.lerp(target_velocity, blend)
	if target_velocity.is_zero_approx() and next_velocity.length_squared() < 0.01:
		return Vector2.ZERO
	return next_velocity


static func _smoothstep(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
