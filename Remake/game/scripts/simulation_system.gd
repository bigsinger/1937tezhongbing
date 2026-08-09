class_name SimulationSystem
extends RefCounted

var system_id := ""
var phase := ""
var priority := 0
var callback: Callable
var enabled := true


func _init(
	new_system_id: String = "",
	new_phase: String = "",
	new_priority: int = 0,
	new_callback: Callable = Callable(),
) -> void:
	system_id = new_system_id.strip_edges().to_lower()
	phase = new_phase.strip_edges().to_lower()
	priority = new_priority
	callback = new_callback


func is_valid() -> bool:
	return (
		not system_id.is_empty()
		and not phase.is_empty()
		and callback.is_valid()
	)


func simulate_tick(tick: int, fixed_delta: float) -> void:
	if enabled and callback.is_valid():
		callback.call(tick, fixed_delta)
