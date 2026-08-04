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
## Two simultaneously moving actors can meet on intersecting diagonal
## sub-cell trajectories even though their occupied grid cells differ. Give
## the lower scene index deterministic right-of-way after both actors have a
## live goal. Static walls and occupied destination cells remain hard, while
## this smaller guard distance lets the winner enter the adjacent free lane
## and breaks the otherwise symmetric replan loop.
const MIN_PRIORITY_PASS_SEPARATION := 4.0
## Patrol prewarming is repeated whenever a level is reconstructed (loading a
## save, replaying a checkpoint, or switching away and back). The authored
## static graph and recovered legacy pathfinder are immutable for that initial
## level state, so dense-map patrol legs can be shared across reconstructions.
## Runtime path queries, opened doors, reservations, and sparse-map actor
## avoidance deliberately never use this process-global cache.
const GLOBAL_STATIC_PREWARM_CACHE_VERSION := "legacy-reverse-v2"
const MAX_GLOBAL_STATIC_PREWARM_PATHS := 16384
## A small set of formal-map actors and vehicles has its connected L2/L3
## footprint one cell away from the serialized reference cell. Larger
## distances indicate a stale/reused scene reference and must not create an
## unbounded runtime footprint.
const MAX_SOURCE_ANCHOR_DISTANCE := 1

var navigation: RefCounted
static var global_static_prewarmed_paths: Dictionary = {}
var actors: Dictionary = {}
var actor_origin_owners: Dictionary = {}
var disabled_source_scenes: Dictionary = {}
var source_scene_footprints: Dictionary = {}
var movement_owners: Dictionary = {}
var sight_owners: Dictionary = {}
var goal_owners: Dictionary = {}
var goal_origin_by_scene: Dictionary = {}
var footprint_blocked_origins: Dictionary = {}
var footprint_blocked_origin_lookups: Dictionary = {}
var footprint_offsets_by_key: Dictionary = {}
var staged_footprint_offsets_by_key: Dictionary = {}
## Hot footprint-cache construction must not repeatedly cross the
## NavigationGridData/GDScript call boundary for every cell and every mask
## component. This byte grid mirrors the current authored L3 solid state and
## is updated incrementally when a door/source footprint changes.
var source_movement_blocked_bits := PackedByteArray()
var footprint_clearance_precompute_usec := 0
var footprint_clearance_incremental_usec := 0
var prewarmed_paths: Dictionary = {}
## The same actor can expose a different connected collision footprint in
## each directional animation. Retain every precomputed route variant instead
## of replacing the north/south profile with the east/west profile.
var prewarmed_paths_by_footprint: Dictionary = {}
var prewarmed_path_build_count := 0
var prewarmed_path_hit_count := 0
var prewarmed_path_suffix_hit_count := 0
## Stable-MOD patrol timelines expose their future absolute endpoints at level
## construction time. Cache those exact static routes before gameplay starts
## so dozens of guards crossing the same captured timestamp do not all run A*
## in one rendered frame. This cache is intentionally exact-key only: if live
## collision has displaced an actor, the runtime query is recomputed against
## the current start and destination instead of replaying stale geometry.
var runtime_evidence_paths: Dictionary = {}
var runtime_evidence_paths_by_footprint: Dictionary = {}
var runtime_evidence_path_build_count := 0
var runtime_evidence_path_hit_count := 0
var runtime_evidence_translated_hit_count := 0
var runtime_evidence_translation_rejections: Dictionary = {}
var static_prewarm_cache_namespace := ""
var static_prewarm_cache_hit_count := 0
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
var deferred_dynamic_destination_count := 0
var relocation_rejection_count := 0
var sprite_footprint_update_count := 0
var registration_finalized := false


func configure(
	source_navigation: RefCounted,
	new_static_prewarm_cache_namespace: String = "",
) -> void:
	navigation = source_navigation
	static_prewarm_cache_namespace = (
		new_static_prewarm_cache_namespace.strip_edges()
	)
	actors.clear()
	actor_origin_owners.clear()
	disabled_source_scenes.clear()
	source_scene_footprints.clear()
	movement_owners.clear()
	sight_owners.clear()
	goal_owners.clear()
	goal_origin_by_scene.clear()
	footprint_blocked_origins.clear()
	footprint_blocked_origin_lookups.clear()
	footprint_offsets_by_key.clear()
	staged_footprint_offsets_by_key.clear()
	source_movement_blocked_bits.clear()
	footprint_clearance_precompute_usec = 0
	footprint_clearance_incremental_usec = 0
	prewarmed_paths.clear()
	prewarmed_paths_by_footprint.clear()
	prewarmed_path_build_count = 0
	prewarmed_path_hit_count = 0
	prewarmed_path_suffix_hit_count = 0
	runtime_evidence_paths.clear()
	runtime_evidence_paths_by_footprint.clear()
	runtime_evidence_path_build_count = 0
	runtime_evidence_path_hit_count = 0
	runtime_evidence_translated_hit_count = 0
	runtime_evidence_translation_rejections.clear()
	static_prewarm_cache_hit_count = 0
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
	deferred_dynamic_destination_count = 0
	relocation_rejection_count = 0
	sprite_footprint_update_count = 0
	registration_finalized = false


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
	# Modern door planning treats a closed, interactive door as a traversable
	# portal.  Its visual and line-of-sight state remain closed until an actor
	# approaches or the player clicks it, but A* can plan the complete route up
	# front instead of stopping at the wall and losing the original destination.
	for footprint_value: Variant in source_scene_footprints.values():
		if not footprint_value is Dictionary:
			continue
		var permanent_footprint := footprint_value as Dictionary
		if not bool(permanent_footprint.get("permanent_movement_release", false)):
			continue
		for cell: Vector2i in (
			permanent_footprint.get("movement", []) as Array[Vector2i]
		):
			movement_release_lookup[cell] = true
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
	_rebuild_source_movement_blocked_bits()
	prewarmed_paths.clear()
	prewarmed_paths_by_footprint.clear()
	runtime_evidence_paths.clear()
	runtime_evidence_paths_by_footprint.clear()
	registration_finalized = true
	_precompute_footprint_clearance()


