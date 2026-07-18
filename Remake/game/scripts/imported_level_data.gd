class_name ImportedLevelData
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_LEVEL_ID := "m000"
const IMPORT_ROOT := "res://../LocalAssets/converted/levels"
const DEFAULT_LEVEL_PATH := IMPORT_ROOT + "/" + DEFAULT_LEVEL_ID + "/level.json"
const NAVIGATION_SCHEMA_VERSION := 1
const NAVIGATION_LAYER_IDS := {
	"line_of_sight_obstacle": 2,
	"movement_obstacle": 3,
	"event_layer": 4,
	"manual_movement_correction": 5,
}


static func load_default() -> Dictionary:
	return load_file(DEFAULT_LEVEL_PATH)


static func level_path(level_id: String) -> String:
	if not is_safe_level_id(level_id):
		return ""
	return "%s/%s/level.json" % [IMPORT_ROOT, level_id]


static func load_level(level_id: String) -> Dictionary:
	return load_file(level_path(level_id))


static func is_safe_level_id(level_id: String) -> bool:
	if level_id.length() != 4 or not level_id.begins_with("m"):
		return false
	return level_id.substr(1).is_valid_int()


static func load_file(resource_path: String = DEFAULT_LEVEL_PATH) -> Dictionary:
	if resource_path.is_empty():
		return {}

	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		return {}

	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}

	return parse_dictionary(json.data as Dictionary)


static func is_valid_dictionary(source: Dictionary) -> bool:
	return not parse_dictionary(source).is_empty()


static func parse_dictionary(source: Dictionary) -> Dictionary:
	var schema_version: Variant = _read_integer(source, "schema_version")
	if schema_version == null or int(schema_version) != SCHEMA_VERSION:
		return {}

	var world_size := _parse_size(source.get("world_size"))
	if world_size.is_empty():
		return {}

	var terrain_image: Variant = _read_string(source, "terrain_image", false)
	if terrain_image == null:
		return {}

	var raw_entities: Variant = source.get("entities")
	if not raw_entities is Array:
		return {}

	var entities: Array[Dictionary] = []
	for raw_entity: Variant in raw_entities as Array:
		if not raw_entity is Dictionary:
			return {}
		var entity := _parse_entity(raw_entity as Dictionary)
		if entity.is_empty():
			return {}
		entities.append(entity)

	var task_anchors: Array[Dictionary] = []
	var raw_task_anchors: Variant = source.get("task_anchors", [])
	if not raw_task_anchors is Array:
		return {}
	for raw_anchor: Variant in raw_task_anchors as Array:
		if not raw_anchor is Dictionary:
			return {}
		var anchor := _parse_task_anchor(raw_anchor as Dictionary)
		if anchor.is_empty():
			return {}
		task_anchors.append(anchor)

	var parsed := {
		"schema_version": SCHEMA_VERSION,
		"world_size": world_size,
		"terrain_image": terrain_image as String,
		"entities": entities,
		"task_anchors": task_anchors,
	}
	if source.has("navigation"):
		var navigation := _parse_navigation(source.get("navigation"))
		if navigation.is_empty():
			return {}
		parsed["navigation"] = navigation
	else:
		parsed["navigation"] = {}
	if source.has("tile_size"):
		var tile_size := _parse_size(source.get("tile_size"))
		if tile_size.is_empty():
			return {}
		parsed["tile_size"] = tile_size
	return parsed


