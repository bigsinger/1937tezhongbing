extends SceneTree

const SOUND_CATALOG: Script = preload(
	"res://scripts/generated/legacy_sound_route_catalog.gd"
)
const ACTOR_AUDIO_RULES: Script = preload(
	"res://scripts/legacy_actor_audio_rules.gd"
)
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")


class RecordingMediaDirector extends CanvasLayer:
	var immediate_requests: Array[Dictionary] = []
	var queued_requests: Array[Dictionary] = []

	func play_audio_index(
		gfl_index: int,
		event_key: String = "direct",
		caption_override: String = "",
		channel_override: String = "",
	) -> bool:
		immediate_requests.append({
			"gfl_index": gfl_index,
			"event_key": event_key,
			"caption": caption_override,
			"channel": channel_override,
		})
		return true

	func request_sfx_audio_index(
		gfl_index: int,
		requester_instance_id: int = 0,
	) -> bool:
		queued_requests.append({
			"gfl_index": gfl_index,
			"requester_instance_id": requester_instance_id,
		})
		return true


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_test_exact_reachability_partition()
	_test_environmental_asset_only_evidence()
	_test_exact_runtime_routes()
	if failures.is_empty():
		print(
			"Legacy sound-reachability tests passed (%d checks). No original media was used."
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_exact_reachability_partition() -> void:
	_expect(
		SOUND_CATALOG.SLF_ENTRY_COUNT == 126
		and SOUND_CATALOG.AUDITED_SPRITE_COUNT == 980
		and SOUND_CATALOG.AUDITED_GROUP_COUNT == 2775
		and SOUND_CATALOG.SOUNDED_GROUP_COUNT == 1137
		and SOUND_CATALOG.SPRITE_GROUP_ONE_BASED_INDICES.size() == 52
		and SOUND_CATALOG.ACTOR_VOICE_ZERO_BASED_INDICES.size() == 42
		and SOUND_CATALOG.REACHABLE_ZERO_BASED_INDICES.size() == 95
		and SOUND_CATALOG.ASSET_ONLY_ZERO_BASED_INDICES.size() == 31,
		"full SLF/SPR audit counts remain exact",
	)
	for slf_index: int in range(SOUND_CATALOG.SLF_ENTRY_COUNT):
		_expect(
			SOUND_CATALOG.is_reachable_zero_based(slf_index)
			!= SOUND_CATALOG.is_asset_only_zero_based(slf_index),
			"SLF index %d belongs to exactly one reachability partition"
			% slf_index,
		)

	var derived_reachable: Array[int] = []
	for one_based_index: int in (
		SOUND_CATALOG.SPRITE_GROUP_ONE_BASED_INDICES
	):
		_append_unique(derived_reachable, one_based_index - 1)
	for zero_based_index: int in (
		SOUND_CATALOG.ACTOR_VOICE_ZERO_BASED_INDICES
	):
		_append_unique(derived_reachable, zero_based_index)
	_append_unique(
		derived_reachable,
		SOUND_CATALOG.UI_BUTTON_ZERO_BASED_INDEX,
	)
	_append_unique(
		derived_reachable,
		SOUND_CATALOG.GLOBAL_ALARM_ZERO_BASED_INDEX,
	)
	derived_reachable.sort()
	_expect(
		derived_reachable == SOUND_CATALOG.REACHABLE_ZERO_BASED_INDICES,
		"the four executable request routes derive all and only 95 reachable sounds",
	)

	var actor_voice_indices: Array[int] = []
	for family_value: Variant in ACTOR_AUDIO_RULES.RULES.values():
		for rule_value: Variant in (family_value as Dictionary).values():
			for raw_index: Variant in (
				(rule_value as Dictionary).get("slf_indices", []) as Array
			):
				_append_unique(actor_voice_indices, int(raw_index))
	actor_voice_indices.sort()
	_expect(
		actor_voice_indices
		== SOUND_CATALOG.ACTOR_VOICE_ZERO_BASED_INDICES,
		"runtime actor selectors cover the exact 42-entry voice route",
	)


func _test_environmental_asset_only_evidence() -> void:
	var expected_asset_only := {
		61: 1391,
		100: 1333,
		123: 1390,
	}
	for raw_index: Variant in expected_asset_only.keys():
		var zero_based_index := int(raw_index)
		var entry: Dictionary = SOUND_CATALOG.environment_entry(
			zero_based_index
		)
		_expect(
			not entry.is_empty()
			and int(entry.get("gfl_index", -1))
				== int(expected_asset_only[raw_index])
			and str(entry.get("reachability", "")) == "asset_only"
			and SOUND_CATALOG.is_asset_only_zero_based(zero_based_index),
			"rain/thunder archive entry %d stays asset-only"
			% zero_based_index,
		)
	_expect(
		SOUND_CATALOG.UI_BUTTON_ZERO_BASED_INDEX == 124
		and SOUND_CATALOG.UI_BUTTON_GFL_INDEX == 1393
		and SOUND_CATALOG.GLOBAL_ALARM_ZERO_BASED_INDEX == 125
		and SOUND_CATALOG.GLOBAL_ALARM_GFL_INDEX == 1324
		and SOUND_CATALOG.GLOBAL_ALARM_UPDATE_COUNTER_LIMIT == 240
		and SOUND_CATALOG.GLOBAL_ALARM_ACTIVE_REQUEST_UPDATES == 241,
		"button release and corpse alarm retain exact archive identities and timing",
	)


func _test_exact_runtime_routes() -> void:
	var game = MAIN_SCRIPT.new()
	var director := RecordingMediaDirector.new()
	var button := Button.new()
	game.media_director = director
	_expect(
		bool(game.call("_connect_original_button_audio", button)),
		"a BaseButton accepts the exact original release-sound route",
	)
	button.pressed.emit()
	_expect(
		director.immediate_requests.size() == 1
		and int(director.immediate_requests[0].get("gfl_index", -1))
			== 1393
		and str(director.immediate_requests[0].get("event_key", ""))
			== "original_ui_button_release"
		and str(director.immediate_requests[0].get("channel", ""))
			== "sfx",
		"valid button activation immediately plays GFL 1393 once",
	)

	game.legacy_global_alarm_active = true
	for _update_index: int in range(240):
		game.call("_advance_original_global_alarm")
	_expect(
		game.legacy_global_alarm_active
		and game.legacy_global_alarm_counter == 240
		and director.queued_requests.size() == 240,
		"corpse alarm remains active through counter 240",
	)
	game.call("_advance_original_global_alarm")
	_expect(
		not game.legacy_global_alarm_active
		and game.legacy_global_alarm_counter == 0
		and director.queued_requests.size() == 241
		and _all_requests_match_gfl(director.queued_requests, 1324),
		"counter 241 clears the flag only after submitting its final queued alarm request",
	)
	game.call("_advance_original_global_alarm")
	_expect(
		director.queued_requests.size() == 241,
		"inactive alarm submits no further request",
	)

	button.free()
	director.free()
	game.free()


func _append_unique(values: Array[int], value: int) -> void:
	if not values.has(value):
		values.append(value)


func _all_requests_match_gfl(
	requests: Array[Dictionary],
	expected_gfl_index: int,
) -> bool:
	for request: Dictionary in requests:
		if int(request.get("gfl_index", -1)) != expected_gfl_index:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
