class_name GameShell
extends CanvasLayer

signal resume_requested
signal save_requested
signal load_requested
signal restart_requested
signal quit_requested
signal settings_changed(settings: Dictionary)
signal map_position_requested(world_position: Vector2)
signal inventory_cycle_requested(direction: int)
signal inventory_reload_requested

const TACTICAL_MAP_VIEW_SCRIPT: Script = preload("res://scripts/tactical_map_view.gd")

enum OverlayMode { NONE, PAUSE_MENU, TACTICAL_MAP, INVENTORY, FAILURE }

var overlay_mode := OverlayMode.NONE
var settings: Dictionary = {}

var _root: Control
var _dim: ColorRect
var _failure_desaturate: ColorRect
var _menu_panel: PanelContainer
var _menu_title: Label
var _menu_message: Label
var _resume_button: Button
var _save_button: Button
var _load_button: Button
var _restart_button: Button
var _fullscreen_toggle: CheckButton
var _subtitles_toggle: CheckButton
var _briefings_toggle: CheckButton
var _edge_scroll_toggle: CheckButton
var _master_volume_slider: HSlider
var _volume_value_label: Label
var _map_panel: PanelContainer
var _map_view: TacticalMapView
var _inventory_panel: PanelContainer
var _inventory_text: RichTextLabel
var _pause_owned := false
var _pause_state_before_overlay := false
var _updating_settings_controls := false


func _ready() -> void:
	layer = 180
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_interface()
	set_settings({})


func set_settings(new_settings: Dictionary) -> void:
	settings = {
		"fullscreen": bool(new_settings.get("fullscreen", false)),
		"subtitles": bool(new_settings.get("subtitles", true)),
		"show_briefings": bool(new_settings.get("show_briefings", true)),
		"edge_scroll": bool(new_settings.get("edge_scroll", true)),
		"master_volume": clampf(float(new_settings.get("master_volume", 0.8)), 0.0, 1.0),
	}
	if _root == null:
		return
	_updating_settings_controls = true
	_fullscreen_toggle.button_pressed = bool(settings["fullscreen"])
	_subtitles_toggle.button_pressed = bool(settings["subtitles"])
	_briefings_toggle.button_pressed = bool(settings["show_briefings"])
	_edge_scroll_toggle.button_pressed = bool(settings["edge_scroll"])
	_master_volume_slider.value = float(settings["master_volume"])
	_update_volume_label()
	_updating_settings_controls = false


func settings_snapshot() -> Dictionary:
	return settings.duplicate(true)


func show_pause_menu(can_load: bool, message: String = "") -> void:
	_enter_mode(OverlayMode.PAUSE_MENU)
	_menu_title.text = "游戏菜单"
	_menu_message.text = message if not message.is_empty() else "游戏已暂停"
	_resume_button.visible = true
	_save_button.visible = true
	_load_button.disabled = not can_load
	_resume_button.grab_focus()


func show_failure(failure_text: String, can_load: bool) -> void:
	_enter_mode(OverlayMode.FAILURE)
	_menu_title.text = "任务失败"
	_menu_message.text = failure_text
	_resume_button.visible = false
	_save_button.visible = false
	_load_button.disabled = not can_load
	if can_load:
		_load_button.grab_focus()
	else:
		_restart_button.grab_focus()


func show_tactical_map(
	terrain_texture: Texture2D,
	world_size: Vector2,
	actor_markers: Array[Dictionary],
	mission_markers: Array[Dictionary],
	camera_world_rect: Rect2,
) -> void:
	_enter_mode(OverlayMode.TACTICAL_MAP)
	_map_view.configure(
		terrain_texture,
		world_size,
		actor_markers,
		mission_markers,
		camera_world_rect,
	)


func update_map_camera(camera_world_rect: Rect2) -> void:
	if _map_view != null:
		_map_view.update_camera_world_rect(camera_world_rect)


func show_inventory(inventory_bbcode: String) -> void:
	_enter_mode(OverlayMode.INVENTORY)
	_inventory_text.text = inventory_bbcode


func update_inventory(inventory_bbcode: String) -> void:
	if _inventory_text != null:
		_inventory_text.text = inventory_bbcode


func set_menu_message(message: String) -> void:
	if _menu_message != null:
		_menu_message.text = message


