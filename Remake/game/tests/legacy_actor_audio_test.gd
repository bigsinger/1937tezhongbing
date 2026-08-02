extends SceneTree

const RULES: Script = preload("res://scripts/legacy_actor_audio_rules.gd")
const CRT_CATALOG: Script = preload(
	"res://scripts/generated/legacy_crt_random_catalog.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")

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
		EXPECTED.size() == 34
		and expected_random_call_sites.size() == 17
		and RULES.all_gfl_indices() == expected_gfl_indices,
		"all 34 runtime-type rules, 17 random sites and exact GFL set are closed",
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
	actor.free()
	director.free()
	game.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
