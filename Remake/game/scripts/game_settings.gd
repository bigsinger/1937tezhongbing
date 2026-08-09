class_name GameSettings
extends RefCounted

const ATOMIC_JSON_STORE: Script = preload("res://scripts/atomic_json_store.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")

const SCHEMA_VERSION := 8
const DEFAULT_PATH := "user://settings.json"
const DISPLAY_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const RESOLUTION_POLICIES: Array[String] = ["desktop", "custom"]
const AUDIO_CHANNELS: Array[String] = ["master", "music", "sfx", "voice"]
const HINT_KEYS: Array[String] = ["controls", "objectives", "interactions"]
const INTERFACE_KEYS: Array[String] = [
	"subtitles",
	"environment_captions",
	"show_briefings",
	"edge_scroll",
	"reduce_camera_motion",
	"reduce_flashes",
	"large_cursor",
	"high_contrast",
	"colorblind_patterns",
	"pause_on_focus_loss",
	"educational_mode",
	"reduced_violence",
	"history_notes",
	"stealth_feedback",
]
const RULESET_MODES: Array[String] = ["classic", "modern"]
const DIFFICULTY_MODES: Array[String] = ["story", "normal", "hard", "custom"]
const LEGACY_DIFFICULTY_MODES: Array[String] = ["original", "easy"]
const CONTROL_SCHEMES: Array[String] = ["classic", "modern"]
const MISSION_RULE_MODES: Array[String] = ["stable_mod", "repaired"]
const LOCALES: Array[String] = ["system", "zh_CN", "en"]

var values: Dictionary = default_document()
var last_result: Dictionary = {}


static func default_document() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"localization": {"locale": "system"},
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
			"max_fps": 60,
			"monitor_index": -1,
		},
		"hints": {
			"controls": true,
			"objectives": true,
			"interactions": true,
		},
		"interface": {
			"subtitles": true,
			"environment_captions": true,
			"show_briefings": true,
			"edge_scroll": true,
			"reduce_camera_motion": false,
			"reduce_flashes": false,
			"large_cursor": false,
			"high_contrast": false,
			"colorblind_patterns": true,
			"pause_on_focus_loss": true,
			"educational_mode": true,
			"reduced_violence": false,
			"history_notes": true,
			"stealth_feedback": true,
			"ui_scale": 1.0,
			"text_scale": 1.0,
			"edge_scroll_speed": 720.0,
			"edge_scroll_margin": 32.0,
			"zoom_step": 0.25,
		},
		"gameplay": {
			# Rules and difficulty are independent. Classic preserves the audited
			# simulation contract; modern enables phased perception and modern
			# balancing while keeping the same maps and mission data.
			"ruleset_mode": "classic",
			"difficulty_mode": "normal",
			"control_scheme": "classic",
			"custom_difficulty": {
				"enemy_accuracy": 0.70,
				"reaction_multiplier": 1.0,
				"perception_multiplier": 1.0,
				"search_multiplier": 1.0,
				"alert_multiplier": 1.0,
				"reinforcement_multiplier": 1.0,
			},
			# Task control-flow is independent from combat difficulty. The
			# shipped default reproduces what the stable MOD actually evaluates;
			# repaired restores briefing/editorial intent for the explicit
			# m006/m008/m009/m011 control-flow forks.
			"mission_rule_mode": "stable_mod",
		},
		"controls": GAME_INPUT_BINDINGS.default_bindings(),
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


func set_locale(locale: String) -> bool:
	if locale not in LOCALES:
		return false
	(values["localization"] as Dictionary)["locale"] = locale
	return true


func locale() -> String:
	var selected := str(
		(values.get("localization", {}) as Dictionary).get("locale", "system")
	)
	return selected if selected in LOCALES else "system"


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


func set_max_fps(max_fps: int) -> void:
	(values["display"] as Dictionary)["max_fps"] = (
		0 if max_fps <= 0 else clampi(max_fps, 30, 360)
	)


func set_monitor_index(monitor_index: int) -> void:
	(values["display"] as Dictionary)["monitor_index"] = clampi(monitor_index, -1, 31)


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


func set_interface_scale(key: String, value: float) -> bool:
	if key not in ["ui_scale", "text_scale"]:
		return false
	(values["interface"] as Dictionary)[key] = clampf(value, 0.75, 2.0)
	return true


func interface_scale(key: String) -> float:
	if key not in ["ui_scale", "text_scale"]:
		return 1.0
	return float((values["interface"] as Dictionary).get(key, 1.0))


func set_camera_setting(key: String, value: float) -> bool:
	var ranges := {
		"edge_scroll_speed": Vector2(240.0, 1800.0),
		"edge_scroll_margin": Vector2(8.0, 96.0),
		"zoom_step": Vector2(0.05, 0.50),
	}
	if not ranges.has(key):
		return false
	var limits := ranges[key] as Vector2
	(values["interface"] as Dictionary)[key] = clampf(value, limits.x, limits.y)
	return true


