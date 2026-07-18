extends SceneTree

const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const LEVEL_VIEW: Script = preload("res://scripts/level_view.gd")
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const DYNAMIC_OCCUPANCY_GRID: Script = preload("res://scripts/dynamic_occupancy_grid.gd")
const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT_SCRIPT: Script = preload("res://scripts/enemy_unit.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var check_count: int = 0


func _init() -> void:
	var failures: Array[String] = []

	var moved: Vector2 = SIMULATION_SCRIPT.advance_towards(
		Vector2.ZERO, Vector2(3.0, 4.0), 2.0, 1.0
	)
	expect(moved.is_equal_approx(Vector2(1.2, 1.6)), "movement uses speed * delta", failures)

	var clamped: Vector2 = SIMULATION_SCRIPT.advance_towards(
		Vector2.ZERO, Vector2(3.0, 4.0), 20.0, 1.0
	)
	expect(clamped.is_equal_approx(Vector2(3.0, 4.0)), "movement does not overshoot", failures)
	expect(
		SIMULATION_SCRIPT.advance_towards(Vector2.ZERO, Vector2.ONE, -1.0, 1.0) == Vector2.ZERO,
		"negative speed is rejected",
		failures
	)
	expect(
		is_equal_approx(SIMULATION_SCRIPT.FIXED_DELTA, 1.0 / 60.0),
		"simulation tick is 60 Hz",
		failures
	)

	var offsets: Dictionary = {}
	var offset_sum := Vector2.ZERO
	var ordered_offsets: Array[Vector2] = []
	for index: int in range(5):
		var offset: Vector2 = SIMULATION_SCRIPT.formation_offset(index, 5)
		offsets[offset] = true
		offset_sum += offset
		ordered_offsets.append(offset)
	expect(offsets.size() == 5, "formation offsets are unique", failures)
	expect(offset_sum.is_zero_approx(), "formation centroid is centered", failures)

	var bounds := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))
	var corner_center: Vector2 = SIMULATION_SCRIPT.clamp_formation_center(
		Vector2.ZERO, ordered_offsets, bounds
	)
	var corner_targets: Dictionary = {}
	for offset: Vector2 in ordered_offsets:
		var target: Vector2 = corner_center + offset
		corner_targets[target] = true
		expect(point_is_inside(target, bounds), "formation target remains inside bounds", failures)
	expect(corner_targets.size() == 5, "corner formation targets stay unique", failures)

	var clamped_camera: Vector2 = LEVEL_VIEW.clamp_camera_center(
		Vector2.ZERO, Vector2(1280.0, 720.0), 1.0, Vector2(4960.0, 2240.0)
	)
	expect(
		clamped_camera.is_equal_approx(Vector2(640.0, 360.0)),
		"camera keeps a full viewport inside a large imported level",
		failures
	)
	expect(
		(
			LEVEL_VIEW
			. clamp_camera_center(
				Vector2(900.0, 900.0), Vector2(1280.0, 720.0), 1.0, Vector2(400.0, 300.0)
			)
			. is_equal_approx(Vector2(200.0, 150.0))
		),
		"camera centers a level smaller than the viewport",
		failures
	)
	expect(
		is_equal_approx(LEVEL_VIEW.stepped_zoom(2.0, true), LEVEL_VIEW.MAX_ZOOM),
		"camera zoom has a stable upper bound",
		failures
	)
	expect(
		LEVEL_VIEW.imported_terrain_path().ends_with("/m000/terrain.png"),
		"first-level terrain import path is deterministic",
		failures
	)

	var synthetic_level := {
		"schema_version": 1,
		"world_size": {"width": 4960, "height": 2240},
		"tile_size": {"width": 32, "height": 16},
		"terrain_image": "terrain.png",
		"navigation":
		{
			"schema_version": 1,
			"relative_path": "navigation.bin",
			"width": 155,
			"height": 140,
			"cell_width": 32,
			"cell_height": 16,
			"layer_ids":
			{
				"line_of_sight_obstacle": 2,
				"movement_obstacle": 3,
				"event_layer": 4,
				"manual_movement_correction": 5,
			},
		},
		"entities":
		[
			{
				"scene_index": 1415,
				"database_entry_id": 925,
				"resource_name": "三等兵.spr",
				"display_name": "三等兵",
				"category_name": "角色",
				"x": 1968,
				"y": 232,
				"reference_x": 1968,
				"reference_y": 232,
				"sprite_preview": "sprites/0925.png",
				"patrol_waypoints": [{"x": 61, "y": 14}, {"x": 62, "y": 14}],
				"patrol": {"current_waypoint_index": 1, "persistent_flag": 1, "enabled": true},
				"faction_id": 1,
				"direction_index": 7,
				"death_state": 0,
				"crawl_state": 0,
				"current_hit_points": 8,
				"default_attack_type": 2,
				"special_sensor": false,
			}
		],
		"task_anchors":
		[
			{
				"scene_index": 1600,
				"database_entry_id": 1020,
				"kind": "exit_detector",
				"x": 144,
				"y": 64,
				"reference_x": 144,
				"reference_y": 64,
			}
		],
	}
	expect(
		IMPORTED_LEVEL_DATA.is_valid_dictionary(synthetic_level),
		"synthetic imported-level dictionary validates",
		failures
	)
	var parsed_level: Dictionary = IMPORTED_LEVEL_DATA.parse_dictionary(synthetic_level)
	expect(
		parsed_level["world_size"] == {"width": 4960, "height": 2240},
		"imported level parses object world size",
		failures
	)
	expect(
		parsed_level["tile_size"] == {"width": 32, "height": 16},
		"imported level preserves optional tile size",
		failures
	)
	var parsed_entities: Array = parsed_level["entities"] as Array
	var parsed_entity: Dictionary = parsed_entities[0] as Dictionary
	expect(
		(
			parsed_entity["database_entry_id"] == 925
			and parsed_entity["resource_name"] == "三等兵.spr"
			and parsed_entity["category_name"] == "角色"
		),
		"imported entity keeps DBL identity and names",
		failures
	)
	expect(
		(
			parsed_entity["x"] == 1968
			and parsed_entity["y"] == 232
			and parsed_entity["reference_x"] == 1968
			and parsed_entity["reference_y"] == 232
		),
		"imported entity keeps world and reference coordinates",
		failures
	)
	expect(
		(parsed_entity["patrol_waypoints"] as Array)[1] == {"x": 62, "y": 14},
		"imported entity parses patrol waypoints",
		failures
	)
	expect(
		(parsed_level["task_anchors"] as Array)[0]["kind"] == "exit_detector",
		"imported level exposes recovered task anchors",
		failures
	)
	expect(
		(parsed_level["navigation"] as Dictionary)["cell_width"] == 32,
		"imported level exposes recovered navigation metadata",
		failures
	)
	var array_compatible_level: Dictionary = synthetic_level.duplicate(true)
	array_compatible_level["world_size"] = [4960, 2240]
	(array_compatible_level["entities"] as Array)[0]["patrol_waypoints"] = [[61, 14]]
	expect(
		IMPORTED_LEVEL_DATA.is_valid_dictionary(array_compatible_level),
		"imported-level parser accepts coordinate-array compatibility form",
		failures
	)
	var wrong_schema: Dictionary = synthetic_level.duplicate(true)
	wrong_schema["schema_version"] = 2
	expect(
		IMPORTED_LEVEL_DATA.parse_dictionary(wrong_schema).is_empty(),
		"unknown imported-level schema is rejected",
		failures
	)
	expect(
		(
			IMPORTED_LEVEL_DATA
			. load_file("res://../LocalAssets/converted/levels/__missing__/level.json")
			. is_empty()
		),
		"missing imported-level JSON returns an empty result",
		failures
	)
	expect(
		IMPORTED_LEVEL_DATA.DEFAULT_LEVEL_PATH.ends_with("/m000/level.json"),
		"first-level metadata path is deterministic",
		failures
	)
	expect(
		IMPORTED_LEVEL_DATA.level_path("m011").ends_with("/m011/level.json"),
		"all formal level metadata paths are deterministic",
		failures
	)
	expect(
		IMPORTED_LEVEL_DATA.level_path("../m011").is_empty(),
		"level metadata paths reject traversal",
		failures
	)
	expect(
		LEVEL_VIEW.imported_terrain_path("m011").ends_with("/m011/terrain.png"),
		"all formal terrain paths are deterministic",
		failures
	)
	expect(
		LEVEL_VIEW.imported_terrain_path("m12").is_empty(),
		"terrain paths reject malformed level identifiers",
		failures
	)
	expect(
		IMPORTED_SPRITE_ANIMATION.sprite_manifest_path("C:/assets/sprites/1024.png").ends_with(
			"/sprite-frames/1024/sprite.json"
		),
		"sprite preview maps to its animation manifest",
		failures
	)
	expect(
		(
			IMPORTED_SPRITE_ANIMATION
			. sprite_manifest_path("C:/assets/sprites/not-an-index.png")
			. is_empty()
		),
		"sprite animation manifest rejects nonnumeric preview names",
		failures
	)
	expect(
		(
			IMPORTED_SPRITE_ANIMATION
			. contained_path("C:/assets/sprite-frames/1024", "../escape.png")
			. is_empty()
		),
		"sprite frame paths reject traversal",
		failures
	)
	expect(
		str(IMPORTED_SPRITE_ANIMATION.serial_semantic(42)["action_key"]) == "run",
		"SPR serial 42 decodes as running",
		failures
	)
	expect(
		str(IMPORTED_SPRITE_ANIMATION.serial_semantic(42)["direction_key"]) == "southwest",
		"SPR serial 42 decodes as southwest",
		failures
	)
	expect(
		IMPORTED_SPRITE_ANIMATION.serial_semantic(180).is_empty(),
		"out-of-range SPR serials are rejected",
		failures
	)

	var movement_layer := PackedInt64Array()
	movement_layer.resize(7 * 5)
	for wall_y in range(4):
		movement_layer[wall_y * 7 + 3] = 1
	var clear_los_layer := PackedInt64Array()
	clear_los_layer.resize(7 * 5)
	var navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		7, 5, Vector2i(32, 16), movement_layer, clear_los_layer
	)
	expect(navigation != null, "synthetic navigation grid is created", failures)
	navigation.prepare_astar()
	expect(
		navigation.find_path(Vector2(17, 9), Vector2(17, 9)).is_empty(),
		"a no-op path does not snap a unit to its cell center",
		failures,
	)
	var routed_path: PackedVector2Array = navigation.find_path(
		navigation.cell_to_world(Vector2i(0, 1)), navigation.cell_to_world(Vector2i(6, 1))
	)
	expect(not routed_path.is_empty(), "A* finds a route around a movement wall", failures)
	var route_uses_gap := false
	var route_crosses_wall := false
	for route_point: Vector2 in routed_path:
		var route_cell := navigation.world_to_cell(route_point)
		route_uses_gap = route_uses_gap or route_cell == Vector2i(3, 4)
		route_crosses_wall = route_crosses_wall or navigation.is_movement_blocked(route_cell)
	expect(route_uses_gap, "A* route uses the only open wall gap", failures)
	expect(not route_crosses_wall, "A* route never crosses Layer 3 obstacles", failures)
	expect(
		path_is_clear(
			navigation,
			navigation.cell_to_world(Vector2i(0, 1)),
			routed_path,
		),
		"every densely sampled A* path segment stays outside Layer 3 obstacles",
		failures,
	)

	var corner_layer := PackedInt64Array([0, 1, 1, 0])
	var corner_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		2, 2, Vector2i(32, 16), corner_layer
	)
	corner_navigation.prepare_astar()
	expect(
		corner_navigation.find_path(Vector2(16, 8), Vector2(48, 24)).is_empty(),
		"diagonal movement cannot cut through a blocked corner",
		failures,
	)
	var corner_sight_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		2, 2, Vector2i(32, 16), PackedInt64Array([0, 0, 0, 0]), corner_layer
	)
	expect(
		not corner_sight_navigation.has_line_of_sight(Vector2(16, 8), Vector2(48, 24)),
		"a supercover sight ray cannot peek diagonally through a blocked corner",
		failures,
	)
	var blocked_start_layer := PackedInt64Array([1, 0, 0])
	var blocked_start_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		3, 1, Vector2i(32, 16), blocked_start_layer
	)
	blocked_start_navigation.prepare_astar()
	expect(
		blocked_start_navigation.find_path(Vector2(16, 8), Vector2(80, 8)).is_empty(),
		"a blocked start is rejected instead of being snapped through a wall",
		failures,
	)
	var occupied_start_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		3, 1, Vector2i(32, 16), PackedInt64Array([1012, 0, 0])
	)
	occupied_start_navigation.prepare_astar()
	expect(
		occupied_start_navigation.find_path(Vector2(16, 8), Vector2(80, 8)).is_empty(),
		"generic A* does not open an unrelated scene-occupied start",
		failures,
	)
	expect(
		not occupied_start_navigation.find_path(Vector2(16, 8), Vector2(80, 8), true).is_empty(),
		"a unit can safely route out of an overlapping scene-occupancy start cell",
		failures,
	)
	var divided_layer := PackedInt64Array()
	divided_layer.resize(5 * 3)
	for divided_y in range(3):
		divided_layer[divided_y * 5 + 2] = 1
	var divided_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), divided_layer
	)
	divided_navigation.prepare_astar()
	var partial_path := divided_navigation.find_path(Vector2(16, 24), Vector2(144, 24))
	expect(
		not partial_path.is_empty() and divided_navigation.world_to_cell(partial_path[-1]).x < 2,
		"an unreachable destination resolves to the closest reachable side of its wall",
		failures,
	)

	var occupancy_layer := PackedInt64Array([0, 1012, 0])
	var occupancy_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		3, 1, Vector2i(32, 16), occupancy_layer
	)
	occupancy_navigation.prepare_astar()
	expect(
		occupancy_navigation.find_path(Vector2(16, 8), Vector2(80, 8)).is_empty(),
		"scene occupancy blocks navigation by default",
		failures,
	)
	occupancy_navigation.prepare_astar([12])
	expect(
		not occupancy_navigation.find_path(Vector2(16, 8), Vector2(80, 8)).is_empty(),
		"the moving scene can be excluded from its own occupancy cells",
		failures,
	)
	expect(
		(
			occupancy_navigation.source_cells_for_scene(NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID, 12)
			== [Vector2i(1, 0)]
		),
		"source scene occupancy can be indexed without mutating Layer 3",
		failures,
	)

	var sight_layer := PackedInt64Array()
	sight_layer.resize(5 * 3)
	sight_layer[1 * 5 + 2] = 1
	var sight_movement_layer := PackedInt64Array()
	sight_movement_layer.resize(5 * 3)
	var sight_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), sight_movement_layer, sight_layer
	)
	var sight_origin := sight_navigation.cell_to_world(Vector2i(0, 1))
	var sight_target := sight_navigation.cell_to_world(Vector2i(4, 1))
	expect(
		not sight_navigation.has_line_of_sight(sight_origin, sight_target),
		"Layer 2 obstacle blocks a Bresenham sight ray",
		failures,
	)
	var endpoint_sight_layer := PackedInt64Array()
	endpoint_sight_layer.resize(5 * 3)
	endpoint_sight_layer[1 * 5] = 1012
	endpoint_sight_layer[1 * 5 + 4] = 1013
	var endpoint_sight_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), sight_movement_layer, endpoint_sight_layer
	)
	expect(
		not endpoint_sight_navigation.has_line_of_sight(sight_origin, sight_target),
		"occupied sight endpoints block unless their scene IDs are explicit",
		failures,
	)
	expect(
		endpoint_sight_navigation.has_line_of_sight(sight_origin, sight_target, [12, 13]),
		"observer and target scene occupancy are exempted from the sight ray",
		failures,
	)
	endpoint_sight_layer[1 * 5] = 1
	var static_endpoint_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), sight_movement_layer, endpoint_sight_layer
	)
	expect(
		not static_endpoint_navigation.has_line_of_sight(sight_origin, sight_target, [12, 13]),
		"a static wall at a ray endpoint is never exempted as scene occupancy",
		failures,
	)
	endpoint_sight_layer[1 * 5] = 1012
	endpoint_sight_layer[1 * 5 + 2] = 1014
	var middle_occupancy_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), sight_movement_layer, endpoint_sight_layer
	)
	expect(
		not middle_occupancy_navigation.has_line_of_sight(sight_origin, sight_target, [12, 13]),
		"a third scene occupying the middle of the ray still blocks sight",
		failures,
	)
	expect(
		TACTICAL_SENSES.is_within_view_cone(
			Vector2.ZERO, Vector2.RIGHT, Vector2(100, 20), 200.0, 90.0
		),
		"enemy view cone accepts a target in front",
		failures,
	)
	expect(
		not TACTICAL_SENSES.is_within_view_cone(
			Vector2.ZERO, Vector2.RIGHT, Vector2(-20, 0), 200.0, 90.0
		),
		"enemy view cone rejects a target behind it",
		failures,
	)
	expect(
		not TACTICAL_SENSES.can_see(
			sight_navigation, sight_origin, Vector2.RIGHT, sight_target, 200.0, 120.0
		),
		"enemy sight combines view cone, distance, and Layer 2 ray casting",
		failures,
	)
	expect(
		not TACTICAL_SENSES.can_see(null, Vector2.ZERO, Vector2.RIGHT, Vector2(20, 0), 100.0, 90.0),
		"enemy sight fails closed when navigation data is missing",
		failures,
	)
	var combat_catalog: Dictionary = COMBAT_PROFILES.load_catalog()
	expect(
		COMBAT_PROFILES.is_valid_catalog(combat_catalog),
		"combat profile catalog validates",
		failures,
	)
	var rifle_profile := (combat_catalog["weapons"] as Dictionary)["rifle_attack"] as Dictionary
	var grenade_profile := (combat_catalog["weapons"] as Dictionary)["grenade_attack"] as Dictionary
	var enemy_sense := (combat_catalog["senses"] as Dictionary)["enemy_default"] as Dictionary
	var dog_sense := (combat_catalog["senses"] as Dictionary)["guard_dog_special"] as Dictionary
	expect(
		(
			int(COMBAT_PROFILES.weapon_profile_for_attack_type(2).get("attack_type", 0)) == 2
			and float(
				COMBAT_PROFILES.weapon_profile_for_attack_type(2).get("horizontal_range", 0.0)
			) == 700.0
		),
		"VWF default attack type resolves to its recovered weapon profile",
		failures,
	)
	var patrol_world_points: PackedVector2Array = ENEMY_UNIT_SCRIPT.patrol_world_points(
		[{"x": 61, "y": 14}, {"x": 62, "y": 14}]
	)
	expect(
		(
			patrol_world_points[0] == Vector2(1968, 232)
			and patrol_world_points[1] == Vector2(2000, 232)
		),
		"enemy patrol grid points convert to the original 32 by 16 cell centers",
		failures,
	)
	expect(
		ENEMY_UNIT_SCRIPT.next_unreached_patrol_index(
			PackedVector2Array([Vector2(32, 16), Vector2(32, 16)]),
			0,
			Vector2(32, 16),
		) == -1,
		"degenerate patrol routes at the actor position do not trigger an A-star request storm",
		failures,
	)
	expect(
		ENEMY_UNIT_SCRIPT.next_unreached_patrol_index(
			PackedVector2Array([Vector2(32, 16), Vector2(64, 16)]),
			0,
			Vector2(32, 16),
		) == 1,
		"patrol routing skips reached waypoints and selects the next distinct destination",
		failures,
	)
	var enemy_fixture = ENEMY_UNIT_SCRIPT.new()
	var empty_animation_groups: Array[Dictionary] = []
	enemy_fixture.configure_enemy(
		{
			"scene_index": 42,
			"display_name": "fixture enemy",
			"x": 64,
			"y": 32,
			"direction_index": 3,
			"current_hit_points": 16,
			"default_attack_type": 3,
			"patrol_waypoints": [],
		},
		null,
		empty_animation_groups,
		empty_animation_groups,
		null,
	)
	expect(
		(
			enemy_fixture.current_hit_points == 16
			and enemy_fixture.maximum_hit_points == 16
			and int(enemy_fixture.weapon_profile.get("attack_type", 0)) == 3
		),
		"enemy runtime consumes recovered hit points and default attack type",
		failures,
	)
	enemy_fixture.free()
	expect(
		(
			TACTICAL_SENSES.is_within_isometric_ellipse(
				Vector2.ZERO, Vector2(640, 0), 640.0, 320.0
			)
			and TACTICAL_SENSES.is_within_isometric_ellipse(
				Vector2.ZERO, Vector2(0, 320), 640.0, 320.0
			)
			and not TACTICAL_SENSES.is_within_isometric_ellipse(
				Vector2.ZERO, Vector2(0, 320.1), 640.0, 320.0
			)
		),
		"original sight and attack distance use the recovered isometric ellipse",
		failures,
	)
	expect(
		(
			int(parsed_entity["faction_id"]) == 1
			and int(parsed_entity["direction_index"]) == 7
			and int(parsed_entity["current_hit_points"]) == 8
			and int(parsed_entity["default_attack_type"]) == 2
			and not bool(parsed_entity["special_sensor_mode"])
			and int(parsed_entity["patrol_current_waypoint_index"]) == 1
			and int(parsed_entity["patrol_persistent_flag"]) == 1
		),
		"imported actor preserves faction, pose, combat, sensor, and patrol state fields",
		failures,
	)
	expect(
		(
			TACTICAL_SENSES.original_direction_center_degrees(1) == 45.0
			and TACTICAL_SENSES.original_direction_half_angle_degrees(1) == 30.0
			and TACTICAL_SENSES.original_direction_center_degrees(7) == 315.0
			and TACTICAL_SENSES.original_direction_half_angle_degrees(7) == 60.0
		),
		"all original direction indices use recovered projected scan geometry",
		failures,
	)
	expect(
		(
			TACTICAL_SENSES.original_visibility_band(
				Vector2.ZERO, Vector2(100, 100), 1, enemy_sense
			) == 1
			and TACTICAL_SENSES.original_visibility_band(
				Vector2.ZERO, Vector2(500, 0), 8, enemy_sense
			) == 2
			and TACTICAL_SENSES.original_visibility_band(
				Vector2.ZERO, Vector2(500, 0), 8, enemy_sense, true
			) == 0
		),
		"ordinary enemy vision preserves direction, near/far bands, and crawl concealment",
		failures,
	)
	expect(
		TACTICAL_SENSES.can_detect_original(
			null, Vector2.ZERO, Vector2(-100, 0), 0, dog_sense, true
		),
		"guard dog special sensing is short-range 360-degree and bypasses normal Layer 2 LOS",
		failures,
	)
	expect(
		(
			TACTICAL_SENSES.is_within_attack_range(Vector2.ZERO, Vector2(96, 0), 96.0, 384.0)
			and TACTICAL_SENSES.is_within_attack_range(Vector2.ZERO, Vector2(384, 0), 96.0, 384.0)
		),
		"attack range includes its exact minimum and maximum boundaries",
		failures,
	)
	expect(
		(
			not TACTICAL_SENSES.is_within_attack_range(Vector2.ZERO, Vector2(95.9, 0), 96.0, 384.0)
			and not TACTICAL_SENSES.is_within_attack_range(
				Vector2.ZERO, Vector2(384.1, 0), 96.0, 384.0
			)
		),
		"attack range rejects points just outside either boundary",
		failures,
	)
	expect(
		not TACTICAL_SENSES.can_attack(sight_navigation, sight_origin, sight_target, rifle_profile),
		"ranged attack is rejected when Layer 2 blocks the shot",
		failures,
	)
	expect(
		not TACTICAL_SENSES.can_attack(null, Vector2.ZERO, Vector2(20, 0), rifle_profile),
		"line-of-sight attacks fail closed without navigation data",
		failures,
	)
	expect(
		not TACTICAL_SENSES.can_attack(sight_navigation, sight_origin, sight_target, grenade_profile),
		"the original grenade attack is also blocked by Layer 2",
		failures,
	)
	expect(
		(
			TACTICAL_SENSES.is_within_original_attack_range(
				Vector2.ZERO, Vector2(700, 0), rifle_profile
			)
			and TACTICAL_SENSES.is_within_original_attack_range(
				Vector2.ZERO, Vector2(0, 350), rifle_profile
			)
			and not TACTICAL_SENSES.is_within_original_attack_range(
				Vector2.ZERO, Vector2(0, 350.1), rifle_profile
			)
		),
		"rifle range uses the recovered 700 by 350 isometric ellipse",
		failures,
	)

	var path_unit = SQUAD_UNIT_SCRIPT.new()
	path_unit.configure("测试队员", Color.WHITE, Vector2.ZERO)
	path_unit.issue_path(PackedVector2Array([Vector2(10, 0), Vector2(10, 10)]))
	path_unit._physics_process(0.1)
	expect(
		path_unit.position.is_equal_approx(Vector2(10, 5)),
		"path following carries remaining movement across waypoints without a pause",
		failures,
	)
	expect(
		path_unit.target_position.is_equal_approx(Vector2(10, 10)),
		"path following preserves the final command target",
		failures,
	)
	path_unit.free()
	expect(
		is_equal_approx(
			SQUAD_UNIT_SCRIPT.animation_frame_seconds({"frame_hold_ticks": 3}),
			0.255,
		),
		"SPR animation holds each frame for parameters[2] + 1 base ticks",
		failures,
	)
	expect(
		is_equal_approx(SQUAD_UNIT_SCRIPT.animation_frame_seconds({}), 0.085),
		"legacy animation groups default to one base sprite tick",
		failures,
	)

	var dynamic_movement := PackedInt64Array()
	dynamic_movement.resize(5 * 3)
	dynamic_movement[1 * 5] = 1001
	dynamic_movement[1 * 5 + 2] = 1002
	dynamic_movement[1 * 5 + 4] = 1
	dynamic_movement[3] = 1010
	var dynamic_sight := PackedInt64Array()
	dynamic_sight.resize(5 * 3)
	dynamic_sight[1 * 5] = 1001
	dynamic_sight[1 * 5 + 2] = 1002
	var dynamic_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), dynamic_movement, dynamic_sight
	)
	var source_before := (
		(dynamic_navigation.layers[NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID] as PackedInt64Array)
		. duplicate()
	)
	var dynamic_grid: RefCounted = DYNAMIC_OCCUPANCY_GRID.new()
	dynamic_grid.configure(dynamic_navigation)
	expect(
		(
			dynamic_grid.register_scene(1, dynamic_navigation.cell_to_world(Vector2i(0, 1)))
			and dynamic_grid.register_scene(2, dynamic_navigation.cell_to_world(Vector2i(2, 1)))
		),
		"only explicitly movable scenes are registered in the dynamic overlay",
		failures,
	)
	dynamic_grid.finalize_registration()
	expect(
		(
			dynamic_grid.runtime_movement_owner(Vector2i(0, 1)) == 1
			and dynamic_grid.runtime_movement_owner(Vector2i(2, 1)) == 2
		),
		"registered scenes preserve their initial effective occupancy",
		failures,
	)
	expect(
		(
			not dynamic_grid.try_relocate(1, dynamic_navigation.cell_to_world(Vector2i(2, 1)))
			and dynamic_grid.runtime_movement_owner(Vector2i(0, 1)) == 1
		),
		"relocation into another actor fails atomically",
		failures,
	)
	expect(
		(
			dynamic_grid.try_relocate(1, dynamic_navigation.cell_to_world(Vector2i(1, 1)))
			and dynamic_grid.runtime_movement_owner(Vector2i(0, 1)) == -1
			and dynamic_grid.runtime_movement_owner(Vector2i(1, 1)) == 1
		),
		"relocation removes only the actor's old overlay and installs its new one",
		failures,
	)
	expect(
		(
			not dynamic_grid.try_relocate(1, dynamic_navigation.cell_to_world(Vector2i(4, 1)))
			and dynamic_grid.runtime_movement_owner(Vector2i(1, 1)) == 1
		),
		"a large relocation cannot tunnel through or enter a static Layer 3 wall",
		failures,
	)
	expect(
		not dynamic_grid.try_relocate(1, dynamic_navigation.cell_to_world(Vector2i(3, 0))),
		"an unregistered scene reference remains a blocking world object",
		failures,
	)
	expect(
		(
			dynamic_grid.try_relocate(2, dynamic_navigation.cell_to_world(Vector2i(3, 1)))
			and dynamic_grid.runtime_movement_owner(Vector2i(2, 1)) == -1
			and dynamic_grid.runtime_movement_owner(Vector2i(3, 1)) == 2
		),
		"moving a scene leaves no dynamic ghost at its baked origin",
		failures,
	)
	expect(
		(
			(dynamic_navigation.layers[NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID] as PackedInt64Array)
			== source_before
		),
		"dynamic relocation never mutates the imported Layer 3 snapshot",
		failures,
	)
	expect(
		dynamic_grid.register_scene(3, dynamic_navigation.cell_to_world(Vector2i(2, 1))),
		"a newly movable scene can join the overlay",
		failures,
	)
	dynamic_grid.finalize_registration()
	expect(
		not (
			dynamic_grid
			. has_line_of_sight(
				dynamic_navigation.cell_to_world(Vector2i(1, 1)),
				dynamic_navigation.cell_to_world(Vector2i(3, 1)),
				[1, 2],
			)
		),
		"a third dynamic actor blocks the current-frame Layer 2 ray",
		failures,
	)
	dynamic_grid.unregister_scene(3)
	expect(
		(
			dynamic_grid
			. has_line_of_sight(
				dynamic_navigation.cell_to_world(Vector2i(1, 1)),
				dynamic_navigation.cell_to_world(Vector2i(3, 1)),
				[1, 2],
			)
		),
		"removing a dynamic actor clears its current sight occupancy without a ghost",
		failures,
	)

	var crossing_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		2, 2, Vector2i(32, 16), PackedInt64Array([0, 0, 0, 0])
	)
	var crossing_grid: RefCounted = DYNAMIC_OCCUPANCY_GRID.new()
	crossing_grid.configure(crossing_navigation)
	crossing_grid.register_scene(10, crossing_navigation.cell_to_world(Vector2i(0, 0)))
	crossing_grid.register_scene(11, crossing_navigation.cell_to_world(Vector2i(1, 0)))
	crossing_grid.finalize_registration()
	var crossing_first: bool = crossing_grid.try_relocate(
		10, crossing_navigation.cell_to_world(Vector2i(1, 1))
	)
	var crossing_second: bool = crossing_grid.try_relocate(
		11, crossing_navigation.cell_to_world(Vector2i(0, 1))
	)
	expect(
		not (crossing_first and crossing_second),
		"same-tick diagonal X crossing never lets both actors pass through each other",
		failures,
	)
	expect(
		not crossing_first and not crossing_second,
		"a diagonal move is rejected when either current-frame side cell has a dynamic actor",
		failures,
	)
	var reserved_path: PackedVector2Array = crossing_grid.find_path_for_scene(
		10,
		crossing_navigation.cell_to_world(Vector2i(0, 0)),
		crossing_navigation.cell_to_world(Vector2i(0, 1)),
	)
	expect(
		not reserved_path.is_empty() and not crossing_grid.goal_owners.is_empty(),
		"a planned actor path reserves its complete destination footprint",
		failures,
	)
	crossing_grid.release_goal(10)
	expect(
		crossing_grid.goal_owners.is_empty(),
		"cancelled movement releases stale destination reservations",
		failures,
	)

	var footprint_values := PackedInt64Array(
		[
			1020, 0, 0, 0, 0,
			1020, 0, 1, 0, 0,
			0, 0, 0, 0, 0,
		]
	)
	var footprint_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), footprint_values
	)
	var footprint_grid: RefCounted = DYNAMIC_OCCUPANCY_GRID.new()
	footprint_grid.configure(footprint_navigation)
	footprint_grid.register_scene(20, footprint_navigation.cell_to_world(Vector2i(0, 0)))
	footprint_grid.finalize_registration()
	var footprint_path: PackedVector2Array = footprint_grid.find_path_for_scene(
		20,
		footprint_navigation.cell_to_world(Vector2i(0, 0)),
		footprint_navigation.cell_to_world(Vector2i(4, 0)),
	)
	var footprint_path_is_clear := not footprint_path.is_empty()
	for waypoint: Vector2 in footprint_path:
		var anchor := footprint_navigation.world_to_cell(waypoint)
		if anchor.x >= 2:
			footprint_path_is_clear = false
	expect(
		footprint_path_is_clear,
		"multi-cell actor A* applies its full footprint and stops before a narrow blocked column",
		failures,
	)

	var reference_navigation: NavigationGridData = NAVIGATION_GRID_DATA.create_for_tests(
		3, 1, Vector2i(32, 16), PackedInt64Array([1030, 0, 1030])
	)
	var reference_grid: RefCounted = DYNAMIC_OCCUPANCY_GRID.new()
	reference_grid.configure(reference_navigation)
	reference_grid.register_scene(
		30,
		reference_navigation.cell_to_world(Vector2i(0, 0)),
		reference_navigation.cell_to_world(Vector2i(2, 0)),
	)
	reference_grid.finalize_registration()
	expect(
		(
			reference_grid.runtime_movement_owner(Vector2i(0, 0)) == 30
			and reference_grid.runtime_movement_owner(Vector2i(2, 0)) == -1
			and (
				(reference_grid.actors[30] as Dictionary)["movement_offsets"]
				as Array[Vector2i]
			) == [Vector2i.ZERO]
		),
		"serialized reference coordinates select one connected footprint and ignore separated historical scene references",
		failures,
	)

	var mission_catalog: Dictionary = MISSION_DATA.load_catalog()
	expect(
		int(mission_catalog.get("mission_count", 0)) == 12,
		"mission catalog contains all twelve formal missions",
		failures
	)
	var bridge_mission: Dictionary = MISSION_DATA.load_mission("m003")
	expect(str(bridge_mission.get("title", "")) == "铁路桥", "m003 title is recovered", failures)
	var bridge_state = MISSION_STATE.new(bridge_mission)
	bridge_state.record_event("trigger_activated", {"display_name": "检测出口精灵", "scene_index": 1235})
	expect(
		int(bridge_state.progress["evacuate_by_truck"]) == 0,
		"mission dependencies reject an early evacuation trigger",
		failures
	)
	for scene_index in range(1230, 1235):
		bridge_state.record_event(
			"trigger_activated", {"display_name": "检测爆炸精灵", "scene_index": scene_index}
		)
	bridge_state.record_event("trigger_activated", {"display_name": "检测爆炸精灵", "scene_index": 1230})
	expect(
		int(bridge_state.progress["place_bridge_charges"]) == 5,
		"task graph de-duplicates the five bridge charge anchors",
		failures
	)
	bridge_state.record_event("trigger_activated", {"display_name": "检测出口精灵", "scene_index": 1235})
	expect(bridge_state.is_victory(), "bridge task graph reaches victory", failures)

	var mine_state = MISSION_STATE.new(MISSION_DATA.load_mission("m008"))
	mine_state.record_event("explosion")
	expect(mine_state.is_failed(), "mine mission rejects a premature explosion", failures)
	var port_state = MISSION_STATE.new(MISSION_DATA.load_mission("m010"))
	port_state.advance_time(3600.0)
	expect(
		port_state.failure_id == "time_limit", "port mission enforces its one-hour limit", failures
	)

	expect(
		SQUAD_UNIT_SCRIPT.direction_group_index(Vector2.DOWN) == 7,
		"southward movement uses legacy direction group 7",
		failures
	)
	expect(
		SQUAD_UNIT_SCRIPT.direction_group_index(Vector2.LEFT) == 1,
		"westward movement uses legacy direction group 1",
		failures
	)
	expect(
		SQUAD_UNIT_SCRIPT.direction_group_index(Vector2.UP) == 3,
		"northward movement uses legacy direction group 3",
		failures
	)
	expect(
		SQUAD_UNIT_SCRIPT.direction_group_index(Vector2.RIGHT) == 5,
		"eastward movement uses legacy direction group 5",
		failures
	)
	var direction_mapping_round_trips := true
	for original_direction in range(1, 9):
		var legacy_group: int = (
			IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(original_direction)
		)
		if (
			IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(legacy_group)
			!= original_direction
		):
			direction_mapping_round_trips = false
	expect(
		(
			direction_mapping_round_trips
			and IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(
				SQUAD_UNIT_SCRIPT.direction_group_index(Vector2.RIGHT)
			) == 3
		),
		"enemy vision converts every reordered animation group back to its original VWF direction",
		failures,
	)

	var main = MAIN_SCENE.instantiate()
	main.create_interface()
	main.spawn_squad()
	expect(main.units.size() == 5, "prototype creates five squad members", failures)
	expect(main.selected_units.size() == 1, "prototype selects one member initially", failures)
	main.clear_selection()
	for unit in main.units:
		main.handle_selection(unit.position, true)
	expect(main.selected_units.size() == 5, "additive selection reaches all members", failures)
	main.issue_formation_move(Vector2.ZERO)
	var issued_targets: Dictionary = {}
	for unit in main.selected_units:
		issued_targets[unit.target_position] = true
		expect(
			point_is_inside(unit.target_position, bounds),
			"issued target remains inside bounds",
			failures
		)
	expect(issued_targets.size() == 5, "issued corner targets stay unique", failures)
	main.spawn_squad()
	expect(main.units.size() == 5, "reset restores five squad members", failures)
	expect(main.selected_units.size() == 1, "reset restores initial selection", failures)
	main.free()

	if failures.is_empty():
		print("Godot logic tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(value: bool, description: String, failures: Array[String]) -> void:
	check_count += 1
	if not value:
		failures.append(description)


func point_is_inside(point: Vector2, bounds: Rect2) -> bool:
	return (
		point.x >= bounds.position.x
		and point.y >= bounds.position.y
		and point.x <= bounds.end.x
		and point.y <= bounds.end.y
	)


func path_is_clear(
	navigation: NavigationGridData,
	world_start: Vector2,
	path: PackedVector2Array,
) -> bool:
	var segment_start := world_start
	for segment_end: Vector2 in path:
		var steps := maxi(ceili(segment_start.distance_to(segment_end) / 4.0), 1)
		for step in range(steps + 1):
			var sample := segment_start.lerp(segment_end, float(step) / float(steps))
			if navigation.is_movement_blocked(navigation.world_to_cell(sample)):
				return false
		segment_start = segment_end
	return true
