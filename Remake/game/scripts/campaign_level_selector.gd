class_name CampaignLevelSelector
extends PanelContainer

signal level_chosen(level_id: String)
signal back_requested

var level_entries: Array[Dictionary] = []
var campaign_progress: Dictionary = {}
var current_level_id := "m000"
var level_buttons: Dictionary = {}

var _summary: Label
var _grid: GridContainer
var _original_texture_pairs: Dictionary = {}
var _original_assets_ready := false


func configure_original_assets(texture_pairs: Dictionary) -> bool:
	_original_texture_pairs.clear()
	_original_assets_ready = texture_pairs.size() == 12
	for level_id: String in texture_pairs:
		var pair := texture_pairs[level_id] as Dictionary
		var normal := pair.get("normal") as Texture2D
		var hover := pair.get("hover") as Texture2D
		if (
			normal == null
			or hover == null
			or normal.get_size() != Vector2(114.0, 33.0)
			or hover.get_size() != Vector2(114.0, 33.0)
		):
			_original_assets_ready = false
			break
		_original_texture_pairs[level_id] = {
			"normal": normal,
			"hover": hover,
		}
	if not _original_assets_ready:
		_original_texture_pairs.clear()
	if _grid != null:
		_rebuild_buttons()
	return _original_assets_ready


func layout_snapshot() -> Dictionary:
	var buttons: Dictionary = {}
	for level_id: String in level_buttons:
		var button := level_buttons[level_id] as Button
		buttons[level_id] = {
			"rect": button.get_global_rect(),
			"enabled": not button.disabled,
			"text": button.text,
			"icon_size": (
				button.icon.get_size()
				if button.icon != null
				else Vector2.ZERO
			),
			"uses_original_asset": _original_texture_pairs.has(level_id),
		}
	return {
		"assets_ready": _original_assets_ready,
		"grid_columns": _grid.columns if _grid != null else 0,
		"grid_rect": _grid.get_global_rect() if _grid != null else Rect2(),
		"buttons": buttons,
	}


func _ready() -> void:
	_build_interface()


func configure(
	entries: Array[Dictionary],
	progress: Dictionary,
	current_id: String,
) -> void:
	level_entries = entries.duplicate(true)
	campaign_progress = progress.duplicate(true)
	current_level_id = current_id
	if _grid != null:
		_rebuild_buttons()


func focus_current() -> void:
	var button := level_buttons.get(current_level_id) as Button
	if button == null and not level_buttons.is_empty():
		button = level_buttons.values()[0] as Button
	if button != null:
		button.grab_focus()


func _build_interface() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	var title := Label.new()
	title.text = "选择关卡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.97, 0.88, 0.61))
	content.add_child(title)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", Color(0.80, 0.83, 0.73))
	content.add_child(_summary)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(_grid)

	var evidence_note := Label.new()
	evidence_note.text = (
		"自由选关沿用稳定 MOD 的十二关路由；进入、退出或失败不会记为通关，"
		+ "只有任务胜利才更新战役完成度。"
	)
	evidence_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evidence_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evidence_note.add_theme_font_size_override("font_size", 13)
	evidence_note.add_theme_color_override("font_color", Color(0.68, 0.72, 0.64))
	content.add_child(evidence_note)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size.y = 42.0
	back.pressed.connect(func() -> void: back_requested.emit())
	content.add_child(back)
	_rebuild_buttons()


func _rebuild_buttons() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	level_buttons.clear()
	var completed_lookup: Dictionary = {}
	for level_value: Variant in campaign_progress.get("completed_level_ids", []) as Array:
		completed_lookup[str(level_value)] = true
	var highest_id := str(campaign_progress.get("highest_unlocked_level_id", "m000"))
	var completed_count := completed_lookup.size()
	_summary.text = (
		"已完成 %d / 12　顺序战役推进至 %s　所有正式关均可自由选择"
		% [completed_count, highest_id.to_upper()]
	)
	for entry: Dictionary in level_entries:
		var level_id := str(entry.get("id", ""))
		if level_id.is_empty():
			continue
		var number := int(entry.get("number", level_buttons.size() + 1))
		var title := str(entry.get("title", level_id.to_upper()))
		var state := "✓ 已完成" if completed_lookup.has(level_id) else "自由选关"
		if level_id == current_level_id:
			state += "　● 当前"
		elif level_id == highest_id and not completed_lookup.has(level_id):
			state += "　◆ 顺序可玩"
		var button := Button.new()
		button.name = "Level_%s" % level_id
		button.text = "第 %02d 关\n%s" % [number, state]
		button.custom_minimum_size = Vector2(245.0, 82.0)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "%s：%s" % [level_id.to_upper(), title]
		button.add_theme_font_size_override("font_size", 14)
		if _original_texture_pairs.has(level_id):
			var textures := _original_texture_pairs[level_id] as Dictionary
			button.icon = textures.get("normal") as Texture2D
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.expand_icon = false
			button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var empty_style := StyleBoxEmpty.new()
			for style_name: String in [
				"normal", "hover", "pressed", "focus", "disabled"
			]:
				button.add_theme_stylebox_override(style_name, empty_style)
			button.mouse_entered.connect(
				_refresh_original_button_texture.bind(level_id)
			)
			button.mouse_exited.connect(
				_refresh_original_button_texture.bind(level_id)
			)
			button.focus_entered.connect(
				_refresh_original_button_texture.bind(level_id)
			)
			button.focus_exited.connect(
				_refresh_original_button_texture.bind(level_id)
			)
			button.button_down.connect(
				_refresh_original_button_texture.bind(level_id)
			)
			button.button_up.connect(
				_refresh_original_button_texture.bind(level_id)
			)
		button.pressed.connect(
			func() -> void:
				level_chosen.emit(level_id)
		)
		_grid.add_child(button)
		level_buttons[level_id] = button


func _refresh_original_button_texture(level_id: String) -> void:
	call_deferred("_apply_original_button_texture", level_id)


func _apply_original_button_texture(level_id: String) -> void:
	var button := level_buttons.get(level_id) as Button
	if button == null or not _original_texture_pairs.has(level_id):
		return
	var textures := _original_texture_pairs[level_id] as Dictionary
	var highlighted := button.is_hovered() or button.has_focus() or button.button_pressed
	button.icon = textures.get("hover" if highlighted else "normal") as Texture2D
