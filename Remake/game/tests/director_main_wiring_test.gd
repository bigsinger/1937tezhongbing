extends SceneTree

const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")

var checks := 0


class TutorialRecorder extends Node:
	var actions: Array[String] = []

	func report_tutorial_action(action: String) -> Array[String]:
		actions.append(action)
		return []


class ActivationRuntime extends Node:
	var game: Node
	var last_error := ""
	var reject := false
	var observed_active := false

	func is_configured() -> bool:
		return true

	func publish_world_event(_event_name: String, payload: Dictionary) -> Array[String]:
		var scene_index := int(payload.get("scene_index", -1))
		observed_active = (game.get("activated_mission_scenes") as Dictionary).has(scene_index)
		last_error = "synthetic rejection" if reject else ""
		return []


class AudioRecorder extends CanvasLayer:
	var continuous_requests: Array[Dictionary] = []
	var exact_plays: Array[int] = []
	var event_plays: Array[String] = []

	func request_sfx_audio_index(gfl_index: int, requester_id: int = 0) -> bool:
		continuous_requests.append({"gfl_index": gfl_index, "requester_id": requester_id})
		return true

	func play_audio_index(
		gfl_index: int,
		_event_key: String = "direct",
		_caption: String = "",
		_channel: String = "",
	) -> bool:
		exact_plays.append(gfl_index)
		return true

	func play_audio_event(
		event_key: String,
		_actor_key: String = "",
		_variant_seed: int = 0,
		_caption: String = "",
		_channel: String = "",
	) -> bool:
		event_plays.append(event_key)
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var main: Node = MAIN_SCRIPT.new()

	main.current_mission = {
		"id": "m000",
		"scene_bindings": {"rescued": [1427, 1428], "target": [2637]},
		"objectives": [],
	}
	main.world_entities_by_scene = {
		1427: {"x": 4176, "y": 1128},
		1428: {"x": 4304, "y": 1176},
		2637: {"x": 10, "y": 20},
	}
	main.runtime_settings["difficulty_mode"] = "original"
	main.call("_configure_mission_direction")
	_expect(
		main.mission_direction_runtime == null
		and main.mission_ai_coordinator == null,
		"original profile has no remake-editorial dialogue/camera/tutorial/AI layer",
		failures,
	)
	main.runtime_settings["difficulty_mode"] = "normal"
	main.call("_configure_mission_direction")
	_expect(
		main.mission_direction_runtime != null
		and main.mission_ai_coordinator != null,
		"enhanced difficulty explicitly enables the editorial director and AI coordinator",
		failures,
	)
	main.mission_direction_runtime.free()
	main.mission_direction_runtime = null
	main.mission_ai_coordinator.free()
	main.mission_ai_coordinator = null
	var recorder := TutorialRecorder.new()
	main.add_child(recorder)
	main.mission_direction_runtime = recorder
	_expect(
		main._direction_binding_positions("rescued", "first") == [Vector2(4176, 1128)],
		"m000 first-rescue selection focuses Pengxin rather than the final rescued binding",
		failures,
	)

	var live_actor = SQUAD_UNIT.new()
	live_actor.configure(
		"live target",
		Color.WHITE,
		Vector2(333, 444),
		null,
		[] as Array[Dictionary],
		[] as Array[Dictionary],
		2637,
	)
	main.add_child(live_actor)
	main.units.append(live_actor)
	_expect(
		main._direction_binding_positions("target", "") == [Vector2(333, 444)],
		"director bindings prefer a live actor position over the imported spawn point",
		failures,
	)

	var audio_recorder := AudioRecorder.new()
	main.add_child(audio_recorder)
	main.media_director = audio_recorder
	var audio_actor = SQUAD_UNIT.new()
	audio_actor.configure("audio actor", Color.WHITE, Vector2.ZERO)
	main.add_child(audio_actor)
	main.call("_connect_combatant", audio_actor)
	audio_actor.original_animation_audio_requested.emit(audio_actor, 1386, true)
	audio_actor.original_animation_audio_requested.emit(audio_actor, 1363, false)
	_expect(
		audio_recorder.continuous_requests.size() == 1
		and int(audio_recorder.continuous_requests[0]["gfl_index"]) == 1386
		and int(audio_recorder.continuous_requests[0]["requester_id"])
			== audio_actor.get_instance_id()
		and audio_recorder.exact_plays == [1363],
		"Main routes continuous and transition SPR sounds through their exact-index paths",
		failures,
	)
	main.call(
		"_on_original_world_animation_audio_requested",
		audio_actor,
		1350,
		true,
		7,
	)
	main.call(
		"_on_original_world_animation_audio_requested",
		audio_actor,
		1267,
		false,
		0,
	)
	_expect(
		audio_recorder.continuous_requests.size() == 2
		and int(audio_recorder.continuous_requests[1]["gfl_index"]) == 1350
		and int(audio_recorder.continuous_requests[1]["requester_id"])
			== int(hash([audio_actor.get_instance_id(), 7]))
		and audio_recorder.exact_plays == [1363, 1267],
		"Main preserves per-particle request identity for authored world-animation audio",
		failures,
	)
	var authored_attack_groups: Array[Dictionary] = []
	for unused_direction: int in range(8):
		authored_attack_groups.append({"sound_gfl_index": 1363})
	audio_actor.attack_groups.assign(authored_attack_groups)
	audio_actor.animation_group_index = 0
	main.call("_on_attack_started", audio_actor, null, 1, 0.0)
	_expect(
		audio_recorder.event_plays.is_empty(),
		"generic attack-event audio is suppressed when the SPR supplies an exact sound",
		failures,
	)
	audio_actor.attack_groups.clear()
	main.call("_on_attack_started", audio_actor, null, 1, 0.0)
	_expect(
		audio_recorder.event_plays == ["attack_pistol"],
		"generic attack-event audio remains available for synthetic or old-schema sprites",
		failures,
	)

	var first = SQUAD_UNIT.new()
	first.configure("first", Color.WHITE, Vector2(100, 100))
	var second = SQUAD_UNIT.new()
	second.configure("second", Color.WHITE, Vector2(200, 100))
	main.add_child(first)
	main.add_child(second)
	main.units.append(first)
	main.units.append(second)
	main.handle_selection(first.position, false)
	main.handle_selection(second.position, true)
	_expect(
		recorder.actions.has("select_multiple_units"),
		"Shift-additive selection completes the m009 multi-select tutorial",
		failures,
	)

	recorder.actions.clear()
	main.current_mission = {
		"id": "m010",
		"simultaneous_zone_rule": {
			"eligible_player_names": ["老赵", "强子", "大牛", "古明"],
		},
	}
	var ordered_units: Array = []
	for name: String in ["老赵", "强子", "大牛", "古明"]:
		var unit = SQUAD_UNIT.new()
		unit.configure(name, Color.WHITE, Vector2.ZERO)
		main.add_child(unit)
		ordered_units.append(unit)
	for index: int in range(3):
		main._record_m010_split_order(ordered_units[index])
	_expect(
		not recorder.actions.has("issue_split_orders"),
		"m010 tutorial remains pending after only three distinct squad orders",
		failures,
	)
	main._record_m010_split_order(ordered_units[3])
	_expect(
		recorder.actions.count("issue_split_orders") == 1,
		"m010 tutorial completes after all four required actors receive orders",
		failures,
	)

	var activation_runtime := ActivationRuntime.new()
	activation_runtime.game = main
	main.add_child(activation_runtime)
	main.mission_runtime = activation_runtime
	main.current_mission = {
		"id": "m001",
		"scene_bindings": {"explosion": [2520, 2521]},
		"charge_policy": {"mode": "preplanted"},
		"objectives": [],
	}
	main.activated_mission_scenes.clear()
	_expect(
		not main._activate_bound_scene("explosion", 2520)
		and not main.activated_mission_scenes.has(2520),
		"source-backed blast targets reject the generic E-key completion path",
		failures,
	)
	_expect(
		main._complete_native_explosion_scene(2520)
		and activation_runtime.observed_active
		and main.activated_mission_scenes.has(2520),
		"the causal native blast is marked before synchronous next-incomplete camera dispatch",
		failures,
	)
	activation_runtime.reject = true
	_expect(
		not main._complete_native_explosion_scene(2521)
		and activation_runtime.observed_active
		and not main.activated_mission_scenes.has(2521),
		"a rejected native blast rolls its tentative director activation back",
		failures,
	)

	main.free()
	if failures.is_empty():
		print("Director/Main wiring tests passed (%d checks)." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
