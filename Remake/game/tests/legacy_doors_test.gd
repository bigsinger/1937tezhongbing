extends SceneTree

const NAVIGATION_GRID_DATA: Script = preload(
	"res://scripts/navigation_grid_data.gd"
)
const DYNAMIC_OCCUPANCY_GRID: Script = preload(
	"res://scripts/dynamic_occupancy_grid.gd"
)
const DOOR_SCRIPT: Script = preload("res://scripts/legacy_door.gd")
const DOOR_CATALOG: Script = preload(
	"res://scripts/legacy_door_catalog.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_catalog()
	_test_permanent_visual_passage()
	_test_visual_navigation_and_snapshot_lifecycle()
	if failures.is_empty():
		print("Legacy door tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_catalog() -> void:
	_expect(
		int(
			DOOR_CATALOG
			. profile_for_entity({"database_entry_id": 175})
			. get("open_gfl_index", 0)
		) == 792,
		"iron gate A resolves to its original open sprite",
	)
	_expect(
		int(
			DOOR_CATALOG
			. profile_for_entity({"database_entry_id": 225})
			. get("open_gfl_index", 0)
		) == 149,
		"station gate B resolves to its original open sprite",
	)
	var authored_open: Dictionary = DOOR_CATALOG.profile_for_entity(
		{"database_entry_id": 341}
	)
	_expect(
		int(authored_open.get("closed_gfl_index", 0)) == 146
			and int(authored_open.get("open_gfl_index", 0)) == 147
			and bool(authored_open.get("starts_open", false))
			and bool(authored_open.get("locked_open", false)),
		"an authored open gate resolves to the same two-state navigation pair",
	)
	_expect(
		DOOR_CATALOG.profile_for_entity(
			{"database_entry_id": 9999}
		).is_empty(),
		"unpaired scenery is not guessed as an interactive door",
	)
	_expect(
		str(
			DOOR_CATALOG
			. permanent_passage_profile_for_entity({"database_entry_id": 98})
			. get("name", "")
		) == "courtyard_arch_a"
			and DOOR_CATALOG.is_permanent_navigation_passage(420)
			and not DOOR_CATALOG.is_permanent_navigation_passage(636),
		"visible arches are classified separately from interactive and closed doors",
	)


func _test_permanent_visual_passage() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(35)
	sight.resize(35)
	var passage_cell := Vector2i(2, 2)
	var stale_reused_cell := Vector2i(6, 0)
	movement[passage_cell.y * 7 + passage_cell.x] = 1033
	movement[stale_reused_cell.y * 7 + stale_reused_cell.x] = 1033
	sight[passage_cell.y * 7 + passage_cell.x] = 1033
	sight[stale_reused_cell.y * 7 + stale_reused_cell.x] = 1033
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		7,
		5,
		Vector2i(32, 16),
		movement,
		sight,
	)
	var entity := {
		"scene_index": 33,
		"database_entry_id": 98,
		"reference_x": 80.0,
		"reference_y": 40.0,
		"sprite_anchor": {"x": 16.0, "y": 8.0},
	}
	var movement_cells: Array[Vector2i] = (
		DOOR_CATALOG.local_source_cells_for_passage(
			entity,
			Vector2(32.0, 16.0),
			navigation,
			NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID,
		)
	)
	var sight_cells: Array[Vector2i] = (
		DOOR_CATALOG.local_source_cells_for_passage(
			entity,
			Vector2(32.0, 16.0),
			navigation,
			NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID,
		)
	)
	_expect(
		movement_cells == [passage_cell]
			and sight_cells == [passage_cell],
		"an open arch releases only source cells intersecting its concrete sprite",
	)
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	occupancy.register_source_scene_footprint(
		33,
		movement_cells,
		sight_cells,
		true,
		true,
	)
	occupancy.finalize_registration()
	_expect(
		not navigation.astar.is_point_solid(passage_cell)
			and not navigation.is_line_of_sight_blocked(passage_cell)
			and navigation.astar.is_point_solid(stale_reused_cell)
			and navigation.is_line_of_sight_blocked(stale_reused_cell),
		"a permanent visual opening releases movement and sight without punching a distant hole",
	)


func _test_visual_navigation_and_snapshot_lifecycle() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(15)
	sight.resize(15)
	var door_cell := Vector2i(2, 1)
	var door_index := door_cell.y * 5 + door_cell.x
	# Seal the rows above and below so the only route between the left and
	# right rooms is the interactive door portal itself.
	movement[Vector2i(2, 0).y * 5 + 2] = 1
	movement[door_index] = 1012
	movement[Vector2i(2, 2).y * 5 + 2] = 1
	sight[door_index] = 1012
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		5,
		3,
		Vector2i(32, 16),
		movement,
		sight,
	)
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	occupancy.register_scene(
		20,
		navigation.cell_to_world(Vector2i(4, 2)),
	)
	var texture := _texture(Color.WHITE)
	var open_texture := _texture(Color(0.4, 0.8, 0.4))
	var profile: Dictionary = DOOR_CATALOG.profile_for_entity(
		{"database_entry_id": 175}
	)
	profile["closed_anchor"] = [16, 8]
	profile["open_anchor"] = [16, 8]
	var door = DOOR_SCRIPT.new()
	_expect(
		door.configure(
			{
				"scene_index": 12,
				"database_entry_id": 175,
				"display_name": "铁丝门-A",
				"x": 80,
				"y": 24,
			},
			profile,
			texture,
			open_texture,
			1,
		),
		"door configures from original scene identity",
	)
	door.bind_dynamic_occupancy(occupancy)
	occupancy.finalize_registration()
	_expect(
		not navigation.astar.is_point_solid(door_cell),
		"closed interactive door is already available to A* route planning",
	)
	_expect(
		not occupancy.has_line_of_sight(
			Vector2(48, 24),
			Vector2(112, 24),
		),
		"closed door keeps original L2 footprint blocked",
	)
	_expect(
		occupancy.prewarm_path_for_scene(
			20,
			navigation.cell_to_world(Vector2i(4, 2)),
			navigation.cell_to_world(Vector2i(3, 2)),
		),
		"an unrelated authored route is cached before a door changes",
	)
	var astar_before_open: AStarGrid2D = navigation.astar
	_expect(
		door.contains_parent_point(door.position),
		"closed door exposes a bounded click target",
	)
	_expect(door.open(), "door opens once")
	_expect(
		not navigation.astar.is_point_solid(door_cell)
			and occupancy.is_source_scene_disabled(12),
		"opening preserves the planned L3 portal and releases the source state",
	)
	_expect(
		navigation.astar == astar_before_open
			and occupancy.prewarmed_paths.has(20)
			and navigation.incremental_source_update_count == 1,
		"opening a door updates its cells in place and preserves unrelated patrol caches",
	)
	_expect(
		not navigation.find_path(
			navigation.cell_to_world(Vector2i(1, 1)),
			navigation.cell_to_world(Vector2i(3, 1)),
		).is_empty(),
		"the planned door passage remains immediately routable after opening",
	)
	_expect(
		occupancy.has_line_of_sight(
			Vector2(48, 24),
			Vector2(112, 24),
		),
		"opening releases exact scene L2 footprint",
	)
	_expect(
		door.texture == open_texture
		and not door.contains_parent_point(door.position),
		"opening swaps to original open art and removes click target",
	)
	door.set_open(false, false)
	_expect(
		not navigation.astar.is_point_solid(door_cell)
			and not occupancy.has_line_of_sight(
				Vector2(48, 24),
				Vector2(112, 24),
			),
		"closing restores visual occlusion without invalidating the A* portal",
	)
	door.open()
	var snapshot: Dictionary = door.snapshot()
	var restored = DOOR_SCRIPT.new()
	restored.configure(
		{
			"scene_index": 12,
			"database_entry_id": 175,
			"display_name": "铁丝门-A",
			"x": 80,
			"y": 24,
		},
		profile,
		texture,
		open_texture,
		1,
	)
	restored.bind_dynamic_occupancy(occupancy)
	restored.set_open(bool(snapshot.get("is_open", false)), false)
	_expect(
		restored.is_open and restored.texture == open_texture,
		"door open state survives snapshot restore",
	)
	door.free()
	restored.free()


func _texture(color: Color) -> Texture2D:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
