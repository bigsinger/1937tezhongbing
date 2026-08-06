class_name WorldInteractionResolver
extends RefCounted

## One semantic ordering is shared by classic and modern controls.  Rendering
## order is deliberately not used for input: a corpse can visually overlap a
## loose weapon, but the recoverable item must remain the first interaction.
enum Priority {
	GROUND = 0,
	COMBAT_TARGET = 40,
	CORPSE_CACHE = 50,
	DOOR = 60,
	FIELD_PICKUP = 80,
	LOOSE_INVENTORY = 100,
}


static func candidate(
	kind: String,
	node: Node2D,
	priority: int,
	world_point: Vector2,
) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	return {
		"kind": kind,
		"node": node,
		"priority": priority,
		"distance_squared": node.global_position.distance_squared_to(world_point),
		"instance_id": node.get_instance_id(),
	}


static func choose(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for value: Dictionary in candidates:
		if value.is_empty():
			continue
		var node_value: Variant = value.get("node")
		if not node_value is Node2D or not is_instance_valid(node_value):
			continue
		if best.is_empty() or _precedes(value, best):
			best = value
	return best


static func _precedes(first: Dictionary, second: Dictionary) -> bool:
	var first_priority := int(first.get("priority", Priority.GROUND))
	var second_priority := int(second.get("priority", Priority.GROUND))
	if first_priority != second_priority:
		return first_priority > second_priority
	var first_distance := float(first.get("distance_squared", INF))
	var second_distance := float(second.get("distance_squared", INF))
	if not is_equal_approx(first_distance, second_distance):
		return first_distance < second_distance
	return int(first.get("instance_id", 0)) < int(second.get("instance_id", 0))
