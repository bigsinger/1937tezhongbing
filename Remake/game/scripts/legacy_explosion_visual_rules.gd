class_name LegacyExplosionVisualRules
extends RefCounted

const CRT_CALL_SITE_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)

## Recovered actor-62 visual-effect construction.
##
## sub_4554A0 requests effect family 11 for the primary/special ellipse and
## family 15 for the strict 256-radius special band. sub_4656C0 routes both to
## sub_465580/sub_464730. That path attempts one or two particles, scatters
## them within 64x32 screen pixels, and sets each dynamic actor's repeat
## counter to five. sub_464A80 decrements that counter only at the last frame
## and destroys the particle after the fifth complete animation cycle.
##
## M1937.exe never calls _srand, so the statically linked MSVCRT generator has
## its default initial state of 1. The whole game shares that generator; this
## remake currently preserves the generator and draw order for this recovered
## path, while other not-yet-recovered rand() call sites can still shift the
## exact variant selected at a given gameplay instant.

const CRT_INITIAL_STATE := 1
const CRT_MULTIPLIER := 214013
const CRT_INCREMENT := 2531011
const CRT_OUTPUT_MASK := 0x7fff
const UINT32_MASK := 0xffffffff

const PARTICLE_COUNT_MODULUS := 3
const PARTICLE_MINIMUM_COUNT := 1
const PARTICLE_REPEAT_COUNT := 5
const SPREAD_HORIZONTAL_RADIUS := 64
const SPREAD_VERTICAL_RADIUS := 32
const MAP_CELL_SIZE := Vector2i(32, 16)
const DEBRIS_COUNT_MODULUS := 8
const DEBRIS_MINIMUM_COUNT := 1
const DEBRIS_RUNTIME_TYPE_BASE := 72
const DEBRIS_RUNTIME_TYPE_COUNT := 5
const DEBRIS_INITIAL_HORIZONTAL_RADIUS := 320
const DEBRIS_INITIAL_JITTER_RADIUS := 160
const DEBRIS_INITIAL_SPEED := 8
const DEBRIS_MINIMUM_HORIZONTAL_RADIUS := 16
const DEBRIS_MINIMUM_JITTER_RADIUS := 8
const DEBRIS_MINIMUM_SPEED := 2
const DYNAMIC_ACTOR_CONSTRUCTOR_CALL_SITES := [
	0x00050967,
	0x00050980,
	0x0005340B,
	0x0005358B,
]
const DYNAMIC_ACTOR_LOAD_FACING_CALL_SITE := 0x0005BBBC
const DYNAMIC_ACTOR_DESTRUCTOR_CALL_SITES := [
	0x00053655,
	0x000537A3,
	0x00050B64,
	0x00050B7D,
]

const FAMILY_PROFILES := {
	10: {
		"effect_family": 10,
		"runtime_actor_types": [63, 64, 65],
		"persistent": true,
	},
	11: {
		"effect_family": 11,
		"runtime_actor_types": [69, 70, 71],
	},
	15: {
		"effect_family": 15,
		"runtime_actor_types": [102, 103, 104],
	},
}

