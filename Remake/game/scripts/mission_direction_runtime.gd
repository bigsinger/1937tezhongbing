class_name MissionDirectionRuntime
extends Node

## Emits data-only presentation and encounter commands for a mission. World
## systems remain authoritative: this runtime never completes objectives,
## moves the camera or mutates an enemy by itself.

signal configured(mission_id: String)
signal difficulty_profile_requested(profile: Dictionary)
signal ai_cooperation_requested(profile: Dictionary)
signal beat_dispatched(beat_id: String, beat: Dictionary)
signal camera_requested(beat_id: String, camera: Dictionary)
signal dialogue_requested(sequence_id: String, lines: Array, source_status: String)
signal tutorial_requested(tutorial_id: String, tutorial: Dictionary)
signal tutorial_completed(tutorial_id: String)
signal ai_directive_requested(beat_id: String, directive: Dictionary)

const DATA_SCRIPT: Script = preload("res://scripts/mission_direction_data.gd")
const CATALOG_PATH := "res://data/mission_direction.json"

var mission_id := ""
var mission_plan: Dictionary = {}
var difficulty_mode := "normal"
var last_error := ""
var elapsed_seconds := 0.0

var _media_director: Node
var _started := false
var _fired_beats: Dictionary = {}
var _completed_tutorials: Dictionary = {}
var _active_tutorials: Dictionary = {}
var _published_events: Array[Dictionary] = []
var _published_event_keys: Dictionary = {}
var _media_dialogue_queue: Array[Dictionary] = []


func configure_for_mission(
	new_mission_id: String,
	new_media_director: Node = null,
	new_difficulty_mode: String = "normal",
	catalog_path: String = CATALOG_PATH,
) -> bool:
	_reset()
	if new_difficulty_mode not in ["easy", "normal", "hard"]:
		return _reject("unknown difficulty mode: %s" % new_difficulty_mode)
	mission_plan = DATA_SCRIPT.load_mission_plan(new_mission_id, catalog_path)
	if mission_plan.is_empty():
		return _reject("mission direction plan is unavailable: %s" % new_mission_id)
	mission_id = new_mission_id
	difficulty_mode = new_difficulty_mode
	attach_media_director(new_media_director)
	last_error = ""
	configured.emit(mission_id)
	return true


func attach_media_director(new_media_director: Node) -> void:
	var finished_callable := Callable(self, "_on_media_dialogue_finished")
	if (
		_media_director != null
		and is_instance_valid(_media_director)
		and _media_director.has_signal("dialogue_finished")
		and _media_director.is_connected("dialogue_finished", finished_callable)
	):
		_media_director.disconnect("dialogue_finished", finished_callable)
	_media_director = new_media_director
	if (
		_media_director != null
		and is_instance_valid(_media_director)
		and _media_director.has_signal("dialogue_finished")
		and not _media_director.is_connected("dialogue_finished", finished_callable)
	):
		_media_director.connect("dialogue_finished", finished_callable)


func start() -> bool:
	if mission_plan.is_empty():
		return _reject("mission direction runtime is not configured")
	if _started:
		return false
	_started = true
	difficulty_profile_requested.emit(difficulty_profile())
	ai_cooperation_requested.emit(ai_cooperation_profile())
	publish_event("mission_started")
	return true


func has_pending_media_dialogue() -> bool:
	if not _media_dialogue_queue.is_empty():
		return true
	return (
		_media_director != null
		and is_instance_valid(_media_director)
		and not str(_media_director.get("dialogue_sequence_id")).is_empty()
	)


func queue_external_dialogue(sequence_id: String, lines: Array) -> bool:
	if (
		sequence_id.is_empty()
		or lines.is_empty()
		or _media_director == null
		or not is_instance_valid(_media_director)
		or not _media_director.has_method("start_dialogue")
	):
		return false
	_queue_media_presentation("", {}, sequence_id, lines)
	return true


