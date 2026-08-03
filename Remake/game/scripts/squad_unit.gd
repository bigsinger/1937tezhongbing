class_name SquadUnit
extends Node2D

const BASE_SPRITE_TICK_SECONDS := 0.085
## A timestamped process-local trace of 710 consecutive m000 update rounds
## measured a 16.686 ms steady interval (59.930 Hz). Observation-marker and
## primary candidate-scan rand() calls therefore follow the 60 Hz actor
## update, independently of the slower idle/reaction counters below.
const ORIGINAL_ACTOR_RANDOM_TICK_SECONDS := 1.0 / 60.0
## sub_456070 (stationary action) and sub_4587E0 (route wait) run in the
## same measured 60 Hz actor update and mutate one shared counter. A
## stationary route actor therefore advances that counter twice per tick.
const ORIGINAL_AI_IDLE_TICK_SECONDS := ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
const ORIGINAL_LOCAL_SEARCH_CALL_SITES: Array[int] = [
	0x0005D08F,
	0x0005D09D,
	0x0005D0B4,
	0x0005D0CB,
	0x0005D15F,
]
const ORIGINAL_PRIMARY_SEARCH_CALL_SITES: Array[int] = [
	0x00055216,
	0x0005528C,
	0x000552A3,
	0x000552BA,
	0x000552D1,
]
const ORIGINAL_BLOCKED_RETRY_CALL_SITES: Array[int] = [
	0x00055BFB,
	0x00055C0F,
	0x00055C23,
	0x00055C3A,
]
const ORIGINAL_TRACKED_REACTION_CALL_SITES: Array[int] = [
	0x0005CB2B,
]
const ORIGINAL_SECONDARY_SEARCH_CALL_SITES: Array[int] = [
	0x0005CEA6,
	0x0005CF33,
	0x0005CF4A,
	0x0005CF61,
	0x0005CF78,
]
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
const LEGACY_ANIMATION_AUDIO_RULES: Script = preload(
	"res://scripts/legacy_animation_audio_rules.gd"
)
const AI_IDLE_RANDOM_RULES: Script = preload(
	"res://scripts/legacy_enemy_ai_rules.gd"
)
const LEGACY_DISGUISE_RULES: Script = preload(
	"res://scripts/legacy_disguise_rules.gd"
)
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)
const ORIGINAL_CRT_RANDOM_STARTUP_CATALOG: Script = preload(
	"res://scripts/original_crt_random_startup_catalog.gd"
)
const ORIGINAL_CRT_RANDOM_RUNTIME_STATE: Script = preload(
	"res://scripts/original_crt_random_runtime_state.gd"
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
signal original_animation_audio_requested(
	actor: Node2D,
	gfl_index: int,
	continuous: bool,
)
## sub_45D7B0 is reached from the addressed actor's runtime update slot.
## Ground-command input therefore queues the acknowledgement here instead of
## consuming the process-global CRT stream synchronously in the input handler.
signal original_command_audio_requested(actor: Node2D, family: String)
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
## The original runtime can keep an actor in a player command slot while its
## live faction/type still accepts the type-11 attention flag.  m007 Tiedan
## (scene 2298, runtime type 9, faction 1) is the recovered example.
var special_control_lock_count := 0
var special_control_source: Node2D
var scene_index := -1
var runtime_actor_type := 0
var original_runtime_index := -1
var original_native_actor_state: Dictionary = {}
var original_crt_level_id := ""
var original_crt_random_source: Node
var original_crt_initialization_profile: Dictionary = {}
var original_crt_observation_gate_enabled := false
var original_crt_observation_gate_elapsed := 0.0
var original_crt_observation_gate_passed := false
var original_crt_observation_gate_serial := 0
var original_crt_last_physics_frame := -1
var original_crt_primary_candidate_scan_enabled := false
var original_crt_primary_candidate_scan_elapsed := 0.0
var original_crt_primary_candidate_scan_passed := false
var original_crt_primary_candidate_scan_serial := 0
var original_crt_primary_candidate_last_physics_frame := -1
var original_crt_runtime_state_profile: Dictionary = {}
var original_secondary_search_enabled := false
var original_secondary_search_elapsed := 0.0
var original_secondary_search_contact_state := false
var original_secondary_search_gate_serial := 0
var original_secondary_search_trigger_serial := 0
var original_secondary_search_last_gate_value := -1
var original_secondary_search_last_candidate_runtime_index := -1
var original_secondary_search_last_goal := Vector2.ZERO
var original_secondary_search_last_navigation_applied := false
var original_secondary_search_last_physics_frame := -1
var original_pursuit_target_runtime_index := -1
var original_pursuit_target_scene_index := -1
var original_pursuit_target: Node2D
var original_pursuit_call_site_rva := 0
var original_pursuit_delay_counter := 0
var original_pursuit_elapsed := 0.0
var original_pursuit_serial := 0
var original_pursuit_last_physics_frame := -1
var original_pursuit_last_command_variant := 0
var original_pursuit_last_navigation_applied := false
var original_recurring_pursuit_last_round_index := 0
var original_recurring_shared_last_round_index := 0
var original_recurring_primary_last_round_index := 0
var original_recurring_secondary_last_round_index := 0
var original_recurring_blocked_last_round_index := 0
var original_recurring_reaction_last_round_index := 0
var original_recurring_actor_event_serial := 0
var original_recurring_actor_event_values_match := true
var original_recurring_blocked_retry_serial := 0
var original_recurring_blocked_retry_last_goal := Vector2.ZERO
var original_recurring_blocked_retry_last_navigation_applied := false
var original_recurring_tracked_reaction_serial := 0
var original_pending_acknowledgement_count := 0
var original_acknowledgement_serial := 0
var original_crt_primary_candidate_last_goal := Vector2.ZERO
var original_crt_primary_candidate_last_navigation_applied := false
var original_local_search_last_physics_frame := -1
var original_local_search_last_round_index := 0
var original_local_search_serial := 0
var original_local_search_point_index := 0
var original_local_search_values_match := true
var original_local_search_last_goal := Vector2.ZERO
var original_local_search_next_wait_limit := 0
var original_local_search_last_navigation_applied := false
var original_first_gameplay_update_serial := 0
var original_first_gameplay_semantic_effects: Array[String] = []
var original_first_gameplay_call_sites := PackedInt32Array()
var original_first_gameplay_goal_kind := 0
var original_first_gameplay_command_variant := 0
var original_first_gameplay_movement_path_state := 0
var original_first_gameplay_movement_mode := 0
var original_first_gameplay_goal := Vector2.ZERO
var original_first_gameplay_resolved_goal := Vector2.ZERO
var original_first_gameplay_route_wait_limit := -1
var original_first_gameplay_navigation_applied := false
var dynamic_occupancy: RefCounted
var dynamic_registered := false
var active_sprite_footprint_key := ""
## Stable-MOD patrol timelines can opt into original-style soft actor
## separation. Static movement layers remain authoritative; only other live
## actors and their transient goal reservations are ignored.
var use_soft_dynamic_occupancy := false
## Optional presentation/gameplay spacing override. A negative value keeps the
## recovered default; patrol controllers use a wider value so group members
## preserve a readable formation even when their authored routes overlap.
var minimum_actor_separation := -1.0
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
var row_slice_renderer: Node2D
var sprite_drawn_by_row_slices := false
var uniform_row_depth_enabled := false
var uniform_row_depth_offset := 0.0
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
var original_ai_previous_world_position := Vector2.ZERO
var original_ai_shared_counter_last_physics_frame := -1
var original_ai_stationary_reset_serial := 0
var original_ai_route_reset_serial := 0
var original_route_update_active := false
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
	sprite_drawn_by_row_slices = false
	uniform_row_depth_enabled = false
	uniform_row_depth_offset = 0.0
	if row_slice_renderer != null and is_instance_valid(row_slice_renderer):
		row_slice_renderer.call("clear_visual")
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
	original_ai_previous_world_position = start_position
	original_ai_shared_counter_last_physics_frame = -1
	original_ai_stationary_reset_serial = 0
	original_ai_route_reset_serial = 0
	original_route_update_active = false
	is_running = true
	is_crawling = false
	move_speed = RUN_SPEED
	scene_index = new_scene_index
	runtime_actor_type = 0
	original_runtime_index = -1
	original_native_actor_state.clear()
	original_crt_level_id = ""
	original_crt_random_source = null
	original_crt_initialization_profile.clear()
	original_crt_observation_gate_enabled = false
	original_crt_observation_gate_elapsed = 0.0
	original_crt_observation_gate_passed = false
	original_crt_observation_gate_serial = 0
	original_crt_last_physics_frame = -1
	original_crt_primary_candidate_scan_enabled = false
	original_crt_primary_candidate_scan_elapsed = 0.0
	original_crt_primary_candidate_scan_passed = false
	original_crt_primary_candidate_scan_serial = 0
	original_crt_primary_candidate_last_physics_frame = -1
	original_crt_runtime_state_profile.clear()
	original_secondary_search_enabled = false
	original_secondary_search_elapsed = 0.0
	original_secondary_search_contact_state = false
	original_secondary_search_gate_serial = 0
	original_secondary_search_trigger_serial = 0
	original_secondary_search_last_gate_value = -1
	original_secondary_search_last_candidate_runtime_index = -1
	original_secondary_search_last_goal = Vector2.ZERO
	original_secondary_search_last_navigation_applied = false
	original_secondary_search_last_physics_frame = -1
	original_pursuit_target_runtime_index = -1
	original_pursuit_target_scene_index = -1
	original_pursuit_target = null
	original_pursuit_call_site_rva = 0
	original_pursuit_delay_counter = 0
	original_pursuit_elapsed = 0.0
	original_pursuit_serial = 0
	original_pursuit_last_physics_frame = -1
	original_pursuit_last_command_variant = 0
	original_pursuit_last_navigation_applied = false
	original_recurring_pursuit_last_round_index = 0
	original_recurring_shared_last_round_index = 0
	original_recurring_primary_last_round_index = 0
	original_recurring_secondary_last_round_index = 0
	original_recurring_blocked_last_round_index = 0
	original_recurring_reaction_last_round_index = 0
	original_recurring_actor_event_serial = 0
	original_recurring_actor_event_values_match = true
	original_recurring_blocked_retry_serial = 0
	original_recurring_blocked_retry_last_goal = Vector2.ZERO
	original_recurring_blocked_retry_last_navigation_applied = false
	original_recurring_tracked_reaction_serial = 0
	original_crt_primary_candidate_last_goal = Vector2.ZERO
	original_crt_primary_candidate_last_navigation_applied = false
	original_local_search_last_physics_frame = -1
	original_local_search_last_round_index = 0
	original_local_search_serial = 0
	original_local_search_point_index = 0
	original_local_search_values_match = true
	original_local_search_last_goal = Vector2.ZERO
	original_local_search_next_wait_limit = 0
	original_local_search_last_navigation_applied = false
	original_first_gameplay_update_serial = 0
	original_first_gameplay_semantic_effects.clear()
	original_first_gameplay_call_sites.clear()
	original_first_gameplay_goal_kind = 0
	original_first_gameplay_command_variant = 0
	original_first_gameplay_movement_path_state = 0
	original_first_gameplay_movement_mode = 0
	original_first_gameplay_goal = Vector2.ZERO
	original_first_gameplay_resolved_goal = Vector2.ZERO
	original_first_gameplay_route_wait_limit = -1
	original_first_gameplay_navigation_applied = false
	dynamic_occupancy = new_dynamic_occupancy
	use_soft_dynamic_occupancy = false
	minimum_actor_separation = -1.0
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
	special_control_lock_count = 0
	special_control_source = null
	if (
		dynamic_occupancy != null
		and scene_index >= 0
	):
		dynamic_registered = dynamic_occupancy.register_scene(
			scene_index, start_position, new_source_reference_position
		)
		if not dynamic_registered:
			dynamic_occupancy = null
	_update_sprite_depth()
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
	# Startup construction consumes the process-global stream before gameplay.
	# The process-local original trace supplies the final active actor's exact
	# rand()%160 value. Synthetic actors and isolated unit tests retain the
	# deterministic local fallback.
	original_ai_idle_random_state = int(
		(scene_index * 214013 + 2531011) & 0x7fffffff
	)
	if original_ai_idle_random_state == 0:
		original_ai_idle_random_state = 1
	if original_crt_initialization_profile.has("initial_idle_limit"):
		original_ai_idle_tick_limit = clampi(
			int(original_crt_initialization_profile.get(
				"initial_idle_limit",
				0,
			)),
			0,
			AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN - 1,
		)
	else:
		original_ai_idle_random_state = (
			AI_IDLE_RANDOM_RULES.msvc_rand_step(
				original_ai_idle_random_state
			)
		)
		original_ai_idle_tick_limit = (
			AI_IDLE_RANDOM_RULES.msvc_rand_value(
				original_ai_idle_random_state
			)
			% AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
		)
	original_ai_previous_world_position = position
	original_ai_shared_counter_last_physics_frame = -1
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
		"previous_world_x": original_ai_previous_world_position.x,
		"previous_world_y": original_ai_previous_world_position.y,
		"stationary_reset_serial": original_ai_stationary_reset_serial,
		"route_reset_serial": original_ai_route_reset_serial,
		"route_update_active": original_route_update_active,
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
	original_ai_previous_world_position = Vector2(
		float(state.get("previous_world_x", position.x)),
		float(state.get("previous_world_y", position.y)),
	)
	original_ai_stationary_reset_serial = maxi(
		int(state.get("stationary_reset_serial", 0)),
		0,
	)
	original_ai_route_reset_serial = maxi(
		int(state.get("route_reset_serial", 0)),
		0,
	)
	original_route_update_active = bool(
		state.get("route_update_active", original_route_update_active)
	)
	original_ai_shared_counter_last_physics_frame = -1
	original_ai_idle_action_active = original_ai_idle_uses_stand_action(
		original_ai_idle_tick_counter,
		original_ai_idle_tick_limit,
	)
	_apply_current_idle_visual(0.0)
	return true


func configure_runtime_actor_type(entity: Dictionary) -> int:
	runtime_actor_type = 0
	original_native_actor_state.clear()
	var header_values: Variant = entity.get("database_header_values", [])
	if header_values is Array and (header_values as Array).size() > 2:
		runtime_actor_type = int((header_values as Array)[2])
	var runtime_profile_value: Variant = entity.get(
		"original_runtime_profile",
		{},
	)
	if runtime_profile_value is Dictionary:
		original_runtime_index = int(
			(runtime_profile_value as Dictionary).get(
				"runtime_index",
				-1,
			)
		)
	else:
		original_runtime_index = -1
	var native_state_value: Variant = entity.get("native_actor_state", {})
	if native_state_value is Dictionary:
		original_native_actor_state = (
			(native_state_value as Dictionary).duplicate(true)
		)
	original_pursuit_target_scene_index = int(
		original_native_actor_state.get(
			"pursuit_actor_scene_index",
			-1,
		)
	)
	original_secondary_search_enabled = (
		AI_IDLE_RANDOM_RULES.secondary_search_runtime_type_enabled(
			runtime_actor_type
		)
	)
	return runtime_actor_type


func original_native_initial_facing_direction(fallback: int) -> int:
	var normalized_fallback := clampi(fallback, 1, 8)
	if (
		int(original_native_actor_state.get(
			"stationary_route_facing_restore_enabled",
			0,
		)) == 0
	):
		return normalized_fallback
	var stored_direction := int(original_native_actor_state.get(
		"stationary_route_facing_direction",
		normalized_fallback,
	))
	return (
		stored_direction
		if stored_direction >= 1 and stored_direction <= 8
		else normalized_fallback
	)


func bind_original_crt_random_source(
	source: Node,
	level_id: String,
	observation_gate_override: int = -1,
) -> bool:
	original_crt_random_source = source
	original_crt_level_id = level_id
	original_crt_initialization_profile = (
		ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.actor_initialization(
			level_id,
			original_runtime_index,
		)
		if original_runtime_index >= 0
		else {}
	)
	original_crt_observation_gate_enabled = (
		observation_gate_override > 0
		if observation_gate_override >= 0
		else (
			original_runtime_index >= 0
			and ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.is_observation_gate_actor(
				level_id,
				original_runtime_index,
			)
		)
	)
	original_crt_observation_gate_elapsed = 0.0
	original_crt_observation_gate_passed = false
	original_crt_observation_gate_serial = 0
	original_crt_last_physics_frame = -1
	original_crt_primary_candidate_scan_enabled = false
	original_crt_primary_candidate_scan_elapsed = 0.0
	original_crt_primary_candidate_scan_passed = false
	original_crt_primary_candidate_scan_serial = 0
	original_crt_primary_candidate_last_physics_frame = -1
	original_secondary_search_enabled = (
		AI_IDLE_RANDOM_RULES.secondary_search_dispatch_enabled(
			level_id,
			runtime_actor_type
		)
	)
	original_secondary_search_elapsed = 0.0
	original_secondary_search_contact_state = false
	original_secondary_search_gate_serial = 0
	original_secondary_search_trigger_serial = 0
	original_secondary_search_last_gate_value = -1
	original_secondary_search_last_candidate_runtime_index = -1
	original_secondary_search_last_goal = Vector2.ZERO
	original_secondary_search_last_navigation_applied = false
	original_secondary_search_last_physics_frame = -1
	original_crt_runtime_state_profile = (
		ORIGINAL_CRT_RANDOM_RUNTIME_STATE.actor_profile(
			level_id,
			original_runtime_index,
		)
		if original_runtime_index >= 0
		else {}
	)
	var runtime_entry_value: Variant = (
		original_crt_runtime_state_profile.get("entry", {})
	)
	var has_runtime_shared_counter := false
	if runtime_entry_value is Dictionary:
		var runtime_entry := runtime_entry_value as Dictionary
		original_route_update_active = (
			int(runtime_entry.get(
				"route_update_active",
				0,
			)) == 1
		)
		if (
			runtime_entry.has("stationary_tick_counter")
			and runtime_entry.has("stationary_tick_limit")
		):
			original_ai_idle_tick_counter = maxi(
				int(runtime_entry.get("stationary_tick_counter", 0)),
				0,
			)
			original_ai_idle_tick_limit = clampi(
				int(runtime_entry.get("stationary_tick_limit", 0)),
				0,
				(
					AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT
					+ AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
					- 1
				),
			)
			has_runtime_shared_counter = true
		original_secondary_search_contact_state = (
			int(runtime_entry.get("contact_state", 0)) != 0
		)
	else:
		original_route_update_active = (
			int(original_native_actor_state.get(
				"route_update_active",
				0,
			)) != 0
		)
		original_secondary_search_contact_state = (
			int(original_native_actor_state.get(
				"contact_state",
				0,
			)) != 0
		)
	original_ai_previous_world_position = position
	original_ai_shared_counter_last_physics_frame = -1
	original_ai_stationary_reset_serial = 0
	original_ai_route_reset_serial = 0
	original_ai_idle_tick_elapsed = 0.0
	if not has_runtime_shared_counter:
		original_ai_idle_tick_counter = 0
	if (
		not has_runtime_shared_counter
		and original_crt_initialization_profile.has("initial_idle_limit")
	):
		original_ai_idle_tick_limit = clampi(
			int(original_crt_initialization_profile.get(
				"initial_idle_limit",
				0,
			)),
			0,
			AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN - 1,
		)
	original_pursuit_target_runtime_index = (
		ORIGINAL_CRT_RANDOM_RUNTIME_STATE
		. pursuit_target_runtime_index(
			level_id,
			original_runtime_index,
		)
		if original_runtime_index >= 0
		else -1
	)
	original_pursuit_target = null
	original_pursuit_call_site_rva = (
		ORIGINAL_CRT_RANDOM_RUNTIME_STATE.pursuit_call_site_rva(
			level_id,
			original_runtime_index,
		)
		if original_runtime_index >= 0
		else 0
	)
	if (
		original_pursuit_target_runtime_index >= 0
		and original_pursuit_call_site_rva == 0
	):
		original_pursuit_call_site_rva = (
			0x0005D394
			if runtime_actor_type == 56
			else 0x0005D47E
		)
	original_pursuit_delay_counter = (
		maxi(
			int((runtime_entry_value as Dictionary).get(
				"pursuit_delay_counter",
				0,
			)),
			0,
		)
		if runtime_entry_value is Dictionary
		else 0
	)
	original_pursuit_elapsed = 0.0
	original_pursuit_serial = 0
	original_pursuit_last_physics_frame = -1
	original_pursuit_last_command_variant = 0
	original_pursuit_last_navigation_applied = false
	original_recurring_pursuit_last_round_index = 0
	original_recurring_shared_last_round_index = 0
	original_recurring_actor_event_serial = 0
	original_recurring_actor_event_values_match = true
	# Playable, ambient and enemy nodes are created in separate batches, while
	# the native executable updates one runtime-index array. Physics priority
	# restores that exact actor consumer order without changing input/focus.
	process_physics_priority = (
		1000 + original_runtime_index
		if original_runtime_index >= 0
		else 2_000_000
	)
	return (
		original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
	)


func initialize_dynamic_original_crt_random() -> bool:
	if (
		original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"next_legacy_crt_random"
		)
	):
		return false
	var idle_value := next_original_crt_random_value(0x00050967)
	var facing_value := next_original_crt_random_value(0x00050980)
	var phase_value := next_original_crt_random_value(0x0005340B)
	var reaction_value := next_original_crt_random_value(0x0005358B)
	# sub_44A350 creates a runtime actor through the normal constructor and then
	# sub_45B950(..., 0) replaces its facing with max(rand() % 9, 1).  Keep that
	# fifth draw in the shared stream; authored startup actors remain checkpointed.
	var loaded_facing_value := next_original_crt_random_value(0x0005BBBC)
	if (
		idle_value < 0
		or facing_value < 0
		or phase_value < 0
		or reaction_value < 0
		or loaded_facing_value < 0
	):
		return false
	var constructor_facing := mini((facing_value % 9) + 1, 8)
	var loaded_facing := maxi(loaded_facing_value % 9, 1)
	original_crt_initialization_profile = {
		"runtime_index": original_runtime_index,
		"scene_index": scene_index,
		"initial_idle_limit": idle_value % 160,
		"constructor_facing_direction": constructor_facing,
		"initial_facing_direction": loaded_facing,
		"initial_ai_phase": phase_value % 60,
		"initial_reaction_limit": (reaction_value % 40) + 40,
	}
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_limit = idle_value % 160
	original_ai_idle_tick_elapsed = 0.0
	original_ai_previous_world_position = position
	original_ai_shared_counter_last_physics_frame = -1
	set_animation_group(loaded_facing - 1)
	apply_idle_frame()
	return true


