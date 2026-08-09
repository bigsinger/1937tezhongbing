class_name NativeContentRuntime
extends RefCounted

const IMPORTED_LEVEL_DATA := preload("res://scripts/imported_level_data.gd")


static func load_entry(entry: Dictionary) -> Dictionary:
	var failure := validate_entry(entry)
	if not failure.is_empty():
		return {"ok": false, "code": failure}
	var level_value: Variant = _read_json(str(entry.get("level_path", "")))
	if not level_value is Dictionary:
		return {"ok": false, "code": "level_json_invalid"}
	var level := IMPORTED_LEVEL_DATA.parse_dictionary(level_value as Dictionary)
	if level.is_empty():
		return {"ok": false, "code": "level_schema_invalid"}
	if (level.get("navigation", {}) as Dictionary).is_empty():
		var navigation_error := _ensure_generated_navigation(
			level,
			str(entry.get("level_path", "")).get_base_dir(),
		)
		if not navigation_error.is_empty():
			return {"ok": false, "code": navigation_error}
	var mission_value: Variant = _read_json(str(entry.get("mission_path", "")))
	if not mission_value is Dictionary or not is_valid_mission(mission_value as Dictionary):
		return {"ok": false, "code": "mission_schema_invalid"}
	var direction: Dictionary = {}
	var direction_path := str(entry.get("direction_path", ""))
	if not direction_path.is_empty():
		var direction_value: Variant = _read_json(direction_path)
		if not direction_value is Dictionary:
			return {"ok": false, "code": "direction_json_invalid"}
		direction = (direction_value as Dictionary).duplicate(true)
	var terrain_path := str(entry.get("terrain_path", ""))
	var terrain_image: Image
	if not terrain_path.is_empty():
		terrain_image = Image.new()
		if terrain_image.load(terrain_path) != OK or terrain_image.is_empty():
			return {"ok": false, "code": "terrain_image_invalid"}
	else:
		var size := level.get("world_size", {}) as Dictionary
		terrain_image = create_synthetic_terrain(
			int(size.get("width", 1)),
			int(size.get("height", 1)),
		)
	return {
		"ok": true,
		"entry": entry.duplicate(true),
		"level": level,
		"mission": (mission_value as Dictionary).duplicate(true),
		"direction": direction,
		"terrain_image": terrain_image,
	}


static func validate_entry(entry: Dictionary) -> String:
	for key: String in ["id", "local_id", "pack_id", "content_identity", "root", "level_path", "mission_path"]:
		if str(entry.get(key, "")).is_empty():
			return "entry_%s_missing" % key
	var root := str(entry.get("root", "")).simplify_path().trim_suffix("/")
	var prefix := root + "/"
	for key: String in ["level_path", "mission_path", "terrain_path", "direction_path"]:
		var path := str(entry.get(key, ""))
		if path.is_empty() and key in ["terrain_path", "direction_path"]:
			continue
		var simplified := path.simplify_path()
		if not simplified.begins_with(prefix) or not FileAccess.file_exists(simplified):
			return "entry_%s_unsafe" % key
	return ""


static func is_valid_mission(mission: Dictionary) -> bool:
	if int(mission.get("schema_version", 0)) != 1:
		return false
	if (
		str(mission.get("id", "")).is_empty()
		or int(mission.get("number", 0)) <= 0
		or str(mission.get("title", "")).is_empty()
		or not mission.get("objectives", []) is Array
		or not mission.get("failure_conditions", []) is Array
	):
		return false
	var ids: Dictionary = {}
	for value: Variant in mission.get("objectives", []) as Array:
		if not value is Dictionary:
			return false
		var objective := value as Dictionary
		var objective_id := str(objective.get("id", ""))
		var condition: Variant = objective.get("condition")
		if (
			objective_id.is_empty() or ids.has(objective_id)
			or not objective.get("required", false) is bool
			or not condition is Dictionary
			or str((condition as Dictionary).get("event", "")).is_empty()
			or int((condition as Dictionary).get("required_count", 0)) <= 0
		):
			return false
		ids[objective_id] = true
	return true


static func create_synthetic_terrain(width: int, height: int) -> Image:
	var safe_width := clampi(width, 1, 4096)
	var safe_height := clampi(height, 1, 4096)
	var image := Image.create(safe_width, safe_height, false, Image.FORMAT_RGBA8)
	image.fill(Color("#59664b"))
	# A sparse checker gives a new package immediate spatial orientation without
	# importing any original or copyrighted texture.
	for y: int in range(0, safe_height, 32):
		for x: int in range(0, safe_width, 32):
			if ((x / 32) as int + (y / 32) as int) % 2 == 0:
				image.fill_rect(
					Rect2i(x, y, mini(32, safe_width - x), mini(32, safe_height - y)),
					Color("#526046"),
				)
	return image


static func _ensure_generated_navigation(level: Dictionary, level_root: String) -> String:
	var world := level.get("world_size", {}) as Dictionary
	var tile := level.get("tile_size", {}) as Dictionary
	var cell_width := int(tile.get("width", 32))
	var cell_height := int(tile.get("height", 16))
	var world_width := int(world.get("width", 0))
	var world_height := int(world.get("height", 0))
	if (
		cell_width <= 0 or cell_height <= 0 or world_width <= 0 or world_height <= 0
		or world_width % cell_width != 0 or world_height % cell_height != 0
	):
		return "generated_navigation_dimensions_invalid"
	var width: int = int(world_width / cell_width)
	var height: int = int(world_height / cell_height)
	var path := level_root.path_join("generated-navigation.bin")
	if not FileAccess.file_exists(path):
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			return "generated_navigation_write_failed"
		output.big_endian = false
		# Keep the trailing NUL in the binary header without embedding a NUL escape
		# in the GDScript source. Godot 4.7 rejects such source strings while parsing.
		output.store_buffer(PackedByteArray([77, 51, 55, 78, 65, 86, 49, 0]))
		for header_value: int in [1, width, height, cell_width, cell_height, 4]:
			output.store_32(header_value)
		var cell_count := width * height
		for layer_id: int in [2, 3, 4, 5]:
			output.store_32(layer_id)
			for _cell_index: int in range(cell_count):
				output.store_32(0)
		output.close()
	level["navigation"] = {
		"schema_version": 1,
		"relative_path": path.get_file(),
		"width": width,
		"height": height,
		"cell_width": cell_width,
		"cell_height": cell_height,
		"layer_ids": {
			"line_of_sight_obstacle": 2,
			"movement_obstacle": 3,
			"event_layer": 4,
			"manual_movement_correction": 5,
		},
	}
	return ""


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
