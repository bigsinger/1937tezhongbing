class_name EnemyUnit
extends "res://scripts/squad_unit.gd"

const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const LEGACY_WORLD_ITEM_RULES: Script = preload(
	"res://scripts/legacy_world_item_rules.gd"
)
const LEGACY_CORPSE_DISCOVERY_RULES: Script = preload(
	"res://scripts/legacy_corpse_discovery_rules.gd"
)
const LEGACY_ENEMY_AI_RULES: Script = preload(
	"res://scripts/legacy_enemy_ai_rules.gd"
)
const SENSE_INTERVAL_SECONDS := 0.20
const CHASE_REPLAN_SECONDS := 0.50
const SEARCH_TIMEOUT_SECONDS := 2.50
const PATROL_PATH_RETRY_MIN_SECONDS := 0.75
const PATROL_PATH_RETRY_STEP_SECONDS := 0.05
## Stable-MOD differential capture recovers a 134 px/s uninterrupted patrol
## displacement in m000.  Original-parity mode applies no editorial mission
## multiplier, so the recovered value is the runtime source of truth.
const STABLE_MOD_BASE_PATROL_SPEED := 134.0
## Entry/steady MOD snapshots are five seconds apart. Across 25 guards that
## reverse a recovered waypoint in that window, the median residual endpoint
## hold is about 2.1 seconds after subtracting travel at 134 px/s.  The
## frame-bound remainder aligns the second audited one-second interval with
## the stable process capture instead of letting three guards depart early.
const STABLE_MOD_PATROL_WAYPOINT_HOLD_SECONDS := 2.1
## The executable's 20..39 reaction-counter range is independent of the 85 ms
## sprite frame clock.  The identity-resolved m000 trace places two scene-1598
## rifle hits in consecutive checkpoints one second apart; a 30 Hz reaction
## counter plus the recovered two-frame attack action reproduces that bound.
const ORIGINAL_ATTACK_REACTION_TICK_SECONDS := 1.0 / 30.0
const ATTACK_RECHECK_MIN_SECONDS := 20.0 * ORIGINAL_ATTACK_REACTION_TICK_SECONDS
const ATTACK_RECHECK_MAX_SECONDS := 39.0 * ORIGINAL_ATTACK_REACTION_TICK_SECONDS
## Editorial accuracy model. The original executable's exact miss formula has
## not been recovered; this bounded base chance makes the authored per-level
## aim-error curve affect real hit resolution without pretending otherwise.
const EDITORIAL_BASE_AIM_MISS_CHANCE := 0.10

enum BehaviorState {
	PATROL,
	CHASE,
	ATTACK,
	SEARCH,
	REGROUP,
	WORLD_ITEM,
	CORPSE_DISCOVERY,
}

signal attack_committed(attacker: EnemyUnit, target: Node2D, attack_type: int)
signal legacy_world_item_interaction_requested(
	enemy: EnemyUnit,
	world_item: Node2D,
)
signal legacy_hypnosis_changed(enemy: EnemyUnit, active: bool)
signal legacy_corpse_discovery_triggered(
	observer: EnemyUnit,
	corpse: EnemyUnit,
)

