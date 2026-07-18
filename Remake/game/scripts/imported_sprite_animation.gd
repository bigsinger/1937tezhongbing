class_name ImportedSpriteAnimation
extends RefCounted

const MIN_SCHEMA_VERSION := 1
const MAX_SCHEMA_VERSION := 2
const DIRECTION_GROUP_COUNT := 8
const MAX_FRAME_TICK_THRESHOLD := 2147483646
const ACTION_KEYS: Array[String] = [
	"none",
	"stand",
	"stand_action",
	"walk",
	"run",
	"death",
	"pistol_attack",
	"crawl",
	"active_action",
	"rifle_attack",
	"machine_gun_attack",
	"grenade_attack",
	"broadsword_attack",
	"dagger_attack",
	"dart_attack",
	"slingshot_attack",
	"reserved_1",
	"reserved_2",
	"reserved_3",
	"reserved_4",
]
const DIRECTION_KEYS: Array[String] = [
	"none", "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"
]


static func legacy_group_index_for_direction(direction_index: int) -> int:
	if direction_index < 1 or direction_index > DIRECTION_GROUP_COUNT:
		return -1
	return (direction_index + 2) % DIRECTION_GROUP_COUNT


static func direction_index_for_legacy_group(group_index: int) -> int:
	if group_index < 0 or group_index >= DIRECTION_GROUP_COUNT:
		return 0
	return posmod(group_index - 3, DIRECTION_GROUP_COUNT) + 1


static func sprite_manifest_path(preview_path: String) -> String:
	if preview_path.is_empty():
		return ""
	var preview_name := preview_path.get_file().get_basename()
	if preview_name.length() != 4 or not preview_name.is_valid_int():
		return ""
	var converted_root := preview_path.get_base_dir().get_base_dir()
	return (
		converted_root
		. path_join("sprite-frames")
		. path_join(preview_name)
		. path_join("sprite.json")
		. simplify_path()
	)


static func load_action_groups(preview_path: String, action_key: String) -> Array[Dictionary]:
	if (
		not ACTION_KEYS.has(action_key)
		or action_key in ["none", "reserved_1", "reserved_2", "reserved_3", "reserved_4"]
	):
		return []
	var manifest_path := sprite_manifest_path(preview_path)
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		return []
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return []
	var manifest := json.data as Dictionary
	var schema_version := int(manifest.get("schema_version", 0))
	if schema_version < MIN_SCHEMA_VERSION or schema_version > MAX_SCHEMA_VERSION:
		return []
	var raw_groups: Variant = manifest.get("groups")
	if not raw_groups is Array:
		return []

	var sprite_directory := manifest_path.get_base_dir().simplify_path()
	var groups: Array[Dictionary] = []
	for unused_index in range(DIRECTION_GROUP_COUNT):
		groups.append({})
	var found_count := 0
	for raw_group: Variant in raw_groups as Array:
		if not raw_group is Dictionary:
			return []
		var group := raw_group as Dictionary
		var semantic := group_semantic(group)
		if semantic.is_empty() or str(semantic["action_key"]) != action_key:
			continue
		var direction_index := int(semantic["direction_index"])
		if direction_index < 1 or direction_index > DIRECTION_GROUP_COUNT:
			continue
		var legacy_group_index := legacy_group_index_for_direction(direction_index)
		if not groups[legacy_group_index].is_empty():
			return []
		var primary: Variant = group.get("primary_triplet")
		var raw_frames: Variant = group.get("frames")
		if not primary is Array or (primary as Array).size() != 3 or not raw_frames is Array:
			return []
		var timing := group_timing(group)
		if timing.is_empty():
			return []
		var frames := load_group_atlas(group, sprite_directory)
		if frames.is_empty():
			frames = load_individual_frames(raw_frames as Array, sprite_directory)
		if frames.is_empty():
			return []
		groups[legacy_group_index] = {
			"group_index": int(group.get("group_index", -1)),
			"serial_id": int(semantic["serial_id"]),
			"action_key": str(semantic["action_key"]),
			"direction_key": str(semantic["direction_key"]),
			"anchor": Vector2(float((primary as Array)[0]), float((primary as Array)[2])),
			"frame_tick_threshold": int(timing["frame_tick_threshold"]),
			"frame_hold_ticks": int(timing["frame_hold_ticks"]),
			"frames": frames,
		}
		found_count += 1
	if found_count != DIRECTION_GROUP_COUNT:
		return []
	return groups


static func load_movement_groups(preview_path: String) -> Array[Dictionary]:
	var groups := load_action_groups(preview_path, "run")
	if groups.is_empty():
		groups = load_action_groups(preview_path, "walk")
	return groups


static func load_walk_groups(preview_path: String) -> Array[Dictionary]:
	return load_action_groups(preview_path, "walk")


