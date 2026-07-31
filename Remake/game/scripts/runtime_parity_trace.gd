class_name RuntimeParityTrace
extends RefCounted

## Cross-runtime evidence shared by the stable MOD and the modern remake.
## Coordinates deliberately stay in the original game's world-pixel space.

const SCHEMA_VERSION := 1
const CONTENT_PROFILE := "repository-mod-12-level-20260729"

var document: Dictionary = {}
var _property_names_by_instance: Dictionary = {}


func configure(
	runtime_name: String,
	level_id: String,
	selector_level: int,
	engine_mission: int,
	scenario_id: String,
	description: String = "",
) -> void:
	document = {
		"schema_version": SCHEMA_VERSION,
		"trace_id": "%s-%s-%s" % [runtime_name, level_id, scenario_id],
		"runtime": runtime_name,
		"content_profile": CONTENT_PROFILE,
		"level": {
			"id": level_id,
			"selector_level": selector_level,
			"engine_mission": engine_mission,
		},
		"scenario": {
			"id": scenario_id,
			"coordinate_space": "legacy-world-pixels",
			"description": description,
		},
		"metadata": {
			"producer": "RuntimeParityTrace",
			"godot_version": str(Engine.get_version_info().get("string", "")),
		},
		"checkpoints": [],
	}


func capture_main(
	checkpoint_id: String,
	main: Node,
	elapsed_ms: float,
	tags: Dictionary = {},
) -> Dictionary:
	if document.is_empty():
		push_error("RuntimeParityTrace must be configured before capture.")
		return {}
	var actors := _capture_main_actors(main)
	var checkpoint := {
		"id": checkpoint_id,
		"sequence": (document["checkpoints"] as Array).size(),
		"elapsed_ms": maxf(elapsed_ms, 0.0),
		"camera": _capture_camera(main),
		"world": {
			"size": _point(_read_property(main, "world_size", Vector2.ZERO)),
			"tracked_actor_count": actors.size(),
			"source_entity_count": (
				int(_read_property(main, "imported_entity_count", 0))
				+ _dictionary_size(_read_property(main, "playable_entities", {}))
			),
			# The original runtime count includes live characters plus spawned
			# pickups/special objects. Keep the absolute totals runtime-local,
			# but preserve their before/after deltas for deployment parity.
			"runtime_object_count": (
				actors.size()
				+ _live_array_count(main, "mission_pickups")
				+ _live_array_count(main, "deployed_mines")
				+ _live_array_count(main, "legacy_special_world_objects")
				+ _live_array_count(main, "legacy_ai_control_effects")
			),
		},
		"actors": actors,
		"mission": _capture_mission(main),
		"tags": _json_safe(tags),
	}
	(document["checkpoints"] as Array).append(checkpoint)
	return checkpoint


func write_to_file(path: String) -> Error:
	if document.is_empty():
		return ERR_UNCONFIGURED
	var parent := path.get_base_dir()
	if not parent.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(parent)
		if directory_error != OK:
			return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "\t") + "\n")
	return OK


func _capture_main_actors(main: Node) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var selected_units: Array = _read_property(main, "selected_units", []) as Array
	for role_and_field: Array in [
		["player", "units"],
		["escort", "escorts"],
		["escort", "ambient_units"],
		["enemy", "enemies"],
	]:
		var role: String = str(role_and_field[0])
		var field: String = str(role_and_field[1])
		for raw_actor: Variant in _read_property(main, field, []) as Array:
			if raw_actor is Node2D:
				records.append(
					_capture_actor(
						raw_actor as Node2D,
						role,
						main,
						selected_units.has(raw_actor),
					)
				)
	records.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_scene := int(first.get("scene_index", -1))
			var second_scene := int(second.get("scene_index", -1))
			if first_scene == second_scene:
				return str(first.get("role", "")) < str(second.get("role", ""))
			return first_scene < second_scene
	)
	return records


