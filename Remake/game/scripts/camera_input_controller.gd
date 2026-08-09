class_name CameraInputController
extends RefCounted

const ACCELERATION_SECONDS := 0.12
const DECELERATION_SECONDS := 0.10

var velocity := Vector2.ZERO


func reset() -> void:
	velocity = Vector2.ZERO


func advance(
	delta: float,
	direction: Vector2,
	speed: float,
	zoom: float,
	reduce_motion: bool,
) -> Vector2:
	var normalized_direction := direction
	if normalized_direction.length_squared() > 1.0:
		normalized_direction = normalized_direction.normalized()
	var target := normalized_direction * maxf(speed, 0.0) / maxf(zoom, 0.001)
	if reduce_motion:
		velocity = target
	else:
		var response := ACCELERATION_SECONDS if not target.is_zero_approx() else DECELERATION_SECONDS
		var blend := 1.0 - exp(-maxf(delta, 0.0) / maxf(response, 0.001))
		velocity = velocity.lerp(target, blend)
		if target.is_zero_approx() and velocity.length_squared() < 0.01:
			velocity = Vector2.ZERO
	return velocity * maxf(delta, 0.0)


func clamp_position(position: Vector2, bounds: Rect2, half_view: Vector2) -> Vector2:
	var minimum := bounds.position + half_view
	var maximum := bounds.end - half_view
	if minimum.x > maximum.x:
		minimum.x = bounds.get_center().x
		maximum.x = minimum.x
	if minimum.y > maximum.y:
		minimum.y = bounds.get_center().y
		maximum.y = minimum.y
	return Vector2(
		clampf(position.x, minimum.x, maximum.x),
		clampf(position.y, minimum.y, maximum.y),
	)


func snapshot() -> Dictionary:
	return {"velocity": velocity}