func consume_retired_original_crt_random() -> bool:
	if (
		original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"next_legacy_crt_random"
		)
	):
		return false
	# Actor removal reaches the derived sub_4538A0 destructor first.  Its
	# sub_453650 reset consumes the AI phase/reaction pair; the base sub_450CE0
	# destructor then calls sub_450AC0 for the idle/facing pair.  The values are
	# written only to the retired native object, so preserve their stream order
	# and diagnostics without mutating the surviving Remake node.
	var reset_ai_phase := next_original_crt_random_value(0x00053655)
	var reset_reaction := next_original_crt_random_value(0x000537A3)
	var reset_idle := next_original_crt_random_value(0x00050B64)
	var reset_facing := next_original_crt_random_value(0x00050B7D)
	if (
		reset_ai_phase < 0
		or reset_reaction < 0
		or reset_idle < 0
		or reset_facing < 0
	):
		return false
	original_crt_initialization_profile["retired_actor_reset"] = {
		"ai_phase": reset_ai_phase % 60,
		"reaction_limit": (reset_reaction % 40) + 40,
		"idle_limit": reset_idle % 160,
		"facing_direction": mini((reset_facing % 9) + 1, 8),
	}
	return true


func bind_original_pursuit_target(target: Node2D) -> bool:
	if (
		original_pursuit_target_runtime_index < 0
		and original_pursuit_target_scene_index < 0
	):
		original_pursuit_target = null
		return target == null
	if (
		target == null
		or not is_instance_valid(target)
		or (
			original_pursuit_target_runtime_index >= 0
			and int(target.get("original_runtime_index"))
				!= original_pursuit_target_runtime_index
		)
		or (
			original_pursuit_target_scene_index >= 0
			and int(target.get("scene_index"))
				!= original_pursuit_target_scene_index
		)
	):
		return false
	original_pursuit_target = target
	if original_pursuit_target_runtime_index < 0:
		original_pursuit_target_runtime_index = int(
			target.get("original_runtime_index")
		)
	if original_pursuit_target_scene_index < 0:
		original_pursuit_target_scene_index = int(target.get("scene_index"))
	if original_pursuit_call_site_rva == 0:
		original_pursuit_call_site_rva = (
			0x0005D394
			if runtime_actor_type == 56
			else 0x0005D47E
		)
	return true


