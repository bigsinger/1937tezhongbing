class_name LegacyRowSliceSprite
extends Node2D

## M1937.exe clips normal-queue SPR frames into one 32-pixel strip for every
## RowLookup column (sub_424F10) and stably sorts those strips by:
##
##     reference_y - primary.z + RowLookup[column]
##
## This renderer reproduces that rule with absolute CanvasItem z values. A
## uniform RowLookup remains one draw item; only genuinely different baselines
## are split, which keeps ordinary actors and flat scenery inexpensive.
const COLUMN_WIDTH := 32
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

static var _slice_texture_cache: Dictionary = {}

var _parts: Array[Sprite2D] = []
var _row_lookup: Array[int] = []
var _anchor := Vector2.ZERO
var _reference_y := 0.0
var _reference_offset_from_parent := 0.0
var _z_bias := 0
var _track_parent_reference_y := false
var _active_part_count := 0


func configure(
	texture: Texture2D,
	anchor: Vector2,
	reference_y: float,
	row_lookup_value: Variant,
	z_bias: int = 0,
	track_parent_reference_y: bool = false,
) -> bool:
	var normalized_rows := _normalized_rows(row_lookup_value)
	var texture_width := (
		int(round(texture.get_width()))
		if texture != null
		else 0
	)
	if (
		texture == null
		or normalized_rows.is_empty()
		or texture_width <= (normalized_rows.size() - 1) * COLUMN_WIDTH
		or texture_width > normalized_rows.size() * COLUMN_WIDTH
		or texture.get_height() <= 0.0
	):
		clear_visual()
		return false

	_anchor = anchor
	_reference_y = reference_y
	_row_lookup = normalized_rows
	_z_bias = z_bias
	_track_parent_reference_y = track_parent_reference_y
	if _track_parent_reference_y and get_parent() is Node2D:
		_reference_offset_from_parent = (
			reference_y - (get_parent() as Node2D).global_position.y
		)
	else:
		_reference_offset_from_parent = 0.0
	set_process(_track_parent_reference_y)

	var uniform := _rows_are_uniform(_row_lookup)
	var required_parts := 1 if uniform else _row_lookup.size()
	_ensure_part_count(required_parts)
	_active_part_count = required_parts
	for part_index: int in range(_parts.size()):
		var part := _parts[part_index]
		part.visible = part_index < required_parts
		if not part.visible:
			part.texture = null
			continue
		if uniform:
			part.texture = texture
			part.position = -_anchor
		else:
			var source_x := part_index * COLUMN_WIDTH
			var slice_width := mini(
				COLUMN_WIDTH,
				texture_width - source_x,
			)
			part.texture = _slice_texture(
				texture,
				source_x,
				slice_width,
				int(round(texture.get_height())),
			)
			part.position = Vector2(
				-_anchor.x + float(source_x),
				-_anchor.y,
			)
	_apply_depths()
	return true


func clear_visual() -> void:
	_active_part_count = 0
	_row_lookup.clear()
	_track_parent_reference_y = false
	set_process(false)
	for part: Sprite2D in _parts:
		part.visible = false
		part.texture = null


func update_reference_y(reference_y: float) -> void:
	if is_equal_approx(_reference_y, reference_y):
		return
	_reference_y = reference_y
	_apply_depths()


func active_part_count() -> int:
	return _active_part_count


func active_depth_keys() -> Array[int]:
	var result: Array[int] = []
	for part_index: int in range(_active_part_count):
		result.append(_parts[part_index].z_index)
	return result


func active_part_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for part_index: int in range(_active_part_count):
		result.append(_parts[part_index].position)
	return result


static func clear_texture_cache() -> void:
	_slice_texture_cache.clear()


static func cached_slice_count() -> int:
	return _slice_texture_cache.size()


func _process(_delta: float) -> void:
	if not _track_parent_reference_y or not get_parent() is Node2D:
		return
	update_reference_y(
		(get_parent() as Node2D).global_position.y
		+ _reference_offset_from_parent
	)


func _ensure_part_count(required_parts: int) -> void:
	while _parts.size() < required_parts:
		var part := Sprite2D.new()
		part.name = "RowSlice_%02d" % _parts.size()
		part.centered = false
		part.z_as_relative = false
		part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(part)
		_parts.append(part)


func _apply_depths() -> void:
	if _active_part_count <= 0 or _row_lookup.is_empty():
		return
	if _active_part_count == 1:
		_parts[0].z_index = WORLD_DEPTH.normal_z(
			_reference_y - _anchor.y + float(_row_lookup[0]),
			_z_bias,
		)
		return
	for column: int in range(_active_part_count):
		_parts[column].z_index = WORLD_DEPTH.normal_z(
			_reference_y - _anchor.y + float(_row_lookup[column]),
			_z_bias,
		)


static func _normalized_rows(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for raw_row: Variant in value as Array:
		if not raw_row is int and not raw_row is float:
			return []
		var row_value := float(raw_row)
		if not is_finite(row_value) or row_value != float(int(row_value)):
			return []
		result.append(int(row_value))
	return result


static func _rows_are_uniform(rows: Array[int]) -> bool:
	if rows.size() <= 1:
		return true
	var first := rows[0]
	for row_index: int in range(1, rows.size()):
		if rows[row_index] != first:
			return false
	return true


static func _slice_texture(
	texture: Texture2D,
	source_x: int,
	width: int,
	height: int,
) -> Texture2D:
	var cache_key := "%d:%d:%d:%d" % [
		texture.get_instance_id(),
		source_x,
		width,
		height,
	]
	if _slice_texture_cache.has(cache_key):
		var cached: Variant = _slice_texture_cache[cache_key]
		if cached is Texture2D and is_instance_valid(cached):
			return cached as Texture2D
	var slice := AtlasTexture.new()
	slice.atlas = texture
	slice.region = Rect2(
		float(source_x),
		0.0,
		float(width),
		float(height),
	)
	slice.filter_clip = true
	_slice_texture_cache[cache_key] = slice
	return slice
