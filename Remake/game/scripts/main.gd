extends Node2D

const SQUAD_UNIT = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT = preload("res://scripts/enemy_unit.gd")
const ESCORT_UNIT = preload("res://scripts/escort_unit.gd")
const LEGACY_ESCORT_RULES: Script = preload(
	"res://scripts/legacy_escort_rules.gd"
)
const LEGACY_MISSION_RULES: Script = preload(
	"res://scripts/legacy_mission_rules.gd"
)
const AMBIENT_UNIT = preload("res://scripts/ambient_unit.gd")
const MISSION_PICKUP = preload("res://scripts/mission_pickup.gd")
const SIMULATION_SCRIPT: Script = preload("res://scripts/simulation.gd")
const LEVEL_VIEW: Script = preload("res://scripts/level_view.gd")
const IMPORTED_LEVEL_DATA: Script = preload("res://scripts/imported_level_data.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload("res://scripts/imported_sprite_animation.gd")
const MISSION_DATA: Script = preload("res://scripts/mission_data.gd")
const MISSION_STATE: Script = preload("res://scripts/mission_state.gd")
const MISSION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_runtime.gd")
const MISSION_DIRECTION_RUNTIME_SCRIPT: Script = preload("res://scripts/mission_direction_runtime.gd")
const MISSION_AI_COORDINATOR_SCRIPT: Script = preload("res://scripts/mission_ai_coordinator.gd")
const MODERN_DIFFICULTY_POLICY: Script = preload(
	"res://scripts/modern_difficulty_policy.gd"
)
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const ORIGINAL_INITIAL_WEAPON_INVENTORY: Script = preload(
	"res://scripts/original_initial_weapon_inventory.gd"
)
const ORIGINAL_INITIAL_ITEM_INVENTORY: Script = preload(
	"res://scripts/original_initial_item_inventory.gd"
)
const ORIGINAL_RUNTIME_ACTOR_CATALOG: Script = preload(
	"res://scripts/original_runtime_actor_catalog.gd"
)
const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const PROJECTILE_WORLD_SCRIPT: Script = preload("res://scripts/projectile_world.gd")
const MEDIA_DIRECTOR_SCRIPT: Script = preload("res://scripts/media_director.gd")
const GAME_SHELL_SCRIPT: Script = preload("res://scripts/game_shell.gd")
const GAME_SETTINGS_SCRIPT: Script = preload("res://scripts/game_settings.gd")
const LOCALIZATION_SERVICE_SCRIPT: Script = preload(
	"res://scripts/localization_service.gd"
)
const HISTORY_ARCHIVE_SCRIPT: Script = preload("res://scripts/history_archive.gd")
const MISSION_STATISTICS_SCRIPT: Script = preload(
	"res://scripts/mission_statistics.gd"
)
const DEVELOPER_DEBUG_OVERLAY_SCRIPT: Script = preload(
	"res://scripts/developer_debug_overlay.gd"
)
const DEVELOPER_WORLD_DEBUG_OVERLAY_SCRIPT: Script = preload(
	"res://scripts/developer_world_debug_overlay.gd"
)
const GAME_SAVE_STORE_SCRIPT: Script = preload("res://scripts/game_save_store.gd")
const CAMPAIGN_PROGRESS_SCRIPT: Script = preload("res://scripts/campaign_progress.gd")
const GAME_SESSION_STATE_SCRIPT: Script = preload("res://scripts/game_session_state.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const LEGACY_INPUT_RULES: Script = preload("res://scripts/legacy_input_rules.gd")
const SMOOTH_CAMERA_PAN: Script = preload("res://scripts/smooth_camera_pan.gd")
const WORLD_AUDIO_SPATIALIZER: Script = preload(
	"res://scripts/world_audio_spatializer.gd"
)
const WORLD_SPATIAL_INDEX_SCRIPT: Script = preload(
	"res://scripts/world_spatial_index.gd"
)
const WORLD_INTERACTION_RESOLVER: Script = preload(
	"res://scripts/world_interaction_resolver.gd"
)
const PERCEPTION_SCHEDULER_SCRIPT: Script = preload(
	"res://scripts/perception_scheduler.gd"
)
const RUNTIME_PERFORMANCE_MONITOR_SCRIPT: Script = preload(
	"res://scripts/runtime_performance_monitor.gd"
)
const CHECKPOINT_MANAGER_SCRIPT: Script = preload(
	"res://scripts/checkpoint_manager.gd"
)
const RUNTIME_DIAGNOSTICS_SCRIPT: Script = preload(
	"res://scripts/runtime_diagnostics.gd"
)
const CONTENT_PACKAGE_VALIDATOR: Script = preload(
	"res://scripts/content_package_validator.gd"
)
const RUNTIME_SERVICE_HUB_SCRIPT: Script = preload(
	"res://scripts/runtime_service_hub.gd"
)
const COMBAT_FEEDBACK: Script = preload("res://scripts/combat_feedback.gd")
const LEVEL_LOAD_PIPELINE_SCRIPT: Script = preload(
	"res://scripts/level_load_pipeline.gd"
)
const LEGACY_CURSOR_PRESENTER: Script = preload(
	"res://scripts/legacy_cursor_presenter.gd"
)
const WORLD_PICKUP_CATALOG: Script = preload("res://scripts/world_pickup_catalog.gd")
const LEGACY_DYNAMIC_WORLD_ITEM_CATALOG: Script = preload(
	"res://scripts/legacy_dynamic_world_item_catalog.gd"
)
const LEGACY_M006_EXCHANGE_RULES: Script = preload(
	"res://scripts/legacy_m006_exchange_rules.gd"
)
const FIELD_PICKUP_SCRIPT: Script = preload("res://scripts/field_pickup.gd")
const EXPLOSIVE_PROP_SCRIPT: Script = preload("res://scripts/explosive_prop.gd")
const LEGACY_SPECIAL_ACTION_PROFILES: Script = preload("res://scripts/legacy_special_action_profiles.gd")
const LEGACY_SPECIAL_WORLD_OBJECT_SCRIPT: Script = preload("res://scripts/legacy_special_world_object.gd")
const LEGACY_EXPLOSION_RULES: Script = preload(
	"res://scripts/legacy_explosion_rules.gd"
)
const LEGACY_EXPLOSION_VISUAL_RULES: Script = preload(
	"res://scripts/legacy_explosion_visual_rules.gd"
)
const LEGACY_CRT_RANDOM_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)
const LEGACY_ACTOR_AUDIO_RULES: Script = preload(
	"res://scripts/legacy_actor_audio_rules.gd"
)
const LEGACY_SOUND_ROUTE_CATALOG: Script = preload(
	"res://scripts/generated/legacy_sound_route_catalog.gd"
)
const LEGACY_MEDIA_ROUTE_CATALOG: Script = preload(
	"res://scripts/generated/legacy_media_route_catalog.gd"
)
const ORIGINAL_STARTUP_MEDIA_QUEUE: Script = preload(
	"res://scripts/original_startup_media_queue.gd"
)
const LEGACY_AMBIENT_PARTICLE_RANDOM_CALL_SITES := {
	0x0005FD2C: true,
	0x0005FD41: true,
	0x0005FD54: true,
	0x0005FD6A: true,
	0x0005FD7F: true,
	0x0005FDA8: true,
	0x0005FDDB: true,
	0x0005FDEE: true,
	0x0005FE02: true,
	0x0005FE19: true,
	0x0005FF45: true,
	0x0005FF65: true,
	0x000600F0: true,
	0x00060105: true,
	0x000601D6: true,
	0x000601E5: true,
	0x00060202: true,
	0x0006026D: true,
	0x00060291: true,
	0x000602A7: true,
	0x000602BC: true,
	0x000602D1: true,
	0x000602FA: true,
	0x00060374: true,
	0x00060396: true,
	0x000603AD: true,
	0x000603C4: true,
}
const ORIGINAL_CRT_RANDOM_STARTUP_CATALOG: Script = preload(
	"res://scripts/original_crt_random_startup_catalog.gd"
)
const ORIGINAL_CRT_RANDOM_LOCAL_SEARCH_TIMING: Script = preload(
	"res://scripts/original_crt_random_local_search_timing.gd"
)
const ORIGINAL_CRT_RANDOM_ACTOR_EVENT_TIMING: Script = preload(
	"res://scripts/original_crt_random_actor_event_timing.gd"
)
const ORIGINAL_CRT_RANDOM_INPUT_BRANCH_TIMING: Script = preload(
	"res://scripts/original_crt_random_input_branch_timing.gd"
)
const LEGACY_AMBIENT_PARTICLE_FIELD_SCRIPT: Script = preload(
	"res://scripts/legacy_ambient_particle_field.gd"
)
const LEGACY_EXPLOSION_EFFECT_SCRIPT: Script = preload(
	"res://scripts/legacy_explosion_effect.gd"
)
const LEGACY_AI_CONTROL_EFFECT_SCRIPT: Script = preload("res://scripts/legacy_ai_control_effect.gd")
const LEGACY_OBSERVATION_BEACON_SCRIPT: Script = preload("res://scripts/legacy_observation_beacon.gd")
const LEGACY_BURIAL_CACHE_SCRIPT: Script = preload("res://scripts/legacy_burial_cache.gd")
const LEGACY_CORPSE_DISCOVERY_RULES: Script = preload(
	"res://scripts/legacy_corpse_discovery_rules.gd"
)
const LEGACY_ENEMY_AI_RULES: Script = preload(
	"res://scripts/legacy_enemy_ai_rules.gd"
)
const LEGACY_DISGUISE_RULES: Script = preload(
	"res://scripts/legacy_disguise_rules.gd"
)
const LEGACY_DOOR_CATALOG: Script = preload(
	"res://scripts/legacy_door_catalog.gd"
)
const LEGACY_DOOR_SCRIPT: Script = preload("res://scripts/legacy_door.gd")
const LEGACY_ROW_SLICE_SPRITE_SCRIPT: Script = preload(
	"res://scripts/legacy_row_slice_sprite.gd"
)
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")
const NAVIGATION_GRID_DATA: Script = preload("res://scripts/navigation_grid_data.gd")
const DYNAMIC_OCCUPANCY_GRID: Script = preload("res://scripts/dynamic_occupancy_grid.gd")
const DEFAULT_WORLD_SIZE := Vector2(1280.0, 720.0)
const DEFAULT_MOVEMENT_BOUNDS := Rect2(Vector2(36.0, 100.0), Vector2(1208.0, 568.0))
const CAMERA_PAN_SPEED := 720.0
const EDGE_SCROLL_MARGIN := 32.0
const EDGE_SCROLL_VERTICAL_MARGIN := 48.0
const EDGE_SCROLL_RELEASE_GRACE_SECONDS := 0.10
const BACKGROUND_ENTITY_Z_INDEX := WORLD_DEPTH.BACKGROUND_Z
const MISSION_INTERACTION_RADIUS := 128.0
const MISSION_ZONE_CHECK_SECONDS := 0.20
const MINIMAP_REFRESH_SECONDS := 0.10
const SIGHT_OBSERVATION_DURATION_SECONDS := 8.0
const RIGHT_DRAG_THRESHOLD := 8.0
const QUICK_SAVE_SLOT := "quick"
const AUTO_SAVE_SLOT := "autosave"
const ORIGINAL_CHEAT_COMPLETE := "FLIPMISSION"
const ORIGINAL_CHEAT_ABOUT := "LOVEBABY"
const ORIGINAL_BURIAL_GRID_SIZE := Vector2i(32, 16)
const ORIGINAL_BURIAL_COUNTER_LIMIT := 100
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
const ORIGINAL_MINIMAP_GFL_IDS: Array[int] = [
	1036, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1025,
]
const PLAYABLE_LOADOUT_ATTACK_TYPES := {
	"老赵": 1,
	"铁蛋": 7,
	"强子": 2,
	"古明": 1,
	"大牛": 5,
}
const WEAPON_ACTION_ATTACK_TYPES := {
	"weapon_1": 4,
	"weapon_2": 7,
	"weapon_3": 5,
	"weapon_4": 6,
	"weapon_5": 1,
	"weapon_6": 2,
	"weapon_7": 3,
	"weapon_8": 8,
	"weapon_9": 9,
	"weapon_10": 10,
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
	10: "炸药包",
	11: "特殊物品",
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
	45: "炸药包",
	99: "特殊控制物品",
}
const MISSION_ITEM_NAMES := {
	"uniform": "日军军服",
	"explosives": "任务炸药",
}
const INVENTORY_ICON_SPRITES_BY_ITEM_ID := {
	33: "0002",
	36: "0377",
	38: "0375",
	41: "0239",
	43: "0374",
	44: "0376",
	45: "0250",
	46: "0373",
	47: "0249",
	48: "0241",
	49: "0245",
	50: "0247",
	51: "0238",
	52: "0242",
	53: "0365",
	54: "0243",
	82: "0240",
	83: "0248",
	92: "0271",
	101: "0246",
}
## World drops must use transparent in-world sprites, never the framed 50x50
## toolbar PSD buttons. Several weapons do not have a one-to-one loose pickup,
## so the closest original weapon/cache art is used deterministically.
const WORLD_WEAPON_SPRITES_BY_ITEM_ID := {
	36: "0377", # pistol
	37: "0372", # rifle
	38: "0375", # machine gun
	39: "0244", # dagger / short blade
	40: "0244", # broadsword
	41: "0239", # throwing-knife box
	42: "0239", # bow ammunition cache
	43: "0374", # mine
	44: "0376", # grenade / launcher ammunition
	45: "0250", # explosives
}
const INVENTORY_ICON_SPRITES_BY_MISSION_ITEM := {
	"uniform": "0243",
	"explosives": "0250",
}
# Exact 50x50 popup icons recovered from the original PSD resource table.
# Vector2i.x is the normal GFL index and Vector2i.y is the selected/hovered
# index.  These take precedence over world-pickup sprites in the UI; the
# latter remain a fallback for incomplete external asset sets.
const ORIGINAL_INVENTORY_PSD_BY_ITEM_ID := {
	33: Vector2i(1166, 1167),
	36: Vector2i(1212, 1213),
	37: Vector2i(1120, 1121),
	38: Vector2i(1164, 1165),
	39: Vector2i(1117, 1118),
	40: Vector2i(1123, 1124),
	41: Vector2i(1149, 1150),
	42: Vector2i(1133, 1134),
	43: Vector2i(1141, 1142),
	44: Vector2i(1210, 1211),
	45: Vector2i(1248, 1249),
	46: Vector2i(1135, 1136),
	47: Vector2i(1240, 1241),
	48: Vector2i(1162, 1163),
	49: Vector2i(1175, 1176),
	50: Vector2i(1230, 1231),
	51: Vector2i(1258, 1259),
	52: Vector2i(1145, 1146),
	53: Vector2i(1195, 1196),
	54: Vector2i(1178, 1179),
	82: Vector2i(1151, 1152),
	83: Vector2i(1234, 1235),
	92: Vector2i(1201, 1202),
	101: Vector2i(1221, 1222),
}
const ORIGINAL_INVENTORY_PSD_BY_MISSION_ITEM := {
	"uniform": Vector2i(1178, 1179),
	"explosives": Vector2i(1248, 1249),
}


class LegacyDeploymentTarget:
	extends Node2D

	var faction_id := 0
	var scene_index := -1
	var original_display_name := "部署点"
	var owner_actor: Node2D
	var active := true

	func configure(world_position: Vector2, new_owner: Node2D) -> void:
		position = world_position
		owner_actor = new_owner

	func is_combat_alive() -> bool:
		return (
			active
			and owner_actor != null
			and is_instance_valid(owner_actor)
			and bool(owner_actor.call("is_combat_alive"))
		)

	func resolve() -> void:
		if not active:
			return
		active = false
		queue_free()

	func _physics_process(_delta: float) -> void:
		if active and not is_combat_alive():
			resolve()

var units: Array[SQUAD_UNIT] = []
var enemies: Array[ENEMY_UNIT] = []
var escorts: Array[ESCORT_UNIT] = []
var ambient_units: Array[AMBIENT_UNIT] = []
var original_runtime_actor_order_cache: Array[Node2D] = []
var original_runtime_actor_order_cache_rebuild_serial := 0
var mission_pickups: Array[MISSION_PICKUP] = []
var next_mission_pickup_serial := 1
var next_legacy_reinforcement_scene_index := 1000000
var next_legacy_reinforcement_serial := 1
var legacy_global_alarm_active := false
var legacy_global_alarm_counter := 0
var selected_units: Array[SQUAD_UNIT] = []
var control_groups: Dictionary = {}
var camera_bookmarks: Dictionary = {}
var status_label: Label
var badge_label: Label
var objective_label: Label
var inventory_label: Label
var level_camera: Camera2D
var direction_camera_tween: Tween
var world_size := DEFAULT_WORLD_SIZE
var movement_bounds := DEFAULT_MOVEMENT_BOUNDS
var terrain_loaded := false
var camera_dragging := false
var right_dragging := false
var right_drag_start_screen := Vector2.ZERO
var right_drag_current_screen := Vector2.ZERO
var edge_scroll_strength := 0.0
var edge_scroll_last_direction := Vector2.ZERO
var edge_scroll_release_elapsed := EDGE_SCROLL_RELEASE_GRACE_SECONDS
var camera_pan_velocity := Vector2.ZERO
## Viewport-local pointer coordinates observed through the ordinary input
## stream. Polling DisplayServer/Viewport directly can report a stale desktop
## position while a live HUD control owns hover in a windowed game.
var pointer_screen_position := Vector2(-1.0, -1.0)
var legacy_cursor_presenter: RefCounted = LEGACY_CURSOR_PRESENTER.new()
var original_force_target_held := false
var sight_observation_mode := false
var sight_target_pending := false
var sight_beacon: Node2D
var sight_observation_target: ENEMY_UNIT
var sight_observation_remaining := 0.0
var tactical_visible_enemies: Dictionary = {}
var burial_mode := false
var burial_target: ENEMY_UNIT
var burial_worker: SQUAD_UNIT
var burial_progress_ticks := 0
var burial_action_started := false
var minimap_refresh_elapsed := 0.0
var original_cheat_buffer := ""
var pending_initial_briefing_level := ""
var pending_direction_start_sequence_id := ""
var pending_victory_media_cue := false
var victory_handled_level_id := ""
var victory_presentation_completed := true
var imported_level: Dictionary = {}
var imported_entity_count := 0
var current_level_index := 0
var playable_entities: Dictionary = {}
var enemy_entities: Array[Dictionary] = []
var ambient_entities: Array[Dictionary] = []
var imported_texture_cache: Dictionary = {}
var imported_animation_cache: Dictionary = {}
## Animation resources are retained across missions, but collision-footprint
## staging must only inspect the groups used by the level being constructed.
## Otherwise every previous mission's directional masks are recomputed against
## the new navigation grid and level-switch cost grows throughout a campaign.
var current_level_animation_cache_keys: Dictionary = {}
var inventory_icon_cache: Dictionary = {}
var current_level_directory := ""
var converted_root := ""
var content_package_validation: Dictionary = {}
var context_cursor_cached_serial := LEGACY_INPUT_RULES.CursorSerial.NORMAL
var context_cursor_last_screen_position := Vector2(INF, INF)
var context_cursor_last_state := -1
var context_cursor_refresh_elapsed := 0.0
var combat_preview_refresh_elapsed := 0.0
var combat_preview_visible := false
var current_mission: Dictionary = {}
var current_mission_state: RefCounted
var mission_runtime: Node
var mission_direction_runtime: Node
var mission_ai_coordinator: Node
var world_entities_by_scene: Dictionary = {}
var activated_mission_scenes: Dictionary = {}
var m010_split_ordered_names: Dictionary = {}
var mission_zone_elapsed := 0.0
var navigation_grid: NavigationGridData
var dynamic_occupancy: RefCounted
var projectile_world: Node2D
var legacy_ambient_particle_layer: CanvasLayer
var legacy_ambient_particle_field: Control
var media_director: CanvasLayer
var game_shell: CanvasLayer
var game_settings: RefCounted
var save_store: RefCounted
var campaign_progress: Dictionary = {}
var startup_level_selection_pending := false
var startup_media_queue: RefCounted = ORIGINAL_STARTUP_MEDIA_QUEUE.new()
var command_line_controls_display := false
var media_event_seed := 0
var last_formation_move_total_usec := 0
var last_formation_move_audio_usec := 0
var last_formation_move_path_usec := 0
var last_formation_move_event_usec := 0
var last_level_load_phase_usec: Dictionary = {}
var last_squad_spawn_phase_usec: Dictionary = {}
var legacy_crt_random_state := 1
var legacy_crt_random_draw_index := 0
var legacy_crt_recurring_level_id := ""
var legacy_crt_recurring_round_index := 0
var legacy_crt_recurring_first_gate_runtime_index := -1
var legacy_crt_recurring_evidence_replay_active := false
var legacy_crt_recurring_evidence_max_round := 0
var legacy_crt_recurring_evidence_invalidation_reason := ""
var legacy_crt_input_branch_id := ""
var legacy_crt_input_branch_active := false
var legacy_crt_random_trace_enabled := false
var legacy_crt_random_trace: Array[Dictionary] = []
var legacy_crt_random_parity_trace_enabled := false
var legacy_crt_random_parity_order_context: HashingContext
var legacy_crt_random_parity_value_context: HashingContext
var legacy_crt_random_parity_actor_order_context: HashingContext
var legacy_crt_random_parity_actor_value_context: HashingContext
var legacy_crt_random_parity_draw_count := 0
var legacy_crt_random_parity_actor_draw_count := 0
var legacy_crt_random_parity_call_site_counts: Dictionary = {}
var legacy_crt_random_parity_actor_call_site_counts: Dictionary = {}
var field_pickups: Array[Node2D] = []
var original_pickup_order_target: Node2D
var original_pickup_order_collector: SQUAD_UNIT
var original_drop_order_actor: SQUAD_UNIT
var original_drop_order_item_id := 0
var original_drop_order_destination := Vector2.ZERO
var explosive_props: Array[Node2D] = []
var legacy_special_world_objects: Array[Node2D] = []
var legacy_explosion_effects: Array[Node2D] = []
var legacy_ai_control_effects: Array[Node] = []
var legacy_deployment_targets: Array[Node2D] = []
var legacy_burial_caches: Array[Node2D] = []
var legacy_doors: Array[Node2D] = []
var automatic_door_broadphase_radius := 0.0
var legacy_navigation_passages: Array[Dictionary] = []
var dormant_destruction_effects_by_scene: Dictionary = {}
var buried_enemy_scene_indices: Dictionary = {}
var field_inventory: Dictionary = {}
var selected_backpack_item_id := 0
var runtime_settings: Dictionary = {
	"fullscreen": false,
	"display_mode": "windowed",
	"resolution_policy": "desktop",
	"window_width": 1280,
	"window_height": 720,
	"vsync": true,
	"max_fps": 60,
	"ruleset_mode": "classic",
	"difficulty_mode": "normal",
	"control_scheme": "classic",
	"mission_rule_mode": "stable_mod",
	"subtitles": true,
	"environment_captions": true,
	"show_briefings": true,
	"edge_scroll": true,
	"reduce_camera_motion": false,
	"reduce_flashes": false,
	"large_cursor": false,
	"high_contrast": false,
	"colorblind_patterns": true,
	"pause_on_focus_loss": true,
	"educational_mode": true,
	"reduced_violence": false,
	"history_notes": true,
	"locale": "system",
	"ui_scale": 1.0,
	"text_scale": 1.0,
	"edge_scroll_speed": CAMERA_PAN_SPEED,
	"edge_scroll_margin": EDGE_SCROLL_MARGIN,
	"zoom_step": 0.25,
	"master_volume": 0.8,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"voice_volume": 1.0,
	"controls": GAME_INPUT_BINDINGS.default_bindings(),
}
var runtime_services: RefCounted = RUNTIME_SERVICE_HUB_SCRIPT.new()
var localization_service: RefCounted = LOCALIZATION_SERVICE_SCRIPT.new()
var history_archive: RefCounted = HISTORY_ARCHIVE_SCRIPT.new()
var mission_statistics: RefCounted = MISSION_STATISTICS_SCRIPT.new()
var developer_debug_overlay: CanvasLayer
var developer_world_debug_overlay: Node2D
var developer_debug_enemy: ENEMY_UNIT
var world_spatial_index: RefCounted = runtime_services.spatial_index
var perception_scheduler: RefCounted = runtime_services.perception_scheduler
var performance_monitor: RefCounted = runtime_services.performance_monitor
var checkpoint_manager: RefCounted = runtime_services.checkpoint_manager
var runtime_diagnostics: RefCounted = runtime_services.diagnostics
var command_bus: RefCounted = runtime_services.command_bus
var navigation_requests: RefCounted = runtime_services.navigation_requests
var runtime_settings_applier: RefCounted = runtime_services.settings_applier
var application_focus_policy: RefCounted = runtime_services.focus_policy
var active_modern_difficulty_profile: Dictionary = {}
var spatial_sync_elapsed := 0.0
var restoring_save := false


func _ready() -> void:
	runtime_diagnostics.build_id = str(
		ProjectSettings.get_setting(
			"application/config/version",
			"development",
		)
	)
	if not command_bus.command_issued.is_connected(_on_runtime_command_issued):
		command_bus.command_issued.connect(_on_runtime_command_issued)
	if not command_bus.event_emitted.is_connected(_on_runtime_event_emitted):
		command_bus.event_emitted.connect(_on_runtime_event_emitted)
	var command_line_arguments := (
		OS.get_cmdline_args() + OS.get_cmdline_user_args()
	)
	legacy_crt_random_trace_enabled = (
		OS.get_environment("M1937_REMAKE_RNG_TRACE") == "1"
		or "--trace-legacy-rng" in command_line_arguments
	)
	legacy_crt_random_parity_trace_enabled = (
		OS.get_environment("M1937_REMAKE_RNG_PARITY_TRACE") == "1"
		or "--trace-legacy-rng-parity" in command_line_arguments
	)
	_initialize_persistence()
	if not history_archive.load_catalog():
		push_warning(history_archive.last_error)
	_create_media_director()
	var tree := get_tree()
	if (
		tree != null
		and not tree.node_added.is_connected(
			_on_runtime_node_added_for_original_button_audio
		)
	):
		tree.node_added.connect(
			_on_runtime_node_added_for_original_button_audio
		)
	_create_game_shell()
	create_interface()
	_connect_existing_original_button_audio(self)
	create_level_camera()
	_create_developer_debug_tools(command_line_arguments)
	startup_level_selection_pending = _should_show_startup_level_selector()
	switch_level(
		requested_level_index(),
		not startup_level_selection_pending,
		not startup_level_selection_pending,
	)
	if startup_level_selection_pending:
		call_deferred("_begin_original_startup_media_sequence")
	queue_redraw()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		if get_tree() != null:
			var transition: Dictionary = application_focus_policy.on_focus_lost(
				bool(runtime_settings.get("pause_on_focus_loss", true)),
				get_tree().paused,
				not _is_runtime_probe(),
			)
			if bool(transition.get("apply", false)):
				get_tree().paused = bool(transition.get("paused", true))
			else:
				return
			if runtime_diagnostics != null:
				runtime_diagnostics.record_command("focus_pause")
	elif what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
		if get_tree() != null:
			var transition: Dictionary = application_focus_policy.on_focus_gained(
				get_tree().paused
			)
			if bool(transition.get("apply", false)):
				get_tree().paused = bool(transition.get("paused", false))


func _on_runtime_command_issued(command: Dictionary) -> void:
	if mission_statistics != null:
		mission_statistics.observe_command(command)
	if runtime_diagnostics == null:
		return
	runtime_diagnostics.record_command(
		str(command.get("name", "unknown")),
		command.get("payload", {}) as Dictionary,
	)


func _on_runtime_event_emitted(event: Dictionary) -> void:
	if mission_statistics != null:
		mission_statistics.observe_event(event)


func next_legacy_crt_random(
	call_site_rva: int,
	runtime_index: int = -1,
) -> Dictionary:
	var metadata: Dictionary = (
		LEGACY_CRT_RANDOM_CATALOG.metadata_for_rva(call_site_rva)
	)
	if metadata.is_empty():
		push_error(
			"拒绝消费未登记的原版 CRT rand 调用点：0x%08X"
			% call_site_rva
		)
		return {}
	if (
		call_site_rva == 0x0005C81C
		and runtime_index
			== legacy_crt_recurring_first_gate_runtime_index
	):
		legacy_crt_recurring_round_index += 1
		if (
			legacy_crt_recurring_evidence_replay_active
			and legacy_crt_recurring_round_index
				> legacy_crt_recurring_evidence_max_round
		):
			invalidate_original_recurring_evidence("catalog_complete")
	var state_before := legacy_crt_random_state
	var state_after: int = LEGACY_CRT_RANDOM_CATALOG.next_state(
		state_before
	)
	var random_value: int = LEGACY_CRT_RANDOM_CATALOG.random_value(
		state_after
	)
	legacy_crt_random_state = state_after
	legacy_crt_random_draw_index += 1
	var draw := {
		"draw_index": legacy_crt_random_draw_index,
		"call_site_rva": call_site_rva,
		"state_before": state_before,
		"state": state_after,
		"value": random_value,
		"runtime_index": runtime_index,
		"domain": str(metadata.get("domain", "")),
		"purpose": str(metadata.get("purpose", "")),
	}
	_record_legacy_crt_random_draw(draw)
	return draw


func legacy_crt_random_stream_snapshot() -> Dictionary:
	# Keep the whole process-global stream transaction together.  Older saves
	# stored only state/draw index plus a subset of the evidence scheduler;
	# this versioned envelope also retains the level identity, bounded replay
	# window and active input branch so the next call after loading cannot be
	# silently assigned to a different actor/update round.
	var snapshot_level_id := legacy_crt_recurring_level_id
	if snapshot_level_id.is_empty() and current_mission is Dictionary:
		snapshot_level_id = str(current_mission.get("id", ""))
	# Synthetic unit-test worlds and the product shell before a formal level is
	# selected have no native stream identity.  Omitting the envelope preserves
	# their legacy save behavior instead of creating an unrestorable empty level.
	if not FORMAL_LEVEL_IDS.has(snapshot_level_id):
		return {}
	return {
		"schema_version": 1,
		"content_profile": (
			ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.CONTENT_PROFILE
		),
		"level_id": snapshot_level_id,
		"state": legacy_crt_random_state,
		"draw_index": legacy_crt_random_draw_index,
		"recurring_round_index": legacy_crt_recurring_round_index,
		"recurring_first_gate_runtime_index": (
			legacy_crt_recurring_first_gate_runtime_index
		),
		"evidence_replay_active": (
			legacy_crt_recurring_evidence_replay_active
		),
		"evidence_max_round": legacy_crt_recurring_evidence_max_round,
		"evidence_invalidation_reason": (
			legacy_crt_recurring_evidence_invalidation_reason
		),
		"input_branch_id": legacy_crt_input_branch_id,
		"input_branch_active": legacy_crt_input_branch_active,
	}


func restore_legacy_crt_random_stream_snapshot(
	snapshot: Dictionary,
) -> bool:
	if (
		int(snapshot.get("schema_version", 0)) != 1
		or str(snapshot.get("content_profile", ""))
			!= ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.CONTENT_PROFILE
	):
		return false
	var snapshot_level_id := str(snapshot.get("level_id", ""))
	if (
		snapshot_level_id.is_empty()
		or not FORMAL_LEVEL_IDS.has(snapshot_level_id)
		or (
			not legacy_crt_recurring_level_id.is_empty()
			and snapshot_level_id != legacy_crt_recurring_level_id
		)
	):
		return false
	var restored_state := int(snapshot.get("state", -1))
	var restored_draw_index := int(snapshot.get("draw_index", -1))
	var restored_round_index := int(
		snapshot.get("recurring_round_index", -1)
	)
	var restored_first_gate := int(
		snapshot.get("recurring_first_gate_runtime_index", -2)
	)
	var restored_max_round := int(
		snapshot.get("evidence_max_round", -1)
	)
	if (
		restored_state < 0
		or restored_state > LEGACY_CRT_RANDOM_CATALOG.UINT32_MASK
		or restored_draw_index < 0
		or restored_round_index < 0
		or restored_first_gate < -1
		or restored_max_round < 0
	):
		return false

	legacy_crt_recurring_level_id = snapshot_level_id
	legacy_crt_random_state = restored_state
	legacy_crt_random_draw_index = restored_draw_index
	legacy_crt_recurring_round_index = restored_round_index
	legacy_crt_recurring_first_gate_runtime_index = restored_first_gate
	legacy_crt_recurring_evidence_max_round = restored_max_round
	legacy_crt_recurring_evidence_invalidation_reason = str(
		snapshot.get("evidence_invalidation_reason", "")
	)
	legacy_crt_recurring_evidence_replay_active = bool(
		snapshot.get("evidence_replay_active", false)
	)
	if (
		legacy_crt_recurring_evidence_replay_active
		and legacy_crt_recurring_round_index
			> legacy_crt_recurring_evidence_max_round
	):
		legacy_crt_recurring_evidence_replay_active = false
		legacy_crt_recurring_evidence_invalidation_reason = (
			"catalog_complete"
		)

	var restored_branch_id := str(snapshot.get("input_branch_id", ""))
	var restored_branch_active := bool(
		snapshot.get("input_branch_active", false)
	)
	if not restore_legacy_crt_input_branch(
		restored_branch_id,
		restored_branch_active,
	):
		# The gameplay state remains loadable, but a stale/mismatched bounded
		# evidence branch must never force future commands onto the wrong trace.
		legacy_crt_recurring_evidence_replay_active = false
		legacy_crt_recurring_evidence_invalidation_reason = (
			"invalid_input_branch_restore"
		)
		legacy_crt_input_branch_id = ""
		legacy_crt_input_branch_active = false

	# Diagnostic traces describe calls after the restore boundary.  Carrying
	# pre-save records forward would make their local order disagree with the
	# restored global draw index even though gameplay state is correct.
	legacy_crt_random_trace.clear()
	if legacy_crt_random_parity_trace_enabled:
		_restart_legacy_crt_random_parity_trace()
	return true


func original_recurring_local_search_event(
	runtime_index: int,
) -> Dictionary:
	if (
		not legacy_crt_recurring_evidence_replay_active
		or
		legacy_crt_recurring_level_id.is_empty()
		or legacy_crt_recurring_round_index <= 0
		or runtime_index < 0
	):
		return {}
	if legacy_crt_input_branch_active:
		return (
			ORIGINAL_CRT_RANDOM_INPUT_BRANCH_TIMING
			. local_search_event_for_actor_round(
				legacy_crt_input_branch_id,
				legacy_crt_recurring_round_index,
				runtime_index,
			)
		)
	return (
		ORIGINAL_CRT_RANDOM_LOCAL_SEARCH_TIMING
		. event_for_actor_round(
			legacy_crt_recurring_level_id,
			legacy_crt_recurring_round_index,
			runtime_index,
		)
	)


func original_recurring_actor_events(
	runtime_index: int,
	accepted_call_sites: Array[int] = [],
) -> Array[Dictionary]:
	if (
		not legacy_crt_recurring_evidence_replay_active
		or legacy_crt_recurring_level_id.is_empty()
		or legacy_crt_recurring_round_index <= 0
		or runtime_index < 0
	):
		return []
	if legacy_crt_input_branch_active:
		return (
			ORIGINAL_CRT_RANDOM_INPUT_BRANCH_TIMING
			. events_for_actor_round(
				legacy_crt_input_branch_id,
				legacy_crt_recurring_round_index,
				runtime_index,
				accepted_call_sites,
			)
		)
	return (
		ORIGINAL_CRT_RANDOM_ACTOR_EVENT_TIMING.events_for_actor_round(
			legacy_crt_recurring_level_id,
			legacy_crt_recurring_round_index,
			runtime_index,
			accepted_call_sites,
		)
	)


func is_original_recurring_evidence_replay_active() -> bool:
	return legacy_crt_recurring_evidence_replay_active


func original_recurring_evidence_round_index() -> int:
	return (
		legacy_crt_recurring_round_index
		if legacy_crt_recurring_evidence_replay_active
		else 0
	)


func begin_legacy_crt_input_branch(branch_id: String) -> bool:
	if (
		not legacy_crt_recurring_evidence_replay_active
		or branch_id.is_empty()
	):
		return false
	var profile: Dictionary = (
		ORIGINAL_CRT_RANDOM_INPUT_BRANCH_TIMING.branch_profile(branch_id)
	)
	var quiet_prefix_round_count := int(
		profile.get("quiet_prefix_round_count", 0)
	)
	var profile_rounds: Array = profile.get("rounds", []) as Array
	if (
		profile.is_empty()
		or str(profile.get("level_id", ""))
			!= legacy_crt_recurring_level_id
		or int(profile.get("complete_round_count", 0)) <= 0
		or legacy_crt_recurring_round_index > quiet_prefix_round_count
		or legacy_crt_recurring_round_index > profile_rounds.size()
	):
		return false
	var expected_draw_index := (
		int(profile.get("first_gameplay_sequence", 0)) - 1
		if legacy_crt_recurring_round_index == 0
		else int((
			profile_rounds[legacy_crt_recurring_round_index - 1]
			as Dictionary
		).get("last_sequence", -1))
	)
	if expected_draw_index != legacy_crt_random_draw_index:
		return false
	legacy_crt_input_branch_id = branch_id
	legacy_crt_input_branch_active = true
	legacy_crt_recurring_evidence_max_round = int(
		profile.get("complete_round_count", 0)
	)
	legacy_crt_recurring_evidence_invalidation_reason = ""
	return true


func restore_legacy_crt_input_branch(
	branch_id: String,
	active: bool,
) -> bool:
	legacy_crt_input_branch_id = ""
	legacy_crt_input_branch_active = false
	if not active:
		return true
	var profile: Dictionary = (
		ORIGINAL_CRT_RANDOM_INPUT_BRANCH_TIMING.branch_profile(branch_id)
	)
	if (
		profile.is_empty()
		or not legacy_crt_recurring_evidence_replay_active
		or str(profile.get("level_id", ""))
			!= legacy_crt_recurring_level_id
	):
		return false
	var profile_rounds: Array = profile.get("rounds", []) as Array
	var round_index := legacy_crt_recurring_round_index
	if round_index < 0 or round_index > profile_rounds.size():
		return false
	var minimum_draw_index := int(profile.get(
		"first_gameplay_sequence",
		0,
	)) - 1
	var maximum_draw_index := minimum_draw_index
	if round_index > 0:
		var round := profile_rounds[round_index - 1] as Dictionary
		minimum_draw_index = int(round.get("first_sequence", 0))
		maximum_draw_index = int(round.get("last_sequence", -1))
	if (
		legacy_crt_random_draw_index < minimum_draw_index
		or legacy_crt_random_draw_index > maximum_draw_index
	):
		return false
	legacy_crt_input_branch_id = branch_id
	legacy_crt_input_branch_active = true
	legacy_crt_recurring_evidence_max_round = int(
		profile.get("complete_round_count", 0)
	)
	return legacy_crt_recurring_evidence_max_round > 0


func invalidate_original_recurring_evidence(reason: String) -> void:
	if not legacy_crt_recurring_evidence_replay_active:
		return
	legacy_crt_recurring_evidence_replay_active = false
	legacy_crt_recurring_evidence_invalidation_reason = reason
	legacy_crt_input_branch_active = false
	legacy_crt_input_branch_id = ""


func commit_legacy_crt_random_draws(draws: Array) -> bool:
	var expected_state := legacy_crt_random_state
	var verified: Array[Dictionary] = []
	for raw_draw: Variant in draws:
		if not raw_draw is Dictionary:
			push_error("原版 CRT rand 批次包含非字典记录")
			return false
		var draw := raw_draw as Dictionary
		var call_site_rva := int(draw.get("call_site_rva", 0))
		var metadata: Dictionary = (
			LEGACY_CRT_RANDOM_CATALOG.metadata_for_rva(call_site_rva)
		)
		if metadata.is_empty():
			push_error(
				"原版 CRT rand 批次包含未登记调用点：0x%08X"
				% call_site_rva
			)
			return false
		var state_before := expected_state
		expected_state = LEGACY_CRT_RANDOM_CATALOG.next_state(expected_state)
		var expected_value: int = (
			LEGACY_CRT_RANDOM_CATALOG.random_value(expected_state)
		)
		if (
			int(draw.get("state", -1)) != expected_state
			or int(draw.get("value", -1)) != expected_value
		):
			push_error(
				(
					"原版 CRT rand 批次状态不连续：调用点 0x%08X，"
					+ "期望 state=0x%08X/value=%d"
				)
				% [call_site_rva, expected_state, expected_value]
			)
			return false
		verified.append({
			"call_site_rva": call_site_rva,
			"state_before": state_before,
			"state": expected_state,
			"value": expected_value,
			"runtime_index": int(draw.get("runtime_index", -1)),
			"domain": str(metadata.get("domain", "")),
			"purpose": str(metadata.get("purpose", "")),
		})
	for draw: Dictionary in verified:
		legacy_crt_random_draw_index += 1
		draw["draw_index"] = legacy_crt_random_draw_index
		_record_legacy_crt_random_draw(draw)
	legacy_crt_random_state = expected_state
	return true


func commit_legacy_ambient_crt_random_batch(
	state_before: int,
	state_after: int,
	call_sites: PackedInt32Array,
	draw_count: int,
) -> bool:
	if state_before != legacy_crt_random_state:
		push_error(
			"原版环境粒子 CRT rand 批次起始状态不连续"
		)
		return false
	if draw_count < 0:
		return false
	# This hot path can exceed 500 original draws per 60 Hz frame. The
	# trace-enabled branch below validates every recovered call site and exact
	# LCG transition in tests/forensics. Ordinary play commits the already
	# verified internal particle transaction in O(1), avoiding a second
	# GDScript pass over the same native sequence.
	if (
		not legacy_crt_random_trace_enabled
		and not legacy_crt_random_parity_trace_enabled
	):
		legacy_crt_random_state = state_after
		legacy_crt_random_draw_index += draw_count
		return true
	if call_sites.size() != draw_count:
		push_error(
			"原版环境粒子 CRT rand 跟踪批次数量不一致"
		)
		return false
	var verified_state := state_before
	for call_site_rva: int in call_sites:
		if not LEGACY_AMBIENT_PARTICLE_RANDOM_CALL_SITES.has(
			call_site_rva
		):
			push_error(
				"原版环境粒子批次包含非法调用点：0x%08X"
				% call_site_rva
			)
			return false
		verified_state = int(
			(
				verified_state * 214013
				+ 2531011
			)
			& 0xFFFFFFFF
		)
	if verified_state != state_after:
		push_error(
			"原版环境粒子 CRT rand 批次结束状态不连续"
		)
		return false
	var trace_state := state_before
	for call_site_rva: int in call_sites:
		var draw_state_before := trace_state
		trace_state = int(
			(
				trace_state * 214013
				+ 2531011
			)
			& 0xFFFFFFFF
		)
		var metadata: Dictionary = (
			LEGACY_CRT_RANDOM_CATALOG.metadata_for_rva(
				call_site_rva
			)
		)
		legacy_crt_random_draw_index += 1
		_record_legacy_crt_random_draw({
			"draw_index": legacy_crt_random_draw_index,
			"call_site_rva": call_site_rva,
			"state_before": draw_state_before,
			"state": trace_state,
			"value": LEGACY_CRT_RANDOM_CATALOG.random_value(
				trace_state
			),
			"runtime_index": -1,
			"domain": str(metadata.get("domain", "")),
			"purpose": str(metadata.get("purpose", "")),
		})
	legacy_crt_random_state = state_after
	return true


func _record_legacy_crt_random_draw(draw: Dictionary) -> void:
	if legacy_crt_random_parity_trace_enabled:
		_record_legacy_crt_random_parity_draw(draw)
	if not legacy_crt_random_trace_enabled:
		return
	legacy_crt_random_trace.append(draw.duplicate(true))
	if legacy_crt_random_trace.size() > 4096:
		legacy_crt_random_trace.pop_front()


func begin_legacy_crt_random_parity_trace() -> bool:
	legacy_crt_random_parity_trace_enabled = true
	return _restart_legacy_crt_random_parity_trace()


func legacy_crt_random_parity_snapshot(
	finalize: bool = false,
) -> Dictionary:
	var snapshot := {
		"draw_count": legacy_crt_random_parity_draw_count,
		"actor_draw_count": legacy_crt_random_parity_actor_draw_count,
		"call_site_counts": (
			legacy_crt_random_parity_call_site_counts.duplicate(true)
		),
		"actor_call_site_counts": (
			legacy_crt_random_parity_actor_call_site_counts.duplicate(true)
		),
		"final_state": legacy_crt_random_state,
		"final_draw_index": legacy_crt_random_draw_index,
		"ordered_call_site_actor_sha256": "",
		"ordered_call_site_actor_value_sha256": "",
		"actor_order_sha256": "",
		"actor_value_sha256": "",
	}
	if not finalize:
		return snapshot
	snapshot["ordered_call_site_actor_sha256"] = (
		_finish_legacy_crt_random_parity_context(
			legacy_crt_random_parity_order_context
		)
	)
	snapshot["ordered_call_site_actor_value_sha256"] = (
		_finish_legacy_crt_random_parity_context(
			legacy_crt_random_parity_value_context
		)
	)
	snapshot["actor_order_sha256"] = (
		_finish_legacy_crt_random_parity_context(
			legacy_crt_random_parity_actor_order_context
		)
	)
	snapshot["actor_value_sha256"] = (
		_finish_legacy_crt_random_parity_context(
			legacy_crt_random_parity_actor_value_context
		)
	)
	legacy_crt_random_parity_trace_enabled = false
	legacy_crt_random_parity_order_context = null
	legacy_crt_random_parity_value_context = null
	legacy_crt_random_parity_actor_order_context = null
	legacy_crt_random_parity_actor_value_context = null
	return snapshot


func _restart_legacy_crt_random_parity_trace() -> bool:
	legacy_crt_random_parity_draw_count = 0
	legacy_crt_random_parity_actor_draw_count = 0
	legacy_crt_random_parity_call_site_counts.clear()
	legacy_crt_random_parity_actor_call_site_counts.clear()
	legacy_crt_random_parity_order_context = HashingContext.new()
	legacy_crt_random_parity_value_context = HashingContext.new()
	legacy_crt_random_parity_actor_order_context = HashingContext.new()
	legacy_crt_random_parity_actor_value_context = HashingContext.new()
	for context: HashingContext in [
		legacy_crt_random_parity_order_context,
		legacy_crt_random_parity_value_context,
		legacy_crt_random_parity_actor_order_context,
		legacy_crt_random_parity_actor_value_context,
	]:
		if context.start(HashingContext.HASH_SHA256) != OK:
			legacy_crt_random_parity_trace_enabled = false
			push_error("无法初始化原版 CRT rand parity 哈希")
			return false
	return true


func _record_legacy_crt_random_parity_draw(draw: Dictionary) -> void:
	if legacy_crt_random_parity_order_context == null:
		if not _restart_legacy_crt_random_parity_trace():
			return
	var call_site_rva := int(draw.get("call_site_rva", 0))
	var runtime_index := int(draw.get("runtime_index", -1))
	var random_value := int(draw.get("value", -1))
	var order_bytes := PackedByteArray()
	order_bytes.resize(8)
	order_bytes.encode_u32(0, call_site_rva)
	order_bytes.encode_s32(4, runtime_index)
	var value_bytes := PackedByteArray()
	value_bytes.resize(12)
	value_bytes.encode_u32(0, call_site_rva)
	value_bytes.encode_s32(4, runtime_index)
	value_bytes.encode_u32(8, random_value)
	if (
		legacy_crt_random_parity_order_context.update(order_bytes) != OK
		or legacy_crt_random_parity_value_context.update(value_bytes) != OK
	):
		legacy_crt_random_parity_trace_enabled = false
		push_error("原版 CRT rand parity 全局哈希更新失败")
		return
	legacy_crt_random_parity_draw_count += 1
	var site_key := "0x%08X" % call_site_rva
	legacy_crt_random_parity_call_site_counts[site_key] = int(
		legacy_crt_random_parity_call_site_counts.get(site_key, 0)
	) + 1
	if runtime_index < 0:
		return
	var actor_site_key := "%d:%s" % [runtime_index, site_key]
	legacy_crt_random_parity_actor_call_site_counts[actor_site_key] = int(
		legacy_crt_random_parity_actor_call_site_counts.get(
			actor_site_key,
			0,
		)
	) + 1
	if (
		legacy_crt_random_parity_actor_order_context.update(order_bytes) != OK
		or legacy_crt_random_parity_actor_value_context.update(value_bytes) != OK
	):
		legacy_crt_random_parity_trace_enabled = false
		push_error("原版 CRT rand parity actor 哈希更新失败")
		return
	legacy_crt_random_parity_actor_draw_count += 1


func _finish_legacy_crt_random_parity_context(
	context: HashingContext,
) -> String:
	if context == null:
		return ""
	return context.finish().hex_encode().to_upper()


func _reset_legacy_crt_random_for_level_load() -> void:
	legacy_crt_random_state = LEGACY_CRT_RANDOM_CATALOG.INITIAL_STATE
	legacy_crt_random_draw_index = 0
	legacy_crt_recurring_level_id = ""
	legacy_crt_recurring_round_index = 0
	legacy_crt_recurring_first_gate_runtime_index = -1
	legacy_crt_recurring_evidence_replay_active = false
	legacy_crt_recurring_evidence_max_round = 0
	legacy_crt_recurring_evidence_invalidation_reason = ""
	legacy_crt_input_branch_id = ""
	legacy_crt_input_branch_active = false
	legacy_crt_random_trace.clear()
	if legacy_crt_random_parity_trace_enabled:
		_restart_legacy_crt_random_parity_trace()


func _configure_legacy_ambient_particle_field(level_id: String) -> bool:
	_clear_legacy_ambient_particle_field()
	if not LEGACY_AMBIENT_PARTICLE_FIELD_SCRIPT.ACTIVE_LEVEL_IDS.has(
		level_id
	):
		return false
	legacy_ambient_particle_layer = CanvasLayer.new()
	legacy_ambient_particle_layer.name = "LegacyAmbientParticleLayer"
	legacy_ambient_particle_layer.layer = 20
	add_child(legacy_ambient_particle_layer)
	legacy_ambient_particle_field = (
		LEGACY_AMBIENT_PARTICLE_FIELD_SCRIPT.new()
	)
	legacy_ambient_particle_field.name = "LegacyAmbientParticleField"
	legacy_ambient_particle_layer.add_child(
		legacy_ambient_particle_field
	)
	legacy_ambient_particle_field.call(
		"set_reduce_flashes",
		bool(runtime_settings.get("reduce_flashes", false)),
	)
	return bool(legacy_ambient_particle_field.call(
		"configure",
		self,
		level_id,
	))


func _clear_legacy_ambient_particle_field() -> void:
	if (
		legacy_ambient_particle_field != null
		and is_instance_valid(legacy_ambient_particle_field)
	):
		legacy_ambient_particle_field.set_physics_process(false)
	legacy_ambient_particle_field = null
	if (
		legacy_ambient_particle_layer != null
		and is_instance_valid(legacy_ambient_particle_layer)
	):
		legacy_ambient_particle_layer.queue_free()
	legacy_ambient_particle_layer = null


func legacy_ambient_particle_snapshot() -> Dictionary:
	if (
		legacy_ambient_particle_field == null
		or not is_instance_valid(legacy_ambient_particle_field)
		or not legacy_ambient_particle_field.has_method(
			"runtime_snapshot"
		)
	):
		return {}
	return legacy_ambient_particle_field.call(
		"runtime_snapshot"
	) as Dictionary


func restore_legacy_ambient_particle_snapshot(
	state: Dictionary,
) -> bool:
	return (
		legacy_ambient_particle_field != null
		and is_instance_valid(legacy_ambient_particle_field)
		and legacy_ambient_particle_field.has_method(
			"restore_runtime_snapshot"
		)
		and bool(legacy_ambient_particle_field.call(
			"restore_runtime_snapshot",
			state,
		))
	)


func _apply_original_crt_random_startup_checkpoint(
	level_id: String,
) -> bool:
	var startup_state: int = (
		ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.startup_state(level_id)
	)
	var startup_draw_count: int = (
		ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.startup_draw_count(
			level_id
		)
	)
	if startup_state <= 0 or startup_draw_count <= 0:
		push_error(
			"Missing original CRT random startup checkpoint for %s"
			% level_id
		)
		return false
	# The original constructs ambient particles and every VWF entity before
	# the first gameplay actor update. Remake does not instantiate those
	# legacy-only objects, so it resumes the proven process-global stream at
	# the exact post-initialization checkpoint instead of inventing draws.
	legacy_crt_random_state = startup_state
	legacy_crt_random_draw_index = startup_draw_count
	legacy_crt_recurring_level_id = level_id
	legacy_crt_recurring_round_index = 0
	legacy_crt_recurring_first_gate_runtime_index = -1
	legacy_crt_recurring_evidence_max_round = (
		ORIGINAL_CRT_RANDOM_ACTOR_EVENT_TIMING
		. level_complete_round_count(level_id)
	)
	legacy_crt_recurring_evidence_replay_active = (
		legacy_crt_recurring_evidence_max_round > 0
	)
	legacy_crt_recurring_evidence_invalidation_reason = ""
	legacy_crt_input_branch_id = ""
	legacy_crt_input_branch_active = false
	var startup_profile: Dictionary = (
		ORIGINAL_CRT_RANDOM_STARTUP_CATALOG.level_profile(level_id)
	)
	var gate_indices_value: Variant = startup_profile.get(
		"observation_gate_actor_indices",
		[],
	)
	if (
		gate_indices_value is Array
		and not (gate_indices_value as Array).is_empty()
	):
		legacy_crt_recurring_first_gate_runtime_index = int(
			(gate_indices_value as Array)[0]
		)
	legacy_crt_random_trace.clear()
	return true


func _replay_original_first_gameplay_random_update(
	level_id: String,
	apply_actor_effects: bool = true,
) -> bool:
	var records: Array[Dictionary] = (
		ORIGINAL_CRT_RANDOM_STARTUP_CATALOG
		. first_gameplay_update_records(level_id)
	)
	if records.is_empty():
		push_error(
			"Missing original first gameplay random update for %s"
			% level_id
		)
		return false
	var actors_by_runtime_index: Dictionary = {}
	var outcome_records_by_runtime_index: Dictionary = {}
	if apply_actor_effects:
		for actor: Node2D in _all_active_runtime_actors():
			var runtime_index := int(actor.get("original_runtime_index"))
			if runtime_index >= 0:
				actors_by_runtime_index[runtime_index] = actor
	for record: Dictionary in records:
		var call_site_rva := (
			str(record.get("call_site_rva", "0x0")).hex_to_int()
		)
		var draw := next_legacy_crt_random(
			call_site_rva,
			int(record.get("runtime_index", -1)),
		)
		if (
			draw.is_empty()
			or int(draw.get("value", -1))
				!= int(record.get("value", -2))
		):
			push_error(
				(
					"Original first gameplay random update diverged for "
					+ "%s at 0x%08X"
				)
				% [level_id, call_site_rva]
			)
			return false
		if (
			apply_actor_effects
			and call_site_rva == 0x0005C81C
		):
			var runtime_index := int(record.get("runtime_index", -1))
			var actor_value: Variant = actors_by_runtime_index.get(
				runtime_index,
			)
			if (
				actor_value is Node2D
				and is_instance_valid(actor_value as Node2D)
				and (actor_value as Node2D).has_method(
					"apply_original_crt_observation_gate_value"
				)
			):
				(actor_value as Node2D).call(
					"apply_original_crt_observation_gate_value",
					int(draw.get("value", 0)),
				)
		if (
			apply_actor_effects
			and call_site_rva != 0x0005C81C
			and int(record.get("runtime_index", -1)) >= 0
		):
			var outcome_runtime_index := int(
				record.get("runtime_index", -1)
			)
			var actor_records_value: Variant = (
				outcome_records_by_runtime_index.get(
					outcome_runtime_index,
					[],
				)
			)
			var actor_records: Array[Dictionary] = []
			if actor_records_value is Array:
				for actor_record_value: Variant in (
					actor_records_value as Array
				):
					if actor_record_value is Dictionary:
						actor_records.append(
							actor_record_value as Dictionary
						)
			actor_records.append(record.duplicate(true))
			outcome_records_by_runtime_index[
				outcome_runtime_index
			] = actor_records
	if apply_actor_effects:
		var outcomes: Array[Dictionary] = (
			ORIGINAL_CRT_RANDOM_STARTUP_CATALOG
			. first_gameplay_update_outcomes(level_id)
		)
		if (
			outcomes.is_empty()
			and not outcome_records_by_runtime_index.is_empty()
		):
			push_error(
				"Missing original first gameplay outcomes for %s"
				% level_id
			)
			return false
		if (
			outcomes.size()
			!= outcome_records_by_runtime_index.size()
		):
			push_error(
				(
					"Original first gameplay outcome count "
					+ "diverged for %s"
				)
				% level_id
			)
			return false
		for outcome: Dictionary in outcomes:
			var runtime_index := int(
				outcome.get("runtime_index", -1)
			)
			var actor_value: Variant = actors_by_runtime_index.get(
				runtime_index,
			)
			var actor_records_value: Variant = (
				outcome_records_by_runtime_index.get(
					runtime_index,
					[],
				)
			)
			if (
				not actor_value is Node2D
				or not is_instance_valid(actor_value as Node2D)
				or not (actor_value as Node2D).has_method(
					"apply_original_first_gameplay_update_outcome"
				)
				or not actor_records_value is Array
				or not bool((actor_value as Node2D).call(
					"apply_original_first_gameplay_update_outcome",
					outcome,
					actor_records_value,
				))
			):
				push_error(
					(
						"Original first gameplay actor outcome "
						+ "failed for %s runtime actor %d"
					)
					% [level_id, runtime_index]
				)
				return false
	return true


func _all_active_runtime_actors() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		result.append(unit)
	for escort: ESCORT_UNIT in escorts:
		result.append(escort)
	for ambient: AMBIENT_UNIT in ambient_units:
		result.append(ambient)
	for enemy: ENEMY_UNIT in enemies:
		result.append(enemy)
	return result


func first_original_secondary_search_candidate(
	source: Node2D,
	_radius: float = (
		LEGACY_ENEMY_AI_RULES.SECONDARY_SEARCH_CANDIDATE_RADIUS
	),
) -> Node2D:
	if source == null or not is_instance_valid(source):
		return null
	_ensure_original_runtime_actor_order_cache()
	for candidate: Node2D in original_runtime_actor_order_cache:
		if (
			candidate == null
			or not is_instance_valid(candidate)
			or not LEGACY_ENEMY_AI_RULES
			. secondary_search_candidate_is_eligible(
				int(candidate.get("faction_id")),
				bool(candidate.get("is_alive")),
			)
			or not LEGACY_ENEMY_AI_RULES
			. is_within_secondary_search_radius(
				source.position,
				candidate.position,
			)
		):
			continue
		return candidate
	return null


func _active_runtime_actor_count() -> int:
	return (
		units.size()
		+ enemies.size()
		+ escorts.size()
		+ ambient_units.size()
	)


func _ensure_original_runtime_actor_order_cache() -> void:
	if (
		original_runtime_actor_order_cache.size()
		== _active_runtime_actor_count()
	):
		return
	original_runtime_actor_order_cache = _all_active_runtime_actors()
	original_runtime_actor_order_cache.sort_custom(
		_original_runtime_actor_precedes
	)
	original_runtime_actor_order_cache_rebuild_serial += 1


func original_secondary_search_world_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)


func _original_runtime_actor_precedes(
	left: Node2D,
	right: Node2D,
) -> bool:
	var left_index := int(left.get("original_runtime_index"))
	var right_index := int(right.get("original_runtime_index"))
	if left_index < 0:
		left_index = 2_000_000_000
	if right_index < 0:
		right_index = 2_000_000_000
	if left_index != right_index:
		return left_index < right_index
	return int(left.get("scene_index")) < int(right.get("scene_index"))


func _bind_original_crt_random_actor(
	actor: Node,
	observation_gate_override: int = -1,
) -> bool:
	if (
		actor == null
		or not is_instance_valid(actor)
		or not actor.has_method("bind_original_crt_random_source")
	):
		return false
	var level_id := str(
		current_mission.get(
			"id",
			FORMAL_LEVEL_IDS[current_level_index],
		)
	)
	var bound := bool(actor.call(
		"bind_original_crt_random_source",
		self,
		level_id,
		observation_gate_override,
	))
	if actor.has_method(
		"apply_original_crt_enemy_startup_profile"
	):
		actor.call("apply_original_crt_enemy_startup_profile")
	return bound


func _exit_tree() -> void:
	if legacy_cursor_presenter != null:
		legacy_cursor_presenter.reset()


func create_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ModernDebugHud"
	# This text layer was useful while the remake was still a prototype, but it
	# is not part of the original 2001 play surface.  Keep it available for
	# developers without covering the recovered top HUD/world pixels in normal
	# product builds.
	canvas.visible = "--modern-debug-hud" in OS.get_cmdline_user_args()
	add_child(canvas)

	var title := Label.new()
	title.position = Vector2(22.0, 18.0)
	title.text = "《1937特种兵》· 现代复刻技术原型"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.97, 0.91, 0.72))
	canvas.add_child(title)

	var help := Label.new()
	help.position = Vector2(24.0, 54.0)
	help.text = "F1 指南 · F2–F6 选人 · R 跑/走 · C 匍匐 · W 武器 · A 物品 · S 视线 · B 掩埋 · M 地图 · Esc 菜单"
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


func switch_level(
	level_index: int,
	show_briefing: bool = true,
	start_direction: bool = true,
) -> void:
	var level_load_started_usec := Time.get_ticks_usec()
	var level_load_phase_started_usec := level_load_started_usec
	last_level_load_phase_usec.clear()
	_cancel_direction_camera_tween()
	_reset_context_cursor()
	pending_initial_briefing_level = ""
	pending_direction_start_sequence_id = ""
	pending_victory_media_cue = false
	victory_handled_level_id = ""
	victory_presentation_completed = true
	m010_split_ordered_names.clear()
	control_groups.clear()
	camera_bookmarks.clear()
	if game_shell != null:
		game_shell.close_for_state_change()
		game_shell.update_original_hud([])
	if media_director != null:
		media_director.close_for_state_change()
	sight_observation_mode = false
	sight_target_pending = false
	burial_mode = false
	if game_shell != null:
		game_shell.set_original_hud_action_state("observation", false)
	current_level_index = posmod(level_index, FORMAL_LEVEL_IDS.size())
	var level_id := FORMAL_LEVEL_IDS[current_level_index]
	_present_loading_progress(level_id, tr("UI_LOADING_READ"), 0.05)
	var load_pipeline: RefCounted = LEVEL_LOAD_PIPELINE_SCRIPT.new()
	var level_resource_path: String = str(
		IMPORTED_LEVEL_DATA.level_path(level_id)
	)
	var terrain_resource_path: String = str(
		LEVEL_VIEW.imported_terrain_path(level_id)
	)
	load_pipeline.begin(
		ProjectSettings.globalize_path(level_resource_path),
		ProjectSettings.globalize_path(terrain_resource_path),
	)
	runtime_services.begin_level(level_id)
	mission_statistics.begin_mission(level_id)
	if game_shell != null:
		game_shell.set_victory_debrief(level_id, "")
	_clear_legacy_ambient_particle_field()
	_reset_legacy_crt_random_for_level_load()
	last_level_load_phase_usec["state_reset"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	_load_mission_graph(level_id)
	_present_loading_progress(level_id, tr("UI_LOADING_WORLD"), 0.18)
	last_level_load_phase_usec["mission_graph"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	var preloaded_level_bundle: Dictionary = load_pipeline.finish()
	load_imported_level(level_id, preloaded_level_bundle)
	_present_loading_progress(level_id, tr("UI_LOADING_ACTORS"), 0.62)
	last_level_load_phase_usec["imported_level"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	spawn_squad()
	_rebuild_world_spatial_index()
	_configure_enemy_perception_schedule()
	_prewarm_inventory_interface()
	# Do not retain parsed JSON after cold reconstruction; later actions use the
	# process-lifetime animation texture cache and can repopulate this tiny
	# staging cache on demand.
	IMPORTED_SPRITE_ANIMATION.clear_manifest_document_cache()
	if _apply_original_crt_random_startup_checkpoint(level_id):
		_replay_original_first_gameplay_random_update(level_id)
	_configure_legacy_ambient_particle_field(level_id)
	last_level_load_phase_usec["squad"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	_prewarm_original_actor_voices()
	_present_loading_progress(level_id, tr("UI_LOADING_PREWARM"), 0.82)
	last_level_load_phase_usec["squad_audio"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	_configure_mission_runtime()
	last_level_load_phase_usec["mission_runtime"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	_configure_mission_direction()
	_present_loading_progress(level_id, tr("UI_LOADING_FINALIZE"), 0.96)
	last_level_load_phase_usec["mission_direction"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	level_load_phase_started_usec = Time.get_ticks_usec()
	if badge_label != null:
		badge_label.text = "M2 / %s / LOCAL ASSETS" % level_id.to_upper()
	var presenting_briefing := show_briefing and _should_show_briefing()
	if presenting_briefing:
		pending_initial_briefing_level = level_id
		var briefing_description := tr("UI_BRIEFING_MISSING")
		if bool(runtime_settings.get("educational_mode", true)):
			var archive_entry: Dictionary = history_archive.entry_for(level_id)
			if not archive_entry.is_empty():
				briefing_description = "%s\n\n%s" % [
					str(archive_entry.get("historical_context", "")),
					tr("UI_BRIEFING_CONTEXT") % str(
						archive_entry.get("objective_context", "")
					),
				]
		media_director.show_briefing(
			level_id,
			"第 %d 关：%s" % [
				int(current_mission.get("number", 0)),
				str(current_mission.get("title", "任务简报")),
			],
			briefing_description,
		)
	elif start_direction:
		_start_initial_direction_sequence()
	_sync_level_selection()
	last_level_load_phase_usec["presentation"] = (
		Time.get_ticks_usec() - level_load_phase_started_usec
	)
	last_level_load_phase_usec["total"] = (
		Time.get_ticks_usec() - level_load_started_usec
	)
	if performance_monitor != null:
		performance_monitor.record_event(
			"level_load",
			int(last_level_load_phase_usec["total"]),
			{
				"level_id": level_id,
				"phases": last_level_load_phase_usec.duplicate(true),
			},
		)
	if game_shell != null and game_shell.has_method("hide_loading"):
		game_shell.call("hide_loading")
	if not restoring_save:
		_save_checkpoint("level_start", true)


func _present_loading_progress(
	level_id: String,
	stage: String,
	progress: float,
) -> void:
	if game_shell == null or not game_shell.has_method("show_loading"):
		return
	game_shell.call("show_loading", level_id, stage, progress)
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false, 0.0)


func _prewarm_original_actor_voices() -> void:
	if media_director == null:
		return
	var warmed_gfl_indices: Dictionary = {}
	for gfl_index: int in [
		LEGACY_SOUND_ROUTE_CATALOG.UI_BUTTON_GFL_INDEX,
		LEGACY_SOUND_ROUTE_CATALOG.GLOBAL_ALARM_GFL_INDEX,
	]:
		warmed_gfl_indices[gfl_index] = true
		media_director.prewarm_audio_index(gfl_index)
	for unit: SQUAD_UNIT in units:
		for family: String in [
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_SELECTED,
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_ACKNOWLEDGE,
		]:
			for gfl_index: int in LEGACY_ACTOR_AUDIO_RULES.gfl_indices_for(
				family,
				unit.runtime_actor_type,
			):
				if warmed_gfl_indices.has(gfl_index):
					continue
				warmed_gfl_indices[gfl_index] = true
				media_director.prewarm_audio_index(gfl_index)
	for enemy: ENEMY_UNIT in enemies:
		for family: String in [
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_HOSTILE_INITIAL,
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_HOSTILE_ALERT,
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_HOSTILE_FOLLOWUP,
		]:
			for gfl_index: int in LEGACY_ACTOR_AUDIO_RULES.gfl_indices_for(
				family,
				enemy.runtime_actor_type,
			):
				if warmed_gfl_indices.has(gfl_index):
					continue
				warmed_gfl_indices[gfl_index] = true
				media_director.prewarm_audio_index(gfl_index)
	for actor: Node2D in _all_active_runtime_actors():
		if not actor.has_method("authored_animation_sound_gfl_indices"):
			continue
		for gfl_index: int in actor.call(
			"authored_animation_sound_gfl_indices"
		) as Array[int]:
			if warmed_gfl_indices.has(gfl_index):
				continue
			warmed_gfl_indices[gfl_index] = true
			media_director.prewarm_audio_index(gfl_index)


func _prewarm_inventory_interface() -> void:
	if game_shell == null or not game_shell.has_method("prewarm_inventory"):
		return
	var started_usec := Time.get_ticks_usec()
	game_shell.call("prewarm_inventory", _inventory_grid_model())
	if performance_monitor != null:
		performance_monitor.record_event(
			"inventory_prewarm",
			Time.get_ticks_usec() - started_usec,
			{"level_id": FORMAL_LEVEL_IDS[current_level_index]},
		)


func _configure_enemy_perception_schedule() -> void:
	var classic := str(runtime_settings.get("ruleset_mode", "classic")) == "classic"
	for enemy: ENEMY_UNIT in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("configure_perception_schedule"):
			enemy.call(
				"configure_perception_schedule",
				0.0 if classic else float(
					perception_scheduler.initial_elapsed_for_scene(enemy.scene_index)
				),
				1 if classic else int(perception_scheduler.slot_count),
			)


func _rebuild_world_spatial_index() -> void:
	if world_spatial_index == null:
		return
	world_spatial_index.clear()
	automatic_door_broadphase_radius = 0.0
	for unit: SQUAD_UNIT in units:
		_register_spatial_node(unit, ["actor", "combatant", "player"])
	for escort: ESCORT_UNIT in escorts:
		_register_spatial_node(escort, ["actor", "combatant", "escort"])
	for enemy: ENEMY_UNIT in enemies:
		_register_spatial_node(enemy, ["actor", "combatant", "enemy"])
	for ambient: AMBIENT_UNIT in ambient_units:
		_register_spatial_node(ambient, ["actor", "combatant", "ambient"])
	for prop: Node2D in explosive_props:
		_register_spatial_node(prop, ["combatant", "explosive"])
	for door: Node2D in legacy_doors:
		_register_spatial_node(door, ["door", "interactable"])
		if door.has_method("approach_radius_from_origin"):
			automatic_door_broadphase_radius = maxf(
				automatic_door_broadphase_radius,
				float(door.call("approach_radius_from_origin")),
			)
	for pickup: Node2D in field_pickups:
		_register_spatial_node(pickup, ["pickup", "field_pickup", "interactable"])
	for pickup: MISSION_PICKUP in mission_pickups:
		_register_spatial_node(pickup, ["pickup", "mission_pickup", "interactable"])
	for cache: Node2D in legacy_burial_caches:
		_register_spatial_node(cache, ["pickup", "interactable", "burial_cache"])
	for enemy: ENEMY_UNIT in enemies:
		enemy.configure_world_spatial_index(world_spatial_index)


func _register_spatial_node(node: Node2D, tags: Array = []) -> void:
	if world_spatial_index == null or node == null or not is_instance_valid(node):
		return
	world_spatial_index.register_node(node, tags)


func _synchronize_world_spatial_index(delta: float) -> void:
	if world_spatial_index == null:
		return
	spatial_sync_elapsed += maxf(delta, 0.0)
	if spatial_sync_elapsed < 0.10:
		return
	spatial_sync_elapsed = fmod(spatial_sync_elapsed, 0.10)
	world_spatial_index.synchronize(_all_active_runtime_actors())


func _should_show_startup_level_selector() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--level=") or argument == "--skip-level-selector":
			return false
		if argument.contains("product_ui_probe.gd"):
			return true
		if argument.contains("res://tests/") or argument.contains("\\tests\\"):
			return false
	return true


func _should_play_original_startup_media() -> bool:
	# The modern edition starts directly at level selection.  The two legacy
	# startup films were long blocking media, delayed the first interactive
	# frame, and are deliberately excluded from distributable builds.
	return false


func _begin_original_startup_media_sequence() -> void:
	if not startup_level_selection_pending:
		return
	if not _should_play_original_startup_media():
		_complete_original_startup_media_sequence()
		return
	startup_media_queue.call(
		"begin",
		LEGACY_MEDIA_ROUTE_CATALOG.startup_sequence(),
	)
	_play_next_original_startup_movie()


func _play_next_original_startup_movie() -> void:
	while bool(startup_media_queue.call("is_active")):
		var movie_id := str(startup_media_queue.call("next_movie_id"))
		if movie_id.is_empty():
			return
		if media_director != null and bool(media_director.play_movie(movie_id)):
			return
		# Missing/invalid optional conversion: resolve immediately and continue
		# with the next original entry. No error popup and no modal deadlock.
		startup_media_queue.call("resolve", movie_id)
	_complete_original_startup_media_sequence()


func _complete_original_startup_media_sequence() -> void:
	startup_media_queue.call("clear")
	if startup_level_selection_pending:
		_open_level_selector(true)


func _should_show_briefing() -> bool:
	if media_director == null or DisplayServer.get_name() == "headless":
		return false
	if not bool(runtime_settings.get("show_briefings", true)):
		return false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--skip-briefing":
			return false
	if _is_runtime_probe():
		return false
	return true


func _is_runtime_probe() -> bool:
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.contains("runtime_probe.gd"):
			return true
	return false


func _load_mission_graph(level_id: String) -> void:
	var mission_rule_mode := (
		"stable_mod"
		if _is_runtime_probe()
		else str(runtime_settings.get("mission_rule_mode", "stable_mod"))
	)
	if mission_rule_mode not in MISSION_DATA.RULE_MODES:
		mission_rule_mode = MISSION_DATA.DEFAULT_RULE_MODE
	current_mission = MISSION_DATA.load_mission_for_rule_mode(
		level_id,
		mission_rule_mode,
	)
	current_mission_state = MISSION_STATE.new(current_mission)
	if objective_label != null:
		objective_label.text = "\n".join(current_mission_state.display_lines())


func load_imported_level(
	level_id: String = LEVEL_VIEW.DEFAULT_LEVEL_ID,
	preloaded_bundle: Dictionary = {},
) -> bool:
	if world_spatial_index != null:
		world_spatial_index.clear()
	_cancel_burial_command()
	_remove_sight_beacon()
	_clear_sight_observation_target()
	_clear_tactical_visible_enemies()
	sight_observation_mode = false
	sight_target_pending = false
	burial_mode = false
	if game_shell != null:
		game_shell.set_original_hud_action_state("observation", false)
	for world_object: Node2D in legacy_special_world_objects:
		if is_instance_valid(world_object):
			_free_level_runtime_node(world_object)
	legacy_special_world_objects.clear()
	for explosion_effect: Node2D in legacy_explosion_effects:
		if is_instance_valid(explosion_effect):
			_free_level_runtime_node(explosion_effect)
	legacy_explosion_effects.clear()
	for effect: Node in legacy_ai_control_effects:
		if is_instance_valid(effect):
			_free_level_runtime_node(effect)
	legacy_ai_control_effects.clear()
	for deployment_target: Node2D in legacy_deployment_targets:
		if is_instance_valid(deployment_target):
			_free_level_runtime_node(deployment_target)
	legacy_deployment_targets.clear()
	for burial_cache: Node2D in legacy_burial_caches:
		if is_instance_valid(burial_cache):
			_free_level_runtime_node(burial_cache)
	legacy_burial_caches.clear()
	# Enemy inventory drops are direct children of Main, unlike authored DBL
	# pickups under ImportedEntities.  Free them before clearing the registry;
	# otherwise an uncollected drop survives a restart as an orphaned node.
	_clear_runtime_mission_pickups()
	legacy_doors.clear()
	legacy_navigation_passages.clear()
	dormant_destruction_effects_by_scene.clear()
	_clear_original_pickup_order()
	_clear_original_drop_order()
	field_pickups.clear()
	explosive_props.clear()
	field_inventory.clear()
	selected_backpack_item_id = 0
	buried_enemy_scene_indices.clear()
	remove_imported_node("ImportedTerrain")
	remove_imported_node("ImportedEntities")
	LEGACY_ROW_SLICE_SPRITE_SCRIPT.clear_texture_cache()
	playable_entities.clear()
	enemy_entities.clear()
	ambient_entities.clear()
	current_level_animation_cache_keys.clear()
	imported_texture_cache.clear()
	# Parsed sprite manifests are needed only while assembling action groups.
	# Their textures remain in imported_animation_cache across level switches.
	IMPORTED_SPRITE_ANIMATION.clear_manifest_document_cache()
	# Animation atlases are shared by the same 43 runtime actor sprite types
	# throughout the campaign.  Keep this cache for the lifetime of the session:
	# clearing it here forced PNG/JSON decoding back onto every level switch and
	# made the first m006/m007 reconstruction exceed ten seconds on the reference
	# machine.  Static scenery still lives in imported_texture_cache and is freed
	# above, so retaining actor action groups does not pin every map decoration.
	# A process restart or content-package reload naturally creates a fresh cache.
	world_entities_by_scene.clear()
	activated_mission_scenes.clear()
	next_mission_pickup_serial = 1
	next_legacy_reinforcement_scene_index = 1000000
	next_legacy_reinforcement_serial = 1
	legacy_global_alarm_active = false
	legacy_global_alarm_counter = 0
	imported_entity_count = 0
	navigation_grid = null
	dynamic_occupancy = null
	current_level_directory = (
		ProjectSettings.globalize_path(IMPORTED_LEVEL_DATA.level_path(level_id)).get_base_dir()
	)
	converted_root = (
		ProjectSettings.globalize_path("res://../LocalAssets/converted").simplify_path()
	)
	if content_package_validation.is_empty():
		content_package_validation = CONTENT_PACKAGE_VALIDATOR.validate(
			converted_root.get_base_dir().path_join("content-manifest.json"),
			converted_root,
			"repository-mod-12-level-20260729",
			OS.has_feature("editor"),
		)
		if not bool(content_package_validation.get("ok", false)):
			terrain_loaded = false
			world_size = DEFAULT_WORLD_SIZE
			movement_bounds = DEFAULT_MOVEMENT_BOUNDS
			configure_level_camera(true)
			var failures := (
				content_package_validation.get("failures", []) as Array
			)
			update_status(tr("STATUS_CONTENT_PACKAGE_INVALID") % "; ".join(failures))
			push_error("Content package validation failed: %s" % failures)
			return false
	if game_shell != null:
		game_shell.configure_original_hud_assets(converted_root)
	if legacy_cursor_presenter != null:
		legacy_cursor_presenter.load_from_converted_root(converted_root)
	var level_source_value: Variant = preloaded_bundle.get("level_source", {})
	imported_level = (
		IMPORTED_LEVEL_DATA.parse_dictionary(level_source_value as Dictionary)
		if level_source_value is Dictionary and not (level_source_value as Dictionary).is_empty()
		else IMPORTED_LEVEL_DATA.load_level(level_id)
	)
	var terrain_image_value: Variant = preloaded_bundle.get("terrain_image")
	var imported: Dictionary = (
		LEVEL_VIEW.terrain_from_image(
			terrain_image_value as Image,
			ProjectSettings.globalize_path(LEVEL_VIEW.imported_terrain_path(level_id)),
		)
		if terrain_image_value is Image
		else LEVEL_VIEW.load_imported_terrain(level_id)
	)
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
	terrain.z_index = WORLD_DEPTH.TERRAIN_Z
	add_child(terrain)
	move_child(terrain, 0)

	terrain_loaded = true
	world_size = imported["size"] as Vector2
	# Original movement commands resolve to the centre of the 32x16
	# navigation cells at the map edge. Stable MOD m009, for example, accepts
	# (16, 1256) exactly. A symmetric 24-pixel presentation margin silently
	# changed that command to (24, 1256).
	var margin := Vector2(16.0, 8.0)
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
	loaded.native_runtime_paths_enabled = (
		str(runtime_settings.get("ruleset_mode", "classic")) == "modern"
	)
	return loaded


func remove_imported_node(node_name: String) -> void:
	var existing := get_node_or_null(node_name)
	if existing != null:
		_free_level_runtime_node(existing)


func _free_level_runtime_node(node: Node) -> void:
	# Level reconstruction is synchronous and no discarded node is allowed to
	# survive into the newly playable scene. Deferred deletion of thousands of
	# sprites and their ImageTextures previously produced a later 0.4–1.0 s
	# hitch, most visibly when entering m007.
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


func _clear_runtime_mission_pickups() -> int:
	var removed := 0
	for mission_pickup: Node2D in mission_pickups:
		if is_instance_valid(mission_pickup):
			_free_level_runtime_node(mission_pickup)
			removed += 1
	mission_pickups.clear()
	return removed


func spawn_imported_entities() -> int:
	if imported_level.is_empty():
		return 0

	var container := Node2D.new()
	container.name = "ImportedEntities"
	add_child(container)
	var spawned := 0
	var entities: Array = imported_level["entities"] as Array
	var level_id := str(
		current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])
	)
	for entity_value: Variant in entities:
		var entity := entity_value as Dictionary
		var scene_index := int(entity["scene_index"])
		var authored_faction_id := int(
			entity.get("faction_id", entity.get("team_id", 0))
		)
		var runtime_faction_id: int = (
			ORIGINAL_RUNTIME_ACTOR_CATALOG.runtime_faction_id(
				level_id,
				scene_index,
				authored_faction_id,
			)
		)
		var original_runtime_profile: Dictionary = (
			ORIGINAL_RUNTIME_ACTOR_CATALOG.actor_for_scene(
				level_id,
				scene_index,
			)
		)
		# Every live RuntimeActor belongs to the same native array. Attach its
		# recovered identity before branching into player, escort, enemy or
		# ambient construction; otherwise the early player/rescue branches lose
		# their runtime index and cannot participate in exact update scheduling.
		var runtime_entity := entity
		if (
			runtime_faction_id != authored_faction_id
			or not original_runtime_profile.is_empty()
		):
			runtime_entity = entity.duplicate(true)
		if not original_runtime_profile.is_empty():
			runtime_entity["original_runtime_profile"] = original_runtime_profile
			runtime_entity["original_runtime_profile_source"] = (
				"stable_mod_read_only_process_snapshot"
			)
		if runtime_faction_id != authored_faction_id:
			runtime_entity["faction_id"] = runtime_faction_id
			runtime_entity["runtime_faction_override"] = true
		var rescue_bound := _is_rescue_bound_scene(scene_index)
		# Keep the public scene dictionary byte-faithful for ordinary scenery and
		# actors. Escort construction reads through this dictionary, so only its
		# early branch needs the enriched runtime identity here.
		world_entities_by_scene[scene_index] = (
			runtime_entity if rescue_bound else entity
		)
		var display_name := entity["display_name"] as String
		if rescue_bound:
			spawned += 1
			continue
		var original_player_loadout: Dictionary = (
			ORIGINAL_INITIAL_WEAPON_INVENTORY.loadout_for_scene(
				level_id,
				scene_index,
			)
		)
		if not original_player_loadout.is_empty():
			playable_entities[display_name] = runtime_entity
			continue
		if (
			authored_faction_id == 3
			and _is_original_squad_display_name(display_name)
		):
			# Some original player slots remain controllable while their live
			# faction differs from the authored VWF faction.  m007 Tiedan is
			# the recovered case: scene 2298 occupies player slot 2 but starts
			# as faction 1, so the faction-only inventory catalog deliberately
			# does not list it under `players`.
			var controllable_entity := runtime_entity.duplicate(true)
			controllable_entity["original_controllable_slot_override"] = true
			playable_entities[display_name] = controllable_entity
			continue
		var database_entry_id := int(entity.get("database_entry_id", 0))
		var permanent_passage_profile: Dictionary = (
			LEGACY_DOOR_CATALOG.permanent_passage_profile_for_entity(entity)
		)
		if not permanent_passage_profile.is_empty():
			var passage_texture := load_entity_texture(entity)
			if passage_texture != null:
				legacy_navigation_passages.append({
					"scene_index": scene_index,
					"entity": entity.duplicate(true),
					"profile": permanent_passage_profile,
					"texture_size": passage_texture.get_size(),
					"movement_release_cells": [],
					"sight_release_cells": [],
				})
		var door_profile: Dictionary = LEGACY_DOOR_CATALOG.profile_for_entity(
			entity
		)
		if not door_profile.is_empty():
			var starts_open := bool(door_profile.get("starts_open", false))
			var closed_door_texture := (
				_load_converted_texture(
					str(door_profile.get("closed_sprite_relative_path", ""))
				)
				if starts_open
				else load_entity_texture(entity)
			)
			var open_door_texture := (
				load_entity_texture(entity)
				if starts_open
				else _load_converted_texture(
					str(door_profile.get("open_sprite_relative_path", ""))
				)
			)
			var closed_door_draw_order := (
				load_draw_order_profile_for_preview(
					_gfl_preview_path(
						int(door_profile.get("closed_gfl_index", 0))
					)
				)
				if starts_open
				else load_entity_draw_order_profile(entity)
			)
			var open_door_draw_order := (
				load_entity_draw_order_profile(entity)
				if starts_open
				else load_draw_order_profile_for_preview(
					_gfl_preview_path(
						int(door_profile.get("open_gfl_index", 0))
					)
				)
			)
			var door: Node2D = LEGACY_DOOR_SCRIPT.new()
			if bool(
				door.call(
					"configure",
					entity,
					door_profile,
					closed_door_texture,
					open_door_texture,
					imported_entity_z_index(entity),
					closed_door_draw_order,
					open_door_draw_order,
				)
			):
				door.name = "LegacyDoor_%04d" % scene_index
				container.add_child(door)
				door.connect(
					"state_changed",
					Callable(self, "_on_legacy_door_state_changed"),
				)
				legacy_doors.append(door)
				spawned += 1
				continue
			door.free()
		var interactable_profile: Dictionary = (
			WORLD_PICKUP_CATALOG.profile_for_database_entry_id(database_entry_id)
		)
		if not interactable_profile.is_empty():
			var interactable_texture := load_entity_texture(entity)
			if str(interactable_profile.get("behavior", "")) == "field_pickup":
				var pickup: Node2D = FIELD_PICKUP_SCRIPT.new()
				pickup.name = "FieldPickup_%04d" % scene_index
				if pickup.configure(
					interactable_profile,
					entity,
					interactable_texture,
					load_entity_draw_order_profile(entity),
				):
					container.add_child(pickup)
					field_pickups.append(pickup)
					spawned += 1
					continue
				pickup.free()
			elif str(interactable_profile.get("behavior", "")) == "explosive_prop":
				var prop: Node2D = EXPLOSIVE_PROP_SCRIPT.new()
				prop.name = "ExplosiveProp_%04d" % scene_index
				if prop.configure(
					interactable_profile,
					entity,
					interactable_texture,
					load_entity_draw_order_profile(entity),
				):
					container.add_child(prop)
					prop.explosion_requested.connect(_on_world_explosion_requested)
					prop.tree_exited.connect(
						Callable(self, "_on_explosive_prop_exited").bind(prop)
					)
					explosive_props.append(prop)
					spawned += 1
					continue
				prop.free()
		if (
			runtime_faction_id == 1
			or _is_mission_combat_target_scene(scene_index)
		):
			enemy_entities.append(runtime_entity)
			spawned += 1
			continue
		if (
			str(entity.get("category_name", "")) == "角色"
			and runtime_faction_id in [2, 3]
		):
			# Neutral animals, vehicles and non-objective civilians are live
			# RuntimeActor objects in the MOD, not baked scenery sprites.
			ambient_entities.append(runtime_entity)
			spawned += 1
			continue
		var texture := load_entity_texture(entity)
		if texture == null:
			continue

		var sprite_z_index := imported_entity_z_index(entity)
		if imported_entity_render_queue(entity) == 0:
			var draw_order_profile := load_entity_draw_order_profile(entity)
			var frame_size: Variant = draw_order_profile.get(
				"frame_size",
				Vector2i.ZERO,
			)
			if (
				not draw_order_profile.is_empty()
				and frame_size is Vector2i
				and frame_size
					== Vector2i(
						int(round(texture.get_width())),
						int(round(texture.get_height())),
					)
			):
				var anchor := imported_entity_sprite_anchor(entity, texture)
				var row_lookup := normalized_draw_order_rows(
					draw_order_profile.get("draw_order_row_lookup", [])
				)
				if draw_order_rows_are_uniform(row_lookup):
					sprite_z_index = WORLD_DEPTH.normal_z(
						float(
							entity.get(
								"reference_y",
								entity.get("y", 0.0),
							)
						)
						- anchor.y
						+ float(row_lookup[0])
					)
				elif not row_lookup.is_empty():
					var row_sprite: Node2D = (
						LEGACY_ROW_SLICE_SPRITE_SCRIPT.new()
					)
					row_sprite.name = (
						"Entity_%04d" % int(entity["scene_index"])
					)
					row_sprite.position = Vector2(
						float(entity["x"]),
						float(entity["y"]),
					)
					if bool(
						row_sprite.call(
							"configure",
							texture,
							anchor,
							float(
								entity.get(
									"reference_y",
									entity.get("y", 0.0),
								)
							),
							row_lookup,
						)
					):
						if (
							imported_entity_is_dormant_destruction_effect(entity)
							or imported_entity_is_hidden_trigger(entity)
						):
							row_sprite.visible = false
						if imported_entity_is_dormant_destruction_effect(entity):
							dormant_destruction_effects_by_scene[
								scene_index
							] = row_sprite
						container.add_child(row_sprite)
						spawned += 1
						continue
					row_sprite.free()

		var sprite := Sprite2D.new()
		sprite.name = "Entity_%04d" % int(entity["scene_index"])
		sprite.texture = texture
		sprite.position = Vector2(float(entity["x"]), float(entity["y"]))
		sprite.offset = (
			texture.get_size() * 0.5
			- imported_entity_sprite_anchor(entity, texture)
		)
		sprite.z_index = sprite_z_index
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if (
			imported_entity_is_dormant_destruction_effect(entity)
			or imported_entity_is_hidden_trigger(entity)
		):
			sprite.visible = false
		if imported_entity_is_dormant_destruction_effect(entity):
			dormant_destruction_effects_by_scene[scene_index] = sprite
		container.add_child(sprite)
		spawned += 1
	return spawned


static func imported_entity_z_index(entity: Dictionary) -> int:
	# The first recovered DBL header value is the original four-queue selector.
	# Queue 1 contains flat ground/shadows, queue 0 shares actor depth sorting,
	# queue 2 is fixed foreground and queue 3 is topmost.
	return WORLD_DEPTH.imported_z(
		imported_entity_render_queue(entity),
		float(entity.get("reference_y", entity.get("y", 0.0))),
	)


static func imported_entity_render_queue(entity: Dictionary) -> int:
	var header_values: Variant = entity.get("database_header_values", [])
	if header_values is Array and not (header_values as Array).is_empty():
		return int((header_values as Array)[0])
	return 0


static func normalized_draw_order_rows(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for raw_row: Variant in value as Array:
		if not raw_row is int and not raw_row is float:
			return []
		var row_value := float(raw_row)
		if not is_finite(row_value) or row_value != float(int(row_value)):
			return []
		result.append(int(row_value))
	return result


static func draw_order_rows_are_uniform(rows: Array[int]) -> bool:
	if rows.is_empty():
		return false
	var first := rows[0]
	for row_index: int in range(1, rows.size()):
		if rows[row_index] != first:
			return false
	return true


static func imported_entity_sprite_anchor(
	entity: Dictionary,
	texture: Texture2D,
) -> Vector2:
	var value: Variant = entity.get("sprite_anchor", {})
	if value is Dictionary:
		var anchor := value as Dictionary
		if anchor.has("x") and anchor.has("y"):
			return Vector2(
				float(anchor["x"]),
				float(anchor["y"]),
			)
	return texture.get_size() * 0.5 if texture != null else Vector2.ZERO


static func imported_entity_is_dormant_destruction_effect(
	entity: Dictionary,
) -> bool:
	var header_values: Variant = entity.get("database_header_values", [])
	if not header_values is Array or (header_values as Array).size() < 3:
		return false
	# DBL runtime types 66/67/68/77 are the four 残毁效果 overlays. The
	# original scene registers them as dormant replacements and only exposes
	# them after the paired destructible has resolved; drawing them at load
	# punches black "damage" holes through otherwise intact roofs and walls.
	return int((header_values as Array)[2]) in [66, 67, 68, 77]


static func imported_entity_is_hidden_trigger(entity: Dictionary) -> bool:
	# These DBL entries are nonvisual world detectors. DBL 1018 ("标注")
	# is deliberately absent: its red map marker is visible in the original.
	return int(entity.get("database_entry_id", 0)) in [
		1001, # buried-state detector
		1008, # line-of-sight detector
		1010, # entrance detector
		1011, # enemy-spawn detector
		1019, # explosion detector
		1020, # exit detector
	]


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
	var cache_key := "%s|%s|sparse" % [preview_path, action_key]
	if imported_animation_cache.has(cache_key):
		current_level_animation_cache_keys[cache_key] = true
		return imported_animation_cache[cache_key] as Array[Dictionary]
	var groups: Array[Dictionary] = IMPORTED_SPRITE_ANIMATION.load_action_groups(
		preview_path,
		action_key,
		true,
	)
	imported_animation_cache[cache_key] = groups
	current_level_animation_cache_keys[cache_key] = true
	return groups


func load_entity_draw_order_profile(entity: Dictionary) -> Dictionary:
	var preview_path := entity_preview_path(entity)
	return load_draw_order_profile_for_preview(preview_path)


func load_draw_order_profile_for_preview(preview_path: String) -> Dictionary:
	if preview_path.is_empty():
		return {}
	var cache_key := "%s|draw-order|0" % preview_path
	if imported_animation_cache.has(cache_key):
		return imported_animation_cache[cache_key] as Dictionary
	var profile: Dictionary = (
		IMPORTED_SPRITE_ANIMATION.load_draw_order_profile(preview_path, 0)
	)
	imported_animation_cache[cache_key] = profile
	return profile


func _gfl_preview_path(gfl_index: int) -> String:
	if converted_root.is_empty() or gfl_index <= 0:
		return ""
	var relative_path := "sprites/%04d.png" % gfl_index
	var preview_path := _contained_converted_path(converted_root, relative_path)
	if preview_path.is_empty() or not FileAccess.file_exists(preview_path):
		return ""
	return preview_path


func _load_gfl_texture(gfl_index: int) -> Texture2D:
	var preview_path := _gfl_preview_path(gfl_index)
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


func _load_gfl_action_groups(
	gfl_index: int,
	action_key: String,
) -> Array[Dictionary]:
	var preview_path := _gfl_preview_path(gfl_index)
	if preview_path.is_empty():
		return []
	var cache_key := "%s|%s|strict" % [preview_path, action_key]
	if imported_animation_cache.has(cache_key):
		current_level_animation_cache_keys[cache_key] = true
		return imported_animation_cache[cache_key] as Array[Dictionary]
	var groups: Array[Dictionary] = (
		IMPORTED_SPRITE_ANIMATION.load_action_groups(
			preview_path,
			action_key,
		)
	)
	imported_animation_cache[cache_key] = groups
	current_level_animation_cache_keys[cache_key] = true
	return groups


func _register_permanent_navigation_passages() -> int:
	if dynamic_occupancy == null or navigation_grid == null:
		return 0
	var registered := 0
	for passage_index: int in range(legacy_navigation_passages.size()):
		var passage := legacy_navigation_passages[passage_index]
		var entity := passage.get("entity", {}) as Dictionary
		var profile := passage.get("profile", {}) as Dictionary
		var texture_size: Vector2 = passage.get(
			"texture_size",
			Vector2.ZERO,
		) as Vector2
		var movement_cells: Array[Vector2i] = (
			LEGACY_DOOR_CATALOG.local_source_cells_for_passage(
				entity,
				texture_size,
				navigation_grid,
				NAVIGATION_GRID_DATA.MOVEMENT_LAYER_ID,
			)
		)
		var sight_cells: Array[Vector2i] = (
			LEGACY_DOOR_CATALOG.local_source_cells_for_passage(
				entity,
				texture_size,
				navigation_grid,
				NAVIGATION_GRID_DATA.LINE_OF_SIGHT_LAYER_ID,
			)
		)
		passage["movement_release_cells"] = movement_cells
		passage["sight_release_cells"] = sight_cells
		legacy_navigation_passages[passage_index] = passage
		if bool(dynamic_occupancy.call(
			"register_source_scene_footprint",
			int(passage.get("scene_index", -1)),
			movement_cells,
			sight_cells,
			true,
			bool(profile.get("release_sight", true)),
		)):
			registered += 1
	return registered


func create_level_camera() -> void:
	level_camera = Camera2D.new()
	level_camera.name = "LevelCamera"
	# Velocity is smoothed explicitly by SmoothCameraPan. Camera2D's second
	# smoothing pass used to add lag and edge jitter, especially in a window.
	level_camera.position_smoothing_enabled = false
	# Actor transforms are physics-interpolated, but the camera is advanced on
	# every rendered frame. Interpolating it a second time would reintroduce the
	# uneven vertical stepping this explicit velocity controller avoids.
	level_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	var spawn_started_usec := Time.get_ticks_usec()
	var spawn_phase_started_usec := spawn_started_usec
	last_squad_spawn_phase_usec.clear()
	if projectile_world != null:
		_free_level_runtime_node(projectile_world)
	projectile_world = PROJECTILE_WORLD_SCRIPT.new()
	projectile_world.name = "ProjectileWorld"
	add_child(projectile_world)
	projectile_world.configure_runtime(
		navigation_grid,
		dynamic_occupancy,
		_load_legacy_projectile_visual_catalog(),
		Callable(self, "_commit_original_dynamic_actor_factory"),
		Callable(self, "_commit_original_dynamic_actor_destructor"),
		world_spatial_index,
	)
	projectile_world.projectile_damage_applied.connect(_on_projectile_damage_applied)
	projectile_world.projectile_impact_created.connect(_on_projectile_impact_created)
	projectile_world.projectile_exploded.connect(_on_projectile_exploded)
	projectile_world.projectile_explosion_actor_requested.connect(
		_on_projectile_explosion_actor_requested
	)
	for unit: SQUAD_UNIT in units:
		_free_level_runtime_node(unit)
	for enemy: ENEMY_UNIT in enemies:
		_free_level_runtime_node(enemy)
	for escort: ESCORT_UNIT in escorts:
		_free_level_runtime_node(escort)
	for ambient: AMBIENT_UNIT in ambient_units:
		_free_level_runtime_node(ambient)
	for pickup: MISSION_PICKUP in mission_pickups:
		_free_level_runtime_node(pickup)
	units.clear()
	enemies.clear()
	escorts.clear()
	ambient_units.clear()
	original_runtime_actor_order_cache.clear()
	original_runtime_actor_order_cache_rebuild_serial = 0
	mission_pickups.clear()
	selected_units.clear()
	dynamic_occupancy = null
	last_squad_spawn_phase_usec["cleanup_and_projectile_world"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	if navigation_grid != null:
		dynamic_occupancy = DYNAMIC_OCCUPANCY_GRID.new()
		var level_id := str(
			current_mission.get(
				"id",
				FORMAL_LEVEL_IDS[current_level_index],
			)
		)
		dynamic_occupancy.configure(
			navigation_grid,
			"initial-static:%s" % level_id,
		)
		for door: Node2D in legacy_doors:
			if is_instance_valid(door) and door.has_method(
				"bind_dynamic_occupancy"
			):
				door.call("bind_dynamic_occupancy", dynamic_occupancy)
		_register_permanent_navigation_passages()
	last_squad_spawn_phase_usec["dynamic_grid"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()

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
		var run_groups: Array[Dictionary] = []
		var walk_groups: Array[Dictionary] = []
		var crawl_groups: Array[Dictionary] = []
		var scene_index := -1
		var source_reference_position: Variant = null
		var entity: Dictionary = {}
		if playable_entities.has(name):
			entity = playable_entities[name] as Dictionary
			scene_index = int(entity["scene_index"])
			source_reference_position = Vector2(
				float(entity["reference_x"]), float(entity["reference_y"])
			)
			# VWF x/y is frequently a patrol/action endpoint. The original
			# RuntimeActor world coordinate is initialized from the reference
			# pair, which is therefore the authoritative live spawn.
			start_position = source_reference_position
			texture = load_entity_texture(entity)
			run_groups = load_entity_action_groups(entity, "run")
			walk_groups = load_entity_action_groups(entity, "walk")
			crawl_groups = load_entity_action_groups(entity, "crawl")
			movement_groups = run_groups if not run_groups.is_empty() else walk_groups
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
		unit.configure_runtime_actor_type(entity)
		unit.configure_modern_navigation_footprint(
			SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(
				unit.runtime_actor_type
			)
		)
		_bind_original_crt_random_actor(unit)
		unit.configure_movement_modes(run_groups, walk_groups, crawl_groups)
		if not entity.is_empty():
			var authored_direction := (
				unit.original_native_initial_facing_direction(
					int(entity.get("direction_index", 1))
				)
			)
			unit.set_animation_group(
				IMPORTED_SPRITE_ANIMATION.legacy_group_index_for_direction(
					authored_direction
				)
			)
			unit.apply_idle_frame()
		var attack_type := playable_initial_attack_type(entity, name)
		var level_id := str(
			current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])
		)
		var original_loadout: Dictionary = (
			ORIGINAL_INITIAL_WEAPON_INVENTORY.loadout_for_actor(
				level_id,
				scene_index,
				name,
			)
		)
		if original_loadout.is_empty() and not entity.is_empty():
			original_loadout = (
				ORIGINAL_INITIAL_WEAPON_INVENTORY.loadout_for_any_actor(
					level_id,
					scene_index,
					name,
				)
			)
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
			int(entity.get("faction_id", 3)),
			maxi(int(entity.get("current_hit_points", 8)), 1),
			weapon_profile,
			attack_groups,
			death_groups,
			false,
			original_loadout.is_empty(),
		)
		# Only actors constructed in the player's command roster use the modern
		# fixed accuracy model. Enemy/ambient subclasses keep their own rules.
		unit.modern_player_combat_rules_enabled = true
		if not original_loadout.is_empty():
			for item_value: Variant in original_loadout.get("items", []):
				if not item_value is Dictionary:
					continue
				var item := item_value as Dictionary
				var initial_attack_type: int = (
					ORIGINAL_INITIAL_WEAPON_INVENTORY.attack_type_for_item_id(
						int(item.get("item_id", 0))
					)
				)
				var initial_profile: Dictionary = (
					COMBAT_PROFILES.weapon_profile_for_attack_type(
						initial_attack_type
					)
				)
				if initial_profile.is_empty():
					continue
				unit.register_original_inventory_weapon(
					initial_profile,
					_attack_groups_for_unit(
						unit,
						str(initial_profile.get("action_key", "")),
					),
					int(item.get("quantity", 0)),
					int(item.get("quantity_mode", -1)),
					initial_attack_type == attack_type,
				)
			unit.equip_attack_type(attack_type)
		else:
			# Synthetic/no-asset scenes retain a compact compatibility loadout.
			# Every imported MOD level is required to resolve the exact catalog.
			for initial_attack_type: int in [4, 1, 2]:
				if initial_attack_type == attack_type:
					continue
				var initial_profile: Dictionary = (
					COMBAT_PROFILES.weapon_profile_for_attack_type(
						initial_attack_type
					)
				)
				if not initial_profile.is_empty():
					unit.register_inventory_weapon(
						initial_profile,
						[],
						true,
						false,
					)
		_configure_original_backpack(unit, level_id, scene_index, name)
		_connect_combatant(unit)
		units.append(unit)
	last_squad_spawn_phase_usec["players"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_spawn_escorts()
	last_squad_spawn_phase_usec["escorts"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_spawn_ambient_units()
	last_squad_spawn_phase_usec["ambient_units"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_spawn_enemies()
	last_squad_spawn_phase_usec["enemies"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_stage_loaded_animation_footprint_profiles()
	last_squad_spawn_phase_usec["stage_footprints"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	if dynamic_occupancy != null:
		dynamic_occupancy.finalize_registration()
	last_squad_spawn_phase_usec["finalize_occupancy"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_configure_modern_enemy_patrol_groups()
	last_squad_spawn_phase_usec["modern_patrol_groups"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	if dynamic_occupancy != null:
		_prewarm_authored_patrol_paths()
	last_squad_spawn_phase_usec["patrol_prewarm"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	_link_original_pursuit_actors()
	var target_nodes: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		target_nodes.append(unit)
	for escort: ESCORT_UNIT in escorts:
		target_nodes.append(escort)
	for enemy: ENEMY_UNIT in enemies:
		enemy.set_potential_targets(target_nodes)
	_refresh_enemy_corpse_candidates()
	_refresh_enemy_world_items()
	_refresh_projectile_world_combatants()
	last_squad_spawn_phase_usec["runtime_links"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	spawn_phase_started_usec = Time.get_ticks_usec()
	# The stable MOD exposes every available portrait in its idle (grayscale)
	# state when a mission first opens.  A character becomes selected only after
	# an original F2-F6 shortcut or a world/HUD click; initial_camera_focus()
	# already places the camera over the first available squad member.
	_refresh_inventory_ui()
	last_squad_spawn_phase_usec["initial_selection"] = (
		Time.get_ticks_usec() - spawn_phase_started_usec
	)
	last_squad_spawn_phase_usec["total"] = (
		Time.get_ticks_usec() - spawn_started_usec
	)


func _link_original_pursuit_actors() -> int:
	var actors_by_runtime_index: Dictionary = {}
	var actors_by_scene_index: Dictionary = {}
	for actor: Node2D in _all_active_runtime_actors():
		var runtime_index := int(actor.get("original_runtime_index"))
		if runtime_index >= 0:
			actors_by_runtime_index[runtime_index] = actor
		var actor_scene_index := int(actor.get("scene_index"))
		if actor_scene_index >= 0:
			actors_by_scene_index[actor_scene_index] = actor
	var linked_count := 0
	for actor: Node2D in _all_active_runtime_actors():
		var target_runtime_index := int(
			actor.get("original_pursuit_target_runtime_index")
		)
		var target_scene_index := int(
			actor.get("original_pursuit_target_scene_index")
		)
		if target_runtime_index < 0 and target_scene_index < 0:
			continue
		var target_value: Variant = (
			actors_by_runtime_index.get(target_runtime_index)
			if target_runtime_index >= 0
			else actors_by_scene_index.get(target_scene_index)
		)
		if (
			target_value is Node2D
			and bool(actor.call(
				"bind_original_pursuit_target",
				target_value as Node2D,
			))
		):
			linked_count += 1
		else:
			push_error(
				(
					(
						"Missing original pursuit target runtime=%d scene=%d "
						+ "for runtime actor %d"
					)
				)
				% [
					target_runtime_index,
					target_scene_index,
					int(actor.get("original_runtime_index")),
				]
			)
	return linked_count


func _stage_loaded_animation_footprint_profiles() -> int:
	if dynamic_occupancy == null or navigation_grid == null:
		return 0
	var staged_count := 0
	if str(runtime_settings.get("ruleset_mode", "classic")) == "modern":
		# Modern human actors deliberately use a one-cell navigation footprint;
		# their large per-frame pixel masks are presentation metadata and must not
		# trigger whole-map clearance grids. Only carts, animals and vehicles retain
		# authored multi-cell movement profiles. This keeps level reconstruction
		# bounded without changing classic compatibility behavior.
		for actor: Node2D in _all_active_runtime_actors():
			if bool(actor.get("use_compact_navigation_footprint")):
				continue
			if not actor.has_method("patrol_movement_footprint_profiles"):
				continue
			var profiles: Variant = actor.call(
				"patrol_movement_footprint_profiles"
			)
			if not profiles is Array:
				continue
			for profile_value: Variant in profiles as Array:
				if not profile_value is Array:
					continue
				var movement_offsets: Array[Vector2i] = []
				movement_offsets.assign(profile_value as Array)
				if dynamic_occupancy.stage_footprint_clearance(movement_offsets):
					staged_count += 1
		return staged_count
	var cache_keys: Array[String] = []
	for cache_key_value: Variant in current_level_animation_cache_keys.keys():
		cache_keys.append(str(cache_key_value))
	cache_keys.sort()
	for cache_key: String in cache_keys:
		var cache_value: Variant = imported_animation_cache.get(cache_key)
		if not cache_value is Array:
			continue
		for group_value: Variant in cache_value as Array:
			if (
				not group_value is Dictionary
				or not (group_value as Dictionary).has("movement_lookup")
				or not (group_value as Dictionary).has("lookup_dimensions")
			):
				continue
			var movement_offsets: Array[Vector2i] = (
				IMPORTED_SPRITE_ANIMATION.lookup_footprint_offsets(
					group_value as Dictionary,
					"movement_lookup",
					navigation_grid.cell_size,
				)
			)
			if dynamic_occupancy.stage_footprint_clearance(movement_offsets):
				staged_count += 1
	return staged_count


func _configure_modern_enemy_patrol_groups(force_for_test: bool = false) -> int:
	if not force_for_test and not _modern_patrol_groups_enabled():
		return 0
	var candidates: Array[ENEMY_UNIT] = []
	for enemy: ENEMY_UNIT in enemies:
		if not enemy.is_alive or not _patrol_route_has_extent(enemy):
			continue
		candidates.append(enemy)
	candidates.sort_custom(
		func(first: ENEMY_UNIT, second: ENEMY_UNIT) -> bool:
			var first_rank := _modern_patrol_leader_rank(first.display_name)
			var second_rank := _modern_patrol_leader_rank(second.display_name)
			if first_rank != second_rank:
				return first_rank > second_rank
			return first.scene_index < second.scene_index
	)
	var assigned: Dictionary = {}
	var group_id := 0
	var follower_offsets: Array[Vector2] = [
		Vector2(-24.0, 38.0),
		Vector2(24.0, 38.0),
		Vector2(0.0, 72.0),
	]
	for leader: ENEMY_UNIT in candidates:
		if assigned.has(leader.get_instance_id()):
			continue
		var nearby: Array[ENEMY_UNIT] = []
		for candidate: ENEMY_UNIT in candidates:
			if (
				candidate == leader
				or assigned.has(candidate.get_instance_id())
				or leader.position.distance_to(candidate.position) > 220.0
			):
				continue
			nearby.append(candidate)
		nearby.sort_custom(
			func(first: ENEMY_UNIT, second: ENEMY_UNIT) -> bool:
				var first_distance := leader.position.distance_squared_to(first.position)
				var second_distance := leader.position.distance_squared_to(second.position)
				if not is_equal_approx(first_distance, second_distance):
					return first_distance < second_distance
				return first.scene_index < second.scene_index
		)
		if nearby.is_empty():
			continue
		group_id += 1
		leader.configure_modern_patrol_formation(group_id, leader)
		assigned[leader.get_instance_id()] = true
		for follower_index: int in range(mini(nearby.size(), follower_offsets.size())):
			var follower := nearby[follower_index]
			follower.configure_modern_patrol_formation(
				group_id,
				leader,
				follower_offsets[follower_index],
			)
			assigned[follower.get_instance_id()] = true
	return group_id


func _modern_patrol_groups_enabled() -> bool:
	if OS.get_environment("M1937_REMAKE_DISABLE_MODERN_PATROLS") == "1":
		return false
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument == "--enable-modern-patrol-groups":
			return true
		if argument.contains("res://tests/") or argument.contains("\\tests\\"):
			return false
	return not _is_runtime_probe()


static func _patrol_route_has_extent(enemy: ENEMY_UNIT) -> bool:
	var waypoints := enemy.patrol_waypoints
	if waypoints.size() < 2:
		return false
	var origin := waypoints[0]
	for waypoint: Vector2 in waypoints:
		if origin.distance_to(waypoint) >= 24.0:
			return true
	return false


static func _modern_patrol_leader_rank(display_name: String) -> int:
	if display_name in ["山本", "龟田"]:
		return 50
	if display_name == "一等兵":
		return 30
	if display_name == "二等兵":
		return 20
	if display_name == "三等兵":
		return 10
	# Named specialists and collaborators lead generic rank-and-file actors,
	# while recognized officers still take precedence.
	return 40


func _prewarm_authored_patrol_paths() -> void:
	if dynamic_occupancy == null:
		return
	var patrol_actors: Array[Node2D] = []
	for enemy: ENEMY_UNIT in enemies:
		patrol_actors.append(enemy)
	for ambient: AMBIENT_UNIT in ambient_units:
		patrol_actors.append(ambient)
	for actor: Node2D in patrol_actors:
		if not bool(actor.get("patrol_enabled")):
			continue
		if actor is ENEMY_UNIT:
			var runtime_timeline_value: Variant = actor.get(
				"stable_mod_patrol_timeline"
			)
			if (
				runtime_timeline_value is Array
				and not (runtime_timeline_value as Array).is_empty()
			):
				_prewarm_stable_mod_patrol_timeline_paths(
					actor,
					runtime_timeline_value as Array,
				)
				# Stable runtime evidence supersedes the serialized waypoint
				# cycle for this actor. Prewarming both spends load time and
				# retains routes that gameplay will never request.
				continue
		var waypoints := actor.get("patrol_waypoints") as PackedVector2Array
		if waypoints.is_empty():
			continue
		var patrol_index := clampi(
			int(actor.get("patrol_index")),
			0,
			waypoints.size() - 1,
		)
		if (
			actor is AMBIENT_UNIT
			and actor.has_method(
				"patrol_movement_footprint_profiles"
			)
		):
			dynamic_occupancy.prewarm_patrol_cycle_footprint_profiles_for_scene(
				int(actor.get("scene_index")),
				actor.position,
				waypoints,
				patrol_index,
				actor.call("patrol_movement_footprint_profiles") as Array,
			)
		else:
			dynamic_occupancy.prewarm_patrol_cycle_for_scene(
				int(actor.get("scene_index")),
				actor.position,
				waypoints,
				patrol_index,
			)


func _prewarm_stable_mod_patrol_timeline_paths(
	actor: Node2D,
	timeline: Array,
) -> void:
	if dynamic_occupancy == null or timeline.size() < 2:
		return
	var actor_scene_index := int(actor.get("scene_index"))
	var movement_profiles: Array = (
		actor.call("patrol_movement_footprint_profiles") as Array
		if actor.has_method("patrol_movement_footprint_profiles")
		else []
	)
	for target_index: int in range(1, timeline.size()):
		var previous_value: Variant = timeline[target_index - 1]
		var target_value: Variant = timeline[target_index]
		if not previous_value is Dictionary or not target_value is Dictionary:
			continue
		var previous_position_value: Variant = (
			(previous_value as Dictionary).get("position")
		)
		var target_position_value: Variant = (
			(target_value as Dictionary).get("position")
		)
		if (
			not previous_position_value is Vector2
			or not target_position_value is Vector2
		):
			continue
		var previous_position := previous_position_value as Vector2
		var target_position := target_position_value as Vector2
		# Short captured corrections use the original component mover directly
		# and never ask A* for a route at runtime.
		if previous_position.distance_to(target_position) <= 48.0:
			continue
		dynamic_occupancy.prewarm_runtime_evidence_path_footprint_profiles_for_scene(
			actor_scene_index,
			previous_position,
			target_position,
			movement_profiles,
		)


static func playable_initial_attack_type(entity: Dictionary, display_name: String) -> int:
	var authored_attack_type := int(entity.get("default_attack_type", 0))
	if authored_attack_type >= 1 and authored_attack_type <= 11:
		return authored_attack_type
	return int(PLAYABLE_LOADOUT_ATTACK_TYPES.get(display_name, 1))


static func _is_original_squad_display_name(display_name: String) -> bool:
	for specification: Dictionary in PLAYABLE_SQUAD:
		if str(specification.get("name", "")) == display_name:
			return true
	return false


func _configure_original_backpack(
	actor: SQUAD_UNIT,
	level_id: String,
	scene_index: int,
	display_name: String,
) -> bool:
	if actor == null:
		return false
	var loadout: Dictionary = ORIGINAL_INITIAL_ITEM_INVENTORY.loadout_for_actor(
		level_id,
		scene_index,
		display_name,
	)
	return not loadout.is_empty() and actor.configure_original_backpack(loadout)


func _configure_original_weapon_container(
	actor: SQUAD_UNIT,
	entity: Dictionary,
	level_id: String,
) -> bool:
	if actor == null:
		return false
	var scene_index := int(entity.get("scene_index", -1))
	var display_name := str(entity.get("display_name", ""))
	var loadout: Dictionary = (
		ORIGINAL_INITIAL_WEAPON_INVENTORY.loadout_for_any_actor(
			level_id,
			scene_index,
			display_name,
		)
	)
	if loadout.is_empty():
		return false
	var configured := true
	for item_value: Variant in loadout.get("items", []):
		if not item_value is Dictionary:
			configured = false
			continue
		var item := item_value as Dictionary
		var attack_type: int = (
			ORIGINAL_INITIAL_WEAPON_INVENTORY.attack_type_for_item_id(
				int(item.get("item_id", 0))
			)
		)
		var profile: Dictionary = (
			COMBAT_PROFILES.weapon_profile_for_attack_type(attack_type)
		)
		if profile.is_empty() or not actor.register_original_inventory_weapon(
			profile,
			load_entity_action_groups(
				entity,
				str(profile.get("action_key", "")),
			),
			int(item.get("quantity", 0)),
			int(item.get("quantity_mode", -1)),
			false,
		):
			configured = false
	var authored_attack_type := int(loadout.get("default_attack_type", 0))
	if authored_attack_type > 0 and not actor.equip_attack_type(
		authored_attack_type
	):
		configured = false
	return configured


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
		var walk_groups := load_entity_action_groups(entity, "walk")
		var run_groups := load_entity_action_groups(entity, "run")
		var movement_groups := walk_groups if not walk_groups.is_empty() else run_groups
		var idle_groups := load_entity_action_groups(entity, "stand")
		var stand_action_groups := load_entity_action_groups(
			entity,
			"stand_action",
		)
		var death_groups := load_entity_action_groups(entity, "death")
		var escort_weapon: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
			int(entity.get("default_attack_type", 0))
		)
		var attack_groups: Array[Dictionary] = []
		if not escort_weapon.is_empty():
			attack_groups = load_entity_action_groups(
				entity,
				str(escort_weapon.get("action_key", "")),
			)
		var escort: ESCORT_UNIT = ESCORT_UNIT.new()
		add_child(escort)
		escort.configure_escort(
			entity,
			texture,
			movement_groups,
			idle_groups,
			death_groups,
			dynamic_occupancy,
			attack_groups,
		)
		escort.configure_modern_navigation_footprint(
			SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(
				escort.runtime_actor_type
			)
		)
		_bind_original_crt_random_actor(escort)
		escort.configure_original_rescue_rule(
			LEGACY_ESCORT_RULES.rule_for(
				str(current_mission.get(
					"id",
					FORMAL_LEVEL_IDS[current_level_index],
				)),
				escort.runtime_actor_type,
			)
		)
		escort.configure_original_ai_idle_animation(stand_action_groups)
		_configure_original_weapon_container(
			escort,
			entity,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
		)
		_configure_original_backpack(
			escort,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
			int(entity.get("scene_index", -1)),
			str(entity.get("display_name", "")),
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
		var walk_groups := load_entity_action_groups(entity, "walk")
		var run_groups := load_entity_action_groups(entity, "run")
		var movement_groups := walk_groups if not walk_groups.is_empty() else run_groups
		var idle_groups := load_entity_action_groups(entity, "stand")
		var stand_action_groups := load_entity_action_groups(
			entity,
			"stand_action",
		)
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
			run_groups,
		)
		enemy.configure_tactical_accessibility(
			bool(runtime_settings.get("colorblind_patterns", true)),
			bool(runtime_settings.get("high_contrast", false)),
		)
		enemy.configure_modern_navigation_footprint(
			SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(
				enemy.runtime_actor_type
			)
		)
		_bind_original_crt_random_actor(enemy)
		enemy.configure_original_ai_idle_animation(stand_action_groups)
		enemy.original_mission_number = int(
			current_mission.get("number", current_level_index + 1)
		)
		_configure_original_weapon_container(
			enemy,
			entity,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
		)
		_configure_original_backpack(
			enemy,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
			int(entity.get("scene_index", -1)),
			str(entity.get("display_name", "")),
		)
		_connect_combatant(enemy)
		enemies.append(enemy)


func _spawn_ambient_units() -> void:
	if dynamic_occupancy == null:
		return
	for entity: Dictionary in ambient_entities:
		var texture := load_entity_texture(entity)
		if texture == null:
			continue
		var movement_groups := load_entity_action_groups(entity, "walk")
		if movement_groups.is_empty():
			movement_groups = load_entity_action_groups(entity, "run")
		var idle_groups := load_entity_action_groups(entity, "stand")
		var stand_action_groups := load_entity_action_groups(
			entity,
			"stand_action",
		)
		var death_groups := load_entity_action_groups(entity, "death")
		var ambient: AMBIENT_UNIT = AMBIENT_UNIT.new()
		add_child(ambient)
		ambient.configure_ambient(
			entity,
			texture,
			movement_groups,
			idle_groups,
			death_groups,
			dynamic_occupancy,
		)
		ambient.configure_modern_navigation_footprint(
			SQUAD_UNIT.runtime_actor_uses_compact_biped_navigation(
				ambient.runtime_actor_type
			)
		)
		_bind_original_crt_random_actor(ambient)
		ambient.configure_original_ai_idle_animation(stand_action_groups)
		_configure_original_weapon_container(
			ambient,
			entity,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
		)
		_configure_original_backpack(
			ambient,
			str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
			int(entity.get("scene_index", -1)),
			str(entity.get("display_name", "")),
		)
		_connect_combatant(ambient)
		ambient_units.append(ambient)


func _process(delta: float) -> void:
	if performance_monitor != null:
		performance_monitor.begin_frame()
	_synchronize_world_spatial_index(delta)
	if navigation_requests != null:
		var processed_navigation_requests := int(
			navigation_requests.process_budget(
				dynamic_occupancy,
				navigation_grid,
				2000,
				3,
			)
		)
		if processed_navigation_requests > 0 and performance_monitor != null:
			performance_monitor.increment(
				"deferred_navigation_requests",
				processed_navigation_requests,
			)
	_advance_sight_observation(delta)
	_update_tactical_sight_visibility()
	_advance_original_disguise_state(delta)
	if mission_direction_runtime != null:
		mission_direction_runtime.advance_time(maxf(delta, 0.0))
	if mission_ai_coordinator != null:
		mission_ai_coordinator.advance_time(maxf(delta, 0.0))
	if mission_runtime != null and mission_runtime.is_configured():
		mission_runtime.advance_time(maxf(delta, 0.0))
		mission_zone_elapsed += maxf(delta, 0.0)
		if mission_zone_elapsed >= MISSION_ZONE_CHECK_SECONDS:
			mission_zone_elapsed = fmod(mission_zone_elapsed, MISSION_ZONE_CHECK_SECONDS)
			_evaluate_transient_mission_zones()
	minimap_refresh_elapsed += maxf(delta, 0.0)
	var controls := runtime_settings.get("controls", {}) as Dictionary
	var force_up_held: bool = GAME_INPUT_BINDINGS.action_is_held(
		"force_target_up", controls
	)
	original_force_target_held = (
		GAME_INPUT_BINDINGS.action_is_held("force_target_ctrl", controls)
		or force_up_held
	)
	_update_context_cursor(delta)
	_update_combat_preview(delta)
	if (
		game_shell != null
		and game_shell.is_tactical_map_visible()
		and minimap_refresh_elapsed >= MINIMAP_REFRESH_SECONDS
	):
		minimap_refresh_elapsed = fmod(minimap_refresh_elapsed, MINIMAP_REFRESH_SECONDS)
		game_shell.update_tactical_map(
			_tactical_actor_markers(),
			_tactical_mission_markers(),
			_camera_world_rect(),
		)
	if level_camera == null:
		if performance_monitor != null:
			performance_monitor.end_frame()
		return
	_sync_level_camera_safe_area()
	var keyboard_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# Up is an original held-state force-target key, not a camera key. Mouse
	# edge scrolling remains the faithful camera control; left/right/down arrow
	# support is a remake convenience.
	if force_up_held:
		keyboard_direction.y = maxf(keyboard_direction.y, 0.0)
	var edge_direction := _advance_mouse_edge_scroll(delta)
	var requested_direction := keyboard_direction + edge_direction
	if requested_direction.length_squared() > 1.0:
		requested_direction = requested_direction.normalized()
	var target_velocity := (
		requested_direction
		* float(runtime_settings.get("edge_scroll_speed", CAMERA_PAN_SPEED))
		/ maxf(level_camera.zoom.x, 0.001)
	)
	camera_pan_velocity = SMOOTH_CAMERA_PAN.advance_velocity(
		camera_pan_velocity,
		target_velocity,
		delta,
		bool(runtime_settings.get("reduce_camera_motion", false)),
	)
	level_camera.position += camera_pan_velocity * maxf(delta, 0.0)
	clamp_level_camera()
	if performance_monitor != null:
		performance_monitor.end_frame()


func _physics_process(_delta: float) -> void:
	if performance_monitor != null:
		performance_monitor.begin_physics()
	_advance_automatic_door_interactions()
	_advance_original_global_alarm()
	_advance_original_escort_rescue_proximity()
	_advance_original_m006_document_exchange()
	_advance_original_pickup_order()
	_advance_original_drop_order()
	_advance_burial_command_world_tick()
	if performance_monitor != null:
		performance_monitor.end_physics()


func _advance_original_global_alarm() -> bool:
	if not legacy_global_alarm_active:
		return false
	legacy_global_alarm_counter += 1
	if (
		legacy_global_alarm_counter
		> LEGACY_SOUND_ROUTE_CATALOG.GLOBAL_ALARM_UPDATE_COUNTER_LIMIT
	):
		# sub_408480 clears the flag on update 241, after incrementing the
		# counter, but still submits index 125 on that final update.
		legacy_global_alarm_counter = 0
		legacy_global_alarm_active = false
	if media_director == null:
		return false
	return bool(media_director.request_sfx_audio_index(
		LEGACY_SOUND_ROUTE_CATALOG.GLOBAL_ALARM_GFL_INDEX,
		get_instance_id(),
	))


func _on_runtime_node_added_for_original_button_audio(node: Node) -> void:
	if node != self and not is_ancestor_of(node):
		return
	_connect_original_button_audio(node)


func _connect_existing_original_button_audio(root_node: Node) -> void:
	_connect_original_button_audio(root_node)
	for child: Node in root_node.get_children():
		_connect_existing_original_button_audio(child)


func _connect_original_button_audio(node: Node) -> bool:
	if not node is BaseButton:
		return false
	var button := node as BaseButton
	if not button.pressed.is_connected(_on_original_ui_button_pressed):
		button.pressed.connect(_on_original_ui_button_pressed)
	return true


func _on_original_ui_button_pressed() -> void:
	if media_director == null:
		return
	media_director.play_audio_index(
		LEGACY_SOUND_ROUTE_CATALOG.UI_BUTTON_GFL_INDEX,
		"original_ui_button_release",
		"",
		"sfx",
	)


func _advance_original_escort_rescue_proximity() -> int:
	var rescued_count := 0
	for escort: ESCORT_UNIT in escorts:
		if (
			escort == null
			or not is_instance_valid(escort)
			or not escort.is_alive
			or escort.rescued_state
			or not escort.has_source_backed_rescue_rule()
		):
			continue
		var rescuer := _first_eligible_escort_rescuer(escort)
		if rescuer != null and escort.rescue(rescuer):
			rescued_count += 1
	return rescued_count


func _first_eligible_escort_rescuer(escort: ESCORT_UNIT) -> SQUAD_UNIT:
	if (
		escort == null
		or not is_instance_valid(escort)
		or not escort.has_source_backed_rescue_rule()
	):
		return null
	var target_names := (
		escort.original_rescue_rule.get("target_names", []) as Array
	)
	# The native handlers test the fixed character globals in this exact order;
	# do not substitute nearest-actor selection here.
	for target_name_value: Variant in target_names:
		var target_name := str(target_name_value)
		for unit: SQUAD_UNIT in units:
			if (
				unit.display_name == target_name
				and escort.can_be_rescued_by(unit)
			):
				return unit
	return null


func _commandable_player_units() -> Array[SQUAD_UNIT]:
	var result: Array[SQUAD_UNIT] = []
	for unit: SQUAD_UNIT in units:
		if unit != null and is_instance_valid(unit):
			result.append(unit)
	for escort: ESCORT_UNIT in escorts:
		if (
			escort != null
			and is_instance_valid(escort)
			and escort.is_player_commandable()
		):
			result.append(escort)
	return result


func _advance_original_disguise_state(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	for unit: SQUAD_UNIT in units:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive:
			continue
		unit.advance_original_disguise_transition(safe_delta)
		if not LEGACY_DISGUISE_RULES.has_cover_recovery(
			unit.runtime_actor_type
		):
			continue
		var burial_exposes_actor: bool = (
			LEGACY_DISGUISE_RULES.burial_can_break_cover(
				unit.runtime_actor_type
			) and burial_action_started
			and burial_worker == unit
			and burial_target != null
			and is_instance_valid(burial_target)
		)
		if (
			unit.faction_id
				== LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
			and not burial_exposes_actor
		):
			# A settled faction-1 disguise has no recovery counter to advance.
			# Avoid a full enemy/LOS scan on every rendered frame while idle.
			unit.advance_original_disguise_recovery(
				safe_delta,
				false,
				false,
			)
			continue
		var observer_has_visibility := _enemy_has_original_visibility_of(unit)
		unit.advance_original_disguise_recovery(
			safe_delta,
			observer_has_visibility,
			burial_exposes_actor,
		)


func _enemy_has_original_visibility_of(actor: SQUAD_UNIT) -> bool:
	for enemy: ENEMY_UNIT in enemies:
		if _enemy_has_original_visibility(enemy, actor):
			return true
	return false


func _enemy_has_original_visibility(
	enemy: ENEMY_UNIT,
	actor: SQUAD_UNIT,
) -> bool:
	if (
		enemy == null
		or actor == null
		or not is_instance_valid(enemy)
		or not is_instance_valid(actor)
		or not enemy.is_alive
		or not actor.is_alive
		or enemy.faction_id != LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
		or not LEGACY_ENEMY_AI_RULES.is_within_alert_ellipse(
			actor.position,
			enemy.position,
			LEGACY_DISGUISE_RULES.OBSERVER_ALERT_RADIUS,
		)
	):
		return false
	var ignored: Array = []
	if enemy.scene_index >= 0:
		ignored.append(enemy.scene_index)
	if actor.scene_index >= 0:
		ignored.append(actor.scene_index)
	return TACTICAL_SENSES.can_detect_original_heading(
		dynamic_occupancy,
		enemy.position,
		actor.position,
		enemy.perception_heading_degrees(),
		TACTICAL_SENSES.original_direction_half_angle_degrees(
			enemy.original_direction_index
		),
		enemy.sense_profile,
		actor.is_crawling,
		ignored,
	)


func _on_original_disguise_attack_committed(
	attacker: Node2D,
	target: Node2D,
	_attack_type: int,
) -> void:
	if (
		not attacker is SQUAD_UNIT
		or target == null
		or not is_instance_valid(attacker)
		or not is_instance_valid(target)
	):
		return
	var unit := attacker as SQUAD_UNIT
	var was_observed := false
	for enemy: ENEMY_UNIT in enemies:
		if not _enemy_has_original_visibility(enemy, unit):
			continue
		was_observed = true
		# sub_45EA70 gives each observer the attacked coordinate, not a live
		# target pointer. This enters the recovered five-point local search.
		enemy.receive_original_coordinate_alert(target.position)
	if not was_observed:
		return
	unit.expose_original_disguise()
	update_status("%s 的伪装行动被敌军目击" % unit.display_name)


func _on_original_pickup_cover_committed(
	collector: SQUAD_UNIT,
	source_world_position: Vector2,
) -> bool:
	if (
		collector == null
		or not is_instance_valid(collector)
		or not collector.is_alive
		or not LEGACY_DISGUISE_RULES.pickup_can_break_cover(
			collector.runtime_actor_type
		)
	):
		return false
	var was_observed := false
	for enemy: ENEMY_UNIT in enemies:
		if not _enemy_has_original_visibility(enemy, collector):
			continue
		was_observed = true
		# sub_45EC20 writes the completed target/container coordinate into each
		# observing actor.  It does not hand out a live target pointer.
		enemy.receive_original_coordinate_alert(source_world_position)
	if not was_observed:
		return false
	collector.expose_original_cover()
	update_status("%s 取物时被敌军目击，身份暴露" % collector.display_name)
	return true


func _on_original_disguise_transition_ready(
	unit: Node2D,
	item_id: int,
) -> void:
	if (
		not unit is SQUAD_UNIT
		or not is_instance_valid(unit)
		or not (unit as SQUAD_UNIT).is_alive
	):
		return
	var actor := unit as SQUAD_UNIT
	var transition: Dictionary = LEGACY_DISGUISE_RULES.transition_for(
		actor.runtime_actor_type,
		item_id,
	)
	if (
		transition.is_empty()
		or actor.backpack_inventory == null
		or not actor.backpack_inventory.has_item(
			int(transition.get("consume_backpack_item_id", 0))
		)
	):
		actor.cancel_original_disguise_transition()
		return
	# The original type 10 <-> 91 transition allocates a fresh actor through
	# sub_44A350 before copying the retained inventory/state fields. Reproduce
	# the exact four-draw in-level factory sequence and four derived/base
	# destructor draws for the retired actor when this is a level-bound runtime
	# actor; isolated fixtures keep their deterministic fallback.
	if (
		not actor.original_crt_level_id.is_empty()
		and (
			not actor.initialize_dynamic_original_crt_random()
			or not actor.consume_retired_original_crt_random()
		)
	):
		actor.cancel_original_disguise_transition()
		return
	var consumed_item_id := int(
		transition.get("consume_backpack_item_id", 0)
	)
	var granted_item_id := int(
		transition.get("grant_backpack_item_id", 0)
	)
	if not actor.consume_backpack_item(consumed_item_id, true):
		return
	if (
		granted_item_id > 0
		and actor.add_backpack_item(granted_item_id, 1, 0) != 1
	):
		actor.add_backpack_item(consumed_item_id, 1, 0)
		return
	var granted_weapon_item_id := int(
		transition.get("grant_weapon_item_id", 0)
	)
	if granted_weapon_item_id > 0:
		var special_profile: Dictionary = (
			COMBAT_PROFILES.weapon_profile_for_attack_type(
				LEGACY_DISGUISE_RULES.SPECIAL_ATTENTION_ATTACK_TYPE
			)
		)
		var special_action_key := str(
			special_profile.get("action_key", "")
		)
		var granted := false
		if (
			not special_action_key.is_empty()
			and actor.has_inventory_weapon(special_action_key)
		):
			granted = actor.add_ammo_item(granted_weapon_item_id, 1) == 1
		elif not special_profile.is_empty():
			granted = actor.register_original_inventory_weapon(
				special_profile,
				_attack_groups_for_actor_variant(
					actor,
					special_action_key,
					int(transition.get("to_runtime_actor_type", 0)),
				),
				1,
				1,
				false,
			)
		if not granted:
			actor.consume_backpack_item(granted_item_id, true)
			actor.add_backpack_item(consumed_item_id, 1, 0)
			return
	var removed_weapon_item_id := int(
		transition.get("remove_weapon_item_id", 0)
	)
	if removed_weapon_item_id > 0:
		actor.remove_ammo_item(removed_weapon_item_id, 1)
	_apply_original_actor_variant(
		actor,
		int(transition.get("to_runtime_actor_type", actor.runtime_actor_type)),
		int(transition.get("to_faction_id", actor.faction_id)),
		int(
			transition.get(
				"appearance_state",
				actor.disguise_appearance_state,
			)
		),
	)
	if (
		selected_backpack_item_id == consumed_item_id
		and (
			actor.backpack_inventory == null
			or not actor.backpack_inventory.has_item(consumed_item_id)
		)
	):
		selected_backpack_item_id = 0
	update_status(
		"%s 已%s"
		% [
			actor.display_name,
			"换上日军军服" if actor.runtime_actor_type == 91 else "换回便装",
		]
	)
	_refresh_inventory_ui()


func _apply_original_actor_variant(
	unit: SQUAD_UNIT,
	runtime_actor_type: int,
	faction_id: int,
	appearance_state: int,
) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var gfl_index := (
		LEGACY_DISGUISE_RULES.DISGUISED_GFL_INDEX
		if runtime_actor_type
			== LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE
		else LEGACY_DISGUISE_RULES.NORMAL_GFL_INDEX
	)
	var attack_groups_by_action: Dictionary = {}
	for action_key: String in unit.inventory_weapon_order:
		attack_groups_by_action[action_key] = (
			_attack_groups_for_actor_variant(
				unit,
				action_key,
				runtime_actor_type,
			)
		)
	unit.apply_original_actor_variant(
		runtime_actor_type,
		faction_id,
		appearance_state,
		_load_gfl_texture(gfl_index),
		_load_gfl_action_groups(gfl_index, "run"),
		_load_gfl_action_groups(gfl_index, "walk"),
		_load_gfl_action_groups(gfl_index, "crawl"),
		_load_gfl_action_groups(gfl_index, "stand"),
		_load_gfl_action_groups(gfl_index, "death"),
		attack_groups_by_action,
	)
	return true


func _update_context_cursor(delta: float = 0.0) -> void:
	if legacy_cursor_presenter == null:
		return
	if game_shell != null and game_shell.is_overlay_open():
		context_cursor_cached_serial = LEGACY_INPUT_RULES.CursorSerial.NORMAL
		context_cursor_last_state = -1
		legacy_cursor_presenter.apply(LEGACY_INPUT_RULES.CursorSerial.NORMAL, delta)
		return
	if _pointer_over_interactive_control():
		context_cursor_cached_serial = LEGACY_INPUT_RULES.CursorSerial.NORMAL
		context_cursor_last_state = -1
		legacy_cursor_presenter.apply(LEGACY_INPUT_RULES.CursorSerial.NORMAL, delta)
		return
	var mouse_screen := get_viewport().get_mouse_position()
	context_cursor_refresh_elapsed += maxf(delta, 0.0)
	var cursor_state := (
		(1 if burial_mode else 0)
		| ((1 if sight_target_pending else 0) << 1)
		| ((1 if not selected_units.is_empty() else 0) << 2)
		| ((1 if original_force_target_held else 0) << 3)
	)
	var refresh_context := (
		mouse_screen.distance_squared_to(context_cursor_last_screen_position) > 0.25
		or cursor_state != context_cursor_last_state
		or context_cursor_refresh_elapsed >= 0.05
	)
	if not refresh_context:
		legacy_cursor_presenter.apply(context_cursor_cached_serial, delta)
		return
	context_cursor_last_screen_position = mouse_screen
	context_cursor_last_state = cursor_state
	context_cursor_refresh_elapsed = 0.0
	var viewport_size := get_viewport_rect().size
	var pointer_inside_world := (
		mouse_screen.x >= 0.0
		and mouse_screen.y >= 0.0
		and mouse_screen.x < viewport_size.x
		and mouse_screen.y < viewport_size.y
	)
	var mouse_world := (
		get_global_transform_with_canvas().affine_inverse() * mouse_screen
	)
	context_cursor_cached_serial = LEGACY_INPUT_RULES.context_cursor_serial(
		burial_mode,
		sight_target_pending,
		not selected_units.is_empty(),
		original_force_target_held,
		(
			legacy_door_at_world_point(mouse_world) != null
			or mission_inventory_pickup_at_world_point(mouse_world) != null
			or field_pickup_at_world_point(mouse_world) != null
		),
		enemy_at_world_point(mouse_world) != null,
		_cursor_ground_is_walkable(mouse_world),
		pointer_inside_world,
	)
	legacy_cursor_presenter.apply(context_cursor_cached_serial, delta)


func _reset_context_cursor() -> void:
	if legacy_cursor_presenter != null:
		legacy_cursor_presenter.reset()
	context_cursor_cached_serial = LEGACY_INPUT_RULES.CursorSerial.NORMAL
	context_cursor_last_screen_position = Vector2(INF, INF)
	context_cursor_last_state = -1
	context_cursor_refresh_elapsed = 0.0


func _pointer_over_interactive_control() -> bool:
	if (
		game_shell != null
		and game_shell.has_method("is_screen_point_over_gameplay_ui")
		and bool(game_shell.call(
			"is_screen_point_over_gameplay_ui",
			get_viewport().get_mouse_position(),
		))
	):
		return true
	var hovered_control := get_viewport().gui_get_hovered_control()
	return (
		hovered_control != null
		and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE
	)


func _pointer_event_over_gameplay_ui(event: InputEvent) -> bool:
	if (
		game_shell == null
		or not game_shell.has_method("is_screen_point_over_gameplay_ui")
	):
		return false
	var screen_position := Vector2(-1.0, -1.0)
	if event is InputEventMouseButton:
		screen_position = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion:
		screen_position = (event as InputEventMouseMotion).position
	else:
		return false
	return bool(game_shell.call(
		"is_screen_point_over_gameplay_ui",
		screen_position,
	))


func _cursor_ground_is_walkable(world_position: Vector2) -> bool:
	if navigation_grid == null:
		return movement_bounds.has_point(world_position)
	var cell := navigation_grid.world_to_cell(world_position)
	return (
		navigation_grid.is_valid_cell(cell)
		and not navigation_grid.is_movement_blocked(cell)
	)

func _update_tactical_sight_visibility() -> void:
	if (
		not sight_target_pending
		and sight_observation_target == null
		and tactical_visible_enemies.is_empty()
	):
		return
	if (
		sight_observation_target != null
		and (
			not is_instance_valid(sight_observation_target)
			or not sight_observation_target.is_alive
			or sight_observation_target.faction_id != 1
		)
	):
		_clear_sight_observation_target()
	var hovered_enemy: ENEMY_UNIT = (
		enemy_at_world_point(_mouse_world_position())
		if sight_target_pending
		else null
	)
	var desired: Dictionary = {}
	for enemy: ENEMY_UNIT in [hovered_enemy, sight_observation_target]:
		if enemy != null and is_instance_valid(enemy):
			desired[enemy.get_instance_id()] = enemy
	for instance_id_value: Variant in tactical_visible_enemies.keys():
		var instance_id := int(instance_id_value)
		if desired.has(instance_id):
			continue
		var enemy := tactical_visible_enemies.get(instance_id) as ENEMY_UNIT
		if enemy != null and is_instance_valid(enemy):
			enemy.set_tactical_ranges_visible(false)
		tactical_visible_enemies.erase(instance_id)
	for instance_id_value: Variant in desired.keys():
		var instance_id := int(instance_id_value)
		if tactical_visible_enemies.has(instance_id):
			continue
		var enemy := desired[instance_id] as ENEMY_UNIT
		enemy.set_tactical_ranges_visible(true)
		tactical_visible_enemies[instance_id] = enemy


func _advance_sight_observation(delta: float) -> void:
	if sight_observation_target == null:
		return
	sight_observation_remaining = maxf(
		sight_observation_remaining - maxf(delta, 0.0),
		0.0,
	)
	if sight_observation_remaining <= 0.0:
		_clear_sight_observation_target()


func _clear_tactical_visible_enemies() -> void:
	for enemy_value: Variant in tactical_visible_enemies.values():
		var enemy := enemy_value as ENEMY_UNIT
		if enemy != null and is_instance_valid(enemy):
			enemy.set_tactical_ranges_visible(false)
	tactical_visible_enemies.clear()


func _update_combat_preview(delta: float) -> void:
	if game_shell == null:
		return
	combat_preview_refresh_elapsed += maxf(delta, 0.0)
	if combat_preview_refresh_elapsed < 0.08:
		return
	combat_preview_refresh_elapsed = fmod(combat_preview_refresh_elapsed, 0.08)
	if selected_units.is_empty() or game_shell.is_overlay_open():
		if combat_preview_visible:
			game_shell.set_combat_preview("")
			combat_preview_visible = false
		return
	var attacker := selected_units[0]
	var mouse_world := _mouse_world_position()
	var target: Node2D = enemy_at_world_point(mouse_world)
	if target == null:
		target = explosive_prop_at_world_point(mouse_world)
	if target == null:
		if combat_preview_visible:
			game_shell.set_combat_preview("")
			combat_preview_visible = false
		return
	var preview_data: Dictionary = COMBAT_FEEDBACK.preview(
		attacker,
		target,
		dynamic_occupancy,
	)
	var attack_type := int(preview_data.get("attack_type", 0))
	var preview_text: String = COMBAT_FEEDBACK.display_text(
		preview_data,
		str(WEAPON_NAMES.get(attack_type, tr("WEAPON_CURRENT"))),
	)
	var status := "ready" if bool(preview_data.get("ready", false)) else (
		"warning"
		if str(preview_data.get("reason", "")) == "out_of_range"
		else "blocked"
	)
	game_shell.set_combat_preview(preview_text, status)
	combat_preview_visible = not preview_text.is_empty()


func _mouse_edge_scroll_direction() -> Vector2:
	if (
		DisplayServer.get_name() == "headless"
		or not DisplayServer.window_is_focused()
		or right_dragging
		or camera_dragging
		or (game_shell != null and game_shell.is_overlay_open())
	):
		return Vector2.ZERO
	var full_viewport_size := get_viewport_rect().size
	var viewport_size := _gameplay_viewport_size()
	var mouse_position := pointer_screen_position
	if game_shell != null and game_shell.has_method("edge_scroll_pointer_position"):
		mouse_position = game_shell.edge_scroll_pointer_position(
			mouse_position,
			full_viewport_size,
		)
	elif _pointer_over_interactive_control():
		return Vector2.ZERO
	return SMOOTH_CAMERA_PAN.edge_intent(
		mouse_position,
		viewport_size,
		float(runtime_settings.get("edge_scroll_margin", EDGE_SCROLL_MARGIN)),
		EDGE_SCROLL_VERTICAL_MARGIN,
	)


func _advance_mouse_edge_scroll(delta: float) -> Vector2:
	if (
		not bool(runtime_settings.get("edge_scroll", true))
		or DisplayServer.get_name() == "headless"
		or not DisplayServer.window_is_focused()
		or right_dragging
		or camera_dragging
		or (game_shell != null and game_shell.is_overlay_open())
		or _pointer_blocks_camera_edge_scroll()
	):
		_reset_camera_edge_intent()
		return Vector2.ZERO
	var requested_direction := _mouse_edge_scroll_direction()
	if not requested_direction.is_zero_approx():
		edge_scroll_last_direction = requested_direction
		edge_scroll_release_elapsed = 0.0
	else:
		edge_scroll_release_elapsed += maxf(delta, 0.0)
		requested_direction = SMOOTH_CAMERA_PAN.retain_edge_intent(
			edge_scroll_last_direction,
			edge_scroll_release_elapsed,
			EDGE_SCROLL_RELEASE_GRACE_SECONDS,
		)
		if requested_direction.is_zero_approx():
			edge_scroll_last_direction = Vector2.ZERO
	edge_scroll_strength = clampf(requested_direction.length(), 0.0, 1.0)
	return requested_direction


func _pointer_blocks_camera_edge_scroll() -> bool:
	if game_shell == null:
		return _pointer_over_interactive_control()
	if game_shell.has_method("is_screen_point_over_edge_scroll_blocker"):
		return bool(game_shell.call(
			"is_screen_point_over_edge_scroll_blocker",
			pointer_screen_position,
		))
	return _pointer_over_interactive_control()


func _reset_camera_edge_intent() -> void:
	edge_scroll_strength = 0.0
	edge_scroll_last_direction = Vector2.ZERO
	edge_scroll_release_elapsed = EDGE_SCROLL_RELEASE_GRACE_SECONDS


static func edge_scroll_direction_for_position(
	mouse_position: Vector2,
	viewport_size: Vector2,
	margin: float = EDGE_SCROLL_MARGIN,
) -> Vector2:
	return SMOOTH_CAMERA_PAN.edge_intent(
		mouse_position,
		viewport_size,
		margin,
		EDGE_SCROLL_VERTICAL_MARGIN,
	)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# Observation only: never warp, capture, confine or resend the pointer.
		pointer_screen_position = (event as InputEventMouse).position
	if is_fullscreen_toggle_event(event):
		_toggle_fullscreen_window_mode()
		get_viewport().set_input_as_handled()
		return
	if not legacy_crt_recurring_evidence_replay_active:
		return
	var affects_evidence := (
		event is InputEventKey
		and (event as InputEventKey).pressed
	) or (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).button_index in [
			MOUSE_BUTTON_LEFT,
			MOUSE_BUTTON_RIGHT,
		]
	)
	if affects_evidence:
		# This observer does not handle, warp, capture or resend the event. The
		# normal GUI/world input path receives it unchanged.
		invalidate_original_recurring_evidence("player_input")


static func is_fullscreen_toggle_event(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and key_event.alt_pressed
		and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	)


func _toggle_fullscreen_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var currently_windowed := (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
	)
	var next_settings := runtime_settings.duplicate(true)
	if currently_windowed:
		var current_size := DisplayServer.window_get_size()
		next_settings["window_width"] = current_size.x
		next_settings["window_height"] = current_size.y
		next_settings["display_mode"] = "fullscreen"
		next_settings["fullscreen"] = true
	else:
		next_settings["display_mode"] = "windowed"
		next_settings["fullscreen"] = false
	_on_shell_settings_changed(next_settings)
	command_bus.issue(
		"toggle_fullscreen",
		{"display_mode": str(next_settings.get("display_mode", "windowed"))},
		"input",
	)
	if game_shell != null:
		game_shell.set_settings(runtime_settings)
	update_status(
		"显示模式：%s（Alt+Enter 可随时切换）"
		% ("全屏" if currently_windowed else "窗口")
	)


func _unhandled_input(event: InputEvent) -> void:
	if game_shell != null and game_shell.is_overlay_open():
		return
	if _pointer_event_over_gameplay_ui(event):
		# This is a defensive boundary in addition to Control.MOUSE_FILTER_STOP.
		# It prevents a HUD press/release from becoming a world order even if a
		# resized window changes the hovered-control state during that frame.
		if event is InputEventMouseButton:
			var ui_mouse_event := event as InputEventMouseButton
			if not ui_mouse_event.pressed:
				if ui_mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
					camera_dragging = false
				elif ui_mouse_event.button_index == MOUSE_BUTTON_RIGHT:
					right_dragging = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and camera_dragging and level_camera != null:
		var motion := event as InputEventMouseMotion
		level_camera.position -= motion.relative / level_camera.zoom.x
		clamp_level_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and right_dragging:
		right_drag_current_screen = (event as InputEventMouseMotion).position
		queue_redraw()
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
				var next_zoom: float = LEVEL_VIEW.zoom_with_step(
					level_camera.zoom.x,
					zoom_in,
					float(runtime_settings.get("zoom_step", 0.25)),
				)
				level_camera.zoom = Vector2.ONE * next_zoom
				clamp_level_camera()
			get_viewport().set_input_as_handled()
			return
		var local_position: Vector2 = (
			get_global_transform_with_canvas().affine_inverse() * mouse_event.position
		)
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if LEGACY_INPUT_RULES.should_submit_world_left(mouse_event.pressed):
				_handle_original_left_click(
					local_position,
					mouse_event.shift_pressed,
					mouse_event.ctrl_pressed or original_force_target_held,
					mouse_event.double_click,
				)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if not LEGACY_INPUT_RULES.should_finish_world_right(mouse_event.pressed):
				right_dragging = true
				right_drag_start_screen = mouse_event.position
				right_drag_current_screen = mouse_event.position
			else:
				var drag_distance := right_drag_start_screen.distance_to(mouse_event.position)
				right_dragging = false
				if _cancel_pending_pointer_mode_from_right_release():
					update_status("已取消当前鼠标命令模式")
				elif drag_distance >= RIGHT_DRAG_THRESHOLD:
					_select_units_in_screen_rect(
						Rect2(right_drag_start_screen, mouse_event.position - right_drag_start_screen).abs(),
						mouse_event.shift_pressed,
					)
				elif str(runtime_settings.get("control_scheme", "classic")) == "modern":
					_handle_modern_context_command(
						local_position,
						mouse_event.ctrl_pressed or original_force_target_held,
					)
				# The original world view assigns the right button exclusively to
				# drag-box selection. A short right click deliberately issues no order.
				queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.echo:
		var key_event := event as InputEventKey
		if _handle_modern_group_or_bookmark_key(key_event):
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and _consume_original_cheat_key(key_event):
			# The final letter of FLIPMISSION is N, which is also the modern
			# noise-lure shortcut. Give the complete original sequence priority.
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and key_event.keycode == KEY_N:
			emit_noise_at(_mouse_world_position(), 640.0)
			get_viewport().set_input_as_handled()
			return
		var controls := runtime_settings.get("controls", {}) as Dictionary
		var action: String = GAME_INPUT_BINDINGS.action_for_event(key_event, controls)
		if (
			GAME_INPUT_BINDINGS.should_trigger_for_event(action, key_event)
			and _handle_original_key_action(action, key_event)
		):
			get_viewport().set_input_as_handled()
		elif key_event.pressed and key_event.ctrl_pressed and key_event.keycode >= KEY_0 and key_event.keycode <= KEY_9:
			var requested_level := 10 if key_event.keycode == KEY_0 else key_event.keycode - KEY_1
			switch_level(requested_level)
			update_status("开发关卡选择：M%03d" % requested_level)
			get_viewport().set_input_as_handled()
		elif key_event.pressed and key_event.keycode == KEY_PAGEUP:
			switch_level(current_level_index - 1)
			get_viewport().set_input_as_handled()
		elif key_event.pressed and key_event.keycode == KEY_PAGEDOWN:
			switch_level(current_level_index + 1)
			get_viewport().set_input_as_handled()
		elif OS.is_debug_build() and not key_event.pressed and key_event.keycode == KEY_F8:
			# The original hard-codes 1937M010.SAV here. Its binary save cannot be
			# loaded by the remake, so debug builds provide the safe level-equivalent.
			switch_level(10)
			update_status("原版 F8 调试后门：已进入 M010（未读取原版二进制存档）")
			get_viewport().set_input_as_handled()


func _cancel_pending_pointer_mode_from_right_release() -> bool:
	var canceled := (
		burial_mode
		or sight_target_pending
		or selected_backpack_item_id > 0
	)
	burial_mode = false
	sight_target_pending = false
	sight_observation_mode = false
	if game_shell != null:
		game_shell.set_original_hud_action_state("observation", false)
	selected_backpack_item_id = 0
	_refresh_inventory_ui()
	return canceled


func _handle_original_left_click(
	world_position: Vector2,
	additive: bool,
	force_target_modifier: bool = false,
	double_click: bool = false,
) -> void:
	if burial_mode:
		# B is an explicit verb, so it must never be stolen by a coincident loot
		# hitbox. Ordinary/context clicks still resolve loose drops before corpses;
		# an intentional burial click always reaches the corpse command.
		_try_bury_at(world_position)
		burial_mode = false
		return
	if sight_target_pending:
		_select_sight_observation_target(world_position)
		return
	if selected_backpack_item_id > 0:
		drop_selected_item_at(world_position)
		return
	if force_target_modifier:
		var forced_target := force_target_at_world_point(world_position)
		if forced_target != null:
			issue_attack_order(forced_target, true)
		else:
			issue_force_attack_order(world_position)
		return
	if str(runtime_settings.get("control_scheme", "classic")) == "modern":
		for unit: SQUAD_UNIT in _commandable_player_units():
			if not unit.is_alive or not unit.contains_parent_point(world_position):
				continue
			handle_selection(world_position, additive)
			if double_click:
				_select_same_actor_type_in_view(unit, additive)
			return
		if not additive:
			clear_selection()
		return
	for unit: SQUAD_UNIT in _commandable_player_units():
		if unit.is_alive and unit.contains_parent_point(world_position):
			handle_selection(world_position, additive)
			return
	# A dead actor drops its loose inventory before the corpse can be buried.
	# Both objects intentionally share the same world coordinate, so resolve the
	# recoverable loose item first; an empty actor-78 cache must never mask it.
	if _try_issue_preferred_pickup(world_position):
		return
	if _try_interact_burial_cache_at(world_position):
		return
	if _try_open_legacy_door_at(world_position):
		return
	if _try_issue_legacy_world_object_deployment(world_position):
		return
	var combat_target: Node2D = enemy_at_world_point(world_position)
	if combat_target == null:
		combat_target = explosive_prop_at_world_point(world_position)
	if combat_target != null:
		issue_attack_order(combat_target)
	else:
		issue_formation_move(world_position)


func _handle_modern_context_command(
	world_position: Vector2,
	force_target_modifier: bool = false,
) -> void:
	if selected_backpack_item_id > 0:
		drop_selected_item_at(world_position)
		return
	if force_target_modifier:
		var forced_target := force_target_at_world_point(world_position)
		if forced_target != null:
			issue_attack_order(forced_target, true)
		else:
			issue_force_attack_order(world_position)
		return
	if _try_issue_preferred_pickup(world_position):
		return
	if _try_interact_burial_cache_at(world_position):
		return
	if _try_open_legacy_door_at(world_position):
		return
	if _try_issue_legacy_world_object_deployment(world_position):
		return
	var combat_target: Node2D = enemy_at_world_point(world_position)
	if combat_target == null:
		combat_target = explosive_prop_at_world_point(world_position)
	if combat_target != null:
		issue_attack_order(combat_target)
	else:
		issue_formation_move(world_position)


func _handle_modern_group_or_bookmark_key(event: InputEventKey) -> bool:
	if (
		str(runtime_settings.get("control_scheme", "classic")) != "modern"
		or not event.pressed
		or event.echo
	):
		return false
	var group_number := _digit_key_number(event.keycode)
	if group_number <= 0:
		return false
	if event.shift_pressed:
		if event.ctrl_pressed:
			_store_camera_bookmark(group_number)
		else:
			_recall_camera_bookmark(group_number)
	else:
		if event.ctrl_pressed:
			_assign_control_group(group_number)
		else:
			_recall_control_group(group_number)
	return true


static func _digit_key_number(keycode: Key) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode - KEY_0)
	return 0


func _assign_control_group(group_number: int) -> void:
	var scene_indices: Array[int] = []
	for unit: SQUAD_UNIT in selected_units:
		if unit != null and is_instance_valid(unit) and unit.is_alive:
			scene_indices.append(unit.scene_index)
	control_groups[group_number] = scene_indices
	update_status(
		tr("STATUS_CONTROL_GROUP_SAVED") % [group_number, scene_indices.size()]
	)
	command_bus.issue(
		"assign_control_group",
		{"group": group_number, "unit_count": scene_indices.size()},
		"input",
	)


func _recall_control_group(group_number: int) -> void:
	var scene_indices_value: Variant = control_groups.get(group_number)
	if not scene_indices_value is Array:
		update_status(tr("STATUS_CONTROL_GROUP_EMPTY") % group_number)
		return
	clear_selection()
	var center := Vector2.ZERO
	for scene_index_value: Variant in scene_indices_value as Array:
		var actor := world_spatial_index.node_for_scene(int(scene_index_value)) as SQUAD_UNIT
		if actor == null or not actor.is_alive:
			continue
		selected_units.append(actor)
		actor.set_selected(true)
		center += actor.position
	if not selected_units.is_empty() and level_camera != null:
		level_camera.position = center / float(selected_units.size())
		clamp_level_camera()
	_refresh_inventory_ui()
	update_status(
		tr("STATUS_CONTROL_GROUP_SELECTED") % [group_number, selected_units.size()]
	)
	command_bus.issue(
		"recall_control_group",
		{"group": group_number, "unit_count": selected_units.size()},
		"input",
	)


func _store_camera_bookmark(bookmark_number: int) -> void:
	if level_camera == null:
		return
	camera_bookmarks[bookmark_number] = level_camera.position
	update_status(tr("STATUS_CAMERA_BOOKMARK_SAVED") % bookmark_number)
	command_bus.issue(
		"store_camera_bookmark",
		{"bookmark": bookmark_number, "position": level_camera.position},
		"input",
	)


func _recall_camera_bookmark(bookmark_number: int) -> void:
	var position_value: Variant = camera_bookmarks.get(bookmark_number)
	if not position_value is Vector2 or level_camera == null:
		update_status(tr("STATUS_CAMERA_BOOKMARK_EMPTY") % bookmark_number)
		return
	level_camera.position = position_value as Vector2
	clamp_level_camera()
	command_bus.issue(
		"recall_camera_bookmark",
		{"bookmark": bookmark_number, "position": level_camera.position},
		"input",
	)


func _select_same_actor_type_in_view(seed: SQUAD_UNIT, additive: bool) -> void:
	if seed == null or not is_instance_valid(seed):
		return
	if not additive:
		clear_selection()
	var visible_world := _camera_world_rect().grow(32.0)
	for candidate: SQUAD_UNIT in _commandable_player_units():
		if (
			not candidate.is_alive
			or candidate.runtime_actor_type != seed.runtime_actor_type
			or not visible_world.has_point(candidate.position)
			or selected_units.has(candidate)
		):
			continue
		selected_units.append(candidate)
		candidate.set_selected(true)
	_refresh_inventory_ui()
	update_status(tr("STATUS_SAME_TYPE_SELECTED") % selected_units.size())
	command_bus.issue(
		"double_click_select_type",
		{
			"runtime_actor_type": seed.runtime_actor_type,
			"unit_count": selected_units.size(),
		},
		"input",
	)


func _consume_original_cheat_key(event: InputEventKey) -> bool:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.unicode <= 0:
		return false
	var typed := String.chr(event.unicode).to_upper()
	if typed.length() != 1 or typed < "A" or typed > "Z":
		return false
	original_cheat_buffer = (original_cheat_buffer + typed).right(16)
	if original_cheat_buffer.ends_with(ORIGINAL_CHEAT_COMPLETE):
		original_cheat_buffer = ""
		_complete_current_mission_from_original_cheat()
		return true
	elif original_cheat_buffer.ends_with(ORIGINAL_CHEAT_ABOUT):
		original_cheat_buffer = ""
		_open_pause_menu()
		if game_shell != null:
			game_shell.set_menu_message(
				"关于《1937特种兵》：原版 LOVEBABY 彩蛋已识别。\n现代复刻工程保留历史玩法并明确标注补写内容。"
			)
		return true
	return false


func _complete_current_mission_from_original_cheat() -> void:
	if current_mission_state == null or current_mission_state.is_failed():
		return
	for objective_value: Variant in current_mission_state.completed.keys():
		current_mission_state.completed[str(objective_value)] = true
	if mission_runtime != null:
		mission_runtime.set("_reported_victory", true)
	_on_mission_victory()


func _handle_original_key_action(action: String, key_event: InputEventKey) -> bool:
	if action.is_empty():
		return false
	command_bus.issue(
		"input_action",
		{"action": action, "pressed": key_event.pressed},
		"input",
	)
	if WEAPON_ACTION_ATTACK_TYPES.has(action):
		_equip_selected_attack_type(int(WEAPON_ACTION_ATTACK_TYPES[action]))
		return true
	if action.begins_with("select_"):
		var index := int(action.trim_prefix("select_")) - 1
		var original_slot_unit := _unit_for_original_character_slot(index)
		if original_slot_unit != null and original_slot_unit.is_alive:
			select_only(original_slot_unit)
			_play_original_actor_audio(
				LEGACY_ACTOR_AUDIO_RULES.FAMILY_SELECTED,
				original_slot_unit,
			)
			update_status("已选择%s" % original_slot_unit.display_name)
		return true
	match action:
		"pause":
			if game_shell != null and game_shell.is_tactical_map_visible():
				game_shell.hide_tactical_map()
				update_status("地图已关闭")
			else:
				_open_pause_menu()
		"guide":
			_open_control_guide()
		"briefing":
			_show_current_briefing()
		"minimap":
			_open_tactical_map()
		"weapon_inventory":
			_open_inventory("weapons")
		"item_inventory":
			_open_inventory("items")
		"toggle_run":
			_toggle_selected_run_walk()
		"toggle_crawl":
			_toggle_selected_crawl()
		"sight_mode":
			_toggle_sight_observation()
		"burial_mode":
			burial_mode = true
			sight_observation_mode = false
			sight_target_pending = false
			if game_shell != null:
				game_shell.set_original_hud_action_state("observation", false)
			update_status("掩埋模式：点击阵亡的敌军目标")
		"quick_save":
			_save_game()
		"quick_load":
			_load_game()
		"interact":
			interact_with_mission_world()
		"reload":
			_reload_selected_units()
		"cycle_weapon":
			_cycle_selected_weapons(-1 if key_event.shift_pressed else 1)
		"detonate":
			_detonate_mission_charges()
		_:
			return false
	return true


func _unit_for_original_character_slot(slot_index: int) -> SQUAD_UNIT:
	# F2..F6 are fixed character identities in the original executable, not a
	# compact list of actors present in the current level.  A missing character
	# therefore leaves a hole: for example m001 has no Tiedan/Daniu, yet F5 must
	# still select Gu Ming instead of the fourth entry in `units`.
	if slot_index < 0 or slot_index >= PLAYABLE_SQUAD.size():
		return null
	var required_name := str(PLAYABLE_SQUAD[slot_index].get("name", ""))
	for unit: SQUAD_UNIT in _commandable_player_units():
		if unit.display_name == required_name:
			return unit
	return null


func clamp_level_camera() -> void:
	if level_camera == null:
		return
	_sync_level_camera_safe_area()
	level_camera.position = LEVEL_VIEW.clamp_camera_center(
		level_camera.position,
		_gameplay_viewport_size(),
		level_camera.zoom.x,
		world_size,
	)


func _gameplay_viewport_size() -> Vector2:
	var full_size := (
		get_viewport_rect().size if is_inside_tree() else DEFAULT_WORLD_SIZE
	)
	if game_shell != null and game_shell.has_method("gameplay_viewport_size"):
		return game_shell.gameplay_viewport_size(full_size)
	return full_size.max(Vector2.ONE)


func _sync_level_camera_safe_area() -> void:
	if level_camera == null or not is_inside_tree():
		return
	var full_size := get_viewport_rect().size.max(Vector2.ONE)
	var safe_size := _gameplay_viewport_size()
	var zoom := maxf(level_camera.zoom.x, 0.001)
	var hidden_height := maxf(full_size.y - safe_size.y, 0.0)
	if media_director != null and media_director.has_method("set_gameplay_safe_area"):
		media_director.call("set_gameplay_safe_area", hidden_height)
	level_camera.offset = (
		game_shell.gameplay_camera_offset(full_size, zoom)
		if game_shell != null and game_shell.has_method("gameplay_camera_offset")
		else Vector2(0.0, hidden_height * 0.5 / zoom)
	)
	# The safe battlefield ends above the HUD. Its hidden continuation may extend
	# below the authored map without exposing black pixels to the player.
	level_camera.limit_left = 0
	# Camera2D applies limits to its un-offset full-viewport centre, then applies
	# `offset`. Allow that base centre to rise by the same world-space amount at
	# the map top; otherwise the full-viewport top clamp and the HUD offset both
	# shift the target upward. floor avoids exposing even a sub-pixel black row.
	level_camera.limit_top = -floori(level_camera.offset.y)
	level_camera.limit_right = int(ceilf(world_size.x))
	level_camera.limit_bottom = int(ceilf(world_size.y + hidden_height / zoom))


func handle_selection(world_point: Vector2, additive: bool) -> void:
	var hit: SQUAD_UNIT
	for unit: SQUAD_UNIT in _commandable_player_units():
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
	if selected_units.size() >= 2:
		_report_direction_action("select_multiple_units")
	_refresh_inventory_ui()
	if selected_units.has(hit) and level_camera != null:
		level_camera.position = hit.position
		clamp_level_camera()
	if selected_units.has(hit):
		_play_original_actor_audio(
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_SELECTED,
			hit,
		)


func _select_units_in_screen_rect(screen_rect: Rect2, additive: bool) -> void:
	if not additive:
		clear_selection()
	for unit: SQUAD_UNIT in _commandable_player_units():
		if not unit.is_alive:
			continue
		var screen_position := get_global_transform_with_canvas() * unit.position
		if screen_rect.has_point(screen_position) and not selected_units.has(unit):
			selected_units.append(unit)
			unit.set_selected(true)
	update_status("框选了 %d 名队员" % selected_units.size())
	if selected_units.size() >= 2:
		_report_direction_action("select_multiple_units")
	_refresh_inventory_ui()


func _try_bury_at(world_point: Vector2) -> bool:
	var corpse: ENEMY_UNIT
	for enemy: ENEMY_UNIT in enemies:
		if (
			not enemy.is_alive
			and enemy.faction_id == 1
			and not buried_enemy_scene_indices.has(int(enemy.scene_index))
			and enemy.contains_parent_point(world_point)
		):
			corpse = enemy
			break
	if corpse == null:
		update_status("掩埋模式：请点击阵亡敌人")
		return false
	burial_target = corpse
	burial_worker = selected_units[0] if not selected_units.is_empty() else null
	burial_progress_ticks = 0
	burial_action_started = false
	if burial_worker == null:
		_cancel_burial_command()
		update_status("请先选择执行掩埋的队员")
		return false
	_clear_original_pickup_order()
	_clear_original_drop_order()
	_cancel_legacy_deployment_for_unit(burial_worker)
	burial_worker.clear_combat_target()
	if not is_original_burial_range(burial_worker.position, corpse.position):
		_issue_burial_approach_path()
	burial_worker.original_command_goal_kind_latch = 4
	burial_worker.queue_original_acknowledgement()
	update_status("已下达掩埋命令，队员将先接近目标")
	return true

func _finish_burial() -> void:
	if (
		burial_target == null
		or not is_instance_valid(burial_target)
		or burial_worker == null
		or not is_instance_valid(burial_worker)
	):
		_cancel_burial_command()
		return
	var scene_index := int(burial_target.scene_index)
	# sub_456CD0 marks the corpse for removal, creates actor 78 through the
	# successful sub_44A350 path, and only then lets the manager run the old
	# corpse's derived/base destructor. Keep that eight-draw transaction atomic.
	if not _commit_original_dynamic_actor_factory("actor 78 藏尸处"):
		_cancel_burial_command()
		return
	_spawn_legacy_burial_cache(
		burial_target.position,
		scene_index,
		burial_target.inventory_snapshot(),
		burial_target.backpack_snapshot(),
	)
	if not _commit_original_dynamic_actor_destructor("被掩埋尸体"):
		_cancel_burial_command()
		return
	if scene_index >= 0:
		buried_enemy_scene_indices[scene_index] = true
	burial_target.mark_legacy_corpse_buried(true)
	burial_target.visible = false
	burial_target.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_enemy_corpse_candidates()
	update_status("掩埋完成：已生成原版藏尸处，尸体物品保留其中")
	_cancel_burial_command(true)


func _advance_burial_command_world_tick() -> void:
	if burial_target == null:
		return
	if (
		not is_instance_valid(burial_target)
		or burial_target.is_alive
		or burial_target.faction_id != 1
		or burial_worker == null
		or not is_instance_valid(burial_worker)
		or not burial_worker.is_alive
	):
		_cancel_burial_command()
		return
	if not is_original_burial_range(burial_worker.position, burial_target.position):
		if burial_action_started:
			burial_action_started = false
			burial_progress_ticks = 0
			burial_worker.set_action_progress(-1.0)
			burial_target.set_action_progress(-1.0)
		if (
			burial_worker.movement_path_index >= burial_worker.movement_path.size()
			and not burial_worker.position.is_equal_approx(burial_target.position)
		):
			_issue_burial_approach_path()
		return
	if not burial_action_started:
		burial_action_started = true
		burial_progress_ticks = 0
		burial_worker.cancel_path()
		_face_actor_toward(burial_worker, burial_target.position)
	burial_progress_ticks += 1
	# The original feedback belongs to the operated object. Drawing it on the
	# worker made the bar wander while the corpse itself remained ambiguous.
	burial_target.set_action_progress(
		clampf(
			float(burial_progress_ticks) / float(ORIGINAL_BURIAL_COUNTER_LIMIT),
			0.0,
			1.0,
		)
	)
	update_status(
		"掩埋中 %d%%"
		% mini(
			int(
				100.0
				* float(burial_progress_ticks)
				/ float(ORIGINAL_BURIAL_COUNTER_LIMIT)
			),
			100,
		)
	)
	# sub_456CD0 completes only when the counter is strictly greater than 100.
	if burial_progress_ticks > ORIGINAL_BURIAL_COUNTER_LIMIT:
		_finish_burial()


func _issue_burial_approach_path() -> void:
	if (
		burial_worker == null
		or burial_target == null
		or not is_instance_valid(burial_worker)
		or not is_instance_valid(burial_target)
	):
		return
	var path := PackedVector2Array()
	if dynamic_occupancy != null and burial_worker.scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			burial_worker.scene_index,
			burial_worker.position,
			burial_target.position,
		)
	elif navigation_grid != null:
		path = navigation_grid.find_path(
			burial_worker.position,
			burial_target.position,
			true,
		)
	else:
		path.append(burial_target.position)
	if path.is_empty() and not is_original_burial_range(
		burial_worker.position, burial_target.position
	):
		burial_worker.cancel_path()
		update_status("无法到达该尸体附近")
		return
	burial_worker.issue_path(path)
	burial_worker.original_command_goal_kind_latch = 4


func _cancel_burial_command(preserve_completed_goal: bool = false) -> void:
	if burial_worker != null and is_instance_valid(burial_worker):
		burial_worker.set_action_progress(-1.0)
		if not preserve_completed_goal:
			burial_worker.original_command_goal_kind_latch = 0
	if burial_target != null and is_instance_valid(burial_target):
		burial_target.set_action_progress(-1.0)
	burial_target = null
	burial_worker = null
	burial_progress_ticks = 0
	burial_action_started = false


static func is_original_burial_range(
	worker_position: Vector2,
	target_position: Vector2,
) -> bool:
	var worker_cell := Vector2i(
		floori(worker_position.x / float(ORIGINAL_BURIAL_GRID_SIZE.x)),
		floori(worker_position.y / float(ORIGINAL_BURIAL_GRID_SIZE.y)),
	)
	var target_cell := Vector2i(
		floori(target_position.x / float(ORIGINAL_BURIAL_GRID_SIZE.x)),
		floori(target_position.y / float(ORIGINAL_BURIAL_GRID_SIZE.y)),
	)
	return (
		absi(worker_cell.x - target_cell.x) <= 1
		and absi(worker_cell.y - target_cell.y) <= 1
	)


static func _face_actor_toward(actor: Node2D, target_position: Vector2) -> void:
	var direction := target_position - actor.position
	if direction.is_zero_approx():
		return
	actor.set_animation_group(SQUAD_UNIT.direction_group_index(direction))
	actor.apply_idle_frame()
	actor.queue_redraw()


func _spawn_legacy_burial_cache(
	world_position: Vector2,
	source_scene_index: int,
	weapon_snapshot: Dictionary,
	backpack_snapshot: Dictionary,
	runtime_snapshot: Dictionary = {},
) -> Node2D:
	var cache: Node2D = LEGACY_BURIAL_CACHE_SCRIPT.new()
	cache.name = "LegacyBurialCache_%d" % source_scene_index
	cache.call(
		"configure",
		world_position,
		source_scene_index,
		weapon_snapshot,
		backpack_snapshot,
		_load_legacy_special_visual(64),
	)
	if not runtime_snapshot.is_empty():
		cache.call("restore_runtime_state", runtime_snapshot)
	cache.connect(
		"tree_exited",
		Callable(self, "_on_legacy_burial_cache_exited").bind(cache),
	)
	add_child(cache)
	legacy_burial_caches.append(cache)
	return cache


func _on_legacy_burial_cache_exited(cache: Node2D) -> void:
	legacy_burial_caches.erase(cache)


func _try_interact_burial_cache_at(world_position: Vector2) -> bool:
	var cache: Node2D
	for candidate: Node2D in legacy_burial_caches:
		if (
			is_instance_valid(candidate)
			and bool(candidate.call("has_loot"))
			and bool(candidate.call("contains_parent_point", world_position))
		):
			cache = candidate
			break
	if cache == null:
		return false
	if selected_units.is_empty():
		update_status("请先选择一名队员查看藏尸处")
		return true
	var collector := selected_units[0]
	if bool(cache.call("can_interact", collector)):
		var transferred := cache.call("transfer_all_to", collector) as Dictionary
		_on_original_pickup_cover_committed(collector, cache.position)
		update_status(
			"已从藏尸处取得 %d 类武器物资和 %d 类背包物品"
			% [
				int(transferred.get("weapon_entries", 0)),
				int(transferred.get("backpack_entries", 0)),
			]
		)
		_refresh_inventory_ui()
		return true
	_clear_original_pickup_order()
	_clear_original_drop_order()
	_cancel_legacy_deployment_for_unit(collector)
	collector.clear_combat_target()
	var path := PackedVector2Array()
	if dynamic_occupancy != null and collector.scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			collector.scene_index,
			collector.position,
			cache.position,
		)
	elif navigation_grid != null:
		path = navigation_grid.find_path(collector.position, cache.position, true)
	else:
		path.append(cache.position)
	collector.issue_path(path)
	update_status("队员正在接近藏尸处；到达后再次点击或按 E 取物")
	return true


func legacy_door_at_world_point(world_position: Vector2) -> Node2D:
	var candidates: Array = []
	if world_spatial_index != null:
		candidates = world_spatial_index.query_radius(world_position, 96.0, ["door"])
	if candidates.is_empty():
		candidates = legacy_doors
	for door_value: Variant in candidates:
		if not door_value is Node2D:
			continue
		var door := door_value as Node2D
		if (
			is_instance_valid(door)
			and not bool(door.get("is_open"))
			and bool(door.call("contains_parent_point", world_position))
		):
			return door
	return null


func mission_inventory_pickup_at_world_point(
	world_position: Vector2,
) -> MISSION_PICKUP:
	var nearest: MISSION_PICKUP
	var nearest_distance := INF
	var candidates: Array = []
	if world_spatial_index != null:
		candidates = world_spatial_index.query_radius(world_position, 96.0, ["mission_pickup"])
	if candidates.is_empty():
		candidates = mission_pickups
	for pickup_value: Variant in candidates:
		if not pickup_value is MISSION_PICKUP:
			continue
		var pickup := pickup_value as MISSION_PICKUP
		if (
			pickup != null
			and is_instance_valid(pickup)
			and not pickup.collected
			and str(pickup.item_payload.get("original_inventory_kind", ""))
				in ["backpack", "weapon"]
			and pickup.contains_parent_point(world_position)
		):
			var distance := pickup.pointer_distance_squared(world_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = pickup
	return nearest


func _preferred_pickup_at_world_point(world_position: Vector2) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var loose_inventory := mission_inventory_pickup_at_world_point(world_position)
	if loose_inventory != null:
		candidates.append(WORLD_INTERACTION_RESOLVER.candidate(
			"loose_inventory",
			loose_inventory,
			WORLD_INTERACTION_RESOLVER.Priority.LOOSE_INVENTORY,
			world_position,
		))
	var field_pickup := field_pickup_at_world_point(world_position)
	if field_pickup != null:
		candidates.append(WORLD_INTERACTION_RESOLVER.candidate(
			"field_pickup",
			field_pickup,
			WORLD_INTERACTION_RESOLVER.Priority.FIELD_PICKUP,
			world_position,
		))
	return WORLD_INTERACTION_RESOLVER.choose(candidates)


func _try_issue_preferred_pickup(world_position: Vector2) -> bool:
	var resolved := _preferred_pickup_at_world_point(world_position)
	if resolved.is_empty():
		return false
	var pickup_value: Variant = resolved.get("node")
	if not pickup_value is Node2D or not is_instance_valid(pickup_value):
		return false
	issue_original_pickup_order(pickup_value as Node2D)
	return true


func _try_open_legacy_door_at(world_position: Vector2) -> bool:
	var door := legacy_door_at_world_point(world_position)
	if door == null:
		return false
	if bool(door.call("open")):
		update_status(
			"已打开%s；原 VWF 移动与视线足印已同步释放"
			% str(door.get("original_display_name"))
		)
	return true


func _on_legacy_door_state_changed(door: Node2D, open: bool) -> void:
	if door == null or not is_instance_valid(door):
		return
	if open:
		# Existing actor paths may have resolved to a nearby partial endpoint
		# while the door was closed. Wake their next normal replan immediately.
		for unit: SQUAD_UNIT in units:
			unit.blocked_elapsed = unit.blocked_replan_seconds
		for enemy: ENEMY_UNIT in enemies:
			enemy.path_request_delay_remaining = 0.0
			enemy.chase_replan_elapsed = enemy.CHASE_REPLAN_SECONDS


func _advance_automatic_door_interactions() -> int:
	if legacy_doors.is_empty():
		return 0
	var moving_actors: Array[Node2D] = []
	for actor: Node2D in _all_active_runtime_actors():
		if not bool(actor.get("is_alive")):
			continue
		var path_value: Variant = actor.get("movement_path")
		if not path_value is PackedVector2Array:
			continue
		if int(actor.get("movement_path_index")) >= (path_value as PackedVector2Array).size():
			continue
		moving_actors.append(actor)
	if moving_actors.is_empty():
		return 0
	var opened_count := 0
	# Doors are static world-index records, so query them around each live actor
	# instead of evaluating the previous doors x actors Cartesian product every
	# physics tick. The radius is derived from the largest authored door bounds;
	# contains_approach_point remains the exact narrow-phase test.
	if (
		world_spatial_index != null
		and automatic_door_broadphase_radius > 0.0
	):
		for actor: Node2D in moving_actors:
			for door: Node2D in world_spatial_index.query_radius(
				actor.global_position,
				automatic_door_broadphase_radius,
				["door"],
			):
				if (
					door == null
					or not is_instance_valid(door)
					or bool(door.get("is_open"))
					or not door.has_method("contains_approach_point")
				):
					continue
				if (
					bool(door.call("contains_approach_point", actor.position))
					and bool(door.call("open"))
				):
					opened_count += 1
		return opened_count
	# Fixtures that deliberately bypass level/index construction retain the
	# original exact fallback.
	for door: Node2D in legacy_doors:
		if (
			door == null
			or not is_instance_valid(door)
			or bool(door.get("is_open"))
			or not door.has_method("contains_approach_point")
		):
			continue
		for actor: Node2D in moving_actors:
			if bool(door.call("contains_approach_point", actor.position)):
				if bool(door.call("open")):
					opened_count += 1
				break
	return opened_count


func restore_legacy_door_states(records: Array) -> int:
	var records_by_scene: Dictionary = {}
	for record_value: Variant in records:
		if record_value is Dictionary:
			var record := record_value as Dictionary
			records_by_scene[int(record.get("scene_index", -1))] = record
	var restored := 0
	for door: Node2D in legacy_doors:
		if not is_instance_valid(door):
			continue
		var scene_index := int(door.get("scene_index"))
		if not records_by_scene.has(scene_index):
			continue
		var record := records_by_scene[scene_index] as Dictionary
		door.call("set_open", bool(record.get("is_open", false)), false)
		restored += 1
	return restored


func _toggle_selected_run_walk() -> void:
	if selected_units.is_empty():
		update_status("请先选择队员")
		return
	var running := not selected_units[0].is_running
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_crawling:
			unit.set_running(running)
	update_status("选中队员切换为%s" % ("跑步" if running else "行走"))


func _toggle_selected_crawl() -> void:
	if selected_units.is_empty():
		update_status("请先选择队员")
		return
	var crawling := not selected_units[0].is_crawling
	for unit: SQUAD_UNIT in selected_units:
		unit.set_crawling(crawling)
	update_status("选中队员切换为%s" % ("匍匐" if crawling else "站立"))
	_report_direction_action("toggle_crawl")


func _toggle_sight_observation() -> void:
	burial_mode = false
	sight_observation_mode = true
	sight_target_pending = true
	if game_shell != null:
		game_shell.set_original_hud_action_state("observation", true)
	update_status("视线观察模式：点击存活敌军查看视野，或点击空地埋下观察标记")


func _select_sight_observation_target(world_point: Vector2) -> void:
	var target := enemy_at_world_point(world_point)
	if target != null and target.is_alive and target.faction_id == 1:
		_set_sight_observation_target(target)
		update_status("正在观察 %s 的动态扇形视野" % target.display_name)
	else:
		_place_or_move_sight_beacon(world_point)
		update_status("已设置原版唯一观察点；进入敌军当前视野后自动触发并消失")
	sight_target_pending = false
	sight_observation_mode = false
	if game_shell != null:
		game_shell.set_original_hud_action_state("observation", false)


func _place_or_move_sight_beacon(world_point: Vector2) -> Node2D:
	var seed := _sight_beacon_seed(world_point)
	if sight_beacon != null and is_instance_valid(sight_beacon):
		sight_beacon.call("move_marker", world_point, seed)
		sight_beacon.call("set_potential_observers", _living_enemy_observers())
		return sight_beacon
	# The original empty-ground S command creates the unique type-90 actor via
	# sub_44A350. Repositioning an existing marker mutates it in place and must
	# not repeat these four in-level constructor draws.
	if not _commit_original_dynamic_actor_factory("actor 90 观察标记"):
		return null
	var marker: Node2D = LEGACY_OBSERVATION_BEACON_SCRIPT.new()
	marker.name = "LegacyObservationBeacon"
	marker.call(
		"configure",
		world_point,
		dynamic_occupancy,
		_living_enemy_observers(),
		_load_legacy_special_visual(341),
		seed,
	)
	marker.call("set_external_polling", true)
	marker.connect("observed", Callable(self, "_on_sight_beacon_observed"))
	marker.connect("tree_exited", Callable(self, "_on_sight_beacon_exited").bind(marker))
	add_child(marker)
	marker.set("original_factory_random_consumed", true)
	sight_beacon = marker
	return marker


func advance_original_observation_for_actor(
	actor: Node2D,
	gate_passed: bool,
) -> bool:
	if (
		not gate_passed
		or sight_beacon == null
		or not is_instance_valid(sight_beacon)
		or actor == null
		or not is_instance_valid(actor)
		or not sight_beacon.has_method("advance_for_observer")
	):
		return false
	return bool(sight_beacon.call(
		"advance_for_observer",
		actor,
		true,
	))


func _living_enemy_observers() -> Array[Node2D]:
	var observers: Array[Node2D] = []
	for enemy: ENEMY_UNIT in enemies:
		if is_instance_valid(enemy) and enemy.is_alive and enemy.faction_id == 1:
			observers.append(enemy)
	return observers


func _on_sight_beacon_observed(marker: Node2D, observer: Node2D) -> void:
	if (
		marker != null
		and is_instance_valid(marker)
		and not bool(marker.get("original_destructor_random_consumed"))
		and _commit_original_dynamic_actor_destructor("actor 90 观察标记")
	):
		marker.set("original_destructor_random_consumed", true)
	if marker == sight_beacon:
		sight_beacon = null
	if observer is ENEMY_UNIT:
		_set_sight_observation_target(observer as ENEMY_UNIT)
		update_status("%s 触发观察点；标记已消失" % (observer as ENEMY_UNIT).display_name)


func _on_sight_beacon_exited(marker: Node2D) -> void:
	if marker == sight_beacon:
		sight_beacon = null


func _set_sight_observation_target(target: ENEMY_UNIT) -> void:
	_clear_sight_observation_target()
	sight_observation_target = target
	if target != null and is_instance_valid(target):
		sight_observation_remaining = SIGHT_OBSERVATION_DURATION_SECONDS
		target.set_selected(true)
		target.set_tactical_ranges_visible(true)


func _clear_sight_observation_target() -> void:
	if sight_observation_target != null and is_instance_valid(sight_observation_target):
		sight_observation_target.set_selected(false)
		sight_observation_target.set_tactical_ranges_visible(false)
	sight_observation_target = null
	sight_observation_remaining = 0.0


func _remove_sight_beacon() -> void:
	if sight_beacon != null and is_instance_valid(sight_beacon):
		sight_beacon.queue_free()
	sight_beacon = null


func _sight_beacon_seed(world_point: Vector2) -> int:
	return maxi(
		1,
		(
			(current_level_index + 1) * 1103515245
			+ floori(world_point.x) * 31
			+ floori(world_point.y) * 17
		) & 0x7fffffff,
	)

func _mouse_world_position() -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * get_viewport().get_mouse_position()


func _reload_selected_units() -> void:
	var reload_count := 0
	var original_count := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		if (
			unit.combat_inventory != null
			and unit.combat_inventory.original_parity_enabled()
		):
			original_count += 1
			continue
		if unit.request_reload():
			reload_count += 1
	if original_count > 0 and reload_count == 0:
		update_status("原版武器直接消耗栏内数量，无需换弹")
	else:
		update_status("%d 名队员开始换弹" % reload_count)


func clear_selection() -> void:
	for unit: SQUAD_UNIT in selected_units:
		unit.set_selected(false)
	selected_units.clear()
	_refresh_inventory_ui()


func select_only(unit: SQUAD_UNIT) -> void:
	clear_selection()
	selected_units.append(unit)
	unit.set_selected(true)
	if level_camera != null:
		level_camera.position = unit.position
		clamp_level_camera()
	_refresh_inventory_ui()


func _equip_selected_attack_type(attack_type: int) -> void:
	var equipped := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		if unit.equip_attack_type(attack_type):
			equipped += 1
	update_status(
		"%d 名队员切换为%s" % [equipped, str(WEAPON_NAMES.get(attack_type, "武器"))]
	)
	if attack_type == 10 and equipped > 0:
		_report_direction_action("equip_explosives")
	_refresh_inventory_ui()
	command_bus.issue(
		"equip_weapon",
		{"attack_type": attack_type, "equipped_units": equipped},
	)


func _cycle_selected_weapons(direction: int) -> void:
	var equipped := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		if unit.cycle_inventory_weapon(direction):
			equipped += 1
	update_status("%d 名队员已轮换武器" % equipped)
	_refresh_inventory_ui()


func _try_issue_legacy_world_object_deployment(world_position: Vector2) -> bool:
	var special_action_selected := false
	for selected_unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(selected_unit)
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_alive:
			continue
		var attack_type := int(unit.weapon_profile.get("attack_type", 0))
		if not LEGACY_SPECIAL_ACTION_PROFILES.is_world_object_attack(attack_type):
			continue
		special_action_selected = true
		_clear_original_pickup_order()
		_clear_original_drop_order()
		var evidence_profile: Dictionary = (
			LEGACY_SPECIAL_ACTION_PROFILES.profile_for_attack_type(attack_type)
		)
		var item_id := int(evidence_profile.get("ammo_item_id", 0))
		if item_id <= 0 or unit.ammo_item_count(item_id) <= 0:
			continue
		var resolved_position_value: Variant = _resolve_legacy_deployment_position(
			unit,
			world_position,
		)
		if not resolved_position_value is Vector2:
			update_status("部署位置不可达，请选择可行走区域")
			return true
		var resolved_position := resolved_position_value as Vector2
		var target := LegacyDeploymentTarget.new()
		target.name = "LegacyDeploymentTarget_%d" % (legacy_deployment_targets.size() + 1)
		target.configure(resolved_position, unit)
		add_child(target)
		legacy_deployment_targets.append(target)
		target.tree_exited.connect(_on_legacy_deployment_target_exited.bind(target))
		if unit.issue_attack(target, true):
			unit.queue_original_acknowledgement()
			update_status(
				"%s前往部署%s → (%d, %d)"
				% [unit.display_name, str(WEAPON_NAMES.get(attack_type, "特殊物品")), resolved_position.x, resolved_position.y]
			)
			return true
		legacy_deployment_targets.erase(target)
		target.free()
		if dynamic_occupancy != null and unit.scene_index >= 0:
			dynamic_occupancy.call("release_goal", unit.scene_index)
	if special_action_selected:
		update_status("当前特殊物品数量不足，无法部署")
	return special_action_selected


func _resolve_legacy_deployment_position(
	unit: SQUAD_UNIT,
	requested_position: Vector2,
) -> Variant:
	if navigation_grid == null:
		return requested_position
	if unit.position.is_equal_approx(requested_position):
		return requested_position
	var path := PackedVector2Array()
	if dynamic_occupancy != null and unit.scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			unit.scene_index,
			unit.position,
			requested_position,
		)
	else:
		path = navigation_grid.find_path(unit.position, requested_position, true)
	if path.is_empty():
		return null
	return path[-1]


func _cancel_legacy_deployment_for_unit(unit: Node2D) -> void:
	if unit == null:
		return
	var cancelled := false
	for target: Node2D in legacy_deployment_targets.duplicate():
		if not is_instance_valid(target) or target.get("owner_actor") != unit:
			continue
		cancelled = true
		legacy_deployment_targets.erase(target)
		if target.has_method("resolve"):
			target.call("resolve")
	if cancelled:
		if unit.has_method("clear_combat_target"):
			unit.call("clear_combat_target")
		if unit.has_method("cancel_path"):
			unit.call("cancel_path")


func issue_formation_move(destination: Vector2) -> void:
	var formation_started_usec := Time.get_ticks_usec()
	last_formation_move_total_usec = 0
	last_formation_move_audio_usec = 0
	last_formation_move_path_usec = 0
	last_formation_move_event_usec = 0
	if selected_units.is_empty():
		update_status("请先选择队员")
		last_formation_move_total_usec = (
			Time.get_ticks_usec() - formation_started_usec
		)
		return
	if terrain_loaded and navigation_grid == null:
		update_status("当前关卡导航数据不可用，已拒绝可能穿墙的移动命令")
		last_formation_move_total_usec = (
			Time.get_ticks_usec() - formation_started_usec
		)
		return
	# A new ordinary ground command replaces the original status-3 pickup
	# command just as sub_458A80 replaces the active target tuple.
	_clear_original_pickup_order()
	_clear_original_drop_order()
	var audio_started_usec := Time.get_ticks_usec()
	# The original trace consumes sub_45D7B0 in the addressed actor's update
	# slot (runtime index 18 in the recovered m000 movement branch), between
	# the neighbouring actor-17 and actor-19 observation calls. Queue the
	# request so this click cannot reorder the process-global CRT stream.
	selected_units[0].queue_original_acknowledgement()
	last_formation_move_audio_usec = (
		Time.get_ticks_usec() - audio_started_usec
	)
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
		_cancel_legacy_deployment_for_unit(unit)
		unit.clear_combat_target()
		var unit_destination := center + offsets[index]
		if navigation_grid == null:
			unit.issue_move(unit_destination)
			planned_count += 1
			continue
		if (
			str(runtime_settings.get("ruleset_mode", "classic")) == "modern"
			and navigation_requests != null
		):
			var request_serial := int(navigation_requests.enqueue(
				unit.scene_index,
				unit.position,
				unit_destination,
				Callable(self, "_complete_deferred_formation_path").bind(unit),
			))
			if request_serial > 0:
				planned_count += 1
				continue
		var path := PackedVector2Array()
		var path_started_usec := Time.get_ticks_usec()
		if dynamic_occupancy != null and unit.scene_index >= 0:
			path = dynamic_occupancy.find_path_for_scene(
				unit.scene_index, unit.position, unit_destination
			)
		else:
			path = navigation_grid.find_path(unit.position, unit_destination)
		last_formation_move_path_usec += (
			Time.get_ticks_usec() - path_started_usec
		)
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
	if planned_count > 0:
		var event_started_usec := Time.get_ticks_usec()
		_report_direction_action("move_order")
		if str(current_mission.get("id", "")) == "m010" and selected_units.size() == 1:
			_record_m010_split_order(selected_units[0])
		last_formation_move_event_usec = (
			Time.get_ticks_usec() - event_started_usec
		)
	last_formation_move_total_usec = (
		Time.get_ticks_usec() - formation_started_usec
	)
	command_bus.issue(
		"formation_move",
		{
			"destination": destination,
			"planned_units": planned_count,
			"selected_units": selected_units.size(),
			"elapsed_usec": last_formation_move_total_usec,
		},
	)


func _complete_deferred_formation_path(
	path: PackedVector2Array,
	request: Dictionary,
	elapsed_usec: int,
	unit: SQUAD_UNIT,
) -> void:
	last_formation_move_path_usec += maxi(elapsed_usec, 0)
	if unit == null or not is_instance_valid(unit) or not unit.is_alive:
		return
	var destination := request.get("destination", unit.position) as Vector2
	if path.is_empty() and not unit.position.is_equal_approx(destination):
		unit.cancel_path()
		update_status(tr("STATUS_NAVIGATION_UNREACHABLE"))
		command_bus.emit_event(
			"navigation_failed",
			{"scene_index": unit.scene_index, "destination": destination},
		)
		return
	unit.issue_path(path)
	command_bus.emit_event(
		"navigation_ready",
		{
			"scene_index": unit.scene_index,
			"waypoints": path.size(),
			"elapsed_usec": elapsed_usec,
		},
	)


func _record_m010_split_order(unit: SQUAD_UNIT) -> void:
	if unit == null or str(current_mission.get("id", "")) != "m010":
		return
	var rule := current_mission.get("simultaneous_zone_rule", {}) as Dictionary
	var eligible_names := rule.get("eligible_player_names", []) as Array
	if eligible_names.is_empty() or not eligible_names.has(unit.display_name):
		return
	m010_split_ordered_names[unit.display_name] = true
	for name_value: Variant in eligible_names:
		if not m010_split_ordered_names.has(str(name_value)):
			return
	_report_direction_action("issue_split_orders")


func enemy_at_world_point(world_point: Vector2) -> ENEMY_UNIT:
	var nearest: ENEMY_UNIT
	var nearest_distance := 30.0 * 30.0
	var candidates: Array = []
	if world_spatial_index != null:
		candidates = world_spatial_index.query_radius(world_point, 30.0, ["enemy"])
	if candidates.is_empty():
		candidates = enemies
	for enemy_value: Variant in candidates:
		if not enemy_value is ENEMY_UNIT:
			continue
		var enemy := enemy_value as ENEMY_UNIT
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
	var candidates: Array = []
	if world_spatial_index != null:
		candidates = world_spatial_index.query_radius(world_point, 30.0, ["explosive"])
	if candidates.is_empty():
		candidates = explosive_props
	for prop_value: Variant in candidates:
		if not prop_value is Node2D:
			continue
		var prop := prop_value as Node2D
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


func field_pickup_at_world_point(world_point: Vector2) -> Node2D:
	var nearest: Node2D
	var nearest_distance := INF
	var candidates: Array = []
	if world_spatial_index != null:
		candidates = world_spatial_index.query_radius(world_point, 96.0, ["field_pickup"])
	if candidates.is_empty():
		candidates = field_pickups
	for pickup_value: Variant in candidates:
		if not pickup_value is Node2D or pickup_value is MISSION_PICKUP:
			continue
		var pickup := pickup_value as Node2D
		if (
			not is_instance_valid(pickup)
			or bool(pickup.get("consumed"))
			or not pickup.has_method("contains_parent_point")
			or not bool(pickup.call("contains_parent_point", world_point))
		):
			continue
		var distance := pickup.position.distance_squared_to(world_point)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = pickup
	return nearest


func force_target_at_world_point(world_point: Vector2) -> Node2D:
	var nearest: Node2D
	var nearest_distance := 30.0 * 30.0
	var candidates: Array[Node2D] = []
	if world_spatial_index != null:
		candidates.assign(
			world_spatial_index.query_radius(world_point, 30.0, ["combatant"])
		)
	if candidates.is_empty():
		for unit: SQUAD_UNIT in units:
			if not selected_units.has(unit):
				candidates.append(unit)
		for escort: ESCORT_UNIT in escorts:
			if not selected_units.has(escort):
				candidates.append(escort)
		for ambient: AMBIENT_UNIT in ambient_units:
			candidates.append(ambient)
		for enemy: ENEMY_UNIT in enemies:
			candidates.append(enemy)
		for prop: Node2D in explosive_props:
			candidates.append(prop)
	for candidate: Node2D in candidates:
		if (
			not is_instance_valid(candidate)
			or not candidate.has_method("is_combat_alive")
			or not bool(candidate.call("is_combat_alive"))
		):
			continue
		var distance := candidate.position.distance_squared_to(world_point)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


func issue_attack_order(target: Node2D, force_target: bool = false) -> void:
	if (
		selected_units.is_empty()
		or target == null
		or not target.has_method("is_combat_alive")
		or not bool(target.call("is_combat_alive"))
	):
		update_status("请先选择存活队员和敌方目标")
		return
	_clear_original_pickup_order()
	_clear_original_drop_order()
	var issued := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		var disguised_player_attack := (
			unit.runtime_actor_type
				== LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE
			and int(target.get("faction_id"))
				== LEGACY_DISGUISE_RULES.DISGUISED_FACTION_ID
		)
		if unit.issue_attack(
			target,
			force_target or disguised_player_attack,
		):
			unit.queue_original_acknowledgement()
			issued += 1
	var target_name := (
		str(target.display_name)
		if target is ENEMY_UNIT
		else str(target.get("original_display_name"))
	)
	var command_name := "强制攻击" if force_target else "攻击"
	update_status("%s命令：%d 名队员 → %s" % [command_name, issued, target_name])
	command_bus.issue(
		"attack_order",
		{
			"target_scene_index": int(target.get("scene_index")),
			"force_target": force_target,
			"issued_units": issued,
		},
	)


func issue_force_attack_order(world_position: Vector2) -> void:
	if selected_units.is_empty():
		update_status("请先选择执行强制攻击的队员")
		return
	_clear_original_pickup_order()
	_clear_original_drop_order()
	var issued := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		if unit.issue_force_attack_at(world_position):
			unit.queue_original_acknowledgement()
			issued += 1
	if issued <= 0:
		update_status("当前武器无法向该位置强制攻击，或正在冷却/弹药不足")
		return
	update_status("强制攻击：%d 名队员向指定位置开火" % issued)
	command_bus.issue(
		"force_attack_coordinate",
		{
			"x": world_position.x,
			"y": world_position.y,
			"issued_units": issued,
		},
	)


func _connect_combatant(combatant: Node2D) -> void:
	if combatant.has_method("set_reduced_violence"):
		combatant.call(
			"set_reduced_violence",
			bool(runtime_settings.get("reduced_violence", false)),
		)
	var spatial_tags: Array[String] = ["actor", "combatant"]
	if combatant is ENEMY_UNIT:
		spatial_tags.append("enemy")
	elif combatant is ESCORT_UNIT:
		spatial_tags.append("escort")
	elif combatant is AMBIENT_UNIT:
		spatial_tags.append("ambient")
	else:
		spatial_tags.append("player")
	_register_spatial_node(combatant, spatial_tags)
	combatant.attack_started.connect(_on_attack_started)
	combatant.attack_hit.connect(_on_attack_hit)
	combatant.attack_missed.connect(_on_attack_missed)
	combatant.damage_received.connect(_on_damage_received)
	combatant.died.connect(_on_combatant_died)
	combatant.ammo_changed.connect(_on_ammo_changed)
	combatant.projectile_requested.connect(_on_projectile_requested)
	combatant.coordinate_attack_started.connect(_on_coordinate_attack_started)
	combatant.coordinate_projectile_requested.connect(
		_on_coordinate_projectile_requested
	)
	combatant.special_action_requested.connect(_on_legacy_special_action_requested)
	combatant.original_disguise_attack_committed.connect(
		_on_original_disguise_attack_committed
	)
	combatant.original_disguise_transition_ready.connect(
		_on_original_disguise_transition_ready
	)
	combatant.original_animation_audio_requested.connect(
		_on_original_animation_audio_requested
	)
	combatant.original_command_audio_requested.connect(
		_on_original_command_audio_requested
	)
	if combatant is ENEMY_UNIT:
		var enemy := combatant as ENEMY_UNIT
		enemy.legacy_world_item_interaction_requested.connect(
			_on_enemy_legacy_world_item_interaction_requested
		)
		enemy.legacy_hypnosis_changed.connect(
			_on_enemy_legacy_hypnosis_changed
		)
		enemy.legacy_corpse_discovery_triggered.connect(
			_on_enemy_legacy_corpse_discovered
		)
		enemy.original_actor_audio_requested.connect(
			_on_enemy_original_actor_audio_requested
		)


func _on_enemy_original_actor_audio_requested(
	enemy: ENEMY_UNIT,
	family: String,
) -> void:
	_play_original_actor_audio(family, enemy)


func _on_original_command_audio_requested(
	actor: Node2D,
	family: String,
) -> void:
	_play_original_actor_audio(family, actor)


func _on_original_animation_audio_requested(
	actor: Node2D,
	gfl_index: int,
	continuous: bool,
) -> void:
	if media_director == null or gfl_index <= 0:
		return
	if continuous:
		var requester_id := actor.get_instance_id() if actor != null else 0
		if _is_actor_footstep_request(actor):
			var mix: Dictionary = WORLD_AUDIO_SPATIALIZER.mix_for_source(
				actor.global_position,
				_camera_world_rect(),
			)
			if not bool(mix.get("audible", true)):
				media_director.stop_sfx_requester(requester_id, gfl_index)
				return
			media_director.request_sfx_audio_index(
				gfl_index,
				requester_id,
				float(mix.get("volume_db", 0.0)),
			)
			return
		media_director.request_sfx_audio_index(
			gfl_index,
			requester_id,
		)
	else:
		media_director.play_audio_index(
			gfl_index,
			"sprite_animation",
		)


func _is_actor_footstep_request(actor: Node2D) -> bool:
	if actor == null or not actor is SQUAD_UNIT:
		return false
	var unit := actor as SQUAD_UNIT
	return (
		unit.combat_action == SQUAD_UNIT.CombatAction.NONE
		and (
			unit.was_moving
			or unit.movement_path_index < unit.movement_path.size()
		)
	)


func _on_projectile_requested(
	attacker: Node2D,
	target: Node2D,
	profile: Dictionary,
) -> void:
	if projectile_world == null:
		return
	projectile_world.launch_all_for_weapon(attacker, target, profile)


func _on_coordinate_projectile_requested(
	attacker: Node2D,
	world_position: Vector2,
	profile: Dictionary,
) -> void:
	if projectile_world == null:
		return
	projectile_world.launch_all_for_weapon(
		attacker,
		null,
		profile,
		world_position,
	)


func _on_coordinate_attack_started(
	attacker: Node2D,
	world_position: Vector2,
	attack_type: int,
	alert_radius: float,
) -> void:
	command_bus.emit_event(
		"attack_started",
		{
			"player": attacker is SQUAD_UNIT,
			"attacker_scene_index": int(attacker.get("scene_index")),
			"target_scene_index": -1,
			"attack_type": attack_type,
			"coordinate_x": world_position.x,
			"coordinate_y": world_position.y,
		},
		"combat",
	)
	if alert_radius <= 0.0:
		return
	_show_world_sound_caption(tr("SOUND_GUNSHOT"), attacker.position, alert_radius)
	# Empty-ground gunfire intentionally exposes the shooter. This is the modern
	# force-fire/lure use case: hearing ignores walls, while later visual contact
	# still uses the clipped sight fan.
	_queue_or_broadcast_alert(
		attacker,
		attacker,
		attacker.position,
		alert_radius,
	)


func _on_legacy_special_action_requested(
	attacker: Node2D,
	target: Node2D,
	_weapon_profile: Dictionary,
) -> void:
	if attacker == null or target == null or not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	var attack_type := int(_weapon_profile.get("attack_type", 0))
	var evidence_profile: Dictionary = LEGACY_SPECIAL_ACTION_PROFILES.profile_for_attack_type(
		attack_type
	)
	if evidence_profile.is_empty():
		return
	if LEGACY_SPECIAL_ACTION_PROFILES.is_world_object_attack(attack_type):
		# SquadUnit consumes the actor's item-45 entry at the recovered hit
		# frame before emitting this request. A second shared-inventory decrement
		# here used to charge the same placement twice.
		_spawn_legacy_special_world_object(
			evidence_profile,
			target.global_position,
			attacker,
		)
	elif attack_type == LEGACY_SPECIAL_ACTION_PROFILES.AI_CONTROL_ATTACK_TYPE:
		_apply_legacy_ai_control(evidence_profile, attacker, target)
	_consume_legacy_deployment_target(target)


func _spawn_legacy_special_world_object(
	evidence_profile: Dictionary,
	world_position: Vector2,
	attacker: Node2D,
	new_source_faction_id: int = -1,
	consume_factory_random: bool = true,
) -> Node2D:
	# sub_456DF0 creates actor 84/85 through sub_44A350. Both known actor
	# resources exist in the stable product, so this is the successful factory
	# path: exactly four constructor draws. sub_45B950 is SAV restore only.
	# Restoring a save passes false because the persisted process-global state
	# already includes this transaction.
	if (
		consume_factory_random
		and not _commit_original_dynamic_actor_factory("actor 84/85")
	):
		return null
	var world_object: Node2D = LEGACY_SPECIAL_WORLD_OBJECT_SCRIPT.new()
	var attack_type := int(evidence_profile.get("attack_type", 0))
	var source_faction_id := new_source_faction_id
	if source_faction_id < 0:
		source_faction_id = int(attacker.get("faction_id")) if is_instance_valid(attacker) else 3
	var visual := _load_legacy_special_visual(
		int(evidence_profile.get("original_gfl_index", 0))
	)
	var resolved_visual_catalog := _load_legacy_explosion_visual_catalog()
	if not bool(world_object.call(
		"configure",
		evidence_profile,
		world_position,
		attacker,
		source_faction_id,
		visual,
		resolved_visual_catalog,
		world_size,
		legacy_crt_random_state,
	)):
		world_object.free()
		return null
	world_object.name = "LegacySpecial_%d_%d" % [attack_type, legacy_special_world_objects.size() + 1]
	var trigger_candidates: Array[Node2D] = []
	for enemy: ENEMY_UNIT in enemies:
		if is_instance_valid(enemy):
			trigger_candidates.append(enemy)
	world_object.call("set_potential_targets", trigger_candidates)
	world_object.connect("explosion_requested", Callable(self, "_on_world_explosion_requested"))
	world_object.connect(
		"resolved",
		Callable(self, "_on_legacy_special_world_object_retired"),
	)
	world_object.connect(
		"disarmed",
		Callable(self, "_on_legacy_special_world_object_retired"),
	)
	world_object.connect(
		"original_animation_audio_requested",
		Callable(self, "_on_original_world_animation_audio_requested"),
	)
	world_object.connect("tree_exited", Callable(self, "_on_legacy_special_world_object_exited").bind(world_object))
	add_child(world_object)
	if world_object.has_method("bind_original_crt_random_source"):
		world_object.call("bind_original_crt_random_source", self)
	world_object.set("original_factory_random_consumed", true)
	legacy_special_world_objects.append(world_object)
	_record_native_timed_explosive_presence(world_object)
	return world_object


func _apply_legacy_ai_control(
	evidence_profile: Dictionary,
	attacker: Node2D,
	target: Node2D,
) -> Node:
	for effect: Node in legacy_ai_control_effects:
		if (
			is_instance_valid(effect)
			and effect.get("target_actor") == target
			and bool(effect.call("is_active"))
		):
			effect.call("refresh", attacker)
			return effect
	if not target.has_method("apply_special_control"):
		return null
	var effect: Node = LEGACY_AI_CONTROL_EFFECT_SCRIPT.new()
	if not bool(effect.call("configure", evidence_profile, attacker, target)):
		effect.free()
		return null
	effect.name = "LegacyAiControl_%d" % (legacy_ai_control_effects.size() + 1)
	effect.connect("released", Callable(self, "_on_legacy_ai_control_released"))
	add_child(effect)
	legacy_ai_control_effects.append(effect)
	return effect


func _on_legacy_special_world_object_exited(world_object: Node2D) -> void:
	legacy_special_world_objects.erase(world_object)


func _on_legacy_special_world_object_retired(world_object: Node2D) -> void:
	if (
		world_object == null
		or not is_instance_valid(world_object)
		or bool(world_object.get("original_destructor_random_consumed"))
	):
		return
	# The actor-62 request is emitted synchronously before resolved/disarmed, so
	# the derived sub_453650 pair and base sub_450AC0 pair are consumed only
	# after the replacement/effect factory, matching manager removal order.
	if not _commit_original_dynamic_actor_destructor("actor 84/85"):
		return
	world_object.set("original_destructor_random_consumed", true)
	if world_object.is_inside_tree():
		world_object.queue_free()


func _commit_original_dynamic_actor_factory(context: String) -> bool:
	var plan: Dictionary = (
		LEGACY_EXPLOSION_VISUAL_RULES.build_dynamic_actor_factory_plan(
			legacy_crt_random_state,
			true,
		)
	)
	if (
		plan.is_empty()
		or not commit_legacy_crt_random_draws(
			plan.get("random_draws", []) as Array
		)
		or legacy_crt_random_state
			!= int(plan.get("next_random_state", -1))
	):
		push_error("%s 工厂的全局 CRT rand 批次不连续" % context)
		return false
	return true


func _commit_original_dynamic_actor_destructor(context: String) -> bool:
	var plan: Dictionary = (
		LEGACY_EXPLOSION_VISUAL_RULES.build_dynamic_actor_destructor_plan(
			legacy_crt_random_state
		)
	)
	if (
		plan.is_empty()
		or not commit_legacy_crt_random_draws(
			plan.get("random_draws", []) as Array
		)
		or legacy_crt_random_state
			!= int(plan.get("next_random_state", -1))
	):
		push_error("%s 析构的全局 CRT rand 批次不连续" % context)
		return false
	return true


func _consume_legacy_deployment_target(target: Node2D) -> void:
	if target == null or not legacy_deployment_targets.has(target):
		return
	legacy_deployment_targets.erase(target)
	if is_instance_valid(target) and target.has_method("resolve"):
		target.call("resolve")


func _on_legacy_deployment_target_exited(target: Node2D) -> void:
	legacy_deployment_targets.erase(target)


func _on_legacy_ai_control_released(effect: Node, _target: Node2D) -> void:
	legacy_ai_control_effects.erase(effect)


func _load_legacy_special_visual(gfl_index: int) -> Dictionary:
	if converted_root.is_empty() or gfl_index <= 0:
		return {}
	var cache_key := "legacy-special-visual:%04d" % gfl_index
	if imported_animation_cache.has(cache_key):
		return (imported_animation_cache[cache_key] as Dictionary).duplicate()
	var stem := "%04d" % gfl_index
	var manifest_relative := "sprite-frames/%s/sprite.json" % stem
	var manifest_path := _contained_converted_path(converted_root, manifest_relative)
	if not manifest_path.is_empty() and FileAccess.file_exists(manifest_path):
		var file := FileAccess.open(manifest_path, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				var manifest := json.data as Dictionary
				var schema_version := int(manifest.get("schema_version", 1))
				var groups: Variant = manifest.get("groups", [])
				if groups is Array and not (groups as Array).is_empty():
					var raw_group: Variant = (groups as Array)[0]
					if raw_group is Dictionary:
						var group := raw_group as Dictionary
						var frames: Array[Texture2D] = IMPORTED_SPRITE_ANIMATION.load_group_atlas(
							group,
							group.get("frames", []) as Array,
							manifest_path.get_base_dir(),
						)
						if frames.is_empty():
							var raw_frames: Variant = group.get("frames", [])
							if raw_frames is Array:
								frames = IMPORTED_SPRITE_ANIMATION.load_individual_frames(
									raw_frames as Array,
									manifest_path.get_base_dir(),
								)
						if not frames.is_empty():
							var primary: Variant = group.get("primary_triplet", [])
							var anchor := frames[0].get_size() * 0.5
							if primary is Array and (primary as Array).size() == 3:
								anchor = Vector2(
									float((primary as Array)[0]),
									float((primary as Array)[2]),
								)
							var runtime_actor_type := 0
							var header_values: Variant = manifest.get("header_values", [])
							if header_values is Array and (header_values as Array).size() >= 3:
								runtime_actor_type = int((header_values as Array)[2])
							var visual := {
								"frames": frames,
								"frame_hold_ticks": maxi(int(group.get("frame_hold_ticks", 1)), 1),
								"anchor": anchor,
								"gfl_index": gfl_index,
								"runtime_actor_type": runtime_actor_type,
								"action_index": int(group.get("action_index", -1)),
							}
							var sound_metadata: Dictionary = (
								IMPORTED_SPRITE_ANIMATION.group_sound_metadata(
									group,
									schema_version,
								)
							)
							if sound_metadata.is_empty():
								return {}
							visual["sound_slf_index"] = int(
								sound_metadata.get("sound_slf_index", 0)
							)
							visual["sound_gfl_index"] = int(
								sound_metadata.get("sound_gfl_index", -1)
							)
							var lookup_tables: Dictionary = (
								IMPORTED_SPRITE_ANIMATION.normalized_lookup_tables(
									group
								)
							)
							if not lookup_tables.is_empty():
								visual["draw_order_row_lookup"] = (
									lookup_tables.get(
										"draw_order_rows",
										[],
									) as Array
								).duplicate()
							imported_animation_cache[cache_key] = visual
							return visual.duplicate()
	var preview_relative := "sprites/%s.png" % stem
	var preview_path := _contained_converted_path(converted_root, preview_relative)
	if preview_path.is_empty() or not FileAccess.file_exists(preview_path):
		return {}
	var texture: Texture2D
	if imported_texture_cache.has(preview_path):
		texture = imported_texture_cache[preview_path] as Texture2D
	else:
		var image := Image.new()
		if image.load(preview_path) != OK or image.is_empty():
			return {}
		texture = ImageTexture.create_from_image(image)
		imported_texture_cache[preview_path] = texture
	var fallback := {
		"frames": [texture],
		"frame_hold_ticks": 1,
		"anchor": texture.get_size() * 0.5,
		"gfl_index": gfl_index,
		"runtime_actor_type": 0,
		"action_index": -1,
		"sound_slf_index": 0,
		"sound_gfl_index": -1,
	}
	imported_animation_cache[cache_key] = fallback
	return fallback.duplicate()


func _load_legacy_explosion_visual_catalog() -> Dictionary:
	var result: Dictionary = {}
	for gfl_index: int in LEGACY_EXPLOSION_VISUAL_RULES.supported_gfl_indices():
		var visual := _load_legacy_special_visual(gfl_index)
		if not visual.is_empty():
			result[gfl_index] = visual
	return result


func _load_legacy_projectile_visual(gfl_index: int) -> Dictionary:
	if converted_root.is_empty() or gfl_index <= 0:
		return {}
	var cache_key := "legacy-projectile-visual:%04d" % gfl_index
	if imported_animation_cache.has(cache_key):
		return (imported_animation_cache[cache_key] as Dictionary).duplicate()
	var stem := "%04d" % gfl_index
	var manifest_relative := "sprite-frames/%s/sprite.json" % stem
	var manifest_path := _contained_converted_path(
		converted_root,
		manifest_relative,
	)
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		return _load_legacy_special_visual(gfl_index)
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var manifest := json.data as Dictionary
	var schema_version := int(manifest.get("schema_version", 1))
	var raw_groups: Variant = manifest.get("groups", [])
	if not raw_groups is Array:
		return {}
	var loaded_groups: Array[Dictionary] = []
	for raw_group: Variant in raw_groups as Array:
		if not raw_group is Dictionary:
			continue
		var group := raw_group as Dictionary
		var frames: Array[Texture2D] = (
			IMPORTED_SPRITE_ANIMATION.load_group_atlas(
				group,
				group.get("frames", []) as Array,
				manifest_path.get_base_dir(),
			)
		)
		if frames.is_empty():
			var raw_frames: Variant = group.get("frames", [])
			if raw_frames is Array:
				frames = IMPORTED_SPRITE_ANIMATION.load_individual_frames(
					raw_frames as Array,
					manifest_path.get_base_dir(),
				)
		if frames.is_empty():
			continue
		var primary := group.get("primary_triplet", []) as Array
		var anchor := frames[0].get_size() * 0.5
		if primary.size() == 3:
			anchor = Vector2(float(primary[0]), float(primary[2]))
		var sound_metadata: Dictionary = (
			IMPORTED_SPRITE_ANIMATION.group_sound_metadata(
				group,
				schema_version,
			)
		)
		if sound_metadata.is_empty():
			return {}
		loaded_groups.append({
			"group_index": int(group.get("group_index", loaded_groups.size())),
			"action_index": int(group.get("action_index", -1)),
			"direction_index": int(group.get("direction_index", 0)),
			"direction_key": String(group.get("direction_key", "none")),
			"frames": frames,
			"frame_hold_ticks": maxi(
				int(group.get("frame_hold_ticks", 1)),
				1,
			),
			"anchor": anchor,
			"sound_slf_index": int(sound_metadata.get("sound_slf_index", 0)),
			"sound_gfl_index": int(sound_metadata.get("sound_gfl_index", -1)),
		})
	if loaded_groups.is_empty():
		return _load_legacy_special_visual(gfl_index)
	loaded_groups.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return int(first["group_index"]) < int(second["group_index"])
	)
	var header_values := manifest.get("header_values", []) as Array
	var visual := {
		"groups": loaded_groups,
		"frames": loaded_groups[0].get("frames", []),
		"frame_hold_ticks": int(loaded_groups[0].get("frame_hold_ticks", 1)),
		"anchor": loaded_groups[0].get("anchor", Vector2.ZERO),
		"gfl_index": gfl_index,
		"action_index": int(loaded_groups[0].get("action_index", -1)),
		"sound_slf_index": int(loaded_groups[0].get("sound_slf_index", 0)),
		"sound_gfl_index": int(loaded_groups[0].get("sound_gfl_index", -1)),
		"runtime_actor_type": (
			int(header_values[2]) if header_values.size() >= 3 else 0
		),
	}
	imported_animation_cache[cache_key] = visual
	return visual.duplicate()


func _load_legacy_projectile_visual_catalog() -> Dictionary:
	var result := _load_legacy_explosion_visual_catalog()
	for gfl_index: int in [19, 20, 251, 306, 528, 635]:
		var visual := _load_legacy_projectile_visual(gfl_index)
		if not visual.is_empty():
			result[gfl_index] = visual
	return result


func _on_projectile_damage_applied(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	damage: int,
) -> void:
	_on_attack_hit(attacker, target, attack_type, damage)


func _on_projectile_impact_created(
	_attacker: Node2D,
	_world_position: Vector2,
	_attack_type: int,
	_runtime_actor_type: int,
	_original_gfl_index: int,
) -> void:
	# The two apparent impact WAVs are loaded archive records but have no
	# executable request path. Visual impact actors retain their own exact SPR
	# group sounds, so do not invent a second event-level playback here.
	pass


func _on_projectile_explosion_actor_requested(
	_attacker: Node2D,
	world_position: Vector2,
	runtime_actor_type: int,
	special_bursts: Array[Dictionary],
) -> void:
	_spawn_legacy_explosion_effect(
		world_position,
		runtime_actor_type,
		special_bursts,
		legacy_crt_random_state,
		true,
	)


func _spawn_legacy_explosion_effect(
	world_position: Vector2,
	runtime_actor_type: int,
	special_bursts: Array[Dictionary] = [],
	initial_random_state: int = 1,
	update_global_random_state: bool = true,
) -> Node2D:
	_show_world_sound_caption(tr("SOUND_EXPLOSION"), world_position, 1280.0)
	var effect: Node2D = LEGACY_EXPLOSION_EFFECT_SCRIPT.new()
	effect.name = "LegacyExplosionActor%d" % runtime_actor_type
	add_child(effect)
	var next_random_state := int(effect.call(
		"configure",
		world_position,
		runtime_actor_type,
		_load_legacy_projectile_visual_catalog(),
		world_size,
		initial_random_state,
		special_bursts,
	))
	if not bool(effect.get("configured")):
		effect.queue_free()
		return null
	if update_global_random_state:
		var draws: Array = (
			effect.call("take_crt_random_draws")
			if effect.has_method("take_crt_random_draws")
			else []
		)
		if (
			not commit_legacy_crt_random_draws(draws)
			or legacy_crt_random_state != next_random_state
		):
			push_error("actor 62 爆炸效果的全局 CRT rand 批次不连续")
			effect.queue_free()
			return null
	if effect.has_method("bind_original_crt_random_source"):
		effect.call("bind_original_crt_random_source", self)
	if effect.has_method("set_reduce_flashes"):
		effect.call(
			"set_reduce_flashes",
			bool(runtime_settings.get("reduce_flashes", false)),
		)
	legacy_explosion_effects.append(effect)
	effect.connect(
		"original_animation_audio_requested",
		Callable(self, "_on_original_world_animation_audio_requested"),
	)
	effect.tree_exited.connect(
		Callable(self, "_on_legacy_explosion_effect_exited").bind(effect)
	)
	return effect


func _on_original_world_animation_audio_requested(
	source: Node2D,
	gfl_index: int,
	continuous: bool,
	local_requester_id: int,
) -> void:
	if media_director == null or gfl_index <= 0:
		return
	if continuous:
		var source_id := source.get_instance_id() if source != null else 0
		var requester_id := int(hash([source_id, local_requester_id]))
		media_director.request_sfx_audio_index(gfl_index, requester_id)
	else:
		media_director.play_audio_index(
			gfl_index,
			"world_animation",
		)


func _spawn_legacy_explosion_effect_from_snapshot(
	snapshot_value: Dictionary,
) -> Node2D:
	var runtime_actor_type := int(
		snapshot_value.get("runtime_actor_type", 0)
	)
	var effect := _spawn_legacy_explosion_effect(
		Vector2(
			float(snapshot_value.get("x", 0.0)),
			float(snapshot_value.get("y", 0.0)),
		),
		runtime_actor_type,
		[],
		int(snapshot_value.get("random_state", 1)),
		false,
	)
	if (
		effect == null
		or not effect.has_method("restore_runtime_state")
		or not bool(effect.call(
			"restore_runtime_state",
			snapshot_value,
		))
	):
		if effect != null and is_instance_valid(effect):
			effect.queue_free()
		return null
	return effect


func _on_legacy_explosion_effect_exited(effect: Node2D) -> void:
	legacy_explosion_effects.erase(effect)


func _on_explosive_prop_exited(prop: Node2D) -> void:
	explosive_props.erase(prop)


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
	for ambient: AMBIENT_UNIT in ambient_units:
		candidates.append(ambient)
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
			or int(candidate.get("runtime_actor_type"))
				in LEGACY_EXPLOSION_RULES.MAIN_EXCLUDED_RUNTIME_ACTOR_TYPES
		):
			continue
		var offset := candidate.global_position - world_position
		var normalized_distance := (
			offset.x * offset.x / (horizontal_radius * horizontal_radius)
			+ offset.y * offset.y / (vertical_radius * vertical_radius)
		)
		if normalized_distance <= 1.0:
			candidate.call("take_damage", damage, instigator if instigator != null else source)
	_resolve_native_destroyed_targets_from_explosion(
		world_position,
		horizontal_radius,
		vertical_radius,
		damage,
	)
	var special_visual_bursts := _apply_legacy_special_damage_bands(
		source,
		instigator,
		world_position,
		candidates,
	)
	if source != null and source.get_script() == EXPLOSIVE_PROP_SCRIPT:
		_spawn_legacy_explosion_effect(
			world_position,
			int(source.get("explosion_actor_type")),
			special_visual_bursts,
			legacy_crt_random_state,
			true,
		)
	elif (
		source != null
		and source.get_script() == LEGACY_SPECIAL_WORLD_OBJECT_SCRIPT
	):
		_spawn_legacy_explosion_effect(
			world_position,
			int(source.get("explosion_actor_type")),
			special_visual_bursts,
			legacy_crt_random_state,
			true,
		)
	var recovered_alert_radius := _legacy_special_alert_radius(source)
	if (
		recovered_alert_radius > 0.0
		and source != null
		and source.get_script() == EXPLOSIVE_PROP_SCRIPT
	):
		_queue_or_broadcast_alert(
			source,
			source,
			world_position,
			recovered_alert_radius,
			true,
		)
		return
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
		recovered_alert_radius,
	)


static func _legacy_special_alert_radius(source: Node2D) -> float:
	if source == null or not source.has_method("explosion_payload"):
		return 0.0
	var payload: Variant = source.call("explosion_payload")
	if not payload is Dictionary:
		return 0.0
	return maxf(float((payload as Dictionary).get("alert_radius", 0.0)), 0.0)


func _apply_legacy_special_damage_bands(
	source: Node2D,
	instigator: Node2D,
	world_position: Vector2,
	candidates: Array[Node2D],
) -> Array[Dictionary]:
	var bursts: Array[Dictionary] = []
	if source == null or not source.has_method("explosion_payload"):
		return bursts
	var payload: Variant = source.call("explosion_payload")
	if not payload is Dictionary:
		return bursts
	var raw_bands: Variant = (payload as Dictionary).get(
		"special_damage_bands",
		[],
	)
	if not raw_bands is Array:
		return bursts
	for raw_band: Variant in raw_bands as Array:
		if not raw_band is Dictionary:
			continue
		var band := raw_band as Dictionary
		var actor_types: Variant = band.get("runtime_actor_types", [])
		var band_damage := maxi(int(band.get("damage", 0)), 0)
		if not actor_types is Array or band_damage <= 0:
			continue
		for candidate: Node2D in candidates:
			if (
				candidate == source
				or not is_instance_valid(candidate)
				or not candidate.has_method("take_damage")
				or not (actor_types as Array).has(int(candidate.get("runtime_actor_type")))
				or not _legacy_special_band_contains(
					band,
					candidate.global_position - world_position,
				)
			):
				continue
			# sub_4554A0 dispatches the special-band effect after calling the
			# damage helper even when that helper finds +0x1CC already resolved.
			# Preserve the visual burst for an actor killed by the main band.
			candidate.call(
				"take_damage",
				band_damage,
				instigator if instigator != null else source,
			)
			bursts.append({
				"effect_family": int(
					band.get("original_visual_effect_type", 11)
				),
				"world_position": candidate.global_position,
			})
	return bursts


func _add_legacy_special_visual_burst(
	source: Node2D,
	effect_family: int,
	center_world_position: Vector2,
) -> void:
	if (
		source == null
		or not is_instance_valid(source)
		or not source.has_method("add_recovered_visual_burst")
	):
		return
	var next_random_state := int(source.call(
		"add_recovered_visual_burst",
		effect_family,
		center_world_position,
		legacy_crt_random_state,
	))
	var draws: Array = (
		source.call("take_crt_random_draws")
		if source.has_method("take_crt_random_draws")
		else []
	)
	if (
		not commit_legacy_crt_random_draws(draws)
		or legacy_crt_random_state != next_random_state
	):
		push_error("特殊部署对象的全局 CRT rand 批次不连续")


static func _legacy_special_band_contains(band: Dictionary, offset: Vector2) -> bool:
	match String(band.get("geometry", "")):
		"ellipse":
			var horizontal_radius := float(band.get("horizontal_radius", 0.0))
			var vertical_radius := float(band.get("vertical_radius", 0.0))
			if horizontal_radius <= 0.0 or vertical_radius <= 0.0:
				return false
			return (
				offset.x * offset.x / (horizontal_radius * horizontal_radius)
				+ offset.y * offset.y / (vertical_radius * vertical_radius)
			) <= 1.0
		"euclidean_radius":
			var radius := float(band.get("radius", 0.0))
			if radius <= 0.0:
				return false
			var distance_squared := offset.length_squared()
			var radius_squared := radius * radius
			return (
				distance_squared < radius_squared
				if bool(band.get("exclusive_boundary", false))
				else distance_squared <= radius_squared
			)
	return false


func _on_projectile_exploded(
	attacker: Node2D,
	world_position: Vector2,
	_horizontal_radius: float,
	_vertical_radius: float,
	alert_radius_override: float = 0.0,
) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var alert_target: Node2D = attacker
	if attacker is ENEMY_UNIT:
		var enemy_attacker := attacker as ENEMY_UNIT
		if enemy_attacker.current_target != null:
			alert_target = enemy_attacker.current_target
	var alert_radius: float = (
		alert_radius_override
		if alert_radius_override > 0.0
		else COMBAT_PROFILES.alert_radius("attack_extended")
	)
	_queue_or_broadcast_alert(
		attacker,
		alert_target,
		world_position,
		alert_radius,
		true,
	)


func _on_attack_started(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	alert_radius: float,
) -> void:
	command_bus.emit_event(
		"attack_started",
		{
			"player": attacker is SQUAD_UNIT,
			"attacker_scene_index": int(attacker.get("scene_index")),
			"target_scene_index": int(target.get("scene_index")) if target != null else -1,
			"attack_type": attack_type,
		},
		"combat",
	)
	if alert_radius > 0.0:
		_show_world_sound_caption(tr("SOUND_GUNSHOT"), attacker.position, alert_radius)
	if (
		mission_ai_coordinator != null
		and attacker is SQUAD_UNIT
		and target is ENEMY_UNIT
		and str(current_mission.get("id", "")) == "m005"
		and _binding_scenes("m005_agui").has(int(target.get("scene_index")))
	):
		mission_ai_coordinator.observe_mission_event(
			"combat_engaged",
			{
				"target_scene_index": int(target.get("scene_index")),
				"target_role_id": "m005_agui",
			},
		)
	# The executable has no event-level attack-sound dispatcher. Attack audio
	# comes only from the active SPR frame group's exact SLF index; a group with
	# no sound field is intentionally silent.
	if LEGACY_DISGUISE_RULES.attack_can_break_disguise(
		int(attacker.get("runtime_actor_type")),
		attack_type,
	):
		# Type 91 pistol/dagger exposure is deferred to the committed hit frame.
		# sub_45EA70 alerts only observers that actually see the disguised actor;
		# the ordinary 640 coordinate broadcast would expose an unseen attack.
		return
	if alert_radius <= 0.0 or target == null:
		return
	# A gunshot exposes the shooter to the opposing side.  When an enemy fires,
	# nearby enemies keep the player's target; when a squad member fires, nearby
	# enemies must hunt the squad member rather than their wounded ally.
	var alert_target: Node2D = target if attacker is ENEMY_UNIT else attacker
	if alert_target == null or not alert_target.has_method("is_combat_alive"):
		return
	_queue_or_broadcast_alert(
		attacker, alert_target, attacker.position, alert_radius
	)
	# sub_45DA20 is not a generic gunshot response. It is emitted only by the
	# corpse-discovery state, whose exact path lives in EnemyUnit.


func _show_world_sound_caption(
	sound_label: String,
	world_position: Vector2,
	audible_radius: float,
) -> void:
	if game_shell == null or level_camera == null or audible_radius <= 0.0:
		return
	var offset := world_position - level_camera.position
	var distance := offset.length()
	if distance > audible_radius:
		return
	var direction := tr("SOUND_DIRECTION_NEAR")
	if distance >= 64.0:
		var directions: Array[String] = [
			tr("SOUND_DIRECTION_EAST"),
			tr("SOUND_DIRECTION_SOUTHEAST"),
			tr("SOUND_DIRECTION_SOUTH"),
			tr("SOUND_DIRECTION_SOUTHWEST"),
			tr("SOUND_DIRECTION_WEST"),
			tr("SOUND_DIRECTION_NORTHWEST"),
			tr("SOUND_DIRECTION_NORTH"),
			tr("SOUND_DIRECTION_NORTHEAST"),
		]
		var normalized_angle := fposmod(offset.angle() + TAU / 16.0, TAU)
		direction = directions[int(floor(normalized_angle / (TAU / 8.0))) % 8]
	game_shell.show_environment_caption(
		tr("SOUND_CAPTION_FORMAT") % [sound_label, direction, distance / 16.0],
	)


func _queue_or_broadcast_alert(
	source: Node2D,
	target: Node2D,
	world_position: Vector2,
	alert_radius: float,
	_allow_enemy_source_in_original: bool = false,
) -> int:
	if mission_ai_coordinator != null:
		var recipients: Array[int] = mission_ai_coordinator.queue_shared_alert(
			source, target, world_position, alert_radius
		)
		return recipients.size()
	# Runtime capture at 0x45DF71 proves ordinary enemy gunfire also writes
	# coordinate commands: scene 1598's first m000 shot queued the player
	# coordinate for runtime-index 16 / scene 1433 and runtime-index 26 /
	# scene 1492. EnemyUnit defers consumption until each recipient's own update
	# so contact or a later authored route can still win native command
	# arbitration.
	var alert_coordinate := world_position
	if (
		int(source.get("faction_id")) != 3
		and target != null
		and is_instance_valid(target)
	):
		alert_coordinate = target.position
	var alerted_count := 0
	_ensure_original_runtime_actor_order_cache()
	for candidate: Node2D in original_runtime_actor_order_cache:
		if not candidate is ENEMY_UNIT:
			continue
		var enemy := candidate as ENEMY_UNIT
		var has_unlost_live_contact := (
			enemy.current_target != null
			and is_instance_valid(enemy.current_target)
			and enemy.behavior_state in [
				ENEMY_UNIT.BehaviorState.CHASE,
				ENEMY_UNIT.BehaviorState.ATTACK,
			]
		)
		if (
			enemy == source
			or not LEGACY_ENEMY_AI_RULES.alert_recipient_is_eligible(
				enemy.faction_id,
				enemy.runtime_actor_type,
				enemy.is_alive,
				has_unlost_live_contact,
			)
			or not LEGACY_ENEMY_AI_RULES.is_within_alert_ellipse(
				world_position,
				enemy.position,
				alert_radius,
			)
		):
			continue
		if enemy.receive_original_coordinate_alert(alert_coordinate):
			alerted_count += 1
			var reaction_draw: Dictionary = next_legacy_crt_random(
				0x0005DF71,
				enemy.original_runtime_index,
			)
			if (
				not reaction_draw.is_empty()
				and source.has_method(
					"apply_original_alert_source_reaction"
				)
			):
				source.call(
					"apply_original_alert_source_reaction",
					int(reaction_draw.get("value", -1)),
				)
	return alerted_count

func emit_noise_at(world_position: Vector2, radius: float = 640.0) -> int:
	var source: Node2D = selected_units[0] if not selected_units.is_empty() else null
	var alerted := 0
	for enemy: ENEMY_UNIT in enemies:
		if not enemy.is_alive or source == null:
			continue
		var profile: Dictionary = enemy.sense_profile
		var recovered_hearing_radius := float(profile.get("hearing_radius", 0.0))
		if recovered_hearing_radius <= 0.0:
			recovered_hearing_radius = maxf(
				float(profile.get("horizontal_radius", 0.0)),
				float(profile.get("vertical_radius", 0.0)),
			)
		var effective_radius := minf(maxf(radius, 0.0), recovered_hearing_radius)
		if (
			effective_radius > 0.0
			and LEGACY_ENEMY_AI_RULES.is_within_alert_ellipse(
				world_position,
				enemy.position,
				effective_radius,
			)
			and enemy.investigate_position(world_position)
		):
			alerted += 1
	update_status("制造声音：%d 名敌人前往调查" % alerted)
	return alerted

func drop_selected_item_at(world_position: Vector2) -> bool:
	if selected_units.is_empty():
		update_status("请先选择队员")
		return false
	var actor: SQUAD_UNIT = selected_units[0]
	if actor.backpack_inventory == null:
		update_status("当前没有可丢弃物品")
		return false
	var item_id := selected_backpack_item_id
	if item_id <= 0 or actor.backpack_inventory.item_count(item_id) <= 0:
		update_status("请先在物品栏选择要放下的物品")
		return false
	if not restore_original_drop_order(actor, item_id, world_position):
		update_status("没有通往放置位置的可行路线")
		return false
	actor.queue_original_acknowledgement()
	var item_name: String = (
		ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id)
	)
	selected_backpack_item_id = 0
	_refresh_inventory_ui()
	update_status(
		"%s 正在前往放下 %s；抵达前物品仍在背包中"
		% [actor.display_name, item_name]
	)
	return true


func restore_original_drop_order(
	actor: SQUAD_UNIT,
	item_id: int,
	world_position: Vector2,
) -> bool:
	if (
		actor == null
		or not is_instance_valid(actor)
		or not actor.is_alive
		or actor.backpack_inventory == null
		or item_id <= 0
		or actor.backpack_inventory.item_count(item_id) <= 0
	):
		return false
	var path := PackedVector2Array()
	if navigation_grid == null:
		path.append(world_position)
	elif dynamic_occupancy != null and actor.scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			actor.scene_index,
			actor.position,
			world_position,
		)
	else:
		path = navigation_grid.find_path(
			actor.position,
			world_position,
			true,
		)
	if path.is_empty() and not actor.position.is_equal_approx(world_position):
		return false
	_clear_original_pickup_order()
	_clear_original_drop_order()
	_cancel_legacy_deployment_for_unit(actor)
	actor.clear_combat_target()
	original_drop_order_actor = actor
	original_drop_order_item_id = item_id
	original_drop_order_destination = (
		path[-1] if not path.is_empty() else actor.position
	)
	actor.issue_path(path)
	return true


func _advance_original_drop_order() -> void:
	if original_drop_order_actor == null:
		return
	if (
		not is_instance_valid(original_drop_order_actor)
		or not original_drop_order_actor.is_alive
		or original_drop_order_actor.backpack_inventory == null
		or original_drop_order_item_id <= 0
		or original_drop_order_actor.backpack_inventory.item_count(
			original_drop_order_item_id
		) <= 0
	):
		_clear_original_drop_order()
		return
	if (
		original_drop_order_actor.movement_path_index
			< original_drop_order_actor.movement_path.size()
		or original_drop_order_actor.position.distance_to(
			original_drop_order_destination
		) > 1.0
	):
		return
	_complete_original_drop_order()


func _complete_original_drop_order() -> bool:
	var actor := original_drop_order_actor
	var item_id := original_drop_order_item_id
	var destination := original_drop_order_destination
	if (
		actor == null
		or not is_instance_valid(actor)
		or not actor.is_alive
		or actor.backpack_inventory == null
		or item_id <= 0
	):
		_clear_original_drop_order()
		return false
	# sub_4583F0 creates runtime type == item ID with sub_44A350 before removing
	# the item from the actor container. The captured drop consumes the four
	# constructor draws; pickup later consumes the four destructor resets.
	if not _commit_original_dynamic_actor_factory(
		"丢弃物品 actor %d" % item_id
	):
		_clear_original_drop_order()
		return false
	var dropped: Dictionary = actor.backpack_inventory.take_for_drop(item_id, 1)
	if dropped.is_empty():
		_clear_original_drop_order()
		_refresh_inventory_ui()
		return false
	var item_name: String = (
		ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id)
	)
	_spawn_original_inventory_pickup(
		destination,
		{
			"original_inventory_kind": "backpack",
			"original_dynamic_actor_lifecycle": true,
			"original_factory_random_consumed": true,
			"original_destructor_random_consumed": false,
			"item_id": item_id,
			"item_name": item_name,
			"quantity": int(dropped.get("quantity", 1)),
			"quantity_mode": int(dropped.get("quantity_mode", 0)),
			"source_scene_index": int(actor.scene_index),
		},
	)
	_clear_original_drop_order()
	_refresh_inventory_ui()
	update_status(
		"%s 已放下 %s；仅能识别它的敌人会在近距视线内前往查看"
		% [actor.display_name, item_name]
	)
	return true


func _clear_original_drop_order() -> void:
	original_drop_order_actor = null
	original_drop_order_item_id = 0
	original_drop_order_destination = Vector2.ZERO


func _on_enemy_legacy_world_item_interaction_requested(
	enemy: ENEMY_UNIT,
	pickup: Node2D,
) -> void:
	if (
		enemy == null
		or not is_instance_valid(enemy)
		or not enemy.is_alive
		or not pickup is MISSION_PICKUP
		or not is_instance_valid(pickup)
		or not mission_pickups.has(pickup as MISSION_PICKUP)
	):
		if enemy != null and is_instance_valid(enemy):
			enemy.complete_legacy_world_item_interaction(pickup, false)
		return
	var mission_pickup := pickup as MISSION_PICKUP
	var payload: Dictionary = mission_pickup.collect(enemy)
	if payload.is_empty():
		enemy.complete_legacy_world_item_interaction(pickup, false)
		return
	var item_id := int(
		payload.get("item_id", mission_pickup.original_actor_type)
	)
	var quantity := maxi(int(payload.get("quantity", 1)), 1)
	var quantity_mode := int(payload.get("quantity_mode", 0))
	var transferred := 0
	if str(payload.get("original_inventory_kind", "")) == "backpack":
		transferred = enemy.add_backpack_item(
			item_id,
			quantity,
			quantity_mode,
		)
	enemy.complete_legacy_world_item_interaction(pickup, true)
	_unregister_mission_pickup(mission_pickup)
	var effect: Dictionary = enemy.apply_legacy_world_item_effect(item_id)
	if bool(effect.get("consume_after_collection", false)):
		enemy.consume_backpack_item(item_id, true, 1)
	var item_name := str(
		payload.get(
			"item_name",
			ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
		)
	)
	update_status(
		"%s 拾取 %s%s"
		% [
			enemy.display_name,
			item_name,
			"" if transferred > 0 else "（物品栏保持原状）",
		]
	)
	_free_level_runtime_node(mission_pickup)
	_refresh_inventory_ui()


func _on_enemy_legacy_hypnosis_changed(
	enemy: ENEMY_UNIT,
	active: bool,
) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if active and enemy.is_alive:
		select_only(enemy)
		update_status("%s 暂时受降头木偶控制" % enemy.display_name)
		return
	if selected_units.has(enemy):
		selected_units.erase(enemy)
	enemy.set_selected(false)
	_refresh_inventory_ui()


func _register_mission_pickup(pickup: MISSION_PICKUP) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	if pickup.world_item_serial <= 0:
		pickup.world_item_serial = next_mission_pickup_serial
		pickup.item_payload["world_item_serial"] = pickup.world_item_serial
	next_mission_pickup_serial = maxi(
		next_mission_pickup_serial,
		pickup.world_item_serial + 1,
	)
	if not mission_pickups.has(pickup):
		mission_pickups.append(pickup)
	_register_spatial_node(pickup, ["pickup", "mission_pickup", "interactable"])
	_refresh_enemy_world_items()


func _unregister_mission_pickup(pickup: MISSION_PICKUP) -> void:
	if (
		pickup != null
		and is_instance_valid(pickup)
		and pickup.collected
		and pickup.original_dynamic_actor_lifecycle
		and not pickup.original_destructor_random_consumed
	):
		if _commit_original_dynamic_actor_destructor(
			"世界物品 actor %d" % pickup.original_actor_type
		):
			pickup.original_destructor_random_consumed = true
			pickup.item_payload["original_destructor_random_consumed"] = true
	mission_pickups.erase(pickup)
	if world_spatial_index != null and pickup != null:
		world_spatial_index.unregister_node(pickup)
	_refresh_enemy_world_items()


func _refresh_enemy_world_items() -> void:
	for enemy: ENEMY_UNIT in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.set_potential_world_items(mission_pickups)


func _refresh_enemy_corpse_candidates() -> void:
	var corpses: Array[Node2D] = []
	for enemy: ENEMY_UNIT in enemies:
		if (
			enemy != null
			and is_instance_valid(enemy)
			and not enemy.is_alive
			and enemy.faction_id
				== LEGACY_CORPSE_DISCOVERY_RULES.ENEMY_FACTION_ID
			and not enemy.legacy_corpse_discovered
			and not enemy.legacy_corpse_buried
		):
			# The original world scan returns the first eligible corpse in
			# insertion order. Keep that order, but do not hand every guard the
			# full live enemy roster: on a 96-guard map that caused 96 x 96
			# dynamic property checks on each common 0.20-second sense tick.
			corpses.append(enemy)
	for enemy: ENEMY_UNIT in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.set_potential_corpses(corpses)


func _refresh_projectile_world_combatants() -> void:
	if projectile_world == null:
		return
	var combatants: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		if is_instance_valid(unit):
			combatants.append(unit)
	for escort: ESCORT_UNIT in escorts:
		if is_instance_valid(escort):
			combatants.append(escort)
	for enemy: ENEMY_UNIT in enemies:
		if is_instance_valid(enemy):
			combatants.append(enemy)
	for ambient: AMBIENT_UNIT in ambient_units:
		if is_instance_valid(ambient):
			combatants.append(ambient)
	for prop: Node2D in explosive_props:
		if is_instance_valid(prop):
			combatants.append(prop)
	projectile_world.set_combatants(combatants)


func _bind_restored_enemy_world_item_targets() -> void:
	_refresh_enemy_world_items()
	for enemy: ENEMY_UNIT in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.bind_restored_legacy_world_item_target(mission_pickups)


func _bind_restored_enemy_corpse_targets() -> void:
	_refresh_enemy_corpse_candidates()
	for enemy: ENEMY_UNIT in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.bind_restored_legacy_corpse_target(enemies)


func _on_enemy_legacy_corpse_discovered(
	observer: ENEMY_UNIT,
	corpse: ENEMY_UNIT,
) -> void:
	if (
		observer == null
		or corpse == null
		or not is_instance_valid(observer)
		or not is_instance_valid(corpse)
	):
		return
	legacy_global_alarm_active = true
	_show_world_sound_caption(tr("SOUND_ALARM"), observer.position, 960.0)
	command_bus.emit_event(
		"alarm_raised",
		{
			"observer_scene_index": observer.scene_index,
			"corpse_scene_index": corpse.scene_index,
		},
		"perception",
	)
	var marker: Dictionary = _nearest_legacy_reinforcement_marker(observer.position)
	if marker.is_empty():
		update_status("%s 发现尸体并拉响警报" % observer.display_name)
		return
	var template: Dictionary = _first_runtime_actor_template(
		LEGACY_CORPSE_DISCOVERY_RULES.REINFORCEMENT_ACTOR_TYPE
	)
	if template.is_empty():
		update_status("%s 发现尸体；缺少二等兵生成模板" % observer.display_name)
		return
	var leader_scene_index := -1
	var spawned := 0
	for ordinal: int in range(
		LEGACY_CORPSE_DISCOVERY_RULES.REINFORCEMENT_COUNT
	):
		var dynamic_scene_index := next_legacy_reinforcement_scene_index
		next_legacy_reinforcement_scene_index += 1
		var serial := next_legacy_reinforcement_serial
		next_legacy_reinforcement_serial += 1
		var spawn_position := _legacy_reinforcement_spawn_position(
			marker,
			ordinal,
		)
		var reinforcement := _spawn_legacy_reinforcement(
			template,
			spawn_position,
			dynamic_scene_index,
			int(marker.get("scene_index", -1)),
			serial,
			leader_scene_index,
		)
		if reinforcement == null:
			continue
		if leader_scene_index < 0:
			leader_scene_index = reinforcement.scene_index
		reinforcement.receive_legacy_corpse_reinforcement_order(
			corpse,
			-1 if spawned == 0 else leader_scene_index,
		)
		spawned += 1
	_refresh_enemy_corpse_candidates()
	_refresh_enemy_world_items()
	_refresh_projectile_world_combatants()
	update_status(
		"%s 发现尸体：警报已触发，%d 名增援出动"
		% [observer.display_name, spawned]
	)


func prepare_legacy_reinforcements_for_restore(records: Array) -> int:
	var reinforcement_records: Array[Dictionary] = []
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var ai_value: Variant = record.get("ai", {})
		if not ai_value is Dictionary:
			continue
		var corpse_state_value: Variant = (
			(ai_value as Dictionary).get("legacy_corpse", {})
		)
		if (
			corpse_state_value is Dictionary
			and bool(
				(corpse_state_value as Dictionary).get(
					"reinforcement_spawned",
					false,
				)
			)
		):
			reinforcement_records.append(record)
	reinforcement_records.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return (
				int(
					(first.get("ai", {}) as Dictionary)
					. get("legacy_corpse", {})
					. get("reinforcement_serial", 0)
				)
				< int(
					(second.get("ai", {}) as Dictionary)
					. get("legacy_corpse", {})
					. get("reinforcement_serial", 0)
				)
			)
	)
	var template: Dictionary = _first_runtime_actor_template(
		LEGACY_CORPSE_DISCOVERY_RULES.REINFORCEMENT_ACTOR_TYPE
	)
	if template.is_empty():
		return 0
	var spawned := 0
	for record: Dictionary in reinforcement_records:
		var scene_index := int(record.get("scene_index", -1))
		if scene_index < 0 or _enemy_by_scene_index(scene_index) != null:
			continue
		var corpse_state := (
			(record.get("ai", {}) as Dictionary)
			. get("legacy_corpse", {}) as Dictionary
		)
		var serial := maxi(
			int(corpse_state.get("reinforcement_serial", 0)),
			1,
		)
		var reinforcement := _spawn_legacy_reinforcement(
			template,
			Vector2(
				float(record.get("x", 0.0)),
				float(record.get("y", 0.0)),
			),
			scene_index,
			int(
				corpse_state.get(
					"reinforcement_source_marker_scene_index",
					-1,
				)
			),
			serial,
			int(
				corpse_state.get(
					"reinforcement_leader_scene_index",
					-1,
				)
			),
			false,
		)
		if reinforcement == null:
			continue
		next_legacy_reinforcement_scene_index = maxi(
			next_legacy_reinforcement_scene_index,
			scene_index + 1,
		)
		next_legacy_reinforcement_serial = maxi(
			next_legacy_reinforcement_serial,
			serial + 1,
		)
		spawned += 1
	if spawned > 0:
		_refresh_enemy_corpse_candidates()
		_refresh_enemy_world_items()
		_refresh_projectile_world_combatants()
	return spawned


func _spawn_legacy_reinforcement(
	template: Dictionary,
	spawn_position: Vector2,
	dynamic_scene_index: int,
	source_marker_scene_index: int,
	serial: int,
	leader_scene_index: int,
	consume_factory_random: bool = true,
) -> ENEMY_UNIT:
	if dynamic_occupancy == null or template.is_empty():
		return null
	var entity := template.duplicate(true)
	entity["scene_index"] = dynamic_scene_index
	entity["x"] = int(round(spawn_position.x))
	entity["y"] = int(round(spawn_position.y))
	entity["reference_x"] = int(round(spawn_position.x))
	entity["reference_y"] = int(round(spawn_position.y))
	entity["faction_id"] = LEGACY_CORPSE_DISCOVERY_RULES.ENEMY_FACTION_ID
	entity["team_id"] = LEGACY_CORPSE_DISCOVERY_RULES.ENEMY_FACTION_ID
	entity["patrol_enabled"] = false
	entity["patrol_waypoints"] = []
	entity["patrol_current_waypoint_index"] = 0
	# This actor is appended at runtime. Reusing the source template's stable
	# startup index would duplicate an existing actor's process order.
	entity.erase("original_runtime_profile")
	entity.erase("original_runtime_profile_source")
	var texture := load_entity_texture(entity)
	if texture == null:
		return null
	var walk_groups := load_entity_action_groups(entity, "walk")
	var run_groups := load_entity_action_groups(entity, "run")
	var movement_groups := walk_groups if not walk_groups.is_empty() else run_groups
	var idle_groups := load_entity_action_groups(entity, "stand")
	var stand_action_groups := load_entity_action_groups(
		entity,
		"stand_action",
	)
	var weapon_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
		int(entity.get("default_attack_type", 2))
	)
	if weapon_profile.is_empty():
		weapon_profile = COMBAT_PROFILES.weapon_profile("rifle_attack")
	var attack_groups := load_entity_action_groups(
		entity,
		str(weapon_profile.get("action_key", "rifle_attack")),
	)
	var death_groups := load_entity_action_groups(entity, "death")
	var reinforcement: ENEMY_UNIT = ENEMY_UNIT.new()
	add_child(reinforcement)
	reinforcement.configure_enemy(
		entity,
		texture,
		movement_groups,
		idle_groups,
		dynamic_occupancy,
		attack_groups,
		death_groups,
		run_groups,
	)
	reinforcement.configure_tactical_accessibility(
		bool(runtime_settings.get("colorblind_patterns", true)),
		bool(runtime_settings.get("high_contrast", false)),
	)
	reinforcement.configure_world_spatial_index(world_spatial_index)
	if not _bind_original_crt_random_actor(reinforcement, 1):
		reinforcement.queue_free()
		return null
	if consume_factory_random:
		if not reinforcement.initialize_dynamic_original_crt_random():
			reinforcement.queue_free()
			return null
		reinforcement.apply_original_crt_enemy_startup_profile()
	reinforcement.configure_original_ai_idle_animation(stand_action_groups)
	reinforcement.original_mission_number = int(
		current_mission.get("number", current_level_index + 1)
	)
	if not reinforcement.dynamic_registered:
		reinforcement.queue_free()
		return null
	reinforcement.legacy_reinforcement_spawned = true
	reinforcement.legacy_reinforcement_source_marker_scene_index = (
		source_marker_scene_index
	)
	reinforcement.legacy_reinforcement_serial = serial
	reinforcement.legacy_reinforcement_leader_scene_index = leader_scene_index
	_connect_combatant(reinforcement)
	var targets: Array[Node2D] = []
	for unit: SQUAD_UNIT in units:
		targets.append(unit)
	for escort: ESCORT_UNIT in escorts:
		targets.append(escort)
	reinforcement.set_potential_targets(targets)
	enemies.append(reinforcement)
	world_entities_by_scene[dynamic_scene_index] = entity
	return reinforcement


func _nearest_legacy_reinforcement_marker(
	observer_position: Vector2,
) -> Dictionary:
	var result: Dictionary = {}
	var nearest_distance_squared := INF
	for entity_value: Variant in world_entities_by_scene.values():
		if not entity_value is Dictionary:
			continue
		var entity := entity_value as Dictionary
		if (
			_entity_runtime_actor_type(entity)
			!= LEGACY_CORPSE_DISCOVERY_RULES.REINFORCEMENT_MARKER_ACTOR_TYPE
		):
			continue
		var marker_position := Vector2(
			float(entity.get("reference_x", entity.get("x", 0))),
			float(entity.get("reference_y", entity.get("y", 0))),
		)
		var distance_squared := observer_position.distance_squared_to(
			marker_position
		)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			result = entity
	return result


func _first_runtime_actor_template(runtime_actor_type: int) -> Dictionary:
	var scene_indices: Array[int] = []
	for scene_key: Variant in world_entities_by_scene.keys():
		scene_indices.append(int(scene_key))
	scene_indices.sort()
	for scene_index: int in scene_indices:
		var entity_value: Variant = world_entities_by_scene.get(scene_index)
		if (
			entity_value is Dictionary
			and _entity_runtime_actor_type(entity_value as Dictionary)
				== runtime_actor_type
		):
			return entity_value as Dictionary
	return {}


static func _entity_runtime_actor_type(entity: Dictionary) -> int:
	var header_values: Variant = entity.get("database_header_values", [])
	if header_values is Array and (header_values as Array).size() > 2:
		return int((header_values as Array)[2])
	return 0


func _legacy_reinforcement_spawn_position(
	marker: Dictionary,
	ordinal: int,
) -> Vector2:
	var marker_position := Vector2(
		float(marker.get("reference_x", marker.get("x", 0))),
		float(marker.get("reference_y", marker.get("y", 0))),
	)
	if navigation_grid == null:
		return marker_position + Vector2(float(ordinal * 24), 0.0)
	var marker_cell := navigation_grid.world_to_cell(marker_position)
	var offsets: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
		Vector2i(-2, 0),
		Vector2i(2, 0),
		Vector2i(0, -2),
		Vector2i(0, 2),
	]
	var start_index := posmod(ordinal, offsets.size())
	for offset_index: int in range(offsets.size()):
		var offset := offsets[(start_index + offset_index) % offsets.size()]
		var candidate := marker_cell + offset
		if (
			not navigation_grid.is_valid_cell(candidate)
			or navigation_grid.is_movement_blocked(candidate)
		):
			continue
		if (
			dynamic_occupancy != null
			and dynamic_occupancy.runtime_movement_owner(candidate) >= 0
		):
			continue
		return navigation_grid.cell_to_world(candidate)
	return marker_position + Vector2(float(ordinal * 24), 0.0)


func _enemy_by_scene_index(target_scene_index: int) -> ENEMY_UNIT:
	for enemy: ENEMY_UNIT in enemies:
		if (
			enemy != null
			and is_instance_valid(enemy)
			and enemy.scene_index == target_scene_index
		):
			return enemy
	return null


func _on_attack_hit(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	damage: int,
) -> void:
	if units.has(attacker) and target != null:
		update_status("%s 命中 %s，造成 %d 点伤害" % [
			attacker.display_name,
			_combat_target_display_name(target),
			damage,
		])
	command_bus.emit_event(
		"attack_hit",
		{
			"player": attacker is SQUAD_UNIT,
			"attacker_scene_index": int(attacker.get("scene_index")),
			"target_scene_index": int(target.get("scene_index")) if target != null else -1,
			"attack_type": attack_type,
			"damage": damage,
		},
		"combat",
	)


func _on_attack_missed(
	attacker: Node2D,
	target: Node2D,
	attack_type: int,
	reason: String,
) -> void:
	if units.has(attacker):
		update_status(
			tr("STATUS_PLAYER_ATTACK_MISSED") % [
				str(attacker.get("display_name")),
				str(WEAPON_NAMES.get(attack_type, tr("WEAPON_GENERIC"))),
				roundi(COMBAT_FEEDBACK.player_hit_chance(attack_type) * 100.0),
			]
		)
	elif target != null and units.has(target) and game_shell != null:
		game_shell.show_environment_caption(tr("STATUS_ENEMY_ATTACK_MISSED"), 1.4)
	command_bus.emit_event(
		"attack_missed",
		{
			"player": attacker is SQUAD_UNIT,
			"attacker_scene_index": int(attacker.get("scene_index")),
			"target_scene_index": int(target.get("scene_index")) if target != null else -1,
			"attack_type": attack_type,
			"reason": reason,
		},
		"combat",
	)


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
		_refresh_inventory_ui()


func _on_ammo_changed(unit: Node2D, magazine: int, reserve: int) -> void:
	if selected_units.has(unit):
		if (
			unit.combat_inventory != null
			and unit.combat_inventory.original_parity_enabled()
		):
			update_status("%s 当前武器数量：%d" % [unit.display_name, magazine])
		else:
			update_status("%s 弹药：%d / %d" % [unit.display_name, magazine, reserve])
		_refresh_inventory_ui()


func _refresh_inventory_ui() -> void:
	_refresh_original_hud()
	if inventory_label == null:
		return
	var lines: Array[String] = []
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_alive:
			continue
		var attack_type := int(unit.weapon_profile.get("attack_type", 0))
		var weapon_name := str(WEAPON_NAMES.get(attack_type, "徒手"))
		var ammo_text := "无限/近战"
		if (
			unit.combat_inventory != null
			and unit.combat_inventory.original_parity_enabled()
		):
			var active_state: Dictionary = unit.combat_inventory.weapon_state(
				unit.combat_inventory.active_weapon_key()
			)
			ammo_text = (
				"耐久"
				if int(active_state.get("quantity_mode", -1)) == 1
				else str(int(active_state.get("quantity", 0)))
			)
		elif int(unit.weapon_profile.get("magazine_capacity", 0)) > 0:
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
		if unit.backpack_inventory != null:
			var backpack_parts := PackedStringArray()
			for entry: Dictionary in unit.backpack_inventory.ordered_entries():
				var item_id := int(entry.get("item_id", 0))
				var quantity := int(entry.get("quantity", 0))
				if quantity <= 0:
					continue
				backpack_parts.append(
					"%s %d"
					% [
						ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
						quantity,
					]
				)
			lines.append(
				"背包｜%s"
				% (
					"空"
					if backpack_parts.is_empty()
					else "｜".join(backpack_parts)
				)
			)
	var squad_supplies: Array[String] = []
	if int(field_inventory.get("explosives", 0)) > 0:
		squad_supplies.append("炸药 %d" % int(field_inventory["explosives"]))
	if int(field_inventory.get("uniform", 0)) > 0:
		squad_supplies.append("军服 %d" % int(field_inventory["uniform"]))
	if not squad_supplies.is_empty():
		lines.append("小队物资｜" + "｜".join(squad_supplies))
	inventory_label.text = "\n".join(lines)
	if (
		game_shell != null
		and int(game_shell.overlay_mode) == int(GAME_SHELL_SCRIPT.OverlayMode.INVENTORY)
	):
		game_shell.update_inventory(_inventory_grid_model())


func _refresh_original_hud() -> void:
	if game_shell == null:
		return
	var actor_states: Array[Dictionary] = []
	for descriptor: Dictionary in PLAYABLE_SQUAD:
		var actor_name := str(descriptor.get("name", ""))
		var actor: SQUAD_UNIT
		for candidate: SQUAD_UNIT in units:
			if candidate.display_name == actor_name:
				actor = candidate
				break
		if actor == null:
			continue
		var ammo_text := ""
		var weapon_name := ""
		var weapon_ammo_text := ""
		var weapon_icon: Texture2D
		if (
			actor.combat_inventory != null
		):
			var active_action_key := str(
				actor.combat_inventory.active_weapon_key()
			)
			var active_state: Dictionary = actor.combat_inventory.weapon_state(
				active_action_key
			)
			var active_profile := active_state.get("profile", {}) as Dictionary
			weapon_name = str(
				WEAPON_NAMES.get(
					int(active_profile.get("attack_type", 0)),
					active_action_key,
				)
			)
			var quantity_mode := int(active_state.get("quantity_mode", -1))
			if bool(active_state.get("original_parity", false)):
				if quantity_mode == 0 or quantity_mode == 2:
					ammo_text = str(int(active_state.get("quantity", 0)))
					weapon_ammo_text = "× %s" % ammo_text
				elif quantity_mode == 1:
					weapon_ammo_text = "耐久武器"
			else:
				weapon_ammo_text = "%d / %d" % [
					int(active_state.get("magazine", 0)),
					int(active_state.get("reserve", 0)),
				]
			weapon_icon = _inventory_icon_for(active_action_key, 0, "")
		actor_states.append({
			"name": actor_name,
			"alive": actor.is_alive,
			"selected": selected_units.has(actor),
			"ammo_text": ammo_text,
			"weapon_name": weapon_name,
			"weapon_ammo_text": weapon_ammo_text,
			"weapon_icon": weapon_icon,
			"health_ratio": (
				float(actor.current_hit_points)
				/ maxf(float(actor.maximum_hit_points), 1.0)
			),
		})
	game_shell.update_original_hud(actor_states)


func _on_combatant_died(unit: Node2D, killer: Node2D) -> void:
	command_bus.emit_event(
		(
			"enemy_eliminated"
			if unit is ENEMY_UNIT
			else "player_eliminated"
			if unit is SQUAD_UNIT
			else "combatant_eliminated"
		),
		{
			"scene_index": int(unit.get("scene_index")),
			"killer_scene_index": (
				int(killer.get("scene_index")) if killer != null else -1
			),
		},
		"combat",
	)
	_cancel_legacy_deployment_for_unit(unit)
	if unit == original_drop_order_actor:
		_clear_original_drop_order()
	selected_units.erase(unit)
	if unit is SQUAD_UNIT:
		_spawn_original_inventory_drops(unit as SQUAD_UNIT)
		_refresh_inventory_ui()
	# Death sounds follow the same SPR-only route. Old-schema or synthetic
	# actors without an authored group remain silent instead of guessing from
	# faction labels.
	var death_alert_radius: float = COMBAT_PROFILES.alert_radius("ally_death")
	if unit is ENEMY_UNIT:
		# sub_4585F0 sends a 256-radius coordinate pulse for a faction-1 death.
		# This coexists with the later directional corpse-discovery alarm and
		# its type-6 reinforcement pair.
		if killer != null:
			_queue_or_broadcast_alert(
				unit,
				killer,
				unit.position,
				death_alert_radius,
				true,
			)
		_refresh_enemy_corpse_candidates()
		_publish_role_eliminations(unit)
		_spawn_role_drops(unit)
		if _living_enemy_count() == 0:
			_publish_mission_event(
				"area_hostiles_cleared", {"area_role": "m009_station"}
			)
	elif unit is ESCORT_UNIT:
		if _is_required_escort_scene(int(unit.scene_index)):
			_publish_mission_event(
				"required_character_lost",
				{
					"display_name": str(unit.display_name),
					"scene_index": int(unit.scene_index),
				},
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


func _is_required_escort_scene(scene_index: int) -> bool:
	for binding_value: Variant in (
		current_mission.get("required_escort_bindings", []) as Array
	):
		if _binding_scenes(str(binding_value)).has(scene_index):
			return true
	return false


func _spawn_original_inventory_drops(unit: SQUAD_UNIT) -> void:
	if unit.backpack_inventory != null:
		var backpack_entries: Array[Dictionary] = (
			unit.backpack_inventory.ordered_entries()
		)
		unit.backpack_inventory.clear()
		for entry: Dictionary in backpack_entries:
			var item_id := int(entry.get("item_id", 0))
			var quantity := int(entry.get("quantity", 0))
			if item_id <= 0 or quantity <= 0:
				continue
			_spawn_original_inventory_pickup(
				unit.position,
				{
					"original_inventory_kind": "backpack",
					"item_id": item_id,
					"item_name": (
						ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id)
					),
					"quantity": quantity,
					"quantity_mode": int(entry.get("quantity_mode", 0)),
					"source_scene_index": int(unit.scene_index),
				},
			)
	if unit.combat_inventory != null:
		var had_original_weapon_container := bool(
			unit.combat_inventory.full_snapshot().get(
				"original_parity",
				false,
			)
		)
		var weapon_drops: Array[Dictionary] = (
			unit.combat_inventory.take_all_original_drops(
				unit.inventory_weapon_order,
			)
		)
		for drop: Dictionary in weapon_drops:
			var item_id := int(drop.get("item_id", 0))
			var profile := drop.get("profile", {}) as Dictionary
			var attack_type := int(profile.get("attack_type", 0))
			_spawn_original_inventory_pickup(
				unit.position,
				{
					"original_inventory_kind": "weapon",
					"item_id": item_id,
					"item_name": str(
						WEAPON_NAMES.get(attack_type, "武器")
					),
					"attack_type": attack_type,
					"action_key": str(drop.get("action_key", "")),
					"quantity": int(drop.get("quantity", 0)),
					"quantity_mode": int(drop.get("quantity_mode", -1)),
					"source_scene_index": int(unit.scene_index),
				},
			)
		if had_original_weapon_container:
			# sub_456AB0 empties both original actor containers on death.
			# Keep the presentation/order mirrors in the same cleared state so
			# an empty +0x22C snapshot round-trips without resurrecting stale
			# action keys from the freshly loaded level.
			unit.inventory_weapon_order.clear()
			unit.attack_groups_by_action.clear()
			unit.call("_sync_equipped_weapon_after_consumption")


func _spawn_original_inventory_pickup(
	world_position: Vector2,
	payload: Dictionary,
) -> void:
	var pickup: MISSION_PICKUP = MISSION_PICKUP.new()
	add_child(pickup)
	pickup.configure(
		payload,
		world_position,
		_mission_pickup_texture_for_payload(payload),
	)
	_register_mission_pickup(pickup)


func _mission_pickup_texture_for_payload(payload: Dictionary) -> Texture2D:
	var item_id := int(payload.get("item_id", 0))
	var world_gfl_index: int = (
		LEGACY_DYNAMIC_WORLD_ITEM_CATALOG.world_gfl_index(item_id)
	)
	if world_gfl_index > 0:
		var world_texture := _load_gfl_texture(world_gfl_index)
		if world_texture != null:
			return world_texture
	if str(payload.get("original_inventory_kind", "")) == "weapon":
		var weapon_texture := _world_weapon_pickup_texture(item_id)
		if weapon_texture != null:
			return weapon_texture
	if not str(payload.get("original_inventory_kind", "")).is_empty():
		return _inventory_icon_for("", item_id, "")
	return null


static func world_weapon_sprite_stem(item_id: int) -> String:
	return str(WORLD_WEAPON_SPRITES_BY_ITEM_ID.get(item_id, ""))


func _world_weapon_pickup_texture(item_id: int) -> Texture2D:
	var sprite_stem := world_weapon_sprite_stem(item_id)
	if sprite_stem.is_empty() or converted_root.is_empty():
		return null
	var cache_key := "%s|world-weapon:%d" % [converted_root, item_id]
	if inventory_icon_cache.has(cache_key):
		return inventory_icon_cache[cache_key] as Texture2D
	var sprite_path := _contained_converted_path(
		converted_root,
		"sprites/%s.png" % sprite_stem,
	)
	if sprite_path.is_empty():
		return null
	var texture := _load_external_texture(sprite_path)
	if texture != null:
		inventory_icon_cache[cache_key] = texture
	return texture


func _advance_original_m006_document_exchange() -> bool:
	var mission_id := str(current_mission.get("id", ""))
	if not LEGACY_M006_EXCHANGE_RULES.is_mission(mission_id):
		return false
	var changed := false
	var carrier := _enemy_by_scene_index(
		LEGACY_M006_EXCHANGE_RULES.CARRIER_SCENE_INDEX
	)
	var exit_entity_value: Variant = world_entities_by_scene.get(
		LEGACY_M006_EXCHANGE_RULES.EXIT_DETECTOR_SCENE_INDEX
	)
	if (
		carrier != null
		and exit_entity_value is Dictionary
		and carrier.backpack_inventory != null
	):
		var exit_entity := exit_entity_value as Dictionary
		var carrier_has_document: bool = carrier.backpack_inventory.has_item(
			LEGACY_M006_EXCHANGE_RULES.DOCUMENT_ITEM_ID
		)
		var exit_position := Vector2(
			float(exit_entity.get("x", 0.0)),
			float(exit_entity.get("y", 0.0)),
		)
		if LEGACY_M006_EXCHANGE_RULES.can_carrier_place_document(
			mission_id,
			carrier.is_alive,
			carrier.runtime_actor_type,
			carrier_has_document,
			carrier.position,
			_entity_runtime_actor_type(exit_entity),
			exit_position,
		):
			# sub_459840 constructs actor 101 before removing item 101 from
			# both actor inventory containers. Preserve that random-stream order.
			if not _commit_original_dynamic_actor_factory(
				"m006 document actor 101"
			):
				return false
			var document_entry: Dictionary = (
				carrier.backpack_inventory.take_for_drop(
					LEGACY_M006_EXCHANGE_RULES.DOCUMENT_ITEM_ID,
					1,
				)
			)
			if document_entry.is_empty():
				push_error("m006 document item changed during native handoff")
				return false
			_spawn_original_inventory_pickup(
				carrier.position + LEGACY_M006_EXCHANGE_RULES.DROP_OFFSET,
				{
					"original_inventory_kind": "backpack",
					"original_actor_type": (
						LEGACY_M006_EXCHANGE_RULES.DOCUMENT_WORLD_ACTOR_TYPE
					),
					"original_dynamic_actor_lifecycle": true,
					"original_factory_random_consumed": true,
					"original_destructor_random_consumed": false,
					"item_id": LEGACY_M006_EXCHANGE_RULES.DOCUMENT_ITEM_ID,
					"item_name": ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(
						LEGACY_M006_EXCHANGE_RULES.DOCUMENT_ITEM_ID
					),
					"item_role": "m006_name_list",
					"m006_native_exchange_document": true,
					"quantity": int(document_entry.get("quantity", 1)),
					"quantity_mode": int(
						document_entry.get("quantity_mode", 0)
					),
					"source_scene_index": int(carrier.scene_index),
				},
			)
			changed = true

	var recipient := _enemy_by_scene_index(
		LEGACY_M006_EXCHANGE_RULES.RECIPIENT_SCENE_INDEX
	)
	var document_pickup := _first_available_original_world_item(
		LEGACY_M006_EXCHANGE_RULES.DOCUMENT_WORLD_ACTOR_TYPE,
		"m006_native_exchange_document",
	)
	if recipient == null or document_pickup == null:
		return changed
	var recipient_has_document: bool = (
		recipient.backpack_inventory != null
		and recipient.backpack_inventory.has_item(
			LEGACY_M006_EXCHANGE_RULES.DOCUMENT_ITEM_ID
		)
	)
	if LEGACY_M006_EXCHANGE_RULES.can_recipient_pursue_document(
		mission_id,
		recipient.is_alive,
		recipient.runtime_actor_type,
		recipient_has_document,
		recipient.position,
		document_pickup.is_available_original_world_item(),
		document_pickup.original_actor_type,
		document_pickup.position,
	):
		changed = (
			recipient.begin_original_mission_world_item_investigation(
				document_pickup
			)
			or changed
		)
	return changed


func _first_available_original_world_item(
	original_actor_type: int,
	required_payload_flag: String = "",
) -> MISSION_PICKUP:
	for pickup: MISSION_PICKUP in mission_pickups:
		if (
			pickup != null
			and is_instance_valid(pickup)
			and pickup.original_actor_type == original_actor_type
			and pickup.is_available_original_world_item()
			and (
				required_payload_flag.is_empty()
				or bool(pickup.item_payload.get(required_payload_flag, false))
			)
		):
			return pickup
	return null


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
		if not LEGACY_MISSION_RULES.role_elimination_is_eligible(
			str(current_mission.get("id", "")),
			role_id,
			int(unit.get("runtime_actor_type")),
		):
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
		var original_item_id := int(payload.get("original_item_id", 0))
		if original_item_id > 0:
			payload["original_inventory_kind"] = str(
				payload.get("original_inventory_kind", "backpack")
			)
			payload["item_id"] = int(payload.get("item_id", original_item_id))
			payload["item_name"] = str(
				payload.get(
					"item_name",
					ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(
						original_item_id
					),
				)
			)
			payload["quantity"] = maxi(int(payload.get("quantity", 1)), 1)
			payload["quantity_mode"] = int(payload.get("quantity_mode", 0))
			var exact_pickup := _find_original_inventory_pickup(
				source_scene,
				original_item_id,
			)
			if exact_pickup != null:
				var merged := exact_pickup.item_payload.duplicate(true)
				for payload_key: Variant in payload.keys():
					merged[payload_key] = payload[payload_key]
				exact_pickup.item_payload = merged
			# Original-item role drops enrich the exact item removed from the
			# actor container. Never fabricate a duplicate after an earlier
			# mission handoff transferred the item to another actor.
			continue
		var pickup: MISSION_PICKUP = MISSION_PICKUP.new()
		add_child(pickup)
		pickup.configure(payload, unit.position)
		_register_mission_pickup(pickup)


func _find_original_inventory_pickup(
	source_scene_index: int,
	item_id: int,
) -> MISSION_PICKUP:
	for pickup: MISSION_PICKUP in mission_pickups:
		if pickup == null or not is_instance_valid(pickup) or pickup.collected:
			continue
		var payload := pickup.item_payload
		if (
			str(payload.get("original_inventory_kind", "")) == "backpack"
			and int(payload.get("source_scene_index", -1))
				== source_scene_index
			and int(payload.get("item_id", 0)) == item_id
		):
			return pickup
	return null


func _living_enemy_count() -> int:
	var count := 0
	for enemy: ENEMY_UNIT in enemies:
		if enemy.is_alive:
			count += 1
	return count


func _configure_mission_runtime() -> void:
	if mission_runtime != null:
		_free_level_runtime_node(mission_runtime)
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


func _configure_mission_direction() -> void:
	if mission_direction_runtime != null:
		mission_direction_runtime.free()
		mission_direction_runtime = null
	if mission_ai_coordinator != null:
		mission_ai_coordinator.free()
		mission_ai_coordinator = null
	active_modern_difficulty_profile.clear()
	# The classic ruleset has the per-level briefing surface and the recovered
	# ending, but no source-backed evidence for the Remake-authored in-game
	# dialogue, camera, tutorial or cooperation beats. Keep that entire layer
	# behind the explicit modern ruleset; difficulty then tunes the modern layer
	# independently instead of silently changing simulation rules.
	var difficulty_mode := _effective_difficulty_mode()
	if difficulty_mode not in ["original", "easy", "normal", "hard"]:
		difficulty_mode = "original"
	# Several missions have recovered stable-MOD control-flow profiles whose actual
	# objective set conflicts with the later Remake editorial sequences. Keep
	# those sequences available in repaired mode, but never narrate repaired
	# goals while the player selected strict stable-MOD behaviour.
	if (
		difficulty_mode == "original"
		or bool(current_mission.get("disable_editorial_direction", false))
	):
		return
	mission_direction_runtime = MISSION_DIRECTION_RUNTIME_SCRIPT.new()
	mission_direction_runtime.name = "MissionDirectionRuntime"
	add_child(mission_direction_runtime)
	mission_direction_runtime.camera_requested.connect(_on_direction_camera_requested)
	mission_direction_runtime.tutorial_requested.connect(_on_direction_tutorial_requested)
	mission_direction_runtime.ai_directive_requested.connect(_on_direction_ai_directive_requested)
	var mission_id := str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index]))
	var direction_media: Node = media_director
	if DisplayServer.get_name() == "headless" or _is_runtime_probe():
		direction_media = null
	if not mission_direction_runtime.configure_for_mission(
		mission_id,
		direction_media,
		difficulty_mode,
	):
		push_warning("十二关导演数据未启用：%s" % mission_direction_runtime.last_error)
		mission_direction_runtime.free()
		mission_direction_runtime = null
		return
	# The coordinator implements labelled remake-editorial cooperation,
	# reinforcement and attacker caps.  It must not alter the reference
	# original mode; EnemyUnit's recovered autonomous perception/alert path
	# remains active when the coordinator is absent.
	if difficulty_mode == "original":
		return
	mission_ai_coordinator = MISSION_AI_COORDINATOR_SCRIPT.new()
	mission_ai_coordinator.name = "MissionAiCoordinator"
	add_child(mission_ai_coordinator)
	mission_ai_coordinator.reinforcement_requested.connect(_on_direction_reinforcement_requested)
	var enemy_nodes: Array[Node2D] = []
	for enemy: ENEMY_UNIT in enemies:
		enemy_nodes.append(enemy)
	active_modern_difficulty_profile = MODERN_DIFFICULTY_POLICY.compose(
		mission_direction_runtime.difficulty_profile(),
		str(runtime_settings.get("difficulty_mode", "normal")),
		runtime_settings.get("custom_difficulty", {}) as Dictionary,
	)
	if not mission_ai_coordinator.configure(
		active_modern_difficulty_profile,
		mission_direction_runtime.ai_cooperation_profile(),
		enemy_nodes,
	):
		push_warning("关卡 AI 调校未启用：%s" % mission_ai_coordinator.last_error)


	if not mission_ai_coordinator.last_error.is_empty():
		active_modern_difficulty_profile.clear()
		return
	if not restoring_save:
		_apply_modern_player_resource_policy(
			float(active_modern_difficulty_profile.get(
				"player_resource_multiplier",
				1.0,
			))
		)


func _apply_modern_player_resource_policy(multiplier: float) -> void:
	if is_equal_approx(multiplier, 1.0):
		return
	for unit: SQUAD_UNIT in units:
		if unit.combat_inventory == null:
			continue
		var adjusted_item_ids: Dictionary = {}
		for action_key: String in unit.combat_inventory.registered_weapon_keys():
			var state: Dictionary = unit.combat_inventory.weapon_state(action_key)
			if int(state.get("ammo_per_attack", 0)) <= 0:
				continue
			var item_id := int(state.get("ammo_item_id", 0))
			if item_id <= 0 or adjusted_item_ids.has(item_id):
				continue
			adjusted_item_ids[item_id] = true
			var current := unit.ammo_item_count(item_id)
			var desired := maxi(1, roundi(float(current) * multiplier))
			if desired > current:
				unit.add_ammo_item(item_id, desired - current)
			elif desired < current:
				unit.remove_ammo_item(item_id, current - desired)


func _start_mission_direction() -> void:
	if mission_direction_runtime != null:
		mission_direction_runtime.start()


func _start_initial_direction_sequence() -> void:
	if DisplayServer.get_name() != "headless" and not _is_runtime_probe():
		var cue := _mission_media_cue("on_start")
		if str(cue.get("kind", "")) == "dialogue":
			pending_direction_start_sequence_id = str(cue.get("sequence_id", ""))
			if not pending_direction_start_sequence_id.is_empty() and _play_mission_media_cue("on_start"):
				return
			pending_direction_start_sequence_id = ""
		elif not cue.is_empty():
			_play_mission_media_cue("on_start")
	_start_mission_direction()


func _on_direction_tutorial_requested(_tutorial_id: String, tutorial: Dictionary) -> void:
	var text := str(tutorial.get("text", ""))
	if not text.is_empty():
		update_status("教程：%s" % text)


func _on_direction_ai_directive_requested(_beat_id: String, directive: Dictionary) -> void:
	if mission_ai_coordinator == null or not mission_ai_coordinator.apply_directive(directive):
		return
	var kind := str(directive.get("kind", ""))
	if kind == "set_posture":
		for enemy: ENEMY_UNIT in enemies:
			if enemy.is_alive:
				enemy.path_request_delay_remaining = 0.0
		return
	if kind not in ["coordinate_search", "coordinate_defense"]:
		return
	var target: Node2D
	for unit: SQUAD_UNIT in selected_units:
		if unit.is_alive:
			target = unit
			break
	if target == null:
		for unit: SQUAD_UNIT in units:
			if unit.is_alive:
				target = unit
				break
	if target == null:
		return
	for responder: Node2D in mission_ai_coordinator.select_attackers(target):
		if responder.has_method("receive_alert"):
			responder.call("receive_alert", target, target.position)


func _on_direction_reinforcement_requested(count: int, reason: String) -> void:
	if mission_ai_coordinator == null or units.is_empty():
		return
	var target: Node2D = selected_units[0] if not selected_units.is_empty() else units[0]
	var responders: Array[Node2D] = mission_ai_coordinator.select_attackers(target)
	var activated := 0
	for responder: Node2D in responders:
		if activated >= count:
			break
		if responder.has_method("receive_alert") and bool(
			responder.call("receive_alert", target, target.position)
		):
			activated += 1
	if activated > 0:
		update_status("敌军增援响应：%d 人（%s）" % [activated, reason])


func _on_direction_camera_requested(_beat_id: String, camera: Dictionary) -> void:
	if level_camera == null:
		return
	var mode := str(camera.get("mode", ""))
	var target_position := level_camera.position
	if mode == "follow_party":
		var party_positions: Array[Vector2] = []
		for unit: SQUAD_UNIT in units:
			if unit.is_alive:
				party_positions.append(unit.position)
		if not party_positions.is_empty():
			target_position = _average_positions(party_positions)
	elif mode == "focus_binding":
		var binding := str(camera.get("binding", ""))
		var positions := _direction_binding_positions(binding, str(camera.get("selection", "")))
		if positions.is_empty():
			return
		target_position = _average_positions(positions)
	else:
		return
	var duration := maxf(float(camera.get("duration_seconds", 1.0)), 0.05)
	var target_zoom := clampf(
		float(camera.get("zoom", level_camera.zoom.x)), LEVEL_VIEW.MIN_ZOOM, LEVEL_VIEW.MAX_ZOOM
	)
	var viewport_size := _gameplay_viewport_size() if is_inside_tree() else Vector2.ONE
	target_position = LEVEL_VIEW.clamp_camera_center(
		target_position, viewport_size, target_zoom, world_size
	)
	_cancel_direction_camera_tween()
	if bool(runtime_settings.get("reduce_camera_motion", false)):
		level_camera.position = target_position
		level_camera.zoom = Vector2.ONE * target_zoom
		if is_inside_tree():
			clamp_level_camera()
		return
	direction_camera_tween = create_tween()
	direction_camera_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	direction_camera_tween.set_trans(Tween.TRANS_SINE)
	direction_camera_tween.set_ease(Tween.EASE_IN_OUT)
	direction_camera_tween.parallel().tween_property(level_camera, "position", target_position, duration)
	direction_camera_tween.parallel().tween_property(level_camera, "zoom", Vector2.ONE * target_zoom, duration)
	direction_camera_tween.finished.connect(_on_direction_camera_tween_finished.bind(direction_camera_tween))


func _cancel_direction_camera_tween() -> void:
	if direction_camera_tween != null and direction_camera_tween.is_valid():
		direction_camera_tween.kill()
	direction_camera_tween = null


func _on_direction_camera_tween_finished(completed_tween: Tween) -> void:
	if completed_tween != direction_camera_tween:
		return
	direction_camera_tween = null
	clamp_level_camera()


func _direction_binding_positions(binding: String, selection: String) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var scene_indices: Array[int] = _binding_scenes(binding)
	if selection == "next_incomplete":
		for scene_index: int in scene_indices:
			if activated_mission_scenes.has(scene_index):
				continue
			var next_position: Variant = _direction_scene_position(scene_index)
			if next_position != null:
				positions.append(next_position as Vector2)
				return positions
	for scene_index: int in scene_indices:
		var scene_position: Variant = _direction_scene_position(scene_index)
		if scene_position != null:
			positions.append(scene_position as Vector2)
	if selection == "first" and positions.size() > 1:
		return [positions[0]]
	if selection == "last" and positions.size() > 1:
		return [positions[-1]]
	return positions


func _direction_scene_position(scene_index: int) -> Variant:
	var live_actor := _direction_live_actor_for_scene(scene_index)
	if live_actor != null:
		return live_actor.position
	if not world_entities_by_scene.has(scene_index):
		return null
	var entity := world_entities_by_scene[scene_index] as Dictionary
	return Vector2(float(entity["x"]), float(entity["y"]))


func _direction_live_actor_for_scene(scene_index: int) -> Node2D:
	for unit: SQUAD_UNIT in units:
		if is_instance_valid(unit) and unit.scene_index == scene_index:
			return unit
	for enemy: ENEMY_UNIT in enemies:
		if is_instance_valid(enemy) and enemy.scene_index == scene_index:
			return enemy
	for escort: ESCORT_UNIT in escorts:
		if is_instance_valid(escort) and escort.scene_index == scene_index:
			return escort
	for ambient: AMBIENT_UNIT in ambient_units:
		if is_instance_valid(ambient) and ambient.scene_index == scene_index:
			return ambient
	return null


static func _average_positions(positions: Array[Vector2]) -> Vector2:
	var total := Vector2.ZERO
	for position_value: Vector2 in positions:
		total += position_value
	return total / maxf(float(positions.size()), 1.0)


func _create_media_director() -> void:
	media_director = MEDIA_DIRECTOR_SCRIPT.new()
	media_director.name = "MediaDirector"
	add_child(media_director)
	media_director.set_input_bindings(runtime_settings.get("controls", {}) as Dictionary)
	media_director.briefing_closed.connect(_on_briefing_closed)
	media_director.dialogue_finished.connect(_on_media_dialogue_finished)
	media_director.movie_finished.connect(_on_media_movie_finished)
	media_director.ending_closed.connect(_on_media_ending_closed)


func _create_developer_debug_tools(arguments: PackedStringArray) -> void:
	developer_world_debug_overlay = DEVELOPER_WORLD_DEBUG_OVERLAY_SCRIPT.new()
	developer_world_debug_overlay.name = "DeveloperWorldDebugOverlay"
	developer_world_debug_overlay.z_index = 900
	add_child(developer_world_debug_overlay)
	developer_world_debug_overlay.configure(self)
	developer_debug_overlay = DEVELOPER_DEBUG_OVERLAY_SCRIPT.new()
	developer_debug_overlay.name = "DeveloperDebugOverlay"
	add_child(developer_debug_overlay)
	developer_debug_overlay.configure(self, "--debug-overlay" in arguments)


func set_developer_debug_enabled(value: bool) -> void:
	if (
		developer_debug_enemy != null
		and is_instance_valid(developer_debug_enemy)
		and developer_debug_enemy != sight_observation_target
	):
		developer_debug_enemy.set_tactical_ranges_visible(false)
	developer_debug_enemy = _debug_enemy_subject() if value else null
	if developer_debug_enemy != null and is_instance_valid(developer_debug_enemy):
		developer_debug_enemy.set_tactical_ranges_visible(true)
	if developer_world_debug_overlay != null:
		developer_world_debug_overlay.set_debug_enabled(value)


func modern_debug_snapshot() -> Dictionary:
	var enemy := _debug_enemy_subject()
	var ai: Dictionary = {}
	if enemy != null and enemy.has_method("modern_ai_debug_snapshot"):
		ai = enemy.modern_ai_debug_snapshot()
	var selected_path_points := 0
	for unit: SQUAD_UNIT in selected_units:
		if unit != null and is_instance_valid(unit):
			selected_path_points += maxi(
				unit.movement_path.size() - unit.movement_path_index,
				0,
			)
	return {
		"level_id": str(current_mission.get("id", "")),
		"ruleset": str(runtime_settings.get("ruleset_mode", "classic")),
		"difficulty": str(runtime_settings.get("difficulty_mode", "normal")),
		"performance": performance_monitor.snapshot(),
		"services": runtime_services.stats(),
		"selected_units": selected_units.size(),
		"selected_path_points": selected_path_points,
		"movement_health": _movement_health_summary(),
		"ai": ai,
	}


func _movement_health_summary() -> Dictionary:
	var actor_values: Array = []
	actor_values.append_array(units)
	actor_values.append_array(enemies)
	actor_values.append_array(escorts)
	actor_values.append_array(ambient_units)
	var active_paths := 0
	var stalled_actors := 0
	var recovery_count := 0
	var recovery_failures := 0
	var worst_no_progress := 0.0
	var worst_scene_index := -1
	for actor_value: Variant in actor_values:
		if not actor_value is Node or not is_instance_valid(actor_value):
			continue
		var actor := actor_value as Node
		if not actor.has_method("movement_health_snapshot"):
			continue
		var health := actor.call("movement_health_snapshot") as Dictionary
		if bool(health.get("path_active", false)):
			active_paths += 1
		var no_progress := float(health.get("no_progress_seconds", 0.0))
		if no_progress >= 0.70:
			stalled_actors += 1
		if no_progress > worst_no_progress:
			worst_no_progress = no_progress
			worst_scene_index = int(health.get("scene_index", -1))
		recovery_count += int(health.get("recovery_count", 0))
		recovery_failures += int(health.get("recovery_failure_count", 0))
	return {
		"active_paths": active_paths,
		"stalled_actors": stalled_actors,
		"recovery_count": recovery_count,
		"recovery_failures": recovery_failures,
		"worst_no_progress_seconds": worst_no_progress,
		"worst_scene_index": worst_scene_index,
	}


func debug_world_subjects() -> Dictionary:
	var live_selected: Array[Node2D] = []
	for unit: SQUAD_UNIT in selected_units:
		if unit != null and is_instance_valid(unit) and unit.is_alive:
			live_selected.append(unit)
	return {
		"selected_units": live_selected,
		"enemy": _debug_enemy_subject(),
	}


func _debug_enemy_subject() -> ENEMY_UNIT:
	if (
		sight_observation_target != null
		and is_instance_valid(sight_observation_target)
		and sight_observation_target.is_alive
	):
		return sight_observation_target
	var camera_position := level_camera.position if level_camera != null else Vector2.ZERO
	var nearest: ENEMY_UNIT
	var nearest_distance := INF
	for enemy: ENEMY_UNIT in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive:
			continue
		var distance := enemy.position.distance_squared_to(camera_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _create_game_shell() -> void:
	game_shell = GAME_SHELL_SCRIPT.new()
	game_shell.name = "GameShell"
	add_child(game_shell)
	game_shell.resume_requested.connect(_on_shell_resumed)
	game_shell.save_requested.connect(_save_game)
	game_shell.load_requested.connect(_load_game)
	game_shell.save_slot_requested.connect(_save_game)
	game_shell.load_slot_requested.connect(_load_game)
	game_shell.restart_requested.connect(_restart_current_level)
	game_shell.next_level_requested.connect(_advance_to_next_level)
	game_shell.level_requested.connect(_on_level_requested)
	game_shell.level_selection_cancelled.connect(_on_level_selection_cancelled)
	game_shell.quit_requested.connect(_quit_game)
	game_shell.settings_changed.connect(_on_shell_settings_changed)
	game_shell.map_position_requested.connect(_on_map_position_requested)
	game_shell.inventory_cycle_requested.connect(_on_inventory_cycle_requested)
	game_shell.inventory_reload_requested.connect(_on_inventory_reload_requested)
	game_shell.inventory_slot_requested.connect(_on_inventory_slot_requested)
	game_shell.original_hud_action_requested.connect(
		_on_original_hud_action_requested
	)
	game_shell.original_hud_actor_requested.connect(
		_on_original_hud_actor_requested
	)
	game_shell.diagnostics_requested.connect(_export_runtime_diagnostics)
	game_shell.set_settings(runtime_settings)
	_apply_runtime_settings(runtime_settings)
	_sync_level_selection()
	_sync_history_archive()


func _initialize_persistence() -> void:
	game_settings = GAME_SETTINGS_SCRIPT.new()
	game_settings.load_from_disk()
	localization_service.install(game_settings.locale())
	game_settings.apply_audio_to_runtime()
	command_line_controls_display = _command_line_has_display_override()
	if not command_line_controls_display:
		game_settings.apply_display_to_runtime()
	var display: Dictionary = game_settings.display_settings()
	runtime_settings = {
		"fullscreen": str(display.get("mode", "fullscreen")) != "windowed",
		"display_mode": str(display.get("mode", "fullscreen")),
		"resolution_policy": str(display.get("resolution_policy", "desktop")),
		"window_width": int(display.get("window_width", 1280)),
		"window_height": int(display.get("window_height", 720)),
		"vsync": bool(display.get("vsync", true)),
		"max_fps": int(display.get("max_fps", 60)),
		"monitor_index": int(display.get("monitor_index", -1)),
		"muted": bool(game_settings.is_muted()),
		"subtitles": bool(game_settings.interface_enabled("subtitles")),
		"environment_captions": bool(
			game_settings.interface_enabled("environment_captions")
		),
		"show_briefings": bool(game_settings.interface_enabled("show_briefings")),
		"edge_scroll": bool(game_settings.interface_enabled("edge_scroll")),
		"reduce_camera_motion": bool(
			game_settings.interface_enabled("reduce_camera_motion")
		),
		"reduce_flashes": bool(game_settings.interface_enabled("reduce_flashes")),
		"large_cursor": bool(game_settings.interface_enabled("large_cursor")),
		"high_contrast": bool(game_settings.interface_enabled("high_contrast")),
		"colorblind_patterns": bool(
			game_settings.interface_enabled("colorblind_patterns")
		),
		"pause_on_focus_loss": bool(
			game_settings.interface_enabled("pause_on_focus_loss")
		),
		"educational_mode": bool(
			game_settings.interface_enabled("educational_mode")
		),
		"reduced_violence": bool(
			game_settings.interface_enabled("reduced_violence")
		),
		"history_notes": bool(
			game_settings.interface_enabled("history_notes")
		),
		"locale": str(game_settings.locale()),
		"ui_scale": float(game_settings.interface_scale("ui_scale")),
		"text_scale": float(game_settings.interface_scale("text_scale")),
		"edge_scroll_speed": float(
			game_settings.camera_setting("edge_scroll_speed", CAMERA_PAN_SPEED)
		),
		"edge_scroll_margin": float(
			game_settings.camera_setting("edge_scroll_margin", EDGE_SCROLL_MARGIN)
		),
		"zoom_step": float(game_settings.camera_setting("zoom_step", 0.25)),
		"ruleset_mode": str(game_settings.ruleset_mode()),
		"difficulty_mode": str(game_settings.difficulty_mode()),
		"control_scheme": str(game_settings.control_scheme()),
		"custom_difficulty": game_settings.custom_difficulty(),
		"mission_rule_mode": str(game_settings.mission_rule_mode()),
		"master_volume": float(game_settings.audio_volume("master")),
		"music_volume": float(game_settings.audio_volume("music")),
		"sfx_volume": float(game_settings.audio_volume("sfx")),
		"voice_volume": float(game_settings.audio_volume("voice")),
		"controls": game_settings.controls_snapshot(),
	}
	save_store = GAME_SAVE_STORE_SCRIPT.new()
	var initial_slot_summaries: Array[Dictionary] = save_store.list_slots()
	checkpoint_manager.restore_from_summaries(initial_slot_summaries)
	campaign_progress = GAME_SAVE_STORE_SCRIPT.default_campaign()
	var latest_slot := _latest_slot_from_summaries(initial_slot_summaries)
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
		# Godot consumes native display switches before GDScript can inspect
		# OS.get_cmdline_args(). Windowed render probes are identifiable by their
		# script path, so persisted fullscreen settings must not override the
		# window mode and resolution already selected by the engine.
		if (
			argument.contains("runtime_probe.gd")
			or argument.contains("campaign_performance_probe.gd")
			or argument.contains("product_ui_probe.gd")
		):
			return true
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--command-line-controls-display":
			return true
	return false


func _on_shell_resumed() -> void:
	update_status("继续任务")


func _restart_current_level() -> void:
	switch_level(current_level_index)
	update_status("本关已重新开始")


func _advance_to_next_level() -> void:
	if (
		current_mission_state == null
		or not current_mission_state.is_victory()
		or current_level_index >= FORMAL_LEVEL_IDS.size() - 1
	):
		update_status("当前没有可进入的下一关")
		return
	switch_level(current_level_index + 1)
	update_status("已进入下一关")


func _open_level_selector(startup: bool = false) -> void:
	if game_shell == null:
		return
	_reset_context_cursor()
	if media_director != null:
		media_director.close_for_state_change()
	game_shell.hide_tactical_map()
	_sync_level_selection()
	game_shell.show_level_selector(startup)


func _on_level_requested(level_id: String) -> void:
	var level_index := FORMAL_LEVEL_IDS.find(level_id)
	if level_index < 0:
		update_status("自由选关失败：无效关卡 %s" % level_id)
		return
	startup_level_selection_pending = false
	startup_media_queue.call("clear")
	switch_level(level_index)
	update_status("自由选关：第 %d 关 %s" % [
		level_index + 1,
		str(current_mission.get("title", level_id.to_upper())),
	])


func _on_level_selection_cancelled() -> void:
	if not startup_level_selection_pending:
		return
	startup_level_selection_pending = false
	startup_media_queue.call("clear")
	switch_level(current_level_index)


func _sync_level_selection() -> void:
	if game_shell == null:
		return
	var entries: Array[Dictionary] = []
	for level_index: int in range(FORMAL_LEVEL_IDS.size()):
		var level_id := FORMAL_LEVEL_IDS[level_index]
		var mission: Dictionary = MISSION_DATA.load_mission_for_rule_mode(
			level_id,
			str(runtime_settings.get("mission_rule_mode", "stable_mod")),
		)
		entries.append(
			{
				"id": level_id,
				"number": level_index + 1,
				"title": str(mission.get("title", level_id.to_upper())),
			}
		)
	game_shell.set_level_selection(
		entries,
		CAMPAIGN_PROGRESS_SCRIPT.normalize(campaign_progress),
		FORMAL_LEVEL_IDS[current_level_index],
	)


func _sync_history_archive() -> void:
	if game_shell == null or history_archive == null:
		return
	var entries: Array[Dictionary] = history_archive.ordered_entries(
		FORMAL_LEVEL_IDS
	)
	var formatted: Dictionary = {}
	for level_id: String in FORMAL_LEVEL_IDS:
		formatted[level_id] = history_archive.formatted_entry(level_id)
	game_shell.set_history_archive(entries, formatted)


func _export_runtime_diagnostics() -> void:
	if runtime_services == null or runtime_diagnostics == null:
		update_status(tr("STATUS_DIAGNOSTICS_UNAVAILABLE"))
		return
	var document: Dictionary = runtime_services.build_diagnostics(runtime_settings)
	document["reproducible_seed"] = legacy_crt_random_state
	document["mission_statistics"] = mission_statistics.snapshot()
	document["movement_health"] = _movement_health_summary()
	var result: Dictionary = runtime_diagnostics.export_bundle(document)
	var message := (
		tr("STATUS_DIAGNOSTICS_EXPORTED") % ProjectSettings.globalize_path(
			str(result.get("path", ""))
		)
		if bool(result.get("ok", false))
		else tr("STATUS_DIAGNOSTICS_FAILED") % str(
			result.get("message", tr("ERROR_UNKNOWN"))
		)
	)
	update_status(message)
	if game_shell != null:
		game_shell.set_menu_message(message)


func _quit_game() -> void:
	get_tree().quit()


func _on_shell_settings_changed(new_settings: Dictionary) -> void:
	var previous_ruleset := str(runtime_settings.get("ruleset_mode", "classic"))
	var previous_difficulty := str(runtime_settings.get("difficulty_mode", "normal"))
	var previous_mission_rule := str(
		runtime_settings.get("mission_rule_mode", "stable_mod")
	)
	var merged_settings := runtime_settings.duplicate(true)
	merged_settings.merge(new_settings, true)
	var fullscreen := bool(merged_settings.get("fullscreen", true))
	var display_mode := str(merged_settings.get("display_mode", "fullscreen"))
	if not fullscreen:
		display_mode = "windowed"
	elif display_mode not in ["fullscreen", "borderless"]:
		display_mode = "fullscreen"
	merged_settings["display_mode"] = display_mode
	merged_settings["fullscreen"] = display_mode != "windowed"
	runtime_settings = merged_settings
	command_line_controls_display = false
	var settings_save_result: Dictionary = {"ok": true}
	if game_settings != null:
		game_settings.set_muted(bool(runtime_settings.get("muted", false)))
		game_settings.set_audio_volume(
			"master", float(runtime_settings.get("master_volume", 0.8))
		)
		for channel: String in ["music", "sfx", "voice"]:
			game_settings.set_audio_volume(
				channel, float(runtime_settings.get("%s_volume" % channel, 1.0))
			)
		game_settings.set_controls(runtime_settings.get("controls", {}) as Dictionary)
		game_settings.set_display_mode(str(runtime_settings["display_mode"]))
		game_settings.set_resolution_policy(
			str(runtime_settings.get("resolution_policy", "desktop"))
		)
		game_settings.set_window_size(Vector2i(
			int(runtime_settings.get("window_width", 1280)),
			int(runtime_settings.get("window_height", 720)),
		))
		game_settings.set_vsync(bool(runtime_settings.get("vsync", true)))
		game_settings.set_max_fps(int(runtime_settings.get("max_fps", 60)))
		game_settings.set_monitor_index(int(runtime_settings.get("monitor_index", -1)))
		game_settings.set_interface_enabled(
			"subtitles", bool(runtime_settings.get("subtitles", true))
		)
		game_settings.set_interface_enabled(
			"environment_captions",
			bool(runtime_settings.get("environment_captions", true)),
		)
		game_settings.set_interface_enabled(
			"show_briefings", bool(runtime_settings.get("show_briefings", true))
		)
		game_settings.set_interface_enabled(
			"edge_scroll", bool(runtime_settings.get("edge_scroll", true))
		)
		game_settings.set_interface_enabled(
			"reduce_camera_motion",
			bool(runtime_settings.get("reduce_camera_motion", false)),
		)
		game_settings.set_interface_enabled(
			"reduce_flashes", bool(runtime_settings.get("reduce_flashes", false))
		)
		game_settings.set_interface_enabled(
			"large_cursor", bool(runtime_settings.get("large_cursor", false))
		)
		game_settings.set_interface_enabled(
			"high_contrast", bool(runtime_settings.get("high_contrast", false))
		)
		game_settings.set_interface_enabled(
			"colorblind_patterns",
			bool(runtime_settings.get("colorblind_patterns", true)),
		)
		game_settings.set_interface_enabled(
			"pause_on_focus_loss",
			bool(runtime_settings.get("pause_on_focus_loss", true)),
		)
		game_settings.set_interface_enabled(
			"educational_mode",
			bool(runtime_settings.get("educational_mode", true)),
		)
		game_settings.set_interface_enabled(
			"reduced_violence",
			bool(runtime_settings.get("reduced_violence", false)),
		)
		game_settings.set_interface_enabled(
			"history_notes",
			bool(runtime_settings.get("history_notes", true)),
		)
		game_settings.set_locale(str(runtime_settings.get("locale", "system")))
		game_settings.set_interface_scale(
			"ui_scale", float(runtime_settings.get("ui_scale", 1.0))
		)
		game_settings.set_interface_scale(
			"text_scale", float(runtime_settings.get("text_scale", 1.0))
		)
		for camera_key: String in [
			"edge_scroll_speed", "edge_scroll_margin", "zoom_step",
		]:
			game_settings.set_camera_setting(
				camera_key, float(runtime_settings.get(camera_key, 0.0))
			)
		game_settings.set_ruleset_mode(
			str(runtime_settings.get("ruleset_mode", "classic"))
		)
		game_settings.set_difficulty_mode(
			str(runtime_settings.get("difficulty_mode", "normal"))
		)
		game_settings.set_control_scheme(
			str(runtime_settings.get("control_scheme", "classic"))
		)
		game_settings.set_custom_difficulty(
			runtime_settings.get("custom_difficulty", {}) as Dictionary
		)
		game_settings.set_mission_rule_mode(
			str(runtime_settings.get("mission_rule_mode", "stable_mod"))
		)
		settings_save_result = game_settings.save_to_disk()
	_apply_runtime_settings(runtime_settings)
	if bool(settings_save_result.get("ok", false)):
		if (
			str(runtime_settings.get("ruleset_mode", "classic")) != previous_ruleset
			or str(runtime_settings.get("difficulty_mode", "normal")) != previous_difficulty
			or str(runtime_settings.get("mission_rule_mode", "stable_mod"))
				!= previous_mission_rule
		):
			update_status("玩法规则已保存，将在重新开始、下一关或读取存档时生效")
		else:
			update_status("设置已应用并保存")
	else:
		var failure_message := "设置已应用，但保存失败：%s" % str(
			settings_save_result.get("message", "未知错误")
		)
		update_status(failure_message)
		if game_shell != null and game_shell.is_overlay_open():
			game_shell.set_menu_message(failure_message)


func _apply_runtime_settings(new_settings: Dictionary) -> void:
	runtime_settings_applier.apply_global(
		new_settings,
		DisplayServer.get_name() == "headless" or command_line_controls_display,
	)
	localization_service.install(str(new_settings.get("locale", "system")))
	if media_director != null and media_director.has_method("set_subtitles_enabled"):
		media_director.set_subtitles_enabled(bool(new_settings.get("subtitles", true)))
	if media_director != null and media_director.has_method("set_input_bindings"):
		media_director.set_input_bindings(new_settings.get("controls", {}) as Dictionary)
	if legacy_cursor_presenter != null and legacy_cursor_presenter.has_method(
		"set_large_cursor"
	):
		legacy_cursor_presenter.set_large_cursor(
			bool(new_settings.get("large_cursor", false))
		)
	if game_shell != null and game_shell.has_method("apply_visual_preferences"):
		game_shell.call("apply_visual_preferences", new_settings)
	if game_shell != null and game_shell.has_method("apply_localization"):
		game_shell.call("apply_localization")
	for combatant: Node2D in _all_active_runtime_actors():
		if combatant.has_method("set_reduced_violence"):
			combatant.call(
				"set_reduced_violence",
				bool(new_settings.get("reduced_violence", false)),
			)
	if (
		legacy_ambient_particle_field != null
		and is_instance_valid(legacy_ambient_particle_field)
		and legacy_ambient_particle_field.has_method("set_reduce_flashes")
	):
		legacy_ambient_particle_field.call(
			"set_reduce_flashes",
			bool(new_settings.get("reduce_flashes", false)),
		)
	for enemy: ENEMY_UNIT in enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.configure_tactical_accessibility(
				bool(new_settings.get("colorblind_patterns", true)),
				bool(new_settings.get("high_contrast", false)),
			)
	for explosion_effect: Node2D in legacy_explosion_effects:
		if (
			explosion_effect != null
			and is_instance_valid(explosion_effect)
			and explosion_effect.has_method("set_reduce_flashes")
		):
			explosion_effect.call(
				"set_reduce_flashes",
				bool(new_settings.get("reduce_flashes", false)),
			)


func _effective_difficulty_mode() -> String:
	if _is_runtime_probe() or str(runtime_settings.get("ruleset_mode", "classic")) == "classic":
		return "original"
	var mode := str(runtime_settings.get("difficulty_mode", "normal"))
	if mode == "story":
		return "easy"
	if mode == "custom":
		return "normal"
	return mode if mode in ["normal", "hard"] else "normal"


func _open_pause_menu() -> void:
	if game_shell == null:
		return
	if media_director != null and media_director.has_method("is_modal_active"):
		if bool(media_director.is_modal_active()):
			return
	_reset_context_cursor()
	var slot_summaries := _save_slot_summaries()
	var can_load := not slot_summaries.is_empty()
	game_shell.set_save_slots(slot_summaries)
	if current_mission_state != null and current_mission_state.is_victory():
		game_shell.show_victory(
			can_load,
			current_level_index < FORMAL_LEVEL_IDS.size() - 1,
		)
	else:
		game_shell.show_pause_menu(can_load)


func _on_original_hud_action_requested(action: String) -> void:
	match action:
		"observation":
			_toggle_sight_observation()
		"minimap":
			_open_tactical_map()
		"system":
			_open_pause_menu()


func _on_original_hud_actor_requested(actor_name: String) -> void:
	for unit: SQUAD_UNIT in units:
		if unit.display_name != actor_name or not unit.is_alive:
			continue
		select_only(unit)
		update_status("已选择%s" % unit.display_name)
		_play_original_actor_audio(
			LEGACY_ACTOR_AUDIO_RULES.FAMILY_SELECTED,
			unit,
		)
		return


func _open_tactical_map() -> void:
	if game_shell == null:
		return
	var visible: bool = game_shell.toggle_tactical_map(
		_current_minimap_texture(),
		world_size,
		_tactical_actor_markers(),
		_tactical_mission_markers(),
		_camera_world_rect(),
	)
	minimap_refresh_elapsed = 0.0
	update_status("右下角地图：%s" % ("显示" if visible else "关闭"))
	if visible:
		_report_direction_action("open_minimap")


func _open_inventory(mode: String = "items") -> void:
	if game_shell != null:
		_reset_context_cursor()
		game_shell.hide_tactical_map()
		game_shell.show_inventory(_inventory_grid_model(), mode)
		if mode == "items":
			_report_direction_action("open_item_inventory")


func _report_direction_action(action: String) -> void:
	if mission_direction_runtime != null:
		mission_direction_runtime.report_tutorial_action(action)


func _open_control_guide() -> void:
	if game_shell == null:
		return
	_reset_context_cursor()
	game_shell.hide_tactical_map()
	game_shell.show_control_guide(
		_load_external_texture(converted_root.path_join("iblock/1047.png"))
	)


func _show_current_briefing() -> void:
	if media_director == null:
		return
	_reset_context_cursor()
	if game_shell != null:
		game_shell.hide_tactical_map()
	media_director.show_briefing(
		str(current_mission.get("id", FORMAL_LEVEL_IDS[current_level_index])),
		"第 %d 关：%s" % [
			int(current_mission.get("number", current_level_index + 1)),
			str(current_mission.get("title", "任务简报")),
		],
		"查看任务目标后按 Enter、Space 或 Esc 返回战场。",
	)


func _current_minimap_texture() -> Texture2D:
	if current_level_index >= 0 and current_level_index < ORIGINAL_MINIMAP_GFL_IDS.size():
		var texture := _load_external_texture(
			converted_root.path_join(
				"iblock/%d.png" % ORIGINAL_MINIMAP_GFL_IDS[current_level_index]
			)
		)
		if texture != null:
			return texture
	var terrain_node := get_node_or_null("ImportedTerrain")
	return (terrain_node as Sprite2D).texture if terrain_node is Sprite2D else null


func _load_external_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if imported_texture_cache.has(path):
		return imported_texture_cache[path] as Texture2D
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	imported_texture_cache[path] = texture
	return texture


func _load_converted_texture(relative_path: String) -> Texture2D:
	if relative_path.is_empty() or converted_root.is_empty():
		return null
	var absolute_path := _contained_converted_path(
		converted_root,
		relative_path,
	)
	if absolute_path.is_empty():
		return null
	if imported_texture_cache.has(absolute_path):
		return imported_texture_cache[absolute_path] as Texture2D
	var image := Image.new()
	if image.load(absolute_path) != OK or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	imported_texture_cache[absolute_path] = texture
	return texture


func _on_map_position_requested(world_position: Vector2) -> void:
	if level_camera == null:
		return
	_cancel_direction_camera_tween()
	camera_pan_velocity = Vector2.ZERO
	_reset_camera_edge_intent()
	level_camera.position = world_position
	clamp_level_camera()
	if level_camera.has_method("force_update_scroll"):
		level_camera.call("force_update_scroll")
	if game_shell != null:
		game_shell.update_map_camera(_camera_world_rect())


func _on_inventory_cycle_requested(direction: int) -> void:
	_cycle_selected_weapons(direction)
	_refresh_inventory_ui()


func _on_inventory_reload_requested() -> void:
	var reload_count := 0
	var original_count := 0
	for unit: SQUAD_UNIT in selected_units:
		_cancel_legacy_deployment_for_unit(unit)
		if (
			unit.combat_inventory != null
			and unit.combat_inventory.original_parity_enabled()
		):
			original_count += 1
			continue
		if unit.request_reload():
			reload_count += 1
	if original_count > 0 and reload_count == 0:
		update_status("原版武器直接消耗栏内数量，无需换弹")
	else:
		update_status("%d 名队员开始换弹" % reload_count)
	if game_shell != null:
		game_shell.update_inventory(_inventory_grid_model())


func _on_inventory_slot_requested(slot: Dictionary) -> void:
	var kind := str(slot.get("kind", ""))
	if kind != "backpack_item":
		selected_backpack_item_id = 0
	if kind == "weapon":
		var action_key := str(slot.get("action_key", ""))
		var equipped := 0
		for unit: SQUAD_UNIT in selected_units:
			_cancel_legacy_deployment_for_unit(unit)
			if unit.equip_inventory_weapon(action_key):
				equipped += 1
		update_status("%d 名队员装备%s" % [equipped, str(slot.get("label", "武器"))])
	elif kind == "active_item":
		_equip_selected_attack_type(int(slot.get("attack_type", 0)))
	elif kind == "backpack_item":
		var item_id := int(slot.get("item_id", 0))
		selected_backpack_item_id = item_id
		var actor: SQUAD_UNIT = (
			selected_units[0] if not selected_units.is_empty() else null
		)
		if actor != null:
			var profile: Dictionary = (
				ORIGINAL_INITIAL_ITEM_INVENTORY.item_profile(item_id)
			)
			if str(profile.get("behavior", "")) == "use":
				if _use_original_backpack_item(actor, item_id, profile):
					selected_backpack_item_id = 0
			else:
				update_status(
					"已选中 %s；点击地面后队员会先寻路，抵达时再放下"
					% str(slot.get("label", "物品"))
				)
	elif kind == "mission_item":
		update_status("%s：在对应任务位置按 E 使用" % str(slot.get("label", "任务物品")))
	_refresh_inventory_ui()


func _use_original_backpack_item(
	actor: SQUAD_UNIT,
	item_id: int,
	profile: Dictionary = {},
) -> bool:
	if (
		actor == null
		or not actor.is_alive
		or actor.backpack_inventory == null
		or not actor.backpack_inventory.has_item(item_id)
	):
		return false
	var resolved_profile: Dictionary = (
		profile
		if not profile.is_empty()
		else ORIGINAL_INITIAL_ITEM_INVENTORY.item_profile(item_id)
	)
	var effect_value: Variant = resolved_profile.get("effect")
	if not effect_value is Dictionary:
		return false
	var effect := effect_value as Dictionary
	var effect_kind := str(effect.get("kind", ""))
	var detail := ""
	match effect_kind:
		"refill_original_weapons":
			if actor.combat_inventory == null:
				return false
			var refill_value: Variant = effect.get("refill_by_weapon_item_id")
			if not refill_value is Dictionary:
				return false
			var added_total := 0
			for raw_weapon_item_id: Variant in (refill_value as Dictionary).keys():
				var weapon_item_id := int(str(raw_weapon_item_id))
				var refill := int((refill_value as Dictionary)[raw_weapon_item_id])
				var owns_weapon := false
				for action_key: String in (
					actor.combat_inventory.registered_weapon_keys()
				):
					var state: Dictionary = (
						actor.combat_inventory.weapon_state(action_key)
					)
					if int(state.get("ammo_item_id", 0)) == weapon_item_id:
						owns_weapon = true
						break
				if owns_weapon:
					added_total += int(
						actor.combat_inventory.add_item(weapon_item_id, refill)
					)
			actor.call("_sync_ammo_from_inventory", true)
			detail = "补充 %d 发/件武器用量" % added_total
		"set_hit_points":
			var previous := actor.current_hit_points
			actor.current_hit_points = clampi(
				int(effect.get("value", 8)),
				0,
				actor.maximum_hit_points,
			)
			detail = "生命 %d → %d" % [previous, actor.current_hit_points]
		"heal":
			var previous := actor.current_hit_points
			var cap := mini(
				int(effect.get("cap", actor.maximum_hit_points)),
				actor.maximum_hit_points,
			)
			actor.current_hit_points = mini(
				actor.current_hit_points + maxi(int(effect.get("value", 0)), 0),
				cap,
			)
			detail = "生命 %d → %d" % [previous, actor.current_hit_points]
		"set_disguise":
			if not actor.begin_original_disguise_transition(item_id):
				return false
			update_status(
				"%s 开始更换 %s"
				% [
					actor.display_name,
					ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
				]
			)
			_refresh_inventory_ui()
			return true
		_:
			return false
	if not actor.consume_backpack_item(item_id):
		return false
	if (
		selected_backpack_item_id == item_id
		and not actor.backpack_inventory.has_item(item_id)
	):
		selected_backpack_item_id = 0
	update_status(
		"%s 使用 %s：%s"
		% [
			actor.display_name,
			ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
			detail,
		]
	)
	_refresh_inventory_ui()
	return true


func _camera_world_rect() -> Rect2:
	if level_camera == null:
		return Rect2()
	var visible_size := _gameplay_viewport_size() / maxf(level_camera.zoom.x, 0.001)
	return Rect2(level_camera.position - visible_size * 0.5, visible_size)


func _tactical_actor_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	for unit: SQUAD_UNIT in units:
		if unit.is_alive:
			markers.append({
				"id": "player:%d" % unit.scene_index,
				"position": unit.position,
				"color": Color(0.28, 0.72, 1.0),
				"radius": 5.0,
				"selected": selected_units.has(unit),
			})
	for escort: ESCORT_UNIT in escorts:
		if escort.is_alive:
			var commandable := escort.is_player_commandable()
			markers.append({
				"id": "escort:%d" % escort.scene_index,
				"position": escort.position,
				"color": (
					Color(0.28, 0.72, 1.0)
					if commandable
					else Color(0.88, 0.82, 0.35)
						if not escort.rescued_state
						else Color(0.36, 0.82, 0.78)
				),
				"radius": 5.0 if commandable else 4.0,
				"selected": commandable and selected_units.has(escort),
			})
	for ambient: AMBIENT_UNIT in ambient_units:
		if ambient.is_alive:
			markers.append({
				"id": "ambient:%d" % ambient.scene_index,
				"position": ambient.position,
				"color": Color(0.72, 0.70, 0.56),
				"radius": 2.5,
			})
	for enemy: ENEMY_UNIT in enemies:
		if enemy.is_alive:
			markers.append({
				"id": "enemy:%d" % enemy.scene_index,
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
				"id": "mission:%s:%d" % [binding_kind, scene_index],
				"position": Vector2(float(entity["x"]), float(entity["y"])),
				"color": color,
				"radius": 6.0,
			})
	return markers


func _inventory_grid_model() -> Dictionary:
	var actor: SQUAD_UNIT = selected_units[0] if not selected_units.is_empty() else null
	if actor == null and not units.is_empty():
		actor = units[0]
	var actor_name := "未选择队员" if actor == null else actor.display_name
	if selected_units.size() > 1:
		actor_name = "已选 %d 人" % selected_units.size()
	var weapon_slots: Array[Dictionary] = []
	var backpack_slots: Array[Dictionary] = []
	var mission_item_slots: Array[Dictionary] = []
	if actor != null and actor.combat_inventory != null:
		var active_key := str(actor.combat_inventory.active_weapon_key())
		for action_key: String in actor.combat_inventory.registered_weapon_keys():
			var state: Dictionary = actor.combat_inventory.weapon_state(action_key)
			var profile := state.get("profile", {}) as Dictionary
			var attack_type := int(profile.get("attack_type", 0))
			var label := str(WEAPON_NAMES.get(attack_type, action_key))
			var is_original := bool(state.get("original_parity", false))
			var quantity_mode := int(state.get("quantity_mode", -1))
			var quantity := (
				int(state.get("quantity", 0))
				if is_original
				else int(state.get("magazine", 0))
					+ int(state.get("reserve", 0))
			)
			var description := ""
			if is_original:
				description = (
					"%s：原版耐久武器，普通攻击不消耗"
					% label
					if quantity_mode == 1
					else "%s：剩余 %d" % [label, quantity]
				)
			else:
				description = "%s：弹匣 %d，备用 %d" % [
					label,
					int(state.get("magazine", 0)),
					int(state.get("reserve", 0)),
				]
			weapon_slots.append({
				"kind": "weapon",
				"action_key": action_key,
				"attack_type": attack_type,
				"label": label,
				"short_label": label.left(3),
				"quantity": 0 if is_original and quantity_mode == 1 else quantity,
				"active": action_key == active_key,
				"enabled": actor.is_alive,
				"icon": _inventory_icon_for(action_key, 0, ""),
				"icon_selected": _inventory_icon_for(action_key, 0, "", true),
				"description": description,
			})
	if actor != null and actor.backpack_inventory != null:
		for entry: Dictionary in actor.backpack_inventory.ordered_entries():
			var item_id := int(entry.get("item_id", 0))
			var quantity := int(entry.get("quantity", 0))
			var quantity_mode := int(entry.get("quantity_mode", -1))
			var profile: Dictionary = (
				ORIGINAL_INITIAL_ITEM_INVENTORY.item_profile(item_id)
			)
			var label := str(
				profile.get(
					"display_name",
					ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
				)
			)
			var behavior := str(profile.get("behavior", "world_interaction"))
			var description := "%s × %d" % [label, quantity]
			if quantity_mode == 1:
				description += "；原版耐久物品，普通使用不消耗"
			elif quantity_mode == 2:
				description += "；原版保留零数量条目"
			if behavior == "use":
				description += "；点击使用"
			elif behavior == "mission_item":
				description += "；任务物品"
			else:
				description += "；选中后点击地面，抵达时放下"
			backpack_slots.append({
				"kind": "backpack_item",
				"item_id": item_id,
				"quantity_mode": quantity_mode,
				"label": label,
				"short_label": label.left(3),
				"quantity": quantity,
				"active": item_id == selected_backpack_item_id,
				"enabled": actor.is_alive and quantity > 0,
				"icon": _inventory_icon_for("", item_id, ""),
				"icon_selected": _inventory_icon_for("", item_id, "", true),
				"description": description,
			})
	for raw_key: Variant in field_inventory.keys():
		var quantity := int(field_inventory[raw_key])
		if quantity <= 0:
			continue
		var item_key := str(raw_key)
		var label := str(MISSION_ITEM_NAMES.get(item_key, item_key))
		mission_item_slots.append({
			"kind": "mission_item",
			"item_key": item_key,
			"label": label,
			"short_label": label.left(3),
			"quantity": quantity,
			"enabled": true,
			"icon": _inventory_icon_for("", 0, item_key),
			"icon_selected": _inventory_icon_for("", 0, item_key, true),
			"description": "%s × %d；在任务交互点使用" % [label, quantity],
		})
	return {
		"actor_name": actor_name,
		"groups": [
			{"title": "武器", "mode": "weapons", "slots": weapon_slots},
			{"title": "原版角色背包", "mode": "items", "slots": backpack_slots},
			{"title": "任务物资", "mode": "items", "slots": mission_item_slots},
		],
	}


func _inventory_icon_for(
	action_key: String,
	item_id: int,
	item_key: String,
	selected: bool = false,
) -> Texture2D:
	var resolved_item_id := item_id
	if not action_key.is_empty():
		var weapon_profile: Dictionary = COMBAT_PROFILES.weapon_profile(action_key)
		resolved_item_id = int(weapon_profile.get("ammo_item_id", 0))
	var logical_key := (
		"mission:%s" % item_key
		if not item_key.is_empty()
		else "item:%d" % resolved_item_id
	)
	logical_key += ":selected" if selected else ":normal"
	var cache_key := "%s|%s" % [converted_root, logical_key]
	if inventory_icon_cache.has(cache_key):
		return inventory_icon_cache[cache_key] as Texture2D

	var original_pair := Vector2i.ZERO
	if not item_key.is_empty():
		original_pair = ORIGINAL_INVENTORY_PSD_BY_MISSION_ITEM.get(
			item_key,
			Vector2i.ZERO,
		)
	else:
		original_pair = ORIGINAL_INVENTORY_PSD_BY_ITEM_ID.get(
			resolved_item_id,
			Vector2i.ZERO,
		)
	var original_psd_index := original_pair.y if selected else original_pair.x
	var icon: Texture2D
	if original_psd_index > 0 and not converted_root.is_empty():
		var original_icon_path := _contained_converted_path(
			converted_root,
			"psd/%04d.png" % original_psd_index,
		)
		if not original_icon_path.is_empty():
			icon = _load_external_texture(original_icon_path)
	if icon != null:
		inventory_icon_cache[cache_key] = icon
		return icon

	var sprite_stem := ""
	if not item_key.is_empty():
		sprite_stem = str(INVENTORY_ICON_SPRITES_BY_MISSION_ITEM.get(item_key, ""))
	else:
		sprite_stem = str(INVENTORY_ICON_SPRITES_BY_ITEM_ID.get(resolved_item_id, ""))
	if not sprite_stem.is_empty() and not converted_root.is_empty():
		var sprite_path := _contained_converted_path(
			converted_root,
			"sprites/%s.png" % sprite_stem,
		)
		if not sprite_path.is_empty():
			icon = _load_external_texture(sprite_path)
	if icon == null:
		# Several original weapon IDs have no recovered world-pickup sprite.
		# Keep every grid cell visual and stable without pretending a made-up
		# glyph is original artwork.
		icon = _inventory_fallback_icon(logical_key)
	inventory_icon_cache[cache_key] = icon
	return icon


func _inventory_fallback_icon(logical_key: String) -> Texture2D:
	var image := Image.create(32, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.08, 0.09, 0.07, 0.0))
	var hue := fmod(absf(float(logical_key.hash())) * 0.000000119, 1.0)
	var fill_color := Color.from_hsv(hue, 0.38, 0.48, 0.95)
	var line_color := Color(0.91, 0.76, 0.38, 1.0)
	for y: int in range(4, 36):
		for x: int in range(3, 29):
			var border := x in [3, 28] or y in [4, 35]
			var diagonal := x == 4 + ((y - 4) * 23 / 31) or x == 27 - ((y - 4) * 23 / 31)
			image.set_pixel(x, y, line_color if border or diagonal else fill_color)
	return ImageTexture.create_from_image(image)


func _inventory_bbcode() -> String:
	var lines := PackedStringArray()
	lines.append("[color=#e7d89a][b]当前关卡：%s　选中队员：%d[/b][/color]" % [str(current_mission.get("title", "")), selected_units.size()])
	lines.append("")
	for unit: SQUAD_UNIT in _commandable_player_units():
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
				if bool(weapon_state.get("original_parity", false)):
					if int(weapon_state.get("quantity_mode", -1)) != 1:
						ammunition = " × %d" % int(
							weapon_state.get("quantity", 0)
						)
				elif int(weapon_state.get("magazine_capacity", 0)) > 0:
					ammunition = " %d/%d" % [int(weapon_state.get("magazine", 0)), int(weapon_state.get("reserve", 0))]
				weapon_parts.append(weapon_name + ammunition)
			if not weapon_parts.is_empty():
				lines.append("　武器：" + "　｜　".join(weapon_parts))
		lines.append("")
	var shared_parts := PackedStringArray()
	for raw_key: Variant in field_inventory.keys():
		var quantity := int(field_inventory[raw_key])
		if quantity > 0:
			shared_parts.append("%s × %d" % [str(raw_key), quantity])
	lines.append("[color=#9fd6a0][b]小队任务物资：[/b][/color]%s" % ("无" if shared_parts.is_empty() else "　｜　".join(shared_parts)))
	lines.append("[color=#aeb7a8]提示：W 查看并切换原版武器；数量就是剩余可用次数，耐久武器不消耗。[/color]")
	return "\n".join(lines)


func _save_slot_summaries() -> Array[Dictionary]:
	if save_store == null:
		return []
	return save_store.list_slots()


func _latest_save_slot() -> String:
	if save_store == null:
		return ""
	var slots: Array[Dictionary] = save_store.list_slots()
	return _latest_slot_from_summaries(slots)


func _latest_slot_from_summaries(slots: Array[Dictionary]) -> String:
	if slots.is_empty():
		return ""
	slots.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return GAME_SAVE_STORE_SCRIPT.slot_summary_is_newer(first, second)
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
	if game_shell != null:
		game_shell.set_save_slots(_save_slot_summaries())
	return true


func _save_checkpoint(reason: String, force: bool = false) -> bool:
	if checkpoint_manager == null or restoring_save:
		return false
	var slot_id := str(checkpoint_manager.reserve_slot(reason, force))
	if slot_id.is_empty():
		return false
	var saved := _save_game(slot_id, false)
	if runtime_diagnostics != null:
		runtime_diagnostics.record_command(
			"checkpoint_saved" if saved else "checkpoint_failed",
			{"slot_id": slot_id, "reason": reason},
		)
	return saved


func _load_game(slot_id: String = "") -> bool:
	if save_store == null:
		_show_load_feedback("存档系统尚未初始化")
		return false
	if slot_id.is_empty():
		slot_id = _latest_save_slot()
	if slot_id.is_empty():
		_show_load_feedback("没有可读取的存档")
		return false
	var result: Dictionary = save_store.load_slot(slot_id)
	if not bool(result.get("ok", false)):
		_show_load_feedback("读取失败：%s" % str(result.get("message", "存档损坏")))
		return false
	var document := result.get("data", {}) as Dictionary
	var session := document.get("session", {}) as Dictionary
	var source_save_schema := int(
		result.get("source_schema_version", document.get("schema_version", 0))
	)
	var level_id := str(session.get("level_id", ""))
	var level_index := FORMAL_LEVEL_IDS.find(level_id)
	if level_index < 0:
		_show_load_feedback("读取失败：存档关卡编号无效")
		return false
	if game_shell != null:
		game_shell.close_for_state_change()
	var saved_runtime_profile_value: Variant = session.get(
		"runtime_profile",
		{},
	)
	if source_save_schema >= 2 and saved_runtime_profile_value is Dictionary:
		var saved_runtime_profile := saved_runtime_profile_value as Dictionary
		for profile_key: String in [
			"ruleset_mode",
			"difficulty_mode",
			"control_scheme",
			"mission_rule_mode",
		]:
			runtime_settings[profile_key] = str(
				saved_runtime_profile.get(profile_key, runtime_settings.get(profile_key, ""))
			)
		if saved_runtime_profile.get("custom_difficulty", {}) is Dictionary:
			runtime_settings["custom_difficulty"] = (
				(saved_runtime_profile["custom_difficulty"] as Dictionary)
				.duplicate(true)
			)
		if game_settings != null:
			game_settings.set_ruleset_mode(str(runtime_settings["ruleset_mode"]))
			game_settings.set_difficulty_mode(str(runtime_settings["difficulty_mode"]))
			game_settings.set_control_scheme(str(runtime_settings["control_scheme"]))
			game_settings.set_custom_difficulty(
				runtime_settings["custom_difficulty"] as Dictionary
			)
	# A save owns the mission graph under which objective progress was
	# recorded. Resolve it before switch_level() creates MissionState, or an
	# a forked mission checkpoint could be restored against the other rule profile.
	var saved_mission_rule := str(
		session.get(
			"mission_rule_mode",
			runtime_settings.get("mission_rule_mode", "stable_mod"),
		)
	)
	if saved_mission_rule in MISSION_DATA.RULE_MODES:
		runtime_settings["mission_rule_mode"] = saved_mission_rule
		if game_settings != null:
			game_settings.set_mission_rule_mode(saved_mission_rule)
	var saved_direction_state: Variant = (
		(session.get("world", {}) as Dictionary).get("mission_direction", {})
	)
	# A save owns the difficulty under which its actors and director state were
	# created.  Adopt it before rebuilding the level so restore_state never
	# silently rejects a valid save or changes combat balance mid-session.
	if source_save_schema < 2 and saved_direction_state is Dictionary:
		var saved_mode := str(
			(saved_direction_state as Dictionary).get(
				"difficulty_mode",
				runtime_settings.get("difficulty_mode", "original"),
			)
		)
		if saved_mode in ["original", "easy", "normal", "hard"]:
			runtime_settings["ruleset_mode"] = (
				"classic" if saved_mode == "original" else "modern"
			)
			runtime_settings["difficulty_mode"] = (
				"story" if saved_mode == "easy" else "normal" if saved_mode == "original" else saved_mode
			)
			if game_settings != null:
				game_settings.set_ruleset_mode(
					str(runtime_settings["ruleset_mode"])
				)
				game_settings.set_difficulty_mode(
					str(runtime_settings["difficulty_mode"])
				)
			if game_shell != null:
				game_shell.set_settings(runtime_settings)
	if game_settings != null:
		game_settings.save_to_disk()
	if game_shell != null:
		game_shell.set_settings(runtime_settings)
	restoring_save = true
	switch_level(level_index, false, false)
	restoring_save = false
	var applied: Dictionary = GAME_SESSION_STATE_SCRIPT.apply_after_level_loaded(self, session)
	if not bool(applied.get("ok", false)):
		_show_load_feedback("读取失败：无法恢复关卡状态")
		return false
	if (
		not saved_direction_state is Dictionary
		or (saved_direction_state as Dictionary).is_empty()
		or not bool(applied.get("mission_direction_restored", false))
	):
		_start_mission_direction()
	campaign_progress = (
		(document.get("campaign", GAME_SAVE_STORE_SCRIPT.default_campaign()) as Dictionary)
		.duplicate(true)
	)
	var warnings := applied.get("warnings", []) as Array
	if saved_runtime_profile_value is Dictionary:
		var saved_content_identity := str(
			(saved_runtime_profile_value as Dictionary).get(
				"content_identity",
				"",
			)
		)
		var current_content_identity := _current_content_identity()
		if (
			not saved_content_identity.is_empty()
			and not current_content_identity.is_empty()
			and saved_content_identity != current_content_identity
			and not saved_content_identity.begins_with("legacy_schema_")
		):
			warnings.append(
				"save content identity differs from the active package"
			)
	if current_mission_state.is_failed():
		_on_mission_failed(str(current_mission_state.failure_id))
	elif current_mission_state.is_victory():
		victory_handled_level_id = level_id
		update_status("存档已恢复：本关任务已完成，可进入下一关")
		_resume_incomplete_victory_presentation()
	else:
		update_status(
			"存档已恢复%s" % ("" if warnings.is_empty() else "（%d 项内容降级）" % warnings.size())
		)
	return true


func _current_content_identity() -> String:
	var identity := str(
		content_package_validation.get("content_identity_sha256", "")
	)
	if not identity.is_empty():
		return identity
	return str(
		content_package_validation.get("status", "development_unmanifested")
	)


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
	campaign_progress = CAMPAIGN_PROGRESS_SCRIPT.record_victory(
		campaign_progress,
		level_id,
	)
	_sync_level_selection()


func _publish_mission_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
	if mission_runtime == null or not mission_runtime.is_configured():
		return []
	var progress_before: Dictionary = {}
	if current_mission_state != null:
		progress_before = current_mission_state.progress.duplicate()
	var completed: Array[String] = mission_runtime.publish_world_event(event_name, payload)
	if not mission_runtime.last_error.is_empty():
		push_warning("任务事件被拒绝：%s" % mission_runtime.last_error)
	else:
		if mission_ai_coordinator != null:
			mission_ai_coordinator.observe_mission_event(event_name, payload)
	if mission_runtime.last_error.is_empty() and event_name == "story_anchor_reached" and not completed.is_empty():
		_play_mission_media_cue("on_story_anchor", str(payload.get("role_id", "")))
		if (
			str(current_mission.get("id", "")) == "m006"
			and str(payload.get("role_id", "")) == "m006_exchange_point"
			and completed.has("follow_contact")
		):
			_report_direction_action("follow_target")
	if mission_direction_runtime != null and current_mission_state != null:
		for objective_value: Variant in current_mission_state.progress.keys():
			var objective_id := str(objective_value)
			var count := int(current_mission_state.progress.get(objective_id, 0))
			if count != int(progress_before.get(objective_id, 0)):
				mission_direction_runtime.publish_event(
					"objective_progress",
					{"objective_id": objective_id, "count": count},
				)
	return completed


func _on_objective_completed(objective_id: String) -> void:
	if mission_direction_runtime != null:
		mission_direction_runtime.publish_event(
			"objective_completed", {"objective_id": objective_id}
		)
	if objective_id == "place_mine_charges":
		_report_direction_action("place_all_charges")
	update_status("任务目标完成：%s" % objective_id)
	_play_mission_media_cue("on_objective", objective_id)
	_save_checkpoint("objective:%s" % objective_id)


func _on_mission_victory() -> void:
	var level_id := str(current_mission.get("id", ""))
	if not level_id.is_empty() and victory_handled_level_id == level_id:
		return
	victory_handled_level_id = level_id
	if mission_direction_runtime != null:
		mission_direction_runtime.publish_event("victory")
	_update_campaign_progress_for_victory()
	victory_presentation_completed = false
	_save_game(AUTO_SAVE_SLOT, false)
	update_status("任务完成！已自动保存；按 Esc 打开菜单选择后续操作。")
	_refresh_mission_ui()
	pending_victory_media_cue = not _mission_media_cue("on_victory").is_empty()
	call_deferred("_try_play_pending_victory_media_cue")
	call_deferred("_try_complete_victory_presentation")


func _on_briefing_closed(level_id: String) -> void:
	if (
		pending_initial_briefing_level == level_id
		and str(current_mission.get("id", "")) == level_id
	):
		pending_initial_briefing_level = ""
		_start_initial_direction_sequence()


func _on_media_dialogue_finished(sequence_id: String, _skipped: bool) -> void:
	if sequence_id == pending_direction_start_sequence_id:
		pending_direction_start_sequence_id = ""
		_start_mission_direction()
	if pending_victory_media_cue:
		call_deferred("_try_play_pending_victory_media_cue")
	call_deferred("_try_complete_victory_presentation")


func _on_media_movie_finished(movie_id: String, _skipped: bool) -> void:
	if bool(startup_media_queue.call("resolve", movie_id)):
		call_deferred("_play_next_original_startup_movie")
		return
	call_deferred("_try_complete_victory_presentation")


func _on_media_ending_closed() -> void:
	call_deferred("_try_complete_victory_presentation")


func _try_play_pending_victory_media_cue() -> void:
	if not pending_victory_media_cue or media_director == null:
		return
	if not media_director.dialogue_sequence_id.is_empty():
		return
	if (
		mission_direction_runtime != null
		and mission_direction_runtime.has_pending_media_dialogue()
	):
		return
	pending_victory_media_cue = false
	_play_mission_media_cue("on_victory")
	call_deferred("_try_complete_victory_presentation")


func _resume_incomplete_victory_presentation() -> void:
	if victory_presentation_completed or media_director == null:
		return
	if (
		mission_direction_runtime != null
		and mission_direction_runtime.has_method("replay_fired_beat_presentation")
	):
		mission_direction_runtime.call("replay_fired_beat_presentation", "victory")
	pending_victory_media_cue = not _mission_media_cue("on_victory").is_empty()
	call_deferred("_try_play_pending_victory_media_cue")
	call_deferred("_try_complete_victory_presentation")


func _try_complete_victory_presentation() -> void:
	if victory_presentation_completed or current_mission_state == null:
		return
	if not current_mission_state.is_victory() or pending_victory_media_cue:
		return
	if media_director != null and (
		media_director.active_ending
		or not media_director.active_movie.is_empty()
		or not media_director.dialogue_sequence_id.is_empty()
	):
		return
	if (
		mission_direction_runtime != null
		and mission_direction_runtime.has_pending_media_dialogue()
	):
		return
	victory_presentation_completed = true
	if game_shell != null and mission_statistics != null and history_archive != null:
		var level_id := str(current_mission.get("id", ""))
		var debrief: String = history_archive.build_debrief(
			level_id,
			mission_statistics.snapshot(),
		)
		if not bool(runtime_settings.get("history_notes", true)):
			debrief = "[b]%s[/b]\n%s" % [tr("UI_MISSION_DEBRIEF"), _mission_statistics_summary(
				mission_statistics.snapshot()
			)]
		game_shell.set_victory_debrief(level_id, debrief)
	_save_game(AUTO_SAVE_SLOT, false)


func _mission_statistics_summary(statistics: Dictionary) -> String:
	var elapsed_seconds := maxi(int(statistics.get("elapsed_msec", 0)) / 1000, 0)
	return tr("STATS_SUMMARY_FORMAT") % [
		elapsed_seconds / 60,
		elapsed_seconds % 60,
		int(statistics.get("commands", 0)),
		int(statistics.get("attacks", 0)),
		int(statistics.get("hits", 0)),
		int(statistics.get("enemies_eliminated", 0)),
	]


func _play_mission_media_cue(section: String, key: String = "") -> bool:
	if media_director == null:
		return false
	var cue := _mission_media_cue(section, key)
	if cue.is_empty() or not _mission_media_cue_enabled(cue):
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
			var sequence_id := str(cue.get("sequence_id", ""))
			var lines := (cue.get("lines", []) as Array).duplicate(true)
			if (
				mission_direction_runtime != null
				and mission_direction_runtime.has_method("queue_external_dialogue")
			):
				return bool(
					mission_direction_runtime.call(
						"queue_external_dialogue",
						sequence_id,
						lines,
					)
				)
			return bool(
				media_director.start_dialogue(
					sequence_id,
					lines,
				)
			)
		"movie":
			_reset_context_cursor()
			return bool(media_director.play_movie(str(cue.get("movie_id", ""))))
		"ending":
			_reset_context_cursor()
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


func _mission_media_cue_enabled(cue: Dictionary) -> bool:
	if str(cue.get("source_status", "")) != "remake_editorial":
		return true
	return _effective_difficulty_mode() != "original"


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
	update_status(tr("STATUS_MISSION_FAILURE_FORMAT") % failure_id)
	_refresh_mission_ui()
	if game_shell != null:
		_reset_context_cursor()
		var slot_summaries := _save_slot_summaries()
		game_shell.set_save_slots(slot_summaries)
		game_shell.show_failure(
			tr("UI_MISSION_FAILURE_DETAILS_FORMAT") % failure_id,
			not slot_summaries.is_empty(),
		)


func _refresh_mission_ui() -> void:
	if objective_label == null or current_mission_state == null:
		return
	var lines: Array[String] = current_mission_state.display_lines()
	if current_mission_state.is_victory():
		lines.append("★ 任务完成")
	elif current_mission_state.is_failed():
		lines.append("× 任务失败：%s" % current_mission_state.failure_id)
	objective_label.text = "\n".join(lines)


func _on_escort_rescued(escort: Node2D, _rescuer: Node2D) -> void:
	var payload := {
		"scene_index": int(escort.scene_index),
		"display_name": str(escort.display_name),
	}
	if str(escort.display_name) in ["铁蛋爹", "铁蛋娘"]:
		payload["family_role"] = "tiedan_parents"
	_publish_mission_event("entity_rescued", payload)
	_report_direction_action("rescue_escort")
	if str(current_mission.get("id", "")) == "m006":
		_report_direction_action("follow_target")
	update_status("已营救 %s，请护送其完成任务" % escort.display_name)
	if escort.has_method("is_player_commandable") and bool(
		escort.call("is_player_commandable")
	):
		update_status("已营救 %s，其已加入可操作队伍" % escort.display_name)


func interact_with_mission_world() -> void:
	var origins := _interaction_origins()
	if origins.is_empty():
		update_status("没有可执行交互的存活队员")
		return
	for origin: SQUAD_UNIT in origins:
		_cancel_legacy_deployment_for_unit(origin)
	if _advance_original_escort_rescue_proximity() > 0:
		return
	for cache: Node2D in legacy_burial_caches:
		if not is_instance_valid(cache) or not bool(cache.call("has_loot")):
			continue
		for origin: SQUAD_UNIT in origins:
			if not bool(cache.call("can_interact", origin)):
				continue
			var transferred := cache.call("transfer_all_to", origin) as Dictionary
			update_status(
				"已从藏尸处取得 %d 类武器物资和 %d 类背包物品"
				% [
					int(transferred.get("weapon_entries", 0)),
					int(transferred.get("backpack_entries", 0)),
				]
			)
			_refresh_inventory_ui()
			return
	var nearest_escort: ESCORT_UNIT
	var nearest_distance := INF
	var nearest_rescuer: SQUAD_UNIT
	for escort: ESCORT_UNIT in escorts:
		if (
			escort.rescued_state
			or not escort.is_alive
			or escort.has_source_backed_rescue_rule()
		):
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
	var nearest_pickup_collector: SQUAD_UNIT
	nearest_distance = INF
	for pickup: MISSION_PICKUP in mission_pickups:
		if pickup.collected:
			continue
		for origin: SQUAD_UNIT in origins:
			if not pickup.can_collect(origin):
				continue
			var distance := origin.position.distance_to(pickup.position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_pickup = pickup
				nearest_pickup_collector = origin
	if nearest_pickup != null and nearest_distance <= MISSION_INTERACTION_RADIUS:
		var pickup_world_position := nearest_pickup.position
		var payload := nearest_pickup.collect(nearest_pickup_collector)
		_unregister_mission_pickup(nearest_pickup)
		_free_level_runtime_node(nearest_pickup)
		if (
			nearest_pickup_collector != null
			and _collect_original_inventory_pickup(
				payload,
				nearest_pickup_collector,
				pickup_world_position,
			)
		):
			_report_direction_action("pickup_role_drop")
			return
		if nearest_pickup_collector != null:
			_on_original_pickup_cover_committed(
				nearest_pickup_collector,
				pickup_world_position,
			)
		_publish_item_acquired_if_mission_bound(payload)
		_report_direction_action("pickup_role_drop")
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
		var field_pickup_world_position := nearest_field_pickup.position
		var field_payload: Dictionary = nearest_field_pickup.collect(nearest_field_collector)
		if not field_payload.is_empty():
			field_pickups.erase(nearest_field_pickup)
			_apply_field_pickup(
				field_payload,
				nearest_field_collector,
				field_pickup_world_position,
			)
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


func _collect_original_inventory_pickup(
	payload: Dictionary,
	collector: SQUAD_UNIT,
	source_world_position: Variant = null,
) -> bool:
	var inventory_kind := str(payload.get("original_inventory_kind", ""))
	if inventory_kind not in ["backpack", "weapon"]:
		return false
	var item_id := int(payload.get("item_id", 0))
	var quantity := maxi(int(payload.get("quantity", 0)), 0)
	var quantity_mode := int(payload.get("quantity_mode", -1))
	var committed_world_position := collector.position
	if source_world_position is Vector2:
		committed_world_position = source_world_position as Vector2
	var accepted := false
	if inventory_kind == "backpack":
		accepted = (
			quantity > 0
			and collector.add_backpack_item(
				item_id,
				quantity,
				quantity_mode,
			) == quantity
		)
	else:
		var attack_type := int(payload.get("attack_type", 0))
		if attack_type <= 0:
			attack_type = (
				ORIGINAL_INITIAL_WEAPON_INVENTORY.attack_type_for_item_id(item_id)
			)
		var profile: Dictionary = (
			COMBAT_PROFILES.weapon_profile_for_attack_type(attack_type)
		)
		var action_key := str(profile.get("action_key", ""))
		if not profile.is_empty() and not action_key.is_empty():
			if collector.has_inventory_weapon(action_key):
				accepted = (
					quantity <= 0
					or collector.add_ammo_item(item_id, quantity) == quantity
				)
			else:
				accepted = collector.register_original_inventory_weapon(
					profile,
					_attack_groups_for_unit(collector, action_key),
					quantity,
					quantity_mode,
					false,
				)
	if not accepted:
		# Collection is already committed by the original interaction flow.
		# Preserve the evidence in the mission event instead of silently losing it.
		var rejected_event_payload := payload.duplicate(true)
		rejected_event_payload["collector_name"] = str(collector.display_name)
		_publish_item_acquired_if_mission_bound(rejected_event_payload)
		_on_original_pickup_cover_committed(
			collector,
			committed_world_position,
		)
		update_status("物品容器冲突，已按任务物品记录")
		return true
	var item_name := str(
		payload.get(
			"item_name",
			ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id),
		)
	)
	var event_payload := payload.duplicate(true)
	event_payload["item_name"] = item_name
	event_payload["collector_name"] = str(collector.display_name)
	_publish_item_acquired_if_mission_bound(event_payload)
	_on_original_pickup_cover_committed(
		collector,
		committed_world_position,
	)
	update_status("%s 拾取 %s" % [collector.display_name, item_name])
	command_bus.emit_event(
		"pickup_collected",
		{"item_id": item_id, "quantity": quantity},
		"inventory",
	)
	_refresh_inventory_ui()
	return true


func _publish_item_acquired_if_mission_bound(
	payload: Dictionary,
) -> Array[String]:
	# Most DBL world pickups are ordinary actor inventory, not mission facts.
	# MissionRuntime deliberately rejects unbound scenes, so only route the
	# acquisition when its source participates in this mission's binding graph.
	for field: String in [
		"scene_index",
		"source_scene_index",
		"trigger_scene_index",
	]:
		if payload.has(field) and _scene_is_mission_bound(int(payload[field])):
			var item_role := str(payload.get("item_role", ""))
			var collector_name := str(payload.get("collector_name", ""))
			if (
				not item_role.is_empty()
				and not LEGACY_MISSION_RULES.item_holder_is_eligible(
					str(current_mission.get("id", "")),
					item_role,
					collector_name,
				)
			):
				update_status("该任务物品必须交给指定队员携带")
				return []
			return _publish_mission_event("item_acquired", payload)
	return []


func issue_original_pickup_order(pickup: Node2D) -> bool:
	if (
		pickup == null
		or not is_instance_valid(pickup)
		or _world_pickup_is_consumed(pickup)
		or selected_units.is_empty()
	):
		update_status("请先选择存活队员和可拾取物品")
		return false
	var collector: SQUAD_UNIT
	var nearest_distance := INF
	for unit: SQUAD_UNIT in selected_units:
		if not unit.is_alive:
			continue
		var distance := unit.position.distance_squared_to(pickup.position)
		if distance < nearest_distance:
			nearest_distance = distance
			collector = unit
	if (
		collector == null
		or not _collector_can_use_world_pickup(collector, pickup)
	):
		update_status("当前队员不能拾取该物品")
		return false
	_clear_original_pickup_order()
	_clear_original_drop_order()
	_cancel_legacy_deployment_for_unit(collector)
	collector.clear_combat_target()
	original_pickup_order_target = pickup
	original_pickup_order_collector = collector
	collector.queue_original_acknowledgement()
	if bool(pickup.call("can_collect", collector)):
		return _complete_original_pickup_order()
	var path := PackedVector2Array()
	if navigation_grid == null:
		path.append(pickup.position)
	elif dynamic_occupancy != null and collector.scene_index >= 0:
		path = dynamic_occupancy.find_path_for_scene(
			collector.scene_index,
			collector.position,
			pickup.position,
		)
	else:
		path = navigation_grid.find_path(
			collector.position,
			pickup.position,
			true,
		)
	if path.is_empty() and not collector.position.is_equal_approx(pickup.position):
		_clear_original_pickup_order()
		update_status("没有通往该物品的可行路线")
		return false
	collector.issue_path(path)
	update_status("%s 正在接近 %s" % [
		collector.display_name,
		_world_pickup_display_name(pickup),
	])
	return true


func _advance_original_pickup_order() -> void:
	if original_pickup_order_target == null:
		return
	if (
		not is_instance_valid(original_pickup_order_target)
		or original_pickup_order_target.is_queued_for_deletion()
		or _world_pickup_is_consumed(original_pickup_order_target)
		or original_pickup_order_collector == null
		or not is_instance_valid(original_pickup_order_collector)
		or not original_pickup_order_collector.is_alive
	):
		_clear_original_pickup_order()
		return
	if bool(
		original_pickup_order_target.call(
			"can_collect",
			original_pickup_order_collector,
		)
	):
		_complete_original_pickup_order()


func _complete_original_pickup_order() -> bool:
	var pickup := original_pickup_order_target
	var collector := original_pickup_order_collector
	if (
		pickup == null
		or collector == null
		or not is_instance_valid(pickup)
		or not is_instance_valid(collector)
		or not _collector_can_use_world_pickup(collector, pickup)
	):
		_clear_original_pickup_order()
		return false
	var pickup_world_position: Vector2 = pickup.position
	var payload := pickup.call("collect", collector) as Dictionary
	if payload.is_empty():
		return false
	_clear_original_pickup_order()
	if pickup is MISSION_PICKUP:
		var mission_pickup := pickup as MISSION_PICKUP
		_unregister_mission_pickup(mission_pickup)
		_collect_original_inventory_pickup(
			payload,
			collector,
			pickup_world_position,
		)
		_free_level_runtime_node(mission_pickup)
	else:
		field_pickups.erase(pickup)
		_apply_field_pickup(payload, collector, pickup_world_position)
	return true


func _clear_original_pickup_order() -> void:
	original_pickup_order_target = null
	original_pickup_order_collector = null


func _collector_can_use_field_pickup(collector: SQUAD_UNIT, pickup: Node2D) -> bool:
	var grant: Dictionary = pickup.get("grant") as Dictionary
	return (
		collector != null
		and str(grant.get("kind", ""))
			== WORLD_PICKUP_CATALOG.ORIGINAL_INVENTORY_GRANT_KIND
	)


func _collector_can_use_world_pickup(
	collector: SQUAD_UNIT,
	pickup: Node2D,
) -> bool:
	if collector == null or pickup == null or not is_instance_valid(pickup):
		return false
	if pickup is MISSION_PICKUP:
		return str(
			(pickup as MISSION_PICKUP).item_payload.get(
				"original_inventory_kind",
				"",
			)
		) in ["backpack", "weapon"]
	return _collector_can_use_field_pickup(collector, pickup)


func _world_pickup_is_consumed(pickup: Node2D) -> bool:
	if pickup == null or not is_instance_valid(pickup):
		return true
	if pickup is MISSION_PICKUP:
		return (pickup as MISSION_PICKUP).collected
	return bool(pickup.get("consumed"))


func _world_pickup_display_name(pickup: Node2D) -> String:
	if pickup is MISSION_PICKUP:
		var payload := (pickup as MISSION_PICKUP).item_payload
		return str(
			payload.get(
				"item_name",
				ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(
					int(payload.get("item_id", 0))
				),
			)
		)
	return str(pickup.get("original_display_name"))


func _apply_field_pickup(
	payload: Dictionary,
	collector: SQUAD_UNIT,
	source_world_position: Variant = null,
) -> void:
	_cancel_legacy_deployment_for_unit(collector)
	var grant := payload.get("grant", {}) as Dictionary
	if (
		str(grant.get("kind", ""))
		!= WORLD_PICKUP_CATALOG.ORIGINAL_INVENTORY_GRANT_KIND
	):
		return
	var item_id := int(grant.get("item_id", 0))
	var exact_payload := payload.duplicate(true)
	exact_payload["original_inventory_kind"] = str(grant.get("container", ""))
	exact_payload["item_id"] = item_id
	exact_payload["quantity"] = int(grant.get("quantity", 1))
	exact_payload["quantity_mode"] = int(grant.get("quantity_mode", -1))
	exact_payload["item_name"] = (
		ORIGINAL_INITIAL_ITEM_INVENTORY.item_display_name(item_id)
	)
	if not _collect_original_inventory_pickup(
		exact_payload,
		collector,
		source_world_position,
	):
		return
	# A DBL pickup can also be a mission scene binding (notably m001's
	# uniform). The inventory event was already published above; only suppress
	# the now-consumed world binding so it cannot reappear as a ghost target.
	_mark_field_pickup_binding_activated(int(payload.get("scene_index", -1)))


func _attack_groups_for_unit(unit: SQUAD_UNIT, action_key: String) -> Array[Dictionary]:
	return _attack_groups_for_actor_variant(
		unit,
		action_key,
		unit.runtime_actor_type,
	)


func _attack_groups_for_actor_variant(
	unit: SQUAD_UNIT,
	action_key: String,
	runtime_actor_type: int,
) -> Array[Dictionary]:
	if not playable_entities.has(unit.display_name):
		return []
	var resolved_action_key := action_key
	if not IMPORTED_SPRITE_ANIMATION.ACTION_KEYS.has(resolved_action_key):
		var profile: Dictionary = COMBAT_PROFILES.weapon_profile(action_key)
		var animation_action := int(profile.get("animation_action", 0))
		if (
			animation_action > 0
			and animation_action < IMPORTED_SPRITE_ANIMATION.ACTION_KEYS.size()
		):
			resolved_action_key = IMPORTED_SPRITE_ANIMATION.ACTION_KEYS[animation_action]
	if (
		runtime_actor_type
		== LEGACY_DISGUISE_RULES.DISGUISED_RUNTIME_ACTOR_TYPE
	):
		return _load_gfl_action_groups(
			LEGACY_DISGUISE_RULES.DISGUISED_GFL_INDEX,
			resolved_action_key,
		)
	var entity := playable_entities[unit.display_name] as Dictionary
	if (
		runtime_actor_type == LEGACY_DISGUISE_RULES.NORMAL_RUNTIME_ACTOR_TYPE
		and _entity_runtime_actor_type(entity)
			== LEGACY_DISGUISE_RULES.NORMAL_RUNTIME_ACTOR_TYPE
	):
		return _load_gfl_action_groups(
			LEGACY_DISGUISE_RULES.NORMAL_GFL_INDEX,
			resolved_action_key,
		)
	return load_entity_action_groups(
		entity,
		resolved_action_key,
	)


func _current_native_mission_rule() -> Dictionary:
	return LEGACY_MISSION_RULES.rule_for(
		str(current_mission.get("id", ""))
	)


func _current_native_target_rule() -> Dictionary:
	return LEGACY_MISSION_RULES.target_rule_for(
		str(current_mission.get("id", ""))
	)


func _record_native_timed_explosive_presence(world_object: Node2D) -> void:
	if world_object == null or not is_instance_valid(world_object):
		return
	var rule := _current_native_target_rule()
	if (
		str(rule.get("completion", ""))
			!= LEGACY_MISSION_RULES.TIMED_EXPLOSIVE_WITHIN_RADIUS
		or int(world_object.get("original_actor_type"))
			!= int(rule.get("required_runtime_actor_type", 0))
	):
		return
	var binding := str(rule.get("binding", ""))
	var radius := float(rule.get("radius_world", 0.0))
	var exclusive := bool(rule.get("exclusive_boundary", true))
	for scene_index: int in _binding_scenes(binding):
		if (
			activated_mission_scenes.has(scene_index)
			or not world_entities_by_scene.has(scene_index)
		):
			continue
		var entity := world_entities_by_scene[scene_index] as Dictionary
		var target_position := Vector2(float(entity["x"]), float(entity["y"]))
		if LEGACY_MISSION_RULES.distance_matches(
			world_object.global_position,
			target_position,
			radius,
			exclusive,
		):
			_complete_native_explosion_scene(scene_index)


func _resolve_native_destroyed_targets_from_explosion(
	explosion_position: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
	damage: int,
) -> void:
	var rule := _current_native_target_rule()
	if (
		damage <= 0
		or str(rule.get("completion", ""))
			!= LEGACY_MISSION_RULES.TARGET_HIT_POINTS_NONPOSITIVE
	):
		return
	for scene_index: int in _binding_scenes(str(rule.get("binding", ""))):
		if (
			activated_mission_scenes.has(scene_index)
			or not world_entities_by_scene.has(scene_index)
		):
			continue
		var entity := world_entities_by_scene[scene_index] as Dictionary
		var target_position := Vector2(float(entity["x"]), float(entity["y"]))
		if (
			LEGACY_MISSION_RULES.explosion_destroys_target(
				maxi(int(entity.get("current_hit_points", 8)), 1),
				damage,
			)
			and LEGACY_MISSION_RULES.explosion_covers_target(
				explosion_position,
				target_position,
				horizontal_radius,
				vertical_radius,
			)
		):
			_complete_native_explosion_scene(scene_index)


func _complete_native_explosion_scene(scene_index: int) -> bool:
	if (
		activated_mission_scenes.has(scene_index)
		or mission_runtime == null
		or not mission_runtime.is_configured()
	):
		return activated_mission_scenes.has(scene_index)
	activated_mission_scenes[scene_index] = true
	_publish_mission_event(
		"trigger_activated",
		{"scene_index": scene_index, "display_name": "检测爆炸精灵"},
	)
	if not mission_runtime.last_error.is_empty():
		activated_mission_scenes.erase(scene_index)
		return false
	_report_direction_action("place_charge")
	var all_completed := true
	for target_scene: int in _binding_scenes("explosion"):
		if not activated_mission_scenes.has(target_scene):
			all_completed = false
			break
	if all_completed:
		_report_direction_action("place_all_charges")
	update_status("原版任务目标 %d 已满足" % scene_index)
	queue_redraw()
	return true


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
		_publish_item_acquired_if_mission_bound(payload)
		activated_mission_scenes[scene_index] = true
		queue_redraw()
		return true
	if binding_kind == "explosion":
		if activated_mission_scenes.has(scene_index):
			return true
		var native_rule := _current_native_target_rule()
		var native_completion := str(native_rule.get("completion", ""))
		if native_completion == LEGACY_MISSION_RULES.TIMED_EXPLOSIVE_WITHIN_RADIUS:
			update_status("请选择定时炸药并部署到任务点 128 范围内")
			return false
		if native_completion == LEGACY_MISSION_RULES.TARGET_HIT_POINTS_NONPOSITIVE:
			update_status("该任务点必须由真实爆炸摧毁，不能直接交互完成")
			return false
		var charge_policy := _current_charge_policy()
		var charge_mode := str(charge_policy.get("mode", "preplanted"))
		var quantity_per_target := maxi(
			int(charge_policy.get("quantity_per_target", 1)), 1
		)
		if charge_mode == "inventory_required":
			var inventory_item_id := _charge_policy_item_id(charge_policy)
			if (
				inventory_item_id <= 0
				or _actor_item_quantity_across_squad(inventory_item_id)
					< quantity_per_target
			):
				update_status("该任务点需要 %d 个炸药" % quantity_per_target)
				return false
		elif charge_mode != "preplanted":
			update_status("任务爆破策略无效，无法激活任务点")
			return false
		if mission_runtime == null or not mission_runtime.is_configured():
			return false
		# The mission callback can synchronously start a `next_incomplete`
		# camera, so expose the causal scene before publishing. Rejected events
		# roll this tentative activation back.
		activated_mission_scenes[scene_index] = true
		_publish_mission_event(
			"trigger_activated",
			{"scene_index": scene_index, "display_name": "检测爆炸精灵"},
		)
		if not mission_runtime.last_error.is_empty():
			activated_mission_scenes.erase(scene_index)
			return false
		if charge_mode == "inventory_required":
			var inventory_item_id := _charge_policy_item_id(charge_policy)
			if (
				_consume_actor_item_across_squad(
					inventory_item_id,
					quantity_per_target,
				)
				!= quantity_per_target
			):
				# The preflight count and consumption occur synchronously, so
				# this is an invariant guard rather than a recoverable branch.
				push_error("Actor inventory changed while activating charge scene %d" % scene_index)
		_refresh_inventory_ui()
		_report_direction_action("place_charge")
		var every_charge_placed := true
		for charge_scene: int in _binding_scenes("explosion"):
			if not activated_mission_scenes.has(charge_scene):
				every_charge_placed = false
				break
		if every_charge_placed:
			_report_direction_action("place_all_charges")
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


func _consume_actor_item_across_squad(item_id: int, quantity: int) -> int:
	var remaining := maxi(quantity, 0)
	var consumed := 0
	var ordered_units: Array[SQUAD_UNIT] = []
	for unit: SQUAD_UNIT in selected_units:
		if not ordered_units.has(unit):
			ordered_units.append(unit)
	for unit: SQUAD_UNIT in units:
		if not ordered_units.has(unit):
			ordered_units.append(unit)
	for unit: SQUAD_UNIT in ordered_units:
		if remaining <= 0:
			break
		var removed := unit.remove_ammo_item(item_id, remaining)
		consumed += removed
		remaining -= removed
	return consumed


func _actor_item_quantity_across_squad(item_id: int) -> int:
	var quantity := 0
	for unit: SQUAD_UNIT in units:
		if is_instance_valid(unit):
			quantity += unit.ammo_item_count(item_id)
	return quantity


func _charge_policy_item_id(charge_policy: Dictionary) -> int:
	var explicit_item_id := int(charge_policy.get("inventory_item_id", 0))
	if explicit_item_id > 0:
		return explicit_item_id
	match str(charge_policy.get("inventory_item_key", "explosives")):
		"explosives":
			return 45
	return 0


func _migrate_legacy_field_inventory() -> void:
	# Early Remake saves mirrored DBL 998/990 pickups into a shared dictionary
	# as well as the actor containers. Collapse that duplicate representation
	# after actor snapshots have been restored. If a very early save contains
	# only the shared entry, preserve it by granting it to the selected actor.
	_migrate_legacy_weapon_field_item("explosives", 45)
	_migrate_legacy_backpack_field_item("uniform", 54)


func _migrate_legacy_weapon_field_item(item_key: String, item_id: int) -> void:
	var legacy_quantity := maxi(int(field_inventory.get(item_key, 0)), 0)
	if legacy_quantity <= 0:
		return
	if _actor_item_quantity_across_squad(item_id) > 0:
		field_inventory.erase(item_key)
		return
	var actor := _preferred_inventory_migration_actor()
	if actor == null:
		return
	var attack_type: int = (
		ORIGINAL_INITIAL_WEAPON_INVENTORY.attack_type_for_item_id(item_id)
	)
	var profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(
		attack_type
	)
	var action_key := str(profile.get("action_key", ""))
	var accepted := false
	if not profile.is_empty() and not action_key.is_empty():
		accepted = actor.register_original_inventory_weapon(
			profile,
			_attack_groups_for_unit(actor, action_key),
			legacy_quantity,
			ORIGINAL_INITIAL_WEAPON_INVENTORY.quantity_mode_for_item_id(item_id),
			false,
		)
	if accepted:
		field_inventory.erase(item_key)


func _migrate_legacy_backpack_field_item(item_key: String, item_id: int) -> void:
	var legacy_quantity := maxi(int(field_inventory.get(item_key, 0)), 0)
	if legacy_quantity <= 0:
		return
	for unit: SQUAD_UNIT in units:
		if (
			is_instance_valid(unit)
			and unit.backpack_inventory != null
			and unit.backpack_inventory.item_count(item_id) > 0
		):
			field_inventory.erase(item_key)
			return
	var actor := _preferred_inventory_migration_actor()
	if (
		actor != null
		and actor.add_backpack_item(item_id, legacy_quantity, 0)
			== legacy_quantity
	):
		field_inventory.erase(item_key)


func _preferred_inventory_migration_actor() -> SQUAD_UNIT:
	for unit: SQUAD_UNIT in selected_units:
		if is_instance_valid(unit) and unit.is_alive:
			return unit
	for unit: SQUAD_UNIT in units:
		if is_instance_valid(unit) and unit.is_alive:
			return unit
	return null


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
	if current_mission_state.is_failed():
		return
	update_status("炸药已引爆；前往东南升降机撤离")


func _binding_is_interactive(binding_kind: String) -> bool:
	if binding_kind == "exit":
		return true
	if binding_kind == "explosion":
		# The source-backed cases are invisible runtime predicates: type 98 is
		# either destroyed by an actual blast or observes a nearby type 85.
		# They never complete through the generic E-key hotspot.
		return _current_native_target_rule().is_empty()
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
	_evaluate_native_item_holder_conditions()
	for scene_index: int in _binding_scenes("exit"):
		_evaluate_exit_scene(scene_index)
	_observe_first_ai_zone_approach()
	_evaluate_simultaneous_zone_rule()


func _evaluate_native_item_holder_conditions() -> int:
	if (
		mission_runtime == null
		or not mission_runtime.is_configured()
		or current_mission_state == null
		or current_mission_state.is_failed()
		or current_mission_state.is_victory()
	):
		return 0
	var native_rule := _current_native_mission_rule()
	var raw_holder_rules: Variant = native_rule.get("item_holders", {})
	if not raw_holder_rules is Dictionary or (raw_holder_rules as Dictionary).is_empty():
		return 0
	var raw_role_drops: Variant = current_mission.get("role_drops", {})
	if not raw_role_drops is Dictionary:
		return 0
	var published := 0
	for item_role_value: Variant in (raw_holder_rules as Dictionary).keys():
		var item_role := str(item_role_value)
		var objective: Dictionary = {}
		for raw_objective: Variant in current_mission.get("objectives", []) as Array:
			if not raw_objective is Dictionary:
				continue
			var candidate := raw_objective as Dictionary
			var condition := candidate.get("condition", {}) as Dictionary
			var where := condition.get("where", {}) as Dictionary
			if (
				str(condition.get("event", "")) == "item_acquired"
				and str(where.get("item_role", "")) == item_role
			):
				objective = candidate
				break
		if objective.is_empty():
			continue
		var objective_id := str(objective.get("id", ""))
		if (
			objective_id.is_empty()
			or current_mission_state.is_objective_complete(objective_id)
			or not current_mission_state.dependencies_complete(objective)
		):
			continue
		var source_scene_index := -1
		var item_id := 0
		for role_binding_value: Variant in (raw_role_drops as Dictionary).keys():
			var role_binding := str(role_binding_value)
			var raw_drop: Variant = (raw_role_drops as Dictionary)[role_binding_value]
			if (
				not raw_drop is Dictionary
				or str((raw_drop as Dictionary).get("item_role", "")) != item_role
			):
				continue
			item_id = int((raw_drop as Dictionary).get("original_item_id", 0))
			var scenes := _binding_scenes(role_binding)
			if not scenes.is_empty():
				source_scene_index = scenes[0]
			break
		if item_id <= 0 or source_scene_index < 0:
			continue
		for unit: SQUAD_UNIT in units:
			if (
				not unit.is_alive
				or unit.backpack_inventory == null
				or not LEGACY_MISSION_RULES.item_holder_is_eligible(
					str(current_mission.get("id", "")),
					item_role,
					str(unit.display_name),
				)
				or unit.backpack_inventory.item_count(item_id) <= 0
			):
				continue
			var completed := _publish_mission_event(
				"item_acquired",
				{
					"item_role": item_role,
					"item_id": item_id,
					"original_item_id": item_id,
					"source_scene_index": source_scene_index,
					"collector_name": str(unit.display_name),
				},
			)
			if not mission_runtime.last_error.is_empty():
				break
			if not completed.is_empty() or current_mission_state.is_objective_complete(
				objective_id
			):
				published += 1
			break
	return published


func _observe_first_ai_zone_approach() -> void:
	if (
		mission_ai_coordinator == null
		or str(current_mission.get("id", "")) != "m010"
	):
		return
	var rule := current_mission.get("simultaneous_zone_rule", {}) as Dictionary
	var radius := maxf(float(rule.get("radius_world", 0.0)), 1.0)
	for scene_index: int in _binding_scenes(str(rule.get("binding", "high_ground"))):
		if not world_entities_by_scene.has(scene_index):
			continue
		var entity := world_entities_by_scene[scene_index] as Dictionary
		var zone_position := Vector2(float(entity["x"]), float(entity["y"]))
		for unit: SQUAD_UNIT in units:
			if unit.is_alive and unit.position.distance_to(zone_position) <= radius:
				mission_ai_coordinator.observe_mission_event(
					"zone_approached",
					{"scene_index": scene_index, "zone_role": str(rule.get("zone_role", ""))},
				)
				return


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
	var native_rules: Dictionary = LEGACY_MISSION_RULES.exit_rule_for(
		str(current_mission.get("id", ""))
	)
	var raw_rules: Variant = current_mission.get("exit_party", {})
	var rules: Dictionary = (
		native_rules
		if not native_rules.is_empty()
		else (raw_rules as Dictionary if raw_rules is Dictionary else {})
	)
	var radius_world := float(
		rules.get("radius_world", MISSION_INTERACTION_RADIUS)
	)
	var exclusive_boundary := bool(
		rules.get("exclusive_boundary", false)
	)
	var raw_runtime_types: Variant = rules.get("player_runtime_types", {})
	var player_runtime_types := (
		raw_runtime_types as Dictionary
		if raw_runtime_types is Dictionary
		else {}
	)
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
					and LEGACY_MISSION_RULES.distance_matches(
						unit.position,
						exit_position,
						radius_world,
						exclusive_boundary,
					)
				)
				if found_player and player_runtime_types.has(required_name):
					var allowed_types: Variant = player_runtime_types[required_name]
					found_player = (
						allowed_types is Array
						and (allowed_types as Array).has(unit.runtime_actor_type)
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
			if not LEGACY_MISSION_RULES.distance_matches(
				unit.position,
				exit_position,
				radius_world,
				exclusive_boundary,
			):
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
				and LEGACY_MISSION_RULES.distance_matches(
					escort.position,
					exit_position,
					radius_world,
					exclusive_boundary,
				)
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
		for unit: SQUAD_UNIT in _commandable_player_units():
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
		if not binding_value is Array:
			continue
		# Godot's JSON parser exposes integral JSON numbers as floats in the
		# raw mission dictionary. Normalize before comparing with runtime ints.
		for raw_scene: Variant in binding_value as Array:
			if int(raw_scene) == scene_index:
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


func _play_original_actor_audio(
	family: String,
	actor: Node,
	activation_flag: int = 1,
) -> bool:
	if actor == null:
		return false
	var runtime_actor_type := int(actor.get("runtime_actor_type"))
	var profile: Dictionary = LEGACY_ACTOR_AUDIO_RULES.selector_profile(
		family,
		runtime_actor_type,
		activation_flag,
	)
	if profile.is_empty():
		return false
	var random_value := -1
	if bool(profile.get("random_required", false)):
		var runtime_index_value: Variant = actor.get(
			"original_runtime_index"
		)
		var runtime_index := (
			int(runtime_index_value)
			if runtime_index_value != null
			else -1
		)
		var draw := next_legacy_crt_random(
			int(profile.get("call_site_rva", 0)),
			runtime_index,
		)
		if draw.is_empty():
			return false
		random_value = int(draw.get("value", -1))
	var selection: Dictionary = LEGACY_ACTOR_AUDIO_RULES.select(
		family,
		runtime_actor_type,
		random_value,
		activation_flag,
	)
	if selection.is_empty() or media_director == null:
		return false
	return bool(media_director.play_audio_index(
		int(selection.get("gfl_index", -1)),
		str(selection.get("event_key", "original_actor_voice")),
		"",
		str(selection.get("channel", "voice")),
	))


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
		_draw_selection_marquee()
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
	_draw_selection_marquee()


func _draw_selection_marquee() -> void:
	if not right_dragging:
		return
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var start_world := inverse * right_drag_start_screen
	var current_world := inverse * right_drag_current_screen
	var selection_rect := Rect2(start_world, current_world - start_world).abs()
	draw_rect(selection_rect, Color(0.92, 0.82, 0.28, 0.11), true)
	draw_rect(selection_rect, Color(0.98, 0.88, 0.34, 0.95), false, 1.5)


func _draw_mission_markers() -> void:
	# Imported levels already contain the original marker sprites (for example
	# DBL 1018's red 标注). Large editorial circles obscure those sprites and
	# were never part of the original battlefield presentation.
	if terrain_loaded:
		return
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
