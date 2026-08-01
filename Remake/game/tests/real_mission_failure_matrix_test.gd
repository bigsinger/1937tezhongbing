extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]
const REPAIRED_LEVEL_IDS: Array[String] = ["m006", "m008", "m009", "m011"]

var failures: Array[String] = []
var check_count := 0
var failure_trace_count := 0
var nonfailure_trace_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)

	for level_index: int in range(LEVEL_IDS.size()):
		_validate_profile(main, level_index, "stable_mod")
	for level_id: String in REPAIRED_LEVEL_IDS:
		_validate_profile(main, LEVEL_IDS.find(level_id), "repaired")

	root.remove_child(main)
	main.free()
	await process_frame
	_expect(
		failure_trace_count == 43,
		"failure matrix executes every recovered player, escort, timeout and repaired-only route",
	)
	_expect(
		nonfailure_trace_count == 3,
		"failure matrix also exercises non-required deaths and stable m008 detonation",
	)
	if failures.is_empty():
		print(
			(
				"Real mission failure matrix passed "
				+ "(%d checks, %d failure traces, %d non-failure controls, "
				+ "no global pointer control)."
			)
			% [
				check_count,
				failure_trace_count,
				nonfailure_trace_count,
			]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_profile(main: Node, level_index: int, rule_mode: String) -> void:
	var level_id := LEVEL_IDS[level_index]
	_load_profile(main, level_index, rule_mode)
	var profile_label := "%s/%s" % [level_id, rule_mode]
	var has_required_loss := _declares_failure(main, "required_character_lost")
	var has_time_limit := _declares_failure(main, "time_limit")
	var has_premature_explosion := _declares_failure(main, "premature_explosion")
	_expect(
		has_required_loss,
		"%s declares its recovered required-character failure" % profile_label,
	)

	if has_required_loss:
		var required_names := (
			main.current_mission.get("required_survivors", []) as Array
		).duplicate()
		if required_names.is_empty():
			# An empty list is the product's explicit "any active player" fallback.
			# The repaired m009 profile currently exercises this documented route.
			var fallback_actor: Node2D = _first_living_player(main)
			_expect(
				fallback_actor != null,
				"%s fallback failure route has a living player" % profile_label,
			)
			if fallback_actor != null:
				_kill_and_expect_failure(
					main,
					fallback_actor,
					"required_character_lost",
					"%s fallback player %s"
						% [profile_label, str(fallback_actor.get("display_name"))],
				)
		else:
			for required_name_value: Variant in required_names:
				_load_profile(main, level_index, rule_mode)
				var required_name := str(required_name_value)
				var required_actor: Node2D = _living_player_named(main, required_name)
				_expect(
					required_actor != null,
					"%s exposes required player %s" % [profile_label, required_name],
				)
				if required_actor != null:
					_kill_and_expect_failure(
						main,
						required_actor,
						"required_character_lost",
						"%s required player %s" % [profile_label, required_name],
					)

			_load_profile(main, level_index, rule_mode)
			var nonrequired_player: Node2D = _first_nonrequired_player(main)
			if nonrequired_player != null:
				var nonrequired_name := str(nonrequired_player.get("display_name"))
				nonrequired_player.call("take_damage", 1_000_000, null)
				nonfailure_trace_count += 1
				_expect(
					not main.current_mission_state.is_failed(),
					"%s non-required player %s does not fail the mission"
						% [profile_label, nonrequired_name],
				)

		_load_profile(main, level_index, rule_mode)
		var required_escort_scenes := _required_escort_scenes(main)
		for scene_index: int in required_escort_scenes:
			_load_profile(main, level_index, rule_mode)
			var required_escort: Node2D = _living_escort_scene(main, scene_index)
			_expect(
				required_escort != null,
				"%s exposes required escort scene %d" % [profile_label, scene_index],
			)
			if required_escort != null:
				_kill_and_expect_failure(
					main,
					required_escort,
					"required_character_lost",
					"%s required escort scene %d" % [profile_label, scene_index],
				)

		_load_profile(main, level_index, rule_mode)
		var nonrequired_escort: Node2D = _first_nonrequired_escort(main)
		if nonrequired_escort != null:
			var nonrequired_scene := int(nonrequired_escort.get("scene_index"))
			nonrequired_escort.call("take_damage", 1_000_000, null)
			nonfailure_trace_count += 1
			_expect(
				not main.current_mission_state.is_failed(),
				"%s non-required escort scene %d does not fail the mission"
					% [profile_label, nonrequired_scene],
			)

	if has_time_limit:
		_load_profile(main, level_index, rule_mode)
		var time_limit := float(main.current_mission.get("time_limit_seconds", 0.0))
		_expect(time_limit > 0.25, "%s exposes a positive time limit" % profile_label)
		if time_limit > 0.25:
			main.mission_runtime.advance_time(time_limit - 0.25)
			_expect(
				not main.current_mission_state.is_failed(),
				"%s remains active immediately before its exact time limit"
					% profile_label,
			)
			main.mission_runtime.advance_time(0.25)
			failure_trace_count += 1
			_expect_failed(main, "time_limit", "%s exact time-limit boundary" % profile_label)

	if level_id == "m008" and rule_mode == "stable_mod":
		_expect(
			not has_premature_explosion,
			"m008/stable_mod does not invent the repaired premature-explosion failure",
		)
		_load_profile(main, level_index, rule_mode)
		main._detonate_mission_charges()
		nonfailure_trace_count += 1
		_expect(
			not main.current_mission_state.is_failed(),
			"m008/stable_mod manual detonation remains a non-failing compatibility action",
		)

	if has_premature_explosion:
		_load_profile(main, level_index, rule_mode)
		main._detonate_mission_charges()
		failure_trace_count += 1
		_expect_failed(
			main,
			"premature_explosion",
			"%s repaired-only premature detonation" % profile_label,
		)


func _load_profile(main: Node, level_index: int, rule_mode: String) -> void:
	main.runtime_settings["mission_rule_mode"] = rule_mode
	main.runtime_settings["difficulty_mode"] = "original"
	main.switch_level(level_index, false, false)
	_prepare_level(main)
	var expected_id := LEVEL_IDS[level_index]
	_expect(
		str(main.current_mission.get("id", "")) == expected_id,
		"%s/%s loads the expected real mission" % [expected_id, rule_mode],
	)
	_expect(
		str(main.current_mission.get("rule_mode", "stable_mod")) == rule_mode,
		"%s/%s resolves the requested mission profile" % [expected_id, rule_mode],
	)


func _prepare_level(main: Node) -> void:
	# This gate needs the real combatant death -> main -> MissionRuntime path,
	# but no presentation, autosave or autonomous AI. It never sends desktop or
	# viewport input and never captures, clips or warps the system pointer.
	if main.mission_direction_runtime != null:
		main.mission_direction_runtime.free()
		main.mission_direction_runtime = null
	if main.mission_ai_coordinator != null:
		main.mission_ai_coordinator.free()
		main.mission_ai_coordinator = null
	var runtime: Node = main.mission_runtime
	for connection: Dictionary in [
		{"signal": "state_changed", "method": "_refresh_mission_ui"},
		{"signal": "objective_completed", "method": "_on_objective_completed"},
		{"signal": "victory", "method": "_on_mission_victory"},
		{"signal": "failed", "method": "_on_mission_failed"},
	]:
		var callable := Callable(main, str(connection["method"]))
		var signal_name := StringName(str(connection["signal"]))
		if runtime.is_connected(signal_name, callable):
			runtime.disconnect(signal_name, callable)
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		actor.set_process(false)
		actor.set_physics_process(false)


func _declares_failure(main: Node, failure_id: String) -> bool:
	for raw_failure: Variant in (
		main.current_mission.get("failure_conditions", []) as Array
	):
		if (
			raw_failure is Dictionary
			and str((raw_failure as Dictionary).get("id", "")) == failure_id
		):
			return true
	return false


func _living_player_named(main: Node, display_name: String):
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if (
			bool(unit.get("is_alive"))
			and str(unit.get("display_name")) == display_name
		):
			return unit
	return null


func _first_living_player(main: Node):
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if bool(unit.get("is_alive")):
			return unit
	return null


func _first_nonrequired_player(main: Node):
	var required_names := main.current_mission.get("required_survivors", []) as Array
	if required_names.is_empty():
		return null
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if (
			bool(unit.get("is_alive"))
			and not required_names.has(str(unit.get("display_name")))
		):
			return unit
	return null


func _required_escort_scenes(main: Node) -> Array[int]:
	var result: Array[int] = []
	for binding_value: Variant in (
		main.current_mission.get("required_escort_bindings", []) as Array
	):
		for scene_index: int in main._binding_scenes(str(binding_value)):
			if not result.has(scene_index):
				result.append(scene_index)
	result.sort()
	return result


func _living_escort_scene(main: Node, scene_index: int):
	for escort_value: Variant in main.escorts:
		var escort := escort_value as Node2D
		if (
			bool(escort.get("is_alive"))
			and int(escort.get("scene_index")) == scene_index
		):
			return escort
	return null


func _first_nonrequired_escort(main: Node):
	var required_scenes := _required_escort_scenes(main)
	for escort_value: Variant in main.escorts:
		var escort := escort_value as Node2D
		if (
			bool(escort.get("is_alive"))
			and not required_scenes.has(int(escort.get("scene_index")))
		):
			return escort
	return null


func _kill_and_expect_failure(
	main: Node,
	actor: Node2D,
	expected_failure: String,
	trace_label: String,
) -> void:
	actor.call("take_damage", 1_000_000, null)
	failure_trace_count += 1
	_expect_failed(main, expected_failure, trace_label)


func _expect_failed(main: Node, expected_failure: String, trace_label: String) -> void:
	_expect(
		main.current_mission_state.is_failed()
			and str(main.current_mission_state.failure_id) == expected_failure,
		"%s reaches failure %s through the product runtime"
			% [trace_label, expected_failure],
	)


func _expect(condition: bool, description: String) -> void:
	check_count += 1
	if not condition:
		failures.append(description)
