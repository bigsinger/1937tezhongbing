class_name RemakeSimulation
extends RefCounted

const TICK_RATE: int = 60
const FIXED_DELTA: float = 1.0 / float(TICK_RATE)


static func advance_towards(
	current: Vector2, target: Vector2, speed: float, delta: float
) -> Vector2:
	if speed <= 0.0 or delta <= 0.0:
		return current
	var offset: Vector2 = target - current
	var distance: float = offset.length()
	if distance <= 0.001:
		return target
	var travel: float = minf(speed * delta, distance)
	return current + offset / distance * travel


static func formation_offset(index: int, member_count: int, spacing: float = 34.0) -> Vector2:
	if member_count <= 1:
		return Vector2.ZERO
	var columns: int = ceili(sqrt(float(member_count)))
	var row: int = index / columns
	var column: int = index % columns
	var rows: int = ceili(float(member_count) / float(columns))
	var members_in_row: int = mini(columns, member_count - row * columns)
	var weighted_row_sum := 0
	for row_index: int in range(rows):
		weighted_row_sum += row_index * mini(columns, member_count - row_index * columns)
	var mean_row: float = float(weighted_row_sum) / float(member_count)
	return Vector2(
		(float(column) - float(members_in_row - 1) * 0.5) * spacing,
		(float(row) - mean_row) * spacing
	)


static func clamp_formation_center(
	destination: Vector2, offsets: Array[Vector2], bounds: Rect2
) -> Vector2:
	if offsets.is_empty():
		return Vector2(
			clampf(destination.x, bounds.position.x, bounds.end.x),
			clampf(destination.y, bounds.position.y, bounds.end.y)
		)

	var minimum_offset: Vector2 = offsets[0]
	var maximum_offset: Vector2 = offsets[0]
	for offset: Vector2 in offsets:
		minimum_offset = minimum_offset.min(offset)
		maximum_offset = maximum_offset.max(offset)

	return Vector2(
		clampf(
			destination.x, bounds.position.x - minimum_offset.x, bounds.end.x - maximum_offset.x
		),
		clampf(destination.y, bounds.position.y - minimum_offset.y, bounds.end.y - maximum_offset.y)
	)
