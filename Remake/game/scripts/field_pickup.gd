class_name FieldPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal collected(pickup: Node2D, collector: Node, payload: Dictionary)

const PICKUP_BEHAVIOR := "field_pickup"
const ORIGINAL_NAVIGATION_CELL_SIZE := Vector2(32.0, 16.0)

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
	if consumed or collector == null or not is_instance_valid(collector):
		return false
	# sub_456AB0 is reached once the collector and target are at most one
	# original 32x16 navigation cell apart on each axis. Preserve that
	# anisotropic rule instead of approximating it with a circular radius.
	var collector_cell := Vector2i(
		floori(collector.global_position.x / ORIGINAL_NAVIGATION_CELL_SIZE.x),
		floori(collector.global_position.y / ORIGINAL_NAVIGATION_CELL_SIZE.y),
	)
	var pickup_cell := Vector2i(
		floori(global_position.x / ORIGINAL_NAVIGATION_CELL_SIZE.x),
		floori(global_position.y / ORIGINAL_NAVIGATION_CELL_SIZE.y),
	)
	var cell_delta := (collector_cell - pickup_cell).abs()
	return cell_delta.x <= 1 and cell_delta.y <= 1


func contains_parent_point(parent_point: Vector2) -> bool:
	if consumed or not visible:
		return false
	var local_point := parent_point - position
	if _original_sprite != null and _original_sprite.texture != null:
		return _original_sprite.get_rect().has_point(local_point)
	return local_point.length_squared() <= 16.0 * 16.0


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
	if texture != null:
		_original_sprite.offset = (
			texture.get_size() * 0.5
			- _entity_sprite_anchor(texture)
		)


func _entity_sprite_anchor(texture: Texture2D) -> Vector2:
	var value: Variant = entity_metadata.get("sprite_anchor", {})
	if value is Dictionary:
		var anchor := value as Dictionary
		if anchor.has("x") and anchor.has("y"):
			return Vector2(float(anchor["x"]), float(anchor["y"]))
	return texture.get_size() * 0.5


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
		"original_inventory_item":
			return (
				Color(0.83, 0.64, 0.20)
				if String(grant.get("container", "")) == "weapon"
				else Color(0.35, 0.65, 0.88)
			)
		"weapon", "ammunition", "active_weapon_ammunition":
			return Color(0.83, 0.64, 0.20)
		"healing":
			return Color(0.34, 0.78, 0.38)
		"deployable":
			return Color(0.46, 0.47, 0.39)
		"mission_item":
			return Color(0.35, 0.65, 0.88)
	return Color(0.72, 0.72, 0.68)
