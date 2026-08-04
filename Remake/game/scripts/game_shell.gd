class_name GameShell
extends CanvasLayer

signal resume_requested
signal save_requested
signal load_requested
signal save_slot_requested(slot_id: String)
signal load_slot_requested(slot_id: String)
signal restart_requested
signal next_level_requested
signal level_requested(level_id: String)
signal level_selection_cancelled
signal quit_requested
signal settings_changed(settings: Dictionary)
signal map_position_requested(world_position: Vector2)
signal inventory_cycle_requested(direction: int)
signal inventory_reload_requested
signal inventory_slot_requested(slot: Dictionary)
signal original_hud_action_requested(action: String)
signal original_hud_actor_requested(actor_name: String)

const TACTICAL_MAP_VIEW_SCRIPT: Script = preload("res://scripts/tactical_map_view.gd")
const SAVE_SLOT_SELECTOR_SCRIPT: Script = preload("res://scripts/save_slot_selector.gd")
const CAMPAIGN_LEVEL_SELECTOR_SCRIPT: Script = preload(
	"res://scripts/campaign_level_selector.gd"
)
const INVENTORY_GRID_VIEW_SCRIPT: Script = preload("res://scripts/inventory_grid_view.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const ORIGINAL_INVENTORY_POPUP_SIZE := Vector2(276.0, 421.0)
const ORIGINAL_BOTTOM_HUD_HEIGHT := 62.0
const ORIGINAL_INVENTORY_BACKGROUND_PSD := 1129
const ORIGINAL_HELP_SIZE := Vector2(640.0, 480.0)
const ORIGINAL_PAUSE_MENU_SIZE := Vector2(132.0, 318.0)
const ORIGINAL_PAUSE_MENU_CENTER_OFFSET := Vector2(-305.0, -118.0)
const ORIGINAL_PAUSE_MENU_BUTTON_PITCH := 40.0
const ORIGINAL_PAUSE_MENU_BACKGROUND_PSD := 1095
const ORIGINAL_PAUSE_MENU_LABEL_OFFSET := Vector2i(5, 4)
const ORIGINAL_FAILURE_TITLE_SIZE := Vector2(172.0, 50.0)
const ORIGINAL_FAILURE_TITLE_CENTER_OFFSET := Vector2(-99.0, -59.0)
const ORIGINAL_FAILURE_BUTTON_SIZE := Vector2(132.0, 38.0)
const ORIGINAL_FAILURE_RESTART_CENTER_OFFSET := Vector2(-158.0, -3.0)
const ORIGINAL_FAILURE_MAIN_CENTER_OFFSET := Vector2(-8.0, -3.0)
const ORIGINAL_FAILURE_TITLE_BACKGROUND_PSD := 1093
const ORIGINAL_FAILURE_BUTTON_BACKGROUND_PSD := 1095
const ORIGINAL_FAILURE_RESTART_NORMAL_PSD := 1260
const ORIGINAL_FAILURE_RESTART_HOVER_PSD := 1261
const ORIGINAL_FAILURE_RESTART_LABEL_OFFSET := Vector2i(8, 8)
const ORIGINAL_FAILURE_TEXT_COLOR := Color(0.69, 0.70, 0.53, 1.0)
const ORIGINAL_FAILURE_TEXT_HOVER_COLOR := Color(0.94, 0.94, 0.86, 1.0)
const ORIGINAL_LEVEL_SELECTOR_BACKGROUND_PSD := 1094
const ORIGINAL_LEVEL_SELECTOR_LABELS := {
	"m000": {"normal": 1089, "hover": 1090},
	"m001": {"normal": 1081, "hover": 1082},
	"m002": {"normal": 1073, "hover": 1074},
	"m003": {"normal": 1083, "hover": 1084},
	"m004": {"normal": 1071, "hover": 1072},
	"m005": {"normal": 1067, "hover": 1068},
	"m006": {"normal": 1065, "hover": 1066},
	"m007": {"normal": 1085, "hover": 1086},
	"m008": {"normal": 1063, "hover": 1064},
	"m009": {"normal": 1069, "hover": 1070},
	"m010": {"normal": 1087, "hover": 1088},
	"m011": {"normal": 1079, "hover": 1080},
}
const ORIGINAL_CREDITS_PSD := 1254
const OVERLAY_DIM_COLOR := Color(0.018, 0.024, 0.020, 0.78)
const ORIGINAL_HELP_BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const ORIGINAL_HUD_PORTRAITS := {
	"老赵": {"dead": 1187, "idle": 1188, "selected": 1189},
	"铁蛋": {"dead": 1215, "idle": 1216, "selected": 1217},
	"强子": {"dead": 1198, "idle": 1199, "selected": 1200},
	"古明": {"dead": 1154, "idle": 1155, "selected": 1156},
	"大牛": {"dead": 1126, "idle": 1127, "selected": 1128},
}
const ORIGINAL_HUD_AMMO_STATUS := {
	"老赵": 1186,
	"铁蛋": 1214,
	"强子": 1197,
	"古明": 1153,
	"大牛": 1125,
}
const ORIGINAL_HUD_ACTIONS: Array[Dictionary] = [
	{
		"action": "observation",
		"normal": 1160,
		"active": 1161,
		"tooltip": "观察敌军视线（S）",
		"toggle": true,
	},
	{
		"action": "minimap",
		"normal": 1143,
		"active": 1144,
		"tooltip": "显示或隐藏地图（M）",
		"toggle": true,
	},
	{
		"action": "system",
		"normal": 1232,
		"active": 1233,
		"tooltip": "游戏菜单（Esc）",
		"toggle": false,
	},
]
const ORIGINAL_PAUSE_MENU_BUTTONS: Array[Dictionary] = [
	{"id": "resume", "normal": 1103, "hover": 1104, "tooltip": "开始游戏"},
	{"id": "restart", "normal": 1114, "hover": 1115, "tooltip": "重玩本关"},
	{"id": "missions", "normal": 1101, "hover": 1102, "tooltip": "返回任务"},
	{"id": "save", "normal": 1097, "hover": 1098, "tooltip": "存储进度"},
	{"id": "load", "normal": 1109, "hover": 1110, "tooltip": "载入进度"},
	{"id": "settings", "normal": 1107, "hover": 1108, "tooltip": "游戏设置"},
	{"id": "credits", "normal": 1112, "hover": 1113, "tooltip": "制作人员"},
	{"id": "quit", "normal": 1105, "hover": 1106, "tooltip": "退出游戏"},
]
const DISPLAY_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const DIFFICULTY_MODES: Array[String] = ["original", "easy", "normal", "hard"]
const MISSION_RULE_MODES: Array[String] = ["stable_mod", "repaired"]

enum OverlayMode {
	NONE,
	PAUSE_MENU,
	TACTICAL_MAP,
	INVENTORY,
	FAILURE,
	SLOT_SELECTOR,
	SETTINGS,
	HELP,
	LEVEL_SELECTOR,
	MODERN_MENU,
	CREDITS,
}

var overlay_mode := OverlayMode.NONE
var settings: Dictionary = {}

var _root: Control
var _hud_root: Control
var _original_top_hud: Control
var _original_hud_status_row: HBoxContainer
var _original_hud_status_controls: Dictionary = {}
var _original_hud_ammo_font: SystemFont
var _original_bottom_hud: Control
var _original_hud_background: NinePatchRect
var _original_hud_border: NinePatchRect
var _original_hud_portrait_row: HBoxContainer
var _original_hud_action_row: HBoxContainer
var _original_hud_weapon_panel: Panel
var _original_hud_weapon_icon: TextureRect
var _original_hud_weapon_name: Label
var _original_hud_weapon_ammo: Label
var _original_hud_portrait_controls: Dictionary = {}
var _original_hud_action_buttons: Dictionary = {}
var _original_hud_texture_cache: Dictionary = {}
var _original_hud_converted_root := ""
var _original_hud_assets_ready := false
var _original_overlay_assets_ready := false
var _original_hud_requested_visible := false
var _dim: ColorRect
var _failure_desaturate: ColorRect
var _menu_panel: PanelContainer
var _classic_menu_panel: Control
var _classic_menu_buttons: Dictionary = {}
var _classic_resume_button: TextureButton
var _classic_restart_button: TextureButton
var _classic_level_select_button: TextureButton
var _classic_save_button: TextureButton
var _classic_load_button: TextureButton
var _classic_settings_button: TextureButton
var _classic_credits_button: TextureButton
var _classic_quit_button: TextureButton
var _classic_failure_panel: Control
var _failure_title_background: TextureRect
var _failure_title_label: Label
var _failure_restart_button: TextureButton
var _failure_main_button: TextureButton
var _failure_main_label: Label
var _original_failure_font: SystemFont
var _failure_text := ""
var _failure_can_load := false
var _menu_title: Label
var _menu_message: Label
var _resume_button: Button
var _next_level_button: Button
var _save_button: Button
var _load_button: Button
var _restart_button: Button
var _level_select_button: Button
var _display_mode_option: OptionButton
var _difficulty_option: OptionButton
var _mission_rule_option: OptionButton
var _subtitles_toggle: CheckButton
var _briefings_toggle: CheckButton
var _edge_scroll_toggle: CheckButton
var _reduce_camera_motion_toggle: CheckButton
var _large_cursor_toggle: CheckButton
var _muted_toggle: CheckButton
var _master_volume_slider: HSlider
var _volume_value_label: Label
var _audio_sliders: Dictionary = {}
var _audio_value_labels: Dictionary = {}
var _settings_panel: PanelContainer
var _settings_return_mode := OverlayMode.PAUSE_MENU
var _modern_menu_return_mode := OverlayMode.PAUSE_MENU
var _control_buttons: Dictionary = {}
var _capturing_action := ""
var _settings_status: Label
var _map_panel: PanelContainer
var _map_view: TacticalMapView
var _map_requested_visible := false
var _inventory_panel: PanelContainer
var _inventory_background: TextureRect
var _inventory_view: InventoryGridView
var _inventory_mode := "items"
var _help_panel: PanelContainer
var _help_texture: TextureRect
var _help_fallback: Label
var _credits_panel: PanelContainer
var _credits_texture: TextureRect
var _credits_return_mode := OverlayMode.PAUSE_MENU
var _slot_selector_panel: PanelContainer
var _slot_selector: SaveSlotSelector
var _slot_return_mode := OverlayMode.PAUSE_MENU
var _save_slot_summaries: Array[Dictionary] = []
var _level_selector_panel: PanelContainer
var _level_selector: CampaignLevelSelector
var _level_selector_return_mode := OverlayMode.PAUSE_MENU
var _level_entries: Array[Dictionary] = []
var _campaign_progress: Dictionary = {}
var _current_level_id := "m000"
var _pause_owned := false
var _pause_state_before_overlay := false
var _updating_settings_controls := false
var _suppress_release_keycode := 0


func _ready() -> void:
	layer = 180
	# This layer owns both paused menus and the live bottom HUD/minimap. WHEN_PAUSED
	# made the live controls hoverable but silently excluded their GUI events
	# during gameplay. ALWAYS keeps both surfaces interactive; each handler still
	# gates itself by overlay_mode and the world has an explicit no-click-through
	# boundary below this CanvasLayer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	set_settings({})


func set_settings(new_settings: Dictionary) -> void:
	var display_mode := str(new_settings.get(
		"display_mode",
		"fullscreen" if bool(new_settings.get("fullscreen", false)) else "windowed",
	))
	if display_mode not in DISPLAY_MODES:
		display_mode = "windowed"
	var resolution_policy := str(new_settings.get("resolution_policy", "desktop"))
	if resolution_policy not in ["desktop", "custom"]:
		resolution_policy = "desktop"
	var difficulty_mode := str(new_settings.get("difficulty_mode", "original"))
	if difficulty_mode not in DIFFICULTY_MODES:
		difficulty_mode = "original"
	var mission_rule_mode := str(new_settings.get("mission_rule_mode", "stable_mod"))
	if mission_rule_mode not in MISSION_RULE_MODES:
		mission_rule_mode = "stable_mod"
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
		"reduce_camera_motion": bool(new_settings.get("reduce_camera_motion", false)),
		"large_cursor": bool(new_settings.get("large_cursor", false)),
		"difficulty_mode": difficulty_mode,
		"mission_rule_mode": mission_rule_mode,
		"master_volume": clampf(float(new_settings.get("master_volume", 0.8)), 0.0, 1.0),
		"music_volume": clampf(float(new_settings.get("music_volume", 0.8)), 0.0, 1.0),
		"sfx_volume": clampf(float(new_settings.get("sfx_volume", 0.9)), 0.0, 1.0),
		"voice_volume": clampf(float(new_settings.get("voice_volume", 1.0)), 0.0, 1.0),
		"controls": GAME_INPUT_BINDINGS.normalize_bindings(new_settings.get("controls", {})),
	}
	if _root == null:
		return
	_updating_settings_controls = true
	_select_display_mode(str(settings["display_mode"]))
	_subtitles_toggle.button_pressed = bool(settings["subtitles"])
	_briefings_toggle.button_pressed = bool(settings["show_briefings"])
	_edge_scroll_toggle.button_pressed = bool(settings["edge_scroll"])
	_reduce_camera_motion_toggle.button_pressed = bool(
		settings["reduce_camera_motion"]
	)
	_large_cursor_toggle.button_pressed = bool(settings["large_cursor"])
	_select_difficulty_mode(str(settings["difficulty_mode"]))
	_select_mission_rule_mode(str(settings["mission_rule_mode"]))
	_muted_toggle.button_pressed = bool(settings["muted"])
	for channel: String in ["master", "music", "sfx", "voice"]:
		if _audio_sliders.has(channel):
			(_audio_sliders[channel] as HSlider).value = float(settings["%s_volume" % channel])
	_update_volume_labels()
	_update_control_buttons()
	_updating_settings_controls = false


