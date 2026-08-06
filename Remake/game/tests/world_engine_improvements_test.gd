extends SceneTree

const WORLD_AUDIO_SPATIALIZER: Script = preload(
	"res://scripts/world_audio_spatializer.gd"
)
const SMOOTH_CAMERA_PAN: Script = preload(
	"res://scripts/smooth_camera_pan.gd"
)
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const LEGACY_BURIAL_CACHE: Script = preload(
	"res://scripts/legacy_burial_cache.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const NAVIGATION_GRID_DATA: Script = preload(
	"res://scripts/navigation_grid_data.gd"
)
const DYNAMIC_OCCUPANCY_GRID: Script = preload(
	"res://scripts/dynamic_occupancy_grid.gd"
)
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const FIELD_PICKUP: Script = preload("res://scripts/field_pickup.gd")
const WORLD_INTERACTION_RESOLVER: Script = preload(
	"res://scripts/world_interaction_resolver.gd"
)
const MOVEMENT_RECOVERY_PLANNER: Script = preload(
	"res://scripts/movement_recovery_planner.gd"
)
const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const MEDIA_DIRECTOR: Script = preload("res://scripts/media_director.gd")

var failures: Array[String] = []
var checks := 0


class AlwaysVisibleNavigation extends RefCounted:
	func has_line_of_sight(
		_unused_origin: Vector2,
		_unused_target: Vector2,
		_unused_ignored: Array = [],
	) -> bool:
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_world_audio_attenuation()
	_test_smooth_viewport_local_camera_pan()
	_test_physics_render_interpolation()
	_test_row_sliced_actor_has_no_fallback_artifact()
	_test_inventory_drop_interaction()
	_test_pickup_priority_and_pointer_padding()
	_test_inventory_drops_reset_with_level()
	_test_burial_cache_does_not_mask_loose_drops()
	_test_modern_player_accuracy_and_lethal_melee()
	_test_coordinate_force_fire()
	_test_enemy_chase_locomotion_and_replan_policy()
	_test_enemy_gaze_and_visibility_bands()
	_test_enemy_returns_to_duty()
	_test_sight_observation_persists_after_selection()
	_test_patrol_formation_separation()
	_test_modern_patrol_leadership()
	_test_patrol_speed_round_trip()
	_test_readable_movement_animation_cadence()
	_test_component_movement_carries_waypoint_time()
	_test_single_pass_vision_clipping()
	_test_bounded_movement_recovery_route()
	_test_subtitle_safe_area()
	_test_world_weapon_drop_art_catalog()
	_test_compact_biped_navigation_footprints()
	if failures.is_empty():
		print("World engine improvement tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_world_audio_attenuation() -> void:
	var view := Rect2(0.0, 0.0, 1000.0, 600.0)
	var near_mix: Dictionary = WORLD_AUDIO_SPATIALIZER.mix_for_source(
		view.get_center(), view
	)
	var edge_mix: Dictionary = WORLD_AUDIO_SPATIALIZER.mix_for_source(
		Vector2(990.0, 300.0), view
	)
	var culled_mix: Dictionary = WORLD_AUDIO_SPATIALIZER.mix_for_source(
		Vector2(1400.0, 300.0), view
	)
	_expect(
		bool(near_mix.get("audible", false))
			and is_zero_approx(float(near_mix.get("volume_db", -80.0))),
		"nearby footsteps retain the authored recording level",
	)
	_expect(
		bool(edge_mix.get("audible", false))
			and float(edge_mix.get("volume_db", 0.0)) < -1.0
			and float(edge_mix.get("volume_db", -80.0)) > -80.0,
		"footsteps attenuate smoothly with camera distance",
	)
	_expect(
		not bool(culled_mix.get("audible", true))
			and float(culled_mix.get("volume_db", 0.0)) <= -80.0,
		"far-offscreen footsteps consume no mixer voice",
	)


func _test_smooth_viewport_local_camera_pan() -> void:
	var viewport := Vector2(1280.0, 720.0)
	_expect(
		SMOOTH_CAMERA_PAN.edge_intent(viewport * 0.5, viewport).is_zero_approx(),
		"the camera remains still away from viewport edges",
	)
	var left: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(Vector2(0.0, 360.0), viewport)
	var partial: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(Vector2(16.0, 360.0), viewport)
	var outside: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(Vector2(-1.0, 360.0), viewport)
	_expect(
		left.x < -0.99 and partial.x < 0.0 and absf(partial.x) < absf(left.x),
		"edge intent ramps continuously instead of switching camera speed abruptly",
	)
	_expect(
		outside.is_zero_approx(),
		"a pointer outside an unfocused/windowed viewport never scrolls the camera",
	)
	var diagonal: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(Vector2.ZERO, viewport)
	_expect(
		diagonal.length() <= 1.00001,
		"diagonal edge scrolling is normalized",
	)
	var vertical_outer: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(
		Vector2(640.0, 0.0),
		viewport,
		32.0,
		48.0,
	)
	var vertical_mid: Vector2 = SMOOTH_CAMERA_PAN.edge_intent(
		Vector2(640.0, 24.0),
		viewport,
		32.0,
		48.0,
	)
	_expect(
		vertical_outer.y < -0.99
			and vertical_mid.y < 0.0
			and absf(vertical_mid.y) < absf(vertical_outer.y),
		"vertical scrolling uses the same smooth curve over a wider controllable band",
	)
	var velocity: Vector2 = SMOOTH_CAMERA_PAN.advance_velocity(
		Vector2.ZERO, Vector2(600.0, 0.0), 1.0 / 60.0
	)
	var slowing: Vector2 = SMOOTH_CAMERA_PAN.advance_velocity(
		velocity, Vector2.ZERO, 1.0 / 60.0
	)
	_expect(
		velocity.x > 0.0 and velocity.x < 600.0
			and slowing.x >= 0.0 and slowing.x < velocity.x,
		"camera velocity accelerates and decelerates without pointer warping",
	)
	var horizontal_tail: Vector2 = SMOOTH_CAMERA_PAN.retain_edge_intent(
		Vector2.RIGHT,
		0.04,
		0.10,
	)
	var vertical_tail: Vector2 = SMOOTH_CAMERA_PAN.retain_edge_intent(
		Vector2.DOWN,
		0.04,
		0.10,
	)
	_expect(
		horizontal_tail.x > 0.0
			and vertical_tail.y > 0.0
			and is_equal_approx(horizontal_tail.x, vertical_tail.y)
			and SMOOTH_CAMERA_PAN.retain_edge_intent(
				Vector2.DOWN,
				0.10,
				0.10,
			).is_zero_approx(),
		"horizontal and vertical edge loss use the same short eased release tail",
	)


func _test_physics_render_interpolation() -> void:
	_expect(
		bool(ProjectSettings.get_setting(
			"physics/common/physics_interpolation",
			false,
		)),
		"physics-driven actors are interpolated between fixed 60 Hz simulation ticks",
	)
	_expect(
		not bool(ProjectSettings.get_setting(
			"application/boot_splash/show_image",
			true,
		)),
		"the executable starts without an engine or legacy logo splash",
	)


func _test_row_sliced_actor_has_no_fallback_artifact() -> void:
	var unit = SQUAD_UNIT.new()
	unit.sprite_texture = null
	unit.sprite_drawn_by_row_slices = true
	_expect(
		not unit.uses_fallback_silhouette(),
		"a row-sliced imported actor never receives the missing-art i-shaped overlay",
	)
	unit.sprite_drawn_by_row_slices = false
	_expect(
		unit.uses_fallback_silhouette(),
		"a genuinely missing actor texture still has a readable fallback silhouette",
	)
	unit.free()


func _test_inventory_drop_interaction() -> void:
	var pickup = MISSION_PICKUP.new()
	pickup.configure(
		{
			"original_inventory_kind": "weapon",
			"item_id": 7,
			"quantity": 12,
		},
		Vector2(80.0, 24.0),
	)
	var collector := Node2D.new()
	collector.position = Vector2(48.0, 8.0)
	_expect(
		pickup.contains_parent_point(pickup.position)
			and pickup.can_collect(collector),
		"enemy inventory drops expose click and one-cell collection targets",
	)
	var payload: Dictionary = pickup.collect(collector)
	_expect(
		int(payload.get("item_id", 0)) == 7
			and pickup.collected
			and not pickup.visible
			and pickup.collect(collector).is_empty(),
		"a collected drop disappears and can contribute its quantity only once",
	)
	pickup.free()
	collector.free()


func _test_pickup_priority_and_pointer_padding() -> void:
	var main = MAIN_SCRIPT.new()
	var click_point := Vector2(128.0, 64.0)
	var loose = MISSION_PICKUP.new()
	loose.configure(
		{"original_inventory_kind": "weapon", "item_id": 37, "quantity": 5},
		click_point + Vector2(20.0, 0.0),
	)
	main.add_child(loose)
	main.mission_pickups.append(loose)
	var field = FIELD_PICKUP.new()
	field.configure(
		{
			"behavior": "field_pickup",
			"database_entry_id": 1,
			"interaction_radius": 48.0,
			"grant": {"kind": "healing", "amount": 1},
		},
		{"x": click_point.x, "y": click_point.y, "scene_index": 91},
	)
	main.add_child(field)
	main.field_pickups.append(field)
	var resolved := main.call("_preferred_pickup_at_world_point", click_point) as Dictionary
	_expect(
		loose.contains_parent_point(click_point)
			and str(resolved.get("kind", "")) == "loose_inventory"
			and resolved.get("node") == loose,
		"padded pointer targets keep small drops easy to click and loose inventory wins overlaps",
	)
	var nearer = MISSION_PICKUP.new()
	nearer.configure(
		{"original_inventory_kind": "backpack", "item_id": 83, "quantity": 1},
		click_point + Vector2(4.0, 0.0),
	)
	main.add_child(nearer)
	main.mission_pickups.append(nearer)
	_expect(
		main.mission_inventory_pickup_at_world_point(click_point) == nearer,
		"overlapping loose drops resolve to the nearest pointer target deterministically",
	)
	main.free()


func _test_inventory_drops_reset_with_level() -> void:
	var main = MAIN_SCRIPT.new()
	var pickup = MISSION_PICKUP.new()
	pickup.configure(
		{"original_inventory_kind": "backpack", "item_id": 9, "quantity": 1},
		Vector2(16.0, 8.0),
	)
	main.add_child(pickup)
	main.mission_pickups.append(pickup)
	_expect(
		int(main.call("_clear_runtime_mission_pickups")) == 1
			and main.mission_pickups.is_empty()
			and not is_instance_valid(pickup),
		"restarting a level destroys every uncollected runtime drop",
	)
	main.free()


func _test_burial_cache_does_not_mask_loose_drops() -> void:
	var main = MAIN_SCRIPT.new()
	var world_position := Vector2(96.0, 48.0)
	var cache = LEGACY_BURIAL_CACHE.new()
	cache.configure(world_position, 77, {}, {})
	main.add_child(cache)
	main.legacy_burial_caches.append(cache)
	var pickup = MISSION_PICKUP.new()
	pickup.configure(
		{
			"original_inventory_kind": "weapon",
			"item_id": 37,
			"quantity": 5,
		},
		world_position,
	)
	main.add_child(pickup)
	main.mission_pickups.append(pickup)
	_expect(
		main.mission_inventory_pickup_at_world_point(world_position) == pickup
			and not bool(main.call(
				"_try_interact_burial_cache_at",
				world_position,
			)),
		"an empty burial cache cannot intercept loose inventory dropped at the corpse position",
	)
	main.free()


func _test_modern_player_accuracy_and_lethal_melee() -> void:
	_expect(
		is_equal_approx(SQUAD_UNIT.player_hit_chance_for_attack_type(1), 0.80)
			and is_equal_approx(
				SQUAD_UNIT.player_hit_chance_for_attack_type(2),
				0.90,
			)
			and is_equal_approx(
				SQUAD_UNIT.player_hit_chance_for_attack_type(4),
				1.0,
			),
		"player pistol, rifle and melee accuracy is fixed at 80%, 90% and 100%",
	)
	var attacker = SQUAD_UNIT.new()
	var target = SQUAD_UNIT.new()
	root.add_child(attacker)
	root.add_child(target)
	attacker.scene_index = 11
	attacker.faction_id = 3
	attacker.runtime_actor_type = 4
	attacker.position = Vector2.ZERO
	attacker.dynamic_occupancy = AlwaysVisibleNavigation.new()
	attacker.weapon_profile = {
		"attack_type": 4,
		"horizontal_range": 32.0,
		"vertical_range": 16.0,
		"requires_line_of_sight": true,
		"damage": 1,
		"direct_actor_hit_count": 1,
		"ammo_per_attack": 1,
		"alert_radius": 0.0,
	}
	attacker.infinite_ammo = true
	attacker.modern_player_combat_rules_enabled = true
	target.scene_index = 12
	target.faction_id = 1
	target.runtime_actor_type = 4
	target.maximum_hit_points = 12
	target.current_hit_points = 12
	target.position = Vector2(24.0, 8.0)
	_expect(
		target.is_inside_tree() and target.is_combat_alive(),
		"the melee fixture target is live in the test scene tree",
	)
	_expect(
		SQUAD_UNIT.factions_are_hostile(attacker.faction_id, target.faction_id),
		"the melee fixture uses hostile player/enemy factions",
	)
	_expect(
		attacker.can_attack_target(target),
		"the melee fixture is visible and inside its authored range",
	)
	var attack_started: bool = attacker.try_start_attack(target)
	_expect(
		attack_started and attacker.player_attack_attempt_serial == 1,
		"a player melee attack starts inside the authored range and records one accuracy attempt",
	)
	_expect(
		not target.is_alive and target.current_hit_points == 0,
		"a player melee attack committed inside the authored range always kills at its hit frame",
	)
	attacker.free()
	target.free()


func _test_coordinate_force_fire() -> void:
	var attacker = SQUAD_UNIT.new()
	root.add_child(attacker)
	attacker.scene_index = 21
	attacker.faction_id = 3
	attacker.is_alive = true
	attacker.infinite_ammo = true
	attacker.weapon_profile = {
		"attack_type": 1,
		"damage": 1,
		"ammo_per_attack": 1,
		"alert_radius": 640.0,
	}
	var starts: Array[Vector2] = []
	var projectiles: Array[Vector2] = []
	attacker.coordinate_attack_started.connect(
		func(_actor: Node2D, point: Vector2, _type: int, _radius: float) -> void:
			starts.append(point)
	)
	attacker.coordinate_projectile_requested.connect(
		func(_actor: Node2D, point: Vector2, _profile: Dictionary) -> void:
			projectiles.append(point)
	)
	var target_point := Vector2(320.0, 96.0)
	_expect(
		attacker.issue_force_attack_at(target_point)
			and starts == [target_point]
			and projectiles == [target_point],
		"Ctrl force-fire commits a real coordinate projectile without requiring an actor target",
	)
	attacker.free()


func _movement_groups(step: Vector2) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for unused_index: int in range(8):
		var frames: Array[Texture2D] = []
		groups.append({
			"secondary_triplet": [int(step.x), 1, int(step.y)],
			"frame_hold_ticks": 1,
			"frames": frames,
		})
	return groups


func _test_enemy_chase_locomotion_and_replan_policy() -> void:
	var enemy = ENEMY_UNIT.new()
	enemy.is_alive = true
	enemy.has_authored_run_animation = true
	enemy.locomotion_can_move = true
	var empty_crawl_groups: Array[Dictionary] = []
	enemy.configure_movement_modes(
		_movement_groups(Vector2(2.0, 1.0)),
		_movement_groups(Vector2(2.0, 1.0)),
		empty_crawl_groups,
	)
	enemy.call("_set_enemy_pursuit_locomotion", true)
	_expect(
		enemy.is_running and enemy.move_speed > SQUAD_UNIT.WALK_SPEED * 2.5,
		"a chasing enemy switches to its authored run cycle and matching run speed",
	)
	enemy.call("_set_enemy_pursuit_locomotion", false)
	_expect(
		not enemy.is_running and is_equal_approx(enemy.move_speed, SQUAD_UNIT.WALK_SPEED),
		"attack/search/patrol transitions restore synchronized walking locomotion",
	)
	_expect(
		not MOVEMENT_RECOVERY_PLANNER.chase_replan_required(
			Vector2(100.0, 100.0),
			Vector2(110.0, 100.0),
			true,
			28.0,
		)
			and MOVEMENT_RECOVERY_PLANNER.chase_replan_required(
				Vector2(100.0, 100.0),
				Vector2(140.0, 100.0),
				true,
				28.0,
			),
		"moving-target chase paths are coalesced until the target meaningfully changes cell",
	)
	enemy.free()


func _test_enemy_gaze_and_visibility_bands() -> void:
	var profile := {
		"horizontal_radius": 100.0,
		"vertical_radius": 50.0,
		"near_band_ratio": 0.5,
		"crawling_hidden_in_far_band": true,
		"requires_line_of_sight": false,
	}
	_expect(
		TACTICAL_SENSES.original_visibility_band_heading(
			Vector2.ZERO, Vector2(80.0, 0.0), 0.0, 45.0, profile, false
		) == 2
			and TACTICAL_SENSES.original_visibility_band_heading(
				Vector2.ZERO, Vector2(80.0, 0.0), 0.0, 45.0, profile, true
			) == 0
			and TACTICAL_SENSES.original_visibility_band_heading(
				Vector2.ZERO, Vector2(30.0, 0.0), 0.0, 45.0, profile, true
			) == 1,
		"far green sight hides prone units while the near red band detects both postures",
	)
	var enemy = ENEMY_UNIT.new()
	enemy.mission_ai_coordinator = Node.new()
	enemy.original_direction_index = 3
	enemy.sense_profile = profile
	enemy.behavior_state = ENEMY_UNIT.BehaviorState.PATROL
	enemy.gaze_heading_bucket = -1
	enemy.gaze_sweep_elapsed = 0.0
	enemy.call("_advance_gaze_heading", 1.125)
	_expect(
		enemy.gaze_heading_degrees >= 15.0 and enemy.gaze_heading_degrees <= 21.0,
		"patrolling sight sweeps around the actor's current authored facing",
	)
	var target = SQUAD_UNIT.new()
	root.add_child(target)
	target.position = Vector2(0.0, 40.0)
	target.is_alive = true
	enemy.current_target = target
	enemy.behavior_state = ENEMY_UNIT.BehaviorState.CHASE
	enemy.call("_advance_gaze_heading", 0.1)
	_expect(
		absf(enemy.gaze_heading_degrees - 90.0) <= 3.0,
		"chase sight tracks the live target heading instead of a stale direction index",
	)
	target.free()
	enemy.mission_ai_coordinator.free()
	enemy.free()


func _test_enemy_returns_to_duty() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(35)
	sight.resize(35)
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		7, 5, Vector2i(32, 16), movement, sight
	)
	navigation.prepare_astar()
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	occupancy.register_scene(31, Vector2(16.0, 8.0))
	occupancy.finalize_registration()
	var enemy = ENEMY_UNIT.new()
	enemy.scene_index = 31
	enemy.position = Vector2(16.0, 8.0)
	enemy.is_alive = true
	enemy.locomotion_can_move = true
	enemy.dynamic_occupancy = occupancy
	enemy.mission_ai_coordinator = Node.new()
	enemy.patrol_waypoints = PackedVector2Array([Vector2(176.0, 40.0)])
	enemy.patrol_index = 0
	enemy.call("_capture_duty_snapshot")
	enemy.call("_begin_return_to_duty")
	_expect(
		enemy.behavior_state == ENEMY_UNIT.BehaviorState.RETURN_TO_DUTY
			and enemy.movement_path_index < enemy.movement_path.size(),
		"an expired modern search first routes the guard back to its recorded duty waypoint",
	)
	enemy.position = enemy.return_to_duty_destination
	enemy.movement_path_index = enemy.movement_path.size()
	enemy.call("_update_return_to_duty", 0.1)
	_expect(
		enemy.behavior_state == ENEMY_UNIT.BehaviorState.PATROL
			and not enemy.duty_snapshot_active,
		"a guard resumes its authored patrol only after completing return-to-duty",
	)
	enemy.mission_ai_coordinator.free()
	enemy.free()


