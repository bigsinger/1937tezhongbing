class_name LegacySpecialWorldObject
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)

const SPECIAL_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const EXPLOSION_VISUAL_RULES: Script = preload(
	"res://scripts/legacy_explosion_visual_rules.gd"
)
const ANIMATION_AUDIO_RULES: Script = preload(
	"res://scripts/legacy_animation_audio_rules.gd"
)

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
signal original_animation_audio_requested(
	source: Node2D,
	gfl_index: int,
	continuous: bool,
	local_requester_id: int,
)

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
var restored_trigger_scene_index := -1
var potential_targets: Array[Node2D] = []
var trigger_faction_id := 0
var trigger_horizontal_radius := 0.0
var trigger_vertical_radius := 0.0
var fuse_world_ticks := 0
var blast_damage := 0
var blast_horizontal_radius := 0.0
var blast_vertical_radius := 0.0
var alert_radius := 0.0
var special_damage_bands: Array[Dictionary] = []
var original_texture: Texture2D
var original_frames: Array[Texture2D] = []
var original_anchor := Vector2.ZERO
var original_frame_hold_ticks := 1
var original_frame_index := 0
var original_animation_ticks := 0
var original_action_index := -1
var original_sound_gfl_index := -1
var original_draw_order_rows: Array = []
var original_row_slice_renderer: Node2D
var original_drawn_by_row_slices := false
var evidence_profile: Dictionary = {}
var resolved_visual_catalog: Dictionary = {}
var resolved_particles: Array[Dictionary] = []
var resolved_visual_burst_count := 0
var visual_random_state := 1
var crt_random_draws: Array[Dictionary] = []
var visual_world_size := Vector2.ZERO
var next_particle_audio_requester_id := 1


func configure(
	profile: Dictionary,
	world_position: Vector2,
	new_owner: Node2D = null,
	new_faction_id: int = 3,
	visual: Variant = null,
	new_resolved_visual_catalog: Dictionary = {},
	new_visual_world_size: Vector2 = Vector2.ZERO,
	new_visual_random_state: int = 1,
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
	alert_radius = maxf(float(profile.get("alert_radius", 0.0)), 0.0)
	special_damage_bands.clear()
	for raw_band: Variant in profile.get("special_damage_bands", []) as Array:
		if raw_band is Dictionary:
			special_damage_bands.append((raw_band as Dictionary).duplicate(true))
	resolved_visual_catalog = new_resolved_visual_catalog.duplicate()
	resolved_particles.clear()
	resolved_visual_burst_count = 0
	visual_world_size = new_visual_world_size
	visual_random_state = new_visual_random_state
	crt_random_draws.clear()
	original_frames.clear()
	original_anchor = Vector2.ZERO
	original_frame_hold_ticks = 1
	original_action_index = -1
	original_sound_gfl_index = -1
	next_particle_audio_requester_id = 1
	original_draw_order_rows.clear()
	original_drawn_by_row_slices = false
	if (
		original_row_slice_renderer != null
		and is_instance_valid(original_row_slice_renderer)
	):
		original_row_slice_renderer.call("clear_visual")
	if visual is Texture2D:
		original_frames.append(visual as Texture2D)
		original_anchor = (visual as Texture2D).get_size() * 0.5
	elif visual is Dictionary:
		var raw_frames: Variant = (visual as Dictionary).get("frames", [])
		if raw_frames is Array:
			for raw_frame: Variant in raw_frames as Array:
				if raw_frame is Texture2D:
					original_frames.append(raw_frame as Texture2D)
		original_anchor = (visual as Dictionary).get(
			"anchor",
			original_frames[0].get_size() * 0.5 if not original_frames.is_empty() else Vector2.ZERO,
		) as Vector2
		original_frame_hold_ticks = maxi(
			int((visual as Dictionary).get("frame_hold_ticks", 1)),
			1,
		)
		original_action_index = int(
			(visual as Dictionary).get("action_index", -1)
		)
		original_sound_gfl_index = int(
			(visual as Dictionary).get("sound_gfl_index", -1)
		)
		var raw_draw_order_rows: Variant = (visual as Dictionary).get(
			"draw_order_row_lookup",
			[],
		)
		if raw_draw_order_rows is Array:
			original_draw_order_rows = (
				raw_draw_order_rows as Array
			).duplicate()
	original_texture = original_frames[0] if not original_frames.is_empty() else null
	original_frame_index = 0
	original_animation_ticks = 0
	age_world_ticks = 0
	resolved_world_ticks = 0
	trigger_target = null
	restored_trigger_scene_index = -1
	visible = true
	_apply_original_draw_order()
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


func is_persistable() -> bool:
	return (
		state == State.ACTIVE
		or (
			state == State.RESOLVED
			and not resolved_particles.is_empty()
		)
	)


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
		_advance_resolved_particles(safe_ticks)
		if (
			resolved_visual_burst_count > 0
			and resolved_particles.is_empty()
			and is_inside_tree()
		):
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
		"alert_radius": alert_radius,
		"special_damage_bands": special_damage_bands.duplicate(true),
		"source_faction_id": faction_id,
		"attack_type": attack_type,
		"original_actor_type": original_actor_type,
		"original_gfl_index": original_gfl_index,
	}


