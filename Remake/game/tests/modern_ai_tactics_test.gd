extends SceneTree

const BLACKBOARD := preload("res://scripts/ai_evidence_blackboard.gd")
const COMMUNICATION := preload("res://scripts/ai_communication_service.gd")
const SEARCH := preload("res://scripts/enemy_search_controller.gd")
const DUTY := preload("res://scripts/enemy_duty_controller.gd")
const COORDINATOR := preload("res://scripts/mission_ai_coordinator.gd")
const QA_STATS := preload("res://scripts/ai_qa_statistics.gd")

class FakeEnemy extends Node2D:
	var scene_index := -1
	var is_alive := true
	var maximum_hit_points := 8
	var current_hit_points := 8
	var weapon_profile := {"damage": 2}
	var attack_recheck_seconds := 0.4
	var attack_recheck_elapsed := 0.0
	var move_speed := 90.0
	var sense_profile := {"horizontal_radius": 400.0, "vertical_radius": 240.0}
	var current_target: Node2D
	var received_orders: Array[Dictionary] = []
	var forced_attacks: Array[Vector2] = []
	var ammo := 3
	var noise_events := 0

	func configure_editorial_ai(_coordinator: Node, _difficulty: Dictionary, _cooperation: Dictionary) -> void:
		pass

	func clear_editorial_ai_coordinator(_coordinator: Node) -> void:
		pass

	func apply_editorial_ai_posture(_posture: String, _tags: Array[String]) -> void:
		pass

	func receive_editorial_search_order(
		target: Node2D,
		candidates: Array,
		role: String,
		serial: int,
	) -> bool:
		received_orders.append({
			"target_is_null": target == null,
			"candidates": candidates.duplicate(true),
			"role": role,
			"serial": serial,
		})
		return true

	func issue_force_attack_at(world_position: Vector2) -> bool:
		if ammo <= 0:
			return false
		ammo -= 1
		noise_events += 1
		forced_attacks.append(world_position)
		return true