func _test_sight_observation_persists_after_selection() -> void:
	var main = MAIN_SCRIPT.new()
	var enemy = ENEMY_UNIT.new()
	enemy.is_alive = true
	enemy.faction_id = 1
	main.add_child(enemy)
	main.call("_set_sight_observation_target", enemy)
	main.clear_selection()
	_expect(
		main.sight_observation_target == enemy
			and main.sight_observation_remaining > 0.0
			and enemy.tactical_ranges_visible,
		"selecting a squad member no longer instantly cancels an S-observed enemy",
	)
	main.call("_advance_sight_observation", 9.0)
	_expect(
		main.sight_observation_target == null and not enemy.tactical_ranges_visible,
		"S observation expires automatically after a useful bounded interval",
	)
	main.free()


func _test_patrol_formation_separation() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(15)
	sight.resize(15)
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		5, 3, Vector2i(32, 16), movement, sight
	)
	navigation.prepare_astar()
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	occupancy.register_scene(1, Vector2(16.0, 8.0))
	occupancy.register_scene(2, Vector2(48.0, 8.0))
	occupancy.register_scene(3, Vector2(16.0, 24.0))
	occupancy.register_scene(4, Vector2(48.0, 24.0))
	occupancy.finalize_registration()
	_expect(
		not occupancy.try_relocate(1, Vector2(24.0, 8.0), true, 28.0)
			and occupancy.try_relocate(1, Vector2(8.0, 8.0), true, 28.0),
		"soft patrol movement rejects overlap but still permits actors to separate",
	)
	_expect(
		not occupancy.try_relocate_from_runtime_evidence(
			3, Vector2(24.0, 24.0), 28.0
		),
		"runtime relocation can enforce explicit modern patrol spacing",
	)
	var evidenced_enemy = ENEMY_UNIT.new()
	evidenced_enemy.stable_mod_patrol_timeline.assign([
		{"elapsed_seconds": 0.0, "position": Vector2.ZERO},
		{"elapsed_seconds": 1.0, "position": Vector2(32.0, 16.0)},
	])
	evidenced_enemy.call("_update_patrol", 0.0)
	_expect(
		float(evidenced_enemy.minimum_actor_separation) < 0.0,
		"process-captured patrols do not receive a second spacing displacement",
	)
	var authored_enemy = ENEMY_UNIT.new()
	authored_enemy.call("_update_patrol", 0.0)
	_expect(
		is_equal_approx(
			float(authored_enemy.minimum_actor_separation),
			28.0,
		),
		"authored patrols without runtime evidence keep modern formation spacing",
	)
	evidenced_enemy.free()
	authored_enemy.free()