var behavior_state := BehaviorState.PATROL
var patrol_waypoints := PackedVector2Array()
var patrol_index := 0
var patrol_enabled := false
var patrol_wait_remaining := 0.0
var patrol_path_in_flight := false
var original_direction_index := 1
var sense_profile: Dictionary = {}
var potential_targets: Array[Node2D] = []
var potential_world_items: Array[Node2D] = []
var potential_corpses: Array[Node2D] = []
var current_target: Node2D
var legacy_world_item_target: Node2D
var legacy_world_item_interaction_pending := false
var legacy_world_item_replan_elapsed := 0.0
var pending_legacy_world_item_serial := 0
var legacy_hypnosis_active := false
var legacy_hypnosis_counter := 0
var legacy_poison_active := false
var legacy_poison_counter := 0
var legacy_distraction_active := false
var legacy_distraction_counter := 0
var legacy_distraction_limit := 0
var legacy_effect_random_state := 1
var legacy_corpse_discovered := false
var legacy_corpse_buried := false
var legacy_corpse_target: Node2D
var pending_legacy_corpse_scene_index := -1
var legacy_corpse_reaction_counter := 0
var legacy_corpse_reaction_limit := 0
var legacy_corpse_reaction_elapsed := 0.0
var legacy_corpse_random_state := 1
var legacy_reinforcement_spawned := false
var legacy_reinforcement_source_marker_scene_index := -1
var legacy_reinforcement_serial := 0
var legacy_reinforcement_leader_scene_index := -1
var last_known_target_position := Vector2.ZERO
var sense_elapsed := 0.0
var chase_replan_elapsed := 0.0
var search_elapsed := 0.0
var legacy_search_active := false
var legacy_search_finishing := false
var legacy_search_origin := Vector2.ZERO
var legacy_search_point_index := 0
var legacy_search_wait_counter := 0
var legacy_search_wait_limit := 0
var legacy_search_tick_elapsed := 0.0
var legacy_search_random_state := 1
var attack_recheck_elapsed := 0.0
var attack_recheck_seconds := ATTACK_RECHECK_MIN_SECONDS
var attack_count := 0
var path_request_delay_remaining := 0.0
var patrol_path_retry_seconds := PATROL_PATH_RETRY_MIN_SECONDS
var special_control_lock_count := 0
var special_control_source: Node2D
var tactical_ranges_visible := false
var mission_ai_coordinator: Node
## No miss dispersion is applied until an explicitly editorial difficulty
## profile configures it.  Original-parity mode therefore uses the recovered
## hit/damage path without a remake-only random miss layer.
var editorial_aim_error_multiplier := 0.0
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
		Vector2(
			float(entity.get("reference_x", entity.get("x", 0))),
			float(entity.get("reference_y", entity.get("y", 0))),
		),
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
	configure_runtime_actor_type(entity)
	move_speed = STABLE_MOD_BASE_PATROL_SPEED
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
	patrol_wait_remaining = 0.0
	patrol_path_in_flight = false
	legacy_effect_random_state = int(
		(scene_index * 1103515245 + 12345) & 0x7fffffff
	)
	if legacy_effect_random_state == 0:
		legacy_effect_random_state = 1
	legacy_corpse_random_state = int(
		(scene_index * 1664525 + 1013904223) & 0x7fffffff
	)
	if legacy_corpse_random_state == 0:
		legacy_corpse_random_state = 1
	legacy_search_random_state = int(
		(scene_index * 22695477 + 1) & 0x7fffffff
	)
	if legacy_search_random_state == 0:
		legacy_search_random_state = 1
	_clear_legacy_coordinate_search()
	legacy_corpse_discovered = false
	legacy_corpse_buried = false
	_clear_legacy_corpse_attention()
	legacy_reinforcement_spawned = false
	legacy_reinforcement_source_marker_scene_index = -1
	legacy_reinforcement_serial = 0
	legacy_reinforcement_leader_scene_index = -1
	_clear_all_legacy_world_item_runtime()
	attack_recheck_seconds = _deterministic_attack_interval()
	queue_redraw()


func set_potential_targets(targets: Array[Node2D]) -> void:
	potential_targets = targets.duplicate()


func set_potential_world_items(items: Array) -> void:
	potential_world_items.clear()
	for item_value: Variant in items:
		if item_value is Node2D and is_instance_valid(item_value):
			potential_world_items.append(item_value as Node2D)


func set_potential_corpses(corpses: Array) -> void:
	potential_corpses.clear()
	for corpse_value: Variant in corpses:
		if corpse_value is Node2D and is_instance_valid(corpse_value):
			potential_corpses.append(corpse_value as Node2D)


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
	if not is_alive or combat_action != CombatAction.NONE or hurt_remaining > 0.0:
		super._physics_process(safe_delta)
		return
	var legacy_effect_blocked_at_start := (
		legacy_hypnosis_active
		or legacy_poison_active
		or legacy_distraction_active
	)
	if legacy_effect_blocked_at_start:
		advance_legacy_world_item_effect_ticks(1)
		super._physics_process(safe_delta)
		original_direction_index = (
			IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(
				animation_group_index
			)
		)
		return
	path_request_delay_remaining = maxf(path_request_delay_remaining - safe_delta, 0.0)
	sense_elapsed += safe_delta
	chase_replan_elapsed += safe_delta
	attack_recheck_elapsed += safe_delta
	if sense_elapsed >= SENSE_INTERVAL_SECONDS and behavior_state != BehaviorState.REGROUP:
		sense_elapsed = fmod(sense_elapsed, SENSE_INTERVAL_SECONDS)
		_update_detection()
	var attention_holds_idle := (
		is_special_controlled()
		and behavior_state == BehaviorState.PATROL
		and current_target == null
	)
	if not attention_holds_idle:
		_update_behavior(safe_delta)
	super._physics_process(safe_delta)
	if attention_holds_idle and is_special_controlled():
		_face_special_control_source()
	original_direction_index = (
		IMPORTED_SPRITE_ANIMATION.direction_index_for_legacy_group(animation_group_index)
	)


func apply_special_control(source: Node2D = null) -> bool:
	if not is_alive:
		return false
	special_control_lock_count += 1
	special_control_source = source
	if special_control_lock_count == 1:
		# Target +656 does not erase an existing combat target. It suppresses
		# ordinary idle/path updates and makes the target face the dedicated
		# source actor until movement or a combat transition clears the flag.
		if behavior_state == BehaviorState.PATROL and current_target == null:
			cancel_path()
			patrol_wait_remaining = 0.0
			patrol_path_in_flight = false
			apply_idle_frame()
			_face_special_control_source()
		queue_redraw()
	return true


func refresh_special_control_source(source: Node2D = null) -> bool:
	if special_control_lock_count <= 0:
		return false
	special_control_source = source
	_face_special_control_source()
	return true


