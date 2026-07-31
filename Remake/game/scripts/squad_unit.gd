class_name SquadUnit
extends Node2D

const BASE_SPRITE_TICK_SECONDS := 0.085
## The actor AI counters recovered around M1937.exe sub_4587E0/sub_458A80
## advance on the same 30 Hz logic cadence already used by the recovered
## enemy reaction counter.
const ORIGINAL_AI_IDLE_TICK_SECONDS := 1.0 / 30.0
## RuntimeActor movement is advanced by M1937's 60 Hz actor update.  The
## secondary SPR triplet supplies the maximum X and Y displacement per tick
## (components 0 and 2); run mode uses three times the walk values.
const ORIGINAL_MOVEMENT_TICKS_PER_SECOND := 60.0
const ORIGINAL_RUN_STEP_MULTIPLIER := 3.0
const MAX_MOVEMENT_SUBSTEP_SECONDS := 1.0 / ORIGINAL_MOVEMENT_TICKS_PER_SECOND
const DEFAULT_REPLAN_BLOCKED_SECONDS := 0.25
const COMBAT_REPATH_SECONDS := 0.40
## Representative vector magnitudes retained for settings, probes and
## externally-authored speed scaling.  Exact path advancement remains
## component-capped at 360/180, 120/60 and 120/60 pixels per second.
const WALK_SPEED := 134.16407864998737
const RUN_SPEED := 402.49223594996215
const CRAWL_SPEED := 134.16407864998737
const TACTICAL_SENSES_SCRIPT: Script = preload("res://scripts/tactical_senses.gd")
const PROJECTILE_PROFILES: Script = preload("res://scripts/projectile_profiles.gd")
const COMBAT_INVENTORY_SCRIPT: Script = preload("res://scripts/combat_inventory.gd")
const BACKPACK_INVENTORY_SCRIPT: Script = preload("res://scripts/backpack_inventory.gd")
const LEGACY_SPECIAL_ACTION_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const LEGACY_COMBAT_RULES: Script = preload("res://scripts/legacy_combat_rules.gd")
const SPR_ANIMATION_RULES: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const AI_IDLE_RANDOM_RULES: Script = preload(
	"res://scripts/legacy_enemy_ai_rules.gd"
)
const LEGACY_DISGUISE_RULES: Script = preload(
	"res://scripts/legacy_disguise_rules.gd"
)
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

enum CombatAction { NONE, ATTACK, RELOAD, DEATH }

signal attack_started(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	alert_radius: float,
)
signal attack_hit(attacker: Node2D, target: Node2D, attack_type: int, damage: int)
signal projectile_requested(attacker: Node2D, target: Node2D, weapon_profile: Dictionary)
signal special_action_requested(attacker: Node2D, target: Node2D, weapon_profile: Dictionary)
signal original_disguise_attack_committed(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
)
signal original_disguise_transition_ready(unit: Node2D, item_id: int)
signal damage_received(unit: Node2D, attacker: Node2D, damage: int, remaining_hit_points: int)
signal died(unit: Node2D, killer: Node2D)
signal ammo_changed(unit: Node2D, magazine: int, reserve: int)

@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = RUN_SPEED

var display_name: String = "队员"
var body_color: Color = Color.WHITE
var selected: bool = false
var action_progress_ratio := -1.0
var target_position: Vector2
var movement_path := PackedVector2Array()
var movement_path_index := 0
var was_moving := false
var blocked_elapsed := 0.0
var blocked_replan_seconds := DEFAULT_REPLAN_BLOCKED_SECONDS
var is_crawling := false
var is_running := true
var is_alive := true
var faction_id := 3
var current_hit_points := 8
var maximum_hit_points := 8
var damage_event_count := 0
var damage_taken_total := 0
var last_damage_attacker_scene_index := -1
var scene_index := -1
var runtime_actor_type := 0
var dynamic_occupancy: RefCounted
var dynamic_registered := false
var active_sprite_footprint_key := ""
## Stable-MOD patrol timelines can opt into original-style soft actor
## separation. Static movement layers remain authoritative; only other live
## actors and their transient goal reservations are ignored.
var use_soft_dynamic_occupancy := false
## A short patrol displacement captured from the stable original runtime is
## stronger movement evidence than the reconstructed VWF footprint at that
## exact location. This flag is enabled only while replaying such a segment;
## ordinary patrol, player movement, pursuit and combat never use it.
var use_recorded_patrol_relocation := false
## A small set of process-proven patrol legs follow reconstructed A* geometry
## but end in a cell that the converted static overlay rejects. Only the final
## waypoint of those explicitly catalogued legs may use runtime evidence.
var use_recorded_patrol_final_relocation := false
var sprite_texture: Texture2D
var sprite_anchor := Vector2.ZERO
var movement_groups: Array[Dictionary] = []
var idle_groups: Array[Dictionary] = []
var run_groups: Array[Dictionary] = []
var walk_groups: Array[Dictionary] = []
var crawl_groups: Array[Dictionary] = []
var standing_idle_groups: Array[Dictionary] = []
var stand_action_groups: Array[Dictionary] = []
var walk_step_components := Vector2.ZERO
var crawl_step_components := Vector2.ZERO
var uses_original_component_movement := false
var animation_group_index := 7
var animation_frame_index := 0
var animation_elapsed := 0.0
var original_ai_idle_animation_enabled := false
var original_ai_idle_action_active := false
var original_ai_idle_tick_counter := 0
var original_ai_idle_tick_limit := 0
var original_ai_idle_tick_elapsed := 0.0
var original_ai_idle_frame_index := 0
var original_ai_idle_frame_elapsed := 0.0
var original_ai_idle_random_state := 1
var weapon_profile: Dictionary = {}
var attack_groups: Array[Dictionary] = []
var death_groups: Array[Dictionary] = []
var magazine_ammo := 0
var reserve_ammo := 0
var infinite_ammo := false
var combat_target: Node2D
var combat_target_forced := false
var auto_combat_enabled := false
var combat_repath_elapsed := COMBAT_REPATH_SECONDS
var attack_cooldown_remaining := 0.0
var combat_action := CombatAction.NONE
var action_frame_index := 0
var action_frame_elapsed := 0.0
var action_finished := false
var reload_remaining := 0.0
var pending_hit_target: Node2D
var pending_hit_forced := false
var pending_hit_resolved := false
var hurt_remaining := 0.0
var death_emitted := false
var combat_inventory: RefCounted
var backpack_inventory: RefCounted
var attack_groups_by_action: Dictionary = {}
var inventory_weapon_order: Array[String] = []
var disguise_appearance_state := 0
var disguise_transition_item_id := 0
var disguise_transition_tick_counter := 0
var disguise_transition_tick_elapsed := 0.0
var disguise_recovery_tick_counter := 0
var disguise_recovery_tick_elapsed := 0.0


func configure(
	new_name: String,
	color: Color,
	start_position: Vector2,
	texture: Texture2D = null,
	new_movement_groups: Array[Dictionary] = [],
	new_idle_groups: Array[Dictionary] = [],
	new_scene_index: int = -1,
	new_dynamic_occupancy: RefCounted = null,
	new_source_reference_position: Variant = null,
) -> void:
	display_name = new_name
	body_color = color
	sprite_texture = texture
	movement_groups = new_movement_groups
	idle_groups = new_idle_groups
	run_groups = new_movement_groups
	walk_groups = new_movement_groups
	crawl_groups = []
	standing_idle_groups = new_idle_groups
	stand_action_groups = []
	walk_step_components = _authored_motion_components(
		new_movement_groups,
		animation_group_index,
	)
	crawl_step_components = walk_step_components
	uses_original_component_movement = not walk_step_components.is_zero_approx()
	original_ai_idle_animation_enabled = false
	original_ai_idle_action_active = false
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_limit = 0
	original_ai_idle_tick_elapsed = 0.0
	original_ai_idle_frame_index = 0
	original_ai_idle_frame_elapsed = 0.0
	original_ai_idle_random_state = 1
	is_running = true
	is_crawling = false
	move_speed = RUN_SPEED
	scene_index = new_scene_index
	runtime_actor_type = 0
	dynamic_occupancy = new_dynamic_occupancy
	use_soft_dynamic_occupancy = false
	use_recorded_patrol_relocation = false
	use_recorded_patrol_final_relocation = false
	position = start_position
	target_position = start_position
	movement_path.clear()
	movement_path_index = 0
	was_moving = false
	blocked_elapsed = 0.0
	dynamic_registered = false
	active_sprite_footprint_key = ""
	combat_target = null
	combat_target_forced = false
	auto_combat_enabled = false
	combat_action = CombatAction.NONE
	action_finished = false
	hurt_remaining = 0.0
	death_emitted = false
	combat_inventory = null
	backpack_inventory = null
	attack_groups_by_action.clear()
	inventory_weapon_order.clear()
	disguise_appearance_state = 0
	disguise_transition_item_id = 0
	disguise_transition_tick_counter = 0
	disguise_transition_tick_elapsed = 0.0
	disguise_recovery_tick_counter = 0
	disguise_recovery_tick_elapsed = 0.0
	is_alive = true
	damage_event_count = 0
	damage_taken_total = 0
	last_damage_attacker_scene_index = -1
	if (
		dynamic_occupancy != null
		and scene_index >= 0
	):
		dynamic_registered = dynamic_occupancy.register_scene(
			scene_index, start_position, new_source_reference_position
		)
		if not dynamic_registered:
			dynamic_occupancy = null
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	if movement_groups.size() >= 8:
		var first_group: int = (
			SPR_ANIMATION_RULES.first_usable_group_index(
				movement_groups
			)
		)
		if first_group >= 0:
			animation_group_index = first_group
			animation_frame_index = 0
			animation_elapsed = 0.0
			update_animation_frame()
		apply_idle_frame()
	elif sprite_texture != null:
		sprite_anchor = sprite_texture.get_size() * 0.5
	queue_redraw()