func register_source_scene_footprint(
	scene_index: int,
	movement_cells: Array[Vector2i],
	sight_cells: Array[Vector2i],
	permanent_movement_release: bool = false,
) -> bool:
	if navigation == null or scene_index < 0:
		return false
	source_scene_footprints[scene_index] = {
		"movement": movement_cells.duplicate(),
		"sight": sight_cells.duplicate(),
		"permanent_movement_release": permanent_movement_release,
	}
	return not movement_cells.is_empty() or not sight_cells.is_empty()


func stage_footprint_clearance(movement_offsets: Array[Vector2i]) -> bool:
	var normalized := _normalized_footprint_offsets(movement_offsets)
	if normalized.size() <= 1:
		return false
	var cache_key := _movement_offsets_cache_key(normalized)
	if footprint_blocked_origins.has(cache_key):
		return false
	if registration_finalized:
		_blocked_origins_for_offsets(normalized)
		return true
	if staged_footprint_offsets_by_key.has(cache_key):
		return false
	staged_footprint_offsets_by_key[cache_key] = normalized
	return true


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
	_refresh_source_movement_blocked_bits(changed_cells)
	_refresh_footprint_clearance_for_cells(changed_cells)
	# Opening a door can only add shorter alternatives, so every existing
	# authored path remains valid. Closing can invalidate cached geometry and
	# therefore keeps the conservative cache reset.
	if not disabled:
		prewarmed_paths.clear()
		prewarmed_paths_by_footprint.clear()
		runtime_evidence_paths.clear()
		runtime_evidence_paths_by_footprint.clear()
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


func update_scene_footprint(
	scene_index: int,
	movement_offsets: Array[Vector2i],
	sight_offsets: Array[Vector2i],
) -> bool:
	if navigation == null or not actors.has(scene_index):
		return false
	var normalized_movement := _normalized_footprint_offsets(movement_offsets)
	var normalized_sight := _normalized_footprint_offsets(sight_offsets)
	var actor := actors[scene_index] as Dictionary
	var previous_movement := actor["movement_offsets"] as Array[Vector2i]
	var previous_sight := actor["sight_offsets"] as Array[Vector2i]
	if (
		previous_movement == normalized_movement
		and previous_sight == normalized_sight
	):
		return true

	var origin := actor["origin"] as Vector2i
	var reserved_goal: Variant = goal_origin_by_scene.get(scene_index)
	_remove_footprint(
		movement_owners,
		scene_index,
		origin,
		previous_movement,
	)
	_remove_footprint(
		sight_owners,
		scene_index,
		origin,
		previous_sight,
	)
	_clear_goal(scene_index)
	actor["movement_offsets"] = normalized_movement
	actor["sight_offsets"] = normalized_sight
	actors[scene_index] = actor
	_add_footprint(
		movement_owners,
		scene_index,
		origin,
		normalized_movement,
	)
	_add_footprint(
		sight_owners,
		scene_index,
		origin,
		normalized_sight,
	)
	if reserved_goal is Vector2i:
		_reserve_goal_origin(
			scene_index,
			normalized_movement,
			reserved_goal as Vector2i,
		)
	# Bulk actor construction changes the action/direction footprint several
	# times before finalize_registration() has released every serialized
	# source actor from the authored grid. Building a whole-map clearance cache
	# at each intermediate visual is both stale and extremely expensive for
	# vehicles: m004 formerly scanned its 170x200 grid repeatedly for the same
	# 18 ambient actors. Stage the unique profile for the one authoritative
	# final precompute; runtime animation changes still update immediately.
	if normalized_movement.size() > 1:
		stage_footprint_clearance(normalized_movement)
	sprite_footprint_update_count += 1
	return true


