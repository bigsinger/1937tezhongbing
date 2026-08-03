class_name LegacyExplosionRules
extends RefCounted

## Runtime actors 61 and 62 share sub_4554A0. Their primary sprite differs,
## but damage, secondary bands, alerting and particle-family behavior are the
## same.

const MAIN_DAMAGE := 128
const MAIN_HORIZONTAL_RADIUS := 128.0
const MAIN_VERTICAL_RADIUS := 64.0
const MAIN_EXCLUDED_RUNTIME_ACTOR_TYPES := [85]
const ALERT_RADIUS := 800.0
const SPECIAL_DAMAGE_BANDS: Array[Dictionary] = [
	{
		"runtime_actor_types": [34, 86, 87, 88, 94, 95, 96, 97],
		"geometry": "ellipse",
		"horizontal_radius": 384.0,
		"vertical_radius": 192.0,
		"damage": 128,
		"original_visual_effect_type": 11,
	},
	{
		"runtime_actor_types": [66, 67, 68, 77, 93],
		"geometry": "euclidean_radius",
		"radius": 256.0,
		"exclusive_boundary": true,
		"damage": 128,
		"original_visual_effect_type": 15,
	},
]
const ACTOR_VISUALS := {
	61: {
		"runtime_actor_type": 61,
		"original_gfl_index": 19,
		"frame_count": 10,
		"frame_hold_ticks": 3,
	},
	62: {
		"runtime_actor_type": 62,
		"original_gfl_index": 20,
		"frame_count": 10,
		"frame_hold_ticks": 2,
	},
}


static func profile_for_actor(runtime_actor_type: int) -> Dictionary:
	var visual_value: Variant = ACTOR_VISUALS.get(runtime_actor_type)
	if not visual_value is Dictionary:
		return {}
	var result := (visual_value as Dictionary).duplicate(true)
	result["blast_damage"] = MAIN_DAMAGE
	result["blast_horizontal_radius"] = MAIN_HORIZONTAL_RADIUS
	result["blast_vertical_radius"] = MAIN_VERTICAL_RADIUS
	result["main_excluded_runtime_actor_types"] = (
		MAIN_EXCLUDED_RUNTIME_ACTOR_TYPES.duplicate()
	)
	result["alert_radius"] = ALERT_RADIUS
	result["special_damage_bands"] = SPECIAL_DAMAGE_BANDS.duplicate(true)
	return result


static func band_contains(band: Dictionary, offset: Vector2) -> bool:
	match String(band.get("geometry", "")):
		"ellipse":
			var horizontal_radius := float(
				band.get("horizontal_radius", 0.0)
			)
			var vertical_radius := float(
				band.get("vertical_radius", 0.0)
			)
			if horizontal_radius <= 0.0 or vertical_radius <= 0.0:
				return false
			return (
				offset.x * offset.x / (horizontal_radius * horizontal_radius)
				+ offset.y * offset.y / (vertical_radius * vertical_radius)
			) <= 1.0
		"euclidean_radius":
			var radius := float(band.get("radius", 0.0))
			if radius <= 0.0:
				return false
			var distance_squared := offset.length_squared()
			var radius_squared := radius * radius
			return (
				distance_squared < radius_squared
				if bool(band.get("exclusive_boundary", false))
				else distance_squared <= radius_squared
			)
	return false


static func main_ellipse_contains(offset: Vector2) -> bool:
	return (
		offset.x * offset.x
			/ (MAIN_HORIZONTAL_RADIUS * MAIN_HORIZONTAL_RADIUS)
		+ offset.y * offset.y
			/ (MAIN_VERTICAL_RADIUS * MAIN_VERTICAL_RADIUS)
	) <= 1.0
