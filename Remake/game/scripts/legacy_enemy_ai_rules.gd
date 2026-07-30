class_name LegacyEnemyAiRules
extends RefCounted

## Recovered coordinate-alert and local-search constants from M1937.exe.
##
## - sub_45DDA0 uses sub_45A7C0's strict directional boundary constructed from
##   (R*cos(angle), R/2*sin(angle)); R is normally 640. It skips dead actors
##   and runtime type 91, and writes a coordinate command rather than a live
##   target pointer.
## - sub_45C710 uses strict counter > limit transitions.
## - sub_45E4B0 calls sub_45D060 for five local search points.
## - sub_45D060 chooses x in ±[0,31], y in ±[0,15], clamps to a 16-pixel
##   world margin, then waits rand()%160+40 ticks before the next point.

const ENEMY_FACTION_ID := 1
const EXCLUDED_ALERT_RUNTIME_ACTOR_TYPE := 91
const DEFAULT_ALERT_HORIZONTAL_RADIUS := 640.0
const DEFAULT_ALERT_VERTICAL_RADIUS := 320.0
const REACTION_MINIMUM_LIMIT := 40
const REACTION_RANDOM_SPAN := 40
const SEARCH_POINT_COUNT := 5
const SEARCH_HORIZONTAL_SPAN := 32
const SEARCH_VERTICAL_SPAN := 16
const SEARCH_WAIT_MINIMUM_LIMIT := 40
const SEARCH_WAIT_RANDOM_SPAN := 160
const WORLD_MARGIN := 16.0


static func msvc_rand_step(state: int) -> int:
	return int((state * 214013 + 2531011) & 0x7fffffff)


static func msvc_rand_value(state_after_step: int) -> int:
	return int((state_after_step >> 16) & 0x7fff)


static func reaction_limit_from_state(state: int) -> Dictionary:
	var next_state := msvc_rand_step(state)
	return {
		"state": next_state,
		"limit": (
			msvc_rand_value(next_state) % REACTION_RANDOM_SPAN
			+ REACTION_MINIMUM_LIMIT
		),
	}


static func initial_search_wait_from_state(state: int) -> Dictionary:
	var next_state := msvc_rand_step(state)
	return {
		"state": next_state,
		"limit": (
			msvc_rand_value(next_state) % SEARCH_WAIT_RANDOM_SPAN
			+ SEARCH_WAIT_MINIMUM_LIMIT
		),
	}


static func local_search_point_from_state(
	state: int,
	origin: Vector2,
	world_bounds: Rect2,
) -> Dictionary:
	var next_state := msvc_rand_step(state)
	var x_offset := (
		msvc_rand_value(next_state) % SEARCH_HORIZONTAL_SPAN
	)
	next_state = msvc_rand_step(next_state)
	var y_offset := (
		msvc_rand_value(next_state) % SEARCH_VERTICAL_SPAN
	)
	next_state = msvc_rand_step(next_state)
	if msvc_rand_value(next_state) % 2 > 0:
		x_offset = -x_offset
	next_state = msvc_rand_step(next_state)
	if msvc_rand_value(next_state) % 2 > 0:
		y_offset = -y_offset
	var point := origin + Vector2(x_offset, y_offset)
	var minimum := world_bounds.position + Vector2(WORLD_MARGIN, WORLD_MARGIN)
	var maximum := (
		world_bounds.end
		- Vector2(WORLD_MARGIN, WORLD_MARGIN)
	)
	if maximum.x < minimum.x:
		minimum.x = world_bounds.position.x
		maximum.x = world_bounds.end.x
	if maximum.y < minimum.y:
		minimum.y = world_bounds.position.y
		maximum.y = world_bounds.end.y
	point = point.clamp(minimum, maximum)
	next_state = msvc_rand_step(next_state)
	return {
		"state": next_state,
		"point": point,
		"next_wait_limit": (
			msvc_rand_value(next_state) % SEARCH_WAIT_RANDOM_SPAN
			+ SEARCH_WAIT_MINIMUM_LIMIT
		),
	}


static func counter_has_completed(counter: int, limit: int) -> bool:
	return counter > limit


static func is_within_alert_ellipse(
	source_position: Vector2,
	recipient_position: Vector2,
	horizontal_radius: float,
) -> bool:
	if horizontal_radius <= 0.0:
		return false
	var offset := recipient_position - source_position
	var distance_squared := offset.length_squared()
	if distance_squared <= 0.0:
		return true
	# sub_45A7C0 does not use the analytic radial intersection of an ellipse.
	# It measures the length of the parametric point
	# (R*cos(angle), R*0.5*sin(angle)) at the recipient's screen-space angle,
	# then sub_45DDA0 applies a strict Euclidean-distance comparison.
	var directional_boundary_squared := (
		horizontal_radius
		* horizontal_radius
		* (
			offset.x * offset.x
			+ 0.25 * offset.y * offset.y
		)
		/ distance_squared
	)
	return distance_squared < directional_boundary_squared


static func alert_recipient_is_eligible(
	faction_id: int,
	runtime_actor_type: int,
	is_alive: bool,
	has_unlost_live_contact: bool,
) -> bool:
	return (
		faction_id == ENEMY_FACTION_ID
		and runtime_actor_type != EXCLUDED_ALERT_RUNTIME_ACTOR_TYPE
		and is_alive
		and not has_unlost_live_contact
	)
