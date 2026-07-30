extends SceneTree

const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const LEGACY_CURSOR_PRESENTER: Script = preload(
	"res://scripts/legacy_cursor_presenter.gd"
)
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
const EXPECTED_FIDELITY_KEY_SCENE_COUNT := 258
const WORLD_PICKUP_DATABASE_IDS: Array[int] = [
	982, 983, 984, 986, 987, 988, 990, 993, 998, 999, 1003,
]

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
	validate_runtime_actor_sprite_actions()
	validate_original_cursor_asset()
	validate_special_action_assets()
	validate_m000_farmland_depth()
	validate_all_level_fidelity_baselines()
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
	var movement_triplet_count := 0
	var usable_movement_triplet_count := 0
	for directory_name: String in directories:
		var manifest_path: String = sprite_root.path_join(directory_name).path_join("sprite.json")
		if not FileAccess.file_exists(manifest_path):
			continue
		var manifest: Dictionary = load_json_dictionary(manifest_path)
		expect(not manifest.is_empty(), "sprite %s manifest parses" % directory_name)
		if manifest.is_empty():
			continue
		manifest_count += 1
		var manifest_groups := manifest.get("groups", []) as Array
		expect(
			(
				int(manifest.get("schema_version", 0))
				== IMPORTED_SPRITE_ANIMATION.MAX_SCHEMA_VERSION
				and int(manifest.get("gfl_index", -1)) == int(directory_name)
				and int(manifest.get("group_count", -1)) == manifest_groups.size()
			),
			"sprite %s uses corrected schema 3, GFL identity, and group count" % directory_name,
		)
		var serial_lookup: Dictionary = {}
		var manifest_frame_count := 0
		for source_group_index: int in range(manifest_groups.size()):
			var group_value: Variant = manifest_groups[source_group_index]
			var group := group_value as Dictionary
			group_count += 1
			var semantic: Dictionary = IMPORTED_SPRITE_ANIMATION.group_semantic(group)
			expect(
				(
					not semantic.is_empty()
					and int(group.get("group_index", -1)) == source_group_index
					and not serial_lookup.has(int(semantic.get("serial_id", -1)))
				),
				(
					"sprite %s group %d has a unique exact action/direction serial"
					% [directory_name, source_group_index]
				),
			)
			if str(group.get("action_key", "")) in ["walk", "crawl"]:
				movement_triplet_count += 1
				var movement_triplet := group.get(
					"secondary_triplet",
					[],
				) as Array
				if (
					movement_triplet.size() == 3
					and int(movement_triplet[0]) > 0
					and int(movement_triplet[2]) > 0
				):
					usable_movement_triplet_count += 1
			if not semantic.is_empty():
				serial_lookup[int(semantic["serial_id"])] = true
			expect(
				(
					IMPORTED_SPRITE_ANIMATION.triplet_is_integral(
						group.get("primary_triplet")
					)
					and IMPORTED_SPRITE_ANIMATION.triplet_is_integral(
						group.get("secondary_triplet")
					)
					and IMPORTED_SPRITE_ANIMATION.triplet_is_integral(
						group.get("tertiary_triplet")
					)
				),
				(
					"sprite %s group %d preserves all three integral SPR triplets"
					% [directory_name, source_group_index]
				),
			)
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
			manifest_frame_count += frames.size()
			expect(
				(
					frames.size() == int(group.get("frame_count", -1))
					and IMPORTED_SPRITE_ANIMATION.group_frame_layout_is_valid(
						group,
						frames,
					)
				),
				(
					"sprite %s group %d frame order, dimensions, and atlas match its manifest"
					% [directory_name, int(group.get("group_index", -1))]
				),
			)
		expect(
			manifest_frame_count == int(manifest.get("frame_count", -1)),
			"sprite %s total frame count matches its manifest" % directory_name,
		)
	expect(manifest_count == EXPECTED_SPRITE_COUNT, "all 980 sprite manifests validate")
	expect(group_count == EXPECTED_GROUP_COUNT, "all 2,775 animation groups validate")
	expect(frame_count == EXPECTED_FRAME_COUNT, "all 11,898 animation frames validate")
	expect(
		movement_triplet_count == 373
		and usable_movement_triplet_count == movement_triplet_count,
		"all 373 walk/crawl groups expose usable corrected X/Z movement components",
	)