func replay_fired_beat_presentation(beat_id: String) -> bool:
	# Save snapshots deliberately exclude modal node state. Rebuild only the
	# presentation of an already-fired beat; gameplay effects (AI/tutorials and
	# beat bookkeeping) must not run twice.
	if not _fired_beats.has(beat_id) or has_pending_media_dialogue():
		return false
	var beats := _beat_by_id()
	if not beats.has(beat_id):
		return false
	var beat := beats[beat_id] as Dictionary
	if beat.has("dialogue"):
		var dialogue := beat["dialogue"] as Dictionary
		var sequence_id := str(dialogue.get("sequence_id", ""))
		var lines := (dialogue.get("lines", []) as Array).duplicate(true)
		dialogue_requested.emit(sequence_id, lines, str(dialogue.get("source_status", "")))
		if (
			_media_director != null
			and is_instance_valid(_media_director)
			and _media_director.has_method("start_dialogue")
		):
			_queue_media_presentation(
				beat_id,
				(beat.get("camera", {}) as Dictionary).duplicate(true),
				sequence_id,
				lines,
			)
		elif beat.has("camera"):
			camera_requested.emit(beat_id, (beat["camera"] as Dictionary).duplicate(true))
		return true
	if beat.has("camera"):
		camera_requested.emit(beat_id, (beat["camera"] as Dictionary).duplicate(true))
		return true
	return false


func publish_event(event_name: String, payload: Dictionary = {}) -> Array[String]:
	var dispatched: Array[String] = []
	if mission_plan.is_empty():
		_reject("mission direction runtime is not configured")
		return dispatched
	if event_name not in DATA_SCRIPT.TRIGGER_EVENTS or event_name == "elapsed_seconds":
		_reject("unsupported published direction event: %s" % event_name)
		return dispatched
	last_error = ""
	_remember_event(event_name, payload)
	dispatched.append_array(_dispatch_matching_event(event_name, payload))
	return dispatched


func advance_time(delta_seconds: float) -> Array[String]:
	var dispatched: Array[String] = []
	if mission_plan.is_empty() or delta_seconds <= 0.0:
		return dispatched
	elapsed_seconds += delta_seconds
	dispatched.append_array(_dispatch_elapsed_beats())
	return dispatched


func report_tutorial_action(action: String) -> Array[String]:
	var completed: Array[String] = []
	if action.is_empty():
		return completed
	for tutorial_value: Variant in _active_tutorials.values():
		var tutorial := tutorial_value as Dictionary
		if (
			str(tutorial.get("gate_mode", "")) == "observe_action"
			and str(tutorial.get("completion_action", "")) == action
		):
			var tutorial_id := str(tutorial.get("id", ""))
			if _complete_tutorial(tutorial_id):
				completed.append(tutorial_id)
	_replay_pending_beats()
	return completed


func acknowledge_tutorial(tutorial_id: String) -> bool:
	if not _active_tutorials.has(tutorial_id):
		return false
	var tutorial := _active_tutorials[tutorial_id] as Dictionary
	if str(tutorial.get("gate_mode", "")) != "acknowledge":
		return false
	var completed := _complete_tutorial(tutorial_id)
	if completed:
		_replay_pending_beats()
	return completed


func dismiss_tutorial(tutorial_id: String) -> bool:
	# Non-blocking observed tutorials may be hidden without claiming that the
	# taught action happened. This keeps presentation state separate from gates.
	if not _active_tutorials.has(tutorial_id):
		return false
	var tutorial := _active_tutorials[tutorial_id] as Dictionary
	if bool(tutorial.get("blocking", false)):
		return false
	_active_tutorials.erase(tutorial_id)
	return true


func is_beat_fired(beat_id: String) -> bool:
	return _fired_beats.has(beat_id)


func is_tutorial_complete(tutorial_id: String) -> bool:
	return _completed_tutorials.has(tutorial_id)


func active_tutorials() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _active_tutorials.keys()
	ids.sort()
	for tutorial_id: Variant in ids:
		result.append((_active_tutorials[tutorial_id] as Dictionary).duplicate(true))
	return result