func configure_original_hud_assets(converted_root: String) -> bool:
	var normalized_root := converted_root.simplify_path()
	if (
		_original_hud_assets_ready
		and normalized_root == _original_hud_converted_root
	):
		return true
	_original_hud_converted_root = normalized_root
	_original_hud_texture_cache.clear()
	_original_hud_assets_ready = false
	_original_overlay_assets_ready = false
	if _original_bottom_hud == null or normalized_root.is_empty():
		_update_original_hud_visibility()
		return false

	var background := _load_original_hud_texture("iblock", 1137)
	var border := _load_original_hud_texture("psd", 1138)
	if background == null or border == null:
		_update_original_hud_visibility()
		return false
	_original_hud_background.texture = background
	_original_hud_border.texture = border
	if (
		_load_original_hud_texture("iblock", 1140) == null
		or _load_original_hud_texture("iblock", 1139) == null
	):
		_update_original_hud_visibility()
		return false
	_set_original_hud_side_texture("OriginalHudLeftBorder", "iblock", 1140)
	_set_original_hud_side_texture("OriginalHudRightBorder", "iblock", 1139)

	for actor_name: String in ORIGINAL_HUD_PORTRAITS:
		var portrait := ORIGINAL_HUD_PORTRAITS[actor_name] as Dictionary
		for state: String in ["dead", "idle", "selected"]:
			if _load_original_hud_texture("psd", int(portrait[state])) == null:
				_update_original_hud_visibility()
				return false
		if (
			_load_original_hud_texture(
				"psd", int(ORIGINAL_HUD_AMMO_STATUS[actor_name])
			) == null
		):
			_update_original_hud_visibility()
			return false
	for descriptor: Dictionary in ORIGINAL_HUD_ACTIONS:
		var action := str(descriptor["action"])
		var button := _original_hud_action_buttons.get(action) as TextureButton
		if button == null:
			continue
		var normal := _load_original_hud_texture("psd", int(descriptor["normal"]))
		var active := _load_original_hud_texture("psd", int(descriptor["active"]))
		if normal == null or active == null:
			_update_original_hud_visibility()
			return false
		button.texture_normal = normal
		button.texture_hover = active
		button.texture_pressed = active
		button.texture_focused = active

	var inventory_background := _load_original_color_keyed_hud_texture(
		"psd",
		ORIGINAL_INVENTORY_BACKGROUND_PSD,
	)
	var inventory_ready := _inventory_background != null and inventory_background != null
	if inventory_ready:
		_inventory_background.texture = inventory_background
	var classic_menu_ready := _configure_original_pause_menu_assets()
	var classic_failure_ready := _configure_original_failure_assets()
	var level_selector_ready := _configure_original_level_selector_assets()
	var credits := _load_original_hud_texture("psd", ORIGINAL_CREDITS_PSD)
	var credits_ready := _credits_texture != null and credits != null
	if credits_ready:
		_credits_texture.texture = credits
	_original_overlay_assets_ready = (
		inventory_ready
		and classic_menu_ready
		and classic_failure_ready
		and level_selector_ready
		and credits_ready
	)

	_original_hud_assets_ready = true
	_update_original_hud_portrait_textures()
	_update_original_hud_status_textures()
	_update_original_hud_visibility()
	return true


func _configure_original_pause_menu_assets() -> bool:
	if _classic_menu_buttons.size() != ORIGINAL_PAUSE_MENU_BUTTONS.size():
		return false
	var background := _load_original_hud_texture(
		"psd", ORIGINAL_PAUSE_MENU_BACKGROUND_PSD
	)
	if background == null:
		return false
	for descriptor: Dictionary in ORIGINAL_PAUSE_MENU_BUTTONS:
		var button := _classic_menu_buttons.get(str(descriptor["id"])) as TextureButton
		if button == null:
			return false
		var normal := _load_original_hud_texture("psd", int(descriptor["normal"]))
		var hover := _load_original_hud_texture("psd", int(descriptor["hover"]))
		if normal == null or hover == null:
			return false
		var normal_composite := _compose_original_pause_menu_texture(
			background, normal
		)
		var hover_composite := _compose_original_pause_menu_texture(
			background, hover
		)
		if normal_composite == null or hover_composite == null:
			return false
		button.texture_normal = normal_composite
		button.texture_hover = hover_composite
		button.texture_pressed = hover_composite
		button.texture_focused = hover_composite
		button.texture_disabled = normal_composite
		button.size = normal_composite.get_size()
	return true


func _configure_original_failure_assets() -> bool:
	if (
		_failure_title_background == null
		or _failure_restart_button == null
		or _failure_main_button == null
	):
		return false
	var title_background := _load_original_hud_texture(
		"psd", ORIGINAL_FAILURE_TITLE_BACKGROUND_PSD
	)
	var button_background := _load_original_hud_texture(
		"psd", ORIGINAL_FAILURE_BUTTON_BACKGROUND_PSD
	)
	var restart_normal := _load_original_hud_texture(
		"psd", ORIGINAL_FAILURE_RESTART_NORMAL_PSD
	)
	var restart_hover := _load_original_hud_texture(
		"psd", ORIGINAL_FAILURE_RESTART_HOVER_PSD
	)
	if (
		title_background == null
		or button_background == null
		or restart_normal == null
		or restart_hover == null
	):
		return false
	_failure_title_background.texture = title_background
	var restart_normal_composite := _compose_original_pause_menu_texture(
		button_background,
		restart_normal,
		ORIGINAL_FAILURE_RESTART_LABEL_OFFSET,
	)
	var restart_hover_composite := _compose_original_pause_menu_texture(
		button_background,
		restart_hover,
		ORIGINAL_FAILURE_RESTART_LABEL_OFFSET,
	)
	if restart_normal_composite == null or restart_hover_composite == null:
		return false
	_failure_restart_button.texture_normal = restart_normal_composite
	_failure_restart_button.texture_hover = restart_hover_composite
	_failure_restart_button.texture_pressed = restart_hover_composite
	_failure_restart_button.texture_focused = restart_hover_composite
	_failure_restart_button.size = restart_normal_composite.get_size()
	_failure_main_button.texture_normal = button_background
	_failure_main_button.texture_hover = button_background
	_failure_main_button.texture_pressed = button_background
	_failure_main_button.texture_focused = button_background
	_failure_main_button.size = button_background.get_size()
	return true


