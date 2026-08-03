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
	_test_dynamic_actor_factory_lifecycle()
	_test_effect_11_burst_plan()
	_test_global_stream_batch_commit()
	_test_effect_15_missing_type_102()
	_test_persistent_scorch_and_debris_plans()
	_test_native_bresenham_ties()
	_test_world_object_five_cycle_lifetime()
	_test_world_object_animation_audio()
	_test_actor_61_effect_lifecycle()
	_test_explosion_effect_animation_audio()
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
		RULES.supported_gfl_indices() == [
			21, 23, 25, 150, 151, 200, 201, 202, 379, 380, 868, 869, 1000,
		],
		"the first-match GFL particle catalog is exact",
	)
	_expect(
		(RULES.family_profile(10).get("runtime_actor_types", []) as Array)
			== [63, 64, 65]
		and bool(RULES.family_profile(10).get("persistent", false)),
		"effect family 10 maps to persistent scorch types 63/64/65",
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


func _test_dynamic_actor_factory_lifecycle() -> void:
	var success: Dictionary = RULES.build_dynamic_actor_factory_plan(
		RULES.CRT_INITIAL_STATE,
		true,
	)
	var success_sites: Array[int] = []
	for raw_draw: Variant in success.get("random_draws", []) as Array:
		success_sites.append(
			int((raw_draw as Dictionary).get("call_site_rva", 0))
		)
	_expect(
		int(success.get("random_draw_count", 0)) == 5
		and int(success.get("next_random_state", 0)) == 3403800452
		and success_sites == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x0005BBBC,
		],
		"successful dynamic effects consume constructor then loaded-facing draws",
	)
	var failure: Dictionary = RULES.build_dynamic_actor_factory_plan(
		RULES.CRT_INITIAL_STATE,
		false,
	)
	var failure_sites: Array[int] = []
	for raw_draw: Variant in failure.get("random_draws", []) as Array:
		failure_sites.append(
			int((raw_draw as Dictionary).get("call_site_rva", 0))
		)
	_expect(
		int(failure.get("random_draw_count", 0)) == 8
		and int(failure.get("next_random_state", 0)) == 1924036713
		and failure_sites == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"failed dynamic effects destruct immediately without a loaded-facing draw",
	)
	var destructor: Dictionary = RULES.build_dynamic_actor_destructor_plan(
		RULES.CRT_INITIAL_STATE
	)
	var destructor_sites: Array[int] = []
	for raw_draw: Variant in destructor.get("random_draws", []) as Array:
		destructor_sites.append(
			int((raw_draw as Dictionary).get("call_site_rva", 0))
		)
	_expect(
		int(destructor.get("random_draw_count", 0)) == 4
		and destructor_sites == [
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"completed dynamic effects consume derived then base destructor draws",
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
		and int(plan.get("next_random_state", 0)) == 4270317332
		and int(plan.get("random_draw_count", 0)) == 21
		and random_draws.size() == 21,
		"effect 11 consumes scatter plus two successful actor factories",
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
			0x00064841,
			0x00064883,
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x0005BBBC,
			0x0006476E,
			0x000647FB,
			0x0006480F,
			0x00064861,
			0x000648B0,
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x0005BBBC,
		],
		"effect 11 records scatter and factory calls in native execution order",
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
		int(second.get("runtime_actor_type", 0)) == 71
		and int(second.get("gfl_index", -1)) == 23
		and second.get("world_position", Vector2.ZERO) == Vector2(59.0, 89.0)
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
		and game.legacy_crt_random_draw_index == 21
		and game.legacy_crt_random_trace.size() == 21,
		"the session-global stream atomically commits and indexes a recovered batch",
	)
	var next_draw: Dictionary = game.next_legacy_crt_random(0x0005D15F)
	_expect(
		int(next_draw.get("draw_index", 0)) == 22
		and int(next_draw.get("call_site_rva", 0)) == 0x0005D15F
		and game.legacy_crt_random_draw_index == 22,
		"single draws continue the same process-global stream after a batch",
	)
	game.free()


