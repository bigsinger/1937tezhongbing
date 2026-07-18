class_name InventoryGridView
extends VBoxContainer

signal slot_activated(slot: Dictionary)

const COLUMN_COUNT := 5
const CELL_SIZE := Vector2(50.0, 74.0)
const ROW_GAP := 10
const ORIGINAL_ROW_PITCH := int(CELL_SIZE.y) + ROW_GAP

var mode := "items"
var model: Dictionary = {}
var _heading: Label
var _mode_hint: Label
var _groups: VBoxContainer
var _slot_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_heading = Label.new()
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 23)
	_heading.add_theme_color_override("font_color", Color(0.96, 0.88, 0.63))
	add_child(_heading)
	_mode_hint = Label.new()
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.add_theme_font_size_override("font_size", 14)
	_mode_hint.add_theme_color_override("font_color", Color(0.75, 0.79, 0.68))
	add_child(_mode_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(254.0, 292.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_groups = VBoxContainer.new()
	_groups.custom_minimum_size.x = 254.0
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups.add_theme_constant_override("separation", 4)
	scroll.add_child(_groups)
	_rebuild()


func configure(new_model: Dictionary, new_mode: String = "items") -> void:
	model = new_model.duplicate(true)
	mode = new_mode if new_mode in ["weapons", "items"] else "items"
	if is_node_ready():
		_rebuild()


func visible_slot_count() -> int:
	var count := 0
	for raw_group: Variant in model.get("groups", []):
		if not raw_group is Dictionary:
			continue
		var group := raw_group as Dictionary
		if not _group_is_visible(group):
			continue
		for raw_slot: Variant in group.get("slots", []):
			if raw_slot is Dictionary:
				count += 1
	return count


func focus_first_slot() -> bool:
	for button: Button in _slot_buttons:
		if is_instance_valid(button) and button.visible and not button.disabled:
			button.grab_focus()
			return true
	return false


func first_slot_button() -> Button:
	for button: Button in _slot_buttons:
		if is_instance_valid(button):
			return button
	return null


func _rebuild() -> void:
	if _groups == null:
		return
	_slot_buttons.clear()
	for child: Node in _groups.get_children():
		child.queue_free()
	var actor_name := str(model.get("actor_name", "当前队员"))
	_heading.text = "%s · %s" % [actor_name, "武器" if mode == "weapons" else "物品"]
	_mode_hint.text = (
		"点击方格装备武器；数字键 1–0 对应原版武器"
		if mode == "weapons"
		else "点击方格使用或装备物品；数量显示在格内"
	)
	var visible_groups := 0
	for raw_group: Variant in model.get("groups", []):
		if not raw_group is Dictionary:
			continue
		var group := raw_group as Dictionary
		if not _group_is_visible(group):
			continue
		visible_groups += 1
		_add_group(group)
	if visible_groups == 0:
		var empty := Label.new()
		empty.text = "（该栏目前为空）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 80.0
		_groups.add_child(empty)


func _group_is_visible(group: Dictionary) -> bool:
	var group_mode := str(group.get("mode", "items"))
	return group_mode == mode or group_mode == "both"


func _add_group(group: Dictionary) -> void:
	var band := Label.new()
	band.text = "  %s" % str(group.get("title", "物品"))
	band.custom_minimum_size.y = 24.0
	band.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_theme_font_size_override("font_size", 15)
	band.add_theme_color_override("font_color", Color(0.93, 0.85, 0.61))
	band.add_theme_stylebox_override("normal", _band_style())
	_groups.add_child(band)

	var grid := GridContainer.new()
	grid.columns = COLUMN_COUNT
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", ROW_GAP)
	_groups.add_child(grid)
	var slots: Array = group.get("slots", []) as Array
	for raw_slot: Variant in slots:
		if raw_slot is Dictionary:
			grid.add_child(_make_slot(raw_slot as Dictionary))
	# Preserve the five-column silhouette of the original popup even for a
	# partially populated group.
	var fillers := (COLUMN_COUNT - (slots.size() % COLUMN_COUNT)) % COLUMN_COUNT
	for unused_index in range(fillers):
		var filler := Panel.new()
		filler.custom_minimum_size = CELL_SIZE
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		filler.add_theme_stylebox_override("panel", _cell_style(false, true))
		grid.add_child(filler)


func _make_slot(slot: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	button.disabled = not bool(slot.get("enabled", true))
	button.tooltip_text = str(slot.get("description", slot.get("label", "")))
	var label := str(slot.get("short_label", slot.get("label", "")))
	var quantity := int(slot.get("quantity", 0))
	button.text = label + ("\n×%d" % quantity if quantity > 0 else "")
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override(
		"normal", _cell_style(bool(slot.get("active", false)), false)
	)
	button.add_theme_stylebox_override("hover", _cell_style(true, false))
	button.add_theme_stylebox_override("pressed", _cell_style(true, false))
	var icon_value: Variant = slot.get("icon")
	if icon_value is Texture2D:
		button.icon = icon_value as Texture2D
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 32)
	button.pressed.connect(func() -> void: slot_activated.emit(slot.duplicate(true)))
	_slot_buttons.append(button)
	return button


func _cell_style(active: bool, empty: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.34, 0.31, 0.19, 0.96)
		if active
		else Color(0.105, 0.115, 0.09, 0.86 if not empty else 0.48)
	)
	style.border_color = Color(0.90, 0.73, 0.34, 0.92) if active else Color(0.42, 0.44, 0.35, 0.82)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _band_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.16, 0.115, 0.96)
	style.border_color = Color(0.39, 0.40, 0.30, 0.85)
	style.border_width_bottom = 1
	return style
