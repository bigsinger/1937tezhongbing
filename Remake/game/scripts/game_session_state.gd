class_name GameSessionState
extends RefCounted

## Captures and restores the mutable portion of Main's current level.
##
## Node references, textures, navigation caches and signal connections never
## enter JSON.  The caller first switches to `session.level_id`, then invokes
## `apply_after_level_loaded()` so the imported level supplies those resources.

const COMBAT_INVENTORY: Script = preload("res://scripts/combat_inventory.gd")
const LAND_MINE: Script = preload("res://scripts/land_mine.gd")
const MISSION_PICKUP: Script = preload("res://scripts/mission_pickup.gd")
const SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")


static func capture(game: Node) -> Dictionary:
	if game == null:
		return {}
	var current_mission: Dictionary = _dictionary_property(game, "current_mission")
	var level_id := str(current_mission.get("id", ""))
	if level_id.is_empty():
		level_id = str(current_mission.get("level_id", "m000"))
	if not SAVE_STORE.is_valid_level_id(level_id):
		level_id = "m000"
	var session: Dictionary = SAVE_STORE.empty_session(level_id)
	var mission_state: Variant = game.get("current_mission_state")
	if mission_state != null:
		session["elapsed_seconds"] = maxf(float(mission_state.get("elapsed_seconds")), 0.0)
		session["mission"] = _capture_mission(game, mission_state)
	var camera: Variant = game.get("level_camera")
	if camera is Camera2D:
		var camera_node := camera as Camera2D
		session["camera"] = {
			"x": camera_node.position.x,
			"y": camera_node.position.y,
			"zoom": camera_node.zoom.x,
		}
	for group_name: String in ["units", "enemies", "escorts"]:
		var output_name := "squad" if group_name == "units" else group_name
		var actors: Array = _array_property(game, group_name)
		var records: Array = []
		for actor_value: Variant in actors:
			if actor_value is Node2D and is_instance_valid(actor_value):
				records.append(_capture_actor(actor_value as Node2D, group_name))
		session[output_name] = records
	session["world"] = _capture_world(game)
	return session


