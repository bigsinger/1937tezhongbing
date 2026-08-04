extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TRACE_SCRIPT: Script = preload("res://scripts/runtime_parity_trace.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const ORIGINAL_ITEMS: Script = preload("res://scripts/original_initial_item_inventory.gd")
const LEGACY_DISGUISE_RULES: Script = preload("res://scripts/legacy_disguise_rules.gd")

const OUTPUT_ARGUMENT_PREFIX := "--output-dir="
const MOVE_SPEED_ARGUMENT_PREFIX := "--move-speed="
const LEVEL_ARGUMENT_PREFIX := "--level-id="
const SCENARIO_ARGUMENT_PREFIX := "--scenario-id="
const PLAYER_SCENE_ARGUMENT_PREFIX := "--player-scene-index="
const OUTBOUND_ARGUMENT_PREFIX := "--outbound-target="
const RETURN_ARGUMENT_PREFIX := "--return-target="
const OBSERVATION_ARGUMENT_PREFIX := "--observation-seconds="
const COMMAND_HANDOFF_ARGUMENT_PREFIX := "--command-handoff-seconds="
const PATROL_SETTLE_ARGUMENT_PREFIX := "--patrol-settle-seconds="
const PRIMARY_DATABASE_ENTRY_ID := 924
const MINE_PICKUP_SCENARIO_ID := "m001-mine-pickup-inventory-v1"
const PISTOL_ATTACK_SCENARIO_ID := "m000-pistol-attack-inventory-v1"
const NATIVE_REQUIRED_FAILURE_SUFFIX := "-native-required-player-failure-v1"
const HUMAN_INPUT_NATURAL_FAILURE_SUFFIX := "-human-input-natural-failure-v1"
const HUMAN_INPUT_CHEAT_VICTORY_SUFFIX := "-human-input-cheat-victory-v1"
const NATIVE_REQUIRED_FAILURE_SCENES := {
	"m000": 1436,
	"m001": 1994,
	"m002": 886,
	"m003": 1150,
	"m004": 2629,
	"m005": 663,
	"m006": 1458,
	"m007": 2325,
	"m008": 753,
	"m009": 1709,
	"m010": 1590,
	"m011": 1176,
}
const HUMAN_INPUT_NATURAL_FAILURE_ROUTES := {
	"m000": {
		"player_scene": 1436,
		"selection_key": KEY_F4,
		"target_world": Vector2(1392.0, 536.0),
	},
	"m001": {
		"player_scene": 1994,
		"selection_key": KEY_F5,
		"target_world": Vector2(2800.0, 3848.0),
	},
	"m002": {
		"player_scene": 886,
		"selection_key": KEY_F2,
		"action_kind": "weapon_noise_lure",
		"weapon_key": KEY_5,
		"target_scene": 840,
		"approach_world": Vector2(464.0, 1688.0),
	},
	"m003": {
		"player_scene": 1150,
		"selection_key": KEY_F2,
		"target_world": Vector2(1104.0, 2968.0),
	},
	"m004": {
		"player_scene": 2629,
		"selection_key": KEY_F6,
		"target_world": Vector2(1936.0, 312.0),
	},
	"m005": {
		"player_scene": 663,
		"selection_key": KEY_F2,
		"target_world": Vector2(432.0, 2856.0),
	},
	"m006": {
		"player_scene": 1458,
		"selection_key": KEY_F4,
		"action_kind": "weapon_noise_lure",
		"weapon_key": KEY_5,
		"target_scene": 1429,
	},
	"m007": {
		"player_scene": 2325,
		"selection_key": KEY_F2,
		"action_kind": "weapon_noise_lure",
		"weapon_key": KEY_5,
		"target_scene": 2326,
		"post_shot_world": Vector2(1200.0, 640.0),
	},
	"m008": {
		"player_scene": 753,
		"selection_key": KEY_F2,
		"target_world": Vector2(1072.0, 424.0),
	},
	"m009": {
		"player_scene": 1709,
		"selection_key": KEY_F2,
		"action_kind": "weapon_noise_lure",
		"weapon_key": KEY_5,
		"target_scene": 1302,
		"post_shot_world": Vector2(400.0, 1360.0),
	},
	"m010": {
		"player_scene": 1590,
		"selection_key": KEY_F2,
		"action_kind": "weapon_noise_lure",
		"weapon_key": KEY_5,
		"target_scene": 1133,
		"cancel_weapon_key": KEY_1,
		"post_shot_candidates": [
			Vector2(160.0, 160.0),
			Vector2(176.0, 160.0),
			Vector2(192.0, 160.0),
			Vector2(208.0, 160.0),
			Vector2(208.0, 88.0),
			Vector2(240.0, 88.0),
			Vector2(272.0, 88.0),
			Vector2(304.0, 88.0),
			Vector2(208.0, 120.0),
			Vector2(240.0, 120.0),
			Vector2(272.0, 120.0),
			Vector2(304.0, 120.0),
			Vector2(208.0, 152.0),
			Vector2(240.0, 152.0),
			Vector2(272.0, 152.0),
			Vector2(304.0, 152.0),
			Vector2(640.0, 120.0),
			Vector2(640.0, 200.0),
			Vector2(640.0, 280.0),
			Vector2(480.0, 280.0),
			Vector2(800.0, 200.0),
		],
	},
	"m011": {
		"player_scene": 1176,
		"selection_key": KEY_F2,
		"target_world": Vector2(1936.0, 344.0),
	},
}
const SIGHT_DIRECT_TARGET_SCENARIO_ID := "m010-sight-direct-target-v1"
const BURIAL_COMMAND_SCENARIO_ID := "m010-burial-command-v1"
const BURIAL_COMPLETION_SCENARIO_ID := "m010-burial-completion-v1"
const BACKPACK_DROP_SCENARIO_ID := "m010-cigarette-drop-inventory-v1"
const M010_CONTEXT_TARGET_SCENE_INDEX := 1126
const M010_LAO_ZHAO_SCENE_INDEX := 1590
const M010_DANIU_SCENE_INDEX := 1591
const M001_PLAYER_SCENE_INDEX := 2280
const M001_MINE_SCENE_INDEX := 2096
const LAND_MINE_ITEM_ID := 43
const WEAPON_ATTACK_SCENARIOS := {
	PISTOL_ATTACK_SCENARIO_ID: {
		"player_scene": 1436,
		"target_scene": 1598,
		"attack_type": 1,
		"item_id": 36,
		"before_quantity": 7,
		"after_quantity": 6,
		"description": (
			"Select scene 1436, equip the original pistol and attack live "
			+ "scene 1598; capture the direct ammunition count before and after."
		),
	},
	"m010-rifle-attack-inventory-v1": {
		"player_scene": 1589,
		"target_scene": 1126,
		"attack_type": 2,
		"item_id": 37,
		"before_quantity": 20,
		"after_quantity": 19,
		"description": (
			"Select Qiangzi scene 1589, equip the original rifle and attack "
			+ "live scene 1126; capture the direct ammunition count."
		),
	},
	"m010-machine-gun-attack-inventory-v1": {
		"player_scene": 1589,
		"target_scene": 1126,
		"attack_type": 3,
		"item_id": 38,
		"before_quantity": 10,
		"after_quantity": 9,
		"description": (
			"Select Qiangzi scene 1589, equip the original machine gun and "
			+ "attack live scene 1126; capture one-count attack consumption."
		),
	},
	"m004-dart-attack-inventory-v1": {
		"player_scene": 2629,
		"target_scene": 2685,
		"attack_type": 6,
		"item_id": 41,
		"before_quantity": 20,
		"after_quantity": 19,
		"description": (
			"Select Daniu scene 2629, equip the original dart and attack "
			+ "stationary scene 2685; capture its mode-0 item consumption."
		),
	},
	"m007-slingshot-attack-inventory-v1": {
		"player_scene": 2298,
		"target_scene": 2389,
		"target_is_player": true,
		"attack_type": 7,
		"item_id": 42,
		"before_quantity": 1,
		"after_quantity": 1,
		"require_target_damage": true,
		"force_target": true,
		"description": (
			"Select Tiedan scene 2298, equip his original durable slingshot, "
			+ "and force-target adjacent Gu Ming scene 2389; verify item 42 "
			+ "remains owned and the projectile commits target damage."
		),
	},
	"m007-special-attention-attack-inventory-v1": {
		"player_scene": 2389,
		"target_scene": 2298,
		"target_is_player": true,
		"attack_type": 11,
		"item_id": 99,
		"before_quantity": 1,
		"after_quantity": 1,
		"complete_guming_disguise": true,
		"require_attention_hold": true,
		"force_target": true,
		"description": (
			"Complete Gu Ming scene 2389's original uniform transition, "
			+ "then force-target adjacent scene 2298 with type 11; verify "
			+ "the attention hold "
			+ "and durable item 99."
		),
	},
	"m010-dagger-attack-inventory-v1": {
		"player_scene": 1591,
		"target_scene": 1126,
		"attack_type": 4,
		"item_id": 39,
		"before_quantity": 1,
		"after_quantity": 1,
		"after_target_hit_points": 0,
		"description": (
			"Select Daniu scene 1591, equip the original dagger and attack "
			+ "live scene 1126; capture durable mode-1 inventory plus the "
			+ "committed target outcome."
		),
	},
	"m010-broadsword-attack-inventory-v1": {
		"player_scene": 1591,
		"target_scene": 1126,
		"attack_type": 5,
		"item_id": 40,
		"before_quantity": 1,
		"after_quantity": 1,
		"after_target_hit_points": 0,
		"description": (
			"Select Daniu scene 1591, equip the original broadsword and "
			+ "attack live scene 1126; capture durable mode-1 inventory plus "
			+ "the committed target outcome."
		),
	},
	"m010-grenade-attack-inventory-v1": {
		"player_scene": 1589,
		"target_scene": 1126,
		"attack_type": 9,
		"item_id": 44,
		"before_quantity": 3,
		"after_quantity": 2,
		"description": (
			"Select Qiangzi scene 1589, equip the original grenade and attack "
			+ "live scene 1126; capture its mode-0 item consumption."
		),
	},
	"m010-mine-deploy-inventory-v1": {
		"player_scene": 1590,
		"attack_type": 8,
		"item_id": 43,
		"before_quantity": 3,
		"after_quantity": 2,
		"world_point": Vector2(176.0, 104.0),
		"description": (
			"Select Lao Zhao scene 1590, equip the original mine and deploy "
			+ "it at the verified walkable point (176,104); capture mode-0 "
			+ "item consumption."
		),
	},
	"m010-explosive-deploy-inventory-v1": {
		"player_scene": 1590,
		"attack_type": 10,
		"item_id": 45,
		"before_quantity": 3,
		"after_quantity": 2,
		"world_point": Vector2(176.0, 104.0),
		"description": (
			"Select Lao Zhao scene 1590, equip the original timed explosive "
			+ "and deploy it at the verified walkable point (176,104); "
			+ "capture mode-0 item consumption."
		),
	},
}
const WORLD_ITEM_SCENARIOS := {
	"m007-chicken-world-item-v1": {
		"target_scene": 2327,
		"item_id": 33,
		"before_quantity": 0,
		"after_quantity": 1,
		"description": (
			"Create an authentic type-33 chicken world actor at enemy scene "
			+ "2327, then observe the normal scan, collection and durable transfer."
		),
	},
	"m010-canned-meat-world-item-v1": {
		"target_scene": 1126,
		"item_id": 48,
		"before_quantity": 1,
		"after_quantity": 2,
		"description": (
			"Create an authentic type-48 canned-meat world actor at enemy "
			+ "scene 1126 and observe the normal durable transfer."
		),
	},
	"m010-hypnosis-doll-world-item-v1": {
		"target_scene": 1126,
		"item_id": 49,
		"before_quantity": 0,
		"after_quantity": 0,
		"effect": "hypnosis",
		"description": (
			"Create an authentic type-49 hypnosis doll at enemy scene 1126 "
			+ "and observe forced consumption plus temporary player control."
		),
	},
	"m010-poisoned-wine-world-item-v1": {
		"target_scene": 1126,
		"item_id": 52,
		"before_quantity": 0,
		"after_quantity": 0,
		"effect": "poison",
		"description": (
			"Create authentic type-52 poisoned wine at enemy scene 1126 and "
			+ "observe forced consumption, distraction and delayed damage."
		),
	},
	"m009-dog-bone-world-item-v1": {
		"target_scene": 1355,
		"item_id": 82,
		"before_quantity": 0,
		"after_quantity": 1,
		"effect": "distraction",
		"description": (
			"Create an authentic type-82 dog bone at dog scene 1355 and "
			+ "observe its durable transfer and bounded distraction."
		),
	},
	"m010-cigarette-world-item-v1": {
		"target_scene": 1126,
		"item_id": 83,
		"before_quantity": 0,
		"after_quantity": 1,
		"effect": "distraction",
		"description": (
			"Create an authentic type-83 cigarette at enemy scene 1126 and "
			+ "observe its durable transfer and bounded distraction."
		),
	},
}
## Layer-3-verified, obstacle-free cell centres: (1,3) and (5,3).
## The short observation window issues the return order before the first
## command can settle, so goal replacement and facing are both observable.
const OUTBOUND_TARGET := Vector2(48.0, 56.0)
const RETURN_TARGET := Vector2(176.0, 56.0)
const OBSERVATION_SECONDS := 0.75
## The reference trace records the first scene-1598 hit at the return-observed
## checkpoint and the second one at the settled checkpoint. Bound those event
## milestones by simulated physics ticks. A wall-clock SceneTreeTimer can expire
## after fewer physics ticks on a busy CI host and move an otherwise identical
## hit into the following checkpoint.
const NATURAL_CONTACT_FIRST_DAMAGE_DEADLINE_SECONDS := 6.0
const NATURAL_CONTACT_SECOND_DAMAGE_DEADLINE_SECONDS := 3.0
## Every identity-resolved stable-MOD patrol trace records its comparable
## gameplay-entry movement window from five seconds onward. Use simulation
## time so CI load cannot shift the patrol/controller phase.
const PATROL_CAPTURE_SETTLE_SECONDS := 5.0
## The natural-contact reference's contact-ready positions are the same
## gameplay-entry patrol checkpoint. The old 9.2-second value compensated for
## the pre-evidence authored-route phase; the recovered timeline reaches the
## corresponding MOD positions at exactly five simulated seconds.
const NATURAL_CONTACT_CAPTURE_SETTLE_SECONDS := 5.0
## The read-only MOD trace has a 307 ms handoff between the outbound-observed
## snapshot and the replacement command. Reproduce that physics time instead
## of relying on host-dependent process/screenshot latency.
const NATURAL_CONTACT_COMMAND_HANDOFF_SECONDS := 0.30
const FORMAL_LEVEL_IDS: Array[String] = [
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

var output_directory := ""
var failures: Array[String] = []


func _init() -> void:
	output_directory = _parse_output_directory(OS.get_cmdline_user_args())
	call_deferred("_run_probe")


func _run_probe() -> void:
	var arguments := OS.get_cmdline_user_args()
	var level_id := _parse_level_id(arguments)
	var level_index := FORMAL_LEVEL_IDS.find(level_id)
	var scenario_id := _parse_string_argument(
		arguments,
		SCENARIO_ARGUMENT_PREFIX,
		(
			"m000-basic-movement-v1"
			if level_id == "m000"
			else _enemy_patrol_scenario_id(level_id)
		),
	)
	var player_scene_index := _parse_integer_argument(
		arguments,
		PLAYER_SCENE_ARGUMENT_PREFIX,
		-1,
	)
	var outbound_target := _parse_vector_argument(
		arguments,
		OUTBOUND_ARGUMENT_PREFIX,
		OUTBOUND_TARGET,
	)
	var return_target := _parse_vector_argument(
		arguments,
		RETURN_ARGUMENT_PREFIX,
		RETURN_TARGET,
	)
	var observation_seconds := _parse_positive_float_argument(
		arguments,
		OBSERVATION_ARGUMENT_PREFIX,
		OBSERVATION_SECONDS,
	)
	var command_handoff_seconds := _parse_positive_float_argument(
		arguments,
		COMMAND_HANDOFF_ARGUMENT_PREFIX,
		0.0,
	)
	var patrol_settle_seconds := _parse_positive_float_argument(
		arguments,
		PATROL_SETTLE_ARGUMENT_PREFIX,
		PATROL_CAPTURE_SETTLE_SECONDS,
	)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	if int(main.get("current_level_index")) != level_index:
		main.call("switch_level", level_index, false, false)
		await process_frame
	var started := Time.get_ticks_usec()

	var trace = TRACE_SCRIPT.new()
	var scenario_description := _scenario_description(scenario_id, level_id)
	trace.configure(
		"remake",
		level_id,
		level_index + 1,
		level_index + 1,
		scenario_id,
		scenario_description,
	)
	if scenario_id == MINE_PICKUP_SCENARIO_ID:
		await _run_mine_pickup_probe(main, trace, started)
		return
	if scenario_id == _human_input_natural_failure_scenario_id(level_id):
		await _run_human_input_natural_failure_probe(
			main,
			trace,
			started,
			level_id,
			scenario_id,
		)
		return
	if scenario_id == _human_input_cheat_victory_scenario_id(level_id):
		await _run_human_input_cheat_victory_probe(
			main,
			trace,
			started,
			level_id,
			scenario_id,
		)
		return
	if scenario_id == _native_required_failure_scenario_id(level_id):
		await _run_native_required_failure_probe(
			main,
			trace,
			started,
			int(NATIVE_REQUIRED_FAILURE_SCENES.get(level_id, -1)),
			scenario_id,
		)
		return
	if WEAPON_ATTACK_SCENARIOS.has(scenario_id):
		await _run_weapon_attack_probe(main, trace, started, scenario_id)
		return
	if WORLD_ITEM_SCENARIOS.has(scenario_id):
		await _run_world_item_probe(main, trace, started, scenario_id)
		return
	if scenario_id == BACKPACK_DROP_SCENARIO_ID:
		await _run_backpack_drop_probe(main, trace, started)
		return
	if scenario_id == SIGHT_DIRECT_TARGET_SCENARIO_ID:
		await _run_sight_direct_target_probe(main, trace, started)
		return
	if scenario_id in [
		BURIAL_COMMAND_SCENARIO_ID,
		BURIAL_COMPLETION_SCENARIO_ID,
	]:
		await _run_burial_command_probe(
			main,
			trace,
			started,
			scenario_id == BURIAL_COMPLETION_SCENARIO_ID,
		)
		return
	if scenario_id == _enemy_patrol_scenario_id(level_id):
		await _run_enemy_patrol_probe(
			main,
			trace,
			started,
			observation_seconds,
			level_id,
			patrol_settle_seconds,
		)
		return
	if scenario_id == "m000-natural-contact-v1":
		await _run_natural_contact_probe(
			main,
			trace,
			started,
			outbound_target,
			return_target,
			observation_seconds,
		)
		return
	trace.capture_main("gameplay_ready", main, _elapsed_ms(started))

	var primary = (
		_player_for_scene(main, player_scene_index)
		if player_scene_index >= 0
		else _primary_unit(main)
	)
	_expect(
		primary != null,
		(
			"requested controllable scene %d exists" % player_scene_index
			if player_scene_index >= 0
			else "m000 primary DBL 924 actor exists"
		),
	)
	if primary != null:
		var initial_position: Vector2 = primary.position
		var calibrated_speed := _parse_move_speed(arguments)
		if calibrated_speed > 0.0:
			primary.set("move_speed", calibrated_speed)
		main.select_only(primary)
		trace.capture_main("player_selected", main, _elapsed_ms(started))

		main.issue_formation_move(outbound_target)
		_expect(
			primary.target_position.distance_to(outbound_target) <= 1.0,
			"outbound target is accepted exactly",
		)
		if command_handoff_seconds > 0.0:
			await _wait_physics_seconds(command_handoff_seconds)
		trace.capture_main(
			"move_outbound_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var outbound_observed_positions := await _observe_movement_positions(
			primary,
			observation_seconds,
		)
		trace.capture_main(
			"move_outbound_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main, outbound_observed_positions),
		)
		_expect(
			primary.position.distance_to(outbound_target)
			< initial_position.distance_to(outbound_target),
			"outbound movement approaches the target",
		)

		var outbound_position: Vector2 = primary.position
		main.issue_formation_move(return_target)
		_expect(
			primary.target_position.distance_to(return_target) <= 1.0,
			"second click replaces the active goal",
		)
		if command_handoff_seconds > 0.0:
			await _wait_physics_seconds(command_handoff_seconds)
		trace.capture_main(
			"move_return_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var return_observed_positions := await _observe_movement_positions(
			primary,
			observation_seconds,
		)
		trace.capture_main(
			"move_return_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main, return_observed_positions),
		)
		_expect(
			primary.position.distance_to(return_target)
			< outbound_position.distance_to(return_target),
			"return movement approaches the replacement target",
		)

	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(trace.write_to_file(trace_path) == OK, "Remake parity trace writes")
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace.document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_mine_pickup_probe(
	main: Node,
	trace: RefCounted,
	started: int,
) -> void:
	var collector := _player_for_scene(main, M001_PLAYER_SCENE_INDEX)
	var pickup := _field_pickup_for_scene(main, M001_MINE_SCENE_INDEX)
	_expect(collector != null, "m001 scene 2280 player exists")
	_expect(pickup != null, "m001 scene 2096 mine pickup exists")
	if collector != null and pickup != null:
		main.call("select_only", collector)
		var before_quantity := _inventory_quantity(
			collector,
			"weapon_entries",
			LAND_MINE_ITEM_ID,
		)
		trace.call(
			"capture_main",
			"before_pickup",
			main,
			_elapsed_ms(started),
		)
		var order_issued := bool(
			main.call("issue_original_pickup_order", pickup)
		)
		_expect(order_issued, "m001 mine click submits the original pickup order")
		var quantity_changed := await _wait_for_inventory_quantity(
			collector,
			"weapon_entries",
			LAND_MINE_ITEM_ID,
			before_quantity + 1,
			10.0,
		)
		_expect(
			quantity_changed,
			"m001 original mine pickup adds exactly one item 43",
		)
		trace.call(
			"capture_main",
			"after_pickup",
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(
				collector,
				"weapon_entries",
				LAND_MINE_ITEM_ID,
			) == before_quantity + 1,
			"m001 mine quantity delta remains exact at capture",
		)
	await _finish_inventory_probe(
		main,
		trace,
		MINE_PICKUP_SCENARIO_ID,
	)


func _run_native_required_failure_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	required_scene_index: int,
	scenario_id: String,
) -> void:
	var player := _player_for_scene(main, required_scene_index)
	_expect(
		player != null,
		"required player scene %d exists" % required_scene_index,
	)
	if player != null:
		trace.call(
			"capture_main",
			"gameplay_active",
			main,
			_elapsed_ms(started),
			{
				"damage_entry": "SquadUnit.take_damage",
				"mission_evaluator": "MissionRuntime.record_event",
			},
		)
		var hit_points_before := int(player.get("current_hit_points"))
		var applied := int(player.call("take_damage", 32, null))
		_expect(
			applied == hit_points_before,
			"Remake accepts the same unconditional 32-damage native probe",
		)
		_expect(
			not bool(player.get("is_alive"))
			and int(player.get("current_hit_points")) == 0,
			"scene %d reaches the authentic dead/zero-HP state"
			% required_scene_index,
		)
		_expect(
			main.current_mission_state.is_failed()
			and str(main.current_mission_state.failure_id)
				== "required_character_lost",
			"real actor death reaches the required-character failure",
		)
		trace.call(
			"capture_main",
			"required_player_lost",
			main,
			_elapsed_ms(started),
			{
				"damage_entry": "SquadUnit.take_damage",
				"mission_evaluator": "MissionRuntime.record_event",
				"original_result_state": 2,
			},
		)
	await _finish_inventory_probe(
		main,
		trace,
		scenario_id,
	)


func _run_human_input_cheat_victory_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	level_id: String,
	scenario_id: String,
) -> void:
	_expect(
		main.current_mission_state != null
			and not main.current_mission_state.is_failed()
			and not main.current_mission_state.is_victory(),
		"%s begins in the active mission state" % level_id,
	)
	trace.call(
		"capture_main",
		"gameplay_active",
		main,
		_elapsed_ms(started),
		{
			"input_isolation": "target-viewport-events",
			"mission_result_writes": 0,
			"original_result_state": 0,
		},
	)

	var input_sequence := await _type_original_cheat_text(main, "FLIPMISSION")
	# Victory handling schedules media/save presentation with call_deferred().
	# Let those product callbacks observe the same input-driven state before the
	# second checkpoint, without calling the completion method from this probe.
	for _frame_index: int in range(4):
		await process_frame
	var all_objectives_completed := true
	for objective_value: Variant in main.current_mission_state.completed.values():
		if not bool(objective_value):
			all_objectives_completed = false
			break
	_expect(
		input_sequence.size() == "FLIPMISSION".length(),
		"all eleven original cheat letters reach the target viewport",
	)
	_expect(
		main.current_mission_state.is_victory()
			and not main.current_mission_state.is_failed(),
		"%s FLIPMISSION input reaches the product victory state" % level_id,
	)
	_expect(
		all_objectives_completed,
		"%s cheat transition marks every authored objective complete" % level_id,
	)
	_expect(
		str(main.get("original_cheat_buffer")).is_empty()
			and str(main.get("victory_handled_level_id")) == level_id,
		"%s product victory handler consumes and records the cheat transition"
		% level_id,
	)
	trace.call(
		"capture_main",
		"cheat_input_committed",
		main,
		_elapsed_ms(started),
		{
			"input_isolation": "target-viewport-events",
			"mission_result_writes": 0,
			"original_result_state": 3,
			"cheat_code": "FLIPMISSION",
			"cheat_key_count": input_sequence.size(),
		},
	)

	var trace_document: Dictionary = trace.get("document") as Dictionary
	var metadata := trace_document.get("metadata", {}) as Dictionary
	metadata.merge(
		{
			"input_isolation": "target-viewport-events",
			"mission_evaluator": "MissionState+Main._on_mission_victory",
			"mission_observer": "RuntimeParityTrace-read-only",
			"evidence_scope": "cheat-victory-transition-only",
			"cheat_code": "FLIPMISSION",
			"cheat_key_count": input_sequence.size(),
			"mission_result_writes": 0,
			"actor_state_writes": 0,
			"system_cursor_calls": 0,
			"system_keyboard_calls": 0,
			"global_focus_calls": 0,
		},
		true,
	)
	trace_document["metadata"] = metadata
	trace_document["input"] = {
		"action_kind": "original_builtin_cheat_text",
		"text": "FLIPMISSION",
		"viewport_input_events": input_sequence.size() * 2,
		"sequence": input_sequence,
	}
	trace_document["passed"] = failures.is_empty()
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake human-input cheat-victory parity trace writes",
		)
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (
					trace_document.get("checkpoints", []) as Array
				).size(),
				"viewport_input_events": input_sequence.size() * 2,
				"failures": failures,
			}
		)
	)
	get_root().remove_child(main)
	main.free()
	await process_frame
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_human_input_natural_failure_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	level_id: String,
	scenario_id: String,
) -> void:
	var route := (
		HUMAN_INPUT_NATURAL_FAILURE_ROUTES.get(level_id, {}) as Dictionary
	)
	var player_scene := int(route.get("player_scene", -1))
	var player := _player_for_scene(main, player_scene)
	_expect(not route.is_empty(), "%s natural-failure route exists" % level_id)
	_expect(
		player != null,
		"%s required player scene %d exists" % [level_id, player_scene],
	)
	var input_kind := str(route.get("action_kind", "ground_danger_route"))
	var target_scene := int(route.get("target_scene", -1))
	var target_world := route.get("target_world", Vector2.ZERO) as Vector2
	var hit_point_samples: Array[int] = []
	var attacker_scene_indices: Array[int] = []
	var input_submitted := false
	var attack_command_observed := false
	var before_pistol_quantity := -1
	var after_pistol_quantity := -1
	var viewport_input_events := 0
	var input_sequence: Array[Dictionary] = []
	var post_shot_world_used := Vector2.ZERO
	var attacker_runtime_samples: Array[Dictionary] = []

	if player != null:
		# The stable-MOD capture checks five seconds of spawn safety before it
		# submits input. Keep the same autonomous-world phase while driving only
		# target-viewport key and mouse events.
		await _wait_physics_seconds(5.0)
		hit_point_samples.append(int(player.get("current_hit_points")))
		trace.call(
			"capture_main",
			"gameplay_active",
			main,
			_elapsed_ms(started),
			{
				"input_isolation": "target-viewport-events",
				"mission_result_writes": 0,
				"system_cursor_calls": 0,
				"global_focus_calls": 0,
			},
		)

		await _tap_key(route.get("selection_key", KEY_F2) as Key)
		viewport_input_events += 2
		input_sequence.append({
			"kind": "character_hotkey",
			"keycode": int(route.get("selection_key", KEY_F2)),
			"scene_index": player_scene,
		})
		_expect(
			(main.get("selected_units") as Array).size() == 1
				and (main.get("selected_units") as Array)[0] == player,
			"%s original character hotkey selects only scene %d"
			% [level_id, player_scene],
		)

		if input_kind == "weapon_noise_lure":
			var lure := _enemy_for_scene(main, target_scene)
			_expect(
				lure != null,
				"%s noise-lure enemy scene %d exists"
				% [level_id, target_scene],
			)
			if lure != null:
				if route.has("approach_world"):
					var approach_world := route["approach_world"] as Vector2
					await _pan_view_to_world(main, approach_world)
					await _click_world(main, approach_world)
					viewport_input_events += 5
					input_sequence.append({
						"kind": "ground_move",
						"world": [approach_world.x, approach_world.y],
						"purpose": "approach_lure",
					})
					var approach_reached := false
					for _frame_index: int in range(900):
						if player.position.distance_to(approach_world) <= 18.0:
							approach_reached = true
							break
						if not bool(player.get("is_alive")):
							break
						await physics_frame
					_expect(
						approach_reached,
						"%s viewport ground click reaches the audited lure point"
						% level_id,
					)
				target_world = lure.position
				before_pistol_quantity = _inventory_quantity(
					player,
					"weapon_entries",
					36,
				)
				await _tap_key(route.get("weapon_key", KEY_5) as Key)
				viewport_input_events += 2
				input_sequence.append({
					"kind": "weapon_hotkey",
					"keycode": int(route.get("weapon_key", KEY_5)),
					"attack_type": 1,
				})
				_expect(
					int(
						(player.get("weapon_profile") as Dictionary)
						. get("attack_type", 0)
					) == 1,
					"%s original digit 5 equips the pistol" % level_id,
				)
				await _pan_view_to_world(main, target_world)
				# Patrol actors continue moving while the middle-drag input is
				# processed. Aim at the current actor origin, not the position
				# sampled before the camera gesture.
				target_world = lure.position
				_expect(
					main.call("enemy_at_world_point", target_world) == lure,
					"%s current lure coordinate resolves scene %d before input"
					% [level_id, target_scene],
				)
				await _click_world(main, target_world, true)
				viewport_input_events += 5
				input_sequence.append({
					"kind": "force_target_attack",
					"scene_index": target_scene,
					"world": [target_world.x, target_world.y],
					"modifier": "ctrl",
				})
				input_submitted = true
				attack_command_observed = player.get("combat_target") == lure
				for _frame_index: int in range(180):
					after_pistol_quantity = _inventory_quantity(
						player,
						"weapon_entries",
						36,
					)
					if (
						after_pistol_quantity < before_pistol_quantity
						or player.get("combat_target") == lure
					):
						attack_command_observed = true
					if after_pistol_quantity < before_pistol_quantity:
						break
					await physics_frame
				_expect(
					attack_command_observed
						and after_pistol_quantity < before_pistol_quantity,
					(
						"%s pistol click enters the real combat pipeline "
						+ "and consumes direct ammunition"
					) % level_id,
				)
				if route.has("cancel_weapon_key"):
					var action_finished := false
					for _frame_index: int in range(180):
						if int(player.get("combat_action")) == 0:
							action_finished = true
							break
						await physics_frame
					_expect(
						action_finished,
						"%s first audible pistol action reaches its final frame" % level_id,
					)
					await _tap_key(route["cancel_weapon_key"] as Key)
					viewport_input_events += 2
					input_sequence.append({
						"kind": "weapon_hotkey",
						"keycode": int(route["cancel_weapon_key"]),
						"attack_type": 4,
						"purpose": "release_sustained_fire",
					})
					_expect(
						int(
							(player.get("weapon_profile") as Dictionary).get(
								"attack_type", 0
							)
						) == 4
							and player.get("combat_target") == null,
						"%s original digit 1 releases sustained pistol fire" % level_id,
					)
				var has_post_shot_order := (
					route.has("post_shot_world")
					or route.has("post_shot_candidates")
				)
				if has_post_shot_order:
					# One follow-up ground command is genuine player input and mirrors
					# releasing an attack order after its first audible shot.  It keeps
					# this probe about enemy retaliation instead of letting the player
					# empty an entire pistol into the selected guard.
					var post_shot_world := route.get(
						"post_shot_world", Vector2.ZERO
					) as Vector2
					if route.has("post_shot_candidates"):
						post_shot_world = _first_audited_ground_destination(
							main,
							player,
							route["post_shot_candidates"] as Array,
						)
					_expect(
						not post_shot_world.is_equal_approx(Vector2.ZERO),
						"%s resolves a reachable interaction-free follow-up point" % level_id,
					)
					post_shot_world_used = post_shot_world
					await _pan_view_to_world(main, post_shot_world)
					await _click_world(main, post_shot_world)
					viewport_input_events += 5
					input_sequence.append({
						"kind": "ground_move",
						"world": [post_shot_world.x, post_shot_world.y],
						"purpose": "enter_retaliation_zone",
					})
					await physics_frame
					var post_shot_target := player.get("target_position") as Vector2
					_expect(
						player.get("combat_target") == null
							and (
								post_shot_target.distance_to(post_shot_world) <= 24.0
								or not (
									player.get("movement_path") as PackedVector2Array
								).is_empty()
							),
						"%s follow-up ground click releases sustained fire"
						% level_id,
					)
		else:
			await _pan_view_to_world(main, target_world)
			await _click_world(main, target_world)
			viewport_input_events += 5
			input_sequence.append({
				"kind": "ground_move",
				"world": [target_world.x, target_world.y],
				"purpose": "danger_route",
			})
			input_submitted = true
			await physics_frame
			var target_position := player.get("target_position") as Vector2
			attack_command_observed = (
				target_position.distance_to(target_world) <= 1.0
				or not (player.get("movement_path") as PackedVector2Array).is_empty()
				or player.get("combat_target") != null
			)
			_expect(
				attack_command_observed,
				"%s ground click submits the audited danger route" % level_id,
			)
		_expect(input_submitted, "%s natural-failure input is submitted" % level_id)
		trace.call(
			"capture_main",
			"failure_input_submitted",
			main,
			_elapsed_ms(started),
			{
				"action_kind": input_kind,
				"target_scene_index": target_scene,
				"target_world": [target_world.x, target_world.y],
			},
		)

		for _frame_index: int in range(2400):
			var hit_points := int(player.get("current_hit_points"))
			if hit_point_samples.back() != hit_points:
				hit_point_samples.append(hit_points)
			var last_attacker := int(
				player.get("last_damage_attacker_scene_index")
			)
			if last_attacker >= 0 and not attacker_scene_indices.has(last_attacker):
				attacker_scene_indices.append(last_attacker)
			for enemy: Node2D in main.get("enemies") as Array:
				if (
					enemy.get("current_target") == player
					and not attacker_scene_indices.has(
						int(enemy.get("scene_index"))
					)
				):
					attacker_scene_indices.append(
						int(enemy.get("scene_index"))
					)
				if (
					_frame_index % 30 == 0
					and (
						enemy.get("current_target") == player
						or attacker_scene_indices.has(
							int(enemy.get("scene_index"))
						)
						or (
							int(enemy.get("behavior_state")) != 0
							and enemy.position.distance_to(player.position) < 1000.0
						)
					)
				):
					var path := enemy.get("movement_path") as PackedVector2Array
					var live_target: Variant = enemy.get("current_target")
					attacker_runtime_samples.append({
						"frame": _frame_index,
						"scene_index": int(enemy.get("scene_index")),
						"position": [enemy.position.x, enemy.position.y],
						"behavior_state": int(enemy.get("behavior_state")),
						"target_scene_index": int(
							live_target.get("scene_index")
							if live_target is Node2D and is_instance_valid(live_target)
							else -1
						),
						"can_attack": bool(enemy.call("_can_attack_current_target")),
						"attack_count": int(enemy.get("attack_count")),
						"attack_recheck_elapsed": float(
							enemy.get("attack_recheck_elapsed")
						),
						"attack_recheck_seconds": float(
							enemy.get("attack_recheck_seconds")
						),
						"combat_action": int(enemy.get("combat_action")),
						"action_finished": bool(enemy.get("action_finished")),
						"movement_path_remaining": maxi(
							path.size() - int(enemy.get("movement_path_index")),
							0,
						),
						"target_position": [
							(enemy.get("target_position") as Vector2).x,
							(enemy.get("target_position") as Vector2).y,
						],
						"last_known_target_position": [
							(enemy.get("last_known_target_position") as Vector2).x,
							(enemy.get("last_known_target_position") as Vector2).y,
						],
						"use_soft_dynamic_occupancy": bool(
							enemy.get("use_soft_dynamic_occupancy")
						),
					})
			if (
				not bool(player.get("is_alive"))
				or int(player.get("current_hit_points")) <= 0
			):
				break
			await physics_frame
		attacker_scene_indices.sort()
		_expect(
			hit_point_samples.size() >= 2
				and hit_point_samples.back() == 0
				and not bool(player.get("is_alive")),
			"%s original enemy AI naturally reduces scene %d from 8 HP to death"
			% [level_id, player_scene],
		)
		_expect(
			int(player.get("damage_event_count")) > 0
				and int(player.get("damage_taken_total"))
					>= hit_point_samples[0],
			"%s death contains real enemy damage events" % level_id,
		)
		_expect(
			main.current_mission_state.is_failed()
				and str(main.current_mission_state.failure_id)
					== "required_character_lost",
			"%s natural actor death reaches required_character_lost" % level_id,
		)
		trace.call(
			"capture_main",
			"required_player_lost",
			main,
			_elapsed_ms(started),
			{
				"damage_entry": "original_unmodified_gameplay_pipeline",
				"mission_evaluator": "MissionRuntime.record_event",
				"original_result_state": 2,
			},
		)

	var trace_document: Dictionary = trace.get("document") as Dictionary
	var metadata := trace_document.get("metadata", {}) as Dictionary
	metadata.merge(
		{
			"input_isolation": "target-viewport-events",
			"damage_entry": "original_unmodified_gameplay_pipeline",
			"mission_evaluator": "MissionRuntime.record_event",
			"mission_result_writes": 0,
			"system_cursor_calls": 0,
			"global_focus_calls": 0,
		},
		true,
	)
	trace_document["metadata"] = metadata
	var input_document := {
		"action_kind": input_kind,
		"player_scene_index": player_scene,
		"target_scene_index": target_scene,
		"target_world": [target_world.x, target_world.y],
		"target_cell": [
			floori(target_world.x / 32.0),
			floori(target_world.y / 16.0),
		],
		"viewport_input_events": viewport_input_events,
		"sequence": input_sequence,
		"pistol_quantity": [
			before_pistol_quantity,
			after_pistol_quantity,
		],
	}
	if not post_shot_world_used.is_equal_approx(Vector2.ZERO):
		input_document["post_shot_world"] = [
			post_shot_world_used.x,
			post_shot_world_used.y,
		]
	trace_document["input"] = input_document
	trace_document["combat"] = {
		"hit_point_samples": hit_point_samples,
		"attacker_scene_indices": attacker_scene_indices,
		"damage_event_count": (
			int(player.get("damage_event_count")) if player != null else 0
		),
		"damage_taken_total": (
			int(player.get("damage_taken_total")) if player != null else 0
		),
		"attacker_runtime_samples": attacker_runtime_samples,
	}
	trace_document["passed"] = failures.is_empty()
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		var write_error: Error = trace.call("write_to_file", trace_path)
		_expect(write_error == OK, "Remake natural-failure parity trace writes")
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (
					trace_document.get("checkpoints", []) as Array
				).size(),
				"hit_point_samples": hit_point_samples,
				"attacker_scene_indices": attacker_scene_indices,
				"failures": failures,
			}
		)
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_weapon_attack_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	scenario_id: String,
) -> void:
	var scenario: Dictionary = WEAPON_ATTACK_SCENARIOS[scenario_id]
	var player_scene := int(scenario.get("player_scene", -1))
	var target_scene := int(scenario.get("target_scene", -1))
	var attack_type := int(scenario.get("attack_type", 0))
	var item_id := int(scenario.get("item_id", -1))
	var before_expected := int(scenario.get("before_quantity", -1))
	var after_expected := int(scenario.get("after_quantity", -1))
	var is_deployment := scenario.has("world_point")
	var attacker := _player_for_scene(main, player_scene)
	var target = null
	if not is_deployment:
		target = (
			_combatant_for_scene(main, target_scene)
			if bool(scenario.get("target_is_player", false))
			else _enemy_for_scene(main, target_scene)
		)
	_expect(attacker != null, "weapon parity player scene %d exists" % player_scene)
	if not is_deployment:
		_expect(target != null, "weapon parity target scene %d exists" % target_scene)
	if attacker != null and (is_deployment or target != null):
		main.call("select_only", attacker)
		if bool(scenario.get("seed_original_weapon", false)):
			var seeded_profile: Dictionary = (
				COMBAT_PROFILES.weapon_profile_for_attack_type(attack_type)
			)
			var seeded_groups: Array[Dictionary] = (
				main.call(
					"_attack_groups_for_unit",
					attacker,
					str(seeded_profile.get("action_key", "")),
				)
				as Array[Dictionary]
			)
			_expect(
				bool(
					attacker.call(
						"register_original_inventory_weapon",
						seeded_profile,
						seeded_groups,
						before_expected,
						1,
						false,
					)
				),
				"scene %d receives original durable item %d" % [
					player_scene,
					item_id,
				],
			)
		if bool(scenario.get("complete_guming_disguise", false)):
			var backpack: Variant = attacker.get("backpack_inventory")
			_expect(backpack != null, "Gu Ming backpack exists for disguise parity")
			if backpack != null:
				if not bool(backpack.call("has_item", 54)):
					attacker.call("add_backpack_item", 54, 1, 0)
				_expect(
					bool(
						main.call(
							"_use_original_backpack_item",
							attacker,
							54,
							ORIGINAL_ITEMS.item_profile(54),
						)
					),
					"Gu Ming begins the original uniform transition",
				)
				for unused_tick: int in range(
					LEGACY_DISGUISE_RULES.CHANGE_TICK_LIMIT + 1
				):
					attacker.call(
						"advance_original_disguise_transition",
						(
							LEGACY_DISGUISE_RULES.ORIGINAL_ACTOR_TICK_SECONDS
							+ 0.000001
						),
					)
				_expect(
					int(attacker.get("runtime_actor_type")) == 91
					and int(attacker.get("faction_id")) == 1,
					"Gu Ming reaches authentic type 91 enemy-uniform state",
				)
		_expect(
			bool(attacker.call("equip_attack_type", attack_type)),
			"scene %d equips original attack type %d" % [
				player_scene,
				attack_type,
			],
		)
		var before_quantity := _inventory_quantity(
			attacker,
			"weapon_entries",
			item_id,
		)
		var before_target_hit_points := (
			int(target.get("current_hit_points")) if target != null else -1
		)
		_expect(
			before_quantity == before_expected,
			"item %d starts at the original quantity %d" % [
				item_id,
				before_expected,
			],
		)
		var checkpoint_verb := "deploy" if is_deployment else "attack"
		trace.call(
			"capture_main",
			"before_%s" % checkpoint_verb,
			main,
			_elapsed_ms(started),
		)
		if is_deployment:
			_expect(
				bool(
					main.call(
						"_try_issue_legacy_world_object_deployment",
						scenario["world_point"] as Vector2,
					)
				),
				"attack type %d accepts the original deployment point" % attack_type,
			)
		else:
			main.call(
				"issue_attack_order",
				target,
				bool(scenario.get("force_target", false)),
			)
		var quantity_changed := false
		var target_hit_points_changed := true
		var attention_hold_observed := true
		if bool(scenario.get("require_attention_hold", false)):
			attention_hold_observed = await _wait_for_attention_hold(
				target,
				12.0,
			)
			quantity_changed = (
				_inventory_quantity(
					attacker,
					"weapon_entries",
					item_id,
				)
				== after_expected
			)
		elif bool(scenario.get("require_target_damage", false)):
			target_hit_points_changed = await _wait_for_target_damage(
				target,
				before_target_hit_points,
				12.0,
			)
			quantity_changed = (
				_inventory_quantity(
					attacker,
					"weapon_entries",
					item_id,
				)
				== after_expected
			)
		elif scenario.has("after_target_hit_points"):
			target_hit_points_changed = await _wait_for_target_hit_points(
				target,
				int(scenario["after_target_hit_points"]),
				12.0,
			)
			quantity_changed = (
				_inventory_quantity(
					attacker,
					"weapon_entries",
					item_id,
				)
				== after_expected
			)
		else:
			quantity_changed = await _wait_for_inventory_quantity(
				attacker,
				"weapon_entries",
				item_id,
				after_expected,
				12.0,
			)
		_expect(
			quantity_changed,
			"attack type %d reaches item %d quantity %d" % [
				attack_type,
				item_id,
				after_expected,
			],
		)
		_expect(
			target_hit_points_changed,
			"target scene %d reaches original hit points %d" % [
				target_scene,
				int(scenario.get("after_target_hit_points", 0)),
			],
		)
		_expect(
			attention_hold_observed,
			"target scene %d receives original type-11 attention hold"
			% target_scene,
		)
		# Freeze the command after the first committed attack. In-flight
		# projectiles keep running, but a slow CI host cannot submit a second
		# attack while the outcome checkpoint is waiting for the original HP.
		attacker.call("clear_combat_target")
		attacker.call("cancel_path")
		trace.call(
			"capture_main",
			"after_%s" % checkpoint_verb,
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(
				attacker,
				"weapon_entries",
				item_id,
			) == after_expected,
			"item %d quantity remains exact at capture" % item_id,
		)
	await _finish_inventory_probe(
		main,
		trace,
		scenario_id,
	)