func is_overlay_open() -> bool:
	return overlay_mode != OverlayMode.NONE


func is_failure_open() -> bool:
	return overlay_mode == OverlayMode.FAILURE


func close_active_overlay() -> bool:
	if overlay_mode in [OverlayMode.NONE, OverlayMode.FAILURE]:
		return false
	_close_overlay()
	resume_requested.emit()
	return true


func close_for_state_change() -> void:
	if overlay_mode != OverlayMode.NONE:
		_close_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if overlay_mode == OverlayMode.NONE:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if overlay_mode == OverlayMode.FAILURE and key_event.keycode == KEY_R:
		_on_restart_pressed()
		get_viewport().set_input_as_handled()
		return
	var should_close := (
		key_event.keycode == KEY_ESCAPE
		or (overlay_mode == OverlayMode.TACTICAL_MAP and key_event.keycode == KEY_M)
		or (
			overlay_mode == OverlayMode.INVENTORY
			and key_event.keycode in [KEY_B, KEY_I]
		)
	)
	if should_close and close_active_overlay():
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_release_pause()


func _enter_mode(mode: int) -> void:
	_acquire_pause()
	overlay_mode = mode
	_root.visible = true
	_dim.visible = mode != OverlayMode.FAILURE
	_failure_desaturate.visible = mode == OverlayMode.FAILURE
	_menu_panel.visible = mode in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]
	_map_panel.visible = mode == OverlayMode.TACTICAL_MAP
	_inventory_panel.visible = mode == OverlayMode.INVENTORY


func _close_overlay() -> void:
	overlay_mode = OverlayMode.NONE
	if _root != null:
		_root.visible = false
	_release_pause()


func _acquire_pause() -> void:
	if _pause_owned:
		return
	var tree := get_tree()
	if tree == null:
		return
	_pause_state_before_overlay = tree.paused
	_pause_owned = true
	tree.paused = true


func _release_pause() -> void:
	if not _pause_owned:
		return
	var tree := get_tree()
	if tree != null:
		tree.paused = _pause_state_before_overlay
	_pause_owned = false


func _on_resume_pressed() -> void:
	if overlay_mode == OverlayMode.FAILURE:
		return
	_close_overlay()
	resume_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	load_requested.emit()


func _on_restart_pressed() -> void:
	_close_overlay()
	restart_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_setting_changed(_value: Variant = null) -> void:
	if _updating_settings_controls:
		return
	settings = {
		"fullscreen": _fullscreen_toggle.button_pressed,
		"subtitles": _subtitles_toggle.button_pressed,
		"show_briefings": _briefings_toggle.button_pressed,
		"edge_scroll": _edge_scroll_toggle.button_pressed,
		"master_volume": clampf(float(_master_volume_slider.value), 0.0, 1.0),
	}
	_update_volume_label()
	settings_changed.emit(settings_snapshot())


func _update_volume_label() -> void:
	if _volume_value_label != null and _master_volume_slider != null:
		_volume_value_label.text = "%d%%" % roundi(float(_master_volume_slider.value) * 100.0)


