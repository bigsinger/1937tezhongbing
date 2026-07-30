class_name CombatProjectile
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const LEGACY_PROJECTILE_RULES: Script = preload(
	"res://scripts/legacy_projectile_rules.gd"
)
const LEGACY_EXPLOSION_RULES: Script = preload(
	"res://scripts/legacy_explosion_rules.gd"
)

signal damage_applied(projectile: Node2D, victim: Node2D, amount: int)
signal impact_created(
	projectile: Node2D,
	world_position: Vector2,
	runtime_actor_type: int,
	original_gfl_index: int,
)
signal exploded(
	projectile: Node2D,
	world_position: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
)
signal explosion_actor_requested(
	projectile: Node2D,
	attacker: Node2D,
	world_position: Vector2,
	runtime_actor_type: int,
	special_bursts: Array[Dictionary],
)
signal resolved(projectile: Node2D)

enum State { FLYING, LANDED, RESOLVED }

const RESOLVED_VISUAL_SECONDS := 1.0 / 60.0

var source: Node2D
var primary_target: Node2D
var weapon_profile: Dictionary = {}
var projectile_profile: Dictionary = {}
var damage_candidates: Array[Node2D] = []
var navigation_grid: Variant
var dynamic_occupancy: Variant
var projectile_visual: Dictionary = {}
var start_world_position := Vector2.ZERO
var destination := Vector2.ZERO
var path_points := PackedVector2Array()
var path_index := 0
var world_step_pixels := 1
var delivery_mode := 0
var arc_tick := 0
var arc_coefficient := 0.0
var physics_tick_accumulator := 0.0
var flight_duration := 0.05
var flight_elapsed := 0.0
var landed_elapsed := 0.0
var visual_height := 0.0
var source_vertical_baseline := 0.0
var state := State.RESOLVED
var resolved_visual_remaining := 0.0
var attack_type := 0
var damage := 0
var visual_groups: Array[Dictionary] = []
var visual_group_index := 0
var visual_frame_index := 0
var visual_frame_elapsed_ticks := 0
var impact_visual: Dictionary = {}


func configure(
	new_source: Node2D,
	new_primary_target: Node2D,
	target_world_position: Vector2,
	new_weapon_profile: Dictionary,
	new_projectile_profile: Dictionary,
	new_damage_candidates: Array[Node2D] = [],
	new_navigation_grid: Variant = null,
	new_dynamic_occupancy: Variant = null,
	new_projectile_visual: Dictionary = {},
	new_start_world_position: Variant = null,
) -> bool:
	if (
		new_source == null
		or new_weapon_profile.is_empty()
		or new_projectile_profile.is_empty()
	):
		return false
	source = new_source
	primary_target = new_primary_target
	weapon_profile = new_weapon_profile.duplicate(true)
	projectile_profile = new_projectile_profile.duplicate(true)
	damage_candidates = new_damage_candidates.duplicate()
	navigation_grid = new_navigation_grid
	dynamic_occupancy = new_dynamic_occupancy
	projectile_visual = new_projectile_visual.duplicate()
	attack_type = int(projectile_profile.get("attack_type", 0))
	delivery_mode = int(projectile_profile.get("delivery_mode", 0))
	world_step_pixels = maxi(
		int(projectile_profile.get("world_step_pixels", 1)),
		1,
	)
	damage = maxi(
		int(
			weapon_profile.get(
				"resolved_projectile_damage",
				projectile_profile.get("direct_damage", 0),
			)
		),
		0,
	)
	var impact_visual_value: Variant = projectile_visual.get(
		"impact_visual",
		{},
	)
	impact_visual = (
		(impact_visual_value as Dictionary).duplicate()
		if impact_visual_value is Dictionary
		else {}
	)
	var launch_offset := Vector2.ZERO
	if new_source.has_method("legacy_projectile_launch_offset"):
		var offset_value: Variant = new_source.call(
			"legacy_projectile_launch_offset"
		)
		if offset_value is Vector2:
			launch_offset = offset_value as Vector2
	if new_source.has_method("legacy_projectile_vertical_baseline"):
		source_vertical_baseline = float(
			new_source.call("legacy_projectile_vertical_baseline")
		)
	else:
		source_vertical_baseline = 0.0
	start_world_position = (
		new_start_world_position as Vector2
		if new_start_world_position is Vector2
		else new_source.global_position + Vector2(launch_offset.x, 0.0)
	)
	destination = target_world_position
	path_points = LEGACY_PROJECTILE_RULES.build_inclusive_bresenham_path(
		start_world_position,
		destination,
	)
	if path_points.is_empty():
		return false
	start_world_position = path_points[0]
	destination = path_points[-1]
	path_index = 0
	arc_tick = 0
	arc_coefficient = (
		LEGACY_PROJECTILE_RULES.original_arc_coefficient(
			path_points.size(),
			world_step_pixels,
		)
		if delivery_mode == 1
		else 0.0
	)
	physics_tick_accumulator = 0.0
	flight_duration = (
		float(
			LEGACY_PROJECTILE_RULES.path_resolution_world_ticks(
				path_points.size(),
				world_step_pixels,
			)
		)
		/ float(LEGACY_PROJECTILE_RULES.WORLD_TICKS_PER_SECOND)
	)
	flight_elapsed = 0.0
	landed_elapsed = 0.0
	visual_height = (
		source_vertical_baseline if delivery_mode in [3, 4] else 0.0
	)
	state = State.FLYING
	resolved_visual_remaining = 0.0
	global_position = start_world_position
	_configure_visual_groups()
	z_index = WORLD_DEPTH.normal_z(global_position.y, 4)
	queue_redraw()
	return true