func original_pursuit_snapshot() -> Dictionary:
	return {
		"target_runtime_index": original_pursuit_target_runtime_index,
		"target_scene_index": original_pursuit_target_scene_index,
		"call_site_rva": original_pursuit_call_site_rva,
		"delay_counter": original_pursuit_delay_counter,
		"elapsed": original_pursuit_elapsed,
		"serial": original_pursuit_serial,
		"last_command_variant": original_pursuit_last_command_variant,
		"last_navigation_applied": (
			original_pursuit_last_navigation_applied
		),
	}


func next_original_crt_random_value(call_site_rva: int) -> int:
	if (
		original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"next_legacy_crt_random"
		)
	):
		return -1
	var draw_value: Variant = original_crt_random_source.call(
		"next_legacy_crt_random",
		call_site_rva,
		original_runtime_index,
	)
	if not draw_value is Dictionary or (draw_value as Dictionary).is_empty():
		return -1
	return int((draw_value as Dictionary).get("value", -1))


func next_original_crt_random_values(
	call_site_rvas: Array[int],
) -> Array[int]:
	var values: Array[int] = []
	if (
		original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"next_legacy_crt_random"
		)
	):
		return values
	for call_site_rva: int in call_site_rvas:
		var value := next_original_crt_random_value(call_site_rva)
		if value < 0:
			return []
		values.append(value)
	return values


func _original_recurring_evidence_round_index() -> int:
	if (
		original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"original_recurring_evidence_round_index"
		)
	):
		return 0
	return maxi(
		int(original_crt_random_source.call(
			"original_recurring_evidence_round_index"
		)),
		0,
	)


func _original_recurring_actor_events(
	accepted_call_sites: Array[int],
) -> Array[Dictionary]:
	if (
		original_runtime_index < 0
		or _original_recurring_evidence_round_index() <= 0
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"original_recurring_actor_events"
		)
	):
		return []
	var events_value: Variant = original_crt_random_source.call(
		"original_recurring_actor_events",
		original_runtime_index,
		accepted_call_sites,
	)
	var events: Array[Dictionary] = []
	if not events_value is Array:
		return events
	for event_value: Variant in events_value as Array:
		if event_value is Dictionary:
			events.append((event_value as Dictionary).duplicate(true))
	return events


func original_crt_random_timing_snapshot() -> Dictionary:
	return {
		"level_id": original_crt_level_id,
		"runtime_index": original_runtime_index,
		"observation_gate_enabled": (
			original_crt_observation_gate_enabled
		),
		"observation_gate_elapsed": (
			original_crt_observation_gate_elapsed
		),
		"observation_gate_passed": (
			original_crt_observation_gate_passed
		),
		"observation_gate_serial": (
			original_crt_observation_gate_serial
		),
		"primary_candidate_scan_enabled": (
			original_crt_primary_candidate_scan_enabled
		),
		"primary_candidate_scan_elapsed": (
			original_crt_primary_candidate_scan_elapsed
		),
		"primary_candidate_scan_passed": (
			original_crt_primary_candidate_scan_passed
		),
		"primary_candidate_scan_serial": (
			original_crt_primary_candidate_scan_serial
		),
		"primary_candidate_last_goal_x": (
			original_crt_primary_candidate_last_goal.x
		),
		"primary_candidate_last_goal_y": (
			original_crt_primary_candidate_last_goal.y
		),
		"primary_candidate_last_navigation_applied": (
			original_crt_primary_candidate_last_navigation_applied
		),
		"pending_acknowledgement_count": (
			original_pending_acknowledgement_count
		),
		"acknowledgement_serial": original_acknowledgement_serial,
		"secondary_search": original_secondary_search_snapshot(),
		"pursuit": original_pursuit_snapshot(),
		"recurring_actor_events": {
			"pursuit_last_round_index": (
				original_recurring_pursuit_last_round_index
			),
			"shared_last_round_index": (
				original_recurring_shared_last_round_index
			),
			"primary_last_round_index": (
				original_recurring_primary_last_round_index
			),
			"secondary_last_round_index": (
				original_recurring_secondary_last_round_index
			),
			"blocked_last_round_index": (
				original_recurring_blocked_last_round_index
			),
			"reaction_last_round_index": (
				original_recurring_reaction_last_round_index
			),
			"serial": original_recurring_actor_event_serial,
			"values_match": (
				original_recurring_actor_event_values_match
			),
			"blocked_retry_serial": (
				original_recurring_blocked_retry_serial
			),
			"blocked_retry_last_goal_x": (
				original_recurring_blocked_retry_last_goal.x
			),
			"blocked_retry_last_goal_y": (
				original_recurring_blocked_retry_last_goal.y
			),
			"blocked_retry_last_navigation_applied": (
				original_recurring_blocked_retry_last_navigation_applied
			),
			"tracked_reaction_serial": (
				original_recurring_tracked_reaction_serial
			),
		},
		"local_search": original_local_search_snapshot(),
		"first_gameplay_update_serial": (
			original_first_gameplay_update_serial
		),
		"first_gameplay_semantic_effects": (
			original_first_gameplay_semantic_effects.duplicate()
		),
		"first_gameplay_call_sites": Array(
			original_first_gameplay_call_sites
		),
		"first_gameplay_goal_kind": (
			original_first_gameplay_goal_kind
		),
		"first_gameplay_command_variant": (
			original_first_gameplay_command_variant
		),
		"first_gameplay_movement_path_state": (
			original_first_gameplay_movement_path_state
		),
		"first_gameplay_movement_mode": (
			original_first_gameplay_movement_mode
		),
		"first_gameplay_goal_x": original_first_gameplay_goal.x,
		"first_gameplay_goal_y": original_first_gameplay_goal.y,
		"first_gameplay_resolved_goal_x": (
			original_first_gameplay_resolved_goal.x
		),
		"first_gameplay_resolved_goal_y": (
			original_first_gameplay_resolved_goal.y
		),
		"first_gameplay_route_wait_limit": (
			original_first_gameplay_route_wait_limit
		),
		"first_gameplay_navigation_applied": (
			original_first_gameplay_navigation_applied
		),
	}


