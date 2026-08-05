class_name LegacyExplosionEffect
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const EXPLOSION_RULES: Script = preload(
	"res://scripts/legacy_explosion_rules.gd"
)
const VISUAL_RULES: Script = preload(
	"res://scripts/legacy_explosion_visual_rules.gd"
)
const ANIMATION_AUDIO_RULES: Script = preload(
	"res://scripts/legacy_animation_audio_rules.gd"
)

signal original_animation_audio_requested(
	source: Node2D,
	gfl_index: int,
	continuous: bool,
	local_requester_id: int,
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
var primary_destructor_consumed := false
var primary_action_index := -1
var primary_sound_gfl_index := -1
var particles: Array[Dictionary] = []
var ground_decals: Array[Dictionary] = []
var debris_particles: Array[Dictionary] = []
var pending_bursts: Array[Dictionary] = []
var pending_bursts_released := false
var visual_catalog: Dictionary = {}
var world_size := Vector2.ZERO
var random_state := VISUAL_RULES.CRT_INITIAL_STATE
var crt_random_draws: Array[Dictionary] = []
var original_crt_random_source: Node
var configured := false
var next_particle_audio_requester_id := 1
var reduced_flash_mode := false


func set_reduce_flashes(value: bool) -> void:
	reduced_flash_mode = value
	modulate = Color(0.82, 0.82, 0.82, 0.92) if value else Color.WHITE


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
	original_crt_random_source = null
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
	primary_action_index = int(visual.get("action_index", -1))
	primary_sound_gfl_index = int(visual.get("sound_gfl_index", -1))
	primary_frame_index = 0
	primary_frame_elapsed_ticks = 0
	primary_complete = false
	primary_destructor_consumed = false
	particles.clear()
	ground_decals.clear()
	debris_particles.clear()
	pending_bursts.clear()
	pending_bursts_released = false
	next_particle_audio_requester_id = 1
	# sub_463F40 creates actor 61/62 through sub_44A350 before dispatching its
	# child effects. Native in-level traces fix this successful factory path at
	# the four constructor draws; sub_45B950 is a separate SAV-load consumer.
	var primary_factory_plan: Dictionary = (
		VISUAL_RULES.build_dynamic_actor_factory_plan(
			_active_random_state(),
			true,
		)
	)
	if primary_factory_plan.is_empty() or not _commit_random_plan(
		primary_factory_plan
	):
		return random_state
	# sub_463F40 creates the persistent effect-10 scorch family first and the
	# effect-12 debris cluster second. The damage-band effect 11/15 is emitted
	# only when the actor-61/62 primary animation reaches its native action
	# frame, so retain it as a pending batch instead of shifting the CRT stream.
	_add_burst(10, world_position)
	_add_debris_cluster(world_position)
	if special_bursts.is_empty():
		pending_bursts.append({
			"effect_family": 11,
			"world_position": world_position,
		})
	else:
		for burst: Dictionary in special_bursts:
			pending_bursts.append(burst.duplicate(true))
	configured = true
	z_index = WORLD_DEPTH.normal_z(global_position.y, 5)
	queue_redraw()
	return random_state


func bind_original_crt_random_source(source: Node) -> void:
	original_crt_random_source = source


func take_crt_random_draws() -> Array[Dictionary]:
	var result := crt_random_draws.duplicate(true)
	crt_random_draws.clear()
	return result


func advance_world_ticks(ticks: int = 1) -> void:
	for unused_tick: int in range(maxi(ticks, 0)):
		_advance_primary()
		_advance_particles()
		_advance_debris_particles()
	if is_visual_complete() and is_inside_tree():
		queue_free()
	queue_redraw()


func remaining_particle_count() -> int:
	return particles.size()


func remaining_debris_count() -> int:
	return debris_particles.size()


func persistent_scorch_count() -> int:
	return ground_decals.size()


func is_visual_complete() -> bool:
	return (
		primary_complete
		and pending_bursts_released
		and particles.is_empty()
		and debris_particles.is_empty()
		and ground_decals.is_empty()
	)


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
	var decal_snapshots: Array[Dictionary] = []
	for decal: Dictionary in ground_decals:
		var decal_position := decal.get(
			"local_position",
			Vector2.ZERO,
		) as Vector2
		var decal_anchor := decal.get("anchor", Vector2.ZERO) as Vector2
		decal_snapshots.append({
			"runtime_actor_type": int(decal.get("runtime_actor_type", 0)),
			"gfl_index": int(decal.get("gfl_index", -1)),
			"local_x": decal_position.x,
			"local_y": decal_position.y,
			"anchor_x": decal_anchor.x,
			"anchor_y": decal_anchor.y,
		})
	var debris_snapshots: Array[Dictionary] = []
	for debris: Dictionary in debris_particles:
		var path := debris.get("path", PackedVector2Array()) as PackedVector2Array
		var path_start := path[0] if not path.is_empty() else global_position
		var path_end := path[-1] if not path.is_empty() else global_position
		var debris_position := debris.get(
			"world_position",
			global_position,
		) as Vector2
		var debris_anchor := debris.get("anchor", Vector2.ZERO) as Vector2
		debris_snapshots.append({
			"runtime_actor_type": int(debris.get("runtime_actor_type", 0)),
			"gfl_index": int(debris.get("gfl_index", -1)),
			"anchor_x": debris_anchor.x,
			"anchor_y": debris_anchor.y,
			"frame_count": int(debris.get("frame_count", 1)),
			"frame_hold_ticks": int(debris.get("frame_hold_ticks", 1)),
			"frame_index": int(debris.get("frame_index", 0)),
			"frame_elapsed_ticks": int(debris.get("frame_elapsed_ticks", 0)),
			"repeat_count": int(debris.get("repeat_count", 1)),
			"remaining_flights": int(debris.get("remaining_flights", 1)),
			"angle_degrees": int(debris.get("angle_degrees", 0)),
			"speed": int(debris.get("speed", 2)),
			"path_start_x": path_start.x,
			"path_start_y": path_start.y,
			"path_end_x": path_end.x,
			"path_end_y": path_end.y,
			"path_index": int(debris.get("path_index", 0)),
			"flight_tick": int(debris.get("flight_tick", 0)),
			"world_x": debris_position.x,
			"world_y": debris_position.y,
			"height": int(debris.get("height", 0)),
		})
	var pending_burst_snapshots: Array[Dictionary] = []
	for pending_burst: Dictionary in pending_bursts:
		var pending_position := pending_burst.get(
			"world_position",
			global_position,
		) as Vector2
		pending_burst_snapshots.append({
			"effect_family": int(pending_burst.get("effect_family", 11)),
			"world_x": pending_position.x,
			"world_y": pending_position.y,
		})
	return {
		"schema_version": 2,
		"runtime_actor_type": runtime_actor_type,
		"x": global_position.x,
		"y": global_position.y,
		"random_state": random_state,
		"primary_frame_index": primary_frame_index,
		"primary_frame_elapsed_ticks": primary_frame_elapsed_ticks,
		"primary_complete": primary_complete,
		"primary_destructor_consumed": primary_destructor_consumed,
		"particles": particle_snapshots,
		"ground_decals": decal_snapshots,
		"debris_particles": debris_snapshots,
		"pending_bursts": pending_burst_snapshots,
		"pending_bursts_released": pending_bursts_released,
	}


func restore_runtime_state(snapshot_value: Dictionary) -> bool:
	var schema_version := int(snapshot_value.get("schema_version", 0))
	if (
		not configured
		or schema_version < 1
		or schema_version > 2
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
	primary_destructor_consumed = bool(snapshot_value.get(
		"primary_destructor_consumed",
		primary_complete,
	))
	particles.clear()
	ground_decals.clear()
	debris_particles.clear()
	pending_bursts.clear()
	crt_random_draws.clear()
	next_particle_audio_requester_id = 1
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
			"action_index": int(visual.get("action_index", -1)),
			"sound_gfl_index": int(visual.get("sound_gfl_index", -1)),
			"audio_requester_id": _allocate_particle_audio_requester_id(),
		})
	var raw_decals: Variant = snapshot_value.get("ground_decals", [])
	if not raw_decals is Array:
		return false
	for raw_decal: Variant in raw_decals as Array:
		if not raw_decal is Dictionary:
			return false
		var saved_decal := raw_decal as Dictionary
		var decal_gfl_index := int(saved_decal.get("gfl_index", -1))
		var decal_visual_value: Variant = visual_catalog.get(
			decal_gfl_index,
			{},
		)
		var decal_visual := (
			decal_visual_value as Dictionary
			if decal_visual_value is Dictionary
			else {}
		)
		var decal_frames: Array[Texture2D] = []
		for raw_frame: Variant in decal_visual.get("frames", []) as Array:
			if raw_frame is Texture2D:
				decal_frames.append(raw_frame as Texture2D)
		ground_decals.append({
			"runtime_actor_type": int(saved_decal.get("runtime_actor_type", 0)),
			"gfl_index": decal_gfl_index,
			"local_position": Vector2(
				float(saved_decal.get("local_x", 0.0)),
				float(saved_decal.get("local_y", 0.0)),
			),
			"anchor": Vector2(
				float(saved_decal.get("anchor_x", 0.0)),
				float(saved_decal.get("anchor_y", 0.0)),
			),
			"frames": decal_frames,
		})
	var raw_debris: Variant = snapshot_value.get("debris_particles", [])
	if not raw_debris is Array:
		return false
	for raw_debris_particle: Variant in raw_debris as Array:
		if not raw_debris_particle is Dictionary:
			return false
		var saved_debris := raw_debris_particle as Dictionary
		var debris_gfl_index := int(saved_debris.get("gfl_index", -1))
		var debris_visual_value: Variant = visual_catalog.get(
			debris_gfl_index,
			{},
		)
		var debris_visual := (
			debris_visual_value as Dictionary
			if debris_visual_value is Dictionary
			else {}
		)
		var debris_frames: Array[Texture2D] = []
		for raw_frame: Variant in debris_visual.get("frames", []) as Array:
			if raw_frame is Texture2D:
				debris_frames.append(raw_frame as Texture2D)
		var debris_path: PackedVector2Array = VISUAL_RULES.bresenham_path(
			Vector2(
				float(saved_debris.get("path_start_x", global_position.x)),
				float(saved_debris.get("path_start_y", global_position.y)),
			),
			Vector2(
				float(saved_debris.get("path_end_x", global_position.x)),
				float(saved_debris.get("path_end_y", global_position.y)),
			),
		)
		var debris_frame_count := maxi(
			int(saved_debris.get("frame_count", 1)),
			1,
		)
		var debris_frame_hold := maxi(
			int(saved_debris.get("frame_hold_ticks", 1)),
			1,
		)
		var debris_repeat_count := maxi(
			int(saved_debris.get("repeat_count", 1)),
			1,
		)
		debris_particles.append({
			"runtime_actor_type": int(saved_debris.get("runtime_actor_type", 0)),
			"gfl_index": debris_gfl_index,
			"anchor": Vector2(
				float(saved_debris.get("anchor_x", 0.0)),
				float(saved_debris.get("anchor_y", 0.0)),
			),
			"frames": debris_frames,
			"frame_count": debris_frame_count,
			"frame_hold_ticks": debris_frame_hold,
			"frame_index": clampi(
				int(saved_debris.get("frame_index", 0)),
				0,
				debris_frame_count - 1,
			),
			"frame_elapsed_ticks": clampi(
				int(saved_debris.get("frame_elapsed_ticks", 0)),
				0,
				debris_frame_hold - 1,
			),
			"repeat_count": debris_repeat_count,
			"remaining_flights": clampi(
				int(saved_debris.get("remaining_flights", 1)),
				1,
				debris_repeat_count,
			),
			"angle_degrees": posmod(
				int(saved_debris.get("angle_degrees", 0)),
				360,
			),
			"speed": maxi(int(saved_debris.get("speed", 2)), 2),
			"path": debris_path,
			"path_index": clampi(
				int(saved_debris.get("path_index", 0)),
				0,
				maxi(debris_path.size() - 1, 0),
			),
			"flight_tick": maxi(int(saved_debris.get("flight_tick", 0)), 0),
			"world_position": Vector2(
				float(saved_debris.get("world_x", global_position.x)),
				float(saved_debris.get("world_y", global_position.y)),
			),
			"height": maxi(int(saved_debris.get("height", 0)), 0),
		})
	var raw_pending_bursts: Variant = snapshot_value.get("pending_bursts", [])
	if not raw_pending_bursts is Array:
		return false
	for raw_pending_burst: Variant in raw_pending_bursts as Array:
		if not raw_pending_burst is Dictionary:
			return false
		var saved_pending_burst := raw_pending_burst as Dictionary
		var pending_position := Vector2(
			float(saved_pending_burst.get("world_x", global_position.x)),
			float(saved_pending_burst.get("world_y", global_position.y)),
		)
		# Schema 1 briefly stored the in-memory Vector2 directly. Accept it so
		# developer snapshots made before the JSON-safe schema remain loadable.
		if (
			schema_version == 1
			and saved_pending_burst.get("world_position") is Vector2
		):
			pending_position = saved_pending_burst.get(
				"world_position",
				global_position,
			) as Vector2
		pending_bursts.append({
			"effect_family": int(saved_pending_burst.get("effect_family", 11)),
			"world_position": pending_position,
		})
	pending_bursts_released = bool(snapshot_value.get(
		"pending_bursts_released",
		true,
	))
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
		_active_random_state(),
	)
	if plan.is_empty() or not _commit_random_plan(plan):
		return
	for raw_particle: Variant in plan.get("particles", []) as Array:
		if not raw_particle is Dictionary:
			continue
		var particle_plan := raw_particle as Dictionary
		var gfl_index := int(particle_plan.get("gfl_index", -1))
		var visual_value: Variant = visual_catalog.get(gfl_index, {})
		var visual := (
			visual_value as Dictionary if visual_value is Dictionary else {}
		)
		var frames: Array[Texture2D] = _visual_frames(gfl_index)
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
		var runtime_particle := {
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
			"action_index": int(visual.get("action_index", -1)),
			"sound_gfl_index": int(visual.get("sound_gfl_index", -1)),
			"audio_requester_id": _allocate_particle_audio_requester_id(),
		}
		if bool(particle_plan.get("persistent", false)):
			ground_decals.append(runtime_particle)
		else:
			particles.append(runtime_particle)


