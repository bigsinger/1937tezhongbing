extends SceneTree

const RULES: Script = preload("res://scripts/legacy_actor_audio_rules.gd")
const CRT_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const SQUAD_UNIT_SCRIPT: Script = preload("res://scripts/squad_unit.gd")

const EXPECTED := [
	["selected", 1, 0, [103], [1344]],
	["selected", 2, 0x0005D64F, [98, 99], [1331, 1332]],
	["selected", 8, 0x0005D67C, [63, 70], [1282, 1289]],
	["selected", 9, 0x0005D6A9, [120, 122], [1383, 1385]],
	["selected", 10, 0x0005D6D6, [86, 87], [1312, 1313]],
	["selected", 91, 0x0005D6D6, [86, 87], [1312, 1313]],
	["acknowledge", 1, 0x0005D7CF, [105, 104], [1346, 1345]],
	["acknowledge", 2, 0x0005D7F8, [96, 97], [1329, 1330]],
	["acknowledge", 8, 0x0005D821, [65, 66], [1284, 1285]],
	["acknowledge", 9, 0, [121], [1384]],
	["acknowledge", 10, 0x0005D855, [83, 88], [1309, 1314]],
	["acknowledge", 91, 0x0005D855, [83, 88], [1309, 1314]],
	["hostile_initial_challenge", 4, 0x0005D921, [113, 114], [1361, 1362]],
	["hostile_initial_challenge", 5, 0, [107], [1354]],
	["hostile_initial_challenge", 6, 0, [107], [1354]],
	["hostile_initial_challenge", 7, 0, [94], [1327]],
	["hostile_initial_challenge", 11, 0, [107], [1354]],
	["hostile_initial_challenge", 12, 0x0005D960, [90, 91], [1316, 1317]],
	["hostile_initial_challenge", 13, 0, [107], [1354]],
	["hostile_initial_challenge", 14, 0, [107], [1354]],
	["hostile_initial_challenge", 15, 0x0005D989, [117, 118], [1380, 1381]],
	["hostile_initial_challenge", 21, 0, [101], [1337]],
	["hostile_initial_challenge", 23, 0x0005D9BD, [74, 75], [1297, 1298]],
	["hostile_corpse_alert", 4, 0, [108], [1355]],
	["hostile_corpse_alert", 5, 0, [108], [1355]],
	["hostile_corpse_alert", 6, 0, [108], [1355]],
	["hostile_corpse_alert", 11, 0, [108], [1355]],
	["hostile_corpse_alert", 12, 0, [108], [1355]],
	["hostile_corpse_alert", 13, 0, [108], [1355]],
	["hostile_corpse_alert", 14, 0, [108], [1355]],
	["hostile_followup_challenge", 4, 0x0005DA81, [111, 112], [1359, 1360]],
	["hostile_followup_challenge", 5, 0x0005DAAA, [106, 110], [1353, 1357]],
	["hostile_followup_challenge", 6, 0x0005DAAA, [106, 110], [1353, 1357]],
	["hostile_followup_challenge", 7, 0x0005DAD3, [92, 93], [1325, 1326]],
	["hostile_followup_challenge", 11, 0x0005DAAA, [106, 110], [1353, 1357]],
	["hostile_followup_challenge", 12, 0, [89], [1315]],
	["hostile_followup_challenge", 13, 0x0005DAAA, [106, 110], [1353, 1357]],
	["hostile_followup_challenge", 14, 0x0005DAAA, [106, 110], [1353, 1357]],
	["hostile_followup_challenge", 15, 0x0005DB07, [115, 116], [1378, 1379]],
	["hostile_followup_challenge", 21, 0, [102], [1338]],
	["hostile_followup_challenge", 23, 0x0005DB3B, [78, 79], [1301, 1302]],
]

const EXPECTED_SEMANTICS := {
	"selected": ["select_player_selected_sound", "selected_sound_two_way_variant"],
	"acknowledge": ["select_player_acknowledgement_sound", "acknowledgement_sound_two_way_variant"],
	"hostile_initial_challenge": ["select_hostile_initial_challenge_sound", "hostile_initial_challenge_two_way_variant"],
	"hostile_followup_challenge": ["select_hostile_followup_challenge_sound", "hostile_followup_challenge_two_way_variant"],
}

var failures: Array[String] = []
var checks := 0


class ActorFixture extends Node:
	var runtime_actor_type := 0


class TargetFixture extends Node2D:
	var faction_id := 3
	var scene_index := 9001
	var is_crawling := false
	var alive := true

	func is_combat_alive() -> bool:
		return alive