func validate_runtime_actor_sprite_actions() -> void:
	var catalog := load_json_dictionary(
		"res://data/original_runtime_actor_catalog.json"
	)
	expect(
		(
			int(catalog.get("schema_version", 0)) == 1
			and int((catalog.get("summary", {}) as Dictionary).get(
				"resolved_actor_count",
				-1,
			)) == 772
		),
		"runtime actor catalog exposes the 772 recovered stable-MOD actors",
	)
	var catalog_levels: Dictionary = catalog.get("levels", {}) as Dictionary
	var preview_paths: Dictionary = {}
	var resolved_actor_count := 0
	var patrol_timeline_actor_count := 0
	var patrol_final_relocation_actor_count := 0
	var runtime_faction_override_count := 0
	for level_id: String in LEVEL_IDS:
		var level: Dictionary = IMPORTED_LEVEL_DATA.load_level(level_id)
		var entities_by_scene: Dictionary = {}
		for entity_value: Variant in level.get("entities", []) as Array:
			var entity := entity_value as Dictionary
			entities_by_scene[int(entity.get("scene_index", -1))] = entity
		var catalog_level := catalog_levels.get(level_id, {}) as Dictionary
		var actors := catalog_level.get("actors", {}) as Dictionary
		var level_path: String = ProjectSettings.globalize_path(
			IMPORTED_LEVEL_DATA.level_path(level_id)
		)
		for scene_key: Variant in actors.keys():
			var scene_index := int(scene_key)
			var runtime_profile := actors[scene_key] as Dictionary
			expect(
				entities_by_scene.has(scene_index),
				"%s runtime actor scene %d still exists in its VWF" % [level_id, scene_index],
			)
			if not entities_by_scene.has(scene_index):
				continue
			resolved_actor_count += 1
			var entity := entities_by_scene[scene_index] as Dictionary
			if (
				int(runtime_profile.get("runtime_faction_id", 0))
				!= int(runtime_profile.get("vwf_faction_id", 0))
			):
				runtime_faction_override_count += 1
			if runtime_profile.has("patrol_timeline"):
				var timeline := (
					runtime_profile.get("patrol_timeline", []) as Array
				)
				var observed_position := (
					(runtime_profile.get("observed", {}) as Dictionary).get(
						"position",
						[],
					) as Array
				)
				patrol_timeline_actor_count += 1
				expect(
					(
						int(runtime_profile.get("runtime_faction_id", 0)) == 1
						and timeline.size() == 5
						and (timeline[0] as Dictionary).get("position", [])
						== observed_position
						and int((timeline[0] as Dictionary).get(
							"elapsed_ms",
							-1,
						)) == 0
						and int((timeline[-1] as Dictionary).get(
							"elapsed_ms",
							-1,
						)) == 12000
					),
					(
						"%s runtime actor scene %d binds its audited spawn and patrol loop"
						% [level_id, scene_index]
					),
				)
			if runtime_profile.has("patrol_final_relocation_target_indices"):
				var target_indices := (
					runtime_profile.get(
						"patrol_final_relocation_target_indices",
						[],
					) as Array
				)
				var normalized_target_indices: Array[int] = []
				for target_index_value: Variant in target_indices:
					normalized_target_indices.append(int(target_index_value))
				patrol_final_relocation_actor_count += 1
				expect(
					level_id == "m004"
					and (
						(
							scene_index == 2534
							and normalized_target_indices == [2]
						)
						or (
							scene_index == 2657
							and normalized_target_indices == [1, 3]
						)
					),
					"%s scene %d keeps only its audited final-endpoint correction"
					% [level_id, scene_index],
				)
			var relative_preview := str(entity.get("sprite_preview", ""))
			var preview_path := (
				level_path
				. get_base_dir()
				. path_join(relative_preview)
				. simplify_path()
			)
			expect(
				not relative_preview.is_empty()
				and FileAccess.file_exists(preview_path),
				"%s runtime actor scene %d has its exact SPR preview" % [level_id, scene_index],
			)
			if not relative_preview.is_empty() and FileAccess.file_exists(preview_path):
				preview_paths[preview_path] = true

	var action_set_count := 0
	var full_action_set_count := 0
	var sparse_action_set_count := 0
	var actor_group_count := 0
	var actor_frame_count := 0
	var stand_action_set_count := 0
	var stand_action_group_count := 0
	var stand_action_frame_count := 0
	var active_action_set_count := 0
	var active_action_group_count := 0
	var active_action_frame_count := 0
	for preview_value: Variant in preview_paths.keys():
		var preview_path := str(preview_value)
		var manifest_path: String = (
			IMPORTED_SPRITE_ANIMATION.sprite_manifest_path(preview_path)
		)
		var manifest: Dictionary = load_json_dictionary(manifest_path)
		expect(
			not manifest.is_empty(),
			"runtime actor %s has a loadable SPR manifest" % preview_path.get_file(),
		)
		if manifest.is_empty():
			continue
		var action_groups: Dictionary = {}
		for group_value: Variant in manifest.get("groups", []) as Array:
			var source_group := group_value as Dictionary
			var action_key := str(source_group.get("action_key", ""))
			if not action_groups.has(action_key):
				action_groups[action_key] = []
			(action_groups[action_key] as Array).append(source_group)
			actor_group_count += 1
			actor_frame_count += (
				(source_group.get("frames", []) as Array).size()
			)

		for action_value: Variant in action_groups.keys():
			var action_key := str(action_value)
			var source_groups := action_groups[action_value] as Array
			if action_key == "stand_action":
				stand_action_set_count += 1
				stand_action_group_count += source_groups.size()
				for source_value: Variant in source_groups:
					stand_action_frame_count += ((source_value as Dictionary).get(
						"frames", []
					) as Array).size()
			elif action_key == "active_action":
				active_action_set_count += 1
				active_action_group_count += source_groups.size()
				for source_value: Variant in source_groups:
					active_action_frame_count += ((source_value as Dictionary).get(
						"frames", []
					) as Array).size()
			var direction_lookup: Dictionary = {}
			for source_value: Variant in source_groups:
				var source_group := source_value as Dictionary
				var semantic: Dictionary = (
					IMPORTED_SPRITE_ANIMATION.group_semantic(source_group)
				)
				if not semantic.is_empty():
					direction_lookup[int(semantic["direction_index"])] = true
			var sparse: bool = direction_lookup.size() != 8
			var loaded_groups: Array[Dictionary] = (
				IMPORTED_SPRITE_ANIMATION.load_action_groups(
					preview_path,
					action_key,
					sparse,
				)
			)
			action_set_count += 1
			if sparse:
				sparse_action_set_count += 1
			else:
				full_action_set_count += 1
			expect(
				(
					loaded_groups.size()
					== IMPORTED_SPRITE_ANIMATION.DIRECTION_GROUP_COUNT
					and IMPORTED_SPRITE_ANIMATION.available_group_count(
						loaded_groups
					) == source_groups.size()
				),
				(
					"runtime actor %s action %s loads all %d authored directions"
					% [
						preview_path.get_file(),
						action_key,
						source_groups.size(),
					]
				),
			)
			if loaded_groups.size() != IMPORTED_SPRITE_ANIMATION.DIRECTION_GROUP_COUNT:
				continue
			for source_value: Variant in source_groups:
				var source_group := source_value as Dictionary
				var semantic: Dictionary = (
					IMPORTED_SPRITE_ANIMATION.group_semantic(source_group)
				)
				if semantic.is_empty():
					continue
				var runtime_index: int = (
					IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(
						int(semantic["direction_index"])
					)
				)
				var runtime_group: Dictionary = loaded_groups[runtime_index]
				var primary: Array = source_group.get("primary_triplet", []) as Array
				var timing: Dictionary = IMPORTED_SPRITE_ANIMATION.group_timing(
					source_group
				)
				expect(
					(
						int(runtime_group.get("serial_id", -1))
						== int(semantic["serial_id"])
						and int(runtime_group.get("group_index", -1))
						== int(source_group.get("group_index", -2))
						and runtime_group.get("primary_triplet", [])
						== source_group.get("primary_triplet", [])
						and runtime_group.get("secondary_triplet", [])
						== source_group.get("secondary_triplet", [])
						and runtime_group.get("tertiary_triplet", [])
						== source_group.get("tertiary_triplet", [])
						and (runtime_group.get("anchor", Vector2.ZERO) as Vector2)
						== Vector2(float(primary[0]), float(primary[2]))
						and int(runtime_group.get("frame_hold_ticks", -1))
						== int(timing.get("frame_hold_ticks", -2))
						and (runtime_group.get("frames", []) as Array).size()
						== (source_group.get("frames", []) as Array).size()
					),
					(
						"runtime actor %s action %s direction %d preserves serial, triplets, anchor, timing, and frames"
						% [
							preview_path.get_file(),
							action_key,
							int(semantic["direction_index"]),
						]
					),
				)
			for direction_index: int in range(1, 9):
				if direction_lookup.has(direction_index):
					continue
				var runtime_index: int = (
					IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(
						direction_index
					)
				)
				expect(
					loaded_groups[runtime_index].is_empty(),
					(
						"runtime actor %s action %s leaves unauthored direction %d absent"
						% [preview_path.get_file(), action_key, direction_index]
					),
				)

	expect(resolved_actor_count == 772, "all 772 recovered actors bind to formal VWF scenes")
	expect(
		patrol_timeline_actor_count == 656,
		"all 656 m000-m011 stable-MOD enemy patrol timelines bind to VWF scenes",
	)
	expect(
		patrol_final_relocation_actor_count == 2,
		"only the two audited m004 final-endpoint corrections are attached",
	)
	expect(
		runtime_faction_override_count == 5,
		"all five stable-MOD runtime faction corrections remain attached",
	)
	expect(preview_paths.size() == 39, "the 772 actors resolve to 39 exact original SPR resources")
	expect(action_set_count == 212, "all 212 actor action sets load through the runtime")
	expect(full_action_set_count == 204, "all 204 eight-direction actor actions remain complete")
	expect(
		sparse_action_set_count == 8,
		"the eight original four-direction vehicle actions retain exact sparse serial behavior",
	)
	expect(actor_group_count == 1664, "all 1,664 actor animation groups are runtime reachable")
	expect(actor_frame_count == 9896, "all 9,896 actor animation frames are runtime reachable")
	expect(
		(
			stand_action_set_count == 30
			and stand_action_group_count == 240
			and stand_action_frame_count == 1912
		),
		"AI idle cycling can reach all 30 stand_action sets, 240 directions, and 1,912 frames",
	)
	expect(
		(
			active_action_set_count == 1
			and active_action_group_count == 8
			and active_action_frame_count == 72
		),
		"the original type 8/10 active_action set retains all eight directions and 72 frames",
	)


