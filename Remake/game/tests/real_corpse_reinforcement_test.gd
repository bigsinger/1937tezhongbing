extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
)
const RULES: Script = preload(
	"res://scripts/legacy_corpse_discovery_rules.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var original_count := (main.enemies as Array).size()
	_expect(original_count >= 2, "m000 supplies observer and corpse actors")
	if original_count >= 2:
		var observer := (main.enemies as Array)[0] as Node2D
		var corpse := (main.enemies as Array)[1] as Node2D
		corpse.set("is_alive", false)
		corpse.set("current_hit_points", 0)
		corpse.set("legacy_corpse_discovered", true)
		var expected_marker: Dictionary = main.call(
			"_nearest_legacy_reinforcement_marker",
			observer.position,
		)
		main.call(
			"_on_enemy_legacy_corpse_discovered",
			observer,
			corpse,
		)
		var after_spawn := (main.enemies as Array).size()
		_expect(
			after_spawn == original_count + RULES.REINFORCEMENT_COUNT,
			"corpse alarm creates the exact two-soldier reinforcement pair",
		)
		var dynamic_scenes: Array[int] = []
		for enemy_value: Variant in main.enemies as Array:
			var enemy := enemy_value as Node2D
			if not bool(enemy.get("legacy_reinforcement_spawned")):
				continue
			dynamic_scenes.append(int(enemy.get("scene_index")))
			_expect(
				int(enemy.get("runtime_actor_type"))
					== RULES.REINFORCEMENT_ACTOR_TYPE,
				"dynamic reinforcement uses runtime actor type 6",
			)
			_expect(
				int(
					enemy.get(
						"legacy_reinforcement_source_marker_scene_index"
					)
				)
					== int(expected_marker.get("scene_index", -1)),
				"dynamic pair uses nearest type-93 marker",
			)
			_expect(
				bool(enemy.get("dynamic_registered")),
				"dynamic reinforcement owns a navigation cell",
			)
		_expect(
			dynamic_scenes.size() == RULES.REINFORCEMENT_COUNT
			and dynamic_scenes[0] != dynamic_scenes[1],
			"dynamic reinforcement scene identities are unique",
		)

		var session: Dictionary = GAME_SESSION_STATE.capture(main)
		main.switch_level(0)
		await process_frame
		var restored: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
			main,
			session,
		)
		_expect(bool(restored.get("ok", false)), "reinforcement save restores")
		var restored_dynamic := 0
		for enemy_value: Variant in main.enemies as Array:
			var enemy := enemy_value as Node2D
			if bool(enemy.get("legacy_reinforcement_spawned")):
				restored_dynamic += 1
		_expect(
			restored_dynamic == RULES.REINFORCEMENT_COUNT,
			"save/load recreates both dynamic reinforcement actors",
		)
		_expect(
			bool(main.get("legacy_global_alarm_active")),
			"global corpse alarm survives save/load",
		)
	main.queue_free()
	if failures.is_empty():
		print("Real corpse-reinforcement tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
