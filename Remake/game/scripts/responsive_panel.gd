class_name ResponsivePanel
extends PanelContainer

signal action_requested(action_id: String)

@export var title_key := "UI_RETURN"
@export var description_key := ""
@export var action_ids: Array[String] = []
@export var action_keys: Array[String] = []
@export var minimum_panel_size := Vector2(360.0, 220.0)

var title_label: Label
var description_label: Label
var action_buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = minimum_panel_size
	if get_child_count() == 0:
		_build()
	apply_localization()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)
	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.visible = not description_key.is_empty()
	column.add_child(description_label)
	for index: int in range(action_ids.size()):
		var button := Button.new()
		button.name = "Action_%s" % action_ids[index]
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(action_requested.emit.bind(action_ids[index]))
		column.add_child(button)
		action_buttons.append(button)


func apply_localization() -> void:
	if title_label != null:
		title_label.text = tr(title_key)
	if description_label != null:
		description_label.text = tr(description_key) if not description_key.is_empty() else ""
	for index: int in range(action_buttons.size()):
		var key := action_keys[index] if index < action_keys.size() else "UI_RETURN"
		action_buttons[index].text = tr(key)
		action_buttons[index].tooltip_text = tr(key)


func _gui_input(event: InputEvent) -> void:
	# Explicitly consume panel pointer input so no click can issue a world move.
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		accept_event()