func _run_world_item_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	scenario_id: String,
) -> void:
	var scenario: Dictionary = WORLD_ITEM_SCENARIOS[scenario_id]
	var target_scene := int(scenario.get("target_scene", -1))
	var item_id := int(scenario.get("item_id", 0))
	var before_expected := int(scenario.get("before_quantity", -1))
	var after_expected := int(scenario.get("after_quantity", -1))
	var effect_kind := str(scenario.get("effect", "carry"))
	var target := _enemy_for_scene(main, target_scene)
	_expect(target != null, "world-item target scene %d exists" % target_scene)
	if target != null:
		var before_quantity := _inventory_quantity(
			target,
			"item_entries",
			item_id,
		)
		var before_hit_points := int(target.get("current_hit_points"))
		_expect(
			before_quantity == before_expected,
			"target item %d starts at original quantity %d" % [
				item_id,
				before_expected,
			],
		)
		trace.call(
			"capture_main",
			"before_collection",
			main,
			_elapsed_ms(started),
		)
		var pickup_count_before := (main.get("mission_pickups") as Array).size()
		main.call(
			"_spawn_original_inventory_pickup",
			target.position,
			{
				"original_inventory_kind": "backpack",
				"item_id": item_id,
				"item_name": "Original item %d" % item_id,
				"quantity": 1,
				"quantity_mode": 0,
				"source_scene_index": -1,
			},
		)
		_expect(
			(main.get("mission_pickups") as Array).size()
				== pickup_count_before + 1,
			"authentic world-item actor is registered for normal enemy scan",
		)
		var collected := await _wait_for_world_item_collection(
			target,
			item_id,
			after_expected,
			effect_kind,
			12.0,
		)
		_expect(
			collected,
			"target scene %d collects and applies item %d" % [
				target_scene,
				item_id,
			],
		)
		trace.call(
			"capture_main",
			"after_collection",
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(target, "item_entries", item_id)
				== after_expected,
			"target item %d reaches exact post-collection quantity %d" % [
				item_id,
				after_expected,
			],
		)
		if effect_kind == "poison":
			var damaged := await _wait_for_target_damage(
				target,
				before_hit_points,
				12.0,
			)
			_expect(
				damaged,
				"poisoned-wine damage resolves after the original counter boundary",
			)
			trace.call(
				"capture_main",
				"after_effect",
				main,
				_elapsed_ms(started),
			)
	await _finish_inventory_probe(
		main,
		trace,
		scenario_id,
	)