func _add_debris_cluster(center_world_position: Vector2) -> void:
	var plan: Dictionary = VISUAL_RULES.build_debris_cluster_plan(
		center_world_position,
		_active_random_state(),
	)
	if plan.is_empty() or not _commit_random_plan(plan):
		return
	for raw_debris: Variant in plan.get("debris", []) as Array:
		if not raw_debris is Dictionary:
			continue
		var debris_plan := raw_debris as Dictionary
		var gfl_index := int(debris_plan.get("gfl_index", -1))
		var visual_value: Variant = visual_catalog.get(gfl_index, {})
		var visual := (
			visual_value as Dictionary if visual_value is Dictionary else {}
		)
		var frames: Array[Texture2D] = _visual_frames(gfl_index)
		var frame_count := maxi(
			int(debris_plan.get("frame_count", 1)),
			1,
		)
		var frame_hold_ticks := maxi(
			int(debris_plan.get("frame_hold_ticks", 1)),
			1,
		)
		if not frames.is_empty():
			frame_count = frames.size()
			frame_hold_ticks = maxi(
				int(visual.get("frame_hold_ticks", frame_hold_ticks)),
				1,
			)
		debris_particles.append({
			"runtime_actor_type": int(debris_plan.get("runtime_actor_type", 0)),
			"gfl_index": gfl_index,
			"anchor": visual.get(
				"anchor",
				debris_plan.get("anchor", Vector2.ZERO),
			) as Vector2,
			"frames": frames,
			"frame_count": frame_count,
			"frame_hold_ticks": frame_hold_ticks,
			"frame_index": 0,
			"frame_elapsed_ticks": 0,
			"repeat_count": maxi(int(debris_plan.get("repeat_count", 1)), 1),
			"remaining_flights": maxi(
				int(debris_plan.get("remaining_flights", 1)),
				1,
			),
			"angle_degrees": posmod(
				int(debris_plan.get("angle_degrees", 0)),
				360,
			),
			"speed": maxi(int(debris_plan.get("speed", 2)), 2),
			"path": debris_plan.get("path", PackedVector2Array()) as PackedVector2Array,
			"path_index": 0,
			"flight_tick": 0,
			"world_position": debris_plan.get(
				"world_position",
				center_world_position,
			) as Vector2,
			"height": 0,
		})