# sub_41BF80 selects the first SPR in GFL order whose SPR header value 2 is
# the requested runtime actor type. Runtime type 102 has no matching SPR in
# the known 1,394-entry archive, so that original particle attempt fails.
const PARTICLE_PROFILES := {
	63: {
		"runtime_actor_type": 63,
		"gfl_index": 200,
		"frame_count": 1,
		"frame_hold_ticks": 1,
		"anchor": Vector2(49.0, 19.0),
	},
	64: {
		"runtime_actor_type": 64,
		"gfl_index": 201,
		"frame_count": 1,
		"frame_hold_ticks": 1,
		"anchor": Vector2(36.0, 16.0),
	},
	65: {
		"runtime_actor_type": 65,
		"gfl_index": 202,
		"frame_count": 1,
		"frame_hold_ticks": 1,
		"anchor": Vector2(21.0, 10.0),
	},
	69: {
		"runtime_actor_type": 69,
		"gfl_index": 21,
		"frame_count": 9,
		"frame_hold_ticks": 2,
		"anchor": Vector2(38.0, 112.0),
	},
	70: {
		"runtime_actor_type": 70,
		"gfl_index": 25,
		"frame_count": 10,
		"frame_hold_ticks": 3,
		"anchor": Vector2(34.0, 146.0),
	},
	71: {
		"runtime_actor_type": 71,
		"gfl_index": 23,
		"frame_count": 10,
		"frame_hold_ticks": 3,
		"anchor": Vector2(94.0, 172.0),
	},
	102: {
		"runtime_actor_type": 102,
		"gfl_index": -1,
		"frame_count": 0,
		"frame_hold_ticks": 0,
		"anchor": Vector2.ZERO,
	},
	103: {
		"runtime_actor_type": 103,
		"gfl_index": 379,
		"frame_count": 10,
		"frame_hold_ticks": 3,
		"anchor": Vector2(34.0, 146.0),
	},
	104: {
		"runtime_actor_type": 104,
		"gfl_index": 380,
		"frame_count": 10,
		"frame_hold_ticks": 3,
		"anchor": Vector2(94.0, 172.0),
	},
	72: {
		"runtime_actor_type": 72,
		"gfl_index": 150,
		"frame_count": 4,
		"frame_hold_ticks": 1,
		"anchor": Vector2(20.0, 20.0),
	},
	73: {
		"runtime_actor_type": 73,
		"gfl_index": 151,
		"frame_count": 4,
		"frame_hold_ticks": 1,
		"anchor": Vector2(7.0, 7.0),
	},
	74: {
		"runtime_actor_type": 74,
		"gfl_index": 868,
		"frame_count": 4,
		"frame_hold_ticks": 1,
		"anchor": Vector2(20.0, 20.0),
	},
	75: {
		"runtime_actor_type": 75,
		"gfl_index": 869,
		"frame_count": 4,
		"frame_hold_ticks": 1,
		"anchor": Vector2(7.0, 7.0),
	},
	76: {
		"runtime_actor_type": 76,
		"gfl_index": 1000,
		"frame_count": 4,
		"frame_hold_ticks": 1,
		"anchor": Vector2(20.0, 20.0),
	},
}


static func family_profile(effect_family: int) -> Dictionary:
	var value: Variant = FAMILY_PROFILES.get(effect_family)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func particle_profile(runtime_actor_type: int) -> Dictionary:
	var value: Variant = PARTICLE_PROFILES.get(runtime_actor_type)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func supported_gfl_indices() -> Array[int]:
	var result: Array[int] = []
	for raw_profile: Variant in PARTICLE_PROFILES.values():
		var profile := raw_profile as Dictionary
		var gfl_index := int(profile.get("gfl_index", -1))
		if gfl_index >= 0 and not result.has(gfl_index):
			result.append(gfl_index)
	result.sort()
	return result


static func next_crt_rand(state: int) -> Dictionary:
	var next_state := (state * CRT_MULTIPLIER + CRT_INCREMENT) & UINT32_MASK
	return {
		"state": next_state,
		"value": (next_state >> 16) & CRT_OUTPUT_MASK,
	}


