extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const RUNTIME_STATE_SNAPSHOT: Script = preload(
	"res://scripts/runtime_state_snapshot.gd"
)
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]

var failures: Array[String] = []
var check_count := 0
var committed_world_actions := 0
var disk_store: RefCounted
var disk_test_root := ""
var disk_capture_enabled := true
var pending_completed_objectives: Array[String] = []
var expected_objective_records: Dictionary = {}
var objective_disk_records: Dictionary = {}
var initial_disk_records: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	disk_test_root = "user://real-mission-objective-disk-%d" % OS.get_process_id()
	_cleanup_disk_test_root()
	disk_store = GAME_SAVE_STORE.new(disk_test_root)

	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := LEVEL_IDS[level_index]
		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		_register_required_objective_records(main, level_id)
		_save_initial_disk_checkpoint(main, level_id)
		_expect(
			str(main.current_mission.get("id", "")) == level_id,
			"%s loads the matching real mission graph" % level_id,
		)
		_expect(main.terrain_loaded, "%s loads its real MOD terrain" % level_id)
		_expect(
			not main.world_entities_by_scene.is_empty(),
			"%s exposes real scene objects to product interactions" % level_id,
		)
		_expect(not main.units.is_empty(), "%s has at least one playable actor" % level_id)
		if main.units.is_empty():
			continue

		_perform_checkpoint_world_action(main, level_id)
		var checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		var checkpoint_hash: String = RUNTIME_STATE_SNAPSHOT.snapshot_hash(
			{"session": checkpoint}
		)
		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		var restore_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
			main,
			checkpoint,
		)
		var restored_checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		_expect(
			bool(restore_result.get("ok", false))
				and (restore_result.get("warnings", []) as Array).is_empty(),
			"%s restores its real mid-mission checkpoint without warnings" % level_id,
		)
		_expect(
			RUNTIME_STATE_SNAPSHOT.snapshot_hash({"session": restored_checkpoint})
				== checkpoint_hash,
			"%s mid-mission checkpoint round-trips every captured world state"
				% level_id,
		)

		_complete_level_after_checkpoint(main, level_id)
		for raw_objective: Variant in main.current_mission.get("objectives", []) as Array:
			if not raw_objective is Dictionary:
				continue
			var objective := raw_objective as Dictionary
			if not bool(objective.get("required", false)):
				continue
			var objective_id := str(objective.get("id", ""))
			_expect(
				main.current_mission_state.is_objective_complete(objective_id),
				"%s completes required objective %s through world actions"
					% [level_id, objective_id],
			)
		_expect(
			main.current_mission_state.is_victory(),
			"%s reaches victory without direct mission-event injection" % level_id,
		)

		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		_trigger_primary_failure(main, level_id)
		await process_frame

	# The shipped/default pass above exercises stable-MOD control flow. Every
	# mission with an explicitly recovered-vs-repaired fork also needs a full
	# world-action closure under the opt-in repaired rules.
	for level_id: String in ["m006", "m008", "m009", "m011"]:
		var level_index := LEVEL_IDS.find(level_id)
		disk_capture_enabled = false
		main.runtime_settings["mission_rule_mode"] = "repaired"
		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		_expect(
			str(main.current_mission.get("rule_mode", "")) == "repaired",
			"%s loads the repaired mission profile on explicit request" % level_id,
		)
		_perform_checkpoint_world_action(main, level_id)
		var checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		_expect(
			str(checkpoint.get("mission_rule_mode", "")) == "repaired",
			"%s repaired checkpoint owns its mission-rule identity" % level_id,
		)
		main.runtime_settings["mission_rule_mode"] = str(
			checkpoint.get("mission_rule_mode", "stable_mod")
		)
		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		var restore_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
			main,
			checkpoint,
		)
		_expect(
			bool(restore_result.get("ok", false))
				and (restore_result.get("warnings", []) as Array).is_empty(),
			"%s restores a repaired-profile checkpoint without warnings" % level_id,
		)
		_complete_level_after_checkpoint(main, level_id)
		_expect(
			main.current_mission_state.is_victory(),
			"%s repaired profile reaches victory through product world actions"
				% level_id,
		)
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	disk_capture_enabled = false
	_validate_all_objective_disk_checkpoints(main)

	root.remove_child(main)
	main.free()
	await process_frame
	_cleanup_disk_test_root()
	_expect(
		committed_world_actions >= 100,
		"the twelve-level gate exercised a substantial real interaction sequence",
	)
	_expect(
		objective_disk_records.size() == expected_objective_records.size(),
		"every stable-MOD required objective owns a physical disk checkpoint",
	)
	if failures.is_empty():
		print(
			(
				"Real twelve-level mission world loops passed "
				+ "(%d checks, %d committed world actions, "
				+ "%d physical objective resumes)."
			)
			% [
				check_count,
				committed_world_actions,
				objective_disk_records.size(),
			]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _prepare_level_for_deterministic_world_actions(main: Node) -> void:
	# Presentation and AI cooperation are tested independently. Removing them
	# here keeps this gate focused on real world-object -> mission-state wiring
	# and also prevents victory from writing an autosave during CI.
	if main.mission_direction_runtime != null:
		main.mission_direction_runtime.free()
		main.mission_direction_runtime = null
	if main.mission_ai_coordinator != null:
		main.mission_ai_coordinator.free()
		main.mission_ai_coordinator = null
	var runtime: Node = main.mission_runtime
	for connection: Dictionary in [
		{"signal": "state_changed", "method": "_refresh_mission_ui"},
		{"signal": "objective_completed", "method": "_on_objective_completed"},
		{"signal": "victory", "method": "_on_mission_victory"},
		{"signal": "failed", "method": "_on_mission_failed"},
	]:
		var callable := Callable(main, str(connection["method"]))
		var signal_name := StringName(str(connection["signal"]))
		if runtime.is_connected(signal_name, callable):
			runtime.disconnect(signal_name, callable)
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		actor.set_process(false)
		actor.set_physics_process(false)
	if disk_capture_enabled:
		var disk_callable := Callable(
			self,
			"_on_required_objective_completed",
		).bind(main)
		if not runtime.is_connected("objective_completed", disk_callable):
			runtime.connect("objective_completed", disk_callable)


func _perform_checkpoint_world_action(main: Node, level_id: String) -> void:
	match level_id:
		"m000":
			_rescue_scene(main, 1427)
		"m001":
			_collect_field_scene(main, 2099)
		"m002":
			_rescue_scene(main, 877)
		"m003":
			_collect_database_pickups(main, 998, 1)
		"m004":
			_rescue_scene(main, 2700)
		"m005":
			_eliminate_scene(main, 736)
		"m006":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_interact_bound_scene(main, 1461)
			else:
				_eliminate_scene(main, 1457)
		"m007":
			_rescue_scene(main, 2394)
		"m008":
			_collect_database_pickups(main, 998, 1)
		"m009":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_eliminate_scene(main, 1610)
			else:
				_collect_database_pickups(main, 998, 1)
		"m010":
			_move_first_simultaneous_zone_actor(main)
		"m011":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_eliminate_scene(main, 759)
			else:
				_interact_bound_scene(main, 1348)
				_expect(
					not main.current_mission_state.is_victory(),
					"m011 stable profile ignores an overwritten explosion target",
				)
		_:
			_expect(false, "unsupported real mission checkpoint %s" % level_id)


func _complete_level_after_checkpoint(main: Node, level_id: String) -> void:
	match level_id:
		"m000":
			_rescue_scene(main, 1428)
			_use_exit(main, 1600)
		"m001":
			_rescue_scene(main, 2506)
			_place_all_charges(main)
			_use_exit(main, 2522)
		"m002":
			_collect_database_pickups(main, 998, 1)
			_place_all_charges(main)
			_use_exit(main, 895)
		"m003":
			_collect_database_pickups(main, 998, 4)
			_place_all_charges(main)
			_use_exit(main, 1235)
		"m004":
			_eliminate_scene(main, 2637)
			_collect_role_item(main, "m004_plan_document", "acquire_plan")
			_place_all_charges(main)
		"m005":
			_collect_role_item(main, "m005_document", "acquire_document")
		"m006":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_eliminate_scene(main, 1457)
				_eliminate_scene(main, 1460)
				_use_exit(main, 1462)
			else:
				_collect_role_item(main, "m006_name_list", "acquire_name_list")
				_expect_actor_backpack_item(main, "强子", 101)
				_eliminate_scene(main, 1460)
		"m007":
			_rescue_scene(main, 2395)
			_rescue_scene(main, 2299)
			_use_exit(main, 2391)
		"m008":
			_collect_database_pickups(main, 998, 3)
			_place_all_charges(main)
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				main._detonate_mission_charges()
				committed_world_actions += 1
			_use_exit(main, 802)
		"m009":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_collect_database_pickups(main, 998, 4)
				_eliminate_scene(main, 1611)
				_collect_role_item(
					main,
					"m009_transfer_document",
					"obtain_documents",
				)
			else:
				_collect_database_pickups(main, 998, 3)
			_place_all_charges(main)
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_eliminate_all_hostiles(main)
		"m010":
			_occupy_simultaneous_zones(main)
		"m011":
			if str(main.current_mission.get("rule_mode", "")) == "repaired":
				_place_all_charges(main)
				_use_exit(main, 1359)
			else:
				_interact_bound_scene(main, 1353)
				_expect(
					not main.current_mission_state.is_victory(),
					"m011 stable profile still requires Old Zhao and Qiangzi at the exit",
				)
				_use_exit(main, 1359)
		_:
			_expect(false, "unsupported real mission remainder %s" % level_id)


func _trigger_primary_failure(main: Node, level_id: String) -> void:
	var expected_failure := "required_character_lost"
	if level_id in ["m001", "m007", "m010"]:
		var time_limit := float(main.current_mission.get("time_limit_seconds", 0.0))
		_expect(time_limit > 0.0, "%s declares its time-limit failure threshold" % level_id)
		# Main forwards frame deltas to this same product runtime. Advancing the
		# bounded timer directly avoids touching global cursor state in headless QA.
		main.mission_runtime.advance_time(time_limit + 1.0)
		expected_failure = "time_limit"
		committed_world_actions += 1
	elif level_id == "m000":
		var required_escort = null
		for escort_value: Variant in main.escorts:
			var candidate := escort_value as Node2D
			if main._is_required_escort_scene(int(candidate.get("scene_index"))):
				required_escort = candidate
				break
		_expect(
			required_escort != null,
			"m000 failure path has a living required rescue actor",
		)
		if required_escort != null:
			required_escort.call("take_damage", 1_000_000, null)
			committed_world_actions += 1
	elif (
		level_id == "m008"
		and str(main.current_mission.get("rule_mode", "")) == "repaired"
	):
		main._detonate_mission_charges()
		expected_failure = "premature_explosion"
		committed_world_actions += 1
	else:
		var required_player = _first_living_player(main)
		_expect(
			required_player != null,
			"%s failure path has a living required player" % level_id,
		)
		if required_player != null:
			required_player.call("take_damage", 1_000_000, null)
			committed_world_actions += 1
	_expect(
		main.current_mission_state.is_failed()
			and str(main.current_mission_state.failure_id) == expected_failure,
		"%s reaches primary failure %s through its product world path"
			% [level_id, expected_failure],
	)


func _first_living_player(main: Node):
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if bool(unit.get("is_alive")):
			return unit
	return null


func _expect_actor_backpack_item(
	main: Node,
	display_name: String,
	item_id: int,
) -> void:
	var actor = null
	for unit_value: Variant in main.units:
		var candidate := unit_value as Node
		if str(candidate.get("display_name")) == display_name:
			actor = candidate
			break
	var quantity := 0
	if actor != null and actor.get("backpack_inventory") != null:
		quantity = int(actor.get("backpack_inventory").call("item_count", item_id))
	_expect(
		actor != null and quantity > 0,
		"%s owns original backpack item %d after world pickup"
			% [display_name, item_id],
	)


func _select_and_move_player(main: Node, world_position: Vector2):
	var unit = _first_living_player(main)
	_expect(unit != null, "world action has a living player")
	if unit == null:
		return null
	main.select_only(unit)
	unit.position = world_position
	return unit


func _rescue_scene(main: Node, scene_index: int) -> void:
	var target = null
	for escort_value: Variant in main.escorts:
		var escort := escort_value as Node2D
		if int(escort.get("scene_index")) == scene_index:
			target = escort
			break
	_expect(target != null, "rescue scene %d has a live escort actor" % scene_index)
	if target == null:
		return
	_select_and_move_player(main, target.position)
	main.interact_with_mission_world()
	committed_world_actions += 1
	_expect(
		bool(target.get("rescued_state")),
		"scene %d is rescued through the E/world interaction path" % scene_index,
	)
	_flush_completed_objective_saves(main)


func _collect_field_scene(main: Node, scene_index: int) -> void:
	var pickup = null
	for pickup_value: Variant in main.field_pickups:
		var candidate := pickup_value as Node2D
		if int(candidate.get("scene_index")) == scene_index:
			pickup = candidate
			break
	_expect(pickup != null, "field-pickup scene %d exists in the real map" % scene_index)
	if pickup == null:
		return
	_collect_specific_field_pickup(main, pickup)


func _collect_database_pickups(
	main: Node,
	database_entry_id: int,
	required_count: int,
) -> void:
	var collected := 0
	while collected < required_count:
		var pickup = null
		for pickup_value: Variant in main.field_pickups:
			var candidate := pickup_value as Node2D
			if (
				not bool(candidate.get("consumed"))
				and int(candidate.get("database_entry_id")) == database_entry_id
			):
				pickup = candidate
				break
		if pickup == null:
			break
		_collect_specific_field_pickup(main, pickup)
		if bool(pickup.get("consumed")):
			collected += 1
	_expect(
		collected == required_count,
		"%s collects %d real DBL %d pickups through world interaction"
			% [
				str(main.current_mission.get("id", "")),
				required_count,
				database_entry_id,
			],
	)


func _collect_specific_field_pickup(main: Node, pickup: Node2D) -> void:
	for _attempt: int in range(8):
		if bool(pickup.get("consumed")):
			_flush_completed_objective_saves(main)
			return
		_select_and_move_player(main, pickup.position)
		main.interact_with_mission_world()
		committed_world_actions += 1
	_expect(bool(pickup.get("consumed")), "real field pickup is consumable through E")
	_expect(
		str(main.mission_runtime.get("last_error")).is_empty(),
		"ordinary inventory pickup does not pollute mission-event validation",
	)
	_flush_completed_objective_saves(main)


func _eliminate_scene(main: Node, scene_index: int) -> void:
	var target = null
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		if int(enemy.get("scene_index")) == scene_index:
			target = enemy
			break
	_expect(target != null, "combat-role scene %d is a live enemy actor" % scene_index)
	if target == null:
		return
	var attacker = _first_living_player(main)
	_expect(attacker != null, "combat-role scene %d has a living attacker" % scene_index)
	if attacker == null:
		return
	if bool(target.get("is_alive")):
		target.call("take_damage", 1_000_000, attacker)
		committed_world_actions += 1
	_expect(not bool(target.get("is_alive")), "combat damage eliminates scene %d" % scene_index)
	_flush_completed_objective_saves(main)


func _collect_role_item(
	main: Node,
	item_role: String,
	objective_id: String,
) -> void:
	for _attempt: int in range(64):
		if main.current_mission_state.is_objective_complete(objective_id):
			break
		var role_pickup = null
		for pickup_value: Variant in main.mission_pickups:
			var candidate := pickup_value as Node2D
			var payload := candidate.get("item_payload") as Dictionary
			if (
				not bool(candidate.get("collected"))
				and str(payload.get("item_role", "")) == item_role
			):
				role_pickup = candidate
				break
		if role_pickup == null:
			break
		_select_and_move_player(main, role_pickup.position)
		main.interact_with_mission_world()
		committed_world_actions += 1
	_expect(
		main.current_mission_state.is_objective_complete(objective_id),
		"%s role drop is acquired through the ground-pickup path" % item_role,
	)
	_flush_completed_objective_saves(main)


func _place_all_charges(main: Node) -> void:
	var scenes: Array[int] = main._binding_scenes("explosion")
	for scene_index: int in scenes:
		_interact_bound_scene(main, scene_index)
	var every_scene_activated := true
	for scene_index: int in scenes:
		if not main.activated_mission_scenes.has(scene_index):
			every_scene_activated = false
			break
	_expect(
		every_scene_activated,
		"%s activates every real explosion scene" % str(main.current_mission.get("id", "")),
	)


func _interact_bound_scene(main: Node, scene_index: int) -> void:
	var entity: Variant = main.world_entities_by_scene.get(scene_index)
	_expect(entity is Dictionary, "bound scene %d exists in the real level" % scene_index)
	if not entity is Dictionary:
		return
	var world_position := Vector2(float(entity["x"]), float(entity["y"]))
	for _attempt: int in range(12):
		if (
			main.activated_mission_scenes.has(scene_index)
			or main.current_mission_state.is_victory()
			or main.current_mission_state.is_failed()
		):
			break
		_select_and_move_player(main, world_position)
		main.interact_with_mission_world()
		committed_world_actions += 1
	_expect(
		main.activated_mission_scenes.has(scene_index)
			or main.current_mission_state.is_victory(),
		"bound scene %d commits through proximity interaction" % scene_index,
	)
	_flush_completed_objective_saves(main)


func _use_exit(main: Node, scene_index: int) -> void:
	var raw_entity: Variant = main.world_entities_by_scene.get(scene_index)
	_expect(raw_entity is Dictionary, "exit scene %d exists in the real level" % scene_index)
	if not raw_entity is Dictionary:
		return
	var entity := raw_entity as Dictionary
	var exit_position := Vector2(float(entity["x"]), float(entity["y"]))
	var rules := main.current_mission.get("exit_party", {}) as Dictionary
	var required_player_names := rules.get("player_names", []) as Array
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if (
			bool(unit.get("is_alive"))
			and (
				required_player_names.is_empty()
				or required_player_names.has(str(unit.get("display_name")))
			)
		):
			unit.position = exit_position
	var required_escort_scenes: Array[int] = []
	var escort_bindings := rules.get("escort_bindings", []) as Array
	if escort_bindings.is_empty():
		for escort_value: Variant in main.escorts:
			required_escort_scenes.append(int((escort_value as Node).get("scene_index")))
	else:
		for binding_value: Variant in escort_bindings:
			for bound_scene: int in main._binding_scenes(str(binding_value)):
				if not required_escort_scenes.has(bound_scene):
					required_escort_scenes.append(bound_scene)
	for escort_value: Variant in main.escorts:
		var escort := escort_value as Node2D
		if required_escort_scenes.has(int(escort.get("scene_index"))):
			escort.position = exit_position
	_interact_bound_scene(main, scene_index)


func _eliminate_all_hostiles(main: Node) -> void:
	var attacker = _first_living_player(main)
	_expect(attacker != null, "hostile-clear action has a living player")
	if attacker == null:
		return
	var eliminated := 0
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		if not bool(enemy.get("is_alive")):
			continue
		enemy.call("take_damage", 1_000_000, attacker)
		eliminated += 1
		committed_world_actions += 1
	_expect(eliminated > 0, "m009 clears remaining live enemies through combat damage")
	_expect(main._living_enemy_count() == 0, "m009 has no live hostile after the clear action")
	_flush_completed_objective_saves(main)


func _move_first_simultaneous_zone_actor(main: Node) -> void:
	var rule := main.current_mission.get("simultaneous_zone_rule", {}) as Dictionary
	var names := rule.get("eligible_player_names", []) as Array
	var scenes: Array[int] = main._binding_scenes(str(rule.get("binding", "high_ground")))
	_expect(
		not names.is_empty() and not scenes.is_empty(),
		"m010 checkpoint exposes a named actor and real high-ground zone",
	)
	if names.is_empty() or scenes.is_empty():
		return
	var unit = null
	for unit_value: Variant in main.units:
		var candidate := unit_value as Node2D
		if str(candidate.get("display_name")) == str(names[0]):
			unit = candidate
			break
	var raw_entity: Variant = main.world_entities_by_scene.get(scenes[0])
	_expect(unit != null, "m010 checkpoint actor %s exists" % str(names[0]))
	_expect(raw_entity is Dictionary, "m010 checkpoint zone %d exists" % scenes[0])
	if unit != null and raw_entity is Dictionary:
		var entity := raw_entity as Dictionary
		unit.position = Vector2(float(entity["x"]), float(entity["y"]))
		committed_world_actions += 1


func _occupy_simultaneous_zones(main: Node) -> void:
	var rule := main.current_mission.get("simultaneous_zone_rule", {}) as Dictionary
	var names := rule.get("eligible_player_names", []) as Array
	var scenes: Array[int] = main._binding_scenes(str(rule.get("binding", "high_ground")))
	_expect(
		names.size() == scenes.size() and scenes.size() == 4,
		"m010 exposes four named actors and four real high-ground zones",
	)
	for index: int in range(mini(names.size(), scenes.size())):
		var unit = null
		for unit_value: Variant in main.units:
			var candidate := unit_value as Node2D
			if str(candidate.get("display_name")) == str(names[index]):
				unit = candidate
				break
		var raw_entity: Variant = main.world_entities_by_scene.get(scenes[index])
		_expect(unit != null, "m010 eligible actor %s exists" % str(names[index]))
		_expect(raw_entity is Dictionary, "m010 zone scene %d exists" % scenes[index])
		if unit != null and raw_entity is Dictionary:
			var entity := raw_entity as Dictionary
			unit.position = Vector2(float(entity["x"]), float(entity["y"]))
			committed_world_actions += 1
	main._evaluate_transient_mission_zones()
	committed_world_actions += 1
	_flush_completed_objective_saves(main)


func _register_required_objective_records(main: Node, level_id: String) -> void:
	pending_completed_objectives.clear()
	var required_index := 0
	for objective_value: Variant in main.current_mission.get("objectives", []) as Array:
		if not objective_value is Dictionary:
			continue
		var objective := objective_value as Dictionary
		if not bool(objective.get("required", false)):
			continue
		var objective_id := str(objective.get("id", ""))
		var record_key := "%s:%s" % [level_id, objective_id]
		expected_objective_records[record_key] = {
			"level_id": level_id,
			"objective_id": objective_id,
			"slot_id": "%s_o%02d" % [level_id, required_index],
		}
		required_index += 1


func _save_initial_disk_checkpoint(main: Node, level_id: String) -> void:
	var slot_id := "%s_initial" % level_id
	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	var result: Dictionary = disk_store.save_slot(
		slot_id,
		session,
		GAME_SAVE_STORE.default_campaign(),
	)
	_expect(
		bool(result.get("ok", false)),
		"%s writes its initial physical-disk checkpoint" % level_id,
	)
	if not bool(result.get("ok", false)):
		return
	var loaded: Dictionary = disk_store.load_slot(slot_id)
	_expect(
		bool(loaded.get("ok", false)),
		"%s reads its initial physical-disk checkpoint" % level_id,
	)
	if not bool(loaded.get("ok", false)):
		return
	var loaded_session := (
		(loaded.get("data", {}) as Dictionary).get("session", {}) as Dictionary
	)
	initial_disk_records[level_id] = {
		"level_id": level_id,
		"objective_id": "",
		"slot_id": slot_id,
		"session_hash": RUNTIME_STATE_SNAPSHOT.snapshot_hash(
			{"session": loaded_session}
		),
	}


func _on_required_objective_completed(
	objective_id: String,
	main: Node,
) -> void:
	if not disk_capture_enabled:
		return
	var level_id := str(main.current_mission.get("id", ""))
	var record_key := "%s:%s" % [level_id, objective_id]
	if (
		not expected_objective_records.has(record_key)
		or objective_disk_records.has(record_key)
		or pending_completed_objectives.has(objective_id)
	):
		return
	pending_completed_objectives.append(objective_id)


func _flush_completed_objective_saves(main: Node) -> void:
	if not disk_capture_enabled or pending_completed_objectives.is_empty():
		return
	var level_id := str(main.current_mission.get("id", ""))
	var completed_now := pending_completed_objectives.duplicate()
	pending_completed_objectives.clear()
	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	for objective_id: String in completed_now:
		var record_key := "%s:%s" % [level_id, objective_id]
		if not expected_objective_records.has(record_key):
			_expect(false, "%s emitted unknown required objective %s" % [level_id, objective_id])
			continue
		var expected := expected_objective_records[record_key] as Dictionary
		var slot_id := str(expected.get("slot_id", ""))
		var result: Dictionary = disk_store.save_slot(
			slot_id,
			session,
			GAME_SAVE_STORE.default_campaign(),
		)
		_expect(
			bool(result.get("ok", false)),
			"%s objective %s writes a physical-disk checkpoint"
				% [level_id, objective_id],
		)
		if not bool(result.get("ok", false)):
			continue
		var loaded: Dictionary = disk_store.load_slot(slot_id)
		_expect(
			bool(loaded.get("ok", false)),
			"%s objective %s immediately reads from physical disk"
				% [level_id, objective_id],
		)
		if not bool(loaded.get("ok", false)):
			continue
		var loaded_session := (
			(loaded.get("data", {}) as Dictionary).get("session", {}) as Dictionary
		)
		var completed := (
			(loaded_session.get("mission", {}) as Dictionary).get(
				"completed",
				{},
			) as Dictionary
		)
		_expect(
			bool(completed.get(objective_id, false)),
			"%s objective %s is complete in the disk document"
				% [level_id, objective_id],
		)
		objective_disk_records[record_key] = {
			"level_id": level_id,
			"objective_id": objective_id,
			"slot_id": slot_id,
			"session_hash": RUNTIME_STATE_SNAPSHOT.snapshot_hash(
				{"session": loaded_session}
			),
		}


func _validate_all_objective_disk_checkpoints(main: Node) -> void:
	_expect(
		initial_disk_records.size() == LEVEL_IDS.size(),
		"all twelve stable-MOD missions own an initial physical checkpoint",
	)
	var records: Array[Dictionary] = []
	for level_id: String in LEVEL_IDS:
		if initial_disk_records.has(level_id):
			records.append(
				(initial_disk_records[level_id] as Dictionary).duplicate(true)
			)
	var objective_keys: Array = objective_disk_records.keys()
	objective_keys.sort()
	for record_key_value: Variant in objective_keys:
		records.append(
			(objective_disk_records[str(record_key_value)] as Dictionary)
			.duplicate(true)
		)
	for record: Dictionary in records:
		var level_id := str(record.get("level_id", ""))
		var slot_id := str(record.get("slot_id", ""))
		var load_result: Dictionary = disk_store.load_slot(slot_id)
		_expect(
			bool(load_result.get("ok", false)),
			"%s checkpoint %s remains readable after the full campaign"
				% [level_id, slot_id],
		)
		if not bool(load_result.get("ok", false)):
			continue
		var document := load_result.get("data", {}) as Dictionary
		var session := document.get("session", {}) as Dictionary
		var level_index := LEVEL_IDS.find(level_id)
		_expect(level_index >= 0, "disk checkpoint references a formal level")
		if level_index < 0:
			continue
		main.runtime_settings["mission_rule_mode"] = str(
			session.get("mission_rule_mode", "stable_mod")
		)
		main.switch_level(level_index, false, false)
		_prepare_level_for_deterministic_world_actions(main)
		var apply_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
			main,
			session,
		)
		_expect(
			bool(apply_result.get("ok", false))
				and (apply_result.get("warnings", []) as Array).is_empty(),
			"%s checkpoint %s rebuilds the product world without warnings"
				% [level_id, slot_id],
		)
		var restored: Dictionary = GAME_SESSION_STATE.capture(main)
		var normalize_result: Dictionary = disk_store.save_slot(
			"resume_probe",
			restored,
			GAME_SAVE_STORE.default_campaign(),
		)
		_expect(
			bool(normalize_result.get("ok", false)),
			"%s checkpoint %s can be written again after resume"
				% [level_id, slot_id],
		)
		var normalized_restore_result: Dictionary = disk_store.load_slot(
			"resume_probe"
		)
		var normalized_restored := (
			(
				normalized_restore_result.get("data", {}) as Dictionary
			).get("session", {}) as Dictionary
		)
		_expect(
			bool(normalized_restore_result.get("ok", false))
				and RUNTIME_STATE_SNAPSHOT.snapshot_hash(
					{"session": normalized_restored}
				)
				== str(record.get("session_hash", "")),
			"%s checkpoint %s resumes with an exact normalized world-state hash"
				% [level_id, slot_id],
		)


func _cleanup_disk_test_root() -> void:
	var absolute_root := ProjectSettings.globalize_path(disk_test_root)
	if absolute_root.is_empty() or not DirAccess.dir_exists_absolute(absolute_root):
		return
	_remove_disk_tree(absolute_root)


func _remove_disk_tree(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var child_name := directory.get_next()
	while not child_name.is_empty():
		var child_path := absolute_path.path_join(child_name)
		if directory.current_is_dir():
			_remove_disk_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		child_name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)


func _expect(condition: bool, description: String) -> void:
	check_count += 1
	if not condition:
		failures.append(description)
