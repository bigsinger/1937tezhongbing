class_name EnemyUnit
extends "res://scripts/squad_unit.gd"

const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const SENSE_INTERVAL_SECONDS := 0.20
const CHASE_REPLAN_SECONDS := 0.50
const SEARCH_TIMEOUT_SECONDS := 2.50
const PATROL_PATH_RETRY_MIN_SECONDS := 0.75
const PATROL_PATH_RETRY_STEP_SECONDS := 0.05
const ATTACK_RECHECK_MIN_SECONDS := 20.0 * BASE_SPRITE_TICK_SECONDS
const ATTACK_RECHECK_MAX_SECONDS := 39.0 * BASE_SPRITE_TICK_SECONDS

enum BehaviorState { PATROL, CHASE, ATTACK, SEARCH }

signal attack_committed(attacker: EnemyUnit, target: Node2D, attack_type: int)

var behavior_state := BehaviorState.PATROL
var patrol_waypoints := PackedVector2Array()
var patrol_index := 0
var patrol_enabled := false
var original_direction_index := 1
var sense_profile: Dictionary = {}
var potential_targets: Array[Node2D] = []
var current_target: Node2D
var last_known_target_position := Vector2.ZERO
var sense_elapsed := 0.0
var chase_replan_elapsed := 0.0
var search_elapsed := 0.0
var attack_recheck_elapsed := 0.0
var attack_recheck_seconds := ATTACK_RECHECK_MIN_SECONDS
var attack_count := 0
var path_request_delay_remaining := 0.0
var patrol_path_retry_seconds := PATROL_PATH_RETRY_MIN_SECONDS


func configure_enemy(
	entity: Dictionary,
	texture: Texture2D,
	new_movement_groups: Array[Dictionary],
	new_idle_groups: Array[Dictionary],
	new_dynamic_occupancy: RefCounted,
	new_attack_groups: Array[Dictionary] = [],
	new_death_groups: Array[Dictionary] = [],
) -> void:
	configure(
		str(entity.get("display_name", "enemy")),
		Color("b86b5b"),
		Vector2(float(entity.get("x", 0)), float(entity.get("y", 0))),
		texture,
		new_movement_groups,
		new_idle_groups,
		int(entity.get("scene_index", -1)),
		new_dynamic_occupancy,
		Vector2(
			float(entity.get("reference_x", entity.get("x", 0))),
			float(entity.get("reference_y", entity.get("y", 0))),
		),
	)
	move_speed = 92.0
	blocked_replan_seconds = 0.65 + float(posmod(scene_index * 11, 8)) * 0.05
	patrol_path_retry_seconds = (
		PATROL_PATH_RETRY_MIN_SECONDS
		+ float(posmod(scene_index * 17, 12)) * PATROL_PATH_RETRY_STEP_SECONDS
	)
	# Spread the first patrol requests over several physics frames. Large original
	# maps can contain about one hundred active actors, and issuing every A* query
	# in the same frame creates an avoidable startup spike.
	path_request_delay_remaining = float(posmod(scene_index * 37, 24)) / 60.0
	original_direction_index = clampi(int(entity.get("direction_index", 1)), 1, 8)
	set_animation_group(
		IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(original_direction_index)
	)
	apply_idle_frame()
	sense_profile = COMBAT_PROFILES.sense_profile(
		"guard_dog_special" if bool(entity.get("special_sensor_mode", false)) else "enemy_default"
	)
	weapon_profile = COMBAT_PROFILES.weapon_profile_for_attack_type(
		int(entity.get("default_attack_type", 2))
	)
	if weapon_profile.is_empty():
		weapon_profile = COMBAT_PROFILES.weapon_profile("rifle_attack")
	configure_combat(
		1,
		maxi(int(entity.get("current_hit_points", 8)), 1),
		weapon_profile,
		new_attack_groups,
		new_death_groups,
		true,
	)
	patrol_waypoints = patrol_world_points(entity.get("patrol_waypoints", []))
	patrol_index = clampi(int(entity.get("patrol_current_waypoint_index", 0)), 0, maxi(0, patrol_waypoints.size() - 1))
	patrol_enabled = bool(entity.get("patrol_enabled", true)) and not patrol_waypoints.is_empty()
	attack_recheck_seconds = _deterministic_attack_interval()
	queue_redraw()


func set_potential_targets(targets: Array[Node2D]) -> void:
	potential_targets = targets.duplicate()


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	if not is_alive or combat_action != CombatAction.NONE or hurt_remaining > 0.0:
		super._physics_process(safe_delta)
		return
	path_request_delay_remaining = maxf(path_request_delay_remaining - safe_delta, 0.0)
	sense_elapsed += safe_delta
	chase_replan_elapsed += safe_delta
	attack_recheck_elapsed += safe_delta
	if sense_elapsed >= SENSE_INTERVAL_SECONDS:
		sense_elapsed = fmod(sense_elapsed, SENSE_INTERVAL_SECONDS)
		_update_detection()
	_update_behavior(safe_delta)
	super._physics_process(safe_delta)
	original_direction_index = (
		IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(animation_group_index)
	)


