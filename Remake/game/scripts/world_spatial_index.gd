class_name WorldSpatialIndex
extends RefCounted

## Event-driven broad phase. Nodes remain authoritative; records change only
## when lifecycle code registers/unregisters them or an actor crosses a bucket.

const DEFAULT_CELL_SIZE := Vector2(128.0, 128.0)
const MAX_TAG_BITS := 62

var cell_size := DEFAULT_CELL_SIZE
var _records: Dictionary = {}
var _buckets: Dictionary = {}
var _scene_nodes: Dictionary = {}
var _tag_bits: Dictionary = {}
var _next_tag_bit := 0
var _query_masks: Dictionary = {}
var _revision := 0
var _query_count := 0
var _candidate_count := 0
var _bucket_crossings := 0
var _lifecycle_events := 0
var _audit_failures := 0


class SpatialRecord extends RefCounted:
	var node: Node2D
	var cell: Vector2i
	var tag_mask := 0
	var scene_index := -1
	var active := true

	func _init(
		new_node: Node2D,
		new_cell: Vector2i,
		new_tag_mask: int,
		new_scene_index: int,
	) -> void:
		node = new_node
		cell = new_cell
		tag_mask = new_tag_mask
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
	_tag_bits.clear()
	_query_masks.clear()
	_next_tag_bit = 0
	_revision += 1
	_query_count = 0
	_candidate_count = 0
	_bucket_crossings = 0
	_lifecycle_events = 0
	_audit_failures = 0


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
	var record := SpatialRecord.new(
		node,
		world_to_cell(node.global_position),
		_mask_for_tags(tags, true),
		resolved_scene_index,
	)
	_records[instance_id] = record
	_add_to_bucket(record.cell, instance_id)
	if resolved_scene_index >= 0:
		_scene_nodes[resolved_scene_index] = node
	_revision += 1
	_lifecycle_events += 1
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
	if record.scene_index >= 0 and _scene_nodes.get(record.scene_index) == node:
		_scene_nodes.erase(record.scene_index)
	_records.erase(instance_id)
	_revision += 1
	_lifecycle_events += 1
	return true


