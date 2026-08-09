class_name MissionAiCoordinator
extends Node

## Applies a mission's editorial tuning to already-created enemy nodes and
## provides deterministic cooperation decisions. Main only needs to register
## enemies and forward alert/directive events; no per-level AI branches live
## here or in EnemyUnit.

signal enemy_tuning_applied(enemy: Node2D, values: Dictionary)
signal cooperation_alert_delivered(enemy: Node2D, target: Node2D)
signal reinforcement_requested(count: int, reason: String)
signal reinforcement_threshold_reached(trigger_name: String, tags: Array[String])
signal posture_changed(posture: String)

const DATA_SCRIPT: Script = preload("res://scripts/mission_direction_data.gd")
const EVIDENCE_BLACKBOARD_SCRIPT: Script = preload(
	"res://scripts/ai_evidence_blackboard.gd"
)
const COMMUNICATION_SERVICE_SCRIPT: Script = preload(
	"res://scripts/ai_communication_service.gd"
)
const QA_STATISTICS_SCRIPT: Script = preload("res://scripts/ai_qa_statistics.gd")
const ENEMY_SEARCH_CONTROLLER_SCRIPT: Script = preload(
	"res://scripts/enemy_search_controller.gd"
)
const TICK_RATE := 60

var difficulty_profile: Dictionary = {}
var cooperation_profile: Dictionary = {}
var enemies: Array[Node2D] = []
var reinforcement_budget_remaining := 0
var active_posture := ""
var reinforcement_disabled := false
var reinforcement_trigger_name := "none"
var reinforcement_trigger_reached := false
var reinforcement_trigger_source := ""
var cooperation_tags: Array[String] = []
var last_error := ""
var _pending_alerts: Array[Dictionary] = []
var _command_serial := 0
var _observed_event_counts: Dictionary = {}
var evidence_blackboard: RefCounted = EVIDENCE_BLACKBOARD_SCRIPT.new()
var communication_service: RefCounted = COMMUNICATION_SERVICE_SCRIPT.new()
var qa_statistics: RefCounted = QA_STATISTICS_SCRIPT.new()
var communication_transmission_check: Callable = Callable()
var simulation_tick := 0


func configure(
	new_difficulty_profile: Dictionary,
	new_cooperation_profile: Dictionary,
	new_enemies: Array[Node2D] = [],
) -> bool:
	_reset()
	if new_difficulty_profile.is_empty() or new_cooperation_profile.is_empty():
		return _reject("AI coordinator profiles cannot be empty")
	if str(new_difficulty_profile.get("source_status", "")) != "remake_editorial":
		return _reject("difficulty profile provenance is invalid")
	if str(new_cooperation_profile.get("source_status", "")) != "remake_editorial":
		return _reject("cooperation profile provenance is invalid")
	difficulty_profile = new_difficulty_profile.duplicate(true)
	cooperation_profile = new_cooperation_profile.duplicate(true)
	reinforcement_trigger_name = str(
		cooperation_profile.get("reinforcement_trigger", "none")
	)
	reinforcement_trigger_reached = reinforcement_trigger_name == "none"
	cooperation_tags.clear()
	for raw_tag: Variant in cooperation_profile.get("tags", []) as Array:
		cooperation_tags.append(str(raw_tag))
	reinforcement_budget_remaining = maxi(
		0, int(difficulty_profile.get("reinforcement_budget", 0))
	)
	for enemy: Node2D in new_enemies:
		register_enemy(enemy)
	last_error = ""
	return true


func register_enemy(enemy: Node2D) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemies.has(enemy):
		return false
	enemies.append(enemy)
	var applied_values := _apply_difficulty(enemy)
	if enemy.has_method("configure_editorial_ai"):
		enemy.call(
			"configure_editorial_ai",
			self,
			applied_values,
			cooperation_profile.duplicate(true),
		)
	if not active_posture.is_empty() and enemy.has_method("apply_editorial_ai_posture"):
		enemy.call(
			"apply_editorial_ai_posture",
			active_posture,
			cooperation_tags.duplicate(),
		)
	return true


