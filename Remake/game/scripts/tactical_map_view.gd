class_name TacticalMapView
extends Control

signal world_position_requested(world_position: Vector2)

const MAP_MARGIN := 18.0
const CAMERA_COLOR := Color(0.95, 0.89, 0.53, 0.92)

var terrain_texture: Texture2D
var world_size := Vector2.ONE
var actor_markers: Array[Dictionary] = []
var mission_markers: Array[Dictionary] = []
var camera_world_rect := Rect2()


func configure(
	new_terrain_texture: Texture2D,
	new_world_size: Vector2,
	new_actor_markers: Array[Dictionary],
	new_mission_markers: Array[Dictionary],
	new_camera_world_rect: Rect2,
) -> void:
	terrain_texture = new_terrain_texture
	world_size = new_world_size.max(Vector2.ONE)
	actor_markers = new_actor_markers.duplicate(true)
	mission_markers = new_mission_markers.duplicate(true)
	camera_world_rect = new_camera_world_rect
	queue_redraw()


func update_camera_world_rect(new_camera_world_rect: Rect2) -> void:
	camera_world_rect = new_camera_world_rect
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var map_rect := _map_rect()
	if not map_rect.has_point(mouse_event.position):
		return
	var normalized := (mouse_event.position - map_rect.position) / map_rect.size
	world_position_requested.emit(normalized * world_size)
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.031, 0.027, 0.98), true)
	var map_rect := _map_rect()
	if terrain_texture != null:
		draw_texture_rect(terrain_texture, map_rect, false)
	else:
		draw_rect(map_rect, Color(0.12, 0.16, 0.12), true)
		_draw_fallback_grid(map_rect)
	draw_rect(map_rect, Color(0.70, 0.72, 0.58, 0.82), false, 2.0)

	for marker: Dictionary in mission_markers:
		var point := _world_to_map(marker.get("position", Vector2.ZERO) as Vector2, map_rect)
		var color: Color = marker.get("color", Color(0.95, 0.70, 0.20)) as Color
		var radius := maxf(float(marker.get("radius", 6.0)), 3.0)
		var diamond := PackedVector2Array([
			point + Vector2(0.0, -radius),
			point + Vector2(radius, 0.0),
			point + Vector2(0.0, radius),
			point + Vector2(-radius, 0.0),
		])
		draw_colored_polygon(diamond, color)
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color.WHITE, 1.0)

	for marker: Dictionary in actor_markers:
		var point := _world_to_map(marker.get("position", Vector2.ZERO) as Vector2, map_rect)
		var color: Color = marker.get("color", Color.WHITE) as Color
		var radius := maxf(float(marker.get("radius", 4.0)), 2.0)
		draw_circle(point, radius, color)
		if bool(marker.get("selected", false)):
			draw_arc(point, radius + 3.0, 0.0, TAU, 18, Color.WHITE, 1.5)

	if camera_world_rect.size.x > 0.0 and camera_world_rect.size.y > 0.0:
		var top_left := _world_to_map(camera_world_rect.position, map_rect)
		var bottom_right := _world_to_map(camera_world_rect.end, map_rect)
		var visible_rect := Rect2(top_left, bottom_right - top_left).intersection(map_rect)
		if visible_rect.size.x > 0.0 and visible_rect.size.y > 0.0:
			draw_rect(visible_rect, CAMERA_COLOR, false, 2.0)


func _map_rect() -> Rect2:
	var available := (size - Vector2.ONE * MAP_MARGIN * 2.0).max(Vector2.ONE)
	var scale_factor := minf(available.x / world_size.x, available.y / world_size.y)
	var fitted_size := world_size * maxf(scale_factor, 0.0001)
	return Rect2((size - fitted_size) * 0.5, fitted_size)


func _world_to_map(world_position: Vector2, map_rect: Rect2) -> Vector2:
	var normalized := Vector2(
		clampf(world_position.x / world_size.x, 0.0, 1.0),
		clampf(world_position.y / world_size.y, 0.0, 1.0),
	)
	return map_rect.position + normalized * map_rect.size


func _draw_fallback_grid(map_rect: Rect2) -> void:
	for index: int in range(1, 8):
		var ratio := float(index) / 8.0
		var vertical_x := lerpf(map_rect.position.x, map_rect.end.x, ratio)
		var horizontal_y := lerpf(map_rect.position.y, map_rect.end.y, ratio)
		draw_line(
			Vector2(vertical_x, map_rect.position.y),
			Vector2(vertical_x, map_rect.end.y),
			Color(0.32, 0.38, 0.31, 0.45),
			1.0,
		)
		draw_line(
			Vector2(map_rect.position.x, horizontal_y),
			Vector2(map_rect.end.x, horizontal_y),
			Color(0.32, 0.38, 0.31, 0.45),
			1.0,
		)
