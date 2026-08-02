extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
const ORIGINAL_INVENTORY_ACTOR_BY_LEVEL := {
	"m000": "强子",
	"m001": "强子",
	"m002": "老赵",
	"m003": "古明",
	"m004": "大牛",
	"m005": "强子",
	"m006": "强子",
	"m007": "老赵",
	"m008": "大牛",
	"m009": "强子",
	"m010": "强子",
	"m011": "强子",
}

var output_path := ""
var metadata_path := ""
var level_id := "m000"
var camera_left := 0
var camera_top := 0
var expected_width := 1024
var expected_height := 768
var world_only := true
var overlay := "none"


func _init() -> void:
	_parse_arguments(OS.get_cmdline_user_args())
	call_deferred("_run_probe")


func _run_probe() -> void:
	var failures: Array[String] = []
	if output_path.is_empty():
		failures.append("--output=PATH is required")
	if not level_id in FORMAL_LEVEL_IDS:
		failures.append("unsupported level id: %s" % level_id)
	if overlay not in ["none", "weapons", "items", "minimap", "help", "pause"]:
		failures.append("unsupported overlay: %s" % overlay)
	if not failures.is_empty():
		_finish(failures, Vector2.ZERO, Vector2i.ZERO, 0, 0)
		return

	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(expected_width, expected_height))
	DisplayServer.window_set_position(Vector2i(3000, 100))
	root.content_scale_size = Vector2i(expected_width, expected_height)
	await process_frame
	await process_frame

	var requested_index := FORMAL_LEVEL_IDS.find(level_id)
	# Reload even when _ready() already selected this level. The product path
	# may have started its authored camera sequence; parity capture needs the
	# stable MOD camera origin, not a director tween racing the probe.
	main.switch_level(requested_index, false, false)
	await process_frame
	if str(main.current_mission.get("id", "")) != level_id:
		failures.append("requested level did not load")
	if not bool(main.terrain_loaded):
		failures.append("terrain did not load")
	if main.level_camera == null:
		failures.append("level camera is missing")

	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	if main.media_director != null:
		main.media_director.close_for_state_change()
	if overlay != "none":
		world_only = false
		if overlay in ["weapons", "items"]:
			main._on_original_hud_actor_requested(
				str(ORIGINAL_INVENTORY_ACTOR_BY_LEVEL[level_id])
			)
		match overlay:
			"weapons":
				main._open_inventory("weapons")
			"items":
				main._open_inventory("items")
			"minimap":
				main._open_tactical_map()
			"help":
				main._open_control_guide()
			"pause":
				main._open_pause_menu()
		paused = false
	# Stop the product controller's per-frame camera clamp. It uses the full
	# 768-pixel modern viewport, while the original clamps against its
	# 708-pixel map viewport above the toolbar.
	main.set_process(false)
	main.set_physics_process(false)
	if world_only:
		main.clear_selection()
		for child: Node in main.get_children():
			if child is CanvasLayer:
				(child as CanvasLayer).visible = false

	var camera_position := Vector2.ZERO
	if main.level_camera != null:
		main.level_camera.position_smoothing_enabled = false
		main.level_camera.zoom = Vector2.ONE
		# The stable MOD metadata supplies the already-clamped original camera
		# origin. Keep that exact origin even near the lower map edge, where the
		# original 708-pixel playfield and this 768-pixel capture surface have
		# different native clamp centers.
		main.level_camera.limit_left = -100000
		main.level_camera.limit_top = -100000
		main.level_camera.limit_right = 100000
		main.level_camera.limit_bottom = 100000
		camera_position = Vector2(
			float(camera_left) + float(expected_width) * 0.5,
			float(camera_top) + float(expected_height) * 0.5,
		)
		main.level_camera.position = camera_position
		main.level_camera.force_update_scroll()
		camera_position = main.level_camera.position

	for _frame_index: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

	var viewport_size := root.size
	if viewport_size != Vector2i(expected_width, expected_height):
		failures.append(
			"viewport is %s, expected %dx%d"
			% [viewport_size, expected_width, expected_height]
		)
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("rendered viewport image is empty")
	else:
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var save_error := image.save_png(output_path)
		if save_error != OK:
			failures.append("could not save viewport image: %d" % save_error)

	_finish(
		failures,
		camera_position,
		viewport_size,
		int(main.imported_entity_count),
		int(main.playable_entities.size()),
	)


func _finish(
	failures: Array[String],
	camera_position: Vector2,
	viewport_size: Vector2i,
	imported_entity_count: int,
	playable_entity_count: int,
) -> void:
	if metadata_path.is_empty() and not output_path.is_empty():
		metadata_path = output_path.get_basename() + ".json"
	if not metadata_path.is_empty():
		DirAccess.make_dir_recursive_absolute(metadata_path.get_base_dir())
		var metadata := {
			"schema_version": 1,
			"runtime": "remake",
			"level_id": level_id,
			"camera_left": camera_left,
			"camera_top": camera_top,
			"camera_center": [camera_position.x, camera_position.y],
			"viewport": [viewport_size.x, viewport_size.y],
			"imported_entity_count": imported_entity_count,
			"playable_entity_count": playable_entity_count,
			"output": output_path,
			"world_only": world_only,
			"overlay": overlay,
			"failures": failures,
			"passed": failures.is_empty(),
		}
		var file := FileAccess.open(metadata_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(metadata, "\t") + "\n")
	if failures.is_empty():
		print(
			"Visual parity probe passed: %s camera=(%d,%d)"
			% [level_id, camera_left, camera_top]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _parse_arguments(arguments: PackedStringArray) -> void:
	for argument: String in arguments:
		if argument.begins_with("--output="):
			output_path = ProjectSettings.globalize_path(
				argument.trim_prefix("--output=")
			)
		elif argument.begins_with("--metadata="):
			metadata_path = ProjectSettings.globalize_path(
				argument.trim_prefix("--metadata=")
			)
		elif argument.begins_with("--level-id="):
			level_id = argument.trim_prefix("--level-id=").to_lower()
		elif argument.begins_with("--camera-left="):
			camera_left = int(argument.trim_prefix("--camera-left="))
		elif argument.begins_with("--camera-top="):
			camera_top = int(argument.trim_prefix("--camera-top="))
		elif argument.begins_with("--viewport-width="):
			expected_width = int(argument.trim_prefix("--viewport-width="))
		elif argument.begins_with("--viewport-height="):
			expected_height = int(argument.trim_prefix("--viewport-height="))
		elif argument == "--include-ui":
			world_only = false
		elif argument.begins_with("--overlay="):
			overlay = argument.trim_prefix("--overlay=").to_lower()