func configure_communication_transmission_check(check: Callable) -> void:
	communication_transmission_check = check


func unregister_enemy(enemy: Node2D) -> bool:
	var index := enemies.find(enemy)
	if index < 0:
		return false
	enemies.remove_at(index)
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("clear_editorial_ai_coordinator"):
		enemy.call("clear_editorial_ai_coordinator", self)
	return true


## Consumes the same world events already published to MissionRuntime. The
## trigger names are authored remake semantics, not recovered original AI.
## Reaching a threshold arms the corresponding director reinforcement beat;
## the beat still decides how much of the bounded budget to release.
func observe_mission_event(event_name: String, payload: Dictionary = {}) -> bool:
	if event_name.is_empty():
		return false
	_observed_event_counts[event_name] = int(_observed_event_counts.get(event_name, 0)) + 1
	if reinforcement_trigger_reached or reinforcement_trigger_name == "none":
		return false
	if not _event_reaches_reinforcement_threshold(event_name, payload):
		return false
	_mark_reinforcement_threshold(event_name)
	return true


## Every autonomous EnemyUnit calls this immediately before committing a
## shot. Candidates tracking the same target are distance/scene-index sorted,
## so the authored global cap applies outside director-issued attack orders.
func request_attack_permission(enemy: Node2D, target: Node2D) -> bool:
	if (
		enemy == null
		or target == null
		or not is_instance_valid(enemy)
		or not is_instance_valid(target)
		or not enemies.has(enemy)
		or not bool(enemy.get("is_alive"))
	):
		return false
	var attacker_limit := maxi(
		1,
		int(difficulty_profile.get("max_simultaneous_attackers", 1)),
	)
	var enemy_distance := enemy.position.distance_squared_to(target.position)
	var enemy_scene_index := int(enemy.get("scene_index"))
	var higher_ranked_count := 0
	for candidate: Node2D in enemies:
		if (
			candidate == null
			or not is_instance_valid(candidate)
			or not bool(candidate.get("is_alive"))
			or candidate.get("current_target") != target
		):
			continue
		if candidate == enemy:
			continue
		var candidate_distance := candidate.position.distance_squared_to(
			target.position
		)
		if (
			candidate_distance < enemy_distance
			or (
				is_equal_approx(candidate_distance, enemy_distance)
				and int(candidate.get("scene_index")) < enemy_scene_index
			)
		):
			higher_ranked_count += 1
			if higher_ranked_count >= attacker_limit:
				return false
	return true


