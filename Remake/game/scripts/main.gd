extends Node2D

const SQUAD_UNIT = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT = preload("res://scripts/enemy_unit.gd")
const ESCORT_UNIT = preload("res://scripts/escort_unit.gd")
const MISSION_PICKUP = preload("res://scripts/mission_pickup.gd")
const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const LEVEL_VIEW: Script = preload("res://scripts/level_view.gd")
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const PROJECTILE_WORLD_SCRIPT: Script = preload("res://scripts/projectile_world.gd")
const MEDIA_DIRECTOR_SCRIPT: Script = preload("res://scripts/media_director.gd")
const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const GAME_SETTINGS_SCRIPT: Script = preload("res://scripts/game_settings.gd")
const GAME_SAVE_STORE_SCRIPT: Script = preload("res://scripts/game_save_store.gd")
const GAME_SESSION_STATE_SCRIPT: Script = preload("res://scripts/game_session_state.gd")
const WORLD_PICKUP_CATALOG: Script = preload("res://scripts/world_pickup_catalog.gd")
const FIELD_PICKUP_SCRIPT: Script = preload("res://scripts/field_pickup.gd")
const EXPLOSIVE_PROP_SCRIPT: Script = preload("res://scripts/explosive_prop.gd")
const LAND_MINE_SCRIPT: Script = preload("res://scripts/land_mine.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const DYNAMIC_OCCUPANCY_GRID: Script = preload("res://scripts/dynamic_occupancy_grid.gd")
const DEFAULT_WORLD_SIZE := Vector2(1280.0, 720.0)
const DEFAULT_MOVEMENT_BOUNDS := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))
const CAMERA_PAN_SPEED := 720.0
const EDGE_SCROLL_MARGIN := 18.0
const MISSION_INTERACTION_RADIUS := 128.0
const MISSION_ZONE_CHECK_SECONDS := 0.20
const QUICK_SAVE_SLOT := "quick"
const AUTO_SAVE_SLOT := "autosave"
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
const PLAYABLE_LOADOUT_ATTACK_TYPES := {
	"老赵": 1,
	"铁蛋": 7,
	"强子": 2,
	"古明": 1,
	"大牛": 5,
}
const WEAPON_KEY_ATTACK_TYPES := {
	KEY_1: 1,
	KEY_2: 2,
	KEY_3: 3,
	KEY_4: 4,
	KEY_5: 5,
	KEY_6: 6,
	KEY_7: 7,
	KEY_8: 9,
}
const WEAPON_NAMES := {
	1: "手枪",
	2: "步枪",
	3: "机枪",
	4: "匕首",
	5: "大刀",
	6: "飞刀",
	7: "弹弓",
	8: "地雷",
	9: "手榴弹",
	10: "特殊地雷",
	11: "特殊动作",
}
const INVENTORY_ITEM_NAMES := {
	36: "手枪弹",
	37: "步枪弹",
	38: "机枪弹",
	39: "匕首",
	40: "大刀",
	41: "飞刀",
	42: "弹弓弹",
	43: "地雷",
	44: "手榴弹",
	45: "特殊地雷",
	99: "特殊物品",
}

var units: Array[SQUAD_UNIT] = []
var enemies: Array[ENEMY_UNIT] = []
var escorts: Array[ESCORT_UNIT] = []
var mission_pickups: Array[MISSION_PICKUP] = []
var selected_units: Array[SQUAD_UNIT] = []
var status_label: Label
var badge_label: Label
var objective_label: Label
var inventory_label: Label
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
var mission_runtime: Node
var world_entities_by_scene: Dictionary = {}
var activated_mission_scenes: Dictionary = {}
var mission_zone_elapsed := 0.0
var navigation_grid: NavigationGridData
var dynamic_occupancy: RefCounted
var projectile_world: Node2D
var media_director: CanvasLayer
var game_shell: CanvasLayer
var game_settings: RefCounted
var save_store: RefCounted
var campaign_progress: Dictionary = {}
var command_line_controls_display := false
var media_event_seed := 0
var field_pickups: Array[Node2D] = []
var explosive_props: Array[Node2D] = []
var deployed_mines: Array[Node2D] = []
var field_inventory: Dictionary = {}
var runtime_settings: Dictionary = {
	"fullscreen": false,
	"subtitles": true,
	"show_briefings": true,
	"edge_scroll": true,
	"master_volume": 0.8,
}


func _ready() -> void:
	_initialize_persistence()
	_create_media_director()
	_create_game_shell()
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
	help.text = "左键选择 · 右键移动/攻击 · E 交互 · 1–8/TAB 切武器 · Q 换弹 · X 布雷 · F 引爆 · M 地图 · B/I 背包 · Esc 菜单"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.82, 0.84, 0.76))
	canvas.add_child(help)

	inventory_label = Label.new()
	inventory_label.position = Vector2(24.0, 78.0)
	inventory_label.size = Vector2(660.0, 92.0)
	inventory_label.add_theme_font_size_override("font_size", 14)
	inventory_label.add_theme_color_override("font_color", Color(0.80, 0.90, 0.78))
	canvas.add_child(inventory_label)

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


func switch_level(level_index: int, show_briefing: bool = true) -> void:
	current_level_index = posmod(level_index, FORMAL_LEVEL_IDS.size())
	var level_id := FORMAL_LEVEL_IDS[current_level_index]
	_load_mission_graph(level_id)
	load_imported_level(level_id)
	spawn_squad()
	_configure_mission_runtime()
	if badge_label != null:
		badge_label.text = "M2 / %s / LOCAL ASSETS" % level_id.to_upper()
	if show_briefing and _should_show_briefing():
		media_director.show_briefing(
			level_id,
			"第 %d 关：%s" % [
				int(current_mission.get("number", 0)),
				str(current_mission.get("title", "任务简报")),
			],
			"原版简报图尚未导入；右侧任务目标仍可正常进行。",
		)


func _should_show_briefing() -> bool:
	if media_director == null or DisplayServer.get_name() == "headless":
		return false
	if not bool(runtime_settings.get("show_briefings", true)):
		return false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--skip-briefing":
			return false
	for argument: String in OS.get_cmdline_args():
		if argument.contains("runtime_probe.gd"):
			return false
	return true


func _load_mission_graph(level_id: String) -> void:
	current_mission = MISSION_DATA.load_mission(level_id)
	current_mission_state = MISSION_STATE.new(current_mission)
	if objective_label != null:
		objective_label.text = "\n".join(current_mission_state.display_lines())


func load_imported_level(level_id: String = LEVEL_VIEW.DEFAULT_LEVEL_ID) -> bool:
	for mine: Node2D in deployed_mines:
		if is_instance_valid(mine):
			mine.queue_free()
	deployed_mines.clear()
	field_pickups.clear()
	explosive_props.clear()
	field_inventory.clear()
	remove_imported_node("ImportedTerrain")
	remove_imported_node("ImportedEntities")
	playable_entities.clear()
	enemy_entities.clear()
	imported_texture_cache.clear()
	imported_animation_cache.clear()
	world_entities_by_scene.clear()
	activated_mission_scenes.clear()
	mission_pickups.clear()
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
		var scene_index := int(entity["scene_index"])
		world_entities_by_scene[scene_index] = entity
		var display_name := entity["display_name"] as String
		if _is_rescue_bound_scene(scene_index):
			spawned += 1
			continue
		if is_playable_name(display_name):
			if not playable_entities.has(display_name):
				playable_entities[display_name] = entity
			continue
		var database_entry_id := int(entity.get("database_entry_id", 0))
		var interactable_profile: Dictionary = (
			WORLD_PICKUP_CATALOG.profile_for_database_entry_id(database_entry_id)
		)
		if not interactable_profile.is_empty():
			var interactable_texture := load_entity_texture(entity)
			if str(interactable_profile.get("behavior", "")) == "field_pickup":
				var pickup: Node2D = FIELD_PICKUP_SCRIPT.new()
				pickup.name = "FieldPickup_%04d" % scene_index
				if pickup.configure(interactable_profile, entity, interactable_texture):
					container.add_child(pickup)
					field_pickups.append(pickup)
					spawned += 1
					continue
				pickup.free()
			elif str(interactable_profile.get("behavior", "")) == "explosive_prop":
				var prop: Node2D = EXPLOSIVE_PROP_SCRIPT.new()
				prop.name = "ExplosiveProp_%04d" % scene_index
				if prop.configure(interactable_profile, entity, interactable_texture):
					container.add_child(prop)
					prop.explosion_requested.connect(_on_world_explosion_requested)
					explosive_props.append(prop)
					spawned += 1
					continue
				prop.free()
		if (
			int(entity.get("faction_id", entity.get("team_id", 0))) == 1
			or _is_mission_combat_target_scene(scene_index)
		):
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
	if projectile_world != null:
		remove_child(projectile_world)
		projectile_world.queue_free()
	projectile_world = PROJECTILE_WORLD_SCRIPT.new()
	projectile_world.name = "ProjectileWorld"
	add_child(projectile_world)
	projectile_world.projectile_damage_applied.connect(_on_projectile_damage_applied)
	projectile_world.projectile_exploded.connect(_on_projectile_exploded)
	for unit: SQUAD_UNIT in units:
		unit.queue_free()
	for enemy: ENEMY_UNIT in enemies:
		enemy.queue_free()
	for escort: ESCORT_UNIT in escorts:
		escort.queue_free()
	for pickup: MISSION_PICKUP in mission_pickups:
		pickup.queue_free()
	units.clear()
	enemies.clear()
	escorts.clear()
	mission_pickups.clear()
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
		var entity: Dictionary = {}
		if playable_entities.has(name):
			entity = playable_entities[name] as Dictionary
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
		var attack_type := int(PLAYABLE_LOADOUT_ATTACK_TYPES.get(name, 1))
		var weapon_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
			attack_type
		)
		var attack_groups: Array[Dictionary] = []
		var death_groups: Array[Dictionary] = []
		if not entity.is_empty():
			attack_groups = load_entity_action_groups(
				entity, str(weapon_profile.get("action_key", "pistol_attack"))
			)
			death_groups = load_entity_action_groups(entity, "death")
		unit.configure_combat(
			3,
			maxi(int(entity.get("current_hit_points", 8)), 1),
			weapon_profile,
			attack_groups,
			death_groups,
			false,
		)
		_connect_combatant(unit)
		units.append(unit)
	_spawn_escorts()
	_spawn_enemies()
	if dynamic_occupancy != null:
		dynamic_occupancy.finalize_registration()
	var target_nodes: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		target_nodes.append(unit)
	for escort: ESCORT_UNIT in escorts:
		target_nodes.append(escort)
	for enemy: ENEMY_UNIT in enemies:
		enemy.set_potential_targets(target_nodes)
	var projectile_combatants: Array[Node2D] = target_nodes.duplicate()
	for enemy: ENEMY_UNIT in enemies:
		projectile_combatants.append(enemy)
	for prop: Node2D in explosive_props:
		if is_instance_valid(prop):
			projectile_combatants.append(prop)
	projectile_world.set_combatants(projectile_combatants)
	if not units.is_empty():
		select_only(units[0])


