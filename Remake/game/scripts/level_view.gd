class_name LevelView
extends RefCounted

const DEFAULT_LEVEL_ID := "m000"
const IMPORT_ROOT := "res://../LocalAssets/converted/levels"
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const LOCALIZATION_SERVICE_SCRIPT: Script = preload("res://scripts/localization_service.gd")


static func imported_terrain_path(level_id: String = DEFAULT_LEVEL_ID) -> String:
	if not IMPORTED_LEVEL_DATA.is_safe_level_id(level_id):
		return ""
	var level_root := "%s/%s" % [IMPORT_ROOT, level_id]
	# Source conversions keep PNG for forensic reproducibility. Portable builds
	# may carry a pixel-identical lossless WebP copy to avoid shipping the much
	# larger PNG payload. Prefer it when present and preserve the original path
	# contract for development checkouts without local assets.
	var webp_path := "%s/terrain.webp" % level_root
	if FileAccess.file_exists(ProjectSettings.globalize_path(webp_path)):
		return webp_path
	return "%s/terrain.png" % level_root


static func load_imported_terrain(level_id: String = DEFAULT_LEVEL_ID) -> Dictionary:
	var resource_path := imported_terrain_path(level_id)
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(absolute_path):
		return {}

	var image := Image.new()
	var error := image.load(absolute_path)
	if error != OK or image.is_empty():
		push_warning(
			LOCALIZATION_SERVICE_SCRIPT.translate_key("ERROR_TERRAIN_LOAD_FORMAT")
			% [absolute_path, error]
		)
		return {}

	return terrain_from_image(image, absolute_path)


static func terrain_from_image(image: Image, source_path: String = "") -> Dictionary:
	if image == null or image.is_empty():
		return {}
	return {
		"path": source_path,
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
	return zoom_with_step(current_zoom, zoom_in, 0.15)


static func zoom_with_step(current_zoom: float, zoom_in: bool, step: float) -> float:
	var safe_step := clampf(step, 0.05, 0.50)
	var multiplier := 1.0 + safe_step if zoom_in else 1.0 / (1.0 + safe_step)
	return clampf(current_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
