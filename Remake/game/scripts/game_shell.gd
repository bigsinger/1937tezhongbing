class_name GameShell
extends CanvasLayer

signal resume_requested
signal save_requested
signal load_requested
signal save_slot_requested(slot_id: String)
signal load_slot_requested(slot_id: String)
signal restart_requested
signal next_level_requested
signal quit_requested
signal settings_changed(settings: Dictionary)
signal map_position_requested(world_position: Vector2)
signal inventory_cycle_requested(direction: int)
signal inventory_reload_requested
signal inventory_slot_requested(slot: Dictionary)

const TACTICAL_MAP_VIEW_SCRIPT: Script = preload("res://scripts/tactical_map_view.gd")
const SAVE_SLOT_SELECTOR_SCRIPT: Script = preload("res://scripts/save_slot_selector.gd")
const INVENTORY_GRID_VIEW_SCRIPT: Script = preload("res://scripts/inventory_grid_view.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const ORIGINAL_INVENTORY_POPUP_SIZE := Vector2(276.0, 421.0)
const ORIGINAL_BOTTOM_HUD_HEIGHT := 62.0
const TACTICAL_MAP_PANEL_CHROME := Vector2(44.0, 77.0)

enum OverlayMode { NONE, PAUSE_MENU, TACTICAL_MAP, INVENTORY, FAILURE, SLOT_SELECTOR, SETTINGS, HELP }

var overlay_mode := OverlayMode.NONE
var settings: Dictionary = {}

var _root: Control
var _hud_root: Control
var _dim: ColorRect
var _failure_desaturate: ColorRect
var _menu_panel: PanelContainer
var _menu_title: Label
var _menu_message: Label
var _resume_button: Button
var _next_level_button: Button
var _save_button: Button
var _load_button: Button
var _restart_button: Button
var _fullscreen_toggle: CheckButton
var _subtitles_toggle: CheckButton
var _briefings_toggle: CheckButton
var _edge_scroll_toggle: CheckButton
var _muted_toggle: CheckButton
var _master_volume_slider: HSlider
var _volume_value_label: Label
var _audio_sliders: Dictionary = {}
var _audio_value_labels: Dictionary = {}
var _settings_panel: PanelContainer
var _settings_return_mode := OverlayMode.PAUSE_MENU
var _control_buttons: Dictionary = {}
var _capturing_action := ""
var _settings_status: Label
var _map_panel: PanelContainer
var _map_view: TacticalMapView
var _map_requested_visible := false
var _inventory_panel: PanelContainer
var _inventory_view: InventoryGridView
var _inventory_mode := "items"
var _help_panel: PanelContainer
var _help_texture: TextureRect
var _help_fallback: Label
var _slot_selector_panel: PanelContainer
var _slot_selector: SaveSlotSelector
var _slot_return_mode := OverlayMode.PAUSE_MENU
var _save_slot_summaries: Array[Dictionary] = []
var _pause_owned := false
var _pause_state_before_overlay := false
var _updating_settings_controls := false
var _suppress_release_keycode := 0


func _ready() -> void:
	layer = 180
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build_interface()
	set_settings({})


func set_settings(new_settings: Dictionary) -> void:
	var display_mode := str(new_settings.get(
		"display_mode",
		"fullscreen" if bool(new_settings.get("fullscreen", false)) else "windowed",
	))
	if display_mode not in ["windowed", "fullscreen", "borderless"]:
		display_mode = "windowed"
	var resolution_policy := str(new_settings.get("resolution_policy", "desktop"))
	if resolution_policy not in ["desktop", "custom"]:
		resolution_policy = "desktop"
	settings = {
		"fullscreen": display_mode != "windowed",
		"display_mode": display_mode,
		"muted": bool(new_settings.get("muted", false)),
		"resolution_policy": resolution_policy,
		"window_width": clampi(int(new_settings.get("window_width", 1280)), 800, 7680),
		"window_height": clampi(int(new_settings.get("window_height", 720)), 600, 4320),
		"vsync": bool(new_settings.get("vsync", true)),
		"subtitles": bool(new_settings.get("subtitles", true)),
		"show_briefings": bool(new_settings.get("show_briefings", true)),
		"edge_scroll": bool(new_settings.get("edge_scroll", true)),
		"master_volume": clampf(float(new_settings.get("master_volume", 0.8)), 0.0, 1.0),
		"music_volume": clampf(float(new_settings.get("music_volume", 0.8)), 0.0, 1.0),
		"sfx_volume": clampf(float(new_settings.get("sfx_volume", 0.9)), 0.0, 1.0),
		"voice_volume": clampf(float(new_settings.get("voice_volume", 1.0)), 0.0, 1.0),
		"controls": GAME_INPUT_BINDINGS.normalize_bindings(new_settings.get("controls", {})),
	}
	if _root == null:
		return
	_updating_settings_controls = true
	_fullscreen_toggle.button_pressed = bool(settings["fullscreen"])
	_subtitles_toggle.button_pressed = bool(settings["subtitles"])
	_briefings_toggle.button_pressed = bool(settings["show_briefings"])
	_edge_scroll_toggle.button_pressed = bool(settings["edge_scroll"])
	_muted_toggle.button_pressed = bool(settings["muted"])
	for channel: String in ["master", "music", "sfx", "voice"]:
		if _audio_sliders.has(channel):
			(_audio_sliders[channel] as HSlider).value = float(settings["%s_volume" % channel])
	_update_volume_labels()
	_update_control_buttons()
	_updating_settings_controls = false


func settings_snapshot() -> Dictionary:
	return settings.duplicate(true)


func show_pause_menu(can_load: bool, message: String = "") -> void:
	_enter_mode(OverlayMode.PAUSE_MENU)
	_menu_title.text = "游戏菜单"
	_menu_message.text = message if not message.is_empty() else "游戏已暂停"
	_resume_button.visible = true
	_next_level_button.visible = false
	_save_button.visible = true
	_load_button.disabled = not can_load
	_resume_button.grab_focus()


func show_victory(can_load: bool, has_next_level: bool) -> void:
	_enter_mode(OverlayMode.PAUSE_MENU)
	_menu_title.text = "任务完成" if has_next_level else "战役完成"
	_menu_message.text = (
		"进度已自动保存，可以进入下一关。"
		if has_next_level
		else "十二关任务已经全部完成，可以读取存档或返回战场查看。"
	)
	_resume_button.visible = true
	_next_level_button.visible = has_next_level
	_save_button.visible = true
	_load_button.disabled = not can_load
	if has_next_level:
		_next_level_button.grab_focus()
	else:
		_resume_button.grab_focus()


func set_save_slots(summaries: Array[Dictionary]) -> void:
	_save_slot_summaries = summaries.duplicate(true)


func show_failure(failure_text: String, can_load: bool) -> void:
	_enter_mode(OverlayMode.FAILURE)
	_menu_title.text = "任务失败"
	_menu_message.text = failure_text
	_resume_button.visible = false
	_next_level_button.visible = false
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
	_resize_tactical_map(terrain_texture)
	_map_requested_visible = true
	_map_panel.visible = overlay_mode == OverlayMode.NONE
	_map_view.configure(
		terrain_texture,
		world_size,
		actor_markers,
		mission_markers,
		camera_world_rect,
	)


func toggle_tactical_map(
	terrain_texture: Texture2D,
	world_size: Vector2,
	actor_markers: Array[Dictionary],
	mission_markers: Array[Dictionary],
	camera_world_rect: Rect2,
) -> bool:
	_map_requested_visible = not _map_requested_visible
	_map_panel.visible = _map_requested_visible and overlay_mode == OverlayMode.NONE
	if _map_requested_visible:
		_resize_tactical_map(terrain_texture)
		_map_view.configure(
			terrain_texture,
			world_size,
			actor_markers,
			mission_markers,
			camera_world_rect,
		)
	return _map_requested_visible


func update_tactical_map(
	actor_markers: Array[Dictionary],
	mission_markers: Array[Dictionary],
	camera_world_rect: Rect2,
) -> void:
	if _map_view == null:
		return
	_map_view.update_markers(actor_markers, mission_markers)
	_map_view.update_camera_world_rect(camera_world_rect)


func hide_tactical_map() -> void:
	_map_requested_visible = false
	if _map_panel != null:
		_map_panel.visible = false


func is_tactical_map_visible() -> bool:
	return _map_requested_visible and _map_panel != null and _map_panel.visible


func update_map_camera(camera_world_rect: Rect2) -> void:
	if _map_view != null:
		_map_view.update_camera_world_rect(camera_world_rect)


func show_inventory(inventory_data: Variant, requested_mode: String = "items") -> void:
	_enter_mode(OverlayMode.INVENTORY)
	_inventory_mode = requested_mode if requested_mode in ["weapons", "items"] else "items"
	_inventory_view.configure(_normalized_inventory_model(inventory_data), _inventory_mode)
	_inventory_view.focus_first_slot()


func update_inventory(inventory_data: Variant, requested_mode: String = "") -> void:
	if _inventory_view == null:
		return
	if requested_mode in ["weapons", "items"]:
		_inventory_mode = requested_mode
	_inventory_view.configure(_normalized_inventory_model(inventory_data), _inventory_mode)
	_inventory_view.focus_first_slot()


func show_control_guide(original_help_texture: Texture2D = null) -> void:
	_enter_mode(OverlayMode.HELP)
	_help_texture.texture = original_help_texture
	_help_texture.visible = original_help_texture != null
	_help_fallback.visible = original_help_texture == null


func _normalized_inventory_model(inventory_data: Variant) -> Dictionary:
	if inventory_data is Dictionary:
		return (inventory_data as Dictionary).duplicate(true)
	# Compatibility with pre-grid callers and old saves under test.  The text is
	# still represented as a real grid cell instead of reverting to a text dump.
	return {
		"actor_name": "当前队员",
		"groups": [
			{
				"title": "当前状态",
				"mode": _inventory_mode,
				"slots": [
					{
						"label": str(inventory_data),
						"short_label": str(inventory_data).left(6),
						"description": str(inventory_data),
						"enabled": false,
					}
				],
			}
		],
	}


func set_menu_message(message: String) -> void:
	if _menu_message != null:
		_menu_message.text = message


func is_overlay_open() -> bool:
	return overlay_mode != OverlayMode.NONE


func is_failure_open() -> bool:
	return (
		overlay_mode == OverlayMode.FAILURE
		or (overlay_mode == OverlayMode.SLOT_SELECTOR and _slot_return_mode == OverlayMode.FAILURE)
	)


func close_active_overlay() -> bool:
	if overlay_mode in [OverlayMode.NONE, OverlayMode.FAILURE]:
		return false
	if overlay_mode == OverlayMode.SLOT_SELECTOR:
		_return_from_slot_selector()
		return true
	if overlay_mode == OverlayMode.SETTINGS:
		_return_from_settings()
		return true
	_close_overlay()
	resume_requested.emit()
	return true


func close_for_state_change() -> void:
	hide_tactical_map()
	if overlay_mode != OverlayMode.NONE:
		_close_overlay()


func _input(event: InputEvent) -> void:
	if overlay_mode == OverlayMode.NONE or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if (
		not mouse_event.pressed
		and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		and close_active_overlay()
	):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if overlay_mode == OverlayMode.NONE:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	if overlay_mode == OverlayMode.SETTINGS and not _capturing_action.is_empty():
		if not key_event.pressed:
			return
		if key_event.keycode == KEY_BACKSPACE:
			_cancel_binding_capture("已取消重新绑定")
		else:
			_apply_captured_binding(key_event)
		get_viewport().set_input_as_handled()
		return
	var event_binding: Dictionary = GAME_INPUT_BINDINGS.binding_from_event(key_event)
	if (
		not key_event.pressed
		and _suppress_release_keycode > 0
		and int(event_binding.get("keycode", 0)) == _suppress_release_keycode
	):
		_suppress_release_keycode = 0
		get_viewport().set_input_as_handled()
		return
	var bound_action: String = GAME_INPUT_BINDINGS.action_for_event(
		key_event, settings.get("controls", {}) as Dictionary
	)
	var bound_action_triggered: bool = GAME_INPUT_BINDINGS.should_trigger_for_event(
		bound_action, key_event
	)
	if (
		overlay_mode == OverlayMode.INVENTORY
		and bound_action_triggered
		and bound_action in ["weapon_inventory", "item_inventory"]
	):
		var requested_mode := "weapons" if bound_action == "weapon_inventory" else "items"
		if requested_mode == _inventory_mode:
			close_active_overlay()
		else:
			_inventory_mode = requested_mode
			_inventory_view.configure(_inventory_view.model, _inventory_mode)
			_inventory_view.focus_first_slot()
		get_viewport().set_input_as_handled()
		return
	var should_close := (
		(bound_action_triggered and bound_action == "pause")
		or (
			overlay_mode == OverlayMode.HELP
			and bound_action_triggered
			and bound_action == "guide"
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
	var failure_background := (
		mode == OverlayMode.FAILURE
		or (mode == OverlayMode.SLOT_SELECTOR and _slot_return_mode == OverlayMode.FAILURE)
	)
	_dim.visible = not failure_background
	_failure_desaturate.visible = failure_background
	_menu_panel.visible = mode in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]
	_map_panel.visible = mode == OverlayMode.TACTICAL_MAP
	_inventory_panel.visible = mode == OverlayMode.INVENTORY
	_slot_selector_panel.visible = mode == OverlayMode.SLOT_SELECTOR
	_settings_panel.visible = mode == OverlayMode.SETTINGS
	_help_panel.visible = mode == OverlayMode.HELP


func _close_overlay() -> void:
	overlay_mode = OverlayMode.NONE
	if _root != null:
		_root.visible = false
	if _map_panel != null:
		_map_panel.visible = _map_requested_visible
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
	_show_slot_selector(SaveSlotSelector.Mode.SAVE)


func _on_load_pressed() -> void:
	_show_slot_selector(SaveSlotSelector.Mode.LOAD)


func _show_slot_selector(selector_mode: int) -> void:
	_slot_return_mode = overlay_mode
	_enter_mode(OverlayMode.SLOT_SELECTOR)
	_slot_selector.configure(selector_mode, _save_slot_summaries)


func _return_from_slot_selector() -> void:
	var return_mode := _slot_return_mode
	if return_mode not in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]:
		return_mode = OverlayMode.PAUSE_MENU
	_enter_mode(return_mode)


func _on_slot_chosen(slot_id: String) -> void:
	if _slot_selector.mode == SaveSlotSelector.Mode.SAVE:
		_return_from_slot_selector()
		save_slot_requested.emit(slot_id)
	else:
		load_slot_requested.emit(slot_id)


func _on_restart_pressed() -> void:
	_close_overlay()
	restart_requested.emit()


func _on_next_level_pressed() -> void:
	_close_overlay()
	next_level_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _show_settings() -> void:
	_settings_return_mode = overlay_mode
	if _settings_return_mode not in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]:
		_settings_return_mode = OverlayMode.PAUSE_MENU
	_enter_mode(OverlayMode.SETTINGS)
	if _settings_status != null:
		_settings_status.text = "点击任一按键按钮进行重映射；Backspace 取消等待"