func configure_original_ai_idle_animation(
	new_stand_action_groups: Array[Dictionary],
) -> bool:
	stand_action_groups = new_stand_action_groups
	original_ai_idle_animation_enabled = (
		SPR_ANIMATION_RULES.available_group_count(stand_action_groups) > 0
	)
	original_ai_idle_action_active = false
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_elapsed = 0.0
	original_ai_idle_frame_index = 0
	original_ai_idle_frame_elapsed = 0.0
	# The executable uses one process-global MSVCRT rand() stream. Until every
	# call site is recovered, seed a per-scene MSVCRT stream so save/replay is
	# deterministic while retaining the exact rand()%160 first interval and
	# rand()%160+40 subsequent interval domains.
	original_ai_idle_random_state = int(
		(scene_index * 214013 + 2531011) & 0x7fffffff
	)
	if original_ai_idle_random_state == 0:
		original_ai_idle_random_state = 1
	original_ai_idle_random_state = AI_IDLE_RANDOM_RULES.msvc_rand_step(
		original_ai_idle_random_state
	)
	original_ai_idle_tick_limit = (
		AI_IDLE_RANDOM_RULES.msvc_rand_value(
			original_ai_idle_random_state
		)
		% AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
	)
	apply_idle_frame()
	return original_ai_idle_animation_enabled


static func original_ai_idle_uses_stand_action(
	counter: int,
	limit: int,
) -> bool:
	var third := maxi(limit, 0) / 3
	return (
		third > 0
		and counter >= third
		and counter < 2 * third
	)


func original_ai_idle_animation_snapshot() -> Dictionary:
	return {
		"enabled": original_ai_idle_animation_enabled,
		"action_active": original_ai_idle_action_active,
		"tick_counter": original_ai_idle_tick_counter,
		"tick_limit": original_ai_idle_tick_limit,
		"tick_elapsed": original_ai_idle_tick_elapsed,
		"frame_index": original_ai_idle_frame_index,
		"frame_elapsed": original_ai_idle_frame_elapsed,
		"random_state": original_ai_idle_random_state,
	}


func restore_original_ai_idle_animation(state: Dictionary) -> bool:
	if state.is_empty() or not original_ai_idle_animation_enabled:
		return false
	original_ai_idle_tick_limit = clampi(
		int(state.get("tick_limit", original_ai_idle_tick_limit)),
		0,
		AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
		+ AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT
		- 1,
	)
	original_ai_idle_tick_counter = clampi(
		int(state.get("tick_counter", 0)),
		0,
		maxi(original_ai_idle_tick_limit, 0),
	)
	original_ai_idle_tick_elapsed = clampf(
		float(state.get("tick_elapsed", 0.0)),
		0.0,
		ORIGINAL_AI_IDLE_TICK_SECONDS,
	)
	original_ai_idle_frame_index = maxi(
		int(state.get("frame_index", 0)),
		0,
	)
	original_ai_idle_frame_elapsed = maxf(
		float(state.get("frame_elapsed", 0.0)),
		0.0,
	)
	original_ai_idle_random_state = maxi(
		int(state.get("random_state", original_ai_idle_random_state)),
		1,
	)
	original_ai_idle_action_active = original_ai_idle_uses_stand_action(
		original_ai_idle_tick_counter,
		original_ai_idle_tick_limit,
	)
	_apply_current_idle_visual(0.0)
	return true


func configure_runtime_actor_type(entity: Dictionary) -> int:
	runtime_actor_type = 0
	var header_values: Variant = entity.get("database_header_values", [])
	if header_values is Array and (header_values as Array).size() > 2:
		runtime_actor_type = int((header_values as Array)[2])
	return runtime_actor_type


func configure_movement_modes(
	new_run_groups: Array[Dictionary],
	new_walk_groups: Array[Dictionary],
	new_crawl_groups: Array[Dictionary],
) -> void:
	run_groups = new_run_groups if not new_run_groups.is_empty() else movement_groups
	walk_groups = new_walk_groups if not new_walk_groups.is_empty() else run_groups
	crawl_groups = new_crawl_groups
	walk_step_components = _authored_motion_components(
		walk_groups,
		animation_group_index,
	)
	crawl_step_components = _authored_motion_components(
		crawl_groups,
		animation_group_index,
	)
	if crawl_step_components.is_zero_approx():
		crawl_step_components = walk_step_components
	uses_original_component_movement = not walk_step_components.is_zero_approx()
	_apply_movement_mode()


func toggle_run_walk() -> bool:
	if not is_alive or is_crawling:
		return is_running
	return set_running(not is_running)


func set_running(value: bool) -> bool:
	if not is_alive:
		return is_running
	is_running = value
	_apply_movement_mode()
	return is_running


func set_crawling(value: bool) -> bool:
	if not is_alive:
		return is_crawling
	is_crawling = value
	_apply_movement_mode()
	return is_crawling


func toggle_crawling() -> bool:
	return set_crawling(not is_crawling)


func movement_mode_name() -> String:
	if is_crawling:
		return "crawl"
	return "run" if is_running else "walk"


func _apply_movement_mode() -> void:
	var show_movement_frame := (
		was_moving
		or movement_path_index < movement_path.size()
	)
	if is_crawling and not crawl_groups.is_empty():
		movement_groups = crawl_groups
		idle_groups = crawl_groups
		move_speed = _original_mode_nominal_speed(CRAWL_SPEED)
	elif is_running:
		movement_groups = run_groups if not run_groups.is_empty() else walk_groups
		idle_groups = standing_idle_groups
		move_speed = _original_mode_nominal_speed(RUN_SPEED)
	else:
		movement_groups = walk_groups if not walk_groups.is_empty() else run_groups
		idle_groups = standing_idle_groups
		move_speed = _original_mode_nominal_speed(WALK_SPEED)
	animation_frame_index = 0
	animation_elapsed = 0.0
	if (
		not SPR_ANIMATION_RULES.action_group_available(
			movement_groups,
			animation_group_index,
		)
	):
		var first_group: int = (
			SPR_ANIMATION_RULES.first_usable_group_index(
				movement_groups
			)
		)
		if first_group >= 0:
			animation_group_index = first_group
	if show_movement_frame:
		update_animation_frame()
	else:
		apply_idle_frame()
	queue_redraw()


func _original_mode_nominal_speed(fallback: float) -> float:
	if not uses_original_component_movement:
		return fallback
	var step_components := (
		crawl_step_components
		if is_crawling
		else walk_step_components * (ORIGINAL_RUN_STEP_MULTIPLIER if is_running else 1.0)
	)
	if step_components.is_zero_approx():
		return fallback
	return (step_components * ORIGINAL_MOVEMENT_TICKS_PER_SECOND).length()


static func _authored_motion_components(
	groups: Array[Dictionary],
	preferred_group_index: int = -1,
) -> Vector2:
	if groups.is_empty():
		return Vector2.ZERO
	var candidate_indices: Array[int] = []
	if preferred_group_index >= 0 and preferred_group_index < groups.size():
		candidate_indices.append(preferred_group_index)
	for group_index: int in range(groups.size()):
		if not candidate_indices.has(group_index):
			candidate_indices.append(group_index)
	for group_index: int in candidate_indices:
		var group := groups[group_index]
		var raw_triplet: Variant = group.get("secondary_triplet", [])
		if not SPR_ANIMATION_RULES.triplet_is_integral(raw_triplet):
			continue
		var triplet := raw_triplet as Array
		var components := Vector2(
			absf(float(triplet[0])),
			absf(float(triplet[2])),
		)
		if components.x > 0.0 and components.y > 0.0:
			return components
	return Vector2.ZERO