func _run_backpack_drop_probe(
	main: Node,
	trace: RefCounted,
	started: int,
) -> void:
	const PLAYER_SCENE := 1589
	const ITEM_ID := 83
	const DROP_WORLD := Vector2(176.0, 104.0)
	var actor := _player_for_scene(main, PLAYER_SCENE)
	_expect(actor != null, "m010 Qiangzi scene 1589 exists for backpack drop")
	if actor != null:
		main.call("select_only", actor)
		var before_quantity := _inventory_quantity(
			actor,
			"item_entries",
			ITEM_ID,
		)
		_expect(
			before_quantity == 1,
			"Qiangzi starts with one original cigarette item 83",
		)
		trace.call(
			"capture_main",
			"before_drop",
			main,
			_elapsed_ms(started),
		)
		main.call(
			"_on_inventory_slot_requested",
			{
				"kind": "backpack_item",
				"item_id": ITEM_ID,
				"label": "香烟",
			},
		)
		_expect(
			int(main.get("selected_backpack_item_id")) == ITEM_ID,
			"A-panel item selection arms the original one-shot placement mode",
		)
		_expect(
			bool(main.call("drop_selected_item_at", DROP_WORLD)),
			"backpack placement accepts the verified walkable point",
		)
		var dropped := false
		for _frame_index: int in range(12 * 60):
			if (
				_inventory_quantity(actor, "item_entries", ITEM_ID) == 0
				and _has_original_drop_pickup(main, PLAYER_SCENE, ITEM_ID)
			):
				dropped = true
				break
			await physics_frame
		_expect(
			dropped,
			"state-9 approach removes one cigarette only after creating its world actor",
		)
		trace.call(
			"capture_main",
			"after_drop",
			main,
			_elapsed_ms(started),
		)
		_expect(
			_inventory_quantity(actor, "item_entries", ITEM_ID) == 0
				and _has_original_drop_pickup(main, PLAYER_SCENE, ITEM_ID),
			"drop checkpoint preserves the exact item delta and source identity",
		)
	await _finish_inventory_probe(
		main,
		trace,
		BACKPACK_DROP_SCENARIO_ID,
	)


