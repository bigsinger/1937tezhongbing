extends SceneTree

const RULES: Script = preload("res://scripts/legacy_animation_audio_rules.gd")
const IMPORTED_ANIMATION: Script = preload(
	"res://scripts/imported_sprite_animation.gd"
)
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")

var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var schema_four_group := {
		"parameters": [54, 0, 0, 0, 0, 0, 0, 0, 37],
		"sound_slf_index": 37,
		"sound_gfl_index": 1363,
	}
	_expect(
		IMPORTED_ANIMATION.group_sound_metadata(schema_four_group, 4)
			== {"sound_slf_index": 37, "sound_gfl_index": 1363},
		"schema-four SPR sound metadata preserves exact SLF and GFL identities",
		failures,
	)
	_expect(
		IMPORTED_ANIMATION.group_sound_metadata(
			{
				"parameters": [54, 0, 0, 0, 0, 0, 0, 0, 37],
				"sound_slf_index": 36,
				"sound_gfl_index": 1363,
			},
			4,
		).is_empty(),
		"schema-four SPR manifests reject a mismatched explicit SLF index",
		failures,
	)
	_expect(
		IMPORTED_ANIMATION.group_sound_metadata(schema_four_group, 3)
			== {"sound_slf_index": 37, "sound_gfl_index": -1},
		"older local imports remain loadable but cannot guess a GFL sound",
		failures,
	)
	_expect(
		RULES.request_mode_for_action(3) == RULES.RequestMode.CONTINUOUS
		and RULES.request_mode_for_action(11) == RULES.RequestMode.CONTINUOUS,
		"walk and grenade actions use the recovered continuous request branch",
		failures,
	)
	_expect(
		RULES.request_mode_for_action(5) == RULES.RequestMode.ENTER_LAST_FRAME
		and RULES.request_mode_for_action(6) == RULES.RequestMode.ENTER_LAST_FRAME
		and RULES.request_mode_for_action(15) == RULES.RequestMode.ENTER_LAST_FRAME,
		"death and recovered attack actions request sound on entry to their last frame",
		failures,
	)
	var attack_group := _group(6, 1363, 3)
	_expect(
		not RULES.transition_requests_sound(attack_group, 0, 1)
		and RULES.transition_requests_sound(attack_group, 1, 2)
		and not RULES.transition_requests_sound(attack_group, 2, 2),
		"last-frame sound fires exactly once on the transition into the last frame",
		failures,
	)
	var action_zero := _group(0, 1324, 3)
	_expect(
		RULES.transition_requests_sound(action_zero, 0, 1)
		and not RULES.transition_requests_sound(action_zero, 1, 1),
		"action zero requests sound only when entering frame index one",
		failures,
	)
	_expect(
		RULES.requests_continuously(_group(3, 1386, 2))
		and not RULES.requests_continuously(attack_group)
		and not RULES.requests_continuously(_group(3, -1, 2)),
		"continuous requests require both a continuous action and resolved GFL sound",
		failures,
	)

	var movement_groups := _direction_groups(_group(3, 1386, 2))
	var silent_idle_groups := _direction_groups(_group(1, -1, 1))
	var unit = SQUAD_UNIT.new()
	unit.configure(
		"audio fixture",
		Color.WHITE,
		Vector2.ZERO,
		null,
		movement_groups,
		silent_idle_groups,
	)
	unit.animation_group_index = 0
	var requests: Array[Dictionary] = []
	unit.original_animation_audio_requested.connect(
		func(_actor: Node2D, gfl_index: int, continuous: bool) -> void:
			requests.append({"gfl_index": gfl_index, "continuous": continuous})
	)
	unit.advance_animation(0.0)
	_expect(
		requests == [{"gfl_index": 1386, "continuous": true}],
		"an active movement serial forwards its exact continuous GFL request",
		failures,
	)

	requests.clear()
	var attack_groups := _direction_groups(attack_group)
	unit.attack_groups = attack_groups
	unit.call("_start_one_shot", unit.CombatAction.ATTACK, attack_groups)
	unit.call("_advance_combat_action", 0.085)
	_expect(
		requests.is_empty(),
		"an attack does not play its frame-group sound before the hit frame",
		failures,
	)
	unit.call("_advance_combat_action", 0.085)
	_expect(
		requests == [{"gfl_index": 1363, "continuous": false}],
		"an attack forwards the exact one-shot sound on entry to its final frame",
		failures,
	)
	_expect(
		unit.has_authored_attack_animation_sound(),
		"combat fallback can detect an exact authored attack sound",
		failures,
	)

	requests.clear()
	var death_groups := _direction_groups(_group(5, 1368, 3))
	unit.death_groups = death_groups
	unit.call("_start_one_shot", unit.CombatAction.DEATH, death_groups)
	unit.call("_advance_combat_action", 0.17)
	_expect(
		requests == [{"gfl_index": 1368, "continuous": false}],
		"death forwards its exact authored sound at the recovered last-frame edge",
		failures,
	)
	_expect(
		unit.has_authored_death_animation_sound()
		and unit.authored_animation_sound_gfl_indices() == [1363, 1368, 1386],
		"prewarming enumerates unique exact movement, attack, and death sounds",
		failures,
	)
	unit.free()

	if failures.is_empty():
		print("Legacy animation-audio tests passed (%d checks). No original media was used." % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _group(action_index: int, gfl_index: int, frame_count: int) -> Dictionary:
	var frames: Array[Texture2D] = []
	for unused_frame: int in range(frame_count):
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		frames.append(ImageTexture.create_from_image(image))
	return {
		"serial_id": action_index * 9 + 1,
		"action_index": action_index,
		"sound_gfl_index": gfl_index,
		"frame_hold_ticks": 1,
		"anchor": Vector2.ONE,
		"frames": frames,
	}


func _direction_groups(group: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unused_direction: int in range(8):
		result.append(group.duplicate())
	return result


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
