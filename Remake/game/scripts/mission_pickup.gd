class_name MissionPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

var item_payload: Dictionary = {}
var collected := false
var original_texture: Texture2D
var original_sprite: Sprite2D
var original_actor_type := 0
var original_target_status := 3
var world_item_serial := 0
var original_dynamic_actor_lifecycle := false
var original_factory_random_consumed := false
var original_destructor_random_consumed := false


func configure(
	payload: Dictionary,
	world_position: Vector2,
	texture: Texture2D = null,
) -> void:
	item_payload = payload.duplicate(true)
	position = world_position
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	original_actor_type = int(
		item_payload.get(
			"original_actor_type",
			item_payload.get("item_id", 0)
			if not str(item_payload.get("original_inventory_kind", "")).is_empty()
			else 0,
		)
	)
	original_target_status = int(
		item_payload.get("original_target_status", 3)
	)
	world_item_serial = maxi(
		int(item_payload.get("world_item_serial", 0)),
		0,
	)
	original_dynamic_actor_lifecycle = bool(
		item_payload.get("original_dynamic_actor_lifecycle", false)
	)
	original_factory_random_consumed = bool(
		item_payload.get("original_factory_random_consumed", false)
	)
	original_destructor_random_consumed = bool(
		item_payload.get("original_destructor_random_consumed", false)
	)
	if original_actor_type > 0:
		item_payload["original_actor_type"] = original_actor_type
		item_payload["original_target_status"] = original_target_status
	if world_item_serial > 0:
		item_payload["world_item_serial"] = world_item_serial
	original_texture = texture
	if original_texture != null:
		original_sprite = Sprite2D.new()
		original_sprite.texture = original_texture
		add_child(original_sprite)
	queue_redraw()


func collect() -> Dictionary:
	if collected:
		return {}
	collected = true
	visible = false
	return item_payload.duplicate(true)


func is_available_original_world_item() -> bool:
	return (
		not collected
		and visible
		and original_actor_type > 0
		and original_target_status == 3
	)


func snapshot() -> Dictionary:
	return {
		"x": position.x,
		"y": position.y,
		"payload": item_payload.duplicate(true),
		"original_actor_type": original_actor_type,
		"original_target_status": original_target_status,
		"world_item_serial": world_item_serial,
		"original_dynamic_actor_lifecycle": (
			original_dynamic_actor_lifecycle
		),
		"original_factory_random_consumed": (
			original_factory_random_consumed
		),
		"original_destructor_random_consumed": (
			original_destructor_random_consumed
		),
	}


func _draw() -> void:
	if original_texture != null:
		return
	draw_circle(Vector2.ZERO, 13.0, Color(0.08, 0.06, 0.02, 0.82))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0),
		]),
		Color(0.98, 0.78, 0.22),
	)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(1.0, 0.91, 0.48), 2.0)