func add_recovered_visual_burst(
	effect_family: int,
	center_world_position: Vector2,
	random_state: int = -1,
) -> int:
	if state not in [State.TRIGGERED, State.RESOLVED]:
		return visual_random_state
	var start_state := visual_random_state if random_state < 0 else random_state
	var plan: Dictionary = EXPLOSION_VISUAL_RULES.build_burst_plan(
		effect_family,
		center_world_position,
		visual_world_size,
		start_state,
	)
	if plan.is_empty():
		return visual_random_state
	visual_random_state = int(plan.get("next_random_state", start_state))
	for raw_draw: Variant in plan.get("random_draws", []) as Array:
		if raw_draw is Dictionary:
			crt_random_draws.append((raw_draw as Dictionary).duplicate(true))
	resolved_visual_burst_count += 1
	for raw_particle: Variant in plan.get("particles", []) as Array:
		if not raw_particle is Dictionary:
			continue
		var particle_plan := raw_particle as Dictionary
		var gfl_index := int(particle_plan.get("gfl_index", -1))
		var visual_value: Variant = resolved_visual_catalog.get(gfl_index, {})
		var visual := visual_value as Dictionary if visual_value is Dictionary else {}
		var frames: Array[Texture2D] = []
		var raw_frames: Variant = visual.get("frames", [])
		if raw_frames is Array:
			for raw_frame: Variant in raw_frames as Array:
				if raw_frame is Texture2D:
					frames.append(raw_frame as Texture2D)
		var frame_count := maxi(int(particle_plan.get("frame_count", 0)), 1)
		var frame_hold_ticks := maxi(
			int(particle_plan.get("frame_hold_ticks", 0)),
			1,
		)
		var visual_hold_ticks := int(visual.get("frame_hold_ticks", frame_hold_ticks))
		if visual_hold_ticks == frame_hold_ticks and not frames.is_empty():
			frame_count = frames.size()
		resolved_particles.append({
			"runtime_actor_type": int(particle_plan.get("runtime_actor_type", 0)),
			"gfl_index": gfl_index,
			"local_position": (
				particle_plan.get("world_position", center_world_position) as Vector2
			) - global_position,
			"anchor": visual.get(
				"anchor",
				particle_plan.get("anchor", Vector2.ZERO),
			) as Vector2,
			"frames": frames,
			"frame_count": frame_count,
			"frame_hold_ticks": frame_hold_ticks,
			"frame_index": 0,
			"frame_elapsed_ticks": 0,
			"completed_loops": 0,
			"repeat_count": maxi(
				int(particle_plan.get("repeat_count", 1)),
				1,
			),
			"action_index": int(visual.get("action_index", -1)),
			"sound_gfl_index": int(visual.get("sound_gfl_index", -1)),
			"audio_requester_id": _allocate_particle_audio_requester_id(),
		})
	queue_redraw()
	return visual_random_state


func take_crt_random_draws() -> Array[Dictionary]:
	var result := crt_random_draws.duplicate(true)
	crt_random_draws.clear()
	return result


func resolved_particle_count() -> int:
	return resolved_particles.size()


func maximum_resolved_visual_lifetime_ticks() -> int:
	var maximum_ticks := 0
	for particle: Dictionary in resolved_particles:
		maximum_ticks = maxi(
			maximum_ticks,
			int(particle.get("frame_count", 0))
			* int(particle.get("frame_hold_ticks", 0))
			* int(particle.get("repeat_count", 0)),
		)
	return maximum_ticks