func release_special_control(_source: Node2D = null) -> bool:
	if special_control_lock_count <= 0:
		return false
	special_control_lock_count -= 1
	if special_control_lock_count == 0:
		special_control_source = null
		sense_elapsed = SENSE_INTERVAL_SECONDS
		chase_replan_elapsed = CHASE_REPLAN_SECONDS
		path_request_delay_remaining = 0.0
		queue_redraw()
	return true


func is_special_controlled() -> bool:
	return special_control_lock_count > 0


func _release_special_control_for_combat() -> bool:
	if special_control_lock_count <= 0:
		return false
	special_control_lock_count = 0
	special_control_source = null
	path_request_delay_remaining = 0.0
	queue_redraw()
	return true


func _face_special_control_source() -> void:
	if not is_instance_valid(special_control_source):
		return
	var direction := special_control_source.position - position
	if direction.is_zero_approx():
		return
	set_animation_group(direction_group_index(direction))
	apply_idle_frame()
	queue_redraw()


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
		# Hearing is event driven. A standing, silent target inside the recovered
		# radius must not be treated as a continuous omnidirectional noise source;
		# Main routes explicit N-key, dropped-item, shot and explosion events to
		# investigate_position/receive_alert.
		if not visible:
			continue
		var distance_squared := position.distance_squared_to(target.position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_visible = target
	if nearest_visible != null:
		_clear_legacy_world_item_target()
		_clear_legacy_corpse_attention()
		_release_special_control_for_combat()
		var already_tracking := (
			current_target == nearest_visible
			and behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK]
		)
		current_target = nearest_visible
		last_known_target_position = nearest_visible.position
		search_elapsed = 0.0
		if not already_tracking:
			# The original actor's reaction counter runs while the guard patrols.
			# Do not discard that accumulated time at first visual contact: a
			# ready guard can commit the first shot immediately, as observed in
			# the stable m000 natural-contact trace.
			behavior_state = (
				BehaviorState.ATTACK if _can_attack_current_target() else BehaviorState.CHASE
			)
	elif current_target != null and behavior_state in [BehaviorState.CHASE, BehaviorState.ATTACK]:
		_release_special_control_for_combat()
		if mission_ai_coordinator == null:
			_begin_legacy_coordinate_search(last_known_target_position)
		else:
			current_target = null
			behavior_state = BehaviorState.SEARCH
			search_elapsed = 0.0
			_issue_path_to(last_known_target_position)
	elif (
		behavior_state in [
			BehaviorState.PATROL,
			BehaviorState.WORLD_ITEM,
			BehaviorState.CORPSE_DISCOVERY,
		]
		and not is_special_controlled()
		and not has_active_legacy_world_item_effect()
	):
		if behavior_state != BehaviorState.CORPSE_DISCOVERY:
			var visible_corpse := _first_visible_legacy_corpse()
			if visible_corpse != null:
				_begin_legacy_corpse_discovery(visible_corpse)
				return
		if behavior_state == BehaviorState.PATROL:
			var visible_world_item := _first_visible_allowed_world_item()
			if visible_world_item != null:
				_begin_legacy_world_item_investigation(visible_world_item)


func _update_behavior(delta: float) -> void:
	match behavior_state:
		BehaviorState.PATROL:
			_update_patrol(delta)
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
			if legacy_search_active or legacy_search_finishing:
				_update_legacy_coordinate_search(delta)
				return
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
		BehaviorState.WORLD_ITEM:
			_update_legacy_world_item_investigation(delta)
		BehaviorState.CORPSE_DISCOVERY:
			_update_legacy_corpse_discovery(delta)


func _update_patrol(delta: float) -> void:
	if not patrol_enabled or patrol_waypoints.is_empty():
		return
	if path_request_delay_remaining > 0.0:
		return
	if movement_path_index < movement_path.size():
		return
	if patrol_path_in_flight:
		patrol_path_in_flight = false
		patrol_wait_remaining = STABLE_MOD_PATROL_WAYPOINT_HOLD_SECONDS
		apply_idle_frame()
		return
	if patrol_wait_remaining > 0.0:
		patrol_wait_remaining = maxf(patrol_wait_remaining - maxf(delta, 0.0), 0.0)
		return
	var next_index := next_unreached_patrol_index(patrol_waypoints, patrol_index, position)
	if next_index < 0:
		path_request_delay_remaining = patrol_path_retry_seconds
		return
	patrol_index = next_index
	var destination := patrol_waypoints[patrol_index]
	patrol_path_in_flight = _issue_path_to(destination)


func _enter_patrol() -> void:
	_clear_legacy_world_item_target()
	_clear_legacy_corpse_attention()
	_clear_legacy_coordinate_search()
	behavior_state = BehaviorState.PATROL
	search_elapsed = 0.0
	regroup_remaining = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	patrol_wait_remaining = 0.0
	patrol_path_in_flight = false
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
	_clear_legacy_world_item_target()
	_clear_legacy_corpse_attention()
	_clear_legacy_coordinate_search()
	_release_special_control_for_combat()
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
	return _begin_legacy_coordinate_search(world_position)