static func build_burst_plan(
	effect_family: int,
	center: Vector2,
	world_size: Vector2,
	initial_state: int,
) -> Dictionary:
	var family := family_profile(effect_family)
	if family.is_empty():
		return {}
	var count_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"particle_attempt_count_max_rand_mod_3_one",
		)
	)
	var variant_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"particle_runtime_type_variant_rand_mod_3",
		)
	)
	var x_sign_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"x_sign_rand_mod_2",
		)
	)
	var y_sign_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"y_sign_rand_mod_2",
		)
	)
	var x_magnitude_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"x_magnitude_positive_or_negative_branch",
		)
	)
	var y_magnitude_sites: Array[int] = (
		CRT_CALL_SITE_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"y_magnitude_positive_or_negative_branch",
		)
	)
	if (
		count_sites.size() != 1
		or variant_sites.size() != 1
		or x_sign_sites.size() != 1
		or y_sign_sites.size() != 1
		or x_magnitude_sites.size() != 2
		or y_magnitude_sites.size() != 2
	):
		push_error("爆炸粒子 CRT rand 调用点目录不完整")
		return {}
	var state := initial_state & UINT32_MASK
	var random_draws: Array[Dictionary] = []
	var draw := next_crt_rand(state)
	state = int(draw["state"])
	_append_random_draw(random_draws, count_sites[0], draw)
	var attempted_count := maxi(
		int(draw["value"]) % PARTICLE_COUNT_MODULUS,
		PARTICLE_MINIMUM_COUNT,
	)
	var particles: Array[Dictionary] = []
	var runtime_types := family.get("runtime_actor_types", []) as Array
	for unused_index: int in range(attempted_count):
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, variant_sites[0], draw)
		var runtime_actor_type := int(
			runtime_types[int(draw["value"]) % runtime_types.size()]
		)
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, x_sign_sites[0], draw)
		var subtract_x := int(draw["value"]) % 2 != 0
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, y_sign_sites[0], draw)
		var subtract_y := int(draw["value"]) % 2 != 0
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(
			random_draws,
			x_magnitude_sites[1] if subtract_x else x_magnitude_sites[0],
			draw,
		)
		var x_offset := int(draw["value"]) % SPREAD_HORIZONTAL_RADIUS
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(
			random_draws,
			y_magnitude_sites[1] if subtract_y else y_magnitude_sites[0],
			draw,
		)
		var y_offset := int(draw["value"]) % SPREAD_VERTICAL_RADIUS
		var particle_position := Vector2(
			center.x - x_offset if subtract_x else center.x + x_offset,
			center.y - y_offset if subtract_y else center.y + y_offset,
		)
		particle_position = _clamp_original_map_position(
			particle_position,
			world_size,
		)
		var profile := particle_profile(runtime_actor_type)
		var asset_available := int(profile.get("gfl_index", -1)) >= 0
		var factory_plan := build_dynamic_actor_factory_plan(
			state,
			asset_available,
		)
		if factory_plan.is_empty():
			return {}
		state = int(factory_plan.get("next_random_state", state))
		_append_plan_draws(random_draws, factory_plan)
		# Missing runtime type 102 reproduces sub_44A350 returning null. The
		# four constructor and four immediate destructor draws still occur, but
		# the load-facing draw and particle insertion do not.
		if not asset_available:
			continue
		particles.append({
			"runtime_actor_type": runtime_actor_type,
			"gfl_index": int(profile["gfl_index"]),
			"world_position": particle_position,
			"frame_count": int(profile["frame_count"]),
			"frame_hold_ticks": int(profile["frame_hold_ticks"]),
			"anchor": profile["anchor"] as Vector2,
			"repeat_count": PARTICLE_REPEAT_COUNT,
			"persistent": bool(family.get("persistent", false)),
		})
	return {
		"effect_family": effect_family,
		"attempted_particle_count": attempted_count,
		"particles": particles,
		"next_random_state": state,
		"random_draws": random_draws,
		"random_draw_count": random_draws.size(),
	}


