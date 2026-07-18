extends Node2D

const SQUAD_UNIT = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT = preload("res://scripts/enemy_unit.gd")
const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const LEVEL_VIEW: Script = preload("res://scripts/level_view.gd")
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const DYNAMIC_OCCUPANCY_GRID: Script = preload("res://scripts/dynamic_occupancy_grid.gd")
const DEFAULT_WORLD_SIZE := Vector2(1280.0, 720.0)
const DEFAULT_MOVEMENT_BOUNDS := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))
const CAMERA_PAN_SPEED := 720.0
const FORMAL_LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]
const PLAYABLE_SQUAD: Array[Dictionary] = [
	{"name": "老赵", "color": Color("8fa66b")},
	{"name": "铁蛋", "color": Color("c89d5b")},
	{"name": "强子", "color": Color("7994a8")},
	{"name": "古明", "color": Color("b56f68")},
	{"name": "大牛", "color": Color("8c7ba8")},
]

var units: Array[SQUAD_UNIT] = []
var enemies: Array[ENEMY_UNIT] = []
var selected_units: Array[SQUAD_UNIT] = []
var status_label: Label
var badge_label: Label
var objective_label: Label
var level_camera: Camera2D
var world_size := DEFAULT_WORLD_SIZE
var movement_bounds := DEFAULT_MOVEMENT_BOUNDS
var terrain_loaded := false
var camera_dragging := false
var imported_level: Dictionary = {}
var imported_entity_count := 0
var current_level_index := 0
var playable_entities: Dictionary = {}
var enemy_entities: Array[Dictionary] = []
var imported_texture_cache: Dictionary = {}
var imported_animation_cache: Dictionary = {}
var current_level_directory := ""
var converted_root := ""
var current_mission: Dictionary = {}
var current_mission_state: RefCounted
var navigation_grid: NavigationGridData
var dynamic_occupancy: RefCounted


func _ready() -> void:
	create_interface()
	create_level_camera()
	switch_level(requested_level_index())
	queue_redraw()


func create_interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var title := Label.new()
	title.position = Vector2(22.0, 18.0)
	title.text = "《1937特种兵》· 现代复刻技术原型"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.97, 0.91, 0.72))
	canvas.add_child(title)

	var help := Label.new()
	help.position = Vector2(24.0, 54.0)
	help.text = "左键选择 · Shift 多选 · 右键移动 · WASD/方向键平移 · 滚轮缩放 · PgUp/PgDn 切关 · R 重置"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.82, 0.84, 0.76))
	canvas.add_child(help)

	status_label = Label.new()
	status_label.position = Vector2(24.0, 680.0)
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.81, 0.37))
	canvas.add_child(status_label)
	update_status("原版资源尚未导入，当前为程序化占位场景")

	badge_label = Label.new()
	badge_label.position = Vector2(1042.0, 22.0)
	badge_label.text = "M2 / LOCAL ASSET MODE"
	badge_label.add_theme_font_size_override("font_size", 14)
	badge_label.add_theme_color_override("font_color", Color(0.63, 0.78, 0.65))
	canvas.add_child(badge_label)

	objective_label = Label.new()
	objective_label.position = Vector2(880.0, 54.0)
	objective_label.size = Vector2(376.0, 190.0)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_font_size_override("font_size", 14)
	objective_label.add_theme_color_override("font_color", Color(0.94, 0.89, 0.72))
	canvas.add_child(objective_label)


func requested_level_index() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			var requested_id := argument.trim_prefix("--level=").to_lower()
			var index := FORMAL_LEVEL_IDS.find(requested_id)
			if index >= 0:
				return index
	return 0


func switch_level(level_index: int) -> void:
	current_level_index = posmod(level_index, FORMAL_LEVEL_IDS.size())
	var level_id := FORMAL_LEVEL_IDS[current_level_index]
	_load_mission_graph(level_id)
	load_imported_level(level_id)
	spawn_squad()
	if badge_label != null:
		badge_label.text = "M2 / %s / LOCAL ASSETS" % level_id.to_upper()


func _load_mission_graph(level_id: String) -> void:
	current_mission = MISSION_DATA.load_mission(level_id)
	current_mission_state = MISSION_STATE.new(current_mission)
	if objective_label != null:
		objective_label.text = "\n".join(current_mission_state.display_lines())


