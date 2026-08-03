class_name LegacyDoor
extends Sprite2D

const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal state_changed(door: LegacyDoor, open: bool)

var scene_index := -1
var database_entry_id := 0
var original_display_name := "门"
var open_gfl_index := 0
var closed_texture: Texture2D
var open_texture: Texture2D
var closed_anchor := Vector2.ZERO
var open_anchor := Vector2.ZERO
var reference_y := 0.0
var fallback_z_index := 0
var closed_draw_order_profile: Dictionary = {}
var open_draw_order_profile: Dictionary = {}
var row_slice_renderer: Node2D
var sprite_drawn_by_row_slices := false
var is_open := false
var starts_open := false
var locked_open := false
var dynamic_occupancy: RefCounted
var movement_release_cells: Array[Vector2i] = []
var sight_release_cells: Array[Vector2i] = []


func configure(
	entity: Dictionary,
	profile: Dictionary,
	new_closed_texture: Texture2D,
	new_open_texture: Texture2D,
	new_z_index: int,
	new_closed_draw_order_profile: Dictionary = {},
	new_open_draw_order_profile: Dictionary = {},
) -> bool:
	if (
		entity.is_empty()
		or profile.is_empty()
		or new_closed_texture == null
		or new_open_texture == null
	):
		return false
	scene_index = int(entity.get("scene_index", -1))
	database_entry_id = int(entity.get("database_entry_id", 0))
	original_display_name = str(
		entity.get("display_name", profile.get("name", "门"))
	)
	open_gfl_index = int(profile.get("open_gfl_index", 0))
	closed_texture = new_closed_texture
	open_texture = new_open_texture
	closed_anchor = _profile_anchor(
		profile,
		"closed_anchor",
		closed_texture.get_size() * 0.5,
	)
	open_anchor = _profile_anchor(
		profile,
		"open_anchor",
		open_texture.get_size() * 0.5,
	)
	closed_draw_order_profile = new_closed_draw_order_profile.duplicate(true)
	open_draw_order_profile = new_open_draw_order_profile.duplicate(true)
	starts_open = bool(profile.get("starts_open", false))
	locked_open = bool(profile.get("locked_open", starts_open))
	position = Vector2(
		float(entity.get("x", entity.get("reference_x", 0))),
		float(entity.get("y", entity.get("reference_y", 0))),
	)
	reference_y = float(entity.get("reference_y", entity.get("y", position.y)))
	fallback_z_index = new_z_index
	z_index = fallback_z_index
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = true
	is_open = starts_open
	_apply_visual_state()
	return scene_index >= 0


func bind_dynamic_occupancy(occupancy: RefCounted) -> void:
	dynamic_occupancy = occupancy
	movement_release_cells.clear()
	sight_release_cells.clear()
	if dynamic_occupancy != null:
		var source_navigation: Variant = dynamic_occupancy.get("navigation")
		if source_navigation is RefCounted:
			movement_release_cells = _derive_release_cells(
				source_navigation as RefCounted,
				3,
			)
			sight_release_cells = _derive_release_cells(
				source_navigation as RefCounted,
				2,
			)
		if dynamic_occupancy.has_method("register_source_scene_footprint"):
			dynamic_occupancy.call(
				"register_source_scene_footprint",
				scene_index,
				movement_release_cells,
				sight_release_cells,
			)
	_apply_navigation_state()


func open() -> bool:
	return set_open(true)


func set_open(value: bool, emit_change: bool = true) -> bool:
	# Authored open passages have no closed interaction state.  Keeping them
	# permanently open also prevents a restored save from turning a visible
	# opening back into an invisible navigation wall.
	if locked_open and not value:
		_apply_navigation_state()
		return false
	if is_open == value:
		_apply_navigation_state()
		return false
	is_open = value
	_apply_visual_state()
	_apply_navigation_state()
	if emit_change:
		state_changed.emit(self, is_open)
	return true


func contains_parent_point(parent_point: Vector2) -> bool:
	if is_open or closed_texture == null:
		return false
	var local := parent_point - position
	var size := closed_texture.get_size()
	var source_rect := Rect2(-closed_anchor, size)
	var minimum_size := Vector2(maxf(size.x, 48.0), maxf(size.y, 40.0))
	var expansion := (minimum_size - size).max(Vector2.ZERO) * 0.5
	return source_rect.grow_individual(
		expansion.x,
		expansion.y,
		expansion.x,
		expansion.y,
	).has_point(local)


func snapshot() -> Dictionary:
	return {
		"scene_index": scene_index,
		"database_entry_id": database_entry_id,
		"open_gfl_index": open_gfl_index,
		"is_open": is_open,
		"starts_open": starts_open,
		"locked_open": locked_open,
	}


func _apply_navigation_state() -> void:
	if (
		dynamic_occupancy != null
		and dynamic_occupancy.has_method("set_source_scene_disabled")
	):
		dynamic_occupancy.call(
			"set_source_scene_disabled",
			scene_index,
			is_open,
		)


