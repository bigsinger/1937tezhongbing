class_name SquadUnit
extends Node2D

const BASE_SPRITE_TICK_SECONDS := 0.085
const DEFAULT_REPLAN_BLOCKED_SECONDS := 0.25

@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = 150.0

var display_name: String = "队员"
var body_color: Color = Color.WHITE
var selected: bool = false
var target_position: Vector2
var movement_path := PackedVector2Array()
var movement_path_index := 0
var was_moving := false
var blocked_elapsed := 0.0
var blocked_replan_seconds := DEFAULT_REPLAN_BLOCKED_SECONDS
var is_crawling := false
var is_alive := true
var scene_index := -1
var dynamic_occupancy: RefCounted
var sprite_texture: Texture2D
var sprite_anchor := Vector2.ZERO
var movement_groups: Array[Dictionary] = []
var idle_groups: Array[Dictionary] = []
var animation_group_index := 7
var animation_frame_index := 0
var animation_elapsed := 0.0


func configure(
	new_name: String,
	color: Color,
	start_position: Vector2,
	texture: Texture2D = null,
	new_movement_groups: Array[Dictionary] = [],
	new_idle_groups: Array[Dictionary] = [],
	new_scene_index: int = -1,
	new_dynamic_occupancy: RefCounted = null,
	new_source_reference_position: Variant = null,
) -> void:
	display_name = new_name
	body_color = color
	sprite_texture = texture
	movement_groups = new_movement_groups
	idle_groups = new_idle_groups
	scene_index = new_scene_index
	dynamic_occupancy = new_dynamic_occupancy
	position = start_position
	target_position = start_position
	movement_path.clear()
	movement_path_index = 0
	was_moving = false
	blocked_elapsed = 0.0
	if (
		dynamic_occupancy != null
		and scene_index >= 0
		and not dynamic_occupancy.register_scene(
			scene_index, start_position, new_source_reference_position
		)
	):
		dynamic_occupancy = null
	z_index = clampi(int(position.y) + 1, -4096, 4095)
	if movement_groups.size() >= 8:
		set_animation_group(7)
		apply_idle_frame()
	elif sprite_texture != null:
		sprite_anchor = sprite_texture.get_size() * 0.5
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func issue_move(destination: Vector2) -> void:
	issue_path(PackedVector2Array([destination]))


func issue_path(path: PackedVector2Array) -> void:
	movement_path = path.duplicate()
	movement_path_index = 0
	blocked_elapsed = 0.0
	while (
		movement_path_index < movement_path.size()
		and position.is_equal_approx(movement_path[movement_path_index])
	):
		movement_path_index += 1
	if movement_path_index < movement_path.size():
		target_position = movement_path[-1]
	else:
		target_position = position
	queue_redraw()


func cancel_path() -> void:
	if dynamic_occupancy != null and scene_index >= 0:
		dynamic_occupancy.release_goal(scene_index)
	movement_path.clear()
	movement_path_index = 0
	target_position = position
	blocked_elapsed = 0.0
	_apply_idle_state()
	queue_redraw()


func contains_parent_point(parent_point: Vector2) -> bool:
	return position.distance_squared_to(parent_point) <= 26.0 * 26.0


