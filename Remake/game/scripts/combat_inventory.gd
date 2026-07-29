class_name CombatInventory
extends RefCounted

signal active_weapon_changed(action_key: String)
signal item_changed(item_id: int, quantity: int)
signal magazine_changed(action_key: String, magazine: int)

const SUPPORTED_AMMO_ITEM_IDS := [36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 99]
const ORIGINAL_QUANTITY_MODES := {
	36: 2,
	37: 2,
	38: 2,
	39: 1,
	40: 1,
	41: 0,
	42: 1,
	43: 0,
	44: 0,
	45: 0,
	99: 1,
}

var _items: Dictionary = {}
var _weapons: Dictionary = {}
var _active_action_key := ""
var _original_parity := false


func _init() -> void:
	_reset_items()


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
		"original_parity": false,
		"quantity_mode": -1,
		"owned": true,
	}
	_weapons[action_key] = state
	if load_profile_defaults:
		add_item(
			ammo_item_id,
			maxi(int(weapon_profile.get("starting_reserve_ammo", 0)), 0),
		)
	if _active_action_key.is_empty():
		_set_active_action_key(action_key)
	magazine_changed.emit(action_key, int(state["magazine"]))
	return true


func register_original_weapon(
	action_key: String,
	weapon_profile: Dictionary,
	quantity: int,
	quantity_mode: int,
	equip_now: bool = false,
) -> bool:
	if action_key.is_empty() or weapon_profile.is_empty() or quantity < 0:
		return false
	var item_id := int(weapon_profile.get("ammo_item_id", 0))
	if (
		not supports_ammo_item(item_id)
		or not ORIGINAL_QUANTITY_MODES.has(item_id)
		or int(ORIGINAL_QUANTITY_MODES[item_id]) != quantity_mode
	):
		return false
	var owned := quantity_mode == 2 or quantity > 0
	var state := {
		"action_key": action_key,
		"profile": weapon_profile.duplicate(true),
		"ammo_item_id": item_id,
		"magazine_capacity": 0,
		"magazine": quantity,
		"ammo_per_attack": maxi(int(weapon_profile.get("ammo_per_attack", 0)), 0),
		"original_parity": true,
		"quantity_mode": quantity_mode,
		"owned": owned,
	}
	_weapons[action_key] = state
	_items[item_id] = quantity
	_original_parity = true
	item_changed.emit(item_id, quantity)
	magazine_changed.emit(action_key, quantity)
	if owned and (_active_action_key.is_empty() or equip_now):
		_set_active_action_key(action_key)
	return true


func unregister_weapon(action_key: String) -> bool:
	if not _weapons.erase(action_key):
		return false
	if _active_action_key == action_key:
		_set_active_action_key(_first_owned_weapon_key())
	return true


func equip_weapon(action_key: String) -> bool:
	if not _weapon_is_owned(action_key):
		return false
	_set_active_action_key(action_key)
	return true


func active_weapon_key() -> String:
	return _active_action_key


func active_weapon_profile() -> Dictionary:
	return weapon_profile(_active_action_key)


func weapon_profile(action_key: String) -> Dictionary:
	if not _weapons.has(action_key):
		return {}
	var profile: Variant = (_weapons[action_key] as Dictionary).get("profile", {})
	return (profile as Dictionary).duplicate(true) if profile is Dictionary else {}


func weapon_state(action_key: String) -> Dictionary:
	if not _weapon_is_owned(action_key):
		return {}
	var state := (_weapons[action_key] as Dictionary).duplicate(true)
	var item_id := int(state.get("ammo_item_id", 0))
	if bool(state.get("original_parity", false)):
		var quantity := ammo_item_count(item_id)
		state["quantity"] = quantity
		state["magazine"] = quantity
		state["reserve"] = 0
	else:
		state["reserve"] = ammo_item_count(item_id)
	return state


func registered_weapon_keys() -> Array[String]:
	var result: Array[String] = []
	for action_key_value: Variant in _weapons:
		var action_key := str(action_key_value)
		if _weapon_is_owned(action_key):
			result.append(action_key)
	return result


