class_name LegacyBurialCache
extends Node2D

const WORLD_DEPTH: Script = preload("res://scripts/world_depth.gd")

## Recovered from DBL entry 1001 (`藏尸处.spr`).
const ORIGINAL_ACTOR_TYPE := 78
const ORIGINAL_GFL_INDEX := 64
const INTERACTION_RADIUS := 48.0

var original_actor_type := ORIGINAL_ACTOR_TYPE
var original_gfl_index := ORIGINAL_GFL_INDEX
var source_enemy_scene_index := -1
var weapon_inventory_snapshot: Dictionary = {}
var backpack_inventory_snapshot: Dictionary = {}
var original_frames: Array[Texture2D] = []
var original_frame_hold_ticks := 1
var original_frame_index := 0
var age_world_ticks := 0


func configure(
	world_position: Vector2,
	source_scene_index: int,
	weapon_snapshot: Dictionary,
	backpack_snapshot: Dictionary,
	visual: Variant = null,
) -> bool:
	position = world_position
	source_enemy_scene_index = source_scene_index
	weapon_inventory_snapshot = weapon_snapshot.duplicate(true)
	backpack_inventory_snapshot = backpack_snapshot.duplicate(true)
	age_world_ticks = 0
	_set_visual(visual)
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	queue_redraw()
	return true


func contains_parent_point(parent_point: Vector2) -> bool:
	return position.distance_squared_to(parent_point) <= 24.0 * 24.0


func can_interact(collector: Node2D) -> bool:
	return (
		collector != null
		and is_instance_valid(collector)
		and bool(collector.get("is_alive"))
		and global_position.distance_squared_to(collector.global_position)
		<= INTERACTION_RADIUS * INTERACTION_RADIUS
	)


func has_loot() -> bool:
	var weapon_items: Variant = weapon_inventory_snapshot.get("items", {})
	if weapon_items is Dictionary:
		for value: Variant in (weapon_items as Dictionary).values():
			if int(value) > 0:
				return true
	var weapons: Variant = weapon_inventory_snapshot.get("weapons", {})
	if weapons is Dictionary:
		for state_value: Variant in (weapons as Dictionary).values():
			if state_value is Dictionary and bool((state_value as Dictionary).get("owned", false)):
				return true
	var backpack_entries: Variant = backpack_inventory_snapshot.get("entries", [])
	if backpack_entries is Array:
		for entry_value: Variant in backpack_entries as Array:
			if entry_value is Dictionary and int((entry_value as Dictionary).get("quantity", 0)) > 0:
				return true
	return false


func transfer_all_to(collector: Node2D) -> Dictionary:
	if not can_interact(collector):
		return {}
	var transferred_weapon_entries := 0
	var transferred_weapon_quantity := 0
	var no_attack_groups: Array[Dictionary] = []
	var raw_weapons: Variant = weapon_inventory_snapshot.get("weapons", {})
	var raw_items: Variant = weapon_inventory_snapshot.get("items", {})
	if raw_weapons is Dictionary and raw_items is Dictionary:
		for action_key_value: Variant in (raw_weapons as Dictionary).keys():
			var state_value: Variant = (raw_weapons as Dictionary)[action_key_value]
			if not state_value is Dictionary:
				continue
			var state := state_value as Dictionary
			var item_id := int(state.get("ammo_item_id", 0))
			var quantity := _dictionary_int(raw_items as Dictionary, item_id)
			var quantity_mode := int(state.get("quantity_mode", -1))
			var profile_value: Variant = state.get("profile", {})
			if (
				not bool(state.get("owned", false))
				or not profile_value is Dictionary
				or quantity_mode < 0
			):
				continue
			var action_key := str(action_key_value)
			var accepted := false
			if collector.has_method("has_inventory_weapon") and bool(
				collector.call("has_inventory_weapon", action_key)
			):
				if quantity > 0 and collector.has_method("add_ammo_item"):
					accepted = int(collector.call("add_ammo_item", item_id, quantity)) > 0
				elif quantity_mode == 1:
					accepted = true
			elif collector.has_method("register_original_inventory_weapon"):
				accepted = bool(
					collector.call(
						"register_original_inventory_weapon",
						(profile_value as Dictionary).duplicate(true),
						no_attack_groups,
						quantity,
						quantity_mode,
						false,
					)
				)
			if accepted:
				transferred_weapon_entries += 1
				transferred_weapon_quantity += quantity
	weapon_inventory_snapshot = {}

	var transferred_backpack_entries := 0
	var transferred_backpack_quantity := 0
	var raw_entries: Variant = backpack_inventory_snapshot.get("entries", [])
	if raw_entries is Array and collector.has_method("add_backpack_item"):
		for entry_value: Variant in raw_entries as Array:
			if not entry_value is Dictionary:
				continue
			var entry := entry_value as Dictionary
			var quantity := maxi(int(entry.get("quantity", 0)), 0)
			if quantity <= 0:
				continue
			var accepted := int(
				collector.call(
					"add_backpack_item",
					int(entry.get("item_id", 0)),
					quantity,
					int(entry.get("quantity_mode", 0)),
				)
			)
			if accepted > 0:
				transferred_backpack_entries += 1
				transferred_backpack_quantity += accepted
	backpack_inventory_snapshot = {}
	queue_redraw()
	return {
		"weapon_entries": transferred_weapon_entries,
		"weapon_quantity": transferred_weapon_quantity,
		"backpack_entries": transferred_backpack_entries,
		"backpack_quantity": transferred_backpack_quantity,
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"original_actor_type": original_actor_type,
		"original_gfl_index": original_gfl_index,
		"source_enemy_scene_index": source_enemy_scene_index,
		"x": position.x,
		"y": position.y,
		"weapon_inventory": weapon_inventory_snapshot.duplicate(true),
		"backpack_inventory": backpack_inventory_snapshot.duplicate(true),
		"age_world_ticks": age_world_ticks,
	}