func _physics_process(delta: float) -> void:
	var previous_position := position
	var next_position := position
	var next_path_index := movement_path_index
	var remaining_distance := maxf(move_speed, 0.0) * maxf(delta, 0.0)
	while next_path_index < movement_path.size() and remaining_distance > 0.0:
		var waypoint := movement_path[next_path_index]
		var distance_to_waypoint := next_position.distance_to(waypoint)
		if distance_to_waypoint <= remaining_distance:
			next_position = waypoint
			remaining_distance -= distance_to_waypoint
			next_path_index += 1
		else:
			next_position = next_position.move_toward(waypoint, remaining_distance)
			remaining_distance = 0.0
	if (
		next_position != position
		and dynamic_occupancy != null
		and scene_index >= 0
		and not dynamic_occupancy.try_relocate(scene_index, next_position)
	):
		blocked_elapsed += maxf(delta, 0.0)
		if blocked_elapsed >= maxf(blocked_replan_seconds, 0.05):
			blocked_elapsed = 0.0
			var replanned: PackedVector2Array = dynamic_occupancy.find_path_for_scene(
				scene_index, position, target_position
			)
			if not replanned.is_empty():
				issue_path(replanned)
		_apply_idle_state()
		return
	position = next_position
	movement_path_index = next_path_index
	blocked_elapsed = 0.0
	var displacement := position - previous_position
	if not displacement.is_zero_approx():
		set_animation_group(direction_group_index(displacement))
		advance_animation(delta)
		was_moving = true
		z_index = clampi(int(position.y) + 1, -4096, 4095)
		queue_redraw()
	else:
		_apply_idle_state()


func _exit_tree() -> void:
	if dynamic_occupancy != null and scene_index >= 0:
		dynamic_occupancy.unregister_scene(scene_index)


func _apply_idle_state() -> void:
	if not was_moving and animation_frame_index == 0:
		return
	was_moving = false
	animation_frame_index = 0
	animation_elapsed = 0.0
	apply_idle_frame()
	queue_redraw()


static func direction_group_index(direction: Vector2) -> int:
	if direction.is_zero_approx():
		return 7
	var octant := roundi(direction.angle() / (PI / 4.0))
	return posmod(octant + 5, 8)


func set_animation_group(group_index: int) -> void:
	if movement_groups.size() < 8:
		return
	var safe_index := clampi(group_index, 0, 7)
	if animation_group_index != safe_index:
		animation_group_index = safe_index
		animation_frame_index = 0
		animation_elapsed = 0.0
	update_animation_frame()


func advance_animation(delta: float) -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.size() <= 1:
		return
	var frame_seconds := animation_frame_seconds(group)
	animation_elapsed += maxf(delta, 0.0)
	while animation_elapsed >= frame_seconds:
		animation_elapsed -= frame_seconds
		animation_frame_index = (animation_frame_index + 1) % frames.size()
	update_animation_frame()


static func animation_frame_seconds(group: Dictionary) -> float:
	return BASE_SPRITE_TICK_SECONDS * maxi(int(group.get("frame_hold_ticks", 1)), 1)


func update_animation_frame() -> void:
	if movement_groups.size() < 8:
		return
	var group := movement_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return
	animation_frame_index = clampi(animation_frame_index, 0, frames.size() - 1)
	sprite_texture = frames[animation_frame_index]
	sprite_anchor = group["anchor"] as Vector2


func apply_idle_frame() -> void:
	if idle_groups.size() < 8:
		update_animation_frame()
		return
	var group := idle_groups[animation_group_index]
	var frames := group["frames"] as Array[Texture2D]
	if frames.is_empty():
		return
	sprite_texture = frames[0]
	sprite_anchor = group["anchor"] as Vector2


func _draw() -> void:
	draw_flat_ellipse(Vector2(0.0, 8.0), Vector2(20.0, 10.0), Color(0.0, 0.0, 0.0, 0.35))
	if sprite_texture != null:
		draw_texture(sprite_texture, -sprite_anchor)
	else:
		draw_circle(Vector2.ZERO, 15.0, body_color)
		draw_circle(Vector2(0.0, -12.0), 8.0, body_color.lightened(0.18))
		draw_line(Vector2(-8.0, 1.0), Vector2(11.0, 1.0), Color(0.13, 0.12, 0.09), 4.0)
	if selected:
		draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 40, Color(0.98, 0.84, 0.25), 3.0)
		if position.distance_squared_to(target_position) > 4.0:
			draw_line(Vector2.ZERO, target_position - position, Color(0.98, 0.84, 0.25, 0.65), 1.5)


func draw_flat_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in range(24):
		var angle: float = TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)