func validate_original_cursor_asset() -> void:
	var converted_root := ProjectSettings.globalize_path(
		"res://../LocalAssets/converted"
	).simplify_path()
	var manifest_path := converted_root.path_join(
		"sprite-frames/0016/sprite.json"
	).simplify_path()
	var manifest := load_json_dictionary(manifest_path)
	expect(not manifest.is_empty(), "original GFL 16 mouse.spr manifest loads")
	if manifest.is_empty():
		return
	var header_values := manifest.get("header_values", []) as Array
	expect(
		int(manifest.get("gfl_index", -1)) == 16
		and str(manifest.get("resource_name", "")) == "mouse.spr"
		and header_values.size() >= 3
		and int(header_values[2]) == 55,
		"original cursor manifest preserves GFL index, name, and runtime type 55",
	)
	var presenter: RefCounted = LEGACY_CURSOR_PRESENTER.new()
	expect(
		bool(presenter.load_from_converted_root(converted_root)),
		"runtime cursor presenter loads every required original frame",
	)
	expect(
		presenter.available_serial_ids() == [0, 1, 2, 3, 4, 6, 8, 9, 10],
		"mouse.spr exposes the nine recovered cursor serial IDs",
	)
	expect(
		str(presenter.source_manifest_path).simplify_path() == manifest_path,
		"cursor runtime records the contained original manifest path",
	)


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


