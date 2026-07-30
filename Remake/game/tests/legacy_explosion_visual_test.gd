extends SceneTree

const RULES: Script = preload(
	"res://scripts/legacy_explosion_visual_rules.gd"
)
const MAIN: Script = preload("res://scripts/main.gd")
const SPECIAL_PROFILES: Script = preload(
	"res://scripts/legacy_special_action_profiles.gd"
)
const SPECIAL_WORLD_OBJECT: Script = preload(
	"res://scripts/legacy_special_world_object.gd"
)


class MockEnemy:
	extends Node2D

	var faction_id := 1
	var hit_points := 10
	var scene_index := 901

	func is_combat_alive() -> bool:
		return hit_points > 0


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_recovered_particle_catalog()
	_test_original_crt_sequence()
	_test_effect_11_burst_plan()
	_test_effect_15_missing_type_102()
	_test_world_object_five_cycle_lifetime()
	_test_real_first_match_assets_when_available()
	if failures.is_empty():
		print("Legacy explosion-visual tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_recovered_particle_catalog() -> void:
	_expect(
		RULES.supported_gfl_indices() == [21, 23, 25, 379, 380],
		"the first-match GFL particle catalog is exact",
	)
	_expect(
		(RULES.family_profile(11).get("runtime_actor_types", []) as Array)
			== [69, 70, 71],
		"effect family 11 maps to runtime types 69/70/71",
	)
	_expect(
		(RULES.family_profile(15).get("runtime_actor_types", []) as Array)
			== [102, 103, 104],
		"effect family 15 maps to runtime types 102/103/104",
	)
	_expect(
		int(RULES.particle_profile(102).get("gfl_index", 0)) == -1,
		"missing runtime type 102 remains an attempted but unspawned particle",
	)
	_expect(
		RULES.particle_lifetime_ticks(69) == 90
		and RULES.particle_lifetime_ticks(70) == 150
		and RULES.particle_lifetime_ticks(71) == 150
		and RULES.particle_lifetime_ticks(102) == 0
		and RULES.particle_lifetime_ticks(103) == 150
		and RULES.particle_lifetime_ticks(104) == 150,
		"particle lifetimes preserve five complete original animation cycles",
	)


func _test_original_crt_sequence() -> void:
	var expected_values := [41, 18467, 6334, 26500, 19169, 15724]
	var state := RULES.CRT_INITIAL_STATE
	var actual_values: Array[int] = []
	for unused_index: int in range(expected_values.size()):
		var step: Dictionary = RULES.next_crt_rand(state)
		state = int(step["state"])
		actual_values.append(int(step["value"]))
	_expect(
		actual_values == expected_values,
		"the default-seed MSVCRT rand sequence matches the executable",
	)


func _test_effect_11_burst_plan() -> void:
	var plan: Dictionary = RULES.build_burst_plan(
		11,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var particles := plan.get("particles", []) as Array
	_expect(
		int(plan.get("attempted_particle_count", 0)) == 2
		and particles.size() == 2
		and int(plan.get("next_random_state", 0)) == 373929026,
		"effect 11 consumes the exact eleven rand draws from seed 1",
	)
	var first := particles[0] as Dictionary
	var second := particles[1] as Dictionary
	_expect(
		int(first.get("runtime_actor_type", 0)) == 71
		and int(first.get("gfl_index", -1)) == 23
		and first.get("world_position", Vector2.ZERO) == Vector2(133.0, 112.0)
		and int(first.get("repeat_count", 0)) == 5,
		"effect 11 first particle preserves variant, scatter, asset, and repeats",
	)
	_expect(
		int(second.get("runtime_actor_type", 0)) == 69
		and int(second.get("gfl_index", -1)) == 21
		and second.get("world_position", Vector2.ZERO) == Vector2(116.0, 109.0)
		and int(second.get("repeat_count", 0)) == 5,
		"effect 11 second particle preserves variant, scatter, asset, and repeats",
	)


func _test_effect_15_missing_type_102() -> void:
	var plan: Dictionary = RULES.build_burst_plan(
		15,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var particles := plan.get("particles", []) as Array
	_expect(
		int(plan.get("attempted_particle_count", 0)) == 2
		and particles.size() == 1
		and int(plan.get("next_random_state", 0)) == 373929026,
		"missing type 102 consumes its draws without creating a particle",
	)
	var particle := particles[0] as Dictionary
	_expect(
		int(particle.get("runtime_actor_type", 0)) == 104
		and int(particle.get("gfl_index", -1)) == 380
		and particle.get("world_position", Vector2.ZERO) == Vector2(133.0, 112.0),
		"effect 15 retains the surviving type-104 particle",
	)


func _test_world_object_five_cycle_lifetime() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var world_object = SPECIAL_WORLD_OBJECT.new()
	arena.add_child(world_object)
	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(8)
	_expect(
		not profile.has("resolved_visual_ticks"),
		"the obsolete invented eight-tick lifetime is absent",
	)
	_expect(
		world_object.configure(
			profile,
			Vector2(100.0, 100.0),
			null,
			3,
			null,
			{},
			Vector2(1000.0, 1000.0),
			RULES.CRT_INITIAL_STATE,
		),
		"the recovered explosion visual configures without converted assets",
	)
	var enemy := MockEnemy.new()
	enemy.position = Vector2(100.0, 100.0)
	arena.add_child(enemy)
	var candidates: Array[Node2D] = [enemy]
	world_object.set_potential_targets(candidates)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.is_resolved()
		and world_object.resolved_particle_count() == 2
		and world_object.maximum_resolved_visual_lifetime_ticks() == 150,
		"the asset-free world object still uses the recovered particle plan",
	)
	world_object.advance_world_ticks(89)
	_expect(
		world_object.resolved_particle_count() == 2,
		"both particles remain before the 90-tick boundary",
	)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.resolved_particle_count() == 1,
		"the nine-frame type-69 particle ends exactly at tick 90",
	)
	world_object.advance_world_ticks(59)
	_expect(
		world_object.resolved_particle_count() == 1,
		"the ten-frame type-71 particle remains through tick 149",
	)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.resolved_particle_count() == 0,
		"the final particle ends after its fifth cycle at tick 150",
	)
	arena.queue_free()


