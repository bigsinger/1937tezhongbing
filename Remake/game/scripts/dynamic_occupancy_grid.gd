class_name DynamicOccupancyGrid
extends RefCounted

const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const MOVEMENT_SAMPLE_PIXELS := 4.0
const MIN_ACTOR_SEPARATION := 12.0

var navigation: RefCounted
var actors: Dictionary = {}
var disabled_source_scenes: Dictionary = {}
var movement_owners: Dictionary = {}
var sight_owners: Dictionary = {}
var goal_owners: Dictionary = {}
var accepted_moves: Array[Dictionary] = []
var accepted_moves_physics_frame := -1
var path_query_count := 0
var path_query_elapsed_usec := 0
var relocation_rejection_count := 0


func configure(source_navigation: RefCounted) -> void:
	navigation = source_navigation
	actors.clear()
	disabled_source_scenes.clear()
	movement_owners.clear()
	sight_owners.clear()
	goal_owners.clear()
	accepted_moves.clear()
	accepted_moves_physics_frame = -1
	path_query_count = 0
	path_query_elapsed_usec = 0
	relocation_rejection_count = 0


func register_scene(
	scene_index: int,
	world_position: Vector2,
	source_reference_world_position: Variant = null,
) -> bool:
	if navigation == null or scene_index < 0:
		return false
	if actors.has(scene_index):
		unregister_scene(scene_index, false)
	var origin: Vector2i = navigation.world_to_cell(world_position)
	if not navigation.is_valid_cell(origin):
		return false
	var source_origin := origin
	if source_reference_world_position is Vector2:
		source_origin = navigation.world_to_cell(source_reference_world_position as Vector2)
	var movement_offsets := _source_offsets(
		NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID, scene_index, source_origin
	)
	var sight_offsets := _source_offsets(
		NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID, scene_index, source_origin
	)
	var actor := {
		"scene_index": scene_index,
		"world_position": world_position,
		"origin": origin,
		"source_origin": source_origin,
		"movement_offsets": movement_offsets,
		"sight_offsets": sight_offsets,
	}
	actors[scene_index] = actor
	disabled_source_scenes[scene_index] = true
	_add_footprint(movement_owners, scene_index, origin, movement_offsets)
	_add_footprint(sight_owners, scene_index, origin, sight_offsets)
	return true


func finalize_registration() -> void:
	if navigation == null:
		return
	var scene_indices: Array[int] = []
	for scene_index: Variant in disabled_source_scenes.keys():
		scene_indices.append(int(scene_index))
	scene_indices.sort()
	navigation.prepare_astar(scene_indices)


func unregister_scene(scene_index: int, keep_source_disabled: bool = true) -> void:
	if not actors.has(scene_index):
		return
	var actor := actors[scene_index] as Dictionary
	_remove_footprint(
		movement_owners,
		scene_index,
		actor["origin"] as Vector2i,
		actor["movement_offsets"] as Array[Vector2i],
	)
	_remove_footprint(
		sight_owners,
		scene_index,
		actor["origin"] as Vector2i,
		actor["sight_offsets"] as Array[Vector2i],
	)
	actors.erase(scene_index)
	_clear_goal(scene_index)
	if not keep_source_disabled:
		disabled_source_scenes.erase(scene_index)


