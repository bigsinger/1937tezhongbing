class_name StealthRiskField
extends RefCounted

const CELL_SIZE := Vector2(32.0, 16.0)
const MAX_CACHED_CELLS := 32768

var signature := ""
var cells: Dictionary = {}
var cache_hits := 0
var cache_misses := 0


func segment_risk(
	from: Vector2,
	to: Vector2,
	world_signature: String,
	sampler: Callable,
) -> float:
	if signature != world_signature:
		signature = world_signature
		cells.clear()
	var distance := from.distance_to(to)
	var sample_count := clampi(ceili(distance / minf(CELL_SIZE.x, CELL_SIZE.y)), 1, 128)
	var maximum := 0.0
	for index: int in range(sample_count + 1):
		var point := from.lerp(to, float(index) / float(sample_count))
		var cell := Vector2i(floori(point.x / CELL_SIZE.x), floori(point.y / CELL_SIZE.y))
		if cells.has(cell):
			cache_hits += 1
		else:
			cache_misses += 1
			if cells.size() >= MAX_CACHED_CELLS:
				cells.clear()
			cells[cell] = clampf(float(sampler.call(Vector2(
				(float(cell.x) + 0.5) * CELL_SIZE.x,
				(float(cell.y) + 0.5) * CELL_SIZE.y,
			))), 0.0, 1.0)
		maximum = maxf(maximum, float(cells[cell]))
		if maximum >= 1.0:
			break
	return maximum


func clear() -> void:
	signature = ""
	cells.clear()


func stats() -> Dictionary:
	return {
		"cell_count": cells.size(),
		"cache_hits": cache_hits,
		"cache_misses": cache_misses,
	}
