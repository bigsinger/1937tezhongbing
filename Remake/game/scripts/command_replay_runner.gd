class_name CommandReplayRunner
extends RefCounted

const REPLAY_SCRIPT := preload("res://scripts/command_replay.gd")


func play(
	document: Dictionary,
	active_header: Dictionary,
	restore_initial: Callable,
	submit_command: Callable,
	advance_tick: Callable,
	state_reader: Callable,
) -> Dictionary:
	var replay = REPLAY_SCRIPT.new()
	var validation := replay.validate_for_playback(document, active_header) as Dictionary
	if not bool(validation.get("ok", false)):
		return {"ok": false, "reason": validation.get("reason", "invalid_replay")}
	if (
		not restore_initial.is_valid()
		or not submit_command.is_valid()
		or not advance_tick.is_valid()
		or not state_reader.is_valid()
	):
		return {"ok": false, "reason": "invalid_callbacks"}
	if not bool(restore_initial.call((document.get("header", {}) as Dictionary).duplicate(true))):
		return {"ok": false, "reason": "initial_checkpoint_rejected"}

	var commands := (document.get("commands", []) as Array).duplicate(true)
	commands.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_tick := int(left.get("execute_tick", 0))
			var right_tick := int(right.get("execute_tick", 0))
			if left_tick != right_tick:
				return left_tick < right_tick
			return int(left.get("record_order", 0)) < int(right.get("record_order", 0))
	)
	var expected_hashes := (document.get("hashes", []) as Array).duplicate(true)
	var command_index := 0
	var hash_index := 0
	var current_tick := int((document.get("header", {}) as Dictionary).get("initial_tick", 0))
	var maximum_tick := current_tick
	if not commands.is_empty():
		maximum_tick = maxi(maximum_tick, int((commands[-1] as Dictionary).get("execute_tick", 0)))
	if not expected_hashes.is_empty():
		maximum_tick = maxi(maximum_tick, int((expected_hashes[-1] as Dictionary).get("tick", 0)))
	var actual_hashes: Array[Dictionary] = []
	while current_tick <= maximum_tick:
		while (
			command_index < commands.size()
			and int((commands[command_index] as Dictionary).get("execute_tick", -1)) == current_tick
		):
			var accepted: Variant = submit_command.call((commands[command_index] as Dictionary).duplicate(true))
			if not _accepted(accepted):
				return {
					"ok": false,
					"reason": "command_rejected",
					"command_index": command_index,
					"command": commands[command_index],
				}
			command_index += 1
		if current_tick > int((document.get("header", {}) as Dictionary).get("initial_tick", 0)):
			if not _accepted(advance_tick.call(current_tick)):
				return {"ok": false, "reason": "tick_rejected", "tick": current_tick}
		while (
			hash_index < expected_hashes.size()
			and int((expected_hashes[hash_index] as Dictionary).get("tick", -1)) == current_tick
		):
			var actual_state: Variant = state_reader.call(current_tick)
			var actual := {
				"tick": current_tick,
				"sha256": REPLAY_SCRIPT.state_hash(actual_state),
				"fingerprints": REPLAY_SCRIPT.state_fingerprints(actual_state),
			}
			actual_hashes.append(actual)
			var expected := expected_hashes[hash_index] as Dictionary
			if str(actual["sha256"]) != str(expected.get("sha256", "")):
				replay.commands = commands.duplicate(true)
				var divergence := replay.first_hash_divergence([expected], [actual])
				return {
					"ok": false,
					"reason": "state_divergence",
					"tick": current_tick,
					"divergence": divergence,
				}
			hash_index += 1
		current_tick += 1
	return {
		"ok": command_index == commands.size() and hash_index == expected_hashes.size(),
		"commands_replayed": command_index,
		"hashes_verified": hash_index,
		"final_tick": maximum_tick,
	}


func _accepted(value: Variant) -> bool:
	if value is Dictionary:
		return bool((value as Dictionary).get("accepted", (value as Dictionary).get("ok", false)))
	return bool(value)
