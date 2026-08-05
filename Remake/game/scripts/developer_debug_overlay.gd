class_name DeveloperDebugOverlay
extends CanvasLayer

const REFRESH_SECONDS := 0.25

var source: Node
var enabled_for_run := false
var refresh_remaining := 0.0
var panel: PanelContainer
var label: RichTextLabel


func configure(new_source: Node, force_enable: bool = false) -> void:
	source = new_source
	enabled_for_run = OS.is_debug_build() or force_enable
	visible = false
	set_process(enabled_for_run)
	set_process_unhandled_input(enabled_for_run)


func _ready() -> void:
	layer = 240
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "DeveloperDiagnosticsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12.0, 12.0)
	panel.size = Vector2(520.0, 310.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.022, 0.90)
	style.border_color = Color(0.25, 0.85, 0.55, 0.90)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = false
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 14)
	label.add_theme_color_override("default_color", Color(0.86, 0.94, 0.86))
	panel.add_child(label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled_for_run or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F10:
		visible = not visible
		refresh_remaining = 0.0
		if source != null and source.has_method("set_developer_debug_enabled"):
			source.call("set_developer_debug_enabled", visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or source == null:
		return
	refresh_remaining -= maxf(delta, 0.0)
	if refresh_remaining > 0.0:
		return
	refresh_remaining = REFRESH_SECONDS
	if not source.has_method("modern_debug_snapshot"):
		return
	var snapshot := source.call("modern_debug_snapshot") as Dictionary
	label.text = _format_snapshot(snapshot)


static func _format_snapshot(snapshot: Dictionary) -> String:
	var performance := snapshot.get("performance", {}) as Dictionary
	var frame := performance.get("frame", {}) as Dictionary
	var engine := performance.get("engine", {}) as Dictionary
	var services := snapshot.get("services", {}) as Dictionary
	var spatial := services.get("spatial_index", {}) as Dictionary
	var navigation := services.get("navigation_requests", {}) as Dictionary
	var ai := snapshot.get("ai", {}) as Dictionary
	var lines: Array[String] = [
		"[color=#7ff0a8][b]%s[/b][/color]" % _text("DEBUG_TITLE"),
		_text("DEBUG_MISSION") % [
			str(snapshot.get("level_id", "-")),
			str(snapshot.get("ruleset", "-")),
			str(snapshot.get("difficulty", "-")),
		],
		"FPS %.1f　CPU frame P95 %.2f ms　P99 %.2f ms" % [
			float(engine.get("fps", 0.0)),
			float(frame.get("p95_ms", 0.0)),
			float(frame.get("p99_ms", 0.0)),
		],
		_text("DEBUG_RESOURCES") % [
			int(engine.get("object_count", 0)),
			int(engine.get("draw_calls", 0)),
			float(engine.get("static_memory_bytes", 0)) / 1048576.0,
		],
		_text("DEBUG_SERVICES") % [
			int(spatial.get("nodes", spatial.get("registered_nodes", 0))),
			int(spatial.get("cells", spatial.get("bucket_count", 0))),
			int(navigation.get("pending", navigation.get("pending_count", 0))),
		],
		_text("DEBUG_SELECTION") % [
			int(snapshot.get("selected_units", 0)),
			int(snapshot.get("selected_path_points", 0)),
			int(ai.get("scene_index", -1)),
		],
		_text("DEBUG_AI") % [
			str(ai.get("behavior", "-")),
			float(ai.get("suspicion", 0.0)) * 100.0,
			float(ai.get("memory_seconds", 0.0)),
			str(ai.get("search_role", "-")),
		],
		_text("DEBUG_FORMATION") % [
			str(ai.get("formation_role", "-")),
			float(ai.get("hit_chance", 0.0)) * 100.0,
			str(ai.get("last_known_position", Vector2.ZERO)),
		],
		"[color=#a9b8aa]%s[/color]" % _text("DEBUG_LEGEND"),
	]
	return "\n".join(lines)


static func _text(key: String) -> String:
	return str(TranslationServer.translate(StringName(key)))
