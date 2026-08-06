extends SceneTree

# Release-only, lossless content compaction. The source conversion under
# Remake/LocalAssets is deliberately never changed: Build-Playable invokes this
# script only after it has created an isolated Copy-mode payload.

const TERRAIN_PNG := "terrain.png"
const TERRAIN_WEBP := "terrain.webp"
const CONVERSION_ONLY_MANIFESTS: Array[String] = [
	"asset-manifest.json",
	"media-transcode-manifest.json",
]


func _initialize() -> void:
	var content_root := ""
	var expected_level_count := 12
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--content-root="):
			content_root = argument.trim_prefix("--content-root=")
		elif argument.begins_with("--expected-level-count="):
			expected_level_count = int(
				argument.trim_prefix("--expected-level-count=")
			)
	if content_root.is_empty() or expected_level_count <= 0:
		printerr(
			"usage: --content-root=<copied converted root> "
			+ "--expected-level-count=<positive count>"
		)
		quit(2)
		return
	var expected_level_ids: Array[String] = []
	for level_index: int in range(expected_level_count):
		expected_level_ids.append("m%03d" % level_index)
	var result := optimize_content(content_root, expected_level_ids)
	if not bool(result.get("ok", false)):
		printerr(JSON.stringify(result, "  "))
		quit(3)
		return
	print(JSON.stringify(result, "  "))
	quit(0)


static func optimize_content(
	content_root: String,
	expected_level_ids: Array[String],
) -> Dictionary:
	var root := content_root.simplify_path().replace("\\", "/").trim_suffix("/")
	var errors: Array[String] = []
	var result := {
		"ok": false,
		"profile": "lossless-portable-v1",
		"content_root": root,
		"bytes_before": 0,
		"bytes_after": 0,
		"terrain_png_bytes": 0,
		"terrain_webp_bytes": 0,
		"terrain_count": 0,
		"preview_files_removed": 0,
		"individual_frames_removed": 0,
		"conversion_manifests_removed": 0,
		"errors": errors,
	}
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		errors.append("content root is missing")
		return result
	var levels_root := _contained_path(root, "levels")
	var frames_root := _contained_path(root, "sprite-frames")
	var previews_root := _contained_path(root, "sprites")
	if (
		levels_root.is_empty()
		or frames_root.is_empty()
		or previews_root.is_empty()
		or not DirAccess.dir_exists_absolute(levels_root)
		or not DirAccess.dir_exists_absolute(frames_root)
		or not DirAccess.dir_exists_absolute(previews_root)
	):
		errors.append("required converted content directories are missing")
		return result
	result["bytes_before"] = _directory_size(root)

	var atlas_validation := _validate_atlas_coverage(frames_root)
	if not bool(atlas_validation.get("ok", false)):
		errors.append_array(atlas_validation.get("errors", []) as Array[String])
		return result
	var frame_paths := atlas_validation.get("frame_paths", []) as Array[String]
	var preview_validation := _validate_preview_fallbacks(
		previews_root,
		frames_root,
	)
	if not bool(preview_validation.get("ok", false)):
		errors.append_array(preview_validation.get("errors", []) as Array[String])
		return result
	var preview_paths := preview_validation.get("preview_paths", []) as Array[String]

	var terrain_plans: Array[Dictionary] = []
	for level_id: String in expected_level_ids:
		var plan := _stage_terrain(levels_root, level_id)
		if not bool(plan.get("ok", false)):
			errors.append(str(plan.get("error", "terrain staging failed")))
			_cleanup_staged_terrain(terrain_plans)
			return result
		terrain_plans.append(plan)

	# Every destructive action below targets an exact path returned by a prior
	# containment check and follows complete atlas/pixel validation. A failed
	# build is disposable, while the source conversion is outside this root.
	for plan: Dictionary in terrain_plans:
		var commit_error := _commit_terrain(plan)
		if not commit_error.is_empty():
			errors.append(commit_error)
			return result
		result["terrain_png_bytes"] = (
			int(result["terrain_png_bytes"]) + int(plan["png_bytes"])
		)
		result["terrain_webp_bytes"] = (
			int(result["terrain_webp_bytes"]) + int(plan["webp_bytes"])
		)
		result["terrain_count"] = int(result["terrain_count"]) + 1

	for frame_path: String in frame_paths:
		if FileAccess.file_exists(frame_path):
			var remove_error := DirAccess.remove_absolute(frame_path)
			if remove_error != OK:
				errors.append("cannot remove individual frame: %s" % frame_path)
				return result
			result["individual_frames_removed"] = (
				int(result["individual_frames_removed"]) + 1
			)
	for preview_path: String in preview_paths:
		if FileAccess.file_exists(preview_path):
			var remove_error := DirAccess.remove_absolute(preview_path)
			if remove_error != OK:
				errors.append("cannot remove preview duplicate: %s" % preview_path)
				return result
			result["preview_files_removed"] = (
				int(result["preview_files_removed"]) + 1
			)
	if DirAccess.get_files_at(previews_root).is_empty():
		DirAccess.remove_absolute(previews_root)

	for manifest_name: String in CONVERSION_ONLY_MANIFESTS:
		var manifest_path := _contained_path(root, manifest_name)
		if not manifest_path.is_empty() and FileAccess.file_exists(manifest_path):
			if DirAccess.remove_absolute(manifest_path) != OK:
				errors.append("cannot remove conversion manifest: %s" % manifest_path)
				return result
			result["conversion_manifests_removed"] = (
				int(result["conversion_manifests_removed"]) + 1
			)

	result["bytes_after"] = _directory_size(root)
	result["ok"] = errors.is_empty()
	return result