func queue_shared_alert(
	source: Node2D,
	target: Node2D,
	world_position: Vector2,
	base_radius: float,
) -> Array[int]:
	var selected_scene_indices: Array[int] = []
	if target == null or not is_instance_valid(target) or base_radius <= 0.0:
		return selected_scene_indices
	var effective_radius := base_radius * float(
		difficulty_profile.get("shared_alert_radius_multiplier", 1.0)
	)
	var candidates: Array[Node2D] = []
	for enemy: Node2D in enemies:
		if (
			enemy == source
			or not is_instance_valid(enemy)
			or not bool(enemy.get("is_alive"))
			or enemy.position.distance_to(world_position) > effective_radius
		):
			continue
		candidates.append(enemy)
	candidates.sort_custom(
		func(left: Node2D, right: Node2D) -> bool:
			var left_distance := left.position.distance_squared_to(world_position)
			var right_distance := right.position.distance_squared_to(world_position)
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return int(left.get("scene_index")) < int(right.get("scene_index"))
	)
	var group_size := mini(
		maxi(1, int(cooperation_profile.get("search_group_size", 1))),
		candidates.size(),
	)
	var recipients: Array[Node2D] = []
	var target_velocity := Vector2.ZERO
	if _has_property(target, "velocity"):
		var velocity_value: Variant = target.get("velocity")
		if velocity_value is Vector2:
			target_velocity = velocity_value as Vector2
	if target_velocity.is_zero_approx() and _has_property(target, "target_position"):
		var intended_position: Variant = target.get("target_position")
		if intended_position is Vector2:
			target_velocity = (intended_position as Vector2) - target.position
	var source_position := world_position
	if source != null and is_instance_valid(source):
		source_position = source.position
	_command_serial += 1
	for index: int in range(group_size):
		var enemy := candidates[index]
		recipients.append(enemy)
		selected_scene_indices.append(int(enemy.get("scene_index")))
	if not recipients.is_empty():
		qa_statistics.record("alert", {"recipient_count": recipients.size()})
		var source_actor_id := int(source.get("scene_index")) if source != null and is_instance_valid(source) else -1
		var initial_recipients: Array[int] = []
		if source_actor_id >= 0:
			initial_recipients.append(source_actor_id)
		var evidence: Dictionary = evidence_blackboard.publish(
			"sighting",
			target.position,
			simulation_tick,
			1.0,
			1,
			source_actor_id,
			"shout",
			initial_recipients,
			maxi(roundi(float(difficulty_profile.get("search_duration_seconds", 12.0)) * 60.0), 60),
		)
		var delay_ticks := maxi(
			ceili(
				maxf(
					0.0,
					float(cooperation_profile.get("alert_share_delay_seconds", 0.0))
					* float(difficulty_profile.get("alert_delay_multiplier", 1.0)),
				)
				* float(TICK_RATE)
			),
			0,
		)
		var target_scene_index := (
			int(target.get("scene_index"))
			if _has_property(target, "scene_index")
			else -1
		)
		var evidence_id := int(evidence.get("evidence_id", -1))
		var recipient_snapshot: Array[int] = selected_scene_indices.duplicate()
		_pending_alerts.append(
			{
				"deliver_tick": simulation_tick + delay_ticks,
				"recipient_scene_indices": recipient_snapshot,
				"target_scene_index": target_scene_index,
				"evidence_id": evidence_id,
				# Freeze all search geometry when the alert is raised. Recipients
				# may receive it a fraction of a second later, but they must not
				# gain an omniscient reference to the target's newer position.
				"last_known_position": target.position,
				"source_position": source_position,
				"target_velocity": target_velocity,
				"command_serial": _command_serial,
			}
		)
	return selected_scene_indices


func advance_time(delta_seconds: float) -> int:
	if delta_seconds <= 0.0:
		return 0
	return advance_ticks(maxi(roundi(delta_seconds * float(TICK_RATE)), 1))


func advance_ticks(tick_count: int = 1) -> int:
	if tick_count <= 0:
		return 0
	return advance_to_tick(simulation_tick + tick_count)


func advance_to_tick(target_tick: int) -> int:
	if target_tick <= simulation_tick:
		return 0
	simulation_tick = target_tick
	evidence_blackboard.advance_to_tick(simulation_tick)
	var delivered := 0
	for index: int in range(_pending_alerts.size() - 1, -1, -1):
		var pending := _pending_alerts[index]
		if int(pending.get("deliver_tick", simulation_tick)) > simulation_tick:
			continue
		var recipient_ids := pending.get("recipient_scene_indices", []) as Array
		for recipient_index: int in range(recipient_ids.size()):
			var enemy := _enemy_for_scene_index(int(recipient_ids[recipient_index]))
			if enemy == null:
				continue
			var serial := int(pending.get("command_serial", 0))
			var scene_index := int(enemy.get("scene_index"))
			var search_order := build_editorial_search_order(
				pending["last_known_position"] as Vector2,
				pending["source_position"] as Vector2,
				pending["target_velocity"] as Vector2,
				recipient_index,
				recipient_ids.size(),
				should_flank(scene_index, serial),
			)
			var evidence_id := int(pending.get("evidence_id", -1))
			evidence_blackboard.grant(scene_index, evidence_id)
			evidence_blackboard.assign_search_sector(
				scene_index,
				str(search_order.get("role", "lead")),
				(search_order.get("candidates", [pending["last_known_position"]]) as Array)[0] as Vector2,
				96.0,
				evidence_id,
			)
			qa_statistics.record("search_assignment", {"role": search_order.get("role", "lead")})
			if (
				should_use_suppressive_fire(scene_index, serial)
				and _has_property(enemy, "attack_recheck_elapsed")
				and _has_property(enemy, "attack_recheck_seconds")
			):
				enemy.set("attack_recheck_elapsed", float(enemy.get("attack_recheck_seconds")))
			var accepted := false
			if enemy.has_method("receive_editorial_search_order"):
				accepted = bool(enemy.call(
					"receive_editorial_search_order",
					null,
					search_order.get("candidates", []),
					str(search_order.get("role", "lead")),
					serial,
				))
			if accepted:
				if (
					should_use_suppressive_fire(scene_index, serial)
					and enemy.has_method("issue_force_attack_at")
				):
					# This is a real coordinate attack: it consumes ammunition on the
					# authored hit frame and emits the same sound event as other shots.
					enemy.call(
						"issue_force_attack_at",
						pending["last_known_position"] as Vector2,
					)
					qa_statistics.record("weapon_fire", {"weapon": "suppressive"})
				delivered += 1
				cooperation_alert_delivered.emit(enemy, null)
		_pending_alerts.remove_at(index)
	return delivered