func _configure_original_level_selector_assets() -> bool:
	if _level_selector == null:
		return false
	var background := _load_original_hud_texture(
		"psd", ORIGINAL_LEVEL_SELECTOR_BACKGROUND_PSD
	)
	if background == null or background.get_size() != Vector2(114.0, 33.0):
		return false
	var texture_pairs: Dictionary = {}
	for level_id: String in ORIGINAL_LEVEL_SELECTOR_LABELS:
		var descriptor := ORIGINAL_LEVEL_SELECTOR_LABELS[level_id] as Dictionary
		var normal := _load_original_hud_texture("psd", int(descriptor["normal"]))
		var hover := _load_original_hud_texture("psd", int(descriptor["hover"]))
		if normal == null or hover == null:
			return false
		var normal_offset := Vector2i(
			maxi(0, int((background.get_width() - normal.get_width()) * 0.5)),
			maxi(0, int((background.get_height() - normal.get_height()) * 0.5)),
		)
		var hover_offset := Vector2i(
			maxi(0, int((background.get_width() - hover.get_width()) * 0.5)),
			maxi(0, int((background.get_height() - hover.get_height()) * 0.5)),
		)
		var normal_composite := _compose_original_pause_menu_texture(
			background, normal, normal_offset
		)
		var hover_composite := _compose_original_pause_menu_texture(
			background, hover, hover_offset
		)
		if normal_composite == null or hover_composite == null:
			return false
		texture_pairs[level_id] = {
			"normal": normal_composite,
			"hover": hover_composite,
		}
	return _level_selector.configure_original_assets(texture_pairs)


func _compose_original_pause_menu_texture(
	background: Texture2D,
	label_texture: Texture2D,
	label_offset: Vector2i = ORIGINAL_PAUSE_MENU_LABEL_OFFSET,
) -> Texture2D:
	var background_image := background.get_image()
	var label_image := label_texture.get_image()
	if background_image == null or label_image == null:
		return null
	if background_image.is_empty() or label_image.is_empty():
		return null
	background_image.convert(Image.FORMAT_RGBA8)
	label_image.convert(Image.FORMAT_RGBA8)
	background_image.blend_rect(
		label_image,
		Rect2i(Vector2i.ZERO, label_image.get_size()),
		label_offset,
	)
	return ImageTexture.create_from_image(background_image)


func set_original_hud_visible(visible: bool) -> void:
	_original_hud_requested_visible = visible
	_update_original_hud_visibility()


func gameplay_viewport_size(full_viewport_size: Vector2) -> Vector2:
	return gameplay_screen_rect(full_viewport_size).size


func gameplay_screen_rect(full_viewport_size: Vector2) -> Rect2:
	var safe_size := full_viewport_size.max(Vector2.ONE)
	if _original_bottom_hud != null and _original_bottom_hud.visible:
		safe_size.y = maxf(safe_size.y - ORIGINAL_BOTTOM_HUD_HEIGHT, 1.0)
	return Rect2(Vector2.ZERO, safe_size)


func gameplay_camera_offset(full_viewport_size: Vector2, zoom: float = 1.0) -> Vector2:
	var safe_rect := gameplay_screen_rect(full_viewport_size)
	var obscured_height := maxf(full_viewport_size.y - safe_rect.size.y, 0.0)
	return Vector2(0.0, obscured_height * 0.5 / maxf(zoom, 0.001))


func edge_scroll_pointer_position(
	screen_position: Vector2,
	full_viewport_size: Vector2,
) -> Vector2:
	var safe_rect := gameplay_screen_rect(full_viewport_size)
	if (
		screen_position.x < safe_rect.position.x
		or screen_position.x >= safe_rect.end.x
		or screen_position.y < safe_rect.position.y
		or screen_position.y >= full_viewport_size.y
	):
		return Vector2(-1.0, -1.0)
	if screen_position.y < safe_rect.end.y:
		return screen_position
	# Empty stonework in the bottom bar acts as the physical lower edge of the
	# battlefield. Buttons, portraits, the weapon switcher and the minimap remain
	# ordinary interactive controls and never start edge scrolling.
	if is_screen_point_over_edge_scroll_blocker(screen_position):
		return Vector2(-1.0, -1.0)
	return Vector2(screen_position.x, safe_rect.end.y - 0.5)


func is_screen_point_over_edge_scroll_blocker(screen_position: Vector2) -> bool:
	if (
		_map_panel != null
		and _map_panel.visible
		and _map_panel.get_global_rect().has_point(screen_position)
	):
		return true
	if (
		_original_hud_weapon_panel != null
		and _original_hud_weapon_panel.visible
		and _original_hud_weapon_panel.get_global_rect().has_point(screen_position)
	):
		return true
	for controls_value: Variant in _original_hud_portrait_controls.values():
		var controls := controls_value as Dictionary
		var button := controls.get("button") as Control
		if (
			button != null
			and button.visible
			and button.get_global_rect().has_point(screen_position)
		):
			return true
	for button_value: Variant in _original_hud_action_buttons.values():
		var button := button_value as Control
		if (
			button != null
			and button.visible
			and button.get_global_rect().has_point(screen_position)
		):
			return true
	return false


func is_screen_point_over_gameplay_ui(screen_position: Vector2) -> bool:
	for control_value: Variant in [_original_bottom_hud, _map_panel]:
		var control := control_value as Control
		if (
			control != null
			and control.visible
			and control.get_global_rect().has_point(screen_position)
		):
			return true
	return false


func update_original_hud(actor_states: Array) -> void:
	var by_name: Dictionary = {}
	var selected_state: Dictionary = {}
	for state: Dictionary in actor_states:
		var actor_name := str(state.get("name", ""))
		if ORIGINAL_HUD_PORTRAITS.has(actor_name):
			by_name[actor_name] = state
			if (
				selected_state.is_empty()
				and bool(state.get("selected", false))
				and bool(state.get("alive", true))
			):
				selected_state = state
	if _original_hud_weapon_panel != null:
		_original_hud_weapon_panel.visible = not selected_state.is_empty()
		_original_hud_weapon_icon.texture = (
			selected_state.get("weapon_icon") as Texture2D
			if not selected_state.is_empty()
			else null
		)
		_original_hud_weapon_name.text = str(
			selected_state.get("weapon_name", "")
		)
		_original_hud_weapon_ammo.text = str(
			selected_state.get("weapon_ammo_text", "")
		)
		_original_hud_weapon_panel.tooltip_text = (
			"当前武器：%s　%s\n点击切换下一件武器（Tab）"
			% [
				_original_hud_weapon_name.text,
				_original_hud_weapon_ammo.text,
			]
			if not selected_state.is_empty()
			else ""
		)
	for actor_name: String in _original_hud_status_controls:
		var status_controls := (
			_original_hud_status_controls[actor_name] as Dictionary
		)
		var status_container := status_controls.get("container") as Control
		status_container.visible = false
		(status_controls.get("ammo_label") as Label).text = ""
	for actor_name: String in ORIGINAL_HUD_PORTRAITS:
		var controls := _original_hud_portrait_controls.get(actor_name) as Dictionary
		if controls == null:
			continue
		var container := controls.get("container") as Control
		var state := by_name.get(actor_name, {}) as Dictionary
		container.visible = not state.is_empty()
		if state.is_empty():
			continue
		controls["alive"] = bool(state.get("alive", true))
		controls["selected"] = bool(state.get("selected", false))
		var status_controls := (
			_original_hud_status_controls.get(actor_name) as Dictionary
		)
		if status_controls != null:
			var status_container := status_controls.get("container") as Control
			status_container.visible = true
			(status_controls.get("ammo_label") as Label).text = str(
				state.get("ammo_text", "")
			)
		var ratio := clampf(float(state.get("health_ratio", 1.0)), 0.0, 1.0)
		var health_fill := controls.get("health_fill") as ColorRect
		var height := 32.0 * ratio
		health_fill.position = Vector2(43.0, 46.0 - height)
		health_fill.size = Vector2(3.0, height)
		health_fill.color = (
			Color.GREEN
			if ratio > 0.5
			else Color.YELLOW
			if ratio > 0.25
			else Color.RED
		)
		var button := controls.get("button") as TextureButton
		button.tooltip_text = "选择%s并定位视图　生命 %d%%" % [
			actor_name,
			roundi(ratio * 100.0),
		]
	_update_original_hud_portrait_textures()
	_update_original_hud_status_textures()
	set_original_hud_visible(not by_name.is_empty())


func set_original_hud_action_state(action: String, active: bool) -> void:
	var button := _original_hud_action_buttons.get(action) as TextureButton
	if button != null and button.toggle_mode:
		button.set_pressed_no_signal(active)


