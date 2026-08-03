extends SceneTree

const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const PROJECTILE_WORLD_SCRIPT: Script = preload(
	"res://scripts/projectile_world.gd"
)


class MockCombatant:
	extends Node2D

	var hit_points := 500
	var scene_index := -1
	var runtime_actor_type := 1

	func is_combat_alive() -> bool:
		return hit_points > 0

	func take_damage(amount: int, _attacker: Node2D = null) -> int:
		var applied := mini(maxi(amount, 0), hit_points)
		hit_points -= applied
		return applied


class LifecycleRecorder:
	extends RefCounted

	var events: Array[String] = []

	func commit_factory(context: String) -> bool:
		events.append("factory:%s" % context)
		return true

	func commit_destructor(context: String) -> bool:
		events.append("destructor:%s" % context)
		return true


var checks := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_dart_to_impact_lifecycle()
	_test_grenade_handoff_order()
	_test_invisible_bullet_impact_lifecycle()
	_test_restore_does_not_replay_factory()
	_test_main_random_stream_sites()
	if failures.is_empty():
		print("Projectile actor lifecycle tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_dart_to_impact_lifecycle() -> void:
	var fixture := _fixture(Vector2(80.0, 0.0))
	var world: Node2D = fixture["world"]
	var recorder: LifecycleRecorder = fixture["recorder"]
	var projectile: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("dart_attack"),
	)
	_expect(
		recorder.events == ["factory:projectile actor 80"],
		"actor 80 consumes its factory at projectile construction",
	)
	projectile.call("advance_world_ticks", 6)
	_expect(
		recorder.events == [
			"factory:projectile actor 80",
			"destructor:projectile actor 80",
			"factory:projectile actor 60",
		],
		"dart impact removes actor 80 before creating actor 60",
	)
	projectile.call("advance_world_ticks", 8)
	_expect(
		recorder.events == [
			"factory:projectile actor 80",
			"destructor:projectile actor 80",
			"factory:projectile actor 60",
			"destructor:projectile actor 60",
		],
		"completed impact retires actor 60 exactly once",
	)
	(fixture["arena"] as Node).queue_free()


func _test_grenade_handoff_order() -> void:
	var fixture := _fixture(Vector2(200.0, 0.0))
	var world: Node2D = fixture["world"]
	var recorder: LifecycleRecorder = fixture["recorder"]
	world.connect(
		"projectile_explosion_actor_requested",
		func(
			_attacker: Node2D,
			_world_position: Vector2,
			runtime_actor_type: int,
			_special_bursts: Array[Dictionary],
		) -> void:
			recorder.events.append(
				"request:projectile actor %d" % runtime_actor_type
			),
	)
	var projectile: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("grenade_attack"),
	)
	projectile.call("advance_world_ticks", 30)
	_expect(
		recorder.events == [
			"factory:projectile actor 57",
			"destructor:projectile actor 57",
			"request:projectile actor 61",
		],
		"grenade endpoint removes actor 57 before requesting actor 61",
	)
	(fixture["arena"] as Node).queue_free()


func _test_invisible_bullet_impact_lifecycle() -> void:
	var fixture := _fixture(Vector2(80.0, 0.0))
	var world: Node2D = fixture["world"]
	var recorder: LifecycleRecorder = fixture["recorder"]
	var projectile: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("rifle_attack"),
	)
	_expect(
		recorder.events.is_empty(),
		"effect-1 bullet owns no travelling dynamic actor",
	)
	projectile.call("advance_world_ticks", 2)
	_expect(
		recorder.events == ["factory:projectile actor 60"],
		"effect-1 collision creates actor 60",
	)
	projectile.call("advance_world_ticks", 8)
	_expect(
		recorder.events == [
			"factory:projectile actor 60",
			"destructor:projectile actor 60",
		],
		"effect-1 impact completion removes actor 60",
	)
	(fixture["arena"] as Node).queue_free()


