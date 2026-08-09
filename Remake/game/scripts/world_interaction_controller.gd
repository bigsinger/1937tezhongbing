class_name WorldInteractionController
extends RefCounted

const DEFAULT_PRIORITY: Array[String] = [
	"loose_pickup",
	"burial_cache",
	"door",
	"deployable",
]


func dispatch(
	world_position: Vector2,
	handlers: Dictionary,
	priority: Array[String] = DEFAULT_PRIORITY,
) -> Dictionary:
	for interaction_id: String in priority:
		var handler_value: Variant = handlers.get(interaction_id)
		if not handler_value is Callable:
			continue
		var handler := handler_value as Callable
		if handler.is_valid() and bool(handler.call(world_position)):
			return {"handled": true, "interaction": interaction_id}
	return {"handled": false, "interaction": "world_fallback"}


func nearest_interactable(
	origins: Array[Vector2],
	candidates: Array[Dictionary],
	maximum_distance: float,
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for candidate: Dictionary in candidates:
		if not bool(candidate.get("available", true)):
			continue
		var position := candidate.get("position", Vector2.ZERO) as Vector2
		for origin: Vector2 in origins:
			var distance := origin.distance_to(position)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	if best.is_empty() or best_distance > maxf(maximum_distance, 0.0):
		return {}
	var result := best.duplicate(true)
	result["distance"] = best_distance
	return result