func _test_effect_15_missing_type_102() -> void:
	var plan: Dictionary = RULES.build_burst_plan(
		15,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		8,
	)
	var particles := plan.get("particles", []) as Array
	_expect(
		int(plan.get("attempted_particle_count", 0)) == 1
		and particles.is_empty()
		and int(plan.get("next_random_state", 0)) == 2251028654
		and int(plan.get("random_draw_count", 0)) == 14,
		"missing type 102 consumes scatter, construction, and immediate destruction",
	)
	var sites: Array[int] = []
	for raw_draw: Variant in plan.get("random_draws", []) as Array:
		sites.append(int((raw_draw as Dictionary).get("call_site_rva", 0)))
	_expect(
		sites.slice(6) == [
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x00053655,
			0x000537A3,
			0x00050B64,
			0x00050B7D,
		],
		"failed type-102 loading omits loaded-facing and runs both destructors",
	)


func _test_persistent_scorch_and_debris_plans() -> void:
	var scorch: Dictionary = RULES.build_burst_plan(
		10,
		Vector2(100.0, 100.0),
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var scorch_particles := scorch.get("particles", []) as Array
	_expect(
		int(scorch.get("attempted_particle_count", 0)) == 2
		and scorch_particles.size() == 2
		and int(scorch.get("random_draw_count", 0)) == 21
		and int(scorch.get("next_random_state", 0)) == 4270317332,
		"effect 10 creates two persistent scorch actors with full factory draws",
	)
	var scorch_types: Array[int] = []
	for raw_particle: Variant in scorch_particles:
		var particle := raw_particle as Dictionary
		scorch_types.append(int(particle.get("runtime_actor_type", 0)))
	_expect(
		scorch_types == [65, 65]
		and bool((scorch_particles[0] as Dictionary).get("persistent", false))
		and (scorch_particles[0] as Dictionary).get(
			"world_position",
			Vector2.ZERO,
		) == Vector2(133.0, 112.0)
		and (scorch_particles[1] as Dictionary).get(
			"world_position",
			Vector2.ZERO,
		) == Vector2(59.0, 89.0),
		"effect 10 retains native variants, positions, and persistence",
	)
	var debris: Dictionary = RULES.build_debris_cluster_plan(
		Vector2(100.0, 100.0),
		int(scorch.get("next_random_state", 0)),
	)
	var debris_entries := debris.get("debris", []) as Array
	_expect(
		int(debris.get("attempted_particle_count", 0)) == 4
		and debris_entries.size() == 4
		and int(debris.get("random_draw_count", 0)) == 41
		and int(debris.get("next_random_state", 0)) == 2346411599,
		"effect 12 consumes count plus four exact ten-draw debris factories",
	)
	var debris_types: Array[int] = []
	var debris_angles: Array[int] = []
	var debris_path_sizes: Array[int] = []
	for raw_debris: Variant in debris_entries:
		var entry := raw_debris as Dictionary
		debris_types.append(int(entry.get("runtime_actor_type", 0)))
		debris_angles.append(int(entry.get("angle_degrees", 0)))
		debris_path_sizes.append(
			(entry.get("path", PackedVector2Array()) as PackedVector2Array).size()
		)
	_expect(
		debris_types == [74, 73, 74, 74]
		and debris_angles == [95, 174, 28, 58]
		and debris_path_sizes == [223, 382, 390, 326],
		"debris variants, retained angles, and native path lengths are deterministic",
	)
	var first_debris := debris_entries[0] as Dictionary
	var first_path := first_debris.get(
		"path",
		PackedVector2Array(),
	) as PackedVector2Array
	_expect(
		int(first_debris.get("gfl_index", -1)) == 868
		and int(first_debris.get("repeat_count", 0)) == 2
		and first_path[0] == Vector2(100.0, 100.0)
		and first_path[-1] == Vector2(134.0, -122.0),
		"the first debris actor preserves its asset, flights, and exact endpoints",
	)
	var first_debris_sites: Array[int] = []
	for raw_draw: Variant in (debris.get("random_draws", []) as Array).slice(
		0,
		11,
	):
		first_debris_sites.append(
			int((raw_draw as Dictionary).get("call_site_rva", 0))
		)
	_expect(
		first_debris_sites == [
			0x000653D2,
			0x00065402,
			0x00064138,
			0x00050967,
			0x00050980,
			0x0005340B,
			0x0005358B,
			0x0005BBBC,
			0x0006458D,
			0x00064604,
			0x0006461C,
		],
		"debris tags the native type/style/factory/angle/branch call order",
	)


func _test_native_bresenham_ties() -> void:
	_expect(
		RULES.bresenham_path(
			Vector2.ZERO,
			Vector2(4.0, 2.0),
		) == PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(1.0, 1.0),
			Vector2(2.0, 1.0),
			Vector2(3.0, 2.0),
			Vector2(4.0, 2.0),
		]),
		"sub_408AD0 horizontal-major zero-error ties advance the minor axis first",
	)
	_expect(
		RULES.bresenham_path(
			Vector2.ZERO,
			Vector2(2.0, 4.0),
		) == PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(1.0, 1.0),
			Vector2(1.0, 2.0),
			Vector2(2.0, 3.0),
			Vector2(2.0, 4.0),
		]),
		"sub_408AD0 vertical-major axis swapping preserves the same tie rule",
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
		"both type-71 particles remain before their 150-tick boundary",
	)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.resolved_particle_count() == 2,
		"factory draws shift the second variant without shortening either lifetime",
	)
	world_object.advance_world_ticks(59)
	_expect(
		world_object.resolved_particle_count() == 2,
		"both ten-frame type-71 particles remain through tick 149",
	)
	world_object.advance_world_ticks(1)
	_expect(
		world_object.resolved_particle_count() == 0,
		"the final particle ends after its fifth cycle at tick 150",
	)
	arena.queue_free()


