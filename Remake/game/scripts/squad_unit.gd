class_name SquadUnit
extends Node2D

const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")

@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = 150.0

var display_name: String = "队员"
var body_color: Color = Color.WHITE
var selected: bool = false
var target_position: Vector2


func configure(new_name: String, color: Color, start_position: Vector2) -> void:
	display_name = new_name
	body_color = color
	position = start_position
	target_position = start_position
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func issue_move(destination: Vector2) -> void:
	target_position = destination
	queue_redraw()


func contains_parent_point(parent_point: Vector2) -> bool:
	return position.distance_squared_to(parent_point) <= 26.0 * 26.0


func _physics_process(delta: float) -> void:
	var next_position: Vector2 = SIMULATION_SCRIPT.advance_towards(
		position, target_position, move_speed, delta
	)
	if next_position != position:
		position = next_position
		queue_redraw()


func _draw() -> void:
	draw_flat_ellipse(Vector2(0.0, 8.0), Vector2(20.0, 10.0), Color(0.0, 0.0, 0.0, 0.35))
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