static func _validate_atlas_coverage(frames_root: String) -> Dictionary:
	var errors: Array[String] = []
	var frame_paths: Array[String] = []
	var sprite_directories := DirAccess.get_directories_at(frames_root)
	sprite_directories.sort()
	if sprite_directories.is_empty():
		errors.append("sprite frame catalog is empty")
	for sprite_name: String in sprite_directories:
		if sprite_name.length() != 4 or not sprite_name.is_valid_int():
			continue
		var sprite_root := _contained_path(frames_root, sprite_name)
		var manifest_path := _contained_path(sprite_root, "sprite.json")
		var manifest := _load_json_dictionary(manifest_path)
		if manifest.is_empty():
			errors.append("sprite manifest cannot be loaded: %s" % sprite_name)
			continue
		var groups_value: Variant = manifest.get("groups", [])
		if not groups_value is Array or (groups_value as Array).is_empty():
			errors.append("sprite manifest has no groups: %s" % sprite_name)
			continue
		for group_value: Variant in groups_value as Array:
			if not group_value is Dictionary:
				errors.append("sprite group is invalid: %s" % sprite_name)
				continue
			var group := group_value as Dictionary
			var group_index := int(group.get("group_index", -1))
			var frames_value: Variant = group.get("frames", [])
			var atlas_value: Variant = group.get("atlas", {})
			if (
				not frames_value is Array
				or (frames_value as Array).is_empty()
				or not atlas_value is Dictionary
			):
				errors.append(
					"sprite %s group %d lacks frame/atlas metadata"
					% [sprite_name, group_index]
				)
				continue
			var frames := frames_value as Array
			var atlas := atlas_value as Dictionary
			var atlas_path := _contained_path(
				sprite_root,
				str(atlas.get("relative_path", "")),
			)
			var frame_width := int(atlas.get("frame_width", 0))
			var frame_height := int(atlas.get("frame_height", 0))
			if (
				atlas_path.is_empty()
				or not FileAccess.file_exists(atlas_path)
				or frame_width <= 0
				or frame_height <= 0
				or int(atlas.get("columns", 0)) != frames.size()
				or int(atlas.get("rows", 0)) != 1
				or int(atlas.get("width", 0)) != frame_width * frames.size()
				or int(atlas.get("height", 0)) != frame_height
			):
				errors.append(
					"sprite %s group %d has no complete atlas"
					% [sprite_name, group_index]
				)
				continue
			for frame_value: Variant in frames:
				if not frame_value is Dictionary:
					errors.append(
						"sprite %s group %d has invalid frame metadata"
						% [sprite_name, group_index]
					)
					continue
				var frame_path := _contained_path(
					sprite_root,
					str((frame_value as Dictionary).get("relative_path", "")),
				)
				if frame_path.is_empty() or not FileAccess.file_exists(frame_path):
					errors.append(
						"sprite %s group %d individual frame is missing"
						% [sprite_name, group_index]
					)
					continue
				frame_paths.append(frame_path)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"frame_paths": frame_paths,
	}