func _active_random_state() -> int:
	if (
		original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
		and original_crt_random_source.has_method(
			"commit_legacy_crt_random_draws"
		)
	):
		return int(original_crt_random_source.get("legacy_crt_random_state"))
	return random_state


func _commit_random_plan(plan: Dictionary) -> bool:
	var next_state := int(plan.get("next_random_state", random_state))
	var draws := plan.get("random_draws", []) as Array
	if (
		original_crt_random_source != null
		and is_instance_valid(original_crt_random_source)
		and original_crt_random_source.has_method(
			"commit_legacy_crt_random_draws"
		)
	):
		if not bool(original_crt_random_source.call(
			"commit_legacy_crt_random_draws",
			draws,
		)):
			return false
		if int(original_crt_random_source.get("legacy_crt_random_state")) != next_state:
			push_error("爆炸效果的延迟 CRT rand 批次与会话流不连续")
			return false
	else:
		for raw_draw: Variant in draws:
			if raw_draw is Dictionary:
				crt_random_draws.append((raw_draw as Dictionary).duplicate(true))
	random_state = next_state
	return true


func _visual_frames(gfl_index: int) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var visual_value: Variant = visual_catalog.get(gfl_index, {})
	if not visual_value is Dictionary:
		return result
	for raw_frame: Variant in (visual_value as Dictionary).get("frames", []) as Array:
		if raw_frame is Texture2D:
			result.append(raw_frame as Texture2D)
	return result


