extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_SESSION_STATE: Script = preload("res://scripts/game_session_state.gd")
const RUNTIME_STATE_SNAPSHOT: Script = preload(
	"res://scripts/runtime_state_snapshot.gd"
)
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const GAME_INPUT_BINDINGS: Script = preload(
	"res://scripts/game_input_bindings.gd"
)
const LEGACY_ESCORT_RULES: Script = preload(
	"res://scripts/legacy_escort_rules.gd"
)
const LEGACY_MISSION_RULES: Script = preload(
	"res://scripts/legacy_mission_rules.gd"
)
const LEGACY_SPECIAL_ACTION_PROFILES: Script = preload(
	"res://scripts/legacy_special_action_profiles.gd"
)
const LEGACY_DISGUISE_RULES: Script = preload(
	"res://scripts/legacy_disguise_rules.gd"
)
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
var submitted_input_events := 0
var disk_store: RefCounted
var disk_test_root := ""
var disk_capture_enabled := true
var pending_completed_objectives: Array[String] = []
var expected_objective_records: Dictionary = {}
var objective_disk_records: Dictionary = {}
var initial_disk_records: Dictionary = {}
var profile_loads := false
var profile_mark_usec := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	profile_loads = OS.get_cmdline_user_args().has("--profile-loads")
	profile_mark_usec = Time.get_ticks_usec()
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
	disk_test_root = "user://real-mission-objective-disk-%d" % OS.get_process_id()
	_cleanup_disk_test_root()
	disk_store = GAME_SAVE_STORE.new(disk_test_root)
	var requested_level_id := _requested_level_id()
	var exercised_level_count := 0

	for level_index: int in range(LEVEL_IDS.size()):
		var level_id := LEVEL_IDS[level_index]
		if not requested_level_id.is_empty() and level_id != requested_level_id:
			continue
		exercised_level_count += 1
		main.switch_level(level_index, false, false)
		_profile_checkpoint("%s initial load" % level_id, main)
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
		if level_id == "m007":
			await _verify_rescued_escort_follow_runtime(main, 2394)
		var checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		var checkpoint_hash: String = RUNTIME_STATE_SNAPSHOT.snapshot_hash(
			{"session": checkpoint}
		)
		main.switch_level(level_index, false, false)
		_profile_checkpoint("%s checkpoint reload" % level_id, main)
		_prepare_level_for_deterministic_world_actions(main)
		var restore_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
			main,
			checkpoint,
		)
		var restored_checkpoint: Dictionary = GAME_SESSION_STATE.capture(main)
		var restored_checkpoint_hash: String = RUNTIME_STATE_SNAPSHOT.snapshot_hash(
			{"session": restored_checkpoint}
		)
		if restored_checkpoint_hash != checkpoint_hash:
			print(
				"%s_CHECKPOINT_DIFF %s"
				% [
					level_id,
					_first_snapshot_difference(
						checkpoint,
						restored_checkpoint,
					),
				]
			)
		_expect(
			bool(restore_result.get("ok", false))
				and (restore_result.get("warnings", []) as Array).is_empty(),
			"%s restores its real mid-mission checkpoint without warnings" % level_id,
		)
		_expect(
			restored_checkpoint_hash == checkpoint_hash,
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
		_profile_checkpoint("%s failure reload" % level_id, main)
		_prepare_level_for_deterministic_world_actions(main)
		_trigger_primary_failure(main, level_id)
		await process_frame

	# The shipped/default pass above exercises stable-MOD control flow. Every
	# mission with an explicitly recovered-vs-repaired fork also needs a full
	# world-action closure under the opt-in repaired rules.
	for level_id: String in ["m006", "m008", "m009", "m011"]:
		if not requested_level_id.is_empty() and level_id != requested_level_id:
			continue
		var level_index := LEVEL_IDS.find(level_id)
		disk_capture_enabled = false
		main.runtime_settings["mission_rule_mode"] = "repaired"
		main.switch_level(level_index, false, false)
		_profile_checkpoint("%s repaired load" % level_id, main)
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
		_profile_checkpoint("%s repaired checkpoint reload" % level_id, main)
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
	_profile_checkpoint("begin physical checkpoint validation", main)
	_validate_all_objective_disk_checkpoints(main, exercised_level_count)

	root.remove_child(main)
	main.free()
	await process_frame
	_cleanup_disk_test_root()
	_expect(
		committed_world_actions >= (1 if not requested_level_id.is_empty() else 100),
		"the requested mission scope exercised a substantial real interaction sequence",
	)
	_expect(
		submitted_input_events >= 2 * exercised_level_count,
		"every level commits mission interactions through target-viewport E input",
	)
	_expect(
		objective_disk_records.size() == expected_objective_records.size(),
		"every stable-MOD required objective owns a physical disk checkpoint",
	)
	if failures.is_empty():
		var scope_label := (
			requested_level_id if not requested_level_id.is_empty() else "twelve-level"
		)
		print(
			(
				"Real %s mission world loops passed "
				+ "(%d checks, %d committed world actions, "
				+ "%d physical objective resumes, %d viewport input events)."
			)
			% [
				scope_label,
				check_count,
				committed_world_actions,
				objective_disk_records.size(),
				submitted_input_events,
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
	# The fixture moves actors and invokes world interactions directly. A real
	# player command invalidates the short input-free CRT evidence lane through
	# Main._input(); mirror that boundary here before any synthetic world action
	# so followers use the normal recovered pursuit scheduler instead of waiting
	# for a captured no-input round that the fixture intentionally bypasses.
	if main.has_method("invalidate_original_recurring_evidence"):
		main.invalidate_original_recurring_evidence("headless_world_action")
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


func _requested_level_id() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--world-loop-level="):
			continue
		var requested := argument.trim_prefix("--world-loop-level=").to_lower()
		if requested in LEVEL_IDS:
			return requested
		push_error("Unsupported world-loop level: %s" % requested)
		return requested
	return ""


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
			_expect_scene_runtime_actor_type(main, 736, 24)
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
			_expect_any_actor_backpack_item(
				main,
				["老赵", "强子", "古明"],
				101,
			)
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


func _expect_any_actor_backpack_item(
	main: Node,
	display_names: Array[String],
	item_id: int,
) -> void:
	var owner_name := ""
	for unit_value: Variant in main.units:
		var candidate := unit_value as Node
		if (
			not display_names.has(str(candidate.get("display_name")))
			or candidate.get("backpack_inventory") == null
			or int(
				candidate.get("backpack_inventory").call("item_count", item_id)
			) <= 0
		):
			continue
		owner_name = str(candidate.get("display_name"))
		break
	_expect(
		not owner_name.is_empty(),
		"one of %s owns original backpack item %d after world pickup"
			% [", ".join(display_names), item_id],
	)


func _expect_scene_runtime_actor_type(
	main: Node,
	scene_index: int,
	runtime_actor_type: int,
) -> void:
	var actor = null
	for enemy_value: Variant in main.enemies:
		var candidate := enemy_value as Node
		if int(candidate.get("scene_index")) == scene_index:
			actor = candidate
			break
	_expect(
		actor != null
		and int(actor.get("runtime_actor_type")) == runtime_actor_type,
		"scene %d resolves to recovered runtime actor type %d"
			% [scene_index, runtime_actor_type],
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
	var rule_value: Variant = target.get("original_rescue_rule")
	var source_backed := (
		rule_value is Dictionary
		and not (rule_value as Dictionary).is_empty()
	)
	var resolved_rescuer: Node2D = null
	if source_backed:
		var rescuer: Node2D = _prepare_source_backed_rescuer(
			main,
			target,
			rule_value as Dictionary,
		)
		_expect(
			rescuer != null,
			"scene %d resolves the recovered rescuer identity" % scene_index,
		)
		if rescuer == null:
			return
		resolved_rescuer = rescuer
		main.select_only(rescuer)
		rescuer.position = target.position
		main._physics_process(1.0 / 60.0)
	else:
		_select_and_move_player(main, target.position)
		_press_interact_key()
	committed_world_actions += 1
	_expect(
		bool(target.get("rescued_state")),
		(
			"scene %d is rescued through recovered automatic proximity"
			if source_backed
			else "scene %d is rescued through the E/world interaction path"
		) % scene_index,
	)
	if (
		source_backed
		and bool((rule_value as Dictionary).get(
			"becomes_commandable",
			false,
		))
	):
		_verify_recruited_actor_commands(main, target, resolved_rescuer)
	_flush_completed_objective_saves(main)


func _prepare_source_backed_rescuer(
	main: Node,
	target: Node2D,
	rule: Dictionary,
) -> Node2D:
	var rescuer: Node2D = null
	for target_name_value: Variant in rule.get("target_names", []) as Array:
		for unit_value: Variant in main.units:
			var candidate := unit_value as Node2D
			if str(candidate.get("display_name")) == str(target_name_value):
				rescuer = candidate
				break
		if rescuer != null:
			break
	if rescuer == null:
		return null
	var required_types := rule.get("target_runtime_types", []) as Array
	if (
		not required_types.is_empty()
		and not required_types.has(int(rescuer.get("runtime_actor_type")))
	):
		_expect(
			int(target.get("runtime_actor_type")) == 19
				and required_types == [91]
				and int(rescuer.get("runtime_actor_type")) == 10,
			"only m001 requires a recovered disguise transition before rescue",
		)
		main.select_only(rescuer)
		main._on_inventory_slot_requested({
			"kind": "backpack_item",
			"item_id": LEGACY_DISGUISE_RULES.UNIFORM_ITEM_ID,
		})
		for _tick: int in range(LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT + 1):
			main._advance_original_disguise_state(
				LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001
			)
		committed_world_actions += 1
		_expect(
			int(rescuer.get("runtime_actor_type")) == 91,
			"m001 Gu Ming completes the exact 101-tick uniform transition",
		)
	return rescuer


func _verify_recruited_actor_commands(
	main: Node,
	recruit: Node2D,
	rescuer: Node2D,
) -> void:
	# Move the rescuer fixture back to its authored spawn so the click below
	# resolves the newly recruited actor rather than an overlapping teammate.
	if rescuer != null and is_instance_valid(rescuer):
		var source_value: Variant = main.world_entities_by_scene.get(
			int(rescuer.get("scene_index"))
		)
		if source_value is Dictionary:
			var source := source_value as Dictionary
			rescuer.position = Vector2(
				float(source.get("reference_x", source.get("x", 0.0))),
				float(source.get("reference_y", source.get("y", 0.0))),
			)
	_click_world(main, recruit.position)
	_expect(
		bool(recruit.call("is_player_commandable"))
			and main.selected_units.has(recruit),
		"%s joins click/box/hotkey-compatible player selection" % str(
			recruit.get("display_name")
		),
	)
	var slot_index := -1
	for index: int in range(main.PLAYABLE_SQUAD.size()):
		if str(main.PLAYABLE_SQUAD[index].get("name", "")) == str(
			recruit.get("display_name")
		):
			slot_index = index
			break
	_expect(
		slot_index >= 0
			and main._unit_for_original_character_slot(slot_index) == recruit,
		"%s occupies its original fixed character hotkey after recruitment"
			% str(recruit.get("display_name")),
	)
	var destination := _short_recruit_command_destination(main, recruit)
	_expect(
		destination != Vector2.INF,
		"%s has a short reachable command fixture" % str(
			recruit.get("display_name")
		),
	)
	if destination == Vector2.INF:
		return
	_click_world(main, destination)
	var issued_path := recruit.get("movement_path") as PackedVector2Array
	_expect(
		not issued_path.is_empty()
			and (recruit.get("target_position") as Vector2).distance_to(
				destination
			) <= 32.0,
		"%s accepts a real target-viewport ground command after recruitment"
			% str(recruit.get("display_name")),
	)
	recruit.call("cancel_path")
	committed_world_actions += 1


func _short_recruit_command_destination(main: Node, recruit: Node2D) -> Vector2:
	if main.dynamic_occupancy == null:
		return Vector2.INF
	for offset: Vector2 in [
		Vector2(96.0, 0.0),
		Vector2(-96.0, 0.0),
		Vector2(0.0, 64.0),
		Vector2(0.0, -64.0),
		Vector2(96.0, 48.0),
		Vector2(-96.0, 48.0),
	]:
		var requested := recruit.position + offset
		if main.enemy_at_world_point(requested) != null:
			continue
		var path: PackedVector2Array = main.dynamic_occupancy.find_path_for_scene(
			int(recruit.get("scene_index")),
			recruit.position,
			requested,
		)
		main.dynamic_occupancy.release_goal(int(recruit.get("scene_index")))
		if (
			path.is_empty()
			or path[-1].distance_to(requested) > 32.0
			or recruit.position.distance_to(path[-1]) < 32.0
		):
			continue
		return path[-1]
	return Vector2.INF


func _verify_rescued_escort_follow_runtime(main: Node, scene_index: int) -> void:
	var escort: Node2D
	for escort_value: Variant in main.escorts:
		var candidate := escort_value as Node2D
		if int(candidate.get("scene_index")) == scene_index:
			escort = candidate
			break
	_expect(escort != null, "m007 follow check resolves rescued scene %d" % scene_index)
	if escort == null:
		return
	var leader_value: Variant = escort.get("follow_target")
	var leader := leader_value as Node2D if leader_value is Node2D else null
	_expect(
		leader != null
			and bool(escort.get("rescued_state"))
			and int(escort.get("faction_id")) == 3,
		"m007 rescue assigns the living rescuer as the faction-3 follow target",
	)
	if leader == null:
		return
	# The mission fixture moved the rescuer beside the hostage without walking
	# its original route. Remove that actor's now-stale dynamic reservation;
	# the checkpoint reload below reconstructs the normal product registration.
	if (
		bool(leader.get("dynamic_registered"))
		and main.dynamic_occupancy != null
	):
		main.dynamic_occupancy.unregister_scene(int(leader.get("scene_index")))
		leader.set("dynamic_registered", false)
	var destination := _find_short_follow_destination(main, escort)
	_expect(
		destination != Vector2.INF,
		"m007 rescued escort has a short reachable follow fixture",
	)
	if destination == Vector2.INF:
		return
	leader.call("cancel_path")
	leader.position = destination
	var leader_registered := bool(main.dynamic_occupancy.register_scene(
		int(leader.get("scene_index")),
		leader.position,
		leader.position,
	))
	leader.set("dynamic_registered", leader_registered)
	_expect(
		leader_registered,
		"m007 follow fixture registers the moved leader in dynamic occupancy",
	)
	escort.call("cancel_path")
	escort.set_physics_process(false)
	var initial_position := escort.position
	var initial_distance := escort.position.distance_to(leader.position)
	await physics_frame
	escort.call("_physics_process", 1.0 / 60.0 + 0.000001)
	var issued_path := escort.get("movement_path") as PackedVector2Array
	_expect(
		initial_distance >= 128.0
			and not issued_path.is_empty()
			and (escort.get("target_position") as Vector2).distance_to(
				leader.position
			) <= 64.0
			and int(escort.get("original_pursuit_serial")) == 1
			and int(escort.get("original_pursuit_call_site_rva"))
				== LEGACY_ESCORT_RULES.ORIGINAL_PURSUIT_CALL_SITE_RVA,
		(
			"m007 rescued escort issues a real A* path through the recovered "
			+ "pursuit tick (distance=%.1f, path=%d, target=%s, leader=%s, "
			+ "serial=%d, call=0x%X, elapsed=%.6f, registered=%s)"
		)
			% [
				initial_distance,
				issued_path.size(),
				str(escort.get("target_position")),
				str(leader.position),
				int(escort.get("original_pursuit_serial")),
				int(escort.get("original_pursuit_call_site_rva")),
				float(escort.get("original_pursuit_elapsed")),
				str(leader_registered),
			],
	)
	if issued_path.is_empty():
		return
	var minimum_distance := initial_distance
	for _tick: int in range(360):
		await physics_frame
		escort.call("_physics_process", 1.0 / 60.0 + 0.000001)
		minimum_distance = minf(
			minimum_distance,
			escort.position.distance_to(leader.position),
		)
		if (
			minimum_distance <= 32.0
		):
			break
	var final_distance := escort.position.distance_to(leader.position)
	_expect(
		minimum_distance + 32.0 < initial_distance,
		(
			"m007 rescued escort advances along the product movement path "
			+ "(distance %.1f -> %.1f/%.1f, actor %s -> %s, leader %s, "
			+ "first %s, path %d/%d)"
		)
			% [
				initial_distance,
				minimum_distance,
				final_distance,
				str(initial_position),
				str(escort.position),
				str(leader.position),
				str(issued_path[0] if not issued_path.is_empty() else Vector2.ZERO),
				int(escort.get("movement_path_index")),
				(escort.get("movement_path") as PackedVector2Array).size(),
			],
	)
	_expect(
		final_distance > 4.0
			and final_distance <= 32.0
			and int(escort.get("original_pursuit_serial")) == 1,
		(
			"m007 follower reaches the nearest occupancy-safe cell beside its "
			+ "leader (final=%.1f, minimum=%.1f, actor=%s, leader=%s, path=%d/%d, "
			+ "serial=%d, applied=%s)"
		)
			% [
				final_distance,
				minimum_distance,
				str(escort.position),
				str(leader.position),
				int(escort.get("movement_path_index")),
				(escort.get("movement_path") as PackedVector2Array).size(),
				int(escort.get("original_pursuit_serial")),
				str(escort.get("original_pursuit_last_navigation_applied")),
			],
	)
	_expect(
		(escort.get("movement_path") as PackedVector2Array).size() > int(
			escort.get("movement_path_index")
		),
		(
			"m007 occupied-target pursuit retains its active native route instead "
			+ "of applying an invented stop band or periodic replan"
		),
	)
	committed_world_actions += 1


func _find_short_follow_destination(main: Node, escort: Node2D) -> Vector2:
	if main.dynamic_occupancy == null:
		return Vector2.INF
	for offset: Vector2 in [
		Vector2(256.0, 0.0),
		Vector2(-256.0, 0.0),
		Vector2(0.0, 192.0),
		Vector2(0.0, -192.0),
		Vector2(224.0, 112.0),
		Vector2(-224.0, 112.0),
		Vector2(224.0, -112.0),
		Vector2(-224.0, -112.0),
	]:
		var requested := escort.position + offset
		var path: PackedVector2Array = main.dynamic_occupancy.find_path_for_scene(
			int(escort.get("scene_index")),
			escort.position,
			requested,
		)
		main.dynamic_occupancy.release_goal(int(escort.get("scene_index")))
		if (
			path.is_empty()
			or escort.position.distance_to(path[-1]) < 128.0
			or path[-1].distance_to(requested) > 32.0
			or not _follow_path_avoids_third_party_occupants(
				main,
				path,
				int(escort.get("scene_index")),
			)
		):
			continue
		return path[-1]
	return Vector2.INF


func _follow_path_avoids_third_party_occupants(
	main: Node,
	path: PackedVector2Array,
	escort_scene_index: int,
) -> bool:
	for point: Vector2 in path:
		var cell: Vector2i = main.navigation_grid.world_to_cell(point)
		var owners_value: Variant = main.dynamic_occupancy.movement_owners.get(
			cell,
			{},
		)
		if not owners_value is Dictionary:
			continue
		for owner_value: Variant in (owners_value as Dictionary).keys():
			if int(owner_value) != escort_scene_index:
				return false
	return true


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
	var collector_name := (
		"古明"
		if str(main.current_mission.get("id", "")) == "m001"
			and scene_index == 2099
		else ""
	)
	_collect_specific_field_pickup(main, pickup, collector_name)


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


func _collect_specific_field_pickup(
	main: Node,
	pickup: Node2D,
	collector_name: String = "",
) -> void:
	for _attempt: int in range(8):
		if bool(pickup.get("consumed")):
			_flush_completed_objective_saves(main)
			return
		var collector: Node2D = null
		if not collector_name.is_empty():
			for unit_value: Variant in main.units:
				var candidate := unit_value as Node2D
				if (
					str(candidate.get("display_name")) == collector_name
					and bool(candidate.get("is_alive"))
				):
					collector = candidate
					break
		if collector == null:
			collector = _first_living_player(main)
		_expect(
			collector != null,
			"field pickup resolves collector %s"
				% (collector_name if not collector_name.is_empty() else "<first living>"),
		)
		if collector == null:
			return
		main.select_only(collector)
		collector.position = pickup.position
		_press_interact_key()
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
		_press_interact_key()
		committed_world_actions += 1
	_expect(
		main.current_mission_state.is_objective_complete(objective_id),
		"%s role drop is acquired through the ground-pickup path" % item_role,
	)
	_flush_completed_objective_saves(main)


func _place_all_charges(main: Node) -> void:
	var scenes: Array[int] = main._binding_scenes("explosion")
	var native_rule: Dictionary = main._current_native_target_rule()
	if not native_rule.is_empty() and not scenes.is_empty():
		_assert_native_target_rejects_generic_interaction(main, scenes[0])
	for scene_index: int in scenes:
		if native_rule.is_empty():
			_interact_bound_scene(main, scene_index)
		else:
			_satisfy_native_explosion_scene(main, scene_index, native_rule)
	var every_scene_activated := true
	for scene_index: int in scenes:
		if not main.activated_mission_scenes.has(scene_index):
			every_scene_activated = false
			break
	_expect(
		every_scene_activated,
		"%s activates every real explosion scene" % str(main.current_mission.get("id", "")),
	)


func _assert_native_target_rejects_generic_interaction(
	main: Node,
	scene_index: int,
) -> void:
	var entity: Variant = main.world_entities_by_scene.get(scene_index)
	_expect(entity is Dictionary, "native target scene %d exists for E rejection" % scene_index)
	if not entity is Dictionary:
		return
	var actor: Node2D = _first_living_player(main)
	_expect(actor != null, "native target E rejection has a living player")
	if actor == null:
		return
	var target_position := Vector2(float(entity["x"]), float(entity["y"]))
	main.select_only(actor)
	actor.position = target_position
	_press_interact_key()
	_expect(
		not main.activated_mission_scenes.has(scene_index),
		"native target scene %d cannot be forged by the generic E interaction"
			% scene_index,
	)
	# The following authentic blast must not kill the fixture actor merely
	# because the negative interaction check placed it on the detector.
	actor.position = target_position + Vector2(256.0, 0.0)


func _satisfy_native_explosion_scene(
	main: Node,
	scene_index: int,
	native_rule: Dictionary,
) -> void:
	if main.activated_mission_scenes.has(scene_index):
		return
	var entity: Variant = main.world_entities_by_scene.get(scene_index)
	_expect(entity is Dictionary, "native target scene %d exists" % scene_index)
	if not entity is Dictionary:
		return
	var attacker: Node2D = _first_living_player(main)
	_expect(attacker != null, "native target scene %d has a living source actor" % scene_index)
	if attacker == null:
		return
	var target_position := Vector2(float(entity["x"]), float(entity["y"]))
	var profile: Dictionary = LEGACY_SPECIAL_ACTION_PROFILES.profile_for_attack_type(10)
	var world_object: Node2D = main._spawn_legacy_special_world_object(
		profile,
		target_position,
		attacker,
	)
	_expect(
		world_object != null,
		"native target scene %d creates the real actor-85 world object" % scene_index,
	)
	if world_object == null:
		return
	committed_world_actions += 1
	if (
		str(native_rule.get("completion", ""))
		== LEGACY_MISSION_RULES.TARGET_HIT_POINTS_NONPOSITIVE
	):
		world_object.call(
			"advance_world_ticks",
			maxi(int(profile.get("fuse_world_ticks", 100)), 1),
		)
	_expect(
		main.activated_mission_scenes.has(scene_index),
		"native scene %d completes through its recovered world-state predicate"
			% scene_index,
	)
	_flush_completed_objective_saves(main)


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
		_press_interact_key()
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


func _press_interact_key() -> void:
	# Keep mission closure deterministic by positioning the fixture beside each
	# recovered world target, but enter the product interaction path exactly as a
	# player does.  Events are submitted only to this Godot test viewport; no
	# desktop focus, cursor or global input API is used.
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.pressed = pressed
		root.push_input(event)
		submitted_input_events += 1


func _click_world(main: Node, world_position: Vector2) -> void:
	main.level_camera.position = world_position
	main.clamp_level_camera()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = main.get_global_transform_with_canvas() * world_position
		root.push_input(event, true)
		submitted_input_events += 1


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
			var zone_position := Vector2(float(entity["x"]), float(entity["y"]))
			var source_entity: Variant = main.world_entities_by_scene.get(
				int(unit.get("scene_index"))
			)
			if source_entity is Dictionary:
				var source := source_entity as Dictionary
				unit.position = Vector2(
					float(source.get("reference_x", source.get("x", 0.0))),
					float(source.get("reference_y", source.get("y", 0.0))),
				)
			unit.call("cancel_path")
			main.select_only(unit)
			_click_world(main, zone_position)
			var issued_path := unit.get("movement_path") as PackedVector2Array
			_expect(
				not issued_path.is_empty()
					and (unit.get("target_position") as Vector2).distance_to(
						zone_position
					) <= float(rule.get("radius_world", 128.0)),
				"m010 actor %s accepts a target-viewport ground command into zone %d"
					% [str(names[index]), scenes[index]],
			)
			unit.call("cancel_path")
			unit.position = zone_position
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


func _validate_all_objective_disk_checkpoints(
	main: Node,
	expected_initial_count: int,
) -> void:
	_expect(
		initial_disk_records.size() == expected_initial_count,
		"every exercised stable-MOD mission owns an initial physical checkpoint",
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
		_profile_checkpoint(
			"%s physical checkpoint %s reload" % [level_id, slot_id],
			main,
		)
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
		var normalized_hash: String = RUNTIME_STATE_SNAPSHOT.snapshot_hash(
			{"session": normalized_restored}
		)
		var expected_hash := str(record.get("session_hash", ""))
		if normalized_hash != expected_hash:
			print(
				"%s_%s_DISK_DIFF %s"
				% [
					level_id,
					slot_id,
					_first_snapshot_difference(session, normalized_restored),
				]
			)
		_expect(
			bool(normalized_restore_result.get("ok", false))
				and normalized_hash == expected_hash,
			"%s checkpoint %s resumes with an exact normalized world-state hash"
				% [level_id, slot_id],
		)


func _first_snapshot_difference(
	expected: Variant,
	actual: Variant,
	path: String = "$",
) -> String:
	if typeof(expected) != typeof(actual):
		return "%s type %d != %d" % [path, typeof(expected), typeof(actual)]
	if expected is Dictionary:
		var expected_dictionary := expected as Dictionary
		var actual_dictionary := actual as Dictionary
		var keys: Array = expected_dictionary.keys()
		keys.sort_custom(
			func(first: Variant, second: Variant) -> bool:
				return str(first) < str(second)
		)
		for key: Variant in keys:
			if not actual_dictionary.has(key):
				return "%s.%s missing" % [path, str(key)]
			var nested := _first_snapshot_difference(
				expected_dictionary[key],
				actual_dictionary[key],
				"%s.%s" % [path, str(key)],
			)
			if not nested.is_empty():
				return nested
		for key: Variant in actual_dictionary.keys():
			if not expected_dictionary.has(key):
				return "%s.%s unexpected" % [path, str(key)]
		return ""
	if expected is Array:
		var expected_array := expected as Array
		var actual_array := actual as Array
		if expected_array.size() != actual_array.size():
			return "%s size %d != %d" % [
				path,
				expected_array.size(),
				actual_array.size(),
			]
		for index: int in range(expected_array.size()):
			var nested := _first_snapshot_difference(
				expected_array[index],
				actual_array[index],
				"%s[%d]" % [path, index],
			)
			if not nested.is_empty():
				return nested
		return ""
	if RUNTIME_STATE_SNAPSHOT.canonical_text(expected) != RUNTIME_STATE_SNAPSHOT.canonical_text(actual):
		return "%s %s != %s" % [
			path,
			RUNTIME_STATE_SNAPSHOT.canonical_text(expected),
			RUNTIME_STATE_SNAPSHOT.canonical_text(actual),
		]
	return ""


func _cleanup_disk_test_root() -> void:
	var absolute_root := ProjectSettings.globalize_path(disk_test_root)
	if absolute_root.is_empty() or not DirAccess.dir_exists_absolute(absolute_root):
		return
	_remove_disk_tree(absolute_root)


func _profile_checkpoint(label: String, main: Node) -> void:
	if not profile_loads:
		return
	var now_usec := Time.get_ticks_usec()
	var dynamic_grid: Variant = main.get("dynamic_occupancy")
	var path_builds := -1
	var global_hits := -1
	if dynamic_grid != null:
		path_builds = int(dynamic_grid.get("prewarmed_path_build_count"))
		global_hits = int(dynamic_grid.get("static_prewarm_cache_hit_count"))
	print(
		"PROFILE %s delta_ms=%.3f path_builds=%d global_hits=%d"
		% [
			label,
			float(now_usec - profile_mark_usec) / 1000.0,
			path_builds,
			global_hits,
		]
	)
	profile_mark_usec = now_usec


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
