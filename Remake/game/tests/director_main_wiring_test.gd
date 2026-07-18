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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var main: Node = MAIN_SCRIPT.new()
	var recorder := TutorialRecorder.new()
	main.add_child(recorder)
	main.mission_direction_runtime = recorder

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
		main._activate_bound_scene("explosion", 2520)
		and activation_runtime.observed_active
		and main.activated_mission_scenes.has(2520),
		"the causal blast is marked before synchronous next-incomplete camera dispatch",
		failures,
	)
	activation_runtime.reject = true
	_expect(
		not main._activate_bound_scene("explosion", 2521)
		and activation_runtime.observed_active
		and not main.activated_mission_scenes.has(2521),
		"a rejected blast rolls its tentative director activation back",
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
