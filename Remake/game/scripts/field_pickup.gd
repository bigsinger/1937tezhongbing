class_name FieldPickup
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)

signal collected(pickup: Node2D, collector: Node, payload: Dictionary)

const PICKUP_BEHAVIOR := "field_pickup"
const ORIGINAL_NAVIGATION_CELL_SIZE := Vector2(32.0, 16.0)
const POINTER_HIT_PADDING := 12.0
const MINIMUM_POINTER_RADIUS := 22.0

var database_entry_id := 0
var scene_index := -1
var profile_key := ""
var original_display_name := ""
var interaction_radius := 0.0
var entity_metadata: Dictionary = {}
var grant: Dictionary = {}
var consumed := false

var _original_sprite: Sprite2D
var _row_slice_renderer: Node2D


func configure(
	profile: Dictionary,
	metadata: Dictionary = {},
	original_texture: Texture2D = null,
	draw_order_profile: Dictionary = {},
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
	z_index = WORLD_DEPTH.normal_z(position.y)
	_set_original_texture(original_texture, draw_order_profile)
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


func contains_parent_point(
	parent_point: Vector2,
	padding: float = POINTER_HIT_PADDING,
) -> bool:
	if consumed or not visible:
		return false
	var local_point := parent_point - position
	if _original_sprite != null and _original_sprite.texture != null:
		return _original_sprite.get_rect().grow(maxf(padding, 0.0)).has_point(
			local_point
		)
	var radius := maxf(MINIMUM_POINTER_RADIUS, 16.0 + maxf(padding, 0.0))
	return local_point.length_squared() <= radius * radius


func pointer_distance_squared(parent_point: Vector2) -> float:
	return position.distance_squared_to(parent_point)


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


func _set_original_texture(
	texture: Texture2D,
	draw_order_profile: Dictionary = {},
) -> void:
	if _original_sprite == null:
		_original_sprite = Sprite2D.new()
		_original_sprite.name = "OriginalSprite"
		add_child(_original_sprite)
	_original_sprite.texture = texture
	_original_sprite.visible = texture != null
	if texture != null:
		var anchor := _entity_sprite_anchor(texture)
		_original_sprite.offset = texture.get_size() * 0.5 - anchor
		if _apply_draw_order_profile(
			texture,
			anchor,
			draw_order_profile,
		):
			_original_sprite.visible = false


func _apply_draw_order_profile(
	texture: Texture2D,
	anchor: Vector2,
	draw_order_profile: Dictionary,
) -> bool:
	if draw_order_profile.is_empty():
		return false
	var frame_size: Variant = draw_order_profile.get(
		"frame_size",
		Vector2i.ZERO,
	)
	var row_lookup: Variant = draw_order_profile.get(
		"draw_order_row_lookup",
		[],
	)
	if (
		not frame_size is Vector2i
		or frame_size
			!= Vector2i(
				int(round(texture.get_width())),
				int(round(texture.get_height())),
			)
		or not row_lookup is Array
		or (row_lookup as Array).is_empty()
	):
		return false
	var reference_y := float(
		entity_metadata.get("reference_y", entity_metadata.get("y", position.y))
	)
	if _rows_are_uniform(row_lookup as Array):
		z_index = WORLD_DEPTH.normal_z(
			reference_y - anchor.y + float((row_lookup as Array)[0])
		)
		return false
	if _row_slice_renderer == null or not is_instance_valid(_row_slice_renderer):
		_row_slice_renderer = LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
		_row_slice_renderer.name = "OriginalRowSlices"
		add_child(_row_slice_renderer)
	_row_slice_renderer.visible = true
	return bool(
		_row_slice_renderer.call(
			"configure",
			texture,
			anchor,
			reference_y,
			row_lookup,
		)
	)


static func _rows_are_uniform(rows: Array) -> bool:
	if rows.is_empty():
		return false
	var first: Variant = rows[0]
	if not first is int and not first is float:
		return false
	for row: Variant in rows:
		if (
			(not row is int and not row is float)
			or float(row) != float(first)
		):
			return false
	return true


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
	# Modern fallback parcel: readable as an item without the old circular
	# outline and minus sign that players mistook for a blocked interaction.
	draw_rect(Rect2(-10.0, 3.0, 22.0, 5.0), Color(0.02, 0.02, 0.015, 0.38), true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-9.0, -6.0),
			Vector2(8.0, -8.0),
			Vector2(10.0, 5.0),
			Vector2(-8.0, 7.0),
		]),
		color.darkened(0.22),
	)
	draw_rect(Rect2(-7.0, -5.0, 14.0, 10.0), color, true)
	draw_rect(Rect2(-1.5, -5.0, 3.0, 10.0), color.lightened(0.32), true)


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