func load_imported_level(level_id: String = LEVEL_VIEW.DEFAULT_LEVEL_ID) -> bool:
	remove_imported_node("ImportedTerrain")
	remove_imported_node("ImportedEntities")
	playable_entities.clear()
	enemy_entities.clear()
	imported_texture_cache.clear()
	imported_animation_cache.clear()
	imported_entity_count = 0
	navigation_grid = null
	dynamic_occupancy = null
	current_level_directory = (
		ProjectSettings.globalize_path(IMPORTED_LEVEL_DATA.level_path(level_id)).get_base_dir()
	)
	converted_root = (
		ProjectSettings.globalize_path("res://../LocalAssets/converted").simplify_path()
	)
	imported_level = IMPORTED_LEVEL_DATA.load_level(level_id)
	var imported: Dictionary = LEVEL_VIEW.load_imported_terrain(level_id)
	if imported.is_empty():
		terrain_loaded = false
		world_size = DEFAULT_WORLD_SIZE
		movement_bounds = DEFAULT_MOVEMENT_BOUNDS
		configure_level_camera(true)
		update_status("未找到本地转换资源，当前为程序化占位场景")
		queue_redraw()
		return false

	var terrain := Sprite2D.new()
	terrain.name = "ImportedTerrain"
	terrain.centered = false
	terrain.texture = imported["texture"] as Texture2D
	terrain.z_index = -100
	add_child(terrain)
	move_child(terrain, 0)

	terrain_loaded = true
	world_size = imported["size"] as Vector2
	var margin := Vector2(24.0, 24.0)
	movement_bounds = Rect2(margin, (world_size - margin * 2.0).max(Vector2.ONE))
	imported_entity_count = spawn_imported_entities()
	navigation_grid = _load_navigation_grid()
	configure_level_camera(true)
	update_status(
		(
			"已加载 %s：%d × %d · 场景实体 %d · 可控队员 %d · 导航%s"
			% [
				level_id.to_upper(),
				int(world_size.x),
				int(world_size.y),
				imported_entity_count,
				playable_entities.size(),
				"就绪" if navigation_grid != null else "不可用",
			]
		)
	)
	queue_redraw()
	return true


func _load_navigation_grid() -> NavigationGridData:
	if imported_level.is_empty():
		return null
	var metadata := imported_level.get("navigation", {}) as Dictionary
	if metadata.is_empty():
		return null
	var navigation_path := _contained_converted_path(
		current_level_directory,
		str(metadata.get("relative_path", "")),
	)
	if navigation_path.is_empty():
		push_warning("忽略越出本地转换目录的导航数据")
		return null
	var loaded: NavigationGridData = NAVIGATION_GRID_DATA.load_file(navigation_path, metadata)
	if loaded == null:
		push_warning("导航数据无效或与关卡元数据不一致：%s" % navigation_path)
		return null
	var navigation_world_size := Vector2(loaded.dimensions * loaded.cell_size)
	if not navigation_world_size.is_equal_approx(world_size):
		push_warning("导航尺寸 %s 与关卡尺寸 %s 不一致" % [navigation_world_size, world_size])
		return null
	var ignored_scene_indices: Array[int] = []
	for entity_value: Variant in playable_entities.values():
		var entity := entity_value as Dictionary
		ignored_scene_indices.append(int(entity["scene_index"]))
	loaded.prepare_astar(ignored_scene_indices)
	return loaded


func remove_imported_node(node_name: String) -> void:
	var existing := get_node_or_null(node_name)
	if existing != null:
		remove_child(existing)
		existing.queue_free()


func spawn_imported_entities() -> int:
	if imported_level.is_empty():
		return 0

	var container := Node2D.new()
	container.name = "ImportedEntities"
	add_child(container)
	var spawned := 0
	var entities: Array = imported_level["entities"] as Array
	for entity_value: Variant in entities:
		var entity := entity_value as Dictionary
		var display_name := entity["display_name"] as String
		if is_playable_name(display_name):
			if not playable_entities.has(display_name):
				playable_entities[display_name] = entity
			continue
		if int(entity.get("faction_id", entity.get("team_id", 0))) == 1:
			enemy_entities.append(entity)
			spawned += 1
			continue
		var texture := load_entity_texture(entity)
		if texture == null:
			continue

		var sprite := Sprite2D.new()
		sprite.name = "Entity_%04d" % int(entity["scene_index"])
		sprite.texture = texture
		sprite.position = Vector2(float(entity["x"]), float(entity["y"]))
		sprite.z_index = clampi(int(entity["y"]), -4096, 4095)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(sprite)
		spawned += 1
	return spawned


func is_playable_name(display_name: String) -> bool:
	for specification: Dictionary in PLAYABLE_SQUAD:
		if display_name == str(specification["name"]):
			return true
	return false


func load_entity_texture(entity: Dictionary) -> Texture2D:
	var preview_path := entity_preview_path(entity)
	if preview_path.is_empty():
		return null
	if imported_texture_cache.has(preview_path):
		return imported_texture_cache[preview_path] as Texture2D

	var image := Image.new()
	if image.load(preview_path) != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	imported_texture_cache[preview_path] = texture
	return texture


