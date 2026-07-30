class_name DynamicOccupancyGrid
extends RefCounted

const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const MOVEMENT_SAMPLE_PIXELS := 4.0
const MIN_ACTOR_SEPARATION := 12.0
## Dynamic actors still collide and reserve moves in try_relocate(). On dense
## original maps, treating every current actor cell as a hard A* wall can split
## an otherwise connected static component and force a full-map GDScript search
## (measured at 126-464 ms). Only when both the actor roster and occupied-cell
## overlay exceed this limit do we plan against authored Layer 3 and enforce
## live separation during movement instead. A few large footprints must not
## make an otherwise sparse mission lose its original dynamic routing.
const MAX_DYNAMIC_PATH_OBSTACLE_CELLS := 64
## A small set of formal-map actors and vehicles has its connected L2/L3
## footprint one cell away from the serialized reference cell. Larger
## distances indicate a stale/reused scene reference and must not create an
## unbounded runtime footprint.
const MAX_SOURCE_ANCHOR_DISTANCE := 1

var navigation: RefCounted
var actors: Dictionary = {}
var actor_origin_owners: Dictionary = {}
var disabled_source_scenes: Dictionary = {}
var source_scene_footprints: Dictionary = {}
var movement_owners: Dictionary = {}
var sight_owners: Dictionary = {}
var goal_owners: Dictionary = {}
var footprint_blocked_origins: Dictionary = {}
var footprint_blocked_origin_lookups: Dictionary = {}
var footprint_offsets_by_key: Dictionary = {}
var footprint_clearance_precompute_usec := 0
var footprint_clearance_incremental_usec := 0
var prewarmed_paths: Dictionary = {}
var prewarmed_path_build_count := 0
var prewarmed_path_hit_count := 0
var prewarmed_path_suffix_hit_count := 0
var last_prewarmed_path_nearest_distance := -1
var accepted_moves: Array[Dictionary] = []
var accepted_diagonal_crossings: Dictionary = {}
var accepted_moves_physics_frame := -1
var path_query_count := 0
var path_query_elapsed_usec := 0
var last_path_query_scene_index := -1
var last_path_query_elapsed_usec := 0
var path_query_profiles: Dictionary = {}
var dense_path_fallback_count := 0
var relocation_rejection_count := 0


func configure(source_navigation: RefCounted) -> void:
	navigation = source_navigation
	actors.clear()
	actor_origin_owners.clear()
	disabled_source_scenes.clear()
	source_scene_footprints.clear()
	movement_owners.clear()
	sight_owners.clear()
	goal_owners.clear()
	footprint_blocked_origins.clear()
	footprint_blocked_origin_lookups.clear()
	footprint_offsets_by_key.clear()
	footprint_clearance_precompute_usec = 0
	footprint_clearance_incremental_usec = 0
	prewarmed_paths.clear()
	prewarmed_path_build_count = 0
	prewarmed_path_hit_count = 0
	prewarmed_path_suffix_hit_count = 0
	last_prewarmed_path_nearest_distance = -1
	accepted_moves.clear()
	accepted_diagonal_crossings.clear()
	accepted_moves_physics_frame = -1
	path_query_count = 0
	path_query_elapsed_usec = 0
	last_path_query_scene_index = -1
	last_path_query_elapsed_usec = 0
	path_query_profiles.clear()
	dense_path_fallback_count = 0
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
	_add_actor_origin_owner(scene_index, origin)
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
	var movement_release_lookup: Dictionary = {}
	var sight_release_lookup: Dictionary = {}
	for scene_index: int in scene_indices:
		if not source_scene_footprints.has(scene_index):
			continue
		var footprint := source_scene_footprints[scene_index] as Dictionary
		for cell: Vector2i in footprint.get("movement", []) as Array[Vector2i]:
			movement_release_lookup[cell] = true
		for cell: Vector2i in footprint.get("sight", []) as Array[Vector2i]:
			sight_release_lookup[cell] = true
	var movement_cells: Array[Vector2i] = []
	for cell_value: Variant in movement_release_lookup.keys():
		movement_cells.append(cell_value as Vector2i)
	movement_cells.sort()
	var sight_cells: Array[Vector2i] = []
	for cell_value: Variant in sight_release_lookup.keys():
		sight_cells.append(cell_value as Vector2i)
	sight_cells.sort()
	navigation.prepare_astar(scene_indices, movement_cells, sight_cells)
	prewarmed_paths.clear()
	_precompute_footprint_clearance()


