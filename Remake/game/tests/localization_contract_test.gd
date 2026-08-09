extends SceneTree

const LOCALIZATION := preload("res://scripts/localization_service.gd")
const PANEL := preload("res://scenes/failure_menu.tscn")
const CAMPAIGN_SELECTOR := preload("res://scripts/campaign_level_selector.gd")
const SAVE_SELECTOR := preload("res://scripts/save_slot_selector.gd")
const INPUT_BINDINGS := preload("res://scripts/game_input_bindings.gd")
const MISSION_DATA := preload("res://scripts/mission_data.gd")
const MISSION_DIRECTION_DATA := preload("res://scripts/mission_direction_data.gd")
const MISSION_DIRECTION_RUNTIME := preload("res://scripts/mission_direction_runtime.gd")
const HISTORY_ARCHIVE := preload("res://scripts/history_archive.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = LOCALIZATION.new()
	service.install("zh_CN")
	var chinese_snapshot := service.validation_snapshot() as Dictionary
	_expect(
		bool(chinese_snapshot.get("ok", false))
			and int(chinese_snapshot.get("zh_CN_count", 0)) >= 170,
		"Chinese and English catalogs expose the same complete key set",
	)
	_expect(
		LOCALIZATION._placeholder_signature("%s %02d %.1f%%") == ["s", "d", "f"],
		"format placeholder signatures are deterministic",
	)
	var panel := PANEL.instantiate()
	root.add_child(panel)
	await process_frame
	_expect(
		str(panel.title_label.text) == "任务失败",
		"standalone responsive panels resolve Chinese localization keys",
	)
	service.install("en")
	panel.apply_localization()
	_expect(
		str(panel.title_label.text) == "Mission failed",
		"the same panel updates to complete English text without reconstruction",
	)
	_expect(
		not str(panel.title_label.text).begins_with("UI_"),
		"missing keys never leak into the visible panel surface",
	)
	await _test_english_product_surfaces(service)
	panel.queue_free()
	service.install("zh_CN")
	if failures.is_empty():
		print("Localization contract tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_english_product_surfaces(service: RefCounted) -> void:
	var campaign = CAMPAIGN_SELECTOR.new()
	var entries: Array[Dictionary] = []
	for number: int in range(1, 13):
		entries.append({
			"id": "m%03d" % (number - 1),
			"number": number,
			"title": "Mission %d" % number,
		})
	campaign.configure(entries, {
		"completed_level_ids": ["m000"],
		"highest_unlocked_level_id": "m001",
	}, "m000")
	root.add_child(campaign)
	var selector = SAVE_SELECTOR.new()
	selector.configure(SAVE_SELECTOR.Mode.LOAD, [{
		"slot_id": "legacy_002",
		"level_id": "m004",
		"elapsed_seconds": 125.0,
		"saved_at_unix": 86400,
	}])
	root.add_child(selector)
	await process_frame
	var surfaces: Array[String] = []
	_collect_surface_strings(campaign, surfaces)
	_collect_surface_strings(selector, surfaces)
	var leaked_keys: Array[String] = []
	var chinese_surfaces: Array[String] = []
	for value: String in surfaces:
		if _contains_han(value):
			chinese_surfaces.append(value)
		if _contains_visible_key(value):
			leaked_keys.append(value)
	_expect(
		chinese_surfaces.is_empty(),
		"campaign and save selectors expose no Chinese player text in English mode",
	)
	_expect(
		leaked_keys.is_empty(),
		"campaign and save selectors expose no raw localization keys",
	)
	_expect(
		surfaces.any(func(value: String) -> bool: return value.contains("Mission select"))
			and surfaces.any(func(value: String) -> bool: return value.contains("Imported legacy 002")),
		"English campaign and imported-save workflows resolve meaningful labels",
	)
	var definitions: Array[Dictionary] = INPUT_BINDINGS.definitions()
	var definitions_localized := definitions.size() >= 20
	for definition: Dictionary in definitions:
		var label := str(definition.get("label", ""))
		var category := str(definition.get("category", ""))
		definitions_localized = (
			definitions_localized
			and not label.is_empty()
			and not category.is_empty()
			and not _contains_han(label + category)
			and not _contains_visible_key(label + category)
		)
	_expect(
		definitions_localized,
		"remappable input labels and categories resolve fully in English",
	)
	var mission_surfaces: Array[String] = []
	for mission_index: int in range(12):
		var mission_id := "m%03d" % mission_index
		for rule_mode: String in ["stable_mod", "repaired"]:
			var mission: Dictionary = MISSION_DATA.load_mission_for_rule_mode(
				mission_id,
				rule_mode,
			)
			var mission_title := str(mission.get("title", ""))
			if mission_title.is_empty():
				print("Empty localized mission title: ", mission_id, "/", rule_mode)
			mission_surfaces.append(mission_title)
			for raw_objective: Variant in mission.get("objectives", []) as Array:
				var objective := raw_objective as Dictionary
				var objective_label := str(objective.get("label", ""))
				if objective_label.is_empty():
					print(
						"Empty localized objective: ",
						mission_id, "/", rule_mode, "/", objective.get("id", ""),
					)
				mission_surfaces.append(objective_label)
		var plan: Dictionary = MISSION_DIRECTION_DATA.load_mission_plan(mission_id)
		for raw_beat: Variant in plan.get("beats", []) as Array:
			var beat := raw_beat as Dictionary
			var tutorial := beat.get("tutorial", {}) as Dictionary
			if not tutorial.is_empty():
				var tutorial_text := str(tutorial.get("text", ""))
				if tutorial_text.is_empty():
					print("Empty localized tutorial: ", mission_id, "/", beat.get("id", ""))
				mission_surfaces.append(tutorial_text)
			var dialogue := beat.get("dialogue", {}) as Dictionary
			for raw_line: Variant in dialogue.get("lines", []) as Array:
				var line := raw_line as Dictionary
				var speaker := str(line.get("speaker", ""))
				if not speaker.is_empty():
					mission_surfaces.append(speaker)
				var dialogue_text := str(line.get("text", ""))
				if dialogue_text.is_empty():
					print("Empty localized dialogue: ", mission_id, "/", beat.get("id", ""))
				mission_surfaces.append(dialogue_text)
	var mission_content_localized := mission_surfaces.size() >= 150
	var invalid_mission_surfaces: Array[String] = []
	for value: String in mission_surfaces:
		var valid_surface := (
			not value.is_empty()
			and not _contains_han(value)
			and not _contains_visible_key(value)
		)
		mission_content_localized = mission_content_localized and valid_surface
		if not valid_surface:
			invalid_mission_surfaces.append(value)
	if not mission_content_localized:
		print(
			"Invalid English mission surfaces (%d total, %d invalid): %s"
			% [
				mission_surfaces.size(),
				invalid_mission_surfaces.size(),
				JSON.stringify(invalid_mission_surfaces),
			]
		)
	_expect(
		mission_content_localized,
		"all twelve mission titles, rule profiles, objectives, tutorials and dialogue resolve in English",
	)
	var direction_runtime = MISSION_DIRECTION_RUNTIME.new()
	root.add_child(direction_runtime)
	var direction_configured: bool = direction_runtime.configure_for_mission(
		"m000", null, "normal"
	)
	direction_runtime.start()
	direction_runtime.advance_ticks(37)
	var direction_before: Dictionary = direction_runtime.capture_state()
	service.install("zh_CN")
	direction_runtime.refresh_localization()
	var direction_after: Dictionary = direction_runtime.capture_state()
	_expect(
		direction_configured
			and _contains_han(str(direction_runtime.mission_plan.get("title", "")))
			and int(direction_after.get("elapsed_ticks", -1)) == 37
			and direction_after.get("fired_beats", [])
				== direction_before.get("fired_beats", []),
		"language switching refreshes active direction text without resetting deterministic state",
	)
	direction_runtime.queue_free()
	service.install("en")
	var history = HISTORY_ARCHIVE.new()
	var history_ids: Array[String] = []
	var english_history_complete := history.load_catalog()
	for mission_index: int in range(12):
		var mission_id := "m%03d" % mission_index
		history_ids.append(mission_id)
		var formatted := history.formatted_entry(mission_id)
		english_history_complete = (
			english_history_complete
			and not formatted.is_empty()
			and not _contains_han(formatted)
			and not _contains_visible_key(formatted)
		)
	english_history_complete = (
		english_history_complete
		and history.validate_required_missions(history_ids).is_empty()
	)
	_expect(
		english_history_complete,
		"the optional twelve-mission history archive is complete in English",
	)
	campaign.queue_free()
	selector.queue_free()


func _collect_surface_strings(node: Node, output: Array[String]) -> void:
	if node is Label:
		_append_visible_string(output, str((node as Label).text))
	elif node is RichTextLabel:
		_append_visible_string(output, str((node as RichTextLabel).text))
	elif node is Button:
		_append_visible_string(output, str((node as Button).text))
	elif node is LineEdit:
		_append_visible_string(output, str((node as LineEdit).placeholder_text))
	elif node is OptionButton:
		var option := node as OptionButton
		for index: int in range(option.item_count):
			_append_visible_string(output, option.get_item_text(index))
	if node is Control:
		_append_visible_string(output, str((node as Control).tooltip_text))
	for child: Node in node.get_children():
		_collect_surface_strings(child, output)


func _append_visible_string(output: Array[String], value: String) -> void:
	var normalized := value.strip_edges()
	if not normalized.is_empty():
		output.append(normalized)


func _contains_han(value: String) -> bool:
	for index: int in range(value.length()):
		var codepoint := value.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9fff:
			return true
	return false


func _contains_visible_key(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("(?:UI|STATUS|INPUT|TOOLTIP|ERROR|STATE)_[A-Z0-9_]+") != OK:
		return true
	return expression.search(value) != null