func _test_world_object_animation_audio() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var world_object = SPECIAL_WORLD_OBJECT.new()
	arena.add_child(world_object)
	var events: Array[Dictionary] = []
	world_object.original_animation_audio_requested.connect(
		func(
			_source: Node2D,
			gfl_index: int,
			continuous: bool,
			local_requester_id: int,
		) -> void:
			events.append({
				"gfl_index": gfl_index,
				"continuous": continuous,
				"local_requester_id": local_requester_id,
			})
	)
	var catalog := {
		21: {"action_index": 0, "sound_gfl_index": -1},
		23: {"action_index": 1, "sound_gfl_index": 1350},
		25: {"action_index": 1, "sound_gfl_index": 1350},
	}
	var profile: Dictionary = SPECIAL_PROFILES.profile_for_attack_type(8)
	world_object.configure(
		profile,
		Vector2(100.0, 100.0),
		null,
		3,
		null,
		catalog,
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	var enemy := MockEnemy.new()
	enemy.position = Vector2(100.0, 100.0)
	arena.add_child(enemy)
	var candidates: Array[Node2D] = [enemy]
	world_object.set_potential_targets(candidates)
	world_object.advance_world_ticks(1)
	world_object.advance_world_ticks(1)
	_expect(
		events.size() == 2
		and int(events[0].get("gfl_index", -1)) == 1350
		and int(events[1].get("gfl_index", -1)) == 1350
		and bool(events[0].get("continuous", false))
		and bool(events[1].get("continuous", false))
		and int(events[0].get("local_requester_id", 0)) > 0,
		"both actor-62 fire particles request their authored continuous SPR sound",
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
	var configure_draws: Array = effect.take_crt_random_draws()
	_expect(
		next_state == 3139824070
		and configure_draws.size() == 47
		and effect.persistent_scorch_count() == 1
		and effect.remaining_debris_count() == 3
		and effect.remaining_particle_count() == 0
		and effect.pending_bursts.size() == 1,
		"actor 61 constructs its primary, scorch, and debris before pending damage fire",
	)
	effect.advance_world_ticks(29)
	_expect(
		not effect.primary_complete
		and effect.remaining_particle_count() == 0,
		"actor 61 does not release damage-band fire before its action boundary",
	)
	effect.advance_world_ticks(1)
	var action_draws: Array = effect.take_crt_random_draws()
	_expect(
		effect.primary_complete
		and effect.primary_destructor_consumed
		and effect.remaining_particle_count() == 2
		and action_draws.size() == 29,
		"tick 30 releases fire and retires the primary on the shared stream",
	)
	effect.advance_world_ticks(600)
	_expect(
		effect.remaining_particle_count() == 0
		and effect.remaining_debris_count() == 0
		and effect.persistent_scorch_count() == 1
		and not effect.is_visual_complete()
		and effect.is_persistable(),
		"transient explosion actors retire while the native scorch remains persisted",
	)
	arena.queue_free()


func _test_explosion_effect_animation_audio() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var effect = EXPLOSION_EFFECT.new()
	arena.add_child(effect)
	var events: Array[Dictionary] = []
	effect.original_animation_audio_requested.connect(
		func(
			_source: Node2D,
			gfl_index: int,
			continuous: bool,
			local_requester_id: int,
		) -> void:
			events.append({
				"gfl_index": gfl_index,
				"continuous": continuous,
				"local_requester_id": local_requester_id,
			})
	)
	var catalog := {
		19: {"action_index": 0, "sound_gfl_index": 1267},
		21: {"action_index": 0, "sound_gfl_index": -1},
		23: {"action_index": 1, "sound_gfl_index": 1350},
		25: {"action_index": 1, "sound_gfl_index": 1350},
	}
	effect.configure(
		Vector2(100.0, 100.0),
		61,
		catalog,
		Vector2(1000.0, 1000.0),
		RULES.CRT_INITIAL_STATE,
	)
	effect.advance_world_ticks(3)
	var primary_events := events.filter(
		func(event: Dictionary) -> bool:
			return int(event.get("gfl_index", -1)) == 1267
	)
	var fire_events := events.filter(
		func(event: Dictionary) -> bool:
			return int(event.get("gfl_index", -1)) == 1350
	)
	var fire_events_valid := true
	for event: Dictionary in fire_events:
		fire_events_valid = (
			fire_events_valid
			and bool(event.get("continuous", false))
			and int(event.get("local_requester_id", 0)) > 0
		)
	_expect(
		primary_events.size() == 1
		and not bool(primary_events[0].get("continuous", true))
		and int(primary_events[0].get("local_requester_id", -1)) == 0,
		"actor-61 primary explosion requests its authored sound on entry to frame one",
	)
	_expect(
		fire_events.is_empty() and fire_events_valid,
		"actor-61 secondary fire remains silent before the recovered action boundary",
	)
	effect.advance_world_ticks(27)
	var released_fire_events := events.filter(
		func(event: Dictionary) -> bool:
			return int(event.get("gfl_index", -1)) == 1350
	)
	var released_events_valid := not released_fire_events.is_empty()
	for event: Dictionary in released_fire_events:
		released_events_valid = (
			released_events_valid
			and bool(event.get("continuous", false))
			and int(event.get("local_requester_id", 0)) > 0
		)
	_expect(
		released_events_valid,
		"actor-61 damage-band fire starts continuous authored audio at tick 30",
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
	source_effect.advance_world_ticks(593)
	restored_effect.advance_world_ticks(593)
	_expect(
		source_effect.remaining_particle_count() == 0
		and restored_effect.remaining_particle_count() == 0
		and source_effect.remaining_debris_count() == 0
		and restored_effect.remaining_debris_count() == 0
		and source_effect.persistent_scorch_count() == 1
		and restored_effect.persistent_scorch_count() == 1
		and source_effect.snapshot() == restored_effect.snapshot(),
		"restored actor 61 retires every transient on the same stream and keeps its scorch",
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
		150: {"runtime_actor_type": 72, "frame_count": 4, "hold": 1},
		151: {"runtime_actor_type": 73, "frame_count": 4, "hold": 1},
		200: {"runtime_actor_type": 63, "frame_count": 1, "hold": 1},
		201: {"runtime_actor_type": 64, "frame_count": 1, "hold": 1},
		202: {"runtime_actor_type": 65, "frame_count": 1, "hold": 1},
		379: {"runtime_actor_type": 103, "frame_count": 10, "hold": 3},
		380: {"runtime_actor_type": 104, "frame_count": 10, "hold": 3},
		868: {"runtime_actor_type": 74, "frame_count": 4, "hold": 1},
		869: {"runtime_actor_type": 75, "frame_count": 4, "hold": 1},
		1000: {"runtime_actor_type": 76, "frame_count": 4, "hold": 1},
	}
	_expect(
		catalog.keys().size() == expected.size(),
		"all thirteen recovered fire, scorch, and debris assets load",
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
	var actor_62_visual := projectile_catalog.get(20, {}) as Dictionary
	var dart_visual := projectile_catalog.get(251, {}) as Dictionary
	_expect(
		int(actor_61_visual.get("runtime_actor_type", 0)) == 61
		and (actor_61_visual.get("frames", []) as Array).size() == 10
		and int(actor_61_visual.get("frame_hold_ticks", 0)) == 3
		and int(actor_61_visual.get("sound_gfl_index", -1)) == 1267,
		"GFL 19 loads the recovered actor-61 primary explosion",
	)
	_expect(
		int(actor_62_visual.get("runtime_actor_type", 0)) == 62
		and (actor_62_visual.get("frames", []) as Array).size() == 10
		and int(actor_62_visual.get("frame_hold_ticks", 0)) == 2
		and int(actor_62_visual.get("sound_gfl_index", -1)) == 1269,
		"GFL 20 loads the recovered actor-62 primary explosion and exact sound",
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