func _return_from_settings() -> void:
	_cancel_binding_capture("")
	_enter_mode(_settings_return_mode)


func _on_rebind_pressed(action: String) -> void:
	_capturing_action = action
	_update_control_buttons()
	if _settings_status != null:
		_settings_status.text = "正在设置“%s”：请按新的组合键（Backspace 取消）" % GAME_INPUT_BINDINGS.label_for_action(action)


func _apply_captured_binding(event: InputEventKey) -> void:
	var action := _capturing_action
	if action.is_empty():
		return
	var binding: Dictionary = GAME_INPUT_BINDINGS.binding_from_event(event)
	if int(binding.get("keycode", 0)) <= 0:
		_cancel_binding_capture("该按键无法识别，请重新选择")
		return
	var controls := settings.get("controls", {}) as Dictionary
	var conflict: String = GAME_INPUT_BINDINGS.conflicting_action(controls, binding, action)
	if not conflict.is_empty():
		controls[conflict] = (controls[action] as Dictionary).duplicate(true)
	controls[action] = binding
	_suppress_release_keycode = int(binding.get("keycode", 0))
	_capturing_action = ""
	_update_control_buttons()
	if _settings_status != null:
		_settings_status.text = (
			"已设置“%s”为 %s%s"
			% [
				GAME_INPUT_BINDINGS.label_for_action(action),
				GAME_INPUT_BINDINGS.display_text(binding),
				"（与“%s”交换）" % GAME_INPUT_BINDINGS.label_for_action(conflict) if not conflict.is_empty() else "",
			]
		)
	settings_changed.emit(settings_snapshot())