func receive_original_coordinate_alert(world_position: Vector2) -> bool:
	if (
		not is_alive
		or (
			current_target != null
			and is_instance_valid(current_target)
			and behavior_state in [
				BehaviorState.CHASE,
				BehaviorState.ATTACK,
			]
		)
	):
		return false
	return _begin_legacy_coordinate_search(world_position)


func _begin_legacy_coordinate_search(world_position: Vector2) -> bool:
	if not is_alive:
		return false
	_clear_legacy_world_item_target()
	_clear_legacy_corpse_attention()
	_release_special_control_for_combat()
	current_target = null
	clear_combat_target()
	last_known_target_position = world_position
	legacy_search_origin = world_position
	legacy_search_active = true
	legacy_search_finishing = false
	legacy_search_point_index = 0
	legacy_search_wait_counter = 0
	legacy_search_tick_elapsed = 0.0
	var sampled: Dictionary = (
		LEGACY_ENEMY_AI_RULES.reaction_limit_from_state(
			legacy_search_random_state
		)
	)
	legacy_search_random_state = int(sampled.get("state", 1))
	legacy_search_wait_limit = int(
		sampled.get(
			"limit",
			LEGACY_ENEMY_AI_RULES.REACTION_MINIMUM_LIMIT,
		)
	)
	search_elapsed = 0.0
	chase_replan_elapsed = CHASE_REPLAN_SECONDS
	behavior_state = BehaviorState.SEARCH
	_issue_path_to(world_position)
	return true


func _update_legacy_coordinate_search(delta: float) -> void:
	if legacy_search_finishing:
		if movement_path_index >= movement_path.size():
			_enter_patrol()
		return
	# The initial coordinate command must be allowed to arrive before the local
	# five-point sub_45E4B0 sweep begins. This preserves playable path intent
	# while retaining the recovered counter ranges and search geometry.
	if movement_path_index < movement_path.size():
		return
	legacy_search_tick_elapsed += maxf(delta, 0.0)
	while (
		legacy_search_tick_elapsed
		>= ORIGINAL_ATTACK_REACTION_TICK_SECONDS
	):
		legacy_search_tick_elapsed -= ORIGINAL_ATTACK_REACTION_TICK_SECONDS
		legacy_search_wait_counter += 1
		if not LEGACY_ENEMY_AI_RULES.counter_has_completed(
			legacy_search_wait_counter,
			legacy_search_wait_limit,
		):
			continue
		if (
			legacy_search_point_index
			>= LEGACY_ENEMY_AI_RULES.SEARCH_POINT_COUNT
		):
			_enter_patrol()
			return
		var sampled: Dictionary = (
			LEGACY_ENEMY_AI_RULES.local_search_point_from_state(
				legacy_search_random_state,
				position,
				_legacy_search_world_bounds(),
			)
		)
		legacy_search_random_state = int(sampled.get("state", 1))
		legacy_search_wait_counter = 0
		legacy_search_wait_limit = int(
			sampled.get(
				"next_wait_limit",
				LEGACY_ENEMY_AI_RULES.SEARCH_WAIT_MINIMUM_LIMIT,
			)
		)
		legacy_search_point_index += 1
		var search_point := sampled.get("point", position) as Vector2
		last_known_target_position = search_point
		_issue_path_to(search_point)
		if (
			legacy_search_point_index
			>= LEGACY_ENEMY_AI_RULES.SEARCH_POINT_COUNT
		):
			# The original clears its search flag on the tick after the fifth
			# coordinate is issued, but the already-issued movement survives.
			legacy_search_active = false
			legacy_search_finishing = true
		return
		if movement_path_index < movement_path.size():
			return


func _clear_legacy_coordinate_search() -> void:
	legacy_search_active = false
	legacy_search_finishing = false
	legacy_search_origin = Vector2.ZERO
	legacy_search_point_index = 0
	legacy_search_wait_counter = 0
	legacy_search_wait_limit = 0
	legacy_search_tick_elapsed = 0.0


func _legacy_search_world_bounds() -> Rect2:
	if dynamic_occupancy != null:
		var source_navigation: Variant = dynamic_occupancy.get("navigation")
		if source_navigation is RefCounted:
			var dimensions: Vector2i = source_navigation.get("dimensions")
			var cell_size: Vector2i = source_navigation.get("cell_size")
			var size := Vector2(dimensions * cell_size)
			if size.x > 0.0 and size.y > 0.0:
				return Rect2(Vector2.ZERO, size)
	return Rect2(Vector2.ZERO, Vector2(65535.0, 65535.0))


