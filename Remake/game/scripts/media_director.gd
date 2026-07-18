extends CanvasLayer

signal media_unavailable(kind: String, media_id: String)
signal audio_started(gfl_index: int, event_key: String)
signal audio_finished(gfl_index: int)
signal briefing_opened(level_id: String, used_original_image: bool)
signal briefing_closed(level_id: String)
signal movie_started(movie_id: String)
signal movie_finished(movie_id: String, skipped: bool)
signal dialogue_line_changed(sequence_id: String, line_index: int, line: Dictionary)
signal dialogue_finished(sequence_id: String, skipped: bool)
signal ending_closed

const CATALOG_SCRIPT: Script = preload("res://scripts/legacy_media_catalog.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const SFX_POOL_SIZE := 8
const AUDIO_CHANNEL_MUSIC := "music"
const AUDIO_CHANNEL_VOICE := "voice"
const AUDIO_CHANNEL_SFX := "sfx"
const FALLBACK_VOICE_EVENTS := {
	"acknowledge": true,
	"battle_cry": true,
	"challenge_attack": true,
	"challenge_chase": true,
	"challenge_stop": true,
	"death": true,
	"investigate": true,
	"selected": true,
	"threat_shoot": true,
}

var catalog: RefCounted
# The original public name is retained for compatibility.  It is now the
# exclusive voice/dialogue channel; short world sounds use the fixed pool.
var audio_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var video_player: VideoStreamPlayer
var overlay: ColorRect
var image_view: TextureRect
var fallback_label: Label
var help_label: Label
var subtitle_panel: ColorRect
var subtitle_label: Label

var active_briefing := ""
var active_movie := ""
var active_ending := false
var active_audio_index := -1
var active_music_index := -1
var _sfx_active_indices: Array[int] = []
var _sfx_cursor := 0
var subtitle_seconds := 0.0
var dialogue_sequence_id := ""
var dialogue_lines: Array = []
var dialogue_line_index := -1
var dialogue_minimum_seconds := 0.0
var subtitles_enabled := true
var _modal_pause_owned := false
var _pause_state_before_modal := false
var _process_mode_before_modal := Node.PROCESS_MODE_INHERIT
var _modal_transition_depth := 0
var _audio_stream_cache: Dictionary = {}
var _audio_stream_loader_override: Callable = Callable()
var _audio_stream_load_count := 0
var input_bindings: Dictionary = GAME_INPUT_BINDINGS.default_bindings()


func _ready() -> void:
	layer = 100
	_ensure_nodes()
	if catalog == null:
		configure()


func configure(converted_root: String = "") -> bool:
	catalog = CATALOG_SCRIPT.new()
	return bool(catalog.call("configure", converted_root))


func set_subtitles_enabled(enabled: bool) -> void:
	subtitles_enabled = enabled
	if not subtitles_enabled and subtitle_panel != null:
		subtitle_panel.visible = false
		subtitle_seconds = 0.0


func set_input_bindings(bindings: Dictionary) -> void:
	input_bindings = GAME_INPUT_BINDINGS.normalize_bindings(bindings)


func is_modal_active() -> bool:
	return _has_active_modal()


func close_for_state_change() -> void:
	# Level replacement/load must not let an old modal keep the new world paused
	# or allow its completion signals to enqueue content from the previous level.
	_modal_transition_depth = 0
	if video_player != null:
		video_player.stop()
		video_player.visible = false
	if audio_player != null:
		audio_player.stop()
	if music_player != null:
		music_player.stop()
	for player: AudioStreamPlayer in sfx_players:
		player.stop()
	active_briefing = ""
	active_movie = ""
	active_ending = false
	active_audio_index = -1
	active_music_index = -1
	for index: int in range(_sfx_active_indices.size()):
		_sfx_active_indices[index] = -1
	dialogue_sequence_id = ""
	dialogue_lines.clear()
	dialogue_line_index = -1
	dialogue_minimum_seconds = 0.0
	subtitle_seconds = 0.0
	if overlay != null:
		overlay.visible = false
	if subtitle_panel != null:
		subtitle_panel.visible = false
	_release_modal_pause()


func play_audio_event(
	event_key: String,
	actor_key: String = "",
	variant_seed: int = 0,
	caption_override: String = "",
	channel_override: String = "",
) -> bool:
	_ensure_catalog()
	var index := int(catalog.call("select_sound_index", event_key, actor_key, variant_seed))
	if index < 0:
		media_unavailable.emit("audio_event", event_key + ":" + actor_key)
		return false
	return _play_audio_index(
		index, event_key, caption_override, actor_key, channel_override
	)


func play_audio_index(
	gfl_index: int,
	event_key: String = "direct",
	caption_override: String = "",
	channel_override: String = "",
) -> bool:
	return _play_audio_index(
		gfl_index, event_key, caption_override, "", channel_override
	)


func _play_audio_index(
	gfl_index: int,
	event_key: String,
	caption_override: String,
	actor_key: String,
	channel_override: String,
) -> bool:
	_ensure_nodes()
	_ensure_catalog()
	var path := str(catalog.call("sound_path", gfl_index))
	if path.is_empty():
		media_unavailable.emit("audio", str(gfl_index))
		return false
	var stream := _load_cached_audio_stream(path)
	if stream == null:
		media_unavailable.emit("audio", str(gfl_index))
		return false
	var metadata: Dictionary = catalog.call("sound_metadata", gfl_index)
	var channel := resolve_audio_channel(
		channel_override, event_key, metadata, actor_key
	)
	if channel == AUDIO_CHANNEL_VOICE:
		audio_player.stream = stream
		active_audio_index = gfl_index
		audio_player.play()
	elif channel == AUDIO_CHANNEL_MUSIC:
		music_player.stop()
		music_player.stream = stream
		active_music_index = gfl_index
		music_player.play()
	else:
		var slot := _acquire_sfx_slot()
		if slot < 0:
			return false
		var sfx_player := sfx_players[slot]
		sfx_player.stop()
		sfx_player.stream = stream
		_sfx_active_indices[slot] = gfl_index
		sfx_player.play()
	var caption := caption_override
	if caption.is_empty():
		if str(metadata.get("category", "")) == "voice":
			caption = str(metadata.get("caption", ""))
	if not caption.is_empty() and dialogue_sequence_id.is_empty():
		_show_subtitle(caption, maxf(1.2, float(caption.length()) * 0.12))
	audio_started.emit(gfl_index, event_key)
	return true


func show_briefing(
	level_id: String,
	fallback_title: String = "任务简报",
	fallback_body: String = "本地尚未导入原版任务简报图。任务目标仍可正常进行。"
) -> bool:
	_ensure_nodes()
	_ensure_catalog()
	_begin_modal_transition()
	stop_movie(true)
	stop_dialogue(true)
	active_ending = false
	active_briefing = level_id
	overlay.visible = true
	help_label.text = "Enter / Space 继续    Esc 跳过"
	var path := str(catalog.call("briefing_path", level_id))
	var used_original := _load_external_image(path)
	if used_original:
		fallback_label.text = ""
		fallback_label.visible = false
	else:
		image_view.texture = null
		fallback_label.text = "%s\n\n%s" % [fallback_title, fallback_body]
		fallback_label.visible = true
		media_unavailable.emit("briefing", level_id)
	_end_modal_transition()
	briefing_opened.emit(level_id, used_original)
	return used_original


func dismiss_briefing() -> void:
	if active_briefing.is_empty():
		return
	var closed := active_briefing
	active_briefing = ""
	if active_movie.is_empty() and dialogue_sequence_id.is_empty():
		overlay.visible = false
	_sync_modal_pause()
	briefing_closed.emit(closed)


func show_ending(target_width: int, fallback_text: String = "任务完成") -> bool:
	_ensure_nodes()
	_ensure_catalog()
	_begin_modal_transition()
	stop_movie(true)
	stop_dialogue(true)
	active_briefing = ""
	active_ending = true
	overlay.visible = true
	help_label.text = "Enter / Space 继续    Esc 跳过"
	var path := str(catalog.call("ending_path", target_width))
	var used_original := _load_external_image(path)
	fallback_label.visible = not used_original
	fallback_label.text = fallback_text if not used_original else ""
	if not used_original:
		media_unavailable.emit("ending", str(target_width))
	_end_modal_transition()
	return used_original


func dismiss_ending() -> void:
	if not active_ending:
		return
	active_ending = false
	if active_movie.is_empty() and active_briefing.is_empty() and dialogue_sequence_id.is_empty():
		overlay.visible = false
	_sync_modal_pause()
	ending_closed.emit()


func play_movie(movie_id: String) -> bool:
	_ensure_nodes()
	_ensure_catalog()
	_begin_modal_transition()
	stop_dialogue(true)
	var path := str(catalog.call("movie_path", movie_id))
	if path.is_empty():
		media_unavailable.emit("movie", movie_id)
		_end_modal_transition()
		return false
	var stream := VideoStreamTheora.new()
	stream.set("file", path)
	video_player.stream = stream
	active_movie = movie_id
	active_briefing = ""
	active_ending = false
	image_view.visible = false
	fallback_label.visible = false
	help_label.text = "Enter / Space / Esc 跳过"
	overlay.visible = true
	video_player.visible = true
	video_player.play()
	_end_modal_transition()
	movie_started.emit(movie_id)
	return true


func stop_movie(skipped: bool = true) -> void:
	if active_movie.is_empty():
		return
	var stopped := active_movie
	active_movie = ""
	video_player.stop()
	video_player.visible = false
	image_view.visible = true
	if active_briefing.is_empty() and dialogue_sequence_id.is_empty() and not active_ending:
		overlay.visible = false
	_sync_modal_pause()
	movie_finished.emit(stopped, skipped)


func start_dialogue(sequence_id: String, lines: Array) -> bool:
	_ensure_nodes()
	_ensure_catalog()
	var errors: PackedStringArray = CATALOG_SCRIPT.validate_dialogue_lines(lines)
	if not errors.is_empty() or lines.is_empty():
		media_unavailable.emit("dialogue", sequence_id)
		return false
	_begin_modal_transition()
	stop_movie(true)
	stop_dialogue(true)
	active_briefing = ""
	active_ending = false
	dialogue_sequence_id = sequence_id
	dialogue_lines = lines.duplicate(true)
	dialogue_line_index = -1
	overlay.visible = true
	image_view.visible = false
	fallback_label.visible = true
	help_label.text = "Enter / Space 下一句    Esc 跳过"
	_end_modal_transition()
	_advance_dialogue_internal()
	return true


func advance_dialogue() -> void:
	if dialogue_sequence_id.is_empty() or dialogue_minimum_seconds > 0.0:
		return
	_advance_dialogue_internal()


func stop_dialogue(skipped: bool = true) -> void:
	if dialogue_sequence_id.is_empty():
		return
	var stopped := dialogue_sequence_id
	dialogue_sequence_id = ""
	dialogue_lines.clear()
	dialogue_line_index = -1
	dialogue_minimum_seconds = 0.0
	fallback_label.text = ""
	if active_movie.is_empty() and active_briefing.is_empty() and not active_ending:
		overlay.visible = false
	_sync_modal_pause()
	dialogue_finished.emit(stopped, skipped)


func _exit_tree() -> void:
	_modal_transition_depth = 0
	_release_modal_pause()


func _process(delta: float) -> void:
	if subtitle_seconds > 0.0:
		subtitle_seconds = maxf(0.0, subtitle_seconds - delta)
		if subtitle_seconds <= 0.0 and dialogue_sequence_id.is_empty():
			subtitle_panel.visible = false
	if dialogue_minimum_seconds > 0.0:
		dialogue_minimum_seconds = maxf(0.0, dialogue_minimum_seconds - delta)
	if not dialogue_sequence_id.is_empty() and dialogue_line_index >= 0:
		var line := dialogue_lines[dialogue_line_index] as Dictionary
		if dialogue_ready_to_auto_advance(
			bool(line.get("auto_advance", false)),
			dialogue_minimum_seconds,
			audio_player.playing,
		):
			_advance_dialogue_internal()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var is_cancel := false
	if event is InputEventKey:
		var pause_binding := input_bindings.get("pause", {}) as Dictionary
		is_cancel = GAME_INPUT_BINDINGS.event_matches(event as InputEventKey, pause_binding)
	else:
		# Keep controller/UI-action accessibility while keyboard Escape follows
		# the same user-remappable pause command used by the game shell.
		is_cancel = event.is_action("ui_cancel")
	# The original commits Escape actions on key release. Consume the press
	# while a media modal is open so the same key cycle cannot reach the menu.
	if is_cancel and event.is_pressed():
		if _has_active_modal():
			get_viewport().set_input_as_handled()
		return
	if not is_cancel and not event.is_pressed():
		return
	var handled := false
	if is_cancel:
		if not active_movie.is_empty():
			stop_movie(true)
			handled = true
		elif not dialogue_sequence_id.is_empty():
			stop_dialogue(true)
			handled = true
		elif not active_briefing.is_empty():
			dismiss_briefing()
			handled = true
		elif active_ending:
			dismiss_ending()
			handled = true
	elif event.is_action("ui_accept"):
		if not active_movie.is_empty():
			stop_movie(true)
			handled = true
		elif not dialogue_sequence_id.is_empty():
			advance_dialogue()
			handled = true
		elif not active_briefing.is_empty():
			dismiss_briefing()
			handled = true
		elif active_ending:
			dismiss_ending()
			handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _advance_dialogue_internal() -> void:
	dialogue_line_index += 1
	if dialogue_line_index >= dialogue_lines.size():
		stop_dialogue(false)
		return
	var line := dialogue_lines[dialogue_line_index] as Dictionary
	var speaker := str(line.get("speaker", ""))
	var text := str(line.get("text", ""))
	fallback_label.text = (speaker + "\n\n" if not speaker.is_empty() else "") + text
	dialogue_minimum_seconds = float(line.get("minimum_seconds", 0.0))
	var audio_started_ok := false
	if line.has("audio_index"):
		audio_started_ok = play_audio_index(
			int(line["audio_index"]), "dialogue", "", AUDIO_CHANNEL_VOICE
		)
	elif line.has("audio_event"):
		audio_started_ok = play_audio_event(
			str(line["audio_event"]),
			str(line.get("actor_key", "")),
			int(line.get("variant", 0)),
			"",
			AUDIO_CHANNEL_VOICE,
		)
	if bool(line.get("auto_advance", false)) and not audio_started_ok:
		dialogue_minimum_seconds = maxf(
			dialogue_minimum_seconds, maxf(1.0, float(text.length()) * 0.08)
		)
	dialogue_line_changed.emit(dialogue_sequence_id, dialogue_line_index, line.duplicate(true))


func _load_external_image(path: String) -> bool:
	image_view.visible = true
	if path.is_empty():
		return false
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return false
	image_view.texture = ImageTexture.create_from_image(image)
	return true


func set_audio_stream_loader(loader: Callable) -> void:
	# Primarily an injection seam for deterministic tests. Replacing the loader
	# starts a fresh cache so streams created by different loaders cannot mix.
	_audio_stream_loader_override = loader
	_audio_stream_cache.clear()
	_audio_stream_load_count = 0


func audio_stream_load_count() -> int:
	return _audio_stream_load_count


func audio_stream_cache_size() -> int:
	return _audio_stream_cache.size()


func _load_cached_audio_stream(path: String) -> AudioStreamWAV:
	var load_path := _audio_load_path(path)
	if load_path.is_empty():
		return null
	var cache_key := normalize_audio_path(load_path)
	if cache_key.is_empty():
		return null
	if _audio_stream_cache.has(cache_key):
		return _audio_stream_cache[cache_key] as AudioStreamWAV
	var stream: AudioStreamWAV = null
	if _audio_stream_loader_override.is_valid():
		_audio_stream_load_count += 1
		var loaded: Variant = _audio_stream_loader_override.call(load_path)
		if loaded is AudioStreamWAV:
			stream = loaded as AudioStreamWAV
	else:
		# Avoid asking the native loader to open a known-invalid path. Missing or
		# removed optional media must degrade without an engine error.
		if not FileAccess.file_exists(load_path):
			return null
		_audio_stream_load_count += 1
		stream = AudioStreamWAV.load_from_file(load_path)
	if stream != null:
		_audio_stream_cache[cache_key] = stream
	return stream


static func normalize_audio_path(path: String) -> String:
	var normalized := _audio_load_path(path)
	if normalized.is_empty():
		return ""
	# Windows paths are case-insensitive. Lower-casing only there preserves the
	# distinct-path semantics of Linux/macOS builds.
	if OS.get_name() == "Windows":
		normalized = normalized.to_lower()
	return normalized


static func _audio_load_path(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		normalized = ProjectSettings.globalize_path(normalized)
	return normalized.replace("\\", "/").simplify_path()


func _show_subtitle(text: String, duration: float) -> void:
	if not subtitles_enabled:
		return
	subtitle_label.text = text
	subtitle_panel.visible = true
	subtitle_seconds = duration


func _on_audio_finished() -> void:
	var finished := active_audio_index
	active_audio_index = -1
	if finished >= 0:
		audio_finished.emit(finished)


func _on_music_finished() -> void:
	var finished := active_music_index
	active_music_index = -1
	if finished >= 0:
		audio_finished.emit(finished)


func _on_sfx_finished(slot: int) -> void:
	if slot < 0 or slot >= _sfx_active_indices.size():
		return
	var finished := _sfx_active_indices[slot]
	_sfx_active_indices[slot] = -1
	if finished >= 0:
		audio_finished.emit(finished)


func _on_video_finished() -> void:
	stop_movie(false)


func _ensure_catalog() -> void:
	if catalog == null:
		configure()


func _ensure_nodes() -> void:
	if audio_player != null:
		return
	_ensure_audio_bus("Music")
	_ensure_audio_bus("Sfx")
	_ensure_audio_bus("Voice")
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "LegacyVoicePlayer"
	audio_player.bus = "Voice"
	audio_player.finished.connect(_on_audio_finished)
	add_child(audio_player)
	music_player = AudioStreamPlayer.new()
	music_player.name = "LegacyMusicPlayer"
	music_player.bus = "Music"
	music_player.finished.connect(_on_music_finished)
	add_child(music_player)
	sfx_players.clear()
	_sfx_active_indices.clear()
	_sfx_cursor = 0
	for slot: int in range(SFX_POOL_SIZE):
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "LegacySfxPlayer%02d" % slot
		sfx_player.bus = "Sfx"
		sfx_player.finished.connect(_on_sfx_finished.bind(slot))
		add_child(sfx_player)
		sfx_players.append(sfx_player)
		_sfx_active_indices.append(-1)

	overlay = ColorRect.new()
	overlay.name = "LegacyMediaOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.015, 0.018, 0.015, 0.97)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	image_view = TextureRect.new()
	image_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay.add_child(image_view)

	video_player = VideoStreamPlayer.new()
	video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	video_player.expand = true
	video_player.bus = "Music"
	video_player.finished.connect(_on_video_finished)
	video_player.visible = false
	overlay.add_child(video_player)

	fallback_label = Label.new()
	fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 96)
	fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback_label.add_theme_font_size_override("font_size", 26)
	overlay.add_child(fallback_label)

	help_label = Label.new()
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -48.0
	help_label.offset_bottom = -12.0
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.68))
	overlay.add_child(help_label)

	subtitle_panel = ColorRect.new()
	subtitle_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle_panel.offset_left = 160.0
	subtitle_panel.offset_right = -160.0
	subtitle_panel.offset_top = -104.0
	subtitle_panel.offset_bottom = -38.0
	subtitle_panel.color = Color(0.0, 0.0, 0.0, 0.78)
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.visible = false
	add_child(subtitle_panel)

	subtitle_label = Label.new()
	subtitle_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_size_override("font_size", 22)
	subtitle_panel.add_child(subtitle_label)