func known_weapon_keys() -> Array[String]:
	var result: Array[String] = []
	for action_key_value: Variant in _weapons:
		result.append(str(action_key_value))
	return result


func consume_active_attack() -> bool:
	return consume_attack(_active_action_key)


func can_consume_active_attack() -> bool:
	return can_consume_attack(_active_action_key)


func can_consume_attack(action_key: String) -> bool:
	if not _weapon_is_owned(action_key):
		return false
	var state := _weapons[action_key] as Dictionary
	if bool(state.get("original_parity", false)):
		var quantity_mode := int(state.get("quantity_mode", -1))
		if quantity_mode == 1:
			return true
		var ammunition := maxi(int(state.get("ammo_per_attack", 0)), 0)
		return (
			ammunition > 0
			and ammo_item_count(int(state.get("ammo_item_id", 0))) >= ammunition
		)
	var capacity := int(state["magazine_capacity"])
	var ammunition := int(state["ammo_per_attack"])
	if capacity <= 0:
		var attack_type := int((state["profile"] as Dictionary).get("attack_type", 0))
		if attack_type in [4, 5, 11]:
			return true
		return (
			ammunition > 0
			and ammo_item_count(int(state["ammo_item_id"])) >= ammunition
		)
	return ammunition > 0 and int(state["magazine"]) >= ammunition


func consume_attack(action_key: String) -> bool:
	if not can_consume_attack(action_key):
		return false
	var state := _weapons[action_key] as Dictionary
	if bool(state.get("original_parity", false)):
		var quantity_mode := int(state.get("quantity_mode", -1))
		if quantity_mode == 1:
			return true
		var item_id := int(state.get("ammo_item_id", 0))
		var ammunition := maxi(int(state.get("ammo_per_attack", 0)), 0)
		var remaining := maxi(ammo_item_count(item_id) - ammunition, 0)
		_items[item_id] = remaining
		state["magazine"] = remaining
		if quantity_mode == 0 and remaining == 0:
			state["owned"] = false
			if _active_action_key == action_key:
				_set_active_action_key(_first_owned_weapon_key())
		item_changed.emit(item_id, remaining)
		magazine_changed.emit(action_key, remaining)
		return true
	var capacity := int(state["magazine_capacity"])
	# The compatibility model remains available for schema-1 saves and focused
	# tests. Product levels use register_original_weapon(), which follows the
	# recovered direct-count quantity modes above.
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
	if not _weapon_is_owned(action_key):
		return 0
	var state := _weapons[action_key] as Dictionary
	if bool(state.get("original_parity", false)):
		return 0
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
	if not _weapon_is_owned(resolved_key):
		return false
	var state := _weapons[resolved_key] as Dictionary
	if bool(state.get("original_parity", false)):
		return false
	return (
		int(state["magazine_capacity"]) > 0
		and int(state["magazine"]) < int(state["ammo_per_attack"])
		and ammo_item_count(int(state["ammo_item_id"])) > 0
	)


func add_item(item_id: int, quantity: int) -> int:
	if not supports_ammo_item(item_id) or quantity <= 0:
		return 0
	_items[item_id] = ammo_item_count(item_id) + quantity
	for action_key_value: Variant in _weapons:
		var state := _weapons[action_key_value] as Dictionary
		if (
			bool(state.get("original_parity", false))
			and int(state.get("ammo_item_id", 0)) == item_id
		):
			state["owned"] = true
			state["magazine"] = int(_items[item_id])
			if _active_action_key.is_empty():
				_set_active_action_key(str(action_key_value))
	item_changed.emit(item_id, int(_items[item_id]))
	return quantity


func remove_item(item_id: int, quantity: int) -> int:
	if not supports_ammo_item(item_id) or quantity <= 0:
		return 0
	var removed := mini(ammo_item_count(item_id), quantity)
	_items[item_id] = ammo_item_count(item_id) - removed
	if removed <= 0:
		return 0
	for action_key_value: Variant in _weapons:
		var action_key := str(action_key_value)
		var state := _weapons[action_key_value] as Dictionary
		if (
			bool(state.get("original_parity", false))
			and int(state.get("ammo_item_id", 0)) == item_id
		):
			state["magazine"] = int(_items[item_id])
			if (
				int(_items[item_id]) == 0
				and int(state.get("quantity_mode", -1)) != 2
			):
				state["owned"] = false
				if _active_action_key == action_key:
					_set_active_action_key(_first_owned_weapon_key())
	item_changed.emit(item_id, int(_items[item_id]))
	return removed