func advance_simulation(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	if state == State.RESOLVED:
		resolved_visual_remaining = maxf(
			resolved_visual_remaining - safe_delta,
			0.0,
		)
		if resolved_visual_remaining <= 0.0 and is_inside_tree():
			queue_free()
		return
	physics_tick_accumulator += (
		safe_delta * float(LEGACY_PROJECTILE_RULES.WORLD_TICKS_PER_SECOND)
	)
	var world_ticks := floori(physics_tick_accumulator + 0.000001)
	if world_ticks <= 0:
		return
	physics_tick_accumulator -= float(world_ticks)
	advance_world_ticks(world_ticks)


func advance_world_ticks(ticks: int = 1) -> void:
	for unused_tick: int in range(maxi(ticks, 0)):
		if state == State.FLYING:
			_process_original_world_tick()
		elif state == State.LANDED:
			_advance_impact_visual_tick()
		else:
			break
	queue_redraw()


func is_resolved() -> bool:
	return state == State.RESOLVED


func is_blast_projectile() -> bool:
	return int(projectile_profile.get("explosion_actor_type", 0)) > 0


func snapshot_runtime_state() -> Dictionary:
	return {
		"schema_version": 2,
		"path_index": path_index,
		"arc_tick": arc_tick,
		"physics_tick_accumulator": physics_tick_accumulator,
		"flight_elapsed": flight_elapsed,
		"state": state,
		"source_vertical_baseline": source_vertical_baseline,
		"visual_group_index": visual_group_index,
		"visual_frame_index": visual_frame_index,
		"visual_frame_elapsed_ticks": visual_frame_elapsed_ticks,
	}


func restore_runtime_state(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 0)) != 2 or path_points.is_empty():
		return false
	path_index = clampi(
		int(snapshot.get("path_index", 0)),
		0,
		path_points.size() - 1,
	)
	arc_tick = maxi(int(snapshot.get("arc_tick", 0)), 0)
	physics_tick_accumulator = clampf(
		float(snapshot.get("physics_tick_accumulator", 0.0)),
		0.0,
		0.999999,
	)
	flight_elapsed = maxf(float(snapshot.get("flight_elapsed", 0.0)), 0.0)
	state = clampi(
		int(snapshot.get("state", State.FLYING)),
		State.FLYING,
		State.RESOLVED,
	) as State
	if state == State.LANDED:
		_configure_impact_visual_groups()
	source_vertical_baseline = float(snapshot.get(
		"source_vertical_baseline",
		source_vertical_baseline,
	))
	visual_group_index = clampi(
		int(snapshot.get("visual_group_index", visual_group_index)),
		0,
		maxi(visual_groups.size() - 1, 0),
	)
	visual_frame_index = maxi(
		int(snapshot.get("visual_frame_index", 0)),
		0,
	)
	visual_frame_elapsed_ticks = maxi(
		int(snapshot.get("visual_frame_elapsed_ticks", 0)),
		0,
	)
	global_position = path_points[path_index]
	visual_height = _restored_visual_height()
	z_index = WORLD_DEPTH.normal_z(global_position.y, 4)
	queue_redraw()
	return true


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func _process_original_world_tick() -> void:
	if path_points.is_empty():
		_finish_resolution()
		return
	global_position = path_points[path_index]
	if delivery_mode in [0, 3, 4]:
		var victim := _runtime_actor_in_current_cell()
		if victim != null:
			_apply_damage(victim, damage)
			_begin_linear_impact()
			return
		if _current_layer2_cell_is_blocked():
			_begin_linear_impact()
			return
	if path_index == path_points.size() - 1:
		if delivery_mode == 1:
			_detonate_actor_61()
		elif delivery_mode in [0, 3, 4]:
			_begin_linear_impact()
		else:
			_finish_resolution()
		return
	_advance_original_path_visual()
	flight_elapsed += (
		1.0 / float(LEGACY_PROJECTILE_RULES.WORLD_TICKS_PER_SECOND)
	)