func snapshot() -> Dictionary:
	var particle_snapshots: Array[Dictionary] = []
	for particle: Dictionary in resolved_particles:
		var local_position := particle.get(
			"local_position",
			Vector2.ZERO,
		) as Vector2
		var anchor := particle.get("anchor", Vector2.ZERO) as Vector2
		particle_snapshots.append({
			"runtime_actor_type": int(
				particle.get("runtime_actor_type", 0)
			),
			"gfl_index": int(particle.get("gfl_index", -1)),
			"local_x": local_position.x,
			"local_y": local_position.y,
			"anchor_x": anchor.x,
			"anchor_y": anchor.y,
			"frame_count": int(particle.get("frame_count", 1)),
			"frame_hold_ticks": int(
				particle.get("frame_hold_ticks", 1)
			),
			"frame_index": int(particle.get("frame_index", 0)),
			"frame_elapsed_ticks": int(
				particle.get("frame_elapsed_ticks", 0)
			),
			"completed_loops": int(
				particle.get("completed_loops", 0)
			),
			"repeat_count": int(particle.get("repeat_count", 1)),
		})
	return {
		"schema_version": 2,
		"attack_type": attack_type,
		"state": state,
		"x": position.x,
		"y": position.y,
		"source_faction_id": faction_id,
		"owner_scene_index": int(owner_actor.get("scene_index")) if is_instance_valid(owner_actor) else -1,
		"owner_display_name": str(owner_actor.get("display_name")) if is_instance_valid(owner_actor) else "",
		"trigger_scene_index": (
			int(trigger_target.get("scene_index"))
			if is_instance_valid(trigger_target)
			else restored_trigger_scene_index
		),
		"age_world_ticks": age_world_ticks,
		"resolved_world_ticks": resolved_world_ticks,
		"visual_random_state": visual_random_state,
		"resolved_visual_burst_count": resolved_visual_burst_count,
		"resolved_particles": particle_snapshots,
	}


func restore_runtime_state(snapshot_value: Dictionary) -> bool:
	if int(snapshot_value.get("attack_type", 0)) != attack_type:
		return false
	var restored_state := int(snapshot_value.get("state", State.ACTIVE))
	if restored_state < State.ACTIVE or restored_state > State.DISARMED:
		return false
	state = restored_state
	position = Vector2(
		float(snapshot_value.get("x", position.x)),
		float(snapshot_value.get("y", position.y)),
	)
	age_world_ticks = maxi(int(snapshot_value.get("age_world_ticks", 0)), 0)
	resolved_world_ticks = maxi(int(snapshot_value.get("resolved_world_ticks", 0)), 0)
	visual_random_state = int(
		snapshot_value.get("visual_random_state", visual_random_state)
	)
	restored_trigger_scene_index = int(
		snapshot_value.get("trigger_scene_index", -1)
	)
	resolved_visual_burst_count = maxi(
		int(snapshot_value.get("resolved_visual_burst_count", 0)),
		0,
	)
	resolved_particles.clear()
	next_particle_audio_requester_id = 1
	var raw_particles: Variant = snapshot_value.get(
		"resolved_particles",
		[],
	)
	if not raw_particles is Array:
		return false
	for raw_particle: Variant in raw_particles as Array:
		if not raw_particle is Dictionary:
			return false
		var saved := raw_particle as Dictionary
		var frame_count := maxi(int(saved.get("frame_count", 0)), 1)
		var frame_hold_ticks := maxi(
			int(saved.get("frame_hold_ticks", 0)),
			1,
		)
		var repeat_count := maxi(int(saved.get("repeat_count", 0)), 1)
		var gfl_index := int(saved.get("gfl_index", -1))
		var frames: Array[Texture2D] = []
		var visual_value: Variant = resolved_visual_catalog.get(
			gfl_index,
			{},
		)
		var visual := (
			visual_value as Dictionary
			if visual_value is Dictionary
			else {}
		)
		for raw_frame: Variant in visual.get("frames", []) as Array:
			if raw_frame is Texture2D:
				frames.append(raw_frame as Texture2D)
		resolved_particles.append({
			"runtime_actor_type": int(
				saved.get("runtime_actor_type", 0)
			),
			"gfl_index": gfl_index,
			"local_position": Vector2(
				float(saved.get("local_x", 0.0)),
				float(saved.get("local_y", 0.0)),
			),
			"anchor": Vector2(
				float(saved.get("anchor_x", 0.0)),
				float(saved.get("anchor_y", 0.0)),
			),
			"frames": frames,
			"frame_count": frame_count,
			"frame_hold_ticks": frame_hold_ticks,
			"frame_index": clampi(
				int(saved.get("frame_index", 0)),
				0,
				frame_count - 1,
			),
			"frame_elapsed_ticks": clampi(
				int(saved.get("frame_elapsed_ticks", 0)),
				0,
				frame_hold_ticks - 1,
			),
			"completed_loops": clampi(
				int(saved.get("completed_loops", 0)),
				0,
				repeat_count - 1,
			),
			"repeat_count": repeat_count,
			"action_index": int(visual.get("action_index", -1)),
			"sound_gfl_index": int(visual.get("sound_gfl_index", -1)),
			"audio_requester_id": _allocate_particle_audio_requester_id(),
		})
	original_animation_ticks = age_world_ticks
	if not original_frames.is_empty():
		original_frame_index = (
			original_animation_ticks / original_frame_hold_ticks
		) % original_frames.size()
	visible = state not in [State.DISARMED]
	if state in [State.ACTIVE, State.TRIGGERED]:
		_apply_original_draw_order()
	else:
		original_drawn_by_row_slices = false
		if (
			original_row_slice_renderer != null
			and is_instance_valid(original_row_slice_renderer)
		):
			original_row_slice_renderer.call("clear_visual")
		z_index = WORLD_DEPTH.normal_z(position.y, 1)
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
	restored_trigger_scene_index = (
		int(candidate.get("scene_index"))
		if candidate != null
		else -1
	)
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
	if resolved_visual_burst_count == 0:
		add_recovered_visual_burst(11, global_position, visual_random_state)
	resolved.emit(self)