func _test_real_first_match_assets_when_available() -> void:
	var converted_root := ProjectSettings.globalize_path(
		"res://../LocalAssets/converted"
	).simplify_path()
	if not FileAccess.file_exists(
		converted_root.path_join("sprite-frames/0021/sprite.json")
	):
		return
	var game = MAIN.new()
	game.converted_root = converted_root
	var catalog: Dictionary = game.call("_load_legacy_explosion_visual_catalog")
	var expected := {
		21: {"runtime_actor_type": 69, "frame_count": 9, "hold": 2},
		23: {"runtime_actor_type": 71, "frame_count": 10, "hold": 3},
		25: {"runtime_actor_type": 70, "frame_count": 10, "hold": 3},
		379: {"runtime_actor_type": 103, "frame_count": 10, "hold": 3},
		380: {"runtime_actor_type": 104, "frame_count": 10, "hold": 3},
	}
	_expect(
		catalog.keys().size() == expected.size(),
		"all five recovered first-match explosion assets load",
	)
	for raw_gfl_index: Variant in expected.keys():
		var gfl_index := int(raw_gfl_index)
		var visual := catalog.get(gfl_index, {}) as Dictionary
		var profile := expected[gfl_index] as Dictionary
		_expect(
			int(visual.get("runtime_actor_type", 0))
				== int(profile["runtime_actor_type"])
			and int(visual.get("frame_hold_ticks", 0)) == int(profile["hold"])
			and (visual.get("frames", []) as Array).size()
				== int(profile["frame_count"]),
			"GFL %d loads its recovered type, frames, and timing" % gfl_index,
		)
	game.free()


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
