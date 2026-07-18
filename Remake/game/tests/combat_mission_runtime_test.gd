extends SceneTree

const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT_SCRIPT: Script = preload("res://scripts/enemy_unit.gd")
const ESCORT_UNIT_SCRIPT: Script = preload("res://scripts/escort_unit.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const FIXTURE_ANCHOR_KIND_BY_BINDING := {
	"explosion": "explosion_detector",
	"exit": "exit_detector",
	"high_ground": "exit_detector",
}


class ClearSight:
	extends RefCounted

	func has_line_of_sight(
		_observer_position: Vector2,
		_target_position: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return true


var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_combat_timing_ammo_and_death(failures)
	_test_alert_propagation(failures)
	_test_faction_and_exit_party_rules(failures)
	_test_m000_world_event_closure(failures)
	_test_m008_manual_explosion_failure(failures)
	_test_all_mission_world_event_closures(failures)

	if failures.is_empty():
		print("Combat and mission runtime tests passed (%d checks)." % check_count)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _test_combat_timing_ammo_and_death(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var clear_sight := ClearSight.new()
	var attack_groups := _animation_groups(3)
	var death_groups := _animation_groups(3)
	var empty_groups: Array[Dictionary] = []
	var weapon_profile := _test_weapon_profile()

	var attacker = SQUAD_UNIT_SCRIPT.new()
	attacker.configure(
		"attacker", Color.WHITE, Vector2.ZERO, null, empty_groups, empty_groups, -1, clear_sight
	)
	attacker.configure_combat(3, 8, weapon_profile, attack_groups, empty_groups, false)
	var target = SQUAD_UNIT_SCRIPT.new()
	target.configure(
		"target", Color.WHITE, Vector2(100.0, 0.0), null, empty_groups, empty_groups, -1, clear_sight
	)
	target.configure_combat(1, 7, {}, empty_groups, death_groups, true)
	arena.add_child(attacker)
	arena.add_child(target)

	var attack_started_events: Array[Dictionary] = []
	var attack_hit_events: Array[Dictionary] = []
	var ammo_events: Array[Vector2i] = []
	attacker.attack_started.connect(
		func(_attacker: Node2D, _target: Node2D, attack_type: int, alert_radius: float) -> void:
			attack_started_events.append(
				{"attack_type": attack_type, "alert_radius": alert_radius}
			)
	)
	attacker.attack_hit.connect(
		func(_attacker: Node2D, _target: Node2D, attack_type: int, damage: int) -> void:
			attack_hit_events.append({"attack_type": attack_type, "damage": damage})
	)
	attacker.ammo_changed.connect(
		func(_unit: Node2D, magazine: int, reserve: int) -> void:
			ammo_events.append(Vector2i(magazine, reserve))
	)
	_expect(attacker.try_start_attack(target), "an in-range attack starts", failures)
	_expect(
		attacker.magazine_ammo == 1 and target.current_hit_points == 7,
		"starting an attack consumes ammunition but does not deal early damage",
		failures,
	)
	_expect(
		attack_started_events.size() == 1
		and int(attack_started_events[0]["attack_type"]) == 2
		and is_equal_approx(float(attack_started_events[0]["alert_radius"]), 640.0),
		"attack start exposes recovered attack type and alert radius",
		failures,
	)

	attacker._physics_process(0.169)
	_expect(
		target.current_hit_points == 7 and attack_hit_events.is_empty(),
		"damage is absent before entering the final attack frame",
		failures,
	)
	attacker._physics_process(0.002)
	_expect(
		target.current_hit_points == 5
		and attack_hit_events.size() == 1
		and int(attack_hit_events[0]["damage"]) == 2,
		"damage is applied exactly when the final attack frame is entered",
		failures,
	)
	attacker._physics_process(0.085)
	_expect(
		target.current_hit_points == 5 and attack_hit_events.size() == 1,
		"holding and finishing the final frame cannot apply damage twice",
		failures,
	)

	_expect(attacker.try_start_attack(target), "a second loaded attack starts", failures)
	attacker._physics_process(0.171)
	attacker._physics_process(0.085)
	_expect(
		attacker.magazine_ammo == 0
		and target.current_hit_points == 3
		and attack_hit_events.size() == 2,
		"each committed attack consumes one round and resolves one hit",
		failures,
	)
	_expect(
		not attacker.try_start_attack(target)
		and attacker.combat_action == SQUAD_UNIT_SCRIPT.CombatAction.RELOAD,
		"an empty magazine starts reload instead of creating a free attack",
		failures,
	)
	attacker._physics_process(0.099)
	_expect(
		attacker.magazine_ammo == 0 and attacker.reserve_ammo == 3,
		"reload does not transfer ammunition before its timer completes",
		failures,
	)
	attacker._physics_process(0.002)
	_expect(
		attacker.magazine_ammo == 2
		and attacker.reserve_ammo == 1
		and ammo_events == [Vector2i(1, 3), Vector2i(0, 3), Vector2i(2, 1)],
		"reload transfers only the magazine deficit and emits exact ammo state",
		failures,
	)

	var casualty = SQUAD_UNIT_SCRIPT.new()
	casualty.configure(
		"casualty", Color.WHITE, Vector2(120.0, 0.0), null, empty_groups, empty_groups, -1, clear_sight
	)
	casualty.configure_combat(1, 3, {}, empty_groups, death_groups, true)
	arena.add_child(casualty)
	var death_events: Array[Node2D] = []
	casualty.died.connect(
		func(_unit: Node2D, killer: Node2D) -> void:
			death_events.append(killer)
	)
	_expect(casualty.take_damage(9, attacker) == 3, "lethal damage is capped at remaining HP", failures)
	_expect(
		not casualty.is_alive
		and casualty.combat_action == SQUAD_UNIT_SCRIPT.CombatAction.DEATH
		and casualty.action_frame_index == 0
		and death_events == [attacker],
		"lethal damage starts one death action and emits one death event",
		failures,
	)
	casualty._physics_process(0.171)
	_expect(
		casualty.action_frame_index == 2 and not casualty.action_finished,
		"death animation reaches its final frame before finishing",
		failures,
	)
	casualty._physics_process(0.085)
	_expect(
		casualty.action_frame_index == 2
		and casualty.action_finished
		and casualty.combat_action == SQUAD_UNIT_SCRIPT.CombatAction.DEATH,
		"death animation holds its final frame instead of returning to idle",
		failures,
	)
	_expect(
		casualty.take_damage(1, attacker) == 0 and death_events.size() == 1,
		"death is idempotent under duplicate damage callbacks",
		failures,
	)

	arena.free()


func _test_alert_propagation(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var clear_sight := ClearSight.new()
	var empty_groups: Array[Dictionary] = []
	var weapon_profile := _test_weapon_profile()
	var attacker = SQUAD_UNIT_SCRIPT.new()
	attacker.configure(
		"attacker", Color.WHITE, Vector2.ZERO, null, empty_groups, empty_groups, -1, clear_sight
	)
	attacker.configure_combat(3, 8, weapon_profile, empty_groups, empty_groups, true)
	var target = SQUAD_UNIT_SCRIPT.new()
	target.configure(
		"target", Color.WHITE, Vector2(80.0, 0.0), null, empty_groups, empty_groups, -1, clear_sight
	)
	target.configure_combat(3, 8, weapon_profile, empty_groups, empty_groups, true)
	var nearby_enemy = _make_alert_enemy("nearby", Vector2(500.0, 0.0), clear_sight)
	var distant_enemy = _make_alert_enemy("distant", Vector2(700.0, 0.0), clear_sight)
	for unit: Node2D in [attacker, target, nearby_enemy, distant_enemy]:
		arena.add_child(unit)

	var main = MAIN_SCRIPT.new()
	main.enemies.append(nearby_enemy)
	main.enemies.append(distant_enemy)
	main._on_attack_started(attacker, target, 2, 640.0)
	_expect(
		nearby_enemy.current_target == attacker
		and nearby_enemy.behavior_state == ENEMY_UNIT_SCRIPT.BehaviorState.CHASE
		and nearby_enemy.last_known_target_position == attacker.position,
		"gunfire alert gives nearby enemies the shooter's live target and position",
		failures,
	)
	_expect(
		distant_enemy.current_target == null
		and distant_enemy.behavior_state == ENEMY_UNIT_SCRIPT.BehaviorState.PATROL,
		"gunfire alert does not propagate beyond its configured radius",
		failures,
	)
	_expect(
		not distant_enemy.receive_alert(null, Vector2.ZERO),
		"enemy alert receiver rejects a missing or dead combat target",
		failures,
	)
	main.free()
	arena.free()


func _test_m000_world_event_closure(failures: Array[String]) -> void:
	var mission: Dictionary = MISSION_DATA.load_mission("m000")
	var level := {
		"entities": [
			{"scene_index": 1427, "display_name": "彭鑫"},
			{"scene_index": 1428, "display_name": "老罗叔"},
		],
		"task_anchors": [
			{"scene_index": 1600, "kind": "exit_detector"},
		],
	}
	var state = MISSION_STATE.new(mission)
	var runtime = MISSION_RUNTIME_SCRIPT.new()
	root.add_child(runtime)
	var completed_signals: Array[String] = []
	var victory_signals := [0]
	runtime.objective_completed.connect(
		func(objective_id: String) -> void:
			completed_signals.append(objective_id)
	)
	runtime.victory.connect(func() -> void: victory_signals[0] += 1)
	_expect(runtime.configure(mission, level, state), "m000 runtime accepts its recovered scene bindings", failures)
	_expect(
		runtime.bound_scenes("rescued") == [1427, 1428]
		and runtime.binding_kinds_for_scene(1600) == ["exit"],
		"m000 runtime indexes rescue actors and exit anchor",
		failures,
	)

	runtime.publish_world_event(
		"trigger_activated",
		{"display_name": "检测出口精灵", "scene_index": 1600},
	)
	_expect(
		not state.is_objective_complete("evacuate") and runtime.durable_fact_count() == 0,
		"an early exit is rejected and is not cached as a durable fact",
		failures,
	)
	runtime.publish_world_event(
		"entity_rescued",
		{"display_name": "彭鑫", "scene_index": 1427},
	)
	runtime.publish_world_event(
		"entity_rescued",
		{"display_name": "彭鑫", "scene_index": 1427, "timestamp": 99.0},
	)
	_expect(
		state.is_objective_complete("rescue_pengxin")
		and int(state.progress["rescue_pengxin"]) == 1
		and runtime.durable_fact_count() == 1,
		"duplicate rescue callbacks collapse to one durable world fact",
		failures,
	)
	runtime.publish_world_event(
		"entity_rescued",
		{"display_name": "老罗叔", "scene_index": 1428},
	)
	_expect(
		state.is_objective_complete("rescue_luoluo") and not state.is_victory(),
		"both rescue objectives complete before evacuation without premature victory",
		failures,
	)
	runtime.publish_world_event(
		"trigger_activated",
		{"display_name": "检测出口精灵", "scene_index": 1600},
	)
	_expect(
		state.is_victory()
		and completed_signals == ["rescue_pengxin", "rescue_luoluo", "evacuate"]
		and victory_signals[0] == 1,
		"m000 rescue-rescue-escort event chain reaches victory exactly once",
		failures,
	)
	runtime.publish_world_event(
		"trigger_activated",
		{"display_name": "检测出口精灵", "scene_index": 1600},
	)
	_expect(victory_signals[0] == 1, "terminal m000 callbacks cannot emit victory twice", failures)
	runtime.free()

	var failure_state = MISSION_STATE.new(mission)
	var failure_runtime = MISSION_RUNTIME_SCRIPT.new()
	root.add_child(failure_runtime)
	var failure_signals: Array[String] = []
	failure_runtime.failed.connect(
		func(failure_id: String) -> void:
			failure_signals.append(failure_id)
	)
	_expect(
		failure_runtime.configure(mission, level, failure_state),
		"m000 failure fixture configures",
		failures,
	)
	failure_runtime.publish_world_event("required_character_lost", {"display_name": "老赵"})
	failure_runtime.publish_world_event("required_character_lost", {"display_name": "老赵"})
	_expect(
		failure_state.failure_id == "required_character_lost"
		and failure_signals == ["required_character_lost"]
		and not failure_state.is_victory(),
		"required-character loss closes m000 through one idempotent failure signal",
		failures,
	)
	failure_runtime.publish_world_event(
		"entity_rescued",
		{"display_name": "彭鑫", "scene_index": 1427},
	)
	_expect(
		not failure_state.is_objective_complete("rescue_pengxin"),
		"world events cannot advance mission objectives after failure",
		failures,
	)
	failure_runtime.free()


func _test_faction_and_exit_party_rules(failures: Array[String]) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var clear_sight := ClearSight.new()
	var empty_groups: Array[Dictionary] = []
	var attacker = SQUAD_UNIT_SCRIPT.new()
	attacker.configure(
		"player", Color.WHITE, Vector2.ZERO, null, empty_groups, empty_groups, -1, clear_sight
	)
	attacker.configure_combat(3, 8, _test_weapon_profile(), empty_groups, empty_groups, true)
	var friendly = SQUAD_UNIT_SCRIPT.new()
	friendly.configure(
		"friendly", Color.WHITE, Vector2(40.0, 0.0), null, empty_groups, empty_groups, -1, clear_sight
	)
	friendly.configure_combat(3, 8, _test_weapon_profile(), empty_groups, empty_groups, true)
	var neutral = ESCORT_UNIT_SCRIPT.new()
	neutral.display_name = "driver"
	neutral.scene_index = 2506
	neutral.position = Vector2(20.0, 0.0)
	neutral.faction_id = 2
	neutral.rescued_state = false
	var enemy = _make_alert_enemy("enemy", Vector2(80.0, 0.0), clear_sight)
	for combatant: Node2D in [attacker, friendly, neutral, enemy]:
		arena.add_child(combatant)
	_expect(
		not attacker.try_start_attack(friendly),
		"the shared combat executor rejects same-faction friendly fire",
		failures,
	)
	_expect(
		not enemy.receive_alert(neutral, neutral.position),
		"an unrecruited neutral escort is not a hostile enemy target",
		failures,
	)
	_expect(neutral.rescue(attacker), "a neutral escort can be rescued by a live player", failures)
	_expect(
		neutral.faction_id == 3 and enemy.receive_alert(neutral, neutral.position),
		"rescue changes the escort to the player faction and enables hostile targeting",
		failures,
	)

	var main = MAIN_SCRIPT.new()
	main.current_mission = {
		"scene_bindings": {"driver": [2506], "exit": [2522]},
		"exit_party": {"player_names": ["古明"], "escort_bindings": ["driver"]},
	}
	attacker.display_name = "古明"
	attacker.position = Vector2.ZERO
	friendly.display_name = "老赵"
	friendly.position = Vector2(900.0, 0.0)
	neutral.position = Vector2.ZERO
	main.units.append(attacker)
	main.units.append(friendly)
	main.escorts.append(neutral)
	_expect(
		main._required_exit_party_is_present(Vector2.ZERO),
		"configured m001 exit party ignores unrelated living players outside the train",
		failures,
	)
	neutral.rescued_state = false
	_expect(
		not main._required_exit_party_is_present(Vector2.ZERO),
		"configured exit party still requires its bound rescued driver",
		failures,
	)
	main.units.clear()
	main.escorts.clear()
	main.free()
	arena.free()


func _test_m008_manual_explosion_failure(failures: Array[String]) -> void:
	var mission: Dictionary = MISSION_DATA.load_mission("m008")
	var level := _build_mission_level_fixture(mission)
	var state = MISSION_STATE.new(mission)
	var runtime = MISSION_RUNTIME_SCRIPT.new()
	root.add_child(runtime)
	_expect(runtime.configure(mission, level, state), "m008 explosion fixture configures", failures)
	var main = MAIN_SCRIPT.new()
	main.current_mission = mission
	main.current_mission_state = state
	main.mission_runtime = runtime
	main._detonate_mission_charges()
	_expect(
		state.failure_id == "premature_explosion",
		"F detonation closes m008 through the recovered premature-explosion failure",
		failures,
	)
	main.mission_runtime = null
	main.free()
	runtime.free()


func _test_all_mission_world_event_closures(failures: Array[String]) -> void:
	var catalog: Dictionary = MISSION_DATA.load_catalog()
	for raw_mission: Variant in catalog.get("missions", []) as Array:
		var mission := raw_mission as Dictionary
		var mission_id := str(mission.get("id", ""))
		var level := _build_mission_level_fixture(mission)
		var state = MISSION_STATE.new(mission)
		var runtime = MISSION_RUNTIME_SCRIPT.new()
		root.add_child(runtime)
		var victory_signals := [0]
		runtime.victory.connect(func() -> void: victory_signals[0] += 1)
		var configured: bool = runtime.configure(mission, level, state)
		_expect(
			configured,
			"%s generated world fixture configures: %s" % [mission_id, runtime.last_error],
			failures,
		)
		if not configured:
			runtime.free()
			continue

		var scene_cursors: Dictionary = {}
		var pending_objectives: Array[Dictionary] = []
		for raw_objective: Variant in mission.get("objectives", []) as Array:
			pending_objectives.append(raw_objective as Dictionary)
		var pass_count := 0
		while not pending_objectives.is_empty() and pass_count <= pending_objectives.size() + 1:
			pass_count += 1
			var made_progress := false
			var completed_indices: Array[int] = []
			for index in range(pending_objectives.size()):
				var objective: Dictionary = pending_objectives[index]
				if not state.dependencies_complete(objective):
					continue
				_publish_fixture_objective_events(
					runtime, mission, state, objective, scene_cursors, failures
				)
				if state.is_objective_complete(str(objective.get("id", ""))):
					completed_indices.append(index)
					made_progress = true
			for index in range(completed_indices.size() - 1, -1, -1):
				pending_objectives.remove_at(completed_indices[index])
			if not made_progress:
				break

		_expect(
			pending_objectives.is_empty(),
			"%s every declared objective is reachable through valid world events" % mission_id,
			failures,
		)
		_expect(state.is_victory(), "%s required objective graph reaches victory" % mission_id, failures)
		_expect(
			victory_signals[0] == 1,
			"%s data-driven closure emits victory exactly once" % mission_id,
			failures,
		)
		runtime.free()


func _build_mission_level_fixture(mission: Dictionary) -> Dictionary:
	var entities: Array[Dictionary] = []
	var task_anchors: Array[Dictionary] = []
	var indexed_scenes: Dictionary = {}
	var scene_bindings := mission.get("scene_bindings", {}) as Dictionary
	for raw_binding_kind: Variant in scene_bindings.keys():
		var binding_kind := str(raw_binding_kind)
		for raw_scene: Variant in scene_bindings[raw_binding_kind] as Array:
			var scene_index := int(raw_scene)
			if indexed_scenes.has(scene_index):
				continue
			indexed_scenes[scene_index] = true
			if FIXTURE_ANCHOR_KIND_BY_BINDING.has(binding_kind):
				task_anchors.append(
					{
						"scene_index": scene_index,
						"kind": str(FIXTURE_ANCHOR_KIND_BY_BINDING[binding_kind]),
					}
				)
			else:
				entities.append(
					{
						"scene_index": scene_index,
						"display_name": "%s fixture" % binding_kind,
					}
				)
	return {"entities": entities, "task_anchors": task_anchors}


func _publish_fixture_objective_events(
	runtime: Node,
	mission: Dictionary,
	state: RefCounted,
	objective: Dictionary,
	scene_cursors: Dictionary,
	failures: Array[String],
) -> void:
	var objective_id := str(objective.get("id", ""))
	var condition := objective.get("condition", {}) as Dictionary
	var required_count := int(condition.get("required_count", 1))
	var attempts := 0
	while not state.is_objective_complete(objective_id) and attempts < required_count + 1:
		attempts += 1
		var event_name := str(condition.get("event", ""))
		var payload := (condition.get("where", {}) as Dictionary).duplicate(true) as Dictionary
		var scene_index := _fixture_scene_for_event(
			mission, runtime, event_name, payload, scene_cursors
		)
		if scene_index >= 0:
			if event_name == "party_at_trigger":
				payload["trigger_scene_index"] = scene_index
			elif event_name == "item_acquired" and payload.has("item_role"):
				payload["source_scene_index"] = scene_index
			else:
				payload["scene_index"] = scene_index
		elif _event_requires_fixture_scene(event_name):
			_expect(
				false,
				"%s/%s has a resolvable bound scene for %s"
				% [str(mission.get("id", "")), objective_id, event_name],
				failures,
			)
			return
		runtime.publish_world_event(event_name, payload)
		_expect(
			runtime.last_error.is_empty(),
			"%s/%s publishes a legal %s event: %s"
			% [str(mission.get("id", "")), objective_id, event_name, runtime.last_error],
			failures,
		)


func _fixture_scene_for_event(
	mission: Dictionary,
	runtime: Node,
	event_name: String,
	payload: Dictionary,
	scene_cursors: Dictionary,
) -> int:
	match event_name:
		"entity_rescued":
			var rescue_kinds: Array[String] = []
			var scene_bindings := mission.get("scene_bindings", {}) as Dictionary
			if payload.has("family_role") and scene_bindings.has("father") and scene_bindings.has("mother"):
				rescue_kinds = ["father", "mother"]
			elif str(payload.get("display_name", "")) == "孙小姐" and scene_bindings.has("reporter"):
				rescue_kinds = ["reporter"]
			elif scene_bindings.has("driver"):
				rescue_kinds = ["driver"]
			else:
				rescue_kinds = ["rescued"]
			return _next_fixture_scene(
				runtime,
				rescue_kinds,
				"rescued:%s" % ",".join(rescue_kinds),
				scene_cursors,
			)
		"item_acquired":
			if payload.has("item_name"):
				var pickup_bindings := mission.get("pickup_bindings", {}) as Dictionary
				for raw_binding_kind: Variant in pickup_bindings.keys():
					var pickup := pickup_bindings[raw_binding_kind] as Dictionary
					if str(pickup.get("item_name", "")) == str(payload["item_name"]):
						return _next_fixture_scene(
							runtime,
							[str(raw_binding_kind)],
							"item_name:%s" % str(payload["item_name"]),
							scene_cursors,
						)
			if payload.has("item_role"):
				var role_drops := mission.get("role_drops", {}) as Dictionary
				for raw_role_id: Variant in role_drops.keys():
					var drop := role_drops[raw_role_id] as Dictionary
					if str(drop.get("item_role", "")) == str(payload["item_role"]):
						return _next_fixture_scene(
							runtime,
							[str(raw_role_id)],
							"item_role:%s" % str(payload["item_role"]),
							scene_cursors,
						)
		"role_eliminated", "story_anchor_reached":
			var role_id := str(payload.get("role_id", ""))
			return _next_fixture_scene(runtime, [role_id], event_name + ":" + role_id, scene_cursors)
		"trigger_activated":
			if str(payload.get("display_name", "")) == "检测爆炸精灵":
				return _next_fixture_scene(runtime, ["explosion"], "explosion", scene_cursors)
			if not runtime.bound_scenes("high_ground").is_empty():
				return _next_fixture_scene(runtime, ["high_ground"], "high_ground", scene_cursors)
			return _next_fixture_scene(runtime, ["exit"], "exit", scene_cursors)
		"party_at_trigger":
			if payload.has("trigger_scene_index"):
				return int(payload["trigger_scene_index"])
			return _next_fixture_scene(runtime, ["exit"], "party_at_exit", scene_cursors)
	return -1


func _next_fixture_scene(
	runtime: Node,
	binding_kinds: Array[String],
	cursor_key: String,
	scene_cursors: Dictionary,
) -> int:
	var candidates: Array[int] = []
	for binding_kind: String in binding_kinds:
		for scene_index: int in runtime.bound_scenes(binding_kind):
			if not candidates.has(scene_index):
				candidates.append(scene_index)
	var cursor := int(scene_cursors.get(cursor_key, 0))
	if cursor < 0 or cursor >= candidates.size():
		return -1
	scene_cursors[cursor_key] = cursor + 1
	return candidates[cursor]


func _event_requires_fixture_scene(event_name: String) -> bool:
	return event_name in [
		"entity_rescued",
		"item_acquired",
		"role_eliminated",
		"story_anchor_reached",
		"trigger_activated",
		"party_at_trigger",
	]


func _make_alert_enemy(name: String, start_position: Vector2, clear_sight: RefCounted):
	var empty_groups: Array[Dictionary] = []
	var enemy = ENEMY_UNIT_SCRIPT.new()
	enemy.configure(
		name, Color.WHITE, start_position, null, empty_groups, empty_groups, -1, clear_sight
	)
	enemy.configure_combat(1, 8, _test_weapon_profile(), empty_groups, empty_groups, true)
	return enemy


func _test_weapon_profile() -> Dictionary:
	return {
		"attack_type": 2,
		"horizontal_range": 700.0,
		"vertical_range": 350.0,
		"requires_line_of_sight": true,
		"damage": 2,
		"burst_count": 1,
		"ammo_per_attack": 1,
		"magazine_capacity": 2,
		"starting_reserve_ammo": 3,
		"reload_seconds": 0.1,
		"recovery_seconds": 0.05,
		"alert_radius": 640.0,
	}


func _animation_groups(frame_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unused_direction in range(8):
		var frames: Array[Texture2D] = []
		for unused_frame in range(frame_count):
			frames.append(null)
		result.append(
			{
				"frames": frames,
				"anchor": Vector2.ZERO,
				"frame_hold_ticks": 1,
			}
		)
	return result


func _expect(value: bool, description: String, failures: Array[String]) -> void:
	check_count += 1
	if not value:
		failures.append(description)