static func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


static func audio_channel_for(
	event_key: String,
	metadata: Dictionary = {},
	actor_key: String = "",
) -> String:
	var category := str(metadata.get("category", ""))
	if category in ["music", "ambience"]:
		return AUDIO_CHANNEL_MUSIC
	if event_key == "dialogue" or category == "voice":
		return AUDIO_CHANNEL_VOICE
	if FALLBACK_VOICE_EVENTS.has(event_key):
		return AUDIO_CHANNEL_VOICE
	# The recovered default alert is a non-voice alarm, while actor-specific
	# alert variants are spoken Japanese shouts.
	if event_key == "alert" and not actor_key.is_empty():
		return AUDIO_CHANNEL_VOICE
	return AUDIO_CHANNEL_SFX


static func resolve_audio_channel(
	channel_override: String,
	event_key: String,
	metadata: Dictionary = {},
	actor_key: String = "",
) -> String:
	if channel_override in [
		AUDIO_CHANNEL_MUSIC,
		AUDIO_CHANNEL_VOICE,
		AUDIO_CHANNEL_SFX,
	]:
		return channel_override
	return audio_channel_for(event_key, metadata, actor_key)


static func select_sfx_slot(playing_slots: Array[bool], cursor: int) -> Dictionary:
	if playing_slots.is_empty():
		return {"slot": -1, "next_cursor": 0}
	var normalized_cursor := posmod(cursor, playing_slots.size())
	for offset: int in range(playing_slots.size()):
		var slot := (normalized_cursor + offset) % playing_slots.size()
		if not playing_slots[slot]:
			return {
				"slot": slot,
				"next_cursor": (slot + 1) % playing_slots.size(),
			}
	# A saturated pool deterministically steals the next round-robin slot.
	return {
		"slot": normalized_cursor,
		"next_cursor": (normalized_cursor + 1) % playing_slots.size(),
	}


