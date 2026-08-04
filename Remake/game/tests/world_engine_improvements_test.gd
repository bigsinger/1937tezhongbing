extends SceneTree

const WORLD_AUDIO_SPATIALIZER: Script = preload(
	"res://scripts/world_audio_spatializer.gd"
)
const SMOOTH_CAMERA_PAN: Script = preload(
	"res://scripts/smooth_camera_pan.gd"
)
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const NAVIGATION_GRID_DATA: Script = preload(
	"res://scripts/navigation_grid_data.gd"
)
const DYNAMIC_OCCUPANCY_GRID: Script = preload(
	"res://scripts/dynamic_occupancy_grid.gd"
)
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_world_audio_attenuation()
	_test_smooth_viewport_local_camera_pan()
	_test_inventory_drop_interaction()
	_test_inventory_drops_reset_with_level()
	_test_patrol_formation_separation()
	_test_modern_patrol_leadership()
	_test_patrol_speed_round_trip()
	_test_distance_synchronized_walk_animation()
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
	leader.free()
	follower.free()


func _test_distance_synchronized_walk_animation() -> void:
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
	var animated_cycle_distance: float = speed * frame_seconds * 10.0
	var authored_cycle_distance: float = Vector2(2.0, 1.0).length() * 2.0 * 10.0
	_expect(
		frame_seconds < 0.05
			and is_equal_approx(
				animated_cycle_distance,
				authored_cycle_distance,
			),
		"walk frames advance from travelled distance instead of producing foot sliding",
	)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