func _transition_to(new_state: State) -> void:
	if state == new_state:
		return
	var old_state := state
	state = new_state
	if state not in [State.ACTIVE, State.TRIGGERED]:
		original_drawn_by_row_slices = false
		if (
			original_row_slice_renderer != null
			and is_instance_valid(original_row_slice_renderer)
		):
			original_row_slice_renderer.call("clear_visual")
	state_changed.emit(self, old_state, new_state)


func _advance_original_animation(ticks: int) -> void:
	if original_frames.is_empty():
		return
	var group := {
		"action_index": original_action_index,
		"sound_gfl_index": original_sound_gfl_index,
		"frame_count": original_frames.size(),
	}
	for unused_tick: int in range(maxi(ticks, 0)):
		if ANIMATION_AUDIO_RULES.requests_continuously(group):
			original_animation_audio_requested.emit(
				self,
				original_sound_gfl_index,
				true,
				0,
			)
		if original_frames.size() <= 1:
			continue
		var previous_frame_index := original_frame_index
		original_animation_ticks += 1
		original_frame_index = (
			original_animation_ticks / original_frame_hold_ticks
		) % original_frames.size()
		if ANIMATION_AUDIO_RULES.transition_requests_sound(
			group,
			previous_frame_index,
			original_frame_index,
		):
			original_animation_audio_requested.emit(
				self,
				original_sound_gfl_index,
				false,
				0,
			)
	_apply_original_draw_order()


func _apply_original_draw_order() -> void:
	original_drawn_by_row_slices = false
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	if original_frames.is_empty() or original_draw_order_rows.is_empty():
		if (
			original_row_slice_renderer != null
			and is_instance_valid(original_row_slice_renderer)
		):
			original_row_slice_renderer.call("clear_visual")
		return
	var frame: Texture2D = original_frames[
		clampi(original_frame_index, 0, original_frames.size() - 1)
	]
	if _rows_are_uniform(original_draw_order_rows):
		z_index = WORLD_DEPTH.normal_z(
			position.y
			- original_anchor.y
			+ float(original_draw_order_rows[0])
		)
		if (
			original_row_slice_renderer != null
			and is_instance_valid(original_row_slice_renderer)
		):
			original_row_slice_renderer.call("clear_visual")
		return
	if (
		original_row_slice_renderer == null
		or not is_instance_valid(original_row_slice_renderer)
	):
		original_row_slice_renderer = LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
		original_row_slice_renderer.name = "OriginalRowSlices"
		add_child(original_row_slice_renderer)
	original_drawn_by_row_slices = bool(
		original_row_slice_renderer.call(
			"configure",
			frame,
			original_anchor,
			position.y,
			original_draw_order_rows,
		)
	)


