extends SceneTree

const CATALOG_SCRIPT: Script = preload("res://scripts/legacy_media_catalog.gd")

var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var catalog: RefCounted = CATALOG_SCRIPT.new()
	expect(bool(catalog.call("configure")), "media fallback map loads", failures)
	expect(bool(catalog.call("has_generated_catalog")), "generated local media catalog loads", failures)

	for level_index: int in range(12):
		var level_id := "m%03d" % level_index
		var briefing_path := str(catalog.call("briefing_path", level_id))
		expect(not briefing_path.is_empty(), "%s briefing image exists" % level_id, failures)
		expect(not Image.load_from_file(briefing_path).is_empty(), "%s briefing image decodes" % level_id, failures)
		var map_path := str(catalog.call("objective_map_path", level_id))
		expect(not map_path.is_empty(), "%s objective map exists" % level_id, failures)
		expect(not Image.load_from_file(map_path).is_empty(), "%s objective map decodes" % level_id, failures)

	var generated: Dictionary = catalog.get("generated_catalog")
	var cues := generated.get("audio_cues", []) as Array
	expect(cues.size() == 128, "all 128 GFL WAV cues are catalogued", failures)
	var slf_count := 0
	var gfl_only_count := 0
	for value: Variant in cues:
		var cue := value as Dictionary
		var index := int(cue.get("gfl_index", -1))
		var path := str(catalog.call("sound_path", index))
		expect(not path.is_empty(), "audio %d exists" % index, failures)
		expect(AudioStreamWAV.load_from_file(path) != null, "audio %d decodes" % index, failures)
		match str(cue.get("source_status", "")):
			"slf":
				slf_count += 1
			"gfl_only":
				gfl_only_count += 1
	expect(slf_count == 126, "126 WAV names are declared by SLF", failures)
	expect(gfl_only_count == 2, "two fire transition WAVs are GFL-only", failures)

	var logo_path := str(catalog.call("movie_path", "logo"))
	if not logo_path.is_empty():
		var stream := VideoStreamTheora.new()
		stream.set("file", logo_path)
		var video_player := VideoStreamPlayer.new()
		root.add_child(video_player)
		video_player.stream = stream
		video_player.play()
		await process_frame
		expect(video_player.is_playing(), "optional transcoded logo starts in Godot", failures)
		video_player.stop()
		video_player.queue_free()
		await process_frame

	if failures.is_empty():
		print("Real local media audit passed (%d checks): 12 briefings, 12 maps, 128 WAV cues." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
