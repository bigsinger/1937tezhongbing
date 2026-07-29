class_name LegacyAiControlEffect
extends Node

const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")

signal applied(effect: Node, target: Node2D)
signal released(effect: Node, target: Node2D)

enum State { INACTIVE, ACTIVE, RELEASED }

var state := State.INACTIVE
var source_actor: Node2D
var target_actor: Node2D
var elapsed_world_ticks := 0
var original_target_flag_offset := 0
var source_anchor_position := Vector2.ZERO
var release_reason := ""
var evidence_profile: Dictionary = {}


func configure(profile: Dictionary, new_source: Node2D, new_target: Node2D) -> bool:
	if (
		not SPECIAL_PROFILES.is_valid_profile(profile)
		or int(profile.get("attack_type", 0)) != SPECIAL_PROFILES.AI_CONTROL_ATTACK_TYPE
		or new_target == null
		or not is_instance_valid(new_target)
		or not new_target.has_method("apply_special_control")
		or not bool(new_target.call("apply_special_control", new_source))
	):
		return false
	evidence_profile = profile.duplicate(true)
	source_actor = new_source
	target_actor = new_target
	elapsed_world_ticks = 0
	original_target_flag_offset = int(profile.get("original_target_flag_offset", 0))
	source_anchor_position = (
		source_actor.position if is_instance_valid(source_actor) else Vector2.ZERO
	)
	release_reason = ""
	state = State.ACTIVE
	applied.emit(self, target_actor)
	return true


func is_active() -> bool:
	return state == State.ACTIVE


func refresh(new_source: Node2D = null) -> bool:
	if state != State.ACTIVE or not is_instance_valid(target_actor):
		return false
	if new_source != null:
		source_actor = new_source
		source_anchor_position = source_actor.position
		if target_actor.has_method("refresh_special_control_source"):
			target_actor.call("refresh_special_control_source", source_actor)
	elapsed_world_ticks = 0
	release_reason = ""
	return true


func advance_world_ticks(ticks: int = 1) -> void:
	if state != State.ACTIVE:
		return
	if not _target_is_alive():
		release("target_inactive")
		return
	if not _target_still_holds_attention():
		release("target_combat_transition")
		return
	if not _source_is_alive():
		release("source_inactive")
		return
	if _source_started_moving():
		release("source_movement")
		return
	elapsed_world_ticks += maxi(ticks, 0)


func release(reason: String = "explicit_release") -> bool:
	if state != State.ACTIVE:
		return false
	state = State.RELEASED
	release_reason = reason
	var released_target := target_actor
	if (
		is_instance_valid(released_target)
		and released_target.has_method("release_special_control")
		and (
			not released_target.has_method("is_special_controlled")
			or bool(released_target.call("is_special_controlled"))
		)
	):
		released_target.call("release_special_control", source_actor)
	released.emit(self, released_target)
	if is_inside_tree():
		queue_free()
	return true


func snapshot() -> Dictionary:
	return {
		"schema_version": 2,
		"attack_type": SPECIAL_PROFILES.AI_CONTROL_ATTACK_TYPE,
		"state": state,
		"source_scene_index": int(source_actor.get("scene_index")) if is_instance_valid(source_actor) else -1,
		"source_display_name": str(source_actor.get("display_name")) if is_instance_valid(source_actor) else "",
		"target_scene_index": int(target_actor.get("scene_index")) if is_instance_valid(target_actor) else -1,
		"target_display_name": str(target_actor.get("display_name")) if is_instance_valid(target_actor) else "",
		"elapsed_world_ticks": elapsed_world_ticks,
		"source_anchor_x": source_anchor_position.x,
		"source_anchor_y": source_anchor_position.y,
	}


func restore_runtime_state(snapshot_value: Dictionary) -> bool:
	if state != State.ACTIVE:
		return false
	var schema_version := int(snapshot_value.get("schema_version", 1))
	if schema_version < 1 or schema_version > 2:
		return false
	elapsed_world_ticks = maxi(int(snapshot_value.get("elapsed_world_ticks", 0)), 0)
	if schema_version >= 2:
		source_anchor_position = Vector2(
			float(snapshot_value.get("source_anchor_x", source_anchor_position.x)),
			float(snapshot_value.get("source_anchor_y", source_anchor_position.y)),
		)
	return true


func restore_elapsed_ticks(restored_ticks: int) -> bool:
	# Schema-1 compatibility: old remake saves stored a synthetic timeout.
	# The timeout is deliberately ignored now that the original release rules
	# are recovered, while the diagnostic elapsed counter remains readable.
	return restore_runtime_state({
		"schema_version": 1,
		"elapsed_world_ticks": restored_ticks,
	})


func _physics_process(_delta: float) -> void:
	advance_world_ticks(1)


func _exit_tree() -> void:
	# Level replacement may free the effect before an original release edge.
	# Always release the target-side lock, but do not emit a second lifecycle
	# signal for an effect that already completed through release().
	if state == State.ACTIVE:
		state = State.RELEASED
		if is_instance_valid(target_actor) and target_actor.has_method("release_special_control"):
			target_actor.call("release_special_control", source_actor)


func _target_is_alive() -> bool:
	return (
		target_actor != null
		and is_instance_valid(target_actor)
		and target_actor.has_method("is_combat_alive")
		and bool(target_actor.call("is_combat_alive"))
	)


func _target_still_holds_attention() -> bool:
	return (
		is_instance_valid(target_actor)
		and target_actor.has_method("is_special_controlled")
		and bool(target_actor.call("is_special_controlled"))
	)


func _source_is_alive() -> bool:
	if source_actor == null or not is_instance_valid(source_actor):
		return false
	return (
		not source_actor.has_method("is_combat_alive")
		or bool(source_actor.call("is_combat_alive"))
	)


func _source_started_moving() -> bool:
	if not is_instance_valid(source_actor):
		return true
	# The executable clears target +656 when the dedicated source actor's
	# current and movement-target coordinate pairs diverge. Checking both an
	# active path and anchor displacement preserves that edge even when a very
	# short path starts and finishes between two effect ticks.
	if not source_actor.position.is_equal_approx(source_anchor_position):
		return true
	var path_value: Variant = source_actor.get("movement_path")
	var path_index_value: Variant = source_actor.get("movement_path_index")
	if (
		path_value is PackedVector2Array
		and path_index_value is int
		and int(path_index_value) < (path_value as PackedVector2Array).size()
	):
		return true
	var target_position_value: Variant = source_actor.get("target_position")
	return (
		target_position_value is Vector2
		and not (target_position_value as Vector2).is_equal_approx(source_actor.position)
	)
