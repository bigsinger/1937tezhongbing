class_name LegacySpecialWorldObject
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")

signal state_changed(world_object: Node2D, old_state: int, new_state: int)
signal triggered(world_object: Node2D, target: Node2D)
signal explosion_requested(
	world_object: Node2D,
	instigator: Node2D,
	world_position: Vector2,
	damage: int,
	horizontal_radius: float,
	vertical_radius: float,
	source_faction_id: int,
)
signal resolved(world_object: Node2D)
signal disarmed(world_object: Node2D)

enum State { INACTIVE, ACTIVE, TRIGGERED, RESOLVED, DISARMED }

var state := State.INACTIVE
var attack_type := 0
var original_actor_type := 0
var original_gfl_index := 0
var consumed_item_id := 0
var owner_actor: Node2D
var faction_id := 0
var age_world_ticks := 0
var resolved_world_ticks := 0
var trigger_target: Node2D
var potential_targets: Array[Node2D] = []
var trigger_faction_id := 0
var trigger_horizontal_radius := 0.0
var trigger_vertical_radius := 0.0
var fuse_world_ticks := 0
var blast_damage := 0
var blast_horizontal_radius := 0.0
var blast_vertical_radius := 0.0
var resolved_visual_ticks := 0
var original_texture: Texture2D
var original_frames: Array[Texture2D] = []
var original_frame_hold_ticks := 1
var original_frame_index := 0
var original_animation_ticks := 0
var evidence_profile: Dictionary = {}


func configure(
	profile: Dictionary,
	world_position: Vector2,
	new_owner: Node2D = null,
	new_faction_id: int = 3,
	visual: Variant = null,
) -> bool:
	if not SPECIAL_PROFILES.is_valid_profile(profile):
		return false
	var requested_attack_type := int(profile.get("attack_type", 0))
	if not SPECIAL_PROFILES.is_world_object_attack(requested_attack_type):
		return false
	attack_type = requested_attack_type
	evidence_profile = profile.duplicate(true)
	original_actor_type = int(profile.get("original_actor_type", 0))
	original_gfl_index = int(profile.get("original_gfl_index", 0))
	consumed_item_id = int(profile.get("ammo_item_id", 0))
	owner_actor = new_owner
	faction_id = new_faction_id
	position = world_position
	trigger_faction_id = int(profile.get("trigger_faction_id", 0))
	trigger_horizontal_radius = float(profile.get("trigger_horizontal_radius", 0.0))
	trigger_vertical_radius = float(profile.get("trigger_vertical_radius", 0.0))
	fuse_world_ticks = maxi(int(profile.get("fuse_world_ticks", 0)), 0)
	blast_damage = maxi(int(profile.get("blast_damage", 0)), 0)
	blast_horizontal_radius = maxf(float(profile.get("blast_horizontal_radius", 0.0)), 0.0)
	blast_vertical_radius = maxf(float(profile.get("blast_vertical_radius", 0.0)), 0.0)
	resolved_visual_ticks = maxi(int(profile.get("resolved_visual_ticks", 0)), 0)
	original_frames.clear()
	original_frame_hold_ticks = 1
	if visual is Texture2D:
		original_frames.append(visual as Texture2D)
	elif visual is Dictionary:
		var raw_frames: Variant = (visual as Dictionary).get("frames", [])
		if raw_frames is Array:
			for raw_frame: Variant in raw_frames as Array:
				if raw_frame is Texture2D:
					original_frames.append(raw_frame as Texture2D)
		original_frame_hold_ticks = maxi(
			int((visual as Dictionary).get("frame_hold_ticks", 1)),
			1,
		)
	original_texture = original_frames[0] if not original_frames.is_empty() else null
	original_frame_index = 0
	original_animation_ticks = 0
	age_world_ticks = 0
	resolved_world_ticks = 0
	trigger_target = null
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	_transition_to(State.ACTIVE)
	queue_redraw()
	return true


func set_potential_targets(candidates: Array[Node2D]) -> void:
	potential_targets = candidates.duplicate()


func has_original_texture() -> bool:
	return original_texture != null


func is_active() -> bool:
	return state == State.ACTIVE


func is_resolved() -> bool:
	return state in [State.RESOLVED, State.DISARMED]


func advance_world_ticks(ticks: int = 1) -> void:
	var safe_ticks := maxi(ticks, 0)
	if safe_ticks <= 0:
		return
	if state == State.ACTIVE:
		_advance_original_animation(safe_ticks)
		age_world_ticks += safe_ticks
		if attack_type == 8:
			var candidate := _nearest_recovered_trigger_target()
			if candidate != null:
				_trigger_and_detonate(candidate)
		elif attack_type == 10 and age_world_ticks >= fuse_world_ticks:
			_trigger_and_detonate(null)
	elif state == State.RESOLVED:
		resolved_world_ticks += safe_ticks
		if resolved_world_ticks >= resolved_visual_ticks and is_inside_tree():
			queue_free()
	queue_redraw()


func try_trigger(candidate: Node2D) -> bool:
	if attack_type != 8 or state != State.ACTIVE or not _is_recovered_trigger_target(candidate):
		return false
	if not _is_inside_trigger_ellipse(candidate.global_position):
		return false
	_trigger_and_detonate(candidate)
	return true


func disarm() -> bool:
	if state != State.ACTIVE:
		return false
	_transition_to(State.DISARMED)
	visible = false
	disarmed.emit(self)
	if is_inside_tree():
		queue_free()
	return true


