class_name SaveSlotSelector
extends PanelContainer

signal slot_chosen(slot_id: String)
signal back_requested

enum Mode { SAVE, LOAD }

const MANUAL_SLOT_IDS: Array[String] = [
	"slot_1", "slot_2", "slot_3", "slot_4", "slot_5",
	"slot_6", "slot_7", "slot_8", "slot_9", "slot_10",
]

var mode := Mode.LOAD
var slot_summaries: Array[Dictionary] = []
var slot_buttons: Dictionary = {}

var _title: Label
var _rows: VBoxContainer
var _pending_overwrite_slot := ""


func _ready() -> void:
	_build_interface()


func configure(new_mode: int, summaries: Array[Dictionary]) -> void:
	mode = new_mode
	slot_summaries = summaries.duplicate(true)
	_pending_overwrite_slot = ""
	if _rows != null:
		_rebuild_rows()


func _build_interface() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.97, 0.88, 0.61))
	content.add_child(_title)
	var help := Label.new()
	help.text = "选择一个存档位置；覆盖已有存档时需要再次确认。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 400.0
	content.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size.x = 650.0
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 7)
	scroll.add_child(_rows)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size.y = 40.0
	back.pressed.connect(func() -> void: back_requested.emit())
	content.add_child(back)
	_rebuild_rows()


func _rebuild_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	_title.text = "保存游戏" if mode == Mode.SAVE else "读取游戏"
	var summaries_by_id: Dictionary = {}
	for summary: Dictionary in slot_summaries:
		summaries_by_id[str(summary.get("slot_id", ""))] = summary
	for slot_id: String in MANUAL_SLOT_IDS:
		_add_slot_button(slot_id, summaries_by_id.get(slot_id, {}) as Dictionary)
	if mode == Mode.LOAD:
		for special_slot_id: String in ["quick", "autosave"]:
			if summaries_by_id.has(special_slot_id):
				_add_slot_button(
					special_slot_id,
					summaries_by_id[special_slot_id] as Dictionary,
				)


func _add_slot_button(slot_id: String, summary: Dictionary) -> void:
	var button := Button.new()
	button.text = _slot_label(slot_id, summary)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 52.0
	button.disabled = mode == Mode.LOAD and summary.is_empty()
	button.pressed.connect(_on_slot_pressed.bind(slot_id, not summary.is_empty()))
	_rows.add_child(button)
	slot_buttons[slot_id] = button


func _on_slot_pressed(slot_id: String, occupied: bool) -> void:
	if mode == Mode.SAVE and occupied and _pending_overwrite_slot != slot_id:
		_pending_overwrite_slot = slot_id
		_refresh_button_labels()
		var button := slot_buttons.get(slot_id) as Button
		if button != null:
			button.text = "再次点击确认覆盖：%s" % _display_slot_name(slot_id)
		return
	_pending_overwrite_slot = ""
	slot_chosen.emit(slot_id)


func _refresh_button_labels() -> void:
	var summaries_by_id: Dictionary = {}
	for summary: Dictionary in slot_summaries:
		summaries_by_id[str(summary.get("slot_id", ""))] = summary
	for raw_slot_id: Variant in slot_buttons.keys():
		var slot_id := str(raw_slot_id)
		var button := slot_buttons[raw_slot_id] as Button
		button.text = _slot_label(
			slot_id,
			summaries_by_id.get(slot_id, {}) as Dictionary,
		)


static func _slot_label(slot_id: String, summary: Dictionary) -> String:
	var display_name := _display_slot_name(slot_id)
	if summary.is_empty():
		return "%s　—　空" % display_name
	var level_id := str(summary.get("level_id", "m000")).to_upper()
	var elapsed := _format_elapsed(float(summary.get("elapsed_seconds", 0.0)))
	var saved_at := _format_timestamp(int(summary.get("saved_at_unix", 0)))
	var recovery := "　[备份恢复]" if bool(summary.get("recovered", false)) else ""
	return "%s　%s　%s　%s%s" % [display_name, level_id, elapsed, saved_at, recovery]


static func _display_slot_name(slot_id: String) -> String:
	if slot_id == "quick":
		return "快速存档"
	if slot_id == "autosave":
		return "自动存档"
	if slot_id.begins_with("slot_"):
		return "存档 %d" % int(slot_id.trim_prefix("slot_"))
	return slot_id


static func _format_elapsed(seconds: float) -> String:
	var whole_seconds := maxi(int(seconds), 0)
	return "%02d:%02d:%02d" % [
		whole_seconds / 3600,
		(whole_seconds / 60) % 60,
		whole_seconds % 60,
	]


static func _format_timestamp(
	unix_time: int,
	utc_offset_minutes: int = 2147483647,
) -> String:
	if unix_time <= 0:
		return "未知时间"
	var resolved_offset := utc_offset_minutes
	if resolved_offset == 2147483647:
		resolved_offset = int(Time.get_time_zone_from_system().get("bias", 0))
	# Godot's Unix conversion is UTC. Save selectors are user-facing, so apply
	# the current system-zone bias before formatting the wall-clock timestamp.
	var value := Time.get_datetime_dict_from_unix_time(
		unix_time + resolved_offset * 60
	)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(value.get("year", 0)),
		int(value.get("month", 0)),
		int(value.get("day", 0)),
		int(value.get("hour", 0)),
		int(value.get("minute", 0)),
	]