func original_component_velocity() -> Vector2:
	if not uses_original_component_movement or move_speed <= 0.0:
		return Vector2.ZERO
	var step_components := (
		crawl_step_components
		if is_crawling
		else walk_step_components * (ORIGINAL_RUN_STEP_MULTIPLIER if is_running else 1.0)
	)
	if step_components.is_zero_approx():
		return Vector2.ZERO
	var unscaled_velocity := step_components * ORIGINAL_MOVEMENT_TICKS_PER_SECOND
	var unscaled_magnitude := unscaled_velocity.length()
	if unscaled_magnitude <= 0.0:
		return Vector2.ZERO
	# Enemies, escorts and ambient actors retain their recovered scalar speed,
	# while the SPR triplet supplies the original isometric X/Y ratio.
	return unscaled_velocity * (move_speed / unscaled_magnitude)


static func advance_component_capped(
	start: Vector2,
	destination: Vector2,
	available_seconds: float,
	component_velocity: Vector2,
) -> Dictionary:
	var seconds := maxf(available_seconds, 0.0)
	var velocity := Vector2(
		maxf(component_velocity.x, 0.0),
		maxf(component_velocity.y, 0.0),
	)
	if start.is_equal_approx(destination):
		return {
			"position": destination,
			"seconds_used": 0.0,
			"reached": true,
		}
	if seconds <= 0.0 or velocity.x <= 0.0 or velocity.y <= 0.0:
		return {
			"position": start,
			"seconds_used": 0.0,
			"reached": false,
		}
	var delta := destination - start
	var component_cap := velocity * seconds
	# M1937 compares integer X/Y step components with the remaining distance.
	# Comparing two independently-divided floating-point times can classify an
	# exact 2/1-pixel tick as just short, leaving the actor motionless for the
	# next tick before the path cursor advances.
	if (
		absf(delta.x) <= component_cap.x + 0.0001
		and absf(delta.y) <= component_cap.y + 0.0001
	):
		return {
			"position": destination,
			"seconds_used": maxf(
				absf(delta.x) / velocity.x,
				absf(delta.y) / velocity.y,
			),
			"reached": true,
		}
	return {
		"position": Vector2(
			move_toward(start.x, destination.x, velocity.x * seconds),
			move_toward(start.y, destination.y, velocity.y * seconds),
		),
		"seconds_used": seconds,
		"reached": false,
	}


func configure_combat(
	new_faction_id: int,
	hit_points: int,
	new_weapon_profile: Dictionary,
	new_attack_groups: Array[Dictionary] = [],
	new_death_groups: Array[Dictionary] = [],
	use_infinite_ammo: bool = false,
	initialize_profile_inventory: bool = true,
) -> void:
	faction_id = new_faction_id
	maximum_hit_points = maxi(hit_points, 1)
	current_hit_points = maximum_hit_points
	is_alive = true
	weapon_profile = new_weapon_profile.duplicate(true)
	attack_groups = new_attack_groups
	death_groups = new_death_groups
	infinite_ammo = use_infinite_ammo
	var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
	magazine_ammo = magazine_capacity
	reserve_ammo = maxi(int(weapon_profile.get("starting_reserve_ammo", 0)), 0)
	combat_inventory = null
	attack_groups_by_action.clear()
	inventory_weapon_order.clear()
	var action_key := str(weapon_profile.get("action_key", ""))
	var ammo_item_id := int(weapon_profile.get("ammo_item_id", 0))
	if (
		not infinite_ammo
		and initialize_profile_inventory
		and not action_key.is_empty()
		and COMBAT_INVENTORY_SCRIPT.supports_ammo_item(ammo_item_id)
	):
		combat_inventory = COMBAT_INVENTORY_SCRIPT.new()
		if combat_inventory.register_weapon(action_key, weapon_profile, true):
			attack_groups_by_action[action_key] = new_attack_groups
			inventory_weapon_order.append(action_key)
			_sync_ammo_from_inventory(false)
	combat_target = null
	combat_target_forced = false
	auto_combat_enabled = false
	combat_repath_elapsed = COMBAT_REPATH_SECONDS
	attack_cooldown_remaining = 0.0
	combat_action = CombatAction.NONE
	action_frame_index = 0
	action_frame_elapsed = 0.0
	action_finished = false
	reload_remaining = 0.0
	pending_hit_target = null
	pending_hit_forced = false
	pending_hit_resolved = false
	hurt_remaining = 0.0
	death_emitted = false
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value and is_alive
	queue_redraw()


func set_action_progress(value: float) -> void:
	action_progress_ratio = clampf(value, 0.0, 1.0) if value >= 0.0 else -1.0
	queue_redraw()


func register_inventory_weapon(
	new_weapon_profile: Dictionary,
	new_attack_groups: Array[Dictionary] = [],
	load_profile_defaults: bool = false,
	equip_now: bool = true,
) -> bool:
	if infinite_ammo or new_weapon_profile.is_empty():
		return false
	var action_key := str(new_weapon_profile.get("action_key", ""))
	if action_key.is_empty():
		return false
	if combat_inventory == null:
		combat_inventory = COMBAT_INVENTORY_SCRIPT.new()
	if combat_inventory.weapon_state(action_key).is_empty():
		if not combat_inventory.register_weapon(
			action_key, new_weapon_profile, load_profile_defaults
		):
			return false
		inventory_weapon_order.append(action_key)
	attack_groups_by_action[action_key] = new_attack_groups
	if equip_now:
		return equip_inventory_weapon(action_key)
	_sync_ammo_from_inventory(false)
	return true


func register_original_inventory_weapon(
	new_weapon_profile: Dictionary,
	new_attack_groups: Array[Dictionary],
	quantity: int,
	quantity_mode: int,
	equip_now: bool = false,
) -> bool:
	if infinite_ammo or new_weapon_profile.is_empty():
		return false
	var action_key := str(new_weapon_profile.get("action_key", ""))
	if action_key.is_empty():
		return false
	if combat_inventory == null:
		combat_inventory = COMBAT_INVENTORY_SCRIPT.new()
	if not combat_inventory.register_original_weapon(
		action_key,
		new_weapon_profile,
		quantity,
		quantity_mode,
		equip_now,
	):
		return false
	if not inventory_weapon_order.has(action_key):
		inventory_weapon_order.append(action_key)
	attack_groups_by_action[action_key] = new_attack_groups
	if equip_now:
		return equip_inventory_weapon(action_key)
	_sync_ammo_from_inventory(false)
	return true


func equip_inventory_weapon(action_key: String) -> bool:
	if (
		combat_inventory == null
		or combat_action != CombatAction.NONE
		or not combat_inventory.equip_weapon(action_key)
	):
		return false
	weapon_profile = combat_inventory.active_weapon_profile()
	attack_groups = attack_groups_by_action.get(action_key, []) as Array[Dictionary]
	clear_combat_target()
	_sync_ammo_from_inventory(true)
	apply_idle_frame()
	queue_redraw()
	return true


func equip_attack_type(attack_type: int) -> bool:
	if combat_inventory == null:
		return false
	for action_key: String in combat_inventory.registered_weapon_keys():
		if int(combat_inventory.weapon_profile(action_key).get("attack_type", 0)) == attack_type:
			return equip_inventory_weapon(action_key)
	return false


func cycle_inventory_weapon(direction: int = 1) -> bool:
	if combat_inventory == null:
		return false
	var available: Array[String] = combat_inventory.registered_weapon_keys()
	if available.size() < 2:
		return false
	var current_index := available.find(combat_inventory.active_weapon_key())
	var next_index := posmod(
		current_index + (1 if direction >= 0 else -1),
		available.size(),
	)
	return equip_inventory_weapon(available[next_index])


func add_ammo_item(item_id: int, quantity: int) -> int:
	if combat_inventory == null:
		return 0
	var accepted := int(combat_inventory.add_item(item_id, quantity))
	if accepted > 0:
		_sync_ammo_from_inventory(true)
	return accepted


func ammo_item_count(item_id: int) -> int:
	if combat_inventory == null:
		return 0
	return int(combat_inventory.ammo_item_count(item_id))


func remove_ammo_item(item_id: int, quantity: int) -> int:
	if combat_inventory == null:
		return 0
	var removed := int(combat_inventory.remove_item(item_id, quantity))
	if removed > 0:
		_sync_ammo_from_inventory(true)
	return removed


func has_inventory_weapon(action_key: String) -> bool:
	return combat_inventory != null and not combat_inventory.weapon_state(action_key).is_empty()


func preferred_finite_ammo_item_id() -> int:
	if combat_inventory == null:
		return 0
	var active_state: Dictionary = combat_inventory.weapon_state(
		combat_inventory.active_weapon_key()
	)
	if int(active_state.get("magazine_capacity", 0)) > 0:
		return int(active_state.get("ammo_item_id", 0))
	for action_key: String in combat_inventory.registered_weapon_keys():
		var state: Dictionary = combat_inventory.weapon_state(action_key)
		if (
			bool(state.get("original_parity", false))
			and int(state.get("quantity_mode", -1)) in [0, 2]
		) or int(state.get("magazine_capacity", 0)) > 0:
			return int(state.get("ammo_item_id", 0))
	return 0