func _test_restore_does_not_replay_factory() -> void:
	var fixture := _fixture(Vector2(160.0, 0.0))
	var world: Node2D = fixture["world"]
	var recorder: LifecycleRecorder = fixture["recorder"]
	var original: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("dart_attack"),
		null,
		null,
		false,
	)
	var snapshot := original.call("snapshot_runtime_state") as Dictionary
	var restored: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("dart_attack"),
		null,
		null,
		false,
	)
	_expect(
		recorder.events.is_empty()
		and int(snapshot.get("schema_version", 0)) == 3
		and bool(snapshot.get("travelling_actor_active", false))
		and restored.call("restore_runtime_state", snapshot),
		"save restoration preserves actor ownership without replaying its factory",
	)
	restored.call("advance_world_ticks", 30)
	_expect(
		recorder.events == [
			"destructor:projectile actor 80",
			"factory:projectile actor 60",
			"destructor:projectile actor 60",
		],
		"restored projectile consumes only post-checkpoint lifecycle events",
	)
	(fixture["arena"] as Node).queue_free()


func _test_main_random_stream_sites() -> void:
	var fixture := _fixture(Vector2(80.0, 0.0))
	var world: Node2D = fixture["world"]
	var game = MAIN_SCRIPT.new()
	game.legacy_crt_random_state = 1
	game.legacy_crt_random_trace_enabled = true
	game.legacy_crt_random_trace.clear()
	world.call(
		"configure_runtime",
		null,
		null,
		_impact_catalog(),
		Callable(game, "_commit_original_dynamic_actor_factory"),
		Callable(game, "_commit_original_dynamic_actor_destructor"),
	)
	var projectile: Node2D = world.call(
		"launch_for_weapon",
		fixture["source"],
		fixture["target"],
		COMBAT_PROFILES.weapon_profile("dart_attack"),
	)
	projectile.call("advance_world_ticks", 14)
	var sites: Array[int] = []
	for raw_draw: Variant in game.legacy_crt_random_trace:
		if raw_draw is Dictionary:
			sites.append(int((raw_draw as Dictionary).get(
				"call_site_rva",
				0,
			)))
	var factory_sites := [
		0x00050967,
		0x00050980,
		0x0005340B,
		0x0005358B,
		0x0005BBBC,
	]
	var destructor_sites := [
		0x00053655,
		0x000537A3,
		0x00050B64,
		0x00050B7D,
	]
	_expect(
		sites == (
			factory_sites
			+ destructor_sites
			+ factory_sites
			+ destructor_sites
		),
		"main stream records actor 80 destruction before actor 60 construction",
	)
	game.free()
	(fixture["arena"] as Node).queue_free()


func _fixture(target_position: Vector2) -> Dictionary:
	var arena := Node2D.new()
	root.add_child(arena)
	var source := MockCombatant.new()
	source.scene_index = 100
	source.position = Vector2.ZERO
	arena.add_child(source)
	var target := MockCombatant.new()
	target.scene_index = 101
	target.position = target_position
	arena.add_child(target)
	var recorder := LifecycleRecorder.new()
	var world = PROJECTILE_WORLD_SCRIPT.new()
	arena.add_child(world)
	var combatants: Array[Node2D] = [source, target]
	world.call("set_combatants", combatants)
	world.call(
		"configure_runtime",
		null,
		null,
		_impact_catalog(),
		Callable(recorder, "commit_factory"),
		Callable(recorder, "commit_destructor"),
	)
	return {
		"arena": arena,
		"world": world,
		"source": source,
		"target": target,
		"recorder": recorder,
	}


func _impact_catalog() -> Dictionary:
	var impact_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	impact_image.fill(Color.WHITE)
	var impact_texture := ImageTexture.create_from_image(impact_image)
	var impact_frames: Array[Texture2D] = [
		impact_texture,
		impact_texture,
		impact_texture,
		impact_texture,
	]
	return {
		306: {
			"frames": impact_frames,
			"frame_hold_ticks": 2,
			"anchor": Vector2.ZERO,
		},
	}


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
