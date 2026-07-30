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
	_expect(
		DOOR_CATALOG.profile_for_entity(
			{"database_entry_id": 9999}
		).is_empty(),
		"unpaired scenery is not guessed as an interactive door",
	)


func _test_visual_navigation_and_snapshot_lifecycle() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(15)
	sight.resize(15)
	var door_cell := Vector2i(2, 1)
	var door_index := door_cell.y * 5 + door_cell.x
	movement[door_index] = 1012
	sight[door_index] = 1012
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		5,
		3,
		Vector2i(32, 16),
		movement,
		sight,
	)
	navigation.prepare_astar()
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	occupancy.finalize_registration()
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
	_expect(
		navigation.astar.is_point_solid(door_cell),
		"closed door keeps original L3 footprint blocked",
	)
	_expect(
		not occupancy.has_line_of_sight(
			Vector2(48, 24),
			Vector2(112, 24),
		),
		"closed door keeps original L2 footprint blocked",
	)
	_expect(
		door.contains_parent_point(door.position),
		"closed door exposes a bounded click target",
	)
	_expect(door.open(), "door opens once")
	_expect(
		not navigation.astar.is_point_solid(door_cell)
		and occupancy.is_source_scene_disabled(12),
		"opening releases exact scene L3 footprint",
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