func original_hud_layout_snapshot() -> Dictionary:
	var status_cells: Dictionary = {}
	for actor_name: String in _original_hud_status_controls:
		var controls := _original_hud_status_controls[actor_name] as Dictionary
		var container := controls.get("container") as Control
		var ammo_label := controls.get("ammo_label") as Label
		status_cells[actor_name] = {
			"visible": container.visible,
			"rect": container.get_global_rect(),
			"ammo_text": ammo_label.text,
		}
	var portraits: Dictionary = {}
	for actor_name: String in _original_hud_portrait_controls:
		var controls := _original_hud_portrait_controls[actor_name] as Dictionary
		var container := controls.get("container") as Control
		portraits[actor_name] = {
			"visible": container.visible,
			"rect": container.get_global_rect(),
			"tooltip": (controls.get("button") as TextureButton).tooltip_text,
			"mouse_filter": (controls.get("button") as TextureButton).mouse_filter,
		}
	var actions: Dictionary = {}
	for action: String in _original_hud_action_buttons:
		var button := _original_hud_action_buttons[action] as TextureButton
		actions[action] = {
			"visible": button.visible,
			"rect": button.get_global_rect(),
			"pressed": button.button_pressed,
			"tooltip": button.tooltip_text,
			"mouse_filter": button.mouse_filter,
		}
	var weapon := {
		"visible": false,
		"rect": Rect2(),
		"name": "",
		"ammo_text": "",
		"has_icon": false,
	}
	if _original_hud_weapon_panel != null:
		weapon = {
			"visible": _original_hud_weapon_panel.visible,
			"rect": _original_hud_weapon_panel.get_global_rect(),
			"name": _original_hud_weapon_name.text,
			"ammo_text": _original_hud_weapon_ammo.text,
			"has_icon": _original_hud_weapon_icon.texture != null,
			"tooltip": _original_hud_weapon_panel.tooltip_text,
			"mouse_filter": _original_hud_weapon_panel.mouse_filter,
		}
	return {
		"assets_ready": _original_hud_assets_ready,
		"top_visible": _original_top_hud != null and _original_top_hud.visible,
		"status_cells": status_cells,
		"visible": _original_bottom_hud != null and _original_bottom_hud.visible,
		"height": ORIGINAL_BOTTOM_HUD_HEIGHT,
		"mouse_filter": (
			_original_bottom_hud.mouse_filter
			if _original_bottom_hud != null
			else Control.MOUSE_FILTER_IGNORE
		),
		"bar_rect": (
			_original_bottom_hud.get_global_rect()
			if _original_bottom_hud != null
			else Rect2()
		),
		"portraits": portraits,
		"weapon": weapon,
		"actions": actions,
	}


func original_overlay_layout_snapshot() -> Dictionary:
	var map_texture_size := Vector2.ZERO
	if _map_view != null and _map_view.terrain_texture != null:
		map_texture_size = _map_view.terrain_texture.get_size()
	var pause_buttons: Dictionary = {}
	for button_id: String in _classic_menu_buttons:
		var button := _classic_menu_buttons[button_id] as TextureButton
		pause_buttons[button_id] = {
			"rect": button.get_global_rect(),
			"visible": button.visible,
			"disabled": button.disabled,
			"texture_size": (
				button.texture_normal.get_size()
				if button.texture_normal != null
				else Vector2.ZERO
			),
		}
	var desaturate_material := _failure_desaturate.material as ShaderMaterial
	var failure_buttons := {
		"restart": {
			"rect": (
				_failure_restart_button.get_global_rect()
				if _failure_restart_button != null
				else Rect2()
			),
			"texture_size": (
				_failure_restart_button.texture_normal.get_size()
				if (
					_failure_restart_button != null
					and _failure_restart_button.texture_normal != null
				)
				else Vector2.ZERO
			),
		},
		"main": {
			"rect": (
				_failure_main_button.get_global_rect()
				if _failure_main_button != null
				else Rect2()
			),
			"texture_size": (
				_failure_main_button.texture_normal.get_size()
				if _failure_main_button != null and _failure_main_button.texture_normal != null
				else Vector2.ZERO
			),
		},
	}
	var level_selector_layout := (
		_level_selector.layout_snapshot()
		if _level_selector != null
		else {}
	)
	return {
		"assets_ready": _original_overlay_assets_ready,
		"inventory_rect": (
			_inventory_panel.get_global_rect()
			if _inventory_panel != null
			else Rect2()
		),
		"inventory_layout": (
			_inventory_view.layout_snapshot()
			if _inventory_view != null
			else {}
		),
		"map_rect": _map_panel.get_global_rect() if _map_panel != null else Rect2(),
		"map_texture_size": map_texture_size,
		"help_rect": _help_panel.get_global_rect() if _help_panel != null else Rect2(),
		"help_texture_size": (
			_help_texture.texture.get_size()
			if _help_texture != null and _help_texture.texture != null
			else Vector2.ZERO
		),
		"pause_menu_rect": (
			_classic_menu_panel.get_global_rect()
			if _classic_menu_panel != null
			else Rect2()
		),
		"pause_buttons": pause_buttons,
		"failure_title_rect": (
			_failure_title_background.get_global_rect()
			if _failure_title_background != null
			else Rect2()
		),
		"failure_title_texture_size": (
			_failure_title_background.texture.get_size()
			if _failure_title_background != null and _failure_title_background.texture != null
			else Vector2.ZERO
		),
		"failure_buttons": failure_buttons,
		"level_selector_panel_rect": (
			_level_selector_panel.get_global_rect()
			if _level_selector_panel != null
			else Rect2()
		),
		"level_selector_layout": level_selector_layout,
		"desaturate_visible": (
			_failure_desaturate != null and _failure_desaturate.visible
		),
		"desaturate_brightness": (
			float(desaturate_material.get_shader_parameter("brightness"))
			if desaturate_material != null
			else 0.0
		),
		"desaturate_average_mix": (
			float(desaturate_material.get_shader_parameter("average_mix"))
			if desaturate_material != null
			else 0.0
		),
		"credits_rect": (
			_credits_panel.get_global_rect()
			if _credits_panel != null
			else Rect2()
		),
		"credits_texture_size": (
			_credits_texture.texture.get_size()
			if _credits_texture != null and _credits_texture.texture != null
			else Vector2.ZERO
		),
		"dim_visible": _dim != null and _dim.visible,
		"backdrop_color": _dim.color if _dim != null else Color.TRANSPARENT,
	}


func settings_snapshot() -> Dictionary:
	return settings.duplicate(true)


func show_pause_menu(can_load: bool, message: String = "") -> void:
	_enter_mode(OverlayMode.PAUSE_MENU)
	_menu_title.text = "游戏菜单"
	_menu_message.text = message if not message.is_empty() else "游戏已暂停"
	_resume_button.visible = true
	_next_level_button.visible = false
	_save_button.visible = true
	_load_button.visible = true
	_load_button.disabled = not can_load
	_restart_button.visible = true
	_level_select_button.visible = true
	_classic_resume_button.visible = true
	_classic_restart_button.visible = true
	_classic_level_select_button.visible = true
	_classic_save_button.visible = true
	_classic_load_button.visible = true
	_classic_load_button.disabled = not can_load
	_classic_settings_button.visible = true
	_classic_credits_button.visible = true
	_classic_quit_button.visible = true
	_release_gui_focus()


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
	_load_button.visible = true
	_load_button.disabled = not can_load
	_restart_button.visible = true
	_level_select_button.visible = true
	_classic_resume_button.visible = true
	_classic_restart_button.visible = true
	_classic_level_select_button.visible = true
	_classic_save_button.visible = true
	_classic_load_button.visible = true
	_classic_load_button.disabled = not can_load
	_classic_settings_button.visible = true
	_classic_credits_button.visible = true
	_classic_quit_button.visible = true
	if has_next_level:
		_next_level_button.grab_focus()
	else:
		_resume_button.grab_focus()


func set_save_slots(summaries: Array[Dictionary]) -> void:
	_save_slot_summaries = summaries.duplicate(true)


func set_level_selection(
	entries: Array[Dictionary],
	progress: Dictionary,
	current_level_id: String,
) -> void:
	_level_entries = entries.duplicate(true)
	_campaign_progress = progress.duplicate(true)
	_current_level_id = current_level_id
	if _level_selector != null:
		_level_selector.configure(
			_level_entries,
			_campaign_progress,
			_current_level_id,
		)


func show_level_selector(startup: bool = false) -> void:
	_level_selector_return_mode = (
		OverlayMode.NONE if startup else overlay_mode
	)
	if (
		not startup
		and _level_selector_return_mode
		not in [
			OverlayMode.PAUSE_MENU,
			OverlayMode.FAILURE,
			OverlayMode.MODERN_MENU,
		]
	):
		_level_selector_return_mode = OverlayMode.PAUSE_MENU
	_enter_mode(OverlayMode.LEVEL_SELECTOR)
	_level_selector.configure(
		_level_entries,
		_campaign_progress,
		_current_level_id,
	)
	_level_selector.focus_current()


func show_failure(failure_text: String, can_load: bool) -> void:
	_failure_text = failure_text
	_failure_can_load = can_load
	_enter_mode(OverlayMode.FAILURE)
	_menu_title.text = "任务失败"
	_menu_message.text = failure_text
	_resume_button.visible = false
	_next_level_button.visible = false
	_save_button.visible = false
	_load_button.visible = true
	_load_button.disabled = not can_load
	_restart_button.visible = true
	_level_select_button.visible = true
	_release_gui_focus()


func show_tactical_map(
	terrain_texture: Texture2D,
	world_size: Vector2,
	actor_markers: Array[Dictionary],
	mission_markers: Array[Dictionary],
	camera_world_rect: Rect2,
) -> void:
	_resize_tactical_map(terrain_texture)
	_map_requested_visible = true
	set_original_hud_action_state("minimap", true)
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
	set_original_hud_action_state("minimap", _map_requested_visible)
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
	set_original_hud_action_state("minimap", false)
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


func update_inventory(inventory_data: Variant, requested_mode: String = "") -> void:
	if _inventory_view == null:
		return
	if requested_mode in ["weapons", "items"]:
		_inventory_mode = requested_mode
	_inventory_view.configure(_normalized_inventory_model(inventory_data), _inventory_mode)


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
	return _mode_uses_failure_background(overlay_mode)


func _mode_uses_failure_background(mode: int) -> bool:
	if mode == OverlayMode.FAILURE:
		return true
	if mode == OverlayMode.MODERN_MENU:
		return _modern_menu_return_mode == OverlayMode.FAILURE
	if mode == OverlayMode.SLOT_SELECTOR:
		return (
			_slot_return_mode == OverlayMode.FAILURE
			or (
				_slot_return_mode == OverlayMode.MODERN_MENU
				and _modern_menu_return_mode == OverlayMode.FAILURE
			)
		)
	if mode == OverlayMode.LEVEL_SELECTOR:
		return (
			_level_selector_return_mode == OverlayMode.FAILURE
			or (
				_level_selector_return_mode == OverlayMode.MODERN_MENU
				and _modern_menu_return_mode == OverlayMode.FAILURE
			)
		)
	if mode == OverlayMode.SETTINGS:
		return (
			_settings_return_mode == OverlayMode.FAILURE
			or (
				_settings_return_mode == OverlayMode.MODERN_MENU
				and _modern_menu_return_mode == OverlayMode.FAILURE
			)
		)
	return false