func _spawn_escorts() -> void:
	if dynamic_occupancy == null:
		return
	for scene_index: int in _rescue_bound_scenes():
		if not world_entities_by_scene.has(scene_index):
			continue
		var entity := world_entities_by_scene[scene_index] as Dictionary
		var texture := load_entity_texture(entity)
		if texture == null:
			continue
		var movement_groups := load_entity_action_groups(entity, "walk")
		if movement_groups.is_empty():
			movement_groups = load_entity_action_groups(entity, "run")
		var idle_groups := load_entity_action_groups(entity, "stand")
		var death_groups := load_entity_action_groups(entity, "death")
		var escort: ESCORT_UNIT = ESCORT_UNIT.new()
		add_child(escort)
		escort.configure_escort(
			entity,
			texture,
			movement_groups,
			idle_groups,
			death_groups,
			dynamic_occupancy,
		)
		escort.rescued.connect(_on_escort_rescued)
		_connect_combatant(escort)
		escorts.append(escort)


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
		var weapon_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
			int(entity.get("default_attack_type", 2))
		)
		if weapon_profile.is_empty():
			weapon_profile = COMBAT_PROFILES.weapon_profile("rifle_attack")
		var attack_groups := load_entity_action_groups(
			entity, str(weapon_profile.get("action_key", "rifle_attack"))
		)
		var death_groups := load_entity_action_groups(entity, "death")
		var enemy: ENEMY_UNIT = ENEMY_UNIT.new()
		add_child(enemy)
		enemy.configure_enemy(
			entity,
			texture,
			movement_groups,
			idle_groups,
			dynamic_occupancy,
			attack_groups,
			death_groups,
		)
		_connect_combatant(enemy)
		enemies.append(enemy)


func _process(delta: float) -> void:
	if mission_runtime != null and mission_runtime.is_configured():
		mission_runtime.advance_time(maxf(delta, 0.0))
		mission_zone_elapsed += maxf(delta, 0.0)
		if mission_zone_elapsed >= MISSION_ZONE_CHECK_SECONDS:
			mission_zone_elapsed = fmod(mission_zone_elapsed, MISSION_ZONE_CHECK_SECONDS)
			_evaluate_transient_mission_zones()
	if level_camera == null:
		return
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	direction += Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if bool(runtime_settings.get("edge_scroll", true)):
		direction += _mouse_edge_scroll_direction()
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	level_camera.position += direction * CAMERA_PAN_SPEED * delta / level_camera.zoom.x
	clamp_level_camera()


func _mouse_edge_scroll_direction() -> Vector2:
	if DisplayServer.get_name() == "headless" or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var viewport_size := get_viewport_rect().size
	var mouse_position := get_viewport().get_mouse_position()
	return edge_scroll_direction_for_position(mouse_position, viewport_size, EDGE_SCROLL_MARGIN)


