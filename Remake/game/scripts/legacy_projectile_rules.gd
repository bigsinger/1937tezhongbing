class_name LegacyProjectileRules
extends RefCounted

## Exact path/timing primitives recovered from M1937.exe's 0x44-byte
## projectile object (sub_463290/sub_4635F0/sub_463A00).

const WORLD_TICKS_PER_SECOND := 60
const ORIGINAL_CELL_SIZE := Vector2i(32, 16)


static func build_inclusive_bresenham_path(
	start_position: Vector2,
	destination: Vector2,
) -> PackedVector2Array:
	# The original arguments and path records are signed 32-bit integers.
	var start := Vector2i(int(start_position.x), int(start_position.y))
	var finish := Vector2i(int(destination.x), int(destination.y))
	var major_value := start.x
	var minor_value := start.y
	var major_delta := absi(finish.x - start.x)
	var minor_delta := absi(finish.y - start.y)
	var major_step := -1 if finish.x - start.x <= 0 else 1
	var minor_step := -1 if finish.y - start.y <= 0 else 1
	var swapped := false
	if minor_delta > major_delta:
		var swapped_value := major_value
		major_value = minor_value
		minor_value = swapped_value
		var swapped_delta := major_delta
		major_delta = minor_delta
		minor_delta = swapped_delta
		var swapped_step := major_step
		major_step = minor_step
		minor_step = swapped_step
		swapped = true
	var doubled_minor := 2 * minor_delta
	var error := doubled_minor - major_delta
	var result := PackedVector2Array()
	for unused_index: int in range(major_delta):
		result.append(
			Vector2(minor_value, major_value)
			if swapped
			else Vector2(major_value, minor_value)
		)
		while error >= 0:
			minor_value += minor_step
			error -= 2 * major_delta
		major_value += major_step
		error += doubled_minor
	result.append(Vector2(finish))
	return result


static func original_arc_coefficient(
	path_point_count: int,
	world_step_pixels: int,
) -> float:
	var safe_step := maxi(world_step_pixels, 1)
	var integer_denominator := path_point_count / safe_step
	if integer_denominator <= 0:
		# The shipped weapon ranges produce a non-zero quotient. This guard only
		# keeps synthetic zero-distance tests deterministic.
		return float(safe_step)
	return float(safe_step) / float(integer_denominator)


static func original_arc_height(
	world_step_pixels: int,
	arc_tick: int,
	coefficient: float,
) -> float:
	# __ftol truncates the quadratic term before it is subtracted.
	return float(
		world_step_pixels * arc_tick
		- int(float(arc_tick) * coefficient * float(arc_tick))
	)


static func path_resolution_world_ticks(
	path_point_count: int,
	world_step_pixels: int,
) -> int:
	if path_point_count <= 0:
		return 0
	return ceili(float(path_point_count - 1) / float(maxi(world_step_pixels, 1))) + 1


static func world_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(ORIGINAL_CELL_SIZE.x)),
		floori(world_position.y / float(ORIGINAL_CELL_SIZE.y)),
	)
