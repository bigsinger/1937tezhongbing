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
const EXPLOSION_EFFECT: Script = preload(
	"res://scripts/legacy_explosion_effect.gd"
)
const CRT_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
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
	_test_global_call_site_catalog()
	_test_effect_11_burst_plan()
	_test_global_stream_batch_commit()
	_test_effect_15_missing_type_102()
	_test_world_object_five_cycle_lifetime()
	_test_actor_61_effect_lifecycle()
	_test_explosion_snapshot_lifecycles()
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


func _test_global_call_site_catalog() -> void:
	_expect(
		CRT_CATALOG.CALL_SITE_COUNT == 119
		and (CRT_CATALOG.CALL_SITES as Dictionary).size() == 119,
		"the generated catalog exposes all 119 direct original rand call sites",
	)
	_expect(
		CRT_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"particle_attempt_count_max_rand_mod_3_one",
		) == [0x00064744]
		and CRT_CATALOG.rvas_for_operation(
			"populate_explosion_particles",
			"x_magnitude_positive_or_negative_branch",
		) == [0x00064841, 0x00064861],
		"explosion planning resolves call sites from the SDK machine source",
	)


func _test_effect_11_burst_plan() -> void:
	var plan: Dictionary = RULES.build_burst_plan(
		11,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var particles := plan.get("particles", []) as Array
	var random_draws := plan.get("random_draws", []) as Array
	_expect(
		int(plan.get("attempted_particle_count", 0)) == 2
		and particles.size() == 2
		and int(plan.get("next_random_state", 0)) == 373929026
		and int(plan.get("random_draw_count", 0)) == 11
		and random_draws.size() == 11,
		"effect 11 consumes the exact eleven rand draws from seed 1",
	)
	var call_site_sequence: Array[int] = []
	for raw_draw: Variant in random_draws:
		call_site_sequence.append(
			int((raw_draw as Dictionary).get("call_site_rva", 0))
		)
	_expect(
		call_site_sequence == [
			0x00064744,
			0x0006476E,
			0x000647FB,
			0x0006480F,
			0x00064861,
			0x000648B0,
			0x0006476E,
			0x000647FB,
			0x0006480F,
			0x00064861,
			0x000648B0,
		],
		"effect 11 records the original branch-specific call-site order",
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


func _test_global_stream_batch_commit() -> void:
	var game = MAIN.new()
	game.legacy_crt_random_trace_enabled = true
	var plan: Dictionary = RULES.build_burst_plan(
		11,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		game.legacy_crt_random_state,
	)
	_expect(
		game.commit_legacy_crt_random_draws(
			plan.get("random_draws", []) as Array
		)
		and game.legacy_crt_random_state
			== int(plan.get("next_random_state", 0))
		and game.legacy_crt_random_draw_index == 11
		and game.legacy_crt_random_trace.size() == 11,
		"the session-global stream atomically commits and indexes a recovered batch",
	)
	var next_draw: Dictionary = game.next_legacy_crt_random(0x0005D15F)
	_expect(
		int(next_draw.get("draw_index", 0)) == 12
		and int(next_draw.get("call_site_rva", 0)) == 0x0005D15F
		and game.legacy_crt_random_draw_index == 12,
		"single draws continue the same process-global stream after a batch",
	)
	game.free()


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


func _test_actor_61_effect_lifecycle() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var effect = EXPLOSION_EFFECT.new()
	arena.add_child(effect)
	var next_state := int(effect.configure(
		Vector2(100.0, 100.0),
		61,
		{},
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	))
	_expect(
		effect.configured
		and effect.original_gfl_index == 19
		and effect.primary_frame_count == 10
		and effect.primary_frame_hold_ticks == 3,
		"grenade actor 61 keeps GFL 19 and its 10x3 primary animation",
	)
	_expect(
		next_state == 373929026
		and effect.remaining_particle_count() == 2,
		"actor 61 consumes the shared CRT sequence for its effect-11 burst",
	)
	effect.advance_world_ticks(30)
	_expect(
		effect.primary_complete
		and effect.remaining_particle_count() == 2,
		"actor 61 primary animation ends at tick 30 while particles continue",
	)
	effect.advance_world_ticks(60)
	_expect(
		effect.remaining_particle_count() == 1,
		"actor 61 type-69 particle ends at tick 90",
	)
	effect.advance_world_ticks(60)
	_expect(
		effect.is_visual_complete(),
		"actor 61 effect closes after the final fifth-cycle particle at tick 150",
	)
	arena.queue_free()


func _test_explosion_snapshot_lifecycles() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var source_effect = EXPLOSION_EFFECT.new()
	arena.add_child(source_effect)
	source_effect.configure(
		Vector2(210.0, 170.0),
		61,
		{},
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	source_effect.advance_world_ticks(37)
	var effect_snapshot := source_effect.snapshot() as Dictionary
	var restored_effect = EXPLOSION_EFFECT.new()
	arena.add_child(restored_effect)
	restored_effect.configure(
		Vector2.ZERO,
		61,
		{},
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	_expect(
		restored_effect.restore_runtime_state(effect_snapshot)
		and restored_effect.snapshot() == effect_snapshot,
		"actor 61 save/load preserves the exact primary frame and particle loops",
	)
	source_effect.advance_world_ticks(113)
	restored_effect.advance_world_ticks(113)
	_expect(
		source_effect.is_visual_complete()
		and restored_effect.is_visual_complete(),
		"restored actor 61 completes on the same fifth-cycle boundary",
	)

	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(8)
	var source_object = SPECIAL_WORLD_OBJECT.new()
	arena.add_child(source_object)
	source_object.configure(
		profile,
		Vector2(300.0, 220.0),
		null,
		3,
		null,
		{},
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var enemy := MockEnemy.new()
	enemy.position = Vector2(300.0, 220.0)
	arena.add_child(enemy)
	var candidates: Array[Node2D] = [enemy]
	source_object.set_potential_targets(candidates)
	source_object.advance_world_ticks(1)
	source_object.advance_world_ticks(37)
	var object_snapshot := source_object.snapshot() as Dictionary
	var restored_object = SPECIAL_WORLD_OBJECT.new()
	arena.add_child(restored_object)
	restored_object.configure(
		profile,
		Vector2.ZERO,
		null,
		3,
		null,
		{},
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var restored_ok: bool = restored_object.restore_runtime_state(
		object_snapshot
	)
	var restored_snapshot := restored_object.snapshot() as Dictionary
	_expect(
		restored_ok and restored_snapshot == object_snapshot,
		"actor 62 world-object save/load preserves every resolved particle",
	)
	source_object.advance_world_ticks(113)
	restored_object.advance_world_ticks(113)
	_expect(
		source_object.resolved_particle_count() == 0
		and restored_object.resolved_particle_count() == 0,
		"restored actor 62 particles finish on the same tick",
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
	var projectile_catalog: Dictionary = game.call(
		"_load_legacy_projectile_visual_catalog"
	)
	var actor_61_visual := projectile_catalog.get(19, {}) as Dictionary
	var dart_visual := projectile_catalog.get(251, {}) as Dictionary
	_expect(
		int(actor_61_visual.get("runtime_actor_type", 0)) == 61
		and (actor_61_visual.get("frames", []) as Array).size() == 10
		and int(actor_61_visual.get("frame_hold_ticks", 0)) == 3,
		"GFL 19 loads the recovered actor-61 primary explosion",
	)
	_expect(
		int(dart_visual.get("runtime_actor_type", 0)) == 80
		and (dart_visual.get("groups", []) as Array).size() == 8,
		"GFL 251 loads all eight directional dart groups",
	)
	game.free()


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