func _cancel_binding_capture(message: String) -> void:
	_capturing_action = ""
	_update_control_buttons()
	if _settings_status != null and not message.is_empty():
		_settings_status.text = message


func _reset_control_bindings() -> void:
	settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
	_cancel_binding_capture("按键已恢复为原版默认配置")
	settings_changed.emit(settings_snapshot())


func _update_control_buttons() -> void:
	if _control_buttons.is_empty():
		return
	var controls := settings.get("controls", {}) as Dictionary
	for action: String in _control_buttons:
		var button := _control_buttons[action] as Button
		button.text = (
			"请按键…"
			if action == _capturing_action
			else GAME_INPUT_BINDINGS.display_text(controls.get(action, {}) as Dictionary)
		)


func _on_setting_changed(_value: Variant = null) -> void:
	if _updating_settings_controls:
		return
	var display_mode := str(settings.get("display_mode", "windowed"))
	if not _fullscreen_toggle.button_pressed:
		display_mode = "windowed"
	elif display_mode == "windowed":
		display_mode = "fullscreen"
	settings = {
		"fullscreen": _fullscreen_toggle.button_pressed,
		"display_mode": display_mode,
		"muted": _muted_toggle.button_pressed,
		"resolution_policy": str(settings.get("resolution_policy", "desktop")),
		"window_width": int(settings.get("window_width", 1280)),
		"window_height": int(settings.get("window_height", 720)),
		"vsync": bool(settings.get("vsync", true)),
		"subtitles": _subtitles_toggle.button_pressed,
		"show_briefings": _briefings_toggle.button_pressed,
		"edge_scroll": _edge_scroll_toggle.button_pressed,
		"master_volume": _audio_slider_value("master", 0.8),
		"music_volume": _audio_slider_value("music", 0.8),
		"sfx_volume": _audio_slider_value("sfx", 0.9),
		"voice_volume": _audio_slider_value("voice", 1.0),
		"controls": (settings.get("controls", {}) as Dictionary).duplicate(true),
	}
	_update_volume_labels()
	settings_changed.emit(settings_snapshot())