static func edge_scroll_direction_for_position(
	mouse_position: Vector2,
	viewport_size: Vector2,
	margin: float = EDGE_SCROLL_MARGIN,
) -> Vector2:
	if (
		mouse_position.x < 0.0
		or mouse_position.y < 0.0
		or mouse_position.x > viewport_size.x
		or mouse_position.y > viewport_size.y
	):
		return Vector2.ZERO
	var safe_margin := clampf(margin, 0.0, minf(viewport_size.x, viewport_size.y) * 0.5)
	var direction := Vector2.ZERO
	if mouse_position.x <= safe_margin:
		direction.x -= 1.0
	elif mouse_position.x >= viewport_size.x - safe_margin:
		direction.x += 1.0
	if mouse_position.y <= safe_margin:
		direction.y -= 1.0
	elif mouse_position.y >= viewport_size.y - safe_margin:
		direction.y += 1.0
	return direction


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
				var combat_target: Node2D = enemy_at_world_point(local_position)
				if combat_target == null:
					combat_target = explosive_prop_at_world_point(local_position)
				if combat_target != null:
					issue_attack_order(combat_target)
				else:
					issue_formation_move(local_position)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_open_pause_menu()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_M:
			_open_tactical_map()
			get_viewport().set_input_as_handled()
		elif key_event.keycode in [KEY_B, KEY_I]:
			_open_inventory()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_F5:
			_save_game()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_F9:
			_load_game()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_R:
			switch_level(current_level_index)
			update_status("关卡已重置")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_E:
			interact_with_mission_world()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_Q:
			var reload_count := 0
			for unit: SQUAD_UNIT in selected_units:
				if unit.request_reload():
					reload_count += 1
			update_status("%d 名队员开始换弹" % reload_count)
			get_viewport().set_input_as_handled()
		elif WEAPON_KEY_ATTACK_TYPES.has(key_event.keycode):
			_equip_selected_attack_type(int(WEAPON_KEY_ATTACK_TYPES[key_event.keycode]))
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_TAB:
			_cycle_selected_weapons(-1 if key_event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_X:
			_deploy_selected_land_mine()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_F:
			_detonate_mission_charges()
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
		if unit.is_alive and unit.contains_parent_point(world_point):
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
	_refresh_inventory_ui()
	if selected_units.has(hit):
		_play_media_audio("selected", _media_actor_key(hit.display_name))


func clear_selection() -> void:
	for unit: SQUAD_UNIT in selected_units:
		unit.set_selected(false)
	selected_units.clear()
	_refresh_inventory_ui()


func select_only(unit: SQUAD_UNIT) -> void:
	clear_selection()
	selected_units.append(unit)
	unit.set_selected(true)
	_refresh_inventory_ui()


func _equip_selected_attack_type(attack_type: int) -> void:
	var equipped := 0
	for unit: SQUAD_UNIT in selected_units:
		if unit.equip_attack_type(attack_type):
			equipped += 1
	update_status(
		"%d 名队员切换为%s" % [equipped, str(WEAPON_NAMES.get(attack_type, "武器"))]
	)
	_refresh_inventory_ui()


func _cycle_selected_weapons(direction: int) -> void:
	var equipped := 0
	for unit: SQUAD_UNIT in selected_units:
		if unit.cycle_inventory_weapon(direction):
			equipped += 1
	update_status("%d 名队员已轮换武器" % equipped)
	_refresh_inventory_ui()


func _deploy_selected_land_mine() -> void:
	var mine_profile: Dictionary = WORLD_PICKUP_CATALOG.deployable_profile("land_mine")
	if mine_profile.is_empty():
		update_status("地雷配置不可用")
		return
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_alive or unit.ammo_item_count(43) <= 0:
			continue
		if unit.remove_ammo_item(43, 1) != 1:
			continue
		var mine: Node2D = LAND_MINE_SCRIPT.new()
		mine.name = "LandMine_%d" % (deployed_mines.size() + 1)
		if not mine.configure(mine_profile, unit.position, unit, unit.faction_id):
			mine.free()
			unit.add_ammo_item(43, 1)
			continue
		add_child(mine)
		var targets: Array[Node2D] = []
		for enemy: ENEMY_UNIT in enemies:
			targets.append(enemy)
		mine.set_potential_targets(targets)
		mine.explosion_requested.connect(_on_world_explosion_requested)
		deployed_mines.append(mine)
		update_status("%s 已布设地雷；0.75 秒后武装" % unit.display_name)
		_refresh_inventory_ui()
		return
	update_status("所选队员没有可用地雷")


func issue_formation_move(destination: Vector2) -> void:
	if selected_units.is_empty():
		update_status("请先选择队员")
		return
	if terrain_loaded and navigation_grid == null:
		update_status("当前关卡导航数据不可用，已拒绝可能穿墙的移动命令")
		return
	_play_media_audio("acknowledge", _media_actor_key(selected_units[0].display_name))
	var offsets: Array[Vector2] = []
	for index: int in range(selected_units.size()):
		offsets.append(SIMULATION_SCRIPT.formation_offset(index, selected_units.size()))
	var center: Vector2 = SIMULATION_SCRIPT.clamp_formation_center(
		destination, offsets, movement_bounds
	)
	var planned_count := 0
	for index: int in range(selected_units.size()):
		var unit := selected_units[index]
		if not unit.is_alive:
			continue
		unit.clear_combat_target()
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


func enemy_at_world_point(world_point: Vector2) -> ENEMY_UNIT:
	var nearest: ENEMY_UNIT
	var nearest_distance := 30.0 * 30.0
	for enemy: ENEMY_UNIT in enemies:
		if not enemy.is_alive:
			continue
		var distance := enemy.position.distance_squared_to(world_point)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func explosive_prop_at_world_point(world_point: Vector2) -> Node2D:
	var nearest: Node2D
	var nearest_distance := 30.0 * 30.0
	for prop: Node2D in explosive_props:
		if (
			not is_instance_valid(prop)
			or not prop.has_method("is_combat_alive")
			or not bool(prop.call("is_combat_alive"))
		):
			continue
		var distance := prop.position.distance_squared_to(world_point)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = prop
	return nearest


func issue_attack_order(target: Node2D) -> void:
	if (
		selected_units.is_empty()
		or target == null
		or not target.has_method("is_combat_alive")
		or not bool(target.call("is_combat_alive"))
	):
		update_status("请先选择存活队员和敌方目标")
		return
	var issued := 0
	for unit: SQUAD_UNIT in selected_units:
		if unit.issue_attack(target):
			issued += 1
	var target_name := (
		str(target.display_name)
		if target is ENEMY_UNIT
		else str(target.get("original_display_name"))
	)
	update_status("攻击命令：%d 名队员 → %s" % [issued, target_name])


func _connect_combatant(combatant: Node2D) -> void:
	combatant.attack_started.connect(_on_attack_started)
	combatant.attack_hit.connect(_on_attack_hit)
	combatant.damage_received.connect(_on_damage_received)
	combatant.died.connect(_on_combatant_died)
	combatant.ammo_changed.connect(_on_ammo_changed)
	combatant.projectile_requested.connect(_on_projectile_requested)


func _on_projectile_requested(
	attacker: Node2D,
	target: Node2D,
	profile: Dictionary,
) -> void:
	if projectile_world == null:
		return
	projectile_world.launch_for_weapon(attacker, target, profile)


func _on_projectile_damage_applied(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	damage: int,
) -> void:
	_on_attack_hit(attacker, target, attack_type, damage)


func _on_world_explosion_requested(
	source: Node2D,
	instigator: Node2D,
	world_position: Vector2,
	damage: int,
	horizontal_radius: float,
	vertical_radius: float,
	_source_faction_id: int,
) -> void:
	if horizontal_radius <= 0.0 or vertical_radius <= 0.0 or damage <= 0:
		return
	var candidates: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		candidates.append(unit)
	for escort: ESCORT_UNIT in escorts:
		candidates.append(escort)
	for enemy: ENEMY_UNIT in enemies:
		candidates.append(enemy)
	for prop: Node2D in explosive_props:
		if is_instance_valid(prop):
			candidates.append(prop)
	for candidate: Node2D in candidates:
		if (
			candidate == source
			or not is_instance_valid(candidate)
			or not candidate.has_method("is_combat_alive")
			or not bool(candidate.call("is_combat_alive"))
			or not candidate.has_method("take_damage")
		):
			continue
		var offset := candidate.global_position - world_position
		var normalized_distance := (
			offset.x * offset.x / (horizontal_radius * horizontal_radius)
			+ offset.y * offset.y / (vertical_radius * vertical_radius)
		)
		if normalized_distance <= 1.0:
			candidate.call("take_damage", damage, instigator if instigator != null else source)
	var alert_source: Node2D = instigator
	if alert_source == null or not is_instance_valid(alert_source):
		for unit: SQUAD_UNIT in units:
			if unit.is_alive:
				alert_source = unit
				break
	_on_projectile_exploded(
		alert_source,
		world_position,
		horizontal_radius,
		vertical_radius,
	)


func _on_projectile_exploded(
	attacker: Node2D,
	world_position: Vector2,
	_horizontal_radius: float,
	_vertical_radius: float,
) -> void:
	_play_media_audio("explosion")
	if attacker == null or not is_instance_valid(attacker):
		return
	var alert_target: Node2D = attacker
	if attacker is ENEMY_UNIT:
		var enemy_attacker := attacker as ENEMY_UNIT
		if enemy_attacker.current_target != null:
			alert_target = enemy_attacker.current_target
	var alert_radius: float = COMBAT_PROFILES.alert_radius("attack_extended")
	for enemy: ENEMY_UNIT in enemies:
		if (
			enemy != attacker
			and enemy.is_alive
			and enemy.position.distance_to(world_position) <= alert_radius
		):
			enemy.receive_alert(alert_target, world_position)


func _on_attack_started(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	alert_radius: float,
) -> void:
	var attack_event := str({
		1: "attack_pistol",
		2: "attack_rifle",
		3: "attack_light_machinegun_burst",
		4: "attack_dagger",
		5: "attack_broadsword",
		6: "attack_dart",
		7: "attack_slingshot",
	}.get(attack_type, ""))
	if not attack_event.is_empty():
		_play_media_audio(attack_event)
	if alert_radius <= 0.0 or target == null:
		return
	# A gunshot exposes the shooter to the opposing side.  When an enemy fires,
	# nearby enemies keep the player's target; when a squad member fires, nearby
	# enemies must hunt the squad member rather than their wounded ally.
	var alert_target: Node2D = target if attacker is ENEMY_UNIT else attacker
	if alert_target == null or not alert_target.has_method("is_combat_alive"):
		return
	var alerted_count := 0
	for enemy: ENEMY_UNIT in enemies:
		if (
			enemy == attacker
			or not enemy.is_alive
			or enemy.position.distance_to(attacker.position) > alert_radius
		):
			continue
		if enemy.receive_alert(alert_target, attacker.position):
			alerted_count += 1
	if alerted_count > 0 and not attacker is ENEMY_UNIT:
		_play_media_audio("alert", "japanese_soldier")


func _on_attack_hit(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	damage: int,
) -> void:
	if attack_type in [6, 7]:
		_play_media_audio("projectile_impact")
	if units.has(attacker) and target != null:
		update_status("%s 命中 %s，造成 %d 点伤害" % [
			attacker.display_name,
			_combat_target_display_name(target),
			damage,
		])


func _combat_target_display_name(target: Node2D) -> String:
	if target == null:
		return "目标"
	if target is SQUAD_UNIT:
		return str(target.display_name)
	var original_name: Variant = target.get("original_display_name")
	return str(original_name) if original_name != null and not str(original_name).is_empty() else str(target.name)


func _on_damage_received(
	unit: Node2D,
	_attacker: Node2D,
	_damage: int,
	_remaining_hit_points: int,
) -> void:
	if units.has(unit):
		_refresh_mission_ui()


func _on_ammo_changed(unit: Node2D, magazine: int, reserve: int) -> void:
	if selected_units.has(unit):
		update_status("%s 弹药：%d / %d" % [unit.display_name, magazine, reserve])
		_refresh_inventory_ui()


func _refresh_inventory_ui() -> void:
	if inventory_label == null:
		return
	var lines: Array[String] = []
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_alive:
			continue
		var attack_type := int(unit.weapon_profile.get("attack_type", 0))
		var weapon_name := str(WEAPON_NAMES.get(attack_type, "徒手"))
		var ammo_text := "无限/近战"
		if int(unit.weapon_profile.get("magazine_capacity", 0)) > 0:
			ammo_text = "%d / %d" % [unit.magazine_ammo, unit.reserve_ammo]
		var deployable_text := ""
		var mine_count := unit.ammo_item_count(43)
		if mine_count > 0:
			deployable_text = "｜地雷 %d" % mine_count
		var inventory_line := "%s｜%s｜弹药 %s｜生命 %d/%d" % [
			unit.display_name,
			weapon_name,
			ammo_text,
			unit.current_hit_points,
			unit.maximum_hit_points,
		]
		lines.append(inventory_line + deployable_text)
	var squad_supplies: Array[String] = []
	if int(field_inventory.get("explosives", 0)) > 0:
		squad_supplies.append("炸药 %d" % int(field_inventory["explosives"]))
	if int(field_inventory.get("uniform", 0)) > 0:
		squad_supplies.append("军服 %d" % int(field_inventory["uniform"]))
	if not squad_supplies.is_empty():
		lines.append("小队物资｜" + "｜".join(squad_supplies))
	inventory_label.text = "\n".join(lines)


func _on_combatant_died(unit: Node2D, killer: Node2D) -> void:
	selected_units.erase(unit)
	var death_actor := (
		"enemy" if unit is ENEMY_UNIT else ("civilian" if unit is ESCORT_UNIT else "ally")
	)
	_play_media_audio("death", death_actor)
	var death_alert_radius: float = COMBAT_PROFILES.alert_radius("ally_death")
	if unit is ENEMY_UNIT:
		if killer != null:
			for enemy: ENEMY_UNIT in enemies:
				if (
					enemy != unit
					and enemy.is_alive
					and enemy.position.distance_to(unit.position) <= death_alert_radius
				):
					enemy.receive_alert(killer, unit.position)
		_publish_role_eliminations(unit)
		_spawn_role_drops(unit)
		if _living_enemy_count() == 0:
			_publish_mission_event(
				"area_hostiles_cleared", {"area_role": "m009_station"}
			)
	elif unit is SQUAD_UNIT:
		var required_survivors: Array = current_mission.get("required_survivors", []) as Array
		if not required_survivors.is_empty() and not required_survivors.has(str(unit.display_name)):
			_refresh_mission_ui()
			return
		var payload := {"display_name": str(unit.display_name)}
		if _scene_is_mission_bound(int(unit.scene_index)):
			payload["scene_index"] = int(unit.scene_index)
		_publish_mission_event("required_character_lost", payload)
	_refresh_mission_ui()


func _publish_role_eliminations(unit: Node2D) -> void:
	var scene_index := int(unit.scene_index)
	for raw_objective: Variant in current_mission.get("objectives", []) as Array:
		if not raw_objective is Dictionary:
			continue
		var objective := raw_objective as Dictionary
		var condition: Variant = objective.get("condition")
		if not condition is Dictionary or str((condition as Dictionary).get("event", "")) != "role_eliminated":
			continue
		var where := (condition as Dictionary).get("where", {}) as Dictionary
		var role_id := str(where.get("role_id", ""))
		if role_id.is_empty() or not _binding_scenes(role_id).has(scene_index):
			continue
		_publish_mission_event(
			"role_eliminated", {"scene_index": scene_index, "role_id": role_id}
		)


func _spawn_role_drops(unit: Node2D) -> void:
	var raw_drops: Variant = current_mission.get("role_drops", {})
	if not raw_drops is Dictionary:
		return
	var source_scene := int(unit.scene_index)
	for role_value: Variant in (raw_drops as Dictionary).keys():
		var role_id := str(role_value)
		if not _binding_scenes(role_id).has(source_scene):
			continue
		var raw_payload: Variant = (raw_drops as Dictionary)[role_value]
		if not raw_payload is Dictionary:
			continue
		var payload := (raw_payload as Dictionary).duplicate(true)
		payload["source_scene_index"] = source_scene
		var pickup: MISSION_PICKUP = MISSION_PICKUP.new()
		add_child(pickup)
		pickup.configure(payload, unit.position)
		mission_pickups.append(pickup)


func _living_enemy_count() -> int:
	var count := 0
	for enemy: ENEMY_UNIT in enemies:
		if enemy.is_alive:
			count += 1
	return count


func _configure_mission_runtime() -> void:
	if mission_runtime != null:
		remove_child(mission_runtime)
		mission_runtime.queue_free()
	mission_runtime = MISSION_RUNTIME_SCRIPT.new()
	add_child(mission_runtime)
	mission_runtime.state_changed.connect(_refresh_mission_ui)
	mission_runtime.objective_completed.connect(_on_objective_completed)
	mission_runtime.victory.connect(_on_mission_victory)
	mission_runtime.failed.connect(_on_mission_failed)
	if not mission_runtime.configure(current_mission, imported_level, current_mission_state):
		update_status("任务运行时初始化失败：%s" % mission_runtime.last_error)
	mission_zone_elapsed = 0.0
	_refresh_mission_ui()
	queue_redraw()


func _create_media_director() -> void:
	media_director = MEDIA_DIRECTOR_SCRIPT.new()
	media_director.name = "MediaDirector"
	add_child(media_director)
	media_director.briefing_closed.connect(_on_briefing_closed)


func _create_game_shell() -> void:
	game_shell = GAME_SHELL_SCRIPT.new()
	game_shell.name = "GameShell"
	add_child(game_shell)
	game_shell.resume_requested.connect(_on_shell_resumed)
	game_shell.save_requested.connect(_save_game)
	game_shell.load_requested.connect(_load_game)
	game_shell.restart_requested.connect(_restart_current_level)
	game_shell.quit_requested.connect(_quit_game)
	game_shell.settings_changed.connect(_on_shell_settings_changed)
	game_shell.map_position_requested.connect(_on_map_position_requested)
	game_shell.inventory_cycle_requested.connect(_on_inventory_cycle_requested)
	game_shell.inventory_reload_requested.connect(_on_inventory_reload_requested)
	game_shell.set_settings(runtime_settings)
	_apply_runtime_settings(runtime_settings)


func _initialize_persistence() -> void:
	game_settings = GAME_SETTINGS_SCRIPT.new()
	game_settings.load_from_disk()
	game_settings.apply_audio_to_runtime()
	command_line_controls_display = _command_line_has_display_override()
	if not command_line_controls_display:
		game_settings.apply_display_to_runtime()
	var display: Dictionary = game_settings.display_settings()
	runtime_settings = {
		"fullscreen": str(display.get("mode", "fullscreen")) != "windowed",
		"display_mode": str(display.get("mode", "fullscreen")),
		"subtitles": bool(game_settings.interface_enabled("subtitles")),
		"show_briefings": bool(game_settings.interface_enabled("show_briefings")),
		"edge_scroll": bool(game_settings.interface_enabled("edge_scroll")),
		"master_volume": float(game_settings.audio_volume("master")),
	}
	save_store = GAME_SAVE_STORE_SCRIPT.new()
	campaign_progress = GAME_SAVE_STORE_SCRIPT.default_campaign()
	var latest_slot := _latest_save_slot()
	if not latest_slot.is_empty():
		var latest_result: Dictionary = save_store.load_slot(latest_slot)
		if bool(latest_result.get("ok", false)):
			var latest_document := latest_result.get("data", {}) as Dictionary
			campaign_progress = (
				(latest_document.get("campaign", campaign_progress) as Dictionary)
				.duplicate(true)
			)


func _command_line_has_display_override() -> bool:
	for argument: String in OS.get_cmdline_args():
		if argument in ["--windowed", "--fullscreen", "--maximized"]:
			return true
		if argument.contains("runtime_probe.gd"):
			return true
	return false


func _on_shell_resumed() -> void:
	update_status("继续任务")


func _restart_current_level() -> void:
	switch_level(current_level_index)
	update_status("本关已重新开始")


func _quit_game() -> void:
	get_tree().quit()


func _on_shell_settings_changed(new_settings: Dictionary) -> void:
	var fullscreen := bool(new_settings.get("fullscreen", true))
	new_settings["display_mode"] = "fullscreen" if fullscreen else "windowed"
	runtime_settings = new_settings.duplicate(true)
	command_line_controls_display = false
	if game_settings != null:
		game_settings.set_audio_volume(
			"master", float(runtime_settings.get("master_volume", 0.8))
		)
		game_settings.set_display_mode(str(runtime_settings["display_mode"]))
		game_settings.set_resolution_policy("desktop")
		game_settings.set_interface_enabled(
			"subtitles", bool(runtime_settings.get("subtitles", true))
		)
		game_settings.set_interface_enabled(
			"show_briefings", bool(runtime_settings.get("show_briefings", true))
		)
		game_settings.set_interface_enabled(
			"edge_scroll", bool(runtime_settings.get("edge_scroll", true))
		)
		game_settings.save_to_disk()
	_apply_runtime_settings(runtime_settings)
	update_status("设置已应用")


func _apply_runtime_settings(new_settings: Dictionary) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		var volume := clampf(float(new_settings.get("master_volume", 0.8)), 0.0, 1.0)
		AudioServer.set_bus_mute(master_bus, volume <= 0.0001)
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(volume, 0.0001)))
	if media_director != null and media_director.has_method("set_subtitles_enabled"):
		media_director.set_subtitles_enabled(bool(new_settings.get("subtitles", true)))
	if DisplayServer.get_name() == "headless" or command_line_controls_display:
		return
	var display_mode := str(new_settings.get(
		"display_mode", "fullscreen" if bool(new_settings.get("fullscreen", false)) else "windowed"
	))
	DisplayServer.window_set_flag(
		DisplayServer.WINDOW_FLAG_BORDERLESS, display_mode == "borderless"
	)
	if display_mode == "fullscreen":
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif display_mode == "borderless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		var was_windowed := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
		if not was_windowed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var window_size := Vector2i(1280, 720)
		DisplayServer.window_set_size(window_size)
		var screen := DisplayServer.window_get_current_screen()
		var screen_position := DisplayServer.screen_get_position(screen)
		var screen_size := DisplayServer.screen_get_size(screen)
		DisplayServer.window_set_position(screen_position + (screen_size - window_size) / 2)


