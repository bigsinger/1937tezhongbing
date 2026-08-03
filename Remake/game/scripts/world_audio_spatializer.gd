class_name WorldAudioSpatializer
extends RefCounted

## Camera-relative attenuation for short world sounds such as footsteps.
##
## The original DirectSound path mixed every actor at full volume.  That is
## fatiguing on modern wide viewports and wastes mixer voices for actors that
## are far outside the rendered area.  Keep the authored WAV unchanged and
## apply presentation-only attenuation at the final playback boundary.

const OFFSCREEN_CULL_MARGIN := 320.0
const MIN_NEAR_RADIUS := 96.0
const NEAR_RADIUS_VIEW_RATIO := 0.18
const FAR_VOLUME_DB := -28.0
const SILENT_VOLUME_DB := -80.0


static func mix_for_source(
	source_world_position: Vector2,
	visible_world_rect: Rect2,
) -> Dictionary:
	if visible_world_rect.size.x <= 0.0 or visible_world_rect.size.y <= 0.0:
		return {"audible": true, "volume_db": 0.0, "distance_ratio": 0.0}
	if not visible_world_rect.grow(OFFSCREEN_CULL_MARGIN).has_point(
		source_world_position
	):
		return {
			"audible": false,
			"volume_db": SILENT_VOLUME_DB,
			"distance_ratio": 1.0,
		}
	var center := visible_world_rect.get_center()
	var distance := center.distance_to(source_world_position)
	var near_radius := maxf(
		MIN_NEAR_RADIUS,
		minf(visible_world_rect.size.x, visible_world_rect.size.y)
			* NEAR_RADIUS_VIEW_RATIO,
	)
	var far_radius := maxf(
		near_radius + 1.0,
		visible_world_rect.size.length() * 0.5 + OFFSCREEN_CULL_MARGIN,
	)
	var ratio := clampf(
		(distance - near_radius) / (far_radius - near_radius),
		0.0,
		1.0,
	)
	# Smoothstep avoids a perceptible volume knee when a unit crosses the near
	# field while still reaching a useful low level close to the cull boundary.
	var smooth_ratio := ratio * ratio * (3.0 - 2.0 * ratio)
	return {
		"audible": true,
		"volume_db": lerpf(0.0, FAR_VOLUME_DB, smooth_ratio),
		"distance_ratio": smooth_ratio,
	}