static func build_debris_cluster_plan(
	center: Vector2,
	initial_state: int,
) -> Dictionary:
	# sub_463F40 dispatches effect 12 immediately after the persistent scorch
	# effect. sub_4653B0 chooses 1..7 debris actors; every actor then consumes
	# its constructor style, fixed flight angle, and branch-specific x/y jitter.
	var count_site := _single_operation_site(
		"create_random_effect_cluster",
		"effect_count_max_rand_mod_8_one",
	)
	var runtime_type_site := _single_operation_site(
		"create_random_effect_cluster",
		"effect_runtime_type_rand_mod_5_plus_72",
	)
	var style_site := _single_operation_site(
		"initialize_effect_particle",
		"effect_repeat_or_style_rand_mod_3_plus_2",
	)
	var angle_site := _single_operation_site(
		"choose_effect_particle_position",
		"initial_angle_rand_mod_360",
	)
	var x_sites: Array[int] = CRT_CALL_SITE_CATALOG.rvas_for_operation(
		"choose_effect_particle_position",
		"x_jitter_positive_or_negative_branch",
	)
	var y_sites: Array[int] = CRT_CALL_SITE_CATALOG.rvas_for_operation(
		"choose_effect_particle_position",
		"y_jitter_positive_or_negative_branch",
	)
	if (
		count_site == 0
		or runtime_type_site == 0
		or style_site == 0
		or angle_site == 0
		or x_sites.size() != 2
		or y_sites.size() != 2
	):
		push_error("爆炸碎片 CRT rand 调用点目录不完整")
		return {}
	var state := initial_state & UINT32_MASK
	var random_draws: Array[Dictionary] = []
	var draw := next_crt_rand(state)
	state = int(draw["state"])
	_append_random_draw(random_draws, count_site, draw)
	var attempted_count := maxi(
		int(draw["value"]) % DEBRIS_COUNT_MODULUS,
		DEBRIS_MINIMUM_COUNT,
	)
	var debris: Array[Dictionary] = []
	for unused_index: int in range(attempted_count):
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, runtime_type_site, draw)
		var runtime_actor_type := (
			DEBRIS_RUNTIME_TYPE_BASE
			+ int(draw["value"]) % DEBRIS_RUNTIME_TYPE_COUNT
		)
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, style_site, draw)
		var repeat_count := int(draw["value"]) % 3 + 2
		var profile := particle_profile(runtime_actor_type)
		var asset_available := int(profile.get("gfl_index", -1)) >= 0
		var factory_plan := build_dynamic_actor_factory_plan(
			state,
			asset_available,
		)
		if factory_plan.is_empty():
			return {}
		state = int(factory_plan.get("next_random_state", state))
		_append_plan_draws(random_draws, factory_plan)
		if not asset_available:
			break
		draw = next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, angle_site, draw)
		var angle_degrees := int(draw["value"]) % 360
		var endpoint_plan := _debris_endpoint_plan(
			center,
			DEBRIS_INITIAL_HORIZONTAL_RADIUS,
			DEBRIS_INITIAL_JITTER_RADIUS,
			angle_degrees,
			state,
			x_sites,
			y_sites,
		)
		if endpoint_plan.is_empty():
			return {}
		state = int(endpoint_plan.get("next_random_state", state))
		for endpoint_draw: Dictionary in (
			endpoint_plan.get("random_draws", []) as Array[Dictionary]
		):
			random_draws.append(endpoint_draw.duplicate(true))
		var endpoint := endpoint_plan.get("endpoint", center) as Vector2
		var path := bresenham_path(center, endpoint)
		debris.append({
			"runtime_actor_type": runtime_actor_type,
			"gfl_index": int(profile.get("gfl_index", -1)),
			"anchor": profile.get("anchor", Vector2.ZERO) as Vector2,
			"frame_count": int(profile.get("frame_count", 1)),
			"frame_hold_ticks": int(profile.get("frame_hold_ticks", 1)),
			"repeat_count": repeat_count,
			"remaining_flights": repeat_count,
			"angle_degrees": angle_degrees,
			"speed": DEBRIS_INITIAL_SPEED,
			"path": path,
			"path_index": 0,
			"flight_tick": 0,
			"world_position": center,
			"height": 0,
		})
	return {
		"effect_family": 12,
		"attempted_particle_count": attempted_count,
		"debris": debris,
		"next_random_state": state,
		"random_draws": random_draws,
		"random_draw_count": random_draws.size(),
}


static func build_dynamic_actor_factory_plan(
	initial_state: int,
	asset_available: bool = true,
) -> Dictionary:
	# sub_44A350 first constructs the 0x2A0-byte actor. The base and derived
	# constructors consume four draws before SPR lookup. Process-local runtime
	# traces of item drops, burial actors and projectile/effect actors prove that
	# a normal successful in-level insertion stops there. 0x5BBBC belongs to the
	# separate SAV restore path, not to the ordinary factory transaction. A failed
	# lookup (notably runtime type 102) immediately invokes the derived/base
	# destructor pair and therefore consumes four constructor plus four reset
	# draws.
	if not _all_sites_registered(DYNAMIC_ACTOR_CONSTRUCTOR_CALL_SITES):
		return {}
	if (
		not asset_available
		and not _all_sites_registered(DYNAMIC_ACTOR_DESTRUCTOR_CALL_SITES)
	):
		return {}
	var state := initial_state & UINT32_MASK
	var random_draws: Array[Dictionary] = []
	for call_site: int in DYNAMIC_ACTOR_CONSTRUCTOR_CALL_SITES:
		var draw := next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, call_site, draw)
	if not asset_available:
		for call_site: int in DYNAMIC_ACTOR_DESTRUCTOR_CALL_SITES:
			var reset_draw := next_crt_rand(state)
			state = int(reset_draw["state"])
			_append_random_draw(random_draws, call_site, reset_draw)
	return {
		"asset_available": asset_available,
		"next_random_state": state,
		"random_draws": random_draws,
		"random_draw_count": random_draws.size(),
	}