func _audio_slider_value(channel: String, fallback: float) -> float:
	if not _audio_sliders.has(channel):
		return fallback
	return clampf(float((_audio_sliders[channel] as HSlider).value), 0.0, 1.0)


func _update_volume_labels() -> void:
	for channel: String in _audio_sliders:
		if _audio_value_labels.has(channel):
			(_audio_value_labels[channel] as Label).text = "%d%%" % roundi(
				float((_audio_sliders[channel] as HSlider).value) * 100.0
			)


func _on_map_position_requested(world_position: Vector2) -> void:
	map_position_requested.emit(world_position)


func _build_interface() -> void:
	_hud_root = Control.new()
	_hud_root.name = "GameHudRoot"
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

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
	_build_slot_selector_panel()
	_build_settings_panel()
	_build_help_panel()
	_root.visible = false


func _build_menu_panel() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "GameMenuPanel"
	_center_control(_menu_panel, Vector2(560.0, 590.0))
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
	_next_level_button = _add_button(content, "进入下一关", _on_next_level_pressed)
	_next_level_button.visible = false
	_save_button = _add_button(content, "保存游戏…", _on_save_pressed)
	_load_button = _add_button(content, "读取游戏…", _on_load_pressed)
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

	_add_button(content, "声音与按键设置", _show_settings)
	_add_button(content, "退出游戏", _on_quit_pressed)


