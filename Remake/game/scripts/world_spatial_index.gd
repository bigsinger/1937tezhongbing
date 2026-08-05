class_name WorldSpatialIndex
extends RefCounted

## Lightweight broad-phase index for world interaction, perception and combat.
## Nodes remain the source of truth; this service only owns disposable lookup
## records and is rebuilt whenever a level changes or a save is restored.

const DEFAULT_CELL_SIZE := Vector2(128.0, 128.0)

var cell_size := DEFAULT_CELL_SIZE
var _records: Dictionary = {}
var _buckets: Dictionary = {}
var _scene_nodes: Dictionary = {}
var _revision := 0
var _query_count := 0
var _candidate_count := 0


class SpatialRecord extends RefCounted:
	var node: Node2D
	var cell: Vector2i
	var tags: Dictionary
	var scene_index: int

	func _init(
		new_node: Node2D,
		new_cell: Vector2i,
		new_tags: Dictionary,
		new_scene_index: int,
	) -> void:
		node = new_node
		cell = new_cell
		tags = new_tags
		scene_index = new_scene_index


func _init(new_cell_size: Vector2 = DEFAULT_CELL_SIZE) -> void:
	cell_size = Vector2(
		maxf(new_cell_size.x, 16.0),
		maxf(new_cell_size.y, 16.0),
	)


func clear() -> void:
	_records.clear()
	_buckets.clear()
	_scene_nodes.clear()
	_revision += 1
	_query_count = 0
	_candidate_count = 0


func register_node(
	node: Node2D,
	tags: Array = [],
	scene_index: int = -1,
) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var instance_id := node.get_instance_id()
	if _records.has(instance_id):
		unregister_node(node)
	var resolved_scene_index := scene_index
	if resolved_scene_index < 0:
		resolved_scene_index = _read_scene_index(node)
	var tag_lookup: Dictionary = {}
	for raw_tag: Variant in tags:
		var normalized := str(raw_tag).strip_edges().to_lower()
		if not normalized.is_empty():
			tag_lookup[normalized] = true
	var cell := world_to_cell(node.global_position)
	_records[instance_id] = SpatialRecord.new(
		node, cell, tag_lookup, resolved_scene_index
	)
	_add_to_bucket(cell, instance_id)
	if resolved_scene_index >= 0:
		_scene_nodes[resolved_scene_index] = node
	_revision += 1
	return true


func unregister_node(node: Node2D) -> bool:
	if node == null:
		return false
	var instance_id := node.get_instance_id()
	var record_value: Variant = _records.get(instance_id)
	if not record_value is SpatialRecord:
		return false
	var record := record_value as SpatialRecord
	_remove_from_bucket(record.cell, instance_id)
	var scene_index := record.scene_index
	if scene_index >= 0 and _scene_nodes.get(scene_index) == node:
		_scene_nodes.erase(scene_index)
	_records.erase(instance_id)
	_revision += 1
	return true


