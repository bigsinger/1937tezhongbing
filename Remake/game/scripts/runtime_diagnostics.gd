class_name RuntimeDiagnostics
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_RECENT_COMMANDS := 128
const DEFAULT_EXPORT_PATH := "user://diagnostics/remake-diagnostics.json"
const DEFAULT_BUNDLE_PATH := "user://diagnostics/remake-diagnostics.zip"

var build_id := "development"
var recent_commands: Array[Dictionary] = []
var warnings: Array[String] = []


func record_command(command_name: String, payload: Dictionary = {}) -> void:
	recent_commands.append({
		"sequence": recent_commands.size(),
		"elapsed_msec": Time.get_ticks_msec(),
		"command": command_name,
		"payload": _safe_payload(payload),
	})
	while recent_commands.size() > MAX_RECENT_COMMANDS:
		recent_commands.pop_front()


func record_warning(message: String) -> void:
	if message.is_empty():
		return
	warnings.append(message)
	while warnings.size() > 64:
		warnings.pop_front()


func build_document(
	level_id: String,
	runtime_settings: Dictionary,
	performance: Dictionary,
	service_stats: Dictionary = {},
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"build_id": build_id,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"platform": OS.get_name(),
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"level_id": level_id,
		# Controls and paths can disclose personal configuration. Only product
		# settings useful for reproduction are exported.
		"settings": _public_settings(runtime_settings),
		"performance": performance.duplicate(true),
		"services": service_stats.duplicate(true),
		"recent_commands": recent_commands.duplicate(true),
		"warnings": warnings.duplicate(),
	}


func export_document(document: Dictionary, path: String = DEFAULT_EXPORT_PATH) -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return {"ok": false, "path": path, "message": "cannot create diagnostics directory"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path, "message": "cannot open diagnostics file"}
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return {"ok": true, "path": path, "message": "diagnostics exported"}


func export_bundle(
	document: Dictionary,
	path: String = DEFAULT_BUNDLE_PATH,
) -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return {
			"ok": false,
			"path": path,
			"message": "cannot create diagnostics directory",
		}
	var packer := ZIPPacker.new()
	var open_error := packer.open(path)
	if open_error != OK:
		return {
			"ok": false,
			"path": path,
			"message": "cannot open diagnostics bundle",
		}
	var json_bytes := JSON.stringify(document, "  ").to_utf8_buffer()
	var entry_error := packer.start_file("diagnostics.json")
	if entry_error == OK:
		entry_error = packer.write_file(json_bytes)
		packer.close_file()
	if entry_error == OK:
		entry_error = packer.start_file("README.txt")
	if entry_error == OK:
		entry_error = packer.write_file(
			(
				"M1937 Remake diagnostic bundle\n"
				+ "This archive contains public display/game settings, runtime metrics, "
				+ "a bounded command trail and reproducibility metadata. "
				+ "It does not contain save games, custom key bindings or personal paths.\n"
			).to_utf8_buffer()
		)
		packer.close_file()
	packer.close()
	if entry_error != OK:
		return {
			"ok": false,
			"path": path,
			"message": "cannot write diagnostics bundle",
		}
	return {"ok": true, "path": path, "message": "diagnostics bundle exported"}


static func _public_settings(settings: Dictionary) -> Dictionary:
	var allowed := [
		"display_mode",
		"resolution_policy",
		"window_width",
		"window_height",
		"vsync",
		"max_fps",
		"ui_scale",
		"ruleset_mode",
		"difficulty_mode",
		"mission_rule_mode",
		"edge_scroll",
		"reduce_camera_motion",
	]
	var result: Dictionary = {}
	for key: String in allowed:
		if settings.has(key):
			result[key] = settings[key]
	return result


static func _safe_payload(payload: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in payload.keys():
		var key := str(key_value)
		var value: Variant = payload[key_value]
		if value == null or value is bool or value is int or value is float or value is String:
			result[key] = value
		elif value is Vector2:
			result[key] = {"x": value.x, "y": value.y}
		elif value is Vector2i:
			result[key] = {"x": value.x, "y": value.y}
	return result