func entity_preview_path(entity: Dictionary) -> String:
	var relative_preview := entity["sprite_preview"] as String
	if relative_preview.is_empty() or current_level_directory.is_empty():
		return ""
	var preview_path := _contained_converted_path(current_level_directory, relative_preview)
	if preview_path.is_empty():
		push_warning("忽略越出本地转换目录的实体预览：%s" % relative_preview)
		return ""
	if not FileAccess.file_exists(preview_path):
		return ""
	return preview_path


func _contained_converted_path(base_directory: String, relative_path: String) -> String:
	if base_directory.is_empty() or relative_path.is_empty() or relative_path.is_absolute_path():
		return ""
	var preview_path := base_directory.path_join(relative_path).simplify_path()
	var root_with_separator := converted_root.trim_suffix("/").trim_suffix("\\") + "/"
	var normalized_preview := preview_path.replace("\\", "/")
	var normalized_root := root_with_separator.replace("\\", "/")
	if not normalized_preview.to_lower().begins_with(normalized_root.to_lower()):
		return ""
	return preview_path


func load_entity_action_groups(entity: Dictionary, action_key: String) -> Array[Dictionary]:
	var preview_path := entity_preview_path(entity)
	if preview_path.is_empty():
		return []
	var cache_key := "%s|%s" % [preview_path, action_key]
	if imported_animation_cache.has(cache_key):
		return imported_animation_cache[cache_key] as Array[Dictionary]
	var groups: Array[Dictionary] = IMPORTED_SPRITE_ANIMATION.load_action_groups(
		preview_path, action_key
	)
	imported_animation_cache[cache_key] = groups
	return groups


func create_level_camera() -> void:
	level_camera = Camera2D.new()
	level_camera.name = "LevelCamera"
	level_camera.position_smoothing_enabled = true
	level_camera.position_smoothing_speed = 12.0
	add_child(level_camera)
	level_camera.enabled = true
	configure_level_camera(true)


func configure_level_camera(reset_position: bool) -> void:
	if level_camera == null:
		return
	level_camera.limit_left = 0
	level_camera.limit_top = 0
	level_camera.limit_right = int(world_size.x)
	level_camera.limit_bottom = int(world_size.y)
	if reset_position:
		level_camera.zoom = Vector2.ONE * LEVEL_VIEW.MAX_ZOOM
		level_camera.position = initial_camera_focus()
	clamp_level_camera()


func initial_camera_focus() -> Vector2:
	for specification: Dictionary in PLAYABLE_SQUAD:
		var name := str(specification["name"])
		if playable_entities.has(name):
			var entity := playable_entities[name] as Dictionary
			return Vector2(float(entity["x"]), float(entity["y"]))
	return Vector2(640.0, 360.0)


func spawn_squad() -> void:
	for unit: SQUAD_UNIT in units:
		unit.queue_free()
	for enemy: ENEMY_UNIT in enemies:
		enemy.queue_free()
	units.clear()
	enemies.clear()
	selected_units.clear()
	dynamic_occupancy = null
	if navigation_grid != null:
		dynamic_occupancy = DYNAMIC_OCCUPANCY_GRID.new()
		dynamic_occupancy.configure(navigation_grid)

	var specifications: Array[Dictionary] = []
	if terrain_loaded and not playable_entities.is_empty():
		for specification: Dictionary in PLAYABLE_SQUAD:
			if playable_entities.has(str(specification["name"])):
				specifications.append(specification)
	else:
		specifications.assign(PLAYABLE_SQUAD)

	for index: int in range(specifications.size()):
		var specification := specifications[index]
		var name := specification["name"] as String
		var start_position := Vector2(270.0 + index * 48.0, 500.0 + (index % 2) * 34.0)
		var texture: Texture2D = null
		var movement_groups: Array[Dictionary] = []
		var idle_groups: Array[Dictionary] = []
		var scene_index := -1
		var source_reference_position: Variant = null
		if playable_entities.has(name):
			var entity := playable_entities[name] as Dictionary
			scene_index = int(entity["scene_index"])
			start_position = Vector2(float(entity["x"]), float(entity["y"]))
			source_reference_position = Vector2(
				float(entity["reference_x"]), float(entity["reference_y"])
			)
			texture = load_entity_texture(entity)
			movement_groups = load_entity_action_groups(entity, "run")
			if movement_groups.is_empty():
				movement_groups = load_entity_action_groups(entity, "walk")
			idle_groups = load_entity_action_groups(entity, "stand")
		var unit: SQUAD_UNIT = SQUAD_UNIT.new()
		add_child(unit)
		(
			unit
			. configure(
				name,
				specification["color"] as Color,
				start_position,
				texture,
				movement_groups,
				idle_groups,
				scene_index,
				dynamic_occupancy,
				source_reference_position,
			)
		)
		units.append(unit)
	_spawn_enemies()
	if dynamic_occupancy != null:
		dynamic_occupancy.finalize_registration()
	var target_nodes: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		target_nodes.append(unit)
	for enemy: ENEMY_UNIT in enemies:
		enemy.set_potential_targets(target_nodes)
	if not units.is_empty():
		select_only(units[0])