static func dialogue_ready_to_auto_advance(
	auto_advance: bool,
	minimum_seconds: float,
	voice_playing: bool,
) -> bool:
	# SFX state is deliberately absent: only the dedicated voice/dialogue
	# channel is allowed to hold an auto-advancing line.
	return auto_advance and minimum_seconds <= 0.0 and not voice_playing


func _acquire_sfx_slot() -> int:
	var playing_slots: Array[bool] = []
	for player: AudioStreamPlayer in sfx_players:
		playing_slots.append(player.playing)
	var selection := select_sfx_slot(playing_slots, _sfx_cursor)
	_sfx_cursor = int(selection["next_cursor"])
	return int(selection["slot"])


func _begin_modal_transition() -> void:
	_modal_transition_depth += 1


func _end_modal_transition() -> void:
	_modal_transition_depth = maxi(_modal_transition_depth - 1, 0)
	_sync_modal_pause()


func _sync_modal_pause() -> void:
	if _modal_transition_depth > 0:
		return
	if _has_active_modal():
		_acquire_modal_pause()
	else:
		_release_modal_pause()


func _has_active_modal() -> bool:
	return (
		not active_briefing.is_empty()
		or not active_movie.is_empty()
		or active_ending
		or not dialogue_sequence_id.is_empty()
	)


func _acquire_modal_pause() -> void:
	if _modal_pause_owned:
		return
	var tree := get_tree()
	if tree == null:
		return
	_pause_state_before_modal = tree.paused
	_process_mode_before_modal = process_mode
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_modal_pause_owned = true
	tree.paused = true


func _release_modal_pause() -> void:
	if not _modal_pause_owned:
		return
	var tree := get_tree()
	if tree != null:
		tree.paused = _pause_state_before_modal
	process_mode = _process_mode_before_modal
	_modal_pause_owned = false