func close_active_overlay() -> bool:
	if overlay_mode in [OverlayMode.NONE, OverlayMode.FAILURE]:
		return false
	if overlay_mode == OverlayMode.MODERN_MENU:
		_enter_mode(_modern_menu_return_mode)
		return true
	if overlay_mode == OverlayMode.CREDITS:
		_enter_mode(_credits_return_mode)
		return true
	if overlay_mode == OverlayMode.SLOT_SELECTOR:
		_return_from_slot_selector()
		return true
	if overlay_mode == OverlayMode.SETTINGS:
		_return_from_settings()
		return true
	if overlay_mode == OverlayMode.LEVEL_SELECTOR:
		_return_from_level_selector()
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
	var failure_background := _mode_uses_failure_background(mode)
	var pause_background := mode == OverlayMode.PAUSE_MENU
	var desaturate_background := pause_background or failure_background
	# The original W/A popup is a right-side panel over the live scene.  It
	# blocks commands while open, but it does not tint the map underneath.
	# F1 replaces the whole primary surface with black before blitting the
	# native 640x480 guide; other modal screens retain the modern dimmer.
	_dim.color = (
		ORIGINAL_HELP_BACKDROP_COLOR
		if mode in [OverlayMode.HELP, OverlayMode.CREDITS]
		else OVERLAY_DIM_COLOR
	)
	var desaturate_material := _failure_desaturate.material as ShaderMaterial
	if desaturate_material != null:
		desaturate_material.set_shader_parameter("brightness", 1.0)
		desaturate_material.set_shader_parameter("average_mix", 1.0)
	_dim.visible = not desaturate_background and mode != OverlayMode.INVENTORY
	_failure_desaturate.visible = desaturate_background
	_classic_menu_panel.visible = mode == OverlayMode.PAUSE_MENU
	_classic_failure_panel.visible = mode == OverlayMode.FAILURE
	_menu_panel.visible = mode == OverlayMode.MODERN_MENU
	_map_panel.visible = mode == OverlayMode.TACTICAL_MAP
	_inventory_panel.visible = mode == OverlayMode.INVENTORY
	_slot_selector_panel.visible = mode == OverlayMode.SLOT_SELECTOR
	_settings_panel.visible = mode == OverlayMode.SETTINGS
	_help_panel.visible = mode == OverlayMode.HELP
	_level_selector_panel.visible = mode == OverlayMode.LEVEL_SELECTOR
	_credits_panel.visible = mode == OverlayMode.CREDITS


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
	if overlay_mode == OverlayMode.PAUSE_MENU and _next_level_button.visible:
		_on_next_level_pressed()
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
	if return_mode not in [
		OverlayMode.PAUSE_MENU,
		OverlayMode.FAILURE,
		OverlayMode.MODERN_MENU,
	]:
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


func _show_level_selector_from_menu() -> void:
	show_level_selector(false)


func _show_failure_main_menu() -> void:
	_modern_menu_return_mode = OverlayMode.FAILURE
	_enter_mode(OverlayMode.MODERN_MENU)
	_menu_title.text = "任务失败"
	_menu_message.text = (
		_failure_text
		+ "\n可重玩本关、读取存档、选择其他任务或调整设置。"
	)
	_resume_button.visible = false
	_next_level_button.visible = false
	_save_button.visible = false
	_load_button.visible = true
	_load_button.disabled = not _failure_can_load
	_restart_button.visible = true
	_level_select_button.visible = true


func _show_game_settings() -> void:
	_modern_menu_return_mode = overlay_mode
	if _modern_menu_return_mode not in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]:
		_modern_menu_return_mode = OverlayMode.PAUSE_MENU
	_enter_mode(OverlayMode.MODERN_MENU)
	_menu_title.text = "游戏设置"
	_menu_message.text = "现代显示、难度与辅助选项"


func _show_credits() -> void:
	_credits_return_mode = overlay_mode
	if _credits_return_mode not in [OverlayMode.PAUSE_MENU, OverlayMode.FAILURE]:
		_credits_return_mode = OverlayMode.PAUSE_MENU
	_enter_mode(OverlayMode.CREDITS)


func _on_level_chosen(level_id: String) -> void:
	_close_overlay()
	level_requested.emit(level_id)


func _return_from_level_selector() -> void:
	var return_mode := _level_selector_return_mode
	if return_mode in [
		OverlayMode.PAUSE_MENU,
		OverlayMode.FAILURE,
		OverlayMode.MODERN_MENU,
	]:
		_enter_mode(return_mode)
		return
	_close_overlay()
	level_selection_cancelled.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _show_settings() -> void:
	_settings_return_mode = overlay_mode
	if _settings_return_mode not in [
		OverlayMode.PAUSE_MENU,
		OverlayMode.FAILURE,
		OverlayMode.MODERN_MENU,
	]:
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
	var display_mode := _selected_display_mode()
	settings = {
		"fullscreen": display_mode != "windowed",
		"display_mode": display_mode,
		"muted": _muted_toggle.button_pressed,
		"resolution_policy": str(settings.get("resolution_policy", "desktop")),
		"window_width": int(settings.get("window_width", 1280)),
		"window_height": int(settings.get("window_height", 720)),
		"vsync": bool(settings.get("vsync", true)),
		"subtitles": _subtitles_toggle.button_pressed,
		"show_briefings": _briefings_toggle.button_pressed,
		"edge_scroll": _edge_scroll_toggle.button_pressed,
		"reduce_camera_motion": _reduce_camera_motion_toggle.button_pressed,
		"large_cursor": _large_cursor_toggle.button_pressed,
		"difficulty_mode": _selected_difficulty_mode(),
		"mission_rule_mode": _selected_mission_rule_mode(),
		"master_volume": _audio_slider_value("master", 0.8),
		"music_volume": _audio_slider_value("music", 0.8),
		"sfx_volume": _audio_slider_value("sfx", 0.9),
		"voice_volume": _audio_slider_value("voice", 1.0),
		"controls": (settings.get("controls", {}) as Dictionary).duplicate(true),
	}
	_update_volume_labels()
	settings_changed.emit(settings_snapshot())


func _selected_display_mode() -> String:
	if _display_mode_option == null or _display_mode_option.selected < 0:
		return str(settings.get("display_mode", "windowed"))
	var mode := str(
		_display_mode_option.get_item_metadata(_display_mode_option.selected)
	)
	return mode if mode in DISPLAY_MODES else "windowed"


func _select_display_mode(mode: String) -> void:
	if _display_mode_option == null:
		return
	var normalized := mode if mode in DISPLAY_MODES else "windowed"
	for index: int in range(_display_mode_option.item_count):
		if str(_display_mode_option.get_item_metadata(index)) == normalized:
			_display_mode_option.select(index)
			return
	_display_mode_option.select(0)


func _audio_slider_value(channel: String, fallback: float) -> float:
	if not _audio_sliders.has(channel):
		return fallback
	return clampf(float((_audio_sliders[channel] as HSlider).value), 0.0, 1.0)


func _selected_difficulty_mode() -> String:
	if _difficulty_option == null or _difficulty_option.selected < 0:
		return str(settings.get("difficulty_mode", "original"))
	var metadata: Variant = _difficulty_option.get_item_metadata(_difficulty_option.selected)
	var mode := str(metadata)
	return mode if mode in DIFFICULTY_MODES else "original"


func _select_difficulty_mode(mode: String) -> void:
	if _difficulty_option == null:
		return
	var normalized := mode if mode in DIFFICULTY_MODES else "original"
	for index: int in range(_difficulty_option.item_count):
		if str(_difficulty_option.get_item_metadata(index)) == normalized:
			_difficulty_option.select(index)
			return
	_difficulty_option.select(0)


func _selected_mission_rule_mode() -> String:
	if _mission_rule_option == null or _mission_rule_option.selected < 0:
		return str(settings.get("mission_rule_mode", "stable_mod"))
	var metadata: Variant = _mission_rule_option.get_item_metadata(
		_mission_rule_option.selected
	)
	var mode := str(metadata)
	return mode if mode in MISSION_RULE_MODES else "stable_mod"


func _select_mission_rule_mode(mode: String) -> void:
	if _mission_rule_option == null:
		return
	var normalized := mode if mode in MISSION_RULE_MODES else "stable_mod"
	for index: int in range(_mission_rule_option.item_count):
		if str(_mission_rule_option.get_item_metadata(index)) == normalized:
			_mission_rule_option.select(index)
			return
	_mission_rule_option.select(0)


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
	_build_original_top_hud()
	_build_original_bottom_hud()

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
	_dim.color = OVERLAY_DIM_COLOR
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_build_menu_panel()
	_build_classic_pause_menu()
	_build_classic_failure_menu()
	_build_map_panel()
	_build_inventory_panel()
	_build_slot_selector_panel()
	_build_level_selector_panel()
	_build_settings_panel()
	_build_help_panel()
	_build_credits_panel()
	_root.visible = false


func _build_original_top_hud() -> void:
	_original_top_hud = Control.new()
	_original_top_hud.name = "OriginalTopHud"
	_original_top_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_original_top_hud.position = Vector2(53.0, 1.0)
	_original_top_hud.size = Vector2(250.0, 20.0)
	_original_top_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_top_hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_original_top_hud.visible = false
	_hud_root.add_child(_original_top_hud)

	_original_hud_ammo_font = SystemFont.new()
	_original_hud_ammo_font.font_names = PackedStringArray([
		"SimSun",
		"宋体",
		"Arial",
	])
	_original_hud_status_row = HBoxContainer.new()
	_original_hud_status_row.name = "OriginalHudAmmoStatus"
	_original_hud_status_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_original_hud_status_row.position = Vector2.ZERO
	_original_hud_status_row.size = Vector2(250.0, 20.0)
	_original_hud_status_row.add_theme_constant_override("separation", 0)
	_original_hud_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_top_hud.add_child(_original_hud_status_row)
	for actor_name: String in ORIGINAL_HUD_PORTRAITS:
		_build_original_hud_status(actor_name)


