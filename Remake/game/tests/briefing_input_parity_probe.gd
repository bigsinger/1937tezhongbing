extends SceneTree

const DIRECTOR_SCRIPT: Script = preload("res://scripts/media_director.gd")
const OUTPUT_ARGUMENT_PREFIX := "--output="
const SCENARIO_ID := "m010-briefing-left-click-dismissal-v1"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var output_path := _argument_value(OUTPUT_ARGUMENT_PREFIX)
	if output_path.is_empty():
		failures.append("missing --output=<absolute path>")

	var director: CanvasLayer = DIRECTOR_SCRIPT.new()
	root.add_child(director)
	await process_frame
	var opened := [0]
	var closed := [0]
	var original_image := [false]
	director.briefing_opened.connect(
		func(_level_id: String, used_original: bool) -> void:
			opened[0] += 1
			original_image[0] = used_original
	)
	director.briefing_closed.connect(
		func(_level_id: String) -> void: closed[0] += 1
	)
	director.call("configure")
	director.call(
		"show_briefing",
		"m010",
		"第 11 关：血色渡口",
		"稳定 MOD 简报输入差分夹具",
	)
	await process_frame

	var checkpoints: Array[Dictionary] = []
	checkpoints.append(_capture(director, "briefing_visible", opened[0], closed[0]))
	_expect(
		not director.active_briefing.is_empty()
		and director.overlay.visible
		and paused,
		"briefing is a visible paused in-window modal",
		failures,
	)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(160.0, 120.0)
	press.global_position = press.position
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	checkpoints.append(_capture(director, "pointer_pressed", opened[0], closed[0]))
	_expect(
		not director.active_briefing.is_empty()
		and director.overlay.visible
		and paused,
		"left-button press is consumed without click-through",
		failures,
	)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = press.position
	release.global_position = press.global_position
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	checkpoints.append(_capture(director, "briefing_dismissed", opened[0], closed[0]))
	_expect(
		director.active_briefing.is_empty()
		and not director.overlay.visible
		and not paused
		and opened[0] == 1
		and closed[0] == 1,
		"left-button release closes exactly one briefing and resumes gameplay",
		failures,
	)

	var report := {
		"schema_version": 1,
		"runtime": "remake",
		"content_profile": "repository-mod-12-level-20260729",
		"level": {
			"id": "m010",
			"selector_level": 11,
			"engine_mission": 11,
		},
		"scenario": {
			"id": SCENARIO_ID,
			"input": "left_mouse_press_release",
			"dismiss_phase": "release",
		},
		"metadata": {
			"input_isolation": "target-viewport-event",
			"global_pointer_control": false,
			"used_original_image": original_image[0],
		},
		"checkpoints": checkpoints,
		"passed": failures.is_empty(),
		"failures": failures,
	}
	if not output_path.is_empty():
		var absolute_path := ProjectSettings.globalize_path(output_path)
		DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
		var output := FileAccess.open(absolute_path, FileAccess.WRITE)
		if output == null:
			failures.append("could not write %s" % absolute_path)
			report["passed"] = false
			report["failures"] = failures
		else:
			output.store_string(JSON.stringify(report, "\t") + "\n")
			output.close()
	print("BRIEFING_INPUT_PARITY_RESULT %s" % JSON.stringify(report))

	root.remove_child(director)
	director.free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _capture(
	director: CanvasLayer,
	checkpoint_id: String,
	opened_count: int,
	closed_count: int,
) -> Dictionary:
	return {
		"id": checkpoint_id,
		"active_briefing": str(director.active_briefing),
		"overlay_visible": bool(director.overlay.visible),
		"tree_paused": paused,
		"opened_count": opened_count,
		"closed_count": closed_count,
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
