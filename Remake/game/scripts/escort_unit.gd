class_name EscortUnit
extends "res://scripts/squad_unit.gd"

const IMPORTED_SPRITE_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const LEGACY_ESCORT_RULES: Script = preload(
	"res://scripts/legacy_escort_rules.gd"
)
# These distances are retained only for synthetic fixtures and actors for
# which no original runtime-type rule has been recovered.
const FOLLOW_REPATH_SECONDS := 0.50
const FOLLOW_START_DISTANCE := 88.0
const FOLLOW_STOP_DISTANCE := 52.0

signal rescued(unit: Node2D, rescuer: Node2D)

var rescued_state := false
var follow_target: Node2D
var follow_repath_elapsed := FOLLOW_REPATH_SECONDS
var original_rescue_rule: Dictionary = {}


func configure_escort(
	entity: Dictionary,
	texture: Texture2D,
	new_movement_groups: Array[Dictionary],
	new_idle_groups: Array[Dictionary],
	new_death_groups: Array[Dictionary],
	new_dynamic_occupancy: RefCounted,
	new_attack_groups: Array[Dictionary] = [],
) -> void:
	configure(
		str(entity.get("display_name", "escort")),
		Color("d3c27a"),
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
	move_speed = 118.0
	var weapon_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
		int(entity.get("default_attack_type", 0))
	)
	configure_combat(
		int(entity.get("faction_id", entity.get("team_id", 2))),
		maxi(int(entity.get("current_hit_points", 8)), 1),
		weapon_profile,
		new_attack_groups,
		new_death_groups,
		false,
	)
	var direction_index := original_native_initial_facing_direction(
		int(entity.get("direction_index", 1))
	)
	set_animation_group(
		IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(direction_index)
	)
	apply_idle_frame()
	rescued_state = false
	follow_target = null
	follow_repath_elapsed = FOLLOW_REPATH_SECONDS
	original_rescue_rule.clear()
	queue_redraw()


func configure_original_rescue_rule(rule: Dictionary) -> void:
	original_rescue_rule = rule.duplicate(true)


func has_source_backed_rescue_rule() -> bool:
	return not original_rescue_rule.is_empty()


func is_player_commandable() -> bool:
	return (
		is_alive
		and rescued_state
		and bool(original_rescue_rule.get("becomes_commandable", false))
	)


func can_be_rescued_by(rescuer: Node2D) -> bool:
	if not has_source_backed_rescue_rule():
		return _target_is_alive(rescuer)
	return (
		LEGACY_ESCORT_RULES.rescuer_is_eligible(
			original_rescue_rule,
			rescuer,
		)
		and LEGACY_ESCORT_RULES.is_within_rescue_range(
			original_rescue_rule,
			position,
			rescuer.position,
		)
	)


func rescue(rescuer: Node2D) -> bool:
	if rescued_state or not is_alive or not can_be_rescued_by(rescuer):
		return false
	rescued_state = true
	if (
		original_rescue_rule.is_empty()
		or bool(original_rescue_rule.get("changes_faction", false))
	):
		faction_id = 3
	if (
		original_rescue_rule.is_empty()
		or bool(original_rescue_rule.get("follows_target", false))
	):
		set_follow_target(rescuer)
	else:
		follow_target = null
	follow_repath_elapsed = FOLLOW_REPATH_SECONDS
	modern_player_combat_rules_enabled = is_player_commandable()
	rescued.emit(self, rescuer)
	queue_redraw()
	return true


func set_follow_target(target: Node2D) -> void:
	if not _target_is_alive(target):
		return
	if (
		has_source_backed_rescue_rule()
		and not bool(original_rescue_rule.get("follows_target", false))
	):
		follow_target = null
		return
	follow_target = target
	if (
		has_source_backed_rescue_rule()
		and bool(original_rescue_rule.get("follows_target", false))
	):
		_bind_dynamic_original_pursuit(target)


func restore_rescued_state(
	new_rescued_state: bool,
	target: Node2D,
	new_follow_repath_elapsed: float = FOLLOW_REPATH_SECONDS,
) -> void:
	rescued_state = new_rescued_state and is_alive
	follow_target = null
	follow_repath_elapsed = maxf(new_follow_repath_elapsed, 0.0)
	if rescued_state and _target_is_alive(target):
		set_follow_target(target)
	queue_redraw()


func _bind_dynamic_original_pursuit(target: Node2D) -> bool:
	var target_runtime_index := int(target.get("original_runtime_index"))
	if target_runtime_index < 0:
		return false
	original_pursuit_target_runtime_index = target_runtime_index
	original_pursuit_target = target
	original_pursuit_call_site_rva = (
		LEGACY_ESCORT_RULES.ORIGINAL_PURSUIT_CALL_SITE_RVA
	)
	original_pursuit_delay_counter = 0
	original_pursuit_elapsed = 0.0
	original_pursuit_serial = 0
	original_pursuit_last_physics_frame = -1
	original_pursuit_last_command_variant = 0
	original_pursuit_last_navigation_applied = false
	return true


func _uses_source_backed_pursuit() -> bool:
	return (
		has_source_backed_rescue_rule()
		and bool(original_rescue_rule.get("follows_target", false))
		and original_pursuit_target_runtime_index >= 0
		and original_pursuit_call_site_rva
			== LEGACY_ESCORT_RULES.ORIGINAL_PURSUIT_CALL_SITE_RVA
		and original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
	)


func _physics_process(delta: float) -> void:
	simulate_tick(delta)
	_notify_spatial_bucket_crossing()


func simulate_tick(delta: float, delta_is_fixed: bool = false) -> void:
	var safe_delta := delta if delta_is_fixed else resolved_simulation_delta(delta)
	# Source-backed followers are advanced by SquadUnit's exact sub_45D330
	# pursuit scheduler. The generic distance-band follower remains only as a
	# compatibility fallback for synthetic fixtures without a captured runtime
	# index/random stream.
	if (
		is_alive
		and rescued_state
		and _target_is_alive(follow_target)
		and not _uses_source_backed_pursuit()
		and (
			original_rescue_rule.is_empty()
			or bool(original_rescue_rule.get("follows_target", false))
		)
	):
		follow_repath_elapsed += safe_delta
		var distance := position.distance_to(follow_target.position)
		if distance <= FOLLOW_STOP_DISTANCE:
			if movement_path_index < movement_path.size():
				cancel_path()
		elif (
			distance >= FOLLOW_START_DISTANCE
			and follow_repath_elapsed >= FOLLOW_REPATH_SECONDS
			and movement_path_index >= movement_path.size()
		):
			follow_repath_elapsed = 0.0
			if dynamic_occupancy != null and dynamic_registered:
				var path: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
					scene_index, position, follow_target.position
				)
				if not path.is_empty():
					issue_path(path)
	super.simulate_tick(safe_delta, true)


func _draw() -> void:
	super._draw()
	if not rescued_state and is_alive:
		draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 32, Color(0.98, 0.82, 0.22), 2.5)