static func _rows_are_uniform(rows: Array) -> bool:
	if rows.is_empty():
		return false
	var first: Variant = rows[0]
	if not first is int and not first is float:
		return false
	for row: Variant in rows:
		if (
			(not row is int and not row is float)
			or float(row) != float(first)
		):
			return false
	return true


func _advance_resolved_particles(ticks: int) -> void:
	for particle_index: int in range(resolved_particles.size() - 1, -1, -1):
		var particle := resolved_particles[particle_index]
		var remaining_ticks := ticks
		while (
			remaining_ticks > 0
			and int(particle.get("completed_loops", 0))
			< int(particle.get("repeat_count", 1))
		):
			var audio_group := {
				"action_index": int(particle.get("action_index", -1)),
				"sound_gfl_index": int(
					particle.get("sound_gfl_index", -1)
				),
				"frame_count": int(particle.get("frame_count", 0)),
			}
			if ANIMATION_AUDIO_RULES.requests_continuously(audio_group):
				original_animation_audio_requested.emit(
					self,
					int(particle.get("sound_gfl_index", -1)),
					true,
					int(particle.get("audio_requester_id", 0)),
				)
			var previous_frame_index := int(particle.get("frame_index", 0))
			particle["frame_elapsed_ticks"] = (
				int(particle.get("frame_elapsed_ticks", 0)) + 1
			)
			if (
				int(particle["frame_elapsed_ticks"])
				>= int(particle.get("frame_hold_ticks", 1))
			):
				particle["frame_elapsed_ticks"] = 0
				particle["frame_index"] = int(particle.get("frame_index", 0)) + 1
				if (
					int(particle["frame_index"])
					>= int(particle.get("frame_count", 1))
				):
					particle["frame_index"] = 0
					particle["completed_loops"] = (
						int(particle.get("completed_loops", 0)) + 1
					)
			var current_frame_index := int(particle.get("frame_index", 0))
			if ANIMATION_AUDIO_RULES.transition_requests_sound(
				audio_group,
				previous_frame_index,
				current_frame_index,
			):
				original_animation_audio_requested.emit(
					self,
					int(particle.get("sound_gfl_index", -1)),
					false,
					int(particle.get("audio_requester_id", 0)),
				)
			remaining_ticks -= 1
		if (
			int(particle.get("completed_loops", 0))
			>= int(particle.get("repeat_count", 1))
		):
			resolved_particles.remove_at(particle_index)


func _allocate_particle_audio_requester_id() -> int:
	var result := next_particle_audio_requester_id
	next_particle_audio_requester_id += 1
	return result


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
	if (
		state in [State.ACTIVE, State.TRIGGERED]
		and not original_frames.is_empty()
		and not original_drawn_by_row_slices
	):
		var frame: Texture2D = original_frames[clampi(original_frame_index, 0, original_frames.size() - 1)]
		draw_texture(frame, -original_anchor)
	elif state in [State.ACTIVE, State.TRIGGERED]:
		var color := Color(0.33, 0.47, 0.24) if attack_type == 8 else Color(0.40, 0.28, 0.18)
		draw_circle(Vector2.ZERO, 9.0, color)
		draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(0.92, 0.73, 0.22), 1.5)
	elif state == State.RESOLVED:
		_draw_resolved_particles()


func _draw_resolved_particles() -> void:
	for particle: Dictionary in resolved_particles:
		var local_position := particle.get("local_position", Vector2.ZERO) as Vector2
		var raw_frames: Variant = particle.get("frames", [])
		if raw_frames is Array and not (raw_frames as Array).is_empty():
			var frames := raw_frames as Array
			var frame_value: Variant = frames[
				clampi(
					int(particle.get("frame_index", 0)),
					0,
					frames.size() - 1,
				)
			]
			if frame_value is Texture2D:
				draw_texture(
					frame_value as Texture2D,
					local_position - (particle.get("anchor", Vector2.ZERO) as Vector2),
				)
				continue
		# Asset-free tests and fresh checkouts retain the recovered timing and
		# positions while using a cheap outline instead of an invented filled
		# blast ellipse.
		var phase := float(int(particle.get("frame_index", 0))) / maxf(
			float(int(particle.get("frame_count", 1))),
			1.0,
		)
		draw_arc(
			local_position,
			8.0 + phase * 10.0,
			0.0,
			TAU,
			16,
			Color(1.0, 0.45, 0.10, 0.78 - phase * 0.45),
			2.0,
		)


func _draw_ellipse(radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