func find_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> PackedVector2Array:
	if navigation == null or not actors.has(scene_index):
		return PackedVector2Array()
	var query_started := Time.get_ticks_usec()
	_clear_goal(scene_index)
	var actor := actors[scene_index] as Dictionary
	var movement_offsets := actor["movement_offsets"] as Array[Vector2i]
	var changed_solids: Array[Vector2i] = []
	var start_cell: Vector2i = navigation.world_to_cell(world_start)
	var needs_actor_clearance := (
		movement_offsets.size() != 1 or movement_offsets[0] != Vector2i.ZERO
	)
	if needs_actor_clearance:
		for y in range(navigation.dimensions.y):
			for x in range(navigation.dimensions.x):
				var candidate := Vector2i(x, y)
				if candidate == start_cell:
					continue
				for offset: Vector2i in movement_offsets:
					if _source_movement_blocked(candidate + offset):
						_mark_temporary_solid(candidate, changed_solids)
						break
	for cell_value: Variant in movement_owners.keys():
		var cell := cell_value as Vector2i
		if not _has_other_owner(movement_owners, cell, scene_index):
			continue
		for offset: Vector2i in movement_offsets:
			var candidate := cell - offset
			if candidate != start_cell:
				_mark_temporary_solid(candidate, changed_solids)
	for cell_value: Variant in goal_owners.keys():
		var cell := cell_value as Vector2i
		if int(goal_owners[cell]) == scene_index:
			continue
		for offset: Vector2i in movement_offsets:
			var candidate := cell - offset
			if candidate != start_cell:
				_mark_temporary_solid(candidate, changed_solids)
	var path: PackedVector2Array = navigation.find_path(world_start, world_destination, true)
	for cell: Vector2i in changed_solids:
		navigation.astar.set_point_solid(cell, false)
	if not path.is_empty():
		var goal_origin: Vector2i = navigation.world_to_cell(path[-1])
		for offset: Vector2i in movement_offsets:
			goal_owners[goal_origin + offset] = scene_index
	path_query_count += 1
	path_query_elapsed_usec += Time.get_ticks_usec() - query_started
	return path


func release_goal(scene_index: int) -> void:
	_clear_goal(scene_index)


func try_relocate(scene_index: int, new_world_position: Vector2) -> bool:
	if navigation == null or not actors.has(scene_index):
		return false
	_sync_move_reservations()
	var actor := actors[scene_index] as Dictionary
	var old_world_position := actor["world_position"] as Vector2
	var old_origin := actor["origin"] as Vector2i
	var new_origin: Vector2i = navigation.world_to_cell(new_world_position)
	if absi(new_origin.x - old_origin.x) > 1 or absi(new_origin.y - old_origin.y) > 1:
		relocation_rejection_count += 1
		return false
	if not _can_traverse(scene_index, actor, old_world_position, new_world_position):
		relocation_rejection_count += 1
		return false
	if not _keeps_actor_separation(scene_index, old_world_position, new_world_position):
		relocation_rejection_count += 1
		return false
	if _crosses_reserved_diagonal(old_origin, new_origin):
		relocation_rejection_count += 1
		return false
	if new_origin != old_origin:
		_remove_footprint(
			movement_owners,
			scene_index,
			old_origin,
			actor["movement_offsets"] as Array[Vector2i],
		)
		_remove_footprint(
			sight_owners,
			scene_index,
			old_origin,
			actor["sight_offsets"] as Array[Vector2i],
		)
		_add_footprint(
			movement_owners,
			scene_index,
			new_origin,
			actor["movement_offsets"] as Array[Vector2i],
		)
		_add_footprint(
			sight_owners,
			scene_index,
			new_origin,
			actor["sight_offsets"] as Array[Vector2i],
		)
	actor["origin"] = new_origin
	actor["world_position"] = new_world_position
	actors[scene_index] = actor
	if new_origin != old_origin:
		accepted_moves.append({"from": old_origin, "to": new_origin})
	return true


func has_line_of_sight(
	world_origin: Vector2,
	world_target: Vector2,
	scene_indices_to_ignore: Array = [],
) -> bool:
	if navigation == null:
		return false
	var ignored: Dictionary = {}
	for scene_index_value: Variant in scene_indices_to_ignore:
		ignored[int(scene_index_value)] = true
	var start: Vector2i = navigation.world_to_cell(world_origin)
	var finish: Vector2i = navigation.world_to_cell(world_target)
	if not navigation.is_valid_cell(start) or not navigation.is_valid_cell(finish):
		return false
	var x: int = start.x
	var y: int = start.y
	var delta_x := absi(finish.x - start.x)
	var delta_y := absi(finish.y - start.y)
	var step_x := 1 if x < finish.x else -1
	var step_y := 1 if y < finish.y else -1
	var error := delta_x - delta_y
	while true:
		if _sight_blocked(Vector2i(x, y), ignored):
			return false
		if x == finish.x and y == finish.y:
			return true
		var doubled_error := error * 2
		var moves_horizontally := doubled_error > -delta_y
		var moves_vertically := doubled_error < delta_x
		if moves_horizontally and moves_vertically:
			if (
				_sight_blocked(Vector2i(x + step_x, y), ignored)
				or _sight_blocked(Vector2i(x, y + step_y), ignored)
			):
				return false
		if moves_horizontally:
			error -= delta_y
			x += step_x
		if moves_vertically:
			error += delta_x
			y += step_y
	return true