func camera_setting(key: String, fallback: float = 0.0) -> float:
	return float((values["interface"] as Dictionary).get(key, fallback))


func set_ruleset_mode(mode: String) -> bool:
	if mode not in RULESET_MODES:
		return false
	(values["gameplay"] as Dictionary)["ruleset_mode"] = mode
	return true


func ruleset_mode() -> String:
	var mode := str((values["gameplay"] as Dictionary).get("ruleset_mode", "classic"))
	return mode if mode in RULESET_MODES else "classic"


func set_difficulty_mode(mode: String) -> bool:
	# Accept pre-schema-6 names at API boundaries so old test harnesses and
	# user scripts migrate without silently losing their intent.
	if mode == "original":
		set_ruleset_mode("classic")
		mode = "normal"
	elif mode == "easy":
		set_ruleset_mode("modern")
		mode = "story"
	if mode not in DIFFICULTY_MODES:
		return false
	(values["gameplay"] as Dictionary)["difficulty_mode"] = mode
	return true


func difficulty_mode() -> String:
	var mode := str((values["gameplay"] as Dictionary).get("difficulty_mode", "normal"))
	return mode if mode in DIFFICULTY_MODES else "normal"


func effective_legacy_difficulty_mode() -> String:
	if ruleset_mode() == "classic":
		return "original"
	var mode := difficulty_mode()
	return "easy" if mode == "story" else "normal" if mode == "custom" else mode


func set_control_scheme(scheme: String) -> bool:
	if scheme not in CONTROL_SCHEMES:
		return false
	(values["gameplay"] as Dictionary)["control_scheme"] = scheme
	return true


func control_scheme() -> String:
	var scheme := str((values["gameplay"] as Dictionary).get("control_scheme", "classic"))
	return scheme if scheme in CONTROL_SCHEMES else "classic"


func set_custom_difficulty(values_override: Dictionary) -> void:
	var custom := (values["gameplay"] as Dictionary)["custom_difficulty"] as Dictionary
	for key: String in custom.keys():
		if values_override.get(key) is int or values_override.get(key) is float:
			custom[key] = clampf(float(values_override[key]), 0.25, 2.0)


func custom_difficulty() -> Dictionary:
	return (
		(values["gameplay"] as Dictionary).get("custom_difficulty", {}) as Dictionary
	).duplicate(true)


func set_mission_rule_mode(mode: String) -> bool:
	if not mode in MISSION_RULE_MODES:
		return false
	(values["gameplay"] as Dictionary)["mission_rule_mode"] = mode
	return true


func mission_rule_mode() -> String:
	var mode := str(
		(values["gameplay"] as Dictionary).get("mission_rule_mode", "stable_mod")
	)
	return mode if mode in MISSION_RULE_MODES else "stable_mod"


func controls_snapshot() -> Dictionary:
	return (values.get("controls", {}) as Dictionary).duplicate(true)


func set_controls(bindings: Dictionary) -> void:
	values["controls"] = GAME_INPUT_BINDINGS.normalize_bindings(bindings)


func set_control_binding(action: String, binding: Dictionary) -> bool:
	if not action in GAME_INPUT_BINDINGS.action_ids():
		return false
	var raw_keycode: Variant = binding.get("keycode")
	if (
		not (raw_keycode is int or raw_keycode is float)
		or int(raw_keycode) <= 0
	):
		return false
	var normalized_single: Dictionary = GAME_INPUT_BINDINGS.normalize_bindings({action: binding})
	var normalized_binding := normalized_single[action] as Dictionary
	if int(normalized_binding.get("keycode", 0)) <= 0:
		return false
	var controls := values["controls"] as Dictionary
	var conflict: String = GAME_INPUT_BINDINGS.conflicting_action(
		controls, normalized_binding, action
	)
	# Swapping is less destructive than silently unbinding the conflicting
	# action and guarantees that every command stays reachable.
	if not conflict.is_empty():
		controls[conflict] = (controls[action] as Dictionary).duplicate(true)
	controls[action] = normalized_binding.duplicate(true)
	return true


func reset_controls() -> void:
	values["controls"] = GAME_INPUT_BINDINGS.default_bindings()


func apply_audio_to_runtime() -> void:
	_ensure_audio_buses()
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


static func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Sfx", "Voice"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, "Master")