func can_discover_legacy_corpse(corpse: Node2D) -> bool:
	if (
		not is_alive
		or faction_id != LEGACY_CORPSE_DISCOVERY_RULES.ENEMY_FACTION_ID
		or corpse == null
		or corpse == self
		or not is_instance_valid(corpse)
		or not LEGACY_CORPSE_DISCOVERY_RULES.is_candidate(
			int(corpse.get("faction_id")),
			bool(corpse.get("is_alive")),
			bool(corpse.get("legacy_corpse_discovered")),
			bool(corpse.get("legacy_corpse_buried")),
		)
	):
		return false
	if TACTICAL_SENSES.original_visibility_band(
		position,
		corpse.position,
		original_direction_index,
		sense_profile,
		false,
	) != LEGACY_CORPSE_DISCOVERY_RULES.REQUIRED_VISIBILITY_BAND:
		return false
	if not bool(sense_profile.get("requires_line_of_sight", true)):
		return true
	if (
		dynamic_occupancy == null
		or not dynamic_occupancy.has_method("has_line_of_sight")
	):
		return false
	var ignored: Array = []
	if scene_index >= 0:
		ignored.append(scene_index)
	var corpse_scene_index := int(corpse.get("scene_index"))
	if corpse_scene_index >= 0:
		ignored.append(corpse_scene_index)
	return bool(
		dynamic_occupancy.has_line_of_sight(
			position,
			corpse.position,
			ignored,
		)
	)


func _first_visible_legacy_corpse() -> Node2D:
	# sub_45C4C0 returns the first eligible world actor. It never chooses the
	# nearest corpse, and the +0x258 claim prevents a second observer.
	for corpse: Node2D in potential_corpses:
		if can_discover_legacy_corpse(corpse):
			return corpse
	return null


func _begin_legacy_corpse_discovery(corpse: Node2D) -> bool:
	if not can_discover_legacy_corpse(corpse):
		return false
	_clear_legacy_world_item_target()
	legacy_corpse_target = corpse
	pending_legacy_corpse_scene_index = -1
	corpse.set("legacy_corpse_discovered", true)
	legacy_corpse_reaction_counter = 0
	legacy_corpse_reaction_elapsed = 0.0
	var sampled: Dictionary = (
		LEGACY_CORPSE_DISCOVERY_RULES.reaction_limit_from_state(
			legacy_corpse_random_state
		)
	)
	legacy_corpse_random_state = int(sampled.get("state", 1))
	legacy_corpse_reaction_limit = int(
		sampled.get(
			"limit",
			LEGACY_CORPSE_DISCOVERY_RULES.REACTION_MINIMUM_LIMIT,
		)
	)
	current_target = null
	clear_combat_target()
	behavior_state = BehaviorState.CORPSE_DISCOVERY
	last_known_target_position = corpse.position
	cancel_path()
	_issue_path_to(corpse.position)
	legacy_corpse_discovery_triggered.emit(self, corpse)
	return true


func _update_legacy_corpse_discovery(delta: float) -> void:
	if (
		legacy_corpse_target == null
		or not is_instance_valid(legacy_corpse_target)
		or bool(legacy_corpse_target.get("legacy_corpse_buried"))
	):
		_enter_patrol()
		return
	if movement_path_index < movement_path.size():
		return
	legacy_corpse_reaction_elapsed += maxf(delta, 0.0)
	while (
		legacy_corpse_reaction_elapsed
		>= ORIGINAL_ATTACK_REACTION_TICK_SECONDS
	):
		legacy_corpse_reaction_elapsed -= ORIGINAL_ATTACK_REACTION_TICK_SECONDS
		legacy_corpse_reaction_counter += 1
		if LEGACY_CORPSE_DISCOVERY_RULES.reaction_has_completed(
			legacy_corpse_reaction_counter,
			legacy_corpse_reaction_limit,
		):
			var corpse_position := legacy_corpse_target.position
			_begin_legacy_coordinate_search(corpse_position)
			return
	if movement_path_index >= movement_path.size():
		var facing := legacy_corpse_target.position - position
		if not facing.is_zero_approx():
			set_animation_group(direction_group_index(facing))
			apply_idle_frame()


func mark_legacy_corpse_buried(value: bool = true) -> void:
	legacy_corpse_buried = value
	if value:
		legacy_corpse_discovered = true
	queue_redraw()


func receive_legacy_corpse_reinforcement_order(
	corpse: Node2D,
	leader_scene_index: int = -1,
) -> bool:
	if not is_alive or corpse == null or not is_instance_valid(corpse):
		return false
	legacy_reinforcement_leader_scene_index = leader_scene_index
	return investigate_position(corpse.position)


func can_consider_legacy_world_item(world_item: Node2D) -> bool:
	if (
		not is_alive
		or faction_id != LEGACY_WORLD_ITEM_RULES.ENEMY_FACTION_ID
		or world_item == null
		or not is_instance_valid(world_item)
		or not world_item.has_method("is_available_original_world_item")
		or not bool(world_item.call("is_available_original_world_item"))
	):
		return false
	var item_id := int(world_item.get("original_actor_type"))
	if not LEGACY_WORLD_ITEM_RULES.accepts_item(
		runtime_actor_type,
		item_id,
		faction_id,
	):
		return false
	if TACTICAL_SENSES.original_visibility_band(
		position,
		world_item.position,
		original_direction_index,
		sense_profile,
		false,
	) != 1:
		return false
	if not bool(sense_profile.get("requires_line_of_sight", true)):
		return true
	if (
		dynamic_occupancy == null
		or not dynamic_occupancy.has_method("has_line_of_sight")
	):
		return false
	var ignored: Array = []
	if scene_index >= 0:
		ignored.append(scene_index)
	return bool(
		dynamic_occupancy.has_line_of_sight(
			position,
			world_item.position,
			ignored,
		)
	)