func _advance_original_path_visual() -> void:
	path_index = mini(
		path_index + world_step_pixels,
		path_points.size() - 1,
	)
	global_position = path_points[path_index]
	if delivery_mode == 1:
		visual_height = LEGACY_PROJECTILE_RULES.original_arc_height(
			world_step_pixels,
			arc_tick,
			arc_coefficient,
		)
		arc_tick += 1
	elif delivery_mode in [3, 4]:
		visual_height = source_vertical_baseline
	_advance_visual_animation()
	z_index = WORLD_DEPTH.normal_z(global_position.y, 4)


func _runtime_actor_in_current_cell() -> Node2D:
	var current_cell := _world_cell(global_position)
	var occupancy_owner := -1
	if (
		dynamic_occupancy != null
		and dynamic_occupancy.has_method("runtime_movement_owner")
	):
		occupancy_owner = int(
			dynamic_occupancy.call("runtime_movement_owner", current_cell)
		)
	if occupancy_owner >= 0:
		var occupied_candidate := _candidate_by_scene_index(occupancy_owner)
		return (
			occupied_candidate
			if _is_original_direct_hit_candidate(occupied_candidate)
			else null
		)
	var ordered_candidates := damage_candidates.duplicate()
	ordered_candidates.sort_custom(
		func(first: Node2D, second: Node2D) -> bool:
			return _candidate_sort_key(first) < _candidate_sort_key(second)
	)
	for candidate: Node2D in ordered_candidates:
		if (
			_is_original_direct_hit_candidate(candidate)
			and _world_cell(candidate.global_position) == current_cell
		):
			return candidate
	return null


func _current_layer2_cell_is_blocked() -> bool:
	var current_cell := _world_cell(global_position)
	var source_scene_index := _node_scene_index(source)
	if (
		dynamic_occupancy != null
		and dynamic_occupancy.has_method("has_line_of_sight")
	):
		var ignored: Array = []
		if source_scene_index >= 0:
			ignored.append(source_scene_index)
		var cell_center := _cell_to_world(current_cell)
		return not bool(dynamic_occupancy.call(
			"has_line_of_sight",
			cell_center,
			cell_center,
			ignored,
		))
	if (
		navigation_grid != null
		and navigation_grid.has_method("is_line_of_sight_blocked")
	):
		var ignored_lookup: Dictionary = {}
		if source_scene_index >= 0:
			ignored_lookup[source_scene_index] = true
		return bool(navigation_grid.call(
			"is_line_of_sight_blocked",
			current_cell,
			ignored_lookup,
		))
	return false


func _detonate_actor_61() -> void:
	if state == State.RESOLVED:
		return
	var explosion_profile: Dictionary = (
		LEGACY_EXPLOSION_RULES.profile_for_actor(61)
	)
	var blast_damage := int(explosion_profile.get("blast_damage", 0))
	var special_bursts: Array[Dictionary] = []
	for candidate: Node2D in damage_candidates:
		if not _is_alive_damage_candidate(candidate):
			continue
		var offset := candidate.global_position - global_position
		if LEGACY_EXPLOSION_RULES.main_ellipse_contains(offset):
			_apply_damage(candidate, blast_damage)
		for raw_band: Variant in explosion_profile.get(
			"special_damage_bands",
			[],
		) as Array:
			if not raw_band is Dictionary:
				continue
			var band := raw_band as Dictionary
			var runtime_actor_types := band.get(
				"runtime_actor_types",
				[],
			) as Array
			if (
				runtime_actor_types.has(_node_runtime_actor_type(candidate))
				and LEGACY_EXPLOSION_RULES.band_contains(band, offset)
			):
				_apply_damage(candidate, int(band.get("damage", 0)))
				special_bursts.append({
					"effect_family": int(
						band.get("original_visual_effect_type", 11)
					),
					"world_position": candidate.global_position,
				})
	explosion_actor_requested.emit(
		self,
		source,
		global_position,
		61,
		special_bursts,
	)
	exploded.emit(
		self,
		global_position,
		float(explosion_profile["blast_horizontal_radius"]),
		float(explosion_profile["blast_vertical_radius"]),
	)
	_finish_resolution()