func _has_original_drop_pickup(
	main: Node,
	source_scene_index: int,
	item_id: int,
) -> bool:
	for pickup_value: Variant in main.get("mission_pickups") as Array:
		var pickup := pickup_value as Node2D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var payload := pickup.get("item_payload") as Dictionary
		if (
			int(payload.get("item_id", 0)) == item_id
			and int(payload.get("source_scene_index", -1)) == source_scene_index
			and str(payload.get("original_inventory_kind", "")) == "backpack"
		):
			return true
	return false


func _wait_for_world_item_collection(
	target: Node2D,
	item_id: int,
	expected_quantity: int,
	effect_kind: String,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		var quantity_ready := (
			_inventory_quantity(target, "item_entries", item_id)
			== expected_quantity
		)
		var effect_ready := true
		match effect_kind:
			"hypnosis":
				effect_ready = (
					bool(target.get("legacy_hypnosis_active"))
					and bool(target.get("selected"))
				)
			"poison":
				var poison_limit := int(
					target.get("legacy_distraction_limit")
				)
				effect_ready = (
					bool(target.get("legacy_poison_active"))
					and bool(target.get("legacy_distraction_active"))
					and poison_limit >= 80
					and poison_limit <= 119
				)
			"distraction":
				var distraction_limit := int(
					target.get("legacy_distraction_limit")
				)
				effect_ready = (
					bool(target.get("legacy_distraction_active"))
					and distraction_limit >= 80
					and distraction_limit <= 119
				)
		if quantity_ready and effect_ready:
			return true
		await physics_frame
	return false


func _wait_for_target_damage(
	target: Node2D,
	before_hit_points: int,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if (
			not bool(target.get("is_alive"))
			or int(target.get("current_hit_points")) < before_hit_points
		):
			return true
		await physics_frame
	return false


func _wait_for_attention_hold(
	target: Node2D,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if (
			target != null
			and is_instance_valid(target)
			and target.has_method("is_special_controlled")
			and bool(target.call("is_special_controlled"))
		):
			return true
		await physics_frame
	return false


func _run_sight_direct_target_probe(
	main: Node,
	trace: RefCounted,
	started: int,
) -> void:
	var target := _enemy_for_scene(main, M010_CONTEXT_TARGET_SCENE_INDEX)
	_expect(target != null, "m010 scene 1126 sight target exists")
	if target != null:
		_expect(
			bool(target.get("is_alive")) and int(target.get("faction_id")) == 1,
			"S direct target starts as a living faction-1 enemy",
		)
		trace.call("capture_main", "before_sight", main, _elapsed_ms(started))
		await _tap_key(KEY_S)
		_expect(
			bool(main.get("sight_target_pending")),
			"S release arms the original one-shot sight command",
		)
		trace.call("capture_main", "sight_mode_armed", main, _elapsed_ms(started))
		await _click_world(main, target.position)
		_expect(
			main.get("sight_observation_target") == target
				and not bool(main.get("sight_target_pending"))
				and not bool(main.get("sight_observation_mode")),
			"living faction-1 click selects the enemy and consumes S once",
		)
		_expect(
			main.get("sight_beacon") == null,
			"direct S target does not create the actor-90 observation marker",
		)
		trace.call(
			"capture_main",
			"sight_target_selected",
			main,
			_elapsed_ms(started),
		)
	await _finish_contextual_probe(main, trace, SIGHT_DIRECT_TARGET_SCENARIO_ID)


func _run_burial_command_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	require_completion: bool = false,
) -> void:
	var attacker := _player_for_scene(main, M010_DANIU_SCENE_INDEX)
	var worker := _player_for_scene(main, M010_LAO_ZHAO_SCENE_INDEX)
	var target := _enemy_for_scene(main, M010_CONTEXT_TARGET_SCENE_INDEX)
	_expect(attacker != null, "m010 Daniu scene 1591 exists")
	_expect(worker != null, "m010 Lao Zhao scene 1590 exists")
	_expect(target != null, "m010 burial target scene 1126 exists")
	if attacker != null and worker != null and target != null:
		trace.call("capture_main", "before_attack", main, _elapsed_ms(started))
		var target_killed := false
		if require_completion:
			var applied := int(target.call("take_damage", 32, null))
			target_killed = not bool(target.get("is_alive"))
			target.position = Vector2(144.0, 64.0)
			_expect(
				applied == 8
					and target_killed
					and target.position == Vector2(144.0, 64.0),
				"the isolated original damage threshold prepares and relocates scene 1126",
			)
		else:
			main.call("select_only", attacker)
			_expect(
				bool(attacker.call("equip_attack_type", 4)),
				"Daniu equips the original durable dagger",
			)
			# The dagger outcome already has its own stable-MOD differential. Keep
			# that verified setup deterministic here so this scenario measures the
			# contextual B release/corpse click rather than duplicating attack input.
			main.call("issue_attack_order", target, false)
			target_killed = await _wait_for_target_hit_points(target, 0, 12.0)
			_expect(target_killed, "the original dagger kills scene 1126")
			attacker.call("clear_combat_target")
			attacker.call("cancel_path")
		trace.call("capture_main", "after_attack", main, _elapsed_ms(started))

		main.call("select_only", worker)
		await _tap_key(KEY_B)
		_expect(
			bool(main.get("burial_mode")),
			"B release arms the original one-shot burial command",
		)
		trace.call("capture_main", "burial_mode_armed", main, _elapsed_ms(started))
		await _click_world(main, target.position)
		_expect(
			main.get("burial_worker") == worker
				and main.get("burial_target") == target
				and not bool(main.get("burial_mode")),
			"dead faction-1 click assigns command kind 4 and consumes B once",
		)
		trace.call("capture_main", "burial_commanded", main, _elapsed_ms(started))
		_expect(
			(main.get("legacy_burial_caches") as Array).is_empty(),
			"B command does not create type 78 before the strict >100 timer",
		)
		if require_completion:
			var completed := await _wait_for_burial_completion(
				main,
				target,
				40.0,
			)
			_expect(
				completed,
				"the accepted B command reaches the strict >100 completion",
			)
			_expect(
				(main.get("legacy_burial_caches") as Array).size() == 1
					and not target.visible
					and (main.get("buried_enemy_scene_indices") as Dictionary).has(
						M010_CONTEXT_TARGET_SCENE_INDEX
					),
				"B completion retires the corpse and creates one actor-78 cache",
			)
			trace.call(
				"capture_main",
				"burial_completed",
				main,
				_elapsed_ms(started),
			)
	await _finish_contextual_probe(
		main,
		trace,
		BURIAL_COMPLETION_SCENARIO_ID
		if require_completion
		else BURIAL_COMMAND_SCENARIO_ID,
	)


func _wait_for_burial_completion(
	main: Node,
	target: Node2D,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if (
			(main.get("legacy_burial_caches") as Array).size() == 1
			and is_instance_valid(target)
			and not target.visible
			and (main.get("buried_enemy_scene_indices") as Dictionary).has(
				M010_CONTEXT_TARGET_SCENE_INDEX
			)
		):
			return true
		await physics_frame
	return false


func _finish_contextual_probe(
	main: Node,
	trace: RefCounted,
	scenario_id: String,
) -> void:
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake contextual parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	get_root().remove_child(main)
	main.free()
	await process_frame
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _wait_for_target_hit_points(
	target: Node,
	expected_hit_points: int,
	timeout_seconds: float,
) -> bool:
	var elapsed := 0.0
	while elapsed <= timeout_seconds:
		if (
			target != null
			and is_instance_valid(target)
			and int(target.get("current_hit_points")) == expected_hit_points
		):
			return true
		await physics_frame
		elapsed += 1.0 / 60.0
	return false


func _finish_inventory_probe(
	main: Node,
	trace: RefCounted,
	scenario_id: String,
) -> void:
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(scenario_id)
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake inventory parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_enemy_patrol_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	observation_seconds: float,
	level_id: String,
	settle_seconds: float,
) -> void:
	# Let the staggered path scheduler issue every first patrol request before
	# measuring. The reference MOD trace likewise starts only after gameplay is
	# fully resumed; commanded/observed pairs compare interval movement rather
	# than unrelated absolute startup phase.
	# The isolated MOD probe resumes the original menu, waits 4.2 seconds for
	# the gameplay capture, then observes five seconds of spawn safety. The
	# frame sweep above identifies the matching post-ready simulation phase.
	await _wait_physics_seconds(settle_seconds)
	var enemy_count := (main.get("enemies") as Array).size()
	_expect(enemy_count > 0, "%s imported enemy roster is available" % level_id)
	var trace_scope := "audited_%s_enemy_identities" % level_id
	trace.call(
		"capture_main",
		"patrol_interval_1_commanded",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	await _wait_physics_seconds(observation_seconds)
	trace.call(
		"capture_main",
		"patrol_interval_1_observed",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	trace.call(
		"capture_main",
		"patrol_interval_2_commanded",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	await _wait_physics_seconds(observation_seconds)
	trace.call(
		"capture_main",
		"patrol_interval_2_observed",
		main,
		_elapsed_ms(started),
		{"scope": trace_scope},
	)
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-%s.json" % _safe_file_component(_enemy_patrol_scenario_id(level_id))
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake patrol parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _run_natural_contact_probe(
	main: Node,
	trace: RefCounted,
	started: int,
	outbound_target: Vector2,
	return_target: Vector2,
	observation_seconds: float,
) -> void:
	# Match the stable MOD probe's gameplay-resume and spawn-safety phase.
	await _wait_physics_seconds(NATURAL_CONTACT_CAPTURE_SETTLE_SECONDS)
	var primary = _primary_unit(main)
	trace.call(
		"capture_main",
		"contact_ready",
		main,
		_elapsed_ms(started),
		{
			"scope": "audited_m000_resolved_actor_identities",
			"ambient_entity_count": (main.get("ambient_entities") as Array).size(),
			"ambient_unit_count": (main.get("ambient_units") as Array).size(),
			"outbound_navigation": _navigation_target_tags(
				main, primary, outbound_target
			) if primary != null else {},
			"return_navigation": _navigation_target_tags(
				main, primary, return_target
			) if primary != null else {},
		},
	)
	_expect(primary != null, "m000 primary DBL 924 actor exists")
	if primary != null:
		main.select_only(primary)
		trace.call(
			"capture_main",
			"player_selected",
			main,
			_elapsed_ms(started),
		)
		main.issue_formation_move(outbound_target)
		_expect(
			primary.target_position.distance_to(outbound_target) <= 1.0,
			"natural-contact outbound target is accepted",
		)
		trace.call(
			"capture_main",
			"move_outbound_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(observation_seconds)
		trace.call(
			"capture_main",
			"move_outbound_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		await _wait_physics_seconds(
			NATURAL_CONTACT_COMMAND_HANDOFF_SECONDS
		)
		main.issue_formation_move(return_target)
		_expect(
			primary.target_position.distance_to(return_target) <= 1.0,
			"natural-contact replacement target is accepted",
		)
		trace.call(
			"capture_main",
			"move_return_commanded",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var first_damage_observed := await _wait_for_damage_event_count(
			primary,
			1,
			maxf(
				observation_seconds,
				NATURAL_CONTACT_FIRST_DAMAGE_DEADLINE_SECONDS,
			),
		)
		_expect(
			first_damage_observed,
			"scene 1598 delivers the first recovered rifle hit before the contact deadline",
		)
		trace.call(
			"capture_main",
			"move_return_observed",
			main,
			_elapsed_ms(started),
			_movement_tags(primary, main),
		)
		var second_damage_observed := await _wait_for_damage_event_count(
			primary,
			2,
			NATURAL_CONTACT_SECOND_DAMAGE_DEADLINE_SECONDS,
		)
		_expect(
			second_damage_observed,
			"scene 1598 delivers the second recovered rifle hit before the settled deadline",
		)
		trace.call(
			"capture_main",
			"contact_settled",
			main,
			_elapsed_ms(started),
			{"scope": "audited_m000_resolved_actor_identities"},
		)
		var contacts := 0
		for enemy: Node2D in main.enemies:
			if (
				enemy.get("current_target") == primary
				and int(enemy.get("behavior_state")) in [1, 2]
			):
				contacts += 1
		_expect(
			contacts > 0,
			"natural movement produces at least one live enemy contact",
		)
	var trace_path := ""
	if not output_directory.is_empty():
		trace_path = output_directory.path_join(
			"remake-m000-natural-contact-v1.json"
		)
		_expect(
			trace.call("write_to_file", trace_path) == OK,
			"Remake natural-contact parity trace writes",
		)
	var trace_document: Dictionary = trace.get("document") as Dictionary
	print(
		"PARITY_RUNTIME_PROBE_RESULT %s"
		% JSON.stringify(
			{
				"trace": trace_path,
				"checkpoints": (trace_document.get("checkpoints", []) as Array).size(),
				"failures": failures,
			}
		)
	)
	main.queue_free()
	if failures.is_empty():
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _primary_unit(main: Node) -> Node2D:
	var entities: Dictionary = main.world_entities_by_scene
	for unit: Node2D in main.units:
		var entity := entities.get(int(unit.get("scene_index")), {}) as Dictionary
		if int(entity.get("database_entry_id", 0)) == PRIMARY_DATABASE_ENTRY_ID:
			return unit
	return null


func _player_for_scene(main: Node, scene_index: int) -> Node2D:
	for unit: Node2D in main.get("units") as Array:
		if int(unit.get("scene_index")) == scene_index:
			return unit
	return null


func _enemy_for_scene(main: Node, scene_index: int) -> Node2D:
	for enemy: Node2D in main.get("enemies") as Array:
		if int(enemy.get("scene_index")) == scene_index:
			return enemy
	return null


func _combatant_for_scene(main: Node, scene_index: int) -> Node2D:
	# A stable-MOD actor can change its live faction/type without changing its
	# serialized scene identity.  Probe the runtime collections by identity so
	# an original disguise/control transition cannot make the parity fixture
	# misclassify an otherwise valid target.
	for field: String in ["units", "escorts", "ambient_units", "enemies"]:
		for actor_value: Variant in main.get(field) as Array:
			if (
				actor_value is Node2D
				and int((actor_value as Node2D).get("scene_index")) == scene_index
			):
				return actor_value as Node2D
	return null


func _field_pickup_for_scene(main: Node, scene_index: int) -> Node2D:
	for pickup: Node2D in main.get("field_pickups") as Array:
		if int(pickup.get("scene_index")) == scene_index:
			return pickup
	return null


func _inventory_quantity(
	actor: Node2D,
	container_key: String,
	item_id: int,
) -> int:
	if actor == null or not actor.has_method("parity_inventory_snapshot"):
		return 0
	var inventory := actor.call("parity_inventory_snapshot") as Dictionary
	for entry_value: Variant in inventory.get(container_key, []) as Array:
		var entry := entry_value as Dictionary
		if int(entry.get("item_id", 0)) == item_id:
			return int(entry.get("quantity", 0))
	return 0


func _wait_for_inventory_quantity(
	actor: Node2D,
	container_key: String,
	item_id: int,
	expected_quantity: int,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if (
			_inventory_quantity(actor, container_key, item_id)
			== expected_quantity
		):
			return true
		await physics_frame
	return (
		_inventory_quantity(actor, container_key, item_id)
		== expected_quantity
	)


func _scenario_description(scenario_id: String, level_id: String) -> String:
	if scenario_id == MINE_PICKUP_SCENARIO_ID:
		return (
			"Select controllable scene 2280 and collect the real "
			+ "scene-2096 mine through the original automatic approach path; "
			+ "capture both inventory containers before and after."
		)
	if scenario_id == _human_input_natural_failure_scenario_id(level_id):
		var route := (
			HUMAN_INPUT_NATURAL_FAILURE_ROUTES.get(level_id, {}) as Dictionary
		)
		if str(route.get("action_kind", "")) == "weapon_noise_lure":
			return (
				"Through target-viewport input, select the required player "
				+ "and pistol, submit a real attack click as a noise lure, "
				+ "then observe enemy combat and required_character_lost."
			)
		return (
			"Through target-viewport input, select the required player, "
			+ "click the audited danger route, then observe enemy combat "
			+ "and required_character_lost."
		)
	if scenario_id == _human_input_cheat_victory_scenario_id(level_id):
		return (
			"Type the original built-in FLIPMISSION cheat through target-viewport "
			+ "key events and observe the product mission state choose victory. "
			+ "This proves the input-to-victory transition, not a non-cheat "
			+ "gameplay completion."
		)
	if scenario_id == _native_required_failure_scenario_id(level_id):
		return (
			"Apply the original unconditional damage threshold to required "
			+ "player scene %d and verify that the real combatant-death "
			+ "event closes %s through required_character_lost."
		) % [
			int(NATIVE_REQUIRED_FAILURE_SCENES.get(level_id, -1)),
			level_id,
		]
	if WEAPON_ATTACK_SCENARIOS.has(scenario_id):
		var scenario: Dictionary = WEAPON_ATTACK_SCENARIOS[scenario_id]
		return str(scenario.get("description", "Weapon inventory parity probe."))
	if WORLD_ITEM_SCENARIOS.has(scenario_id):
		var world_item_scenario: Dictionary = WORLD_ITEM_SCENARIOS[scenario_id]
		return str(
			world_item_scenario.get(
				"description",
				"World-item parity probe.",
			)
		)
	if scenario_id == BACKPACK_DROP_SCENARIO_ID:
		return (
			"Select Qiangzi scene 1589, choose cigarette item 83 in the A backpack, "
			+ "and submit the original state-9 placement at (176,104); capture "
			+ "the item quantity and completed world actor."
		)
	if scenario_id == SIGHT_DIRECT_TARGET_SCENARIO_ID:
		return (
			"Release S and click living faction-1 scene 1126; verify one-shot "
			+ "direct enemy selection without creating actor 90."
		)
	if scenario_id in [
		BURIAL_COMMAND_SCENARIO_ID,
		BURIAL_COMPLETION_SCENARIO_ID,
	]:
		if scenario_id == BURIAL_COMPLETION_SCENARIO_ID:
			return (
				"Prepare scene 1126 through the original damage threshold and "
				+ "relocate only that dead test fixture beside Lao Zhao; release "
				+ "B, click it, then wait for the strict counter to retire it and "
				+ "create exactly one actor-78 burial cache."
			)
		return (
			"Kill scene 1126 with Daniu's original dagger, release B "
			+ "and click the corpse; verify one-shot command kind 4 without "
			+ "premature actor-78 completion."
		)
	if scenario_id == _enemy_patrol_scenario_id(level_id):
		return (
			"Observe the audited %s enemy patrol roster in two one-second intervals."
			% level_id
		)
	if scenario_id == "m000-natural-contact-v1":
		return (
			"Move 强子 into natural enemy contact and observe audited "
			+ "AI target-state transitions."
		)
	return (
		"Select the audited controllable scene, issue two original-coordinate move orders, "
		+ "and observe facing/path replacement."
	)


func _parse_output_directory(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with(OUTPUT_ARGUMENT_PREFIX):
			return argument.trim_prefix(OUTPUT_ARGUMENT_PREFIX).simplify_path()
	return ""


func _parse_level_id(arguments: PackedStringArray) -> String:
	var level_id := _parse_string_argument(
		arguments,
		LEVEL_ARGUMENT_PREFIX,
		"m000",
	).to_lower()
	if FORMAL_LEVEL_IDS.has(level_id):
		return level_id
	failures.append("level argument must identify one of m000 through m011")
	return "m000"


func _enemy_patrol_scenario_id(level_id: String) -> String:
	return "%s-enemy-patrol-v1" % level_id


func _native_required_failure_scenario_id(level_id: String) -> String:
	return level_id + NATIVE_REQUIRED_FAILURE_SUFFIX


func _human_input_natural_failure_scenario_id(level_id: String) -> String:
	return level_id + HUMAN_INPUT_NATURAL_FAILURE_SUFFIX


func _human_input_cheat_victory_scenario_id(level_id: String) -> String:
	return level_id + HUMAN_INPUT_CHEAT_VICTORY_SUFFIX


func _parse_move_speed(arguments: PackedStringArray) -> float:
	for argument: String in arguments:
		if argument.begins_with(MOVE_SPEED_ARGUMENT_PREFIX):
			return maxf(
				argument.trim_prefix(MOVE_SPEED_ARGUMENT_PREFIX).to_float(),
				0.0,
			)
	return 0.0


func _parse_string_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: String,
) -> String:
	for argument: String in arguments:
		if argument.begins_with(prefix):
			var parsed := argument.trim_prefix(prefix).strip_edges()
			if not parsed.is_empty():
				return parsed
	return default_value


func _parse_integer_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: int,
) -> int:
	var value := _parse_string_argument(arguments, prefix, "")
	if not value.is_valid_int():
		return default_value
	return value.to_int()


func _parse_vector_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: Vector2,
) -> Vector2:
	var value := _parse_string_argument(arguments, prefix, "")
	var components := value.split(",", false)
	if components.size() != 2:
		return default_value
	if not components[0].is_valid_float() or not components[1].is_valid_float():
		return default_value
	return Vector2(components[0].to_float(), components[1].to_float())


func _parse_positive_float_argument(
	arguments: PackedStringArray,
	prefix: String,
	default_value: float,
) -> float:
	var value := _parse_string_argument(arguments, prefix, "")
	if not value.is_valid_float():
		return default_value
	return maxf(value.to_float(), 0.05)


func _safe_file_component(value: String) -> String:
	var safe := ""
	for index: int in range(value.length()):
		var character := value.substr(index, 1)
		if (
			character >= "a" and character <= "z"
			or character >= "A" and character <= "Z"
			or character >= "0" and character <= "9"
			or character == "-"
			or character == "_"
		):
			safe += character
		else:
			safe += "-"
	return safe


func _elapsed_ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _wait_for_damage_event_count(
	unit: Node2D,
	minimum_event_count: int,
	deadline_seconds: float,
) -> bool:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		ceili(maxf(deadline_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		if int(unit.get("damage_event_count")) >= minimum_event_count:
			return true
		await physics_frame
	return int(unit.get("damage_event_count")) >= minimum_event_count


func _wait_physics_seconds(duration_seconds: float) -> void:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		roundi(maxf(duration_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	for _frame_index: int in range(frame_count):
		await physics_frame


func _observe_movement_positions(
	unit: Node2D,
	duration_seconds: float,
	sample_interval_frames: int = 5,
) -> Array:
	var ticks_per_second := maxi(
		int(
			ProjectSettings.get_setting(
				"physics/common/physics_ticks_per_second",
				60,
			)
		),
		1,
	)
	var frame_count := maxi(
		roundi(maxf(duration_seconds, 0.0) * float(ticks_per_second)),
		1,
	)
	var interval := maxi(sample_interval_frames, 1)
	var positions: Array = [[unit.position.x, unit.position.y]]
	for frame_index: int in range(frame_count):
		await physics_frame
		if (
			(frame_index + 1) % interval == 0
			or frame_index == frame_count - 1
		):
			var sample := [unit.position.x, unit.position.y]
			var previous: Array = positions.back() as Array
			if (
				absf(float(previous[0]) - float(sample[0])) > 0.001
				or absf(float(previous[1]) - float(sample[1])) > 0.001
				or frame_index == frame_count - 1
			):
				positions.append(sample)
	return positions


func _tap_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame


func _type_original_cheat_text(main: Node, text: String) -> Array[Dictionary]:
	var sequence: Array[Dictionary] = []
	for index: int in range(text.length()):
		var character := text.substr(index, 1).to_upper()
		var unicode_value := character.unicode_at(0)
		var press := InputEventKey.new()
		press.keycode = unicode_value as Key
		press.physical_keycode = unicode_value as Key
		press.unicode = unicode_value
		press.pressed = true
		root.push_input(press)
		await process_frame
		var release := press.duplicate() as InputEventKey
		release.pressed = false
		root.push_input(release)
		await process_frame
		sequence.append({
			"kind": "cheat_letter",
			"letter": character,
			"keycode": unicode_value,
			"event_unicode": press.unicode,
			"buffer_after": str(main.get("original_cheat_buffer")),
			"events": 2,
		})
	return sequence


func _pan_view_to_world(main: Node, world_position: Vector2) -> void:
	var camera := main.get("level_camera") as Camera2D
	if camera == null:
		return
	var viewport_center := root.size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = viewport_center
	root.push_input(press, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = viewport_center
	motion.relative = (
		(camera.position - world_position)
		* camera.zoom.x
	)
	root.push_input(motion, true)
	await process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = viewport_center + motion.relative
	root.push_input(release, true)
	await process_frame


func _first_audited_ground_destination(
	main: Node,
	player: Node2D,
	candidates: Array,
) -> Vector2:
	for candidate_value: Variant in candidates:
		if not candidate_value is Vector2:
			continue
		var candidate := candidate_value as Vector2
		var hits_squad := false
		for unit: Node2D in main.get("units") as Array:
			if (
				bool(unit.get("is_alive"))
				and bool(unit.call("contains_parent_point", candidate))
			):
				hits_squad = true
				break
		if hits_squad:
			continue
		if (
			main.call("enemy_at_world_point", candidate) != null
			or main.call("explosive_prop_at_world_point", candidate) != null
			or main.call("field_pickup_at_world_point", candidate) != null
			or main.call("legacy_door_at_world_point", candidate) != null
		):
			continue
		var hits_burial_cache := false
		for cache: Node2D in main.get("legacy_burial_caches") as Array:
			if bool(cache.call("contains_parent_point", candidate)):
				hits_burial_cache = true
				break
		if hits_burial_cache:
			continue
		var path: PackedVector2Array = main.dynamic_occupancy.find_path_for_scene(
			int(player.get("scene_index")),
			player.position,
			candidate,
		)
		if not path.is_empty() and path[-1].distance_to(candidate) <= 24.0:
			return candidate
	return Vector2.ZERO


func _click_world(
	main: Node,
	world_position: Vector2,
	ctrl_pressed: bool = false,
) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.ctrl_pressed = ctrl_pressed
	click.position = main.get_global_transform_with_canvas() * world_position
	root.push_input(click, true)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame


func _movement_tags(
	unit: Node2D,
	main: Node,
	observed_positions: Array = [],
) -> Dictionary:
	var points: Array = []
	for point: Vector2 in unit.get("movement_path") as PackedVector2Array:
		points.append([point.x, point.y])
	var raw_points: Array = []
	var requested_target: Vector2 = unit.get("target_position")
	for point: Vector2 in main.navigation_grid.find_path(
		unit.position, requested_target, true
	):
		raw_points.append([point.x, point.y])
	var nearby_owners: Dictionary = {}
	for y: int in range(8, 15):
		nearby_owners["7,%d" % y] = int(
			main.dynamic_occupancy.runtime_movement_owner(Vector2i(7, y))
		)
	var movement_offsets: Array = []
	if main.dynamic_occupancy.actors.has(int(unit.get("scene_index"))):
		var actor_state := (
			main.dynamic_occupancy.actors[int(unit.get("scene_index"))] as Dictionary
		)
		for offset: Vector2i in actor_state.get("movement_offsets", []) as Array[Vector2i]:
			movement_offsets.append([offset.x, offset.y])
	var tags := {
		"move_speed": float(unit.get("move_speed")),
		"movement_path_index": int(unit.get("movement_path_index")),
		"movement_offsets": movement_offsets,
		"path": points,
		"raw_layer3_path": raw_points,
		"nearby_runtime_owners": nearby_owners,
	}
	if not observed_positions.is_empty():
		tags["observed_positions"] = observed_positions.duplicate(true)
	return tags


func _navigation_target_tags(main: Node, unit: Node2D, target: Vector2) -> Dictionary:
	if (
		main == null
		or main.get("navigation_grid") == null
		or main.get("dynamic_occupancy") == null
		or unit == null
	):
		return {}
	var navigation: RefCounted = main.get("navigation_grid")
	var occupancy: RefCounted = main.get("dynamic_occupancy")
	var target_cell: Vector2i = navigation.call("world_to_cell", target)
	var movement_owner := -1
	if occupancy.has_method("runtime_movement_owner"):
		movement_owner = int(occupancy.call("runtime_movement_owner", target_cell))
	var goal_owner := -1
	var goal_owners: Dictionary = occupancy.get("goal_owners") as Dictionary
	if goal_owners.has(target_cell):
		goal_owner = int(goal_owners[target_cell])
	var source_movement := -1
	var source_sight := -1
	if navigation.has_method("source_value"):
		source_movement = int(navigation.call("source_value", 3, target_cell))
		source_sight = int(navigation.call("source_value", 2, target_cell))
	var actor_cell := Vector2i(-1, -1)
	if occupancy.has_method("actor_cell"):
		actor_cell = occupancy.call("actor_cell", int(unit.get("scene_index")))
	return {
		"requested_world": [target.x, target.y],
		"target_cell": [target_cell.x, target_cell.y],
		"source_movement": source_movement,
		"source_sight": source_sight,
		"runtime_movement_owner": movement_owner,
		"goal_owner": goal_owner,
		"actor_cell": [actor_cell.x, actor_cell.y],
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
