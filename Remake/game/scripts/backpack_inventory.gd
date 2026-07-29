class_name BackpackInventory
extends RefCounted

signal item_changed(item_id: int, quantity: int, present: bool)

const SUPPORTED_ITEM_IDS := [
	33, 46, 47, 48, 49, 50, 51, 52, 53, 54, 82, 83, 92, 101,
]
const ALLOWED_QUANTITY_MODES := {
	33: [0, 1],
	46: [0],
	47: [0],
	48: [0],
	49: [0, 1],
	50: [0],
	51: [0],
	52: [0, 1],
	53: [0],
	54: [0],
	82: [0],
	83: [0, 1],
	92: [0],
	101: [0],
}

var _entries: Array[Dictionary] = []


func register_original_item(
	item_id: int,
	quantity: int,
	quantity_mode: int,
) -> bool:
	if (
		not supports_item(item_id)
		or quantity < 0
		or not supports_quantity_mode(item_id, quantity_mode)
		or _index_for_item(item_id) >= 0
	):
		return false
	_entries.append({
		"item_id": item_id,
		"quantity": quantity,
		"quantity_mode": quantity_mode,
	})
	item_changed.emit(item_id, quantity, true)
	return true


func add_original_item(
	item_id: int,
	quantity: int,
	quantity_mode: int = 0,
) -> int:
	if (
		not supports_item(item_id)
		or quantity <= 0
		or not supports_quantity_mode(item_id, quantity_mode)
	):
		return 0
	var index := _index_for_item(item_id)
	if index < 0:
		if not register_original_item(item_id, quantity, quantity_mode):
			return 0
		return quantity
	var entry := _entries[index]
	if int(entry.get("quantity_mode", -1)) != quantity_mode:
		return 0
	if quantity_mode == 1:
		# Original sub_4529F0 treats a mode-1 item as a durable unique entry.
		return quantity
	entry["quantity"] = int(entry.get("quantity", 0)) + quantity
	item_changed.emit(item_id, int(entry["quantity"]), true)
	return quantity


func consume(
	item_id: int,
	force_consumption: bool = false,
	quantity: int = 1,
) -> bool:
	if quantity <= 0:
		return false
	var index := _index_for_item(item_id)
	if index < 0:
		return false
	for unused_index: int in range(quantity):
		index = _index_for_item(item_id)
		if index < 0:
			return false
		var entry := _entries[index]
		var mode := int(entry.get("quantity_mode", -1))
		if mode == 1 and not force_consumption:
			continue
		var remaining := maxi(int(entry.get("quantity", 0)) - 1, 0)
		entry["quantity"] = remaining
		if (
			(mode == 0 and remaining <= 0)
			or (mode in [1, 2] and force_consumption and remaining <= 0)
		):
			_entries.remove_at(index)
			item_changed.emit(item_id, 0, false)
		else:
			item_changed.emit(item_id, remaining, true)
	return true


func take_for_drop(item_id: int, quantity: int = 1) -> Dictionary:
	if quantity <= 0:
		return {}
	var index := _index_for_item(item_id)
	if index < 0:
		return {}
	var entry := _entries[index].duplicate(true)
	var available := maxi(int(entry.get("quantity", 0)), 0)
	if available <= 0:
		return {}
	var removed := mini(quantity, available)
	if not consume(item_id, true, removed):
		return {}
	entry["quantity"] = removed
	return entry


func has_item(item_id: int) -> bool:
	return _index_for_item(item_id) >= 0


func item_count(item_id: int) -> int:
	var index := _index_for_item(item_id)
	return 0 if index < 0 else maxi(int(_entries[index].get("quantity", 0)), 0)


func quantity_mode(item_id: int) -> int:
	var index := _index_for_item(item_id)
	return -1 if index < 0 else int(_entries[index].get("quantity_mode", -1))


func ordered_entries() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		output.append(entry.duplicate(true))
	return output


func clear() -> void:
	var previous := ordered_entries()
	_entries.clear()
	for entry: Dictionary in previous:
		item_changed.emit(int(entry.get("item_id", 0)), 0, false)


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"entries": ordered_entries(),
	}


func restore_snapshot(value: Dictionary) -> bool:
	if int(value.get("schema_version", 0)) != 1:
		return false
	var raw_entries: Variant = value.get("entries")
	if not raw_entries is Array:
		return false
	var restored: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			return false
		var entry := raw_entry as Dictionary
		var item_id := int(entry.get("item_id", 0))
		var quantity := int(entry.get("quantity", -1))
		var mode := int(entry.get("quantity_mode", -1))
		if (
			not supports_item(item_id)
			or quantity < 0
			or not supports_quantity_mode(item_id, mode)
			or seen.has(item_id)
		):
			return false
		seen[item_id] = true
		restored.append({
			"item_id": item_id,
			"quantity": quantity,
			"quantity_mode": mode,
		})
	_entries = restored
	for entry: Dictionary in _entries:
		item_changed.emit(
			int(entry["item_id"]),
			int(entry["quantity"]),
			true,
		)
	return true


func _index_for_item(item_id: int) -> int:
	for index: int in range(_entries.size()):
		if int(_entries[index].get("item_id", 0)) == item_id:
			return index
	return -1


static func supports_item(item_id: int) -> bool:
	return item_id in SUPPORTED_ITEM_IDS


static func supports_quantity_mode(item_id: int, quantity_mode: int) -> bool:
	return (
		ALLOWED_QUANTITY_MODES.has(item_id)
		and quantity_mode in (ALLOWED_QUANTITY_MODES[item_id] as Array)
	)