func _spawn_enemies() -> void:
	if dynamic_occupancy == null:
		return
	for entity: Dictionary in enemy_entities:
		var texture := load_entity_texture(entity)
		if texture == null:
			continue
		var movement_groups := load_entity_action_groups(entity, "walk")
		if movement_groups.is_empty():
			movement_groups = load_entity_action_groups(entity, "run")
		var idle_groups := load_entity_action_groups(entity, "stand")
		var enemy: ENEMY_UNIT = ENEMY_UNIT.new()
		add_child(enemy)
		enemy.configure_enemy(
			entity,
			texture,
			movement_groups,
			idle_groups,
			dynamic_occupancy,
		)
		enemies.append(enemy)


func _process(delta: float) -> void:
	if level_camera == null:
		return
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	direction += Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	level_camera.position += direction * CAMERA_PAN_SPEED * delta / level_camera.zoom.x
	clamp_level_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and camera_dragging and level_camera != null:
		var motion := event as InputEventMouseMotion
		level_camera.position -= motion.relative / level_camera.zoom.x
		clamp_level_camera()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_dragging = mouse_event.pressed
			get_viewport().set_input_as_handled()
			return
		if (
			mouse_event.pressed
			and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		):
			if level_camera != null:
				var zoom_in := mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
				var next_zoom: float = LEVEL_VIEW.stepped_zoom(level_camera.zoom.x, zoom_in)
				level_camera.zoom = Vector2.ONE * next_zoom
				clamp_level_camera()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.pressed:
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
		elif key_event.keycode == KEY_PAGEUP:
			switch_level(current_level_index - 1)
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_PAGEDOWN:
			switch_level(current_level_index + 1)
			get_viewport().set_input_as_handled()


func clamp_level_camera() -> void:
	if level_camera == null:
		return
	level_camera.position = LEVEL_VIEW.clamp_camera_center(
		level_camera.position, get_viewport_rect().size, level_camera.zoom.x, world_size
	)


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
	if terrain_loaded and navigation_grid == null:
		update_status("当前关卡导航数据不可用，已拒绝可能穿墙的移动命令")
		return
	var offsets: Array[Vector2] = []
	for index: int in range(selected_units.size()):
		offsets.append(SIMULATION_SCRIPT.formation_offset(index, selected_units.size()))
	var center: Vector2 = SIMULATION_SCRIPT.clamp_formation_center(
		destination, offsets, movement_bounds
	)
	var planned_count := 0
	for index: int in range(selected_units.size()):
		var unit := selected_units[index]
		var unit_destination := center + offsets[index]
		if navigation_grid == null:
			unit.issue_move(unit_destination)
			planned_count += 1
			continue
		var path := PackedVector2Array()
		if dynamic_occupancy != null and unit.scene_index >= 0:
			path = dynamic_occupancy.find_path_for_scene(
				unit.scene_index, unit.position, unit_destination
			)
		else:
			path = navigation_grid.find_path(unit.position, unit_destination)
		if path.is_empty() and not unit.position.is_equal_approx(unit_destination):
			unit.cancel_path()
			continue
		unit.issue_path(path)
		planned_count += 1
	if navigation_grid == null:
		update_status("直线移动命令：%d 名队员 → (%d, %d)" % [planned_count, center.x, center.y])
	else:
		update_status(
			"自动寻路：%d/%d 名队员 → (%d, %d)" % [planned_count, selected_units.size(), center.x, center.y]
		)


func update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _draw() -> void:
	if terrain_loaded:
		return
	draw_rect(Rect2(Vector2.ZERO, world_size), Color("17221b"))
	for x: int in range(0, int(world_size.x) + 1, 64):
		draw_line(Vector2(x, 92.0), Vector2(x, world_size.y), Color(0.32, 0.42, 0.31, 0.16), 1.0)
	for y: int in range(92, int(world_size.y) + 1, 64):
		draw_line(Vector2(0.0, y), Vector2(world_size.x, y), Color(0.32, 0.42, 0.31, 0.16), 1.0)

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
