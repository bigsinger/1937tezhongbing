class_name M1937PackLoader
extends RefCounted

const SCHEMA_VERSION := 1
const RUNTIME_VERSION := "1.0.0"
const USER_CAMPAIGN_ROOT := "user://UserCampaigns"
const CACHE_ROOT := "user://ContentCache"
const MAX_ENTRIES := 8192
const MAX_SINGLE_FILE_BYTES := 64 * 1024 * 1024
const MAX_TOTAL_BYTES := 512 * 1024 * 1024
const MAX_MANIFEST_BYTES := 2 * 1024 * 1024
const MAX_PACKAGE_BYTES := 512 * 1024 * 1024
const MAX_IMAGE_DIMENSION := 16384
const MAX_IMAGE_PIXELS := 67108864
const MAX_AUDIO_SECONDS := 1800.0
const MAX_LEVEL_ENTITIES := 20000
const MAX_MISSION_OBJECTIVES := 1024
const MAX_DIRECTION_SEQUENCES := 512
const MAX_LOCALIZATION_MESSAGES := 10000
const MAX_WORLD_DIMENSION := 1048576
const ZIP_EOCD_SIGNATURE := 0x06054B50
const ZIP_CENTRAL_SIGNATURE := 0x02014B50
const ZIP_EOCD_MIN_BYTES := 22
const ZIP_MAX_COMMENT_BYTES := 65535
const ALLOWED_EXTENSIONS: Array[String] = [
	"json", "bin", "png", "webp", "jpg", "jpeg", "wav", "ogg", "mp3", "md", "txt",
]
const FORBIDDEN_EXTENSIONS: Array[String] = [
	"gd", "gdscript", "cs", "dll", "exe", "com", "bat", "cmd", "ps1", "vbs",
	"js", "msi", "pck", "so", "dylib", "lnk", "url",
]

var _validation_cache: Dictionary = {}
var diagnostics: Array[Dictionary] = []
var _last_discovery_signature := ""
var developer_hot_reload_enabled := OS.is_debug_build()


