class_name IntRingBuffer
extends RefCounted

var capacity := 1
var _values: PackedInt64Array = PackedInt64Array()
var _write_index := 0
var _count := 0


func _init(new_capacity: int = 1) -> void:
	capacity = maxi(new_capacity, 1)
	_values.resize(capacity)


func append(value: int) -> void:
	_values[_write_index] = value
	_write_index = (_write_index + 1) % capacity
	_count = mini(_count + 1, capacity)


func size() -> int:
	return _count


func is_empty() -> bool:
	return _count == 0


func clear() -> void:
	_write_index = 0
	_count = 0


func values() -> PackedInt64Array:
	var result := PackedInt64Array()
	result.resize(_count)
	var start := posmod(_write_index - _count, capacity)
	for index: int in range(_count):
		result[index] = _values[(start + index) % capacity]
	return result


func newest(default_value: int = 0) -> int:
	if _count == 0:
		return default_value
	return _values[posmod(_write_index - 1, capacity)]
