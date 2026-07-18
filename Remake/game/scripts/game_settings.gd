class_name GameSettings
extends RefCounted

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://settings.json"
const DISPLAY_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const RESOLUTION_POLICIES: Array[String] = ["desktop", "custom"]
const AUDIO_CHANNELS: Array[String] = ["master", "music", "sfx", "voice"]
const HINT_KEYS: Array[String] = ["controls", "objectives", "interactions"]
const INTERFACE_KEYS: Array[String] = ["subtitles", "show_briefings", "edge_scroll"]

var values: Dictionary = default_document()
var last_result: Dictionary = {}


static func default_document() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"audio": {
			"master": 1.0,
			"music": 0.80,
			"sfx": 0.90,
			"voice": 1.0,
			"muted": false,
		},
		"display": {
			# Desktop resolution preserves the project's requested behaviour: a
			# fullscreen game follows the active Windows monitor resolution.
			"mode": "fullscreen",
			"resolution_policy": "desktop",
			"window_width": 1280,
			"window_height": 720,
			"vsync": true,
		},
		"hints": {
			"controls": true,
			"objectives": true,
			"interactions": true,
		},
		"interface": {
			"subtitles": true,
			"show_briefings": true,
			"edge_scroll": true,
		},
	}


func reset_to_defaults() -> void:
	values = default_document()


func load_from_disk(path: String = DEFAULT_PATH) -> Dictionary:
	var result: Dictionary = ATOMIC_JSON_STORE.load_document(
		path,
		Callable(self, "_is_loadable_document"),
		default_document(),
	)
	values = _normalize_document(result["data"] as Dictionary)
	# Missing/corrupt settings are a recoverable condition: callers can show the
	# warning while continuing with deterministic safe defaults.
	if not bool(result["ok"]):
		result["degraded"] = true
	else:
		result["degraded"] = bool(result.get("recovered", false))
	result["data"] = values.duplicate(true)
	last_result = result.duplicate(true)
	return result


func save_to_disk(path: String = DEFAULT_PATH) -> Dictionary:
	values = _normalize_document(values)
	var result: Dictionary = ATOMIC_JSON_STORE.save_document(
		path,
		values,
		Callable(self, "_is_loadable_document"),
		true,
	)
	last_result = result.duplicate(true)
	return result


func set_audio_volume(channel: String, linear_volume: float) -> bool:
	if not channel in AUDIO_CHANNELS:
		return false
	(values["audio"] as Dictionary)[channel] = clampf(linear_volume, 0.0, 1.0)
	return true


func audio_volume(channel: String) -> float:
	if not channel in AUDIO_CHANNELS:
		return 0.0
	return float((values["audio"] as Dictionary).get(channel, 0.0))


func set_muted(muted: bool) -> void:
	(values["audio"] as Dictionary)["muted"] = muted


func is_muted() -> bool:
	return bool((values["audio"] as Dictionary).get("muted", false))


func set_display_mode(mode: String) -> bool:
	if not mode in DISPLAY_MODES:
		return false
	(values["display"] as Dictionary)["mode"] = mode
	return true


func set_resolution_policy(policy: String) -> bool:
	if not policy in RESOLUTION_POLICIES:
		return false
	(values["display"] as Dictionary)["resolution_policy"] = policy
	return true


func set_window_size(size: Vector2i) -> void:
	var display := values["display"] as Dictionary
	display["window_width"] = clampi(size.x, 800, 7680)
	display["window_height"] = clampi(size.y, 600, 4320)


func set_vsync(enabled: bool) -> void:
	(values["display"] as Dictionary)["vsync"] = enabled


func display_settings() -> Dictionary:
	return (values["display"] as Dictionary).duplicate(true)


func set_hint_enabled(hint_key: String, enabled: bool) -> bool:
	if not hint_key in HINT_KEYS:
		return false
	(values["hints"] as Dictionary)[hint_key] = enabled
	return true


func hint_enabled(hint_key: String) -> bool:
	return bool((values["hints"] as Dictionary).get(hint_key, false))


func set_interface_enabled(interface_key: String, enabled: bool) -> bool:
	if not interface_key in INTERFACE_KEYS:
		return false
	(values["interface"] as Dictionary)[interface_key] = enabled
	return true


func interface_enabled(interface_key: String) -> bool:
	return bool((values["interface"] as Dictionary).get(interface_key, false))


