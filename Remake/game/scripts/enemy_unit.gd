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
## Editorial accuracy model. The original executable's exact miss formula has
## not been recovered; this bounded base chance makes the authored per-level
## aim-error curve affect real hit resolution without pretending otherwise.
const EDITORIAL_BASE_AIM_MISS_CHANCE := 0.10

enum BehaviorState { PATROL, CHASE, ATTACK, SEARCH, REGROUP }

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
var special_control_lock_count := 0
var tactical_ranges_visible := false
var mission_ai_coordinator: Node
var editorial_aim_error_multiplier := 1.0
var editorial_reaction_multiplier := 1.0
var editorial_regroup_seconds := 0.0
var editorial_regroup_multiplier := 1.0
var editorial_posture_reaction_multiplier := 1.0
var editorial_posture := ""
var editorial_ai_tags: Array[String] = []
var regroup_remaining := 0.0
var last_editorial_aim_miss := false
var _pending_editorial_aim_miss := false


func set_tactical_ranges_visible(value: bool) -> void:
	if tactical_ranges_visible == value:
		return
	tactical_ranges_visible = value
	queue_redraw()


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
	# Recovered walk cadence is slower than the old remake default; this keeps
	# patrols readable and leaves room for the authored run/crawl speeds.
	move_speed = 72.0
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


func configure_editorial_ai(
	coordinator: Node,
	applied_values: Dictionary,
	cooperation: Dictionary,
) -> void:
	mission_ai_coordinator = coordinator
	editorial_aim_error_multiplier = maxf(
		0.0, float(applied_values.get("aim_error_multiplier", 1.0))
	)
	editorial_reaction_multiplier = maxf(
		0.01, float(applied_values.get("reaction_time_multiplier", 1.0))
	)
	editorial_regroup_seconds = maxf(
		0.0, float(cooperation.get("regroup_seconds", 0.0))
	)
	editorial_ai_tags.clear()
	for raw_tag: Variant in cooperation.get("tags", []) as Array:
		editorial_ai_tags.append(str(raw_tag))
	_refresh_editorial_tag_effects()
	attack_recheck_seconds = _deterministic_attack_interval()


func clear_editorial_ai_coordinator(source: Node = null) -> void:
	if source == null or mission_ai_coordinator == source:
		mission_ai_coordinator = null


func apply_editorial_ai_posture(posture: String, tags: Array[String] = []) -> void:
	# Posture names and their interpretation are explicitly remake_editorial.
	# They change reaction cadence and wake patrol scheduling, so set_posture and
	# coordinate_* directives have a direct gameplay consumer on every enemy.
	editorial_posture = posture
	if not tags.is_empty():
		editorial_ai_tags = tags.duplicate()
	_refresh_editorial_tag_effects()
	var normalized := posture.to_lower()
	editorial_posture_reaction_multiplier = 1.0
	if _contains_any(normalized, ["defense", "protect", "guard", "cordon", "crossfire", "contest"]):
		editorial_posture_reaction_multiplier = 0.88
	elif _contains_any(normalized, ["search", "collapse", "block", "intercept"]):
		editorial_posture_reaction_multiplier = 0.92
	elif not normalized.is_empty():
		editorial_posture_reaction_multiplier = 0.96
	attack_recheck_seconds = _deterministic_attack_interval()
	path_request_delay_remaining = 0.0


func editorial_aim_miss_chance(target: Node2D) -> float:
	# Aim dispersion is a ranged-fire concept; recovered melee/special contact
	# actions keep their existing deterministic hit rules.
	if int(weapon_profile.get("attack_type", 0)) in [4, 5, 8, 10, 11]:
		return 0.0
	var range_factor := 1.0
	if target != null and is_instance_valid(target):
		var horizontal_range := maxf(
			float(weapon_profile.get("horizontal_range", 1.0)), 1.0
		)
		var vertical_range := maxf(
			float(weapon_profile.get("vertical_range", 1.0)), 1.0
		)
		var offset := target.position - position
		var normalized_range := clampf(
			sqrt(
				offset.x * offset.x / (horizontal_range * horizontal_range)
				+ offset.y * offset.y / (vertical_range * vertical_range)
			),
			0.0,
			1.0,
		)
		range_factor = lerpf(0.60, 1.35, normalized_range)
	return clampf(
		EDITORIAL_BASE_AIM_MISS_CHANCE
		* editorial_aim_error_multiplier
		* range_factor,
		0.0,
		0.45,
	)