func _apply_damage(victim: Node2D, requested_damage: int) -> int:
	if (
		requested_damage <= 0
		or victim == null
		or not victim.has_method("take_damage")
	):
		return 0
	var applied := int(victim.call("take_damage", requested_damage, source))
	if applied > 0:
		damage_applied.emit(self, victim, applied)
	return applied


func _is_original_direct_hit_candidate(candidate: Node2D) -> bool:
	return (
		candidate != source
		and _is_alive_damage_candidate(candidate)
		and _node_runtime_actor_type(candidate) > 0
	)


func _is_alive_damage_candidate(candidate: Node2D) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and candidate.has_method("is_combat_alive")
		and bool(candidate.call("is_combat_alive"))
		and candidate.has_method("take_damage")
	)


func _candidate_by_scene_index(scene_index: int) -> Node2D:
	for candidate: Node2D in damage_candidates:
		if _node_scene_index(candidate) == scene_index:
			return candidate
	return null


func _world_cell(world_position: Vector2) -> Vector2i:
	if navigation_grid != null and navigation_grid.has_method("world_to_cell"):
		return navigation_grid.call("world_to_cell", world_position) as Vector2i
	return LEGACY_PROJECTILE_RULES.world_cell(world_position)


func _cell_to_world(cell: Vector2i) -> Vector2:
	if navigation_grid != null and navigation_grid.has_method("cell_to_world"):
		return navigation_grid.call("cell_to_world", cell) as Vector2
	return Vector2(
		(float(cell.x) + 0.5)
			* float(LEGACY_PROJECTILE_RULES.ORIGINAL_CELL_SIZE.x),
		(float(cell.y) + 0.5)
			* float(LEGACY_PROJECTILE_RULES.ORIGINAL_CELL_SIZE.y),
	)


func _begin_linear_impact() -> void:
	if state != State.FLYING:
		return
	state = State.LANDED
	visual_height = 0.0
	_configure_impact_visual_groups()
	impact_created.emit(
		self,
		global_position,
		int(projectile_profile.get("impact_actor_type", 60)),
		int(projectile_profile.get("impact_gfl_index", 306)),
	)
	if visual_groups.is_empty():
		_finish_resolution()
	queue_redraw()


func _advance_impact_visual_tick() -> void:
	if state != State.LANDED or visual_groups.is_empty():
		_finish_resolution()
		return
	var group := visual_groups[
		clampi(visual_group_index, 0, visual_groups.size() - 1)
	]
	var frames := group.get("frames", []) as Array
	if frames.is_empty():
		_finish_resolution()
		return
	visual_frame_elapsed_ticks += 1
	if (
		visual_frame_elapsed_ticks
		< maxi(int(group.get("frame_hold_ticks", 1)), 1)
	):
		return
	visual_frame_elapsed_ticks = 0
	if visual_frame_index >= frames.size() - 1:
		_finish_resolution()
	else:
		visual_frame_index += 1


func _configure_impact_visual_groups() -> void:
	visual_groups.clear()
	var raw_groups: Variant = impact_visual.get("groups", [])
	if raw_groups is Array:
		for raw_group: Variant in raw_groups as Array:
			if raw_group is Dictionary:
				visual_groups.append((raw_group as Dictionary).duplicate())
	if visual_groups.is_empty():
		var raw_frames: Variant = impact_visual.get("frames", [])
		if raw_frames is Array and not (raw_frames as Array).is_empty():
			visual_groups.append(impact_visual.duplicate())
	visual_group_index = 0
	visual_frame_index = 0
	visual_frame_elapsed_ticks = 0