static func apply_after_level_loaded(game: Node, session: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	if game == null or not SAVE_STORE.is_valid_level_id(str(session.get("level_id", ""))):
		return {"ok": false, "warnings": ["invalid game or session"]}
	_restore_mission(game, session.get("mission", {}) as Dictionary, float(session.get("elapsed_seconds", 0.0)))
	var records_by_group := {
		"units": session.get("squad", []),
		"enemies": session.get("enemies", []),
		"escorts": session.get("escorts", []),
	}
	for group_name: String in records_by_group:
		_restore_actor_group(
			game,
			group_name,
			records_by_group[group_name] as Array,
			warnings,
		)
	_restore_enemy_targets(game, records_by_group["enemies"] as Array)
	_restore_selection(game)
	var occupancy: Variant = game.get("dynamic_occupancy")
	if occupancy != null and occupancy.has_method("finalize_registration"):
		occupancy.call("finalize_registration")
	_restore_world(game, session.get("world", {}) as Dictionary, warnings)
	_sync_projectile_combatants(game)
	_restore_camera(game, session.get("camera", {}) as Dictionary)
	if game.has_method("_refresh_mission_ui"):
		game.call("_refresh_mission_ui")
	if game.has_method("_refresh_inventory_ui"):
		game.call("_refresh_inventory_ui")
	game.queue_redraw()
	return {"ok": true, "warnings": warnings}


static func _capture_mission(game: Node, mission_state: Variant) -> Dictionary:
	var seen_output: Dictionary = {}
	var raw_seen: Variant = mission_state.get("seen_values")
	if raw_seen is Dictionary:
		for objective_key: Variant in (raw_seen as Dictionary).keys():
			var objective_seen: Variant = (raw_seen as Dictionary)[objective_key]
			var values: Array = []
			if objective_seen is Dictionary:
				for seen_key: Variant in (objective_seen as Dictionary).keys():
					values.append(_json_value(seen_key))
			seen_output[str(objective_key)] = values
	var mission := {
		"completed": _json_dictionary(mission_state.get("completed")),
		"progress": _json_dictionary(mission_state.get("progress")),
		"seen_values": seen_output,
		"failure_id": str(mission_state.get("failure_id")),
		"durable_facts": [],
		"applied_fact_objectives": {},
	}
	var mission_runtime: Variant = game.get("mission_runtime")
	if mission_runtime != null:
		mission["durable_facts"] = _json_value(mission_runtime.get("_durable_facts"))
		mission["applied_fact_objectives"] = _json_dictionary(
			mission_runtime.get("_applied_fact_objectives")
		)
	return mission


static func _capture_actor(actor: Node2D, group_name: String) -> Dictionary:
	var record := {
		"display_name": str(actor.get("display_name")),
		"scene_index": int(actor.get("scene_index")),
		"x": actor.position.x,
		"y": actor.position.y,
		"faction_id": int(actor.get("faction_id")),
		"current_hit_points": int(actor.get("current_hit_points")),
		"maximum_hit_points": int(actor.get("maximum_hit_points")),
		"is_alive": bool(actor.get("is_alive")),
		"is_crawling": bool(actor.get("is_crawling")),
		"selected": bool(actor.get("selected")) if group_name == "units" else false,
	}
	if actor.has_method("inventory_snapshot"):
		record["inventory"] = _json_value(actor.call("inventory_snapshot"))
		record["inventory_weapon_order"] = _json_value(actor.get("inventory_weapon_order"))
	if group_name == "enemies":
		var current_target: Variant = actor.get("current_target")
		record["ai"] = {
			"behavior_state": int(actor.get("behavior_state")),
			"patrol_index": int(actor.get("patrol_index")),
			"patrol_enabled": bool(actor.get("patrol_enabled")),
			"last_known_x": (actor.get("last_known_target_position") as Vector2).x,
			"last_known_y": (actor.get("last_known_target_position") as Vector2).y,
			"search_elapsed": float(actor.get("search_elapsed")),
			"attack_count": int(actor.get("attack_count")),
			"current_target_scene_index": (
				int((current_target as Node).get("scene_index"))
				if current_target is Node and is_instance_valid(current_target)
				else -1
			),
			"current_target_display_name": _actor_display_name(current_target),
		}
	elif group_name == "escorts":
		var follow_target: Variant = actor.get("follow_target")
		record["escort"] = {
			"rescued": bool(actor.get("rescued_state")),
			"follow_scene_index": (
				int((follow_target as Node).get("scene_index"))
				if follow_target is Node and is_instance_valid(follow_target)
				else -1
			),
			"follow_display_name": _actor_display_name(follow_target),
		}
	return record


static func _capture_world(game: Node) -> Dictionary:
	var world := {
		"activated_scene_indices": _sorted_integer_keys(
			_dictionary_property(game, "activated_mission_scenes")
		),
		"collected_scene_indices": [],
		"destroyed_scene_indices": [],
		"remaining_field_pickup_scene_indices": [],
		"explosive_props": [],
		"mission_pickups": [],
		"field_inventory": _json_dictionary(game.get("field_inventory")),
		"deployed_mines": [],
		"projectiles": [],
	}
	for pickup_value: Variant in _array_property(game, "field_pickups"):
		if pickup_value is Node and is_instance_valid(pickup_value) and not bool((pickup_value as Node).get("consumed")):
			(world["remaining_field_pickup_scene_indices"] as Array).append(int((pickup_value as Node).get("scene_index")))
	for prop_value: Variant in _array_property(game, "explosive_props"):
		if prop_value is Node2D and is_instance_valid(prop_value) and not bool((prop_value as Node2D).get("has_exploded")):
			var prop := prop_value as Node2D
			(world["explosive_props"] as Array).append(
				{
					"scene_index": int(prop.get("scene_index")),
					"hit_points": int(prop.get("hit_points")),
				}
			)
	for pickup_value: Variant in _array_property(game, "mission_pickups"):
		if pickup_value is Node2D and is_instance_valid(pickup_value) and not bool((pickup_value as Node2D).get("collected")):
			var pickup := pickup_value as Node2D
			(world["mission_pickups"] as Array).append(
				{
					"x": pickup.position.x,
					"y": pickup.position.y,
					"payload": _json_dictionary(pickup.get("item_payload")),
				}
			)
	for mine_value: Variant in _array_property(game, "deployed_mines"):
		if mine_value is Node2D and is_instance_valid(mine_value):
			var mine := mine_value as Node2D
			if int(mine.get("state")) in [4, 5]:
				continue
			(world["deployed_mines"] as Array).append(_capture_mine(mine))
	var projectile_world: Variant = game.get("projectile_world")
	if projectile_world is Node:
		for child: Node in (projectile_world as Node).get_children():
			if child is Node2D and child.has_method("is_resolved") and not bool(child.call("is_resolved")):
				(world["projectiles"] as Array).append(_capture_projectile(child as Node2D))
	return world


static func _capture_mine(mine: Node2D) -> Dictionary:
	var owner: Variant = mine.get("owner_actor")
	return {
		"x": mine.position.x,
		"y": mine.position.y,
		"owner_scene_index": int((owner as Node).get("scene_index")) if owner is Node and is_instance_valid(owner) else -1,
		"owner_display_name": _actor_display_name(owner),
		"faction_id": int(mine.get("faction_id")),
		"state": int(mine.get("state")),
		"state_elapsed": float(mine.get("state_elapsed")),
		"arm_delay_seconds": float(mine.get("arm_delay_seconds")),
		"trigger_horizontal_radius": float(mine.get("trigger_horizontal_radius")),
		"trigger_vertical_radius": float(mine.get("trigger_vertical_radius")),
		"detonation_delay_seconds": float(mine.get("detonation_delay_seconds")),
		"blast_damage": int(mine.get("blast_damage")),
		"blast_horizontal_radius": float(mine.get("blast_horizontal_radius")),
		"blast_vertical_radius": float(mine.get("blast_vertical_radius")),
		"resolved_visual_seconds": float(mine.get("resolved_visual_seconds")),
	}


static func _capture_projectile(projectile: Node2D) -> Dictionary:
	var source: Variant = projectile.get("source")
	var target: Variant = projectile.get("primary_target")
	var start := projectile.get("start_world_position") as Vector2
	var destination := projectile.get("destination") as Vector2
	return {
		"source_scene_index": int((source as Node).get("scene_index")) if source is Node and is_instance_valid(source) else -1,
		"target_scene_index": int((target as Node).get("scene_index")) if target is Node and is_instance_valid(target) else -1,
		"source_display_name": _actor_display_name(source),
		"target_display_name": _actor_display_name(target),
		"start_x": start.x,
		"start_y": start.y,
		"destination_x": destination.x,
		"destination_y": destination.y,
		"flight_duration": float(projectile.get("flight_duration")),
		"flight_elapsed": float(projectile.get("flight_elapsed")),
		"landed_elapsed": float(projectile.get("landed_elapsed")),
		"state": int(projectile.get("state")),
		"weapon_profile": _json_dictionary(projectile.get("weapon_profile")),
	}


static func _restore_mission(game: Node, mission: Dictionary, elapsed_seconds: float) -> void:
	var mission_state: Variant = game.get("current_mission_state")
	if mission_state == null:
		return
	mission_state.set("completed", _string_dictionary(mission.get("completed", {})))
	mission_state.set("progress", _string_dictionary(mission.get("progress", {})))
	var seen: Dictionary = {}
	var raw_seen: Variant = mission.get("seen_values", {})
	if raw_seen is Dictionary:
		for objective_key: Variant in (raw_seen as Dictionary).keys():
			var objective_seen: Dictionary = {}
			var values: Variant = (raw_seen as Dictionary)[objective_key]
			if values is Array:
				for seen_value: Variant in values as Array:
					objective_seen[_restored_scalar(seen_value)] = true
			seen[str(objective_key)] = objective_seen
	mission_state.set("seen_values", seen)
	mission_state.set("elapsed_seconds", maxf(elapsed_seconds, 0.0))
	mission_state.set("failure_id", str(mission.get("failure_id", "")))
	var runtime: Variant = game.get("mission_runtime")
	if runtime != null:
		var facts: Array[Dictionary] = []
		for fact_value: Variant in mission.get("durable_facts", []) as Array:
			if fact_value is Dictionary:
				facts.append((fact_value as Dictionary).duplicate(true))
		runtime.set("_durable_facts", facts)
		var fact_keys: Dictionary = {}
		for fact_value: Variant in facts:
			if fact_value is Dictionary:
				fact_keys[str((fact_value as Dictionary).get("key", ""))] = true
		runtime.set("_durable_fact_keys", fact_keys)
		runtime.set(
			"_applied_fact_objectives",
			_string_dictionary(mission.get("applied_fact_objectives", {})),
		)
		runtime.set("_reported_victory", bool(mission_state.call("is_victory")))
		runtime.set("_reported_failure_id", str(mission_state.get("failure_id")))


static func _restore_actor_group(
	game: Node,
	group_name: String,
	records: Array,
	warnings: Array[String],
) -> void:
	var actors := _array_property(game, group_name)
	var actors_by_scene: Dictionary = {}
	for actor_value: Variant in actors:
		if actor_value is Node2D and is_instance_valid(actor_value):
			var actor := actor_value as Node2D
			var scene_index := int(actor.get("scene_index"))
			if scene_index >= 0:
				actors_by_scene[scene_index] = actor
	var claimed_actor_ids: Dictionary = {}
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var record_scene_index := int(record.get("scene_index", -1))
		var actor: Node2D = null
		if record_scene_index >= 0:
			actor = actors_by_scene.get(record_scene_index) as Node2D
			if actor != null and claimed_actor_ids.has(actor.get_instance_id()):
				actor = null
		if actor == null:
			var display_name := str(record.get("display_name", ""))
			for actor_value: Variant in actors:
				if (
					actor_value is Node2D
					and is_instance_valid(actor_value)
					and not claimed_actor_ids.has((actor_value as Node2D).get_instance_id())
					and str((actor_value as Node2D).get("display_name")) == display_name
				):
					actor = actor_value as Node2D
					break
		if actor == null:
			warnings.append("actor not found: %s" % str(record.get("display_name", "?")))
			continue
		claimed_actor_ids[actor.get_instance_id()] = true
		_restore_actor(game, actor, record, group_name)


static func _restore_actor(game: Node, actor: Node2D, record: Dictionary, group_name: String) -> void:
	var occupancy: Variant = game.get("dynamic_occupancy")
	var scene_index := int(actor.get("scene_index"))
	if occupancy != null and scene_index >= 0:
		occupancy.call("unregister_scene", scene_index)
	actor.position = Vector2(float(record.get("x", actor.position.x)), float(record.get("y", actor.position.y)))
	actor.set("target_position", actor.position)
	actor.call("cancel_path")
	actor.set("faction_id", int(record.get("faction_id", actor.get("faction_id"))))
	actor.set("maximum_hit_points", maxi(int(record.get("maximum_hit_points", 1)), 1))
	var alive := bool(record.get("is_alive", true))
	actor.set("is_alive", alive)
	actor.set("current_hit_points", clampi(int(record.get("current_hit_points", 0)), 0, int(actor.get("maximum_hit_points"))))
	actor.set("is_crawling", bool(record.get("is_crawling", false)))
	actor.set("selected", bool(record.get("selected", false)) and alive and group_name == "units")
	actor.set("auto_combat_enabled", false)
	actor.set("combat_target", null)
	if record.get("inventory") is Dictionary:
		_restore_inventory(game, actor, record)
	if alive:
		actor.set("death_emitted", false)
		actor.set("combat_action", 0)
		actor.set("action_finished", true)
		if occupancy != null and scene_index >= 0:
			var source_position: Variant = null
			var entities := _dictionary_property(game, "world_entities_by_scene")
			if entities.has(scene_index):
				var entity := entities[scene_index] as Dictionary
				source_position = Vector2(float(entity.get("reference_x", actor.position.x)), float(entity.get("reference_y", actor.position.y)))
			actor.set("dynamic_registered", bool(occupancy.call("register_scene", scene_index, actor.position, source_position)))
		actor.call("apply_idle_frame")
	else:
		actor.set("current_hit_points", 0)
		actor.set("dynamic_registered", false)
		actor.set("death_emitted", true)
		actor.call("_start_one_shot", 3, actor.get("death_groups"))
		actor.call("_advance_combat_action", 999.0)
	if group_name == "enemies" and record.get("ai") is Dictionary:
		var ai := record["ai"] as Dictionary
		actor.set("behavior_state", int(ai.get("behavior_state", 0)))
		actor.set("patrol_index", int(ai.get("patrol_index", 0)))
		actor.set("patrol_enabled", bool(ai.get("patrol_enabled", true)))
		actor.set("last_known_target_position", Vector2(float(ai.get("last_known_x", 0.0)), float(ai.get("last_known_y", 0.0))))
		actor.set("search_elapsed", float(ai.get("search_elapsed", 0.0)))
		actor.set("attack_count", int(ai.get("attack_count", 0)))
	elif group_name == "escorts" and record.get("escort") is Dictionary:
		var escort := record["escort"] as Dictionary
		actor.set("rescued_state", bool(escort.get("rescued", false)))
		if bool(escort.get("rescued", false)):
			actor.set("faction_id", 3)
			var follow := _find_actor_by_identity(
				game,
				int(escort.get("follow_scene_index", -1)),
				str(escort.get("follow_display_name", "")),
			)
			if follow == null:
				follow = _first_living_actor(_array_property(game, "units"))
			actor.set("follow_target", follow)
	actor.set("z_index", clampi(int(actor.position.y) + 1, -4096, 4095))
	actor.queue_redraw()


static func _restore_enemy_targets(game: Node, records: Array) -> void:
	var actors_by_scene: Dictionary = {}
	var enemies := _array_property(game, "enemies")
	for actor_value: Variant in _array_property(game, "enemies"):
		if actor_value is Node2D and is_instance_valid(actor_value):
			var scene_index := int((actor_value as Node2D).get("scene_index"))
			if scene_index >= 0:
				actors_by_scene[scene_index] = actor_value
	var matched_actor_ids: Dictionary = {}
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var record_scene_index := int(record.get("scene_index", -1))
		var actor: Node2D = actors_by_scene.get(record_scene_index) as Node2D if record_scene_index >= 0 else null
		if actor != null and matched_actor_ids.has(actor.get_instance_id()):
			actor = null
		if actor == null:
			var display_name := str(record.get("display_name", ""))
			for actor_value: Variant in enemies:
				if (
					actor_value is Node2D
					and is_instance_valid(actor_value)
					and not matched_actor_ids.has((actor_value as Node2D).get_instance_id())
					and str((actor_value as Node2D).get("display_name")) == display_name
				):
					actor = actor_value as Node2D
					break
		var ai: Variant = record.get("ai", {})
		if actor == null or not ai is Dictionary:
			continue
		matched_actor_ids[actor.get_instance_id()] = true
		var target := _find_actor_by_identity(
			game,
			int((ai as Dictionary).get("current_target_scene_index", -1)),
			str((ai as Dictionary).get("current_target_display_name", "")),
		)
		if target != null and bool(target.get("is_alive")):
			actor.set("current_target", target)
		else:
			actor.set("current_target", null)


static func _restore_selection(game: Node) -> void:
	var selected := _array_property(game, "selected_units")
	selected.clear()
	for actor_value: Variant in _array_property(game, "units"):
		if (
			actor_value is Node2D
			and is_instance_valid(actor_value)
			and bool((actor_value as Node2D).get("is_alive"))
			and bool((actor_value as Node2D).get("selected"))
		):
			selected.append(actor_value)


static func _restore_inventory(game: Node, actor: Node2D, record: Dictionary) -> void:
	var snapshot := record["inventory"] as Dictionary
	if snapshot.is_empty():
		return
	var inventory = COMBAT_INVENTORY.new()
	var raw_items: Variant = snapshot.get("items", {})
	if raw_items is Dictionary:
		var items: Dictionary = {}
		for item_key: Variant in (raw_items as Dictionary).keys():
			items[int(str(item_key))] = maxi(int((raw_items as Dictionary)[item_key]), 0)
		inventory.set("_items", items)
	var weapons: Dictionary = _string_dictionary(snapshot.get("weapons", {}))
	inventory.set("_weapons", weapons)
	var active_key := str(snapshot.get("active_action_key", ""))
	inventory.set("_active_action_key", active_key)
	actor.set("combat_inventory", inventory)
	var order: Array[String] = []
	var raw_order: Variant = record.get("inventory_weapon_order", [])
	if raw_order is Array:
		for action_value: Variant in raw_order as Array:
			var action_key := str(action_value)
			if weapons.has(action_key) and not order.has(action_key):
				order.append(action_key)
	for action_key: Variant in weapons.keys():
		if not order.has(str(action_key)):
			order.append(str(action_key))
	actor.set("inventory_weapon_order", order)
	var groups_by_action: Dictionary = {}
	for action_key: String in order:
		groups_by_action[action_key] = (
			game.call("_attack_groups_for_unit", actor, action_key)
			if game.has_method("_attack_groups_for_unit")
			else []
		)
	actor.set("attack_groups_by_action", groups_by_action)
	if weapons.has(active_key):
		var active_state := weapons[active_key] as Dictionary
		actor.set("weapon_profile", (active_state.get("profile", {}) as Dictionary).duplicate(true))
		actor.set("attack_groups", groups_by_action.get(active_key, []))
	actor.call("_sync_ammo_from_inventory", false)


static func _restore_world(game: Node, world: Dictionary, warnings: Array[String]) -> void:
	var activated: Dictionary = {}
	for value: Variant in world.get("activated_scene_indices", []) as Array:
		activated[int(value)] = true
	game.set("activated_mission_scenes", activated)
	game.set("field_inventory", _string_dictionary(world.get("field_inventory", {})))
	var remaining_pickups: Dictionary = {}
	for value: Variant in world.get("remaining_field_pickup_scene_indices", []) as Array:
		remaining_pickups[int(value)] = true
	var pickup_array := _array_property(game, "field_pickups")
	for index: int in range(pickup_array.size() - 1, -1, -1):
		var pickup: Variant = pickup_array[index]
		if pickup is Node and is_instance_valid(pickup) and not remaining_pickups.has(int((pickup as Node).get("scene_index"))):
			(pickup as Node).queue_free()
			pickup_array.remove_at(index)
	var prop_records: Dictionary = {}
	for record_value: Variant in world.get("explosive_props", []) as Array:
		if record_value is Dictionary:
			prop_records[int((record_value as Dictionary).get("scene_index", -1))] = record_value
	var prop_array := _array_property(game, "explosive_props")
	for index: int in range(prop_array.size() - 1, -1, -1):
		var prop: Variant = prop_array[index]
		if not prop is Node or not is_instance_valid(prop):
			prop_array.remove_at(index)
			continue
		var prop_scene := int((prop as Node).get("scene_index"))
		if not prop_records.has(prop_scene):
			(prop as Node).queue_free()
			prop_array.remove_at(index)
		else:
			(prop as Node).set("hit_points", maxi(int((prop_records[prop_scene] as Dictionary).get("hit_points", 1)), 1))
			(prop as Node).queue_redraw()
	_restore_mission_pickups(game, world.get("mission_pickups", []) as Array)
	_restore_mines(game, world.get("deployed_mines", []) as Array, warnings)
	_restore_projectiles(game, world.get("projectiles", []) as Array, warnings)


static func _restore_mission_pickups(game: Node, records: Array) -> void:
	var existing := _array_property(game, "mission_pickups")
	for pickup_value: Variant in existing:
		if pickup_value is Node and is_instance_valid(pickup_value):
			(pickup_value as Node).queue_free()
	existing.clear()
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var pickup: Node2D = MISSION_PICKUP.new()
		pickup.call("configure", record.get("payload", {}) as Dictionary, Vector2(float(record.get("x", 0.0)), float(record.get("y", 0.0))))
		game.add_child(pickup)
		existing.append(pickup)


static func _restore_mines(game: Node, records: Array, warnings: Array[String]) -> void:
	var mine_array := _array_property(game, "deployed_mines")
	for mine_value: Variant in mine_array:
		if mine_value is Node and is_instance_valid(mine_value):
			(mine_value as Node).queue_free()
	mine_array.clear()
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var owner := _find_actor_by_identity(
			game,
			int(record.get("owner_scene_index", -1)),
			str(record.get("owner_display_name", "")),
		)
		var profile := {
			"key": "land_mine",
			"arm_delay_seconds": float(record.get("arm_delay_seconds", 0.75)),
			"trigger_horizontal_radius": float(record.get("trigger_horizontal_radius", 48.0)),
			"trigger_vertical_radius": float(record.get("trigger_vertical_radius", 28.0)),
			"detonation_delay_seconds": float(record.get("detonation_delay_seconds", 0.35)),
			"blast_damage": int(record.get("blast_damage", 16)),
			"blast_horizontal_radius": float(record.get("blast_horizontal_radius", 96.0)),
			"blast_vertical_radius": float(record.get("blast_vertical_radius", 48.0)),
			"resolved_visual_seconds": float(record.get("resolved_visual_seconds", 0.12)),
		}
		var mine: Node2D = LAND_MINE.new()
		if not bool(mine.call("configure", profile, Vector2(float(record.get("x", 0.0)), float(record.get("y", 0.0))), owner, int(record.get("faction_id", 3)))):
			mine.free()
			warnings.append("a deployed mine could not be restored")
			continue
		game.add_child(mine)
		mine.set("state", int(record.get("state", 1)))
		mine.set("state_elapsed", maxf(float(record.get("state_elapsed", 0.0)), 0.0))
		var targets: Array[Node2D] = []
		for enemy_value: Variant in _array_property(game, "enemies"):
			if enemy_value is Node2D:
				targets.append(enemy_value as Node2D)
		mine.call("set_potential_targets", targets)
		if game.has_method("_on_world_explosion_requested"):
			mine.connect("explosion_requested", Callable(game, "_on_world_explosion_requested"))
		mine_array.append(mine)


static func _restore_projectiles(game: Node, records: Array, warnings: Array[String]) -> void:
	var projectile_world: Variant = game.get("projectile_world")
	if not projectile_world is Node:
		return
	for child: Node in (projectile_world as Node).get_children():
		child.queue_free()
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var source := _find_actor_by_identity(
			game,
			int(record.get("source_scene_index", -1)),
			str(record.get("source_display_name", "")),
		)
		var target := _find_actor_by_identity(
			game,
			int(record.get("target_scene_index", -1)),
			str(record.get("target_display_name", "")),
		)
		if source == null:
			warnings.append("an in-flight projectile lost its source")
			continue
		var destination := Vector2(float(record.get("destination_x", 0.0)), float(record.get("destination_y", 0.0)))
		var projectile: Variant = projectile_world.call("launch_for_weapon", source, target, record.get("weapon_profile", {}) as Dictionary, destination)
		if not projectile is Node2D:
			warnings.append("an in-flight projectile could not be restored")
			continue
		var projectile_node := projectile as Node2D
		projectile_node.set("start_world_position", Vector2(float(record.get("start_x", source.position.x)), float(record.get("start_y", source.position.y))))
		projectile_node.set("flight_duration", maxf(float(record.get("flight_duration", 0.05)), 0.05))
		projectile_node.set("flight_elapsed", maxf(float(record.get("flight_elapsed", 0.0)), 0.0))
		projectile_node.set("landed_elapsed", maxf(float(record.get("landed_elapsed", 0.0)), 0.0))
		projectile_node.set("state", int(record.get("state", 0)))
		var progress: float = clampf(float(projectile_node.get("flight_elapsed")) / float(projectile_node.get("flight_duration")), 0.0, 1.0)
		projectile_node.global_position = (projectile_node.get("start_world_position") as Vector2).lerp(destination, progress)


static func _sync_projectile_combatants(game: Node) -> void:
	var projectile_world: Variant = game.get("projectile_world")
	if not projectile_world is Node or not projectile_world.has_method("set_combatants"):
		return
	var combatants: Array[Node2D] = []
	for group_name: String in ["units", "enemies", "escorts", "explosive_props"]:
		for actor_value: Variant in _array_property(game, group_name):
			if actor_value is Node2D and is_instance_valid(actor_value):
				combatants.append(actor_value as Node2D)
	projectile_world.call("set_combatants", combatants)


static func _restore_camera(game: Node, camera_data: Dictionary) -> void:
	var camera: Variant = game.get("level_camera")
	if not camera is Camera2D:
		return
	var camera_node := camera as Camera2D
	camera_node.position = Vector2(float(camera_data.get("x", camera_node.position.x)), float(camera_data.get("y", camera_node.position.y)))
	var zoom := maxf(float(camera_data.get("zoom", camera_node.zoom.x)), 0.05)
	camera_node.zoom = Vector2(zoom, zoom)
	if game.has_method("configure_level_camera"):
		game.call("configure_level_camera", false)


static func _find_actor_by_scene(game: Node, scene_index: int) -> Node2D:
	if scene_index < 0:
		return null
	for group_name: String in ["units", "enemies", "escorts"]:
		for actor_value: Variant in _array_property(game, group_name):
			if actor_value is Node2D and is_instance_valid(actor_value) and int((actor_value as Node2D).get("scene_index")) == scene_index:
				return actor_value as Node2D
	return null


static func _find_actor_by_identity(game: Node, scene_index: int, display_name: String) -> Node2D:
	var actor := _find_actor_by_scene(game, scene_index)
	if actor != null or display_name.is_empty():
		return actor
	for group_name: String in ["units", "enemies", "escorts"]:
		for actor_value: Variant in _array_property(game, group_name):
			if (
				actor_value is Node2D
				and is_instance_valid(actor_value)
				and str((actor_value as Node2D).get("display_name")) == display_name
			):
				return actor_value as Node2D
	return null


static func _actor_display_name(actor_value: Variant) -> String:
	if actor_value is Node and is_instance_valid(actor_value):
		return str((actor_value as Node).get("display_name"))
	return ""


static func _first_living_actor(actors: Array) -> Node2D:
	for actor_value: Variant in actors:
		if actor_value is Node2D and is_instance_valid(actor_value) and bool((actor_value as Node2D).get("is_alive")):
			return actor_value as Node2D
	return null


static func _array_property(object: Object, property_name: String) -> Array:
	var value: Variant = object.get(property_name)
	return value as Array if value is Array else []


static func _dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value as Dictionary if value is Dictionary else {}


static func _sorted_integer_keys(dictionary: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for key: Variant in dictionary.keys():
		result.append(int(key))
	result.sort()
	return result


static func _json_dictionary(value: Variant) -> Dictionary:
	var converted: Variant = _json_value(value)
	return converted as Dictionary if converted is Dictionary else {}


static func _json_value(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return {"x": (value as Vector2).x, "y": (value as Vector2).y}
	if value is Array:
		var output: Array = []
		for child: Variant in value as Array:
			output.append(_json_value(child))
		return output
	if value is Dictionary:
		var output: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			output[str(key)] = _json_value((value as Dictionary)[key])
		return output
	return null


static func _string_dictionary(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var result: Dictionary = {}
	for key: Variant in (value as Dictionary).keys():
		result[str(key)] = (value as Dictionary)[key]
	return result


static func _restored_scalar(value: Variant) -> Variant:
	# Godot's JSON parser may represent an integral JSON number as a float.
	# Scene-based unique keys must return to int or MissionState de-duplication
	# can accept the same objective event a second time after loading.
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value