class FakeTarget extends Node2D:
	var scene_index := 900
	var is_alive := true
	var velocity := Vector2(80, 0)
	var target_position := Vector2(320, 100)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_evidence_lifecycle()
	_test_communication_and_search_geometry()
	_test_coordinate_only_cooperation_and_restore()
	_test_duty_and_local_statistics()
	if failures.is_empty():
		print("Modern AI tactics tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_evidence_lifecycle() -> void:
	var blackboard = BLACKBOARD.new()
	var published := blackboard.publish(
		"sighting", Vector2(10, 20), 5, 0.8, 1, 7, "shout", [7, 8], 100
	) as Dictionary
	var evidence_id := int(published.get("evidence_id", -1))
	var first := blackboard.latest_for_actor(8) as Dictionary
	_expect(
		bool(published.get("accepted", false))
			and first.get("x") is float
			and not first.values().any(func(value: Variant) -> bool: return value is Object),
		"AI evidence stores coordinates and scalar provenance, never a live target reference",
	)
	blackboard.assign_search_sector(8, "left", Vector2(40, 20), 96.0, evidence_id)
	blackboard.advance_to_tick(45)
	var decayed := blackboard.latest_for_actor(8) as Dictionary
	_expect(
		float(decayed.get("current_confidence", 1.0)) < 0.8
			and blackboard.refresh(evidence_id, Vector2(24, 20), 45, 0.9, 20),
		"confidence decays with fixed ticks and a new observation refreshes the same evidence",
	)
	blackboard.advance_to_tick(65)
	_expect(
		blackboard.latest_for_actor(8).is_empty()
			and blackboard.search_assignment(8).is_empty(),
		"expired evidence also retires its search assignment",
	)


func _test_communication_and_search_geometry() -> void:
	var communication = COMMUNICATION.new()
	var candidates: Array[Node2D] = []
	for index: int in range(4):
		var enemy := FakeEnemy.new()
		enemy.scene_index = 100 + index
		enemy.position = Vector2(index * 40, 0)
		root.add_child(enemy)
		candidates.append(enemy)
	var blocked_id := 102
	var recipients: Array[int] = communication.recipients_in_radius(
		Vector2.ZERO,
		160.0,
		candidates,
		8,
		-1,
		func(_from: Vector2, to: Vector2) -> bool:
			return not is_equal_approx(to.x, 80.0),
	)
	_expect(
		not recipients.has(blocked_id)
			and communication.can_transmit("sound", 140.0, 160.0, false, false, true)
			and not communication.can_transmit("shout", 140.0, 160.0, false, false, true)
			and communication.can_transmit("radio", 9999.0, 0.0, true),
		"shouts respect insulation while physical sound and configured radio retain their rules",
	)
	var actor_ids: Array[int] = [1, 2, 3, 4, 5, 6]
	var assignments: Array[Dictionary] = SEARCH.new().build_assignments(
		Vector2(200, 200), Vector2.RIGHT, actor_ids, 96.0
	)
	var cells: Dictionary = {}
	for assignment: Dictionary in assignments:
		cells[str(assignment.get("position"))] = true
	_expect(
		assignments.size() == actor_ids.size() and cells.size() == actor_ids.size(),
		"coordinated search gives every member a distinct reachable-intent sector",
	)
	for candidate: Node2D in candidates:
		candidate.queue_free()


func _test_coordinate_only_cooperation_and_restore() -> void:
	var actors := _make_cooperation_actors()
	var coordinator: Node = COORDINATOR.new()
	root.add_child(coordinator)
	_expect(
		coordinator.configure(_difficulty_profile(), _cooperation_profile(), actors.enemies),
		"modern coordinator accepts labelled difficulty and cooperation policies",
	)
	var recipients: Array[int] = coordinator.queue_shared_alert(
		actors.source,
		actors.target,
		actors.source.position,
		500.0,
	)
	var captured := coordinator.capture_state() as Dictionary
	actors.target.position = Vector2(900, 900)
	coordinator.advance_time(0.2)
	var ordered_positions: Dictionary = {}
	var null_target_count := 0
	var suppression_count := 0
	for enemy: FakeEnemy in actors.recipients:
		if not enemy.received_orders.is_empty():
			var order := enemy.received_orders[0]
			null_target_count += 1 if bool(order.get("target_is_null", false)) else 0
			ordered_positions[str((order.get("candidates", []) as Array)[0])] = true
		suppression_count += enemy.forced_attacks.size()
	_expect(
		recipients.size() == 4
			and null_target_count == 4
			and ordered_positions.size() == 4,
		"alert recipients receive distinct frozen coordinates without omniscient live targets",
	)
	_expect(
		suppression_count == 4
			and actors.recipients.all(func(enemy: FakeEnemy) -> bool: return enemy.ammo == 2 and enemy.noise_events == 1),
		"suppression is a real coordinate attack that consumes ammunition and emits noise",
	)

	var restored_actors := _make_cooperation_actors(2000)
	var restored: Node = COORDINATOR.new()
	root.add_child(restored)
	restored.configure(_difficulty_profile(), _cooperation_profile(), restored_actors.enemies)
	# Re-map fixture IDs to the captured IDs so pending coordinate orders resolve.
	for index: int in range(restored_actors.enemies.size()):
		(restored_actors.enemies[index] as FakeEnemy).scene_index = (
			actors.enemies[index] as FakeEnemy
		).scene_index
	_expect(
		restored.restore_state(captured)
			and restored.capture_state() == captured,
		"save/load restores the AI blackboard, alert delay, search state and command serial exactly",
	)
	restored.advance_time(0.2)
	_expect(
		restored_actors.recipients.all(func(enemy: FakeEnemy) -> bool: return enemy.received_orders.size() == 1),
		"a restored pending alert resumes once without duplication",
	)
	coordinator.queue_free()
	restored.queue_free()
	_free_cooperation_actors(actors)
	_free_cooperation_actors(restored_actors)


func _test_duty_and_local_statistics() -> void:
	var duty = DUTY.new()
	duty.capture(Vector2(64, 96), 3)
	_expect(
		duty.snapshot() == {
			"active": true, "x": 64.0, "y": 96.0, "patrol_index": 3,
		},
		"duty controller preserves the exact patrol anchor used for post-search return",
	)
	var stats = QA_STATS.new()
	stats.record("alert")
	stats.record("weapon_fire", {"weapon": "rifle"})
	stats.record("ammo_consumed", {"weapon": "rifle", "count": 2})
	stats.record("player_death", {"position": Vector2(130, 65)})
	var snapshot := stats.snapshot() as Dictionary
	_expect(
		int((snapshot.get("counts", {}) as Dictionary).get("alert", 0)) == 1
			and int(((snapshot.get("weapons", {}) as Dictionary).get("rifle", {}) as Dictionary).get("ammo_consumed", 0)) == 2
			and (snapshot.get("player_death_cells_64px", {}) as Dictionary).has("2:1"),
		"AI tuning statistics aggregate locally without any network or upload path",
	)


func _make_cooperation_actors(offset: int = 0) -> Dictionary:
	var source := FakeEnemy.new()
	source.scene_index = 10 + offset
	source.position = Vector2.ZERO
	root.add_child(source)
	var enemies: Array[Node2D] = [source]
	var recipients: Array[FakeEnemy] = []
	for index: int in range(4):
		var enemy := FakeEnemy.new()
		enemy.scene_index = 20 + offset + index
		enemy.position = Vector2(40 + index * 24, 20 + index * 12)
		root.add_child(enemy)
		enemies.append(enemy)
		recipients.append(enemy)
	var target := FakeTarget.new()
	target.scene_index = 90 + offset
	target.position = Vector2(240, 80)
	root.add_child(target)
	return {"source": source, "target": target, "enemies": enemies, "recipients": recipients}


func _free_cooperation_actors(actors: Dictionary) -> void:
	for enemy: Node2D in actors.enemies:
		enemy.queue_free()
	(actors.target as Node2D).queue_free()


func _difficulty_profile() -> Dictionary:
	return {
		"source_status": "remake_editorial",
		"reinforcement_budget": 2,
		"max_simultaneous_attackers": 2,
		"enemy_health_multiplier": 1.0,
		"enemy_damage_multiplier": 1.0,
		"reaction_time_multiplier": 1.0,
		"aim_error_multiplier": 1.0,
		"enemy_hit_chance": 0.75,
		"patrol_speed_multiplier": 1.0,
		"sense_radius_multiplier": 1.0,
		"shared_alert_radius_multiplier": 1.0,
		"alert_delay_multiplier": 1.0,
		"search_duration_seconds": 8.0,
	}


func _cooperation_profile() -> Dictionary:
	return {
		"source_status": "remake_editorial",
		"reinforcement_trigger": "none",
		"tags": ["fixture"],
		"search_group_size": 4,
		"alert_share_delay_seconds": 0.1,
		"flank_pair_chance": 1.0,
		"suppressive_fire_chance": 1.0,
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
