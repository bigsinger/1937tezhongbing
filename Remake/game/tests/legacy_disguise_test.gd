extends SceneTree

const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const ENEMY_UNIT: Script = preload("res://scripts/enemy_unit.gd")
const RULES: Script = preload("res://scripts/legacy_disguise_rules.gd")


class ClearSight:
	extends RefCounted

	func has_line_of_sight(
		_observer_position: Vector2,
		_target_position: Vector2,
		_ignored_scene_indices: Array = [],
	) -> bool:
		return true


var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_transition_contract()
	_test_actor_tick_lifecycle()
	_test_exposure_and_recovery()
	_test_special_identification()
	if failures.is_empty():
		print("Legacy disguise tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_transition_contract() -> void:
	var dress: Dictionary = RULES.transition_for(
		RULES.NORMAL_RUNTIME_ACTOR_TYPE,
		RULES.UNIFORM_ITEM_ID,
	)
	_expect(
		int(dress.get("to_runtime_actor_type", 0)) == 91
		and int(dress.get("to_gfl_index", 0)) == 272
		and int(dress.get("to_faction_id", 0)) == 1
		and int(dress.get("grant_backpack_item_id", 0)) == 92
		and int(dress.get("grant_weapon_item_id", 0)) == 99,
		"uniform transition reproduces type 10 -> 91, GFL 272, faction 1 and items 92/99",
	)
	var undress: Dictionary = RULES.transition_for(
		RULES.DISGUISED_RUNTIME_ACTOR_TYPE,
		RULES.CIVILIAN_CLOTHING_ITEM_ID,
	)
	_expect(
		int(undress.get("to_runtime_actor_type", 0)) == 10
		and int(undress.get("to_gfl_index", 0)) == 270
		and int(undress.get("to_faction_id", 0)) == 3
		and int(undress.get("grant_backpack_item_id", 0)) == 54
		and int(undress.get("remove_weapon_item_id", 0)) == 99,
		"civilian-clothing transition is the exact inverse",
	)
	_expect(
		RULES.attack_can_break_disguise(91, 1)
		and RULES.attack_can_break_disguise(91, 4)
		and not RULES.attack_can_break_disguise(91, 11)
		and not RULES.attack_can_break_disguise(10, 1),
		"only disguised pistol and dagger commits can expose Gu Ming",
	)


func _test_actor_tick_lifecycle() -> void:
	var unit = _unit()
	unit.runtime_actor_type = RULES.NORMAL_RUNTIME_ACTOR_TYPE
	_expect(
		unit.add_backpack_item(RULES.UNIFORM_ITEM_ID, 1, 0) == 1
		and unit.begin_original_disguise_transition(RULES.UNIFORM_ITEM_ID),
		"uniform starts the recovered timed transition",
	)
	var completed_items: Array[int] = []
	unit.original_disguise_transition_ready.connect(
		func(_unit: Node2D, item_id: int) -> void:
			completed_items.append(item_id)
	)
	for unused_tick: int in range(RULES.CHANGE_TICK_LIMIT):
		unit.advance_original_disguise_transition(
			RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001
		)
	_expect(
		completed_items.is_empty()
		and unit.disguise_transition_tick_counter == RULES.CHANGE_TICK_LIMIT,
		"transition remains pending at counter 100",
	)
	unit.advance_original_disguise_transition(
		RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001
	)
	_expect(
		completed_items == [RULES.UNIFORM_ITEM_ID]
		and unit.disguise_transition_item_id == 0,
		"transition completes only on the strict 101st actor tick",
	)
	unit.free()


func _test_exposure_and_recovery() -> void:
	var unit = _unit()
	unit.runtime_actor_type = RULES.DISGUISED_RUNTIME_ACTOR_TYPE
	unit.faction_id = RULES.PLAYER_FACTION_ID
	for unused_tick: int in range(RULES.RECOVERY_TICK_LIMIT):
		unit.advance_original_disguise_recovery(
			RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
			false,
		)
	_expect(
		unit.faction_id == RULES.PLAYER_FACTION_ID
		and unit.disguise_recovery_tick_counter == RULES.RECOVERY_TICK_LIMIT,
		"exposed disguise remains hostile at recovery counter 100",
	)
	unit.advance_original_disguise_recovery(
		RULES.ORIGINAL_ACTOR_TICK_SECONDS + 0.000001,
		false,
	)
	_expect(
		unit.faction_id == RULES.DISGUISED_FACTION_ID
		and unit.disguise_recovery_tick_counter == 0,
		"101 unseen ticks restore the enemy-faction disguise",
	)
	unit.expose_original_disguise()
	unit.advance_original_disguise_recovery(
		RULES.ORIGINAL_ACTOR_TICK_SECONDS * 50.0,
		false,
	)
	unit.advance_original_disguise_recovery(
		RULES.ORIGINAL_ACTOR_TICK_SECONDS,
		true,
	)
	_expect(
		unit.disguise_recovery_tick_counter == 0
		and unit.faction_id == RULES.PLAYER_FACTION_ID,
		"a real observer resets disguise recovery",
	)
	unit.faction_id = RULES.DISGUISED_FACTION_ID
	_expect(
		unit.advance_original_disguise_recovery(0.0, true, true)
		and unit.faction_id == RULES.PLAYER_FACTION_ID,
		"an observed burial exposes the disguised actor immediately",
	)
	var snapshot: Dictionary = unit.original_disguise_state_snapshot()
	var restored = _unit()
	restored.runtime_actor_type = RULES.DISGUISED_RUNTIME_ACTOR_TYPE
	_expect(
		restored.restore_original_disguise_state(snapshot)
		and restored.original_disguise_state_snapshot() == snapshot,
		"transition and recovery counters round-trip through save state",
	)
	unit.free()
	restored.free()


func _test_special_identification() -> void:
	_expect(
		RULES.disguise_detection_mode(
			4,
			1,
			Vector2.ZERO,
			Vector2(1000.0, 1000.0),
		) == "ordinary_vision"
		and RULES.disguise_detection_mode(
			12,
			12,
			Vector2.ZERO,
			Vector2(1000.0, 1000.0),
		) == "ordinary_vision",
		"runtime types 4 and 12 identify type 91 through ordinary vision",
	)
	_expect(
		RULES.disguise_detection_mode(
			19,
			2,
			Vector2.ZERO,
			Vector2(127.0, 0.0),
		) == "close_without_los"
		and RULES.disguise_detection_mode(
			24,
			6,
			Vector2.ZERO,
			Vector2(0.0, 127.0),
		) == "close_without_los"
		and RULES.disguise_detection_mode(
			18,
			8,
			Vector2.ZERO,
			Vector2(0.0, 63.0),
		) == "close_without_los",
		"mission 2/6/8 special identifiers use the recovered 128-pixel rules",
	)
	_expect(
		RULES.disguise_detection_mode(
			19,
			2,
			Vector2.ZERO,
			Vector2(129.0, 0.0),
		).is_empty()
		and RULES.disguise_detection_mode(
			24,
			5,
			Vector2.ZERO,
			Vector2(20.0, 0.0),
		).is_empty(),
		"special identification rejects points outside its boundary and the wrong mission",
	)
	var enemy = ENEMY_UNIT.new()
	root.add_child(enemy)
	enemy.runtime_actor_type = 19
	enemy.original_mission_number = 2
	enemy.faction_id = 1
	enemy.is_alive = true
	enemy.position = Vector2.ZERO
	var target = _unit()
	root.add_child(target)
	target.runtime_actor_type = 91
	target.faction_id = 1
	target.position = Vector2(100.0, 0.0)
	_expect(
		enemy.call("_is_hostile_target", target),
		"enemy runtime consumes special disguise identification as hostility",
	)
	enemy.original_mission_number = 3
	_expect(
		not enemy.call("_is_hostile_target", target),
		"same-faction disguise remains non-hostile without an identifying rule",
	)
	enemy.free()
	target.free()


func _unit():
	var empty_groups: Array[Dictionary] = []
	var unit = SQUAD_UNIT.new()
	unit.configure(
		"Gu Ming",
		Color.WHITE,
		Vector2.ZERO,
		null,
		empty_groups,
		empty_groups,
		-1,
		ClearSight.new(),
	)
	unit.configure_combat(
		3,
		8,
		{},
		empty_groups,
		empty_groups,
		true,
	)
	return unit


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
