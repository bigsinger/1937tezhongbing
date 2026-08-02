extends SceneTree

const RULES: Script = preload("res://scripts/legacy_escort_rules.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const ESCORT_UNIT: Script = preload("res://scripts/escort_unit.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_recovered_rule_table()
	_test_exact_proximity_boundaries()
	_test_rescuer_identity_and_runtime_type()
	_test_follow_and_commandable_transitions()
	if failures.is_empty():
		print("Legacy escort-rule tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_recovered_rule_table() -> void:
	var expected := {
		"m000:17": ["强子", 128.0, "distance_strict", true, true, false],
		"m000:3": ["强子", 128.0, "distance_strict", true, true, false],
		"m001:19": ["古明", 128.0, "isometric_inclusive", false, true, false],
		"m002:1": ["老赵", 128.0, "distance_strict", true, false, true],
		"m004:10": ["大牛", 128.0, "distance_strict", true, false, true],
		"m007:18": ["古明", 128.0, "isometric_inclusive", true, true, false],
		"m007:19": ["古明", 48.0, "isometric_inclusive", true, true, false],
		"m007:26": ["古明", 48.0, "isometric_inclusive", true, true, false],
	}
	for key_value: Variant in expected:
		var key := str(key_value)
		var parts := key.split(":")
		var rule: Dictionary = RULES.rule_for(parts[0], int(parts[1]))
		var values := expected[key] as Array
		_expect(
			not rule.is_empty()
			and (rule.get("target_names", []) as Array)[0] == values[0]
			and is_equal_approx(float(rule.get("radius", 0.0)), float(values[1]))
			and str(rule.get("proximity_kind", "")) == values[2]
			and bool(rule.get("changes_faction", false)) == values[3]
			and bool(rule.get("follows_target", false)) == values[4]
			and bool(rule.get("becomes_commandable", false)) == values[5],
			"%s exposes the source-backed rescue contract" % key,
		)
	_expect(
		RULES.rule_for("m003", 19).is_empty(),
		"unrecovered mission/type pairs do not receive invented rescue behavior",
	)


func _test_exact_proximity_boundaries() -> void:
	var strict: Dictionary = RULES.rule_for("m000", 17)
	_expect(
		RULES.is_within_rescue_range(strict, Vector2.ZERO, Vector2(127.999, 0.0))
		and not RULES.is_within_rescue_range(
			strict,
			Vector2.ZERO,
			Vector2(128.0, 0.0),
		),
		"sub_45EF90-style Euclidean radius is strict at 128",
	)
	var ellipse: Dictionary = RULES.rule_for("m001", 19)
	_expect(
		RULES.is_within_rescue_range(ellipse, Vector2.ZERO, Vector2(128.0, 0.0))
		and RULES.is_within_rescue_range(ellipse, Vector2.ZERO, Vector2(0.0, 64.0))
		and not RULES.is_within_rescue_range(
			ellipse,
			Vector2.ZERO,
			Vector2(0.0, 64.01),
		),
		"sub_45A8C0-style isometric ellipse keeps the recovered 2:1 boundary",
	)


func _test_rescuer_identity_and_runtime_type() -> void:
	var gu_ming = _actor("古明", 10, 11)
	var rule: Dictionary = RULES.rule_for("m001", 19)
	_expect(
		not RULES.rescuer_is_eligible(rule, gu_ming),
		"m001 driver rejects ordinary type-10 Gu Ming",
	)
	gu_ming.runtime_actor_type = 91
	_expect(
		RULES.rescuer_is_eligible(rule, gu_ming),
		"m001 driver accepts only disguised type-91 Gu Ming",
	)
	gu_ming.display_name = "强子"
	_expect(
		not RULES.rescuer_is_eligible(rule, gu_ming),
		"runtime type cannot substitute for the recovered character identity",
	)
	gu_ming.free()


func _test_follow_and_commandable_transitions() -> void:
	var rescuer = _actor("古明", 10, 42)
	var follower = _escort(RULES.rule_for("m007", 18), 2)
	_expect(
		follower.rescue(rescuer)
		and follower.faction_id == 3
		and follower.follow_target == rescuer
		and follower.original_pursuit_target_runtime_index == 42
		and follower.original_pursuit_call_site_rva
			== RULES.ORIGINAL_PURSUIT_CALL_SITE_RVA
		and not follower.is_player_commandable(),
		"m007 reporter switches faction and binds the exact original pursuit",
	)
	follower.free()

	rescuer.display_name = "老赵"
	rescuer.runtime_actor_type = 2
	var recruit = _escort(RULES.rule_for("m002", 1), 2)
	_expect(
		recruit.rescue(rescuer)
		and recruit.faction_id == 3
		and recruit.follow_target == null
		and recruit.is_player_commandable(),
		"m002 Qiangzi becomes commandable without an invented follow target",
	)
	recruit.free()

	rescuer.display_name = "古明"
	rescuer.runtime_actor_type = 91
	var driver = _escort(RULES.rule_for("m001", 19), 2)
	_expect(
		driver.rescue(rescuer)
		and driver.faction_id == 2
		and driver.follow_target == rescuer,
		"m001 driver preserves faction 2 while binding disguised Gu Ming",
	)
	driver.free()
	rescuer.free()


func _actor(name_value: String, actor_type: int, runtime_index: int):
	var actor = SQUAD_UNIT.new()
	root.add_child(actor)
	actor.display_name = name_value
	actor.runtime_actor_type = actor_type
	actor.original_runtime_index = runtime_index
	actor.is_alive = true
	actor.position = Vector2.ZERO
	return actor


func _escort(rule: Dictionary, faction: int):
	var escort = ESCORT_UNIT.new()
	root.add_child(escort)
	escort.is_alive = true
	escort.faction_id = faction
	escort.position = Vector2.ZERO
	escort.configure_original_rescue_rule(rule)
	return escort


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