func will_editorial_attack_miss(target: Node2D, attack_serial: int = -1) -> bool:
	var serial := attack_count if attack_serial < 0 else attack_serial
	return deterministic_aim_sample(scene_index, serial) < editorial_aim_miss_chance(target)


static func deterministic_aim_sample(enemy_scene_index: int, attack_serial: int) -> float:
	var sample := posmod(
		enemy_scene_index * 1664525 + attack_serial * 1013904223 + 0x45D9F3B,
		10000,
	)
	return float(sample) / 10000.0


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	if is_special_controlled() and is_alive:
		# Original type 11 sets and later clears target offset +656. Its exact AI
		# semantics are unresolved; pausing this remake AI is the labelled,
		# reversible playable interpretation owned by LegacyAiControlEffect.
		super._physics_process(safe_delta)
		return
	if not is_alive or combat_action != CombatAction.NONE or hurt_remaining > 0.0:
		super._physics_process(safe_delta)
		return
	path_request_delay_remaining = maxf(path_request_delay_remaining - safe_delta, 0.0)
	sense_elapsed += safe_delta
	chase_replan_elapsed += safe_delta
	attack_recheck_elapsed += safe_delta
	if sense_elapsed >= SENSE_INTERVAL_SECONDS and behavior_state != BehaviorState.REGROUP:
		sense_elapsed = fmod(sense_elapsed, SENSE_INTERVAL_SECONDS)
		_update_detection()
	_update_behavior(safe_delta)
	super._physics_process(safe_delta)
	original_direction_index = (
		IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(animation_group_index)
	)


func apply_special_control(_source: Node2D = null) -> bool:
	if not is_alive:
		return false
	special_control_lock_count += 1
	if special_control_lock_count == 1:
		current_target = null
		behavior_state = BehaviorState.PATROL
		clear_combat_target()
		cancel_path()
		_interrupt_combat_action()
		apply_idle_frame()
		queue_redraw()
	return true


func release_special_control(_source: Node2D = null) -> bool:
	if special_control_lock_count <= 0:
		return false
	special_control_lock_count -= 1
	if special_control_lock_count == 0:
		sense_elapsed = SENSE_INTERVAL_SECONDS
		chase_replan_elapsed = CHASE_REPLAN_SECONDS
		path_request_delay_remaining = 0.0
		queue_redraw()
	return true


func is_special_controlled() -> bool:
	return special_control_lock_count > 0


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
		var visible: bool = TACTICAL_SENSES.can_detect_original(
			dynamic_occupancy,
			position,
			target.position,
			original_direction_index,
			sense_profile,
			bool(target.get("is_crawling")),
			ignored,
		)
		var heard: bool = (not visible) and TACTICAL_SENSES.is_within_hearing_range(position, target.position, sense_profile)
		if not visible and not heard:
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
				if (
					mission_ai_coordinator != null
					and is_instance_valid(mission_ai_coordinator)
					and mission_ai_coordinator.has_method("request_attack_permission")
					and not bool(
						mission_ai_coordinator.call(
							"request_attack_permission", self, current_target
						)
					)
				):
					_enter_regroup()
					return
				_pending_editorial_aim_miss = will_editorial_attack_miss(
					current_target, attack_count
				)
				last_editorial_aim_miss = _pending_editorial_aim_miss
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
		BehaviorState.REGROUP:
			if current_target == null or not is_instance_valid(current_target):
				_enter_patrol()
				return
			regroup_remaining = maxf(regroup_remaining - delta, 0.0)
			if regroup_remaining <= 0.0:
				behavior_state = BehaviorState.CHASE
				chase_replan_elapsed = CHASE_REPLAN_SECONDS


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
	regroup_remaining = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	cancel_path()


func _enter_regroup() -> void:
	behavior_state = BehaviorState.REGROUP
	regroup_remaining = maxf(
		editorial_regroup_seconds * editorial_regroup_multiplier,
		0.05,
	)
	cancel_path()
	apply_idle_frame()
	queue_redraw()


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
	# Search slightly ahead of the last sound/shot when a moving target exposes a
	# velocity, giving guards a deterministic intercept point instead of a dumb
	# beeline to the stale coordinate.
	var velocity_value: Variant = target.get("velocity")
	if velocity_value is Vector2:
		last_known_target_position += (velocity_value as Vector2).normalized() * 48.0
	search_elapsed = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	if behavior_state == BehaviorState.REGROUP:
		return true
	behavior_state = BehaviorState.CHASE
	return true