func find_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	ignore_dynamic_actors: bool = false,
	reserve_goal: bool = true,
) -> PackedVector2Array:
	if navigation == null or not actors.has(scene_index):
		return PackedVector2Array()
	var query_started := Time.get_ticks_usec()
	if reserve_goal:
		_clear_goal(scene_index)
	var actor := actors[scene_index] as Dictionary
	var movement_offsets := actor["movement_offsets"] as Array[Vector2i]
	var query_start_cell: Vector2i = navigation.world_to_cell(world_start)
	var query_destination_cell: Vector2i = navigation.world_to_cell(
		world_destination
	)
	var used_runtime_evidence_path := ignore_dynamic_actors
	var prewarmed_path: Variant = (
		_runtime_evidence_path(
			scene_index,
			world_start,
			world_destination,
		)
		if used_runtime_evidence_path
		else _prewarmed_path(
			scene_index,
			world_start,
			world_destination,
		)
	)
	if prewarmed_path != null:
		if used_runtime_evidence_path:
			runtime_evidence_path_hit_count += 1
			last_prewarmed_path_nearest_distance = 0
		else:
			prewarmed_path_hit_count += 1
		# Runtime-evidence paths are read-only at this boundary and issue_path()
		# takes its own owned copy. Avoid a second full PackedVector2Array copy
		# for every guard on a shared capture timestamp. General patrol-cache
		# callers may derive suffixes and therefore retain the defensive copy.
		var cached_path := prewarmed_path as PackedVector2Array
		if not used_runtime_evidence_path:
			cached_path = cached_path.duplicate()
			if (
				not cached_path.is_empty()
				and navigation.world_to_cell(cached_path[-1])
					== query_destination_cell
				and navigation.is_valid_cell(query_destination_cell)
				and not navigation.astar.is_point_solid(
					query_destination_cell
				)
			):
				cached_path[-1] = world_destination
		if reserve_goal:
			_reserve_path_goal(scene_index, movement_offsets, cached_path)
		_record_path_query(
			scene_index,
			movement_offsets.size(),
			_movement_offsets_cache_key(movement_offsets),
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
	var include_dynamic_path_obstacles := (
		not ignore_dynamic_actors
		and (
			actors.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
			or movement_owners.size() <= MAX_DYNAMIC_PATH_OBSTACLE_CELLS
		)
	)
	var uses_dense_static_path := (
		not ignore_dynamic_actors
		and not include_dynamic_path_obstacles
	)
	# Dense maps and runtime-evidence replay deliberately ignore transient
	# actor reservations. For multi-cell actors their only extra constraint is
	# the authored footprint-clearance grid, which is already available as a
	# compact byte mask. Passing it directly to the recovered pathfinder avoids
	# setting/restoring thousands of AStarGrid2D cells for every motorcycle,
	# cart and vehicle route while retaining the exact original search order.
	var use_packed_footprint_lookup := (
		needs_actor_clearance
		and (
			ignore_dynamic_actors
			or not include_dynamic_path_obstacles
		)
	)
	var additional_solid_lookup := PackedByteArray()
	if needs_actor_clearance:
		var footprint_key := _movement_offsets_cache_key(movement_offsets)
		_blocked_origins_for_offsets(movement_offsets)
		if use_packed_footprint_lookup:
			additional_solid_lookup = (
				footprint_blocked_origin_lookups[footprint_key]
				as PackedByteArray
			)
		else:
			for candidate: Vector2i in (
				footprint_blocked_origins[footprint_key]
				as Array[Vector2i]
			):
				if candidate != start_cell:
					_mark_temporary_solid(candidate, changed_solids)
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
	var packed_unreachable_precheck_before := int(
		navigation.packed_footprint_unreachable_precheck_count
	)
	var path: PackedVector2Array = navigation.find_path(
		world_start,
		world_destination,
		true,
		not changed_solids.is_empty(),
		additional_solid_lookup,
	)
	# A packed mask intentionally skips Godot's native partial-path fallback.
	# If the exact legacy route is empty, reproduce the former temporary-solid
	# query once so unreachable large actors keep the same safe edge route.
	# Successful routes—the performance-sensitive common case—never pay this
	# mutation cost.
	var packed_start_is_isolated := (
		int(navigation.packed_footprint_unreachable_precheck_count)
			> packed_unreachable_precheck_before
		and not bool(navigation.last_packed_reachability_start_has_exit)
	)
	if (
		path.is_empty()
		and not additional_solid_lookup.is_empty()
		and not packed_start_is_isolated
	):
		for candidate: Vector2i in _blocked_origins_for_offsets(
			movement_offsets
		):
			if candidate != start_cell:
				_mark_temporary_solid(candidate, changed_solids)
		path = navigation.find_path(
			world_start,
			world_destination,
			true,
			not changed_solids.is_empty(),
		)
	for cell: Vector2i in changed_solids:
		navigation.astar.set_point_solid(cell, false)
	# A temporary actor/goal reservation can split a narrow but statically
	# connected corridor. Preserve the player's/AI's real destination after
	# the safe partial route so SquadUnit stops at the blocker, replans, and
	# continues when it clears. Never do this for a static disconnection or a
	# multi-cell actor that genuinely cannot fit through the passage.
	if (
		include_dynamic_path_obstacles
		and movement_offsets.size() == 1
		and movement_offsets[0] == Vector2i.ZERO
		and not path.is_empty()
		and path[-1].distance_squared_to(world_destination) > 1.0
		and bool(
			navigation.call(
				"is_statically_reachable",
				world_start,
				world_destination,
			)
		)
	):
		path.append(world_destination)
		deferred_dynamic_destination_count += 1
	if uses_dense_static_path:
		# Dense formal maps deliberately keep transient actors out of A* and
		# enforce separation during relocation. Their resulting route depends
		# only on the authored grid, start/destination cells and the current
		# footprint, so later identical commands and route suffixes can reuse
		# it without changing collision behavior.
		_cache_dense_static_path(
			scene_index,
			world_start,
			world_destination,
			path,
		)
	if reserve_goal:
		_reserve_path_goal(scene_index, movement_offsets, path)
	_record_path_query(
		scene_index,
		movement_offsets.size(),
		_movement_offsets_cache_key(movement_offsets),
		Time.get_ticks_usec() - query_started,
		query_start_cell,
		query_destination_cell,
		path.size(),
		false,
		last_prewarmed_path_nearest_distance,
	)
	return path


## Candidate evaluation for editorial formation slots must not erase an
## actor's current goal or reserve a speculative cell. The returned geometry
## is identical to a normal query; callers explicitly commit the chosen path.
func preview_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> PackedVector2Array:
	return find_path_for_scene(
		scene_index,
		world_start,
		world_destination,
		false,
		false,
	)


func reserve_path_goal_for_scene(
	scene_index: int,
	path: PackedVector2Array,
) -> bool:
	if navigation == null or not actors.has(scene_index) or path.is_empty():
		return false
	_clear_goal(scene_index)
	var actor := actors[scene_index] as Dictionary
	_reserve_path_goal(
		scene_index,
		actor["movement_offsets"] as Array[Vector2i],
		path,
	)
	return true


func _record_path_query(
	scene_index: int,
	movement_offset_count: int,
	movement_footprint_key: String,
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
			"movement_footprint_key": movement_footprint_key,
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
		profile["maximum_movement_footprint_key"] = movement_footprint_key
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


func prewarm_runtime_evidence_path_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> bool:
	if (
		navigation == null
		or not actors.has(scene_index)
		or world_start.is_equal_approx(world_destination)
	):
		return false
	var cache_key := _runtime_evidence_path_cache_key(
		world_start,
		world_destination,
	)
	var footprint_key := _scene_movement_footprint_key(scene_index)
	var profile_caches := (
		runtime_evidence_paths_by_footprint.get(
			scene_index,
			{},
		) as Dictionary
	)
	var scene_cache := profile_caches.get(footprint_key, {}) as Dictionary
	if scene_cache.has(cache_key):
		return not (
			scene_cache[cache_key] as PackedVector2Array
		).is_empty()
	# find_path_for_scene() deliberately sees a cache miss here and computes
	# exactly the same ignore-dynamic route that the timeline would request
	# later. Goal reservation is only a side effect of live commands.
	var path := find_path_for_scene(
		scene_index,
		world_start,
		world_destination,
		true,
	)
	_clear_goal(scene_index)
	profile_caches = (
		runtime_evidence_paths_by_footprint.get(
			scene_index,
			{},
		) as Dictionary
	)
	scene_cache = profile_caches.get(footprint_key, {}) as Dictionary
	scene_cache[cache_key] = path.duplicate()
	profile_caches[footprint_key] = scene_cache
	runtime_evidence_paths_by_footprint[scene_index] = profile_caches
	runtime_evidence_paths[scene_index] = scene_cache
	runtime_evidence_path_build_count += 1
	return not path.is_empty()


func prewarm_runtime_evidence_path_footprint_profiles_for_scene(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	movement_profiles: Array,
) -> int:
	if (
		not actors.has(scene_index)
		or movement_profiles.is_empty()
	):
		return (
			1
			if prewarm_runtime_evidence_path_for_scene(
				scene_index,
				world_start,
				world_destination,
			)
			else 0
		)
	var actor := actors[scene_index] as Dictionary
	var original_offsets := (
		actor.get("movement_offsets", [Vector2i.ZERO])
		as Array[Vector2i]
	)
	var unique_profiles: Dictionary = {}
	unique_profiles[_movement_offsets_cache_key(original_offsets)] = (
		original_offsets
	)
	for profile_value: Variant in movement_profiles:
		if not profile_value is Array:
			continue
		var profile_offsets: Array[Vector2i] = []
		for offset_value: Variant in profile_value as Array:
			if offset_value is Vector2i:
				profile_offsets.append(offset_value as Vector2i)
		var normalized := _normalized_footprint_offsets(profile_offsets)
		unique_profiles[_movement_offsets_cache_key(normalized)] = normalized
	var profile_keys: Array = unique_profiles.keys()
	profile_keys.sort()
	var build_count_before := runtime_evidence_path_build_count
	for profile_key_value: Variant in profile_keys:
		var profile_key := str(profile_key_value)
		actor["movement_offsets"] = (
			unique_profiles[profile_key] as Array[Vector2i]
		)
		actors[scene_index] = actor
		prewarm_runtime_evidence_path_for_scene(
			scene_index,
			world_start,
			world_destination,
		)
	actor["movement_offsets"] = original_offsets
	actors[scene_index] = actor
	var profile_caches := (
		runtime_evidence_paths_by_footprint.get(
			scene_index,
			{},
		) as Dictionary
	)
	var original_key := _movement_offsets_cache_key(original_offsets)
	if profile_caches.has(original_key):
		runtime_evidence_paths[scene_index] = (
			profile_caches[original_key] as Dictionary
		)
	return runtime_evidence_path_build_count - build_count_before


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


func prewarm_patrol_cycle_footprint_profiles_for_scene(
	scene_index: int,
	world_start: Vector2,
	waypoints: PackedVector2Array,
	current_waypoint_index: int,
	movement_profiles: Array,
	lap_count: int = 2,
) -> int:
	if (
		not actors.has(scene_index)
		or movement_profiles.is_empty()
	):
		return prewarm_patrol_cycle_for_scene(
			scene_index,
			world_start,
			waypoints,
			current_waypoint_index,
			lap_count,
		)
	var actor := actors[scene_index] as Dictionary
	var original_offsets := (
		actor.get("movement_offsets", [Vector2i.ZERO])
		as Array[Vector2i]
	)
	var unique_profiles: Dictionary = {}
	unique_profiles[_movement_offsets_cache_key(original_offsets)] = (
		original_offsets
	)
	for profile_value: Variant in movement_profiles:
		if not profile_value is Array:
			continue
		var profile_offsets: Array[Vector2i] = []
		for offset_value: Variant in profile_value as Array:
			if offset_value is Vector2i:
				profile_offsets.append(offset_value as Vector2i)
		var normalized := _normalized_footprint_offsets(profile_offsets)
		unique_profiles[_movement_offsets_cache_key(normalized)] = normalized
	var profile_keys: Array = unique_profiles.keys()
	profile_keys.sort()
	var build_count_before := prewarmed_path_build_count
	for profile_key_value: Variant in profile_keys:
		var profile_key := str(profile_key_value)
		actor["movement_offsets"] = (
			unique_profiles[profile_key] as Array[Vector2i]
		)
		actors[scene_index] = actor
		prewarm_patrol_cycle_for_scene(
			scene_index,
			world_start,
			waypoints,
			current_waypoint_index,
			lap_count,
		)
	actor["movement_offsets"] = original_offsets
	actors[scene_index] = actor
	var profile_caches := (
		prewarmed_paths_by_footprint.get(scene_index, {}) as Dictionary
	)
	var original_key := _movement_offsets_cache_key(original_offsets)
	if profile_caches.has(original_key):
		prewarmed_paths[scene_index] = (
			profile_caches[original_key] as Dictionary
		)
	return prewarmed_path_build_count - build_count_before


func _runtime_evidence_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> Variant:
	if not runtime_evidence_paths_by_footprint.has(scene_index):
		return null
	var footprint_key := _scene_movement_footprint_key(scene_index)
	var profile_caches := (
		runtime_evidence_paths_by_footprint[scene_index] as Dictionary
	)
	if not profile_caches.has(footprint_key):
		return null
	var scene_cache := profile_caches[footprint_key] as Dictionary
	var cache_key := _runtime_evidence_path_cache_key(
		world_start,
		world_destination,
	)
	if scene_cache.has(cache_key):
		return scene_cache[cache_key]
	var translated_path: Variant = _translated_runtime_evidence_path(
		scene_index,
		world_start,
		world_destination,
		cache_key,
		scene_cache,
	)
	if translated_path == null:
		return null
	scene_cache[cache_key] = (
		translated_path as PackedVector2Array
	).duplicate()
	profile_caches[footprint_key] = scene_cache
	runtime_evidence_paths_by_footprint[scene_index] = profile_caches
	runtime_evidence_paths[scene_index] = scene_cache
	runtime_evidence_translated_hit_count += 1
	return scene_cache[cache_key]


func _translated_runtime_evidence_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	requested_key: Vector4i,
	scene_cache: Dictionary,
) -> Variant:
	var actor := actors.get(scene_index, {}) as Dictionary
	var movement_offsets := (
		actor.get("movement_offsets", [Vector2i.ZERO])
		as Array[Vector2i]
	)
	# A translated route is valid for a multi-cell actor only when every
	# occupied component is clear at every translated anchor, including the
	# two possible cardinal anchors around a diagonal. This is the same
	# clearance condition used when the original route was built, but avoids
	# repeating the full-map A* search for collision-shifted motorcycles and
	# carts whose captured displacement is unchanged.
	var requested_delta := Vector2i(
		requested_key.z - requested_key.x,
		requested_key.w - requested_key.y,
	)
	var best_key := Vector4i.ZERO
	var has_best := false
	var best_start_distance := 0x7fffffffffffffff
	for candidate_key_value: Variant in scene_cache.keys():
		if not candidate_key_value is Vector4i:
			continue
		var candidate_key := candidate_key_value as Vector4i
		if Vector2i(
			candidate_key.z - candidate_key.x,
			candidate_key.w - candidate_key.y,
		) != requested_delta:
			continue
		var candidate_path := (
			scene_cache[candidate_key] as PackedVector2Array
		)
		if candidate_path.is_empty():
			continue
		var start_distance := (
			absi(candidate_key.x - requested_key.x)
			+ absi(candidate_key.y - requested_key.y)
		)
		if (
			not has_best
			or start_distance < best_start_distance
			or (
				start_distance == best_start_distance
				and _runtime_evidence_key_precedes(candidate_key, best_key)
			)
			):
				best_key = candidate_key
				best_start_distance = start_distance
				has_best = true
	if not has_best:
		_record_runtime_evidence_translation_rejection(
			scene_index,
			"no_matching_displacement",
			requested_key,
		)
		return null
	var source_start := Vector2(
		float(best_key.x) / 1024.0,
		float(best_key.y) / 1024.0,
	)
	var cell_offset: Vector2i = (
		navigation.world_to_cell(world_start)
		- navigation.world_to_cell(source_start)
	)
	var source_path := scene_cache[best_key] as PackedVector2Array
	var translated := PackedVector2Array()
	var previous_cell: Vector2i = navigation.world_to_cell(world_start)
	for source_waypoint: Vector2 in source_path:
		var translated_cell: Vector2i = (
			navigation.world_to_cell(source_waypoint) + cell_offset
		)
		if not _runtime_evidence_step_is_clear(
			previous_cell,
			translated_cell,
			movement_offsets,
		):
			_record_runtime_evidence_translation_rejection(
				scene_index,
				"blocked_translated_step",
				requested_key,
				{
					"from": previous_cell,
					"to": translated_cell,
					"footprint": _movement_offsets_cache_key(
						movement_offsets
					),
				},
			)
			return null
		translated.append(navigation.cell_to_world(translated_cell))
		previous_cell = translated_cell
	var requested_destination_cell: Vector2i = navigation.world_to_cell(
		world_destination
	)
	if (
		translated.is_empty()
		or previous_cell != requested_destination_cell
		or navigation.astar.is_point_solid(requested_destination_cell)
	):
		_record_runtime_evidence_translation_rejection(
			scene_index,
			"destination_mismatch_or_solid",
			requested_key,
			{
				"resolved": previous_cell,
				"requested": requested_destination_cell,
			},
		)
		return null
	translated[-1] = world_destination
	return translated


func _record_runtime_evidence_translation_rejection(
	scene_index: int,
	reason: String,
	requested_key: Vector4i,
	details: Dictionary = {},
) -> void:
	var scene_record := (
		runtime_evidence_translation_rejections.get(
			scene_index,
			{},
		) as Dictionary
	)
	scene_record["count"] = int(scene_record.get("count", 0)) + 1
	scene_record[reason] = int(scene_record.get(reason, 0)) + 1
	scene_record["last_requested_key"] = requested_key
	scene_record["last_details"] = details.duplicate(true)
	runtime_evidence_translation_rejections[scene_index] = scene_record


func _runtime_evidence_step_is_clear(
	from_cell: Vector2i,
	to_cell: Vector2i,
	movement_offsets: Array[Vector2i],
) -> bool:
	if (
		not navigation.is_valid_cell(from_cell)
		or not navigation.is_valid_cell(to_cell)
		or not _runtime_evidence_anchor_is_clear(
			to_cell,
			movement_offsets,
		)
	):
		return false
	var delta := to_cell - from_cell
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		return false
	if delta.x == 0 or delta.y == 0:
		return true
	# The recovered graph permits a diagonal around one blocked cardinal side,
	# but never through a corner where both cardinal neighbors are blocked.
	return (
		_runtime_evidence_anchor_is_clear(
			from_cell + Vector2i(delta.x, 0),
			movement_offsets,
		)
		or _runtime_evidence_anchor_is_clear(
			from_cell + Vector2i(0, delta.y),
			movement_offsets,
		)
	)


func _runtime_evidence_anchor_is_clear(
	anchor: Vector2i,
	movement_offsets: Array[Vector2i],
) -> bool:
	for offset: Vector2i in movement_offsets:
		var occupied_cell := anchor + offset
		if (
			not navigation.is_valid_cell(occupied_cell)
			or navigation.astar.is_point_solid(occupied_cell)
		):
			return false
	return true


static func _runtime_evidence_key_precedes(
	first: Vector4i,
	second: Vector4i,
) -> bool:
	if first.x != second.x:
		return first.x < second.x
	if first.y != second.y:
		return first.y < second.y
	if first.z != second.z:
		return first.z < second.z
	return first.w < second.w


func _runtime_evidence_path_cache_key(
	world_start: Vector2,
	world_destination: Vector2,
) -> Vector4i:
	# Stable process captures use integer pixels, while movement integration
	# can retain subpixel endpoints. A 1/1024-pixel key distinguishes genuine
	# collision displacement without depending on locale-sensitive strings.
	const SUBPIXEL_SCALE := 1024.0
	return Vector4i(
		roundi(world_start.x * SUBPIXEL_SCALE),
		roundi(world_start.y * SUBPIXEL_SCALE),
		roundi(world_destination.x * SUBPIXEL_SCALE),
		roundi(world_destination.y * SUBPIXEL_SCALE),
	)


func _cache_prewarmed_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	cache_empty_path: bool,
	use_global_static_cache: bool = false,
) -> PackedVector2Array:
	if (
		navigation == null
		or not actors.has(scene_index)
		or world_start.is_equal_approx(world_destination)
	):
		return PackedVector2Array()
	var cache_key := _path_cache_key(world_start, world_destination)
	var footprint_key := _scene_movement_footprint_key(scene_index)
	var profile_caches := (
		prewarmed_paths_by_footprint.get(scene_index, {}) as Dictionary
	)
	var scene_cache := profile_caches.get(footprint_key, {}) as Dictionary
	if scene_cache.has(cache_key):
		return (scene_cache[cache_key] as PackedVector2Array).duplicate()
	var global_cache_key := ""
	if use_global_static_cache and not static_prewarm_cache_namespace.is_empty():
		global_cache_key = _global_static_prewarm_cache_key(
			scene_index,
			cache_key,
		)
		if global_static_prewarmed_paths.has(global_cache_key):
			var global_path := (
				global_static_prewarmed_paths[global_cache_key]
				as PackedVector2Array
			).duplicate()
			scene_cache[cache_key] = global_path.duplicate()
			profile_caches[footprint_key] = scene_cache
			prewarmed_paths_by_footprint[scene_index] = profile_caches
			prewarmed_paths[scene_index] = scene_cache
			static_prewarm_cache_hit_count += 1
			return global_path
	var path := find_path_for_scene(
		scene_index,
		world_start,
		world_destination,
	)
	_clear_goal(scene_index)
	if path.is_empty() and not cache_empty_path:
		return path
	profile_caches = (
		prewarmed_paths_by_footprint.get(scene_index, {}) as Dictionary
	)
	scene_cache = profile_caches.get(footprint_key, {}) as Dictionary
	scene_cache[cache_key] = path.duplicate()
	profile_caches[footprint_key] = scene_cache
	prewarmed_paths_by_footprint[scene_index] = profile_caches
	# Keep the current profile mirrored for diagnostics and compatibility with
	# existing tooling that inspects prewarmed_paths directly.
	prewarmed_paths[scene_index] = scene_cache
	if not global_cache_key.is_empty():
		if (
			global_static_prewarmed_paths.size()
			>= MAX_GLOBAL_STATIC_PREWARM_PATHS
		):
			global_static_prewarmed_paths.clear()
		global_static_prewarmed_paths[global_cache_key] = path.duplicate()
	prewarmed_path_build_count += 1
	return path