func validate_all_level_fidelity_baselines() -> void:
	var catalog := load_json_dictionary("res://data/level_fidelity_baselines.json")
	expect(int(catalog.get("schema_version", 0)) == 2, "twelve-level fidelity baseline schema loads")
	expect(
		str(catalog.get("content_profile", "")) == "repository-mod-12-level-20260729",
		"fidelity baseline is bound to the supported stable Mod profile",
	)
	var baselines := catalog.get("levels", []) as Array
	expect(baselines.size() == LEVEL_IDS.size(), "all twelve fidelity baselines are present")
	expect(
		int((catalog.get("summary", {}) as Dictionary).get("entity_count", -1))
		== EXPECTED_ENTITY_COUNT,
		"fidelity catalog covers all 19,199 formal entities",
	)
	expect(
		int((catalog.get("summary", {}) as Dictionary).get("key_entity_count", -1))
		== EXPECTED_FIDELITY_KEY_SCENE_COUNT,
		"fidelity catalog covers all 258 mission, player and task-anchor scenes",
	)
	if baselines.size() != LEVEL_IDS.size():
		return
	var baseline_ids: Array[String] = []
	var total_baseline_entities := 0
	var total_key_scenes := 0
	for baseline_value: Variant in baselines:
		var baseline := baseline_value as Dictionary
		var level_id := str(baseline.get("id", ""))
		baseline_ids.append(level_id)
		var level: Dictionary = IMPORTED_LEVEL_DATA.load_level(level_id)
		expect(not level.is_empty(), "%s fidelity source level loads" % level_id)
		if level.is_empty():
			continue
		var mission: Dictionary = MISSION_DATA.load_mission(level_id)
		expect(
			int(baseline.get("number", -1)) == int(mission.get("number", -2))
			and str(baseline.get("title", "")) == str(mission.get("title", "")),
			"%s fidelity identity matches its mission catalog" % level_id,
		)
		var world_size := level.get("world_size", {}) as Dictionary
		var expected_world := baseline.get("world_size", {}) as Dictionary
		expect(
			int(world_size.get("width", 0)) == int(expected_world.get("width", -1))
			and int(world_size.get("height", 0)) == int(expected_world.get("height", -1)),
			"%s world dimensions match the recovered VWF baseline" % level_id,
		)
		var navigation := level.get("navigation", {}) as Dictionary
		var expected_navigation := baseline.get("navigation", {}) as Dictionary
		expect(
			int(navigation.get("width", 0)) == int(expected_navigation.get("width", -1))
			and int(navigation.get("height", 0)) == int(expected_navigation.get("height", -1))
			and int(navigation.get("cell_width", 0)) == int(expected_navigation.get("cell_width", -1))
			and int(navigation.get("cell_height", 0)) == int(expected_navigation.get("cell_height", -1)),
			"%s navigation dimensions and cells match the recovered baseline" % level_id,
		)

		var level_path := ProjectSettings.globalize_path(
			IMPORTED_LEVEL_DATA.level_path(level_id)
		)
		var level_directory := level_path.get_base_dir()
		var terrain_path := level_directory.path_join(str(level.get("terrain_image", "")))
		var navigation_path := level_directory.path_join(str(navigation.get("relative_path", "")))
		var expected_artifacts := baseline.get("converted_artifacts", {}) as Dictionary
		expect(
			FileAccess.get_sha256(terrain_path).to_upper()
			== str(expected_artifacts.get("terrain_sha256", "")).to_upper(),
			"%s converted terrain pixels retain their committed SHA-256" % level_id,
		)
		expect(
			FileAccess.get_sha256(navigation_path).to_upper()
			== str(expected_artifacts.get("navigation_sha256", "")).to_upper(),
			"%s converted navigation retains its committed SHA-256" % level_id,
		)

		var entities := level.get("entities", []) as Array
		total_baseline_entities += entities.size()
		expect(
			entities.size() == int(baseline.get("entity_count", -1)),
			"%s preserves every recovered entity" % level_id,
		)
		var entities_by_scene: Dictionary = {}
		var faction_counts: Dictionary = {}
		var queue_counts := {"0": 0, "1": 0, "2": 0, "3": 0}
		var enemy_attack_counts: Dictionary = {}
		var enemy_hit_point_counts: Dictionary = {}
		var world_interactable_counts: Dictionary = {}
		var enemy_count := 0
		var enemy_patrol_count := 0
		var enemy_special_sensor_count := 0
		for entity_value: Variant in entities:
			var entity := entity_value as Dictionary
			entities_by_scene[int(entity.get("scene_index", -1))] = entity
			var faction_key := str(int(entity.get("faction_id", 0)))
			faction_counts[faction_key] = int(faction_counts.get(faction_key, 0)) + 1
			var header := entity.get("database_header_values", []) as Array
			var queue_key := str(int(header[0]) if not header.is_empty() else 0)
			queue_counts[queue_key] = int(queue_counts.get(queue_key, 0)) + 1
			var database_entry_id := int(entity.get("database_entry_id", 0))
			if database_entry_id in WORLD_PICKUP_DATABASE_IDS:
				var pickup_key := str(database_entry_id)
				world_interactable_counts[pickup_key] = (
					int(world_interactable_counts.get(pickup_key, 0)) + 1
				)
			if int(entity.get("faction_id", 0)) == 1:
				enemy_count += 1
				if not (entity.get("patrol_waypoints", []) as Array).is_empty():
					enemy_patrol_count += 1
				if bool(entity.get("special_sensor_mode", false)):
					enemy_special_sensor_count += 1
				var attack_key := str(int(entity.get("default_attack_type", 0)))
				enemy_attack_counts[attack_key] = (
					int(enemy_attack_counts.get(attack_key, 0)) + 1
				)
				var hit_point_key := str(int(entity.get("current_hit_points", 0)))
				enemy_hit_point_counts[hit_point_key] = (
					int(enemy_hit_point_counts.get(hit_point_key, 0)) + 1
				)

		expect(
			integer_dictionary_matches(
				faction_counts,
				baseline.get("faction_counts", {}) as Dictionary,
			),
			"%s faction composition matches the original VWF" % level_id,
		)
		expect(
			integer_dictionary_matches(
				queue_counts,
				baseline.get("draw_queue_counts", {}) as Dictionary,
			),
			"%s all four recovered draw queues retain their entity counts" % level_id,
		)
		expect(
			integer_dictionary_matches(
				world_interactable_counts,
				baseline.get("world_interactable_counts", {}) as Dictionary,
			),
			"%s physical world pickups match the recovered VWF" % level_id,
		)
		var expected_enemy := baseline.get("enemy", {}) as Dictionary
		expect(
			enemy_count == int(expected_enemy.get("count", -1)),
			"%s preserves every recovered enemy" % level_id,
		)
		expect(
			enemy_patrol_count == int(expected_enemy.get("nonempty_patrol_count", -1)),
			"%s preserves every non-empty enemy patrol route" % level_id,
		)
		expect(
			integer_dictionary_matches(
				enemy_attack_counts,
				expected_enemy.get("attack_type_counts", {}) as Dictionary,
			),
			"%s enemy attack-type composition matches the original VWF" % level_id,
		)
		expect(
			integer_dictionary_matches(
				enemy_hit_point_counts,
				expected_enemy.get("hit_point_counts", {}) as Dictionary,
			),
			"%s enemy hit-point composition matches the original VWF" % level_id,
		)
		expect(
			enemy_special_sensor_count == int(expected_enemy.get("special_sensor_count", -1)),
			"%s special-sensor actor count matches the original VWF" % level_id,
		)

		var key_entities := baseline.get("key_entities", []) as Array
		total_key_scenes += key_entities.size()
		for expected_value: Variant in key_entities:
			var expected := expected_value as Dictionary
			var scene_index := int(expected.get("scene_index", -1))
			expect(
				entities_by_scene.has(scene_index),
				"%s key scene %d exists" % [level_id, scene_index],
			)
			if not entities_by_scene.has(scene_index):
				continue
			var actual := entities_by_scene[scene_index] as Dictionary
			var header := actual.get("database_header_values", []) as Array
			var actual_queue := int(header[0]) if not header.is_empty() else 0
			var matches := actual_queue == int(expected.get("draw_queue", -1))
			for key: String in [
				"database_entry_id",
				"display_name",
				"faction_id",
				"default_attack_type",
				"x",
				"y",
				"reference_x",
				"reference_y",
			]:
				matches = matches and actual.get(key) == expected.get(key)
			expect(
				matches,
				"%s key scene %d retains identity, draw layer and position"
				% [level_id, scene_index],
			)

		var anchor_counts: Dictionary = {}
		for anchor_value: Variant in level.get("task_anchors", []) as Array:
			var anchor := anchor_value as Dictionary
			var kind := str(anchor.get("kind", ""))
			anchor_counts[kind] = int(anchor_counts.get(kind, 0)) + 1
		expect(
			integer_dictionary_matches(
				anchor_counts,
				baseline.get("task_anchor_counts", {}) as Dictionary,
			),
			"%s task landmark composition matches the recovered VWF" % level_id,
		)

	expect(baseline_ids == LEVEL_IDS, "fidelity baselines retain canonical m000-m011 order")
	expect(
		total_baseline_entities == EXPECTED_ENTITY_COUNT,
		"all per-level fidelity entity totals sum to 19,199",
	)
	expect(
		total_key_scenes == EXPECTED_FIDELITY_KEY_SCENE_COUNT,
		"all per-level fidelity key-scene totals sum to 258",
	)

	var first_level: Dictionary = IMPORTED_LEVEL_DATA.load_level("m000")
	var first_entities_by_scene: Dictionary = {}
	for entity_value: Variant in first_level.get("entities", []) as Array:
		var entity := entity_value as Dictionary
		first_entities_by_scene[int(entity.get("scene_index", -1))] = entity
	var playable := first_entities_by_scene.get(1436, {}) as Dictionary
	expect(
		MAIN_SCRIPT.playable_initial_attack_type(playable, "强子") == 4,
		"m000 starts its recovered playable actor Qiangzi with authored dagger attack type 4",
	)

	var direction_catalog := load_json_dictionary("res://data/mission_direction.json")
	var first_mission: Dictionary = {}
	for mission_value: Variant in direction_catalog.get("missions", []) as Array:
		var mission := mission_value as Dictionary
		if str(mission.get("id", "")) == "m000":
			first_mission = mission
			break
	var dialogue_speakers: Array[String] = []
	for beat_value: Variant in first_mission.get("beats", []) as Array:
		var beat := beat_value as Dictionary
		for line_value: Variant in (
			(beat.get("dialogue", {}) as Dictionary).get("lines", []) as Array
		):
			dialogue_speakers.append(str((line_value as Dictionary).get("speaker", "")))
	expect(
		not dialogue_speakers.has("老赵") and dialogue_speakers.has("强子"),
		"m000 editorial dialogue names its recovered playable actor Qiangzi instead of Lao Zhao",
	)


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


func integer_dictionary_matches(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key_value: Variant in expected.keys():
		var key := str(key_value)
		if not actual.has(key) or int(actual[key]) != int(expected[key_value]):
			return false
	return true


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