func register_source_scene_footprint(
	scene_index: int,
	movement_cells: Array[Vector2i],
	sight_cells: Array[Vector2i],
) -> bool:
	if navigation == null or scene_index < 0:
		return false
	source_scene_footprints[scene_index] = {
		"movement": movement_cells.duplicate(),
		"sight": sight_cells.duplicate(),
	}
	return not movement_cells.is_empty() or not sight_cells.is_empty()


func set_source_scene_disabled(scene_index: int, disabled: bool) -> bool:
	if navigation == null or scene_index < 0:
		return false
	var was_disabled := disabled_source_scenes.has(scene_index)
	if disabled == was_disabled:
		return false
	if disabled:
		disabled_source_scenes[scene_index] = true
	else:
		# A live runtime actor must continue to suppress its serialized source
		# footprint. This guard lets static doors be closed again without
		# accidentally restoring an actor's stale VWF obstacle cells.
		if actors.has(scene_index):
			return false
		disabled_source_scenes.erase(scene_index)
	var footprint := source_scene_footprints.get(scene_index, {}) as Dictionary
	var movement_release_cells := (
		footprint.get("movement", []) as Array[Vector2i]
	)
	var sight_release_cells := (
		footprint.get("sight", []) as Array[Vector2i]
	)
	var changed_cells: Array[Vector2i] = (
		navigation.set_source_scene_disabled(
			scene_index,
			disabled,
			movement_release_cells,
			sight_release_cells,
		)
	)
	_refresh_footprint_clearance_for_cells(changed_cells)
	# Opening a door can only add shorter alternatives, so every existing
	# authored path remains valid. Closing can invalidate cached geometry and
	# therefore keeps the conservative cache reset.
	if not disabled:
		prewarmed_paths.clear()
	return true


func is_source_scene_disabled(scene_index: int) -> bool:
	return disabled_source_scenes.has(scene_index)


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
	_remove_actor_origin_owner(scene_index, actor["origin"] as Vector2i)
	actors.erase(scene_index)
	_clear_goal(scene_index)
	if not keep_source_disabled:
		disabled_source_scenes.erase(scene_index)


func find_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	ignore_dynamic_actors: bool = false,
) -> PackedVector2Array:
	if navigation == null or not actors.has(scene_index):
		return PackedVector2Array()
	var query_started := Time.get_ticks_usec()
	_clear_goal(scene_index)
	var actor := actors[scene_index] as Dictionary
	var movement_offsets := actor["movement_offsets"] as Array[Vector2i]
	var query_start_cell: Vector2i = navigation.world_to_cell(world_start)
	var query_destination_cell: Vector2i = navigation.world_to_cell(
		world_destination
	)
	var prewarmed_path: Variant = (
		null
		if ignore_dynamic_actors
		else _prewarmed_path(
			scene_index,
			world_start,
			world_destination,
		)
	)
	if prewarmed_path != null:
		prewarmed_path_hit_count += 1
		var cached_path: PackedVector2Array = (
			prewarmed_path as PackedVector2Array
		).duplicate()
		_reserve_path_goal(scene_index, movement_offsets, cached_path)
		_record_path_query(
			scene_index,
			movement_offsets.size(),
			Time.get_ticks_usec() - query_started,
			query_start_cell,
			query_destination_cell,
			cached_path.size(),
			true,
			last_prewarmed_path_nearest_distance,
		)
		return cached_path
	var changed_solids: Array[Vector2i] = []
	var start_cell := query_start_cell
	var needs_actor_clearance := (
		movement_offsets.size() != 1 or movement_offsets[0] != Vector2i.ZERO
	)
	if needs_actor_clearance:
		for candidate: Vector2i in _blocked_origins_for_offsets(
			movement_offsets
		):
			if candidate != start_cell:
				_mark_temporary_solid(candidate, changed_solids)
	var include_dynamic_path_obstacles := (
		not ignore_dynamic_actors
		and (
			actors.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
			or movement_owners.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
		)
	)
	if include_dynamic_path_obstacles:
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
	elif not ignore_dynamic_actors:
		dense_path_fallback_count += 1
	var path: PackedVector2Array = navigation.find_path(world_start, world_destination, true)
	for cell: Vector2i in changed_solids:
		navigation.astar.set_point_solid(cell, false)
	_reserve_path_goal(scene_index, movement_offsets, path)
	_record_path_query(
		scene_index,
		movement_offsets.size(),
		Time.get_ticks_usec() - query_started,
		query_start_cell,
		query_destination_cell,
		path.size(),
		false,
		last_prewarmed_path_nearest_distance,
	)
	return path


