class_name LegacyExplosionEffect
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const EXPLOSION_RULES: Script = preload(
	"res://scripts/legacy_explosion_rules.gd"
)
const VISUAL_RULES: Script = preload(
	"res://scripts/legacy_explosion_visual_rules.gd"
)

var runtime_actor_type := 0
var original_gfl_index := 0
var primary_frames: Array[Texture2D] = []
var primary_anchor := Vector2.ZERO
var primary_frame_count := 0
var primary_frame_hold_ticks := 1
var primary_frame_index := 0
var primary_frame_elapsed_ticks := 0
var primary_complete := false
var particles: Array[Dictionary] = []
var visual_catalog: Dictionary = {}
var world_size := Vector2.ZERO
var random_state := VISUAL_RULES.CRT_INITIAL_STATE
var crt_random_draws: Array[Dictionary] = []
var configured := false


func configure(
	world_position: Vector2,
	new_runtime_actor_type: int,
	new_visual_catalog: Dictionary,
	new_world_size: Vector2,
	initial_random_state: int,
	special_bursts: Array[Dictionary] = [],
) -> int:
	var profile: Dictionary = (
		EXPLOSION_RULES.profile_for_actor(new_runtime_actor_type)
	)
	if profile.is_empty():
		return initial_random_state
	runtime_actor_type = new_runtime_actor_type
	original_gfl_index = int(profile.get("original_gfl_index", 0))
	global_position = world_position
	visual_catalog = new_visual_catalog.duplicate()
	world_size = new_world_size
	random_state = initial_random_state
	crt_random_draws.clear()
	primary_frames.clear()
	var visual_value: Variant = visual_catalog.get(original_gfl_index, {})
	var visual := (
		visual_value as Dictionary if visual_value is Dictionary else {}
	)
	for raw_frame: Variant in visual.get("frames", []) as Array:
		if raw_frame is Texture2D:
			primary_frames.append(raw_frame as Texture2D)
	primary_anchor = visual.get("anchor", Vector2.ZERO) as Vector2
	primary_frame_count = maxi(
		primary_frames.size(),
		int(profile.get("frame_count", 1)),
	)
	primary_frame_hold_ticks = maxi(
		int(profile.get("frame_hold_ticks", 1)),
		1,
	)
	primary_frame_index = 0
	primary_frame_elapsed_ticks = 0
	primary_complete = false
	particles.clear()
	if special_bursts.is_empty():
		_add_burst(11, world_position)
	else:
		for burst: Dictionary in special_bursts:
			_add_burst(
				int(burst.get("effect_family", 11)),
				burst.get("world_position", world_position) as Vector2,
			)
	configured = true
	z_index = WORLD_DEPTH.normal_z(global_position.y, 5)
	queue_redraw()
	return random_state


func take_crt_random_draws() -> Array[Dictionary]:
	var result := crt_random_draws.duplicate(true)
	crt_random_draws.clear()
	return result


func advance_world_ticks(ticks: int = 1) -> void:
	for unused_tick: int in range(maxi(ticks, 0)):
		_advance_primary()
		_advance_particles()
	if primary_complete and particles.is_empty() and is_inside_tree():
		queue_free()
	queue_redraw()


func remaining_particle_count() -> int:
	return particles.size()


func is_visual_complete() -> bool:
	return primary_complete and particles.is_empty()


func is_persistable() -> bool:
	return configured and not is_visual_complete()


func snapshot() -> Dictionary:
	var particle_snapshots: Array[Dictionary] = []
	for particle: Dictionary in particles:
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
		"schema_version": 1,
		"runtime_actor_type": runtime_actor_type,
		"x": global_position.x,
		"y": global_position.y,
		"random_state": random_state,
		"primary_frame_index": primary_frame_index,
		"primary_frame_elapsed_ticks": primary_frame_elapsed_ticks,
		"primary_complete": primary_complete,
		"particles": particle_snapshots,
	}