static func build_saved_actor_facing_plan(initial_state: int) -> Dictionary:
	# sub_45B950 is reached independently while an actor state from a SAV is
	# applied. Keep the one-draw transaction explicit so ordinary dynamic actor
	# creation cannot silently shift the process-global stream.
	if CRT_CALL_SITE_CATALOG.metadata_for_rva(
		DYNAMIC_ACTOR_LOAD_FACING_CALL_SITE
	).is_empty():
		return {}
	var draw := next_crt_rand(initial_state & UINT32_MASK)
	var random_draws: Array[Dictionary] = []
	_append_random_draw(
		random_draws,
		DYNAMIC_ACTOR_LOAD_FACING_CALL_SITE,
		draw,
	)
	return {
		"next_random_state": int(draw["state"]),
		"random_draws": random_draws,
		"random_draw_count": 1,
	}


static func build_dynamic_actor_destructor_plan(initial_state: int) -> Dictionary:
	if not _all_sites_registered(DYNAMIC_ACTOR_DESTRUCTOR_CALL_SITES):
		return {}
	var state := initial_state & UINT32_MASK
	var random_draws: Array[Dictionary] = []
	for call_site: int in DYNAMIC_ACTOR_DESTRUCTOR_CALL_SITES:
		var draw := next_crt_rand(state)
		state = int(draw["state"])
		_append_random_draw(random_draws, call_site, draw)
	return {
		"next_random_state": state,
		"random_draws": random_draws,
		"random_draw_count": random_draws.size(),
	}


static func build_debris_bounce_plan(
	center: Vector2,
	previous_path_length: int,
	previous_speed: int,
	angle_degrees: int,
	initial_state: int,
) -> Dictionary:
	var x_sites: Array[int] = CRT_CALL_SITE_CATALOG.rvas_for_operation(
		"choose_effect_particle_position",
		"x_jitter_positive_or_negative_branch",
	)
	var y_sites: Array[int] = CRT_CALL_SITE_CATALOG.rvas_for_operation(
		"choose_effect_particle_position",
		"y_jitter_positive_or_negative_branch",
	)
	if x_sites.size() != 2 or y_sites.size() != 2:
		return {}
	var horizontal_radius := maxi(
		previous_path_length - int(previous_path_length / 2),
		DEBRIS_MINIMUM_HORIZONTAL_RADIUS,
	)
	var jitter_radius := maxi(
		int(horizontal_radius / 2),
		DEBRIS_MINIMUM_JITTER_RADIUS,
	)
	var speed := maxi(
		int(previous_speed / 2),
		DEBRIS_MINIMUM_SPEED,
	)
	var endpoint_plan := _debris_endpoint_plan(
		center,
		horizontal_radius,
		jitter_radius,
		angle_degrees,
		initial_state,
		x_sites,
		y_sites,
	)
	if endpoint_plan.is_empty():
		return {}
	var endpoint := endpoint_plan.get("endpoint", center) as Vector2
	return {
		"horizontal_radius": horizontal_radius,
		"jitter_radius": jitter_radius,
		"speed": speed,
		"path": bresenham_path(center, endpoint),
		"endpoint": endpoint,
		"next_random_state": int(endpoint_plan.get(
			"next_random_state",
			initial_state,
		)),
		"random_draws": (
			endpoint_plan.get("random_draws", []) as Array
		).duplicate(true),
	}


static func bresenham_path(start: Vector2, end: Vector2) -> PackedVector2Array:
	# This is the instruction-for-instruction integer shape of sub_408AD0,
	# including its major-axis swap, >= 0 tie branch and inclusive endpoint.
	# Those details matter because sub_408D90 samples this array by speed-sized
	# strides and the next bounce radius is derived from its exact length.
	var start_x := int(start.x)
	var start_y := int(start.y)
	var end_x := int(end.x)
	var end_y := int(end.y)
	var major_position := start_x
	var minor_position := start_y
	var major_delta := absi(end_x - start_x)
	var minor_delta := absi(end_y - start_y)
	var major_step := -1 if end_x - start_x <= 0 else 1
	var minor_step := -1 if end_y - start_y <= 0 else 1
	var axes_swapped := false
	if minor_delta > major_delta:
		major_position = start_y
		minor_position = start_x
		var swapped_delta := major_delta
		major_delta = minor_delta
		minor_delta = swapped_delta
		major_step = -1 if end_y - start_y <= 0 else 1
		minor_step = -1 if end_x - start_x <= 0 else 1
		axes_swapped = true
	var doubled_minor := minor_delta * 2
	var error := doubled_minor - major_delta
	var result := PackedVector2Array()
	for unused_step: int in range(major_delta):
		result.append(
			Vector2(minor_position, major_position)
			if axes_swapped
			else Vector2(major_position, minor_position)
		)
		while error >= 0:
			minor_position += minor_step
			error -= major_delta * 2
		major_position += major_step
		error += doubled_minor
	result.append(Vector2(end_x, end_y))
	return result


