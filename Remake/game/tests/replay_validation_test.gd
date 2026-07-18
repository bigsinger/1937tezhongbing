extends SceneTree

const SNAPSHOT: Script = preload("res://scripts/runtime_state_snapshot.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const MISSION_RUNTIME: Script = preload("res://scripts/mission_runtime.gd")

const ANCHOR_KIND_BY_BINDING := {
	"explosion": "explosion_detector",
	"exit": "exit_detector",
	"high_ground": "exit_detector",
}

var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_canonical_snapshot_hashes(failures)
	_test_combat_replay(failures)
	_test_all_mission_replays_and_resets(failures)

	if failures.is_empty():
		print("Deterministic replay validation passed (%d checks)." % check_count)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_canonical_snapshot_hashes(failures: Array[String]) -> void:
	var first := {
		"mission": {"progress": {"b": 2, "a": 1}, "failure_id": ""},
		"combatants": [
			{"scene_index": 2, "position": Vector2(4.0, 8.0), "current_hit_points": 3},
			{"scene_index": 1, "position": Vector2(2.0, 6.0), "current_hit_points": 5},
		],
	}
	var reordered := {
		"combatants": [
			{"current_hit_points": 3, "position": Vector2(4.0, 8.0), "scene_index": 2},
			{"current_hit_points": 5, "position": Vector2(2.0, 6.0), "scene_index": 1},
		],
		"mission": {"failure_id": "", "progress": {"a": 1, "b": 2}},
	}
	var first_hash: String = SNAPSHOT.snapshot_hash(first)
	var reordered_hash: String = SNAPSHOT.snapshot_hash(reordered)
	_expect(
		first_hash.length() == 64,
		"snapshot hash is a lowercase SHA-256 digest",
		failures,
	)
	_expect(
		first_hash == reordered_hash,
		"dictionary insertion order cannot change the snapshot hash",
		failures,
	)
	(reordered["combatants"] as Array)[0]["current_hit_points"] = 2
	_expect(
		first_hash != SNAPSHOT.snapshot_hash(reordered),
		"a combat state mutation changes the snapshot hash",
		failures,
	)


func _test_combat_replay(failures: Array[String]) -> void:
	var events: Array[Dictionary] = [
		{"kind": "combat_fire", "attacker": 100, "target": 200, "damage": 2},
		{"kind": "combat_fire", "attacker": 100, "target": 200, "damage": 2},
		{"kind": "combat_reload", "unit": 100},
		{"kind": "combat_fire", "attacker": 100, "target": 200, "damage": 4},
	]
	var result: Dictionary = SNAPSHOT.verify_replay(
		events,
		Callable(self, "_make_combat_context"),
		Callable(self, "_apply_replay_event"),
		Callable(self, "_read_replay_snapshot"),
		Callable(self, "_dispose_replay_context"),
	)
	_expect(
		bool(result["is_deterministic"]),
		"the same combat command stream produces identical per-step hashes",
		failures,
	)
	_expect(
		(result["baseline_hashes"] as Array).size() == events.size() + 1,
		"combat replay hashes the initial state and every committed event",
		failures,
	)
	_expect(
		str(result["final_hash"]).length() == 64 and int(result["divergence_index"]) == -1,
		"combat replay reports a stable final digest with no divergence",
		failures,
	)

	var context := _make_combat_context()
	for event: Dictionary in events:
		_apply_replay_event(context, event)
	var attacker := _combatant_by_scene(context["combatants"] as Array, 100)
	var target := _combatant_by_scene(context["combatants"] as Array, 200)
	_expect(
		int(attacker["magazine_ammo"]) == 0 and int(attacker["reserve_ammo"]) == 0,
		"deterministic combat replay preserves exact magazine and reserve state",
		failures,
	)
	_expect(
		int(target["current_hit_points"]) == 0 and not bool(target["is_alive"]),
		"deterministic combat replay reaches the exact lethal state",
		failures,
	)


func _test_all_mission_replays_and_resets(failures: Array[String]) -> void:
	var catalog: Dictionary = MISSION_DATA.load_catalog()
	var missions := catalog.get("missions", []) as Array
	_expect(missions.size() == 12, "replay suite discovers all 12 mission graphs", failures)

	for raw_mission: Variant in missions:
		var mission := raw_mission as Dictionary
		var mission_id := str(mission.get("id", ""))
		var level := _build_mission_level_fixture(mission)
		var planning_context := _make_mission_context(mission, level)
		var events := _build_minimal_victory_events(
			mission, planning_context["runtime"] as Node
		)
		_dispose_replay_context(planning_context)
		var expected_event_count := _minimum_required_event_count(mission)
		_expect(
			events.size() == expected_event_count,
			"%s replay plan contains only required objectives and prerequisites" % mission_id,
			failures,
		)

		var replay_result: Dictionary = SNAPSHOT.verify_replay(
			events,
			Callable(self, "_make_mission_context").bind(mission, level),
			Callable(self, "_apply_replay_event"),
			Callable(self, "_read_replay_snapshot"),
			Callable(self, "_dispose_replay_context"),
		)
		_expect(
			bool(replay_result["is_deterministic"]),
			"%s repeats with identical initial, intermediate, and final hashes" % mission_id,
			failures,
		)
		_expect(
			(replay_result["baseline_hashes"] as Array).size() == events.size() + 1,
			"%s records a complete per-event hash chain" % mission_id,
			failures,
		)

		var failure_context := _make_mission_context(mission, level)
		var failure_error := _apply_replay_event(
			failure_context,
			{"kind": "world_event", "name": "required_character_lost", "payload": {}},
		)
		var failed_state := failure_context["state"] as RefCounted
		_expect(
			str(failure_error).is_empty()
			and bool(failed_state.call("is_failed"))
			and str(failed_state.get("failure_id")) == "required_character_lost",
			"%s enters its declared required-character failure state" % mission_id,
			failures,
		)
		if not events.is_empty():
			_apply_replay_event(failure_context, events[0])
		_expect(
			bool(failed_state.call("is_failed")) and not bool(failed_state.call("is_victory")),
			"%s terminal failure rejects later progress" % mission_id,
			failures,
		)
		_dispose_replay_context(failure_context)

		var reset_context := _make_mission_context(mission, level)
		var reset_state := reset_context["state"] as RefCounted
		_expect(
			not bool(reset_state.call("is_failed"))
			and str(reset_state.get("failure_id")).is_empty(),
			"%s fresh replay context clears the prior failure" % mission_id,
			failures,
		)
		for event: Dictionary in events:
			var event_error := _apply_replay_event(reset_context, event)
			if not str(event_error).is_empty():
				failures.append("%s reset replay event failed: %s" % [mission_id, event_error])
				break
		_expect(
			bool(reset_state.call("is_victory")) and not bool(reset_state.call("is_failed")),
			"%s minimal graph closes after failure reset" % mission_id,
			failures,
		)
		_dispose_replay_context(reset_context)


func _make_combat_context() -> Dictionary:
	return {
		"combatants": [
			{
				"scene_index": 100,
				"display_name": "attacker",
				"faction_id": 3,
				"position": Vector2.ZERO,
				"is_alive": true,
				"current_hit_points": 8,
				"maximum_hit_points": 8,
				"combat_action": 0,
				"action_frame_index": 0,
				"action_finished": true,
				"magazine_ammo": 2,
				"reserve_ammo": 1,
			},
			{
				"scene_index": 200,
				"display_name": "target",
				"faction_id": 1,
				"position": Vector2(96.0, 0.0),
				"is_alive": true,
				"current_hit_points": 8,
				"maximum_hit_points": 8,
				"combat_action": 0,
				"action_frame_index": 0,
				"action_finished": true,
				"magazine_ammo": 0,
				"reserve_ammo": 0,
			},
		],
		"state": null,
		"runtime": null,
	}


func _make_mission_context(mission: Dictionary, level: Dictionary) -> Dictionary:
	var state = MISSION_STATE.new(mission)
	var runtime = MISSION_RUNTIME.new()
	if not runtime.configure(mission, level, state):
		push_error("cannot configure %s replay fixture: %s" % [mission.get("id", ""), runtime.last_error])
	return {"combatants": [], "state": state, "runtime": runtime}


func _apply_replay_event(context: Dictionary, raw_event: Variant) -> String:
	if not raw_event is Dictionary:
		return "event must be a dictionary"
	var event := raw_event as Dictionary
	match str(event.get("kind", "")):
		"world_event":
			var runtime := context.get("runtime") as Node
			if runtime == null:
				return "world event has no mission runtime"
			runtime.call(
				"publish_world_event",
				str(event.get("name", "")),
				(event.get("payload", {}) as Dictionary).duplicate(true),
			)
			return str(runtime.get("last_error"))
		"advance_time":
			var runtime := context.get("runtime") as Node
			if runtime == null:
				return "time event has no mission runtime"
			runtime.call("advance_time", float(event.get("delta_seconds", 0.0)))
			return str(runtime.get("last_error"))
		"combat_fire":
			return _apply_combat_fire(context, event)
		"combat_reload":
			return _apply_combat_reload(context, event)
	return "unsupported replay event kind: %s" % str(event.get("kind", ""))


func _read_replay_snapshot(context: Dictionary, replay_cursor: int) -> Dictionary:
	return SNAPSHOT.capture(
		context.get("combatants", []) as Array,
		context.get("state") as RefCounted,
		context.get("runtime") as Node,
		replay_cursor,
	)


func _dispose_replay_context(context: Dictionary) -> void:
	var runtime := context.get("runtime") as Node
	if runtime != null:
		runtime.free()


func _apply_combat_fire(context: Dictionary, event: Dictionary) -> String:
	var combatants := context.get("combatants", []) as Array
	var attacker := _combatant_by_scene(combatants, int(event.get("attacker", -1)))
	var target := _combatant_by_scene(combatants, int(event.get("target", -1)))
	if attacker.is_empty() or target.is_empty():
		return "combat fire references an unknown unit"
	if not bool(attacker.get("is_alive", false)) or not bool(target.get("is_alive", false)):
		return "combat fire references a dead unit"
	if int(attacker.get("magazine_ammo", 0)) <= 0:
		return "combat fire has no magazine ammunition"
	attacker["magazine_ammo"] = int(attacker["magazine_ammo"]) - 1
	attacker["combat_action"] = 1
	attacker["action_frame_index"] = 2
	attacker["action_finished"] = true
	var damage := maxi(0, int(event.get("damage", 0)))
	var remaining := maxi(0, int(target["current_hit_points"]) - damage)
	target["current_hit_points"] = remaining
	if remaining == 0:
		target["is_alive"] = false
		target["combat_action"] = 3
		target["action_frame_index"] = 2
		target["action_finished"] = true
	return ""


func _apply_combat_reload(context: Dictionary, event: Dictionary) -> String:
	var unit := _combatant_by_scene(
		context.get("combatants", []) as Array, int(event.get("unit", -1))
	)
	if unit.is_empty() or not bool(unit.get("is_alive", false)):
		return "combat reload references an unknown or dead unit"
	var magazine := int(unit.get("magazine_ammo", 0))
	var reserve := int(unit.get("reserve_ammo", 0))
	var transfer := mini(2 - magazine, reserve)
	unit["magazine_ammo"] = magazine + transfer
	unit["reserve_ammo"] = reserve - transfer
	unit["combat_action"] = 2
	unit["action_frame_index"] = 0
	unit["action_finished"] = true
	return ""


func _combatant_by_scene(combatants: Array, scene_index: int) -> Dictionary:
	for raw_combatant: Variant in combatants:
		if raw_combatant is Dictionary and int(raw_combatant.get("scene_index", -1)) == scene_index:
			return raw_combatant as Dictionary
	return {}


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
			if ANCHOR_KIND_BY_BINDING.has(binding_kind):
				task_anchors.append(
					{
						"scene_index": scene_index,
						"kind": str(ANCHOR_KIND_BY_BINDING[binding_kind]),
					}
				)
			else:
				entities.append(
					{
						"scene_index": scene_index,
						"display_name": "%s replay fixture" % binding_kind,
					}
				)
	return {"entities": entities, "task_anchors": task_anchors}


func _build_minimal_victory_events(mission: Dictionary, runtime: Node) -> Array[Dictionary]:
	var objectives := mission.get("objectives", []) as Array
	var needed_ids := _required_objective_closure(objectives)
	var completed_ids: Dictionary = {}
	var scene_cursors: Dictionary = {}
	var result: Array[Dictionary] = []
	var made_progress := true
	while completed_ids.size() < needed_ids.size() and made_progress:
		made_progress = false
		for raw_objective: Variant in objectives:
			var objective := raw_objective as Dictionary
			var objective_id := str(objective.get("id", ""))
			if not needed_ids.has(objective_id) or completed_ids.has(objective_id):
				continue
			var dependencies_ready := true
			for dependency: Variant in objective.get("depends_on", []) as Array:
				if not completed_ids.has(str(dependency)):
					dependencies_ready = false
					break
			if not dependencies_ready:
				continue
			var condition := objective.get("condition", {}) as Dictionary
			var required_count := int(condition.get("required_count", 1))
			for _count: int in range(required_count):
				var payload := (condition.get("where", {}) as Dictionary).duplicate(true) as Dictionary
				var scene_index := _scene_for_objective_event(
					mission,
					runtime,
					objective_id,
					str(condition.get("event", "")),
					payload,
					scene_cursors,
				)
				if scene_index >= 0:
					var event_name := str(condition.get("event", ""))
					if event_name == "party_at_trigger":
						payload["trigger_scene_index"] = scene_index
					elif event_name == "item_acquired" and payload.has("item_role"):
						payload["source_scene_index"] = scene_index
					else:
						payload["scene_index"] = scene_index
				result.append(
					{
						"kind": "world_event",
						"name": str(condition.get("event", "")),
						"payload": payload,
					}
				)
			completed_ids[objective_id] = true
			made_progress = true
	return result


func _required_objective_closure(objectives: Array) -> Dictionary:
	var by_id: Dictionary = {}
	var needed: Dictionary = {}
	for raw_objective: Variant in objectives:
		var objective := raw_objective as Dictionary
		by_id[str(objective.get("id", ""))] = objective
		if bool(objective.get("required", false)):
			needed[str(objective.get("id", ""))] = true
	var changed := true
	while changed:
		changed = false
		for objective_id: Variant in needed.keys():
			var objective := by_id.get(str(objective_id), {}) as Dictionary
			for dependency: Variant in objective.get("depends_on", []) as Array:
				var dependency_id := str(dependency)
				if not needed.has(dependency_id):
					needed[dependency_id] = true
					changed = true
	return needed


func _minimum_required_event_count(mission: Dictionary) -> int:
	var objectives := mission.get("objectives", []) as Array
	var needed := _required_objective_closure(objectives)
	var total := 0
	for raw_objective: Variant in objectives:
		var objective := raw_objective as Dictionary
		if needed.has(str(objective.get("id", ""))):
			total += int((objective.get("condition", {}) as Dictionary).get("required_count", 1))
	return total


func _scene_for_objective_event(
	mission: Dictionary,
	runtime: Node,
	objective_id: String,
	event_name: String,
	payload: Dictionary,
	scene_cursors: Dictionary,
) -> int:
	var scene_bindings := mission.get("scene_bindings", {}) as Dictionary
	match event_name:
		"entity_rescued":
			if payload.has("family_role"):
				return _next_bound_scene(runtime, ["father", "mother"], "family", scene_cursors)
			if objective_id.contains("reporter") and scene_bindings.has("reporter"):
				return _next_bound_scene(runtime, ["reporter"], "reporter", scene_cursors)
			if scene_bindings.has("driver"):
				return _next_bound_scene(runtime, ["driver"], "driver", scene_cursors)
			return _next_bound_scene(runtime, ["rescued"], "rescued", scene_cursors)
		"item_acquired":
			if payload.has("item_name"):
				var pickups := mission.get("pickup_bindings", {}) as Dictionary
				for raw_binding: Variant in pickups.keys():
					var pickup := pickups[raw_binding] as Dictionary
					if str(pickup.get("item_name", "")) == str(payload["item_name"]):
						return _next_bound_scene(
							runtime,
							[str(raw_binding)],
							"item-name:%s" % str(payload["item_name"]),
							scene_cursors,
						)
			if payload.has("item_role"):
				var drops := mission.get("role_drops", {}) as Dictionary
				for raw_role: Variant in drops.keys():
					var drop := drops[raw_role] as Dictionary
					if str(drop.get("item_role", "")) == str(payload["item_role"]):
						return _next_bound_scene(
							runtime,
							[str(raw_role)],
							"item-role:%s" % str(payload["item_role"]),
							scene_cursors,
						)
		"role_eliminated", "story_anchor_reached":
			var role_id := str(payload.get("role_id", ""))
			return _next_bound_scene(runtime, [role_id], event_name + ":" + role_id, scene_cursors)
		"trigger_activated":
			if objective_id.contains("capture") and scene_bindings.has("high_ground"):
				return _next_bound_scene(runtime, ["high_ground"], "high-ground", scene_cursors)
			if (
				objective_id.contains("destroy")
				or objective_id.contains("place_")
			) and scene_bindings.has("explosion"):
				return _next_bound_scene(runtime, ["explosion"], "explosion", scene_cursors)
			return _next_bound_scene(runtime, ["exit"], "exit", scene_cursors)
		"party_at_trigger":
			if payload.has("trigger_scene_index"):
				return int(payload["trigger_scene_index"])
			return _next_bound_scene(runtime, ["exit"], "party-at-exit", scene_cursors)
	return -1


func _next_bound_scene(
	runtime: Node,
	binding_kinds: Array[String],
	cursor_key: String,
	scene_cursors: Dictionary,
) -> int:
	var candidates: Array[int] = []
	for binding_kind: String in binding_kinds:
		for scene_index: int in runtime.call("bound_scenes", binding_kind) as Array[int]:
			if not candidates.has(scene_index):
				candidates.append(scene_index)
	var cursor := int(scene_cursors.get(cursor_key, 0))
	if cursor < 0 or cursor >= candidates.size():
		return -1
	scene_cursors[cursor_key] = cursor + 1
	return candidates[cursor]


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
