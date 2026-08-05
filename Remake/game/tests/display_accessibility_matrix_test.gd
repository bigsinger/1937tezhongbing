extends SceneTree

const GAME_SHELL: Script = preload("res://scripts/game_shell.gd")

const DISPLAY_MATRIX: Array[Dictionary] = [
	{"name": "16:10-100", "size": Vector2i(1280, 800), "ui_scale": 1.0},
	{"name": "16:9-125", "size": Vector2i(1920, 1080), "ui_scale": 1.25},
	{"name": "21:9-150", "size": Vector2i(2560, 1080), "ui_scale": 1.50},
	{"name": "4k-200", "size": Vector2i(3840, 2160), "ui_scale": 2.0},
	{"name": "minimum", "size": Vector2i(1024, 768), "ui_scale": 2.0},
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size := root.size
	for descriptor: Dictionary in DISPLAY_MATRIX:
		await _test_layout(descriptor)
	root.size = original_size
	if failures.is_empty():
		print("Display/accessibility matrix passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_layout(descriptor: Dictionary) -> void:
	var viewport_size := descriptor["size"] as Vector2i
	root.size = viewport_size
	var shell = GAME_SHELL.new()
	root.add_child(shell)
	await process_frame
	shell.set_settings({
		"ui_scale": float(descriptor["ui_scale"]),
		"text_scale": float(descriptor["ui_scale"]),
		"high_contrast": true,
		"large_cursor": true,
		"colorblind_patterns": true,
		"display_mode": "windowed",
		"window_width": viewport_size.x,
		"window_height": viewport_size.y,
	})
	shell.apply_visual_preferences(shell.settings_snapshot())
	await process_frame
	var snapshot: Dictionary = shell.visual_layout_snapshot()
	var panels := snapshot["panels"] as Dictionary
	for panel_name: Variant in panels.keys():
		var panel := panels[panel_name] as Dictionary
		var rect := panel["rect"] as Rect2
		_expect(
			rect.size.x <= float(viewport_size.x) + 1.0
				and rect.size.y <= float(viewport_size.y) + 1.0,
			"%s %s remains inside the safe viewport size" % [
				str(descriptor["name"]), str(panel_name),
			],
		)
	_expect(
		bool(shell.settings_snapshot().get("high_contrast", false))
			and bool(shell.settings_snapshot().get("colorblind_patterns", false)),
		"%s retains non-color-only high-contrast preferences" % str(descriptor["name"]),
	)
	shell._show_game_settings()
	await process_frame
	shell._language_option.grab_focus()
	_expect(
		root.gui_get_focus_owner() == shell._language_option,
		"%s settings are reachable through keyboard focus" % str(descriptor["name"]),
	)
	shell.close_for_state_change()
	root.remove_child(shell)
	shell.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