func difficulty_profile() -> Dictionary:
	if mission_plan.is_empty():
		return {}
	return DATA_SCRIPT.difficulty_for_mode(
		mission_plan.get("difficulty", {}) as Dictionary,
		difficulty_mode,
	)


func ai_cooperation_profile() -> Dictionary:
	if mission_plan.is_empty():
		return {}
	return (mission_plan.get("ai_cooperation", {}) as Dictionary).duplicate(true)


func capture_state() -> Dictionary:
	var fired: Array = _fired_beats.keys()
	fired.sort()
	var completed: Array = _completed_tutorials.keys()
	completed.sort()
	var active: Array = _active_tutorials.keys()
	active.sort()
	return {
		"schema_version": 1,
		"mission_id": mission_id,
		"difficulty_mode": difficulty_mode,
		"started": _started,
		"elapsed_seconds": elapsed_seconds,
		"fired_beats": fired,
		"completed_tutorials": completed,
		"active_tutorials": active,
		"published_events": _published_events.duplicate(true),
	}


func restore_state(state: Dictionary) -> bool:
	if mission_plan.is_empty():
		return _reject("mission direction runtime is not configured")
	if (
		int(state.get("schema_version", 0)) != 1
		or str(state.get("mission_id", "")) != mission_id
		or str(state.get("difficulty_mode", "")) != difficulty_mode
		or not state.get("started") is bool
		or not _is_nonnegative_number(state.get("elapsed_seconds"))
	):
		return _reject("mission direction save header is invalid")
	var beat_by_id := _beat_by_id()
	var tutorial_by_id := _tutorial_by_id()
	for field: String in ["fired_beats", "completed_tutorials", "active_tutorials", "published_events"]:
		if not state.get(field) is Array:
			return _reject("mission direction save field %s is invalid" % field)
	var fired: Dictionary = {}
	for raw_id: Variant in state["fired_beats"] as Array:
		var beat_id := str(raw_id)
		if not beat_by_id.has(beat_id) or fired.has(beat_id):
			return _reject("mission direction save has an unknown/duplicate beat")
		fired[beat_id] = true
	var completed: Dictionary = {}
	for raw_id: Variant in state["completed_tutorials"] as Array:
		var tutorial_id := str(raw_id)
		if not tutorial_by_id.has(tutorial_id) or completed.has(tutorial_id):
			return _reject("mission direction save has an unknown/duplicate tutorial")
		completed[tutorial_id] = true
	var active: Dictionary = {}
	for raw_id: Variant in state["active_tutorials"] as Array:
		var tutorial_id := str(raw_id)
		if not tutorial_by_id.has(tutorial_id) or completed.has(tutorial_id) or active.has(tutorial_id):
			return _reject("mission direction save has an invalid active tutorial")
		active[tutorial_id] = (tutorial_by_id[tutorial_id] as Dictionary).duplicate(true)
	var events: Array[Dictionary] = []
	var event_keys: Dictionary = {}
	for raw_event: Variant in state["published_events"] as Array:
		if not raw_event is Dictionary:
			return _reject("mission direction save has a non-object event")
		var event := raw_event as Dictionary
		var event_name := str(event.get("event", ""))
		var payload: Variant = event.get("payload")
		if event_name not in DATA_SCRIPT.TRIGGER_EVENTS or event_name == "elapsed_seconds" or not payload is Dictionary:
			return _reject("mission direction save has an invalid event")
		var event_key := _event_key(event_name, payload as Dictionary)
		if event_keys.has(event_key):
			return _reject("mission direction save has a duplicate event")
		event_keys[event_key] = true
		events.append({"event": event_name, "payload": (payload as Dictionary).duplicate(true)})

	_started = bool(state["started"])
	elapsed_seconds = float(state["elapsed_seconds"])
	_fired_beats = fired
	_completed_tutorials = completed
	_active_tutorials = active
	_published_events = events
	_published_event_keys = event_keys
	last_error = ""
	return true