func _test_patrol_speed_round_trip() -> void:
	var enemy = ENEMY_UNIT.new()
	enemy.stable_mod_patrol_timeline.assign([
		{"elapsed_seconds": 0.0, "position": Vector2.ZERO},
		{"elapsed_seconds": 1.0, "position": Vector2(96.0, 48.0)},
	])
	enemy.move_speed = 112.59720300700191
	_expect(
		enemy.restore_stable_mod_patrol_state({"elapsed": 0.4})
			and is_equal_approx(enemy.move_speed, 112.59720300700191),
		"restoring a patrol cursor preserves its captured in-flight speed",
	)
	enemy.free()


func _test_modern_patrol_leadership() -> void:
	var leader = ENEMY_UNIT.new()
	var follower = ENEMY_UNIT.new()
	leader.is_alive = true
	follower.is_alive = true
	leader.stable_mod_patrol_timeline.assign([
		{"elapsed_seconds": 0.0, "position": Vector2.ZERO},
		{"elapsed_seconds": 1.0, "position": Vector2(32.0, 0.0)},
	])
	follower.stable_mod_patrol_timeline = leader.stable_mod_patrol_timeline.duplicate(true)
	_expect(
		leader.configure_modern_patrol_formation(7, leader)
			and follower.configure_modern_patrol_formation(
				7,
				leader,
				Vector2(-24.0, 38.0),
			)
			and str(leader.modern_patrol_group_role) == "leader"
			and str(follower.modern_patrol_group_role) == "follower"
			and follower.modern_patrol_leader == leader
			and follower.modern_patrol_local_offset == Vector2(-24.0, 38.0)
			and leader.stable_mod_patrol_timeline.is_empty()
			and follower.stable_mod_patrol_timeline.is_empty(),
		"a patrol group has one route-owning leader and stable trailing slots",
	)
	leader.position = Vector2(100.0, 100.0)
	leader.movement_path = PackedVector2Array([Vector2(200.0, 100.0)])
	leader.movement_path_index = 0
	var heading: Vector2 = leader.modern_patrol_heading()
	var lateral: Vector2 = Vector2(-heading.y, heading.x)
	var follower_slot: Vector2 = (
		leader.position
		+ lateral * follower.modern_patrol_local_offset.x
		- heading * follower.modern_patrol_local_offset.y
	)
	follower.position = follower_slot + heading * 20.0
	follower.issue_path(PackedVector2Array([follower_slot - heading * 20.0]))
	follower.call("_update_modern_patrol_follower", 1.0 / 60.0)
	# A following tick with no active path must continue holding; otherwise the
	# replanner immediately recreates the same tiny backward step.
	follower.call("_update_modern_patrol_follower", 1.0 / 60.0)
	_expect(
		follower.movement_path.is_empty()
			and follower.position.is_equal_approx(follower_slot + heading * 20.0),
		"a nearby patrol follower holds instead of visibly reversing while its leader advances",
	)
	leader.free()
	follower.free()