func record_world_evidence(
	type: String,
	world_position: Vector2,
	source_actor_id: int,
	radius: float,
	propagation: String = "sound",
	confidence: float = 0.85,
) -> Dictionary:
	var checker := Callable()
	if propagation == "shout" and communication_transmission_check.is_valid():
		checker = communication_transmission_check
	var recipients: Array[int] = communication_service.recipients_in_radius(
		world_position,
		radius,
		enemies,
		maxi(int(cooperation_profile.get("search_group_size", 4)) * 2, 1),
		source_actor_id,
		checker,
	)
	var result: Dictionary = evidence_blackboard.publish(
		type,
		world_position,
		simulation_tick,
		confidence,
		1,
		source_actor_id,
		propagation,
		recipients,
	)
	if bool(result.get("accepted", false)):
		qa_statistics.record("evidence", {"type": type, "recipient_count": recipients.size()})
	return result


func evidence_snapshot_for_actor(actor_id: int) -> Dictionary:
	return {
		"latest": evidence_blackboard.latest_for_actor(actor_id),
		"search_assignment": evidence_blackboard.search_assignment(actor_id),
	}


func qa_snapshot() -> Dictionary:
	return qa_statistics.snapshot({
		"simulation_tick": simulation_tick,
		"blackboard": evidence_blackboard.statistics(),
	})


func export_local_qa(mission_id: String) -> Dictionary:
	return qa_statistics.export_local(mission_id, {
		"simulation_tick": simulation_tick,
		"blackboard": evidence_blackboard.statistics(),
	})


func _enemy_for_scene_index(scene_index: int) -> Node2D:
	for enemy: Node2D in enemies:
		if is_instance_valid(enemy) and bool(enemy.get("is_alive")) and int(enemy.get("scene_index")) == scene_index:
			return enemy
	return null


func apply_directive(directive: Dictionary) -> bool:
	if str(directive.get("source_status", "")) != "remake_editorial":
		return _reject("AI directive provenance is invalid")
	var kind := str(directive.get("kind", ""))
	match kind:
		"set_posture", "coordinate_search", "coordinate_defense":
			active_posture = str(directive.get("value", ""))
			if active_posture.is_empty():
				return _reject("AI posture/directive value is empty")
			_apply_posture_to_enemies()
			posture_changed.emit(active_posture)
			return true
		"release_reinforcement":
			if reinforcement_disabled:
				return false
			# A direction beat is already gated by its mission event. Treat it as
			# an explicit threshold transition as a compatibility fallback for
			# older callers that do not yet forward observe_mission_event().
			if not reinforcement_trigger_reached:
				_mark_reinforcement_threshold("direction_beat")
			var requested := maxi(0, int(directive.get("value", 0)))
			var granted := mini(requested, reinforcement_budget_remaining)
			if granted <= 0:
				return false
			reinforcement_budget_remaining -= granted
			var reason := active_posture
			if reason.is_empty():
				reason = reinforcement_trigger_name
			reinforcement_requested.emit(granted, reason)
			return true
		"cease_reinforcement":
			reinforcement_disabled = bool(directive.get("value", false))
			return true
		_:
			return _reject("unknown AI directive kind: %s" % kind)


