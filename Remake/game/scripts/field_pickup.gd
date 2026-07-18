class_name FieldPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal collected(pickup: Node2D, collector: Node, payload: Dictionary)

const PICKUP_BEHAVIOR := "field_pickup"

var database_entry_id := 0
var scene_index := -1
var profile_key := ""
var original_display_name := ""
var interaction_radius := 0.0
var entity_metadata: Dictionary = {}
var grant: Dictionary = {}
var consumed := false

var _original_sprite: Sprite2D


func configure(
	profile: Dictionary,
	metadata: Dictionary = {},
	original_texture: Texture2D = null,
) -> bool:
	if (
		String(profile.get("behavior", "")) != PICKUP_BEHAVIOR
		or int(profile.get("database_entry_id", 0)) <= 0
		or float(profile.get("interaction_radius", 0.0)) <= 0.0
		or not profile.get("grant") is Dictionary
	):
		return false
	database_entry_id = int(profile["database_entry_id"])
	profile_key = String(profile.get("key", ""))
	original_display_name = String(profile.get("original_display_name", profile_key))
	interaction_radius = float(profile["interaction_radius"])
	entity_metadata = metadata.duplicate(true)
	grant = (profile["grant"] as Dictionary).duplicate(true)
	scene_index = int(entity_metadata.get("scene_index", -1))
	if entity_metadata.has("x") and entity_metadata.has("y"):
		position = Vector2(float(entity_metadata["x"]), float(entity_metadata["y"]))
	consumed = false
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	_set_original_texture(original_texture)
	queue_redraw()
	return true


func can_collect(collector: Node2D) -> bool:
	return (
		not consumed
		and collector != null
		and is_instance_valid(collector)
		and global_position.distance_squared_to(collector.global_position)
		<= interaction_radius * interaction_radius
	)


func collect(collector: Node2D) -> Dictionary:
	if not can_collect(collector):
		return {}
	consumed = true
	visible = false
	var payload := collection_payload()
	collected.emit(self, collector, payload)
	if is_inside_tree():
		queue_free()
	return payload


func collection_payload() -> Dictionary:
	return {
		"database_entry_id": database_entry_id,
		"scene_index": scene_index,
		"profile_key": profile_key,
		"original_display_name": original_display_name,
		"grant": grant.duplicate(true),
		"entity_metadata": entity_metadata.duplicate(true),
	}


func has_original_texture() -> bool:
	return _original_sprite != null and _original_sprite.texture != null


func _set_original_texture(texture: Texture2D) -> void:
	if _original_sprite == null:
		_original_sprite = Sprite2D.new()
		_original_sprite.name = "OriginalSprite"
		add_child(_original_sprite)
	_original_sprite.texture = texture
	_original_sprite.visible = texture != null


func _draw() -> void:
	if consumed or has_original_texture():
		return
	var color := _fallback_color_for_grant()
	draw_circle(Vector2.ZERO, 11.0, Color(0.06, 0.07, 0.05, 0.88))
	draw_rect(Rect2(-8.0, -6.0, 16.0, 12.0), color, true)
	draw_line(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Color.WHITE, 1.5)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, color.lightened(0.3), 1.5)


func _fallback_color_for_grant() -> Color:
	match String(grant.get("kind", "")):
		"weapon", "ammunition", "active_weapon_ammunition":
			return Color(0.83, 0.64, 0.20)
		"healing":
			return Color(0.34, 0.78, 0.38)
		"deployable":
			return Color(0.46, 0.47, 0.39)
		"mission_item":
			return Color(0.35, 0.65, 0.88)
	return Color(0.72, 0.72, 0.68)
