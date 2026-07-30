class_name NavigationGridData
extends RefCounted

const FORMAT_VERSION := 1
const HEADER_SIZE := 32
const LAYER_COUNT := 4
const LINE_OF_SIGHT_LAYER_ID := 2
const MOVEMENT_LAYER_ID := 3
const EVENT_LAYER_ID := 4
const MANUAL_CORRECTION_LAYER_ID := 5
const MAGIC_BYTES: Array[int] = [77, 51, 55, 78, 65, 86, 49, 0]
const MAX_DESTINATION_SEARCH_RADIUS := 24
const UNREACHED_SCORE := 0x3fffffff
## M1937 direction order: north, northeast, east, southeast, south,
## southwest, west, northwest. It is also the deterministic expansion order
## used when several uniform-cost routes are equivalent.
const ORIGINAL_NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]

var dimensions := Vector2i.ZERO
var cell_size := Vector2i.ZERO
var layers: Dictionary = {}
var astar: AStarGrid2D
var ignored_scene_indices: Dictionary = {}
var source_scene_cells_by_layer: Dictionary = {}
var released_source_cells_by_layer: Dictionary = {}


static func load_file(path: String, metadata: Dictionary) -> NavigationGridData:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var width := int(metadata.get("width", 0))
	var height := int(metadata.get("height", 0))
	var cell_width := int(metadata.get("cell_width", 0))
	var cell_height := int(metadata.get("cell_height", 0))
	if width <= 0 or height <= 0 or cell_width <= 0 or cell_height <= 0:
		return null
	var expected_length := HEADER_SIZE + LAYER_COUNT * (4 + width * height * 4)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != expected_length:
		return null
	var magic := file.get_buffer(MAGIC_BYTES.size())
	if magic.size() != MAGIC_BYTES.size():
		return null
	for index in range(MAGIC_BYTES.size()):
		if magic[index] != MAGIC_BYTES[index]:
			return null
	if (
		file.get_32() != FORMAT_VERSION
		or file.get_32() != width
		or file.get_32() != height
		or file.get_32() != cell_width
		or file.get_32() != cell_height
		or file.get_32() != LAYER_COUNT
	):
		return null

	var result := NavigationGridData.new()
	result.dimensions = Vector2i(width, height)
	result.cell_size = Vector2i(cell_width, cell_height)
	for expected_layer_id in [
		LINE_OF_SIGHT_LAYER_ID,
		MOVEMENT_LAYER_ID,
		EVENT_LAYER_ID,
		MANUAL_CORRECTION_LAYER_ID,
	]:
		if file.get_32() != expected_layer_id:
			return null
		var values := PackedInt64Array()
		values.resize(width * height)
		for cell_index in range(values.size()):
			values[cell_index] = file.get_32()
		result.layers[expected_layer_id] = values
	if file.get_position() != file.get_length():
		return null
	return result


static func create_for_tests(
	width: int,
	height: int,
	new_cell_size: Vector2i,
	movement_values: PackedInt64Array,
	line_of_sight_values: PackedInt64Array = PackedInt64Array(),
) -> NavigationGridData:
	if (
		width <= 0
		or height <= 0
		or new_cell_size.x <= 0
		or new_cell_size.y <= 0
		or movement_values.size() != width * height
	):
		return null
	var result := NavigationGridData.new()
	result.dimensions = Vector2i(width, height)
	result.cell_size = new_cell_size
	result.layers[MOVEMENT_LAYER_ID] = movement_values.duplicate()
	if line_of_sight_values.is_empty():
		result.layers[LINE_OF_SIGHT_LAYER_ID] = movement_values.duplicate()
	elif line_of_sight_values.size() == width * height:
		result.layers[LINE_OF_SIGHT_LAYER_ID] = line_of_sight_values.duplicate()
	else:
		return null
	result.layers[EVENT_LAYER_ID] = _zero_layer(width * height)
	result.layers[MANUAL_CORRECTION_LAYER_ID] = _zero_layer(width * height)
	return result