func select_attackers(target: Node2D, candidates: Array[Node2D] = []) -> Array[Node2D]:
	var eligible: Array[Node2D] = []
	var source := candidates if not candidates.is_empty() else enemies
	for enemy: Node2D in source:
		if enemy != null and is_instance_valid(enemy) and bool(enemy.get("is_alive")):
			eligible.append(enemy)
	if target != null and is_instance_valid(target):
		eligible.sort_custom(
			func(left: Node2D, right: Node2D) -> bool:
				var left_distance := left.position.distance_squared_to(target.position)
				var right_distance := right.position.distance_squared_to(target.position)
				if not is_equal_approx(left_distance, right_distance):
					return left_distance < right_distance
				return int(left.get("scene_index")) < int(right.get("scene_index"))
		)
	var limit := mini(
		maxi(1, int(difficulty_profile.get("max_simultaneous_attackers", 1))),
		eligible.size(),
	)
	return eligible.slice(0, limit) as Array[Node2D]


func _event_reaches_reinforcement_threshold(
	event_name: String,
	_payload: Dictionary,
) -> bool:
	match reinforcement_trigger_name:
		"first_explosion":
			return event_name in ["explosion", "trigger_activated"]
		"second_charge":
			return (
				event_name == "trigger_activated"
				and int(_observed_event_counts.get(event_name, 0)) >= 2
			)
		"prisoner_rescued", "first_rescue":
			return event_name == "entity_rescued"
		"officer_eliminated":
			return (
				event_name == "role_eliminated"
				and str(_payload.get("role_id", "")).contains("officer")
			)
		"commander_eliminated":
			return (
				event_name == "role_eliminated"
				and str(_payload.get("role_id", "")).contains("commander")
			)
		"traitor_engaged":
			return (
				event_name == "combat_engaged"
				and str(_payload.get("target_role_id", "")) == "m005_agui"
			)
		"exchange_reached":
			return event_name == "story_anchor_reached"
		"document_taken":
			return event_name == "item_acquired"
		"first_zone_approach":
			return event_name in ["zone_approached", "party_at_trigger"]
		_:
			return event_name == reinforcement_trigger_name


func _mark_reinforcement_threshold(source: String) -> void:
	if reinforcement_trigger_reached:
		return
	reinforcement_trigger_reached = true
	reinforcement_trigger_source = source
	reinforcement_threshold_reached.emit(
		reinforcement_trigger_name,
		cooperation_tags.duplicate(),
	)


func _apply_posture_to_enemies() -> void:
	for enemy: Node2D in enemies:
		if (
			enemy != null
			and is_instance_valid(enemy)
			and bool(enemy.get("is_alive"))
			and enemy.has_method("apply_editorial_ai_posture")
		):
			enemy.call(
				"apply_editorial_ai_posture",
				active_posture,
				cooperation_tags.duplicate(),
			)


func should_flank(enemy_scene_index: int, command_serial: int) -> bool:
	return deterministic_chance(
		enemy_scene_index,
		command_serial,
		float(cooperation_profile.get("flank_pair_chance", 0.0)),
	)


func should_use_suppressive_fire(enemy_scene_index: int, command_serial: int) -> bool:
	return deterministic_chance(
		enemy_scene_index ^ 0x4D2,
		command_serial,
		float(cooperation_profile.get("suppressive_fire_chance", 0.0)),
	)


## Builds a deterministic formation around the coordinate observed when an
## alert was raised. EnemyUnit tries these positions through the authoritative
## navigation/occupancy grid in order, so walls and narrow corridors collapse
## a wide flank to a compact reachable slot instead of producing stuck guards.
## This is deliberately remake_editorial and is never constructed in strict
## original mode, where Main retains the recovered coordinate broadcast path.
static func build_editorial_search_order(
	last_known_position: Vector2,
	source_position: Vector2,
	target_velocity: Vector2,
	recipient_index: int,
	recipient_count: int,
	wide_flank: bool,
) -> Dictionary:
	return ENEMY_SEARCH_CONTROLLER_SCRIPT.build_order(
		last_known_position,
		source_position,
		target_velocity,
		recipient_index,
		recipient_count,
		wide_flank,
	)