func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_center_control(_settings_panel, Vector2(900.0, 680.0))
	_settings_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.065, 0.078, 0.062, 0.99))
	)
	_root.add_child(_settings_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(content)
	var title := Label.new()
	title.text = "声音与按键设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(0.97, 0.88, 0.61))
	content.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.custom_minimum_size.x = 820.0
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 8)
	scroll.add_child(sections)
	var audio_title := Label.new()
	audio_title.text = "分通道音量"
	audio_title.add_theme_font_size_override("font_size", 19)
	sections.add_child(audio_title)
	_muted_toggle = CheckButton.new()
	_muted_toggle.text = "全部静音（保留各通道音量）"
	_muted_toggle.toggled.connect(_on_setting_changed)
	sections.add_child(_muted_toggle)
	for channel: String in ["master", "music", "sfx", "voice"]:
		_add_audio_channel_row(sections, channel)
	var separator := HSeparator.new()
	sections.add_child(separator)
	var controls_title := Label.new()
	controls_title.text = "按键重映射（默认值来自原版操作指南与程序分发表）"
	controls_title.add_theme_font_size_override("font_size", 19)
	sections.add_child(controls_title)
	var last_category := ""
	for definition: Dictionary in GAME_INPUT_BINDINGS.definitions():
		var category := str(definition["category"])
		if category != last_category:
			last_category = category
			var category_label := Label.new()
			category_label.text = category
			category_label.add_theme_color_override("font_color", Color(0.91, 0.78, 0.44))
			sections.add_child(category_label)
		var row := HBoxContainer.new()
		var action_label := Label.new()
		action_label.text = str(definition["label"])
		action_label.custom_minimum_size.x = 470.0
		row.add_child(action_label)
		var action := str(definition["action"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(230.0, 32.0)
		button.pressed.connect(func() -> void: _on_rebind_pressed(action))
		row.add_child(button)
		_control_buttons[action] = button
		sections.add_child(row)
	_settings_status = Label.new()
	_settings_status.text = "点击任一按键按钮进行重映射；Backspace 取消等待"
	_settings_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_status.add_theme_color_override("font_color", Color(0.86, 0.82, 0.67))
	content.add_child(_settings_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	_add_button(actions, "恢复原版按键", _reset_control_bindings)
	_add_button(actions, "返回游戏菜单", _return_from_settings)


func _add_audio_channel_row(parent: Control, channel: String) -> void:
	var names := {"master": "主音量", "music": "音乐", "sfx": "音效", "voice": "语音"}
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = str(names[channel])
	label.custom_minimum_size.x = 110.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_setting_changed)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 58.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_audio_sliders[channel] = slider
	_audio_value_labels[channel] = value_label
	if channel == "master":
		_master_volume_slider = slider
		_volume_value_label = value_label
	parent.add_child(row)


func _build_map_panel() -> void:
	_map_panel = PanelContainer.new()
	_map_panel.name = "RealtimeMinimapPanel"
	_map_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_map_panel.offset_left = -320.0
	_map_panel.offset_top = -(ORIGINAL_BOTTOM_HUD_HEIGHT + 235.0)
	_map_panel.offset_right = 0.0
	_map_panel.offset_bottom = -ORIGINAL_BOTTOM_HUD_HEIGHT
	_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.065, 0.052, 0.99)))
	_hud_root.add_child(_map_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	_map_panel.add_child(content)
	var title := Label.new()
	title.text = "地图（M）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	content.add_child(title)
	_map_view = TACTICAL_MAP_VIEW_SCRIPT.new()
	_map_view.custom_minimum_size = Vector2(276.0, 158.0)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.world_position_requested.connect(_on_map_position_requested)
	content.add_child(_map_view)
	var help := Label.new()
	help.text = "蓝：我方　红：敌军　黄：任务　点击可卷屏"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 11)
	content.add_child(help)
	_map_panel.visible = false