func _build_original_hud_status(actor_name: String) -> void:
	var container := Control.new()
	container.name = "OriginalHudAmmo_%s" % actor_name
	container.custom_minimum_size = Vector2(50.0, 20.0)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = false
	_original_hud_status_row.add_child(container)

	var texture := TextureRect.new()
	texture.name = "StatusTexture"
	texture.position = Vector2.ZERO
	texture.size = Vector2(50.0, 20.0)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(texture)

	var ammo_label := Label.new()
	ammo_label.name = "AmmoCount"
	ammo_label.position = Vector2(17.0, 2.0)
	ammo_label.size = Vector2(33.0, 20.0)
	ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_label.add_theme_font_override("font", _original_hud_ammo_font)
	ammo_label.add_theme_font_size_override("font_size", 16)
	ammo_label.add_theme_color_override("font_color", Color.RED)
	ammo_label.add_theme_constant_override("outline_size", 0)
	container.add_child(ammo_label)
	_original_hud_status_controls[actor_name] = {
		"container": container,
		"texture": texture,
		"ammo_label": ammo_label,
	}


func _build_original_bottom_hud() -> void:
	_original_bottom_hud = Control.new()
	_original_bottom_hud.name = "OriginalBottomHud"
	_original_bottom_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_original_bottom_hud.offset_top = -ORIGINAL_BOTTOM_HUD_HEIGHT
	_original_bottom_hud.offset_bottom = 0.0
	_original_bottom_hud.mouse_filter = Control.MOUSE_FILTER_STOP
	_original_bottom_hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_original_bottom_hud.visible = false
	_hud_root.add_child(_original_bottom_hud)

	_original_hud_background = NinePatchRect.new()
	_original_hud_background.name = "OriginalHudBackground"
	_original_hud_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_original_hud_background.patch_margin_left = 27
	_original_hud_background.patch_margin_right = 27
	_original_hud_background.patch_margin_top = 2
	_original_hud_background.patch_margin_bottom = 3
	_original_hud_background.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_TILE
	)
	_original_hud_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_bottom_hud.add_child(_original_hud_background)

	_original_hud_border = NinePatchRect.new()
	_original_hud_border.name = "OriginalHudBorder"
	_original_hud_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_original_hud_border.patch_margin_left = 27
	_original_hud_border.patch_margin_right = 27
	_original_hud_border.patch_margin_top = 3
	_original_hud_border.patch_margin_bottom = 4
	_original_hud_border.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_TILE
	)
	_original_hud_border.draw_center = false
	_original_hud_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_bottom_hud.add_child(_original_hud_border)

	for side: String in ["Left", "Right"]:
		var side_texture := TextureRect.new()
		side_texture.name = "OriginalHud%sBorder" % side
		side_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		side_texture.stretch_mode = TextureRect.STRETCH_KEEP
		side_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == "Left":
			side_texture.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			side_texture.offset_left = 0.0
			side_texture.offset_right = 27.0
		else:
			side_texture.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			side_texture.offset_left = -27.0
			side_texture.offset_right = 0.0
		side_texture.offset_top = -62.0
		side_texture.offset_bottom = 0.0
		_original_bottom_hud.add_child(side_texture)

	_original_hud_portrait_row = HBoxContainer.new()
	_original_hud_portrait_row.name = "OriginalHudPortraits"
	_original_hud_portrait_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_original_hud_portrait_row.offset_left = 10.0
	_original_hud_portrait_row.offset_top = 6.0
	_original_hud_portrait_row.offset_right = 10.0 + (50.0 * 5.0)
	_original_hud_portrait_row.offset_bottom = 56.0
	_original_hud_portrait_row.add_theme_constant_override("separation", 0)
	_original_hud_portrait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_bottom_hud.add_child(_original_hud_portrait_row)
	for actor_name: String in ORIGINAL_HUD_PORTRAITS:
		_build_original_hud_portrait(actor_name)

	_original_hud_weapon_panel = Panel.new()
	_original_hud_weapon_panel.name = "OriginalHudWeapon"
	_original_hud_weapon_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_original_hud_weapon_panel.offset_left = -372.0
	_original_hud_weapon_panel.offset_top = 6.0
	_original_hud_weapon_panel.offset_right = -170.0
	_original_hud_weapon_panel.offset_bottom = 56.0
	_original_hud_weapon_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_original_hud_weapon_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_original_hud_weapon_panel.tooltip_text = "点击切换下一件武器（Tab）"
	_original_hud_weapon_panel.gui_input.connect(
		_on_original_hud_weapon_gui_input
	)
	_original_hud_weapon_panel.visible = false
	var weapon_style := StyleBoxFlat.new()
	weapon_style.bg_color = Color(0.035, 0.045, 0.031, 0.82)
	weapon_style.border_color = Color(0.58, 0.50, 0.27, 0.9)
	weapon_style.set_border_width_all(1)
	weapon_style.corner_radius_top_left = 3
	weapon_style.corner_radius_top_right = 3
	weapon_style.corner_radius_bottom_left = 3
	weapon_style.corner_radius_bottom_right = 3
	_original_hud_weapon_panel.add_theme_stylebox_override("panel", weapon_style)
	_original_bottom_hud.add_child(_original_hud_weapon_panel)

	_original_hud_weapon_icon = TextureRect.new()
	_original_hud_weapon_icon.name = "WeaponIcon"
	_original_hud_weapon_icon.position = Vector2(4.0, 3.0)
	_original_hud_weapon_icon.size = Vector2(44.0, 44.0)
	_original_hud_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_original_hud_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_original_hud_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_hud_weapon_panel.add_child(_original_hud_weapon_icon)

	_original_hud_weapon_name = Label.new()
	_original_hud_weapon_name.name = "WeaponName"
	_original_hud_weapon_name.position = Vector2(54.0, 4.0)
	_original_hud_weapon_name.size = Vector2(142.0, 22.0)
	_original_hud_weapon_name.add_theme_color_override(
		"font_color", Color(0.94, 0.88, 0.66)
	)
	_original_hud_weapon_name.add_theme_font_size_override("font_size", 16)
	_original_hud_weapon_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_hud_weapon_panel.add_child(_original_hud_weapon_name)

	_original_hud_weapon_ammo = Label.new()
	_original_hud_weapon_ammo.name = "WeaponAmmo"
	_original_hud_weapon_ammo.position = Vector2(54.0, 25.0)
	_original_hud_weapon_ammo.size = Vector2(142.0, 20.0)
	_original_hud_weapon_ammo.add_theme_color_override(
		"font_color", Color(0.88, 0.34, 0.25)
	)
	_original_hud_weapon_ammo.add_theme_font_size_override("font_size", 14)
	_original_hud_weapon_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_hud_weapon_panel.add_child(_original_hud_weapon_ammo)

	_original_hud_action_row = HBoxContainer.new()
	_original_hud_action_row.name = "OriginalHudActions"
	_original_hud_action_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_original_hud_action_row.offset_left = -160.0
	_original_hud_action_row.offset_top = 6.0
	_original_hud_action_row.offset_right = -10.0
	_original_hud_action_row.offset_bottom = 56.0
	_original_hud_action_row.add_theme_constant_override("separation", 0)
	_original_hud_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_original_bottom_hud.add_child(_original_hud_action_row)
	for descriptor: Dictionary in ORIGINAL_HUD_ACTIONS:
		_build_original_hud_action(descriptor)


func _build_original_hud_portrait(actor_name: String) -> void:
	var container := Control.new()
	container.name = "OriginalHudPortrait_%s" % actor_name
	container.custom_minimum_size = Vector2(50.0, 50.0)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = false
	_original_hud_portrait_row.add_child(container)

	var button := TextureButton.new()
	button.name = "PortraitButton"
	button.position = Vector2.ZERO
	button.size = Vector2(50.0, 50.0)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "选择%s并将视图定位到该角色" % actor_name
	button.pressed.connect(_on_original_hud_actor_pressed.bind(actor_name))
	container.add_child(button)

	var health_back := ColorRect.new()
	health_back.name = "HealthBackground"
	health_back.position = Vector2(42.0, 13.0)
	health_back.size = Vector2(5.0, 34.0)
	health_back.color = Color.BLACK
	health_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(health_back)

	var health_fill := ColorRect.new()
	health_fill.name = "HealthFill"
	health_fill.position = Vector2(43.0, 14.0)
	health_fill.size = Vector2(3.0, 32.0)
	health_fill.color = Color.GREEN
	health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(health_fill)
	_original_hud_portrait_controls[actor_name] = {
		"container": container,
		"button": button,
		"health_back": health_back,
		"health_fill": health_fill,
		"alive": true,
		"selected": false,
	}


func _build_original_hud_action(descriptor: Dictionary) -> void:
	var action := str(descriptor["action"])
	var button := TextureButton.new()
	button.name = "OriginalHudAction_%s" % action
	button.custom_minimum_size = Vector2(50.0, 50.0)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.toggle_mode = bool(descriptor.get("toggle", false))
	button.tooltip_text = str(descriptor.get("tooltip", action))
	button.pressed.connect(_on_original_hud_action_pressed.bind(action))
	_original_hud_action_row.add_child(button)
	_original_hud_action_buttons[action] = button


func _on_original_hud_action_pressed(action: String) -> void:
	original_hud_action_requested.emit(action)


func _on_original_hud_actor_pressed(actor_name: String) -> void:
	original_hud_actor_requested.emit(actor_name)


func _on_original_hud_weapon_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	get_viewport().set_input_as_handled()
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	inventory_cycle_requested.emit(1)


