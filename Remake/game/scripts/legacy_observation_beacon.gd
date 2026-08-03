class_name LegacyObservationBeacon
extends Node2D

const TACTICAL_SENSES: Script = preload("res://scripts/tactical_senses.gd")
const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

signal observed(beacon: Node2D, observer: Node2D)

## Recovered from DBL entry 1008 (`检测视线精灵.spr`).
const ORIGINAL_ACTOR_TYPE := 90
const ORIGINAL_GFL_INDEX := 341

var original_actor_type := ORIGINAL_ACTOR_TYPE
var original_gfl_index := ORIGINAL_GFL_INDEX
var navigation: Variant
var potential_observers: Array[Node2D] = []
var age_world_ticks := 0
var consumed := false
var poll_state := 1
var poll_override := -1
var externally_polled := false
var original_frames: Array[Texture2D] = []
var original_frame_hold_ticks := 1
var original_frame_index := 0
var original_factory_random_consumed := false
var original_destructor_random_consumed := false


func configure(
	world_position: Vector2,
	new_navigation: Variant,
	observers: Array[Node2D],
	visual: Variant = null,
	random_seed: int = 1,
) -> bool:
	position = world_position
	navigation = new_navigation
	potential_observers = observers.duplicate()
	poll_state = random_seed & 0x7fffffff
	if poll_state == 0:
		poll_state = 1
	age_world_ticks = 0
	consumed = false
	original_factory_random_consumed = false
	original_destructor_random_consumed = false
	externally_polled = false
	visible = true
	_set_visual(visual)
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	queue_redraw()
	return true


func move_marker(world_position: Vector2, random_seed: int = 1) -> void:
	position = world_position
	poll_state = random_seed & 0x7fffffff
	if poll_state == 0:
		poll_state = 1
	age_world_ticks = 0
	consumed = false
	visible = true
	z_index = WORLD_DEPTH.normal_z(position.y, 2)
	queue_redraw()


func set_potential_observers(observers: Array[Node2D]) -> void:
	potential_observers = observers.duplicate()


func force_poll_result_for_tests(value: int = -1) -> void:
	poll_override = clampi(value, -1, 1)


func set_external_polling(value: bool) -> void:
	externally_polled = value


func advance_for_observer(
	observer: Node2D,
	gate_passed: bool,
) -> bool:
	if consumed or not gate_passed or not can_be_observed_by(observer):
		return false
	consume(observer)
	return true


func advance_world_ticks(ticks: int = 1) -> Node2D:
	if consumed:
		return null
	for unused_tick: int in range(maxi(ticks, 0)):
		age_world_ticks += 1
		_advance_original_animation()
		if not _poll_passes():
			continue
		for observer: Node2D in potential_observers:
			if not can_be_observed_by(observer):
				continue
			consume(observer)
			return observer
	queue_redraw()
	return null


func can_be_observed_by(observer: Node2D) -> bool:
	if (
		consumed
		or observer == null
		or not is_instance_valid(observer)
		or int(observer.get("faction_id")) != 1
		or not bool(observer.get("is_alive"))
	):
		return false
	var sense_value: Variant = observer.get("sense_profile")
	if not sense_value is Dictionary:
		return false
	var ignored: Array = []
	var scene_index := int(observer.get("scene_index"))
	if scene_index >= 0:
		ignored.append(scene_index)
	return TACTICAL_SENSES.can_detect_original(
		navigation,
		observer.global_position,
		global_position,
		int(observer.get("original_direction_index")),
		sense_value as Dictionary,
		false,
		ignored,
	)


func consume(observer: Node2D) -> void:
	if consumed:
		return
	consumed = true
	visible = false
	observed.emit(self, observer)
	if is_inside_tree():
		queue_free()


func _physics_process(_delta: float) -> void:
	if externally_polled:
		if consumed:
			return
		age_world_ticks += 1
		_advance_original_animation()
		queue_redraw()
	else:
		advance_world_ticks(1)


func _poll_passes() -> bool:
	if poll_override >= 0:
		return poll_override == 1
	# The executable gates marker scanning with `rand() % 2 > 0`. Its Windows
	# CRT is represented with the matching MSVC linear-congruential step so
	# replay remains deterministic without changing the recovered 50% gate.
	poll_state = int((poll_state * 214013 + 2531011) & 0x7fffffff)
	return int((poll_state >> 16) & 0x7fff) % 2 > 0


func _set_visual(visual: Variant) -> void:
	original_frames.clear()
	original_frame_hold_ticks = 1
	if visual is Texture2D:
		original_frames.append(visual as Texture2D)
	elif visual is Dictionary:
		var raw_frames: Variant = (visual as Dictionary).get("frames", [])
		if raw_frames is Array:
			for raw_frame: Variant in raw_frames as Array:
				if raw_frame is Texture2D:
					original_frames.append(raw_frame as Texture2D)
		original_frame_hold_ticks = maxi(
			int((visual as Dictionary).get("frame_hold_ticks", 1)),
			1,
		)
	original_frame_index = 0


func _advance_original_animation() -> void:
	if original_frames.size() <= 1:
		return
	original_frame_index = (
		age_world_ticks / original_frame_hold_ticks
	) % original_frames.size()


func _draw() -> void:
	if consumed:
		return
	if not original_frames.is_empty():
		var frame: Texture2D = original_frames[
			clampi(original_frame_index, 0, original_frames.size() - 1)
		]
		draw_texture(frame, -frame.get_size() * 0.5)
		return
	# Development fallback only; packaged original assets use GFL 341.
	draw_circle(Vector2.ZERO, 5.0, Color(0.24, 0.95, 0.42, 0.92))
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 16, Color(0.24, 0.95, 0.42, 0.78), 1.5)