func update_node(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var instance_id := node.get_instance_id()
	var record_value: Variant = _records.get(instance_id)
	if not record_value is SpatialRecord:
		return false
	var record := record_value as SpatialRecord
	var new_cell := world_to_cell(node.global_position)
	if record.cell == new_cell:
		return false
	_remove_from_bucket(record.cell, instance_id)
	_add_to_bucket(new_cell, instance_id)
	record.cell = new_cell
	_revision += 1
	_bucket_crossings += 1
	return true


func set_node_tags(node: Node2D, tags: Array) -> bool:
	if node == null:
		return false
	var record_value: Variant = _records.get(node.get_instance_id())
	if not record_value is SpatialRecord:
		return false
	var record := record_value as SpatialRecord
	var new_mask := _mask_for_tags(tags, true)
	if new_mask == record.tag_mask:
		return false
	record.tag_mask = new_mask
	_revision += 1
	_lifecycle_events += 1
	return true


func set_node_active(node: Node2D, active: bool) -> bool:
	if node == null:
		return false
	var record_value: Variant = _records.get(node.get_instance_id())
	if not record_value is SpatialRecord:
		return false
	var record := record_value as SpatialRecord
	if record.active == active:
		return false
	record.active = active
	_revision += 1
	_lifecycle_events += 1
	return true


func synchronize(nodes: Array) -> int:
	# Compatibility/debug audit only. Product runtime uses actor boundary events.
	var moved := 0
	for value: Variant in nodes:
		if value is Node2D and is_instance_valid(value):
			moved += 1 if update_node(value as Node2D) else 0
	_prune_invalid_records()
	return moved


func audit_consistency() -> Dictionary:
	var failures: Array[String] = []
	var bucket_members := 0
	for cell_value: Variant in _buckets.keys():
		var cell := cell_value as Vector2i
		var bucket := _buckets[cell] as Dictionary
		bucket_members += bucket.size()
		for instance_value: Variant in bucket.keys():
			var instance_id := int(instance_value)
			var record_value: Variant = _records.get(instance_id)
			if not record_value is SpatialRecord:
				failures.append("bucket references missing record %d" % instance_id)
				continue
			var record := record_value as SpatialRecord
			if record.cell != cell:
				failures.append("record %d is in the wrong bucket" % instance_id)
	for instance_value: Variant in _records.keys():
		var instance_id := int(instance_value)
		var record := _records[instance_id] as SpatialRecord
		var bucket_value: Variant = _buckets.get(record.cell)
		if not bucket_value is Dictionary or not (bucket_value as Dictionary).has(instance_id):
			failures.append("record %d is missing from its bucket" % instance_id)
	if not failures.is_empty():
		_audit_failures += failures.size()
	return {
		"ok": failures.is_empty(),
		"failures": failures,
		"record_count": _records.size(),
		"bucket_member_count": bucket_members,
	}


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
	var result: Array[Node2D] = []
	query_radius_into(
		result,
		center,
		radius,
		required_tags,
		include_inactive,
	)
	return result


func query_radius_into(
	result: Array[Node2D],
	center: Vector2,
	radius: float,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> int:
	result.clear()
	var safe_radius := maxf(radius, 0.0)
	var bounds := Rect2(
		center - Vector2.ONE * safe_radius,
		Vector2.ONE * safe_radius * 2.0,
	)
	var radius_squared := safe_radius * safe_radius
	_query_count += 1
	var required_mask := _mask_for_tags(required_tags, false)
	var minimum_cell := world_to_cell(bounds.position)
	var maximum_cell := world_to_cell(bounds.end)
	# Radius queries are the enemy-perception and pointer-hit-test hot path.
	# Keeping their distance predicate inline avoids allocating a Callable and
	# crossing a dynamic call boundary for every nearby candidate at 5 Hz across
	# a dense patrol. Lifecycle, tag and active-state checks remain identical to
	# the general rectangle query below.
	for y: int in range(minimum_cell.y, maximum_cell.y + 1):
		for x: int in range(minimum_cell.x, maximum_cell.x + 1):
			var bucket_value: Variant = _buckets.get(Vector2i(x, y))
			if not bucket_value is Dictionary:
				continue
			for instance_value: Variant in (bucket_value as Dictionary):
				var instance_id := int(instance_value)
				var record_value: Variant = _records.get(instance_id)
				if not record_value is SpatialRecord:
					continue
				var record := record_value as SpatialRecord
				_candidate_count += 1
				if required_mask != 0 and (record.tag_mask & required_mask) != required_mask:
					continue
				var node := record.node
				if node == null or not is_instance_valid(node):
					continue
				if (
					not include_inactive
					and (not record.active or not node.is_inside_tree())
				):
					continue
				if node.global_position.distance_squared_to(center) <= radius_squared:
					result.append(node)
	return result.size()


func query_rect(
	bounds: Rect2,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> Array[Node2D]:
	var result: Array[Node2D] = []
	query_rect_into(result, bounds, required_tags, include_inactive)
	return result


func query_rect_into(
	result: Array[Node2D],
	bounds: Rect2,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> int:
	result.clear()
	var absolute_bounds := bounds.abs()
	_query_into(
		result,
		absolute_bounds,
		required_tags,
		include_inactive,
		func(node: Node2D) -> bool:
			return absolute_bounds.has_point(node.global_position),
	)
	return result.size()


func nearest(
	center: Vector2,
	radius: float,
	required_tags: Array = [],
	include_inactive: bool = false,
) -> Node2D:
	var best: Node2D
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
			best = node
	return best


func contains_node(node: Node2D) -> bool:
	return node != null and _records.has(node.get_instance_id())


func revision() -> int:
	return _revision


func stats() -> Dictionary:
	return {
		"record_count": _records.size(),
		"bucket_count": _buckets.size(),
		"tag_count": _tag_bits.size(),
		"revision": _revision,
		"query_count": _query_count,
		"candidate_count": _candidate_count,
		"bucket_crossings": _bucket_crossings,
		"lifecycle_events": _lifecycle_events,
		"audit_failures": _audit_failures,
	}


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size.x),
		floori(world_position.y / cell_size.y),
	)


func _query_into(
	result: Array[Node2D],
	bounds: Rect2,
	required_tags: Array,
	include_inactive: bool,
	accept: Callable,
) -> void:
	_query_count += 1
	var required_mask := _mask_for_tags(required_tags, false)
	var minimum_cell := world_to_cell(bounds.position)
	var maximum_cell := world_to_cell(bounds.end)
	for y: int in range(minimum_cell.y, maximum_cell.y + 1):
		for x: int in range(minimum_cell.x, maximum_cell.x + 1):
			var bucket_value: Variant = _buckets.get(Vector2i(x, y))
			if not bucket_value is Dictionary:
				continue
			# A SpatialRecord is authoritative in exactly one bucket. The event
			# boundary moves it by removing the old membership before inserting the
			# new one, so a per-query `seen` dictionary only allocated memory and
			# performed redundant hashes in the hottest broad-phase path.
			for instance_value: Variant in (bucket_value as Dictionary):
				var instance_id := int(instance_value)
				var record_value: Variant = _records.get(instance_id)
				if not record_value is SpatialRecord:
					continue
				var record := record_value as SpatialRecord
				_candidate_count += 1
				if required_mask != 0 and (record.tag_mask & required_mask) != required_mask:
					continue
				var node := record.node
				if node == null or not is_instance_valid(node):
					continue
				if (
					not include_inactive
					and (not record.active or not node.is_inside_tree())
				):
					continue
				if accept.call(node):
					result.append(node)


func _mask_for_tags(tags: Array, create_missing: bool) -> int:
	if tags.is_empty():
		return 0
	if tags.size() == 1:
		var single_tag := str(tags[0]).strip_edges().to_lower()
		if single_tag.is_empty():
			return 0
		if not create_missing and _query_masks.has(single_tag):
			return int(_query_masks[single_tag])
		if not _tag_bits.has(single_tag):
			if not create_missing or _next_tag_bit >= MAX_TAG_BITS:
				return 1 << (MAX_TAG_BITS - 1)
			_tag_bits[single_tag] = 1 << _next_tag_bit
			_next_tag_bit += 1
			_query_masks.clear()
		var single_mask := int(_tag_bits[single_tag])
		_query_masks[single_tag] = single_mask
		return single_mask
	var normalized: Array[String] = []
	for raw_tag: Variant in tags:
		var tag := str(raw_tag).strip_edges().to_lower()
		if not tag.is_empty() and not normalized.has(tag):
			normalized.append(tag)
	normalized.sort()
	var cache_key := "|".join(normalized)
	if not create_missing and _query_masks.has(cache_key):
		return int(_query_masks[cache_key])
	var mask := 0
	for tag: String in normalized:
		if not _tag_bits.has(tag):
			if not create_missing or _next_tag_bit >= MAX_TAG_BITS:
				# Unknown query tags can never match an existing record.
				return 1 << (MAX_TAG_BITS - 1)
			_tag_bits[tag] = 1 << _next_tag_bit
			_next_tag_bit += 1
			_query_masks.clear()
		mask |= int(_tag_bits[tag])
	_query_masks[cache_key] = mask
	return mask


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
	var invalid: Array[int] = []
	for instance_value: Variant in _records.keys():
		var instance_id := int(instance_value)
		var record := _records[instance_id] as SpatialRecord
		if record.node == null or not is_instance_valid(record.node):
			invalid.append(instance_id)
	for instance_id: int in invalid:
		var record := _records[instance_id] as SpatialRecord
		_remove_from_bucket(record.cell, instance_id)
		if record.scene_index >= 0:
			_scene_nodes.erase(record.scene_index)
		_records.erase(instance_id)
	if not invalid.is_empty():
		_revision += 1
		_lifecycle_events += invalid.size()


static func _read_scene_index(node: Node) -> int:
	for property: Dictionary in node.get_property_list():
		if str(property.get("name", "")) == "scene_index":
			return int(node.get("scene_index"))
	return -1