func _resize_tactical_map(texture: Texture2D) -> void:
	if _map_panel == null or _map_view == null:
		return
	var map_size := Vector2(276.0, 158.0)
	if texture != null:
		map_size = texture.get_size()
	_map_view.custom_minimum_size = map_size
	var panel_size := map_size + TACTICAL_MAP_PANEL_CHROME
	_map_panel.offset_left = -panel_size.x
	_map_panel.offset_top = -(ORIGINAL_BOTTOM_HUD_HEIGHT + panel_size.y)
	_map_panel.offset_right = 0.0
	_map_panel.offset_bottom = -ORIGINAL_BOTTOM_HUD_HEIGHT


func _build_inventory_panel() -> void:
	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	_inventory_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inventory_panel.offset_left = -ORIGINAL_INVENTORY_POPUP_SIZE.x
	_inventory_panel.offset_top = -(
		ORIGINAL_BOTTOM_HUD_HEIGHT + ORIGINAL_INVENTORY_POPUP_SIZE.y
	)
	_inventory_panel.offset_right = 0.0
	_inventory_panel.offset_bottom = -ORIGINAL_BOTTOM_HUD_HEIGHT
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory_panel.add_theme_stylebox_override(
		"panel", _inventory_panel_style(Color(0.07, 0.085, 0.065, 0.99))
	)
	_root.add_child(_inventory_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	_inventory_panel.add_child(content)
	_inventory_view = INVENTORY_GRID_VIEW_SCRIPT.new()
	_inventory_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_view.slot_activated.connect(_on_inventory_slot_activated)
	content.add_child(_inventory_view)
	var help := Label.new()
	help.text = "点击方格选择；W / A / Esc 关闭"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	content.add_child(help)


func _on_inventory_slot_activated(slot: Dictionary) -> void:
	inventory_slot_requested.emit(slot)
	if overlay_mode == OverlayMode.INVENTORY:
		_close_overlay()
		resume_requested.emit()


func _build_slot_selector_panel() -> void:
	_slot_selector_panel = PanelContainer.new()
	_slot_selector_panel.name = "SaveSlotSelectorPanel"
	_center_control(_slot_selector_panel, Vector2(760.0, 610.0))
	_slot_selector_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.07, 0.085, 0.065, 0.99))
	)
	_root.add_child(_slot_selector_panel)
	_slot_selector = SAVE_SLOT_SELECTOR_SCRIPT.new()
	_slot_selector.slot_chosen.connect(_on_slot_chosen)
	_slot_selector.back_requested.connect(_return_from_slot_selector)
	_slot_selector_panel.add_child(_slot_selector)