func _capture_actor(
	actor: Node2D,
	role: String,
	main: Node,
	selected: bool,
) -> Dictionary:
	var scene_index := int(_read_property(actor, "scene_index", -1))
	var source_entity: Dictionary = {}
	var entities: Variant = _read_property(main, "world_entities_by_scene", {})
	if entities is Dictionary:
		source_entity = (entities as Dictionary).get(scene_index, {}) as Dictionary
	var target: Vector2 = _read_property(actor, "target_position", actor.position) as Vector2
	var current_target: Variant = _read_property(actor, "current_target", null)
	var current_target_scene := -1
	if current_target is Node2D and is_instance_valid(current_target):
		current_target_scene = int(_read_property(current_target, "scene_index", -1))
	var behavior_state := int(_read_property(actor, "behavior_state", -1))
	var has_live_target := current_target_scene >= 0
	var movement_path: Variant = _read_property(actor, "movement_path", PackedVector2Array())
	var movement_path_index := int(_read_property(actor, "movement_path_index", 0))
	var movement_path_size := (
		(movement_path as PackedVector2Array).size()
		if movement_path is PackedVector2Array
		else 0
	)
	var movement_active := movement_path_index < movement_path_size
	var goal_kind := 2 if has_live_target else (1 if movement_active else 0)
	var captured_weapon := _capture_weapon(actor)
	var record := {
		"actor_id": "scene:%d" % scene_index,
		"role": role,
		"scene_index": maxi(scene_index, 0),
		"database_entry_id": maxi(int(source_entity.get("database_entry_id", 0)), 0),
		"display_name": str(_read_property(actor, "display_name", actor.name)),
		"faction_id": int(_read_property(actor, "faction_id", 0)),
		"position": _point(actor.position),
		"target_position": _point(target),
		"facing_direction": _facing_direction(actor),
		"alive": bool(_read_property(actor, "is_alive", true)),
		"selected": selected,
		"stance": _stance(actor),
		"hit_points": {
			"current": int(_read_property(actor, "current_hit_points", 0)),
			"maximum": int(_read_property(actor, "maximum_hit_points", 0)),
		},
		"weapon": captured_weapon,
		"native": {
			"goal_kind": goal_kind,
			"animation_group_index": int(_read_property(actor, "animation_group_index", -1)),
			"animation_frame_index": int(_read_property(actor, "animation_frame_index", 0)),
			"combat_action": int(_read_property(actor, "combat_action", 0)),
			"movement_path_index": movement_path_index,
			"movement_active": 1 if movement_active else 0,
			"target_status": 0,
			"selected_for_command": 1 if selected else 0,
			"search_or_return_active": 1 if behavior_state == 3 else 0,
			"contact_state": 1 if has_live_target and behavior_state in [1, 2] else 0,
			"target_lost": 0 if has_live_target else 1,
			"reaction_state": maxi(behavior_state, 0),
			"current_hit_points": int(_read_property(actor, "current_hit_points", 0)),
			"default_attack_type": int(captured_weapon.get("attack_type", 0)),
			"damage_event_count": int(_read_property(actor, "damage_event_count", 0)),
			"damage_taken_total": int(_read_property(actor, "damage_taken_total", 0)),
			"last_damage_attacker_scene_index": int(
				_read_property(actor, "last_damage_attacker_scene_index", -1)
			),
			"interest_scene_index": current_target_scene,
			"target_scene_index": current_target_scene,
		},
	}
	var inventory_method := (
		"parity_inventory_snapshot"
		if actor.has_method("parity_inventory_snapshot")
		else "inventory_snapshot"
	)
	if actor.has_method(inventory_method):
		var inventory: Variant = actor.call(inventory_method)
		if inventory is Dictionary:
			record["inventory"] = _json_safe(inventory)
	if role == "enemy":
		record["ai_state"] = behavior_state
		(record["native"] as Dictionary)["patrol_wait_remaining_ms"] = (
			maxf(float(_read_property(actor, "patrol_wait_remaining", 0.0)), 0.0)
			* 1000.0
		)
		(record["native"] as Dictionary)["stable_mod_patrol_target_index"] = int(
			_read_property(actor, "stable_mod_patrol_target_index", -1)
		)
		(record["native"] as Dictionary)["stable_mod_patrol_evidence_distance"] = float(
			_read_property(actor, "stable_mod_patrol_last_evidence_distance", 0.0)
		)
		(record["native"] as Dictionary)["stable_mod_patrol_unbounded_path_distance"] = float(
			_read_property(
				actor,
				"stable_mod_patrol_last_unbounded_path_distance",
				0.0,
			)
		)
		(record["native"] as Dictionary)["stable_mod_patrol_radius_guard_active"] = (
			1
			if bool(_read_property(
				actor,
				"stable_mod_patrol_radius_guard_active",
				false,
			))
			else 0
		)
		(record["native"] as Dictionary)["stable_mod_patrol_final_relocation_active"] = (
			1
			if bool(_read_property(
				actor,
				"use_recorded_patrol_final_relocation",
				false,
			))
			else 0
		)
		(record["native"] as Dictionary)["stable_mod_patrol_final_relocation_targets"] = (
			_json_safe(_read_property(
				actor,
				"stable_mod_patrol_final_relocation_target_indices",
				[],
			))
		)
	return record