static func _zero_layer(size: int) -> PackedInt64Array:
	var values := PackedInt64Array()
	values.resize(size)
	return values


func prepare_astar(
	scene_indices_to_ignore: Array[int] = [],
	movement_cells_to_release: Array[Vector2i] = [],
	sight_cells_to_release: Array[Vector2i] = [],
) -> void:
	ignored_scene_indices.clear()
	for scene_index in scene_indices_to_ignore:
		if scene_index >= 0:
			ignored_scene_indices[scene_index] = true
	released_source_cells_by_layer = {
		MOVEMENT_LAYER_ID: _cell_lookup(movement_cells_to_release),
		LINE_OF_SIGHT_LAYER_ID: _cell_lookup(sight_cells_to_release),
	}
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, dimensions)
	astar.cell_size = Vector2(cell_size)
	astar.offset = Vector2(cell_size) * 0.5
	# Original m000 movement traces permit a diagonal around one blocked
	# cardinal side (for example the tree beside 强子), but never through a
	# corner where both cardinal sides are blocked.
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	# sub_455E30 advances one navigation cell in the same number of actor
	# ticks whether that step is cardinal or diagonal: X and Y are capped
	# independently.  The matching graph metric is therefore Chebyshev
	# (uniform cost for all eight neighboring cells), not Euclidean.
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	astar.update()
	var movement_values := layers[MOVEMENT_LAYER_ID] as PackedInt64Array
	for cell_index in range(movement_values.size()):
		var cell := index_to_cell(cell_index)
		if (
			not is_source_cell_released(MOVEMENT_LAYER_ID, cell)
			and is_blocking_value(
				movement_values[cell_index],
				ignored_scene_indices,
			)
		):
			astar.set_point_solid(cell, true)


func find_path(
	world_start: Vector2,
	world_destination: Vector2,
	allow_scene_occupied_start: bool = false,
) -> PackedVector2Array:
	if world_start.is_equal_approx(world_destination):
		return PackedVector2Array()
	if astar == null:
		prepare_astar()
	var start_cell := world_to_cell(world_start)
	var destination_cell := nearest_walkable_cell(world_to_cell(world_destination))
	if not is_valid_cell(start_cell) or destination_cell.x < 0:
		return PackedVector2Array()
	var temporarily_opened_start := false
	if astar.is_point_solid(start_cell):
		var start_value := movement_value(start_cell)
		if not allow_scene_occupied_start or start_value < 1000:
			return PackedVector2Array()
		astar.set_point_solid(start_cell, false)
		temporarily_opened_start = true
	var path := _original_uniform_path(start_cell, destination_cell)
	path = _canonicalize_equal_cost_steps(path, destination_cell)
	if temporarily_opened_start:
		astar.set_point_solid(start_cell, true)
	if path.is_empty():
		return path
	var resolved_destination_cell := world_to_cell(path[-1])
	if resolved_destination_cell == start_cell and destination_cell != start_cell:
		return PackedVector2Array()
	if path[0].is_equal_approx(world_start):
		path.remove_at(0)
	var requested_destination_cell := world_to_cell(world_destination)
	if (
		is_valid_cell(requested_destination_cell)
		and requested_destination_cell == destination_cell
		and requested_destination_cell == resolved_destination_cell
		and not astar.is_point_solid(requested_destination_cell)
	):
		if path.is_empty() or path[-1].distance_squared_to(world_destination) > 1.0:
			path.append(world_destination)
	return path