func _record_path_query(
	scene_index: int,
	movement_offset_count: int,
	query_elapsed_usec: int,
	start_cell: Vector2i = Vector2i(-1, -1),
	destination_cell: Vector2i = Vector2i(-1, -1),
	path_point_count: int = 0,
	used_cached_path: bool = false,
	cache_nearest_distance: int = -1,
) -> void:
	path_query_count += 1
	path_query_elapsed_usec += query_elapsed_usec
	last_path_query_scene_index = scene_index
	last_path_query_elapsed_usec = query_elapsed_usec
	var profile := path_query_profiles.get(
		scene_index,
		{
			"scene_index": scene_index,
			"query_count": 0,
			"elapsed_usec": 0,
			"maximum_usec": 0,
			"movement_offset_count": movement_offset_count,
			"maximum_start_cell": start_cell,
			"maximum_destination_cell": destination_cell,
			"maximum_path_point_count": path_point_count,
			"maximum_used_cached_path": used_cached_path,
			"maximum_cache_nearest_distance": cache_nearest_distance,
		},
	) as Dictionary
	profile["query_count"] = int(profile["query_count"]) + 1
	profile["elapsed_usec"] = int(profile["elapsed_usec"]) + query_elapsed_usec
	if query_elapsed_usec > int(profile["maximum_usec"]):
		profile["maximum_usec"] = query_elapsed_usec
		profile["maximum_start_cell"] = start_cell
		profile["maximum_destination_cell"] = destination_cell
		profile["maximum_path_point_count"] = path_point_count
		profile["maximum_used_cached_path"] = used_cached_path
		profile["maximum_cache_nearest_distance"] = cache_nearest_distance
	path_query_profiles[scene_index] = profile


func prewarm_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> bool:
	var path := _cache_prewarmed_path(
		scene_index,
		world_start,
		world_destination,
		false,
	)
	return not path.is_empty()


func prewarm_patrol_cycle_for_scene(
	scene_index: int,
	world_start: Vector2,
	waypoints: PackedVector2Array,
	current_waypoint_index: int,
	lap_count: int = 2,
) -> int:
	if (
		navigation == null
		or not actors.has(scene_index)
		or waypoints.is_empty()
	):
		return 0
	if (
		actors.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
		or movement_owners.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
	):
		# Sparse maps deliberately include current actors and reserved goals in
		# A*. A load-time route would freeze one transient occupancy snapshot
		# and measurably change how many original guards start moving. Keep
		# those maps on the staggered real-time planner.
		return 0
	var route_index := clampi(
		current_waypoint_index,
		0,
		waypoints.size() - 1,
	)
	for unused_waypoint: int in range(waypoints.size()):
		if world_start.distance_squared_to(waypoints[route_index]) > 4.0:
			break
		route_index = (route_index + 1) % waypoints.size()
	var current_position := world_start
	var build_count_before := prewarmed_path_build_count
	var maximum_steps := (
		waypoints.size() * maxi(lap_count, 1) + waypoints.size()
	)
	for unused_step: int in range(maximum_steps):
		var destination := waypoints[route_index]
		var path := _cache_prewarmed_path(
			scene_index,
			current_position,
			destination,
			true,
		)
		if path.is_empty():
			# An empty static route is useful cache data too. It prevents an
			# authored but unreachable patrol leg from searching the entire
			# original map every retry tick.
			break
		current_position = path[-1]
		if current_position.distance_squared_to(destination) <= 4.0:
			route_index = (route_index + 1) % waypoints.size()
	return prewarmed_path_build_count - build_count_before