func explosion_payload() -> Dictionary:
	return {
		"source": self,
		"instigator": owner_actor,
		"trigger_target": trigger_target,
		"world_position": global_position,
		"damage": blast_damage,
		"horizontal_radius": blast_horizontal_radius,
		"vertical_radius": blast_vertical_radius,
		"source_faction_id": faction_id,
		"attack_type": attack_type,
		"original_actor_type": original_actor_type,
		"original_gfl_index": original_gfl_index,
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"attack_type": attack_type,
		"state": state,
		"x": position.x,
		"y": position.y,
		"source_faction_id": faction_id,
		"owner_scene_index": int(owner_actor.get("scene_index")) if is_instance_valid(owner_actor) else -1,
		"owner_display_name": str(owner_actor.get("display_name")) if is_instance_valid(owner_actor) else "",
		"trigger_scene_index": int(trigger_target.get("scene_index")) if is_instance_valid(trigger_target) else -1,
		"age_world_ticks": age_world_ticks,
		"resolved_world_ticks": resolved_world_ticks,
	}


func restore_runtime_state(snapshot_value: Dictionary) -> bool:
	if int(snapshot_value.get("attack_type", 0)) != attack_type:
		return false
	var restored_state := int(snapshot_value.get("state", State.ACTIVE))
	if restored_state < State.ACTIVE or restored_state > State.DISARMED:
		return false
	state = restored_state
	age_world_ticks = maxi(int(snapshot_value.get("age_world_ticks", 0)), 0)
	resolved_world_ticks = maxi(int(snapshot_value.get("resolved_world_ticks", 0)), 0)
	original_animation_ticks = age_world_ticks
	if not original_frames.is_empty():
		original_frame_index = (
			original_animation_ticks / original_frame_hold_ticks
		) % original_frames.size()
	visible = state not in [State.DISARMED]
	queue_redraw()
	return true


func _physics_process(_delta: float) -> void:
	# The recovered type-10 threshold is expressed in original world ticks, not
	# seconds. Advancing exactly once per fixed physics tick preserves that unit
	# without inventing an undocumented seconds conversion.
	advance_world_ticks(1)


func _trigger_and_detonate(candidate: Node2D) -> void:
	if state != State.ACTIVE:
		return
	trigger_target = candidate
	_transition_to(State.TRIGGERED)
	triggered.emit(self, candidate)
	_transition_to(State.RESOLVED)
	resolved_world_ticks = 0
	explosion_requested.emit(
		self,
		owner_actor,
		global_position,
		blast_damage,
		blast_horizontal_radius,
		blast_vertical_radius,
		faction_id,
	)
	resolved.emit(self)


func _transition_to(new_state: State) -> void:
	if state == new_state:
		return
	var old_state := state
	state = new_state
	state_changed.emit(self, old_state, new_state)


func _advance_original_animation(ticks: int) -> void:
	if original_frames.size() <= 1:
		return
	original_animation_ticks += ticks
	original_frame_index = (
		original_animation_ticks / original_frame_hold_ticks
	) % original_frames.size()


func _nearest_recovered_trigger_target() -> Node2D:
	var nearest: Node2D
	var nearest_distance := INF
	for candidate: Node2D in potential_targets:
		if not _is_recovered_trigger_target(candidate):
			continue
		var offset := candidate.global_position - global_position
		var normalized_distance := (
			offset.x * offset.x / (trigger_horizontal_radius * trigger_horizontal_radius)
			+ offset.y * offset.y / (trigger_vertical_radius * trigger_vertical_radius)
		)
		if normalized_distance <= 1.0 and normalized_distance < nearest_distance:
			nearest = candidate
			nearest_distance = normalized_distance
	return nearest


func _is_recovered_trigger_target(candidate: Node2D) -> bool:
	# Original actor 84 checks a living faction-1 actor. It does not use the
	# remake's generic hostility relation, so we intentionally keep this exact.
	return (
		candidate != null
		and is_instance_valid(candidate)
		and candidate.has_method("is_combat_alive")
		and bool(candidate.call("is_combat_alive"))
		and int(candidate.get("faction_id")) == trigger_faction_id
	)


func _is_inside_trigger_ellipse(world_position: Vector2) -> bool:
	if trigger_horizontal_radius <= 0.0 or trigger_vertical_radius <= 0.0:
		return false
	var offset := world_position - global_position
	return (
		offset.x * offset.x / (trigger_horizontal_radius * trigger_horizontal_radius)
		+ offset.y * offset.y / (trigger_vertical_radius * trigger_vertical_radius)
	) <= 1.0


func _draw() -> void:
	if not original_frames.is_empty():
		var frame: Texture2D = original_frames[clampi(original_frame_index, 0, original_frames.size() - 1)]
		var texture_size := frame.get_size()
		draw_texture(frame, -texture_size * 0.5)
	elif state in [State.ACTIVE, State.TRIGGERED]:
		var color := Color(0.33, 0.47, 0.24) if attack_type == 8 else Color(0.40, 0.28, 0.18)
		draw_circle(Vector2.ZERO, 9.0, color)
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(0.92, 0.73, 0.22), 1.5)
	elif state == State.RESOLVED:
		_draw_ellipse(
			Vector2(blast_horizontal_radius, blast_vertical_radius),
			Color(1.0, 0.38, 0.08, 0.28),
		)


func _draw_ellipse(radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
