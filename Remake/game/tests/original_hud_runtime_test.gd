extends SceneTree

const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const SMOOTH_CAMERA_PAN: Script = preload("res://scripts/smooth_camera_pan.gd")
const HUD_BASELINE_PATH := "res://data/original_hud_layout_baseline.json"
const OVERLAY_BASELINE_PATH := "res://data/original_overlay_asset_baseline.json"
const HUD_HEIGHT := 62.0
const PORTRAIT_NAMES: Array[String] = ["老赵", "铁蛋", "强子", "古明", "大牛"]
const PSD_TEXTURE_IDS: Array[int] = [
	1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070,
	1071, 1072, 1073, 1074,
	1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086,
	1087, 1088, 1089, 1090,
	1093,
	1094,
	1095,
	1097, 1098,
	1101, 1102, 1103, 1104, 1105, 1106,
	1107, 1108, 1109, 1110, 1112, 1113, 1114, 1115,
	1126, 1127, 1128,
	1125,
	1129,
	1138,
	1143, 1144,
	1154, 1155, 1156,
	1153,
	1160, 1161,
	1187, 1188, 1189,
	1186,
	1198, 1199, 1200,
	1197,
	1215, 1216, 1217,
	1214,
	1232, 1233,
	1254,
	1260, 1261,
]

