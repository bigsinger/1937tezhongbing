extends SceneTree

const CLOCK := preload("res://scripts/simulation_clock.gd")
const COORDINATOR := preload("res://scripts/simulation_coordinator.gd")
const RING_BUFFER := preload("res://scripts/int_ring_buffer.gd")
const PERFORMANCE_MONITOR := preload(
	"res://scripts/runtime_performance_monitor.gd"
)
const RUNTIME_FRAME_CLASSIFIER := preload(
	"res://scripts/runtime_frame_classifier.gd"
)
const SPATIAL_INDEX := preload("res://scripts/world_spatial_index.gd")
const MOVEMENT_RESERVATIONS := preload(
	"res://scripts/movement_reservation_service.gd"
)
const WORLD_INTERACTIONS := preload("res://scripts/world_interaction_controller.gd")
const BURIAL_COMMANDS := preload("res://scripts/burial_command_controller.gd")
const CAMERA_INPUT := preload("res://scripts/camera_input_controller.gd")
const ACTOR_MOVEMENT := preload("res://scripts/actor_movement_controller.gd")
const ACTOR_ANIMATION := preload("res://scripts/actor_animation_controller.gd")
const ACTOR_COMBAT := preload("res://scripts/actor_combat_controller.gd")
const ACTOR_INVENTORY := preload("res://scripts/actor_inventory_controller.gd")
const ACTOR_AUDIO := preload("res://scripts/actor_audio_presenter.gd")
const CLASSIC_PARITY := preload("res://scripts/classic_actor_parity_adapter.gd")
const PRESENTATION_ROUTER := preload("res://scripts/presentation_event_router.gd")
const ENEMY_PERCEPTION := preload("res://scripts/enemy_perception_controller.gd")
const ENEMY_SEARCH := preload("res://scripts/enemy_search_controller.gd")
const ENEMY_DUTY := preload("res://scripts/enemy_duty_controller.gd")
const STEALTH_RISK_FIELD := preload("res://scripts/stealth_risk_field.gd")
const CLASSIC_ENEMY_STRATEGY := preload("res://scripts/classic_enemy_strategy.gd")
const SAVE_GAME_CONTROLLER := preload("res://scripts/save_game_controller.gd")
const AMBIENT_UNIT := preload("res://scripts/ambient_unit.gd")
const SQUAD_UNIT := preload("res://scripts/squad_unit.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

class FakeActor extends Node2D:
	var is_alive := true
	var scene_index := -1

class FakeSaveStore extends RefCounted:
	var summaries: Array[Dictionary] = []
	var loads: Dictionary = {}

	func list_slots() -> Array[Dictionary]:
		return summaries.duplicate(true)

	func load_slot(slot_id: String) -> Dictionary:
		return (loads.get(slot_id, {"ok": false, "code": "missing"}) as Dictionary).duplicate(true)

class FakeParityActor extends RefCounted:
	var original_runtime_index := 7
	var original_native_actor_state := {"facing": 3}
	var original_command_goal_kind_latch := 4
	var original_first_gameplay_movement_path_state := 2
	var original_first_gameplay_movement_mode := 1

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_clock_render_rate_independence()
	_test_phase_and_command_order()
	_test_pause_and_restore()
	_test_o1_performance_monitoring()
	_test_event_driven_spatial_index()
	_test_movement_reservation_fairness()
	_test_composed_runtime_controllers()
	_test_modern_ambient_scheduler_boundary()
	_test_modern_continuous_audio_cadence()
	_test_recurring_evidence_hint_refresh()
	_test_stealth_feedback_contract()
	_test_checkpoint_fallback_contract()
	if failures.is_empty():
		print("Modernization round-two tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_clock_render_rate_independence() -> void:
	var final_states: Array[Dictionary] = []
	for render_rate: int in [30, 60, 120, 240]:
		var coordinator = COORDINATOR.new()
		var model := {"value": 0, "tick_sum": 0}
		coordinator.register_system(
			"fixture",
			"movement",
			func(tick: int, _delta: float) -> void:
				model["value"] = int(model["value"]) + 3
				model["tick_sum"] = int(model["tick_sum"]) + tick,
		)
		for _frame: int in range(render_rate * 2):
			coordinator.advance_time(1.0 / float(render_rate))
		final_states.append({
			"tick": coordinator.clock.tick,
			"value": int(model["value"]),
			"tick_sum": int(model["tick_sum"]),
		})
	_expect(
		final_states.all(func(state: Dictionary) -> bool: return state == final_states[0]),
		"30/60/120/unlimited-like render feeds produce an identical 120-tick state",
	)
	_expect(
		int(final_states[0]["tick"]) == 120
			and int(final_states[0]["value"]) == 360,
		"the fixed clock advances exactly 60 simulation ticks per second",
	)


func _test_phase_and_command_order() -> void:
	var coordinator = COORDINATOR.new()
	var observed: Array[String] = []
	coordinator.register_command_handler(
		"move",
		func(payload: Dictionary, command: Dictionary) -> bool:
			observed.append("command:%d:%s" % [
				int(command["sequence"]),
				str(payload["id"]),
			])
			return true,
	)
	for phase: String in COORDINATOR.PHASE_ORDER:
		if phase == COORDINATOR.PHASE_COMMANDS:
			continue
		coordinator.register_system(
			"fixture_%s" % phase,
			phase,
			func(tick: int, _delta: float, captured_phase: String = phase) -> void:
				observed.append("%s:%d" % [captured_phase, tick]),
		)
	coordinator.schedule_command("move", {"id": "first"})
	coordinator.schedule_command("move", {"id": "second"})
	coordinator.advance_exact_ticks(1)
	_expect(
		observed.slice(0, 2) == ["command:1:first", "command:2:second"],
		"same-tick commands execute in stable sequence order",
	)
	var expected_phases: Array[String] = []
	for phase: String in COORDINATOR.PHASE_ORDER:
		if phase != COORDINATOR.PHASE_COMMANDS:
			expected_phases.append("%s:1" % phase)
	_expect(
		observed.slice(2) == expected_phases,
		"simulation systems execute in the documented deterministic phase order",
	)


func _test_pause_and_restore() -> void:
	var coordinator = COORDINATOR.new()
	coordinator.advance_exact_ticks(7)
	coordinator.schedule_command(
		"wait",
		{"duration_ticks": 12},
		"test",
		4,
		2,
	)
	coordinator.set_paused(true)
	coordinator.advance_time(10.0)
	_expect(
		coordinator.clock.tick == 7,
		"paused wall-clock time does not advance gameplay",
	)
	var saved: Dictionary = coordinator.capture_state()
	var restored = COORDINATOR.new()
	_expect(restored.restore_state(saved), "simulation clock and pending commands restore")
	_expect(
		restored.capture_state() == saved,
		"restored next-tick scheduling state is byte-structurally identical",
	)
	restored.set_paused(false)
	restored.advance_exact_ticks(2)
	_expect(
		restored.clock.tick == 9
			and (restored.command_log() as Array).size() == 1,
		"a restored pending command executes on its original tick",
	)


func _test_o1_performance_monitoring() -> void:
	var ring = RING_BUFFER.new(4)
	for value: int in range(10):
		ring.append(value)
	_expect(
		ring.values() == PackedInt64Array([6, 7, 8, 9]),
		"fixed-capacity ring overwrites old samples without head removal",
	)
	var monitor = PERFORMANCE_MONITOR.new(60, 32)
	monitor.begin_section("navigation_reservation")
	monitor.end_section("navigation_reservation", {"queue": 4})
	monitor.record_event("synthetic_stall", 30_000, {"system": "fixture"})
	monitor.record_present_interval(31_000)
	var snapshot: Dictionary = monitor.snapshot()
	_expect(
		int((snapshot["present"] as Dictionary)["sample_count"]) == 1
			and int(((snapshot["sections"] as Dictionary)[
				"navigation_reservation"
			] as Dictionary)["sample_count"]) == 1,
		"monitor separates presentation intervals from subsystem CPU samples",
	)
	var long_frames := snapshot["long_frames"] as Array
	_expect(
		long_frames.size() == 1
			and str((long_frames[0] as Dictionary)["responsible_system"])
				== "synthetic_stall",
		"a synthetic long frame freezes attribution and nearby counters",
	)
	# Warm the exact begin/end-frame path whose cost is reported.  Keeping the
	# functional snapshot above separate preserves its one-sample assertions.
	for unused_sample: int in range(128):
		monitor.begin_frame()
		monitor.end_frame()
	monitor.begin_physics()
	var exact_physics_usec: int = monitor.end_physics()
	_expect(
		monitor.last_main_cpu_usec >= 0
			and monitor.last_physics_usec == exact_physics_usec,
		"monitor exposes exact most-recent CPU boundaries without coarse engine polling",
	)
	var overhead := (monitor.snapshot() as Dictionary)["monitor"] as Dictionary
	_expect(
		int(overhead.get("call_count", 0)) > 0
			and float(overhead.get("p99_ms", 1.0)) < 0.10,
		"monitor self-overhead exposes a bounded P99 below the disabled-overlay budget",
	)
	var production_coordinator = COORDINATOR.new()
	production_coordinator.register_system(
		"profile_fixture",
		COORDINATOR.PHASE_MOVEMENT,
		func(_tick: int, _delta: float) -> void:
			pass,
	)
	production_coordinator.advance_exact_ticks(1)
	var production_stats := production_coordinator.stats() as Dictionary
	_expect(
		(production_stats["system_usec"] as Dictionary).is_empty(),
		"production simulation skips diagnostic system timing",
	)
	production_coordinator.set_profiling_enabled(true)
	production_coordinator.advance_exact_ticks(1)
	var diagnostic_stats := production_coordinator.stats() as Dictionary
	_expect(
		(diagnostic_stats["system_usec"] as Dictionary).has("profile_fixture"),
		"diagnostic simulation explicitly restores per-system attribution",
	)
	_expect(
		RUNTIME_FRAME_CLASSIFIER.is_host_scheduler_preemption(
			134.0,
			5.2,
			6.4,
			0.0,
			8,
		)
			and not RUNTIME_FRAME_CLASSIFIER.is_host_scheduler_preemption(
				61.0,
				8.0,
				14.0,
				28.0,
				3,
			),
		"host preemption is reported separately without hiding a game-owned path stall",
	)


func _test_recurring_evidence_hint_refresh() -> void:
	var main = MAIN_SCENE.instantiate()
	var actor = SQUAD_UNIT.new()
	main.units.append(actor)
	actor.configure_original_recurring_evidence_active(false)
	_expect(
		actor.original_recurring_evidence_known_inactive,
		"actors cache an inactive recurring-evidence window before startup restore",
	)
	var restored := bool(main.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m000",
	))
	_expect(
		restored and not actor.original_recurring_evidence_known_inactive,
		"startup checkpoint refreshes actor evidence hints before the first recurring round",
	)
	actor.free()
	main.free()


func _test_event_driven_spatial_index() -> void:
	var index = SPATIAL_INDEX.new(Vector2(32.0, 32.0))
	var actor := Node2D.new()
	actor.position = Vector2(8.0, 8.0)
	root.add_child(actor)
	index.register_node(actor, ["actor", "enemy"], 71)
	actor.position = Vector2(76.0, 8.0)
	index.update_node(actor)
	var reused: Array[Node2D] = [actor]
	index.query_radius_into(reused, Vector2(76.0, 8.0), 12.0, ["enemy"])
	_expect(
		reused == [actor]
			and index.query_radius(Vector2(8.0, 8.0), 12.0, ["enemy"]).is_empty(),
		"bucket-crossing events expose the new position in the same simulation tick",
	)
	var audit: Dictionary = index.audit_consistency()
	_expect(
		bool(audit["ok"])
			and int((index.stats() as Dictionary)["bucket_crossings"]) == 1,
		"event index audit finds no duplicate or leaked bucket records",
	)
	index.unregister_node(actor)
	_expect(
		index.node_for_scene(71) == null
			and int((index.stats() as Dictionary)["record_count"]) == 0,
		"explicit lifecycle removal clears scene and bucket lookups",
	)
	actor.queue_free()


func _test_movement_reservation_fairness() -> void:
	var service = MOVEMENT_RESERVATIONS.new()
	service.begin_tick(0)
	var dictionary_boundary_alternatives: Array = [
		Vector2(8.0, 8.0),
		"invalid-entry",
		Vector2(16.0, 8.0),
	]
	_expect(
		service.propose(
			99,
			Vector2.ZERO,
			Vector2(8.0, 0.0),
			MOVEMENT_RESERVATIONS.PRIORITY_PATROL,
			dictionary_boundary_alternatives,
		)
			and bool((service.resolve()[99] as Dictionary)["granted"]),
		"untyped Dictionary proposal alternatives are normalized without runtime type errors",
	)
	service.clear()
	var accepted: Dictionary = {}
	for tick: int in range(1, 16):
		service.begin_tick(tick)
		for actor_id: int in range(1, 11):
			service.propose(
				actor_id,
				Vector2(actor_id * 16.0, 0.0),
				Vector2(96.0, 96.0),
				MOVEMENT_RESERVATIONS.PRIORITY_PATROL,
			)
		var decisions: Dictionary = service.resolve()
		for actor_id: int in range(1, 11):
			if bool((decisions[actor_id] as Dictionary)["granted"]):
				accepted[actor_id] = true
	_expect(
		accepted.size() == 10,
		"wait-age arbitration gives every one of ten conflicting actors a turn",
	)
	var service_stats: Dictionary = service.stats()
	_expect(
		int(service_stats["maximum_wait_age"]) <= 9,
		"reservation wait is bounded and does not permanently starve high scene IDs",
	)
	service.clear()
	var directions_seen: Dictionary = {}
	for tick: int in range(1, 10):
		service.begin_tick(tick)
		service.propose(
			1, Vector2(-8, 0), Vector2(-1, 0), 50, [], "single_door", Vector2.RIGHT
		)
		service.propose(
			2, Vector2(8, 0), Vector2(1, 0), 50, [], "single_door", Vector2.LEFT
		)
		var decisions: Dictionary = service.resolve()
		for actor_id: int in [1, 2]:
			if bool((decisions[actor_id] as Dictionary)["granted"]):
				directions_seen[actor_id] = true
	_expect(
		directions_seen.size() == 2,
		"bounded one-way batches eventually admit both directions through a door",
	)
	service.clear()
	service.begin_tick(1)
	service.propose(1, Vector2(0, 0), Vector2(8, 0), 50)
	service.propose(2, Vector2(8, 0), Vector2(0, 0), 50)
	var swap_decisions := service.resolve() as Dictionary
	_expect(
		int(bool((swap_decisions[1] as Dictionary).get("granted", false)))
			+ int(bool((swap_decisions[2] as Dictionary).get("granted", false))) == 1,
		"opposite edge swaps are prevented before actors overlap",
	)
	service.clear()
	var intersection_served: Dictionary = {}
	for tick: int in range(1, 9):
		service.begin_tick(tick)
		for actor_id: int in range(1, 5):
			service.propose(
				actor_id,
				Vector2(actor_id * 16.0, actor_id * 8.0),
				Vector2(64.0, 64.0),
				MOVEMENT_RESERVATIONS.PRIORITY_PATROL,
			)
		var intersection := service.resolve() as Dictionary
		for actor_id: int in range(1, 5):
			if bool((intersection[actor_id] as Dictionary).get("granted", false)):
				intersection_served[actor_id] = true
	_expect(
		intersection_served.size() == 4,
		"four-way crossing contention serves every actor without rollback jitter",
	)
	var reservation_state := service.capture_state() as Dictionary
	var restored_reservations = MOVEMENT_RESERVATIONS.new()
	_expect(
		restored_reservations.restore_state(reservation_state)
			and restored_reservations.capture_state() == reservation_state,
		"reservation wait age and corridor batches survive save/load exactly",
	)


func _test_composed_runtime_controllers() -> void:
	var interactions = WORLD_INTERACTIONS.new()
	var interaction_order: Array[String] = []
	var interaction_result := interactions.dispatch(Vector2.ZERO, {
		"loose_pickup": func(_point: Vector2) -> bool:
			interaction_order.append("pickup")
			return true,
		"burial_cache": func(_point: Vector2) -> bool:
			interaction_order.append("cache")
			return true,
	})
	_expect(
		bool(interaction_result.get("handled", false))
			and str(interaction_result.get("interaction", "")) == "loose_pickup"
			and interaction_order == ["pickup"],
		"world interaction controller owns deterministic loot-before-corpse priority",
	)

	var camera_positions: Array[Vector2] = []
	for frame_rate: int in [30, 60, 120]:
		var camera = CAMERA_INPUT.new()
		var position := Vector2.ZERO
		for _frame: int in range(frame_rate):
			position += camera.advance(1.0 / float(frame_rate), Vector2.DOWN, 600.0, 1.0, false)
		camera_positions.append(position)
	_expect(
		camera_positions[0].distance_to(camera_positions[1]) < 8.0
			and camera_positions[1].distance_to(camera_positions[2]) < 4.0,
		"camera presentation smoothing remains stable across common render rates",
	)

	var movement = ACTOR_MOVEMENT.new()
	_expect(
		movement.proposed_position(Vector2.ZERO, Vector2(3, 4), 2.5)
			.is_equal_approx(Vector2(1.5, 2.0)),
		"actor movement controller preserves scalar move-toward proposals",
	)

	var animation_group := {
		"frame_hold_ticks": 1,
		"secondary_triplet": [6, 0, 3],
	}
	var frame_seconds := ACTOR_ANIMATION.movement_frame_seconds(animation_group, 120.0)
	_expect(
		frame_seconds >= 1.0 / 18.0 and frame_seconds <= 0.14,
		"animation controller couples authored stride to movement speed without comic frame rates",
	)
	_expect(
		ACTOR_COMBAT.player_hit_chance(4) == 1.0
			and ACTOR_COMBAT.player_hit_chance(1) == 0.8
			and ACTOR_COMBAT.player_hit_chance(2) == 0.9,
		"actor combat controller preserves the approved fixed player hit chances",
	)

	var inventory = ACTOR_INVENTORY.new()
	var consumed := inventory.consume({"smoke": 2}, "smoke", 1) as Dictionary
	_expect(
		int(consumed.get("consumed", 0)) == 1
			and int((consumed.get("counts", {}) as Dictionary).get("smoke", 0)) == 1,
		"actor inventory controller applies bounded, non-negative transactions",
	)
	var parity_actor := FakeParityActor.new()
	var parity = CLASSIC_PARITY.new()
	var parity_snapshot := parity.capture(parity_actor) as Dictionary
	parity_actor.original_runtime_index = -1
	parity_actor.original_native_actor_state.clear()
	parity.restore(parity_actor, parity_snapshot)
	_expect(
		parity_actor.original_runtime_index == 7
			and parity_actor.original_native_actor_state == {"facing": 3}
			and parity_actor.original_command_goal_kind_latch == 4,
		"classic parity adapter is the typed capture/restore boundary for recovered actor fields",
	)
	var duty = ENEMY_DUTY.new()
	duty.capture(Vector2(48, 24), 3)
	var duty_state := duty.snapshot() as Dictionary
	var restored_duty = ENEMY_DUTY.new()
	_expect(
		restored_duty.restore(duty_state)
			and restored_duty.anchor == Vector2(48, 24)
			and restored_duty.patrol_index == 3,
		"enemy duty controller owns a serializable return-to-post snapshot",
	)
	var search_order := ENEMY_SEARCH.build_order(
		Vector2(100, 100), Vector2.ZERO, Vector2.RIGHT, 2, 4, true
	) as Dictionary
	_expect(
		str(search_order.get("role", "")) == "right_flank"
			and (search_order.get("candidates", []) as Array).size() >= 2,
		"enemy search controller produces deterministic reachable fallback candidates",
	)
	var squad_source := FileAccess.get_file_as_string(
		"res://scripts/squad_unit.gd"
	)
	var enemy_source := FileAccess.get_file_as_string(
		"res://scripts/enemy_unit.gd"
	)
	var main_source := FileAccess.get_file_as_string(
		"res://scripts/main.gd"
	)
	var coordinator_source := FileAccess.get_file_as_string(
		"res://scripts/mission_ai_coordinator.gd"
	)
	_expect(
		squad_source.contains("movement_controller.proposed_position(")
			and squad_source.contains("configure_central_simulation")
			and squad_source.contains('inventory_controller.call(')
			and squad_source.contains('classic_parity_adapter.call(')
			and enemy_source.contains('perception_controller.can_detect_heading(')
			and enemy_source.contains('ENEMY_TARGET_SPATIAL_TAGS')
			and enemy_source.contains(
				'modern_behavior_elapsed - MODERN_BEHAVIOR_INTERVAL_SECONDS'
			)
			and main_source.contains('"enemy_target"')
			and enemy_source.contains('duty_controller.capture(')
			and coordinator_source.contains(
				"ENEMY_SEARCH_CONTROLLER_SCRIPT.build_order"
			),
		"extracted actor and enemy controllers are wired into production paths rather than test-only placeholders",
	)

	var worker := FakeActor.new()
	worker.scene_index = 7
	worker.position = Vector2(80, 40)
	var corpse := FakeActor.new()
	corpse.scene_index = 8
	corpse.is_alive = false
	corpse.position = Vector2(120, 60)
	root.add_child(worker)
	root.add_child(corpse)
	var burial = BURIAL_COMMANDS.new()
	_expect(burial.begin(worker, corpse, 2), "burial controller accepts a valid worker and corpse")
	var first := burial.advance() as Dictionary
	var second := burial.advance() as Dictionary
	var third := burial.advance() as Dictionary
	_expect(
		str(first.get("state", "")) == "working"
			and str(second.get("state", "")) == "working"
			and str(third.get("state", "")) == "complete",
		"burial progress uses deterministic simulation ticks and completes strictly after the limit",
	)
	worker.queue_free()
	corpse.queue_free()

	var audio_mix := ACTOR_AUDIO.new().mix_for_source(
		Vector2(5000, 5000), Rect2(Vector2.ZERO, Vector2(640, 360))
	) as Dictionary
	_expect(
		not bool(audio_mix.get("audible", true)),
		"off-screen actor audio is culled at the presentation boundary",
	)
	var router = PRESENTATION_ROUTER.new()
	var routed := {"message": ""}
	router.status_requested.connect(
		func(message: String) -> void: routed["message"] = message
	)
	router.status("ready")
	_expect(
		str(routed.get("message", "")) == "ready"
			and int((router.snapshot() as Dictionary).get("status_serial", 0)) == 1,
		"presentation events are routed without writing gameplay state",
	)


func _test_modern_ambient_scheduler_boundary() -> void:
	var ambient = AMBIENT_UNIT.new()
	ambient.patrol_enabled = true
	ambient.patrol_waypoints = PackedVector2Array([Vector2(32, 16)])
	ambient.patrol_wait_remaining = 0.15
	ambient.configure_modern_ambient_simulation(true)
	ambient._update_patrol(0.10)
	_expect(
		not ambient.legacy_actor_scheduler_enabled
			and not ambient.original_route_update_active
			and is_equal_approx(ambient.patrol_wait_remaining, 0.05),
		"modern ambient patrols use the bounded waypoint hold without the recovered CRT scheduler",
	)
	ambient.configure_modern_ambient_simulation(false)
	_expect(
		ambient.legacy_actor_scheduler_enabled,
		"classic ambient patrols retain the recovered actor scheduler",
	)
	ambient.free()


func _test_modern_continuous_audio_cadence() -> void:
	var actor = SQUAD_UNIT.new()
	var requests := {"count": 0}
	actor.original_animation_audio_requested.connect(
		func(_source: Node2D, _gfl_index: int, _continuous: bool) -> void:
			requests["count"] = int(requests["count"]) + 1
	)
	var continuous_group := {"action_index": 2, "sound_gfl_index": 17}
	actor.configure_modern_presentation_scheduling(true)
	for _tick: int in range(12):
		actor._request_continuous_animation_audio(continuous_group, 1.0 / 60.0)
	_expect(
		int(requests["count"]) == 2,
		"modern sustained animation audio refreshes at 10 Hz instead of every actor tick",
	)
	actor.configure_modern_presentation_scheduling(false)
	for _tick: int in range(4):
		actor._request_continuous_animation_audio(continuous_group, 1.0 / 60.0)
	_expect(
		int(requests["count"]) == 6,
		"classic animation audio retains the recovered per-update request cadence",
	)
	actor.configure_modern_presentation_scheduling(true)
	actor._advance_movement_presentation(1.0 / 60.0, Vector2.RIGHT)
	_expect(
		actor.was_moving
			and actor.modern_movement_presentation_elapsed > 0.0,
		"modern movement keeps 60 Hz gameplay state while accumulating a skipped visual tick",
	)
	actor._advance_movement_presentation(1.0 / 60.0, Vector2.RIGHT)
	_expect(
		actor.modern_movement_presentation_elapsed > 0.0,
		"modern movement keeps accumulating below the authored sprite cadence",
	)
	actor._advance_movement_presentation(1.0 / 60.0, Vector2.RIGHT)
	_expect(
		actor.modern_movement_presentation_elapsed < 0.000001,
		"modern movement commits its accumulated sprite presentation at 20 Hz",
	)
	var phased_actor = SQUAD_UNIT.new()
	phased_actor.scene_index = 2
	phased_actor.configure_modern_presentation_scheduling(true)
	_expect(
		phased_actor.modern_movement_presentation_elapsed
			!= actor.modern_movement_presentation_elapsed,
		"modern presentation commits are deterministically phased across dense actors",
	)
	phased_actor.free()
	var octants_match := true
	for degrees: int in range(-179, 181):
		var direction := Vector2.from_angle(deg_to_rad(float(degrees)))
		var reference := posmod(roundi(direction.angle() / (PI / 4.0)) + 5, 8)
		if SQUAD_UNIT.direction_group_index(direction) != reference:
			octants_match = false
			break
	_expect(
		octants_match,
		"branch-only facing classification matches the recovered nearest-octant mapping",
	)
	actor.free()


func _test_stealth_feedback_contract() -> void:
	var perception = ENEMY_PERCEPTION.new()
	_expect(
		perception.visibility_band(80.0, 100.0, 240.0, true, true) == "near_red"
			and perception.visibility_band(180.0, 100.0, 240.0, true, true) == "none"
			and perception.visibility_band(180.0, 100.0, 240.0, false, true) == "far_green"
			and perception.visibility_band(80.0, 100.0, 240.0, false, false) == "none",
		"near red detects crawling, far green hides crawling, and walls block both bands",
	)
	var risk_field = STEALTH_RISK_FIELD.new()
	var sample_counter := {"count": 0}
	var sampler := func(_point: Vector2) -> float:
		sample_counter["count"] = int(sample_counter["count"]) + 1
		return 0.55
	var first_risk := risk_field.segment_risk(Vector2.ZERO, Vector2(96, 0), "world-a", sampler)
	var first_calls := int(sample_counter["count"])
	var second_risk := risk_field.segment_risk(Vector2.ZERO, Vector2(96, 0), "world-a", sampler)
	_expect(
		first_risk == 0.55 and second_risk == 0.55
			and int(sample_counter["count"]) == first_calls,
		"path risk reuses a quantized field instead of repeating line-of-sight rays",
	)
	var classic = CLASSIC_ENEMY_STRATEGY.new()
	classic.configure_hearing(640.0)
	classic.synchronize("search", 0.65, Vector2(32, 16), 2.0, "far_green")
	var snapshot := classic.public_snapshot() as Dictionary
	_expect(
		str(snapshot.get("awareness_state", "")) == "search"
			and int(snapshot.get("memory_ticks_remaining", 0)) == 120
			and float(snapshot.get("hearing_radius", 0.0)) == 640.0,
		"classic feedback exposes the same read-only public strategy snapshot fields",
	)


func _test_checkpoint_fallback_contract() -> void:
	var profile := {
		"ruleset_mode": "modern",
		"difficulty_mode": "normal",
		"mission_rule_mode": "repaired",
		"content_identity": "fixture",
	}
	var store := FakeSaveStore.new()
	store.summaries = [
		{"slot_id": "checkpoint_2", "level_id": "m000", "saved_at_unix_msec": 200},
		{"slot_id": "checkpoint_1", "level_id": "m000", "saved_at_unix_msec": 100},
	]
	store.loads = {
		"checkpoint_2": {"ok": false, "code": "corrupt_primary_and_backup"},
		"checkpoint_1": {
			"ok": true,
			"data": {"session": {"runtime_profile": profile.duplicate(true)}},
		},
	}
	var controller = SAVE_GAME_CONTROLLER.new()
	var result := controller.latest_compatible_checkpoint(store, "m000", profile) as Dictionary
	_expect(
		bool(result.get("ok", false))
			and str(result.get("slot_id", "")) == "checkpoint_1"
			and (result.get("rejected", []) as Array).size() == 1,
		"a corrupt newest checkpoint automatically falls back to the previous compatible generation",
	)
	controller.invalidate()
	store.summaries.clear()
	var empty := controller.latest_compatible_checkpoint(store, "m000", profile) as Dictionary
	_expect(
		not bool(empty.get("ok", true))
			and str(empty.get("reason", "")) == "no_compatible_checkpoint",
		"checkpoint retry reports an explicit unavailable state without disabling restart or manual load",
	)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
