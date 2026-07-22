class_name TacticalSenses
extends RefCounted

const ORIGINAL_DIRECTION_CENTERS: Array[float] = [
	45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 0.0,
]
const ORIGINAL_DIRECTION_HALF_ANGLES: Array[float] = [
	30.0, 45.0, 60.0, 45.0, 30.0, 45.0, 60.0, 45.0,
]


static func is_within_view_cone(
	observer_position: Vector2,
	facing_direction: Vector2,
	target_position: Vector2,
	view_distance: float,
	view_angle_degrees: float,
) -> bool:
	if view_distance <= 0.0 or view_angle_degrees <= 0.0:
		return false
	var to_target := target_position - observer_position
	if to_target.length_squared() > view_distance * view_distance:
		return false
	if to_target.is_zero_approx() or view_angle_degrees >= 360.0:
		return true
	if facing_direction.is_zero_approx():
		return false
	var half_angle_radians := deg_to_rad(clampf(view_angle_degrees, 0.0, 360.0) * 0.5)
	return facing_direction.normalized().dot(to_target.normalized()) >= cos(half_angle_radians)


static func can_see(
	navigation: Variant,
	observer_position: Vector2,
	facing_direction: Vector2,
	target_position: Vector2,
	view_distance: float,
	view_angle_degrees: float,
	ignored_scene_indices: Array = [],
) -> bool:
	if not is_within_view_cone(
		observer_position,
		facing_direction,
		target_position,
		view_distance,
		view_angle_degrees,
	):
		return false
	return (
		navigation != null
		and navigation.has_method("has_line_of_sight")
		and (
			navigation
			. has_line_of_sight(
				observer_position,
				target_position,
				ignored_scene_indices,
			)
		)
	)


static func is_within_isometric_ellipse(
	origin: Vector2,
	target: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
) -> bool:
	if horizontal_radius <= 0.0 or vertical_radius <= 0.0:
		return false
	var delta := target - origin
	var normalized_squared := (
		(delta.x * delta.x) / (horizontal_radius * horizontal_radius)
		+ (delta.y * delta.y) / (vertical_radius * vertical_radius)
	)
	return normalized_squared <= 1.0


static func original_direction_center_degrees(direction_index: int) -> float:
	if direction_index < 1 or direction_index > ORIGINAL_DIRECTION_CENTERS.size():
		return -1.0
	return ORIGINAL_DIRECTION_CENTERS[direction_index - 1]


static func original_direction_half_angle_degrees(direction_index: int) -> float:
	if direction_index < 1 or direction_index > ORIGINAL_DIRECTION_HALF_ANGLES.size():
		return -1.0
	return ORIGINAL_DIRECTION_HALF_ANGLES[direction_index - 1]


static func is_within_original_directional_field(
	observer_position: Vector2,
	target_position: Vector2,
	direction_index: int,
) -> bool:
	var center := original_direction_center_degrees(direction_index)
	var half_angle := original_direction_half_angle_degrees(direction_index)
	var delta := target_position - observer_position
	if center < 0.0 or half_angle < 0.0:
		return false
	if delta.is_zero_approx():
		return true
	var bearing := fposmod(rad_to_deg(atan2(delta.y, delta.x)), 360.0)
	var difference := absf(fposmod(bearing - center + 180.0, 360.0) - 180.0)
	return difference <= half_angle


static func original_visibility_band(
	observer_position: Vector2,
	target_position: Vector2,
	direction_index: int,
	sense_profile: Dictionary,
	target_is_crawling: bool = false,
) -> int:
	var horizontal_radius := float(sense_profile.get("horizontal_radius", 0.0))
	var vertical_radius := float(sense_profile.get("vertical_radius", 0.0))
	if not is_within_isometric_ellipse(
		observer_position, target_position, horizontal_radius, vertical_radius
	):
		return 0
	if (
		not bool(sense_profile.get("omnidirectional", false))
		and not is_within_original_directional_field(
			observer_position, target_position, direction_index
		)
	):
		return 0
	var delta := target_position - observer_position
	var normalized_squared := (
		(delta.x * delta.x) / (horizontal_radius * horizontal_radius)
		+ (delta.y * delta.y) / (vertical_radius * vertical_radius)
	)
	var near_ratio := clampf(float(sense_profile.get("near_band_ratio", 0.5)), 0.0, 1.0)
	var band := 1 if normalized_squared <= near_ratio * near_ratio else 2
	if (
		band == 2
		and target_is_crawling
		and bool(sense_profile.get("crawling_hidden_in_far_band", false))
	):
		return 0
	return band


static func can_detect_original(
	navigation: Variant,
	observer_position: Vector2,
	target_position: Vector2,
	direction_index: int,
	sense_profile: Dictionary,
	target_is_crawling: bool = false,
	ignored_scene_indices: Array = [],
) -> bool:
	if original_visibility_band(
		observer_position,
		target_position,
		direction_index,
		sense_profile,
		target_is_crawling,
	) == 0:
		return false
	if not bool(sense_profile.get("requires_line_of_sight", true)):
		return true
	return (
		navigation != null
		and navigation.has_method("has_line_of_sight")
		and navigation.has_line_of_sight(
			observer_position, target_position, ignored_scene_indices
		)
	)

static func is_within_hearing_range(observer_position: Vector2, target_position: Vector2, sense_profile: Dictionary) -> bool:
	var radius := float(sense_profile.get("hearing_radius", 0.0))
	if radius <= 0.0:
		radius = maxf(float(sense_profile.get("horizontal_radius", 0.0)), float(sense_profile.get("vertical_radius", 0.0)))
	return radius > 0.0 and observer_position.distance_squared_to(target_position) <= radius * radius


static func is_within_attack_range(
	attacker_position: Vector2,
	target_position: Vector2,
	minimum_range: float,
	maximum_range: float,
) -> bool:
	if minimum_range < 0.0 or maximum_range <= minimum_range:
		return false
	var distance_squared := attacker_position.distance_squared_to(target_position)
	return (
		distance_squared >= minimum_range * minimum_range
		and distance_squared <= maximum_range * maximum_range
	)


static func is_within_original_attack_range(
	attacker_position: Vector2,
	target_position: Vector2,
	weapon_profile: Dictionary,
) -> bool:
	return is_within_isometric_ellipse(
		attacker_position,
		target_position,
		float(weapon_profile.get("horizontal_range", 0.0)),
		float(weapon_profile.get("vertical_range", 0.0)),
	)


static func can_attack(
	navigation: Variant,
	attacker_position: Vector2,
	target_position: Vector2,
	weapon_profile: Dictionary,
	ignored_scene_indices: Array = [],
) -> bool:
	var uses_original_ellipse := (
		weapon_profile.has("horizontal_range") and weapon_profile.has("vertical_range")
	)
	var in_range := is_within_original_attack_range(
		attacker_position, target_position, weapon_profile
	) if uses_original_ellipse else is_within_attack_range(
		attacker_position,
		target_position,
		float(weapon_profile.get("minimum_range", -1.0)),
		float(weapon_profile.get("maximum_range", -1.0)),
	)
	if not in_range:
		return false
	if not bool(weapon_profile.get("requires_line_of_sight", true)):
		return true
	return (
		navigation != null
		and navigation.has_method("has_line_of_sight")
		and (
			navigation
			. has_line_of_sight(
				attacker_position,
				target_position,
				ignored_scene_indices,
			)
		)
	)
