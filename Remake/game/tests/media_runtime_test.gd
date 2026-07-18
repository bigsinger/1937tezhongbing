extends SceneTree

const CATALOG_SCRIPT: Script = preload("res://scripts/legacy_media_catalog.gd")
const DIRECTOR_SCRIPT: Script = preload("res://scripts/media_director.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")

var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var missing_root := ProjectSettings.globalize_path("user://missing-legacy-media")
	var catalog: RefCounted = CATALOG_SCRIPT.new()
	expect(bool(catalog.call("configure", missing_root)), "metadata fallback loads without assets", failures)
	expect(not bool(catalog.call("has_generated_catalog")), "generated catalog is optional", failures)

	var briefing: Dictionary = catalog.call("briefing_metadata", "m000")
	expect(int(briefing.get("gfl_index", -1)) == 1048, "m000 briefing map is deterministic", failures)
	expect(str(catalog.call("briefing_path", "m000")).is_empty(), "missing briefing degrades safely", failures)
	var objective: Dictionary = catalog.call("objective_map_metadata", "m011")
	expect(int(objective.get("gfl_index", -1)) == 1025, "m011 objective-map archive order is recovered", failures)
	var ending: Dictionary = catalog.call("ending_metadata", 900)
	expect(int(ending.get("width", 0)) == 800, "nearest ending resolution is selected", failures)
	var bonus: Dictionary = catalog.call("movie_metadata", "bonus_013")
	expect(str(bonus.get("role", "")) == "unreferenced_bonus", "bonus video cannot masquerade as mission story", failures)
	expect(str(catalog.call("movie_path", "historical_intro")).is_empty(), "missing transcode is non-fatal", failures)

	var pistol: Array[int] = catalog.call("sound_indices", "attack_pistol", "")
	expect(pistol == [1363, 1364, 1365, 1366], "pistol variants map to four recovered WAV indices", failures)
	var dainiu: Array[int] = catalog.call("sound_indices", "acknowledge", "daniu")
	expect(dainiu.size() == 6 and dainiu[0] == 1281, "actor acknowledgement variants are mapped", failures)
	expect(int(catalog.call("select_sound_index", "attack_pistol", "", 5)) == 1364, "variant choice is deterministic", failures)
	expect(str(catalog.call("sound_path", 1363)).is_empty(), "missing WAV degrades safely", failures)

	var valid_lines := [
		{"speaker": "测试", "text": "文本对白在没有原版音频时仍可显示。", "auto_advance": false}
	]
	expect(CATALOG_SCRIPT.validate_dialogue_lines(valid_lines).is_empty(), "text-only dialogue schema validates", failures)
	expect(
		CATALOG_SCRIPT.validate_dialogue_lines([{"speaker": "测试", "text": ""}]).size() == 1,
		"empty dialogue text is rejected",
		failures
	)

	var director: CanvasLayer = DIRECTOR_SCRIPT.new()
	root.add_child(director)
	await process_frame
	expect(bool(director.call("configure", missing_root)), "media director configures without original assets", failures)
	expect(
		director.sfx_players.size() == DIRECTOR_SCRIPT.SFX_POOL_SIZE
		and director.sfx_players.size() == 8,
		"media director creates one fixed eight-player SFX pool",
		failures,
	)
	expect(
		director.music_player != null
		and director.music_player.bus == "Music"
		and director.video_player.bus == "Music",
		"music and movie soundtrack players consume the Music bus",
		failures,
	)
	var audio_node_count := _audio_player_child_count(director)
	director.call("_ensure_nodes")
	expect(
		audio_node_count == 10 and _audio_player_child_count(director) == 10,
		"one music, one voice, and eight SFX channels stay bounded after repeated initialization",
		failures,
	)
	var synthetic_audio_load_calls := [0]
	director.set_audio_stream_loader(func(_path: String) -> AudioStreamWAV:
		synthetic_audio_load_calls[0] += 1
		return AudioStreamWAV.new()
	)
	var cached_stream_a: AudioStreamWAV = director.call(
		"_load_cached_audio_stream",
		"user://media-cache-fixture/../media-cache-fixture/repeated.wav",
	)
	var cached_stream_b: AudioStreamWAV = director.call(
		"_load_cached_audio_stream",
		"user://media-cache-fixture/repeated.wav",
	)
	director.call("close_for_state_change")
	var cached_stream_after_state_change: AudioStreamWAV = director.call(
		"_load_cached_audio_stream",
		"user://media-cache-fixture/repeated.wav",
	)
	expect(
		cached_stream_a != null
		and cached_stream_a == cached_stream_b
		and cached_stream_b == cached_stream_after_state_change
		and int(synthetic_audio_load_calls[0]) == 1
		and director.audio_stream_load_count() == 1
		and director.audio_stream_cache_size() == 1,
		"normalized repeated audio requests load once and survive state changes",
		failures,
	)
	expect(
		director.call("_load_cached_audio_stream", "") == null
		and director.audio_stream_load_count() == 1,
		"an invalid empty audio path is rejected without invoking the loader",
		failures,
	)
	director.set_audio_stream_loader(Callable())
	expect(
		director.call(
			"_load_cached_audio_stream",
			"user://definitely-missing-media-cache-fixture.wav",
		) == null
		and director.audio_stream_load_count() == 0,
		"a missing audio file is rejected safely before invoking the native loader",
		failures,
	)
	expect(
		DIRECTOR_SCRIPT.audio_channel_for("dialogue") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE
		and DIRECTOR_SCRIPT.audio_channel_for("acknowledge") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE
		and DIRECTOR_SCRIPT.audio_channel_for("direct", {"category": "voice"})
		== DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE,
		"dialogue, fallback voice events, and recovered voice metadata use the voice channel",
		failures,
	)
	expect(
		DIRECTOR_SCRIPT.audio_channel_for("attack_pistol") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX
		and DIRECTOR_SCRIPT.audio_channel_for("explosion") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX
		and DIRECTOR_SCRIPT.audio_channel_for("ui_confirm") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX,
		"weapon, explosion, and UI events route to the overlapping SFX pool",
		failures,
	)
	expect(
		DIRECTOR_SCRIPT.audio_channel_for("rain", {"category": "ambience"})
		== DIRECTOR_SCRIPT.AUDIO_CHANNEL_MUSIC
		and DIRECTOR_SCRIPT.audio_channel_for("direct", {"category": "music"})
		== DIRECTOR_SCRIPT.AUDIO_CHANNEL_MUSIC
		and DIRECTOR_SCRIPT.resolve_audio_channel(
			DIRECTOR_SCRIPT.AUDIO_CHANNEL_MUSIC,
			"attack_pistol",
			{"category": "effect"},
		) == DIRECTOR_SCRIPT.AUDIO_CHANNEL_MUSIC,
		"music metadata, ambience metadata, and an explicit music override use the Music channel",
		failures,
	)
	expect(
		DIRECTOR_SCRIPT.resolve_audio_channel(
			DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE,
			"attack_pistol",
		) == DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE
		and DIRECTOR_SCRIPT.resolve_audio_channel(
			DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX,
			"dialogue",
		) == DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX,
		"valid voice and SFX overrides retain their existing behavior",
		failures,
	)
	expect(
		DIRECTOR_SCRIPT.audio_channel_for("alert") == DIRECTOR_SCRIPT.AUDIO_CHANNEL_SFX
		and DIRECTOR_SCRIPT.audio_channel_for("alert", {}, "japanese_soldier")
		== DIRECTOR_SCRIPT.AUDIO_CHANNEL_VOICE,
		"fallback alert routing distinguishes the alarm from an actor shout",
		failures,
	)
	var partially_busy: Array[bool] = [true, true, false, true, true, true, true, true]
	var available_selection: Dictionary = DIRECTOR_SCRIPT.select_sfx_slot(partially_busy, 0)
	expect(
		int(available_selection["slot"]) == 2
		and int(available_selection["next_cursor"]) == 3,
		"SFX allocation deterministically finds the next available round-robin slot",
		failures,
	)
	var all_busy: Array[bool] = [true, true, true, true, true, true, true, true]
	var saturated_selection: Dictionary = DIRECTOR_SCRIPT.select_sfx_slot(all_busy, 7)
	expect(
		int(saturated_selection["slot"]) == 7
		and int(saturated_selection["next_cursor"]) == 0,
		"a saturated SFX pool deterministically steals one bounded slot",
		failures,
	)
	var unavailable_count := [0]
	director.media_unavailable.connect(func(_kind: String, _id: String) -> void: unavailable_count[0] += 1)
	var initial_process_mode: int = director.process_mode
	expect(not paused, "media test starts with an unpaused SceneTree", failures)
	director.call("show_briefing", "m000", "Escape fixture", "release to close")
	var cancel_press := InputEventAction.new()
	cancel_press.action = "ui_cancel"
	cancel_press.pressed = true
	director.call("_unhandled_input", cancel_press)
	expect(
		not director.active_briefing.is_empty() and paused,
		"Escape press is consumed without closing an original-style media modal",
		failures,
	)
	var cancel_release := InputEventAction.new()
	cancel_release.action = "ui_cancel"
	cancel_release.pressed = false
	director.call("_unhandled_input", cancel_release)
	expect(
		director.active_briefing.is_empty() and not paused,
		"Escape release closes the media modal and restores gameplay",
		failures,
	)
	var remapped_controls: Dictionary = GAME_INPUT_BINDINGS.default_bindings()
	remapped_controls["pause"] = {
		"keycode": KEY_Z,
		"ctrl": false,
		"alt": false,
		"shift": false,
		"meta": false,
	}
	director.set_input_bindings(remapped_controls)
	director.call("show_briefing", "m000", "Remap fixture", "Z release to close")
	var old_escape_release := InputEventKey.new()
	old_escape_release.keycode = KEY_ESCAPE
	old_escape_release.pressed = false
	director.call("_unhandled_input", old_escape_release)
	expect(
		not director.active_briefing.is_empty() and paused,
		"the old Escape key no longer closes media after pause is remapped",
		failures,
	)
	var remapped_pause_press := InputEventKey.new()
	remapped_pause_press.keycode = KEY_Z
	remapped_pause_press.pressed = true
	director.call("_unhandled_input", remapped_pause_press)
	var remapped_pause_release := InputEventKey.new()
	remapped_pause_release.keycode = KEY_Z
	remapped_pause_release.pressed = false
	director.call("_unhandled_input", remapped_pause_release)
	expect(
		director.active_briefing.is_empty() and not paused,
		"media cancel follows the remapped pause key and original release cadence",
		failures,
	)
	director.set_input_bindings(GAME_INPUT_BINDINGS.default_bindings())
	director.call("show_briefing", "m001", "State change fixture", "must close")
	director.call("close_for_state_change")
	expect(
		not director.is_modal_active()
		and not director.overlay.visible
		and not paused
		and not director.audio_player.playing
		and not director.music_player.playing,
		"loading, restarting, or switching levels atomically closes old media and releases pause",
		failures,
	)
	expect(not bool(director.call("show_briefing", "m000", "测试简报", "文本降级")), "briefing reports missing image", failures)
	expect(director.overlay.visible, "briefing text fallback remains visible", failures)
	expect(director.fallback_label.text.contains("文本降级"), "briefing fallback explains missing local media", failures)
	expect(
		paused and director.process_mode == Node.PROCESS_MODE_WHEN_PAUSED,
		"an open briefing pauses gameplay while the media director keeps processing",
		failures,
	)
	director.call("dismiss_briefing")
	expect(not director.overlay.visible, "briefing fallback can be dismissed", failures)
	expect(
		not paused and director.process_mode == initial_process_mode,
		"closing the last briefing restores the prior pause and process modes",
		failures,
	)

	director.call("show_briefing", "m000", "测试简报", "嵌套切换")
	expect(bool(director.call("start_dialogue", "synthetic", valid_lines)), "text-only dialogue starts", failures)
	expect(
		director.dialogue_line_index == 0
		and director.active_briefing.is_empty()
		and paused,
		"switching from briefing to dialogue keeps one uninterrupted modal pause",
		failures,
	)
	director.call("show_ending", 900, "测试结局")
	expect(
		director.dialogue_sequence_id.is_empty()
		and director.active_ending
		and paused,
		"switching from dialogue to ending preserves the original pause session",
		failures,
	)
	director.call("dismiss_ending")
	expect(
		not paused and director.process_mode == initial_process_mode,
		"closing a nested modal sequence restores its unpaused baseline",
		failures,
	)

	paused = true
	director.call("show_briefing", "m000", "测试简报", "外部暂停")
	director.call("dismiss_briefing")
	expect(paused, "a modal opened during an external pause restores the paused baseline", failures)
	paused = false

	expect(bool(director.call("start_dialogue", "synthetic", valid_lines)), "standalone dialogue starts", failures)
	expect(director.dialogue_line_index == 0, "first dialogue line is active", failures)
	director.call("advance_dialogue")
	expect(
		director.dialogue_sequence_id.is_empty() and not paused,
		"manual dialogue completion closes the sequence and restores gameplay",
		failures,
	)
	var auto_lines := [
		{"speaker": "测试", "text": "SFX 不应阻塞对白自动推进。", "auto_advance": true}
	]
	expect(bool(director.call("start_dialogue", "sfx-does-not-block", auto_lines)), "auto dialogue fixture starts", failures)
	director.dialogue_minimum_seconds = 0.0
	var sfx_independent_ready: bool = DIRECTOR_SCRIPT.dialogue_ready_to_auto_advance(
		true, 0.0, false
	)
	director.call("_process", 0.0)
	expect(
		sfx_independent_ready and director.dialogue_sequence_id.is_empty(),
		"dialogue auto-advance ignores an active SFX channel",
		failures,
	)
	expect(bool(director.call("start_dialogue", "voice-blocks", auto_lines)), "voice-blocking dialogue fixture starts", failures)
	director.dialogue_minimum_seconds = 0.0
	expect(
		not DIRECTOR_SCRIPT.dialogue_ready_to_auto_advance(true, 0.0, true)
		and director.dialogue_sequence_id == "voice-blocks",
		"dialogue auto-advance waits for the dedicated voice channel",
		failures,
	)
	director.call("_process", 0.0)
	expect(
		director.dialogue_sequence_id.is_empty() and not paused,
		"dialogue advances once the dedicated voice channel stops",
		failures,
	)
	expect(not bool(director.call("play_audio_event", "attack_pistol")), "missing audio returns false instead of crashing", failures)
	expect(int(unavailable_count[0]) >= 2, "missing media signals are observable", failures)
	director.call("show_briefing", "m000", "测试简报", "退出树恢复")
	expect(paused, "final exit-tree fixture owns a modal pause", failures)
	root.remove_child(director)
	expect(not paused, "exiting the tree restores a media-owned pause", failures)
	director.free()
	await process_frame

	if failures.is_empty():
		print("Media catalog and fallback runtime tests passed (%d checks). No original media was used." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _audio_player_child_count(parent: Node) -> int:
	var result := 0
	for child: Node in parent.get_children():
		if child is AudioStreamPlayer:
			result += 1
	return result
