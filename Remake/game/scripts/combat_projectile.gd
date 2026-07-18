class_name CombatProjectile
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal damage_applied(projectile: Node2D, victim: Node2D, amount: int)
signal exploded(projectile: Node2D, world_position: Vector2, horizontal_radius: float, vertical_radius: float)
signal resolved(projectile: Node2D)

enum State { FLYING, LANDED, RESOLVED }

const RESOLVED_VISUAL_SECONDS := 0.12

var source: Node2D
var primary_target: Node2D
var weapon_profile: Dictionary = {}
var projectile_profile: Dictionary = {}
var damage_candidates: Array[Node2D] = []
var start_world_position := Vector2.ZERO
var destination := Vector2.ZERO
var flight_duration := 0.05
var flight_elapsed := 0.0
var landed_elapsed := 0.0
var visual_height := 0.0
var state := State.RESOLVED
var resolved_visual_remaining := 0.0
var attack_type := 0
var damage := 0


func configure(
	new_source: Node2D,
	new_primary_target: Node2D,
	target_world_position: Vector2,
	new_weapon_profile: Dictionary,
	new_projectile_profile: Dictionary,
	new_damage_candidates: Array[Node2D] = [],
) -> bool:
	if new_source == null or new_weapon_profile.is_empty() or new_projectile_profile.is_empty():
		return false
	source = new_source
	primary_target = new_primary_target
	weapon_profile = new_weapon_profile.duplicate(true)
	projectile_profile = new_projectile_profile.duplicate(true)
	damage_candidates = new_damage_candidates.duplicate()
	start_world_position = new_source.global_position
	destination = target_world_position
	global_position = start_world_position
	attack_type = int(weapon_profile.get("attack_type", 0))
	damage = maxi(int(weapon_profile.get("damage", 0)), 0)
	var speed := maxf(float(projectile_profile.get("speed", 1.0)), 1.0)
	flight_duration = maxf(start_world_position.distance_to(destination) / speed, 0.05)
	flight_elapsed = 0.0
	landed_elapsed = 0.0
	visual_height = 0.0
	state = State.FLYING
	resolved_visual_remaining = 0.0
	z_index = WORLD_DEPTH.normal_z(global_position.y, 4)
	queue_redraw()
	return true


