extends SceneTree

const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const TACTICAL_MAP_VIEW: Script = preload("res://scripts/tactical_map_view.gd")
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
const MINIMAP_GFL_IDS: Array[int] = [
	1036, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1025,
]
const MINIMAP_CONTENT_BORDERS: Array[Vector2] = [
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(3.0, 7.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
	Vector2(13.0, 13.0),
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
		var world_size_vector := Vector2(
			float(world_size["width"]),
			float(world_size["height"]),
		)
		expect(
			(
				navigation.dimensions * navigation.cell_size
				== Vector2i(int(world_size["width"]), int(world_size["height"]))
			),
			"%s navigation dimensions match its rendered terrain" % level_id,
		)
		var minimap_path := ProjectSettings.globalize_path(
			"res://../LocalAssets/converted/iblock/%d.png" % MINIMAP_GFL_IDS[LEVEL_IDS.find(level_id)]
		)
		var minimap_image := Image.new()
		expect(
			minimap_image.load(minimap_path) == OK,
			"%s recovered minimap image loads" % level_id,
		)
		if not minimap_image.is_empty():
			var minimap_size := Vector2(minimap_image.get_size())
			var expected_border: Vector2 = MINIMAP_CONTENT_BORDERS[LEVEL_IDS.find(level_id)]
			expect(
				minimap_size.is_equal_approx(
					world_size_vector / TACTICAL_MAP_VIEW.ORIGINAL_WORLD_UNITS_PER_MAP_PIXEL
					+ expected_border * 2.0
				),
				"%s minimap is world/16 plus its recovered symmetric border" % level_id,
			)
			expect(
				TACTICAL_MAP_VIEW.recovered_content_border(
					minimap_size,
					world_size_vector,
				).is_equal_approx(expected_border),
				"%s minimap content rectangle can align dynamic world markers" % level_id,
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
	validate_special_action_assets()
	validate_m000_farmland_depth()
	validate_level_independent_inventory_icons()

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


func validate_special_action_assets() -> void:
	var converted_root := ProjectSettings.globalize_path("res://../LocalAssets/converted").simplify_path()
	for attack_type: int in [8, 10]:
		var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(attack_type)
		var gfl_index := int(profile.get("original_gfl_index", 0))
		var actor_type := int(profile.get("original_actor_type", 0))
		var stem := "%04d" % gfl_index
		var manifest_path := converted_root.path_join("sprite-frames").path_join(stem).path_join("sprite.json")
		var manifest: Dictionary = load_json_dictionary(manifest_path)
		expect(not manifest.is_empty(), "type %d GFL %d manifest loads" % [attack_type, gfl_index])
		if not manifest.is_empty():
			var header_values: Array = manifest.get("header_values", []) as Array
			expect(
				int(manifest.get("gfl_index", 0)) == gfl_index,
				"type %d manifest preserves recovered GFL %d" % [attack_type, gfl_index],
			)
			expect(
				header_values.size() >= 3 and int(header_values[2]) == actor_type,
				"type %d GFL %d header preserves actor type %d" % [attack_type, gfl_index, actor_type],
			)
			expect(
				not String(manifest.get("resource_name", "")).is_empty(),
				"type %d GFL %d retains its original resource identity" % [attack_type, gfl_index],
			)
		var preview_path := converted_root.path_join("sprites").path_join("%s.png" % stem)
		expect(FileAccess.file_exists(preview_path), "type %d GFL %d runtime preview exists" % [attack_type, gfl_index])
		var image := Image.new()
		expect(
			image.load(preview_path) == OK and not image.is_empty(),
			"type %d GFL %d runtime preview decodes" % [attack_type, gfl_index],
		)
	var game = MAIN_SCRIPT.new()
	game.converted_root = converted_root
	var type_8_visual: Dictionary = game.call("_load_legacy_special_visual", 470)
	var type_10_visual: Dictionary = game.call("_load_legacy_special_visual", 900)
	expect(
		(type_8_visual.get("frames", []) as Array).size() == 1,
		"type 8 runtime loads the one recovered GFL 470 frame",
	)
	expect(
		(type_10_visual.get("frames", []) as Array).size() == 2,
		"type 10 runtime loads both recovered GFL 900 animation frames",
	)
	expect(
		int(type_10_visual.get("frame_hold_ticks", 0)) == 1,
		"type 10 runtime preserves the recovered one-tick GFL 900 frame hold",
	)
	game.free()


func validate_level_independent_inventory_icons() -> void:
	var game = MAIN_SCRIPT.new()
	game.converted_root = ProjectSettings.globalize_path(
		"res://../LocalAssets/converted"
	).simplify_path()
	expect(
		game.world_entities_by_scene.is_empty(),
		"inventory icon validation starts without current-level pickup entities",
	)
	for action_key: String in [
		"pistol_attack",
		"rifle_attack",
		"machine_gun_attack",
		"dagger_attack",
		"broadsword_attack",
		"throwing_knife_attack",
		"slingshot_attack",
		"active_action",
		"grenade_attack",
		"active_action_alt",
		"special_attack",
	]:
		expect(
			game._inventory_icon_for(action_key, 0, "") != null,
			"m000/m010 inventory weapon %s has a level-independent original or labelled fallback icon" % action_key,
		)
	for item_id: int in [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 99]:
		expect(
			game._inventory_icon_for("", item_id, "") != null,
			"m000/m010 inventory item %d has a stable grid icon" % item_id,
		)
	for item_key: String in ["uniform", "explosives"]:
		expect(
			game._inventory_icon_for("", 0, item_key) != null,
			"m000/m010 mission item %s has a stable grid icon" % item_key,
		)
	game.free()


func validate_m000_farmland_depth() -> void:
	var level: Dictionary = IMPORTED_LEVEL_DATA.load_level("m000")
	var field_base_count := 0
	var rice_count := 0
	var field_bases_are_background := true
	var rice_uses_y_depth := true
	for entity_value: Variant in level.get("entities", []) as Array:
		var entity := entity_value as Dictionary
		var database_entry_id := int(entity.get("database_entry_id", 0))
		if database_entry_id in [336, 337]:
			field_base_count += 1
			var field_header := entity.get("database_header_values", []) as Array
			field_bases_are_background = (
				field_bases_are_background
				and not field_header.is_empty()
				and int(field_header[0]) == 1
				and MAIN_SCRIPT.imported_entity_z_index(entity) == MAIN_SCRIPT.BACKGROUND_ENTITY_Z_INDEX
			)
		elif database_entry_id == 335:
			rice_count += 1
			var rice_header := entity.get("database_header_values", []) as Array
			rice_uses_y_depth = (
				rice_uses_y_depth
				and not rice_header.is_empty()
				and int(rice_header[0]) == 0
				and MAIN_SCRIPT.imported_entity_z_index(entity)
				== MAIN_SCRIPT.WORLD_DEPTH.normal_z(float(entity.get("reference_y", 0.0)))
			)
	expect(field_base_count == 22 and field_bases_are_background, "m000's 22 farmland base tiles stay behind actors")
	expect(rice_count == 70 and rice_uses_y_depth, "m000's 70 individual rice plants retain baseline depth sorting")


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