func capture_state() -> Dictionary:
	return {
		"schema_version": 3,
		"reinforcement_budget_remaining": reinforcement_budget_remaining,
		"active_posture": active_posture,
		"reinforcement_disabled": reinforcement_disabled,
		"reinforcement_trigger_reached": reinforcement_trigger_reached,
		"reinforcement_trigger_source": reinforcement_trigger_source,
		"observed_event_counts": _observed_event_counts.duplicate(true),
		"command_serial": _command_serial,
		"simulation_tick": simulation_tick,
		"evidence_blackboard": evidence_blackboard.capture_state(),
		"pending_alerts": _serialize_pending_alerts(),
	}


func restore_state(state: Dictionary) -> bool:
	if difficulty_profile.is_empty() or cooperation_profile.is_empty():
		return _reject("AI coordinator is not configured")
	if int(state.get("schema_version", 0)) not in [1, 2, 3]:
		return _reject("AI coordinator state schema is unsupported")
	reinforcement_budget_remaining = clampi(
		int(state.get("reinforcement_budget_remaining", reinforcement_budget_remaining)),
		0,
		maxi(0, int(difficulty_profile.get("reinforcement_budget", 0))),
	)
	active_posture = str(state.get("active_posture", ""))
	reinforcement_disabled = bool(state.get("reinforcement_disabled", false))
	reinforcement_trigger_reached = bool(
		state.get(
			"reinforcement_trigger_reached",
			reinforcement_trigger_name == "none",
		)
	)
	reinforcement_trigger_source = str(state.get("reinforcement_trigger_source", ""))
	var raw_observed_counts: Variant = state.get("observed_event_counts", {})
	_observed_event_counts = (
		(raw_observed_counts as Dictionary).duplicate(true)
		if raw_observed_counts is Dictionary
		else {}
	)
	_command_serial = maxi(0, int(state.get("command_serial", 0)))
	simulation_tick = maxi(int(state.get("simulation_tick", 0)), 0)
	_pending_alerts.clear()
	if int(state.get("schema_version", 0)) >= 2:
		var blackboard_state: Variant = state.get("evidence_blackboard", {})
		if blackboard_state is Dictionary and not evidence_blackboard.restore_state(blackboard_state as Dictionary):
			return _reject("AI evidence blackboard could not be restored")
		_restore_pending_alerts(
			state.get("pending_alerts", []) as Array,
			int(state.get("schema_version", 0)),
		)
	if not active_posture.is_empty():
		_apply_posture_to_enemies()
	last_error = ""
	return true


static func deterministic_chance(
	scene_index: int,
	command_serial: int,
	chance: float,
) -> bool:
	var clamped := clampf(chance, 0.0, 1.0)
	if clamped <= 0.0:
		return false
	if clamped >= 1.0:
		return true
	var sample := posmod(scene_index * 1103515245 + command_serial * 12345 + 0x1F123BB5, 10000)
	return float(sample) / 10000.0 < clamped