func _open_pause_menu() -> void:
	if game_shell == null:
		return
	if media_director != null and media_director.has_method("is_modal_active"):
		if bool(media_director.is_modal_active()):
			return
	game_shell.show_pause_menu(_has_save_slot())


func _open_tactical_map() -> void:
	if game_shell == null:
		return
	var terrain_texture: Texture2D
	var terrain_node := get_node_or_null("ImportedTerrain")
	if terrain_node is Sprite2D:
		terrain_texture = (terrain_node as Sprite2D).texture
	game_shell.show_tactical_map(
		terrain_texture,
		world_size,
		_tactical_actor_markers(),
		_tactical_mission_markers(),
		_camera_world_rect(),
	)


func _open_inventory() -> void:
	if game_shell != null:
		game_shell.show_inventory(_inventory_bbcode())


func _on_map_position_requested(world_position: Vector2) -> void:
	if level_camera == null:
		return
	level_camera.position = world_position
	clamp_level_camera()
	if game_shell != null:
		game_shell.update_map_camera(_camera_world_rect())


func _on_inventory_cycle_requested(direction: int) -> void:
	_cycle_selected_weapons(direction)
	if game_shell != null:
		game_shell.update_inventory(_inventory_bbcode())


func _on_inventory_reload_requested() -> void:
	var reload_count := 0
	for unit: SQUAD_UNIT in selected_units:
		if unit.request_reload():
			reload_count += 1
	update_status("%d 名队员开始换弹" % reload_count)
	if game_shell != null:
		game_shell.update_inventory(_inventory_bbcode())


