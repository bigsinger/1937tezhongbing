class_name MissionPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

var item_payload: Dictionary = {}
var collected := false


func configure(payload: Dictionary, world_position: Vector2) -> void:
	item_payload = payload.duplicate(true)
	position = world_position
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	queue_redraw()


func collect() -> Dictionary:
	if collected:
		return {}
	collected = true
	visible = false
	return item_payload.duplicate(true)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 13.0, Color(0.08, 0.06, 0.02, 0.82))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0),
		]),
		Color(0.98, 0.78, 0.22),
	)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(1.0, 0.91, 0.48), 2.0)