class EnemyAudioFixture extends EnemyUnit:
	var can_attack_fixture := false

	func _can_attack_current_target() -> bool:
		return can_attack_fixture

	func _disguise_detection_mode(_target: Node2D) -> String:
		return "close_without_los"

	func _issue_path_to(_destination: Vector2) -> bool:
		return true


class RecordingMediaDirector extends CanvasLayer:
	var requests: Array[Dictionary] = []

	func play_audio_index(
		gfl_index: int,
		event_key: String = "direct",
		caption_override: String = "",
		channel_override: String = "",
	) -> bool:
		requests.append({
			"gfl_index": gfl_index,
			"event_key": event_key,
			"caption": caption_override,
			"channel": channel_override,
		})
		return true


func _init() -> void:
	_test_exact_selector_tables()
	_test_shared_random_stream_wiring()
	_test_deferred_acknowledgement_update_slot()
	_test_enemy_challenge_trigger_wiring()
	if failures.is_empty():
		print(
			"Legacy actor-audio selector tests passed (%d checks). No original media was used."
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_exact_selector_tables() -> void:
	var expected_gfl_indices: Array[int] = []
	var expected_random_call_sites: Dictionary = {}
	for expected_value: Variant in EXPECTED:
		var expected := expected_value as Array
		var family := str(expected[0])
		var runtime_actor_type := int(expected[1])
		var call_site_rva := int(expected[2])
		var slf_indices := expected[3] as Array
		var gfl_indices := expected[4] as Array
		var profile: Dictionary = RULES.selector_profile(
			family,
			runtime_actor_type,
		)
		_expect(
			int(profile.get("call_site_rva", -1)) == call_site_rva
			and bool(profile.get("random_required", false)) == (call_site_rva != 0)
			and profile.get("slf_indices", []) == slf_indices
			and profile.get("gfl_indices", []) == gfl_indices,
			"%s type %d retains its exact SLF/GFL selector"
			% [family, runtime_actor_type],
		)
		var even_selection: Dictionary = RULES.select(
			family,
			runtime_actor_type,
			2 if call_site_rva != 0 else -1,
		)
		var odd_selection: Dictionary = RULES.select(
			family,
			runtime_actor_type,
			3 if call_site_rva != 0 else -1,
		)
		_expect(
			int(even_selection.get("slf_index", -1)) == int(slf_indices[0])
			and int(even_selection.get("gfl_index", -1)) == int(gfl_indices[0])
			and int(odd_selection.get("slf_index", -1))
			== int(slf_indices[slf_indices.size() - 1])
			and int(odd_selection.get("gfl_index", -1))
			== int(gfl_indices[gfl_indices.size() - 1]),
			"%s type %d preserves even/odd branch order"
			% [family, runtime_actor_type],
		)
		for raw_gfl_index: Variant in gfl_indices:
			var gfl_index := int(raw_gfl_index)
			if not expected_gfl_indices.has(gfl_index):
				expected_gfl_indices.append(gfl_index)
		if call_site_rva == 0:
			continue
		expected_random_call_sites[call_site_rva] = family
		var metadata: Dictionary = CRT_CATALOG.metadata_for_rva(call_site_rva)
		var semantics := EXPECTED_SEMANTICS[family] as Array
		_expect(
			str(metadata.get("domain", "")) == "audio_media"
			and str(metadata.get("semantic_name", "")) == str(semantics[0])
			and str(metadata.get("purpose", "")) == str(semantics[1]),
			"0x%08X is catalogued as its recovered actor-audio consumer"
			% call_site_rva,
		)
	expected_gfl_indices.sort()
	_expect(
		EXPECTED.size() == 41
		and expected_random_call_sites.size() == 17
		and RULES.all_gfl_indices() == expected_gfl_indices,
		"all 41 runtime-type rules, 17 random sites and exact GFL set are closed",
	)
	_expect(
		RULES.selector_profile("selected", 2, 0).is_empty()
		and RULES.selector_profile("selected", 2, 2).is_empty()
		and not RULES.selector_profile("selected", 2, 1).is_empty(),
		"sub_45D610 emits a selection voice only for activation flag one",
	)
	_expect(
		RULES.selector_profile("selected", 77).is_empty()
		and RULES.selector_profile("unknown", 1).is_empty()
		and RULES.select("acknowledge", 2).is_empty(),
		"unmapped actors, families and missing random values fail closed",
	)


func _test_shared_random_stream_wiring() -> void:
	var game = MAIN_SCRIPT.new()
	var director := RecordingMediaDirector.new()
	game.media_director = director
	var actor := ActorFixture.new()

	actor.runtime_actor_type = 1
	_expect(
		bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_SELECTED,
			actor,
		))
		and game.legacy_crt_random_draw_index == 0
		and director.requests.size() == 1
		and int(director.requests[0].get("gfl_index", -1)) == 1344,
		"fixed Qiangzi selection voice plays without consuming rand()",
	)

	actor.runtime_actor_type = 2
	var expected_state: int = CRT_CATALOG.next_state(
		game.legacy_crt_random_state
	)
	var expected_value: int = CRT_CATALOG.random_value(expected_state)
	_expect(
		bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_SELECTED,
			actor,
		))
		and game.legacy_crt_random_state == expected_state
		and game.legacy_crt_random_draw_index == 1
		and int(director.requests[-1].get("gfl_index", -1))
		== (1331 if expected_value % 2 == 0 else 1332)
		and str(director.requests[-1].get("channel", "")) == "voice",
		"randomized Lao Zhao selection voice consumes the shared CRT stream once",
	)

	expected_state = CRT_CATALOG.next_state(game.legacy_crt_random_state)
	expected_value = CRT_CATALOG.random_value(expected_state)
	_expect(
		bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_ACKNOWLEDGE,
			actor,
		))
		and game.legacy_crt_random_state == expected_state
		and game.legacy_crt_random_draw_index == 2
		and int(director.requests[-1].get("gfl_index", -1))
		== (1329 if expected_value % 2 == 0 else 1330),
		"movement acknowledgement continues the same process-global stream",
	)

	var request_count: int = director.requests.size()
	var draw_count: int = int(game.legacy_crt_random_draw_index)
	_expect(
		not bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_SELECTED,
			actor,
			0,
		))
		and director.requests.size() == request_count
		and game.legacy_crt_random_draw_index == draw_count,
		"inactive selection flags neither play nor advance the stream",
	)
	actor.runtime_actor_type = 77
	_expect(
		not bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_SELECTED,
			actor,
		))
		and director.requests.size() == request_count
		and game.legacy_crt_random_draw_index == draw_count,
		"an original unmapped runtime type remains silent without a draw",
	)
	actor.runtime_actor_type = 4
	_expect(
		bool(game.call(
			"_play_original_actor_audio",
			RULES.FAMILY_HOSTILE_ALERT,
			actor,
		))
		and director.requests.size() == request_count + 1
		and int(director.requests[-1].get("gfl_index", -1)) == 1355
		and game.legacy_crt_random_draw_index == draw_count,
		"fixed corpse-alert selector plays GFL 1355 without consuming rand()",
	)
	actor.free()
	director.free()
	game.free()