static func _validate_preview_fallbacks(
	previews_root: String,
	frames_root: String,
) -> Dictionary:
	var errors: Array[String] = []
	var preview_paths: Array[String] = []
	var preview_files := DirAccess.get_files_at(previews_root)
	preview_files.sort()
	for preview_name: String in preview_files:
		if preview_name.get_extension().to_lower() != "png":
			continue
		var stem := preview_name.get_basename()
		if stem.length() != 4 or not stem.is_valid_int():
			errors.append("unexpected sprite preview name: %s" % preview_name)
			continue
		var preview_path := _contained_path(previews_root, preview_name)
		var sprite_root := _contained_path(frames_root, stem)
		var manifest := _load_json_dictionary(
			_contained_path(sprite_root, "sprite.json")
		)
		var group_zero: Dictionary = {}
		for group_value: Variant in manifest.get("groups", []) as Array:
			if (
				group_value is Dictionary
				and int((group_value as Dictionary).get("group_index", -1)) == 0
			):
				group_zero = group_value as Dictionary
				break
		var atlas := group_zero.get("atlas", {}) as Dictionary
		var atlas_path := _contained_path(
			sprite_root,
			str(atlas.get("relative_path", "")),
		)
		var preview_image := Image.new()
		var atlas_image := Image.new()
		if (
			preview_path.is_empty()
			or atlas_path.is_empty()
			or preview_image.load(preview_path) != OK
			or atlas_image.load(atlas_path) != OK
			or preview_image.is_empty()
			or atlas_image.is_empty()
		):
			errors.append("sprite preview/atlas cannot be decoded: %s" % stem)
			continue
		var frame_width := int(atlas.get("frame_width", 0))
		var frame_height := int(atlas.get("frame_height", 0))
		if (
			preview_image.get_size() != Vector2i(frame_width, frame_height)
			or atlas_image.get_width() < frame_width
			or atlas_image.get_height() < frame_height
		):
			errors.append("sprite preview dimensions do not match atlas: %s" % stem)
			continue
		var atlas_preview := atlas_image.get_region(
			Rect2i(0, 0, frame_width, frame_height)
		)
		if not _images_are_pixel_identical(preview_image, atlas_preview):
			errors.append("sprite preview is not atlas frame zero: %s" % stem)
			continue
		preview_paths.append(preview_path)
	return {
		"ok": errors.is_empty() and not preview_paths.is_empty(),
		"errors": errors,
		"preview_paths": preview_paths,
	}