func _update_original_hud_portrait_textures() -> void:
	if not _original_hud_assets_ready:
		return
	for actor_name: String in _original_hud_portrait_controls:
		var controls := _original_hud_portrait_controls[actor_name] as Dictionary
		var portrait := ORIGINAL_HUD_PORTRAITS[actor_name] as Dictionary
		var state := "dead"
		if bool(controls.get("alive", true)):
			state = "selected" if bool(controls.get("selected", false)) else "idle"
		var button := controls.get("button") as TextureButton
		button.texture_normal = _load_original_hud_texture(
			"psd", int(portrait[state])
		)


func _update_original_hud_status_textures() -> void:
	if not _original_hud_assets_ready:
		return
	for actor_name: String in _original_hud_status_controls:
		var controls := _original_hud_status_controls[actor_name] as Dictionary
		var texture := controls.get("texture") as TextureRect
		texture.texture = _load_original_hud_texture(
			"psd", int(ORIGINAL_HUD_AMMO_STATUS[actor_name])
		)


func _set_original_hud_side_texture(
	node_name: String,
	asset_kind: String,
	gfl_index: int,
) -> void:
	var node := _original_bottom_hud.get_node_or_null(node_name) as TextureRect
	if node != null:
		node.texture = _load_original_hud_texture(asset_kind, gfl_index)


func _load_original_hud_texture(asset_kind: String, gfl_index: int) -> Texture2D:
	if _original_hud_converted_root.is_empty() or gfl_index <= 0:
		return null
	var cache_key := "%s/%04d" % [asset_kind, gfl_index]
	if _original_hud_texture_cache.has(cache_key):
		return _original_hud_texture_cache[cache_key] as Texture2D
	var path := _original_hud_converted_root.path_join(
		"%s/%04d.png" % [asset_kind, gfl_index]
	).simplify_path()
	var root_prefix := _original_hud_converted_root.trim_suffix("/").trim_suffix("\\")
	if not path.begins_with(root_prefix + "/") and not path.begins_with(root_prefix + "\\"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_original_hud_texture_cache[cache_key] = texture
	return texture


func _load_original_color_keyed_hud_texture(
	asset_kind: String,
	gfl_index: int,
) -> Texture2D:
	var cache_key := "%s-color-key/%04d" % [asset_kind, gfl_index]
	if _original_hud_texture_cache.has(cache_key):
		return _original_hud_texture_cache[cache_key] as Texture2D
	if _original_hud_converted_root.is_empty() or gfl_index <= 0:
		return null
	var path := _original_hud_converted_root.path_join(
		"%s/%04d.png" % [asset_kind, gfl_index]
	).simplify_path()
	var root_prefix := _original_hud_converted_root.trim_suffix("/").trim_suffix("\\")
	if not path.begins_with(root_prefix + "/") and not path.begins_with(root_prefix + "\\"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	for offset: int in range(0, pixels.size(), 4):
		# The original DirectDraw popup treats exact RGB black as its source
		# colour key even when the archived PSD composite marks it opaque.
		if pixels[offset] == 0 and pixels[offset + 1] == 0 and pixels[offset + 2] == 0:
			pixels[offset + 3] = 0
	var keyed_image := Image.create_from_data(
		image.get_width(),
		image.get_height(),
		false,
		Image.FORMAT_RGBA8,
		pixels,
	)
	var texture := ImageTexture.create_from_image(keyed_image)
	_original_hud_texture_cache[cache_key] = texture
	return texture


func _update_original_hud_visibility() -> void:
	if _original_top_hud != null:
		_original_top_hud.visible = (
			_original_hud_assets_ready and _original_hud_requested_visible
		)
	if _original_bottom_hud != null:
		_original_bottom_hud.visible = (
			_original_hud_assets_ready and _original_hud_requested_visible
		)


func _build_menu_panel() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "GameMenuPanel"
	_center_control(_menu_panel, Vector2(620.0, 700.0))
	_menu_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.115, 0.09, 0.98)))
	_root.add_child(_menu_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 560.0
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)

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
	_level_select_button = _add_button(
		content,
		"选择关卡…",
		_show_level_selector_from_menu,
	)

	var separator := HSeparator.new()
	content.add_child(separator)
	var settings_title := Label.new()
	settings_title.text = "显示与辅助设置"
	settings_title.add_theme_font_size_override("font_size", 18)
	content.add_child(settings_title)

	var difficulty_row := HBoxContainer.new()
	var difficulty_label := Label.new()
	difficulty_label.text = "游戏难度"
	difficulty_label.custom_minimum_size.x = 115.0
	difficulty_row.add_child(difficulty_label)
	_difficulty_option = OptionButton.new()
	_difficulty_option.name = "DifficultyMode"
	_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var difficulty_labels := {
		"original": "原版复刻（MOD 行为基准）",
		"easy": "轻松（重制调校）",
		"normal": "标准（重制调校）",
		"hard": "困难（重制调校）",
	}
	for mode: String in DIFFICULTY_MODES:
		_difficulty_option.add_item(str(difficulty_labels[mode]))
		_difficulty_option.set_item_metadata(_difficulty_option.item_count - 1, mode)
	_difficulty_option.item_selected.connect(_on_setting_changed)
	difficulty_row.add_child(_difficulty_option)
	content.add_child(difficulty_row)
	var difficulty_hint := Label.new()
	difficulty_hint.text = "难度变更会保存，并在重新开始、下一关或读取对应存档时生效"
	difficulty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	difficulty_hint.add_theme_font_size_override("font_size", 13)
	difficulty_hint.add_theme_color_override("font_color", Color(0.75, 0.77, 0.66))
	content.add_child(difficulty_hint)

	var mission_rule_row := HBoxContainer.new()
	var mission_rule_label := Label.new()
	mission_rule_label.text = "任务规则"
	mission_rule_label.custom_minimum_size.x = 115.0
	mission_rule_row.add_child(mission_rule_label)
	_mission_rule_option = OptionButton.new()
	_mission_rule_option.name = "MissionRuleMode"
	_mission_rule_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mission_rule_labels := {
		"stable_mod": "稳定 MOD（忠实保留实际判定）",
		"repaired": "修复增强（按任务简报补全）",
	}
	for mode: String in MISSION_RULE_MODES:
		_mission_rule_option.add_item(str(mission_rule_labels[mode]))
		_mission_rule_option.set_item_metadata(
			_mission_rule_option.item_count - 1,
			mode,
		)
	_mission_rule_option.item_selected.connect(_on_setting_changed)
	mission_rule_row.add_child(_mission_rule_option)
	content.add_child(mission_rule_row)
	var mission_rule_hint := Label.new()
	mission_rule_hint.text = "影响第 10/12 关已确认的原版控制流缺陷；变更在重开、下一关或读档时生效"
	mission_rule_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_rule_hint.add_theme_font_size_override("font_size", 13)
	mission_rule_hint.add_theme_color_override("font_color", Color(0.75, 0.77, 0.66))
	content.add_child(mission_rule_hint)

	var display_row := HBoxContainer.new()
	var display_label := Label.new()
	display_label.text = "显示模式"
	display_label.custom_minimum_size.x = 115.0
	display_row.add_child(display_label)
	_display_mode_option = OptionButton.new()
	_display_mode_option.name = "DisplayMode"
	_display_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var display_labels := {
		"windowed": "窗口（默认 1280×720）",
		"fullscreen": "全屏（当前桌面分辨率）",
		"borderless": "无边框最大化（推荐多任务）",
	}
	for mode: String in DISPLAY_MODES:
		_display_mode_option.add_item(str(display_labels[mode]))
		_display_mode_option.set_item_metadata(
			_display_mode_option.item_count - 1,
			mode,
		)
	_display_mode_option.item_selected.connect(_on_setting_changed)
	display_row.add_child(_display_mode_option)
	content.add_child(display_row)

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

	_reduce_camera_motion_toggle = CheckButton.new()
	_reduce_camera_motion_toggle.text = "减少自动镜头运动（剧情聚焦改为立即定位）"
	_reduce_camera_motion_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_reduce_camera_motion_toggle)

	_large_cursor_toggle = CheckButton.new()
	_large_cursor_toggle.text = "大号原版光标（2 倍，像素锐化）"
	_large_cursor_toggle.toggled.connect(_on_setting_changed)
	content.add_child(_large_cursor_toggle)

	_add_button(content, "声音与按键设置", _show_settings)
	_add_button(content, "退出游戏", _on_quit_pressed)


func _build_classic_pause_menu() -> void:
	_classic_menu_panel = Control.new()
	_classic_menu_panel.name = "OriginalPauseMenu"
	_classic_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_classic_menu_panel.offset_left = ORIGINAL_PAUSE_MENU_CENTER_OFFSET.x
	_classic_menu_panel.offset_top = ORIGINAL_PAUSE_MENU_CENTER_OFFSET.y
	_classic_menu_panel.offset_right = (
		ORIGINAL_PAUSE_MENU_CENTER_OFFSET.x + ORIGINAL_PAUSE_MENU_SIZE.x
	)
	_classic_menu_panel.offset_bottom = (
		ORIGINAL_PAUSE_MENU_CENTER_OFFSET.y + ORIGINAL_PAUSE_MENU_SIZE.y
	)
	_classic_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_classic_menu_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_classic_menu_panel)

	_classic_resume_button = _build_classic_pause_button(
		"resume", 0, _on_resume_pressed
	)
	_classic_restart_button = _build_classic_pause_button(
		"restart", 1, _on_restart_pressed
	)
	_classic_level_select_button = _build_classic_pause_button(
		"missions", 2, _show_level_selector_from_menu
	)
	_classic_save_button = _build_classic_pause_button(
		"save", 3, _on_save_pressed
	)
	_classic_load_button = _build_classic_pause_button(
		"load", 4, _on_load_pressed
	)
	_classic_settings_button = _build_classic_pause_button(
		"settings", 5, _show_game_settings
	)
	_classic_credits_button = _build_classic_pause_button(
		"credits", 6, _show_credits
	)
	_classic_quit_button = _build_classic_pause_button(
		"quit", 7, _on_quit_pressed
	)