func restore_runtime_state(snapshot_value: Dictionary) -> bool:
	if (
		not configured
		or int(snapshot_value.get("schema_version", 0)) != 1
		or int(snapshot_value.get("runtime_actor_type", 0))
			!= runtime_actor_type
	):
		return false
	global_position = Vector2(
		float(snapshot_value.get("x", global_position.x)),
		float(snapshot_value.get("y", global_position.y)),
	)
	random_state = int(snapshot_value.get("random_state", random_state))
	primary_frame_index = clampi(
		int(snapshot_value.get("primary_frame_index", 0)),
		0,
		maxi(primary_frame_count - 1, 0),
	)
	primary_frame_elapsed_ticks = clampi(
		int(snapshot_value.get("primary_frame_elapsed_ticks", 0)),
		0,
		maxi(primary_frame_hold_ticks - 1, 0),
	)
	primary_complete = bool(snapshot_value.get("primary_complete", false))
	particles.clear()
	var raw_particles: Variant = snapshot_value.get("particles", [])
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
		var completed_loops := clampi(
			int(saved.get("completed_loops", 0)),
			0,
			repeat_count - 1,
		)
		var gfl_index := int(saved.get("gfl_index", -1))
		var frames: Array[Texture2D] = []
		var visual_value: Variant = visual_catalog.get(gfl_index, {})
		var visual := (
			visual_value as Dictionary
			if visual_value is Dictionary
			else {}
		)
		for raw_frame: Variant in visual.get("frames", []) as Array:
			if raw_frame is Texture2D:
				frames.append(raw_frame as Texture2D)
		particles.append({
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
			"completed_loops": completed_loops,
			"repeat_count": repeat_count,
		})
	z_index = WORLD_DEPTH.normal_z(global_position.y, 5)
	queue_redraw()
	return true


func _physics_process(_delta: float) -> void:
	advance_world_ticks(1)


func _add_burst(effect_family: int, center_world_position: Vector2) -> void:
	var plan: Dictionary = VISUAL_RULES.build_burst_plan(
		effect_family,
		center_world_position,
		world_size,
		random_state,
	)
	if plan.is_empty():
		return
	random_state = int(plan.get("next_random_state", random_state))
	for raw_draw: Variant in plan.get("random_draws", []) as Array:
		if raw_draw is Dictionary:
			crt_random_draws.append((raw_draw as Dictionary).duplicate(true))
	for raw_particle: Variant in plan.get("particles", []) as Array:
		if not raw_particle is Dictionary:
			continue
		var particle_plan := raw_particle as Dictionary
		var gfl_index := int(particle_plan.get("gfl_index", -1))
		var visual_value: Variant = visual_catalog.get(gfl_index, {})
		var visual := (
			visual_value as Dictionary if visual_value is Dictionary else {}
		)
		var frames: Array[Texture2D] = []
		for raw_frame: Variant in visual.get("frames", []) as Array:
			if raw_frame is Texture2D:
				frames.append(raw_frame as Texture2D)
		var frame_count := maxi(
			int(particle_plan.get("frame_count", 1)),
			1,
		)
		var frame_hold_ticks := maxi(
			int(particle_plan.get("frame_hold_ticks", 1)),
			1,
		)
		if (
			not frames.is_empty()
			and int(visual.get("frame_hold_ticks", frame_hold_ticks))
				== frame_hold_ticks
		):
			frame_count = frames.size()
		particles.append({
			"runtime_actor_type": int(
				particle_plan.get("runtime_actor_type", 0)
			),
			"gfl_index": gfl_index,
			"local_position": (
				particle_plan.get(
					"world_position",
					center_world_position,
				) as Vector2
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
		})


func _advance_primary() -> void:
	if primary_complete:
		return
	primary_frame_elapsed_ticks += 1
	if primary_frame_elapsed_ticks < primary_frame_hold_ticks:
		return
	primary_frame_elapsed_ticks = 0
	primary_frame_index += 1
	if primary_frame_index >= primary_frame_count:
		primary_frame_index = maxi(primary_frame_count - 1, 0)
		primary_complete = true


func _advance_particles() -> void:
	for particle_index: int in range(particles.size() - 1, -1, -1):
		var particle := particles[particle_index]
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
		if (
			int(particle.get("completed_loops", 0))
			>= int(particle.get("repeat_count", 1))
		):
			particles.remove_at(particle_index)


func _draw() -> void:
	if not primary_complete:
		if not primary_frames.is_empty():
			draw_texture(
				primary_frames[
					clampi(
						primary_frame_index,
						0,
						primary_frames.size() - 1,
					)
				],
				-primary_anchor,
			)
		else:
			var primary_phase := float(primary_frame_index) / maxf(
				float(primary_frame_count),
				1.0,
			)
			draw_arc(
				Vector2.ZERO,
				12.0 + primary_phase * 28.0,
				0.0,
				TAU,
				24,
				Color(1.0, 0.52, 0.12, 0.85 - primary_phase * 0.55),
				3.0,
			)
	for particle: Dictionary in particles:
		var local_position := particle.get(
			"local_position",
			Vector2.ZERO,
		) as Vector2
		var frames := particle.get("frames", []) as Array
		if not frames.is_empty():
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
					local_position
						- (particle.get("anchor", Vector2.ZERO) as Vector2),
				)
				continue
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
