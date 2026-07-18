extends SceneTree

const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
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
const PLAYABLE_NAMES := {
	"老赵": true,
	"铁蛋": true,
	"强子": true,
	"古明": true,
	"大牛": true,
}
const EXPECTED_ENTITY_COUNT := 19199
const EXPECTED_SPRITE_COUNT := 980
const EXPECTED_GROUP_COUNT := 2775
const EXPECTED_FRAME_COUNT := 11898
const EXPECTED_MANUAL_CORRECTION_COUNT := 17858

var failures: Array[String] = []
var check_count := 0


func _init() -> void:
	var total_entities := 0
	var total_playable_spawns := 0
	var total_manual_corrections := 0
	var faction_counts := {1: 0, 2: 0, 3: 0}
	var enemy_attack_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	var enemy_hit_point_counts := {4: 0, 8: 0, 16: 0}
	var special_sensor_count := 0
	var nonempty_patrol_count := 0
	for level_id: String in LEVEL_IDS:
		var level: Dictionary = IMPORTED_LEVEL_DATA.load_level(level_id)
		expect(not level.is_empty(), "%s level metadata loads" % level_id)
		if level.is_empty():
			continue
		validate_mission_runtime_bindings(level_id, level)
		total_entities += (level["entities"] as Array).size()
		var metadata: Dictionary = level["navigation"] as Dictionary
		var level_directory: String = (
			ProjectSettings.globalize_path(IMPORTED_LEVEL_DATA.level_path(level_id)).get_base_dir()
		)
		var navigation_path: String = level_directory.path_join(str(metadata["relative_path"]))
		var navigation: NavigationGridData = NAVIGATION_GRID_DATA.load_file(
			navigation_path, metadata
		)
		expect(navigation != null, "%s M37NAV1 data loads" % level_id)
		if navigation == null:
			continue
		var world_size: Dictionary = level["world_size"] as Dictionary
		expect(
			(
				navigation.dimensions * navigation.cell_size
				== Vector2i(int(world_size["width"]), int(world_size["height"]))
			),
			"%s navigation dimensions match its rendered terrain" % level_id,
		)
		var expected_file_size: int = (
			NAVIGATION_GRID_DATA.HEADER_SIZE
			+ (
				NAVIGATION_GRID_DATA.LAYER_COUNT
				* (4 + navigation.dimensions.x * navigation.dimensions.y * 4)
			)
		)
		expect(
			FileAccess.get_file_as_bytes(navigation_path).size() == expected_file_size,
			"%s navigation binary has the exact validated length" % level_id,
		)
		var event_values: PackedInt64Array = (
			navigation.layers[NAVIGATION_GRID_DATA.EVENT_LAYER_ID] as PackedInt64Array
		)
		expect(count_nonzero(event_values) == 0, "%s formal event layer is empty" % level_id)
		var manual_values: PackedInt64Array = (
			navigation.layers[NAVIGATION_GRID_DATA.MANUAL_CORRECTION_LAYER_ID] as PackedInt64Array
		)
		total_manual_corrections += count_value(manual_values, 1)

		var ignored_scene_indices: Array[int] = []
		var playable_entities: Array[Dictionary] = []
		for entity_value: Variant in level["entities"] as Array:
			var entity := entity_value as Dictionary
			var faction_id := int(entity.get("faction_id", 0))
			if faction_counts.has(faction_id):
				faction_counts[faction_id] = int(faction_counts[faction_id]) + 1
			if bool(entity.get("special_sensor_mode", false)):
				special_sensor_count += 1
			if not (entity.get("patrol_waypoints", []) as Array).is_empty():
				nonempty_patrol_count += 1
			if faction_id == 1:
				var attack_type := int(entity.get("default_attack_type", 0))
				var hit_points := int(entity.get("current_hit_points", 0))
				if enemy_attack_counts.has(attack_type):
					enemy_attack_counts[attack_type] = int(enemy_attack_counts[attack_type]) + 1
				if enemy_hit_point_counts.has(hit_points):
					enemy_hit_point_counts[hit_points] = int(enemy_hit_point_counts[hit_points]) + 1
			if PLAYABLE_NAMES.has(str(entity["display_name"])):
				ignored_scene_indices.append(int(entity["scene_index"]))
				playable_entities.append(entity)
		navigation.prepare_astar(ignored_scene_indices)
		var ignored_lookup: Dictionary = {}
		for scene_index: int in ignored_scene_indices:
			ignored_lookup[scene_index] = true
		for entity: Dictionary in playable_entities:
			total_playable_spawns += 1
			var spawn_cell: Vector2i = navigation.world_to_cell(
				Vector2(float(entity["x"]), float(entity["y"]))
			)
			var spawn_value := navigation.movement_value(spawn_cell)
			expect(
				(
					navigation.is_valid_cell(spawn_cell)
					and (
						not navigation.is_movement_blocked(spawn_cell, ignored_lookup)
						or spawn_value >= 1000
					)
				),
				(
					"%s playable scene %d has a valid or escapable entity-occupied spawn"
					% [level_id, int(entity["scene_index"])]
				),
			)

	expect(total_entities == EXPECTED_ENTITY_COUNT, "all 19,199 formal scene entities validate")
	expect(total_playable_spawns > 0, "formal levels contain validated playable spawn cells")
	expect(
		faction_counts == {1: 656, 2: 85, 3: 31},
		"all recovered actor factions match the 656 enemy, 85 neutral, and 31 friendly records",
	)
	expect(
		enemy_attack_counts == {1: 72, 2: 556, 3: 23, 4: 5},
		"all enemy default attack types match the original VWF records",
	)
	expect(
		enemy_hit_point_counts == {4: 1, 8: 640, 16: 15},
		"all enemy current hit-point values match the original VWF records",
	)
	expect(special_sensor_count == 5, "only the five DBL 1007 guard dogs use special sensing")
	expect(nonempty_patrol_count == 516, "all 516 non-empty original patrol routes are preserved")
	expect(
		total_manual_corrections == EXPECTED_MANUAL_CORRECTION_COUNT,
		"all 17,858 Layer 5 editor correction markers are preserved",
	)
	validate_sprite_manifests()

	if failures.is_empty():
		print("Real imported-asset tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func validate_sprite_manifests() -> void:
	var sprite_root: String = ProjectSettings.globalize_path(
		"res://../LocalAssets/converted/sprite-frames"
	)
	var directories: PackedStringArray = DirAccess.get_directories_at(sprite_root)
	directories.sort()
	var manifest_count := 0
	var group_count := 0
	var frame_count := 0
	for directory_name: String in directories:
		var manifest_path: String = sprite_root.path_join(directory_name).path_join("sprite.json")
		if not FileAccess.file_exists(manifest_path):
			continue
		var manifest: Dictionary = load_json_dictionary(manifest_path)
		expect(not manifest.is_empty(), "sprite %s manifest parses" % directory_name)
		if manifest.is_empty():
			continue
		manifest_count += 1
		for group_value: Variant in manifest.get("groups", []) as Array:
			var group := group_value as Dictionary
			group_count += 1
			var parameters: Array = group.get("parameters", []) as Array
			var threshold := int(group.get("frame_tick_threshold", -1))
			var hold_ticks := int(group.get("frame_hold_ticks", -1))
			expect(
				(
					parameters.size() >= 3
					and threshold == int(parameters[2])
					and hold_ticks == threshold + 1
				),
				(
					"sprite %s group %d preserves exact frame timing"
					% [directory_name, int(group.get("group_index", -1))]
				),
			)
			var frames: Array = group.get("frames", []) as Array
			frame_count += frames.size()
			expect(
				frames.size() == int(group.get("frame_count", -1)),
				(
					"sprite %s group %d frame count matches its manifest"
					% [directory_name, int(group.get("group_index", -1))]
				),
			)
	expect(manifest_count == EXPECTED_SPRITE_COUNT, "all 980 sprite manifests validate")
	expect(group_count == EXPECTED_GROUP_COUNT, "all 2,775 animation groups validate")
	expect(frame_count == EXPECTED_FRAME_COUNT, "all 11,898 animation frames validate")


func validate_mission_runtime_bindings(level_id: String, level: Dictionary) -> void:
	var mission: Dictionary = MISSION_DATA.load_mission(level_id)
	expect(not mission.is_empty(), "%s mission definition loads" % level_id)
	if mission.is_empty():
		return
	var state = MISSION_STATE.new(mission)
	var runtime = MISSION_RUNTIME_SCRIPT.new()
	var configured: bool = runtime.configure(mission, level, state)
	expect(
		configured,
		"%s MissionRuntime resolves every real scene binding: %s" % [level_id, runtime.last_error],
	)
	if not configured:
		runtime.free()
		return

	var scene_bindings := mission.get("scene_bindings", {}) as Dictionary
	for raw_binding_kind: Variant in scene_bindings.keys():
		var binding_kind := str(raw_binding_kind)
		var expected_scenes: Array[int] = []
		for raw_scene: Variant in scene_bindings[raw_binding_kind] as Array:
			expected_scenes.append(int(raw_scene))
		expect(
			runtime.bound_scenes(binding_kind) == expected_scenes,
			"%s binding %s preserves its real scene list" % [level_id, binding_kind],
		)
		for scene_index: int in expected_scenes:
			expect(
				runtime.binding_kinds_for_scene(scene_index).has(binding_kind),
				"%s scene %d round-trips binding %s" % [level_id, scene_index, binding_kind],
			)
	runtime.free()


func load_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data as Dictionary


func count_nonzero(values: PackedInt64Array) -> int:
	var count := 0
	for value: int in values:
		if value != 0:
			count += 1
	return count


func count_value(values: PackedInt64Array, expected: int) -> int:
	var count := 0
	for value: int in values:
		if value == expected:
			count += 1
	return count


func expect(value: bool, description: String) -> void:
	check_count += 1
	if not value:
		failures.append(description)
