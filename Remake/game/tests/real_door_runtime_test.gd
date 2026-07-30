extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
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
	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := LEVEL_IDS[level_index]
		main.switch_level(level_index, false, false)
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
				door.texture != null
					and door.get("closed_anchor") is Vector2
					and door.get("open_anchor") is Vector2,
				"%s scene %d uses recovered closed/open art and anchors"
					% [level_id, scene_index],
			)
			_expect(
				not bool(door.get("is_open")),
				"%s scene %d starts closed" % [level_id, scene_index],
			)
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
		print("Real door runtime tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


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


func _any_solid(navigation: RefCounted, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if navigation.get("astar").is_point_solid(cell):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