func runtime_movement_owner(cell: Vector2i) -> int:
	if not movement_owners.has(cell):
		return -1
	var owners := movement_owners[cell] as Dictionary
	var sorted_owners := owners.keys()
	sorted_owners.sort()
	return int(sorted_owners[0]) if not sorted_owners.is_empty() else -1


func actor_cell(scene_index: int) -> Vector2i:
	if not actors.has(scene_index):
		return Vector2i(-1, -1)
	return (actors[scene_index] as Dictionary)["origin"] as Vector2i


func _source_offsets(layer_id: int, scene_index: int, origin: Vector2i) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var source_cells: Array[Vector2i] = navigation.source_cells_for_scene(layer_id, scene_index)
	var source_lookup: Dictionary = {}
	for cell: Vector2i in source_cells:
		source_lookup[cell] = true
	if source_lookup.has(origin):
		var pending: Array[Vector2i] = [origin]
		var visited: Dictionary = {origin: true}
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			offsets.append(cell - origin)
			for y_offset in range(-1, 2):
				for x_offset in range(-1, 2):
					if x_offset == 0 and y_offset == 0:
						continue
					var neighbor := cell + Vector2i(x_offset, y_offset)
					if source_lookup.has(neighbor) and not visited.has(neighbor):
						visited[neighbor] = true
						pending.append(neighbor)
	if offsets.is_empty():
		offsets.append(Vector2i.ZERO)
	offsets.sort()
	return offsets


func _add_footprint(
	owner_map: Dictionary,
	scene_index: int,
	origin: Vector2i,
	offsets: Array[Vector2i],
) -> void:
	for offset: Vector2i in offsets:
		var cell := origin + offset
		var owners := owner_map.get(cell, {}) as Dictionary
		owners[scene_index] = true
		owner_map[cell] = owners


func _remove_footprint(
	owner_map: Dictionary,
	scene_index: int,
	origin: Vector2i,
	offsets: Array[Vector2i],
) -> void:
	for offset: Vector2i in offsets:
		var cell := origin + offset
		if not owner_map.has(cell):
			continue
		var owners := owner_map[cell] as Dictionary
		owners.erase(scene_index)
		if owners.is_empty():
			owner_map.erase(cell)
		else:
			owner_map[cell] = owners


func _can_traverse(
	scene_index: int,
	actor: Dictionary,
	old_world_position: Vector2,
	new_world_position: Vector2,
) -> bool:
	var old_origin := actor["origin"] as Vector2i
	var movement_offsets := actor["movement_offsets"] as Array[Vector2i]
	var steps := maxi(
		ceili(old_world_position.distance_to(new_world_position) / MOVEMENT_SAMPLE_PIXELS), 1
	)
	var previous_origin := old_origin
	for step in range(steps + 1):
		var sample := old_world_position.lerp(new_world_position, float(step) / float(steps))
		var sample_origin: Vector2i = navigation.world_to_cell(sample)
		if sample_origin != previous_origin:
			if (
				absi(sample_origin.x - previous_origin.x) > 1
				or absi(sample_origin.y - previous_origin.y) > 1
				or not _diagonal_transition_is_clear(
					scene_index, previous_origin, sample_origin, movement_offsets
				)
			):
				return false
			previous_origin = sample_origin
		for offset: Vector2i in movement_offsets:
			var cell: Vector2i = sample_origin + offset
			if not navigation.is_valid_cell(cell):
				return false
			if sample_origin != old_origin and _source_movement_blocked(cell):
				return false
			if sample_origin != old_origin and _has_other_owner(movement_owners, cell, scene_index):
				return false
	return true