func _configure_visual_groups() -> void:
	visual_groups.clear()
	var raw_groups: Variant = projectile_visual.get("groups", [])
	if raw_groups is Array:
		for raw_group: Variant in raw_groups as Array:
			if raw_group is Dictionary:
				visual_groups.append((raw_group as Dictionary).duplicate())
	if visual_groups.is_empty():
		var raw_frames: Variant = projectile_visual.get("frames", [])
		if raw_frames is Array and not (raw_frames as Array).is_empty():
			visual_groups.append(projectile_visual.duplicate())
	visual_group_index = _directional_visual_group_index(
		destination - start_world_position
	)
	visual_frame_index = 0
	visual_frame_elapsed_ticks = 0


func _directional_visual_group_index(direction: Vector2) -> int:
	if visual_groups.size() <= 1:
		return 0
	var direction_index := (
		posmod(roundi(direction.angle() / (PI / 4.0)) + 2, 8) + 1
	)
	for group_index: int in range(visual_groups.size()):
		if int(visual_groups[group_index].get("direction_index", 0)) == direction_index:
			return group_index
	return clampi(direction_index - 1, 0, visual_groups.size() - 1)


func _advance_visual_animation() -> void:
	if visual_groups.is_empty():
		return
	var group := visual_groups[
		clampi(visual_group_index, 0, visual_groups.size() - 1)
	]
	var frames := group.get("frames", []) as Array
	if frames.size() <= 1:
		return
	visual_frame_elapsed_ticks += 1
	if (
		visual_frame_elapsed_ticks
		>= maxi(int(group.get("frame_hold_ticks", 1)), 1)
	):
		visual_frame_elapsed_ticks = 0
		visual_frame_index = (visual_frame_index + 1) % frames.size()


func _restored_visual_height() -> float:
	if state == State.LANDED:
		return 0.0
	if delivery_mode == 1 and arc_tick > 0:
		return LEGACY_PROJECTILE_RULES.original_arc_height(
			world_step_pixels,
			arc_tick - 1,
			arc_coefficient,
		)
	return source_vertical_baseline if delivery_mode in [3, 4] else 0.0


func _finish_resolution() -> void:
	if state == State.RESOLVED:
		return
	state = State.RESOLVED
	resolved_visual_remaining = RESOLVED_VISUAL_SECONDS
	resolved.emit(self)
	queue_redraw()


static func _node_scene_index(node: Node) -> int:
	if node == null:
		return -1
	var value: Variant = node.get("scene_index")
	return int(value) if value != null else -1


static func _node_runtime_actor_type(node: Node) -> int:
	if node == null:
		return 0
	var value: Variant = node.get("runtime_actor_type")
	# Asset-free tests may use a generic combatant. An explicit property is
	# required so missing actor-type metadata cannot become a false collision.
	return int(value) if value != null else 0


static func _candidate_sort_key(candidate: Node2D) -> int:
	var scene := _node_scene_index(candidate)
	return scene if scene >= 0 else candidate.get_instance_id()


func _draw() -> void:
	if state == State.RESOLVED:
		return
	if state == State.FLYING and delivery_mode == 0:
		# effect 1 owns no travelling actor or GFL sprite. Only its actor-60
		# impact (effect 8) is visible.
		return
	var draw_position := Vector2(0.0, -visual_height)
	if not visual_groups.is_empty():
		var group := visual_groups[
			clampi(visual_group_index, 0, visual_groups.size() - 1)
		]
		var frames := group.get("frames", []) as Array
		if not frames.is_empty():
			var frame_value: Variant = frames[
				clampi(visual_frame_index, 0, frames.size() - 1)
			]
			if frame_value is Texture2D:
				draw_texture(
					frame_value as Texture2D,
					draw_position
						- (group.get("anchor", Vector2.ZERO) as Vector2),
				)
				return
	# Asset-free fallback keeps tests and fresh source checkouts readable.
	if attack_type == 9:
		draw_circle(draw_position, 5.0, Color(0.20, 0.22, 0.16))
	elif attack_type == 7:
		draw_circle(draw_position, 2.0, Color(0.32, 0.29, 0.24))
	else:
		draw_line(
			draw_position + Vector2(-6.0, 0.0),
			draw_position + Vector2(6.0, 0.0),
			Color(0.86, 0.86, 0.80),
			2.0,
		)