func investigate_position(world_position: Vector2) -> bool:
	if not is_alive:
		return false
	current_target = null
	last_known_target_position = world_position
	search_elapsed = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	behavior_state = BehaviorState.SEARCH
	_issue_path_to(world_position)
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
	return (
		float(20 + tick_offset)
		* BASE_SPRITE_TICK_SECONDS
		* editorial_reaction_multiplier
		* editorial_posture_reaction_multiplier
	)


func _resolve_pending_hit() -> void:
	if pending_hit_resolved:
		return
	if _pending_editorial_aim_miss:
		# The firing animation and alert still happen; only the final ray/hit is
		# rejected. Projectile attacks likewise produce no homing projectile.
		pending_hit_resolved = true
		_pending_editorial_aim_miss = false
		return
	super._resolve_pending_hit()
	_pending_editorial_aim_miss = false


func _refresh_editorial_tag_effects() -> void:
	editorial_regroup_multiplier = 1.0
	for tag: String in editorial_ai_tags:
		var normalized := tag.to_lower()
		if _contains_any(normalized, ["counter", "intercept", "mutual_support", "four_point"]):
			editorial_regroup_multiplier = minf(editorial_regroup_multiplier, 0.82)
		elif _contains_any(normalized, ["protect", "guard", "cordon", "defense"]):
			editorial_regroup_multiplier = minf(editorial_regroup_multiplier, 0.90)


static func _contains_any(value: String, needles: Array[String]) -> bool:
	for needle: String in needles:
		if value.contains(needle):
			return true
	return false


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
	if tactical_ranges_visible and is_alive:
		_draw_tactical_ranges()
	if behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK, BehaviorState.SEARCH]:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.95, 0.20, 0.12), 2.0)


func _draw_tactical_ranges() -> void:
	var vision_radii := Vector2(
		float(sense_profile.get("horizontal_radius", 0.0)),
		float(sense_profile.get("vertical_radius", 0.0)),
	)
	if vision_radii.x > 0.0 and vision_radii.y > 0.0:
		var near_ratio := clampf(float(sense_profile.get("near_band_ratio", 0.5)), 0.1, 1.0)
		# Commandos-style directional perception: green is detectable while the
		# target stands, red is the outer band that needs a prone target. Every
		# ray stops at the first L2 sight obstruction, so walls cut the fan.
		_draw_visibility_fan(vision_radii, 1.0, Color(0.92, 0.22, 0.16, 0.74))
		_draw_visibility_fan(vision_radii, near_ratio, Color(0.20, 0.96, 0.42, 0.88))
	var attack_radii := Vector2(
		float(weapon_profile.get("horizontal_range", 0.0)),
		float(weapon_profile.get("vertical_range", 0.0)),
	)
	if attack_radii.x > 0.0 and attack_radii.y > 0.0:
		_draw_ellipse_outline(attack_radii, Color(0.92, 0.20, 0.16, 0.72), 1.5)


func _draw_ellipse_outline(radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index: int in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(points, color, width, true)

func _draw_visibility_fan(radii: Vector2, ratio: float, outline: Color) -> void:
	# animation_group_index is generated directly from the last movement/attack
	# vector. It is therefore the visual direction that the player sees.
	var octant := posmod(animation_group_index - 5, 8)
	var center: float = rad_to_deg(float(octant) * PI / 4.0)
	var half_angle: float = TACTICAL_SENSES.original_direction_half_angle_degrees(original_direction_index)
	if center < 0.0 or half_angle <= 0.0:
		return
	var points := PackedVector2Array([Vector2.ZERO])
	const STEPS := 10
	for step: int in range(STEPS + 1):
		var degrees: float = center - half_angle + (2.0 * half_angle * float(step) / float(STEPS))
		var candidate := Vector2(cos(deg_to_rad(degrees)) * radii.x * ratio, sin(deg_to_rad(degrees)) * radii.y * ratio)
		var endpoint := _clip_vision_ray(candidate)
		points.append(endpoint)
	if points.size() >= 3:
		draw_polyline(points, outline, 1.5, true)

func _clip_vision_ray(candidate: Vector2) -> Vector2:
	if dynamic_occupancy == null:
		return candidate
	var accepted := Vector2.ZERO
	const STEPS := 8
	for step: int in range(1, STEPS + 1):
		var probe := candidate * (float(step) / float(STEPS))
		if not dynamic_occupancy.has_line_of_sight(position, position + probe, [scene_index]):
			break
		accepted = probe
	return accepted
