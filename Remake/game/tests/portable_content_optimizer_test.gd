extends SceneTree

const OPTIMIZER: Script = preload("res://tools/portable_content_optimizer.gd")
const IMPORTED_SPRITE_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)

var failure_count := 0


func _initialize() -> void:
	var fixture_root := ProjectSettings.globalize_path(
		"user://portable-content-optimizer-test"
	).simplify_path()
	_remove_tree(fixture_root)
	build_fixture(fixture_root)
	IMPORTED_SPRITE_ANIMATION.clear_manifest_document_cache()
	var terrain_before := Image.new()
	terrain_before.load(fixture_root.path_join("levels/m000/terrain.png"))
	var expected_level_ids: Array[String] = ["m000"]
	var result: Dictionary = OPTIMIZER.optimize_content(
		fixture_root,
		expected_level_ids,
	)
	expect(bool(result.get("ok", false)), "portable optimizer accepts a valid content copy")
	expect(
		int(result.get("terrain_count", 0)) == 1
		and int(result.get("preview_files_removed", 0)) == 1
		and int(result.get("individual_frames_removed", 0)) == 2,
		"portable optimizer reports every transformed fixture payload",
	)
	var terrain_webp_path := fixture_root.path_join("levels/m000/terrain.webp")
	expect(
		FileAccess.file_exists(terrain_webp_path)
		and not FileAccess.file_exists(
			fixture_root.path_join("levels/m000/terrain.png")
		),
		"portable terrain replaces PNG with lossless WebP",
	)
	var terrain_after := Image.new()
	terrain_after.load(terrain_webp_path)
	expect(
		OPTIMIZER._images_are_pixel_identical(terrain_before, terrain_after),
		"portable terrain preserves every RGBA pixel",
	)
	expect(
		FileAccess.get_file_as_string(
			fixture_root.path_join("levels/m000/level.json")
		).contains('"terrain_image": "terrain.webp"'),
		"portable level manifest names the transformed terrain",
	)
	var preview_path := fixture_root.path_join("sprites/0001.png")
	expect(
		not FileAccess.file_exists(preview_path)
		and not FileAccess.file_exists(
			fixture_root.path_join("sprite-frames/0001/g000/f0000.png")
		)
		and not FileAccess.file_exists(
			fixture_root.path_join("sprite-frames/0001/g000/f0001.png")
		)
		and FileAccess.file_exists(
			fixture_root.path_join("sprite-frames/0001/g000/atlas.png")
		),
		"portable sprites retain the atlas and omit byte-identical fallbacks",
	)
	IMPORTED_SPRITE_ANIMATION.clear_manifest_document_cache()
	var reconstructed: Texture2D = (
		IMPORTED_SPRITE_ANIMATION.load_preview_texture(preview_path)
	)
	expect(
		reconstructed != null and reconstructed.get_size() == Vector2(2.0, 2.0),
		"runtime reconstructs a missing standalone preview from atlas frame zero",
	)
	expect(
		not FileAccess.file_exists(fixture_root.path_join("asset-manifest.json"))
		and not FileAccess.file_exists(
			fixture_root.path_join("media-transcode-manifest.json")
		),
		"portable copy omits conversion-only manifests",
	)
	IMPORTED_SPRITE_ANIMATION.clear_manifest_document_cache()
	_remove_tree(fixture_root)
	if failure_count == 0:
		print("Portable content optimization tests passed (8 checks).")
		quit(0)
	else:
		printerr("Portable content optimization tests failed: %d" % failure_count)
		quit(1)


func build_fixture(root: String) -> void:
	for relative_directory: String in [
		"levels/m000",
		"sprite-frames/0001/g000",
		"sprites",
	]:
		var error := DirAccess.make_dir_recursive_absolute(
			root.path_join(relative_directory)
		)
		if error != OK:
			push_error("cannot create fixture directory: %s" % relative_directory)

	var terrain := Image.create_empty(4, 3, false, Image.FORMAT_RGBA8)
	for y: int in range(terrain.get_height()):
		for x: int in range(terrain.get_width()):
			terrain.set_pixel(
				x,
				y,
				Color8(20 + x * 30, 40 + y * 40, 90 + x * 10, 80 + y * 70),
			)
	terrain.save_png(root.path_join("levels/m000/terrain.png"))
	_write_text(
		root.path_join("levels/m000/level.json"),
		'{\n  "terrain_image": "terrain.png"\n}\n',
	)

	var frame_zero := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	frame_zero.fill(Color8(30, 80, 140, 255))
	frame_zero.set_pixel(1, 1, Color8(200, 30, 50, 120))
	var frame_one := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	frame_one.fill(Color8(20, 180, 70, 255))
	var atlas := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	atlas.blit_rect(frame_zero, Rect2i(0, 0, 2, 2), Vector2i(0, 0))
	atlas.blit_rect(frame_one, Rect2i(0, 0, 2, 2), Vector2i(2, 0))
	frame_zero.save_png(root.path_join("sprites/0001.png"))
	frame_zero.save_png(root.path_join("sprite-frames/0001/g000/f0000.png"))
	frame_one.save_png(root.path_join("sprite-frames/0001/g000/f0001.png"))
	atlas.save_png(root.path_join("sprite-frames/0001/g000/atlas.png"))
	_write_text(
		root.path_join("sprite-frames/0001/sprite.json"),
		JSON.stringify(
			{
				"schema_version": 4,
				"groups": [
					{
						"group_index": 0,
						"frame_count": 2,
						"atlas": {
							"relative_path": "g000/atlas.png",
							"width": 4,
							"height": 2,
							"frame_width": 2,
							"frame_height": 2,
							"columns": 2,
							"rows": 1,
						},
						"frames": [
							{
								"frame_index": 0,
								"width": 2,
								"height": 2,
								"relative_path": "g000/f0000.png",
							},
							{
								"frame_index": 1,
								"width": 2,
								"height": 2,
								"relative_path": "g000/f0001.png",
							},
						],
					},
				],
			},
			"  ",
		) + "\n",
	)
	_write_text(root.path_join("asset-manifest.json"), "{}\n")
	_write_text(root.path_join("media-transcode-manifest.json"), "{}\n")


func expect(condition: bool, description: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(description)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write fixture file: %s" % path)
		return
	file.store_string(text)
	file.close()


func _remove_tree(root: String) -> void:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return
	for directory_name: String in DirAccess.get_directories_at(root):
		_remove_tree(root.path_join(directory_name))
	for file_name: String in DirAccess.get_files_at(root):
		DirAccess.remove_absolute(root.path_join(file_name))
	DirAccess.remove_absolute(root)