static func _stage_terrain(levels_root: String, level_id: String) -> Dictionary:
	var level_root := _contained_path(levels_root, level_id)
	var png_path := _contained_path(level_root, TERRAIN_PNG)
	var webp_path := _contained_path(level_root, TERRAIN_WEBP)
	var staged_path := _contained_path(level_root, "terrain.portable.tmp.webp")
	var level_path := _contained_path(level_root, "level.json")
	if (
		level_root.is_empty()
		or png_path.is_empty()
		or webp_path.is_empty()
		or staged_path.is_empty()
		or level_path.is_empty()
		or not FileAccess.file_exists(png_path)
		or not FileAccess.file_exists(level_path)
	):
		return {"ok": false, "error": "%s terrain source is missing" % level_id}
	if FileAccess.file_exists(staged_path):
		DirAccess.remove_absolute(staged_path)
	if FileAccess.file_exists(webp_path):
		return {"ok": false, "error": "%s terrain WebP already exists" % level_id}
	var source := Image.new()
	if source.load(png_path) != OK or source.is_empty():
		return {"ok": false, "error": "%s terrain PNG cannot be decoded" % level_id}
	if source.save_webp(staged_path, false, 1.0) != OK:
		return {"ok": false, "error": "%s lossless WebP encoding failed" % level_id}
	var decoded := Image.new()
	if (
		decoded.load(staged_path) != OK
		or decoded.is_empty()
		or not _images_are_pixel_identical(source, decoded)
	):
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "error": "%s WebP pixel verification failed" % level_id}
	var level_text := FileAccess.get_file_as_string(level_path)
	var original_field := '"terrain_image": "terrain.png"'
	var optimized_field := '"terrain_image": "terrain.webp"'
	var first_match := level_text.find(original_field)
	if first_match < 0 or first_match != level_text.rfind(original_field):
		DirAccess.remove_absolute(staged_path)
		return {"ok": false, "error": "%s terrain manifest field is ambiguous" % level_id}
	return {
		"ok": true,
		"level_id": level_id,
		"png_path": png_path,
		"webp_path": webp_path,
		"staged_path": staged_path,
		"level_path": level_path,
		"level_text": level_text.replace(original_field, optimized_field),
		"png_bytes": FileAccess.get_file_as_bytes(png_path).size(),
		"webp_bytes": FileAccess.get_file_as_bytes(staged_path).size(),
	}


static func _commit_terrain(plan: Dictionary) -> String:
	var staged_path := str(plan.get("staged_path", ""))
	var webp_path := str(plan.get("webp_path", ""))
	var level_path := str(plan.get("level_path", ""))
	var png_path := str(plan.get("png_path", ""))
	if DirAccess.rename_absolute(staged_path, webp_path) != OK:
		return "cannot publish lossless terrain: %s" % webp_path
	var level_file := FileAccess.open(level_path, FileAccess.WRITE)
	if level_file == null:
		return "cannot update terrain manifest: %s" % level_path
	level_file.store_string(str(plan.get("level_text", "")))
	level_file.close()
	if DirAccess.remove_absolute(png_path) != OK:
		return "cannot remove superseded terrain PNG: %s" % png_path
	return ""


static func _cleanup_staged_terrain(plans: Array[Dictionary]) -> void:
	for plan: Dictionary in plans:
		var path := str(plan.get("staged_path", ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _images_are_pixel_identical(left: Image, right: Image) -> bool:
	if left == null or right == null or left.is_empty() or right.is_empty():
		return false
	if left.get_size() != right.get_size():
		return false
	var left_rgba := left.duplicate()
	var right_rgba := right.duplicate()
	left_rgba.convert(Image.FORMAT_RGBA8)
	right_rgba.convert(Image.FORMAT_RGBA8)
	return left_rgba.get_data() == right_rgba.get_data()


static func _contained_path(root: String, relative_path: String) -> String:
	if root.is_empty() or relative_path.is_empty() or relative_path.is_absolute_path():
		return ""
	var normalized_root := root.simplify_path().replace("\\", "/").trim_suffix("/")
	var candidate := normalized_root.path_join(relative_path).simplify_path().replace("\\", "/")
	if not candidate.to_lower().begins_with(normalized_root.to_lower() + "/"):
		return ""
	return candidate


static func _directory_size(root: String) -> int:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return 0
	var total := 0
	for file_name: String in DirAccess.get_files_at(root):
		var path := _contained_path(root, file_name)
		if not path.is_empty():
			total += FileAccess.get_file_as_bytes(path).size()
	for directory_name: String in DirAccess.get_directories_at(root):
		var path := _contained_path(root, directory_name)
		if not path.is_empty():
			total += _directory_size(path)
	return total
