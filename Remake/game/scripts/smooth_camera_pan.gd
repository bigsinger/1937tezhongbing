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
	vertical_margin: float = -1.0,
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
	var safe_horizontal_margin := clampf(
		margin,
		1.0,
		maxf(1.0, viewport_size.x * 0.25),
	)
	var safe_vertical_margin := clampf(
		vertical_margin if vertical_margin > 0.0 else margin,
		1.0,
		maxf(1.0, viewport_size.y * 0.25),
	)
	var intent := Vector2.ZERO
	if mouse_position.x < safe_horizontal_margin:
		intent.x = -(1.0 - mouse_position.x / safe_horizontal_margin)
	elif mouse_position.x > viewport_size.x - safe_horizontal_margin:
		intent.x = (
			mouse_position.x - (viewport_size.x - safe_horizontal_margin)
		) / safe_horizontal_margin
	if mouse_position.y < safe_vertical_margin:
		intent.y = -(1.0 - mouse_position.y / safe_vertical_margin)
	elif mouse_position.y > viewport_size.y - safe_vertical_margin:
		intent.y = (
			mouse_position.y - (viewport_size.y - safe_vertical_margin)
		) / safe_vertical_margin
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


static func retain_edge_intent(
	previous_intent: Vector2,
	time_without_edge: float,
	grace_seconds: float,
) -> Vector2:
	if previous_intent.is_zero_approx() or grace_seconds <= 0.0:
		return Vector2.ZERO
	var remaining := 1.0 - clampf(
		maxf(time_without_edge, 0.0) / grace_seconds,
		0.0,
		1.0,
	)
	if remaining <= 0.0:
		return Vector2.ZERO
	# A short eased tail masks one-frame edge loss caused by window borders and
	# the top edge of the bottom HUD. It does not move or confine the pointer.
	return previous_intent * _smoothstep(remaining)


static func _smoothstep(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)