func _global_static_prewarm_cache_key(
	scene_index: int,
	path_key: Vector4i,
) -> String:
	var actor := actors.get(scene_index, {}) as Dictionary
	var movement_offsets := (
		actor.get("movement_offsets", [Vector2i.ZERO])
		as Array[Vector2i]
	)
	return "%s|%s|%dx%d|a%d|d%d|%d,%d,%d,%d|%s" % [
		GLOBAL_STATIC_PREWARM_CACHE_VERSION,
		static_prewarm_cache_namespace,
		int(navigation.dimensions.x),
		int(navigation.dimensions.y),
		actors.size(),
		disabled_source_scenes.size(),
		path_key.x,
		path_key.y,
		path_key.z,
		path_key.w,
		_movement_offsets_cache_key(movement_offsets),
	]


func _prewarmed_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
) -> Variant:
	last_prewarmed_path_nearest_distance = -1
	if not prewarmed_paths_by_footprint.has(scene_index):
		return null
	var footprint_key := _scene_movement_footprint_key(scene_index)
	var profile_caches := (
		prewarmed_paths_by_footprint[scene_index] as Dictionary
	)
	if not profile_caches.has(footprint_key):
		return null
	var scene_cache := profile_caches[footprint_key] as Dictionary
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
	profile_caches[footprint_key] = scene_cache
	prewarmed_paths_by_footprint[scene_index] = profile_caches
	prewarmed_paths[scene_index] = scene_cache
	prewarmed_path_suffix_hit_count += 1
	return best_suffix