func restore_original_crt_random_timing(state: Dictionary) -> bool:
	if (
		state.is_empty()
		or str(state.get("level_id", original_crt_level_id))
			!= original_crt_level_id
		or int(state.get("runtime_index", original_runtime_index))
			!= original_runtime_index
	):
		return false
	original_crt_observation_gate_elapsed = clampf(
		float(state.get("observation_gate_elapsed", 0.0)),
		0.0,
		ORIGINAL_ACTOR_RANDOM_TICK_SECONDS,
	)
	original_crt_observation_gate_passed = bool(
		state.get("observation_gate_passed", false)
	)
	original_crt_observation_gate_serial = maxi(
		int(state.get("observation_gate_serial", 0)),
		0,
	)
	original_crt_primary_candidate_scan_enabled = bool(
		state.get(
			"primary_candidate_scan_enabled",
			original_crt_primary_candidate_scan_enabled,
		)
	)
	original_crt_primary_candidate_scan_elapsed = clampf(
		float(state.get("primary_candidate_scan_elapsed", 0.0)),
		0.0,
		ORIGINAL_ACTOR_RANDOM_TICK_SECONDS,
	)
	original_crt_primary_candidate_scan_passed = bool(
		state.get("primary_candidate_scan_passed", false)
	)
	original_crt_primary_candidate_scan_serial = maxi(
		int(state.get("primary_candidate_scan_serial", 0)),
		0,
	)
	original_crt_primary_candidate_last_goal = Vector2(
		float(state.get("primary_candidate_last_goal_x", 0.0)),
		float(state.get("primary_candidate_last_goal_y", 0.0)),
	)
	original_crt_primary_candidate_last_navigation_applied = bool(
		state.get(
			"primary_candidate_last_navigation_applied",
			false,
		)
	)
	original_pending_acknowledgement_count = maxi(
		int(state.get("pending_acknowledgement_count", 0)),
		0,
	)
	original_acknowledgement_serial = maxi(
		int(state.get("acknowledgement_serial", 0)),
		0,
	)
	var secondary_search_value: Variant = state.get(
		"secondary_search",
		{},
	)
	if secondary_search_value is Dictionary:
		var secondary_search_state := (
			secondary_search_value as Dictionary
		)
		if (
			bool(secondary_search_state.get(
				"enabled",
				original_secondary_search_enabled,
			)) != original_secondary_search_enabled
		):
			return false
		original_secondary_search_elapsed = clampf(
			float(secondary_search_state.get("elapsed", 0.0)),
			0.0,
			ORIGINAL_ACTOR_RANDOM_TICK_SECONDS,
		)
		original_secondary_search_contact_state = bool(
			secondary_search_state.get("contact_state", false)
		)
		original_secondary_search_gate_serial = maxi(
			int(secondary_search_state.get("gate_serial", 0)),
			0,
		)
		original_secondary_search_trigger_serial = maxi(
			int(secondary_search_state.get("trigger_serial", 0)),
			0,
		)
		original_secondary_search_last_gate_value = int(
			secondary_search_state.get("last_gate_value", -1)
		)
		original_secondary_search_last_candidate_runtime_index = int(
			secondary_search_state.get(
				"last_candidate_runtime_index",
				-1,
			)
		)
		original_secondary_search_last_goal = Vector2(
			float(secondary_search_state.get("last_goal_x", 0.0)),
			float(secondary_search_state.get("last_goal_y", 0.0)),
		)
		original_secondary_search_last_navigation_applied = bool(
			secondary_search_state.get(
				"last_navigation_applied",
				false,
			)
		)
	var pursuit_value: Variant = state.get("pursuit", {})
	if pursuit_value is Dictionary:
		var pursuit_state := pursuit_value as Dictionary
		if (
			int(pursuit_state.get(
				"target_runtime_index",
				original_pursuit_target_runtime_index,
			)) != original_pursuit_target_runtime_index
			or int(pursuit_state.get(
				"target_scene_index",
				original_pursuit_target_scene_index,
			)) != original_pursuit_target_scene_index
			or int(pursuit_state.get(
				"call_site_rva",
				original_pursuit_call_site_rva,
			)) != original_pursuit_call_site_rva
		):
			return false
		original_pursuit_delay_counter = maxi(
			int(pursuit_state.get("delay_counter", 0)),
			0,
		)
		original_pursuit_elapsed = clampf(
			float(pursuit_state.get("elapsed", 0.0)),
			0.0,
			ORIGINAL_ACTOR_RANDOM_TICK_SECONDS,
		)
		original_pursuit_serial = maxi(
			int(pursuit_state.get("serial", 0)),
			0,
		)
		original_pursuit_last_command_variant = int(
			pursuit_state.get("last_command_variant", 0)
		)
		original_pursuit_last_navigation_applied = bool(
			pursuit_state.get("last_navigation_applied", false)
		)
	var recurring_actor_events_value: Variant = state.get(
		"recurring_actor_events",
		{},
	)
	if recurring_actor_events_value is Dictionary:
		var recurring_actor_events_state := (
			recurring_actor_events_value as Dictionary
		)
		original_recurring_pursuit_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"pursuit_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_shared_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"shared_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_primary_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"primary_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_secondary_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"secondary_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_blocked_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"blocked_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_reaction_last_round_index = maxi(
			int(recurring_actor_events_state.get(
				"reaction_last_round_index",
				0,
			)),
			0,
		)
		original_recurring_actor_event_serial = maxi(
			int(recurring_actor_events_state.get("serial", 0)),
			0,
		)
		original_recurring_actor_event_values_match = bool(
			recurring_actor_events_state.get("values_match", true)
		)
		original_recurring_blocked_retry_serial = maxi(
			int(recurring_actor_events_state.get(
				"blocked_retry_serial",
				0,
			)),
			0,
		)
		original_recurring_blocked_retry_last_goal = Vector2(
			float(recurring_actor_events_state.get(
				"blocked_retry_last_goal_x",
				0.0,
			)),
			float(recurring_actor_events_state.get(
				"blocked_retry_last_goal_y",
				0.0,
			)),
		)
		original_recurring_blocked_retry_last_navigation_applied = bool(
			recurring_actor_events_state.get(
				"blocked_retry_last_navigation_applied",
				false,
			)
		)
		original_recurring_tracked_reaction_serial = maxi(
			int(recurring_actor_events_state.get(
				"tracked_reaction_serial",
				0,
			)),
			0,
		)
	var local_search_value: Variant = state.get("local_search", {})
	if local_search_value is Dictionary:
		var local_search_state := local_search_value as Dictionary
		original_local_search_last_round_index = maxi(
			int(local_search_state.get("last_round_index", 0)),
			0,
		)
		original_local_search_serial = maxi(
			int(local_search_state.get("serial", 0)),
			0,
		)
		original_local_search_point_index = clampi(
			int(local_search_state.get("point_index", 0)),
			0,
			AI_IDLE_RANDOM_RULES.SEARCH_POINT_COUNT,
		)
		original_local_search_values_match = bool(
			local_search_state.get("values_match", true)
		)
		original_local_search_last_goal = Vector2(
			float(local_search_state.get("last_goal_x", 0.0)),
			float(local_search_state.get("last_goal_y", 0.0)),
		)
		original_local_search_next_wait_limit = clampi(
			int(local_search_state.get("next_wait_limit", 0)),
			0,
			(
				AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT
				+ AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
				- 1
			),
		)
		original_local_search_last_navigation_applied = bool(
			local_search_state.get("last_navigation_applied", false)
		)
	original_first_gameplay_update_serial = maxi(
		int(state.get("first_gameplay_update_serial", 0)),
		0,
	)
	original_first_gameplay_semantic_effects.clear()
	var effects_value: Variant = state.get(
		"first_gameplay_semantic_effects",
		[],
	)
	if effects_value is Array:
		for effect_value: Variant in effects_value as Array:
			var effect := str(effect_value)
			if not effect.is_empty():
				original_first_gameplay_semantic_effects.append(effect)
	original_first_gameplay_call_sites.clear()
	var call_sites_value: Variant = state.get(
		"first_gameplay_call_sites",
		[],
	)
	if call_sites_value is Array:
		for call_site_value: Variant in call_sites_value as Array:
			original_first_gameplay_call_sites.append(
				int(call_site_value)
			)
	original_first_gameplay_goal_kind = int(
		state.get("first_gameplay_goal_kind", 0)
	)
	original_first_gameplay_command_variant = int(
		state.get("first_gameplay_command_variant", 0)
	)
	original_first_gameplay_movement_path_state = int(
		state.get("first_gameplay_movement_path_state", 0)
	)
	original_first_gameplay_movement_mode = int(
		state.get("first_gameplay_movement_mode", 0)
	)
	original_first_gameplay_goal = Vector2(
		float(state.get("first_gameplay_goal_x", 0.0)),
		float(state.get("first_gameplay_goal_y", 0.0)),
	)
	original_first_gameplay_resolved_goal = Vector2(
		float(state.get("first_gameplay_resolved_goal_x", 0.0)),
		float(state.get("first_gameplay_resolved_goal_y", 0.0)),
	)
	original_first_gameplay_route_wait_limit = int(
		state.get("first_gameplay_route_wait_limit", -1)
	)
	original_first_gameplay_navigation_applied = bool(
		state.get("first_gameplay_navigation_applied", false)
	)
	original_crt_last_physics_frame = -1
	original_crt_primary_candidate_last_physics_frame = -1
	original_secondary_search_last_physics_frame = -1
	original_pursuit_last_physics_frame = -1
	original_local_search_last_physics_frame = -1
	return true


func _advance_original_crt_actor_random_tick(delta: float) -> void:
	_advance_original_crt_observation_gate(delta)
	_advance_original_recurring_tracked_reaction_events()
	if original_secondary_search_enabled:
		_advance_original_secondary_search(delta)
	else:
		_advance_original_pursuit(delta)
	_advance_original_recurring_pursuit_events()
	_advance_original_crt_primary_candidate_scan(delta)
	_advance_original_recurring_local_search()


func _consume_original_recurring_actor_events(
	accepted_call_sites: Array[int],
) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for event: Dictionary in _original_recurring_actor_events(
		accepted_call_sites
	):
		var call_site_rva := int(event.get("call_site_rva", 0))
		var actual_value := next_original_crt_random_value(call_site_rva)
		if actual_value < 0:
			break
		original_recurring_actor_event_serial += 1
		original_recurring_actor_event_values_match = (
			original_recurring_actor_event_values_match
			and actual_value == int(event.get("value", -1))
		)
		var applied_event := event.duplicate(true)
		applied_event["actual_value"] = actual_value
		consumed.append(applied_event)
	return consumed


func _advance_original_recurring_tracked_reaction_events() -> bool:
	var round_index := _original_recurring_evidence_round_index()
	if (
		round_index <= 0
		or round_index <= original_recurring_reaction_last_round_index
		or not is_alive
	):
		return false
	original_recurring_reaction_last_round_index = round_index
	var events := _consume_original_recurring_actor_events(
		ORIGINAL_TRACKED_REACTION_CALL_SITES
	)
	if events.is_empty():
		return false
	var handled := false
	for event: Dictionary in events:
		if int(event.get("call_site_rva", 0)) != 0x0005CB2B:
			original_recurring_actor_event_values_match = false
			continue
		original_recurring_tracked_reaction_serial += 1
		handled = (
			_apply_original_tracked_target_reaction_value(
				int(event.get("actual_value", -1))
			)
			or handled
		)
	return handled


func _apply_original_tracked_target_reaction_value(
	random_value: int,
) -> bool:
	if random_value < 0:
		return false
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_limit = (
		random_value % AI_IDLE_RANDOM_RULES.REACTION_RANDOM_SPAN
		+ AI_IDLE_RANDOM_RULES.REACTION_MINIMUM_LIMIT
	)
	original_ai_idle_tick_elapsed = 0.0
	return true


func _advance_original_recurring_blocked_retry_events() -> bool:
	var round_index := _original_recurring_evidence_round_index()
	if (
		round_index <= 0
		or round_index <= original_recurring_blocked_last_round_index
		or not is_alive
	):
		return false
	original_recurring_blocked_last_round_index = round_index
	var events := _consume_original_recurring_actor_events(
		ORIGINAL_BLOCKED_RETRY_CALL_SITES
	)
	if events.is_empty():
		return false
	if events.size() != ORIGINAL_BLOCKED_RETRY_CALL_SITES.size():
		original_recurring_actor_event_values_match = false
		return true
	var origin := position
	var values: Array[int] = []
	for event_index: int in range(events.size()):
		var event := events[event_index]
		if (
			int(event.get("call_site_rva", 0))
			!= ORIGINAL_BLOCKED_RETRY_CALL_SITES[event_index]
		):
			original_recurring_actor_event_values_match = false
			return true
		if event_index == 0:
			var evidence_x := int(event.get("world_x", -1))
			var evidence_y := int(event.get("world_y", -1))
			if evidence_x >= 0 and evidence_y >= 0:
				origin = Vector2(evidence_x, evidence_y)
		values.append(int(event.get("actual_value", -1)))
	original_recurring_blocked_retry_serial += 1
	original_recurring_blocked_retry_last_goal = (
		AI_IDLE_RANDOM_RULES.blocked_retry_point_from_values(
			values,
			origin,
			_original_secondary_search_world_bounds(),
		)
	)
	original_recurring_blocked_retry_last_navigation_applied = false
	if _should_apply_original_first_gameplay_navigation(
		"blocked_retry_destination"
	):
		original_recurring_blocked_retry_last_navigation_applied = (
			_issue_original_first_gameplay_path(
				original_recurring_blocked_retry_last_goal
			)
		)
	return true


