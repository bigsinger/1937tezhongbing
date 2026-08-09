extends SceneTree

const COORDINATOR := preload("res://scripts/simulation_coordinator.gd")
const MISSION_STATE := preload("res://scripts/mission_state.gd")
const DIRECTION_RUNTIME := preload("res://scripts/mission_direction_runtime.gd")
const AI_COORDINATOR := preload("res://scripts/mission_ai_coordinator.gd")
const SAVE_STORE := preload("res://scripts/game_save_store.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_product_timer_render_independence()
	_test_tick_snapshot_round_trip()
	_test_save_schema_migration()
	if failures.is_empty():
		print("Fixed-tick persistence tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_product_timer_render_independence() -> void:
	var final_states: Array[Dictionary] = []
	for render_rate: int in [30, 60, 120, 240]:
		var coordinator = COORDINATOR.new()
		var mission = MISSION_STATE.new(_mission_definition())
		var direction = DIRECTION_RUNTIME.new()
		_expect(direction.configure_for_mission("m000"), "direction fixture configures")
		var ai = AI_COORDINATOR.new()
		_expect(
			ai.configure(
				{
					"source_status": "remake_editorial",
					"reinforcement_budget": 0,
				},
				{
					"source_status": "remake_editorial",
					"reinforcement_trigger": "none",
					"tags": [],
				},
				[],
			),
			"AI timer fixture configures",
		)
		coordinator.register_system(
			"mission_state",
			"mission_state",
			func(_tick: int, _fixed_delta: float) -> void:
				mission.advance_ticks(1),
		)
		coordinator.register_system(
			"mission_direction",
			"mission_state",
			func(_tick: int, _fixed_delta: float) -> void:
				direction.advance_ticks(1),
		)
		coordinator.register_system(
			"mission_ai",
			"perception",
			func(tick: int, _fixed_delta: float) -> void:
				ai.advance_to_tick(tick),
		)
		for _frame: int in range(render_rate * 2):
			coordinator.advance_time(1.0 / float(render_rate))
		final_states.append({
			"simulation_tick": coordinator.clock.tick,
			"mission_ticks": mission.elapsed_ticks,
			"direction_ticks": direction.elapsed_ticks,
			"ai_tick": ai.simulation_tick,
			"mission_failed": mission.is_failed(),
		})
		direction.free()
		ai.free()
	_expect(
		final_states.all(
			func(state: Dictionary) -> bool: return state == final_states[0]
		),
		"mission, direction and AI timers are identical at 30/60/120/unlimited-like rendering",
	)
	_expect(
		final_states[0] == {
			"simulation_tick": 120,
			"mission_ticks": 120,
			"direction_ticks": 120,
			"ai_tick": 120,
			"mission_failed": false,
		},
		"two seconds advances every authoritative product timer by exactly 120 ticks",
	)


func _test_tick_snapshot_round_trip() -> void:
	var direction = DIRECTION_RUNTIME.new()
	_expect(direction.configure_for_mission("m000"), "direction snapshot fixture configures")
	direction.advance_ticks(137)
	var direction_snapshot := direction.capture_state() as Dictionary
	var restored_direction = DIRECTION_RUNTIME.new()
	_expect(
		restored_direction.configure_for_mission("m000")
			and restored_direction.restore_state(direction_snapshot)
			and restored_direction.capture_state() == direction_snapshot,
		"direction elapsed ticks survive an exact snapshot round trip",
	)
	direction.free()
	restored_direction.free()
	var ai = AI_COORDINATOR.new()
	var difficulty := {
		"source_status": "remake_editorial",
		"reinforcement_budget": 0,
	}
	var cooperation := {
		"source_status": "remake_editorial",
		"reinforcement_trigger": "none",
		"tags": [],
	}
	_expect(ai.configure(difficulty, cooperation, []), "AI snapshot fixture configures")
	ai.advance_to_tick(137)
	var ai_snapshot := ai.capture_state() as Dictionary
	var restored_ai = AI_COORDINATOR.new()
	_expect(
		restored_ai.configure(difficulty, cooperation, [])
			and restored_ai.restore_state(ai_snapshot)
			and restored_ai.capture_state() == ai_snapshot,
		"AI blackboard clock and pending timing survive an exact snapshot round trip",
	)
	ai.free()
	restored_ai.free()


func _test_save_schema_migration() -> void:
	var save_root := "user://fixed-tick-persistence-%d" % OS.get_process_id()
	var store = SAVE_STORE.new(save_root)
	var session: Dictionary = SAVE_STORE.empty_session("m004")
	session["elapsed_seconds"] = 73.0 / 60.0
	(session["mission"] as Dictionary)["elapsed_ticks"] = 73
	var saved := store.save_slot("slot_1", session)
	var loaded := store.load_slot("slot_1") as Dictionary
	var loaded_session := (
		(loaded.get("data", {}) as Dictionary).get("session", {}) as Dictionary
	)
	var loaded_mission := loaded_session.get("mission", {}) as Dictionary
	_expect(
		bool(saved.get("ok", false))
			and bool(loaded.get("ok", false))
			and int(loaded_mission.get("elapsed_ticks", -1)) == 73,
		"schema-4 save/load preserves authoritative mission ticks",
	)
	var old_session: Dictionary = SAVE_STORE.empty_session("m004")
	old_session["elapsed_seconds"] = 2.25
	(old_session["mission"] as Dictionary).erase("elapsed_ticks")
	var old_document := {
		"schema_version": 3,
		"game_id": SAVE_STORE.GAME_ID,
		"slot_id": "slot_2",
		"revision": 1,
		"saved_at_unix": 0,
		"campaign": SAVE_STORE.default_campaign(),
		"session": old_session,
	}
	var migrated := store.call("_migrate_document", old_document, "slot_2") as Dictionary
	var migrated_session := migrated.get("session", {}) as Dictionary
	var migrated_mission := migrated_session.get("mission", {}) as Dictionary
	_expect(
		int(migrated.get("schema_version", 0)) == SAVE_STORE.SCHEMA_VERSION
			and int(migrated_mission.get("elapsed_ticks", -1)) == 135
			and bool(store.call("_is_current_document", migrated)),
		"schema-3 saves migrate elapsed seconds forward to exact 60-Hz ticks",
	)


func _mission_definition() -> Dictionary:
	return {
		"id": "fixed_tick_fixture",
		"time_limit_seconds": 3.0,
		"objectives": [{
			"id": "hold",
			"label": "hold",
			"required": true,
			"condition": {
				"event": "fixture_complete",
				"required_count": 1,
			},
			"depends_on": [],
		}],
		"failure_conditions": [{
			"id": "timeout",
			"event": "time_expired",
		}],
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