func _camera_world_rect() -> Rect2:
	if level_camera == null:
		return Rect2()
	var visible_size := get_viewport_rect().size / maxf(level_camera.zoom.x, 0.001)
	return Rect2(level_camera.position - visible_size * 0.5, visible_size)


func _tactical_actor_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	for unit: SQUAD_UNIT in units:
		if unit.is_alive:
			markers.append({
				"position": unit.position,
				"color": Color(0.28, 0.72, 1.0),
				"radius": 5.0,
				"selected": selected_units.has(unit),
			})
	for escort: ESCORT_UNIT in escorts:
		if escort.is_alive:
			markers.append({
				"position": escort.position,
				"color": Color(0.88, 0.82, 0.35) if not escort.rescued_state else Color(0.36, 0.82, 0.78),
				"radius": 4.0,
			})
	for enemy: ENEMY_UNIT in enemies:
		if enemy.is_alive:
			markers.append({
				"position": enemy.position,
				"color": Color(0.92, 0.28, 0.22),
				"radius": 3.5,
			})
	return markers


func _tactical_mission_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var raw_bindings: Variant = current_mission.get("scene_bindings", {})
	if not raw_bindings is Dictionary:
		return markers
	for binding_value: Variant in (raw_bindings as Dictionary).keys():
		var binding_kind := str(binding_value)
		if not _binding_has_world_marker(binding_kind):
			continue
		for scene_index: int in _binding_scenes(binding_kind):
			if not world_entities_by_scene.has(scene_index):
				continue
			var entity := world_entities_by_scene[scene_index] as Dictionary
			var color := Color(0.98, 0.66, 0.18)
			if binding_kind == "exit":
				color = Color(0.28, 0.92, 0.44)
			elif binding_kind == "high_ground":
				color = Color(0.30, 0.72, 1.0)
			if activated_mission_scenes.has(scene_index):
				color = Color(0.48, 0.52, 0.48)
			markers.append({
				"position": Vector2(float(entity["x"]), float(entity["y"])),
				"color": color,
				"radius": 6.0,
			})
	return markers


func _inventory_bbcode() -> String:
	var lines := PackedStringArray()
	lines.append("[color=#e7d89a][b]当前关卡：%s　选中队员：%d[/b][/color]" % [str(current_mission.get("title", "")), selected_units.size()])
	lines.append("")
	for unit: SQUAD_UNIT in units:
		var selected_text := " [color=#fff3a8]● 已选中[/color]" if selected_units.has(unit) else ""
		var state_text := "阵亡" if not unit.is_alive else "生命 %d/%d" % [unit.current_hit_points, unit.maximum_hit_points]
		var attack_type := int(unit.weapon_profile.get("attack_type", 0))
		lines.append("[b]%s[/b]%s　%s　当前：%s" % [
			unit.display_name,
			selected_text,
			state_text,
			str(WEAPON_NAMES.get(attack_type, "徒手")),
		])
		if unit.combat_inventory != null:
			var weapon_parts := PackedStringArray()
			for action_key: String in unit.combat_inventory.registered_weapon_keys():
				var weapon_state: Dictionary = unit.combat_inventory.weapon_state(action_key)
				var profile := weapon_state.get("profile", {}) as Dictionary
				var weapon_name := str(WEAPON_NAMES.get(int(profile.get("attack_type", 0)), action_key))
				var ammunition := ""
				if int(weapon_state.get("magazine_capacity", 0)) > 0:
					ammunition = " %d/%d" % [int(weapon_state.get("magazine", 0)), int(weapon_state.get("reserve", 0))]
				weapon_parts.append(weapon_name + ammunition)
			if not weapon_parts.is_empty():
				lines.append("　武器：" + "　｜　".join(weapon_parts))
		var item_parts := PackedStringArray()
		for raw_item_id: Variant in INVENTORY_ITEM_NAMES.keys():
			var item_id := int(raw_item_id)
			var count := unit.ammo_item_count(item_id)
			if count > 0:
				item_parts.append("%s × %d" % [str(INVENTORY_ITEM_NAMES[item_id]), count])
		lines.append("　物品：%s" % ("无" if item_parts.is_empty() else "　｜　".join(item_parts)))
		lines.append("")
	var shared_parts := PackedStringArray()
	for raw_key: Variant in field_inventory.keys():
		var quantity := int(field_inventory[raw_key])
		if quantity > 0:
			shared_parts.append("%s × %d" % [str(raw_key), quantity])
	lines.append("[color=#9fd6a0][b]小队任务物资：[/b][/color]%s" % ("无" if shared_parts.is_empty() else "　｜　".join(shared_parts)))
	lines.append("[color=#aeb7a8]提示：先在地图上选中队员，再在本界面切换武器或换弹；数字键 1–8 与 Tab 仍可快速操作。[/color]")
	return "\n".join(lines)


func _has_save_slot() -> bool:
	return not _latest_save_slot().is_empty()


func _latest_save_slot() -> String:
	if save_store == null:
		return ""
	var slots: Array[Dictionary] = save_store.list_slots()
	if slots.is_empty():
		return ""
	slots.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_time := int(first.get("saved_at_unix", 0))
			var second_time := int(second.get("saved_at_unix", 0))
			if first_time == second_time:
				var first_slot := str(first.get("slot_id", ""))
				var second_slot := str(second.get("slot_id", ""))
				if first_slot != second_slot:
					return first_slot == QUICK_SAVE_SLOT
				return int(first.get("revision", 0)) > int(second.get("revision", 0))
			return first_time > second_time
	)
	return str(slots[0].get("slot_id", ""))


func _save_game(slot_id: String = QUICK_SAVE_SLOT, announce: bool = true) -> bool:
	if save_store == null or current_mission_state == null:
		if announce:
			_show_save_feedback("存档系统尚未初始化")
		return false
	if current_mission_state.is_failed():
		if announce:
			_show_save_feedback("任务失败状态不能覆盖有效存档，请重玩或读取")
		return false
	var session: Dictionary = GAME_SESSION_STATE_SCRIPT.capture(self)
	var result: Dictionary = save_store.save_slot(slot_id, session, campaign_progress)
	if not bool(result.get("ok", false)):
		if announce:
			_show_save_feedback("保存失败：%s" % str(result.get("message", "未知错误")))
		return false
	if announce:
		_show_save_feedback("进度已保存：%s" % str(current_mission.get("title", session.get("level_id", ""))))
	return true


func _load_game() -> bool:
	if save_store == null:
		_show_load_feedback("存档系统尚未初始化")
		return false
	var slot_id := _latest_save_slot()
	if slot_id.is_empty():
		_show_load_feedback("没有可读取的存档")
		return false
	var result: Dictionary = save_store.load_slot(slot_id)
	if not bool(result.get("ok", false)):
		_show_load_feedback("读取失败：%s" % str(result.get("message", "存档损坏")))
		return false
	var document := result.get("data", {}) as Dictionary
	var session := document.get("session", {}) as Dictionary
	var level_id := str(session.get("level_id", ""))
	var level_index := FORMAL_LEVEL_IDS.find(level_id)
	if level_index < 0:
		_show_load_feedback("读取失败：存档关卡编号无效")
		return false
	if game_shell != null:
		game_shell.close_for_state_change()
	switch_level(level_index, false)
	var applied: Dictionary = GAME_SESSION_STATE_SCRIPT.apply_after_level_loaded(self, session)
	if not bool(applied.get("ok", false)):
		_show_load_feedback("读取失败：无法恢复关卡状态")
		return false
	campaign_progress = (
		(document.get("campaign", GAME_SAVE_STORE_SCRIPT.default_campaign()) as Dictionary)
		.duplicate(true)
	)
	var warnings := applied.get("warnings", []) as Array
	if current_mission_state.is_failed():
		_on_mission_failed(str(current_mission_state.failure_id))
	elif current_mission_state.is_victory():
		update_status("存档已恢复：本关任务已完成，可进入下一关")
	else:
		update_status(
			"存档已恢复%s" % ("" if warnings.is_empty() else "（%d 项内容降级）" % warnings.size())
		)
	return true