func _build_help_panel() -> void:
	_help_panel = PanelContainer.new()
	_help_panel.name = "OriginalControlGuidePanel"
	_center_control(_help_panel, Vector2(700.0, 570.0))
	_help_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.015, 0.02, 0.015, 0.99))
	)
	_root.add_child(_help_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_help_panel.add_child(content)
	var title := Label.new()
	title.text = "原版操作指南"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)
	_help_texture = TextureRect.new()
	_help_texture.custom_minimum_size = Vector2(640.0, 480.0)
	_help_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_help_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_help_texture)
	_help_fallback = Label.new()
	_help_fallback.text = (
		"F2–F6 选择队员　R 跑/走　C 匍匐/站立\n"
		+ "W 武器栏　A 物品栏　S 视线观察　B 掩埋模式　M 地图\n"
		+ "1–0 武器快捷键　F7 任务简报　Esc 系统菜单\n"
		+ "左键选择/下令　右键拖框/菜单返回　按住 Ctrl 或 ↑ 强制目标"
	)
	_help_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_fallback.custom_minimum_size = Vector2(640.0, 440.0)
	_help_fallback.add_theme_font_size_override("font_size", 19)
	content.add_child(_help_fallback)
	_add_button(content, "关闭（F1 / Esc）", _on_resume_pressed)


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


func _inventory_panel_style(color: Color) -> StyleBoxFlat:
	var style := _panel_style(color)
	style.set_corner_radius_all(0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
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