func inventory_snapshot() -> Dictionary:
	if combat_inventory == null:
		return {}
	return combat_inventory.full_snapshot()


## Canonical cross-runtime view of the two original actor containers.
##
## The stable executable stores weapons at actor +0x22C and backpack items at
## actor +0x228.  Both containers are parallel, ordered arrays of item ID,
## quantity and quantity mode.  Runtime parity traces deliberately use that
## recovered representation instead of the remake's save-game dictionaries or
## the compatibility magazine/reserve fields.
func parity_inventory_snapshot() -> Dictionary:
	var weapon_entries: Array[Dictionary] = []
	if combat_inventory != null:
		for action_key: String in inventory_weapon_order:
			var state: Dictionary = combat_inventory.weapon_state(action_key)
			# Mode-0 entries disappear from the original container at zero.
			# weapon_state() likewise hides an unowned mode-0 action, while a
			# zero-round mode-2 firearm remains present.
			if state.is_empty() or not bool(state.get("original_parity", false)):
				continue
			var item_id := int(state.get("ammo_item_id", 0))
			weapon_entries.append({
				"inventory_index": weapon_entries.size(),
				"item_id": item_id,
				"quantity": maxi(combat_inventory.ammo_item_count(item_id), 0),
				"quantity_mode": int(state.get("quantity_mode", -1)),
			})
	var item_entries: Array[Dictionary] = []
	if backpack_inventory != null:
		for raw_entry: Dictionary in backpack_inventory.ordered_entries():
			item_entries.append({
				"inventory_index": item_entries.size(),
				"item_id": int(raw_entry.get("item_id", 0)),
				"quantity": maxi(int(raw_entry.get("quantity", 0)), 0),
				"quantity_mode": int(raw_entry.get("quantity_mode", -1)),
			})
	return {
		"schema_version": 1,
		"active_attack_type": int(weapon_profile.get("attack_type", 0)),
		"weapon_entries": weapon_entries,
		"item_entries": item_entries,
	}


func configure_original_backpack(loadout: Dictionary) -> bool:
	if loadout.is_empty():
		return false
	var inventory = BACKPACK_INVENTORY_SCRIPT.new()
	for item_value: Variant in loadout.get("items", []):
		if not item_value is Dictionary:
			return false
		var item := item_value as Dictionary
		if not inventory.register_original_item(
			int(item.get("item_id", 0)),
			int(item.get("quantity", -1)),
			int(item.get("quantity_mode", -1)),
		):
			return false
	backpack_inventory = inventory
	return true


func add_backpack_item(
	item_id: int,
	quantity: int,
	quantity_mode: int = 0,
) -> int:
	if backpack_inventory == null:
		backpack_inventory = BACKPACK_INVENTORY_SCRIPT.new()
	return int(
		backpack_inventory.add_original_item(item_id, quantity, quantity_mode)
	)


func consume_backpack_item(
	item_id: int,
	force_consumption: bool = false,
	quantity: int = 1,
) -> bool:
	return (
		backpack_inventory != null
		and bool(
			backpack_inventory.consume(
				item_id,
				force_consumption,
				quantity,
			)
		)
	)


func backpack_snapshot() -> Dictionary:
	return (
		backpack_inventory.snapshot()
		if backpack_inventory != null
		else {}
	)


func set_original_disguise(appearance_state: int) -> void:
	disguise_appearance_state = maxi(appearance_state, 0)
	queue_redraw()


func begin_original_disguise_transition(item_id: int) -> bool:
	if (
		not is_alive
		or disguise_transition_item_id != 0
		or backpack_inventory == null
		or not backpack_inventory.has_item(item_id)
		or not LEGACY_DISGUISE_RULES.can_begin_transition(
			runtime_actor_type,
			item_id,
		)
	):
		return false
	clear_combat_target()
	_interrupt_combat_action()
	cancel_path()
	disguise_transition_item_id = item_id
	disguise_transition_tick_counter = 0
	disguise_transition_tick_elapsed = 0.0
	set_action_progress(0.0)
	return true


func advance_original_disguise_transition(delta: float) -> bool:
	if disguise_transition_item_id == 0:
		return false
	if (
		not is_alive
		or backpack_inventory == null
		or not backpack_inventory.has_item(disguise_transition_item_id)
	):
		cancel_original_disguise_transition()
		return false
	disguise_transition_tick_elapsed += maxf(delta, 0.0)
	while (
		disguise_transition_tick_elapsed
		>= LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS
	):
		disguise_transition_tick_elapsed -= (
			LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS
		)
		disguise_transition_tick_counter += 1
		set_action_progress(
			minf(
				float(disguise_transition_tick_counter)
				/ float(LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT + 1),
				1.0,
			)
		)
		if (
			disguise_transition_tick_counter
			> LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT
		):
			var completed_item_id := disguise_transition_item_id
			disguise_transition_item_id = 0
			disguise_transition_tick_counter = 0
			disguise_transition_tick_elapsed = 0.0
			set_action_progress(-1.0)
			original_disguise_transition_ready.emit(
				self,
				completed_item_id,
			)
			return true
	return false


func cancel_original_disguise_transition() -> void:
	disguise_transition_item_id = 0
	disguise_transition_tick_counter = 0
	disguise_transition_tick_elapsed = 0.0
	set_action_progress(-1.0)


func expose_original_disguise() -> bool:
	if runtime_actor_type != LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE:
		return false
	var changed := faction_id != LEGACY_DISGUISE_RULES.PLAYER_FACTION_ID
	faction_id = LEGACY_DISGUISE_RULES.PLAYER_FACTION_ID
	disguise_recovery_tick_counter = 0
	disguise_recovery_tick_elapsed = 0.0
	queue_redraw()
	return changed


func advance_original_disguise_recovery(
	delta: float,
	observer_has_visibility: bool,
	burial_exposes_actor: bool = false,
) -> bool:
	if runtime_actor_type != LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE:
		disguise_recovery_tick_counter = 0
		disguise_recovery_tick_elapsed = 0.0
		return false
	if (
		faction_id == LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
		and burial_exposes_actor
		and observer_has_visibility
	):
		return expose_original_disguise()
	if faction_id != LEGACY_DISGUISE_RULES.PLAYER_FACTION_ID:
		disguise_recovery_tick_counter = 0
		disguise_recovery_tick_elapsed = 0.0
		return false
	if observer_has_visibility:
		disguise_recovery_tick_counter = 0
		disguise_recovery_tick_elapsed = 0.0
		return false
	disguise_recovery_tick_elapsed += maxf(delta, 0.0)
	while (
		disguise_recovery_tick_elapsed
		>= LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS
	):
		disguise_recovery_tick_elapsed -= (
			LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS
		)
		disguise_recovery_tick_counter += 1
		if (
			disguise_recovery_tick_counter
			> LEGACY_DISGUISE_RULES.RECOVERY_TICK_LIMIT
		):
			faction_id = LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
			disguise_recovery_tick_counter = 0
			disguise_recovery_tick_elapsed = 0.0
			queue_redraw()
			return true
	return false


func apply_original_actor_variant(
	new_runtime_actor_type: int,
	new_faction_id: int,
	appearance_state: int,
	texture: Texture2D,
	new_run_groups: Array[Dictionary],
	new_walk_groups: Array[Dictionary],
	new_crawl_groups: Array[Dictionary],
	new_idle_groups: Array[Dictionary],
	new_death_groups: Array[Dictionary],
	new_attack_groups_by_action: Dictionary,
) -> void:
	clear_combat_target()
	_interrupt_combat_action()
	cancel_path()
	runtime_actor_type = new_runtime_actor_type
	faction_id = new_faction_id
	disguise_appearance_state = maxi(appearance_state, 0)
	if texture != null:
		sprite_texture = texture
	run_groups = new_run_groups
	walk_groups = new_walk_groups
	crawl_groups = new_crawl_groups
	standing_idle_groups = new_idle_groups
	death_groups = new_death_groups
	if is_crawling and crawl_groups.is_empty():
		is_crawling = false
	attack_groups_by_action.clear()
	for action_key_value: Variant in new_attack_groups_by_action:
		var action_groups_value: Variant = (
			new_attack_groups_by_action[action_key_value]
		)
		if action_groups_value is Array:
			var typed_action_groups: Array[Dictionary] = []
			typed_action_groups.assign(action_groups_value as Array)
			attack_groups_by_action[str(action_key_value)] = typed_action_groups
	var active_action_key := (
		str(combat_inventory.active_weapon_key())
		if combat_inventory != null
		else ""
	)
	attack_groups = (
		attack_groups_by_action.get(active_action_key, []) as Array[Dictionary]
	)
	disguise_recovery_tick_counter = 0
	disguise_recovery_tick_elapsed = 0.0
	cancel_original_disguise_transition()
	active_sprite_footprint_key = ""
	configure_movement_modes(
		new_run_groups,
		new_walk_groups,
		new_crawl_groups,
	)
	_sync_ammo_from_inventory(false)
	queue_redraw()