func _show_save_feedback(message: String) -> void:
	update_status(message)
	if game_shell != null and game_shell.is_overlay_open():
		game_shell.set_menu_message(message)


func _show_load_feedback(message: String) -> void:
	update_status(message)
	if game_shell != null and game_shell.is_overlay_open():
		game_shell.set_menu_message(message)


func _update_campaign_progress_for_victory() -> void:
	var level_id := str(current_mission.get("id", ""))
	if not FORMAL_LEVEL_IDS.has(level_id):
		return
	if campaign_progress.is_empty():
		campaign_progress = GAME_SAVE_STORE_SCRIPT.default_campaign()
	var completed: Array = campaign_progress.get("completed_level_ids", []) as Array
	if not completed.has(level_id):
		completed.append(level_id)
	completed.sort()
	campaign_progress["completed_level_ids"] = completed
	var next_index := mini(FORMAL_LEVEL_IDS.find(level_id) + 1, FORMAL_LEVEL_IDS.size() - 1)
	var current_highest := str(campaign_progress.get("highest_unlocked_level_id", "m000"))
	var current_highest_index := maxi(FORMAL_LEVEL_IDS.find(current_highest), 0)
	campaign_progress["highest_unlocked_level_id"] = FORMAL_LEVEL_IDS[maxi(next_index, current_highest_index)]


func _publish_mission_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
	if mission_runtime == null or not mission_runtime.is_configured():
		return []
	var completed: Array[String] = mission_runtime.publish_world_event(event_name, payload)
	if not mission_runtime.last_error.is_empty():
		push_warning("任务事件被拒绝：%s" % mission_runtime.last_error)
	elif event_name == "story_anchor_reached" and not completed.is_empty():
		_play_mission_media_cue("on_story_anchor", str(payload.get("role_id", "")))
	return completed


func _on_objective_completed(objective_id: String) -> void:
	_play_media_audio("ui_confirm")
	update_status("任务目标完成：%s" % objective_id)
	_play_mission_media_cue("on_objective", objective_id)


func _on_mission_victory() -> void:
	_play_media_audio("ui_confirm")
	_update_campaign_progress_for_victory()
	_save_game(AUTO_SAVE_SLOT, false)
	update_status("任务完成！按 PageDown 进入下一关，或按 R 重玩。")
	_refresh_mission_ui()
	_play_mission_media_cue("on_victory")


func _on_briefing_closed(level_id: String) -> void:
	if str(current_mission.get("id", "")) == level_id:
		_play_mission_media_cue("on_start")


func _play_mission_media_cue(section: String, key: String = "") -> bool:
	if media_director == null:
		return false
	var cue := _mission_media_cue(section, key)
	if cue.is_empty():
		return false
	match str(cue.get("kind", "")):
		"audio":
			media_event_seed += 1
			return bool(
				media_director.play_audio_event(
					str(cue.get("event_key", "")),
					str(cue.get("actor_key", "")),
					media_event_seed + int(cue.get("variant_offset", 0)),
					str(cue.get("caption", "")),
				)
			)
		"dialogue":
			return bool(
				media_director.start_dialogue(
					str(cue.get("sequence_id", "")),
					(cue.get("lines", []) as Array).duplicate(true),
				)
			)
		"movie":
			return bool(media_director.play_movie(str(cue.get("movie_id", ""))))
		"ending":
			var target_width := 1024
			if is_inside_tree():
				target_width = maxi(int(get_viewport_rect().size.x), 1)
			return bool(
				media_director.show_ending(
					target_width,
					str(cue.get("fallback_text", "任务完成")),
				)
			)
	return false


func _mission_media_cue(section: String, key: String = "") -> Dictionary:
	var raw_media_cues: Variant = current_mission.get("media_cues", {})
	if not raw_media_cues is Dictionary:
		return {}
	var raw_section: Variant = (raw_media_cues as Dictionary).get(section, {})
	if section in ["on_start", "on_victory"]:
		return (raw_section as Dictionary).duplicate(true) if raw_section is Dictionary else {}
	if not raw_section is Dictionary or key.is_empty():
		return {}
	var raw_cue: Variant = (raw_section as Dictionary).get(key, {})
	return (raw_cue as Dictionary).duplicate(true) if raw_cue is Dictionary else {}


func _on_mission_failed(failure_id: String) -> void:
	update_status("任务失败：%s。按 R 重新开始。" % failure_id)
	_refresh_mission_ui()
	if game_shell != null:
		game_shell.show_failure("任务失败：%s\n可重新开始本关，或读取最近存档。" % failure_id, _has_save_slot())


func _refresh_mission_ui() -> void:
	if objective_label == null or current_mission_state == null:
		return
	var lines: Array[String] = current_mission_state.display_lines()
	if current_mission_state.is_victory():
		lines.append("★ 任务完成")
	elif current_mission_state.is_failed():
		lines.append("× 任务失败：%s" % current_mission_state.failure_id)
	objective_label.text = "\n".join(lines)


func _on_escort_rescued(escort: Node2D, rescuer: Node2D) -> void:
	var payload := {
		"scene_index": int(escort.scene_index),
		"display_name": str(escort.display_name),
	}
	if str(escort.display_name) in ["铁蛋爹", "铁蛋娘"]:
		payload["family_role"] = "tiedan_parents"
	_publish_mission_event("entity_rescued", payload)
	update_status("已营救 %s，请护送其完成任务" % escort.display_name)
	_play_media_audio("ui_confirm")
	if rescuer != null:
		escort.set_follow_target(rescuer)


