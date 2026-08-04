extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
)
const ORIGINAL_RUNTIME_ACTOR_CATALOG: Script = preload(
	"res://scripts/original_runtime_actor_catalog.gd"
)
const LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]
const EXPECTED_SUPPORTED_DOOR_COUNT := 177
const EXPECTED_CLOSED_DOOR_COUNT := 97
const EXPECTED_AUTHORED_OPEN_DOOR_COUNT := 80
const EXPECTED_NAVIGATION_DOOR_COUNT := 167
## Counts come from the hash-locked VWF Layer 3 data. "Static" means that the
## encoded scene is not one of the 772 exact RuntimeActor identities; closed
## doors, pickups and historical orphan footprints therefore stay in this
## initially blocking class.
const EXPECTED_STATIC_NAVIGATION := {
	"m000": [2264, 5427, 787, 107, 62],
	"m001": [4751, 4757, 670, 97, 75],
	"m002": [2387, 2714, 235, 95, 34],
	"m003": [10861, 3146, 334, 70, 53],
	"m004": [2290, 8389, 944, 230, 115],
	"m005": [2474, 8375, 258, 100, 92],
	"m006": [2772, 6716, 662, 96, 44],
	"m007": [2226, 6567, 1212, 117, 99],
	"m008": [3475, 2969, 362, 29, 28],
	"m009": [6059, 3625, 705, 102, 48],
	"m010": [16234, 3206, 285, 78, 78],
	"m011": [2364, 3064, 256, 112, 40],
}
const EXPECTED_ANONYMOUS_STATIC_CELL_COUNT := 58157
const EXPECTED_ENCODED_STATIC_CELL_COUNT := 58955
const EXPECTED_ENCODED_STATIC_SCENE_COUNT := 6710
const EXPECTED_ENCODED_ACTOR_CELL_COUNT := 1233
const EXPECTED_ENCODED_ACTOR_SCENE_COUNT := 768

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	var total_doors := 0
	var closed_doors := 0
	var authored_open_doors := 0
	var navigation_doors := 0
	var closed_row_sliced_doors := 0
	var open_row_sliced_doors := 0
	var static_navigation_totals := {
		"anonymous_static_cells": 0,
		"encoded_static_cells": 0,
		"encoded_static_scenes": 0,
		"encoded_actor_cells": 0,
		"encoded_actor_scenes": 0,
	}
	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := LEVEL_IDS[level_index]
		main.switch_level(level_index, false, false)
		var navigation_counts := _audit_static_navigation_footprints(
			main,
			level_id,
		)
		for key: String in static_navigation_totals:
			static_navigation_totals[key] = (
				int(static_navigation_totals[key])
				+ int(navigation_counts.get(key, 0))
			)
		var doors: Array = main.legacy_doors
		total_doors += doors.size()
		for door_value: Variant in doors:
			var door := door_value as Node2D
			var scene_index := int(door.get("scene_index"))
			var sight_cells := (
				door.get("sight_release_cells") as Array[Vector2i]
			)
			var movement_cells := (
				door.get("movement_release_cells") as Array[Vector2i]
			)
			if not movement_cells.is_empty():
				navigation_doors += 1
				_expect(
					not _any_solid(main.navigation_grid, movement_cells),
					"%s scene %d is an A* portal in both visual states"
						% [level_id, scene_index],
				)
			_expect(
				door.call("active_visual_texture") != null
					and door.get("closed_anchor") is Vector2
					and door.get("open_anchor") is Vector2,
				"%s scene %d uses recovered closed/open art and anchors"
					% [level_id, scene_index],
			)
			var starts_open := bool(door.get("starts_open"))
			if starts_open:
				authored_open_doors += 1
			else:
				closed_doors += 1
			_expect(
				bool(door.get("is_open")) == starts_open
					and bool(door.get("locked_open")) == starts_open,
				"%s scene %d starts in its authored door state"
					% [level_id, scene_index],
			)
			if starts_open:
				_expect(
					main.dynamic_occupancy.is_source_scene_disabled(scene_index)
						and not _any_solid(main.navigation_grid, movement_cells),
					"%s scene %d authored opening is immediately traversable"
						% [level_id, scene_index],
				)
			else:
				_expect(
					not main.dynamic_occupancy.is_source_scene_disabled(scene_index)
						and (
							sight_cells.is_empty()
							or _any_line_of_sight_blocked(
								main.navigation_grid,
								sight_cells,
							)
						),
					"%s scene %d keeps its closed art and sight occlusion"
						% [level_id, scene_index],
				)
			if _uses_original_row_slices(door):
				closed_row_sliced_doors += 1
			door.call("set_open", true, false)
			if _uses_original_row_slices(door):
				open_row_sliced_doors += 1
			door.call("set_open", false, false)
	_expect(
		total_doors == EXPECTED_SUPPORTED_DOOR_COUNT,
		"all %d supported door states across the twelve real levels load"
			% EXPECTED_SUPPORTED_DOOR_COUNT,
	)
	_expect(
		closed_doors == EXPECTED_CLOSED_DOOR_COUNT
			and authored_open_doors == EXPECTED_AUTHORED_OPEN_DOOR_COUNT,
		"the real maps retain 97 closed gates and 80 authored openings",
	)
	_expect(
		navigation_doors == EXPECTED_NAVIGATION_DOOR_COUNT,
		(
			"%d/%d real door states own at least one A* portal cell"
		)
			% [navigation_doors, EXPECTED_NAVIGATION_DOOR_COUNT],
	)
	_expect(
		closed_row_sliced_doors == EXPECTED_SUPPORTED_DOOR_COUNT,
		"all %d authored initial door visuals use original per-column baselines"
			% EXPECTED_SUPPORTED_DOOR_COUNT,
	)
	_expect(
		open_row_sliced_doors == EXPECTED_SUPPORTED_DOOR_COUNT,
		"all %d open-door visuals use their original per-column baselines"
			% EXPECTED_SUPPORTED_DOOR_COUNT,
	)
	_expect(
		int(static_navigation_totals["anonymous_static_cells"])
			== EXPECTED_ANONYMOUS_STATIC_CELL_COUNT
			and int(static_navigation_totals["encoded_static_cells"])
			== EXPECTED_ENCODED_STATIC_CELL_COUNT
			and int(static_navigation_totals["encoded_static_scenes"])
			== EXPECTED_ENCODED_STATIC_SCENE_COUNT,
		(
			"all 117,112 original static Layer 3 cells across 6,710 "
			+ "scene footprints remain authoritative"
		),
	)
	_expect(
		int(static_navigation_totals["encoded_actor_cells"])
			== EXPECTED_ENCODED_ACTOR_CELL_COUNT
			and int(static_navigation_totals["encoded_actor_scenes"])
			== EXPECTED_ENCODED_ACTOR_SCENE_COUNT,
		"all 1,233 serialized cells for 768 actor footprints are classified separately",
	)

	main.switch_level(0, false, false)
	var modern_group_count := int(
		main.call("_configure_modern_enemy_patrol_groups", true)
	)
	var modern_leaders := 0
	var modern_followers := 0
	for enemy_value: Variant in main.enemies as Array:
		var role := str((enemy_value as Node).get("modern_patrol_group_role"))
		modern_leaders += 1 if role == "leader" else 0
		modern_followers += 1 if role == "follower" else 0
	_expect(
		modern_group_count > 0
			and modern_leaders == modern_group_count
			and modern_followers >= modern_group_count,
		"m000 forms officer-led patrol groups with one or more trailing soldiers",
	)
	var checkpoint_door := _first_door_with_source_footprint(main)
	_expect(checkpoint_door != null, "m000 exposes a door checkpoint target")
	if checkpoint_door != null:
		var scene_index := int(checkpoint_door.get("scene_index"))
		_expect(
			not main.dynamic_occupancy.is_source_scene_disabled(scene_index),
			"closed real door keeps its serialized footprint enabled",
		)
		var movement_cells := (
			checkpoint_door.get("movement_release_cells") as Array[Vector2i]
		)
		_expect(
			not _any_solid(main.navigation_grid, movement_cells),
			"closed real door leaves every recovered passage cell routable",
		)
		_expect(
			_has_short_path_through_door(main.navigation_grid, movement_cells),
			"a real m000 A* route crosses the closed door portal",
		)
		_expect(
			_click_world(main, checkpoint_door.position)
				and bool(checkpoint_door.get("is_open"))
				and main.dynamic_occupancy.is_source_scene_disabled(scene_index),
			"a target-viewport left click opens a real door and releases its source footprint",
		)
		_expect(
			not _any_solid(main.navigation_grid, movement_cells),
			"opening keeps every recovered passage cell available to A*",
		)
		checkpoint_door.call("set_open", false, false)
		var moving_unit := _first_live_unit(main)
		if moving_unit != null:
			moving_unit.position = checkpoint_door.position
			moving_unit.set(
				"movement_path",
				PackedVector2Array([checkpoint_door.position + Vector2(96.0, 0.0)]),
			)
			moving_unit.set("movement_path_index", 0)
		_expect(
			moving_unit != null
				and int(main.call("_advance_automatic_door_interactions")) >= 1
				and bool(checkpoint_door.get("is_open")),
			"a moving actor opens the real door automatically on approach",
		)
		var checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		main.switch_level(0, false, false)
		var restore_result: Dictionary = (
			GAME_SESSION_STATE.apply_after_level_loaded(main, checkpoint)
		)
		var restored_door := _door_by_scene(main, scene_index)
		_expect(
			bool(restore_result.get("ok", false))
				and restored_door != null
				and bool(restored_door.get("is_open")),
			"real door open state survives session restoration",
		)
		_expect(
			main.dynamic_occupancy.is_source_scene_disabled(scene_index),
			"restored open door keeps its source footprint released",
		)

	main.queue_free()
	if failures.is_empty():
		print(
			(
				"Real door/static-navigation runtime tests passed "
				+ "(%d checks, %d static cells)."
			)
			% [
				checks,
				EXPECTED_ANONYMOUS_STATIC_CELL_COUNT
					+ EXPECTED_ENCODED_STATIC_CELL_COUNT,
			]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _audit_static_navigation_footprints(
	main: Node,
	level_id: String,
) -> Dictionary:
	var counts := {
		"anonymous_static_cells": 0,
		"encoded_static_cells": 0,
		"encoded_static_scenes": 0,
		"encoded_actor_cells": 0,
		"encoded_actor_scenes": 0,
	}
	var navigation: NavigationGridData = main.navigation_grid
	var occupancy: RefCounted = main.dynamic_occupancy
	_expect(
		navigation != null and occupancy != null,
		"%s initializes static and dynamic navigation" % level_id,
	)
	if navigation == null or occupancy == null:
		return counts
	var catalog: Dictionary = ORIGINAL_RUNTIME_ACTOR_CATALOG.load_catalog()
	var catalog_levels := catalog.get("levels", {}) as Dictionary
	var catalog_level := catalog_levels.get(level_id, {}) as Dictionary
	var expected_actor_scenes := catalog_level.get("actors", {}) as Dictionary
	var runtime_actors := occupancy.get("actors") as Dictionary
	var unexpected_runtime_scenes: Array[int] = []
	for scene_value: Variant in runtime_actors.keys():
		var scene_index := int(scene_value)
		if not expected_actor_scenes.has(str(scene_index)):
			unexpected_runtime_scenes.append(scene_index)
	unexpected_runtime_scenes.sort()
	_expect(
		unexpected_runtime_scenes.is_empty(),
		"%s never reclassifies static scenery as a dynamic actor: %s"
			% [level_id, str(unexpected_runtime_scenes)],
	)

	var movement_values := (
		navigation.layers[NavigationGridData.MOVEMENT_LAYER_ID]
		as PackedInt64Array
	)
	var static_scenes: Dictionary = {}
	var actor_scenes: Dictionary = {}
	var door_portal_scenes: Dictionary = {}
	var door_portal_cells: Dictionary = {}
	for door_value: Variant in main.legacy_doors as Array:
		var door := door_value as Node2D
		var movement_cells := (
			door.get("movement_release_cells") as Array[Vector2i]
		)
		if movement_cells.is_empty():
			continue
		door_portal_scenes[int(door.get("scene_index"))] = true
		for release_cell: Vector2i in movement_cells:
			door_portal_cells[release_cell] = true
	var static_state_violations := 0
	var static_state_examples: Array[String] = []
	var live_actor_state_violations := 0
	for cell_index: int in range(movement_values.size()):
		var encoded := int(movement_values[cell_index])
		if encoded == 0:
			continue
		var cell := navigation.index_to_cell(cell_index)
		if encoded < 1000:
			counts["anonymous_static_cells"] = (
				int(counts["anonymous_static_cells"]) + 1
			)
			var anonymous_should_be_open := door_portal_cells.has(cell)
			var anonymous_is_released := navigation.is_source_cell_released(
				NavigationGridData.MOVEMENT_LAYER_ID,
				cell,
			)
			if (
				(
					anonymous_should_be_open
					and (
						not anonymous_is_released
						or navigation.astar.is_point_solid(cell)
					)
				)
				or (
					not anonymous_should_be_open
					and (
						anonymous_is_released
						or not navigation.astar.is_point_solid(cell)
					)
				)
			):
				static_state_violations += 1
				if static_state_examples.size() < 8:
					static_state_examples.append(
						"anonymous %s expected_open=%s released=%s solid=%s"
						% [cell, anonymous_should_be_open, anonymous_is_released, navigation.astar.is_point_solid(cell)]
					)
			continue
		var source_scene := encoded - 1000
		if expected_actor_scenes.has(str(source_scene)):
			counts["encoded_actor_cells"] = (
				int(counts["encoded_actor_cells"]) + 1
			)
			actor_scenes[source_scene] = true
			if (
				runtime_actors.has(source_scene)
				and (
					not navigation.ignored_scene_indices.has(source_scene)
					or navigation.astar.is_point_solid(cell)
				)
			):
				live_actor_state_violations += 1
			continue
		counts["encoded_static_cells"] = (
			int(counts["encoded_static_cells"]) + 1
		)
		static_scenes[source_scene] = true
		var encoded_should_be_open := (
			door_portal_scenes.has(source_scene)
			or door_portal_cells.has(cell)
		)
		var encoded_is_released := (
			navigation.is_source_cell_released(
				NavigationGridData.MOVEMENT_LAYER_ID,
				cell,
			)
		)
		var encoded_source_ignored := (
			navigation.ignored_scene_indices.has(source_scene)
		)
		if (
			(
				encoded_should_be_open
				and (
					(not encoded_is_released and not encoded_source_ignored)
					or navigation.astar.is_point_solid(cell)
				)
			)
			or (
				not encoded_should_be_open
				and (
					encoded_is_released or encoded_source_ignored
					or not navigation.astar.is_point_solid(cell)
				)
			)
		):
			static_state_violations += 1
			if static_state_examples.size() < 8:
				static_state_examples.append(
					"scene %d %s expected_open=%s released=%s ignored=%s solid=%s"
					% [source_scene, cell, encoded_should_be_open, encoded_is_released, encoded_source_ignored, navigation.astar.is_point_solid(cell)]
				)
	counts["encoded_static_scenes"] = static_scenes.size()
	counts["encoded_actor_scenes"] = actor_scenes.size()

	var expected := EXPECTED_STATIC_NAVIGATION.get(level_id, []) as Array
	_expect(
		expected.size() == 5
			and int(counts["anonymous_static_cells"]) == int(expected[0])
			and int(counts["encoded_static_cells"]) == int(expected[1])
			and int(counts["encoded_static_scenes"]) == int(expected[2])
			and int(counts["encoded_actor_cells"]) == int(expected[3])
			and int(counts["encoded_actor_scenes"]) == int(expected[4]),
		"%s Layer 3 static/actor footprint census matches stable MOD"
			% level_id,
	)
	_expect(
		static_state_violations == 0,
		"%s releases only cells owned by interactive door portals: %s"
			% [level_id, str(static_state_examples)],
	)
	_expect(
		live_actor_state_violations == 0,
		"%s replaces live actor source cells only with dynamic occupancy"
			% level_id,
	)
	return counts


func _first_door_with_source_footprint(main: Node) -> Node2D:
	for door_value: Variant in main.legacy_doors as Array:
		var door := door_value as Node2D
		if bool(door.get("starts_open")):
			continue
		if (
			door.get("movement_release_cells") as Array[Vector2i]
		).is_empty():
			continue
		var overlaps_player := false
		for unit_value: Variant in main.units as Array:
			var unit := unit_value as Node2D
			if bool(unit.get("is_alive")) and bool(
				unit.call("contains_parent_point", door.position)
			):
				overlaps_player = true
				break
		if not overlaps_player:
			return door
	return null


func _click_world(main: Node, world_position: Vector2) -> bool:
	main.level_camera.position = world_position
	main.clamp_level_camera()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = main.get_global_transform_with_canvas() * world_position
		root.push_input(event, true)
	return true


func _door_by_scene(main: Node, scene_index: int) -> Node2D:
	for door_value: Variant in main.legacy_doors as Array:
		var door := door_value as Node2D
		if int(door.get("scene_index")) == scene_index:
			return door
	return null


func _first_live_unit(main: Node) -> Node2D:
	for unit_value: Variant in main.units as Array:
		var unit := unit_value as Node2D
		if unit != null and bool(unit.get("is_alive")):
			return unit
	return null


func _uses_original_row_slices(door: Node2D) -> bool:
	var renderer: Variant = door.get("row_slice_renderer")
	return (
		bool(door.get("sprite_drawn_by_row_slices"))
		and renderer is Node2D
		and is_instance_valid(renderer)
		and int((renderer as Node2D).call("active_part_count")) > 1
	)


func _any_solid(navigation: RefCounted, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if navigation.get("astar").is_point_solid(cell):
			return true
	return false


func _any_line_of_sight_blocked(
	navigation: RefCounted,
	cells: Array[Vector2i],
) -> bool:
	for cell: Vector2i in cells:
		if bool(navigation.call("is_line_of_sight_blocked", cell)):
			return true
	return false


func _has_short_path_through_door(
	navigation: RefCounted,
	door_cells: Array[Vector2i],
) -> bool:
	var astar := navigation.get("astar") as AStarGrid2D
	if astar == null:
		return false
	var portal_lookup: Dictionary = {}
	for portal_cell: Vector2i in door_cells:
		portal_lookup[portal_cell] = true
	for portal_cell: Vector2i in door_cells:
		for axis: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var start := portal_cell - axis
			var finish := portal_cell + axis
			if (
				not bool(navigation.call("is_valid_cell", start))
				or not bool(navigation.call("is_valid_cell", finish))
				or astar.is_point_solid(start)
				or astar.is_point_solid(finish)
			):
				continue
			var path: Array[Vector2i] = astar.get_id_path(start, finish)
			for path_cell: Vector2i in path:
				if portal_lookup.has(path_cell):
					return true
	return false


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