func original_disguise_state_snapshot() -> Dictionary:
	return {
		"transition_item_id": disguise_transition_item_id,
		"transition_tick_counter": disguise_transition_tick_counter,
		"transition_tick_elapsed": disguise_transition_tick_elapsed,
		"recovery_tick_counter": disguise_recovery_tick_counter,
		"recovery_tick_elapsed": disguise_recovery_tick_elapsed,
	}


func restore_original_disguise_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	disguise_transition_item_id = maxi(
		int(state.get("transition_item_id", 0)),
		0,
	)
	disguise_transition_tick_counter = clampi(
		int(state.get("transition_tick_counter", 0)),
		0,
		LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT,
	)
	disguise_transition_tick_elapsed = maxf(
		float(state.get("transition_tick_elapsed", 0.0)),
		0.0,
	)
	disguise_recovery_tick_counter = clampi(
		int(state.get("recovery_tick_counter", 0)),
		0,
		LEGACY_DISGUISE_RULES.RECOVERY_TICK_LIMIT,
	)
	disguise_recovery_tick_elapsed = maxf(
		float(state.get("recovery_tick_elapsed", 0.0)),
		0.0,
	)
	set_action_progress(
		float(disguise_transition_tick_counter)
		/ float(LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT + 1)
		if disguise_transition_item_id > 0
		else -1.0
	)
	return true


func issue_move(destination: Vector2) -> void:
	issue_path(PackedVector2Array([destination]))


func issue_path(path: PackedVector2Array) -> void:
	movement_path = path.duplicate()
	movement_path_index = 0
	blocked_elapsed = 0.0
	while (
		movement_path_index < movement_path.size()
		and position.is_equal_approx(movement_path[movement_path_index])
	):
		movement_path_index += 1
	if movement_path_index < movement_path.size():
		target_position = movement_path[-1]
	else:
		target_position = position
	queue_redraw()


func cancel_path() -> void:
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.release_goal(scene_index)
	movement_path.clear()
	movement_path_index = 0
	target_position = position
	blocked_elapsed = 0.0
	_apply_idle_state()
	queue_redraw()


func issue_attack(target: Node2D, force_target: bool = false) -> bool:
	if not is_alive or not _target_is_alive(target) or weapon_profile.is_empty():
		return false
	combat_target = target
	combat_target_forced = force_target
	auto_combat_enabled = true
	# The original runtime lets a commanded squad member leave a crowded
	# formation while approaching an attack line. Treat other dynamic actors
	# as soft obstacles for that command so stationary team-mates cannot trap
	# the attacker at the spawn edge; static L3 footprints and L2 line of
	# sight remain authoritative.
	use_soft_dynamic_occupancy = true
	combat_repath_elapsed = COMBAT_REPATH_SECONDS
	return true


func clear_combat_target() -> void:
	combat_target = null
	combat_target_forced = false
	auto_combat_enabled = false
	use_soft_dynamic_occupancy = false
	combat_repath_elapsed = COMBAT_REPATH_SECONDS


func is_combat_alive() -> bool:
	return is_alive


func can_attack_target(target: Node2D, allow_non_hostile: bool = false) -> bool:
	if (
		not is_alive
		or not _target_is_alive(target)
		or not (
			allow_non_hostile
			or factions_are_hostile(faction_id, int(target.get("faction_id")))
			or _is_destructible_world_target(target)
		)
		or weapon_profile.is_empty()
		or dynamic_occupancy == null
	):
		return false
	var ignored: Array = [scene_index]
	var target_scene_index := int(target.get("scene_index"))
	if target_scene_index >= 0:
		ignored.append(target_scene_index)
	return TACTICAL_SENSES_SCRIPT.can_attack(
		dynamic_occupancy,
		position,
		target.position,
		weapon_profile,
		ignored,
	)


func _is_destructible_world_target(target: Node2D) -> bool:
	return (
		target != null
		and target.has_method("explosion_payload")
		and target.has_method("take_damage")
	)


static func factions_are_hostile(first_faction: int, second_faction: int) -> bool:
	return (
		(first_faction == 1 and second_faction == 3)
		or (first_faction == 3 and second_faction == 1)
	)


func try_start_attack(target: Node2D, force_target: bool = false) -> bool:
	var forced := force_target or (target == combat_target and combat_target_forced)
	if (
		not is_alive
		or combat_action != CombatAction.NONE
		or hurt_remaining > 0.0
		or attack_cooldown_remaining > 0.0
		or not can_attack_target(target, forced)
	):
		return false
	var ammo_per_attack := maxi(int(weapon_profile.get("ammo_per_attack", 0)), 0)
	var attack_type := int(weapon_profile.get("attack_type", 0))
	var defer_item_cost_to_hit_frame := attack_type in [8, 10]
	if not infinite_ammo and ammo_per_attack > 0:
		if combat_inventory != null:
			var inventory_ready: bool = (
				combat_inventory.can_consume_active_attack()
				if defer_item_cost_to_hit_frame
				else combat_inventory.consume_active_attack()
			)
			if not inventory_ready:
				_start_reload()
				return false
			if not defer_item_cost_to_hit_frame:
				_sync_ammo_from_inventory(true)
		else:
			if magazine_ammo < ammo_per_attack:
				_start_reload()
				return false
			if not defer_item_cost_to_hit_frame:
				magazine_ammo -= ammo_per_attack
				ammo_changed.emit(self, magazine_ammo, reserve_ammo)

	var facing := target.position - position
	if not facing.is_zero_approx():
		set_animation_group(direction_group_index(facing))
	cancel_path()
	pending_hit_target = target
	pending_hit_forced = forced
	pending_hit_resolved = false
	attack_cooldown_remaining = maxf(
		float(weapon_profile.get("recovery_seconds", 0.5)), 0.05
	)
	attack_started.emit(
		self,
		target,
		int(weapon_profile.get("attack_type", 0)),
		float(weapon_profile.get("alert_radius", 0.0)),
	)
	_start_one_shot(CombatAction.ATTACK, attack_groups)
	if action_finished:
		_resolve_pending_hit()
		combat_action = CombatAction.NONE
		_sync_equipped_weapon_after_consumption()
		apply_idle_frame()
	return true


func request_reload() -> bool:
	if not is_alive or combat_action != CombatAction.NONE or hurt_remaining > 0.0:
		return false
	if (
		combat_inventory != null
		and combat_inventory.original_parity_enabled()
	):
		return false
	return _start_reload()


func take_damage(amount: int, attacker: Node2D = null) -> int:
	if not is_alive or amount <= 0:
		return 0
	var accepted_damage: int = LEGACY_COMBAT_RULES.accepted_actor_damage(
		runtime_actor_type,
		amount,
	)
	if accepted_damage <= 0:
		return 0
	var applied := mini(accepted_damage, current_hit_points)
	current_hit_points -= applied
	damage_event_count += 1
	damage_taken_total += applied
	last_damage_attacker_scene_index = (
		int(attacker.get("scene_index"))
		if attacker != null and is_instance_valid(attacker)
		else -1
	)
	damage_received.emit(self, attacker, applied, current_hit_points)
	_on_damage_taken(attacker)
	if current_hit_points <= 0:
		_die(attacker)
	# Original sub_458700 performs no non-lethal command, animation or timing
	# write: it only subtracts HP and dispatches death at zero. Keep the current
	# attack and issued movement intact instead of inventing hit-stun.
	queue_redraw()
	return applied


func heal(amount: int) -> int:
	if not is_alive or amount <= 0 or current_hit_points >= maximum_hit_points:
		return 0
	var applied := mini(amount, maximum_hit_points - current_hit_points)
	current_hit_points += applied
	queue_redraw()
	return applied


func _on_damage_taken(_attacker: Node2D) -> void:
	pass


func contains_parent_point(parent_point: Vector2) -> bool:
	return position.distance_squared_to(parent_point) <= 26.0 * 26.0