func _cache_prewarmed_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	cache_empty_path: bool,
) -> PackedVector2Array:
	if (
		navigation == null
		or not actors.has(scene_index)
		or world_start.is_equal_approx(world_destination)
	):
		return PackedVector2Array()
	var cache_key := _path_cache_key(world_start, world_destination)
	var scene_cache := prewarmed_paths.get(scene_index, {}) as Dictionary
	if scene_cache.has(cache_key):
		return (scene_cache[cache_key] as PackedVector2Array).duplicate()
	var path := find_path_for_scene(
		scene_index,
		world_start,
		world_destination,
	)
	_clear_goal(scene_index)
	if path.is_empty() and not cache_empty_path:
		return path
	scene_cache = prewarmed_paths.get(scene_index, {}) as Dictionary
	scene_cache[cache_key] = path.duplicate()
	prewarmed_paths[scene_index] = scene_cache
	prewarmed_path_build_count += 1
	return path


func _prewarmed_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> Variant:
	last_prewarmed_path_nearest_distance = -1
	if not prewarmed_paths.has(scene_index):
		return null
	var scene_cache := prewarmed_paths[scene_index] as Dictionary
	var cache_key := _path_cache_key(world_start, world_destination)
	if scene_cache.has(cache_key):
		last_prewarmed_path_nearest_distance = 0
		return scene_cache[cache_key]
	var start_cell := Vector2i(cache_key.x, cache_key.y)
	var destination_cell := Vector2i(cache_key.z, cache_key.w)
	var best_distance := 3
	var best_suffix := PackedVector2Array()
	for candidate_key_value: Variant in scene_cache.keys():
		var candidate_key := candidate_key_value as Vector4i
		if Vector2i(candidate_key.z, candidate_key.w) != destination_cell:
			continue
		var candidate_path := (
			scene_cache[candidate_key] as PackedVector2Array
		)
		for waypoint_index: int in range(candidate_path.size()):
			var waypoint_cell: Vector2i = navigation.world_to_cell(
				candidate_path[waypoint_index]
			)
			var distance := maxi(
				absi(waypoint_cell.x - start_cell.x),
				absi(waypoint_cell.y - start_cell.y),
			)
			if (
				last_prewarmed_path_nearest_distance < 0
				or distance < last_prewarmed_path_nearest_distance
			):
				last_prewarmed_path_nearest_distance = distance
			if distance >= best_distance:
				continue
			best_distance = distance
			best_suffix = candidate_path.slice(waypoint_index)
			if best_distance == 0:
				break
		if best_distance == 0:
			break
	if best_suffix.is_empty():
		return null
	scene_cache[cache_key] = best_suffix.duplicate()
	prewarmed_paths[scene_index] = scene_cache
	prewarmed_path_suffix_hit_count += 1
	return best_suffix


func _path_cache_key(
	world_start: Vector2,
	world_destination: Vector2,
) -> Vector4i:
	var start_cell: Vector2i = navigation.world_to_cell(world_start)
	var destination_cell: Vector2i = navigation.world_to_cell(
		world_destination
	)
	return Vector4i(
		start_cell.x,
		start_cell.y,
		destination_cell.x,
		destination_cell.y,
	)


func _reserve_path_goal(
	scene_index: int,
	movement_offsets: Array[Vector2i],
	path: PackedVector2Array,
) -> void:
	if path.is_empty():
		return
	var goal_origin: Vector2i = navigation.world_to_cell(path[-1])
	for offset: Vector2i in movement_offsets:
		goal_owners[goal_origin + offset] = scene_index