func ammo_item_count(item_id: int) -> int:
	return int(_items.get(item_id, 0))


func item_snapshot() -> Dictionary:
	return _items.duplicate(true)


func original_parity_enabled() -> bool:
	return _original_parity


func original_quantity_mode(item_id: int) -> int:
	return int(ORIGINAL_QUANTITY_MODES.get(item_id, -1))


func full_snapshot() -> Dictionary:
	return {
		"schema_version": 2,
		"original_parity": _original_parity,
		"active_action_key": _active_action_key,
		"items": _items.duplicate(true),
		"weapons": _weapons.duplicate(true),
	}


func take_all_original_drops(
	preferred_order: Array[String] = [],
) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if not _original_parity:
		# Synthetic/schema-1 compatibility inventories do not claim original
		# death-drop semantics and must not be cleared by this exact path.
		return drops
	var order: Array[String] = []
	for action_key: String in preferred_order:
		if _weapons.has(action_key) and not order.has(action_key):
			order.append(action_key)
	for action_key_value: Variant in _weapons.keys():
		var action_key := str(action_key_value)
		if not order.has(action_key):
			order.append(action_key)
	for action_key: String in order:
		var state_value: Variant = _weapons.get(action_key)
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		if not bool(state.get("original_parity", false)):
			continue
		var item_id := int(state.get("ammo_item_id", 0))
		var quantity_mode := int(state.get("quantity_mode", -1))
		var quantity := ammo_item_count(item_id)
		if (
			not supports_ammo_item(item_id)
			or not bool(state.get("owned", false))
			or quantity_mode < 0
		):
			continue
		drops.append({
			"action_key": action_key,
			"item_id": item_id,
			"quantity": quantity,
			"quantity_mode": quantity_mode,
			"profile": (state.get("profile", {}) as Dictionary).duplicate(true),
		})
	_weapons.clear()
	_active_action_key = ""
	_original_parity = false
	_reset_items()
	return drops


func restore_snapshot(snapshot: Dictionary) -> bool:
	_weapons.clear()
	_active_action_key = ""
	_original_parity = false
	_reset_items()
	var schema_version := int(snapshot.get("schema_version", 1))
	if schema_version <= 1:
		return _restore_schema_1_as_original(snapshot)
	if schema_version != 2:
		return false
	_restore_items(snapshot.get("items", {}))
	var raw_weapons: Variant = snapshot.get("weapons", {})
	if not raw_weapons is Dictionary:
		return false
	for raw_key: Variant in (raw_weapons as Dictionary).keys():
		var action_key := str(raw_key)
		var raw_state: Variant = (raw_weapons as Dictionary)[raw_key]
		if action_key.is_empty() or not raw_state is Dictionary:
			continue
		var state := (raw_state as Dictionary).duplicate(true)
		var profile: Variant = state.get("profile", {})
		var item_id := int(state.get("ammo_item_id", 0))
		if (
			not profile is Dictionary
			or not supports_ammo_item(item_id)
		):
			continue
		state["action_key"] = action_key
		state["profile"] = (profile as Dictionary).duplicate(true)
		state["ammo_item_id"] = item_id
		state["ammo_per_attack"] = maxi(int(state.get("ammo_per_attack", 0)), 0)
		var is_original := bool(state.get("original_parity", false))
		state["original_parity"] = is_original
		if is_original:
			var quantity_mode := int(
				state.get(
					"quantity_mode",
					ORIGINAL_QUANTITY_MODES.get(item_id, -1),
				)
			)
			if (
				not ORIGINAL_QUANTITY_MODES.has(item_id)
				or quantity_mode != int(ORIGINAL_QUANTITY_MODES[item_id])
			):
				continue
			state["quantity_mode"] = quantity_mode
			state["magazine_capacity"] = 0
			state["magazine"] = ammo_item_count(item_id)
			state["owned"] = (
				true
				if quantity_mode == 2
				else bool(
					state.get(
						"owned",
						ammo_item_count(item_id) > 0,
					)
				)
			)
			_original_parity = true
		else:
			state["quantity_mode"] = -1
			state["magazine_capacity"] = maxi(
				int(state.get("magazine_capacity", 0)),
				0,
			)
			state["magazine"] = maxi(int(state.get("magazine", 0)), 0)
			state["owned"] = bool(state.get("owned", true))
		_weapons[action_key] = state
	var requested_active := str(snapshot.get("active_action_key", ""))
	_active_action_key = (
		requested_active
		if _weapon_is_owned(requested_active)
		else _first_owned_weapon_key()
	)
	return true