func _build_classic_pause_button(
	button_id: String,
	row: int,
	callback: Callable,
) -> TextureButton:
	var descriptor: Dictionary = {}
	for candidate: Dictionary in ORIGINAL_PAUSE_MENU_BUTTONS:
		if str(candidate["id"]) == button_id:
			descriptor = candidate
			break
	var button := TextureButton.new()
	button.name = "OriginalPause_%s" % button_id
	button.position = Vector2(0.0, float(row) * ORIGINAL_PAUSE_MENU_BUTTON_PITCH)
	button.size = Vector2(132.0, 38.0)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = str(descriptor.get("tooltip", button_id))
	button.pressed.connect(callback)
	_classic_menu_panel.add_child(button)
	_classic_menu_buttons[button_id] = button
	return button


func _build_classic_failure_menu() -> void:
	_original_failure_font = SystemFont.new()
	_original_failure_font.font_names = PackedStringArray([
		"SimSun",
		"NSimSun",
		"宋体",
	])
	_original_failure_font.font_weight = 400
	_original_failure_font.allow_system_fallback = true
	_original_failure_font.force_autohinter = true

	_classic_failure_panel = Control.new()
	_classic_failure_panel.name = "OriginalFailureMenu"
	_classic_failure_panel.set_anchors_preset(Control.PRESET_CENTER)
	_classic_failure_panel.offset_left = 0.0
	_classic_failure_panel.offset_top = 0.0
	_classic_failure_panel.offset_right = 0.0
	_classic_failure_panel.offset_bottom = 0.0
	_classic_failure_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_classic_failure_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.add_child(_classic_failure_panel)

	_failure_title_background = TextureRect.new()
	_failure_title_background.name = "OriginalFailureTitle"
	_failure_title_background.position = ORIGINAL_FAILURE_TITLE_CENTER_OFFSET
	_failure_title_background.size = ORIGINAL_FAILURE_TITLE_SIZE
	_failure_title_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_failure_title_background.stretch_mode = TextureRect.STRETCH_KEEP
	_failure_title_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_classic_failure_panel.add_child(_failure_title_background)

	_failure_title_label = Label.new()
	_failure_title_label.name = "OriginalFailureTitleText"
	_failure_title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_failure_title_label.text = "任务失败"
	_failure_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_failure_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_failure_title_label.add_theme_font_size_override("font_size", 38)
	_style_original_failure_text(_failure_title_label)
	_failure_title_background.add_child(_failure_title_label)

	_failure_restart_button = TextureButton.new()
	_failure_restart_button.name = "OriginalFailureRestart"
	_failure_restart_button.position = ORIGINAL_FAILURE_RESTART_CENTER_OFFSET
	_failure_restart_button.size = ORIGINAL_FAILURE_BUTTON_SIZE
	_failure_restart_button.ignore_texture_size = true
	_failure_restart_button.stretch_mode = TextureButton.STRETCH_KEEP
	_failure_restart_button.focus_mode = Control.FOCUS_ALL
	_failure_restart_button.tooltip_text = "重玩本关"
	_failure_restart_button.pressed.connect(_on_restart_pressed)
	_classic_failure_panel.add_child(_failure_restart_button)

	_failure_main_button = TextureButton.new()
	_failure_main_button.name = "OriginalFailureMain"
	_failure_main_button.position = ORIGINAL_FAILURE_MAIN_CENTER_OFFSET
	_failure_main_button.size = ORIGINAL_FAILURE_BUTTON_SIZE
	_failure_main_button.ignore_texture_size = true
	_failure_main_button.stretch_mode = TextureButton.STRETCH_KEEP
	_failure_main_button.focus_mode = Control.FOCUS_ALL
	_failure_main_button.tooltip_text = "回主界面"
	_failure_main_button.pressed.connect(_show_failure_main_menu)
	_failure_main_button.mouse_entered.connect(_set_failure_main_highlight.bind(true))
	_failure_main_button.mouse_exited.connect(_set_failure_main_highlight.bind(false))
	_failure_main_button.focus_entered.connect(_set_failure_main_highlight.bind(true))
	_failure_main_button.focus_exited.connect(_set_failure_main_highlight.bind(false))
	_classic_failure_panel.add_child(_failure_main_button)

	_failure_main_label = Label.new()
	_failure_main_label.name = "OriginalFailureMainText"
	_failure_main_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_failure_main_label.text = "回主界面"
	_failure_main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_failure_main_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_failure_main_label.add_theme_font_size_override("font_size", 25)
	_failure_main_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_original_failure_text(_failure_main_label)
	_failure_main_button.add_child(_failure_main_label)


func _style_original_failure_text(label: Label) -> void:
	label.add_theme_font_override("font", _original_failure_font)
	label.add_theme_color_override("font_color", ORIGINAL_FAILURE_TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.02, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_failure_main_highlight(highlighted: bool) -> void:
	if _failure_main_label == null:
		return
	_failure_main_label.add_theme_color_override(
		"font_color",
		ORIGINAL_FAILURE_TEXT_HOVER_COLOR if highlighted else ORIGINAL_FAILURE_TEXT_COLOR,
	)


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
	_map_panel.offset_left = -276.0
	_map_panel.offset_top = -(ORIGINAL_BOTTOM_HUD_HEIGHT + 158.0)
	_map_panel.offset_right = 0.0
	_map_panel.offset_bottom = -ORIGINAL_BOTTOM_HUD_HEIGHT
	# The child map view owns pointer input. PASS keeps that child in the GUI
	# hit-test chain while allowing any unclaimed decorative-border event to
	# reach Main's explicit no-click-through boundary. IGNORE on this container
	# can exclude its descendants from viewport GUI picking on some renderers.
	_map_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud_root.add_child(_map_panel)
	_map_view = TACTICAL_MAP_VIEW_SCRIPT.new()
	_map_view.custom_minimum_size = Vector2(276.0, 158.0)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_view.focus_mode = Control.FOCUS_NONE
	_map_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_map_view.tooltip_text = "点击或拖动以移动游戏视图"
	_map_view.world_position_requested.connect(_on_map_position_requested)
	_map_panel.add_child(_map_view)
	_map_panel.visible = false


func _resize_tactical_map(texture: Texture2D) -> void:
	if _map_panel == null or _map_view == null:
		return
	var map_size := Vector2(276.0, 158.0)
	if texture != null:
		map_size = texture.get_size()
	_map_view.custom_minimum_size = map_size
	_map_panel.offset_left = -map_size.x
	_map_panel.offset_top = -(ORIGINAL_BOTTOM_HUD_HEIGHT + map_size.y)
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
	_inventory_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(_inventory_panel)
	_inventory_background = TextureRect.new()
	_inventory_background.name = "OriginalInventoryBackground"
	_inventory_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inventory_background.stretch_mode = TextureRect.STRETCH_KEEP
	_inventory_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_inventory_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_panel.add_child(_inventory_background)
	_inventory_view = INVENTORY_GRID_VIEW_SCRIPT.new()
	_inventory_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inventory_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_view.slot_activated.connect(_on_inventory_slot_activated)
	_inventory_panel.add_child(_inventory_view)


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


func _build_level_selector_panel() -> void:
	_level_selector_panel = PanelContainer.new()
	_level_selector_panel.name = "CampaignLevelSelectorPanel"
	_center_control(_level_selector_panel, Vector2(820.0, 600.0))
	_level_selector_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.065, 0.078, 0.062, 0.99)),
	)
	_root.add_child(_level_selector_panel)
	_level_selector = CAMPAIGN_LEVEL_SELECTOR_SCRIPT.new()
	_level_selector_panel.add_child(_level_selector)
	_level_selector.level_chosen.connect(_on_level_chosen)
	_level_selector.back_requested.connect(_return_from_level_selector)


func _build_help_panel() -> void:
	_help_panel = PanelContainer.new()
	_help_panel.name = "OriginalControlGuidePanel"
	_center_control(_help_panel, ORIGINAL_HELP_SIZE)
	_help_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(_help_panel)
	_help_texture = TextureRect.new()
	_help_texture.custom_minimum_size = ORIGINAL_HELP_SIZE
	_help_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_help_texture.stretch_mode = TextureRect.STRETCH_KEEP
	_help_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_help_panel.add_child(_help_texture)
	_help_fallback = Label.new()
	_help_fallback.text = (
		"F2–F6 选择队员　R 跑/走　C 匍匐/站立\n"
		+ "W 武器栏　A 物品栏　S 视线观察　B 掩埋模式　M 地图\n"
		+ "1–0 武器快捷键　F7 任务简报　Esc 系统菜单\n"
		+ "左键选择/下令　右键拖框/菜单返回　按住 Ctrl 或 ↑ 强制目标"
	)
	_help_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_fallback.custom_minimum_size = ORIGINAL_HELP_SIZE
	_help_fallback.add_theme_font_size_override("font_size", 19)
	_help_fallback.add_theme_color_override("font_color", Color(0.92, 0.90, 0.78))
	_help_fallback.add_theme_color_override("font_outline_color", Color.BLACK)
	_help_fallback.add_theme_constant_override("outline_size", 2)
	_help_panel.add_child(_help_fallback)


func _build_credits_panel() -> void:
	_credits_panel = PanelContainer.new()
	_credits_panel.name = "OriginalCreditsPanel"
	_center_control(_credits_panel, ORIGINAL_HELP_SIZE)
	_credits_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(_credits_panel)
	_credits_texture = TextureRect.new()
	_credits_texture.custom_minimum_size = ORIGINAL_HELP_SIZE
	_credits_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_credits_texture.stretch_mode = TextureRect.STRETCH_KEEP
	_credits_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_credits_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_credits_panel.add_child(_credits_texture)


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


func _release_gui_focus() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


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
uniform float brightness = 0.48;
uniform float average_mix = 0.0;
void fragment() {
	vec4 source = texture(screen_texture, SCREEN_UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float average = (source.r + source.g + source.b) / 3.0;
	float gray = mix(luminance, average, average_mix);
	COLOR = vec4(vec3(gray) * brightness, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