func interact_with_mission_world() -> void:
	var origins := _interaction_origins()
	if origins.is_empty():
		update_status("没有可执行交互的存活队员")
		return
	var nearest_escort: ESCORT_UNIT
	var nearest_distance := INF
	var nearest_rescuer: SQUAD_UNIT
	for escort: ESCORT_UNIT in escorts:
		if escort.rescued_state or not escort.is_alive:
			continue
		for origin: SQUAD_UNIT in origins:
			var distance := origin.position.distance_to(escort.position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_escort = escort
				nearest_rescuer = origin
	if nearest_escort != null and nearest_distance <= MISSION_INTERACTION_RADIUS:
		nearest_escort.rescue(nearest_rescuer)
		return

	var nearest_pickup: MISSION_PICKUP
	nearest_distance = INF
	for pickup: MISSION_PICKUP in mission_pickups:
		if pickup.collected:
			continue
		var distance := _nearest_origin_distance(origins, pickup.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_pickup = pickup
	if nearest_pickup != null and nearest_distance <= MISSION_INTERACTION_RADIUS:
		var payload := nearest_pickup.collect()
		_publish_mission_event("item_acquired", payload)
		update_status("已取得任务物品")
		return

	var nearest_field_pickup: Node2D
	var nearest_field_collector: SQUAD_UNIT
	nearest_distance = INF
	for pickup: Node2D in field_pickups:
		if not is_instance_valid(pickup) or bool(pickup.get("consumed")):
			continue
		for origin: SQUAD_UNIT in origins:
			if not pickup.can_collect(origin) or not _collector_can_use_field_pickup(origin, pickup):
				continue
			var distance := origin.position.distance_to(pickup.position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_field_pickup = pickup
				nearest_field_collector = origin
	if nearest_field_pickup != null and nearest_field_collector != null:
		var field_payload: Dictionary = nearest_field_pickup.collect(nearest_field_collector)
		if not field_payload.is_empty():
			field_pickups.erase(nearest_field_pickup)
			_apply_field_pickup(field_payload, nearest_field_collector)
			return

	var best_scene := -1
	var best_binding := ""
	nearest_distance = INF
	for binding_value: Variant in (current_mission.get("scene_bindings", {}) as Dictionary).keys():
		var binding_kind := str(binding_value)
		if not _binding_is_interactive(binding_kind):
			continue
		for scene_index: int in _binding_scenes(binding_kind):
			if (
				activated_mission_scenes.has(scene_index)
				or not world_entities_by_scene.has(scene_index)
			):
				continue
			var entity := world_entities_by_scene[scene_index] as Dictionary
			var world_position := Vector2(float(entity["x"]), float(entity["y"]))
			var distance := _nearest_origin_distance(origins, world_position)
			if distance < nearest_distance:
				nearest_distance = distance
				best_scene = scene_index
				best_binding = binding_kind
	if best_scene >= 0 and nearest_distance <= MISSION_INTERACTION_RADIUS:
		if _activate_bound_scene(best_binding, best_scene):
			return
	update_status("附近没有可交互任务目标")


func _collector_can_use_field_pickup(collector: SQUAD_UNIT, pickup: Node2D) -> bool:
	var grant: Dictionary = pickup.get("grant") as Dictionary
	if str(grant.get("kind", "")) == "healing":
		return collector.current_hit_points < collector.maximum_hit_points
	if str(grant.get("kind", "")) == "active_weapon_ammunition":
		return collector.preferred_finite_ammo_item_id() > 0
	return true


func _apply_field_pickup(payload: Dictionary, collector: SQUAD_UNIT) -> void:
	var grant := payload.get("grant", {}) as Dictionary
	var grant_kind := str(grant.get("kind", ""))
	var quantity := maxi(int(grant.get("quantity", 1)), 1)
	var description := str(payload.get("original_display_name", "物品"))
	match grant_kind:
		"weapon":
			var action_key := str(grant.get("action_key", ""))
			var profile: Dictionary = COMBAT_PROFILES.weapon_profile(action_key)
			if profile.is_empty():
				return
			if collector.has_inventory_weapon(action_key):
				collector.add_ammo_item(
					int(profile.get("ammo_item_id", 0)),
					maxi(int(profile.get("starting_reserve_ammo", 0)), 1),
				)
				collector.equip_inventory_weapon(action_key)
			else:
				collector.register_inventory_weapon(
					profile,
					_attack_groups_for_unit(collector, action_key),
					true,
					true,
				)
		"ammunition":
			var action_key := str(grant.get("action_key", ""))
			var profile: Dictionary = COMBAT_PROFILES.weapon_profile(action_key)
			if not profile.is_empty() and not collector.has_inventory_weapon(action_key):
				collector.register_inventory_weapon(
					profile,
					_attack_groups_for_unit(collector, action_key),
					false,
					true,
				)
			collector.add_ammo_item(int(grant.get("item_id", 0)), quantity)
		"active_weapon_ammunition":
			collector.add_ammo_item(collector.preferred_finite_ammo_item_id(), quantity)
		"deployable":
			collector.add_ammo_item(int(grant.get("item_id", 43)), quantity)
		"mission_item":
			var item_key := str(grant.get("item_key", ""))
			field_inventory[item_key] = int(field_inventory.get(item_key, 0)) + quantity
			if item_key == "uniform":
				var source_scene_index := int(payload.get("scene_index", -1))
				_publish_mission_event(
					"item_acquired",
					{
						"item_name": "日军军服",
						"source_scene_index": source_scene_index,
					},
				)
				_mark_field_pickup_binding_activated(source_scene_index)
		"healing":
			var healed := collector.heal(int(grant.get("healing_hit_points", 0)))
			description += "（恢复 %d 点生命）" % healed
		_:
			return
	_play_media_audio("ui_confirm")
	update_status("%s 拾取 %s" % [collector.display_name, description])
	_refresh_inventory_ui()


func _attack_groups_for_unit(unit: SQUAD_UNIT, action_key: String) -> Array[Dictionary]:
	if not playable_entities.has(unit.display_name):
		return []
	return load_entity_action_groups(
		playable_entities[unit.display_name] as Dictionary,
		action_key,
	)


func _activate_bound_scene(binding_kind: String, scene_index: int) -> bool:
	if activated_mission_scenes.has(scene_index):
		return true
	if binding_kind == "exit":
		_evaluate_exit_scene(scene_index)
		return true
	var raw_pickups: Variant = current_mission.get("pickup_bindings", {})
	if raw_pickups is Dictionary and (raw_pickups as Dictionary).has(binding_kind):
		var payload := ((raw_pickups as Dictionary)[binding_kind] as Dictionary).duplicate(true)
		payload["source_scene_index"] = scene_index
		_publish_mission_event("item_acquired", payload)
		activated_mission_scenes[scene_index] = true
		queue_redraw()
		return true
	if binding_kind == "explosion":
		if activated_mission_scenes.has(scene_index):
			return true
		var charge_policy := _current_charge_policy()
		var charge_mode := str(charge_policy.get("mode", "preplanted"))
		var inventory_item_key := str(
			charge_policy.get("inventory_item_key", "explosives")
		)
		var quantity_per_target := maxi(
			int(charge_policy.get("quantity_per_target", 1)), 1
		)
		if charge_mode == "inventory_required":
			if int(field_inventory.get(inventory_item_key, 0)) < quantity_per_target:
				update_status("该任务点需要 %d 个炸药" % quantity_per_target)
				return false
		elif charge_mode != "preplanted":
			update_status("任务爆破策略无效，无法激活任务点")
			return false
		if mission_runtime == null or not mission_runtime.is_configured():
			return false
		_publish_mission_event(
			"trigger_activated",
			{"scene_index": scene_index, "display_name": "检测爆炸精灵"},
		)
		if not mission_runtime.last_error.is_empty():
			return false
		if charge_mode == "inventory_required":
			field_inventory[inventory_item_key] = (
				int(field_inventory.get(inventory_item_key, 0)) - quantity_per_target
			)
		_play_media_audio("explosion")
		_refresh_inventory_ui()
		activated_mission_scenes[scene_index] = true
		update_status("已激活任务点 %d" % scene_index)
		queue_redraw()
		return true
	for raw_objective: Variant in current_mission.get("objectives", []) as Array:
		var objective := raw_objective as Dictionary
		var condition := objective.get("condition", {}) as Dictionary
		if (
			str(condition.get("event", "")) == "story_anchor_reached"
			and str((condition.get("where", {}) as Dictionary).get("role_id", "")) == binding_kind
		):
			_publish_mission_event(
				"story_anchor_reached",
				{"scene_index": scene_index, "role_id": binding_kind},
			)
			activated_mission_scenes[scene_index] = true
			queue_redraw()
			return true
	return false


func _current_charge_policy() -> Dictionary:
	var raw_policy: Variant = current_mission.get("charge_policy", {})
	if raw_policy is Dictionary and not (raw_policy as Dictionary).is_empty():
		return raw_policy as Dictionary
	# Optional policy defaults conservatively to a preplanted task anchor. This
	# never consumes a backpack item merely because one happens to be present.
	return {
		"mode": "preplanted",
		"inventory_item_key": "explosives",
		"quantity_per_target": 1,
	}


func _mark_field_pickup_binding_activated(scene_index: int) -> void:
	if scene_index < 0:
		return
	var raw_pickup_bindings: Variant = current_mission.get("pickup_bindings", {})
	if not raw_pickup_bindings is Dictionary:
		return
	for binding_value: Variant in (raw_pickup_bindings as Dictionary).keys():
		if _binding_scenes(str(binding_value)).has(scene_index):
			activated_mission_scenes[scene_index] = true
			queue_redraw()
			return


func _detonate_mission_charges() -> void:
	if str(current_mission.get("id", "")) != "m008":
		update_status("当前任务没有可手动引爆的矿坑炸药")
		return
	_publish_mission_event("explosion", {"cause": "manual_detonation"})
	_play_media_audio("explosion")
	if current_mission_state.is_failed():
		return
	update_status("炸药已引爆；前往东南升降机撤离")


func _binding_is_interactive(binding_kind: String) -> bool:
	if binding_kind in ["exit", "explosion"]:
		return true
	var raw_pickups: Variant = current_mission.get("pickup_bindings", {})
	if raw_pickups is Dictionary and (raw_pickups as Dictionary).has(binding_kind):
		return true
	for raw_objective: Variant in current_mission.get("objectives", []) as Array:
		if not raw_objective is Dictionary:
			continue
		var condition := (raw_objective as Dictionary).get("condition", {}) as Dictionary
		if (
			str(condition.get("event", "")) == "story_anchor_reached"
			and str((condition.get("where", {}) as Dictionary).get("role_id", "")) == binding_kind
		):
			return true
	return false


func _binding_has_world_marker(binding_kind: String) -> bool:
	return binding_kind == "high_ground" or _binding_is_interactive(binding_kind)


func _evaluate_transient_mission_zones() -> void:
	for scene_index: int in _binding_scenes("exit"):
		_evaluate_exit_scene(scene_index)
	_evaluate_simultaneous_zone_rule()


func _evaluate_simultaneous_zone_rule() -> void:
	var raw_rule: Variant = current_mission.get("simultaneous_zone_rule", {})
	if (
		not raw_rule is Dictionary
		or mission_runtime == null
		or not mission_runtime.is_configured()
		or current_mission_state == null
		or current_mission_state.is_failed()
		or current_mission_state.is_victory()
	):
		return
	var rule := raw_rule as Dictionary
	if bool(rule.get("requires_hostiles_cleared", false)) and _living_enemy_count() > 0:
		return
	var binding_kind := str(rule.get("binding", ""))
	var zone_scenes: Array[int] = _binding_scenes(binding_kind)
	if zone_scenes.is_empty():
		return
	var eligible_names: Array = rule.get("eligible_player_names", []) as Array
	var radius := float(rule.get("radius_world", 0.0))
	var candidate_indices_by_zone: Array = []
	for scene_index: int in zone_scenes:
		if not world_entities_by_scene.has(scene_index):
			return
		var entity := world_entities_by_scene[scene_index] as Dictionary
		var zone_position := Vector2(float(entity["x"]), float(entity["y"]))
		var candidates: Array[int] = []
		for unit_index: int in range(units.size()):
			var unit := units[unit_index]
			if (
				unit.is_alive
				and eligible_names.has(str(unit.display_name))
				and unit.position.distance_to(zone_position) <= radius
			):
				candidates.append(unit_index)
		if candidates.is_empty():
			return
		candidate_indices_by_zone.append(candidates)
	if (
		bool(rule.get("distinct_occupants", true))
		and not _can_assign_distinct_zone_occupants(candidate_indices_by_zone, 0, {})
	):
		return
	_publish_mission_event(
		str(rule.get("event", "simultaneous_zones_occupied")),
		{
			"zone_role": str(rule.get("zone_role", "")),
			"occupied_scene_indices": zone_scenes.duplicate(),
		},
	)


func _can_assign_distinct_zone_occupants(
	candidates_by_zone: Array,
	zone_index: int,
	used_unit_indices: Dictionary,
) -> bool:
	if zone_index >= candidates_by_zone.size():
		return true
	for unit_index: int in candidates_by_zone[zone_index] as Array[int]:
		if used_unit_indices.has(unit_index):
			continue
		used_unit_indices[unit_index] = true
		if _can_assign_distinct_zone_occupants(
			candidates_by_zone, zone_index + 1, used_unit_indices
		):
			return true
		used_unit_indices.erase(unit_index)
	return false


func _evaluate_exit_scene(scene_index: int) -> void:
	if activated_mission_scenes.has(scene_index) or not world_entities_by_scene.has(scene_index):
		return
	var entity := world_entities_by_scene[scene_index] as Dictionary
	var exit_position := Vector2(float(entity["x"]), float(entity["y"]))
	if not _required_exit_party_is_present(exit_position):
		return
	var payload := {
		"scene_index": scene_index,
		"trigger_scene_index": scene_index,
		"display_name": "检测出口精灵",
	}
	var completed := _publish_mission_event("trigger_activated", payload)
	completed.append_array(_publish_mission_event("party_at_trigger", payload))
	if not completed.is_empty() or current_mission_state.is_victory():
		activated_mission_scenes[scene_index] = true
		queue_redraw()


func _required_exit_party_is_present(exit_position: Vector2) -> bool:
	var raw_rules: Variant = current_mission.get("exit_party", {})
	var rules := raw_rules as Dictionary if raw_rules is Dictionary else {}
	var raw_player_names: Variant = rules.get("player_names", [])
	if raw_player_names is Array and not (raw_player_names as Array).is_empty():
		for name_value: Variant in raw_player_names as Array:
			var required_name := str(name_value)
			var found_player := false
			for unit: SQUAD_UNIT in units:
				if unit.display_name != required_name:
					continue
				found_player = (
					unit.is_alive
					and unit.position.distance_to(exit_position) <= MISSION_INTERACTION_RADIUS
				)
				break
			if not found_player:
				return false
	else:
		var living_players := 0
		for unit: SQUAD_UNIT in units:
			if not unit.is_alive:
				continue
			living_players += 1
			if unit.position.distance_to(exit_position) > MISSION_INTERACTION_RADIUS:
				return false
		if living_players == 0:
			return false

	var required_escort_scenes: Array[int] = []
	var raw_escort_bindings: Variant = rules.get("escort_bindings", [])
	if raw_escort_bindings is Array and not (raw_escort_bindings as Array).is_empty():
		for binding_value: Variant in raw_escort_bindings as Array:
			for bound_scene: int in _binding_scenes(str(binding_value)):
				if not required_escort_scenes.has(bound_scene):
					required_escort_scenes.append(bound_scene)
	else:
		for escort: ESCORT_UNIT in escorts:
			required_escort_scenes.append(escort.scene_index)
	for required_scene: int in required_escort_scenes:
		var found_escort := false
		for escort: ESCORT_UNIT in escorts:
			if escort.scene_index != required_scene:
				continue
			found_escort = (
				escort.is_alive
				and escort.rescued_state
				and escort.position.distance_to(exit_position) <= MISSION_INTERACTION_RADIUS
			)
			break
		if not found_escort:
			return false
	return true


func _interaction_origins() -> Array[SQUAD_UNIT]:
	var origins: Array[SQUAD_UNIT] = []
	for unit: SQUAD_UNIT in selected_units:
		if unit.is_alive:
			origins.append(unit)
	if origins.is_empty():
		for unit: SQUAD_UNIT in units:
			if unit.is_alive:
				origins.append(unit)
	return origins


func _nearest_origin_distance(origins: Array[SQUAD_UNIT], world_position: Vector2) -> float:
	var nearest := INF
	for origin: SQUAD_UNIT in origins:
		nearest = minf(nearest, origin.position.distance_to(world_position))
	return nearest


func _binding_scenes(binding_kind: String) -> Array[int]:
	var result: Array[int] = []
	var raw_bindings: Variant = current_mission.get("scene_bindings", {})
	if not raw_bindings is Dictionary:
		return result
	var raw_scenes: Variant = (raw_bindings as Dictionary).get(binding_kind, [])
	if not raw_scenes is Array:
		return result
	for scene_value: Variant in raw_scenes as Array:
		result.append(int(scene_value))
	return result


func _scene_is_mission_bound(scene_index: int) -> bool:
	if scene_index < 0:
		return false
	var raw_bindings: Variant = current_mission.get("scene_bindings", {})
	if not raw_bindings is Dictionary:
		return false
	for binding_value: Variant in (raw_bindings as Dictionary).values():
		if binding_value is Array and (binding_value as Array).has(scene_index):
			return true
	return false


func _rescue_bound_scenes() -> Array[int]:
	var result: Array[int] = []
	for binding_kind: String in ["rescued", "driver", "reporter", "father", "mother"]:
		for scene_index: int in _binding_scenes(binding_kind):
			if not result.has(scene_index):
				result.append(scene_index)
	return result


func _is_rescue_bound_scene(scene_index: int) -> bool:
	return _rescue_bound_scenes().has(scene_index)


func _is_mission_combat_target_scene(scene_index: int) -> bool:
	for raw_objective: Variant in current_mission.get("objectives", []) as Array:
		if not raw_objective is Dictionary:
			continue
		var condition := (raw_objective as Dictionary).get("condition", {}) as Dictionary
		if str(condition.get("event", "")) != "role_eliminated":
			continue
		var role_id := str((condition.get("where", {}) as Dictionary).get("role_id", ""))
		if _binding_scenes(role_id).has(scene_index):
			return true
	var raw_drops: Variant = current_mission.get("role_drops", {})
	if raw_drops is Dictionary:
		for role_value: Variant in (raw_drops as Dictionary).keys():
			if _binding_scenes(str(role_value)).has(scene_index):
				return true
	return false


func update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _play_media_audio(event_key: String, actor_key: String = "") -> bool:
	if media_director == null or event_key.is_empty():
		return false
	media_event_seed += 1
	return bool(media_director.play_audio_event(event_key, actor_key, media_event_seed))


func _media_actor_key(actor_name: String) -> String:
	return str({
		"大牛": "daniu",
		"古明": "guming",
		"老赵": "laozhao",
		"强子": "qiangzi",
		"铁蛋": "tiedan",
		"二狗": "ergou",
		"龟田": "guitian",
		"蓝脚七": "lanjiaoqi",
		"山本": "shanben",
		"孙大麻子": "sun_damazi",
	}.get(actor_name, ""))


func _draw() -> void:
	if terrain_loaded:
		_draw_mission_markers()
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
	_draw_mission_markers()


func _draw_mission_markers() -> void:
	var raw_bindings: Variant = current_mission.get("scene_bindings", {})
	if not raw_bindings is Dictionary:
		return
	for binding_value: Variant in (raw_bindings as Dictionary).keys():
		var binding_kind := str(binding_value)
		if not _binding_has_world_marker(binding_kind):
			continue
		for scene_index: int in _binding_scenes(binding_kind):
			if not world_entities_by_scene.has(scene_index):
				continue
			var entity := world_entities_by_scene[scene_index] as Dictionary
			var marker_position := Vector2(float(entity["x"]), float(entity["y"]))
			var marker_color := Color(0.98, 0.66, 0.18, 0.95)
			if binding_kind == "exit":
				marker_color = Color(0.28, 0.92, 0.44, 0.95)
			elif binding_kind == "high_ground":
				marker_color = Color(0.30, 0.72, 1.0, 0.95)
			elif binding_kind != "explosion":
				marker_color = Color(0.96, 0.84, 0.24, 0.95)
			if activated_mission_scenes.has(scene_index):
				marker_color = Color(0.48, 0.52, 0.48, 0.70)
			draw_circle(marker_position, 6.0, marker_color)
			draw_arc(marker_position, 24.0, 0.0, TAU, 32, marker_color, 3.0)