static func group_semantic(group: Dictionary) -> Dictionary:
	if group.has("serial_id") and group.has("action_key") and group.has("direction_key"):
		var serial_id := int(group["serial_id"])
		var decoded := serial_semantic(serial_id)
		if (
			decoded.is_empty()
			or str(group["action_key"]) != str(decoded["action_key"])
			or str(group["direction_key"]) != str(decoded["direction_key"])
		):
			return {}
		return decoded
	var parameters: Variant = group.get("parameters")
	if not parameters is Array or (parameters as Array).is_empty():
		return {}
	return serial_semantic(int((parameters as Array)[0]))


static func group_timing(group: Dictionary) -> Dictionary:
	var threshold := -1
	var parameters: Variant = group.get("parameters")
	if parameters is Array and (parameters as Array).size() > 2:
		var legacy_threshold: Variant = (parameters as Array)[2]
		if not is_integral_number(legacy_threshold):
			return {}
		threshold = int(legacy_threshold)

	if group.has("frame_tick_threshold"):
		var explicit_threshold: Variant = group["frame_tick_threshold"]
		if not is_integral_number(explicit_threshold):
			return {}
		var parsed_threshold := int(explicit_threshold)
		if threshold >= 0 and parsed_threshold != threshold:
			return {}
		threshold = parsed_threshold

	if threshold < 0 or threshold > MAX_FRAME_TICK_THRESHOLD:
		return {}
	var hold_ticks := threshold + 1
	if group.has("frame_hold_ticks"):
		var explicit_hold: Variant = group["frame_hold_ticks"]
		if not is_integral_number(explicit_hold) or int(explicit_hold) != hold_ticks:
			return {}
	return {
		"frame_tick_threshold": threshold,
		"frame_hold_ticks": hold_ticks,
	}


static func is_integral_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(float(value)) and float(value) == float(int(value))
	return false


static func serial_semantic(serial_id: int) -> Dictionary:
	if serial_id < 0 or serial_id >= ACTION_KEYS.size() * 9:
		return {}
	var action_index := serial_id / 9
	var direction_index := serial_id % 9
	return {
		"serial_id": serial_id,
		"action_index": action_index,
		"action_key": ACTION_KEYS[action_index],
		"direction_index": direction_index,
		"direction_key": DIRECTION_KEYS[direction_index],
	}


static func load_group_atlas(group: Dictionary, sprite_directory: String) -> Array[Texture2D]:
	var raw_atlas: Variant = group.get("atlas")
	if not raw_atlas is Dictionary:
		return []
	var atlas := raw_atlas as Dictionary
	var relative_path: Variant = atlas.get("relative_path")
	if not relative_path is String:
		return []
	var atlas_path := contained_path(sprite_directory, relative_path as String)
	if atlas_path.is_empty() or not FileAccess.file_exists(atlas_path):
		return []
	var frame_width := int(atlas.get("frame_width", 0))
	var frame_height := int(atlas.get("frame_height", 0))
	var columns := int(atlas.get("columns", 0))
	if frame_width <= 0 or frame_height <= 0 or columns <= 0:
		return []
	var image := Image.new()
	if image.load(atlas_path) != OK or image.is_empty():
		return []
	if image.get_width() != frame_width * columns or image.get_height() != frame_height:
		return []
	var atlas_texture := ImageTexture.create_from_image(image)
	var frames: Array[Texture2D] = []
	for column in range(columns):
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = atlas_texture
		frame_texture.region = Rect2(
			float(column * frame_width),
			0.0,
			float(frame_width),
			float(frame_height),
		)
		frame_texture.filter_clip = true
		frames.append(frame_texture)
	return frames


static func load_individual_frames(raw_frames: Array, sprite_directory: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for raw_frame: Variant in raw_frames:
		if not raw_frame is Dictionary:
			return []
		var relative_path: Variant = (raw_frame as Dictionary).get("relative_path")
		if not relative_path is String:
			return []
		var frame_path := contained_path(sprite_directory, relative_path as String)
		if frame_path.is_empty() or not FileAccess.file_exists(frame_path):
			return []
		var image := Image.new()
		if image.load(frame_path) != OK or image.is_empty():
			return []
		frames.append(ImageTexture.create_from_image(image))
	return frames


static func contained_path(root: String, relative_path: String) -> String:
	if relative_path.is_empty() or relative_path.is_absolute_path():
		return ""
	var normalized_root := root.simplify_path().replace("\\", "/").trim_suffix("/") + "/"
	var candidate := root.path_join(relative_path).simplify_path().replace("\\", "/")
	if not candidate.to_lower().begins_with(normalized_root.to_lower()):
		return ""
	return candidate