func _restore_schema_1_as_original(snapshot: Dictionary) -> bool:
	var raw_items: Variant = snapshot.get("items", {})
	var source_items: Dictionary = {}
	if raw_items is Dictionary:
		for raw_key: Variant in (raw_items as Dictionary).keys():
			var item_id := int(str(raw_key))
			if supports_ammo_item(item_id):
				source_items[item_id] = maxi(
					int((raw_items as Dictionary)[raw_key]),
					0,
				)
	var raw_weapons: Variant = snapshot.get("weapons", {})
	if raw_weapons is Dictionary:
		for raw_key: Variant in (raw_weapons as Dictionary).keys():
			var action_key := str(raw_key)
			var raw_state: Variant = (raw_weapons as Dictionary)[raw_key]
			if action_key.is_empty() or not raw_state is Dictionary:
				continue
			var old_state := raw_state as Dictionary
			var profile: Variant = old_state.get("profile", {})
			var item_id := int(old_state.get("ammo_item_id", 0))
			if (
				not profile is Dictionary
				or not ORIGINAL_QUANTITY_MODES.has(item_id)
			):
				continue
			var quantity_mode := int(ORIGINAL_QUANTITY_MODES[item_id])
			var quantity := int(source_items.get(item_id, 0))
			if int(old_state.get("magazine_capacity", 0)) > 0:
				quantity += maxi(int(old_state.get("magazine", 0)), 0)
			elif quantity_mode == 1 and quantity <= 0:
				quantity = 1
			register_original_weapon(
				action_key,
				(profile as Dictionary).duplicate(true),
				quantity,
				quantity_mode,
				false,
			)
	# Preserve unsupported/no-profile item dictionaries from early saves.
	for item_id_value: Variant in source_items.keys():
		var item_id := int(item_id_value)
		if ammo_item_count(item_id) == 0:
			_items[item_id] = int(source_items[item_id])
	_original_parity = true
	var requested_active := str(snapshot.get("active_action_key", ""))
	_active_action_key = (
		requested_active
		if _weapon_is_owned(requested_active)
		else _first_owned_weapon_key()
	)
	return true


func _restore_items(raw_items: Variant) -> void:
	if not raw_items is Dictionary:
		return
	for raw_key: Variant in (raw_items as Dictionary).keys():
		var item_id := int(str(raw_key))
		if supports_ammo_item(item_id):
			_items[item_id] = maxi(int((raw_items as Dictionary)[raw_key]), 0)


func _reset_items() -> void:
	_items.clear()
	for item_id: int in SUPPORTED_AMMO_ITEM_IDS:
		_items[item_id] = 0


func _weapon_is_owned(action_key: String) -> bool:
	if action_key.is_empty() or not _weapons.has(action_key):
		return false
	var state := _weapons[action_key] as Dictionary
	return bool(state.get("owned", true))


func _first_owned_weapon_key() -> String:
	for action_key_value: Variant in _weapons:
		var action_key := str(action_key_value)
		if _weapon_is_owned(action_key):
			return action_key
	return ""


func _set_active_action_key(action_key: String) -> void:
	var resolved := action_key if _weapon_is_owned(action_key) else ""
	if _active_action_key == resolved:
		return
	_active_action_key = resolved
	active_weapon_changed.emit(_active_action_key)


static func supports_ammo_item(item_id: int) -> bool:
	return item_id in SUPPORTED_AMMO_ITEM_IDS