func _apply_visual_state() -> void:
	var active_texture := open_texture if is_open else closed_texture
	var active_anchor := open_anchor if is_open else closed_anchor
	var active_draw_order := (
		open_draw_order_profile
		if is_open
		else closed_draw_order_profile
	)
	sprite_drawn_by_row_slices = false
	if not active_draw_order.is_empty():
		var frame_size: Variant = active_draw_order.get(
			"frame_size",
			Vector2i.ZERO,
		)
		if (
			frame_size is Vector2i
			and frame_size
				== Vector2i(
					int(round(active_texture.get_width())),
					int(round(active_texture.get_height())),
				)
		):
			if row_slice_renderer == null or not is_instance_valid(row_slice_renderer):
				row_slice_renderer = LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
				row_slice_renderer.name = "OriginalRowSlices"
				add_child(row_slice_renderer)
			sprite_drawn_by_row_slices = bool(
				row_slice_renderer.call(
					"configure",
					active_texture,
					active_anchor,
					reference_y,
					active_draw_order.get("draw_order_row_lookup", []),
				)
			)
	if sprite_drawn_by_row_slices:
		texture = null
		return
	if row_slice_renderer != null and is_instance_valid(row_slice_renderer):
		row_slice_renderer.call("clear_visual")
	texture = active_texture
	offset = texture.get_size() * 0.5 - active_anchor
	z_index = fallback_z_index
	var row_lookup: Variant = active_draw_order.get(
		"draw_order_row_lookup",
		[],
	)
	if (
		row_lookup is Array
		and not (row_lookup as Array).is_empty()
		and _rows_are_uniform(row_lookup as Array)
	):
		z_index = WORLD_DEPTH.normal_z(
			reference_y - active_anchor.y + float((row_lookup as Array)[0])
		)


func active_visual_texture() -> Texture2D:
	return open_texture if is_open else closed_texture


static func _rows_are_uniform(rows: Array) -> bool:
	if rows.is_empty():
		return false
	if not rows[0] is int and not rows[0] is float:
		return false
	var first := float(rows[0])
	for row_index: int in range(1, rows.size()):
		if (
			(not rows[row_index] is int and not rows[row_index] is float)
			or float(rows[row_index]) != first
		):
			return false
	return true


func _derive_release_cells(
	source_navigation: RefCounted,
	layer_id: int,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if closed_texture == null or open_texture == null:
		return result
	var closed_image := closed_texture.get_image()
	var open_image := open_texture.get_image()
	if closed_image == null or open_image == null:
		return result
	var cell_size: Vector2i = source_navigation.get("cell_size")
	var dimensions: Vector2i = source_navigation.get("dimensions")
	var closed_top_left := position - closed_anchor
	var closed_bottom_right := closed_top_left + closed_texture.get_size()
	var minimum_cell := Vector2i(
		floori(closed_top_left.x / float(cell_size.x)),
		floori(closed_top_left.y / float(cell_size.y)),
	)
	var maximum_cell := Vector2i(
		floori((closed_bottom_right.x - 0.001) / float(cell_size.x)),
		floori((closed_bottom_right.y - 0.001) / float(cell_size.y)),
	)
	for y: int in range(
		maxi(minimum_cell.y, 0),
		mini(maximum_cell.y, dimensions.y - 1) + 1,
	):
		for x: int in range(
			maxi(minimum_cell.x, 0),
			mini(maximum_cell.x, dimensions.x - 1) + 1,
		):
			var cell := Vector2i(x, y)
			if int(source_navigation.call("source_value", layer_id, cell)) == 0:
				continue
			var closed_pixels := _opaque_pixels_in_cell(
				closed_image,
				closed_anchor,
				cell,
				cell_size,
			)
			if closed_pixels <= 0:
				continue
			var open_pixels := _opaque_pixels_in_cell(
				open_image,
				open_anchor,
				cell,
				cell_size,
			)
			if open_pixels == 0:
				result.append(cell)
	result.sort()
	return result


func _opaque_pixels_in_cell(
	image: Image,
	image_anchor: Vector2,
	cell: Vector2i,
	cell_size: Vector2i,
) -> int:
	var image_top_left := position - image_anchor
	var world_min := Vector2(cell * cell_size)
	var world_max := world_min + Vector2(cell_size)
	var minimum_pixel := Vector2i(
		maxi(floori(world_min.x - image_top_left.x), 0),
		maxi(floori(world_min.y - image_top_left.y), 0),
	)
	var maximum_pixel := Vector2i(
		mini(ceili(world_max.x - image_top_left.x), image.get_width()),
		mini(ceili(world_max.y - image_top_left.y), image.get_height()),
	)
	if minimum_pixel.x >= maximum_pixel.x or minimum_pixel.y >= maximum_pixel.y:
		return 0
	var count := 0
	for y: int in range(minimum_pixel.y, maximum_pixel.y):
		for x: int in range(minimum_pixel.x, maximum_pixel.x):
			if image.get_pixel(x, y).a > 0.1:
				count += 1
	return count


static func _profile_anchor(
	profile: Dictionary,
	key: String,
	fallback: Vector2,
) -> Vector2:
	var value: Variant = profile.get(key)
	if value is Array and (value as Array).size() == 2:
		return Vector2(
			float((value as Array)[0]),
			float((value as Array)[1]),
		)
	return fallback