static func _parse_navigation(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source := value as Dictionary
	var schema_version: Variant = _read_integer(source, "schema_version")
	var relative_path: Variant = _read_string(source, "relative_path", false)
	var width: Variant = _read_integer(source, "width")
	var height: Variant = _read_integer(source, "height")
	var cell_width: Variant = _read_integer(source, "cell_width")
	var cell_height: Variant = _read_integer(source, "cell_height")
	if (
		schema_version == null
		or int(schema_version) != NAVIGATION_SCHEMA_VERSION
		or relative_path == null
		or (relative_path as String).is_absolute_path()
		or (relative_path as String).simplify_path().begins_with("..")
		or width == null
		or int(width) <= 0
		or height == null
		or int(height) <= 0
		or cell_width == null
		or int(cell_width) <= 0
		or cell_height == null
		or int(cell_height) <= 0
	):
		return {}
	var layer_ids: Variant = source.get("layer_ids")
	if not layer_ids is Dictionary:
		return {}
	for key: String in NAVIGATION_LAYER_IDS:
		var actual: Variant = _read_integer(layer_ids as Dictionary, key)
		if actual == null or int(actual) != int(NAVIGATION_LAYER_IDS[key]):
			return {}
	return {
		"schema_version": NAVIGATION_SCHEMA_VERSION,
		"relative_path": relative_path as String,
		"width": int(width),
		"height": int(height),
		"cell_width": int(cell_width),
		"cell_height": int(cell_height),
		"layer_ids": NAVIGATION_LAYER_IDS.duplicate(),
	}


static func _parse_task_anchor(source: Dictionary) -> Dictionary:
	var scene_index: Variant = _read_integer(source, "scene_index")
	var database_entry_id: Variant = _read_integer(source, "database_entry_id")
	var x: Variant = _read_integer(source, "x")
	var y: Variant = _read_integer(source, "y")
	var reference_x: Variant = _read_integer(source, "reference_x")
	var reference_y: Variant = _read_integer(source, "reference_y")
	var kind: Variant = _read_string(source, "kind", false)
	if (
		scene_index == null
		or int(scene_index) < 0
		or database_entry_id == null
		or int(database_entry_id) < 0
		or x == null
		or y == null
		or reference_x == null
		or reference_y == null
		or kind == null
	):
		return {}
	return {
		"scene_index": int(scene_index),
		"database_entry_id": int(database_entry_id),
		"kind": kind as String,
		"x": int(x),
		"y": int(y),
		"reference_x": int(reference_x),
		"reference_y": int(reference_y),
	}


static func _parse_entity(source: Dictionary) -> Dictionary:
	var scene_index: Variant = _read_integer(source, "scene_index")
	var database_entry_id: Variant = _read_integer(source, "database_entry_id")
	var x: Variant = _read_integer(source, "x")
	var y: Variant = _read_integer(source, "y")
	var reference_x: Variant = _read_integer(source, "reference_x")
	var reference_y: Variant = _read_integer(source, "reference_y")
	if (
		scene_index == null
		or int(scene_index) < 0
		or database_entry_id == null
		or int(database_entry_id) < 0
		or x == null
		or y == null
		or reference_x == null
		or reference_y == null
	):
		return {}

	var resource_name: Variant = _read_string(source, "resource_name", false)
	var display_name: Variant = _read_string(source, "display_name", true)
	var category_name: Variant = _read_string(source, "category_name", true)
	if resource_name == null or display_name == null or category_name == null:
		return {}

	var sprite_preview: Variant = source.get("sprite_preview")
	if sprite_preview == null:
		sprite_preview = ""
	elif not sprite_preview is String:
		return {}
	var database_header_values: Array[int] = []
	var raw_database_header_values: Variant = source.get("database_header_values", [])
	if not raw_database_header_values is Array:
		return {}
	for raw_header_value: Variant in raw_database_header_values as Array:
		var header_value: Variant = _normalize_integer(raw_header_value)
		if header_value == null:
			return {}
		database_header_values.append(int(header_value))

	var raw_waypoints: Variant = source.get("patrol_waypoints")
	if not raw_waypoints is Array:
		return {}
	var patrol_waypoints: Array[Dictionary] = []
	for raw_waypoint: Variant in raw_waypoints as Array:
		var waypoint := _parse_point(raw_waypoint)
		if waypoint.is_empty():
			return {}
		patrol_waypoints.append(waypoint)
	var faction_id: Variant = _read_optional_integer_alias(source, ["faction_id", "team_id"], 0)
	var direction_index: Variant = _read_optional_integer_alias(source, ["direction_index", "direction"], 1)
	var death_state: Variant = _read_optional_integer_alias(source, ["death_state", "alive_state"], 0)
	var crawl_state: Variant = _read_optional_integer_alias(source, ["crawl_state"], 0)
	var current_hit_points: Variant = _read_optional_integer_alias(
		source, ["current_hit_points", "hit_points"], 0
	)
	var default_attack_type: Variant = _read_optional_integer_alias(
		source, ["default_attack_type", "attack_type"], 0
	)
	if (
		faction_id == null
		or int(faction_id) < 0
		or direction_index == null
		or int(direction_index) < 0
		or death_state == null
		or crawl_state == null
		or current_hit_points == null
		or int(current_hit_points) < 0
		or default_attack_type == null
		or int(default_attack_type) < 0
		or int(default_attack_type) > 11
	):
		return {}
	var special_sensor_mode := false
	for key: String in ["special_sensor_mode", "special_sensor"]:
		if not source.has(key):
			continue
		var raw_special: Variant = source[key]
		if raw_special is bool:
			special_sensor_mode = bool(raw_special)
		elif _normalize_integer(raw_special) != null:
			special_sensor_mode = int(raw_special) != 0
		else:
			return {}
		break
	var patrol_current_waypoint_index := 0
	var patrol_enabled := not patrol_waypoints.is_empty()
	var patrol_persistent_flag := 0
	var patrol_value: Variant = source.get("patrol")
	if patrol_value is Dictionary:
		var patrol := patrol_value as Dictionary
		var raw_patrol_index: Variant = _read_optional_integer_alias(
			patrol, ["current_waypoint_index", "behavior"], 0
		)
		if raw_patrol_index == null or int(raw_patrol_index) < 0:
			return {}
		patrol_current_waypoint_index = int(raw_patrol_index)
		var raw_persistent_flag: Variant = _read_optional_integer_alias(
			patrol, ["persistent_flag"], 0
		)
		if raw_persistent_flag == null:
			return {}
		patrol_persistent_flag = int(raw_persistent_flag)

	return {
		"scene_index": int(scene_index),
		"database_entry_id": int(database_entry_id),
		"resource_name": resource_name as String,
		"display_name": display_name as String,
		"category_name": category_name as String,
		"x": int(x),
		"y": int(y),
		"reference_x": int(reference_x),
		"reference_y": int(reference_y),
		"sprite_preview": sprite_preview as String,
		"database_header_values": database_header_values,
		"patrol_waypoints": patrol_waypoints,
		"patrol_current_waypoint_index": patrol_current_waypoint_index,
		"patrol_enabled": patrol_enabled,
		"patrol_persistent_flag": patrol_persistent_flag,
		"faction_id": int(faction_id),
		"team_id": int(faction_id),
		"direction_index": int(direction_index),
		"death_state": int(death_state),
		"crawl_state": int(crawl_state),
		"current_hit_points": int(current_hit_points),
		"default_attack_type": int(default_attack_type),
		"special_sensor_mode": special_sensor_mode,
	}


static func _parse_size(value: Variant) -> Dictionary:
	var width: Variant
	var height: Variant
	if value is Dictionary:
		width = _read_integer(value as Dictionary, "width")
		height = _read_integer(value as Dictionary, "height")
	elif value is Array and (value as Array).size() == 2:
		width = _normalize_integer((value as Array)[0])
		height = _normalize_integer((value as Array)[1])
	else:
		return {}

	if width == null or height == null or int(width) <= 0 or int(height) <= 0:
		return {}
	return {"width": int(width), "height": int(height)}


static func _parse_point(value: Variant) -> Dictionary:
	var x: Variant
	var y: Variant
	if value is Dictionary:
		x = _read_integer(value as Dictionary, "x")
		y = _read_integer(value as Dictionary, "y")
	elif value is Array and (value as Array).size() == 2:
		x = _normalize_integer((value as Array)[0])
		y = _normalize_integer((value as Array)[1])
	else:
		return {}

	if x == null or y == null:
		return {}
	return {"x": int(x), "y": int(y)}


static func _read_integer(source: Dictionary, key: String) -> Variant:
	if not source.has(key):
		return null
	return _normalize_integer(source[key])


static func _read_optional_integer_alias(
	source: Dictionary, keys: Array, default_value: int
) -> Variant:
	for key_value: Variant in keys:
		var key := str(key_value)
		if source.has(key):
			return _normalize_integer(source[key])
	return default_value


static func _normalize_integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and not is_nan(value) and not is_inf(value) and value == floorf(value):
		return int(value)
	return null


static func _read_string(source: Dictionary, key: String, allow_empty: bool) -> Variant:
	if not source.has(key) or not source[key] is String:
		return null
	var value := source[key] as String
	if not allow_empty and value.is_empty():
		return null
	return value
