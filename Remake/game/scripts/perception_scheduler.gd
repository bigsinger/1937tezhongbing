class_name PerceptionScheduler
extends RefCounted

## Deterministically phases expensive perception updates. Classic rules can
## request slot_count=1; modern rules use multiple slots without introducing
## random, save-dependent timing.

const DEFAULT_INTERVAL_SECONDS := 0.20
const DEFAULT_SLOT_COUNT := 12

var interval_seconds := DEFAULT_INTERVAL_SECONDS
var slot_count := DEFAULT_SLOT_COUNT


func _init(
	new_interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
	new_slot_count: int = DEFAULT_SLOT_COUNT,
) -> void:
	interval_seconds = maxf(new_interval_seconds, 1.0 / 120.0)
	slot_count = maxi(new_slot_count, 1)


func phase_for_scene(scene_index: int) -> int:
	if slot_count <= 1:
		return 0
	return posmod(scene_index * 37 + 11, slot_count)


func initial_elapsed_for_scene(scene_index: int) -> float:
	if slot_count <= 1:
		return 0.0
	var slot_duration := interval_seconds / float(slot_count)
	# EnemyUnit triggers when elapsed reaches interval. Starting closer to the
	# boundary yields the requested first-update phase while preserving the
	# interval thereafter.
	return interval_seconds - float(phase_for_scene(scene_index)) * slot_duration


func schedule_snapshot(scene_indices: Array[int]) -> Dictionary:
	var slots: Dictionary = {}
	for scene_index: int in scene_indices:
		var slot := phase_for_scene(scene_index)
		slots[slot] = int(slots.get(slot, 0)) + 1
	return {
		"interval_seconds": interval_seconds,
		"slot_count": slot_count,
		"actors": scene_indices.size(),
		"slot_population": slots,
	}