func _test_readable_movement_animation_cadence() -> void:
	var group := {
		"frame_hold_ticks": 2,
		"secondary_triplet": [2, 1, 1],
		"frames": [null, null, null, null, null, null, null, null, null, null],
	}
	var speed: float = 134.16407864998737
	var frame_seconds: float = SQUAD_UNIT.movement_animation_frame_seconds_for_speed(
		group,
		speed,
	)
	_expect(
		is_equal_approx(
			frame_seconds,
			SQUAD_UNIT.MODERN_MOVEMENT_MIN_FRAME_SECONDS,
		)
			and frame_seconds * 10.0 >= 0.5,
		(
			"fast ten-frame run cycles are capped at a readable modern cadence "
			+ "instead of flickering through a full cycle in under half a second"
		),
	)


func _test_component_movement_carries_waypoint_time() -> void:
	var unit = SQUAD_UNIT.new()
	unit.position = Vector2.ZERO
	unit.target_position = Vector2.ZERO
	unit.uses_original_component_movement = true
	unit.walk_step_components = Vector2(2.0, 1.0)
	unit.is_running = false
	unit.is_crawling = false
	unit.move_speed = SQUAD_UNIT.WALK_SPEED
	unit.use_continuous_waypoint_motion = true
	unit.issue_path(PackedVector2Array([
		Vector2(1.0, 0.5),
		Vector2(2.0, 1.0),
	]))
	unit._physics_process(1.0 / 60.0)
	_expect(
		unit.position.is_equal_approx(Vector2(2.0, 1.0))
			and unit.movement_path_index == 2,
		"enemy-style component movement carries residual physics time across short A* waypoints",
	)
	unit.free()