func _original_uniform_path(
	start_cell: Vector2i,
	destination_cell: Vector2i,
) -> PackedVector2Array:
	var cell_count := dimensions.x * dimensions.y
	var scores := PackedInt32Array()
	scores.resize(cell_count)
	scores.fill(UNREACHED_SCORE)
	var previous := PackedInt32Array()
	previous.resize(cell_count)
	previous.fill(-1)
	var closed := PackedByteArray()
	closed.resize(cell_count)
	var start_index := cell_to_index(start_cell)
	var destination_index := cell_to_index(destination_cell)
	var insertion_serial := 0
	var heap: Array[Vector4i] = []
	scores[start_index] = 0
	_heap_push(
		heap,
		Vector4i(
			_chebyshev_distance(start_cell, destination_cell),
			_alignment_deviation(
				start_cell,
				start_cell,
				destination_cell,
			),
			insertion_serial,
			start_index,
		),
	)
	insertion_serial += 1
	var best_index := start_index
	var best_heuristic := _chebyshev_distance(
		start_cell,
		destination_cell,
	)
	var best_squared_distance := (
		start_cell - destination_cell
	).length_squared()
	var resolved_index := -1
	while not heap.is_empty():
		var entry := _heap_pop(heap)
		var current_index := entry.w
		if closed[current_index] != 0:
			continue
		var current := index_to_cell(current_index)
		var heuristic := _chebyshev_distance(
			current,
			destination_cell,
		)
		if (
			entry.x != scores[current_index] + heuristic
			or entry.y != _alignment_deviation(
				current,
				start_cell,
				destination_cell,
			)
		):
			continue
		closed[current_index] = 1
		var squared_distance := (
			current - destination_cell
		).length_squared()
		if (
			heuristic < best_heuristic
			or (
				heuristic == best_heuristic
				and squared_distance < best_squared_distance
			)
		):
			best_index = current_index
			best_heuristic = heuristic
			best_squared_distance = squared_distance
		if current_index == destination_index:
			resolved_index = current_index
			break
		for direction: Vector2i in ORIGINAL_NEIGHBOR_DIRECTIONS:
			var neighbor := current + direction
			if not _astar_step_is_clear(current, neighbor):
				continue
			var neighbor_index := cell_to_index(neighbor)
			if closed[neighbor_index] != 0:
				continue
			var next_score := scores[current_index] + 1
			if next_score >= scores[neighbor_index]:
				continue
			scores[neighbor_index] = next_score
			previous[neighbor_index] = current_index
			_heap_push(
				heap,
				Vector4i(
					next_score + _chebyshev_distance(
						neighbor,
						destination_cell,
					),
					_alignment_deviation(
						neighbor,
						start_cell,
						destination_cell,
					),
					insertion_serial,
					neighbor_index,
				),
			)
			insertion_serial += 1
	if resolved_index < 0:
		resolved_index = best_index
	if resolved_index != start_index and previous[resolved_index] < 0:
		return PackedVector2Array()
	var reversed_cells: Array[Vector2i] = []
	var cursor := resolved_index
	while cursor >= 0:
		reversed_cells.append(index_to_cell(cursor))
		if cursor == start_index:
			break
		cursor = previous[cursor]
	if reversed_cells.is_empty() or reversed_cells[-1] != start_cell:
		return PackedVector2Array()
	var result := PackedVector2Array()
	for reversed_index: int in range(
		reversed_cells.size() - 1,
		-1,
		-1,
	):
		result.append(cell_to_world(reversed_cells[reversed_index]))
	return result


static func _chebyshev_distance(
	first: Vector2i,
	second: Vector2i,
) -> int:
	return maxi(
		absi(first.x - second.x),
		absi(first.y - second.y),
	)


static func _alignment_deviation(
	cell: Vector2i,
	start: Vector2i,
	destination: Vector2i,
) -> int:
	var deviation := 0
	if start.x == destination.x:
		deviation += absi(cell.x - start.x)
	if start.y == destination.y:
		deviation += absi(cell.y - start.y)
	return deviation


static func _heap_entry_precedes(
	first: Vector4i,
	second: Vector4i,
) -> bool:
	return (
		first.x < second.x
		or (
			first.x == second.x
			and (
				first.y < second.y
				or (first.y == second.y and first.z < second.z)
			)
		)
	)


