extends SceneTree

const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const HUD_BASELINE_PATH := "res://data/original_hud_layout_baseline.json"
const OVERLAY_BASELINE_PATH := "res://data/original_overlay_asset_baseline.json"
const HUD_HEIGHT := 62.0
const PORTRAIT_NAMES: Array[String] = ["老赵", "铁蛋", "强子", "古明", "大牛"]
const PSD_TEXTURE_IDS: Array[int] = [
	1126, 1127, 1128,
	1129,
	1138,
	1143, 1144,
	1154, 1155, 1156,
	1160, 1161,
	1187, 1188, 1189,
	1198, 1199, 1200,
	1215, 1216, 1217,
	1232, 1233,
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
		{"name": "老赵", "alive": true, "selected": true, "health_ratio": 1.0},
		{"name": "铁蛋", "alive": true, "selected": false, "health_ratio": 0.75},
		{"name": "强子", "alive": true, "selected": false, "health_ratio": 0.5},
		{"name": "古明", "alive": true, "selected": false, "health_ratio": 0.25},
		{"name": "大牛", "alive": false, "selected": false, "health_ratio": 0.0},
	])
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
				is_equal_approx(rect.size.y, 50.0),
				"%s portrait keeps the original 50-pixel height" % actor_name,
			)
	_expect(visible_portraits == 5, "all five supplied actor portraits are visible")
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
		action_right <= float(viewport_size.x) and action_right >= float(viewport_size.x) - 8.0,
		"right action cluster remains anchored to the viewport edge; right %.1f / %d"
		% [action_right, viewport_size.x],
	)
	_expect(
		portrait_right < action_left,
		"portrait and action clusters never overlap",
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
	shell.original_hud_action_requested.connect(
		func(action: String) -> void: actions.append(action)
	)
	shell.original_hud_actor_requested.connect(
		func(actor_name: String) -> void: actors.append(actor_name)
	)
	(shell._original_hud_action_buttons["system"] as TextureButton).pressed.emit()
	(
		(shell._original_hud_portrait_controls["老赵"] as Dictionary)["button"]
		as TextureButton
	).pressed.emit()
	_expect(actions == ["system"], "system button emits only its scoped HUD action")
	_expect(actors == ["老赵"], "portrait button emits only its actor selection")
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
		"老赵": 50.0,
		"铁蛋": 37.5,
		"强子": 25.0,
		"古明": 12.5,
		"大牛": 0.0,
	}
	for actor_name: String in expected_heights:
		var controls := shell._original_hud_portrait_controls[actor_name] as Dictionary
		var fill := controls["health_fill"] as ColorRect
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
		var width := 1024 if index == 1138 else 276 if index == 1129 else 50
		var height := 62 if index == 1138 else 421 if index == 1129 else 50
		if not _save_fixture_png(
			psd_root.path_join("%04d.png" % index),
			width,
			height,
			Color(0.25, 0.28, 0.21, 1.0),
		):
			return false
	return true


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