func apply_legacy_world_item_effect(
	item_id: int,
	forced_distraction_limit: int = -1,
) -> Dictionary:
	var profile: Dictionary = LEGACY_WORLD_ITEM_RULES.effect_profile(item_id)
	if profile.is_empty() or not is_alive:
		return {}
	var kind := str(profile.get("kind", ""))
	var result := profile.duplicate(true)
	_clear_legacy_world_item_target()
	_clear_legacy_corpse_attention()
	current_target = null
	clear_combat_target()
	auto_combat_enabled = false
	cancel_path()
	behavior_state = BehaviorState.PATROL
	match kind:
		"hypnosis":
			legacy_hypnosis_active = true
			legacy_hypnosis_counter = 0
			set_selected(true)
			legacy_hypnosis_changed.emit(self, true)
		"poison_and_distraction":
			_start_legacy_distraction(forced_distraction_limit)
			legacy_poison_active = true
			legacy_poison_counter = 0
			result["distraction_limit"] = legacy_distraction_limit
		"distraction":
			_start_legacy_distraction(forced_distraction_limit)
			result["distraction_limit"] = legacy_distraction_limit
		"carry":
			pass
		_:
			return {}
	queue_redraw()
	return result


func advance_legacy_world_item_effect_ticks(ticks: int = 1) -> Dictionary:
	var result := {
		"hypnosis_finished": false,
		"distraction_finished": false,
		"poison_damage": 0,
	}
	for unused_tick: int in range(maxi(ticks, 0)):
		# sub_45C710 returns immediately from both hypnosis and poison branches.
		# This means a simultaneous poison/distraction effect does not advance its
		# ordinary distraction counter before the poison branch resolves.
		if legacy_hypnosis_active:
			legacy_hypnosis_counter += 1
			if (
				legacy_hypnosis_counter
				> LEGACY_WORLD_ITEM_RULES.HYPNOSIS_COUNTER_LIMIT
			):
				legacy_hypnosis_active = false
				legacy_hypnosis_counter = 0
				set_selected(false)
				result["hypnosis_finished"] = true
				legacy_hypnosis_changed.emit(self, false)
			continue
		if legacy_poison_active:
			legacy_poison_counter += 1
			if (
				legacy_poison_counter
				> LEGACY_WORLD_ITEM_RULES.POISON_COUNTER_LIMIT
			):
				result["poison_damage"] = (
					int(result["poison_damage"])
					+ take_damage(LEGACY_WORLD_ITEM_RULES.POISON_DAMAGE, null)
				)
			continue
		if legacy_distraction_active:
			legacy_distraction_counter += 1
			if legacy_distraction_counter > legacy_distraction_limit:
				legacy_distraction_active = false
				legacy_distraction_counter = 0
				legacy_distraction_limit = 0
				result["distraction_finished"] = true
	queue_redraw()
	return result


func has_active_legacy_world_item_effect() -> bool:
	return (
		legacy_hypnosis_active
		or legacy_poison_active
		or legacy_distraction_active
	)


func complete_legacy_world_item_interaction(
	world_item: Node2D,
	success: bool,
) -> void:
	if world_item != legacy_world_item_target:
		return
	_clear_legacy_world_item_target()
	if behavior_state == BehaviorState.WORLD_ITEM:
		_enter_patrol()
	if not success:
		path_request_delay_remaining = patrol_path_retry_seconds


func legacy_enemy_ai_state_snapshot() -> Dictionary:
	return {
		"search_active": legacy_search_active,
		"search_finishing": legacy_search_finishing,
		"search_origin_x": legacy_search_origin.x,
		"search_origin_y": legacy_search_origin.y,
		"search_point_index": legacy_search_point_index,
		"search_wait_counter": legacy_search_wait_counter,
		"search_wait_limit": legacy_search_wait_limit,
		"search_tick_elapsed": legacy_search_tick_elapsed,
		"search_random_state": legacy_search_random_state,
	}


func restore_legacy_enemy_ai_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	legacy_search_active = bool(state.get("search_active", false))
	legacy_search_finishing = bool(
		state.get("search_finishing", false)
	)
	legacy_search_origin = Vector2(
		float(state.get("search_origin_x", 0.0)),
		float(state.get("search_origin_y", 0.0)),
	)
	legacy_search_point_index = clampi(
		int(state.get("search_point_index", 0)),
		0,
		LEGACY_ENEMY_AI_RULES.SEARCH_POINT_COUNT,
	)
	legacy_search_wait_counter = maxi(
		int(state.get("search_wait_counter", 0)),
		0,
	)
	legacy_search_wait_limit = maxi(
		int(state.get("search_wait_limit", 0)),
		0,
	)
	legacy_search_tick_elapsed = maxf(
		float(state.get("search_tick_elapsed", 0.0)),
		0.0,
	)
	legacy_search_random_state = maxi(
		int(state.get("search_random_state", legacy_search_random_state)),
		1,
	)
	return true