func _update_detection() -> void:
	var nearest_visible: Node2D
	var nearest_distance_squared := INF
	for target: Node2D in potential_targets:
		if not _is_hostile_target(target):
			continue
		var ignored: Array = [scene_index]
		var target_scene_index := int(target.get("scene_index"))
		if target_scene_index >= 0:
			ignored.append(target_scene_index)
		if not TACTICAL_SENSES.can_detect_original(
			dynamic_occupancy,
			position,
			target.position,
			original_direction_index,
			sense_profile,
			bool(target.get("is_crawling")),
			ignored,
		):
			continue
		var distance_squared := position.distance_squared_to(target.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_visible = target
	if nearest_visible != null:
		var already_tracking := (
			current_target == nearest_visible
			and behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK]
		)
		current_target = nearest_visible
		last_known_target_position = nearest_visible.position
		search_elapsed = 0.0
		if not already_tracking:
			attack_recheck_elapsed = 0.0
		behavior_state = (
			BehaviorState.ATTACK if _can_attack_current_target() else BehaviorState.CHASE
		)
	elif current_target != null and behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK]:
		behavior_state = BehaviorState.SEARCH
		search_elapsed = 0.0
		_issue_path_to(last_known_target_position)


func _update_behavior(delta: float) -> void:
	match behavior_state:
		BehaviorState.PATROL:
			_update_patrol()
		BehaviorState.CHASE:
			if current_target == null or not is_instance_valid(current_target):
				_enter_patrol()
				return
			if _can_attack_current_target():
				behavior_state = BehaviorState.ATTACK
				cancel_path()
				return
			if chase_replan_elapsed >= CHASE_REPLAN_SECONDS:
				chase_replan_elapsed = 0.0
				last_known_target_position = current_target.position
				_issue_path_to(last_known_target_position)
		BehaviorState.ATTACK:
			if movement_path_index < movement_path.size():
				cancel_path()
			if current_target == null or not is_instance_valid(current_target):
				_enter_patrol()
				return
			if not _can_attack_current_target():
				behavior_state = BehaviorState.CHASE
				chase_replan_elapsed = CHASE_REPLAN_SECONDS
				return
			if attack_recheck_elapsed >= attack_recheck_seconds:
				attack_recheck_elapsed = 0.0
				attack_recheck_seconds = _deterministic_attack_interval()
				if try_start_attack(current_target):
					attack_count += 1
					attack_committed.emit(
						self, current_target, int(weapon_profile.get("attack_type", 0))
					)
		BehaviorState.SEARCH:
			if movement_path_index < movement_path.size():
				return
			search_elapsed += delta
			if search_elapsed >= SEARCH_TIMEOUT_SECONDS:
				current_target = null
				_enter_patrol()


func _update_patrol() -> void:
	if not patrol_enabled or patrol_waypoints.is_empty():
		return
	if path_request_delay_remaining > 0.0:
		return
	if movement_path_index < movement_path.size():
		return
	var next_index := next_unreached_patrol_index(patrol_waypoints, patrol_index, position)
	if next_index < 0:
		path_request_delay_remaining = patrol_path_retry_seconds
		return
	patrol_index = next_index
	var destination := patrol_waypoints[patrol_index]
	_issue_path_to(destination)


func _enter_patrol() -> void:
	behavior_state = BehaviorState.PATROL
	search_elapsed = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	cancel_path()


func _issue_path_to(destination: Vector2) -> bool:
	if dynamic_occupancy == null or scene_index < 0:
		return false
	var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
		scene_index, position, destination
	)
	var has_actionable_point := false
	for waypoint: Vector2 in path:
		if position.distance_squared_to(waypoint) > 1.0:
			has_actionable_point = true
			break
	if not has_actionable_point:
		path_request_delay_remaining = patrol_path_retry_seconds
		cancel_path()
		return false
	issue_path(path)
	return true


func _can_attack_current_target() -> bool:
	return can_attack_target(current_target)


func receive_alert(target: Node2D, world_position: Vector2) -> bool:
	if not is_alive or not _is_hostile_target(target):
		return false
	current_target = target
	last_known_target_position = world_position
	search_elapsed = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	behavior_state = BehaviorState.CHASE
	return true


func _is_hostile_target(target: Node2D) -> bool:
	return (
		_target_is_alive(target)
		and factions_are_hostile(faction_id, int(target.get("faction_id")))
	)


func _on_damage_taken(attacker: Node2D) -> void:
	if _target_is_alive(attacker):
		receive_alert(attacker, attacker.position)


func _deterministic_attack_interval() -> float:
	var tick_offset := posmod(scene_index * 17 + attack_count * 13, 20)
	return float(20 + tick_offset) * BASE_SPRITE_TICK_SECONDS


static func patrol_world_points(raw_waypoints: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not raw_waypoints is Array:
		return result
	for raw_waypoint: Variant in raw_waypoints as Array:
		if not raw_waypoint is Dictionary:
			continue
		var waypoint := raw_waypoint as Dictionary
		result.append(
			Vector2(
				float(int(waypoint.get("x", 0)) * 32 + 16),
				float(int(waypoint.get("y", 0)) * 16 + 8),
			)
		)
	return result


static func next_unreached_patrol_index(
	waypoints: PackedVector2Array,
	current_index: int,
	world_position: Vector2,
) -> int:
	if waypoints.is_empty():
		return -1
	var candidate_index := clampi(current_index, 0, waypoints.size() - 1)
	for unused_waypoint in range(waypoints.size()):
		if world_position.distance_squared_to(waypoints[candidate_index]) > 4.0:
			return candidate_index
		candidate_index = (candidate_index + 1) % waypoints.size()
	return -1


func _draw() -> void:
	super._draw()
	if behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK, BehaviorState.SEARCH]:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.95, 0.20, 0.12), 2.0)