func original_local_search_snapshot() -> Dictionary:
	return {
		"last_round_index": original_local_search_last_round_index,
		"serial": original_local_search_serial,
		"point_index": original_local_search_point_index,
		"values_match": original_local_search_values_match,
		"last_goal_x": original_local_search_last_goal.x,
		"last_goal_y": original_local_search_last_goal.y,
		"next_wait_limit": original_local_search_next_wait_limit,
		"last_navigation_applied": (
			original_local_search_last_navigation_applied
		),
	}


func _advance_original_recurring_local_search() -> bool:
	var physics_frame := Engine.get_physics_frames()
	if original_local_search_last_physics_frame == physics_frame:
		return false
	original_local_search_last_physics_frame = physics_frame
	if (
		not is_alive
		or original_runtime_index < 0
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
		or not original_crt_random_source.has_method(
			"original_recurring_local_search_event"
		)
	):
		return false
	var event_value: Variant = original_crt_random_source.call(
		"original_recurring_local_search_event",
		original_runtime_index,
	)
	if not event_value is Dictionary:
		return false
	var event := event_value as Dictionary
	if event.is_empty():
		return false
	var round_index := int(event.get("round_index", 0))
	if (
		round_index <= 0
		or round_index <= original_local_search_last_round_index
	):
		return false
	var expected_values_value: Variant = event.get("values", [])
	if (
		not expected_values_value is Array
		or (expected_values_value as Array).size()
			!= ORIGINAL_LOCAL_SEARCH_CALL_SITES.size()
	):
		return false
	var expected_values: Array[int] = []
	for value: Variant in expected_values_value as Array:
		expected_values.append(int(value))
	var actual_values := next_original_crt_random_values(
		ORIGINAL_LOCAL_SEARCH_CALL_SITES
	)
	if actual_values.size() != ORIGINAL_LOCAL_SEARCH_CALL_SITES.size():
		return false
	original_local_search_last_round_index = round_index
	original_local_search_serial += 1
	original_local_search_values_match = (
		actual_values == expected_values
	)
	var sampled: Dictionary = (
		AI_IDLE_RANDOM_RULES.local_search_point_from_values(
			actual_values,
			position,
			_original_secondary_search_world_bounds(),
		)
	)
	if sampled.is_empty():
		return false
	original_local_search_last_goal = sampled.get(
		"point",
		position,
	) as Vector2
	original_local_search_next_wait_limit = int(
		sampled.get(
			"next_wait_limit",
			AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT,
		)
	)
	# sub_45D060 clears the shared +0x16C counter and writes the fifth
	# rand()%160+40 result to +0x170 before issuing the coordinate command.
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_limit = original_local_search_next_wait_limit
	original_ai_idle_tick_elapsed = 0.0
	original_route_update_active = false
	original_local_search_point_index += 1
	if (
		original_local_search_point_index
		> AI_IDLE_RANDOM_RULES.SEARCH_POINT_COUNT
	):
		original_local_search_point_index = 1
	cancel_path()
	original_local_search_last_navigation_applied = (
		_issue_original_first_gameplay_path(
			original_local_search_last_goal
		)
	)
	return true


func original_secondary_search_snapshot() -> Dictionary:
	return {
		"enabled": original_secondary_search_enabled,
		"elapsed": original_secondary_search_elapsed,
		"contact_state": original_secondary_search_contact_state,
		"gate_serial": original_secondary_search_gate_serial,
		"trigger_serial": original_secondary_search_trigger_serial,
		"last_gate_value": original_secondary_search_last_gate_value,
		"last_candidate_runtime_index": (
			original_secondary_search_last_candidate_runtime_index
		),
		"last_goal_x": original_secondary_search_last_goal.x,
		"last_goal_y": original_secondary_search_last_goal.y,
		"last_navigation_applied": (
			original_secondary_search_last_navigation_applied
		),
	}


func _advance_original_secondary_search(delta: float) -> void:
	var physics_frame := Engine.get_physics_frames()
	if original_secondary_search_last_physics_frame == physics_frame:
		return
	original_secondary_search_last_physics_frame = physics_frame
	if (
		not original_secondary_search_enabled
		or not is_alive
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
	):
		return
	if _original_recurring_evidence_round_index() > 0:
		original_secondary_search_elapsed = 0.0
		_advance_original_recurring_secondary_search_events()
		return
	original_secondary_search_elapsed += maxf(delta, 0.0)
	while (
		original_secondary_search_elapsed
		>= ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
	):
		original_secondary_search_elapsed -= (
			ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
		)
		_advance_original_secondary_search_once()


func _advance_original_recurring_secondary_search_events() -> bool:
	var round_index := _original_recurring_evidence_round_index()
	if (
		round_index <= 0
		or round_index <= original_recurring_secondary_last_round_index
		or not is_alive
	):
		return false
	original_recurring_secondary_last_round_index = round_index
	var events := _consume_original_recurring_actor_events(
		ORIGINAL_SECONDARY_SEARCH_CALL_SITES
	)
	if events.is_empty():
		# Native sub_45CE90 clears an arrived contact without drawing, then
		# resumes its gate on the following actor update.
		if (
			original_secondary_search_contact_state
			and movement_path_index >= movement_path.size()
		):
			original_secondary_search_contact_state = false
		return false
	var gate_seen := false
	var offset_values: Array[int] = []
	for event: Dictionary in events:
		var call_site_rva := int(event.get("call_site_rva", 0))
		var actual_value := int(event.get("actual_value", -1))
		if call_site_rva == 0x0005CEA6:
			gate_seen = true
			original_secondary_search_contact_state = false
			original_secondary_search_gate_serial += 1
			original_secondary_search_last_gate_value = actual_value
		elif call_site_rva in ORIGINAL_SECONDARY_SEARCH_CALL_SITES:
			offset_values.append(actual_value)
		else:
			original_recurring_actor_event_values_match = false
	if offset_values.is_empty():
		return gate_seen
	if not gate_seen or offset_values.size() != 4:
		original_recurring_actor_event_values_match = false
		return true
	original_secondary_search_last_goal = (
		AI_IDLE_RANDOM_RULES.secondary_search_point_from_values(
			offset_values,
			position,
			_original_secondary_search_world_bounds(),
		)
	)
	original_secondary_search_contact_state = true
	original_secondary_search_trigger_serial += 1
	original_secondary_search_last_candidate_runtime_index = -1
	if (
		original_crt_random_source.has_method(
			"first_original_secondary_search_candidate"
		)
	):
		var candidate_value: Variant = original_crt_random_source.call(
			"first_original_secondary_search_candidate",
			self,
			AI_IDLE_RANDOM_RULES.SECONDARY_SEARCH_CANDIDATE_RADIUS,
		)
		if (
			candidate_value is Node2D
			and is_instance_valid(candidate_value as Node2D)
		):
			original_secondary_search_last_candidate_runtime_index = int(
				(candidate_value as Node2D).get("original_runtime_index")
			)
	original_secondary_search_last_navigation_applied = (
		_issue_original_first_gameplay_path(
			original_secondary_search_last_goal
		)
	)
	return true


func _advance_original_secondary_search_once() -> bool:
	if (
		not original_secondary_search_enabled
		or not is_alive
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
	):
		return false
	var candidate: Node2D
	if not original_secondary_search_contact_state:
		var gate_value := next_original_crt_random_value(0x0005CEA6)
		if gate_value < 0:
			return false
		original_secondary_search_gate_serial += 1
		original_secondary_search_last_gate_value = gate_value
		if (
			gate_value % 2 > 0
			and original_crt_random_source.has_method(
				"first_original_secondary_search_candidate"
			)
		):
			var candidate_value: Variant = (
				original_crt_random_source.call(
					"first_original_secondary_search_candidate",
					self,
					AI_IDLE_RANDOM_RULES
					. SECONDARY_SEARCH_CANDIDATE_RADIUS,
				)
			)
			if (
				candidate_value is Node2D
				and is_instance_valid(candidate_value as Node2D)
			):
				candidate = candidate_value as Node2D
	var candidate_found := (
		candidate != null and is_instance_valid(candidate)
	)
	if original_secondary_search_contact_state or candidate_found:
		if original_secondary_search_contact_state:
			if movement_path_index < movement_path.size():
				_advance_original_pursuit_once()
				return true
			# sub_45CE90 clears contact on this tick and resumes candidate
			# gating only on the following actor update.
			original_secondary_search_contact_state = false
		if candidate_found:
			var values := next_original_crt_random_values([
				0x0005CF33,
				0x0005CF4A,
				0x0005CF61,
				0x0005CF78,
			])
			if values.size() != 4:
				return false
			original_secondary_search_last_goal = (
				AI_IDLE_RANDOM_RULES
				. secondary_search_point_from_values(
					values,
					position,
					_original_secondary_search_world_bounds(),
				)
			)
			original_secondary_search_contact_state = true
			original_secondary_search_trigger_serial += 1
			original_secondary_search_last_candidate_runtime_index = (
				int(candidate.get("original_runtime_index"))
			)
			original_secondary_search_last_navigation_applied = (
				_issue_original_first_gameplay_path(
					original_secondary_search_last_goal
				)
			)
		_advance_original_pursuit_once()
		return true
	# sub_45CE90 reaches sub_45D330 both before and after its route/local-search
	# fallback when neither an active contact nor a candidate is present.
	_advance_original_pursuit_once()
	_advance_original_pursuit_once()
	return true


func _original_secondary_search_world_bounds() -> Rect2:
	if (
		original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
		and original_crt_random_source.has_method(
			"original_secondary_search_world_bounds"
		)
	):
		var bounds_value: Variant = original_crt_random_source.call(
			"original_secondary_search_world_bounds"
		)
		if bounds_value is Rect2:
			return bounds_value as Rect2
	return Rect2(
		Vector2.ZERO,
		Vector2(1_000_000.0, 1_000_000.0),
	)


func _advance_original_pursuit(delta: float) -> void:
	var physics_frame := Engine.get_physics_frames()
	if original_pursuit_last_physics_frame == physics_frame:
		return
	original_pursuit_last_physics_frame = physics_frame
	if (
		original_pursuit_target_runtime_index < 0
		or original_pursuit_call_site_rva not in [
			0x0005D394,
			0x0005D47E,
		]
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
	):
		return
	original_pursuit_elapsed += maxf(delta, 0.0)
	while (
		original_pursuit_elapsed
		>= ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
	):
		original_pursuit_elapsed -= ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
		_advance_original_pursuit_once()


func _advance_original_recurring_pursuit_events() -> bool:
	var round_index := _original_recurring_evidence_round_index()
	if (
		round_index <= 0
		or round_index <= original_recurring_pursuit_last_round_index
		or not is_alive
	):
		return false
	original_recurring_pursuit_last_round_index = round_index
	var events := _original_recurring_actor_events([
		0x0005D394,
		0x0005D47E,
	])
	var handled := false
	for event: Dictionary in events:
		var call_site_rva := int(event.get("call_site_rva", 0))
		var actual_value := next_original_crt_random_value(call_site_rva)
		if actual_value < 0:
			continue
		original_recurring_actor_event_serial += 1
		original_recurring_actor_event_values_match = (
			original_recurring_actor_event_values_match
			and actual_value == int(event.get("value", -1))
		)
		var evidence_delay := int(event.get(
			"pursuit_delay_counter",
			-1,
		))
		if evidence_delay >= 0:
			original_pursuit_delay_counter = evidence_delay
		handled = (
			_apply_original_pursuit_random_value(
				actual_value,
				call_site_rva,
			)
			or handled
		)
	return handled