func apply_display_to_runtime() -> void:
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = int((values["display"] as Dictionary).get("max_fps", 60))
		return
	var display := values["display"] as Dictionary
	var mode := str(display["mode"])
	var requested_screen := int(display.get("monitor_index", -1))
	if requested_screen >= 0 and requested_screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(requested_screen)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == "borderless")
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var requested_size := Vector2i(
				int(display["window_width"]), int(display["window_height"])
			)
			if str(display.get("resolution_policy", "desktop")) == "desktop":
				var usable := DisplayServer.screen_get_usable_rect(
					DisplayServer.window_get_current_screen()
				)
				requested_size = Vector2i(
					maxi(800, floori(float(usable.size.x) * 0.85)),
					maxi(600, floori(float(usable.size.y) * 0.85)),
				)
			DisplayServer.window_set_size(requested_size)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(display["vsync"]) else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = int(display.get("max_fps", 60))


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
	return int(document["schema_version"]) in [0, 1, 2, 3, 4, 5, 6, 7, SCHEMA_VERSION]


func _normalize_document(document: Dictionary) -> Dictionary:
	var defaults := default_document()
	if not _is_loadable_document(document):
		return defaults
	var version := int(document.get("schema_version", 0))
	if version == 0:
		return _migrate_v0(document)
	var raw_localization_value: Variant = document.get("localization", {})
	var raw_localization := (
		raw_localization_value as Dictionary
		if raw_localization_value is Dictionary
		else {}
	)
	var locale_value := str(raw_localization.get("locale", "system"))
	(defaults["localization"] as Dictionary)["locale"] = (
		locale_value if locale_value in LOCALES else "system"
	)

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
	var raw_max_fps := _normalized_int(
		raw_display.get("max_fps"), int(display["max_fps"]), 0, 360
	)
	display["max_fps"] = 0 if raw_max_fps <= 0 else maxi(raw_max_fps, 30)
	display["monitor_index"] = _normalized_int(
		raw_display.get("monitor_index"), int(display["monitor_index"]), -1, 31
	)

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
	for scale_key: String in ["ui_scale", "text_scale"]:
		interface[scale_key] = _normalized_float(
			raw_interface.get(scale_key), float(interface[scale_key]), 0.75, 2.0
		)
	interface["edge_scroll_speed"] = _normalized_float(
		raw_interface.get("edge_scroll_speed"),
		float(interface["edge_scroll_speed"]),
		240.0,
		1800.0,
	)
	interface["edge_scroll_margin"] = _normalized_float(
		raw_interface.get("edge_scroll_margin"),
		float(interface["edge_scroll_margin"]),
		8.0,
		96.0,
	)
	interface["zoom_step"] = _normalized_float(
		raw_interface.get("zoom_step"),
		float(interface["zoom_step"]),
		0.05,
		0.50,
	)
	var raw_gameplay_value: Variant = document.get("gameplay", {})
	var raw_gameplay: Dictionary = (
		raw_gameplay_value as Dictionary if raw_gameplay_value is Dictionary else {}
	)
	var gameplay := defaults["gameplay"] as Dictionary
	var ruleset_mode := str(raw_gameplay.get("ruleset_mode", gameplay["ruleset_mode"]))
	var difficulty_mode := str(raw_gameplay.get("difficulty_mode", gameplay["difficulty_mode"]))
	# Schema 0..5 encoded the classic contract as a difficulty named original.
	if difficulty_mode == "original":
		ruleset_mode = "classic"
		difficulty_mode = "normal"
	elif difficulty_mode == "easy":
		ruleset_mode = "modern"
		difficulty_mode = "story"
	gameplay["ruleset_mode"] = (
		ruleset_mode if ruleset_mode in RULESET_MODES else gameplay["ruleset_mode"]
	)
	gameplay["difficulty_mode"] = (
		difficulty_mode if difficulty_mode in DIFFICULTY_MODES else gameplay["difficulty_mode"]
	)
	var control_scheme := str(raw_gameplay.get("control_scheme", gameplay["control_scheme"]))
	gameplay["control_scheme"] = (
		control_scheme if control_scheme in CONTROL_SCHEMES else gameplay["control_scheme"]
	)
	var raw_custom_value: Variant = raw_gameplay.get("custom_difficulty", {})
	var raw_custom := raw_custom_value as Dictionary if raw_custom_value is Dictionary else {}
	var custom := gameplay["custom_difficulty"] as Dictionary
	for custom_key: String in custom.keys():
		custom[custom_key] = _normalized_float(
			raw_custom.get(custom_key), float(custom[custom_key]), 0.25, 2.0
		)
	var mission_rule_mode := str(
		raw_gameplay.get("mission_rule_mode", gameplay["mission_rule_mode"])
	)
	gameplay["mission_rule_mode"] = (
		mission_rule_mode
		if mission_rule_mode in MISSION_RULE_MODES
		else gameplay["mission_rule_mode"]
	)
	defaults["controls"] = GAME_INPUT_BINDINGS.normalize_bindings(document.get("controls", {}))
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