func _cache_dense_static_path(
	scene_index: int,
	world_start: Vector2,
	world_destination: Vector2,
	path: PackedVector2Array,
) -> void:
	var cache_key := _path_cache_key(world_start, world_destination)
	var footprint_key := _scene_movement_footprint_key(scene_index)
	var profile_caches := (
		prewarmed_paths_by_footprint.get(scene_index, {}) as Dictionary
	)
	var scene_cache := profile_caches.get(footprint_key, {}) as Dictionary
	scene_cache[cache_key] = path.duplicate()
	profile_caches[footprint_key] = scene_cache
	prewarmed_paths_by_footprint[scene_index] = profile_caches
	prewarmed_paths[scene_index] = scene_cache


func _scene_movement_footprint_key(scene_index: int) -> String:
	var actor := actors.get(scene_index, {}) as Dictionary
	var movement_offsets := (
		actor.get("movement_offsets", [Vector2i.ZERO])
		as Array[Vector2i]
	)
	return _movement_offsets_cache_key(movement_offsets)


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
	_reserve_goal_origin(scene_index, movement_offsets, goal_origin)


func _reserve_goal_origin(
	scene_index: int,
	movement_offsets: Array[Vector2i],
	goal_origin: Vector2i,
) -> void:
	goal_origin_by_scene[scene_index] = goal_origin
	for offset: Vector2i in movement_offsets:
		goal_owners[goal_origin + offset] = scene_index