func _advance_original_pursuit_once() -> bool:
	# During the short, input-free evidence lane, exact conditional calls are
	# consumed by _advance_original_recurring_pursuit_events().  Unscheduled
	# semantic draws would shift the process-global stream.  Round zero is kept
	# available for isolated tests and pre-gameplay startup behavior.
	if _original_recurring_evidence_round_index() > 0:
		return true
	var target := _resolved_original_pursuit_target()
	if (
		target == null
		or not is_alive
	):
		return false
	# Native sub_45D330 reports a handled pursuit while +0x1FC is non-zero,
	# but performs no rand() call and leaves the active route untouched.
	if movement_path_index < movement_path.size():
		return true
	var random_value := next_original_crt_random_value(
		original_pursuit_call_site_rva
	)
	if random_value < 0:
		return false
	return _apply_original_pursuit_random_value(
		random_value,
		original_pursuit_call_site_rva,
	)


func _apply_original_pursuit_random_value(
	random_value: int,
	call_site_rva: int,
) -> bool:
	if random_value < 0 or not is_alive:
		return false
	original_pursuit_serial += 1
	if call_site_rva == 0x0005D394:
		original_pursuit_delay_counter += 1
		if original_pursuit_delay_counter <= random_value % 10:
			original_pursuit_last_navigation_applied = false
			return true
		original_pursuit_delay_counter = 0
	else:
		original_pursuit_delay_counter = 0
	var target := _resolved_original_pursuit_target()
	if target == null:
		original_pursuit_last_navigation_applied = false
		return true
	var destination := target.position
	var far_override := (
		call_site_rva == 0x0005D47E
		and random_value % 10 < 5
		and position.distance_to(destination) > 128.0
	)
	original_pursuit_last_command_variant = 1 if far_override else 0
	original_pursuit_last_navigation_applied = false
	if not _should_apply_original_pursuit_navigation():
		return true
	set_crawling(false)
	set_running(far_override or bool(target.get("is_running")))
	original_pursuit_last_navigation_applied = (
		_issue_original_first_gameplay_path(destination)
	)
	return true


func _resolved_original_pursuit_target() -> Node2D:
	if (
		original_pursuit_target == null
		or not is_instance_valid(original_pursuit_target)
	):
		return null
	if bool(original_pursuit_target.get("is_alive")):
		return original_pursuit_target
	var chained_value: Variant = original_pursuit_target.get(
		"original_pursuit_target"
	)
	if (
		chained_value is Node2D
		and is_instance_valid(chained_value as Node2D)
		and bool((chained_value as Node2D).get("is_alive"))
	):
		original_pursuit_target = chained_value as Node2D
		original_pursuit_target_runtime_index = int(
			original_pursuit_target.get("original_runtime_index")
		)
		original_pursuit_target_scene_index = int(
			original_pursuit_target.get("scene_index")
		)
		return original_pursuit_target
	original_pursuit_target = null
	original_pursuit_target_runtime_index = -1
	original_pursuit_target_scene_index = -1
	original_pursuit_call_site_rva = 0
	return null


func _should_apply_original_pursuit_navigation() -> bool:
	return true


func _advance_original_crt_observation_gate(delta: float) -> void:
	var physics_frame := Engine.get_physics_frames()
	if original_crt_last_physics_frame == physics_frame:
		return
	original_crt_last_physics_frame = physics_frame
	if (
		not original_crt_observation_gate_enabled
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
	):
		return
	original_crt_observation_gate_elapsed += maxf(delta, 0.0)
	while (
		original_crt_observation_gate_elapsed
		>= ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
	):
		original_crt_observation_gate_elapsed -= (
			ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
		)
		var random_value := next_original_crt_random_value(0x0005C81C)
		if random_value < 0:
			return
		apply_original_crt_observation_gate_value(random_value)


func apply_original_crt_observation_gate_value(
	random_value: int,
) -> bool:
	if not original_crt_observation_gate_enabled or random_value < 0:
		return false
	original_crt_observation_gate_passed = random_value % 2 > 0
	original_crt_observation_gate_serial += 1
	if (
		original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
		and original_crt_random_source.has_method(
			"advance_original_observation_for_actor"
		)
	):
		original_crt_random_source.call(
			"advance_original_observation_for_actor",
			self,
			original_crt_observation_gate_passed,
		)
	return true


func _advance_original_crt_primary_candidate_scan(delta: float) -> void:
	var physics_frame := Engine.get_physics_frames()
	if (
		original_crt_primary_candidate_last_physics_frame
		== physics_frame
	):
		return
	original_crt_primary_candidate_last_physics_frame = physics_frame
	if (
		not original_crt_primary_candidate_scan_enabled
		or original_crt_random_source == null
		or not is_instance_valid(original_crt_random_source)
	):
		return
	if _original_recurring_evidence_round_index() > 0:
		original_crt_primary_candidate_scan_elapsed = 0.0
		_advance_original_recurring_primary_search_events()
		return
	original_crt_primary_candidate_scan_elapsed += maxf(delta, 0.0)
	while (
		original_crt_primary_candidate_scan_elapsed
		>= ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
	):
		original_crt_primary_candidate_scan_elapsed -= (
			ORIGINAL_ACTOR_RANDOM_TICK_SECONDS
		)
		var random_value := next_original_crt_random_value(
			0x00055216
		)
		if random_value < 0:
			return
		apply_original_crt_primary_candidate_scan_value(
			random_value
		)


func _advance_original_recurring_primary_search_events() -> bool:
	var round_index := _original_recurring_evidence_round_index()
	if (
		round_index <= 0
		or round_index <= original_recurring_primary_last_round_index
		or not is_alive
	):
		return false
	original_recurring_primary_last_round_index = round_index
	var events := _consume_original_recurring_actor_events(
		ORIGINAL_PRIMARY_SEARCH_CALL_SITES
	)
	if events.is_empty():
		return false
	var gate_seen := false
	var origin := position
	var offset_values: Array[int] = []
	for event: Dictionary in events:
		var call_site_rva := int(event.get("call_site_rva", 0))
		var actual_value := int(event.get("actual_value", -1))
		if call_site_rva == 0x00055216:
			gate_seen = true
			var evidence_x := int(event.get("world_x", -1))
			var evidence_y := int(event.get("world_y", -1))
			if evidence_x >= 0 and evidence_y >= 0:
				origin = Vector2(evidence_x, evidence_y)
			apply_original_crt_primary_candidate_scan_value(actual_value)
		elif call_site_rva in ORIGINAL_PRIMARY_SEARCH_CALL_SITES:
			offset_values.append(actual_value)
		else:
			original_recurring_actor_event_values_match = false
	if offset_values.is_empty():
		return gate_seen
	if not gate_seen or offset_values.size() != 4:
		original_recurring_actor_event_values_match = false
		return true
	original_crt_primary_candidate_last_goal = (
		AI_IDLE_RANDOM_RULES.primary_search_point_from_values(
			offset_values,
			origin,
			_original_secondary_search_world_bounds(),
		)
	)
	original_crt_primary_candidate_last_navigation_applied = (
		_issue_original_first_gameplay_path(
			original_crt_primary_candidate_last_goal
		)
	)
	return true


func apply_original_crt_primary_candidate_scan_value(
	random_value: int,
) -> bool:
	if (
		not original_crt_primary_candidate_scan_enabled
		or random_value < 0
	):
		return false
	original_crt_primary_candidate_scan_passed = (
		random_value % 2 > 0
	)
	original_crt_primary_candidate_scan_serial += 1
	return true


func apply_original_first_gameplay_update_outcome(
	outcome: Dictionary,
	random_records: Array[Dictionary],
) -> bool:
	if (
		outcome.is_empty()
		or int(outcome.get("runtime_index", -1))
			!= original_runtime_index
		or int(outcome.get("scene_index", -1)) != scene_index
	):
		return false
	var state_value: Variant = outcome.get("post_update_state", {})
	var effects_value: Variant = outcome.get("semantic_effects", [])
	var expected_sites_value: Variant = outcome.get("call_site_rvas", [])
	if (
		not state_value is Dictionary
		or not effects_value is Array
		or not expected_sites_value is Array
		or random_records.size()
			!= (expected_sites_value as Array).size()
	):
		return false
	var expected_sites := expected_sites_value as Array
	var call_sites := PackedInt32Array()
	for record_index: int in range(random_records.size()):
		var record := random_records[record_index]
		var actual_site := str(
			record.get("call_site_rva", "0x0")
		).hex_to_int()
		var expected_site := str(expected_sites[record_index]).hex_to_int()
		if actual_site != expected_site:
			return false
		call_sites.append(actual_site)
	var effects: Array[String] = []
	for effect_value: Variant in effects_value as Array:
		var effect := str(effect_value)
		if effect.is_empty():
			return false
		effects.append(effect)
	var state := state_value as Dictionary
	original_first_gameplay_update_serial += 1
	original_first_gameplay_semantic_effects = effects
	original_first_gameplay_call_sites = call_sites
	original_first_gameplay_goal_kind = int(
		state.get("goal_kind", 0)
	)
	original_first_gameplay_command_variant = int(
		state.get("command_variant", 0)
	)
	original_first_gameplay_movement_path_state = int(
		state.get("movement_path_state", 0)
	)
	original_first_gameplay_movement_mode = int(
		state.get("movement_mode", 0)
	)
	original_first_gameplay_goal = Vector2(
		float(state.get("goal_x", 0)),
		float(state.get("goal_y", 0)),
	)
	original_first_gameplay_resolved_goal = Vector2(
		float(state.get("resolved_goal_x", 0)),
		float(state.get("resolved_goal_y", 0)),
	)
	original_first_gameplay_route_wait_limit = int(
		outcome.get("route_wait_limit", -1)
	)
	if effects.has("primary_candidate_scan"):
		var primary_candidate_value := -1
		for random_record: Dictionary in random_records:
			if (
				str(
					random_record.get("call_site_rva", "0x0")
				).hex_to_int()
				== 0x00055216
			):
				primary_candidate_value = int(
					random_record.get("value", -1)
				)
				break
		if primary_candidate_value < 0:
			return false
		original_crt_primary_candidate_scan_enabled = true
		original_crt_primary_candidate_scan_elapsed = 0.0
		original_crt_primary_candidate_scan_passed = false
		original_crt_primary_candidate_scan_serial = 0
		original_crt_primary_candidate_last_physics_frame = -1
		if not apply_original_crt_primary_candidate_scan_value(
			primary_candidate_value
	):
			return false
	if effects.has("route_wait_limit"):
		if (
			original_first_gameplay_route_wait_limit < 40
			or original_first_gameplay_route_wait_limit > 199
		):
			return false
		original_ai_idle_tick_counter = 0
		original_ai_idle_tick_limit = (
			original_first_gameplay_route_wait_limit
		)
		original_ai_idle_tick_elapsed = 0.0
		original_ai_idle_action_active = false
		original_ai_idle_frame_index = 0
		original_ai_idle_frame_elapsed = 0.0
		original_route_update_active = false
		original_ai_route_reset_serial += 1
	if (
		effects.has("secondary_candidate_scan")
		or effects.has("secondary_search_destination")
	):
		# Types 18 and 26 reach sub_45CE90 through a second native dispatch
		# path that is not described by the six-type direct switch. The exact
		# first-update record is the authoritative per-actor enablement proof.
		original_secondary_search_enabled = true
		for random_record: Dictionary in random_records:
			if (
				str(random_record.get("call_site_rva", "0x0"))
				.hex_to_int() == 0x0005CEA6
			):
				original_secondary_search_gate_serial = maxi(
					original_secondary_search_gate_serial,
					1,
				)
				original_secondary_search_last_gate_value = int(
					random_record.get("value", -1)
				)
				break
	var navigation_effect := ""
	var destination := Vector2.ZERO
	if effects.has("secondary_search_destination"):
		navigation_effect = "secondary_search_destination"
		destination = original_first_gameplay_goal
	elif effects.has("blocked_retry_destination"):
		navigation_effect = "blocked_retry_destination"
		destination = original_first_gameplay_resolved_goal
	elif effects.has("pursuit_command_snapshot"):
		navigation_effect = "pursuit_command_snapshot"
		destination = original_first_gameplay_goal
	original_first_gameplay_navigation_applied = false
	if (
		not navigation_effect.is_empty()
		and original_first_gameplay_goal_kind == 1
		and destination != Vector2.ZERO
		and _should_apply_original_first_gameplay_navigation(
			navigation_effect
		)
	):
		_apply_original_first_gameplay_movement_mode(
			original_first_gameplay_movement_mode
		)
		original_first_gameplay_navigation_applied = (
			_issue_original_first_gameplay_path(destination)
		)
	if navigation_effect == "secondary_search_destination":
		# The captured post-update command is the active +0x250 contact
		# produced by the same gate plus four destination draws.
		original_secondary_search_contact_state = true
		original_secondary_search_gate_serial = maxi(
			original_secondary_search_gate_serial,
			1,
		)
		original_secondary_search_trigger_serial = maxi(
			original_secondary_search_trigger_serial,
			1,
		)
		original_secondary_search_last_goal = destination
		original_secondary_search_last_navigation_applied = (
			original_first_gameplay_navigation_applied
		)
	return true


