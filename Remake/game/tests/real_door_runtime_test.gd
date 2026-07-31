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
const EXPECTED_SUPPORTED_DOOR_COUNT := 96
const EXPECTED_NAVIGATION_DOOR_COUNT := 94
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
				door.call("active_visual_texture") != null
					and door.get("closed_anchor") is Vector2
					and door.get("open_anchor") is Vector2,
				"%s scene %d uses recovered closed/open art and anchors"
					% [level_id, scene_index],
			)
			_expect(
				not bool(door.get("is_open")),
				"%s scene %d starts closed" % [level_id, scene_index],
			)
			if _uses_original_row_slices(door):
				closed_row_sliced_doors += 1
			door.call("set_open", true, false)
			if _uses_original_row_slices(door):
				open_row_sliced_doors += 1
			door.call("set_open", false, false)
	_expect(
		total_doors == EXPECTED_SUPPORTED_DOOR_COUNT,
		"all %d supported closed doors across the twelve real levels load"
			% EXPECTED_SUPPORTED_DOOR_COUNT,
	)
	_expect(
		navigation_doors == EXPECTED_NAVIGATION_DOOR_COUNT,
		(
			"%d real doors release local VWF movement cells; two decorative "
			+ "instances have no closed-only blocked cell"
		)
			% EXPECTED_NAVIGATION_DOOR_COUNT,
	)
	_expect(
		closed_row_sliced_doors == EXPECTED_SUPPORTED_DOOR_COUNT,
		"all %d closed-door visuals use their original per-column baselines"
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
			_any_solid(main.navigation_grid, movement_cells),
			"closed real door blocks at least one recovered passage cell",
		)
		_expect(
			bool(checkpoint_door.call("open"))
				and main.dynamic_occupancy.is_source_scene_disabled(scene_index),
			"opening a real door releases its source footprint",
		)
		_expect(
			not _any_solid(main.navigation_grid, movement_cells),
			"opening clears every recovered passage cell from A*",
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
	var static_state_violations := 0
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
			if (
				navigation.is_source_cell_released(
					NavigationGridData.MOVEMENT_LAYER_ID,
					cell,
				)
				or not navigation.astar.is_point_solid(cell)
			):
				static_state_violations += 1
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
		if (
			navigation.ignored_scene_indices.has(source_scene)
			or navigation.is_source_cell_released(
				NavigationGridData.MOVEMENT_LAYER_ID,
				cell,
			)
			or not navigation.astar.is_point_solid(cell)
		):
			static_state_violations += 1
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
		"%s keeps every anonymous and non-actor source cell solid" % level_id,
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
		if not (
			door.get("movement_release_cells") as Array[Vector2i]
		).is_empty():
			return door
	return null


func _door_by_scene(main: Node, scene_index: int) -> Node2D:
	for door_value: Variant in main.legacy_doors as Array:
		var door := door_value as Node2D
		if int(door.get("scene_index")) == scene_index:
			return door
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


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