static func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _apply_difficulty(enemy: Node2D) -> Dictionary:
	var base_health := maxi(1, int(enemy.get("maximum_hit_points")))
	var current_health := maxi(0, int(enemy.get("current_hit_points")))
	var health_ratio := float(current_health) / float(base_health)
	var weapon := (enemy.get("weapon_profile") as Dictionary).duplicate(true)
	var base_damage := float(weapon.get("damage", 0.0))
	var base_reaction := maxf(0.01, float(enemy.get("attack_recheck_seconds")))
	var values: Dictionary = DATA_SCRIPT.apply_enemy_scalars(
		base_health, base_damage, base_reaction, difficulty_profile
	)
	# Keep the authored scalar beside the derived first interval so EnemyUnit can
	# apply it again when deterministic post-shot intervals are regenerated.
	values["reaction_time_multiplier"] = maxf(
		0.01, float(difficulty_profile.get("reaction_time_multiplier", 1.0))
	)
	enemy.set("maximum_hit_points", int(values["health"]))
	enemy.set("current_hit_points", clampi(roundi(float(values["health"]) * health_ratio), 0, int(values["health"])))
	enemy.set("move_speed", float(enemy.get("move_speed")) * float(values["patrol_speed_multiplier"]))
	enemy.set("attack_recheck_seconds", float(values["reaction_seconds"]))
	if weapon.has("damage"):
		weapon["damage"] = maxi(0, roundi(float(values["damage"])))
		enemy.set("weapon_profile", weapon)
	var sense: Dictionary = (enemy.get("sense_profile") as Dictionary).duplicate(true)
	for field: String in ["horizontal_radius", "vertical_radius"]:
		if sense.has(field):
			sense[field] = float(sense[field]) * float(values["sense_radius_multiplier"])
	if not sense.is_empty():
		enemy.set("sense_profile", sense)
	enemy_tuning_applied.emit(enemy, values)
	return values


func _reset() -> void:
	difficulty_profile = {}
	cooperation_profile = {}
	enemies = []
	reinforcement_budget_remaining = 0
	active_posture = ""
	reinforcement_disabled = false
	reinforcement_trigger_name = "none"
	reinforcement_trigger_reached = false
	reinforcement_trigger_source = ""
	cooperation_tags = []
	last_error = ""
	_pending_alerts = []
	_command_serial = 0
	_observed_event_counts = {}
	simulation_tick = 0
	evidence_blackboard.clear()
	qa_statistics.clear()
	communication_transmission_check = Callable()


func _serialize_pending_alerts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pending: Dictionary in _pending_alerts:
		var known := pending.get("last_known_position", Vector2.ZERO) as Vector2
		var source := pending.get("source_position", Vector2.ZERO) as Vector2
		var velocity := pending.get("target_velocity", Vector2.ZERO) as Vector2
		result.append({
			"deliver_tick": maxi(
				int(pending.get("deliver_tick", simulation_tick)),
				simulation_tick,
			),
			"remaining_seconds": (
				float(maxi(int(pending.get("deliver_tick", simulation_tick)) - simulation_tick, 0))
				/ float(TICK_RATE)
			),
			"recipient_scene_indices": (pending.get("recipient_scene_indices", []) as Array).duplicate(),
			"target_scene_index": int(pending.get("target_scene_index", -1)),
			"evidence_id": int(pending.get("evidence_id", -1)),
			"last_known_x": known.x,
			"last_known_y": known.y,
			"source_x": source.x,
			"source_y": source.y,
			"velocity_x": velocity.x,
			"velocity_y": velocity.y,
			"command_serial": int(pending.get("command_serial", 0)),
		})
	return result


func _restore_pending_alerts(records: Array, source_schema: int = 3) -> void:
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			continue
		var record := raw_record as Dictionary
		var deliver_tick := simulation_tick + maxi(
			ceili(maxf(float(record.get("remaining_seconds", 0.0)), 0.0) * float(TICK_RATE)),
			0,
		)
		if (
			source_schema >= 3
			and (record.get("deliver_tick") is int or record.get("deliver_tick") is float)
		):
			deliver_tick = maxi(roundi(float(record["deliver_tick"])), simulation_tick)
		_pending_alerts.append({
			"deliver_tick": deliver_tick,
			"recipient_scene_indices": (record.get("recipient_scene_indices", []) as Array).duplicate(),
			"target_scene_index": int(record.get("target_scene_index", -1)),
			"evidence_id": int(record.get("evidence_id", -1)),
			"last_known_position": Vector2(float(record.get("last_known_x", 0.0)), float(record.get("last_known_y", 0.0))),
			"source_position": Vector2(float(record.get("source_x", 0.0)), float(record.get("source_y", 0.0))),
			"target_velocity": Vector2(float(record.get("velocity_x", 0.0)), float(record.get("velocity_y", 0.0))),
			"command_serial": maxi(int(record.get("command_serial", 0)), 0),
		})


func _reject(message: String) -> bool:
	last_error = message
	return false