var failures: Array[String] = []
var checks := 0
var baseline: Dictionary = {}
var overlay_baseline: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	baseline = _load_baseline()
	_expect(not baseline.is_empty(), "original HUD layout baseline loads")
	overlay_baseline = _load_json_baseline(OVERLAY_BASELINE_PATH)
	_expect(not overlay_baseline.is_empty(), "original overlay asset baseline loads")
	var fixture_root := ProjectSettings.globalize_path(
		"user://original-hud-runtime-test"
	).simplify_path()
	_expect(_write_fixture_assets(fixture_root), "synthetic HUD assets are available")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shell: GameShell = GAME_SHELL_SCRIPT.new()
	viewport.add_child(shell)
	await process_frame
	_expect(
		shell.configure_original_hud_assets(fixture_root),
		"synthetic original HUD asset set loads",
	)
	shell.update_original_hud([
		{"name": "老赵", "alive": true, "selected": true, "health_ratio": 1.0, "ammo_text": ""},
		{"name": "铁蛋", "alive": true, "selected": false, "health_ratio": 0.75, "ammo_text": ""},
		{"name": "强子", "alive": true, "selected": false, "health_ratio": 0.5, "ammo_text": "50"},
		{"name": "古明", "alive": true, "selected": false, "health_ratio": 0.25, "ammo_text": "30"},
		{"name": "大牛", "alive": false, "selected": false, "health_ratio": 0.0, "ammo_text": ""},
	])
	var weapon_texture := _fixture_texture(
		Vector2i(32, 40), Color(0.72, 0.58, 0.24, 1.0)
	)
	var weapon_states: Array[Dictionary] = []
	var hud_actor_names: Array = GAME_SHELL_SCRIPT.ORIGINAL_HUD_PORTRAITS.keys()
	for actor_index: int in range(hud_actor_names.size()):
		weapon_states.append({
			"name": str(hud_actor_names[actor_index]),
			"alive": actor_index != 4,
			"selected": actor_index == 0,
			"health_ratio": maxf(1.0 - float(actor_index) * 0.25, 0.0),
			"ammo_text": "50" if actor_index == 2 else "30" if actor_index == 3 else "",
			"weapon_name": "Rifle" if actor_index == 0 else "",
			"weapon_ammo_text": "12 / 40" if actor_index == 0 else "",
			"weapon_icon": weapon_texture if actor_index == 0 else null,
		})
	shell.update_original_hud(weapon_states)
	await process_frame
	await _check_layout(shell, Vector2i(1024, 768))
	await _check_overlay_layout(shell, Vector2i(1024, 768))
	viewport.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	await _check_layout(shell, Vector2i(1920, 1080))
	await _check_overlay_layout(shell, Vector2i(1920, 1080))
	_check_action_and_actor_signals(shell)
	_check_mode_state(shell)
	_check_health_bars(shell)

	viewport.remove_child(shell)
	shell.free()
	root.remove_child(viewport)
	viewport.free()
	await process_frame
	if failures.is_empty():
		print("Original HUD runtime tests passed (%d checks)." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _check_layout(shell: GameShell, viewport_size: Vector2i) -> void:
	var layout := shell.original_hud_layout_snapshot()
	var bar := layout.get("bar_rect", Rect2()) as Rect2
	var viewport_key := "%dx%d" % [viewport_size.x, viewport_size.y]
	var expected := (
		(baseline.get("viewports", {}) as Dictionary).get(viewport_key, {})
		as Dictionary
	)
	_expect(not expected.is_empty(), "%s HUD baseline exists" % viewport_key)
	var expected_bar := _rect_from_record(expected.get("bar_rect", {}) as Dictionary)
	_expect(bool(layout.get("assets_ready", false)), "HUD assets remain ready")
	_expect(bool(layout.get("visible", false)), "HUD remains visible")
	_expect(bool(layout.get("top_visible", false)), "top ammo HUD remains visible")
	_expect(
		int(layout.get("mouse_filter", Control.MOUSE_FILTER_IGNORE))
			== Control.MOUSE_FILTER_STOP
			and shell.gameplay_viewport_size(Vector2(viewport_size))
			== Vector2(float(viewport_size.x), float(viewport_size.y) - HUD_HEIGHT),
		"the HUD consumes pointer input and exposes the true gameplay edge",
	)
	var gameplay_size := shell.gameplay_viewport_size(Vector2(viewport_size))
	_expect(
		SMOOTH_CAMERA_PAN.edge_intent(
			Vector2(gameplay_size.x * 0.5, gameplay_size.y - 1.0),
			gameplay_size,
		).y > 0.0,
		"hovering just above the HUD produces downward vertical scrolling",
	)
	_expect(
		shell._original_hud_background.axis_stretch_horizontal
		== NinePatchRect.AXIS_STRETCH_MODE_TILE
		and shell._original_hud_border.axis_stretch_horizontal
		== NinePatchRect.AXIS_STRETCH_MODE_TILE,
		"modern widths tile the recovered stone centre instead of stretching it",
	)
	_expect(
		bar.position.is_equal_approx(expected_bar.position),
		"HUD starts exactly 62 pixels above the viewport bottom at %s; actual %s"
		% [viewport_size, bar],
	)
	_expect(
		bar.size.is_equal_approx(expected_bar.size),
		"HUD spans the full viewport width at %s; actual %s" % [viewport_size, bar],
	)
	var portraits := layout.get("portraits", {}) as Dictionary
	var visible_portraits := 0
	var portrait_right := 0.0
	for actor_name: String in PORTRAIT_NAMES:
		var portrait := portraits.get(actor_name, {}) as Dictionary
		if bool(portrait.get("visible", false)):
			visible_portraits += 1
			var rect := portrait.get("rect", Rect2()) as Rect2
			portrait_right = maxf(portrait_right, rect.end.x)
			_expect(
				rect.size.is_equal_approx(Vector2(50.0, 50.0)),
				"%s portrait keeps the original contiguous 50x50 slot" % actor_name,
			)
			_expect(
				not str(portrait.get("tooltip", "")).is_empty()
					and int(portrait.get("mouse_filter", Control.MOUSE_FILTER_IGNORE))
						== Control.MOUSE_FILTER_STOP,
				"%s portrait is a self-contained hinted button" % actor_name,
			)
	_expect(visible_portraits == 5, "all five supplied actor portraits are visible")
	var status_cells := layout.get("status_cells", {}) as Dictionary
	var visible_status_cells := 0
	for actor_name: String in PORTRAIT_NAMES:
		var status := status_cells.get(actor_name, {}) as Dictionary
		if bool(status.get("visible", false)):
			visible_status_cells += 1
			_expect(
				(status.get("rect", Rect2()) as Rect2).size
				== Vector2(50.0, 20.0),
				"%s ammo cell keeps the original 50x20 size" % actor_name,
			)
	_expect(visible_status_cells == 5, "all five supplied ammo cells are visible")
	var first_status := status_cells[PORTRAIT_NAMES[0]] as Dictionary
	_expect(
		(first_status.get("rect", Rect2()) as Rect2).is_equal_approx(
			_rect_from_record(expected.get("first_status_rect", {}) as Dictionary)
		),
		"first ammo cell matches the %s pixel baseline" % viewport_key,
	)
	_expect(
		str((status_cells[PORTRAIT_NAMES[2]] as Dictionary).get("ammo_text", "")) == "50"
		and str((status_cells[PORTRAIT_NAMES[3]] as Dictionary).get("ammo_text", "")) == "30",
		"top ammo cells expose original quantity text",
	)
	var first_portrait := portraits[PORTRAIT_NAMES[0]] as Dictionary
	_expect(
		(first_portrait.get("rect", Rect2()) as Rect2).is_equal_approx(
			_rect_from_record(expected.get("first_portrait_rect", {}) as Dictionary)
		),
		"first portrait matches the %s pixel baseline" % viewport_key,
	)
	var actions := layout.get("actions", {}) as Dictionary
	_expect(actions.size() == 3, "HUD exposes exactly three original action buttons")
	var action_left := float(viewport_size.x)
	var action_right := 0.0
	for action: String in ["observation", "minimap", "system"]:
		var action_state := actions.get(action, {}) as Dictionary
		var rect := action_state.get("rect", Rect2()) as Rect2
		_expect(
			rect.size.is_equal_approx(Vector2(50.0, 50.0)),
			"%s keeps the original 50x50 hit target" % action,
		)
		_expect(
			not str(action_state.get("tooltip", "")).is_empty()
				and int(action_state.get("mouse_filter", Control.MOUSE_FILTER_IGNORE))
					== Control.MOUSE_FILTER_STOP,
			"%s provides a tooltip and owns its click" % action,
		)
		var expected_action := _rect_from_record(
			((expected.get("action_rects", {}) as Dictionary).get(action, {}) as Dictionary)
		)
		_expect(
			rect.is_equal_approx(expected_action),
			"%s matches the %s pixel baseline" % [action, viewport_key],
		)
		action_left = minf(action_left, rect.position.x)
		action_right = maxf(action_right, rect.end.x)
	_expect(
		is_equal_approx(action_right, float(viewport_size.x) - 10.0),
		"right action cluster keeps the recovered ten-pixel inset; right %.1f / %d"
		% [action_right, viewport_size.x],
	)
	_expect(
		portrait_right < action_left,
		"portrait and action clusters never overlap",
	)
	var weapon := layout.get("weapon", {}) as Dictionary
	var weapon_rect := weapon.get("rect", Rect2()) as Rect2
	_expect(
		bool(weapon.get("visible", false))
			and bool(weapon.get("has_icon", false))
			and str(weapon.get("name", "")) == "Rifle"
			and str(weapon.get("ammo_text", "")) == "12 / 40",
		"bottom HUD exposes the selected actor's current weapon and ammunition",
	)
	_expect(
		weapon_rect.position.x >= portrait_right
			and weapon_rect.end.x <= action_left,
		"weapon panel stays between portrait and action clusters",
	)
	_expect(
		is_equal_approx(weapon_rect.end.x, action_left - 10.0)
			and not str(weapon.get("tooltip", "")).is_empty()
			and int(weapon.get("mouse_filter", Control.MOUSE_FILTER_IGNORE))
				== Control.MOUSE_FILTER_STOP,
		"weapon control sits beside the right actions, is hinted, and owns its click",
	)
	await process_frame


func _load_baseline() -> Dictionary:
	return _load_json_baseline(HUD_BASELINE_PATH)


func _load_json_baseline(path: String) -> Dictionary:
	var source := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(source)
	if parsed is Dictionary and int((parsed as Dictionary).get("schema_version", 0)) == 1:
		return parsed as Dictionary
	return {}


func _check_overlay_layout(shell: GameShell, viewport_size: Vector2i) -> void:
	var slot_texture := _fixture_texture(Vector2i(50, 50), Color(0.55, 0.3, 0.1, 1.0))
	var slots: Array[Dictionary] = []
	for index: int in range(7):
		slots.append({
			"kind": "fixture",
			"label": "格%d" % index,
			"quantity": index + 1,
			"enabled": true,
			"active": index == 0,
			"icon": slot_texture,
			"icon_selected": slot_texture,
		})
	shell.show_inventory({
		"actor_name": "强子",
		"groups": [{"title": "物品", "mode": "items", "slots": slots}],
	}, "items")
	paused = false
	await process_frame
	await process_frame
	var layout := shell.original_overlay_layout_snapshot()
	var inventory_rect := layout.get("inventory_rect", Rect2()) as Rect2
	_expect(
		bool(layout.get("assets_ready", false)),
		"original overlay background assets remain ready",
	)
	_expect(
		inventory_rect == Rect2(
			float(viewport_size.x - 276),
			float(viewport_size.y - 483),
			276.0,
			421.0,
		),
		"inventory stays bottom-right at %s" % viewport_size,
	)
	var inventory_layout := layout.get("inventory_layout", {}) as Dictionary
	var rendered_slots := inventory_layout.get("slots", []) as Array
	_expect(rendered_slots.size() == 7, "inventory retains every fixture slot")
	_expect(
		rendered_slots.all(func(slot: Dictionary) -> bool: return not bool(slot.get("focused", false))),
		"opening the original inventory does not invent a focused first slot",
	)
	if rendered_slots.size() == 7:
		_expect(
			((rendered_slots[0] as Dictionary).get("rect", Rect2()) as Rect2)
			== Rect2(13.0, 40.0, 50.0, 74.0),
			"inventory first cell matches the original hit-test origin",
		)
		_expect(
			((rendered_slots[5] as Dictionary).get("rect", Rect2()) as Rect2)
			== Rect2(13.0, 124.0, 50.0, 74.0),
			"inventory sixth cell starts the second 84-pixel row",
		)
	var first_button := shell._inventory_view.first_slot_button()
	var quantity_label := (
		first_button.get_node_or_null("OriginalQuantityFrame/OriginalQuantity") as Label
		if first_button != null
		else null
	)
	_expect(
		quantity_label != null and quantity_label.text == "X1",
		"inventory quantity retains the original compact Xn spelling",
	)
	shell.close_for_state_change()

	for raw_map: Variant in overlay_baseline.get("minimaps", []) as Array:
		var map_record := raw_map as Dictionary
		var map_size := Vector2i(
			int(map_record.get("width", 0)),
			int(map_record.get("height", 0)),
		)
		var map_texture := _fixture_texture(map_size, Color(0.25, 0.32, 0.22, 1.0))
		shell.show_tactical_map(
			map_texture,
			Vector2(float(map_size.x * 16), float(map_size.y * 16)),
			[],
			[],
			Rect2(),
		)
		await process_frame
		layout = shell.original_overlay_layout_snapshot()
		_expect(
			(layout.get("map_rect", Rect2()) as Rect2) == Rect2(
				float(viewport_size.x - map_size.x),
				float(viewport_size.y - 62 - map_size.y),
				float(map_size.x),
				float(map_size.y),
			),
			"%s minimap keeps native size at %s"
			% [str(map_record.get("level_id", "")), viewport_size],
		)
		shell.hide_tactical_map()

	var help_texture := _fixture_texture(Vector2i(640, 480), Color(0.02, 0.02, 0.02, 1.0))
	shell.show_control_guide(help_texture)
	paused = false
	await process_frame
	layout = shell.original_overlay_layout_snapshot()
	_expect(
		(layout.get("help_rect", Rect2()) as Rect2) == Rect2(
			(float(viewport_size.x) - 640.0) * 0.5,
			(float(viewport_size.y) - 480.0) * 0.5,
			640.0,
			480.0,
		),
		"F1 guide remains centered at native 640x480 in %s" % viewport_size,
	)
	_expect(
		(layout.get("backdrop_color", Color.TRANSPARENT) as Color).is_equal_approx(
			Color.BLACK
		),
		"F1 guide reproduces the original opaque black primary-surface backdrop",
	)
	shell.close_for_state_change()

	shell.show_pause_menu(false)
	paused = false
	await process_frame
	await process_frame
	layout = shell.original_overlay_layout_snapshot()
	var pause_origin := Vector2(
		float(viewport_size.x) * 0.5 - 305.0,
		float(viewport_size.y) * 0.5 - 118.0,
	)
	_expect(
		(layout.get("pause_menu_rect", Rect2()) as Rect2)
		== Rect2(pause_origin, Vector2(132.0, 318.0)),
		"original pause menu retains its recovered center-relative geometry at %s"
		% viewport_size,
	)
	var pause_buttons := layout.get("pause_buttons", {}) as Dictionary
	var ordered_button_ids: Array[String] = [
		"resume", "restart", "missions", "save",
		"load", "settings", "credits", "quit",
	]
	_expect(
		pause_buttons.size() == ordered_button_ids.size(),
		"pause menu exposes exactly the eight original entries",
	)
	for row: int in range(ordered_button_ids.size()):
		var button_id := ordered_button_ids[row]
		var button_record := pause_buttons.get(button_id, {}) as Dictionary
		var button_rect := button_record.get("rect", Rect2()) as Rect2
		var texture_size := button_record.get("texture_size", Vector2.ZERO) as Vector2
		_expect(
			button_rect.position == pause_origin + Vector2(0.0, float(row) * 40.0),
			"pause entry %s retains the recovered 40-pixel row pitch" % button_id,
		)
		_expect(
			button_rect.size == texture_size
			and texture_size == Vector2(132.0, 38.0),
			"pause entry %s composites the original 132x38 stone frame" % button_id,
		)
	_expect(
		bool(layout.get("desaturate_visible", false))
		and is_equal_approx(float(layout.get("desaturate_brightness", 0.0)), 1.0)
		and is_equal_approx(float(layout.get("desaturate_average_mix", 0.0)), 1.0)
		and not bool(layout.get("dim_visible", true)),
		"pause reproduces the original equal-RGB grayscale surface without dimming",
	)

	shell._show_credits()
	paused = false
	await process_frame
	layout = shell.original_overlay_layout_snapshot()
	_expect(
		(layout.get("credits_rect", Rect2()) as Rect2) == Rect2(
			(float(viewport_size.x) - 640.0) * 0.5,
			(float(viewport_size.y) - 480.0) * 0.5,
			640.0,
			480.0,
		),
		"original credits remain centered at native 640x480 in %s" % viewport_size,
	)
	_expect(
		(layout.get("credits_texture_size", Vector2.ZERO) as Vector2)
		== Vector2(640.0, 480.0),
		"credits use the original PSD 1254 composite",
	)
	_expect(
		(layout.get("backdrop_color", Color.TRANSPARENT) as Color).is_equal_approx(
			Color.BLACK
		),
		"credits use the original black outer surface",
	)
	_expect(shell.close_active_overlay(), "credits return to the owning pause menu")
	shell.close_for_state_change()

	shell.show_failure("必要队员牺牲", false)
	paused = false
	await process_frame
	layout = shell.original_overlay_layout_snapshot()
	var viewport_center := Vector2(viewport_size) * 0.5
	_expect(
		(layout.get("failure_title_rect", Rect2()) as Rect2)
		== Rect2(
			viewport_center + Vector2(-99.0, -59.0),
			Vector2(172.0, 50.0),
		),
		"failure title retains its recovered center-relative geometry at %s"
		% viewport_size,
	)
	_expect(
		(layout.get("failure_title_texture_size", Vector2.ZERO) as Vector2)
		== Vector2(172.0, 50.0),
		"failure title uses original PSD 1093",
	)
	var failure_buttons := layout.get("failure_buttons", {}) as Dictionary
	var restart_record := failure_buttons.get("restart", {}) as Dictionary
	var main_record := failure_buttons.get("main", {}) as Dictionary
	_expect(
		(restart_record.get("rect", Rect2()) as Rect2)
		== Rect2(
			viewport_center + Vector2(-158.0, -3.0),
			Vector2(132.0, 38.0),
		)
		and (restart_record.get("texture_size", Vector2.ZERO) as Vector2)
		== Vector2(132.0, 38.0),
		"failure restart composites PSD 1095 with PSD 1260 at the recovered position",
	)
	_expect(
		(main_record.get("rect", Rect2()) as Rect2)
		== Rect2(
			viewport_center + Vector2(-8.0, -3.0),
			Vector2(132.0, 38.0),
		)
		and (main_record.get("texture_size", Vector2.ZERO) as Vector2)
		== Vector2(132.0, 38.0),
		"failure main button retains the recovered horizontal layout",
	)
	_expect(
		bool(layout.get("desaturate_visible", false))
		and is_equal_approx(float(layout.get("desaturate_brightness", 0.0)), 1.0)
		and is_equal_approx(float(layout.get("desaturate_average_mix", 0.0)), 1.0)
		and not bool(layout.get("dim_visible", true)),
		"failure reproduces the original equal-RGB grayscale surface without dimming",
	)
	shell.close_for_state_change()

	var level_entries: Array[Dictionary] = []
	for level_index: int in range(12):
		level_entries.append({
			"id": "m%03d" % level_index,
			"number": level_index + 1,
			"title": "Fixture mission %02d" % (level_index + 1),
			"unlocked": true,
		})
	shell.set_level_selection(level_entries, {
		"highest_unlocked_level_id": "m011",
		"completed_level_ids": ["m000", "m001"],
	}, "m001")
	shell.show_level_selector(true)
	paused = false
	await process_frame
	await process_frame
	layout = shell.original_overlay_layout_snapshot()
	_expect(
		(layout.get("level_selector_panel_rect", Rect2()) as Rect2)
		== Rect2(
			(Vector2(viewport_size) - Vector2(820.0, 600.0)) * 0.5,
			Vector2(820.0, 600.0),
		),
		"free selector keeps its centered 820x600 product surface at %s"
		% viewport_size,
	)
	var selector_layout := layout.get("level_selector_layout", {}) as Dictionary
	var selector_buttons := selector_layout.get("buttons", {}) as Dictionary
	_expect(
		bool(selector_layout.get("assets_ready", false))
		and int(selector_layout.get("grid_columns", 0)) == 3
		and selector_buttons.size() == 12,
		"free selector maps exactly twelve formal missions into a three-column grid",
	)
	for level_index: int in range(12):
		var level_id := "m%03d" % level_index
		var button_record := selector_buttons.get(level_id, {}) as Dictionary
		var button_rect := button_record.get("rect", Rect2()) as Rect2
		_expect(
			bool(button_record.get("enabled", false))
			and bool(button_record.get("uses_original_asset", false))
			and (button_record.get("icon_size", Vector2.ZERO) as Vector2)
			== Vector2(114.0, 33.0)
			and button_rect.size.x >= 245.0
			and button_rect.size.y >= 82.0,
			"%s uses its original normal/bright mission label within a usable hit target"
			% level_id,
		)
	shell.close_for_state_change()


func _fixture_texture(dimensions: Vector2i, color: Color) -> Texture2D:
	var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _rect_from_record(record: Dictionary) -> Rect2:
	return Rect2(
		float(record.get("x", 0.0)),
		float(record.get("y", 0.0)),
		float(record.get("width", 0.0)),
		float(record.get("height", 0.0)),
	)


func _check_action_and_actor_signals(shell: GameShell) -> void:
	var actions: Array[String] = []
	var actors: Array[String] = []
	var weapon_cycles: Array[int] = []
	shell.original_hud_action_requested.connect(
		func(action: String) -> void: actions.append(action)
	)
	shell.original_hud_actor_requested.connect(
		func(actor_name: String) -> void: actors.append(actor_name)
	)
	shell.inventory_cycle_requested.connect(
		func(direction: int) -> void: weapon_cycles.append(direction)
	)
	for action: String in ["observation", "minimap", "system"]:
		(shell._original_hud_action_buttons[action] as TextureButton).pressed.emit()
	(
		(shell._original_hud_portrait_controls["老赵"] as Dictionary)["button"]
		as TextureButton
	).pressed.emit()
	var weapon_click := InputEventMouseButton.new()
	weapon_click.button_index = MOUSE_BUTTON_LEFT
	weapon_click.pressed = true
	shell._original_hud_weapon_panel.gui_input.emit(weapon_click)
	_expect(
		actions == ["observation", "minimap", "system"],
		"every bottom action button emits its scoped gameplay action",
	)
	_expect(actors == ["老赵"], "portrait button emits only its actor selection")
	_expect(
		weapon_cycles == [1],
		"weapon panel click cycles the selected actor weapon once",
	)
	_expect(
		Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"HUD interaction never captures or confines the system pointer",
	)


func _check_mode_state(shell: GameShell) -> void:
	shell.set_original_hud_action_state("minimap", true)
	var layout := shell.original_hud_layout_snapshot()
	_expect(
		bool((layout["actions"]["minimap"] as Dictionary)["pressed"]),
		"map button mirrors an externally opened minimap",
	)
	shell.set_original_hud_action_state("minimap", false)
	layout = shell.original_hud_layout_snapshot()
	_expect(
		not bool((layout["actions"]["minimap"] as Dictionary)["pressed"]),
		"map button clears when the minimap closes",
	)


func _check_health_bars(shell: GameShell) -> void:
	var expected_heights := {
		"老赵": 32.0,
		"铁蛋": 24.0,
		"强子": 16.0,
		"古明": 8.0,
		"大牛": 0.0,
	}
	for actor_name: String in expected_heights:
		var controls := shell._original_hud_portrait_controls[actor_name] as Dictionary
		var back := controls["health_back"] as ColorRect
		var fill := controls["health_fill"] as ColorRect
		_expect(
			back.position == Vector2(42.0, 13.0)
			and back.size == Vector2(5.0, 34.0)
			and back.color == Color.BLACK,
			"%s health bar keeps the recovered 5x34 in-portrait black frame"
			% actor_name,
		)
		_expect(
			is_equal_approx(fill.position.x, 43.0)
			and is_equal_approx(fill.size.x, 3.0)
			and is_equal_approx(fill.position.y + fill.size.y, 46.0),
			"%s health fill stays inside the recovered 3x32 interior" % actor_name,
		)
		_expect(
			is_equal_approx(fill.size.y, float(expected_heights[actor_name])),
			"%s health bar reflects its exact health ratio" % actor_name,
		)


func _write_fixture_assets(fixture_root: String) -> bool:
	var iblock_root := fixture_root.path_join("iblock")
	var psd_root := fixture_root.path_join("psd")
	if DirAccess.make_dir_recursive_absolute(iblock_root) != OK:
		return false
	if DirAccess.make_dir_recursive_absolute(psd_root) != OK:
		return false
	if not _save_fixture_png(
		iblock_root.path_join("1137.png"),
		1024,
		62,
		Color(0.12, 0.15, 0.11, 1.0),
	):
		return false
	for index: int in [1139, 1140]:
		if not _save_fixture_png(
			iblock_root.path_join("%04d.png" % index),
			27,
			64,
			Color(0.2, 0.22, 0.18, 1.0),
		):
			return false
	for index: int in PSD_TEXTURE_IDS:
		var fixture_size := _fixture_psd_size(index)
		if not _save_fixture_png(
			psd_root.path_join("%04d.png" % index),
			fixture_size.x,
			fixture_size.y,
			Color(0.25, 0.28, 0.21, 1.0),
		):
			return false
	return true


func _fixture_psd_size(index: int) -> Vector2i:
	match index:
		1125, 1153, 1186, 1197, 1214:
			return Vector2i(50, 20)
		1063, 1064:
			return Vector2i(106, 25)
		1065, 1066:
			return Vector2i(50, 25)
		1067, 1068:
			return Vector2i(108, 25)
		1069, 1070:
			return Vector2i(108, 25)
		1071, 1072:
			return Vector2i(107, 26)
		1073, 1074:
			return Vector2i(53, 25)
		1079, 1080:
			return Vector2i(106, 26)
		1081, 1082:
			return Vector2i(107, 26)
		1083, 1084:
			return Vector2i(79, 26)
		1085, 1086:
			return Vector2i(51, 25)
		1087, 1088:
			return Vector2i(107, 25)
		1089, 1090:
			return Vector2i(106, 25)
		1093:
			return Vector2i(172, 50)
		1094:
			return Vector2i(114, 33)
		1095:
			return Vector2i(132, 38)
		1097, 1098, 1109, 1110, 1114, 1115:
			return Vector2i(120, 28)
		1101, 1102:
			return Vector2i(120, 29)
		1103, 1104, 1112, 1113:
			return Vector2i(119, 29 if index in [1103, 1104] else 28)
		1105, 1106, 1107, 1108:
			return Vector2i(120, 27)
		1129:
			return Vector2i(276, 421)
		1138:
			return Vector2i(1024, 62)
		1254:
			return Vector2i(640, 480)
		1260, 1261:
			return Vector2i(103, 25)
		_:
			return Vector2i(50, 50)


func _save_fixture_png(
	path: String,
	width: int,
	height: int,
	color: Color,
) -> bool:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image.save_png(path) == OK


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