func _physics_process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - safe_delta, 0.0)
	if combat_action != CombatAction.NONE:
		_suspend_original_ai_idle_action()
		_advance_combat_action(safe_delta)
		return
	if not is_alive:
		return
	if auto_combat_enabled and _update_auto_combat(safe_delta):
		_advance_original_ai_idle_animation(safe_delta)
		return

	var previous_position := position
	var next_position := position
	var next_path_index := movement_path_index
	var component_velocity := original_component_velocity()
	var relocation_applied_incrementally := false
	var relocation_targets_final_waypoint := false
	var movement_blocked := false
	if not component_velocity.is_zero_approx():
		var remaining_seconds := safe_delta
		while next_path_index < movement_path.size() and remaining_seconds > 0.0:
			relocation_targets_final_waypoint = (
				next_path_index == movement_path.size() - 1
			)
			var substep_seconds := minf(
				remaining_seconds,
				MAX_MOVEMENT_SUBSTEP_SECONDS,
			)
			var candidate_position := next_position
			var candidate_path_index := next_path_index
			var segment := advance_component_capped(
				candidate_position,
				movement_path[candidate_path_index],
				substep_seconds,
				component_velocity,
			)
			candidate_position = segment["position"] as Vector2
			if bool(segment["reached"]):
				candidate_path_index += 1
			# RuntimeActor chooses its next grid cell only on the following
			# 60 Hz update. Any unused part of this tick is intentionally not
			# carried into the next waypoint.
			if (
				candidate_position != next_position
				and dynamic_occupancy != null
				and scene_index >= 0
			):
				relocation_applied_incrementally = true
				if not _try_relocate_runtime(
					candidate_position,
					relocation_targets_final_waypoint,
				):
					movement_blocked = true
					break
			next_position = candidate_position
			next_path_index = candidate_path_index
			remaining_seconds = maxf(
				remaining_seconds - substep_seconds,
				0.0,
			)
	else:
		# Fixtures and fallback actors without an authored secondary SPR
		# triplet retain ordinary scalar movement.
		var remaining_distance := maxf(move_speed, 0.0) * safe_delta
		while next_path_index < movement_path.size() and remaining_distance > 0.0:
			relocation_targets_final_waypoint = (
				next_path_index == movement_path.size() - 1
			)
			var waypoint := movement_path[next_path_index]
			var distance_to_waypoint := next_position.distance_to(waypoint)
			if distance_to_waypoint <= remaining_distance:
				next_position = waypoint
				remaining_distance -= distance_to_waypoint
				next_path_index += 1
			else:
				next_position = next_position.move_toward(
					waypoint,
					remaining_distance,
				)
				remaining_distance = 0.0
	if (
		not movement_blocked
		and not relocation_applied_incrementally
		and next_position != position
		and dynamic_occupancy != null
		and scene_index >= 0
		and not _try_relocate_runtime(
			next_position,
			relocation_targets_final_waypoint,
		)
	):
		movement_blocked = true
	if movement_blocked:
		# Earlier fixed substeps may already have been accepted by the runtime
		# occupancy grid. Keep the node and path cursor synchronized with that
		# last accepted position before replanning.
		position = next_position
		movement_path_index = next_path_index
		blocked_elapsed += safe_delta
		if blocked_elapsed >= maxf(blocked_replan_seconds, 0.05):
			blocked_elapsed = 0.0
			var replanned := _find_movement_path_runtime(target_position)
			if not replanned.is_empty():
				issue_path(replanned)
		var accepted_displacement := position - previous_position
		if accepted_displacement.is_zero_approx():
			_apply_idle_state()
		else:
			_suspend_original_ai_idle_action()
			set_animation_group(direction_group_index(accepted_displacement))
			advance_animation(safe_delta)
			was_moving = true
			z_index = WORLD_DEPTH.normal_z(position.y, 1)
			queue_redraw()
		return
	position = next_position
	movement_path_index = next_path_index
	blocked_elapsed = 0.0
	var displacement := position - previous_position
	if not displacement.is_zero_approx():
		_suspend_original_ai_idle_action()
		set_animation_group(direction_group_index(displacement))
		advance_animation(safe_delta)
		was_moving = true
		z_index = WORLD_DEPTH.normal_z(position.y, 1)
		queue_redraw()
	else:
		_apply_idle_state()
		_advance_original_ai_idle_animation(safe_delta)


func _try_relocate_runtime(
	new_world_position: Vector2,
	targets_final_waypoint: bool = false,
) -> bool:
	if dynamic_occupancy == null or scene_index < 0:
		return false
	if (
		use_recorded_patrol_relocation
		or (
			use_recorded_patrol_final_relocation
			and targets_final_waypoint
		)
	):
		return bool(
			dynamic_occupancy.call(
				"try_relocate_from_runtime_evidence",
				scene_index,
				new_world_position,
			)
		)
	if use_soft_dynamic_occupancy:
		return bool(
			dynamic_occupancy.call(
				"try_relocate",
				scene_index,
				new_world_position,
				true,
			)
		)
	return bool(
		dynamic_occupancy.call(
			"try_relocate",
			scene_index,
			new_world_position,
		)
	)


func _find_movement_path_runtime(
	destination: Vector2,
) -> PackedVector2Array:
	if dynamic_occupancy == null or scene_index < 0:
		return PackedVector2Array()
	if use_soft_dynamic_occupancy:
		var soft_path := dynamic_occupancy.call(
			"find_path_for_scene",
			scene_index,
			position,
			destination,
			true,
		) as PackedVector2Array
		if (
			not soft_path.is_empty()
			and soft_path[-1].distance_squared_to(destination) > 1.0
		):
			soft_path.append(destination)
		return soft_path
	return dynamic_occupancy.call(
		"find_path_for_scene",
		scene_index,
		position,
		destination,
	) as PackedVector2Array


func _update_auto_combat(delta: float) -> bool:
	if not _target_is_alive(combat_target):
		clear_combat_target()
		return false
	if can_attack_target(combat_target, combat_target_forced):
		if movement_path_index < movement_path.size():
			cancel_path()
		if attack_cooldown_remaining <= 0.0:
			try_start_attack(combat_target, combat_target_forced)
		else:
			_apply_idle_state()
		return true
	combat_repath_elapsed += delta
	if (
		combat_repath_elapsed >= COMBAT_REPATH_SECONDS
		or movement_path_index >= movement_path.size()
	):
		combat_repath_elapsed = 0.0
		if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
			var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
				scene_index, position, combat_target.position
			)
			if not path.is_empty():
				issue_path(path)
		elif dynamic_occupancy == null:
			issue_move(combat_target.position)
	return false


func _target_is_alive(target: Node2D) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.is_inside_tree()
		and target.has_method("is_combat_alive")
		and bool(target.call("is_combat_alive"))
	)


func _start_one_shot(action: int, groups: Array[Dictionary]) -> void:
	combat_action = action
	action_frame_index = 0
	action_frame_elapsed = 0.0
	action_finished = _action_frame_count(groups) <= 0
	was_moving = false
	if action_finished:
		return
	_apply_action_frame(groups)
	if action == CombatAction.ATTACK and _action_frame_count(groups) == 1:
		_resolve_pending_hit()


func _advance_combat_action(delta: float) -> void:
	if combat_action == CombatAction.RELOAD:
		reload_remaining = maxf(reload_remaining - delta, 0.0)
		if reload_remaining <= 0.0:
			_finish_reload()
		return
	if action_finished:
		return
	var groups := death_groups if combat_action == CombatAction.DEATH else attack_groups
	var frame_count := _action_frame_count(groups)
	if frame_count <= 0:
		action_finished = true
		if combat_action == CombatAction.ATTACK:
			combat_action = CombatAction.NONE
			_sync_equipped_weapon_after_consumption()
		return
	var group := groups[clampi(animation_group_index, 0, 7)]
	if group.is_empty():
		action_finished = true
		return
	var frame_seconds := animation_frame_seconds(group)
	action_frame_elapsed += delta
	while action_frame_elapsed >= frame_seconds and not action_finished:
		action_frame_elapsed -= frame_seconds
		if action_frame_index >= frame_count - 1:
			action_finished = true
			if combat_action == CombatAction.ATTACK:
				combat_action = CombatAction.NONE
				pending_hit_target = null
				_sync_equipped_weapon_after_consumption()
				apply_idle_frame()
			return
		action_frame_index += 1
		_apply_action_frame(groups)
		if combat_action == CombatAction.ATTACK and action_frame_index == frame_count - 1:
			_resolve_pending_hit()


func _apply_action_frame(groups: Array[Dictionary]) -> void:
	if groups.size() < 8:
		return
	var group := groups[clampi(animation_group_index, 0, 7)]
	if group.is_empty():
		return
	var frames := group.get("frames", []) as Array[Texture2D]
	if frames.is_empty():
		return
	action_frame_index = clampi(action_frame_index, 0, frames.size() - 1)
	sprite_texture = frames[action_frame_index]
	sprite_anchor = group.get("anchor", Vector2.ZERO) as Vector2
	_apply_dynamic_sprite_footprint(group)
	queue_redraw()


func _action_frame_count(groups: Array[Dictionary]) -> int:
	if groups.size() < 8:
		return 0
	var group := groups[clampi(animation_group_index, 0, 7)]
	if group.is_empty():
		return 0
	return (group.get("frames", []) as Array[Texture2D]).size()


