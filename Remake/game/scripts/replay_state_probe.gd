class_name ReplayStateProbe
extends RefCounted


static func capture(game: Node) -> Dictionary:
	if game == null:
		return {}
	var actors: Dictionary = {}
	for group_name: String in ["units", "enemies", "escorts", "ambient_units"]:
		var group_value: Variant = game.get(group_name)
		if not group_value is Array:
			continue
		for actor_value: Variant in group_value as Array:
			if not actor_value is Node2D or not is_instance_valid(actor_value):
				continue
			var actor := actor_value as Node2D
			var actor_id := int(actor.get("scene_index"))
			actors[str(actor_id)] = _actor_state(actor, group_name)
	var doors: Dictionary = {}
	var door_value: Variant = game.get("legacy_doors")
	if door_value is Array:
		for raw_door: Variant in door_value as Array:
			if raw_door is Node2D and is_instance_valid(raw_door):
				var door := raw_door as Node2D
				doors[str(int(door.get("scene_index")))] = bool(door.get("is_open"))
	var mission: Dictionary = {}
	var mission_state: Variant = game.get("current_mission_state")
	if mission_state is RefCounted:
		mission = {
			"completed": _value(mission_state.get("completed")),
			"progress": _value(mission_state.get("progress")),
			"failure_id": str(mission_state.get("failure_id")),
			"elapsed_seconds": float(mission_state.get("elapsed_seconds")),
		}
	var simulation: Dictionary = {}
	var coordinator: Variant = game.get("simulation_coordinator")
	if coordinator != null and coordinator.has_method("capture_state"):
		simulation = coordinator.call("capture_state")
	var tactical: Dictionary = {}
	var tactical_queue: Variant = game.get("tactical_command_queue")
	if tactical_queue != null and tactical_queue.has_method("capture_state"):
		tactical = tactical_queue.call("capture_state")
	var ai: Dictionary = {}
	var ai_coordinator: Variant = game.get("mission_ai_coordinator")
	if ai_coordinator != null and ai_coordinator.has_method("capture_state"):
		ai = ai_coordinator.call("capture_state")
	return {
		"simulation": _value(simulation),
		"actors": actors,
		"doors": doors,
		"mission": mission,
		"tactical": _value(tactical),
		"ai": _value(ai),
		"random": {
			"state": int(game.get("legacy_crt_random_state")),
			"draw_index": int(game.get("legacy_crt_random_draw_index")),
		},
	}


static func _actor_state(actor: Node2D, group_name: String) -> Dictionary:
	var state := {
		"group": group_name,
		"x": actor.position.x,
		"y": actor.position.y,
		"alive": bool(actor.get("is_alive")),
		"hp": int(actor.get("current_hit_points")),
		"action": int(actor.get("combat_action")),
		"frame": int(actor.get("action_frame_index")),
		"path_index": int(actor.get("movement_path_index")),
	}
	# Every runtime actor derives from SquadUnit. Enemies expose the tactical
	# target through current_target; the other groups use combat_target. Avoid
	# enumerating the full Godot property list twice per actor at each replay
	# checkpoint (116 dense-map actors made that reflection pass dominant).
	var target: Variant = (
		actor.get("current_target")
		if group_name == "enemies"
		else actor.get("combat_target")
	)
	state["target"] = int(target.get("scene_index")) if target is Node2D and is_instance_valid(target) else -1
	state["magazine"] = int(actor.get("magazine_ammo"))
	state["reserve"] = int(actor.get("reserve_ammo"))
	if group_name == "enemies":
		state["behavior"] = int(actor.get("behavior_state"))
	return state


static func _value(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return {"x": (value as Vector2).x, "y": (value as Vector2).y}
	if value is Array:
		var array: Array = []
		for item: Variant in value as Array:
			array.append(_value(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		var keys: Array[String] = []
		for raw_key: Variant in (value as Dictionary).keys():
			keys.append(str(raw_key))
		keys.sort()
		for key: String in keys:
			dictionary[key] = _value((value as Dictionary).get(key))
		return dictionary
	return null
