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

var dimensions := Vector2i.ZERO
var cell_size := Vector2i.ZERO
var layers: Dictionary = {}
var astar: AStarGrid2D
var ignored_scene_indices: Dictionary = {}
var source_scene_cells_by_layer: Dictionary = {}


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


func prepare_astar(scene_indices_to_ignore: Array[int] = []) -> void:
	ignored_scene_indices.clear()
	for scene_index in scene_indices_to_ignore:
		if scene_index >= 0:
			ignored_scene_indices[scene_index] = true
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, dimensions)
	astar.cell_size = Vector2(cell_size)
	astar.offset = Vector2(cell_size) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	var movement_values := layers[MOVEMENT_LAYER_ID] as PackedInt64Array
	for cell_index in range(movement_values.size()):
		if is_blocking_value(movement_values[cell_index], ignored_scene_indices):
			astar.set_point_solid(index_to_cell(cell_index), true)


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
	var path := astar.get_point_path(start_cell, destination_cell, true)
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
	return is_blocking_value(source_value(LINE_OF_SIGHT_LAYER_ID, cell), ignored)


func is_movement_blocked(cell: Vector2i, ignored: Dictionary = {}) -> bool:
	if not is_valid_cell(cell):
		return true
	return is_blocking_value(movement_value(cell), ignored)


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