func _advance_primary() -> void:
	if primary_complete:
		_release_pending_bursts()
		_consume_primary_destructor()
		return
	var audio_group := {
		"action_index": primary_action_index,
		"sound_gfl_index": primary_sound_gfl_index,
		"frame_count": primary_frame_count,
	}
	if ANIMATION_AUDIO_RULES.requests_continuously(audio_group):
		original_animation_audio_requested.emit(
			self,
			primary_sound_gfl_index,
			true,
			0,
		)
	var previous_frame_index := primary_frame_index
	primary_frame_elapsed_ticks += 1
	if primary_frame_elapsed_ticks < primary_frame_hold_ticks:
		return
	primary_frame_elapsed_ticks = 0
	primary_frame_index += 1
	if primary_frame_index >= primary_frame_count:
		primary_frame_index = maxi(primary_frame_count - 1, 0)
		primary_complete = true
	if ANIMATION_AUDIO_RULES.transition_requests_sound(
		audio_group,
		previous_frame_index,
		primary_frame_index,
	):
		original_animation_audio_requested.emit(
			self,
			primary_sound_gfl_index,
			false,
			0,
		)
	if primary_complete:
		_release_pending_bursts()
		_consume_primary_destructor()


func _release_pending_bursts() -> void:
	if pending_bursts_released:
		return
	pending_bursts_released = true
	for burst: Dictionary in pending_bursts:
		_add_burst(
			int(burst.get("effect_family", 11)),
			burst.get("world_position", global_position) as Vector2,
		)


