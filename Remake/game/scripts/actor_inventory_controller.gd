class_name ActorInventoryController
extends RefCounted


func normalized_transfer(snapshot: Dictionary) -> Dictionary:
	var result := {"weapons": {}, "items": {}}
	for section: String in ["weapons", "items"]:
		var source: Variant = snapshot.get(section, {})
		if not source is Dictionary:
			continue
		var normalized := result[section] as Dictionary
		for key_value: Variant in (source as Dictionary).keys():
			var quantity := maxi(int((source as Dictionary)[key_value]), 0)
			if quantity > 0:
				normalized[str(key_value)] = quantity
	return result


func merge_counts(destination: Dictionary, incoming: Dictionary) -> Dictionary:
	var result := destination.duplicate(true)
	for key_value: Variant in incoming.keys():
		var key := str(key_value)
		var quantity := maxi(int(incoming[key_value]), 0)
		if quantity > 0:
			result[key] = maxi(int(result.get(key, 0)), 0) + quantity
	return result


func consume(counts: Dictionary, key: String, quantity: int) -> Dictionary:
	var result := counts.duplicate(true)
	var available := maxi(int(result.get(key, 0)), 0)
	var consumed := mini(available, maxi(quantity, 0))
	if consumed >= available:
		result.erase(key)
	else:
		result[key] = available - consumed
	return {"counts": result, "consumed": consumed}


func add_original_item(
	inventory: RefCounted,
	item_id: int,
	quantity: int,
	quantity_mode: int,
) -> int:
	if inventory == null or not inventory.has_method("add_original_item"):
		return 0
	return int(inventory.call(
		"add_original_item",
		item_id,
		quantity,
		quantity_mode,
	))


func consume_original_item(
	inventory: RefCounted,
	item_id: int,
	force_consumption: bool,
	quantity: int,
) -> bool:
	return (
		inventory != null
		and inventory.has_method("consume")
		and bool(inventory.call(
			"consume",
			item_id,
			force_consumption,
			quantity,
		))
	)


func original_snapshot(inventory: RefCounted) -> Dictionary:
	if inventory == null or not inventory.has_method("snapshot"):
		return {}
	var value: Variant = inventory.call("snapshot")
	return value as Dictionary if value is Dictionary else {}