func resume_restored_legacy_search() -> bool:
	if (
		not is_alive
		or behavior_state != BehaviorState.SEARCH
		or (not legacy_search_active and not legacy_search_finishing)
	):
		return false
	return _issue_path_to(last_known_target_position)


func legacy_world_item_state_snapshot() -> Dictionary:
	return {
		"target_serial": (
			int(legacy_world_item_target.get("world_item_serial"))
			if (
				legacy_world_item_target != null
				and is_instance_valid(legacy_world_item_target)
			)
			else pending_legacy_world_item_serial
		),
		"interaction_pending": legacy_world_item_interaction_pending,
		"replan_elapsed": legacy_world_item_replan_elapsed,
		"hypnosis_active": legacy_hypnosis_active,
		"hypnosis_counter": legacy_hypnosis_counter,
		"poison_active": legacy_poison_active,
		"poison_counter": legacy_poison_counter,
		"distraction_active": legacy_distraction_active,
		"distraction_counter": legacy_distraction_counter,
		"distraction_limit": legacy_distraction_limit,
		"random_state": legacy_effect_random_state,
	}


func restore_legacy_world_item_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	pending_legacy_world_item_serial = maxi(
		int(state.get("target_serial", 0)),
		0,
	)
	legacy_world_item_interaction_pending = false
	legacy_world_item_replan_elapsed = maxf(
		float(state.get("replan_elapsed", 0.0)),
		0.0,
	)
	legacy_hypnosis_active = bool(state.get("hypnosis_active", false))
	legacy_hypnosis_counter = maxi(
		int(state.get("hypnosis_counter", 0)),
		0,
	)
	legacy_poison_active = bool(state.get("poison_active", false))
	legacy_poison_counter = maxi(int(state.get("poison_counter", 0)), 0)
	legacy_distraction_active = bool(
		state.get("distraction_active", false)
	)
	legacy_distraction_counter = maxi(
		int(state.get("distraction_counter", 0)),
		0,
	)
	legacy_distraction_limit = maxi(
		int(state.get("distraction_limit", 0)),
		0,
	)
	legacy_effect_random_state = maxi(
		int(state.get("random_state", legacy_effect_random_state)),
		1,
	)
	if legacy_hypnosis_active:
		set_selected(true)
	return true


func bind_restored_legacy_world_item_target(items: Array) -> bool:
	if pending_legacy_world_item_serial <= 0:
		return true
	for item_value: Variant in items:
		if (
			item_value is Node2D
			and is_instance_valid(item_value)
			and int((item_value as Node2D).get("world_item_serial"))
				== pending_legacy_world_item_serial
		):
			legacy_world_item_target = item_value as Node2D
			legacy_world_item_interaction_pending = false
			pending_legacy_world_item_serial = 0
			if behavior_state == BehaviorState.WORLD_ITEM:
				_issue_path_to(legacy_world_item_target.position)
			return true
	pending_legacy_world_item_serial = 0
	if behavior_state == BehaviorState.WORLD_ITEM:
		_enter_patrol()
	return false


func legacy_corpse_state_snapshot() -> Dictionary:
	return {
		"discovered": legacy_corpse_discovered,
		"buried": legacy_corpse_buried,
		"target_scene_index": (
			int(legacy_corpse_target.get("scene_index"))
			if (
				legacy_corpse_target != null
				and is_instance_valid(legacy_corpse_target)
			)
			else pending_legacy_corpse_scene_index
		),
		"reaction_counter": legacy_corpse_reaction_counter,
		"reaction_limit": legacy_corpse_reaction_limit,
		"reaction_elapsed": legacy_corpse_reaction_elapsed,
		"random_state": legacy_corpse_random_state,
		"reinforcement_spawned": legacy_reinforcement_spawned,
		"reinforcement_source_marker_scene_index": (
			legacy_reinforcement_source_marker_scene_index
		),
		"reinforcement_serial": legacy_reinforcement_serial,
		"reinforcement_leader_scene_index": (
			legacy_reinforcement_leader_scene_index
		),
	}


func restore_legacy_corpse_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	legacy_corpse_discovered = bool(state.get("discovered", false))
	legacy_corpse_buried = bool(state.get("buried", false))
	pending_legacy_corpse_scene_index = int(
		state.get("target_scene_index", -1)
	)
	legacy_corpse_target = null
	legacy_corpse_reaction_counter = maxi(
		int(state.get("reaction_counter", 0)),
		0,
	)
	legacy_corpse_reaction_limit = maxi(
		int(state.get("reaction_limit", 0)),
		0,
	)
	legacy_corpse_reaction_elapsed = maxf(
		float(state.get("reaction_elapsed", 0.0)),
		0.0,
	)
	legacy_corpse_random_state = maxi(
		int(state.get("random_state", legacy_corpse_random_state)),
		1,
	)
	legacy_reinforcement_spawned = bool(
		state.get("reinforcement_spawned", false)
	)
	legacy_reinforcement_source_marker_scene_index = int(
		state.get("reinforcement_source_marker_scene_index", -1)
	)
	legacy_reinforcement_serial = maxi(
		int(state.get("reinforcement_serial", 0)),
		0,
	)
	legacy_reinforcement_leader_scene_index = int(
		state.get("reinforcement_leader_scene_index", -1)
	)
	return true