func release_goal(scene_index: int) -> void:
	_clear_goal(scene_index)


func try_relocate(
	scene_index: int,
	new_world_position: Vector2,
	ignore_dynamic_actors: bool = false,
) -> bool:
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
	if not _can_traverse(
		scene_index,
		actor,
		old_world_position,
		new_world_position,
		ignore_dynamic_actors,
	):
		relocation_rejection_count += 1
		return false
	if (
		not ignore_dynamic_actors
		and not _keeps_actor_separation(
			scene_index,
			old_world_position,
			new_world_position,
		)
	):
		relocation_rejection_count += 1
		return false
	if (
		not ignore_dynamic_actors
		and _crosses_reserved_diagonal(old_origin, new_origin)
	):
		relocation_rejection_count += 1
		return false
	return _commit_relocation(
		scene_index,
		actor,
		old_origin,
		new_origin,
		new_world_position,
	)


## Replays one adjacent substep from a stable original-runtime patrol capture.
## This deliberately bypasses only reconstructed static/dynamic occupancy:
## the original process has already demonstrated that this short segment is
## traversable. World bounds, one-cell-at-a-time motion and occupancy
## bookkeeping remain enforced.
func try_relocate_from_runtime_evidence(
	scene_index: int,
	new_world_position: Vector2,
) -> bool:
	if navigation == null or not actors.has(scene_index):
		return false
	var actor := actors[scene_index] as Dictionary
	var old_origin := actor["origin"] as Vector2i
	var new_origin: Vector2i = navigation.world_to_cell(new_world_position)
	if (
		not navigation.is_valid_cell(new_origin)
		or absi(new_origin.x - old_origin.x) > 1
		or absi(new_origin.y - old_origin.y) > 1
	):
		relocation_rejection_count += 1
		return false
	return _commit_relocation(
		scene_index,
		actor,
		old_origin,
		new_origin,
		new_world_position,
	)


func _commit_relocation(
	scene_index: int,
	actor: Dictionary,
	old_origin: Vector2i,
	new_origin: Vector2i,
	new_world_position: Vector2,
) -> bool:
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
		_remove_actor_origin_owner(scene_index, old_origin)
		_add_actor_origin_owner(scene_index, new_origin)
	actor["origin"] = new_origin
	actor["world_position"] = new_world_position
	actors[scene_index] = actor
	if new_origin != old_origin:
		accepted_moves.append({"from": old_origin, "to": new_origin})
		if (
			absi(new_origin.x - old_origin.x) == 1
			and absi(new_origin.y - old_origin.y) == 1
		):
			accepted_diagonal_crossings[
				old_origin + new_origin
			] = true
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
	var source_seed := origin
	if not source_lookup.has(source_seed):
		var nearest_distance := MAX_SOURCE_ANCHOR_DISTANCE + 1
		for cell: Vector2i in source_cells:
			var distance := maxi(
				absi(cell.x - origin.x),
				absi(cell.y - origin.y),
			)
			if (
				distance < nearest_distance
				or (
					distance == nearest_distance
					and (
						cell.y < source_seed.y
						or (cell.y == source_seed.y and cell.x < source_seed.x)
					)
				)
			):
				nearest_distance = distance
				source_seed = cell
		if nearest_distance > MAX_SOURCE_ANCHOR_DISTANCE:
			source_seed = origin
	if source_lookup.has(source_seed):
		var pending: Array[Vector2i] = [source_seed]
		var visited: Dictionary = {source_seed: true}
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


func _precompute_footprint_clearance() -> void:
	footprint_blocked_origins.clear()
	footprint_blocked_origin_lookups.clear()
	footprint_offsets_by_key.clear()
	footprint_clearance_precompute_usec = 0
	footprint_clearance_incremental_usec = 0
	var started_usec := Time.get_ticks_usec()
	for actor_value: Variant in actors.values():
		var actor := actor_value as Dictionary
		var offsets := actor["movement_offsets"] as Array[Vector2i]
		if offsets.size() <= 1:
			continue
		_blocked_origins_for_offsets(offsets)
	footprint_clearance_precompute_usec = Time.get_ticks_usec() - started_usec


