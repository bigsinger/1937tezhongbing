class_name EnemyPerceptionController
extends RefCounted

const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")

const BAND_NONE := "none"
const BAND_FAR_GREEN := "far_green"
const BAND_NEAR_RED := "near_red"


func visibility_band(
	distance: float,
	near_radius: float,
	far_radius: float,
	target_crawling: bool,
	line_of_sight_clear: bool,
) -> String:
	if not line_of_sight_clear or distance > maxf(far_radius, near_radius):
		return BAND_NONE
	if distance <= maxf(near_radius, 0.0):
		return BAND_NEAR_RED
	return BAND_NONE if target_crawling else BAND_FAR_GREEN


func visibility_band_index_heading(
	navigation: Variant,
	observer_position: Vector2,
	target_position: Vector2,
	heading_degrees: float,
	half_angle_degrees: float,
	sense_profile: Dictionary,
	target_crawling: bool,
	ignored_scene_indices: Array = [],
) -> int:
	var band: int = TACTICAL_SENSES.original_visibility_band_heading(
		observer_position,
		target_position,
		heading_degrees,
		half_angle_degrees,
		sense_profile,
		target_crawling,
	)
	if band <= 0 or not bool(sense_profile.get("requires_line_of_sight", true)):
		return band
	if navigation == null or not navigation.has_method("has_line_of_sight"):
		return 0
	var line_of_sight_clear := (
		(navigation as DynamicOccupancyGrid).has_line_of_sight(
			observer_position,
			target_position,
			ignored_scene_indices,
		)
		if navigation is DynamicOccupancyGrid
		else bool(navigation.call(
			"has_line_of_sight",
			observer_position,
			target_position,
			ignored_scene_indices,
		))
	)
	return band if line_of_sight_clear else 0


func can_detect_heading(
	navigation: Variant,
	observer_position: Vector2,
	target_position: Vector2,
	heading_degrees: float,
	half_angle_degrees: float,
	sense_profile: Dictionary,
	target_crawling: bool,
	ignored_scene_indices: Array = [],
) -> bool:
	return visibility_band_index_heading(
		navigation,
		observer_position,
		target_position,
		heading_degrees,
		half_angle_degrees,
		sense_profile,
		target_crawling,
		ignored_scene_indices,
	) > 0


func visibility_band_heading(
	navigation: Variant,
	observer_position: Vector2,
	target_position: Vector2,
	heading_degrees: float,
	half_angle_degrees: float,
	sense_profile: Dictionary,
	target_crawling: bool,
	ignored_scene_indices: Array = [],
) -> String:
	var band := visibility_band_index_heading(
		navigation,
		observer_position,
		target_position,
		heading_degrees,
		half_angle_degrees,
		sense_profile,
		target_crawling,
		ignored_scene_indices,
	)
	return BAND_NEAR_RED if band == 1 else BAND_FAR_GREEN if band == 2 else BAND_NONE