func _capture_weapon(actor: Node2D) -> Dictionary:
	var profile: Variant = _read_property(actor, "weapon_profile", {})
	var weapon_profile: Dictionary = profile as Dictionary if profile is Dictionary else {}
	return {
		"attack_type": int(weapon_profile.get("attack_type", 0)),
		"action_key": str(weapon_profile.get("action_key", "")),
		"magazine_ammo": int(_read_property(actor, "magazine_ammo", 0)),
		"reserve_ammo": int(_read_property(actor, "reserve_ammo", 0)),
		"infinite_ammo": bool(_read_property(actor, "infinite_ammo", false)),
	}


func _capture_camera(main: Node) -> Dictionary:
	var camera: Variant = _read_property(main, "level_camera", null)
	var position := Vector2.ZERO
	var zoom := Vector2.ONE
	if camera is Camera2D:
		position = (camera as Camera2D).position
		zoom = (camera as Camera2D).zoom
	var viewport_size := Vector2.ZERO
	if main.get_viewport() != null:
		viewport_size = main.get_viewport_rect().size
	return {
		"position": _point(position),
		"viewport": _point(viewport_size),
		"zoom": _point(zoom),
	}


func _capture_mission(main: Node) -> Dictionary:
	var mission: Variant = _read_property(main, "current_mission", {})
	var mission_definition: Dictionary = mission as Dictionary if mission is Dictionary else {}
	var state: Variant = _read_property(main, "current_mission_state", null)
	var status := "unknown"
	if state is Object:
		if (state as Object).has_method("is_victory") and bool((state as Object).call("is_victory")):
			status = "victory"
		elif (state as Object).has_method("is_failed") and bool((state as Object).call("is_failed")):
			status = "failed"
		else:
			status = "active"
	return {
		"id": str(mission_definition.get("id", "")),
		"status": status,
		"failure_id": str(_read_property(state, "failure_id", "")),
		"completed": _json_safe(_read_property(state, "completed", {})),
		"progress": _json_safe(_read_property(state, "progress", {})),
		"elapsed_seconds": maxf(float(_read_property(state, "elapsed_seconds", 0.0)), 0.0),
	}


func _facing_direction(actor: Node2D) -> int:
	var original_direction := int(_read_property(actor, "original_direction_index", 0))
	if original_direction >= 1 and original_direction <= 8:
		return original_direction
	var group_index := int(_read_property(actor, "animation_group_index", -1))
	if group_index < 0 or group_index >= 8:
		return 0
	return posmod(group_index - 3, 8) + 1


func _stance(actor: Node2D) -> String:
	if bool(_read_property(actor, "is_crawling", false)):
		return "crawl"
	if bool(_read_property(actor, "is_running", false)):
		return "run"
	return "walk"


func _point(value: Variant) -> Array[float]:
	if value is Vector2:
		var point := value as Vector2
		return [point.x, point.y]
	if value is Vector2i:
		var cell := value as Vector2i
		return [float(cell.x), float(cell.y)]
	if value is Array and (value as Array).size() >= 2:
		return [float((value as Array)[0]), float((value as Array)[1])]
	return [0.0, 0.0]


func _read_property(source: Variant, field: String, default_value: Variant) -> Variant:
	if source is Dictionary:
		return (source as Dictionary).get(field, default_value)
	if not source is Object:
		return default_value
	var source_object := source as Object
	var instance_id := source_object.get_instance_id()
	if not _property_names_by_instance.has(instance_id):
		var property_names: Dictionary = {}
		for property: Dictionary in source_object.get_property_list():
			property_names[str(property.get("name", ""))] = true
		_property_names_by_instance[instance_id] = property_names
	var cached_names := _property_names_by_instance[instance_id] as Dictionary
	if cached_names.has(field):
		return source_object.get(field)
	return default_value


func _dictionary_size(value: Variant) -> int:
	return (value as Dictionary).size() if value is Dictionary else 0


func _live_array_count(source: Variant, field: String) -> int:
	var value: Variant = _read_property(source, field, [])
	if not value is Array:
		return 0
	var count := 0
	for item: Variant in value as Array:
		if item is Object and is_instance_valid(item):
			count += 1
	return count


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return str(value) if typeof(value) == TYPE_STRING_NAME else value
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return _point(value)
		TYPE_ARRAY:
			var output: Array = []
			for item: Variant in value as Array:
				output.append(_json_safe(item))
			return output
		TYPE_DICTIONARY:
			var output: Dictionary = {}
			var keys: Array = (value as Dictionary).keys()
			keys.sort_custom(func(first: Variant, second: Variant) -> bool: return str(first) < str(second))
			for key: Variant in keys:
				output[str(key)] = _json_safe((value as Dictionary)[key])
			return output
	return str(value)