func _blocked_origins_for_offsets(
	offsets: Array[Vector2i],
) -> Array[Vector2i]:
	var cache_key := _movement_offsets_cache_key(offsets)
	if footprint_blocked_origins.has(cache_key):
		return (
			footprint_blocked_origins[cache_key]
			as Array[Vector2i]
		)
	var blocked: Array[Vector2i] = []
	var blocked_lookup: Dictionary = {}
	for y: int in range(navigation.dimensions.y):
		for x: int in range(navigation.dimensions.x):
			var candidate := Vector2i(x, y)
			for offset: Vector2i in offsets:
				if _source_movement_blocked(candidate + offset):
					blocked.append(candidate)
					blocked_lookup[candidate] = true
					break
	footprint_blocked_origins[cache_key] = blocked
	footprint_blocked_origin_lookups[cache_key] = blocked_lookup
	footprint_offsets_by_key[cache_key] = offsets.duplicate()
	return blocked


func _refresh_footprint_clearance_for_cells(
	changed_cells: Array[Vector2i],
) -> void:
	if changed_cells.is_empty() or footprint_offsets_by_key.is_empty():
		return
	var started_usec := Time.get_ticks_usec()
	for cache_key_value: Variant in footprint_offsets_by_key.keys():
		var cache_key := str(cache_key_value)
		var offsets := (
			footprint_offsets_by_key[cache_key] as Array[Vector2i]
		)
		var blocked := (
			footprint_blocked_origins[cache_key] as Array[Vector2i]
		)
		var blocked_lookup := (
			footprint_blocked_origin_lookups[cache_key] as Dictionary
		)
		var candidates: Dictionary = {}
		for changed_cell: Vector2i in changed_cells:
			for offset: Vector2i in offsets:
				var candidate := changed_cell - offset
				if navigation.is_valid_cell(candidate):
					candidates[candidate] = true
		for candidate_value: Variant in candidates.keys():
			var candidate := candidate_value as Vector2i
			var now_blocked := false
			for offset: Vector2i in offsets:
				if _source_movement_blocked(candidate + offset):
					now_blocked = true
					break
			if now_blocked and not blocked_lookup.has(candidate):
				blocked_lookup[candidate] = true
				blocked.append(candidate)
			elif not now_blocked and blocked_lookup.has(candidate):
				blocked_lookup.erase(candidate)
				blocked.erase(candidate)
		footprint_blocked_origins[cache_key] = blocked
		footprint_blocked_origin_lookups[cache_key] = blocked_lookup
	footprint_clearance_incremental_usec += (
		Time.get_ticks_usec() - started_usec
	)


static func _movement_offsets_cache_key(
	offsets: Array[Vector2i],
) -> String:
	var parts: PackedStringArray = []
	for offset: Vector2i in offsets:
		parts.append("%d,%d" % [offset.x, offset.y])
	return ";".join(parts)


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


func _add_actor_origin_owner(
	scene_index: int,
	origin: Vector2i,
) -> void:
	var owners := actor_origin_owners.get(origin, {}) as Dictionary
	owners[scene_index] = true
	actor_origin_owners[origin] = owners


func _remove_actor_origin_owner(
	scene_index: int,
	origin: Vector2i,
) -> void:
	if not actor_origin_owners.has(origin):
		return
	var owners := actor_origin_owners[origin] as Dictionary
	owners.erase(scene_index)
	if owners.is_empty():
		actor_origin_owners.erase(origin)
	else:
		actor_origin_owners[origin] = owners


