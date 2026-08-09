extends SceneTree

const TACTICAL_QUEUE := preload("res://scripts/tactical_command_queue.gd")
const COMMAND_REPLAY := preload("res://scripts/command_replay.gd")
const REPLAY_RUNNER := preload("res://scripts/command_replay_runner.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_complete_tactical_queue_contract()
	_test_product_command_replay_contract()
	if failures.is_empty():
		print("Tactical planning and product replay tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_complete_tactical_queue_contract() -> void:
	var queue = TACTICAL_QUEUE.new()
	_expect(queue.begin_planning(), "modern tactical planning enters an explicit paused plan state")
	var kinds: Array[String] = [
		"move", "stance", "attack", "force_attack", "pickup", "open_door",
		"drop_lure", "bury", "special_item", "wait",
	]
	for index: int in range(kinds.size()):
		var result := queue.enqueue(
			1,
			kinds[index],
			{"ordinal": index},
			3 if kinds[index] == "wait" else 1,
			{"actor_alive": true},
			30,
			"wait" if kinds[index] in ["move", "pickup", "bury"] else "skip",
		) as Dictionary
		_expect(bool(result.get("accepted", false)), "queue accepts tactical action %s" % kinds[index])
	var released := queue.release_payload() as Dictionary
	_expect(
		not queue.planning_active and queue.activate_released_plan(released, 10),
		"all actors release their ordered queues onto the same simulation boundary",
	)
	var executed: Array[String] = []
	var executor := func(command: Dictionary) -> Dictionary:
		executed.append(str(command.get("kind", "")))
		return {"accepted": true, "complete": true}
	var complete := func(_command: Dictionary) -> Dictionary: return {"accepted": true}
	var precondition := func(_command: Dictionary) -> Dictionary: return {"accepted": true}
	for tick: int in range(11, 20):
		queue.advance_tick(tick, executor, complete, precondition)
		if tick == 18:
			break
	var state_before_save := queue.capture_state() as Dictionary
	var restored = TACTICAL_QUEUE.new()
	_expect(
		restored.restore_state(state_before_save)
			and restored.capture_state() == state_before_save,
		"queue cursor, sequence, wait remainder, timeout and failure policy survive save/load exactly",
	)
	for tick: int in range(19, 28):
		restored.advance_tick(tick, executor, complete, precondition)
	_expect(
		int((restored.snapshot() as Dictionary).get("runtime_count", -1)) == 0
			and executed.slice(0, 9) == kinds.slice(0, 9),
		"move, stance, combat, pickup, door, lure, burial, item and timed wait complete in sequence",
	)


func _test_product_command_replay_contract() -> void:
	var header := {
		"runtime_version": "2.0.0-test",
		"ruleset_mode": "modern",
		"difficulty_mode": "normal",
		"content_identity": "synthetic-content-sha256",
		"initial_checkpoint": "fixture-checkpoint",
		"initial_tick": 0,
		"random_state": 12345,
	}
	var recorder = COMMAND_REPLAY.new()
	_expect(recorder.begin(header), "replay recording binds checkpoint, rules, difficulty, content and RNG state")
	var model := _initial_replay_model()
	recorder.record_hash(0, model)
	var command_specs: Array[Dictionary] = [
		{"tick": 1, "name": "release_tactical_plan", "payload": {"actors": [1, 2]}},
		{"tick": 2, "name": "move", "actor_id": 1, "payload": {"x": 64.0, "y": 32.0}},
		{"tick": 3, "name": "open_door", "actor_id": 1, "payload": {"door": 70}},
		{"tick": 4, "name": "pickup", "actor_id": 1, "payload": {"pickup": 80, "item": "documents"}},
		{"tick": 5, "name": "attack", "actor_id": 1, "payload": {"target": 2, "damage": 8}},
		{"tick": 6, "name": "mission_event", "payload": {"event": "item_acquired"}},
	]
	for index: int in range(command_specs.size()):
		var spec := command_specs[index]
		recorder.observe_scheduled({
			"sequence": index + 1,
			"execute_tick": int(spec["tick"]),
			"actor_id": int(spec.get("actor_id", -1)),
			"name": str(spec["name"]),
			"source": "viewport-logical-command",
			"payload": spec.get("payload", {}),
			"precondition": {},
			"timeout_tick": 120,
			"failure_policy": "skip",
		})
		_apply_replay_model_command(model, recorder.commands[-1])
		model["tick"] = int(spec["tick"])
		recorder.record_hash(int(spec["tick"]), model)
	var document := recorder.finish() as Dictionary
	var playback_model := _initial_replay_model()
	var runner = REPLAY_RUNNER.new()
	var playback := runner.play(
		document,
		header,
		func(_replay_header: Dictionary) -> bool:
			playback_model = _initial_replay_model()
			return true,
		func(command: Dictionary) -> bool:
			return _apply_replay_model_command(playback_model, command),
		func(tick: int) -> bool:
			playback_model["tick"] = tick
			return true,
		func(_tick: int) -> Dictionary: return playback_model.duplicate(true),
	) as Dictionary
	_expect(
		bool(playback.get("ok", false))
			and int(playback.get("commands_replayed", 0)) == command_specs.size()
			and int(playback.get("hashes_verified", 0)) == command_specs.size() + 1,
		"headless replay reproduces tactical release, movement, door, pickup, combat and mission events without divergence",
	)

	var mismatched_header := header.duplicate(true)
	mismatched_header["content_identity"] = "other-content"
	var refused := runner.play(
		document,
		mismatched_header,
		func(_header: Dictionary) -> bool: return true,
		func(_command: Dictionary) -> bool: return true,
		func(_tick: int) -> bool: return true,
		func(_tick: int) -> Dictionary: return {},
	) as Dictionary
	_expect(
		not bool(refused.get("ok", true))
			and str(refused.get("reason", "")) == "content_identity_mismatch",
		"replay refuses incompatible content before restoring or executing commands",
	)

	var divergent_model := _initial_replay_model()
	var divergence := runner.play(
		document,
		header,
		func(_header: Dictionary) -> bool:
			divergent_model = _initial_replay_model()
			return true,
		func(command: Dictionary) -> bool:
			var accepted := _apply_replay_model_command(divergent_model, command)
			if str(command.get("name", "")) == "attack":
				(divergent_model["actors"] as Dictionary)["2"]["hp"] = 1
			return accepted,
		func(tick: int) -> bool:
			divergent_model["tick"] = tick
			return true,
		func(_tick: int) -> Dictionary: return divergent_model.duplicate(true),
	) as Dictionary
	var detail := divergence.get("divergence", {}) as Dictionary
	_expect(
		str(divergence.get("reason", "")) == "state_divergence"
			and str(detail.get("field", "")).contains("actors.2.hp")
			and not (detail.get("recent_commands", []) as Array).is_empty(),
		"first divergence identifies the system/actor field and bounded recent logical commands",
	)


func _initial_replay_model() -> Dictionary:
	return {
		"tick": 0,
		"tactical": {"released": false},
		"actors": {
			"1": {"x": 0.0, "y": 0.0, "hp": 8, "inventory": []},
			"2": {"x": 96.0, "y": 32.0, "hp": 8, "inventory": []},
		},
		"doors": {"70": false},
		"pickups": {"80": true},
		"mission": {"progress": 0},
	}


func _apply_replay_model_command(model: Dictionary, command: Dictionary) -> bool:
	var payload := command.get("payload", {}) as Dictionary
	match str(command.get("name", "")):
		"release_tactical_plan":
			(model["tactical"] as Dictionary)["released"] = true
		"move":
			var actor := (model["actors"] as Dictionary)[str(command.get("actor_id", 1))] as Dictionary
			actor["x"] = float(payload.get("x", 0.0))
			actor["y"] = float(payload.get("y", 0.0))
		"open_door":
			(model["doors"] as Dictionary)[str(payload.get("door", 70))] = true
		"pickup":
			(model["pickups"] as Dictionary)[str(payload.get("pickup", 80))] = false
			((model["actors"] as Dictionary)["1"] as Dictionary)["inventory"].append(str(payload.get("item", "")))
		"attack":
			var target := (model["actors"] as Dictionary)[str(payload.get("target", 2))] as Dictionary
			target["hp"] = maxi(int(target["hp"]) - int(payload.get("damage", 0)), 0)
		"mission_event":
			(model["mission"] as Dictionary)["progress"] = int((model["mission"] as Dictionary)["progress"]) + 1
		_:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