func apply_audio_to_runtime() -> void:
	var audio := values["audio"] as Dictionary
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, bool(audio["muted"]))
	for channel: String in AUDIO_CHANNELS:
		var bus_name := channel.capitalize()
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		var linear_value := float(audio[channel])
		AudioServer.set_bus_volume_db(bus_index, -80.0 if linear_value <= 0.0 else linear_to_db(linear_value))


func apply_display_to_runtime() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var display := values["display"] as Dictionary
	var mode := str(display["mode"])
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(
				Vector2i(int(display["window_width"]), int(display["window_height"]))
			)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(display["vsync"]) else DisplayServer.VSYNC_DISABLED
	)


func _is_loadable_document(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var document := value as Dictionary
	if not document.has("schema_version"):
		# Pre-release v0 settings had flat keys and no explicit version.
		return (
			document.has("master_volume")
			or document.has("fullscreen")
			or document.has("show_hints")
		)
	if not _is_number(document["schema_version"]):
		return false
	return int(document["schema_version"]) in [0, SCHEMA_VERSION]


func _normalize_document(document: Dictionary) -> Dictionary:
	var defaults := default_document()
	if not _is_loadable_document(document):
		return defaults
	var version := int(document.get("schema_version", 0))
	if version == 0:
		return _migrate_v0(document)

	var raw_audio_value: Variant = document.get("audio", {})
	var raw_audio: Dictionary = raw_audio_value as Dictionary if raw_audio_value is Dictionary else {}
	var audio := defaults["audio"] as Dictionary
	for channel: String in AUDIO_CHANNELS:
		audio[channel] = _normalized_float(raw_audio.get(channel), float(audio[channel]), 0.0, 1.0)
	audio["muted"] = _normalized_bool(raw_audio.get("muted"), bool(audio["muted"]))

	var raw_display_value: Variant = document.get("display", {})
	var raw_display: Dictionary = raw_display_value as Dictionary if raw_display_value is Dictionary else {}
	var display := defaults["display"] as Dictionary
	var mode := str(raw_display.get("mode", display["mode"]))
	display["mode"] = mode if mode in DISPLAY_MODES else display["mode"]
	var policy := str(raw_display.get("resolution_policy", display["resolution_policy"]))
	display["resolution_policy"] = (
		policy if policy in RESOLUTION_POLICIES else display["resolution_policy"]
	)
	display["window_width"] = _normalized_int(
		raw_display.get("window_width"), int(display["window_width"]), 800, 7680
	)
	display["window_height"] = _normalized_int(
		raw_display.get("window_height"), int(display["window_height"]), 600, 4320
	)
	display["vsync"] = _normalized_bool(raw_display.get("vsync"), bool(display["vsync"]))

	var raw_hints_value: Variant = document.get("hints", {})
	var raw_hints: Dictionary = raw_hints_value as Dictionary if raw_hints_value is Dictionary else {}
	var hints := defaults["hints"] as Dictionary
	for hint_key: String in HINT_KEYS:
		hints[hint_key] = _normalized_bool(raw_hints.get(hint_key), bool(hints[hint_key]))
	var raw_interface_value: Variant = document.get("interface", {})
	var raw_interface: Dictionary = raw_interface_value as Dictionary if raw_interface_value is Dictionary else {}
	var interface := defaults["interface"] as Dictionary
	for interface_key: String in INTERFACE_KEYS:
		interface[interface_key] = _normalized_bool(
			raw_interface.get(interface_key), bool(interface[interface_key])
		)
	return defaults


func _migrate_v0(document: Dictionary) -> Dictionary:
	var migrated := default_document()
	var audio := migrated["audio"] as Dictionary
	audio["master"] = _normalized_float(document.get("master_volume"), 1.0, 0.0, 1.0)
	var display := migrated["display"] as Dictionary
	display["mode"] = "fullscreen" if _normalized_bool(document.get("fullscreen"), true) else "windowed"
	var show_hints := _normalized_bool(document.get("show_hints"), true)
	var hints := migrated["hints"] as Dictionary
	for hint_key: String in HINT_KEYS:
		hints[hint_key] = show_hints
	return migrated


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _normalized_float(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not _is_number(value):
		return fallback
	return clampf(float(value), minimum, maximum)


static func _normalized_int(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if not _is_number(value):
		return fallback
	return clampi(int(value), minimum, maximum)


static func _normalized_bool(value: Variant, fallback: bool) -> bool:
	return bool(value) if value is bool else fallback