func bind_restored_legacy_corpse_target(corpses: Array) -> bool:
	if pending_legacy_corpse_scene_index < 0:
		return true
	for corpse_value: Variant in corpses:
		if (
			corpse_value is Node2D
			and is_instance_valid(corpse_value)
			and int((corpse_value as Node2D).get("scene_index"))
				== pending_legacy_corpse_scene_index
		):
			legacy_corpse_target = corpse_value as Node2D
			pending_legacy_corpse_scene_index = -1
			if behavior_state == BehaviorState.CORPSE_DISCOVERY:
				_issue_path_to(legacy_corpse_target.position)
			return true
	pending_legacy_corpse_scene_index = -1
	if behavior_state == BehaviorState.CORPSE_DISCOVERY:
		_enter_patrol()
	return false


func _first_visible_allowed_world_item() -> Node2D:
	for world_item: Node2D in potential_world_items:
		if can_consider_legacy_world_item(world_item):
			return world_item
	return null


func _begin_legacy_world_item_investigation(world_item: Node2D) -> bool:
	if not can_consider_legacy_world_item(world_item):
		return false
	legacy_world_item_target = world_item
	legacy_world_item_interaction_pending = false
	legacy_world_item_replan_elapsed = CHASE_REPLAN_SECONDS
	current_target = null
	behavior_state = BehaviorState.WORLD_ITEM
	cancel_path()
	if LEGACY_WORLD_ITEM_RULES.is_adjacent_navigation_cell(
		position,
		world_item.position,
	):
		return true
	_issue_path_to(world_item.position)
	return true


func _update_legacy_world_item_investigation(delta: float) -> void:
	if (
		legacy_world_item_target == null
		or not is_instance_valid(legacy_world_item_target)
		or not legacy_world_item_target.has_method(
			"is_available_original_world_item"
		)
		or not bool(
			legacy_world_item_target.call(
				"is_available_original_world_item"
			)
		)
	):
		_clear_legacy_world_item_target()
		_enter_patrol()
		return
	if LEGACY_WORLD_ITEM_RULES.is_adjacent_navigation_cell(
		position,
		legacy_world_item_target.position,
	):
		cancel_path()
		if not legacy_world_item_interaction_pending:
			legacy_world_item_interaction_pending = true
			legacy_world_item_interaction_requested.emit(
				self,
				legacy_world_item_target,
			)
		return
	if movement_path_index < movement_path.size():
		return
	legacy_world_item_replan_elapsed += maxf(delta, 0.0)
	if legacy_world_item_replan_elapsed < CHASE_REPLAN_SECONDS:
		return
	legacy_world_item_replan_elapsed = 0.0
	_issue_path_to(legacy_world_item_target.position)


func _start_legacy_distraction(forced_limit: int = -1) -> void:
	legacy_distraction_active = true
	legacy_distraction_counter = 0
	if forced_limit >= LEGACY_WORLD_ITEM_RULES.DISTRACTION_MINIMUM_LIMIT:
		legacy_distraction_limit = forced_limit
		return
	var sample: Dictionary = (
		LEGACY_WORLD_ITEM_RULES.distraction_limit_from_state(
			legacy_effect_random_state
		)
	)
	legacy_effect_random_state = int(sample.get("state", 1))
	legacy_distraction_limit = int(
		sample.get(
			"limit",
			LEGACY_WORLD_ITEM_RULES.DISTRACTION_MINIMUM_LIMIT,
		)
	)


func _clear_legacy_world_item_target() -> void:
	legacy_world_item_target = null
	legacy_world_item_interaction_pending = false
	legacy_world_item_replan_elapsed = 0.0
	pending_legacy_world_item_serial = 0


func _clear_legacy_corpse_attention() -> void:
	legacy_corpse_target = null
	pending_legacy_corpse_scene_index = -1
	legacy_corpse_reaction_counter = 0
	legacy_corpse_reaction_limit = 0
	legacy_corpse_reaction_elapsed = 0.0


func _clear_all_legacy_world_item_runtime() -> void:
	_clear_legacy_world_item_target()
	legacy_hypnosis_active = false
	legacy_hypnosis_counter = 0
	legacy_poison_active = false
	legacy_poison_counter = 0
	legacy_distraction_active = false
	legacy_distraction_counter = 0
	legacy_distraction_limit = 0


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
		* ORIGINAL_ATTACK_REACTION_TICK_SECONDS
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
	# The fan is parameterized in the executable's logical isometric angle.
	# Scaling x/y by the recovered ellipse radii projects it to screen pixels.
	var center: float = TACTICAL_SENSES.original_direction_center_degrees(
		original_direction_index
	)
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