func release_goal(scene_index: int) -> void:
	_clear_goal(scene_index)


func try_relocate(
	scene_index: int,
	new_world_position: Vector2,
	ignore_dynamic_actors: bool = false,
	minimum_actor_separation: float = -1.0,
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
		(not ignore_dynamic_actors or minimum_actor_separation > 0.0)
		and not _keeps_actor_separation(
			scene_index,
			old_world_position,
			new_world_position,
			(
				minimum_actor_separation
				if minimum_actor_separation > 0.0
				else MIN_ACTOR_SEPARATION
			),
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
	minimum_actor_separation: float = -1.0,
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
	var old_world_position := actor["world_position"] as Vector2
	if (
		minimum_actor_separation > 0.0
		and not _keeps_actor_separation(
			scene_index,
			old_world_position,
			new_world_position,
			minimum_actor_separation,
		)
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
	var staged_keys: Array[String] = []
	for cache_key_value: Variant in staged_footprint_offsets_by_key.keys():
		staged_keys.append(str(cache_key_value))
	staged_keys.sort()
	for cache_key: String in staged_keys:
		var staged_value: Variant = staged_footprint_offsets_by_key.get(cache_key)
		if staged_value is Array:
			_blocked_origins_for_offsets(
				staged_value as Array[Vector2i]
			)
	for actor_value: Variant in actors.values():
		var actor := actor_value as Dictionary
		var offsets := actor["movement_offsets"] as Array[Vector2i]
		if offsets.size() <= 1:
			continue
		_blocked_origins_for_offsets(offsets)
	staged_footprint_offsets_by_key.clear()
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
	var width: int = navigation.dimensions.x
	var height: int = navigation.dimensions.y
	# One Dictionary<Vector2i, bool> per action/direction footprint consumed
	# tens of MiB on m004. Navigation dimensions are fixed, so a compact byte
	# grid preserves exact O(1) membership for incremental door updates.
	var blocked_lookup := PackedByteArray()
	blocked_lookup.resize(width * height)
	blocked_lookup.fill(0)
	var has_fast_source_grid := (
		source_movement_blocked_bits.size() == width * height
	)
	for y: int in range(navigation.dimensions.y):
		for x: int in range(navigation.dimensions.x):
			var candidate := Vector2i(x, y)
			for offset: Vector2i in offsets:
				var footprint_cell := candidate + offset
				var source_blocked := (
					footprint_cell.x < 0
					or footprint_cell.y < 0
					or footprint_cell.x >= width
					or footprint_cell.y >= height
				)
				if not source_blocked:
					if has_fast_source_grid:
						source_blocked = (
							source_movement_blocked_bits[
								footprint_cell.y * width + footprint_cell.x
							]
							!= 0
						)
					else:
						source_blocked = _source_movement_blocked(footprint_cell)
				if source_blocked:
					blocked.append(candidate)
					blocked_lookup[y * width + x] = 1
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
			footprint_blocked_origin_lookups[cache_key]
			as PackedByteArray
		)
		var width: int = navigation.dimensions.x
		var candidates: Dictionary = {}
		for changed_cell: Vector2i in changed_cells:
			for offset: Vector2i in offsets:
				var candidate := changed_cell - offset
				if navigation.is_valid_cell(candidate):
					candidates[candidate] = true
		for candidate_value: Variant in candidates.keys():
			var candidate := candidate_value as Vector2i
			var candidate_index := candidate.y * width + candidate.x
			var now_blocked := false
			for offset: Vector2i in offsets:
				if _source_movement_blocked(candidate + offset):
					now_blocked = true
					break
			if now_blocked and blocked_lookup[candidate_index] == 0:
				blocked_lookup[candidate_index] = 1
				blocked.append(candidate)
			elif not now_blocked and blocked_lookup[candidate_index] != 0:
				blocked_lookup[candidate_index] = 0
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


static func _normalized_footprint_offsets(
	offsets: Array[Vector2i],
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for offset: Vector2i in offsets:
		if seen.has(offset):
			continue
		seen[offset] = true
		result.append(offset)
	result.sort()
	return result


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
	if navigation == null or not navigation.is_valid_cell(cell):
		return true
	var width: int = navigation.dimensions.x
	var index := cell.y * width + cell.x
	if (
		index >= 0
		and index < source_movement_blocked_bits.size()
		and source_movement_blocked_bits.size()
			== width * navigation.dimensions.y
	):
		return source_movement_blocked_bits[index] != 0
	return navigation.is_movement_blocked(cell, disabled_source_scenes)


func _rebuild_source_movement_blocked_bits() -> void:
	source_movement_blocked_bits.clear()
	if navigation == null:
		return
	var width: int = navigation.dimensions.x
	var height: int = navigation.dimensions.y
	if width <= 0 or height <= 0:
		return
	source_movement_blocked_bits.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			var cell := Vector2i(x, y)
			source_movement_blocked_bits[y * width + x] = (
				1
				if navigation.is_movement_blocked(
					cell,
					disabled_source_scenes,
				)
				else 0
			)


func _refresh_source_movement_blocked_bits(
	changed_cells: Array[Vector2i],
) -> void:
	if navigation == null or changed_cells.is_empty():
		return
	var width: int = navigation.dimensions.x
	var height: int = navigation.dimensions.y
	if source_movement_blocked_bits.size() != width * height:
		_rebuild_source_movement_blocked_bits()
		return
	for cell: Vector2i in changed_cells:
		if not navigation.is_valid_cell(cell):
			continue
		source_movement_blocked_bits[cell.y * width + cell.x] = (
			1
			if navigation.is_movement_blocked(
				cell,
				disabled_source_scenes,
			)
			else 0
		)


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
	minimum_separation: float = MIN_ACTOR_SEPARATION,
) -> bool:
	minimum_separation = maxf(minimum_separation, 0.0)
	var target_origin: Vector2i = navigation.world_to_cell(
		new_world_position
	)
	var x_radius := maxi(
		ceili(minimum_separation / float(navigation.cell_size.x)),
		1,
	)
	var y_radius := maxi(
		ceili(minimum_separation / float(navigation.cell_size.y)),
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
					new_distance < minimum_separation
					and new_distance <= old_distance
				):
					var other_origin := (
						(actors[other_scene] as Dictionary)["origin"]
						as Vector2i
					)
					if (
						scene_index < other_scene
						and goal_origin_by_scene.has(scene_index)
						and goal_origin_by_scene.has(other_scene)
						and target_origin != other_origin
						and new_distance
						>= MIN_PRIORITY_PASS_SEPARATION
					):
						continue
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
	goal_origin_by_scene.erase(scene_index)
