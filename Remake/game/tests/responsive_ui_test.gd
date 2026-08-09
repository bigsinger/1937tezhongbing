extends SceneTree

const SAFE_AREA := preload("res://scripts/ui_safe_area_service.gd")
const PANEL_SCENES: Array[PackedScene] = [
	preload("res://scenes/game_hud.tscn"),
	preload("res://scenes/pause_menu.tscn"),
	preload("res://scenes/failure_menu.tscn"),
	preload("res://scenes/settings_menu.tscn"),
	preload("res://scenes/save_slot_menu.tscn"),
	preload("res://scenes/inventory_panel.tscn"),
	preload("res://scenes/tactical_map_panel.tscn"),
	preload("res://scenes/tactical_planning_panel.tscn"),
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene: PackedScene in PANEL_SCENES:
		var panel := scene.instantiate()
		root.add_child(panel)
		_expect(panel.get_script() != null, "%s is independently instantiable" % panel.name)
		if panel is Control:
			_expect(
				(panel as Control).mouse_filter == Control.MOUSE_FILTER_STOP,
				"%s intercepts pointer input" % panel.name,
			)
		panel.queue_free()
	var safe_area = SAFE_AREA.new()
	for resolution: Vector2 in [
		Vector2(1024, 768), Vector2(1280, 800), Vector2(1920, 1080),
		Vector2(2560, 1080), Vector2(3840, 2160),
	]:
		var rect := safe_area.safe_rect(resolution, 1.0) as Rect2
		_expect(
			rect.position.x >= 0.0 and rect.position.y >= 0.0
				and rect.end.x <= resolution.x and rect.end.y <= resolution.y
				and rect.size.x > 0.0 and rect.size.y > 0.0,
			"safe area remains inside %dx%d" % [int(resolution.x), int(resolution.y)],
		)
	if failures.is_empty():
		print("Responsive UI tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