static func _debris_endpoint_plan(
	center: Vector2,
	horizontal_radius: int,
	jitter_radius: int,
	angle_degrees: int,
	initial_state: int,
	x_sites: Array[int],
	y_sites: Array[int],
) -> Dictionary:
	if jitter_radius <= 0 or x_sites.size() != 2 or y_sites.size() != 2:
		return {}
	var center_x := int(center.x)
	var center_y := int(center.y)
	var radians := deg_to_rad(float(angle_degrees))
	var endpoint_x := center_x - int(cos(radians) * horizontal_radius)
	var endpoint_y := center_y - int(
		sin(radians) * horizontal_radius * 0.5
	)
	var state := initial_state & UINT32_MASK
	var random_draws: Array[Dictionary] = []
	var draw := next_crt_rand(state)
	state = int(draw["state"])
	var x_positive := endpoint_x >= center_x
	_append_random_draw(
		random_draws,
		x_sites[1] if x_positive else x_sites[0],
		draw,
	)
	var x_jitter := int(draw["value"]) % jitter_radius
	endpoint_x += x_jitter if x_positive else -x_jitter
	draw = next_crt_rand(state)
	state = int(draw["state"])
	var y_positive := endpoint_y >= center_y
	_append_random_draw(
		random_draws,
		y_sites[1] if y_positive else y_sites[0],
		draw,
	)
	var y_jitter := int(draw["value"]) % jitter_radius
	endpoint_y += int(y_jitter / 2) if y_positive else -int(y_jitter / 2)
	return {
		"endpoint": Vector2(endpoint_x, endpoint_y),
		"next_random_state": state,
		"random_draws": random_draws,
	}


static func _single_operation_site(
	semantic_name: String,
	purpose: String,
) -> int:
	var sites: Array[int] = CRT_CALL_SITE_CATALOG.rvas_for_operation(
		semantic_name,
		purpose,
	)
	return sites[0] if sites.size() == 1 else 0


static func _append_random_draw(
	draws: Array[Dictionary],
	call_site_rva: int,
	draw: Dictionary,
) -> void:
	draws.append({
		"call_site_rva": call_site_rva,
		"state": int(draw.get("state", 0)),
		"value": int(draw.get("value", 0)),
	})


static func _append_plan_draws(
	draws: Array[Dictionary],
	plan: Dictionary,
) -> void:
	for raw_draw: Variant in plan.get("random_draws", []) as Array:
		if raw_draw is Dictionary:
			draws.append((raw_draw as Dictionary).duplicate(true))


static func _all_sites_registered(call_sites: Array) -> bool:
	for raw_call_site: Variant in call_sites:
		if CRT_CALL_SITE_CATALOG.metadata_for_rva(
			int(raw_call_site)
		).is_empty():
			push_error(
				"动态效果对象 CRT rand 调用点未登记：0x%08X"
				% int(raw_call_site)
			)
			return false
	return true


static func particle_lifetime_ticks(runtime_actor_type: int) -> int:
	var profile := particle_profile(runtime_actor_type)
	return (
		int(profile.get("frame_count", 0))
		* int(profile.get("frame_hold_ticks", 0))
		* PARTICLE_REPEAT_COUNT
	)


static func _clamp_original_map_position(
	position: Vector2,
	world_size: Vector2,
) -> Vector2:
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return position
	var result := position
	if result.x <= 0.0:
		result.x = float(MAP_CELL_SIZE.x)
	elif result.x >= world_size.x:
		result.x = world_size.x - float(MAP_CELL_SIZE.x)
	if result.y <= 0.0:
		result.y = float(MAP_CELL_SIZE.y)
	elif result.y >= world_size.y:
		result.y = world_size.y - float(MAP_CELL_SIZE.y)
	return result
