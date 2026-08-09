class_name RuntimePerformanceMonitor
extends RefCounted

const RING_BUFFER := preload("res://scripts/int_ring_buffer.gd")

const DEFAULT_FRAME_WINDOW := 3600
const DEFAULT_EVENT_WINDOW := 256
const LONG_FRAME_USEC := 25_000
const MAX_LONG_FRAMES := 32
const SECTION_NAMES: Array[String] = [
	"main_cpu",
	"physics",
	"ai_perception",
	"navigation_reservation",
	"world_interaction",
	"ui",
	"resource_loading",
	"node_construction",
]

var frame_window := DEFAULT_FRAME_WINDOW
var event_window := DEFAULT_EVENT_WINDOW
var present_intervals: IntRingBuffer
var main_cpu_times: IntRingBuffer
var physics_times: IntRingBuffer
var monitor_overhead_times: IntRingBuffer
var section_samples: Dictionary = {}
var counters: Dictionary = {}
var enabled := true

var _events: Array = []
var _event_write_index := 0
var _event_count := 0
var _long_frames: Array = []
var _long_frame_write_index := 0
var _long_frame_count := 0
var _recent_commands: Array[Dictionary] = []
var _frame_started_usec := 0
var _previous_frame_started_usec := 0
var _physics_started_usec := 0
## Exact most-recent samples are exposed to the external campaign probe. Godot's
## built-in TIME_PROCESS monitors refresh at a coarse cadence on Windows and a
## single value can otherwise be counted as dozens of independent frame samples.
var last_main_cpu_usec := 0
var last_physics_usec := 0
var _section_starts: Dictionary = {}
var _monitor_overhead_total_usec := 0
var _monitor_call_count := 0


func _init(
	new_frame_window: int = DEFAULT_FRAME_WINDOW,
	new_event_window: int = DEFAULT_EVENT_WINDOW,
) -> void:
	frame_window = maxi(new_frame_window, 60)
	event_window = maxi(new_event_window, 32)
	present_intervals = RING_BUFFER.new(frame_window)
	main_cpu_times = RING_BUFFER.new(frame_window)
	physics_times = RING_BUFFER.new(frame_window)
	monitor_overhead_times = RING_BUFFER.new(frame_window)
	for section: String in SECTION_NAMES:
		section_samples[section] = RING_BUFFER.new(frame_window)
	_events.resize(event_window)
	_long_frames.resize(MAX_LONG_FRAMES)


func begin_frame() -> void:
	if not enabled:
		return
	var monitor_started := Time.get_ticks_usec()
	var now := monitor_started
	if _previous_frame_started_usec > 0:
		_record_present_interval(maxi(now - _previous_frame_started_usec, 0))
	_previous_frame_started_usec = now
	_frame_started_usec = now
	_record_overhead(monitor_started)


func end_frame() -> int:
	if not enabled or _frame_started_usec <= 0:
		return 0
	var monitor_started := Time.get_ticks_usec()
	var elapsed := maxi(monitor_started - _frame_started_usec, 0)
	_frame_started_usec = 0
	last_main_cpu_usec = elapsed
	main_cpu_times.append(elapsed)
	(section_samples["main_cpu"] as IntRingBuffer).append(elapsed)
	# The first call has no preceding presentation boundary. Keep compatibility
	# with one-shot probes while all subsequent frame samples are true intervals.
	if present_intervals.is_empty():
		_record_present_interval(elapsed)
	_record_overhead(monitor_started)
	return elapsed


func record_present_interval(elapsed_usec: int) -> void:
	if enabled:
		_record_present_interval(maxi(elapsed_usec, 0))


func begin_physics() -> void:
	if enabled:
		_physics_started_usec = Time.get_ticks_usec()


func end_physics() -> int:
	if not enabled or _physics_started_usec <= 0:
		return 0
	var elapsed := maxi(Time.get_ticks_usec() - _physics_started_usec, 0)
	_physics_started_usec = 0
	last_physics_usec = elapsed
	physics_times.append(elapsed)
	(section_samples["physics"] as IntRingBuffer).append(elapsed)
	return elapsed