func _resolve_pending_hit() -> void:
	if pending_hit_resolved:
		return
	pending_hit_resolved = true
	if not can_attack_target(pending_hit_target, pending_hit_forced):
		return
	var attack_type := int(weapon_profile.get("attack_type", 0))
	if LEGACY_DISGUISE_RULES.attack_can_break_disguise(
		runtime_actor_type,
		attack_type,
	):
		original_disguise_attack_committed.emit(
			self,
			pending_hit_target,
			attack_type,
		)
	if LEGACY_SPECIAL_ACTION_PROFILES.is_special_attack(attack_type):
		if attack_type in [8, 10] and not infinite_ammo:
			var ammo_per_attack := maxi(int(weapon_profile.get("ammo_per_attack", 0)), 0)
			if combat_inventory != null:
				if not combat_inventory.consume_active_attack():
					return
				_sync_ammo_from_inventory(true)
			elif ammo_per_attack <= 0 or magazine_ammo < ammo_per_attack:
				return
			else:
				magazine_ammo -= ammo_per_attack
				ammo_changed.emit(self, magazine_ammo, reserve_ammo)
		special_action_requested.emit(self, pending_hit_target, weapon_profile.duplicate(true))
		return
	var target_cell_coincides: bool = false
	if pending_hit_target != null:
		target_cell_coincides = bool(
			LEGACY_COMBAT_RULES.attack_target_cell_coincides(
			global_position,
			pending_hit_target.global_position,
		)
		)
	if (
		PROJECTILE_PROFILES.is_projectile_attack(attack_type)
		and (attack_type == 9 or not target_cell_coincides)
	):
		var projectile_weapon_profile := weapon_profile.duplicate(true)
		projectile_weapon_profile["resolved_projectile_damage"] = (
			LEGACY_COMBAT_RULES.direct_actor_damage(
				attack_type,
				runtime_actor_type,
				int(weapon_profile.get("damage", 1)),
			)
		)
		projectile_requested.emit(
			self,
			pending_hit_target,
			projectile_weapon_profile,
		)
		return
	var damage: int = LEGACY_COMBAT_RULES.direct_actor_damage(
		attack_type,
		runtime_actor_type,
		int(weapon_profile.get("damage", 1)),
	)
	var direct_hit_count: int = LEGACY_COMBAT_RULES.direct_actor_hit_count(attack_type)
	for unused_shot in range(direct_hit_count):
		if not _target_is_alive(pending_hit_target):
			break
		var applied := int(pending_hit_target.call("take_damage", damage, self))
		if applied > 0:
			attack_hit.emit(self, pending_hit_target, attack_type, applied)


func _start_reload() -> bool:
	var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
	if combat_inventory != null:
		if combat_inventory.original_parity_enabled():
			return false
		var state: Dictionary = combat_inventory.weapon_state(
			combat_inventory.active_weapon_key()
		)
		magazine_ammo = int(state.get("magazine", 0))
		reserve_ammo = int(state.get("reserve", 0))
	if (
		infinite_ammo
		or magazine_capacity <= 0
		or magazine_ammo >= magazine_capacity
		or reserve_ammo <= 0
	):
		return false
	cancel_path()
	combat_action = CombatAction.RELOAD
	reload_remaining = maxf(float(weapon_profile.get("reload_seconds", 1.5)), 0.05)
	action_finished = false
	_apply_idle_state()
	return true


func _finish_reload() -> void:
	if combat_inventory != null:
		combat_inventory.reload_active_weapon()
		_sync_ammo_from_inventory(false)
	else:
		var magazine_capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
		var needed := maxi(magazine_capacity - magazine_ammo, 0)
		var transferred := mini(needed, reserve_ammo)
		magazine_ammo += transferred
		reserve_ammo -= transferred
	combat_action = CombatAction.NONE
	reload_remaining = 0.0
	action_finished = true
	ammo_changed.emit(self, magazine_ammo, reserve_ammo)
	apply_idle_frame()


func _sync_ammo_from_inventory(emit_change: bool) -> void:
	if combat_inventory == null:
		return
	var state: Dictionary = combat_inventory.weapon_state(combat_inventory.active_weapon_key())
	magazine_ammo = int(state.get("magazine", 0))
	reserve_ammo = int(state.get("reserve", 0))
	if emit_change:
		ammo_changed.emit(self, magazine_ammo, reserve_ammo)


func _sync_equipped_weapon_after_consumption() -> void:
	if combat_inventory == null:
		return
	var active_key := str(combat_inventory.active_weapon_key())
	if active_key.is_empty():
		weapon_profile = {}
		attack_groups = []
		magazine_ammo = 0
		reserve_ammo = 0
		ammo_changed.emit(self, 0, 0)
		return
	var active_profile: Dictionary = combat_inventory.active_weapon_profile()
	if active_profile.is_empty():
		return
	weapon_profile = active_profile
	attack_groups = attack_groups_by_action.get(active_key, []) as Array[Dictionary]
	_sync_ammo_from_inventory(true)


func _interrupt_combat_action() -> void:
	if combat_action == CombatAction.DEATH:
		return
	combat_action = CombatAction.NONE
	action_finished = true
	pending_hit_target = null
	pending_hit_forced = false
	pending_hit_resolved = true
	reload_remaining = 0.0


func _die(killer: Node2D) -> void:
	if not is_alive or death_emitted:
		return
	is_alive = false
	selected = false
	action_progress_ratio = -1.0
	cancel_original_disguise_transition()
	clear_combat_target()
	_interrupt_combat_action()
	cancel_path()
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.unregister_scene(scene_index)
		dynamic_registered = false
	self_modulate = Color.WHITE
	pending_hit_target = null
	_start_one_shot(CombatAction.DEATH, death_groups)
	death_emitted = true
	died.emit(self, killer)
	queue_redraw()


func _exit_tree() -> void:
	if dynamic_occupancy != null and dynamic_registered and scene_index >= 0:
		dynamic_occupancy.unregister_scene(scene_index)
		dynamic_registered = false


func _apply_idle_state() -> void:
	if not was_moving and animation_frame_index == 0:
		return
	was_moving = false
	animation_frame_index = 0
	animation_elapsed = 0.0
	apply_idle_frame()
	queue_redraw()


func _advance_original_ai_idle_animation(delta: float) -> void:
	if (
		not original_ai_idle_animation_enabled
		or not is_alive
		or combat_action != CombatAction.NONE
		or is_crawling
		or movement_path_index < movement_path.size()
		or was_moving
	):
		_suspend_original_ai_idle_action()
		return
	original_ai_idle_tick_elapsed += maxf(delta, 0.0)
	while (
		original_ai_idle_tick_elapsed
		>= ORIGINAL_AI_IDLE_TICK_SECONDS
	):
		original_ai_idle_tick_elapsed -= ORIGINAL_AI_IDLE_TICK_SECONDS
		original_ai_idle_tick_counter += 1
		if original_ai_idle_tick_counter >= original_ai_idle_tick_limit:
			original_ai_idle_tick_counter = 0
			var sampled: Dictionary = (
				AI_IDLE_RANDOM_RULES.initial_search_wait_from_state(
					original_ai_idle_random_state
				)
			)
			original_ai_idle_random_state = int(
				sampled.get("state", original_ai_idle_random_state)
			)
			original_ai_idle_tick_limit = int(
				sampled.get(
					"limit",
					AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT,
				)
			)
	var next_action_active := original_ai_idle_uses_stand_action(
		original_ai_idle_tick_counter,
		original_ai_idle_tick_limit,
	)
	if next_action_active != original_ai_idle_action_active:
		original_ai_idle_action_active = next_action_active
		original_ai_idle_frame_index = 0
		original_ai_idle_frame_elapsed = 0.0
	if not _apply_current_idle_visual(maxf(delta, 0.0)):
		return
	queue_redraw()


func _suspend_original_ai_idle_action() -> void:
	if not original_ai_idle_action_active:
		return
	original_ai_idle_action_active = false
	original_ai_idle_frame_index = 0
	original_ai_idle_frame_elapsed = 0.0


