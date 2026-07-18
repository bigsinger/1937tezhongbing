class_name CombatInventory
extends RefCounted

signal active_weapon_changed(action_key: String)
signal item_changed(item_id: int, quantity: int)
signal magazine_changed(action_key: String, magazine: int)

const SUPPORTED_AMMO_ITEM_IDS := [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 99]

var _items: Dictionary = {}
var _weapons: Dictionary = {}
var _active_action_key := ""


func _init() -> void:
	for item_id: int in SUPPORTED_AMMO_ITEM_IDS:
		_items[item_id] = 0


func register_weapon(
	action_key: String,
	weapon_profile: Dictionary,
	load_profile_defaults: bool = false,
) -> bool:
	if action_key.is_empty() or weapon_profile.is_empty():
		return false
	var ammo_item_id := int(weapon_profile.get("ammo_item_id", 0))
	if not supports_ammo_item(ammo_item_id):
		return false
	var capacity := maxi(int(weapon_profile.get("magazine_capacity", 0)), 0)
	var state := {
		"action_key": action_key,
		"profile": weapon_profile.duplicate(true),
		"ammo_item_id": ammo_item_id,
		"magazine_capacity": capacity,
		"magazine": capacity if load_profile_defaults else 0,
		"ammo_per_attack": maxi(int(weapon_profile.get("ammo_per_attack", 0)), 0),
	}
	_weapons[action_key] = state
	if load_profile_defaults:
		add_item(ammo_item_id, maxi(int(weapon_profile.get("starting_reserve_ammo", 0)), 0))
	if _active_action_key.is_empty():
		_active_action_key = action_key
		active_weapon_changed.emit(_active_action_key)
	magazine_changed.emit(action_key, int(state["magazine"]))
	return true


func unregister_weapon(action_key: String) -> bool:
	if not _weapons.erase(action_key):
		return false
	if _active_action_key == action_key:
		_active_action_key = ""
		if not _weapons.is_empty():
			_active_action_key = String(_weapons.keys()[0])
		active_weapon_changed.emit(_active_action_key)
	return true


func equip_weapon(action_key: String) -> bool:
	if not _weapons.has(action_key):
		return false
	if _active_action_key != action_key:
		_active_action_key = action_key
		active_weapon_changed.emit(action_key)
	return true


func active_weapon_key() -> String:
	return _active_action_key


func active_weapon_profile() -> Dictionary:
	return weapon_profile(_active_action_key)


func weapon_profile(action_key: String) -> Dictionary:
	if not _weapons.has(action_key):
		return {}
	return ((_weapons[action_key] as Dictionary)["profile"] as Dictionary).duplicate(true)


func weapon_state(action_key: String) -> Dictionary:
	if not _weapons.has(action_key):
		return {}
	var state := (_weapons[action_key] as Dictionary).duplicate(true)
	state["reserve"] = ammo_item_count(int(state["ammo_item_id"]))
	return state


func registered_weapon_keys() -> Array[String]:
	var result: Array[String] = []
	for action_key_value: Variant in _weapons:
		result.append(String(action_key_value))
	return result


func consume_active_attack() -> bool:
	return consume_attack(_active_action_key)


func can_consume_active_attack() -> bool:
	return can_consume_attack(_active_action_key)


func can_consume_attack(action_key: String) -> bool:
	if not _weapons.has(action_key):
		return false
	var state := _weapons[action_key] as Dictionary
	var capacity := int(state["magazine_capacity"])
	var ammunition := int(state["ammo_per_attack"])
	if capacity <= 0:
		var attack_type := int((state["profile"] as Dictionary).get("attack_type", 0))
		if attack_type in [4, 5, 11]:
			return true
		return ammunition > 0 and ammo_item_count(int(state["ammo_item_id"])) >= ammunition
	return ammunition > 0 and int(state["magazine"]) >= ammunition


func consume_attack(action_key: String) -> bool:
	if not can_consume_attack(action_key):
		return false
	var state := _weapons[action_key] as Dictionary
	var capacity := int(state["magazine_capacity"])
	# Recovered melee types 4/5 do not consume a stored item. Recovered type 11
	# also skips the item-removal path: sub_456DF0 sets a target flag but has no
	# item-99 consumption call. Types 8/10 consume mapped items 43/45 directly.
	if capacity <= 0:
		var attack_type := int((state["profile"] as Dictionary).get("attack_type", 0))
		if attack_type in [4, 5, 11]:
			return true
		var direct_item_cost := int(state["ammo_per_attack"])
		var direct_item_id := int(state["ammo_item_id"])
		remove_item(direct_item_id, direct_item_cost)
		return true
	var ammunition := int(state["ammo_per_attack"])
	state["magazine"] = int(state["magazine"]) - ammunition
	magazine_changed.emit(action_key, int(state["magazine"]))
	return true


func reload_active_weapon() -> int:
	return reload_weapon(_active_action_key)


func reload_weapon(action_key: String) -> int:
	if not _weapons.has(action_key):
		return 0
	var state := _weapons[action_key] as Dictionary
	var capacity := int(state["magazine_capacity"])
	var needed := maxi(capacity - int(state["magazine"]), 0)
	if needed <= 0:
		return 0
	var item_id := int(state["ammo_item_id"])
	var transferred := mini(needed, ammo_item_count(item_id))
	if transferred <= 0:
		return 0
	state["magazine"] = int(state["magazine"]) + transferred
	_items[item_id] = ammo_item_count(item_id) - transferred
	item_changed.emit(item_id, int(_items[item_id]))
	magazine_changed.emit(action_key, int(state["magazine"]))
	return transferred


func needs_reload(action_key: String = "") -> bool:
	var resolved_key := _active_action_key if action_key.is_empty() else action_key
	if not _weapons.has(resolved_key):
		return false
	var state := _weapons[resolved_key] as Dictionary
	return (
		int(state["magazine_capacity"]) > 0
		and int(state["magazine"]) < int(state["ammo_per_attack"])
		and ammo_item_count(int(state["ammo_item_id"])) > 0
	)


func add_item(item_id: int, quantity: int) -> int:
	if not supports_ammo_item(item_id) or quantity <= 0:
		return 0
	_items[item_id] = ammo_item_count(item_id) + quantity
	item_changed.emit(item_id, int(_items[item_id]))
	return quantity


func remove_item(item_id: int, quantity: int) -> int:
	if not supports_ammo_item(item_id) or quantity <= 0:
		return 0
	var removed := mini(ammo_item_count(item_id), quantity)
	_items[item_id] = ammo_item_count(item_id) - removed
	if removed > 0:
		item_changed.emit(item_id, int(_items[item_id]))
	return removed


func ammo_item_count(item_id: int) -> int:
	return int(_items.get(item_id, 0))


func item_snapshot() -> Dictionary:
	return _items.duplicate(true)


func full_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"active_action_key": _active_action_key,
		"items": _items.duplicate(true),
		"weapons": _weapons.duplicate(true),
	}


static func supports_ammo_item(item_id: int) -> bool:
	return item_id in SUPPORTED_AMMO_ITEM_IDS
