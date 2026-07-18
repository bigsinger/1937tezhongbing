class_name LevelView
extends RefCounted

const DEFAULT_LEVEL_ID := "m000"
const IMPORT_ROOT := "res://../LocalAssets/converted/levels"
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")


static func imported_terrain_path(level_id: String = DEFAULT_LEVEL_ID) -> String:
	if not IMPORTED_LEVEL_DATA.is_safe_level_id(level_id):
		return ""
	return "%s/%s/terrain.png" % [IMPORT_ROOT, level_id]


static func load_imported_terrain(level_id: String = DEFAULT_LEVEL_ID) -> Dictionary:
	var resource_path := imported_terrain_path(level_id)
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		return {}

	var image := Image.new()
	var error := image.load(absolute_path)
	if error != OK or image.is_empty():
		push_warning("无法加载已转换地形：%s（错误 %d）" % [absolute_path, error])
		return {}

	return {
		"path": absolute_path,
		"size": Vector2(image.get_width(), image.get_height()),
		"texture": ImageTexture.create_from_image(image),
	}


static func clamp_camera_center(
	center: Vector2, viewport_size: Vector2, zoom_factor: float, world_size: Vector2
) -> Vector2:
	var safe_zoom := clampf(zoom_factor, MIN_ZOOM, MAX_ZOOM)
	var visible_half := viewport_size / (2.0 * safe_zoom)
	var result := center
	if world_size.x <= visible_half.x * 2.0:
		result.x = world_size.x * 0.5
	else:
		result.x = clampf(result.x, visible_half.x, world_size.x - visible_half.x)
	if world_size.y <= visible_half.y * 2.0:
		result.y = world_size.y * 0.5
	else:
		result.y = clampf(result.y, visible_half.y, world_size.y - visible_half.y)
	return result


static func stepped_zoom(current_zoom: float, zoom_in: bool) -> float:
	var multiplier := 1.15 if zoom_in else 1.0 / 1.15
	return clampf(current_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
