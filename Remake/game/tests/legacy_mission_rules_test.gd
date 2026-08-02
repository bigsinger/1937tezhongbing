extends SceneTree

const RULES: Script = preload("res://scripts/legacy_mission_rules.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_rule_table()
	_test_distance_boundaries()
	_test_explosion_geometry()
	_test_explosion_damage_threshold()
	_test_item_holders()
	if failures.is_empty():
		print("Legacy mission-rule tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_rule_table() -> void:
	for level_id: String in ["m001", "m002", "m003", "m004", "m006", "m008"]:
		var rule: Dictionary = RULES.rule_for(level_id)
		_expect(
			RULES.is_valid_rule(level_id, rule)
			and str(rule.get("source_status", RULES.SOURCE_STATUS))
				== RULES.SOURCE_STATUS,
			"%s exposes a valid source-backed evaluator subset" % level_id,
		)
	_expect(
		RULES.rule_for("m005").is_empty(),
		"levels without a recovered special predicate receive no invented rule",
	)
	_expect(
		str(RULES.target_rule_for("m003").get("completion", ""))
			== RULES.TIMED_EXPLOSIVE_WITHIN_RADIUS
		and int(
			RULES.target_rule_for("m003").get(
				"required_runtime_actor_type",
				0,
			)
		) == 85
		and str(RULES.target_rule_for("m004").get("completion", ""))
			== RULES.TARGET_HIT_POINTS_NONPOSITIVE,
		"bridge/mine targets use type-85 presence while granaries use destruction",
	)


func _test_distance_boundaries() -> void:
	_expect(
		RULES.distance_matches(Vector2.ZERO, Vector2(127.999, 0.0), 128.0, true)
		and not RULES.distance_matches(Vector2.ZERO, Vector2(128.0, 0.0), 128.0, true),
		"sub_45EF90 and m002/m008 exits reject the exact 128 boundary",
	)
	_expect(
		RULES.distance_matches(Vector2.ZERO, Vector2(128.0, 0.0), 128.0, false)
		and not RULES.distance_matches(Vector2.ZERO, Vector2(128.001, 0.0), 128.0, false),
		"m001/m003 exits preserve the inclusive 128 boundary",
	)
	var m001_exit: Dictionary = RULES.exit_rule_for("m001")
	_expect(
		(m001_exit.get("player_runtime_types", {}) as Dictionary).get("古明", [])
			== [91],
		"m001 train exit requires Gu Ming's live disguised runtime type 91",
	)


func _test_explosion_geometry() -> void:
	_expect(
		RULES.explosion_covers_target(
			Vector2.ZERO,
			Vector2(128.0, 0.0),
			128.0,
			64.0,
		)
		and RULES.explosion_covers_target(
			Vector2.ZERO,
			Vector2(0.0, 64.0),
			128.0,
			64.0,
		)
		and not RULES.explosion_covers_target(
			Vector2.ZERO,
			Vector2(96.0, 48.0),
			128.0,
			64.0,
		),
		"target destruction uses the recovered 128x64 blast ellipse",
	)


func _test_explosion_damage_threshold() -> void:
	_expect(
		not RULES.explosion_destroys_target(8, 7)
		and RULES.explosion_destroys_target(8, 8)
		and RULES.explosion_destroys_target(8, 16)
		and not RULES.explosion_destroys_target(0, 128),
		"type-98 targets require damage to cross their live hit-point threshold",
	)


func _test_item_holders() -> void:
	_expect(
		RULES.item_holder_is_eligible("m004", "m004_plan_document", "古明")
		and RULES.item_holder_is_eligible("m004", "m004_plan_document", "大牛")
		and not RULES.item_holder_is_eligible("m004", "m004_plan_document", "老赵"),
		"m004 item 101 is accepted only in Gu Ming or Daniu's original container",
	)
	_expect(
		RULES.item_holder_is_eligible("m006", "m006_name_list", "强子")
		and not RULES.item_holder_is_eligible("m006", "m006_name_list", "老赵"),
		"m006 item 101 is accepted only in Qiangzi's original container",
	)
	_expect(
		RULES.item_holder_is_eligible("m000", "ordinary_item", "任何人"),
		"unrestricted ordinary mission items keep generic acquisition behavior",
	)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