func _test_single_pass_vision_clipping() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(15)
	sight.resize(15)
	sight[7] = 1
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		5,
		3,
		Vector2i(32, 16),
		movement,
		sight,
	)
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	var origin := Vector2(16.0, 24.0)
	var blocked_target := Vector2(144.0, 24.0)
	var clipped: Vector2 = occupancy.clip_line_of_sight_ray(
		origin,
		blocked_target,
	)
	_expect(
		clipped.x > origin.x
			and clipped.x < 64.0
			and is_equal_approx(clipped.y, origin.y)
			and not occupancy.has_line_of_sight(origin, blocked_target),
		"one-pass tactical vision clipping stops immediately before the first L2 wall cell",
	)
	var clear_target := Vector2(144.0, 8.0)
	_expect(
		occupancy.clip_line_of_sight_ray(origin - Vector2(0.0, 16.0), clear_target)
			.is_equal_approx(clear_target),
		"one-pass tactical vision clipping preserves an unobstructed fan ray",
	)


func _test_bounded_movement_recovery_route() -> void:
	var movement := PackedInt64Array()
	var sight := PackedInt64Array()
	movement.resize(35)
	sight.resize(35)
	var navigation = NAVIGATION_GRID_DATA.create_for_tests(
		7, 5, Vector2i(32, 16), movement, sight
	)
	navigation.prepare_astar()
	var occupancy = DYNAMIC_OCCUPANCY_GRID.new()
	occupancy.configure(navigation)
	var start := Vector2(48.0, 40.0)
	var blocked := Vector2(80.0, 40.0)
	var goal := Vector2(176.0, 40.0)
	occupancy.register_scene(41, start)
	occupancy.register_scene(42, blocked)
	occupancy.finalize_registration()
	var path_queries_before := int(occupancy.path_query_count)
	var recovery: PackedVector2Array = MOVEMENT_RECOVERY_PLANNER.recovery_path(
		occupancy,
		41,
		start,
		goal,
		blocked,
	)
	var crosses_blocked_cell := false
	for point: Vector2 in recovery:
		if navigation.world_to_cell(point) == navigation.world_to_cell(blocked):
			crosses_blocked_cell = true
			break
	_expect(
		not recovery.is_empty()
			and recovery[-1].distance_to(goal) <= 20.0
			and not crosses_blocked_cell,
		"hard-stuck recovery chooses a bounded neighbouring detour without teleporting through the blocker",
	)
	_expect(
		int(occupancy.path_query_count) - path_queries_before
			<= MOVEMENT_RECOVERY_PLANNER.MAX_CANDIDATE_ROUTES * 2,
		"hard-stuck recovery has a strict A* query budget instead of scanning every neighbouring route",
	)
	_expect(
		not is_equal_approx(
			SQUAD_UNIT.movement_watchdog_phase_for_scene(41),
			SQUAD_UNIT.movement_watchdog_phase_for_scene(42),
		),
		"movement watchdog maintenance is deterministically dephased by actor identity",
	)


func _test_subtitle_safe_area() -> void:
	var media = MEDIA_DIRECTOR.new()
	root.add_child(media)
	media.set_gameplay_safe_area(62.0)
	_expect(
		is_equal_approx(media.subtitle_panel.offset_bottom, -78.0)
			and is_equal_approx(media.subtitle_panel.offset_top, -144.0),
		"dialogue subtitles reserve the live 62-pixel bottom HUD instead of being covered by it",
	)
	media.free()


func _test_world_weapon_drop_art_catalog() -> void:
	var all_world_art := true
	for item_id: int in range(36, 46):
		all_world_art = (
			all_world_art
			and not str(MAIN_SCRIPT.world_weapon_sprite_stem(item_id)).is_empty()
		)
	_expect(
		all_world_art,
		"every original weapon drop resolves to transparent world art rather than a framed HUD PSD",
	)


func _test_compact_biped_navigation_footprints() -> void:
	_expect(
		SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(1)
			and SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(27)
			and SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(56)
			and not SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(14)
			and not SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(28),
		"human and military-dog actors use a stable compact navigation footprint while motorcycles and large props retain authored masks",
	)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
