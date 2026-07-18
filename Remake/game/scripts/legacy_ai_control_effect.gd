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
var duration_world_ticks := 0
var original_target_flag_offset := 0
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
	duration_world_ticks = maxi(int(profile.get("duration_world_ticks", 0)), 1)
	original_target_flag_offset = int(profile.get("original_target_flag_offset", 0))
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
	elapsed_world_ticks = 0
	return true


func advance_world_ticks(ticks: int = 1) -> void:
	if state != State.ACTIVE:
		return
	if not _target_is_alive():
		release()
		return
	elapsed_world_ticks += maxi(ticks, 0)
	if elapsed_world_ticks >= duration_world_ticks:
		release()


func release() -> bool:
	if state != State.ACTIVE:
		return false
	state = State.RELEASED
	var released_target := target_actor
	if is_instance_valid(released_target) and released_target.has_method("release_special_control"):
		released_target.call("release_special_control", source_actor)
	released.emit(self, released_target)
	if is_inside_tree():
		queue_free()
	return true


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"attack_type": SPECIAL_PROFILES.AI_CONTROL_ATTACK_TYPE,
		"state": state,
		"source_scene_index": int(source_actor.get("scene_index")) if is_instance_valid(source_actor) else -1,
		"source_display_name": str(source_actor.get("display_name")) if is_instance_valid(source_actor) else "",
		"target_scene_index": int(target_actor.get("scene_index")) if is_instance_valid(target_actor) else -1,
		"target_display_name": str(target_actor.get("display_name")) if is_instance_valid(target_actor) else "",
		"elapsed_world_ticks": elapsed_world_ticks,
		"duration_world_ticks": duration_world_ticks,
	}


func restore_elapsed_ticks(restored_ticks: int) -> bool:
	if state != State.ACTIVE:
		return false
	elapsed_world_ticks = clampi(restored_ticks, 0, duration_world_ticks - 1)
	return true


func _physics_process(_delta: float) -> void:
	advance_world_ticks(1)


func _exit_tree() -> void:
	# Level replacement may free the effect before its normal duration expires.
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