func _on_map_position_requested(world_position: Vector2) -> void:
	map_position_requested.emit(world_position)


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "GameShellRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_failure_desaturate = ColorRect.new()
	_failure_desaturate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_failure_desaturate.mouse_filter = Control.MOUSE_FILTER_STOP
	_failure_desaturate.material = _failure_shader_material()
	_root.add_child(_failure_desaturate)

	_dim = ColorRect.new()
	_dim.color = Color(0.018, 0.024, 0.020, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_build_menu_panel()
	_build_map_panel()
	_build_inventory_panel()
	_root.visible = false


func _build_menu_panel() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "GameMenuPanel"
	_center_control(_menu_panel, Vector2(560.0, 650.0))
	_menu_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.115, 0.09, 0.98)))
	_root.add_child(_menu_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	_menu_panel.add_child(content)

	_menu_title = Label.new()
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_title.add_theme_font_size_override("font_size", 30)
	_menu_title.add_theme_color_override("font_color", Color(0.97, 0.88, 0.61))
	content.add_child(_menu_title)

	_menu_message = Label.new()
	_menu_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_message.custom_minimum_size = Vector2(0.0, 42.0)
	content.add_child(_menu_message)

	_resume_button = _add_button(content, "继续游戏", _on_resume_pressed)
	_save_button = _add_button(content, "保存当前进度（F5）", _on_save_pressed)
	_load_button = _add_button(content, "读取最近存档（F9）", _on_load_pressed)
	_restart_button = _add_button(content, "重新开始本关", _on_restart_pressed)

	var separator := HSeparator.new()
	content.add_child(separator)
	var settings_title := Label.new()
	settings_title.text = "显示与辅助设置"
	settings_title.add_theme_font_size_override("font_size", 18)
	content.add_child(settings_title)

	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.text = "全屏（使用当前桌面分辨率）"
	_fullscreen_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_fullscreen_toggle)

	_subtitles_toggle = CheckButton.new()
	_subtitles_toggle.text = "显示语音字幕"
	_subtitles_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_subtitles_toggle)

	_briefings_toggle = CheckButton.new()
	_briefings_toggle.text = "切换关卡时显示任务简报"
	_briefings_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_briefings_toggle)

	_edge_scroll_toggle = CheckButton.new()
	_edge_scroll_toggle.text = "鼠标移动到屏幕边缘时卷屏"
	_edge_scroll_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_edge_scroll_toggle)

	var volume_row := HBoxContainer.new()
	var volume_label := Label.new()
	volume_label.text = "主音量"
	volume_label.custom_minimum_size.x = 88.0
	volume_row.add_child(volume_label)
	_master_volume_slider = HSlider.new()
	_master_volume_slider.min_value = 0.0
	_master_volume_slider.max_value = 1.0
	_master_volume_slider.step = 0.05
	_master_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_master_volume_slider.value_changed.connect(_on_setting_changed)
	volume_row.add_child(_master_volume_slider)
	_volume_value_label = Label.new()
	_volume_value_label.custom_minimum_size.x = 52.0
	_volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_value_label)
	content.add_child(volume_row)

	_add_button(content, "退出游戏", _on_quit_pressed)


func _build_map_panel() -> void:
	_map_panel = PanelContainer.new()
	_map_panel.name = "TacticalMapPanel"
	_map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_panel.offset_left = 30.0
	_map_panel.offset_top = 24.0
	_map_panel.offset_right = -30.0
	_map_panel.offset_bottom = -24.0
	_map_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.065, 0.052, 0.99)))
	_root.add_child(_map_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_map_panel.add_child(content)
	var title := Label.new()
	title.text = "战术地图"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	_map_view = TACTICAL_MAP_VIEW_SCRIPT.new()
	_map_view.custom_minimum_size = Vector2(640.0, 420.0)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.world_position_requested.connect(_on_map_position_requested)
	content.add_child(_map_view)
	var help := Label.new()
	help.text = "蓝色：我方　红色：敌军　黄色菱形：任务位置　浅色框：当前视野　｜　单击地图移动视野　｜　M / Esc 返回"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(help)
	_add_button(content, "关闭地图", _on_resume_pressed)


func _build_inventory_panel() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_center_control(_inventory_panel, Vector2(920.0, 610.0))
	_inventory_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.085, 0.065, 0.99)))
	_root.add_child(_inventory_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_inventory_panel.add_child(content)
	var title := Label.new()
	title.text = "小队背包"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	_inventory_text = RichTextLabel.new()
	_inventory_text.bbcode_enabled = true
	_inventory_text.fit_content = false
	_inventory_text.scroll_active = true
	_inventory_text.selection_enabled = true
	_inventory_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_text.add_theme_font_size_override("normal_font_size", 17)
	content.add_child(_inventory_text)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	_add_button(actions, "上一件武器", func() -> void: inventory_cycle_requested.emit(-1))
	_add_button(actions, "下一件武器", func() -> void: inventory_cycle_requested.emit(1))
	_add_button(actions, "为选中队员换弹", func() -> void: inventory_reload_requested.emit())
	_add_button(actions, "关闭（B / I / Esc）", _on_resume_pressed)


func _add_button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _center_control(control: Control, dimensions: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.offset_left = -dimensions.x * 0.5
	control.offset_top = -dimensions.y * 0.5
	control.offset_right = dimensions.x * 0.5
	control.offset_bottom = dimensions.y * 0.5


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.55, 0.57, 0.43, 0.78)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style


func _failure_shader_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(gray) * 0.48, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