func advance_simulation(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	if state == State.RESOLVED:
		resolved_visual_remaining = maxf(resolved_visual_remaining - remaining, 0.0)
		if resolved_visual_remaining <= 0.0 and is_inside_tree():
			queue_free()
		return
	if state == State.FLYING:
		var previous_position := global_position
		var usable := minf(remaining, maxf(flight_duration - flight_elapsed, 0.0))
		flight_elapsed += usable
		remaining -= usable
		var progress := clampf(flight_elapsed / flight_duration, 0.0, 1.0)
		global_position = start_world_position.lerp(destination, progress)
		visual_height = _arc_height_at(progress)
		z_index = WORLD_DEPTH.normal_z(global_position.y, 4)
		if not _has_blast() and _resolve_segment_collision(previous_position, global_position):
			return
		if progress >= 1.0:
			global_position = destination
			visual_height = 0.0
			if _has_blast():
				state = State.LANDED
			else:
				_resolve_direct_arrival()
				return
	if state == State.LANDED:
		landed_elapsed += remaining
		if landed_elapsed >= float(projectile_profile.get("detonation_delay_seconds", 0.0)):
			_detonate()
	queue_redraw()


func is_resolved() -> bool:
	return state == State.RESOLVED


func is_blast_projectile() -> bool:
	return _has_blast()


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func _resolve_segment_collision(from_position: Vector2, to_position: Vector2) -> bool:
	var best_target: Node2D
	var best_distance_from_start := INF
	var collision_radius := float(projectile_profile.get("collision_radius", 8.0))
	for candidate: Node2D in damage_candidates:
		if not _can_directly_hit(candidate):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(
			candidate.global_position, from_position, to_position
		)
		if closest.distance_squared_to(candidate.global_position) > collision_radius * collision_radius:
			continue
		var distance_from_start := from_position.distance_squared_to(closest)
		if distance_from_start < best_distance_from_start:
			best_distance_from_start = distance_from_start
			best_target = candidate
	if best_target == null:
		return false
	_apply_damage(best_target)
	_finish_resolution()
	return true


func _resolve_direct_arrival() -> void:
	var collision_radius := float(projectile_profile.get("collision_radius", 8.0))
	if (
		_can_directly_hit(primary_target)
		and primary_target.global_position.distance_squared_to(destination)
		<= collision_radius * collision_radius
	):
		_apply_damage(primary_target)
	_finish_resolution()


func _detonate() -> void:
	if state == State.RESOLVED:
		return
	var horizontal_radius := float(projectile_profile.get("blast_horizontal_radius", 0.0))
	var vertical_radius := float(projectile_profile.get("blast_vertical_radius", 0.0))
	for candidate: Node2D in damage_candidates:
		if not _can_blast_hit(candidate):
			continue
		var offset := candidate.global_position - global_position
		var normalized_distance := (
			offset.x * offset.x / (horizontal_radius * horizontal_radius)
			+ offset.y * offset.y / (vertical_radius * vertical_radius)
		)
		if normalized_distance <= 1.0:
			_apply_damage(candidate)
	exploded.emit(self, global_position, horizontal_radius, vertical_radius)
	_finish_resolution()


func _apply_damage(victim: Node2D) -> int:
	if damage <= 0 or victim == null or not victim.has_method("take_damage"):
		return 0
	var applied := int(victim.call("take_damage", damage, source))
	if applied > 0:
		damage_applied.emit(self, victim, applied)
	return applied


func _can_directly_hit(candidate: Node2D) -> bool:
	return _is_alive_combatant(candidate) and (
		_factions_are_hostile(_source_faction(), int(candidate.get("faction_id")))
		or candidate.has_method("explosion_payload")
	)


func _can_blast_hit(candidate: Node2D) -> bool:
	if not _is_alive_combatant(candidate):
		return false
	if bool(projectile_profile.get("friendly_fire", false)):
		return true
	return _factions_are_hostile(_source_faction(), int(candidate.get("faction_id")))


func _is_alive_combatant(candidate: Node2D) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and candidate.has_method("is_combat_alive")
		and bool(candidate.call("is_combat_alive"))
		and candidate.has_method("take_damage")
	)


func _source_faction() -> int:
	if source == null or not is_instance_valid(source):
		return 0
	return int(source.get("faction_id"))


func _has_blast() -> bool:
	return (
		float(projectile_profile.get("blast_horizontal_radius", 0.0)) > 0.0
		and float(projectile_profile.get("blast_vertical_radius", 0.0)) > 0.0
	)


func _arc_height_at(progress: float) -> float:
	if String(projectile_profile.get("motion", "linear")) != "arc":
		return 0.0
	return 4.0 * float(projectile_profile.get("arc_height", 0.0)) * progress * (1.0 - progress)


func _finish_resolution() -> void:
	if state == State.RESOLVED:
		return
	state = State.RESOLVED
	resolved_visual_remaining = RESOLVED_VISUAL_SECONDS
	resolved.emit(self)
	queue_redraw()


static func _factions_are_hostile(first_faction: int, second_faction: int) -> bool:
	return (
		(first_faction == 1 and second_faction == 3)
		or (first_faction == 3 and second_faction == 1)
	)


func _draw() -> void:
	if state == State.RESOLVED and _has_blast():
		var horizontal_radius := float(projectile_profile.get("blast_horizontal_radius", 0.0))
		var vertical_radius := float(projectile_profile.get("blast_vertical_radius", 0.0))
		_draw_ellipse(Vector2.ZERO, Vector2(horizontal_radius, vertical_radius), Color(1.0, 0.45, 0.12, 0.28))
		return
	var draw_position := Vector2(0.0, -visual_height)
	if attack_type == 9:
		draw_circle(draw_position, 6.0, Color(0.20, 0.22, 0.16))
		draw_circle(draw_position + Vector2(-2.0, -2.0), 2.0, Color(0.62, 0.54, 0.26))
	elif attack_type == 7:
		draw_circle(draw_position, 3.5, Color(0.32, 0.29, 0.24))
	else:
		draw_line(draw_position + Vector2(-7.0, 0.0), draw_position + Vector2(7.0, 0.0), Color(0.86, 0.86, 0.80), 2.0)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
