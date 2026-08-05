class_name LevelLoadPipeline
extends RefCounted

## Reads and decodes immutable level data off the main thread.  Scene-tree
## mutation and texture creation remain on the main thread as required by
## Godot.  Starting this before the old level is dismantled overlaps disk I/O
## with deterministic cleanup instead of extending the visible loading pause.

var _thread: Thread
var _running := false


func begin(level_json_path: String, terrain_path: String) -> bool:
	if _running:
		return false
	_thread = Thread.new()
	_running = true
	var error := _thread.start(
		Callable(LevelLoadPipeline, "_read_bundle").bind(
			level_json_path,
			terrain_path,
		)
	)
	if error != OK:
		_running = false
		_thread = null
		return false
	return true


func finish() -> Dictionary:
	if not _running or _thread == null:
		return {}
	var result: Variant = _thread.wait_to_finish()
	_running = false
	_thread = null
	return result as Dictionary if result is Dictionary else {}


static func _read_bundle(
	level_json_path: String,
	terrain_path: String,
) -> Dictionary:
	var result := {
		"level_source": {},
		"terrain_image": null,
		"errors": [],
	}
	if FileAccess.file_exists(level_json_path):
		var level_file := FileAccess.open(level_json_path, FileAccess.READ)
		if level_file != null:
			var parser := JSON.new()
			if parser.parse(level_file.get_as_text()) == OK and parser.data is Dictionary:
				result["level_source"] = (parser.data as Dictionary).duplicate(true)
			else:
				(result["errors"] as Array).append("level JSON is invalid")
			level_file.close()
		else:
			(result["errors"] as Array).append("level JSON cannot be opened")
	else:
		(result["errors"] as Array).append("level JSON is missing")
	if FileAccess.file_exists(terrain_path):
		var image := Image.new()
		var image_error := image.load(terrain_path)
		if image_error == OK and not image.is_empty():
			result["terrain_image"] = image
		else:
			(result["errors"] as Array).append(
				"terrain image cannot be decoded (%d)" % image_error
			)
	else:
		(result["errors"] as Array).append("terrain image is missing")
	return result
