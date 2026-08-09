class_name TacticalPlanningPanel
extends CanvasLayer

signal execute_requested
signal undo_requested
signal clear_requested
signal clear_selected_requested
signal wait_requested(ticks: int)

const OVERLAY_SCRIPT := preload("res://scripts/tactical_plan_overlay.gd")

var _overlay: TacticalPlanOverlay
var _root: Control
var _summary: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_overlay = OVERLAY_SCRIPT.new()
	add_child(_overlay)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0.17, 0.21, 0.22, 0.10)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -480.0
	panel.offset_top = 18.0
	panel.offset_right = -18.0
	panel.offset_bottom = 78.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_summary)
	_add_button(row, tr("UI_TACTICAL_WAIT"), wait_requested.emit.bind(60))
	_add_button(row, tr("UI_TACTICAL_UNDO"), undo_requested.emit)
	_add_button(row, tr("UI_TACTICAL_CLEAR_SELECTED"), clear_selected_requested.emit)
	_add_button(row, tr("UI_TACTICAL_CLEAR"), clear_requested.emit)
	_add_button(row, tr("UI_TACTICAL_EXECUTE"), execute_requested.emit)
	hide_panel()


func show_plan(snapshot: Dictionary, visuals: Array[Dictionary]) -> void:
	visible = true
	_root.visible = true
	_overlay.visible = true
	_overlay.set_entries(visuals)
	_summary.text = tr("UI_TACTICAL_PLAN_COUNT") % int(snapshot.get("planned_count", 0))


func hide_panel() -> void:
	visible = false
	if _root != null:
		_root.visible = false
	if _overlay != null:
		_overlay.visible = false


func blocks_screen_point(screen_position: Vector2) -> bool:
	if not visible or _root == null:
		return false
	for child: Node in _root.get_children():
		if (
			child is Control
			and (child as Control).visible
			and (child as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE
			and (child as Control).get_global_rect().has_point(screen_position)
		):
			return true
	return false


func _add_button(parent: Control, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	parent.add_child(button)
