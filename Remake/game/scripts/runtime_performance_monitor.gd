class_name RuntimePerformanceMonitor
extends RefCounted

const DEFAULT_FRAME_WINDOW := 3600
const DEFAULT_EVENT_WINDOW := 256

var frame_window := DEFAULT_FRAME_WINDOW
var event_window := DEFAULT_EVENT_WINDOW
var frame_times_usec: PackedInt64Array = PackedInt64Array()
var physics_times_usec: PackedInt64Array = PackedInt64Array()
var events: Array[Dictionary] = []
var counters: Dictionary = {}
var _frame_started_usec := 0
var _physics_started_usec := 0
var _section_starts: Dictionary = {}


func _init(
	new_frame_window: int = DEFAULT_FRAME_WINDOW,
	new_event_window: int = DEFAULT_EVENT_WINDOW,
) -> void:
	frame_window = maxi(new_frame_window, 60)
	event_window = maxi(new_event_window, 32)


func begin_frame() -> void:
	_frame_started_usec = Time.get_ticks_usec()


func end_frame() -> int:
	if _frame_started_usec <= 0:
		return 0
	var elapsed := maxi(Time.get_ticks_usec() - _frame_started_usec, 0)
	_frame_started_usec = 0
	_append_sample(frame_times_usec, elapsed, frame_window)
	return elapsed


func begin_physics() -> void:
	_physics_started_usec = Time.get_ticks_usec()


func end_physics() -> int:
	if _physics_started_usec <= 0:
		return 0
	var elapsed := maxi(Time.get_ticks_usec() - _physics_started_usec, 0)
	_physics_started_usec = 0
	_append_sample(physics_times_usec, elapsed, frame_window)
	return elapsed


func begin_section(section: String) -> void:
	if not section.is_empty():
		_section_starts[section] = Time.get_ticks_usec()


func end_section(section: String, metadata: Dictionary = {}) -> int:
	if not _section_starts.has(section):
		return 0
	var elapsed := maxi(
		Time.get_ticks_usec() - int(_section_starts[section]),
		0,
	)
	_section_starts.erase(section)
	record_event(section, elapsed, metadata)
	return elapsed


func increment(counter: String, amount: int = 1) -> void:
	if counter.is_empty():
		return
	counters[counter] = int(counters.get(counter, 0)) + amount


func record_event(name: String, elapsed_usec: int, metadata: Dictionary = {}) -> void:
	events.append({
		"name": name,
		"elapsed_usec": maxi(elapsed_usec, 0),
		"recorded_at_msec": Time.get_ticks_msec(),
		"metadata": metadata.duplicate(true),
	})
	while events.size() > event_window:
		events.pop_front()


func snapshot() -> Dictionary:
	return {
		"frame": _sample_summary(frame_times_usec),
		"physics": _sample_summary(physics_times_usec),
		"events": events.duplicate(true),
		"counters": counters.duplicate(true),
		"engine": {
			"fps": float(Engine.get_frames_per_second()),
			"process_frames": Engine.get_process_frames(),
			"physics_frames": Engine.get_physics_frames(),
			"static_memory_bytes": int(
				Performance.get_monitor(Performance.MEMORY_STATIC)
			),
			"object_count": int(
				Performance.get_monitor(Performance.OBJECT_COUNT)
			),
			"draw_calls": int(
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			),
		},
	}


func clear() -> void:
	frame_times_usec = PackedInt64Array()
	physics_times_usec = PackedInt64Array()
	events.clear()
	counters.clear()
	_section_starts.clear()


static func _append_sample(samples: PackedInt64Array, value: int, limit: int) -> void:
	samples.append(value)
	if samples.size() > limit:
		samples.remove_at(0)


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
	return clampi(ceili(float(count) * percentile) - 1, 0, maxi(count - 1, 0))