func begin_section(section: String) -> void:
	if enabled and not section.is_empty():
		_section_starts[section] = Time.get_ticks_usec()


func end_section(section: String, metadata: Dictionary = {}) -> int:
	if not enabled or not _section_starts.has(section):
		return 0
	var elapsed := maxi(
		Time.get_ticks_usec() - int(_section_starts[section]),
		0,
	)
	_section_starts.erase(section)
	var category := _category_for_section(section)
	(section_samples[category] as IntRingBuffer).append(elapsed)
	record_event(section, elapsed, metadata.merged({"category": category}))
	return elapsed


func increment(counter: String, amount: int = 1) -> void:
	if enabled and not counter.is_empty():
		counters[counter] = int(counters.get(counter, 0)) + amount


func observe_command(command: Dictionary) -> void:
	if not enabled:
		return
	_recent_commands.append(_sanitize_command(command))
	if _recent_commands.size() > 16:
		_recent_commands.remove_at(0)


func record_event(name: String, elapsed_usec: int, metadata: Dictionary = {}) -> void:
	if not enabled:
		return
	_append_event({
		"name": name,
		"elapsed_usec": maxi(elapsed_usec, 0),
		"recorded_at_msec": Time.get_ticks_msec(),
		"metadata": _sanitize_metadata(metadata),
	})


func snapshot() -> Dictionary:
	var sections: Dictionary = {}
	for section: String in SECTION_NAMES:
		sections[section] = _sample_summary(
			(section_samples[section] as IntRingBuffer).values()
		)
	var present_summary := _sample_summary(present_intervals.values())
	return {
		"frame": present_summary,
		"present": present_summary,
		"main_cpu": _sample_summary(main_cpu_times.values()),
		"physics": _sample_summary(physics_times.values()),
		"sections": sections,
		"events": _ordered_ring_values(_events, _event_write_index, _event_count),
		"long_frames": _ordered_ring_values(
			_long_frames,
			_long_frame_write_index,
			_long_frame_count,
		),
		"counters": counters.duplicate(true),
		"monitor": _monitor_summary(),
		"engine": {
			"fps": float(Engine.get_frames_per_second()),
			"process_frames": Engine.get_process_frames(),
			"physics_frames": Engine.get_physics_frames(),
			"process_time_ms": float(Performance.get_monitor(
				Performance.TIME_PROCESS
			)) * 1000.0,
			"physics_process_time_ms": float(Performance.get_monitor(
				Performance.TIME_PHYSICS_PROCESS
			)) * 1000.0,
			"navigation_process_time_ms": float(Performance.get_monitor(
				Performance.TIME_NAVIGATION_PROCESS
			)) * 1000.0,
			"static_memory_bytes": int(Performance.get_monitor(
				Performance.MEMORY_STATIC
			)),
			"object_count": int(Performance.get_monitor(
				Performance.OBJECT_COUNT
			)),
			"draw_calls": int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
			)),
		},
	}


func clear() -> void:
	present_intervals.clear()
	main_cpu_times.clear()
	physics_times.clear()
	monitor_overhead_times.clear()
	for sample_value: Variant in section_samples.values():
		(sample_value as IntRingBuffer).clear()
	_event_write_index = 0
	_event_count = 0
	_long_frame_write_index = 0
	_long_frame_count = 0
	_recent_commands.clear()
	counters.clear()
	_section_starts.clear()
	_previous_frame_started_usec = 0
	last_main_cpu_usec = 0
	last_physics_usec = 0
	_monitor_overhead_total_usec = 0
	_monitor_call_count = 0


func _record_present_interval(elapsed_usec: int) -> void:
	present_intervals.append(elapsed_usec)
	if elapsed_usec >= LONG_FRAME_USEC:
		_append_long_frame({
			"interval_usec": elapsed_usec,
			"recorded_at_msec": Time.get_ticks_msec(),
			"responsible_system": _recent_responsible_system(),
			"counters": counters.duplicate(true),
			"recent_commands": _recent_commands.duplicate(true),
		})