func _diagonal_transition_is_clear(
	scene_index: int,
	from_origin: Vector2i,
	to_origin: Vector2i,
	movement_offsets: Array[Vector2i],
) -> bool:
	if (
		absi(to_origin.x - from_origin.x) != 1
		or absi(to_origin.y - from_origin.y) != 1
	):
		return true
	if _crosses_reserved_diagonal(from_origin, to_origin):
		return false
	var side_origins: Array[Vector2i] = [
		Vector2i(to_origin.x, from_origin.y),
		Vector2i(from_origin.x, to_origin.y),
	]
	for side_origin: Vector2i in side_origins:
		for offset: Vector2i in movement_offsets:
			var side_cell := side_origin + offset
			if (
				_source_movement_blocked(side_cell)
				or _has_other_owner(movement_owners, side_cell, scene_index)
			):
				return false
	return true


func _mark_temporary_solid(cell: Vector2i, changed_solids: Array[Vector2i]) -> void:
	if (
		not navigation.is_valid_cell(cell)
		or navigation.astar.is_point_solid(cell)
	):
		return
	navigation.astar.set_point_solid(cell, true)
	changed_solids.append(cell)


func _source_movement_blocked(cell: Vector2i) -> bool:
	var value: int = navigation.movement_value(cell)
	if value == 0:
		return false
	return value < 1000 or not disabled_source_scenes.has(value - 1000)


func _has_other_owner(owner_map: Dictionary, cell: Vector2i, scene_index: int) -> bool:
	if not owner_map.has(cell):
		return false
	var owners := owner_map[cell] as Dictionary
	for owner: Variant in owners.keys():
		if int(owner) != scene_index:
			return true
	return false


func _keeps_actor_separation(
	scene_index: int,
	old_world_position: Vector2,
	new_world_position: Vector2,
) -> bool:
	for other_scene_value: Variant in actors.keys():
		var other_scene := int(other_scene_value)
		if other_scene == scene_index:
			continue
		var other_position := (actors[other_scene] as Dictionary)["world_position"] as Vector2
		var old_distance := old_world_position.distance_to(other_position)
		var new_distance := new_world_position.distance_to(other_position)
		if new_distance < MIN_ACTOR_SEPARATION and new_distance <= old_distance:
			return false
	return true


func _sync_move_reservations() -> void:
	var current_frame := int(Engine.get_physics_frames())
	if current_frame != accepted_moves_physics_frame:
		accepted_moves_physics_frame = current_frame
		accepted_moves.clear()


func _crosses_reserved_diagonal(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if absi(to_cell.x - from_cell.x) != 1 or absi(to_cell.y - from_cell.y) != 1:
		return false
	for move: Dictionary in accepted_moves:
		var other_from := move["from"] as Vector2i
		var other_to := move["to"] as Vector2i
		if (
			absi(other_to.x - other_from.x) == 1
			and absi(other_to.y - other_from.y) == 1
			and from_cell + to_cell == other_from + other_to
		):
			return true
	return false


func _sight_blocked(cell: Vector2i, ignored: Dictionary) -> bool:
	if not navigation.is_valid_cell(cell):
		return true
	var source_value: int = navigation.source_value(
		NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID, cell
	)
	if source_value != 0:
		var source_scene: int = source_value - 1000
		if (
			source_value < 1000
			or (not disabled_source_scenes.has(source_scene) and not ignored.has(source_scene))
		):
			return true
	if not sight_owners.has(cell):
		return false
	var owners := sight_owners[cell] as Dictionary
	for owner: Variant in owners.keys():
		if not ignored.has(int(owner)):
			return true
	return false


func _clear_goal(scene_index: int) -> void:
	var cells_to_clear: Array[Vector2i] = []
	for cell_value: Variant in goal_owners.keys():
		var cell := cell_value as Vector2i
		if int(goal_owners[cell]) == scene_index:
			cells_to_clear.append(cell)
	for cell: Vector2i in cells_to_clear:
		goal_owners.erase(cell)