func _apply_current_idle_visual(advance_delta: float) -> bool:
	var groups: Array[Dictionary] = (
		stand_action_groups
		if original_ai_idle_action_active and not is_crawling
		else idle_groups
	)
	if (
		not SPR_ANIMATION_RULES.action_group_available(
			groups,
			animation_group_index,
		)
	):
		# IEngineSprite::SetCurrentSerial leaves the current serial untouched
		# when action 1 or 2 has no authored direction.
		return false
	var group := groups[animation_group_index]
	var frames := group.get("frames", []) as Array[Texture2D]
	if frames.is_empty():
		return false
	if original_ai_idle_action_active and not is_crawling:
		original_ai_idle_frame_index = clampi(
			original_ai_idle_frame_index,
			0,
			frames.size() - 1,
		)
		if advance_delta > 0.0 and frames.size() > 1:
			var frame_seconds := animation_frame_seconds(group)
			original_ai_idle_frame_elapsed += advance_delta
			while original_ai_idle_frame_elapsed >= frame_seconds:
				original_ai_idle_frame_elapsed -= frame_seconds
				original_ai_idle_frame_index = (
					original_ai_idle_frame_index + 1
				) % frames.size()
		sprite_texture = frames[original_ai_idle_frame_index]
	else:
		sprite_texture = frames[0]
	sprite_anchor = group.get("anchor", Vector2.ZERO) as Vector2
	_apply_dynamic_sprite_footprint(group)
	return true


static func direction_group_index(direction: Vector2) -> int:
	if direction.is_zero_approx():
		return 7
	var octant := roundi(direction.angle() / (PI / 4.0))
	return posmod(octant + 5, 8)


func set_animation_group(group_index: int) -> bool:
	if movement_groups.size() < 8:
		return false
	var safe_index := clampi(group_index, 0, 7)
	if (
		not SPR_ANIMATION_RULES.action_group_available(
			movement_groups,
			safe_index,
		)
	):
		# IEngineSprite::SetCurrentSerial returns failure without changing the
		# current serial when a sparse SPR has no requested direction.
		return false
	if animation_group_index != safe_index:
		animation_group_index = safe_index
		animation_frame_index = 0
		animation_elapsed = 0.0
	update_animation_frame()
	return true


func advance_animation(delta: float) -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	if group.is_empty():
		return
	var frames := group["frames"] as Array[Texture2D]
	if frames.size() <= 1:
		return
	var frame_seconds := animation_frame_seconds(group)
	animation_elapsed += maxf(delta, 0.0)
	while animation_elapsed >= frame_seconds:
		animation_elapsed -= frame_seconds
		animation_frame_index = (animation_frame_index + 1) % frames.size()
	update_animation_frame()


static func animation_frame_seconds(group: Dictionary) -> float:
	return BASE_SPRITE_TICK_SECONDS * maxi(int(group.get("frame_hold_ticks", 1)), 1)


func update_animation_frame() -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	if group.is_empty():
		return
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return
	animation_frame_index = clampi(animation_frame_index, 0, frames.size() - 1)
	sprite_texture = frames[animation_frame_index]
	sprite_anchor = group["anchor"] as Vector2
	_apply_dynamic_sprite_footprint(group)


func apply_idle_frame() -> bool:
	if original_ai_idle_animation_enabled:
		return _apply_current_idle_visual(0.0)
	if idle_groups.size() < 8:
		update_animation_frame()
		return false
	var group := idle_groups[animation_group_index]
	if group.is_empty():
		# Exact SetCurrentSerial failure keeps the already displayed serial.
		return false
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return false
	sprite_texture = frames[0]
	sprite_anchor = group["anchor"] as Vector2
	_apply_dynamic_sprite_footprint(group)
	return true


func _apply_dynamic_sprite_footprint(group: Dictionary) -> bool:
	if (
		not dynamic_registered
		or dynamic_occupancy == null
		or scene_index < 0
		or not dynamic_occupancy.has_method("update_scene_footprint")
		or not group.has("lookup_dimensions")
		or not group.has("movement_lookup")
		or not group.has("sight_lookup")
	):
		return false
	var profile_key := str(group.get("lookup_profile_key", ""))
	if profile_key.is_empty():
		profile_key = "%d:%d" % [
			int(group.get("group_index", -1)),
			hash(
				[
					group.get("primary_triplet", []),
					group.get("lookup_dimensions"),
					group.get("movement_lookup", []),
					group.get("sight_lookup", []),
				]
			),
		]
	if profile_key == active_sprite_footprint_key:
		return true
	var source_navigation: Variant = dynamic_occupancy.get("navigation")
	if source_navigation == null:
		return false
	var cell_size_value: Variant = source_navigation.get("cell_size")
	if not cell_size_value is Vector2i:
		return false
	var cell_size := cell_size_value as Vector2i
	var movement_offsets: Array[Vector2i] = (
		SPR_ANIMATION_RULES.lookup_footprint_offsets(
			group,
			"movement_lookup",
			cell_size,
		)
	)
	var sight_offsets: Array[Vector2i] = (
		SPR_ANIMATION_RULES.lookup_footprint_offsets(
			group,
			"sight_lookup",
			cell_size,
		)
	)
	if not bool(
		dynamic_occupancy.call(
			"update_scene_footprint",
			scene_index,
			movement_offsets,
			sight_offsets,
		)
	):
		return false
	active_sprite_footprint_key = profile_key
	return true


func legacy_projectile_launch_offset() -> Vector2:
	var triplets := _active_legacy_sprite_triplets()
	if triplets.is_empty():
		return Vector2.ZERO
	var primary := triplets["primary"] as Array
	var tertiary := triplets["tertiary"] as Array
	# M1937.exe sub_463290 starts the Bresenham path at:
	# world_x + actor(+0x50) - actor(+0x44), world_y.
	return Vector2(float(int(tertiary[0]) - int(primary[0])), 0.0)


func legacy_projectile_vertical_baseline() -> float:
	var triplets := _active_legacy_sprite_triplets()
	if triplets.is_empty():
		return 0.0
	var primary := triplets["primary"] as Array
	var tertiary := triplets["tertiary"] as Array
	# sub_463290 stores (+0x58)-(+0x4c), then subtracts that value
	# from the projectile actor's visual Z. Godot draws positive height
	# upward, hence the equivalent primary_z-tertiary_z result.
	return float(int(primary[2]) - int(tertiary[2]))


func _active_legacy_sprite_triplets() -> Dictionary:
	var groups: Array[Dictionary] = []
	if combat_action == CombatAction.ATTACK and attack_groups.size() >= 8:
		groups = attack_groups
	elif combat_action == CombatAction.DEATH and death_groups.size() >= 8:
		groups = death_groups
	elif was_moving and movement_groups.size() >= 8:
		groups = movement_groups
	elif idle_groups.size() >= 8:
		groups = idle_groups
	elif movement_groups.size() >= 8:
		groups = movement_groups
	if groups.size() < 8:
		return {}
	var group := groups[clampi(animation_group_index, 0, 7)]
	if group.is_empty():
		return {}
	var primary_value: Variant = group.get("primary_triplet", [])
	var tertiary_value: Variant = group.get("tertiary_triplet", [])
	if (
		not primary_value is Array
		or (primary_value as Array).size() != 3
		or not tertiary_value is Array
		or (tertiary_value as Array).size() != 3
	):
		return {}
	return {
		"primary": (primary_value as Array),
		"tertiary": (tertiary_value as Array),
	}


func _draw() -> void:
	if sprite_texture != null:
		draw_texture(sprite_texture, -sprite_anchor)
	else:
		draw_flat_ellipse(
			Vector2(0.0, 8.0),
			Vector2(20.0, 10.0),
			Color(0.0, 0.0, 0.0, 0.35),
		)
		draw_circle(Vector2.ZERO, 15.0, body_color)
		draw_circle(Vector2(0.0, -12.0), 8.0, body_color.lightened(0.18))
		draw_line(Vector2(-8.0, 1.0), Vector2(11.0, 1.0), Color(0.13, 0.12, 0.09), 4.0)
	if maximum_hit_points > 0 and (selected or current_hit_points < maximum_hit_points):
		var health_ratio := clampf(
			float(current_hit_points) / float(maximum_hit_points), 0.0, 1.0
		)
		# Imported sprites have widely varying heights. Anchor the selection bar
		# above the actual sprite bounds, never across its face/body.
		var health_y := -maxf(sprite_anchor.y, 28.0) - 12.0
		draw_rect(Rect2(-18.0, health_y, 36.0, 5.0), Color(0.08, 0.08, 0.07, 0.85), true)
		draw_rect(
			Rect2(-17.0, health_y + 1.0, 34.0 * health_ratio, 3.0),
			Color(0.30, 0.78, 0.30) if health_ratio > 0.35 else Color(0.92, 0.25, 0.18),
			true,
		)
	if action_progress_ratio >= 0.0:
		var progress_y := -maxf(sprite_anchor.y, 28.0) - 20.0
		draw_rect(
			Rect2(-18.0, progress_y, 36.0, 4.0),
			Color(0.08, 0.08, 0.07, 0.88),
			true,
		)
		draw_rect(
			Rect2(-17.0, progress_y + 1.0, 34.0 * action_progress_ratio, 2.0),
			Color(0.88, 0.70, 0.22),
			true,
		)
	if selected:
		# Selection is communicated by the compact overhead health bar; the old
		# ground ring obscured the imported sprite and was unlike the original UI.
		pass


func draw_flat_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(24):
		var angle: float = TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