func _consume_primary_destructor() -> void:
	if primary_destructor_consumed:
		return
	if _consume_dynamic_actor_destructor():
		primary_destructor_consumed = true


func _advance_particles() -> void:
	# sub_464A80 walks creation order. A completed entry is replaced with the
	# last pointer and that replacement is processed at the same index, so use
	# the same forward/swap-remove behavior instead of reverse iteration.
	var particle_index := 0
	while particle_index < particles.size():
		var particle := particles[particle_index]
		var audio_group := {
			"action_index": int(particle.get("action_index", -1)),
			"sound_gfl_index": int(particle.get("sound_gfl_index", -1)),
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
		if (
			int(particle.get("completed_loops", 0))
			>= int(particle.get("repeat_count", 1))
		):
			if _consume_dynamic_actor_destructor():
				particles[particle_index] = particles[-1]
				particles.pop_back()
				continue
		particle_index += 1


func _advance_debris_particles() -> void:
	# sub_465930 invokes sub_4642F0 from index zero upward and uses the same
	# swap-with-last removal rule. Bounce draws can choose different branch
	# sites, so preserving this order is observable in the shared CRT trace.
	var debris_index := 0
	while debris_index < debris_particles.size():
		var debris := debris_particles[debris_index]
		_advance_debris_animation(debris)
		var path := debris.get("path", PackedVector2Array()) as PackedVector2Array
		var speed := maxi(int(debris.get("speed", 2)), 2)
		if path.is_empty():
			if _consume_dynamic_actor_destructor():
				debris_particles[debris_index] = debris_particles[-1]
				debris_particles.pop_back()
				continue
			debris_index += 1
			continue
		var path_index := mini(
			int(debris.get("path_index", 0)) + speed,
			path.size() - 1,
		)
		debris["path_index"] = path_index
		debris["world_position"] = path[path_index]
		var flight_tick := maxi(int(debris.get("flight_tick", 0)), 0)
		var flight_tick_limit := maxi(int(path.size() / speed), 1)
		var gravity := float(speed * 2) / float(flight_tick_limit)
		var height := int(
			float(speed * 2 * flight_tick)
			- float(flight_tick * flight_tick) * gravity
		)
		debris["height"] = maxi(height, 0)
		if height > 0 or flight_tick < flight_tick_limit:
			debris["flight_tick"] = flight_tick + 1
			debris_index += 1
			continue
		debris["height"] = 0
		var remaining_flights := (
			int(debris.get("remaining_flights", 1)) - 1
		)
		debris["remaining_flights"] = remaining_flights
		if remaining_flights <= 0:
			if _consume_dynamic_actor_destructor():
				debris_particles[debris_index] = debris_particles[-1]
				debris_particles.pop_back()
				continue
			debris_index += 1
			continue
		var bounce_plan: Dictionary = VISUAL_RULES.build_debris_bounce_plan(
			debris.get("world_position", global_position) as Vector2,
			path.size(),
			speed,
			int(debris.get("angle_degrees", 0)),
			_active_random_state(),
		)
		if bounce_plan.is_empty() or not _commit_random_plan(bounce_plan):
			if _consume_dynamic_actor_destructor():
				debris_particles[debris_index] = debris_particles[-1]
				debris_particles.pop_back()
				continue
			debris_index += 1
			continue
		debris["speed"] = int(bounce_plan.get("speed", speed))
		debris["path"] = bounce_plan.get(
			"path",
			PackedVector2Array(),
		) as PackedVector2Array
		debris["path_index"] = 0
		debris["flight_tick"] = 0
		debris_index += 1


func _advance_debris_animation(debris: Dictionary) -> void:
	var frame_hold_ticks := maxi(
		int(debris.get("frame_hold_ticks", 1)),
		1,
	)
	var frame_elapsed := int(debris.get("frame_elapsed_ticks", 0)) + 1
	if frame_elapsed < frame_hold_ticks:
		debris["frame_elapsed_ticks"] = frame_elapsed
		return
	debris["frame_elapsed_ticks"] = 0
	debris["frame_index"] = posmod(
		int(debris.get("frame_index", 0)) + 1,
		maxi(int(debris.get("frame_count", 1)), 1),
	)


func _consume_dynamic_actor_destructor() -> bool:
	var plan: Dictionary = VISUAL_RULES.build_dynamic_actor_destructor_plan(
		_active_random_state()
	)
	return not plan.is_empty() and _commit_random_plan(plan)


func _allocate_particle_audio_requester_id() -> int:
	var result := next_particle_audio_requester_id
	next_particle_audio_requester_id += 1
	return result


func _draw() -> void:
	for decal: Dictionary in ground_decals:
		var decal_position := decal.get(
			"local_position",
			Vector2.ZERO,
		) as Vector2
		var decal_frames := decal.get("frames", []) as Array
		if not decal_frames.is_empty() and decal_frames[0] is Texture2D:
			draw_texture(
				decal_frames[0] as Texture2D,
				decal_position
					- (decal.get("anchor", Vector2.ZERO) as Vector2),
			)
		else:
			draw_set_transform(decal_position, 0.0, Vector2(1.8, 0.8))
			draw_circle(Vector2.ZERO, 12.0, Color(0.12, 0.10, 0.08, 0.72))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
	for debris: Dictionary in debris_particles:
		var debris_local_position := (
			debris.get("world_position", global_position) as Vector2
		) - global_position - Vector2(0.0, float(debris.get("height", 0)))
		var debris_frames := debris.get("frames", []) as Array
		if not debris_frames.is_empty():
			var debris_frame_value: Variant = debris_frames[
				clampi(
					int(debris.get("frame_index", 0)),
					0,
					debris_frames.size() - 1,
				)
			]
			if debris_frame_value is Texture2D:
				draw_texture(
					debris_frame_value as Texture2D,
					debris_local_position
						- (debris.get("anchor", Vector2.ZERO) as Vector2),
				)
				continue
		draw_rect(
			Rect2(debris_local_position - Vector2(3.0, 3.0), Vector2(6.0, 6.0)),
			Color(0.48, 0.32, 0.18, 0.90),
		)
