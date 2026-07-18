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

const CATALOG_SCRIPT: Script = preload("res://scripts/legacy_media_catalog.gd")
const SFX_POOL_SIZE := 8
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


func is_modal_active() -> bool:
	return _has_active_modal()


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
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		media_unavailable.emit("audio", str(gfl_index))
		return false
	var metadata: Dictionary = catalog.call("sound_metadata", gfl_index)
	var channel := channel_override
	if channel not in [AUDIO_CHANNEL_VOICE, AUDIO_CHANNEL_SFX]:
		channel = audio_channel_for(event_key, metadata, actor_key)
	if channel == AUDIO_CHANNEL_VOICE:
		audio_player.stream = stream
		active_audio_index = gfl_index
		audio_player.play()
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
	if not event.is_pressed() or event.is_echo():
		return
	var handled := false
	if event.is_action("ui_cancel"):
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
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "LegacyVoicePlayer"
	audio_player.finished.connect(_on_audio_finished)
	add_child(audio_player)
	sfx_players.clear()
	_sfx_active_indices.clear()
	_sfx_cursor = 0
	for slot: int in range(SFX_POOL_SIZE):
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "LegacySfxPlayer%02d" % slot
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


static func audio_channel_for(
	event_key: String,
	metadata: Dictionary = {},
	actor_key: String = "",
) -> String:
	if event_key == "dialogue" or str(metadata.get("category", "")) == "voice":
		return AUDIO_CHANNEL_VOICE
	if FALLBACK_VOICE_EVENTS.has(event_key):
		return AUDIO_CHANNEL_VOICE
	# The recovered default alert is a non-voice alarm, while actor-specific
	# alert variants are spoken Japanese shouts.
	if event_key == "alert" and not actor_key.is_empty():
		return AUDIO_CHANNEL_VOICE
	return AUDIO_CHANNEL_SFX


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