static func _heap_push(
	heap: Array[Vector4i],
	entry: Vector4i,
) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2 as int
		if _heap_entry_precedes(heap[parent], entry):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


static func _heap_pop(heap: Array[Vector4i]) -> Vector4i:
	var result := heap[0]
	var tail: Vector4i = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var child := left
		var right := left + 1
		if (
			right < heap.size()
			and _heap_entry_precedes(heap[right], heap[left])
		):
			child = right
		if _heap_entry_precedes(tail, heap[child]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = tail
	return result


func _canonicalize_equal_cost_steps(
	path: PackedVector2Array,
	destination_cell: Vector2i,
) -> PackedVector2Array:
	if path.size() < 3 or astar == null:
		return path
	var result := path.duplicate()
	var start_cell := world_to_cell(result[0])
	# A uniform eight-way search may encounter two opposite diagonals whose
	# minor-axis components cancel. M1937 keeps the straight cardinal pair in
	# this case (for example the first m000 tree-edge route), avoiding a
	# visible one-cell zigzag without changing path cost.
	for index: int in range(result.size() - 2):
		var first := world_to_cell(result[index])
		var middle := world_to_cell(result[index + 1])
		var finish := world_to_cell(result[index + 2])
		var candidate := middle
		if (
			first.x == finish.x
			and absi(finish.y - first.y) == 2
			and middle.x != first.x
		):
			candidate = first + Vector2i(
				0,
				signi(finish.y - first.y),
			)
		elif (
			first.y == finish.y
			and absi(finish.x - first.x) == 2
			and middle.y != first.y
		):
			candidate = first + Vector2i(
				signi(finish.x - first.x),
				0,
			)
		if (
			candidate != middle
			and _astar_step_is_clear(first, candidate)
			and _astar_step_is_clear(candidate, finish)
		):
			result[index + 1] = cell_to_world(candidate)
	# AStarGrid2D can return any of several equal-cost staircases. Stable MOD
	# m000 traces return from a one-cell obstacle detour as soon as the
	# original corridor is clear. They also place a same-direction vertical
	# step before the remaining diagonals: this makes the final movement
	# octant (and therefore the retained idle facing) match the original.
	for _pass_index: int in range(result.size()):
		var changed := false
		for index: int in range(result.size() - 2):
			var first := world_to_cell(result[index])
			var middle := world_to_cell(result[index + 1])
			var finish := world_to_cell(result[index + 2])
			var first_step := middle - first
			var second_step := finish - middle
			if (
				first_step == second_step
				or maxi(absi(first_step.x), absi(first_step.y)) != 1
				or maxi(absi(second_step.x), absi(second_step.y)) != 1
			):
				continue
			var candidate := first + second_step
			if candidate == middle or candidate == first or candidate == finish:
				continue
			if not _reduces_wrong_way_detour(
				middle,
				candidate,
				start_cell,
				destination_cell,
			):
				continue
			if not _astar_step_is_clear(first, candidate):
				continue
			if not _astar_step_is_clear(candidate, finish):
				continue
			result[index + 1] = cell_to_world(candidate)
			changed = true
		if not changed:
			break
	# Run the vertical-first pass separately. Combining both transforms in one
	# loop can make an obstacle-detour correction and a staircase correction
	# undo one another on alternating passes.
	for _pass_index: int in range(result.size()):
		var changed := false
		for index: int in range(result.size() - 2):
			var first := world_to_cell(result[index])
			var middle := world_to_cell(result[index + 1])
			var finish := world_to_cell(result[index + 2])
			var first_step := middle - first
			var second_step := finish - middle
			if not _restores_vertical_first_order(
				first_step,
				second_step,
				first,
				destination_cell,
			):
				continue
			var candidate := first + second_step
			if (
				_reduces_wrong_way_detour(
					candidate,
					middle,
					start_cell,
					destination_cell,
				)
				or
				not _astar_step_is_clear(first, candidate)
				or not _astar_step_is_clear(candidate, finish)
			):
				continue
			result[index + 1] = cell_to_world(candidate)
			changed = true
		if not changed:
			break
	return result


func _restores_vertical_first_order(
	first_step: Vector2i,
	second_step: Vector2i,
	first: Vector2i,
	destination: Vector2i,
) -> bool:
	if (
		absi(first_step.x) != 1
		or absi(first_step.y) != 1
		or second_step.x != 0
		or absi(second_step.y) != 1
		or first_step.y != second_step.y
	):
		return false
	var remaining := destination - first
	return (
		remaining.x != 0
		and remaining.y != 0
		and first_step.x * remaining.x > 0
		and second_step.y * remaining.y > 0
	)


func _astar_step_is_clear(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if (
		not is_valid_cell(from_cell)
		or not is_valid_cell(to_cell)
		or astar.is_point_solid(to_cell)
	):
		return false
	var delta := to_cell - from_cell
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		return false
	if delta.x == 0 or delta.y == 0:
		return true
	var side_x := Vector2i(to_cell.x, from_cell.y)
	var side_y := Vector2i(from_cell.x, to_cell.y)
	return (
		not astar.is_point_solid(side_x)
		or not astar.is_point_solid(side_y)
	)


func _reduces_wrong_way_detour(
	current: Vector2i,
	candidate: Vector2i,
	start: Vector2i,
	destination: Vector2i,
) -> bool:
	var improves := false
	for axis: int in range(2):
		var target_delta := destination[axis] - start[axis]
		var current_delta := current[axis] - start[axis]
		var candidate_delta := candidate[axis] - start[axis]
		var current_is_wrong := (
			current_delta != 0
			and (target_delta == 0 or current_delta * target_delta < 0)
		)
		var candidate_is_wrong := (
			candidate_delta != 0
			and (target_delta == 0 or candidate_delta * target_delta < 0)
		)
		if candidate_is_wrong and absi(candidate_delta) > absi(current_delta):
			return false
		if current_is_wrong and absi(candidate_delta) < absi(current_delta):
			improves = true
	return improves


func nearest_walkable_cell(requested: Vector2i) -> Vector2i:
	if astar == null:
		return Vector2i(-1, -1)
	var clamped := Vector2i(
		clampi(requested.x, 0, dimensions.x - 1),
		clampi(requested.y, 0, dimensions.y - 1),
	)
	if not astar.is_point_solid(clamped):
		return clamped
	for radius in range(1, MAX_DESTINATION_SEARCH_RADIUS + 1):
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for y in range(clamped.y - radius, clamped.y + radius + 1):
			for x in range(clamped.x - radius, clamped.x + radius + 1):
				if (
					x < 0
					or y < 0
					or x >= dimensions.x
					or y >= dimensions.y
					or (abs(x - clamped.x) != radius and abs(y - clamped.y) != radius)
				):
					continue
				var candidate := Vector2i(x, y)
				if astar.is_point_solid(candidate):
					continue
				var distance := Vector2(candidate - clamped).length_squared()
				if distance < best_distance:
					best_distance = distance
					best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func has_line_of_sight(
	world_origin: Vector2,
	world_target: Vector2,
	scene_indices_to_ignore: Array = [],
) -> bool:
	var ignored: Dictionary = {}
	for scene_index_value: Variant in scene_indices_to_ignore:
		var scene_index := int(scene_index_value)
		if scene_index >= 0:
			ignored[scene_index] = true
	var start := world_to_cell(world_origin)
	var finish := world_to_cell(world_target)
	if not is_valid_cell(start) or not is_valid_cell(finish):
		return false
	var x := start.x
	var y := start.y
	var delta_x := absi(finish.x - start.x)
	var delta_y := absi(finish.y - start.y)
	var step_x := 1 if x < finish.x else -1
	var step_y := 1 if y < finish.y else -1
	var error := delta_x - delta_y
	while true:
		var cell := Vector2i(x, y)
		if is_line_of_sight_blocked(cell, ignored):
			return false
		if x == finish.x and y == finish.y:
			return true
		var doubled_error := error * 2
		var moves_horizontally := doubled_error > -delta_y
		var moves_vertically := doubled_error < delta_x
		if moves_horizontally and moves_vertically:
			if (
				is_line_of_sight_blocked(Vector2i(x + step_x, y), ignored)
				or is_line_of_sight_blocked(Vector2i(x, y + step_y), ignored)
			):
				return false
		if moves_horizontally:
			error -= delta_y
			x += step_x
		if moves_vertically:
			error += delta_x
			y += step_y
	return true


func is_line_of_sight_blocked(cell: Vector2i, ignored: Dictionary = {}) -> bool:
	if not is_valid_cell(cell):
		return true
	if is_source_cell_released(LINE_OF_SIGHT_LAYER_ID, cell):
		return false
	return is_blocking_value(source_value(LINE_OF_SIGHT_LAYER_ID, cell), ignored)


func is_movement_blocked(cell: Vector2i, ignored: Dictionary = {}) -> bool:
	if not is_valid_cell(cell):
		return true
	if is_source_cell_released(MOVEMENT_LAYER_ID, cell):
		return false
	return is_blocking_value(movement_value(cell), ignored)


func is_source_cell_released(layer_id: int, cell: Vector2i) -> bool:
	if not released_source_cells_by_layer.has(layer_id):
		return false
	return (
		released_source_cells_by_layer[layer_id] as Dictionary
	).has(cell)


func movement_value(cell: Vector2i) -> int:
	return source_value(MOVEMENT_LAYER_ID, cell)


func source_value(layer_id: int, cell: Vector2i) -> int:
	if not is_valid_cell(cell) or not layers.has(layer_id):
		return -1
	var values := layers[layer_id] as PackedInt64Array
	return values[cell_to_index(cell)]


func source_cells_for_scene(layer_id: int, scene_index: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if scene_index < 0 or not layers.has(layer_id):
		return cells
	if not source_scene_cells_by_layer.has(layer_id):
		_build_source_scene_cell_index(layer_id)
	var layer_index := source_scene_cells_by_layer.get(layer_id, {}) as Dictionary
	if not layer_index.has(scene_index):
		return cells
	for cell_value: Variant in layer_index[scene_index] as Array:
		cells.append(cell_value as Vector2i)
	return cells


func _build_source_scene_cell_index(layer_id: int) -> void:
	var layer_index: Dictionary = {}
	var values := layers[layer_id] as PackedInt64Array
	for cell_index in range(values.size()):
		var encoded := int(values[cell_index])
		if encoded < 1000:
			continue
		var scene_index := encoded - 1000
		var scene_cells: Array[Vector2i] = []
		if layer_index.has(scene_index):
			for cell_value: Variant in layer_index[scene_index] as Array:
				scene_cells.append(cell_value as Vector2i)
		scene_cells.append(index_to_cell(cell_index))
		layer_index[scene_index] = scene_cells
	source_scene_cells_by_layer[layer_id] = layer_index


static func is_blocking_value(value: int, ignored: Dictionary) -> bool:
	if value == 0:
		return false
	if value >= 1000 and ignored.has(value - 1000):
		return false
	return true


static func _cell_lookup(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in cells:
		result[cell] = true
	return result


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(cell_size.x)),
		floori(world_position.y / float(cell_size.y)),
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * float(cell_size.x),
		(float(cell.y) + 0.5) * float(cell_size.y),
	)


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < dimensions.x and cell.y < dimensions.y


func cell_to_index(cell: Vector2i) -> int:
	return cell.y * dimensions.x + cell.x


func index_to_cell(index: int) -> Vector2i:
	return Vector2i(index % dimensions.x, floori(float(index) / float(dimensions.x)))
