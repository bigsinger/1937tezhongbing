extends SceneTree

const LEGACY_INPUT_RULES: Script = preload("res://scripts/legacy_input_rules.gd")
const GAME_INPUT_BINDINGS: Script = preload("res://scripts/game_input_bindings.gd")
const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")

var checks := 0


func _init() -> void:
	var failures: Array[String] = []
	_validate_scan_codes_and_phases(failures)
	_validate_mouse_transitions(failures)
	_validate_edge_scroll(failures)
	_validate_cursor_modes(failures)
	_validate_pointer_safety_source_guards(failures)
	if failures.is_empty():
		print("Original input parity tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _validate_scan_codes_and_phases(failures: Array[String]) -> void:
	var expected_scan_codes := {
		"pause": 0x01,
		"weapon_1": 0x02,
		"weapon_2": 0x03,
		"weapon_3": 0x04,
		"weapon_4": 0x05,
		"weapon_5": 0x06,
		"weapon_6": 0x07,
		"weapon_7": 0x08,
		"weapon_8": 0x09,
		"weapon_9": 0x0A,
		"weapon_10": 0x0B,
		"weapon_inventory": 0x11,
		"toggle_run": 0x13,
		"force_target_ctrl": 0x1D,
		"item_inventory": 0x1E,
		"sight_mode": 0x1F,
		"toggle_crawl": 0x2E,
		"burial_mode": 0x30,
		"minimap": 0x32,
		"guide": 0x3B,
		"select_1": 0x3C,
		"select_2": 0x3D,
		"select_3": 0x3E,
		"select_4": 0x3F,
		"select_5": 0x40,
		"briefing": 0x41,
		"debug_load_m010": 0x42,
		"force_target_up": 0xC8,
	}
	for action: String in expected_scan_codes:
		_expect(
			LEGACY_INPUT_RULES.direct_input_scan_code_for_action(action)
				== int(expected_scan_codes[action]),
			"%s keeps its recovered DirectInput scan code" % action,
			failures,
		)

	var press_actions: Array[String] = [
		"select_1",
		"select_2",
		"select_3",
		"select_4",
		"select_5",
		"weapon_1",
		"weapon_2",
		"weapon_3",
		"weapon_4",
		"weapon_5",
		"weapon_6",
		"weapon_7",
		"weapon_8",
		"weapon_9",
		"weapon_10",
	]
	var release_actions: Array[String] = [
		"pause",
		"guide",
		"briefing",
		"toggle_run",
		"toggle_crawl",
		"weapon_inventory",
		"item_inventory",
		"sight_mode",
		"burial_mode",
		"minimap",
	]
	for action: String in press_actions:
		_expect(
			_trigger_result(action, true) and not _trigger_result(action, false),
			"%s submits on press only" % action,
			failures,
		)
	for action: String in release_actions:
		_expect(
			not _trigger_result(action, true) and _trigger_result(action, false),
			"%s submits on release only" % action,
			failures,
		)
	for action: String in ["force_target_ctrl", "force_target_up"]:
		_expect(
			not _trigger_result(action, true) and not _trigger_result(action, false),
			"%s remains a sampled held-state channel" % action,
			failures,
		)

	var definitions_by_action := {}
	for definition: Dictionary in GAME_INPUT_BINDINGS.definitions():
		definitions_by_action[str(definition["action"])] = definition
	_expect(
		str((definitions_by_action["weapon_1"] as Dictionary)["trigger_phase"])
			== LEGACY_INPUT_RULES.PHASE_PRESS
		and int((definitions_by_action["weapon_1"] as Dictionary)["legacy_scan_code"])
			== 0x02
		and str((definitions_by_action["minimap"] as Dictionary)["trigger_phase"])
			== LEGACY_INPUT_RULES.PHASE_RELEASE
		and int((definitions_by_action["minimap"] as Dictionary)["legacy_scan_code"])
			== 0x32,
		"settings metadata exposes recovered input phase and scan code",
		failures,
	)
	_expect(
		LEGACY_INPUT_RULES.WORLD_LEFT_COMMAND_PHASE == LEGACY_INPUT_RULES.PHASE_PRESS
		and LEGACY_INPUT_RULES.WORLD_RIGHT_SELECTION_PHASE
			== LEGACY_INPUT_RULES.PHASE_RELEASE
		and LEGACY_INPUT_RULES.should_submit_world_left(true)
		and not LEGACY_INPUT_RULES.should_submit_world_left(false)
		and not LEGACY_INPUT_RULES.should_finish_world_right(true)
		and LEGACY_INPUT_RULES.should_finish_world_right(false),
		"world left/right commands preserve their recovered transition phases",
		failures,
	)


func _trigger_result(action: String, pressed: bool) -> bool:
	var event := InputEventKey.new()
	event.pressed = pressed
	return GAME_INPUT_BINDINGS.should_trigger_for_event(action, event)


func _validate_mouse_transitions(failures: Array[String]) -> void:
	var idle: Dictionary = LEGACY_INPUT_RULES.mouse_button_transition(false, false)
	var press: Dictionary = LEGACY_INPUT_RULES.mouse_button_transition(false, true)
	var held: Dictionary = LEGACY_INPUT_RULES.mouse_button_transition(true, true)
	var release: Dictionary = LEGACY_INPUT_RULES.mouse_button_transition(true, false)
	_expect(
		not bool(idle["pressed"]) and not bool(idle["down"]) and not bool(idle["released"]),
		"mouse idle transition is empty",
		failures,
	)
	_expect(
		bool(press["pressed"]) and bool(press["down"]) and not bool(press["released"]),
		"mouse press transition exposes press and held state",
		failures,
	)
	_expect(
		not bool(held["pressed"]) and bool(held["down"]) and not bool(held["released"]),
		"mouse held transition does not repeat its press edge",
		failures,
	)
	_expect(
		not bool(release["pressed"]) and not bool(release["down"]) and bool(release["released"]),
		"mouse release transition exposes its release edge",
		failures,
	)


func _validate_edge_scroll(failures: Array[String]) -> void:
	var viewport_size := Vector2(1280.0, 720.0)
	_expect(
		LEGACY_INPUT_RULES.edge_direction_for_position(
			Vector2(0.0, 360.0), viewport_size
		) == Vector2.LEFT
		and LEGACY_INPUT_RULES.edge_direction_for_position(
			Vector2(1.0, 360.0), viewport_size
		) == Vector2.LEFT
		and LEGACY_INPUT_RULES.edge_direction_for_position(
			Vector2(2.0, 360.0), viewport_size
		).is_zero_approx()
		and LEGACY_INPUT_RULES.edge_direction_for_position(
			Vector2(1278.0, 360.0), viewport_size
		).is_zero_approx()
		and LEGACY_INPUT_RULES.edge_direction_for_position(
			Vector2(1279.0, 360.0), viewport_size
		) == Vector2.RIGHT,
		"original client edge uses coordinates 0/1 and the outermost right column",
		failures,
	)
	var modern_corner: Vector2 = MAIN_SCRIPT.edge_scroll_direction_for_position(
		Vector2(1.0, 1.0), viewport_size
	)
	_expect(
		modern_corner.x < 0.0
		and modern_corner.y < 0.0
		and is_equal_approx(modern_corner.length(), 1.0)
		and MAIN_SCRIPT.edge_scroll_direction_for_position(
			Vector2(1280.0, 360.0), viewport_size
		).is_zero_approx(),
		"Main uses normalized modern edge intent and rejects coordinates outside the client",
		failures,
	)
	var expected_codes := {
		Vector2.UP: LEGACY_INPUT_RULES.EdgeDirection.NORTH,
		Vector2(1.0, -1.0): LEGACY_INPUT_RULES.EdgeDirection.NORTHEAST,
		Vector2.RIGHT: LEGACY_INPUT_RULES.EdgeDirection.EAST,
		Vector2(1.0, 1.0): LEGACY_INPUT_RULES.EdgeDirection.SOUTHEAST,
		Vector2.DOWN: LEGACY_INPUT_RULES.EdgeDirection.SOUTH,
		Vector2(-1.0, 1.0): LEGACY_INPUT_RULES.EdgeDirection.SOUTHWEST,
		Vector2.LEFT: LEGACY_INPUT_RULES.EdgeDirection.WEST,
		Vector2(-1.0, -1.0): LEGACY_INPUT_RULES.EdgeDirection.NORTHWEST,
	}
	for direction: Vector2 in expected_codes:
		_expect(
			LEGACY_INPUT_RULES.edge_direction_code(direction)
				== int(expected_codes[direction]),
			"edge direction %s retains its original compass code" % direction,
			failures,
		)
	var strength := 0.0
	for _tick: int in range(8):
		strength = LEGACY_INPUT_RULES.advance_scroll_strength(strength, true)
	_expect(is_equal_approx(strength, 1.0), "edge velocity reaches its limit in eight updates", failures)
	for _tick: int in range(8):
		strength = LEGACY_INPUT_RULES.advance_scroll_strength(strength, false)
	_expect(is_zero_approx(strength), "edge velocity decays to zero in eight updates", failures)
	_expect(
		LEGACY_INPUT_RULES.advance_original_integer_scroll_velocity(0, 64, true) == 8
		and LEGACY_INPUT_RULES.advance_original_integer_scroll_velocity(64, 64, false) == 56,
		"integer velocity preserves the original limit/8 step",
		failures,
	)


func _validate_cursor_modes(failures: Array[String]) -> void:
	_expect(
		LEGACY_INPUT_RULES.context_cursor_serial(
			true, true, true, true, true, true, true
		) == LEGACY_INPUT_RULES.CursorSerial.BURIAL,
		"burial cursor has the original highest pointer-mode priority",
		failures,
	)
	_expect(
		LEGACY_INPUT_RULES.context_cursor_serial(
			false, true, true, true, true, true, true
		) == LEGACY_INPUT_RULES.CursorSerial.SIGHT,
		"sight cursor precedes ordinary target and interaction cursors",
		failures,
	)
	_expect(
		LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, true, true, true, true, true
		) == LEGACY_INPUT_RULES.CursorSerial.FORCE_TARGET
		and LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, true, false, true, false, true
		) == LEGACY_INPUT_RULES.CursorSerial.INTERACT
		and LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, true, false, false, true, true
		) == LEGACY_INPUT_RULES.CursorSerial.FORCE_TARGET,
		"force-target, door interaction, and enemy hover choose recovered cursor serials",
		failures,
	)
	_expect(
		LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, true, false, false, false, true
		) == LEGACY_INPUT_RULES.CursorSerial.MOVE
		and LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, true, false, false, false, false
		) == LEGACY_INPUT_RULES.CursorSerial.BLOCKED
		and LEGACY_INPUT_RULES.context_cursor_serial(
			false, false, false, false, false, false, true
		) == LEGACY_INPUT_RULES.CursorSerial.NORMAL,
		"ground and no-selection states preserve move, blocked, and normal cursors",
		failures,
	)


func _validate_pointer_safety_source_guards(failures: Array[String]) -> void:
	var forbidden_tokens: Array[String] = [
		"warp_mouse(",
		"MOUSE_MODE_CAPTURED",
		"mouse_set_position",
		"SetCursorPos",
		"ClipCursor",
		"DisplayServer.mouse_get_position",
	]
	for path: String in [
		"res://scripts/main.gd",
		"res://scripts/legacy_input_rules.gd",
		"res://scripts/legacy_cursor_presenter.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		for token: String in forbidden_tokens:
			_expect(
				not source.contains(token),
				"%s never uses forbidden pointer control %s" % [path.get_file(), token],
				failures,
			)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	checks += 1
	if not condition:
		failures.append(message)