func _should_apply_original_first_gameplay_navigation(
	_effect: String,
) -> bool:
	return true


func _apply_original_first_gameplay_movement_mode(mode: int) -> void:
	if mode == 3:
		set_crawling(true)
		return
	set_crawling(false)
	set_running(mode == 2)


func _issue_original_first_gameplay_path(
	destination: Vector2,
) -> bool:
	if (
		dynamic_occupancy == null
		or scene_index < 0
		or not dynamic_registered
	):
		return false
	var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
		scene_index,
		position,
		destination,
	)
	var has_actionable_point := false
	for waypoint: Vector2 in path:
		if position.distance_squared_to(waypoint) > 1.0:
			has_actionable_point = true
			break
	if not has_actionable_point:
		return false
	issue_path(path)
	return true


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
	# Original enemy actors own the same +0x22C container as players, but
	# sub_456DF0 only consumes items for player runtime types. `infinite_ammo`
	# therefore means "do not consume on attack", not "has no inventory".
	if new_weapon_profile.is_empty():
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
	# Original enemy actors own the same +0x22C container as players, but
	# sub_456DF0 only consumes items for player runtime types. `infinite_ammo`
	# therefore means "do not consume on attack", not "has no inventory".
	if new_weapon_profile.is_empty():
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
			# sub_459290/sub_459370 consumes one rand() before it raises the
			# actor-replacement flag.  The resulting 20..59 limit belongs to the
			# old actor and is discarded when sub_450200 installs the new one, but
			# the shared-stream draw and its type-specific call site are observable.
			if (
				original_crt_random_source != null
				and is_instance_valid(original_crt_random_source)
			):
				var completion_call_site := (
					0x000593E1
					if runtime_actor_type
						== LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE
					else 0x00059343
				)
				var completion_value := next_original_crt_random_value(
					completion_call_site
				)
				if completion_value < 0:
					disguise_transition_tick_counter = (
						LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT
					)
					return false
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
	return expose_original_cover()


func expose_original_cover() -> bool:
	if not LEGACY_DISGUISE_RULES.has_cover_recovery(runtime_actor_type):
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
	if not LEGACY_DISGUISE_RULES.has_cover_recovery(runtime_actor_type):
		disguise_recovery_tick_counter = 0
		disguise_recovery_tick_elapsed = 0.0
		return false
	if (
		faction_id == LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
		and burial_exposes_actor
		and LEGACY_DISGUISE_RULES.burial_can_break_cover(runtime_actor_type)
		and observer_has_visibility
	):
		return expose_original_cover()
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


func queue_original_acknowledgement() -> void:
	original_pending_acknowledgement_count += 1


func _consume_original_pending_acknowledgement() -> bool:
	if original_pending_acknowledgement_count <= 0:
		return false
	original_pending_acknowledgement_count -= 1
	original_acknowledgement_serial += 1
	original_command_audio_requested.emit(self, "acknowledge")
	return true


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


func apply_special_control(source: Node2D = null) -> bool:
	if not is_alive:
		return false
	special_control_lock_count += 1
	special_control_source = source
	if special_control_lock_count == 1:
		# Target +656 suppresses an ordinary idle/movement command but does not
		# erase a combat transition already in progress.
		if combat_action == CombatAction.NONE and combat_target == null:
			cancel_path()
			_face_special_control_source()
		queue_redraw()
	return true


func apply_original_alert_source_reaction(random_value: int) -> bool:
	if random_value < 0:
		return false
	# sub_45DDA0 writes +0x24C/+0x25C/+0x290 on the source actor after
	# every accepted recipient, then stores rand()%40+40 at +0x248.
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_limit = (
		random_value
		% AI_IDLE_RANDOM_RULES.REACTION_RANDOM_SPAN
		+ AI_IDLE_RANDOM_RULES.REACTION_MINIMUM_LIMIT
	)
	original_ai_idle_tick_elapsed = 0.0
	special_control_lock_count = 0
	special_control_source = null
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
		queue_redraw()
	return true


func is_special_controlled() -> bool:
	return special_control_lock_count > 0


