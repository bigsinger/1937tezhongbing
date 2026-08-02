class_name LegacyCursorPresenter
extends RefCounted

const IMPORTED_SPRITE_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const LEGACY_INPUT_RULES: Script = preload("res://scripts/legacy_input_rules.gd")

const ORIGINAL_CURSOR_GFL_INDEX := 16
const ORIGINAL_CURSOR_RUNTIME_TYPE := 55
const ORIGINAL_CURSOR_STEM := "0016"
const ORIGINAL_CURSOR_RESOURCE_NAME := "mouse.spr"
const ORIGINAL_CURSOR_TICKS_PER_SECOND := 60.0
const LARGE_CURSOR_SCALE := 2.0

var groups_by_serial: Dictionary = {}
var source_manifest_path := ""
var current_serial := -1
var current_frame := -1
var frame_elapsed := 0.0
var applied_custom_cursor := false
var large_cursor_enabled := false
var _scaled_cursor_textures: Dictionary = {}


func load_from_converted_root(converted_root: String) -> bool:
	groups_by_serial.clear()
	source_manifest_path = ""
	current_serial = -1
	current_frame = -1
	frame_elapsed = 0.0
	var manifest_path := (
		converted_root
		. path_join("sprite-frames")
		. path_join(ORIGINAL_CURSOR_STEM)
		. path_join("sprite.json")
		. simplify_path()
	)
	if converted_root.is_empty() or not FileAccess.file_exists(manifest_path):
		return false
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return false
	var manifest := json.data as Dictionary
	var header_values: Variant = manifest.get("header_values")
	if (
		int(manifest.get("gfl_index", -1)) != ORIGINAL_CURSOR_GFL_INDEX
		or str(manifest.get("resource_name", "")) != ORIGINAL_CURSOR_RESOURCE_NAME
		or not header_values is Array
		or (header_values as Array).size() < 3
		or int((header_values as Array)[2]) != ORIGINAL_CURSOR_RUNTIME_TYPE
	):
		return false
	var raw_groups: Variant = manifest.get("groups")
	if not raw_groups is Array:
		return false
	var sprite_directory := manifest_path.get_base_dir().simplify_path()
	for raw_group: Variant in raw_groups as Array:
		if not raw_group is Dictionary:
			groups_by_serial.clear()
			return false
		var group := raw_group as Dictionary
		var semantic: Dictionary = IMPORTED_SPRITE_ANIMATION.group_semantic(group)
		var timing: Dictionary = IMPORTED_SPRITE_ANIMATION.group_timing(group)
		var primary: Variant = group.get("primary_triplet")
		var raw_frames: Variant = group.get("frames")
		if (
			semantic.is_empty()
			or timing.is_empty()
			or not primary is Array
			or (primary as Array).size() != 3
			or not raw_frames is Array
		):
			groups_by_serial.clear()
			return false
		var frames: Array[Texture2D] = (
			IMPORTED_SPRITE_ANIMATION.load_individual_frames(
				raw_frames as Array,
				sprite_directory,
			)
		)
		if frames.is_empty():
			groups_by_serial.clear()
			return false
		var serial_id := int(semantic.get("serial_id", -1))
		if serial_id < 0 or groups_by_serial.has(serial_id):
			groups_by_serial.clear()
			return false
		groups_by_serial[serial_id] = {
			"anchor": Vector2(
				float((primary as Array)[0]),
				float((primary as Array)[2]),
			),
			"frame_hold_ticks": int(timing["frame_hold_ticks"]),
			"frames": frames,
		}
	source_manifest_path = manifest_path
	return (
		groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.NORMAL)
		and groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.MOVE)
		and groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.FORCE_TARGET)
		and groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.BURIAL)
		and groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.SIGHT)
		and groups_by_serial.has(LEGACY_INPUT_RULES.CursorSerial.BLOCKED)
	)


func has_original_assets() -> bool:
	return not groups_by_serial.is_empty()


func available_serial_ids() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in groups_by_serial.keys():
		result.append(int(value))
	result.sort()
	return result


func set_large_cursor(enabled: bool) -> void:
	if large_cursor_enabled == enabled:
		return
	reset()
	large_cursor_enabled = enabled
	_scaled_cursor_textures.clear()


func apply(serial_id: int, delta: float = 0.0) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var group_value: Variant = groups_by_serial.get(serial_id)
	if not group_value is Dictionary:
		_clear_custom_cursor()
		Input.set_default_cursor_shape(
			LEGACY_INPUT_RULES.fallback_cursor_shape(serial_id)
		)
		current_serial = serial_id
		current_frame = -1
		frame_elapsed = 0.0
		return false
	var group := group_value as Dictionary
	var frames := group.get("frames", []) as Array[Texture2D]
	if frames.is_empty():
		return false
	var cursor_changed := false
	if current_serial != serial_id:
		current_serial = serial_id
		current_frame = 0
		frame_elapsed = 0.0
		cursor_changed = true
	else:
		var frame_seconds := (
			float(maxi(int(group.get("frame_hold_ticks", 1)), 1))
			/ ORIGINAL_CURSOR_TICKS_PER_SECOND
		)
		frame_elapsed += maxf(delta, 0.0)
		while frame_elapsed >= frame_seconds:
			frame_elapsed -= frame_seconds
			current_frame = (current_frame + 1) % frames.size()
			cursor_changed = true
	if applied_custom_cursor and not cursor_changed:
		return true
	var safe_frame := clampi(current_frame, 0, frames.size() - 1)
	var source_texture: Texture2D = frames[safe_frame]
	var texture := _cursor_texture(source_texture)
	var cursor_scale := LARGE_CURSOR_SCALE if large_cursor_enabled else 1.0
	var raw_anchor := group.get("anchor", Vector2.ZERO) as Vector2
	var hotspot := Vector2(
		clampf(
			raw_anchor.x * cursor_scale,
			0.0,
			float(maxi(texture.get_width() - 1, 0)),
		),
		clampf(
			raw_anchor.y * cursor_scale,
			0.0,
			float(maxi(texture.get_height() - 1, 0)),
		),
	)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
	applied_custom_cursor = true
	return true


func _cursor_texture(source_texture: Texture2D) -> Texture2D:
	if not large_cursor_enabled:
		return source_texture
	var cache_key := int(source_texture.get_instance_id())
	var cached: Variant = _scaled_cursor_textures.get(cache_key)
	if cached is Texture2D:
		return cached as Texture2D
	var image := source_texture.get_image()
	if image == null or image.is_empty():
		return source_texture
	image.resize(
		maxi(roundi(float(image.get_width()) * LARGE_CURSOR_SCALE), 1),
		maxi(roundi(float(image.get_height()) * LARGE_CURSOR_SCALE), 1),
		Image.INTERPOLATE_NEAREST,
	)
	var scaled := ImageTexture.create_from_image(image)
	_scaled_cursor_textures[cache_key] = scaled
	return scaled


func reset() -> void:
	if DisplayServer.get_name() != "headless":
		_clear_custom_cursor()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	current_serial = -1
	current_frame = -1
	frame_elapsed = 0.0


func _clear_custom_cursor() -> void:
	if not applied_custom_cursor:
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	applied_custom_cursor = false