func _test_deferred_acknowledgement_update_slot() -> void:
	var game = MAIN_SCRIPT.new()
	var director := RecordingMediaDirector.new()
	game.media_director = director
	game.call("_apply_original_crt_random_startup_checkpoint", "m000")
	game.legacy_crt_random_trace_enabled = true
	var actor = SQUAD_UNIT_SCRIPT.new()
	actor.runtime_actor_type = 1
	actor.original_runtime_index = 18
	actor.original_crt_level_id = "m000"
	actor.original_command_audio_requested.connect(
		Callable(game, "_on_original_command_audio_requested")
	)
	var state_before := int(game.legacy_crt_random_state)
	var draw_index_before := int(game.legacy_crt_random_draw_index)
	actor.queue_original_acknowledgement()
	var queued_snapshot: Dictionary = actor.original_crt_random_timing_snapshot()
	_expect(
		game.legacy_crt_random_state == state_before
		and game.legacy_crt_random_draw_index == draw_index_before
		and actor.original_pending_acknowledgement_count == 1
		and director.requests.is_empty(),
		"ground input queues acknowledgement without advancing the shared stream",
	)

	var restored = SQUAD_UNIT_SCRIPT.new()
	restored.runtime_actor_type = 1
	restored.original_runtime_index = 18
	restored.original_crt_level_id = "m000"
	restored.original_command_audio_requested.connect(
		Callable(game, "_on_original_command_audio_requested")
	)
	_expect(
		restored.restore_original_crt_random_timing(queued_snapshot)
		and restored.original_pending_acknowledgement_count == 1
		and restored.original_acknowledgement_serial == 0,
		"pending actor-slot acknowledgement survives save and restore",
	)
	var expected_state: int = CRT_CATALOG.next_state(state_before)
	var expected_value: int = CRT_CATALOG.random_value(expected_state)
	restored.call("_physics_process", 0.0)
	_expect(
		game.legacy_crt_random_state == expected_state
		and game.legacy_crt_random_draw_index == draw_index_before + 1
		and restored.original_pending_acknowledgement_count == 0
		and restored.original_acknowledgement_serial == 1
		and game.legacy_crt_random_trace.size() == 1
		and int(game.legacy_crt_random_trace[0].get("call_site_rva", 0))
			== 0x0005D7CF
		and int(game.legacy_crt_random_trace[0].get("runtime_index", -1)) == 18
		and director.requests.size() == 1
		and int(director.requests[0].get("gfl_index", -1))
			== (1346 if expected_value % 2 == 0 else 1345),
		"actor update consumes one m000 acknowledgement at runtime index 18",
	)
	restored.call("_physics_process", 0.0)
	_expect(
		game.legacy_crt_random_draw_index == draw_index_before + 1
		and director.requests.size() == 1,
		"an actor update cannot replay an already consumed acknowledgement",
	)
	restored.free()
	actor.free()
	director.free()
	game.free()