func _dispatch_matching_event(event_name: String, payload: Dictionary) -> Array[String]:
	var dispatched: Array[String] = []
	for raw_beat: Variant in mission_plan.get("beats", []) as Array:
		var beat := raw_beat as Dictionary
		var beat_id := str(beat.get("id", ""))
		if _fired_beats.has(beat_id) or not _beat_gate_is_open(beat):
			continue
		if _trigger_matches(beat.get("trigger", {}) as Dictionary, event_name, payload):
			_dispatch_beat(beat)
			dispatched.append(beat_id)
	return dispatched


func _dispatch_elapsed_beats() -> Array[String]:
	var dispatched: Array[String] = []
	for raw_beat: Variant in mission_plan.get("beats", []) as Array:
		var beat := raw_beat as Dictionary
		var beat_id := str(beat.get("id", ""))
		if _fired_beats.has(beat_id) or not _beat_gate_is_open(beat):
			continue
		var trigger := beat.get("trigger", {}) as Dictionary
		if (
			str(trigger.get("event", "")) == "elapsed_seconds"
			and elapsed_seconds >= float(trigger.get("at_seconds", INF))
		):
			_dispatch_beat(beat)
			dispatched.append(beat_id)
	return dispatched


func _replay_pending_beats() -> Array[String]:
	var dispatched: Array[String] = []
	for event: Dictionary in _published_events:
		dispatched.append_array(
			_dispatch_matching_event(str(event["event"]), event["payload"] as Dictionary)
		)
	dispatched.append_array(_dispatch_elapsed_beats())
	return dispatched


func _dispatch_beat(beat: Dictionary) -> void:
	var beat_id := str(beat.get("id", ""))
	_fired_beats[beat_id] = true
	beat_dispatched.emit(beat_id, beat.duplicate(true))
	# Tutorial gates and AI posture affect gameplay immediately. Camera is
	# presentation state: when a beat has dialogue it starts with that queued
	# sequence, so two beats dispatched in one frame cannot replace each
	# other's shot before the matching line is visible.
	if beat.has("tutorial"):
		var tutorial := (beat["tutorial"] as Dictionary).duplicate(true)
		var tutorial_id := str(tutorial.get("id", ""))
		if not _completed_tutorials.has(tutorial_id):
			_active_tutorials[tutorial_id] = tutorial
			tutorial_requested.emit(tutorial_id, tutorial.duplicate(true))
	if beat.has("ai_directive"):
		ai_directive_requested.emit(
			beat_id, (beat["ai_directive"] as Dictionary).duplicate(true)
		)
	if beat.has("dialogue"):
		var dialogue := beat["dialogue"] as Dictionary
		var sequence_id := str(dialogue.get("sequence_id", ""))
		var lines := (dialogue.get("lines", []) as Array).duplicate(true)
		dialogue_requested.emit(sequence_id, lines, str(dialogue.get("source_status", "")))
		if _media_director != null and is_instance_valid(_media_director) and _media_director.has_method("start_dialogue"):
			_queue_media_presentation(
				beat_id,
				(beat.get("camera", {}) as Dictionary).duplicate(true),
				sequence_id,
				lines,
			)
		elif beat.has("camera"):
			camera_requested.emit(beat_id, (beat["camera"] as Dictionary).duplicate(true))
	elif beat.has("camera"):
		camera_requested.emit(beat_id, (beat["camera"] as Dictionary).duplicate(true))


func _queue_media_presentation(
	beat_id: String,
	camera: Dictionary,
	sequence_id: String,
	lines: Array,
) -> void:
	if _media_director == null or not is_instance_valid(_media_director):
		return
	var presentation := {
		"beat_id": beat_id,
		"camera": camera.duplicate(true),
		"sequence_id": sequence_id,
		"lines": lines.duplicate(true),
	}
	# Lightweight test doubles without MediaDirector's completion signal retain
	# the old direct-call contract. The real director gets a deterministic queue
	# so objective-complete and victory signals in the same frame cannot replace
	# one another's text or camera shot.
	if not _media_director.has_signal("dialogue_finished"):
		if not camera.is_empty():
			camera_requested.emit(beat_id, camera.duplicate(true))
		_media_director.call("start_dialogue", sequence_id, lines)
		return
	var active_sequence := str(_media_director.get("dialogue_sequence_id"))
	if active_sequence.is_empty() and _media_dialogue_queue.is_empty():
		_start_media_presentation(presentation)
		return
	_media_dialogue_queue.append(presentation)