func _recent_responsible_system() -> String:
	var events := _ordered_ring_values(_events, _event_write_index, _event_count)
	var best_name := "unattributed"
	var best_elapsed := 0
	for index: int in range(maxi(events.size() - 8, 0), events.size()):
		var event := events[index] as Dictionary
		if int(event.get("elapsed_usec", 0)) > best_elapsed:
			best_elapsed = int(event["elapsed_usec"])
			best_name = str(event.get("name", best_name))
	return best_name


func _append_event(value: Dictionary) -> void:
	_events[_event_write_index] = value
	_event_write_index = (_event_write_index + 1) % event_window
	_event_count = mini(_event_count + 1, event_window)


func _append_long_frame(value: Dictionary) -> void:
	_long_frames[_long_frame_write_index] = value
	_long_frame_write_index = (_long_frame_write_index + 1) % MAX_LONG_FRAMES
	_long_frame_count = mini(_long_frame_count + 1, MAX_LONG_FRAMES)


func _record_overhead(started_usec: int) -> void:
	var elapsed := maxi(Time.get_ticks_usec() - started_usec, 0)
	_monitor_overhead_total_usec += elapsed
	_monitor_call_count += 1
	monitor_overhead_times.append(elapsed)


func _monitor_summary() -> Dictionary:
	var summary := _sample_summary(monitor_overhead_times.values())
	# Preserve the original field for diagnostic readers while exposing the
	# complete fixed-window distribution required by the performance budget.
	summary["call_count"] = _monitor_call_count
	summary["average_overhead_ms"] = (
		float(_monitor_overhead_total_usec)
		/ float(maxi(_monitor_call_count, 1))
		/ 1000.0
	)
	return summary


static func _category_for_section(section: String) -> String:
	var normalized := section.to_lower()
	if "nav" in normalized or "reservation" in normalized or "path" in normalized:
		return "navigation_reservation"
	if "ai" in normalized or "sense" in normalized or "perception" in normalized:
		return "ai_perception"
	if "ui" in normalized or "hud" in normalized or "menu" in normalized:
		return "ui"
	if "load" in normalized or "resource" in normalized or "prewarm" in normalized:
		return "resource_loading"
	if "construct" in normalized or "spawn" in normalized or "node" in normalized:
		return "node_construction"
	return "world_interaction"


static func _sanitize_command(command: Dictionary) -> Dictionary:
	return {
		"sequence": int(command.get("sequence", 0)),
		"name": str(command.get("name", "")),
		"source": str(command.get("source", "")),
		"simulation_tick": int(command.get("simulation_tick", -1)),
	}


static func _sanitize_metadata(metadata: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key_value: Variant in metadata.keys():
		var key := str(key_value)
		if key.to_lower().contains("path") or key.to_lower().contains("user"):
			continue
		var value: Variant = metadata[key_value]
		if value is bool or value is int or value is float or value is String:
			output[key] = value
		elif value is Dictionary:
			output[key] = _sanitize_metadata(value as Dictionary)
	return output


static func _ordered_ring_values(
	storage: Array,
	write_index: int,
	count: int,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count <= 0 or storage.is_empty():
		return result
	var start := posmod(write_index - count, storage.size())
	for index: int in range(count):
		var value: Variant = storage[(start + index) % storage.size()]
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


static func _sample_summary(samples: PackedInt64Array) -> Dictionary:
	if samples.is_empty():
		return {
			"sample_count": 0,
			"average_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
			"maximum_ms": 0.0,
		}
	var ordered: Array[int] = []
	var total := 0
	for sample: int in samples:
		ordered.append(sample)
		total += sample
	ordered.sort()
	return {
		"sample_count": ordered.size(),
		"average_ms": float(total) / float(ordered.size()) / 1000.0,
		"p95_ms": float(ordered[_percentile_index(ordered.size(), 0.95)]) / 1000.0,
		"p99_ms": float(ordered[_percentile_index(ordered.size(), 0.99)]) / 1000.0,
		"maximum_ms": float(ordered[-1]) / 1000.0,
	}


static func _percentile_index(count: int, percentile: float) -> int:
	return clampi(
		ceili(float(count) * percentile) - 1,
		0,
		maxi(count - 1, 0),
	)