func _test_enemy_challenge_trigger_wiring() -> void:
	var game = MAIN_SCRIPT.new()
	var director := RecordingMediaDirector.new()
	var enemy := EnemyAudioFixture.new()
	var target := TargetFixture.new()
	root.add_child(enemy)
	root.add_child(target)
	game.media_director = director
	enemy.runtime_actor_type = 4
	enemy.faction_id = 1
	enemy.scene_index = 7001
	enemy.position = Vector2.ZERO
	enemy.original_crt_random_source = game
	enemy.original_crt_level_id = "m000"
	target.position = Vector2(192.0, 0.0)
	game.call("_connect_combatant", enemy)

	var initial_state: int = CRT_CATALOG.next_state(
		game.legacy_crt_random_state
	)
	var initial_value: int = CRT_CATALOG.random_value(initial_state)
	enemy.call("_acquire_visible_live_target", target)
	_expect(
		enemy.current_target == target
		and enemy.behavior_state == EnemyUnit.BehaviorState.CHASE
		and enemy.legacy_contact_acquired_this_tick,
		"first visible live target enters original contact state before follow-up",
	)
	_expect(
		game.legacy_crt_random_state == initial_state
		and game.legacy_crt_random_draw_index == 1
		and director.requests.size() == 1
		and int(director.requests[-1].get("gfl_index", -1))
		== (1361 if initial_value % 2 == 0 else 1362),
		"first live-target acquisition emits sub_45D900 on the shared stream",
	)

	enemy.call("_acquire_visible_live_target", target)
	_expect(
		game.legacy_crt_random_draw_index == 1
		and director.requests.size() == 1,
		"continued tracking does not replay the first-contact voice",
	)

	# Simulate the next actor update. sub_45C710 cannot run its state-1
	# reaction-expiry branch in the same update that acquired the target.
	enemy.legacy_contact_acquired_this_tick = false
	enemy.attack_recheck_elapsed = enemy.attack_recheck_seconds
	enemy.chase_replan_elapsed = 0.0
	var deadline_state: int = CRT_CATALOG.next_state(initial_state)
	var deadline_value: int = CRT_CATALOG.random_value(deadline_state)
	var followup_state: int = CRT_CATALOG.next_state(deadline_state)
	var followup_value: int = CRT_CATALOG.random_value(followup_state)
	enemy.call("_update_behavior", 0.0)
	_expect(
		game.legacy_crt_random_state == followup_state
		and game.legacy_crt_random_draw_index == 3
		and director.requests.size() == 2
		and int(director.requests[-1].get("gfl_index", -1))
		== (1359 if followup_value % 2 == 0 else 1360),
		(
			"failed attack readiness draws 0x45CD01 before sub_45DA60 follow-up voice "
			+ "[draws=%d requests=%d state=%d behavior=%d acquired=%s elapsed=%.4f limit=%.4f]"
			% [
				game.legacy_crt_random_draw_index,
				director.requests.size(),
				game.legacy_crt_random_state,
				enemy.behavior_state,
				str(enemy.legacy_contact_acquired_this_tick),
				enemy.attack_recheck_elapsed,
				enemy.attack_recheck_seconds,
			]
		),
	)
	_expect(
		is_equal_approx(
			enemy.attack_recheck_seconds,
			float(20 + deadline_value % 20)
				* enemy.ORIGINAL_ATTACK_REACTION_TICK_SECONDS,
		),
		"0x45CD01 now drives the exact 20..39 tick follow-up deadline",
	)

	enemy.call("_update_behavior", 0.0)
	_expect(
		game.legacy_crt_random_draw_index == 3
		and director.requests.size() == 2,
		"follow-up challenge waits for the next recovered reaction deadline",
	)
	enemy.can_attack_fixture = true
	enemy.attack_recheck_elapsed = enemy.attack_recheck_seconds
	enemy.call("_update_behavior", 0.0)
	_expect(
		enemy.behavior_state == EnemyUnit.BehaviorState.ATTACK
		and game.legacy_crt_random_draw_index == 3
		and director.requests.size() == 2,
		"an attackable target enters attack state without a false chase voice",
	)

	target.free()
	enemy.free()
	director.free()
	game.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
