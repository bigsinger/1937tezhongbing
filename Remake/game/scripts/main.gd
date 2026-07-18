extends Node2D

const SQUAD_UNIT = preload("res://scripts/squad_unit.gd")
const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const WORLD_SIZE := Vector2(1280.0, 720.0)
const MOVEMENT_BOUNDS := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))

var units: Array[SQUAD_UNIT] = []
var selected_units: Array[SQUAD_UNIT] = []
var status_label: Label


func _ready() -> void:
	create_interface()
	spawn_squad()
	queue_redraw()


func create_interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var title := Label.new()
	title.position = Vector2(22.0, 18.0)
	title.text = "1937 特种兵 · 现代复刻技术原型"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.97, 0.91, 0.72))
	canvas.add_child(title)

	var help := Label.new()
	help.position = Vector2(24.0, 54.0)
	help.text = "左键选择 · Shift 多选 · 右键编队移动 · R 重置"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.82, 0.84, 0.76))
	canvas.add_child(help)

	status_label = Label.new()
	status_label.position = Vector2(24.0, 680.0)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.81, 0.37))
	canvas.add_child(status_label)
	update_status("原版资源尚未导入，当前为程序化占位场景")

	var badge := Label.new()
	badge.position = Vector2(1052.0, 22.0)
	badge.text = "M0 / FORMAT RESEARCH"
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color(0.63, 0.78, 0.65))
	canvas.add_child(badge)


func spawn_squad() -> void:
	for unit: SQUAD_UNIT in units:
		unit.queue_free()
	units.clear()
	selected_units.clear()

	var names: Array[String] = ["老赵", "钢蛋", "强子", "小梅", "阿福"]
	var colors: Array[Color] = [
		Color("8fa66b"), Color("c89d5b"), Color("7994a8"), Color("b56f68"), Color("8c7ba8")
	]
	for index: int in range(names.size()):
		var unit: SQUAD_UNIT = SQUAD_UNIT.new()
		add_child(unit)
		var start_position := Vector2(270.0 + index * 48.0, 500.0 + (index % 2) * 34.0)
		unit.configure(names[index], colors[index], start_position)
		units.append(unit)
	select_only(units[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		var local_position: Vector2 = (
			get_global_transform_with_canvas().affine_inverse() * mouse_event.position
		)
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			handle_selection(local_position, mouse_event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			issue_formation_move(local_position)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_R:
			spawn_squad()
			update_status("队伍已重置")
			get_viewport().set_input_as_handled()


func handle_selection(world_point: Vector2, additive: bool) -> void:
	var hit: SQUAD_UNIT
	for unit: SQUAD_UNIT in units:
		if unit.contains_parent_point(world_point):
			hit = unit
			break
	if hit == null:
		if not additive:
			clear_selection()
		update_status("未选中队员")
		return
	if additive:
		if selected_units.has(hit):
			selected_units.erase(hit)
			hit.set_selected(false)
		else:
			selected_units.append(hit)
			hit.set_selected(true)
	else:
		select_only(hit)
	update_status("已选择 %d 名队员" % selected_units.size())


func clear_selection() -> void:
	for unit: SQUAD_UNIT in selected_units:
		unit.set_selected(false)
	selected_units.clear()


func select_only(unit: SQUAD_UNIT) -> void:
	clear_selection()
	selected_units.append(unit)
	unit.set_selected(true)


func issue_formation_move(destination: Vector2) -> void:
	if selected_units.is_empty():
		update_status("请先选择队员")
		return
	var offsets: Array[Vector2] = []
	for index: int in range(selected_units.size()):
		offsets.append(SIMULATION_SCRIPT.formation_offset(index, selected_units.size()))
	var center: Vector2 = SIMULATION_SCRIPT.clamp_formation_center(
		destination, offsets, MOVEMENT_BOUNDS
	)
	for index: int in range(selected_units.size()):
		selected_units[index].issue_move(center + offsets[index])
	update_status("移动命令：%d 名队员 → (%d, %d)" % [selected_units.size(), center.x, center.y])


func update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("17221b"))
	for x: int in range(0, int(WORLD_SIZE.x) + 1, 64):
		draw_line(Vector2(x, 92.0), Vector2(x, WORLD_SIZE.y), Color(0.32, 0.42, 0.31, 0.16), 1.0)
	for y: int in range(92, int(WORLD_SIZE.y) + 1, 64):
		draw_line(Vector2(0.0, y), Vector2(WORLD_SIZE.x, y), Color(0.32, 0.42, 0.31, 0.16), 1.0)

	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(0, 310), Vector2(1280, 250), Vector2(1280, 325), Vector2(0, 385)]
		),
		Color("33452e")
	)
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(0, 332), Vector2(1280, 272), Vector2(1280, 296), Vector2(0, 356)]
		),
		Color("756849")
	)

	draw_rect(Rect2(755.0, 370.0, 215.0, 130.0), Color("5a4934"), true)
	draw_colored_polygon(
		PackedVector2Array([Vector2(735, 370), Vector2(862, 300), Vector2(992, 370)]),
		Color("684132")
	)
	draw_rect(Rect2(835.0, 430.0, 54.0, 70.0), Color("2b271f"), true)

	var tree_positions: Array[Vector2] = [
		Vector2(150, 180),
		Vector2(240, 245),
		Vector2(1080, 190),
		Vector2(1135, 440),
		Vector2(650, 555)
	]
	for tree_position: Vector2 in tree_positions:
		draw_circle(tree_position + Vector2(4, 8), 29.0, Color(0.0, 0.0, 0.0, 0.25))
		draw_circle(tree_position, 25.0, Color("315b38"))
		draw_circle(tree_position + Vector2(-10, -8), 17.0, Color("416f42"))