func update_node(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var instance_id := node.get_instance_id()
	var record_value: Variant = _records.get(instance_id)
	if not record_value is SpatialRecord:
		return false
	var record := record_value as SpatialRecord
	var old_cell := record.cell
	var new_cell := world_to_cell(node.global_position)
	if old_cell == new_cell:
		return false
	_remove_from_bucket(old_cell, instance_id)
	_add_to_bucket(new_cell, instance_id)
	record.cell = new_cell
	_revision += 1
	return true


func synchronize(nodes: Array) -> int:
	var moved := 0
	for value: Variant in nodes:
		if value is Node2D and is_instance_valid(value):
			moved += 1 if update_node(value as Node2D) else 0
	_prune_invalid_records()
	return moved


func node_for_scene(scene_index: int) -> Node2D:
	var node := _scene_nodes.get(scene_index) as Node2D
	if node == null or not is_instance_valid(node):
		_scene_nodes.erase(scene_index)
		return null
	return node


func query_radius(
	center: Vector2,
	radius: float,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> Array[Node2D]:
	var safe_radius := maxf(radius, 0.0)
	var bounds := Rect2(
		center - Vector2.ONE * safe_radius,
		Vector2.ONE * safe_radius * 2.0,
	)
	var candidates := _query_rect_candidates(bounds, required_tags, include_inactive)
	var radius_squared := safe_radius * safe_radius
	var result: Array[Node2D] = []
	for node: Node2D in candidates:
		if node.global_position.distance_squared_to(center) <= radius_squared:
			result.append(node)
	return result


func query_rect(
	bounds: Rect2,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> Array[Node2D]:
	var candidates := _query_rect_candidates(bounds.abs(), required_tags, include_inactive)
	var result: Array[Node2D] = []
	for node: Node2D in candidates:
		if bounds.abs().has_point(node.global_position):
			result.append(node)
	return result


func nearest(
	center: Vector2,
	radius: float,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> Node2D:
	var result: Node2D
	var best_distance_squared := INF
	for node: Node2D in query_radius(
		center,
		radius,
		required_tags,
		include_inactive,
	):
		var distance_squared := node.global_position.distance_squared_to(center)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			result = node
	return result


func contains_node(node: Node2D) -> bool:
	return node != null and _records.has(node.get_instance_id())


func revision() -> int:
	return _revision


func stats() -> Dictionary:
	return {
		"record_count": _records.size(),
		"bucket_count": _buckets.size(),
		"revision": _revision,
		"query_count": _query_count,
		"candidate_count": _candidate_count,
	}


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size.x),
		floori(world_position.y / cell_size.y),
	)


func _query_rect_candidates(
	bounds: Rect2,
	required_tags: Array,
	include_inactive: bool,
) -> Array[Node2D]:
	_query_count += 1
	var normalized_tags: Array[String] = []
	for raw_tag: Variant in required_tags:
		var normalized := str(raw_tag).strip_edges().to_lower()
		if not normalized.is_empty():
			normalized_tags.append(normalized)
	var min_cell := world_to_cell(bounds.position)
	var max_cell := world_to_cell(bounds.end)
	var seen: Dictionary = {}
	var result: Array[Node2D] = []
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var bucket_value: Variant = _buckets.get(Vector2i(x, y))
			if not bucket_value is Dictionary:
				continue
			for instance_id_value: Variant in (bucket_value as Dictionary).keys():
				var instance_id := int(instance_id_value)
				if seen.has(instance_id):
					continue
				seen[instance_id] = true
				var record_value: Variant = _records.get(instance_id)
				if not record_value is SpatialRecord:
					continue
				var record := record_value as SpatialRecord
				if not _record_has_tags(record, normalized_tags):
					continue
				var node := record.node
				if node == null or not is_instance_valid(node):
					continue
				if not include_inactive and not node.is_inside_tree():
					continue
				result.append(node)
	_candidate_count += result.size()
	return result


func _record_has_tags(record: SpatialRecord, required_tags: Array[String]) -> bool:
	if required_tags.is_empty():
		return true
	for tag: String in required_tags:
		if not record.tags.has(tag):
			return false
	return true


func _add_to_bucket(cell: Vector2i, instance_id: int) -> void:
	var bucket: Dictionary = _buckets.get(cell, {}) as Dictionary
	bucket[instance_id] = true
	_buckets[cell] = bucket


func _remove_from_bucket(cell: Vector2i, instance_id: int) -> void:
	var bucket_value: Variant = _buckets.get(cell)
	if not bucket_value is Dictionary:
		return
	var bucket := bucket_value as Dictionary
	bucket.erase(instance_id)
	if bucket.is_empty():
		_buckets.erase(cell)


func _prune_invalid_records() -> void:
	var invalid_ids: Array[int] = []
	for instance_id_value: Variant in _records.keys():
		var instance_id := int(instance_id_value)
		var record := _records[instance_id] as SpatialRecord
		var node := record.node
		if node == null or not is_instance_valid(node):
			invalid_ids.append(instance_id)
	for instance_id: int in invalid_ids:
		var record := _records[instance_id] as SpatialRecord
		_remove_from_bucket(record.cell, instance_id)
		var scene_index := record.scene_index
		if scene_index >= 0:
			_scene_nodes.erase(scene_index)
		_records.erase(instance_id)
	if not invalid_ids.is_empty():
		_revision += 1


static func _read_scene_index(node: Node) -> int:
	for property: Dictionary in node.get_property_list():
		if str(property.get("name", "")) == "scene_index":
			return int(node.get("scene_index"))
	return -1
