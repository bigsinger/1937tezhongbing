class_name LandMine
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal armed(mine: Node2D)
signal triggered(mine: Node2D, target: Node2D)
signal explosion_requested(
	mine: Node2D,
	instigator: Node2D,
	world_position: Vector2,
	damage: int,
	horizontal_radius: float,
	vertical_radius: float,
	source_faction_id: int,
)
signal disarmed(mine: Node2D)

enum State { UNPLACED, ARMING, ARMED, TRIGGERED, RESOLVED, DISARMED }

var state := State.UNPLACED
var owner_actor: Node2D
var faction_id := 0
var arm_delay_seconds := 0.0
var trigger_horizontal_radius := 0.0
var trigger_vertical_radius := 0.0
var detonation_delay_seconds := 0.0
var blast_damage := 0
var blast_horizontal_radius := 0.0
var blast_vertical_radius := 0.0
var resolved_visual_seconds := 0.0
var state_elapsed := 0.0
var trigger_target: Node2D
var potential_targets: Array[Node2D] = []


func configure(
	profile: Dictionary,
	world_position: Vector2,
	new_owner: Node2D = null,
	new_faction_id: int = 3,
) -> bool:
	if (
		String(profile.get("key", "")) != "land_mine"
		or float(profile.get("arm_delay_seconds", 0.0)) <= 0.0
		or float(profile.get("trigger_horizontal_radius", 0.0)) <= 0.0
		or float(profile.get("trigger_vertical_radius", 0.0)) <= 0.0
		or float(profile.get("detonation_delay_seconds", 0.0)) <= 0.0
		or int(profile.get("blast_damage", 0)) <= 0
		or float(profile.get("blast_horizontal_radius", 0.0)) <= 0.0
		or float(profile.get("blast_vertical_radius", 0.0)) <= 0.0
	):
		return false
	position = world_position
	owner_actor = new_owner
	faction_id = new_faction_id
	arm_delay_seconds = float(profile["arm_delay_seconds"])
	trigger_horizontal_radius = float(profile["trigger_horizontal_radius"])
	trigger_vertical_radius = float(profile["trigger_vertical_radius"])
	detonation_delay_seconds = float(profile["detonation_delay_seconds"])
	blast_damage = int(profile["blast_damage"])
	blast_horizontal_radius = float(profile["blast_horizontal_radius"])
	blast_vertical_radius = float(profile["blast_vertical_radius"])
	resolved_visual_seconds = maxf(float(profile.get("resolved_visual_seconds", 0.12)), 0.0)
	state = State.ARMING
	state_elapsed = 0.0
	trigger_target = null
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	queue_redraw()
	return true


func set_potential_targets(candidates: Array[Node2D]) -> void:
	potential_targets = candidates.duplicate()


func is_armed() -> bool:
	return state == State.ARMED


func is_resolved() -> bool:
	return state in [State.RESOLVED, State.DISARMED]


func advance_simulation(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	if state == State.ARMING:
		var arming_remaining := maxf(arm_delay_seconds - state_elapsed, 0.0)
		var arming_step := minf(remaining, arming_remaining)
		state_elapsed += arming_step
		remaining -= arming_step
		if state_elapsed >= arm_delay_seconds:
			state = State.ARMED
			state_elapsed = 0.0
			armed.emit(self)
	if state == State.ARMED:
		var candidate := _nearest_hostile_in_trigger_ellipse()
		if candidate != null:
			_trigger(candidate)
	if state == State.TRIGGERED:
		state_elapsed += remaining
		if state_elapsed >= detonation_delay_seconds:
			_detonate()
	elif state == State.RESOLVED:
		state_elapsed += remaining
		if state_elapsed >= resolved_visual_seconds and is_inside_tree():
			queue_free()
	queue_redraw()


func try_trigger(candidate: Node2D) -> bool:
	if state != State.ARMED or not _is_hostile_alive(candidate):
		return false
	if not _is_inside_trigger_ellipse(candidate.global_position):
		return false
	_trigger(candidate)
	return true


func disarm() -> bool:
	if state not in [State.ARMING, State.ARMED]:
		return false
	state = State.DISARMED
	state_elapsed = 0.0
	disarmed.emit(self)
	visible = false
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
	}


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func _trigger(candidate: Node2D) -> void:
	if state != State.ARMED:
		return
	state = State.TRIGGERED
	state_elapsed = 0.0
	trigger_target = candidate
	triggered.emit(self, candidate)


func _detonate() -> void:
	if state != State.TRIGGERED:
		return
	state = State.RESOLVED
	state_elapsed = 0.0
	explosion_requested.emit(
		self,
		owner_actor,
		global_position,
		blast_damage,
		blast_horizontal_radius,
		blast_vertical_radius,
		faction_id,
	)


func _nearest_hostile_in_trigger_ellipse() -> Node2D:
	var nearest: Node2D
	var nearest_normalized_distance := INF
	for candidate: Node2D in potential_targets:
		if not _is_hostile_alive(candidate):
			continue
		var offset := candidate.global_position - global_position
		var normalized_distance := (
			offset.x * offset.x / (trigger_horizontal_radius * trigger_horizontal_radius)
			+ offset.y * offset.y / (trigger_vertical_radius * trigger_vertical_radius)
		)
		if normalized_distance <= 1.0 and normalized_distance < nearest_normalized_distance:
			nearest = candidate
			nearest_normalized_distance = normalized_distance
	return nearest


func _is_inside_trigger_ellipse(world_position: Vector2) -> bool:
	var offset := world_position - global_position
	return (
		offset.x * offset.x / (trigger_horizontal_radius * trigger_horizontal_radius)
		+ offset.y * offset.y / (trigger_vertical_radius * trigger_vertical_radius)
	) <= 1.0


func _is_hostile_alive(candidate: Node2D) -> bool:
	return (
		candidate != null
		and is_instance_valid(candidate)
		and candidate.has_method("is_combat_alive")
		and bool(candidate.call("is_combat_alive"))
		and _factions_are_hostile(faction_id, int(candidate.get("faction_id")))
	)


static func _factions_are_hostile(first_faction: int, second_faction: int) -> bool:
	return (
		(first_faction == 1 and second_faction == 3)
		or (first_faction == 3 and second_faction == 1)
	)


func _draw() -> void:
	match state:
		State.ARMING:
			draw_circle(Vector2.ZERO, 8.0, Color(0.34, 0.35, 0.29))
			draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, Color(0.85, 0.68, 0.18), 1.5)
		State.ARMED:
			draw_circle(Vector2.ZERO, 8.0, Color(0.26, 0.31, 0.22))
			draw_circle(Vector2.ZERO, 2.0, Color(0.82, 0.10, 0.06))
		State.TRIGGERED:
			draw_circle(Vector2.ZERO, 9.0, Color(0.50, 0.15, 0.07))
			draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 20, Color(1.0, 0.35, 0.12), 2.0)
		State.RESOLVED:
			_draw_ellipse(
				Vector2(blast_horizontal_radius, blast_vertical_radius),
				Color(1.0, 0.43, 0.10, 0.32),
			)


func _draw_ellipse(radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