func restore_runtime_state(value: Dictionary) -> bool:
	if (
		int(value.get("original_actor_type", ORIGINAL_ACTOR_TYPE)) != ORIGINAL_ACTOR_TYPE
		or int(value.get("original_gfl_index", ORIGINAL_GFL_INDEX)) != ORIGINAL_GFL_INDEX
	):
		return false
	position = Vector2(float(value.get("x", position.x)), float(value.get("y", position.y)))
	source_enemy_scene_index = int(
		value.get("source_enemy_scene_index", source_enemy_scene_index)
	)
	var weapon_value: Variant = value.get("weapon_inventory", {})
	var backpack_value: Variant = value.get("backpack_inventory", {})
	weapon_inventory_snapshot = (
		(weapon_value as Dictionary).duplicate(true)
		if weapon_value is Dictionary
		else {}
	)
	backpack_inventory_snapshot = (
		(backpack_value as Dictionary).duplicate(true)
		if backpack_value is Dictionary
		else {}
	)
	age_world_ticks = maxi(int(value.get("age_world_ticks", 0)), 0)
	_update_frame()
	z_index = WORLD_DEPTH.normal_z(position.y, 1)
	queue_redraw()
	return true


func _physics_process(_delta: float) -> void:
	age_world_ticks += 1
	_update_frame()
	queue_redraw()


func _set_visual(visual: Variant) -> void:
	original_frames.clear()
	original_frame_hold_ticks = 1
	if visual is Texture2D:
		original_frames.append(visual as Texture2D)
	elif visual is Dictionary:
		var raw_frames: Variant = (visual as Dictionary).get("frames", [])
		if raw_frames is Array:
			for raw_frame: Variant in raw_frames as Array:
				if raw_frame is Texture2D:
					original_frames.append(raw_frame as Texture2D)
		original_frame_hold_ticks = maxi(
			int((visual as Dictionary).get("frame_hold_ticks", 1)),
			1,
		)
	_update_frame()


func _update_frame() -> void:
	if original_frames.size() <= 1:
		original_frame_index = 0
		return
	original_frame_index = (
		age_world_ticks / original_frame_hold_ticks
	) % original_frames.size()


func _draw() -> void:
	if not original_frames.is_empty():
		var frame: Texture2D = original_frames[
			clampi(original_frame_index, 0, original_frames.size() - 1)
		]
		draw_texture(frame, -frame.get_size() * 0.5)
		return
	var color := Color(0.36, 0.29, 0.19, 0.96)
	draw_rect(Rect2(-15.0, -7.0, 30.0, 14.0), color, true)
	draw_arc(Vector2.ZERO, 18.0, PI, TAU, 16, Color(0.65, 0.54, 0.34), 1.5)


static func _dictionary_int(dictionary: Dictionary, numeric_key: int) -> int:
	if dictionary.has(numeric_key):
		return int(dictionary[numeric_key])
	var string_key := str(numeric_key)
	return int(dictionary.get(string_key, 0))
