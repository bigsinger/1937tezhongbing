class_name DeveloperWorldDebugOverlay
extends Node2D

const ELLIPSE_SEGMENTS := 64

var source: Node
var debug_enabled := false
var refresh_remaining := 0.0


func configure(new_source: Node) -> void:
	source = new_source
	visible = false
	set_process(false)


func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	visible = value
	set_process(value)
	queue_redraw()


func _process(delta: float) -> void:
	if not debug_enabled:
		return
	refresh_remaining -= maxf(delta, 0.0)
	if refresh_remaining <= 0.0:
		refresh_remaining = 0.10
		queue_redraw()


func _draw() -> void:
	if not debug_enabled or source == null or not source.has_method("debug_world_subjects"):
		return
	var subjects := source.call("debug_world_subjects") as Dictionary
	for raw_actor: Variant in subjects.get("selected_units", []) as Array:
		if raw_actor is Node2D and is_instance_valid(raw_actor):
			_draw_actor_path(raw_actor as Node2D, Color(1.0, 0.83, 0.22, 0.95))
	var enemy: Node2D = subjects.get("enemy") as Node2D
	if enemy == null or not is_instance_valid(enemy):
		return
	_draw_actor_path(enemy, Color(1.0, 0.58, 0.20, 0.94))
	var sense_profile := enemy.get("sense_profile") as Dictionary
	var hearing_radius := float(sense_profile.get(
		"hearing_radius",
		maxf(
			float(sense_profile.get("horizontal_radius", 0.0)),
			float(sense_profile.get("vertical_radius", 0.0)),
		),
	))
	var hearing_vertical := float(
		sense_profile.get("hearing_vertical_radius", hearing_radius * 0.5)
	)
	if hearing_radius > 0.0 and hearing_vertical > 0.0:
		draw_polyline(
			_ellipse_points(enemy.position, hearing_radius, hearing_vertical),
			Color(0.25, 0.90, 1.0, 0.72),
			1.5,
			true,
		)
	var last_known: Vector2 = enemy.get("last_known_target_position") as Vector2
	if not last_known.is_zero_approx():
		draw_line(enemy.position, last_known, Color(1.0, 0.48, 0.18, 0.75), 1.5)
		draw_circle(last_known, 6.0, Color(1.0, 0.48, 0.18, 0.90), false, 1.5)


func _draw_actor_path(actor: Node2D, color: Color) -> void:
	var raw_path: Variant = actor.get("movement_path")
	if not raw_path is PackedVector2Array:
		return
	var path := raw_path as PackedVector2Array
	var index := clampi(int(actor.get("movement_path_index")), 0, path.size())
	var points := PackedVector2Array([actor.position])
	for waypoint_index: int in range(index, path.size()):
		points.append(path[waypoint_index])
	if points.size() >= 2:
		draw_polyline(points, color, 2.0, true)
	for point: Vector2 in points:
		draw_circle(point, 2.5, color)


static func _ellipse_points(
	center: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index: int in range(ELLIPSE_SEGMENTS + 1):
		var angle := TAU * float(index) / float(ELLIPSE_SEGMENTS)
		points.append(
			center + Vector2(cos(angle) * horizontal_radius, sin(angle) * vertical_radius)
		)
	return points