func _on_media_dialogue_finished(_sequence_id: String, _skipped: bool) -> void:
	call_deferred("_play_next_media_dialogue")


func _play_next_media_dialogue() -> void:
	if _media_director == null or not is_instance_valid(_media_director):
		_media_dialogue_queue.clear()
		return
	if not str(_media_director.get("dialogue_sequence_id")).is_empty():
		return
	while not _media_dialogue_queue.is_empty():
		var queued := _media_dialogue_queue.pop_front() as Dictionary
		if _start_media_presentation(queued):
			return


func _start_media_presentation(presentation: Dictionary) -> bool:
	if _media_director == null or not is_instance_valid(_media_director):
		return false
	if not bool(_media_director.call(
		"start_dialogue",
		str(presentation.get("sequence_id", "")),
		presentation.get("lines", []) as Array,
	)):
		return false
	var camera := presentation.get("camera", {}) as Dictionary
	if not camera.is_empty():
		camera_requested.emit(
			str(presentation.get("beat_id", "")),
			camera.duplicate(true),
		)
	return true


func _complete_tutorial(tutorial_id: String) -> bool:
	if tutorial_id.is_empty() or _completed_tutorials.has(tutorial_id):
		return false
	_completed_tutorials[tutorial_id] = true
	_active_tutorials.erase(tutorial_id)
	tutorial_completed.emit(tutorial_id)
	return true


func _beat_gate_is_open(beat: Dictionary) -> bool:
	for raw_id: Variant in beat.get("requires_tutorials", []) as Array:
		if not _completed_tutorials.has(str(raw_id)):
			return false
	return true


static func _trigger_matches(
	trigger: Dictionary,
	event_name: String,
	payload: Dictionary,
) -> bool:
	if str(trigger.get("event", "")) != event_name:
		return false
	var where := trigger.get("where", {}) as Dictionary
	for raw_key: Variant in where.keys():
		var key := str(raw_key)
		if not payload.has(key):
			return false
		if key == "count":
			if int(payload[key]) < int(where[raw_key]):
				return false
		elif payload[key] != where[raw_key]:
			return false
	return true


func _remember_event(event_name: String, payload: Dictionary) -> void:
	var key := _event_key(event_name, payload)
	if _published_event_keys.has(key):
		return
	_published_event_keys[key] = true
	_published_events.append({"event": event_name, "payload": payload.duplicate(true)})


func _beat_by_id() -> Dictionary:
	var result: Dictionary = {}
	for raw_beat: Variant in mission_plan.get("beats", []) as Array:
		var beat := raw_beat as Dictionary
		result[str(beat.get("id", ""))] = beat
	return result


func _tutorial_by_id() -> Dictionary:
	var result: Dictionary = {}
	for raw_beat: Variant in mission_plan.get("beats", []) as Array:
		var beat := raw_beat as Dictionary
		if beat.has("tutorial"):
			var tutorial := beat["tutorial"] as Dictionary
			result[str(tutorial.get("id", ""))] = tutorial
	return result


static func _event_key(event_name: String, payload: Dictionary) -> String:
	return "%s|%s" % [event_name, JSON.stringify(payload, "", true, true)]


func _reset() -> void:
	attach_media_director(null)
	mission_id = ""
	mission_plan = {}
	difficulty_mode = "normal"
	last_error = ""
	elapsed_seconds = 0.0
	_started = false
	_fired_beats = {}
	_completed_tutorials = {}
	_active_tutorials = {}
	_published_events = []
	_published_event_keys = {}
	_media_dialogue_queue = []


static func _is_nonnegative_number(value: Variant) -> bool:
	return (value is int or value is float) and float(value) >= 0.0


func _reject(message: String) -> bool:
	last_error = message
	return false
