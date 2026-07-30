class_name LegacyExplosionVisualRules
extends RefCounted

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

const FAMILY_PROFILES := {
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
	var state := initial_state & UINT32_MASK
	var draw := next_crt_rand(state)
	state = int(draw["state"])
	var attempted_count := maxi(
		int(draw["value"]) % PARTICLE_COUNT_MODULUS,
		PARTICLE_MINIMUM_COUNT,
	)
	var particles: Array[Dictionary] = []
	var runtime_types := family.get("runtime_actor_types", []) as Array
	for unused_index: int in range(attempted_count):
		draw = next_crt_rand(state)
		state = int(draw["state"])
		var runtime_actor_type := int(
			runtime_types[int(draw["value"]) % runtime_types.size()]
		)
		draw = next_crt_rand(state)
		state = int(draw["state"])
		var subtract_x := int(draw["value"]) % 2 != 0
		draw = next_crt_rand(state)
		state = int(draw["state"])
		var subtract_y := int(draw["value"]) % 2 != 0
		draw = next_crt_rand(state)
		state = int(draw["state"])
		var x_offset := int(draw["value"]) % SPREAD_HORIZONTAL_RADIUS
		draw = next_crt_rand(state)
		state = int(draw["state"])
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
		# Missing runtime type 102 reproduces sub_44A350 returning null. The
		# random draws still occurred, but no particle enters the effect list.
		if int(profile.get("gfl_index", -1)) < 0:
			continue
		particles.append({
			"runtime_actor_type": runtime_actor_type,
			"gfl_index": int(profile["gfl_index"]),
			"world_position": particle_position,
			"frame_count": int(profile["frame_count"]),
			"frame_hold_ticks": int(profile["frame_hold_ticks"]),
			"anchor": profile["anchor"] as Vector2,
			"repeat_count": PARTICLE_REPEAT_COUNT,
		})
	return {
		"effect_family": effect_family,
		"attempted_particle_count": attempted_count,
		"particles": particles,
		"next_random_state": state,
	}


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