func _release_special_control_for_combat() -> bool:
	if special_control_lock_count <= 0:
		return false
	special_control_lock_count = 0
	special_control_source = null
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
	var attack_type := int(weapon_profile.get("attack_type", 0))
	if (
		allow_non_hostile
		and LEGACY_COMBAT_RULES.coordinate_projectile_count(attack_type) > 0
	):
		# Original forced targeting commits a coordinate projectile even when
		# L2 blocks the eventual hit or no attack-range approach is reachable.
		# The projectile world still performs its normal L2 collision, while
		# attack_started creates the authentic gunshot alert.  m002 depends on
		# this behavior to lure scene 870 toward Old Zhao's isolated yard.
		return true
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
	_release_special_control_for_combat()
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
	# Native sub_457B40 has no independent recovery counter. The authored SPR
	# sequence itself owns the attack cadence and returns idle on final-frame
	# entry; keep this compatibility field normalized to zero.
	attack_cooldown_remaining = 0.0
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
		pending_hit_target = null
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
	_advance_original_crt_actor_random_tick(safe_delta)
	_advance_original_ai_shared_counter(safe_delta)
	_advance_original_recurring_blocked_retry_events()
	_consume_original_pending_acknowledgement()
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
	if is_special_controlled():
		_face_special_control_source()
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
		# Scalar/fallback actors validate their complete frame displacement
		# only after calculating it. A rejected move has not been committed to
		# DynamicOccupancyGrid, so keep the Node2D and path cursor at their last
		# accepted state. Advancing the visual position here used to let
		# fallback actors drift through one another while the occupancy grid
		# correctly retained their old cells.
		next_position = position
		next_path_index = movement_path_index
	if movement_blocked:
		# Earlier fixed substeps may already have been accepted by the runtime
		# occupancy grid. Keep the node and path cursor synchronized with that
		# last accepted position before replanning.
		position = next_position
		movement_path_index = next_path_index
		blocked_elapsed += safe_delta
		if blocked_elapsed >= maxf(blocked_replan_seconds, 0.05):
			blocked_elapsed = 0.0
			# sub_45D330 pursuit commands retain the commanded target
			# coordinate while a followed actor occupies or clears the next
			# cell. Re-running A* against that same coordinate every retry
			# interval is both behaviorally wrong (the original command stays
			# pending) and produces a visible hitch for the two-cell pushcart
			# follower in m005. Keep retrying the already proven route; the
			# next original pursuit command is issued only after this path
			# actually completes.
			if not original_pursuit_last_navigation_applied:
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
			_update_sprite_depth()
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
		_update_sprite_depth()
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
				minimum_actor_separation,
			)
		)
	if use_soft_dynamic_occupancy:
		return bool(
			dynamic_occupancy.call(
				"try_relocate",
				scene_index,
				new_world_position,
				true,
				minimum_actor_separation,
			)
		)
	return bool(
		dynamic_occupancy.call(
			"try_relocate",
			scene_index,
			new_world_position,
			false,
			minimum_actor_separation,
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
			# Stable runtime-evidence cache values are shared read-only. Only a
			# redirected/partial endpoint needs an independent mutable copy.
			soft_path = soft_path.duplicate()
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
	_request_continuous_animation_audio(_active_action_group(groups))
	if action == CombatAction.ATTACK and _action_frame_count(groups) == 1:
		_resolve_pending_hit()
		action_finished = true


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
	_request_continuous_animation_audio(group)
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
		var previous_frame_index := action_frame_index
		action_frame_index += 1
		_apply_action_frame(groups)
		_request_transition_animation_audio(
			group,
			previous_frame_index,
			action_frame_index,
		)
		if combat_action == CombatAction.ATTACK and action_frame_index == frame_count - 1:
			_resolve_pending_hit()
			# sub_41D6A0 detects entry to the final frame and sub_457B40
			# commits the hit, clears the attack and restores idle in this same
			# actor update. Do not hold the final frame or add a cooldown.
			action_finished = true
			combat_action = CombatAction.NONE
			pending_hit_target = null
			_sync_equipped_weapon_after_consumption()
			apply_idle_frame()
			return


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
	_apply_row_slice_visual(group)
	queue_redraw()


func _action_frame_count(groups: Array[Dictionary]) -> int:
	if groups.size() < 8:
		return 0
	var group := groups[clampi(animation_group_index, 0, 7)]
	if group.is_empty():
		return 0
	return (group.get("frames", []) as Array[Texture2D]).size()


func _active_action_group(groups: Array[Dictionary]) -> Dictionary:
	if groups.size() < 8:
		return {}
	return groups[clampi(animation_group_index, 0, 7)]


func has_authored_attack_animation_sound() -> bool:
	return (
		LEGACY_ANIMATION_AUDIO_RULES.sound_gfl_index(
			_active_action_group(attack_groups)
		) > 0
	)


func has_authored_death_animation_sound() -> bool:
	return (
		LEGACY_ANIMATION_AUDIO_RULES.sound_gfl_index(
			_active_action_group(death_groups)
		) > 0
	)


func authored_animation_sound_gfl_indices() -> Array[int]:
	var result: Array[int] = []
	var group_sets: Array = [
		run_groups,
		walk_groups,
		crawl_groups,
		idle_groups,
		standing_idle_groups,
		stand_action_groups,
		attack_groups,
		death_groups,
	]
	for stored_groups: Variant in attack_groups_by_action.values():
		if stored_groups is Array:
			group_sets.append(stored_groups)
	for groups_value: Variant in group_sets:
		if not groups_value is Array:
			continue
		for group_value: Variant in groups_value as Array:
			if not group_value is Dictionary:
				continue
			var gfl_index: int = (
				LEGACY_ANIMATION_AUDIO_RULES.sound_gfl_index(
					group_value as Dictionary
				)
			)
			if gfl_index > 0 and not result.has(gfl_index):
				result.append(gfl_index)
	result.sort()
	return result


func _request_continuous_animation_audio(group: Dictionary) -> bool:
	if not LEGACY_ANIMATION_AUDIO_RULES.requests_continuously(group):
		return false
	original_animation_audio_requested.emit(
		self,
		LEGACY_ANIMATION_AUDIO_RULES.sound_gfl_index(group),
		true,
	)
	return true


func _request_transition_animation_audio(
	group: Dictionary,
	previous_frame_index: int,
	current_frame_index: int,
) -> bool:
	if not LEGACY_ANIMATION_AUDIO_RULES.transition_requests_sound(
		group,
		previous_frame_index,
		current_frame_index,
	):
		return false
	original_animation_audio_requested.emit(
		self,
		LEGACY_ANIMATION_AUDIO_RULES.sound_gfl_index(group),
		false,
	)
	return true


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
	special_control_lock_count = 0
	special_control_source = null
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


func set_original_route_update_active(value: bool) -> void:
	original_route_update_active = value


func _advance_original_ai_shared_counter(delta: float) -> void:
	var physics_frame := Engine.get_physics_frames()
	if original_ai_shared_counter_last_physics_frame == physics_frame:
		return
	original_ai_shared_counter_last_physics_frame = physics_frame
	var current_world_position := position
	var stationary := current_world_position.is_equal_approx(
		original_ai_previous_world_position
	)
	original_ai_previous_world_position = current_world_position
	if (
		not is_alive
		or (
			original_crt_level_id.is_empty()
			and original_crt_initialization_profile.is_empty()
		)
	):
		return
	var evidence_round_index := (
		_original_recurring_evidence_round_index()
	)
	var scheduled_by_site: Dictionary = {}
	if (
		evidence_round_index > 0
		and evidence_round_index
			> original_recurring_shared_last_round_index
	):
		original_recurring_shared_last_round_index = evidence_round_index
		for event: Dictionary in _original_recurring_actor_events([
			0x00056105,
			0x0005614F,
			0x00058946,
		]):
			scheduled_by_site[int(event.get("call_site_rva", 0))] = (
				event
			)
	original_ai_idle_tick_elapsed += maxf(delta, 0.0)
	while (
		original_ai_idle_tick_elapsed
		>= ORIGINAL_AI_IDLE_TICK_SECONDS
	):
		original_ai_idle_tick_elapsed -= ORIGINAL_AI_IDLE_TICK_SECONDS
		if stationary or scheduled_by_site.has(0x00056105):
			original_ai_idle_tick_counter += 1
			if scheduled_by_site.has(0x00056105):
				_apply_original_recurring_shared_event(
					scheduled_by_site[0x00056105] as Dictionary,
					0x00056105,
				)
				scheduled_by_site.erase(0x00056105)
			elif (
				evidence_round_index <= 0
				and original_ai_idle_tick_counter
				>= original_ai_idle_tick_limit
			):
				var stationary_limit := _next_original_ai_wait_limit(
					0x00056105
				)
				if stationary_limit >= 0:
					original_ai_idle_tick_counter = 0
					original_ai_idle_tick_limit = stationary_limit
					original_ai_stationary_reset_serial += 1
		if scheduled_by_site.has(0x0005614F):
			_apply_original_recurring_shared_event(
				scheduled_by_site[0x0005614F] as Dictionary,
				0x0005614F,
			)
			scheduled_by_site.erase(0x0005614F)
		if (
			original_route_update_active
			or scheduled_by_site.has(0x00058946)
		):
			original_ai_idle_tick_counter += 1
			if scheduled_by_site.has(0x00058946):
				_apply_original_recurring_shared_event(
					scheduled_by_site[0x00058946] as Dictionary,
					0x00058946,
				)
				scheduled_by_site.erase(0x00058946)
			elif (
				evidence_round_index <= 0
				and original_ai_idle_tick_counter
				>= original_ai_idle_tick_limit
			):
				var route_limit := _next_original_ai_wait_limit(
					0x00058946
				)
				if route_limit >= 0:
					original_ai_idle_tick_counter = 0
					original_ai_idle_tick_limit = route_limit
					original_route_update_active = false
					original_ai_route_reset_serial += 1
					_on_original_route_wait_completed()


func _apply_original_recurring_shared_event(
	event: Dictionary,
	call_site_rva: int,
) -> bool:
	var evidence_counter := int(event.get(
		"shared_counter_before",
		-1,
	))
	var evidence_limit := int(event.get("shared_limit_before", -1))
	if evidence_counter >= 0 and evidence_limit >= 0:
		original_ai_idle_tick_counter = evidence_counter
		original_ai_idle_tick_limit = evidence_limit
	var evidence_route_active := int(event.get(
		"route_update_active",
		-1,
	))
	if evidence_route_active >= 0:
		original_route_update_active = evidence_route_active != 0
	var actual_value := next_original_crt_random_value(call_site_rva)
	if actual_value < 0:
		return false
	original_recurring_actor_event_serial += 1
	original_recurring_actor_event_values_match = (
		original_recurring_actor_event_values_match
		and actual_value == int(event.get("value", -1))
	)
	original_ai_idle_tick_counter = 0
	original_ai_idle_tick_elapsed = 0.0
	if call_site_rva == 0x0005614F:
		original_ai_idle_tick_limit = actual_value % 60
		return true
	original_ai_idle_tick_limit = (
		actual_value
		% AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
		+ AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT
	)
	if call_site_rva == 0x00058946:
		original_route_update_active = false
		original_ai_route_reset_serial += 1
		_on_original_route_wait_completed()
	else:
		original_ai_stationary_reset_serial += 1
	return true


func _next_original_ai_wait_limit(call_site_rva: int) -> int:
	var random_value := next_original_crt_random_value(call_site_rva)
	if random_value >= 0:
		return (
			random_value
			% AI_IDLE_RANDOM_RULES.SEARCH_WAIT_RANDOM_SPAN
			+ AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT
		)
	var sampled: Dictionary = (
		AI_IDLE_RANDOM_RULES.initial_search_wait_from_state(
			original_ai_idle_random_state
		)
	)
	original_ai_idle_random_state = int(
		sampled.get(
			"state",
			original_ai_idle_random_state,
		)
	)
	return int(
		sampled.get(
			"limit",
			AI_IDLE_RANDOM_RULES.SEARCH_WAIT_MINIMUM_LIMIT,
		)
	)


func _on_original_route_wait_completed() -> void:
	pass


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
	_request_continuous_animation_audio(group)
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
	_apply_row_slice_visual(group)
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
	_request_continuous_animation_audio(group)
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
	_apply_row_slice_visual(group)


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
	_request_continuous_animation_audio(group)
	sprite_texture = frames[0]
	sprite_anchor = group["anchor"] as Vector2
	_apply_dynamic_sprite_footprint(group)
	_apply_row_slice_visual(group)
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


func patrol_movement_footprint_profiles() -> Array:
	var profiles: Array = []
	if (
		dynamic_occupancy == null
		or movement_groups.is_empty()
	):
		return profiles
	var source_navigation: Variant = dynamic_occupancy.get("navigation")
	if source_navigation == null:
		return profiles
	var cell_size_value: Variant = source_navigation.get("cell_size")
	if not cell_size_value is Vector2i:
		return profiles
	var profile_keys: Dictionary = {}
	for group: Dictionary in movement_groups:
		if (
			group.is_empty()
			or not group.has("lookup_dimensions")
			or not group.has("movement_lookup")
		):
			continue
		var movement_offsets: Array[Vector2i] = (
			SPR_ANIMATION_RULES.lookup_footprint_offsets(
				group,
				"movement_lookup",
				cell_size_value as Vector2i,
			)
		)
		var profile_key := str(movement_offsets)
		if profile_keys.has(profile_key):
			continue
		profile_keys[profile_key] = true
		profiles.append(movement_offsets)
	return profiles


func _apply_row_slice_visual(group: Dictionary) -> bool:
	var row_lookup: Variant = group.get("draw_order_row_lookup", [])
	if sprite_texture == null or not row_lookup is Array or (row_lookup as Array).is_empty():
		sprite_drawn_by_row_slices = false
		uniform_row_depth_enabled = false
		uniform_row_depth_offset = 0.0
		if row_slice_renderer != null and is_instance_valid(row_slice_renderer):
			row_slice_renderer.call("clear_visual")
		_update_sprite_depth()
		return false
	var normalized_rows := _normalized_draw_order_rows(row_lookup)
	var expected_columns := ceili(
		sprite_texture.get_width()
		/ float(LEGACY_ROW_SLICE_SPRITE_SCRIPT.COLUMN_WIDTH)
	)
	if normalized_rows.size() != expected_columns:
		sprite_drawn_by_row_slices = false
		uniform_row_depth_enabled = false
		uniform_row_depth_offset = 0.0
		if row_slice_renderer != null and is_instance_valid(row_slice_renderer):
			row_slice_renderer.call("clear_visual")
		_update_sprite_depth()
		return false
	if _draw_order_rows_are_uniform(normalized_rows):
		sprite_drawn_by_row_slices = false
		uniform_row_depth_enabled = true
		uniform_row_depth_offset = (
			-sprite_anchor.y + float(normalized_rows[0])
		)
		if row_slice_renderer != null and is_instance_valid(row_slice_renderer):
			row_slice_renderer.call("clear_visual")
		_update_sprite_depth()
		return false
	uniform_row_depth_enabled = false
	uniform_row_depth_offset = 0.0
	_update_sprite_depth()
	if row_slice_renderer == null or not is_instance_valid(row_slice_renderer):
		row_slice_renderer = LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
		row_slice_renderer.name = "OriginalRowSlices"
		add_child(row_slice_renderer)
	sprite_drawn_by_row_slices = bool(
		row_slice_renderer.call(
			"configure",
			sprite_texture,
			sprite_anchor,
			position.y,
			normalized_rows,
			1,
			true,
		)
	)
	return sprite_drawn_by_row_slices


func _update_sprite_depth() -> void:
	var depth_reference_y := position.y
	if uniform_row_depth_enabled:
		depth_reference_y += uniform_row_depth_offset
	z_index = WORLD_DEPTH.normal_z(depth_reference_y, 1)


static func _normalized_draw_order_rows(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for raw_row: Variant in value as Array:
		if not raw_row is int and not raw_row is float:
			return []
		var row_value := float(raw_row)
		if not is_finite(row_value) or row_value != float(int(row_value)):
			return []
		result.append(int(row_value))
	return result


static func _draw_order_rows_are_uniform(rows: Array[int]) -> bool:
	if rows.is_empty():
		return false
	var first := rows[0]
	for row_index: int in range(1, rows.size()):
		if rows[row_index] != first:
			return false
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
	if sprite_texture != null and not sprite_drawn_by_row_slices:
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
