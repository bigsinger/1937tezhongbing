class_name InventoryGridView
extends Control

signal slot_activated(slot: Dictionary)

# Recovered from the original popup hit test used by sub_45ACE0 callers:
#   x = screen_width - 276 + 13 + 50 * column
#   y = screen_height - 62 - 421 + 40 + 84 * row
# The visible icon is 50x50; the remaining 24 pixels hold the quantity.
const COLUMN_COUNT := 5
const CELL_SIZE := Vector2(50.0, 74.0)
const GRID_ORIGIN := Vector2(13.0, 40.0)
const ROW_GAP := 10
const ORIGINAL_ROW_PITCH := int(CELL_SIZE.y) + ROW_GAP

var mode := "items"
var model: Dictionary = {}
var _groups: GridContainer
var _slot_buttons: Array[Button] = []
var _slot_visuals: Dictionary = {}
var _empty_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(276.0, 421.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_groups = GridContainer.new()
	_groups.name = "OriginalInventoryGrid"
	_groups.position = GRID_ORIGIN
	_groups.columns = COLUMN_COUNT
	_groups.add_theme_constant_override("h_separation", 0)
	_groups.add_theme_constant_override("v_separation", ROW_GAP)
	add_child(_groups)
	_empty_label = Label.new()
	_empty_label.position = GRID_ORIGIN
	_empty_label.size = Vector2(250.0, 74.0)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", Color(0.83, 0.83, 0.76))
	_empty_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_empty_label.add_theme_constant_override("outline_size", 2)
	add_child(_empty_label)
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


func slot_icon_texture(button: Button) -> Texture2D:
	var state_value: Variant = _slot_visuals.get(button)
	if not state_value is Dictionary:
		return null
	var icon_rect := (state_value as Dictionary).get("icon_rect") as TextureRect
	return icon_rect.texture if icon_rect != null else null


func layout_snapshot() -> Dictionary:
	var slots: Array[Dictionary] = []
	for index: int in range(_slot_buttons.size()):
		var button := _slot_buttons[index]
		if not is_instance_valid(button):
			continue
		slots.append({
			"index": index,
			"rect": Rect2(GRID_ORIGIN + button.position, button.size),
			"disabled": button.disabled,
			"focused": button.has_focus(),
		})
	return {
		"panel_size": custom_minimum_size,
		"grid_origin": GRID_ORIGIN,
		"column_count": COLUMN_COUNT,
		"cell_size": CELL_SIZE,
		"row_pitch": ORIGINAL_ROW_PITCH,
		"slots": slots,
	}


func _rebuild() -> void:
	if _groups == null:
		return
	_slot_buttons.clear()
	_slot_visuals.clear()
	for child: Node in _groups.get_children():
		child.queue_free()
	var visible_slots: Array[Dictionary] = []
	for raw_group: Variant in model.get("groups", []):
		if not raw_group is Dictionary:
			continue
		var group := raw_group as Dictionary
		if not _group_is_visible(group):
			continue
		for raw_slot: Variant in group.get("slots", []):
			if raw_slot is Dictionary:
				visible_slots.append((raw_slot as Dictionary).duplicate(true))
	for slot: Dictionary in visible_slots:
		_groups.add_child(_make_slot(slot))
	_empty_label.visible = visible_slots.is_empty()
	_empty_label.text = "（该栏目前为空）"


func _group_is_visible(group: Dictionary) -> bool:
	var group_mode := str(group.get("mode", "items"))
	return group_mode == mode or group_mode == "both"


func _make_slot(slot: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = not bool(slot.get("enabled", true))
	button.tooltip_text = str(slot.get("description", slot.get("label", "")))
	button.text = ""
	button.add_theme_stylebox_override("normal", _transparent_cell_style(false))
	button.add_theme_stylebox_override("hover", _transparent_cell_style(true))
	button.add_theme_stylebox_override("pressed", _transparent_cell_style(true))
	button.add_theme_stylebox_override("focus", _transparent_cell_style(true))
	button.add_theme_stylebox_override("disabled", _transparent_cell_style(false))

	var icon_rect := TextureRect.new()
	icon_rect.name = "OriginalItemIcon"
	icon_rect.position = Vector2.ZERO
	icon_rect.size = Vector2(50.0, 50.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(icon_rect)

	var quantity_frame := Panel.new()
	quantity_frame.name = "OriginalQuantityFrame"
	quantity_frame.position = Vector2(2.0, 53.0)
	quantity_frame.size = Vector2(50.0, 24.0)
	quantity_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var quantity_style := StyleBoxFlat.new()
	quantity_style.bg_color = Color.BLACK
	var quantity_green := Color8(0, 157, 8, 255)
	quantity_style.border_color = quantity_green
	quantity_style.border_width_left = 1
	quantity_style.border_width_top = 1
	quantity_style.border_width_right = 1
	quantity_style.border_width_bottom = 1
	quantity_frame.add_theme_stylebox_override("panel", quantity_style)
	button.add_child(quantity_frame)
	for segment: Rect2 in [
		Rect2(6.0, 1.0, 1.0, 6.0),
		Rect2(6.0, 6.0, 38.0, 1.0),
		Rect2(43.0, 6.0, 1.0, 6.0),
	]:
		var accent := ColorRect.new()
		accent.position = segment.position
		accent.size = segment.size
		accent.color = quantity_green
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quantity_frame.add_child(accent)

	var quantity_label := Label.new()
	quantity_label.name = "OriginalQuantity"
	quantity_label.position = Vector2(3.0, 3.0)
	quantity_label.size = Vector2(46.0, 21.0)
	quantity_label.scale = Vector2(1.25, 1.0)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_label.add_theme_font_size_override("font_size", 14)
	quantity_label.add_theme_color_override("font_color", Color.RED)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var quantity := int(slot.get("quantity", 0))
	var is_weapon := str(slot.get("kind", "")) == "weapon"
	quantity_label.text = (
		"%d发" % quantity
		if is_weapon and quantity > 0
		else ""
		if is_weapon
		else "X%d" % quantity
	)
	quantity_frame.visible = is_weapon or quantity > 0
	quantity_frame.add_child(quantity_label)

	_slot_visuals[button] = {
		"active": bool(slot.get("active", false)),
		"hovered": false,
		"focused": false,
		"normal": slot.get("icon") as Texture2D,
		"selected": slot.get("icon_selected") as Texture2D,
		"icon_rect": icon_rect,
	}
	button.mouse_entered.connect(_set_slot_hovered.bind(button, true))
	button.mouse_exited.connect(_set_slot_hovered.bind(button, false))
	button.focus_entered.connect(_set_slot_focused.bind(button, true))
	button.focus_exited.connect(_set_slot_focused.bind(button, false))
	button.pressed.connect(func() -> void: slot_activated.emit(slot.duplicate(true)))
	_slot_buttons.append(button)
	_refresh_slot_visual(button)
	return button


func _set_slot_hovered(button: Button, hovered: bool) -> void:
	var state_value: Variant = _slot_visuals.get(button)
	if not state_value is Dictionary:
		return
	(state_value as Dictionary)["hovered"] = hovered
	_refresh_slot_visual(button)


func _set_slot_focused(button: Button, focused: bool) -> void:
	var state_value: Variant = _slot_visuals.get(button)
	if not state_value is Dictionary:
		return
	(state_value as Dictionary)["focused"] = focused
	_refresh_slot_visual(button)


func _refresh_slot_visual(button: Button) -> void:
	var state_value: Variant = _slot_visuals.get(button)
	if not state_value is Dictionary:
		return
	var state := state_value as Dictionary
	var icon_rect := state.get("icon_rect") as TextureRect
	if icon_rect == null:
		return
	var highlighted := (
		bool(state.get("hovered", false))
		or bool(state.get("focused", false))
	)
	var selected := state.get("selected") as Texture2D
	var normal := state.get("normal") as Texture2D
	icon_rect.texture = selected if highlighted and selected != null else normal
	icon_rect.modulate = Color(0.55, 0.55, 0.55, 0.88) if button.disabled else Color.WHITE


func _transparent_cell_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(0.76, 0.92, 0.53, 0.9) if highlighted else Color.TRANSPARENT
	style.border_width_left = 1 if highlighted else 0
	style.border_width_top = 1 if highlighted else 0
	style.border_width_right = 1 if highlighted else 0
	style.border_width_bottom = 1 if highlighted else 0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style