func discover(root_path: String = USER_CAMPAIGN_ROOT) -> Array[Dictionary]:
	diagnostics.clear()
	# Tests and editor play-test sessions may point discovery at an isolated
	# directory without mutating the player's normal user:// content library.
	# The override is deliberately process-local and never changes project or
	# operating-system input state.
	if root_path == USER_CAMPAIGN_ROOT:
		var override_root := OS.get_environment("M1937_USER_CAMPAIGN_ROOT")
		if not override_root.is_empty():
			root_path = override_root
	var absolute_root := ProjectSettings.globalize_path(root_path)
	DirAccess.make_dir_recursive_absolute(absolute_root)
	var directory := DirAccess.open(absolute_root)
	if directory == null:
		return []
	var package_paths: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.to_lower().ends_with(".m1937pack"):
			package_paths.append(absolute_root.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	package_paths.sort()

	var discovered: Array[Dictionary] = []
	var ids: Dictionary = {}
	for package_path: String in package_paths:
		var result := validate(package_path)
		if not bool(result.get("ok", false)):
			diagnostics.append({
				"path": package_path,
				"code": str(result.get("code", "invalid_package")),
				"detail": str(result.get("detail", "")),
			})
			continue
		var manifest := result.get("manifest", {}) as Dictionary
		var pack_id := str(manifest.get("pack_id", ""))
		if ids.has(pack_id):
			diagnostics.append({
				"path": package_path,
				"code": "duplicate_pack_id",
				"detail": pack_id,
			})
			continue
		ids[pack_id] = true
		discovered.append(result)

	var compatible := resolve_compatible_packages(discovered)
	_last_discovery_signature = _discovery_signature(package_paths)
	return compatible


func resolve_compatible_packages(discovered: Array[Dictionary]) -> Array[Dictionary]:
	# Kept separate from filesystem discovery so dependency/conflict resolution
	# can be covered by clean-room tests without constructing malicious archives.
	var installed_ids: Dictionary = {}
	for package: Dictionary in discovered:
		installed_ids[str((package["manifest"] as Dictionary).get("pack_id", ""))] = package
	var blocked_ids: Dictionary = {}
	for package: Dictionary in discovered:
		var manifest := package["manifest"] as Dictionary
		var pack_id := str(manifest.get("pack_id", ""))
		var minimum_runtime := str(manifest.get("minimum_runtime_version", "0.0.0"))
		if _compare_semantic_versions(minimum_runtime, RUNTIME_VERSION) > 0:
			blocked_ids[pack_id] = true
			diagnostics.append({
				"path": str(package.get("path", "")),
				"code": "runtime_version_incompatible",
				"detail": "%s > %s" % [minimum_runtime, RUNTIME_VERSION],
			})
		for conflict_value: Variant in manifest.get("conflicts", []) as Array:
			var conflict_id := str(conflict_value)
			if installed_ids.has(conflict_id):
				blocked_ids[pack_id] = true
				blocked_ids[conflict_id] = true
				diagnostics.append({
					"path": str(package.get("path", "")),
					"code": "content_conflict",
					"detail": "%s <> %s" % [pack_id, conflict_id],
				})
	var compatible: Array[Dictionary] = []
	var changed := true
	while changed:
		changed = false
		for package: Dictionary in discovered:
			var manifest := package["manifest"] as Dictionary
			var pack_id := str(manifest.get("pack_id", ""))
			if blocked_ids.has(pack_id):
				continue
			for dependency_value: Variant in manifest.get("dependencies", []) as Array:
				var dependency := str(dependency_value)
				if not installed_ids.has(dependency) or blocked_ids.has(dependency):
					blocked_ids[pack_id] = true
					diagnostics.append({
						"path": str(package.get("path", "")),
						"code": "missing_dependencies",
						"detail": dependency,
					})
					changed = true
					break
	for package: Dictionary in discovered:
		var pack_id := str((package["manifest"] as Dictionary).get("pack_id", ""))
		if not blocked_ids.has(pack_id):
			compatible.append(package)
	return compatible


func discover_if_changed(root_path: String = USER_CAMPAIGN_ROOT) -> Dictionary:
	if not developer_hot_reload_enabled:
		return {"changed": false, "packages": []}
	if root_path == USER_CAMPAIGN_ROOT:
		var override_root := OS.get_environment("M1937_USER_CAMPAIGN_ROOT")
		if not override_root.is_empty():
			root_path = override_root
	var absolute_root := ProjectSettings.globalize_path(root_path)
	var directory := DirAccess.open(absolute_root)
	if directory == null:
		return {"changed": not _last_discovery_signature.is_empty(), "packages": []}
	var paths: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.to_lower().ends_with(".m1937pack"):
			paths.append(absolute_root.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	var signature := _discovery_signature(paths)
	if signature == _last_discovery_signature:
		return {"changed": false, "packages": []}
	_validation_cache.clear()
	var packages := discover(root_path)
	return {"changed": true, "packages": packages}


func validate(package_path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(package_path)
	if not FileAccess.file_exists(absolute_path):
		return _failure("package_missing", absolute_path)
	var package_file := FileAccess.open(absolute_path, FileAccess.READ)
	if package_file == null:
		return _failure("package_open_failed", absolute_path)
	var package_size := package_file.get_length()
	package_file.close()
	if package_size <= 0 or package_size > MAX_PACKAGE_BYTES:
		return _failure("package_size_invalid", str(package_size))
	var modified := FileAccess.get_modified_time(absolute_path)
	var cache_key := "%s|%d|%d" % [absolute_path, modified, package_size]
	if _validation_cache.has(cache_key):
		return (_validation_cache[cache_key] as Dictionary).duplicate(true)

	var directory_result := _inspect_zip_directory(absolute_path)
	if not bool(directory_result.get("ok", false)):
		return directory_result
	var entries := directory_result.get("entries", {}) as Dictionary
	if not entries.has("manifest.json") or not entries.has("campaign.json"):
		return _failure("required_file_missing", "manifest.json or campaign.json")
	var manifest_info := entries["manifest.json"] as Dictionary
	if int(manifest_info.get("length", 0)) > MAX_MANIFEST_BYTES:
		return _failure("manifest_too_large", "")

	var reader := ZIPReader.new()
	var open_error := reader.open(absolute_path)
	if open_error != OK:
		return _failure("zip_open_failed", str(open_error))
	var manifest_bytes := reader.read_file("manifest.json")
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		reader.close()
		return _failure("manifest_json_invalid", "")
	var manifest := parsed as Dictionary
	var identity_error := _validate_manifest_identity(manifest)
	if not identity_error.is_empty():
		reader.close()
		return _failure("manifest_identity_invalid", identity_error)

	var declared_value: Variant = manifest.get("files")
	if not declared_value is Array:
		reader.close()
		return _failure("manifest_files_invalid", "not an array")
	var declared_files := declared_value as Array
	if declared_files.size() != entries.size() - 1:
		reader.close()
		return _failure("manifest_file_count_mismatch", "")
	var seen: Dictionary = {}
	for value: Variant in declared_files:
		if not value is Dictionary:
			reader.close()
			return _failure("manifest_file_invalid", "not an object")
		var declared := value as Dictionary
		var relative := _normalize_relative_path(str(declared.get("path", "")))
		if relative.is_empty() or relative == "manifest.json" or seen.has(relative.to_lower()):
			reader.close()
			return _failure("manifest_path_invalid", str(declared.get("path", "")))
		seen[relative.to_lower()] = true
		if not entries.has(relative):
			reader.close()
			return _failure("manifest_payload_missing", relative)
		var entry := entries[relative] as Dictionary
		if int(declared.get("length", -1)) != int(entry.get("length", -2)):
			reader.close()
			return _failure("payload_length_mismatch", relative)
		var bytes := reader.read_file(relative)
		if bytes.size() != int(entry.get("length", -1)):
			reader.close()
			return _failure("payload_truncated", relative)
		var semantic_error := _validate_payload_semantics(relative, bytes)
		if not semantic_error.is_empty():
			reader.close()
			return _failure("payload_policy_invalid", "%s: %s" % [relative, semantic_error])
		var actual_hash := _bytes_sha256(bytes)
		var expected_hash := str(declared.get("sha256", "")).to_lower()
		if not _is_sha256(expected_hash) or actual_hash != expected_hash:
			reader.close()
			return _failure("payload_hash_mismatch", relative)
	reader.close()

	for level_value: Variant in manifest.get("level_entries", []) as Array:
		var level_path := _normalize_relative_path(str(level_value))
		if (
			level_path.is_empty()
			or not level_path.begins_with("levels/")
			or not level_path.ends_with("/level.json")
			or not entries.has(level_path)
		):
			return _failure("level_entry_invalid", str(level_value))
	var result := {
		"ok": true,
		"path": absolute_path,
		"manifest": manifest.duplicate(true),
		"package_sha256": FileAccess.get_sha256(absolute_path).to_lower(),
		"content_identity": "%s@%s:%s" % [
			str(manifest.get("pack_id", "")),
			str(manifest.get("version", "")),
			FileAccess.get_sha256(absolute_path).to_lower(),
		],
		"entry_count": entries.size(),
		"total_uncompressed_bytes": int(directory_result.get("total_bytes", 0)),
		"modified_time": modified,
	}
	_validation_cache[cache_key] = result.duplicate(true)
	return result


func install_to_cache(package: Dictionary) -> Dictionary:
	if not bool(package.get("ok", false)):
		return _failure("package_not_validated", "")
	var package_hash := str(package.get("package_sha256", ""))
	if not _is_sha256(package_hash):
		return _failure("package_hash_invalid", "")
	var root := ProjectSettings.globalize_path(CACHE_ROOT).path_join(package_hash)
	var marker := root.path_join(".validated.json")
	if FileAccess.file_exists(marker):
		return {
			"ok": true,
			"root": root,
			"content_identity": str(package.get("content_identity", "")),
			"cached": true,
		}
	DirAccess.make_dir_recursive_absolute(root)
	var reader := ZIPReader.new()
	var error := reader.open(str(package.get("path", "")))
	if error != OK:
		return _failure("zip_open_failed", str(error))
	var files := reader.get_files()
	files.sort()
	for relative_value: Variant in files:
		var relative := _normalize_relative_path(str(relative_value))
		if relative.is_empty():
			reader.close()
			return _failure("cache_path_invalid", str(relative_value))
		var target := root.path_join(relative).simplify_path()
		if not target.begins_with(root.trim_suffix("/") + "/"):
			reader.close()
			return _failure("cache_path_escape", relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var bytes := reader.read_file(relative)
		if bytes.size() > MAX_SINGLE_FILE_BYTES:
			reader.close()
			return _failure("cache_payload_too_large", relative)
		var temporary := target + ".part"
		var output := FileAccess.open(temporary, FileAccess.WRITE)
		if output == null:
			reader.close()
			return _failure("cache_write_failed", relative)
		output.store_buffer(bytes)
		output.flush()
		output.close()
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		if DirAccess.rename_absolute(temporary, target) != OK:
			reader.close()
			return _failure("cache_commit_failed", relative)
	reader.close()
	var marker_file := FileAccess.open(marker, FileAccess.WRITE)
	if marker_file == null:
		return _failure("cache_marker_failed", "")
	marker_file.store_string(JSON.stringify({
		"schema_version": 1,
		"content_identity": str(package.get("content_identity", "")),
		"package_sha256": package_hash,
	}, "  "))
	marker_file.close()
	return {
		"ok": true,
		"root": root,
		"content_identity": str(package.get("content_identity", "")),
		"cached": false,
	}


func campaign_entries(package: Dictionary) -> Array[Dictionary]:
	var installed := install_to_cache(package)
	if not bool(installed.get("ok", false)):
		return []
	var root := str(installed.get("root", ""))
	var campaign_path := root.path_join("campaign.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(campaign_path))
	if not parsed is Dictionary:
		return []
	var campaign := parsed as Dictionary
	if int(campaign.get("schema_version", 0)) != 1:
		return []
	var raw_levels: Variant = campaign.get("levels", [])
	if not raw_levels is Array:
		return []
	var manifest := package.get("manifest", {}) as Dictionary
	var entries: Array[Dictionary] = []
	var ids: Dictionary = {}
	for raw_value: Variant in raw_levels as Array:
		if not raw_value is Dictionary:
			return []
		var raw := raw_value as Dictionary
		var local_id := str(raw.get("id", ""))
		if not _is_content_id(local_id) or ids.has(local_id):
			return []
		ids[local_id] = true
		var level_path := _normalize_relative_path(str(raw.get("level", "")))
		var mission_path := _normalize_relative_path(str(raw.get("mission", "")))
		var terrain_value := str(raw.get("terrain", ""))
		var terrain_path := (
			_normalize_relative_path(terrain_value)
			if not terrain_value.is_empty()
			else ""
		)
		if level_path.is_empty() or mission_path.is_empty():
			return []
		var required_paths: Array[String] = [level_path, mission_path]
		if not terrain_path.is_empty():
			required_paths.append(terrain_path)
		for path: String in required_paths:
			if not FileAccess.file_exists(root.path_join(path)):
				return []
		var pack_id := str(manifest.get("pack_id", ""))
		entries.append({
			"id": "%s:%s" % [pack_id, local_id],
			"local_id": local_id,
			"number": int(raw.get("number", entries.size() + 1)),
			"title": str(raw.get("title", local_id)),
			"pack_id": pack_id,
			"pack_version": str(manifest.get("version", "")),
			"content_identity": str(package.get("content_identity", "")),
			"root": root,
			"level_path": root.path_join(level_path),
			"mission_path": root.path_join(mission_path),
			"terrain_path": root.path_join(terrain_path) if not terrain_path.is_empty() else "",
			"direction_path": _optional_content_path(root, str(raw.get("direction", ""))),
		})
	return entries


func _inspect_zip_directory(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("package_open_failed", path)
	var length := file.get_length()
	var tail_length := mini(length, ZIP_EOCD_MIN_BYTES + ZIP_MAX_COMMENT_BYTES)
	file.seek(length - tail_length)
	var tail := file.get_buffer(tail_length)
	var eocd_offset := -1
	for index: int in range(tail.size() - ZIP_EOCD_MIN_BYTES, -1, -1):
		if tail.decode_u32(index) == ZIP_EOCD_SIGNATURE:
			eocd_offset = index
			break
	if eocd_offset < 0:
		file.close()
		return _failure("zip_directory_missing", "")
	var disk_number := int(tail.decode_u16(eocd_offset + 4))
	var directory_disk := int(tail.decode_u16(eocd_offset + 6))
	var disk_entries := int(tail.decode_u16(eocd_offset + 8))
	var entry_count := int(tail.decode_u16(eocd_offset + 10))
	var directory_size := int(tail.decode_u32(eocd_offset + 12))
	var directory_offset := int(tail.decode_u32(eocd_offset + 16))
	if (
		disk_number != 0 or directory_disk != 0 or disk_entries != entry_count
		or entry_count < 2 or entry_count > MAX_ENTRIES
		or entry_count == 0xFFFF or directory_size == 0xFFFFFFFF
		or directory_offset == 0xFFFFFFFF
		or directory_offset + directory_size > length
	):
		file.close()
		return _failure("zip_directory_unsupported", "")
	file.seek(directory_offset)
	var central := file.get_buffer(directory_size)
	file.close()
	var cursor := 0
	var entries: Dictionary = {}
	var lower_paths: Dictionary = {}
	var total := 0
	for _entry_index: int in range(entry_count):
		if cursor + 46 > central.size() or central.decode_u32(cursor) != ZIP_CENTRAL_SIGNATURE:
			return _failure("zip_central_truncated", "")
		var flags := int(central.decode_u16(cursor + 8))
		var compression := int(central.decode_u16(cursor + 10))
		var compressed_size := int(central.decode_u32(cursor + 20))
		var uncompressed_size := int(central.decode_u32(cursor + 24))
		var name_length := int(central.decode_u16(cursor + 28))
		var extra_length := int(central.decode_u16(cursor + 30))
		var comment_length := int(central.decode_u16(cursor + 32))
		var external_attributes := int(central.decode_u32(cursor + 38))
		var record_size := 46 + name_length + extra_length + comment_length
		if cursor + record_size > central.size() or name_length <= 0:
			return _failure("zip_central_truncated", "")
		var name := central.slice(cursor + 46, cursor + 46 + name_length).get_string_from_utf8()
		var normalized := _normalize_relative_path(name)
		var lower := normalized.to_lower()
		if (
			normalized.is_empty() or lower_paths.has(lower)
			or flags & 1 != 0 or compression not in [0, 8]
			or (external_attributes >> 16) & 0xF000 == 0xA000
			or compressed_size == 0xFFFFFFFF or uncompressed_size == 0xFFFFFFFF
			or uncompressed_size > MAX_SINGLE_FILE_BYTES
		):
			return _failure("zip_entry_unsafe", name)
		total += uncompressed_size
		if total > MAX_TOTAL_BYTES:
			return _failure("zip_total_too_large", "")
		lower_paths[lower] = true
		entries[normalized] = {
			"length": uncompressed_size,
			"compressed_length": compressed_size,
		}
		cursor += record_size
	if cursor != central.size():
		return _failure("zip_central_trailing_data", "")
	return {"ok": true, "entries": entries, "total_bytes": total}


func _validate_manifest_identity(manifest: Dictionary) -> String:
	if int(manifest.get("schema_version", 0)) != SCHEMA_VERSION:
		return "schema_version"
	var pack_id := str(manifest.get("pack_id", ""))
	if not _is_pack_id(pack_id):
		return "pack_id"
	if not _is_semantic_version(str(manifest.get("version", ""))):
		return "version"
	if not _is_semantic_version(str(manifest.get("minimum_runtime_version", ""))):
		return "minimum_runtime_version"
	if str(manifest.get("display_name", "")).is_empty() or str(manifest.get("display_name", "")).length() > 128:
		return "display_name"
	var source_declaration := str(manifest.get("source_declaration", ""))
	if source_declaration.is_empty() or source_declaration.length() > 512:
		return "source_declaration"
	var levels: Variant = manifest.get("level_entries")
	if not levels is Array or (levels as Array).is_empty() or (levels as Array).size() > 128:
		return "level_entries"
	for key: String in ["dependencies", "conflicts", "capabilities", "files"]:
		if not manifest.get(key, []) is Array:
			return key
	var dependency_ids: Dictionary = {}
	for dependency_value: Variant in manifest.get("dependencies", []) as Array:
		var dependency := str(dependency_value)
		if not _is_pack_id(dependency) or dependency == pack_id or dependency_ids.has(dependency):
			return "dependencies"
		dependency_ids[dependency] = true
	var conflict_ids: Dictionary = {}
	for conflict_value: Variant in manifest.get("conflicts", []) as Array:
		var conflict := str(conflict_value)
		if (
			not _is_pack_id(conflict) or conflict == pack_id
			or conflict_ids.has(conflict) or dependency_ids.has(conflict)
		):
			return "conflicts"
		conflict_ids[conflict] = true
	var capabilities := manifest.get("capabilities", []) as Array
	if capabilities.size() > 64:
		return "capabilities"
	for capability_value: Variant in capabilities:
		if not _is_pack_id(str(capability_value)):
			return "capabilities"
	return ""


func _normalize_relative_path(path: String) -> String:
	if path.is_empty() or path.contains("\\") or path.begins_with("/") or path.contains(":"):
		return ""
	var segments := path.split("/", true)
	for segment: String in segments:
		if segment.is_empty() or segment in [".", ".."] or segment.ends_with(" ") or segment.ends_with("."):
			return ""
	var extension := path.get_extension().to_lower()
	if extension in FORBIDDEN_EXTENSIONS or extension not in ALLOWED_EXTENSIONS:
		return ""
	return "/".join(segments)


func _optional_content_path(root: String, value: String) -> String:
	if value.is_empty():
		return ""
	var relative := _normalize_relative_path(value)
	if relative.is_empty():
		return ""
	var path := root.path_join(relative)
	return path if FileAccess.file_exists(path) else ""


func _is_pack_id(value: String) -> bool:
	if value.length() < 3 or value.length() > 64:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._-":
			return false
	return true


func _is_content_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _bytes_sha256(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return "".sha256_text()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _discovery_signature(paths: Array[String]) -> String:
	var rows: Array[String] = []
	for path: String in paths:
		var length := -1
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			length = file.get_length()
			file.close()
		rows.append("%s|%d|%d" % [
			path,
			FileAccess.get_modified_time(path),
			length,
		])
	return _bytes_sha256("\n".join(rows).to_utf8_buffer())


func _validate_payload_semantics(path: String, bytes: PackedByteArray) -> String:
	match path.get_extension().to_lower():
		"json":
			return _validate_json_payload(path, bytes)
		"png", "jpg", "jpeg", "webp":
			var dimensions := _image_dimensions(path.get_extension().to_lower(), bytes)
			if dimensions == Vector2i.ZERO:
				return "invalid image header"
			if (
				dimensions.x > MAX_IMAGE_DIMENSION
				or dimensions.y > MAX_IMAGE_DIMENSION
				or dimensions.x * dimensions.y > MAX_IMAGE_PIXELS
			):
				return "image dimensions exceed policy"
		"wav", "ogg", "mp3":
			var duration := _audio_duration(path.get_extension().to_lower(), bytes)
			if duration < 0.0:
				return "invalid or unsupported audio header"
			if duration > MAX_AUDIO_SECONDS:
				return "audio duration exceeds policy"
	return ""


func _validate_json_payload(path: String, bytes: PackedByteArray) -> String:
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return "JSON root must be an object"
	var root := parser.data as Dictionary
	if path == "campaign.json":
		var levels: Variant = root.get("levels")
		if not levels is Array or (levels as Array).is_empty() or (levels as Array).size() > 128:
			return "campaign levels must contain 1..128 entries"
	elif path.ends_with("/level.json"):
		var entities: Variant = root.get("entities")
		if not entities is Array or (entities as Array).size() > MAX_LEVEL_ENTITIES:
			return "level entity count exceeds policy"
		var world: Variant = root.get("world_size")
		if not world is Dictionary:
			return "world_size is required"
		for key: String in ["width", "height"]:
			var dimension := int((world as Dictionary).get(key, 0))
			if dimension <= 0 or dimension > MAX_WORLD_DIMENSION:
				return "world_size.%s exceeds policy" % key
	elif path.ends_with("/mission.json"):
		var objectives: Variant = root.get("objectives")
		if not objectives is Array or (objectives as Array).size() > MAX_MISSION_OBJECTIVES:
			return "mission objective count exceeds policy"
		var failures: Variant = root.get("failure_conditions", [])
		if not failures is Array or (failures as Array).size() > MAX_MISSION_OBJECTIVES:
			return "mission failure count exceeds policy"
	elif path.ends_with("/direction.json"):
		var sequences: Variant = root.get("sequences")
		if not sequences is Array or (sequences as Array).size() > MAX_DIRECTION_SEQUENCES:
			return "direction sequence count exceeds policy"
	elif path.begins_with("localization/") and root.size() > MAX_LOCALIZATION_MESSAGES:
		return "localization message count exceeds policy"
	return ""


func _image_dimensions(extension: String, bytes: PackedByteArray) -> Vector2i:
	match extension:
		"png":
			if (
				bytes.size() >= 24 and bytes[0] == 137 and bytes[1] == 80
				and bytes[2] == 78 and bytes[3] == 71
				and _ascii_equals(bytes, 12, "IHDR")
			):
				return Vector2i(_decode_u32_be(bytes, 16), _decode_u32_be(bytes, 20))
		"jpg", "jpeg":
			if bytes.size() < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8:
				return Vector2i.ZERO
			var offset := 2
			while offset + 4 <= bytes.size():
				while offset < bytes.size() and bytes[offset] == 0xFF:
					offset += 1
				if offset >= bytes.size():
					break
				var marker := int(bytes[offset])
				offset += 1
				if marker in [0xD8, 0xD9] or (marker >= 0xD0 and marker <= 0xD7):
					continue
				if offset + 2 > bytes.size():
					break
				var length := _decode_u16_be(bytes, offset)
				if length < 2 or offset + length > bytes.size():
					break
				if marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]:
					if length >= 7:
						return Vector2i(
							_decode_u16_be(bytes, offset + 5),
							_decode_u16_be(bytes, offset + 3),
						)
					break
				offset += length
		"webp":
			if (
				bytes.size() < 30 or not _ascii_equals(bytes, 0, "RIFF")
				or not _ascii_equals(bytes, 8, "WEBP")
			):
				return Vector2i.ZERO
			if _ascii_equals(bytes, 12, "VP8X"):
				return Vector2i(1 + _decode_u24_le(bytes, 24), 1 + _decode_u24_le(bytes, 27))
			if (
				_ascii_equals(bytes, 12, "VP8 ") and bytes.size() >= 30
				and bytes[23] == 0x9D and bytes[24] == 0x01 and bytes[25] == 0x2A
			):
				return Vector2i(bytes.decode_u16(26) & 0x3FFF, bytes.decode_u16(28) & 0x3FFF)
			if _ascii_equals(bytes, 12, "VP8L") and bytes.size() >= 25 and bytes[20] == 0x2F:
				var bits := int(bytes.decode_u32(21))
				return Vector2i(1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF))
	return Vector2i.ZERO


func _audio_duration(extension: String, bytes: PackedByteArray) -> float:
	match extension:
		"wav":
			return _wav_duration(bytes)
		"ogg":
			return _ogg_duration(bytes)
		"mp3":
			return _mp3_duration(bytes)
	return -1.0


func _wav_duration(bytes: PackedByteArray) -> float:
	if (
		bytes.size() < 12 or not _ascii_equals(bytes, 0, "RIFF")
		or not _ascii_equals(bytes, 8, "WAVE")
	):
		return -1.0
	var byte_rate := 0
	var data_bytes := 0
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk_size := int(bytes.decode_u32(offset + 4))
		var payload := offset + 8
		if chunk_size < 0 or payload + chunk_size > bytes.size():
			return -1.0
		if _ascii_equals(bytes, offset, "fmt ") and chunk_size >= 16:
			byte_rate = int(bytes.decode_u32(payload + 8))
		elif _ascii_equals(bytes, offset, "data"):
			data_bytes = chunk_size
		offset = payload + chunk_size + (chunk_size & 1)
	return float(data_bytes) / float(byte_rate) if byte_rate > 0 and data_bytes > 0 else -1.0


func _ogg_duration(bytes: PackedByteArray) -> float:
	var offset := 0
	var sample_rate := 0
	var last_granule := 0
	while offset + 27 <= bytes.size():
		if not _ascii_equals(bytes, offset, "OggS"):
			return -1.0
		var segment_count := int(bytes[offset + 26])
		if offset + 27 + segment_count > bytes.size():
			return -1.0
		var payload_bytes := 0
		for index: int in range(segment_count):
			payload_bytes += int(bytes[offset + 27 + index])
		var payload_offset := offset + 27 + segment_count
		if payload_offset + payload_bytes > bytes.size():
			return -1.0
		var granule := int(bytes.decode_s64(offset + 6))
		if granule >= 0:
			last_granule = maxi(last_granule, granule)
		if (
			sample_rate == 0 and payload_bytes >= 16 and bytes[payload_offset] == 1
			and _ascii_equals(bytes, payload_offset + 1, "vorbis")
		):
			sample_rate = int(bytes.decode_u32(payload_offset + 12))
		offset = payload_offset + payload_bytes
	return float(last_granule) / float(sample_rate) if sample_rate > 0 else -1.0


func _mp3_duration(bytes: PackedByteArray) -> float:
	var offset := 0
	if bytes.size() >= 10 and _ascii_equals(bytes, 0, "ID3"):
		offset = 10 + ((bytes[6] & 0x7F) << 21) + ((bytes[7] & 0x7F) << 14) + ((bytes[8] & 0x7F) << 7) + (bytes[9] & 0x7F)
	var sample_count := 0
	var sample_rate := 0
	while offset + 4 <= bytes.size():
		var header := _decode_u32_be(bytes, offset)
		if header & 0xFFE00000 != 0xFFE00000:
			offset += 1
			continue
		var version_bits := (header >> 19) & 3
		var layer_bits := (header >> 17) & 3
		var bitrate_index := (header >> 12) & 0xF
		var rate_index := (header >> 10) & 3
		if version_bits == 1 or layer_bits != 1 or bitrate_index in [0, 15] or rate_index == 3:
			offset += 1
			continue
		var base_rates: Array[int] = [44100, 48000, 32000]
		sample_rate = base_rates[rate_index]
		if version_bits == 2:
			sample_rate /= 2
		elif version_bits == 0:
			sample_rate /= 4
		var mpeg1 := version_bits == 3
		var bitrates: Array[int] = (
			[0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
			if mpeg1 else [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
		)
		var bitrate := bitrates[bitrate_index] * 1000
		var padding := (header >> 9) & 1
		var frame_length := (144 if mpeg1 else 72) * bitrate / sample_rate + padding
		if frame_length <= 4 or offset + frame_length > bytes.size():
			break
		sample_count += 1152 if mpeg1 else 576
		offset += frame_length
	return float(sample_count) / float(sample_rate) if sample_count > 0 and sample_rate > 0 else -1.0


func _is_semantic_version(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var without_build := value.split("+", true, 1)[0]
	var core := without_build.split("-", true, 1)[0]
	var pieces := core.split(".")
	if pieces.size() != 3:
		return false
	for piece: String in pieces:
		if piece.is_empty() or not piece.is_valid_int() or (piece.length() > 1 and piece.begins_with("0")):
			return false
	return true


func _compare_semantic_versions(left: String, right: String) -> int:
	if not _is_semantic_version(left) or not _is_semantic_version(right):
		return 0
	for index: int in range(3):
		var left_value := int(left.split("+", true, 1)[0].split("-", true, 1)[0].split(".")[index])
		var right_value := int(right.split("+", true, 1)[0].split("-", true, 1)[0].split(".")[index])
		if left_value != right_value:
			return -1 if left_value < right_value else 1
	var left_pre := _semantic_prerelease(left)
	var right_pre := _semantic_prerelease(right)
	if left_pre == right_pre:
		return 0
	if left_pre.is_empty():
		return 1
	if right_pre.is_empty():
		return -1
	return -1 if left_pre.naturalnocasecmp_to(right_pre) < 0 else 1


func _semantic_prerelease(value: String) -> String:
	var core_and_pre := value.split("+", true, 1)[0]
	var parts := core_and_pre.split("-", true, 1)
	return parts[1] if parts.size() > 1 else ""


func _ascii_equals(bytes: PackedByteArray, offset: int, expected: String) -> bool:
	var expected_bytes := expected.to_ascii_buffer()
	if offset < 0 or offset + expected_bytes.size() > bytes.size():
		return false
	for index: int in range(expected_bytes.size()):
		if bytes[offset + index] != expected_bytes[index]:
			return false
	return true


func _decode_u16_be(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 8) | int(bytes[offset + 1])


func _decode_u32_be(bytes: PackedByteArray, offset: int) -> int:
	return (
		(int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16)
		| (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])
	)


func _decode_u24_le(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16)


func _failure(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