func _can_traverse(
	scene_index: int,
	actor: Dictionary,
	old_world_position: Vector2,
	new_world_position: Vector2,
	ignore_dynamic_actors: bool = false,
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
					scene_index,
					previous_origin,
					sample_origin,
					movement_offsets,
					ignore_dynamic_actors,
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
			if (
				not ignore_dynamic_actors
				and sample_origin != old_origin
				and _has_other_owner(
					movement_owners,
					cell,
					scene_index,
				)
			):
				return false
	return true


func _diagonal_transition_is_clear(
	scene_index: int,
	from_origin: Vector2i,
	to_origin: Vector2i,
	movement_offsets: Array[Vector2i],
	ignore_dynamic_actors: bool = false,
) -> bool:
	if (
		absi(to_origin.x - from_origin.x) != 1
		or absi(to_origin.y - from_origin.y) != 1
	):
		return true
	if (
		not ignore_dynamic_actors
		and _crosses_reserved_diagonal(from_origin, to_origin)
	):
		return false
	var side_origins: Array[Vector2i] = [
		Vector2i(to_origin.x, from_origin.y),
		Vector2i(from_origin.x, to_origin.y),
	]
	var blocked_side_count := 0
	for side_origin: Vector2i in side_origins:
		var side_blocked := false
		for offset: Vector2i in movement_offsets:
			var side_cell := side_origin + offset
			if (
				_source_movement_blocked(side_cell)
				or (
					not ignore_dynamic_actors
					and _has_other_owner(
						movement_owners,
						side_cell,
						scene_index,
					)
				)
			):
				side_blocked = true
				break
		if side_blocked:
			blocked_side_count += 1
	return blocked_side_count < side_origins.size()


func _mark_temporary_solid(cell: Vector2i, changed_solids: Array[Vector2i]) -> void:
	if (
		not navigation.is_valid_cell(cell)
		or navigation.astar.is_point_solid(cell)
	):
		return
	navigation.astar.set_point_solid(cell, true)
	changed_solids.append(cell)


func _source_movement_blocked(cell: Vector2i) -> bool:
	return navigation.is_movement_blocked(cell, disabled_source_scenes)


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
	var target_origin: Vector2i = navigation.world_to_cell(
		new_world_position
	)
	var x_radius := maxi(
		ceili(MIN_ACTOR_SEPARATION / float(navigation.cell_size.x)),
		1,
	)
	var y_radius := maxi(
		ceili(MIN_ACTOR_SEPARATION / float(navigation.cell_size.y)),
		1,
	)
	for y: int in range(
		target_origin.y - y_radius,
		target_origin.y + y_radius + 1,
	):
		for x: int in range(
			target_origin.x - x_radius,
			target_origin.x + x_radius + 1,
		):
			var origin := Vector2i(x, y)
			if not actor_origin_owners.has(origin):
				continue
			for other_scene_value: Variant in (
				actor_origin_owners[origin] as Dictionary
			).keys():
				var other_scene := int(other_scene_value)
				if other_scene == scene_index:
					continue
				var other_position := (
					(actors[other_scene] as Dictionary)["world_position"]
					as Vector2
				)
				var old_distance := old_world_position.distance_to(
					other_position
				)
				var new_distance := new_world_position.distance_to(
					other_position
				)
				if (
					new_distance < MIN_ACTOR_SEPARATION
					and new_distance <= old_distance
				):
					return false
	return true


func _sync_move_reservations() -> void:
	var current_frame := int(Engine.get_physics_frames())
	if current_frame != accepted_moves_physics_frame:
		accepted_moves_physics_frame = current_frame
		accepted_moves.clear()
		accepted_diagonal_crossings.clear()


func _crosses_reserved_diagonal(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if absi(to_cell.x - from_cell.x) != 1 or absi(to_cell.y - from_cell.y) != 1:
		return false
	return accepted_diagonal_crossings.has(from_cell + to_cell)


func _sight_blocked(cell: Vector2i, ignored: Dictionary) -> bool:
	if not navigation.is_valid_cell(cell):
		return true
	var source_value: int = navigation.source_value(
		NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID, cell
	)
	if (
		source_value != 0
		and not navigation.is_source_cell_released(
			NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID,
			cell,
		)
	):
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
