extends SceneTree

const WORLD_SPATIAL_INDEX: Script = preload(
	"res://scripts/world_spatial_index.gd"
)
const PERCEPTION_SCHEDULER: Script = preload(
	"res://scripts/perception_scheduler.gd"
)
const RUNTIME_PERFORMANCE_MONITOR: Script = preload(
	"res://scripts/runtime_performance_monitor.gd"
)
const CHECKPOINT_MANAGER: Script = preload(
	"res://scripts/checkpoint_manager.gd"
)
const RUNTIME_DIAGNOSTICS: Script = preload(
	"res://scripts/runtime_diagnostics.gd"
)
const CONTENT_PACKAGE_VALIDATOR: Script = preload(
	"res://scripts/content_package_validator.gd"
)
const GAME_COMMAND_BUS: Script = preload("res://scripts/game_command_bus.gd")
const RUNTIME_SERVICE_HUB: Script = preload(
	"res://scripts/runtime_service_hub.gd"
)
const NAVIGATION_REQUEST_QUEUE: Script = preload(
	"res://scripts/navigation_request_queue.gd"
)
const MODERN_DIFFICULTY_POLICY: Script = preload(
	"res://scripts/modern_difficulty_policy.gd"
)
const LEVEL_LOAD_PIPELINE: Script = preload(
	"res://scripts/level_load_pipeline.gd"
)
const HISTORY_ARCHIVE: Script = preload("res://scripts/history_archive.gd")
const MISSION_STATISTICS: Script = preload("res://scripts/mission_statistics.gd")
const LOCALIZATION_SERVICE: Script = preload(
	"res://scripts/localization_service.gd"
)
const COMBAT_FEEDBACK: Script = preload("res://scripts/combat_feedback.gd")
const APPLICATION_FOCUS_POLICY: Script = preload(
	"res://scripts/application_focus_policy.gd"
)

var failures: Array[String] = []
var checks := 0


class IndexedActor extends Node2D:
	var scene_index := -1


class FakeNavigation extends RefCounted:
	func find_path(start_world: Vector2, destination_world: Vector2) -> PackedVector2Array:
		return PackedVector2Array([start_world, destination_world])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_product_identity()
	_test_localization_catalogs()
	_test_focus_lifecycle_policy()
	_test_spatial_index()
	_test_perception_schedule()
	_test_performance_monitor()
	_test_checkpoint_rotation()
	_test_privacy_safe_diagnostics()
	_test_content_package_validation()
	_test_command_and_service_boundary()
	_test_navigation_request_budget()
	_test_modern_difficulty_policy()
	_test_background_level_loading()
	_test_history_archive_and_debrief()
	_test_diagnostics_bundle()
	if failures.is_empty():
		print("Modernization system tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_product_identity() -> void:
	_expect(
		str(ProjectSettings.get_setting("application/config/name", ""))
			== "1937 Remake",
		"the exported product no longer presents itself as a prototype",
	)
	_expect(
		str(ProjectSettings.get_setting("application/config/version", ""))
			== "0.9.0-rc.1",
		"the product exposes a versioned release identity",
	)
	_expect(
		bool(ProjectSettings.get_setting(
			"application/config/use_custom_user_dir",
			false,
		))
			and str(ProjectSettings.get_setting(
				"application/config/custom_user_dir_name",
				"",
			)) == "1937 Remake Prototype",
		"the modern title preserves the existing settings and save directory",
	)


func _test_localization_catalogs() -> void:
	var chinese_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/localization/zh_CN.json")
	)
	var english_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/localization/en.json")
	)
	_expect(
		chinese_value is Dictionary and english_value is Dictionary,
		"localization catalogs are valid JSON dictionaries",
	)
	if not chinese_value is Dictionary or not english_value is Dictionary:
		return
	var chinese := chinese_value as Dictionary
	var english := english_value as Dictionary
	var chinese_keys := chinese.keys()
	var english_keys := english.keys()
	chinese_keys.sort()
	english_keys.sort()
	_expect(
		chinese_keys == english_keys,
		"Chinese and English catalogs expose the same modern product keys",
	)
	var required_ui_keys: Array[String] = [
		"UI_GAME_SETTINGS_TITLE",
		"UI_GAME_SETTINGS_DESCRIPTION",
		"UI_SUBTITLES",
		"UI_SHOW_BRIEFINGS",
		"UI_EDGE_SCROLL_ENABLED",
		"UI_REDUCE_CAMERA_MOTION",
		"UI_LARGE_CURSOR",
		"STATUS_MISSION_FAILURE_FORMAT",
		"UI_MISSION_FAILURE_DETAILS_FORMAT",
	]
	var all_required_ui_keys_present := true
	for key: String in required_ui_keys:
		all_required_ui_keys_present = (
			all_required_ui_keys_present
			and chinese.has(key)
			and english.has(key)
		)
	_expect(
		all_required_ui_keys_present,
		"modern settings and mission-failure text are catalog-backed",
	)
	var localization = LOCALIZATION_SERVICE.new()
	_expect(
		localization.install("en") == "en"
			and str(TranslationServer.translate(&"UI_RULESET")) == "Ruleset",
		"the English catalog can replace modern settings text at runtime",
	)
	var preview_text: String = COMBAT_FEEDBACK.display_text(
		{
			"visible": true,
			"ready": true,
			"reason": "ready",
			"hit_chance": 0.8,
			"distance": 32.0,
			"horizontal_range": 128.0,
			"alert_radius": 640.0,
		},
		"Pistol",
	)
	_expect(
		preview_text.contains("Hit 80%") and preview_text.contains("Ready to attack"),
		"combat feedback resolves through the active translation catalog",
	)
	localization.install("zh_CN")


func _test_focus_lifecycle_policy() -> void:
	var policy = APPLICATION_FOCUS_POLICY.new()
	var lost: Dictionary = policy.on_focus_lost(true, false, true)
	var gained: Dictionary = policy.on_focus_gained(true)
	_expect(
		bool(lost["apply"])
			and bool(lost["paused"])
			and bool(gained["apply"])
			and not bool(gained["paused"]),
		"focus loss pauses and focus gain restores the prior running state",
	)
	var already_paused: Dictionary = policy.on_focus_lost(true, true, true)
	var restored_paused: Dictionary = policy.on_focus_gained(true)
	_expect(
		bool(already_paused["paused"])
			and bool(restored_paused["paused"]),
		"focus policy never resumes a game that was already paused",
	)
	var probe_loss: Dictionary = policy.on_focus_lost(true, false, false)
	_expect(
		not bool(probe_loss["apply"]),
		"non-interactive probes ignore desktop focus without deadlocking",
	)


func _test_spatial_index() -> void:
	var index = WORLD_SPATIAL_INDEX.new(Vector2(64.0, 64.0))
	var first := IndexedActor.new()
	first.scene_index = 10
	first.position = Vector2(20.0, 20.0)
	root.add_child(first)
	var second := IndexedActor.new()
	second.scene_index = 11
	second.position = Vector2(180.0, 20.0)
	root.add_child(second)
	_expect(index.register_node(first, ["actor", "enemy"]), "spatial index registers actors")
	_expect(index.register_node(second, ["actor", "enemy"]), "spatial index registers a second actor")
	_expect(
		index.query_radius(Vector2.ZERO, 64.0, ["enemy"]) == [first],
		"radius query visits only nearby tagged buckets",
	)
	_expect(index.node_for_scene(11) == second, "scene identity lookup is constant-time")
	second.position = Vector2(30.0, 25.0)
	_expect(index.update_node(second), "moving across a cell updates the broad phase")
	_expect(
		index.query_radius(Vector2.ZERO, 64.0, ["enemy"]).size() == 2,
		"updated actors are visible in their new bucket",
	)
	_expect(index.unregister_node(first), "spatial index unregisters removed actors")
	_expect(index.node_for_scene(10) == null, "unregistered scene identity is removed")
	first.queue_free()
	second.queue_free()


func _test_perception_schedule() -> void:
	var scheduler = PERCEPTION_SCHEDULER.new(0.20, 12)
	var indices: Array[int] = []
	var phases: Dictionary = {}
	for scene_index: int in range(100, 124):
		indices.append(scene_index)
		phases[scheduler.phase_for_scene(scene_index)] = true
	_expect(phases.size() == 12, "twenty-four guards distribute across all perception slots")
	var snapshot: Dictionary = scheduler.schedule_snapshot(indices)
	_expect(int(snapshot["actors"]) == 24, "perception schedule reports its actor population")
	_expect(
		float(scheduler.initial_elapsed_for_scene(100)) >= 0.0
			and float(scheduler.initial_elapsed_for_scene(100)) <= 0.20,
		"perception phase remains within the configured interval",
	)


func _test_performance_monitor() -> void:
	var monitor = RUNTIME_PERFORMANCE_MONITOR.new(60, 32)
	monitor.begin_frame()
	var elapsed: int = monitor.end_frame()
	monitor.increment("path_queries", 3)
	monitor.record_event("inventory_prewarm", 1200, {"slots": 8})
	var snapshot: Dictionary = monitor.snapshot()
	_expect(elapsed >= 0, "performance monitor accepts a frame sample")
	_expect(
		int((snapshot["frame"] as Dictionary)["sample_count"]) == 1,
		"performance snapshot publishes frame statistics",
	)
	_expect(
		int((snapshot["counters"] as Dictionary)["path_queries"]) == 3,
		"performance snapshot publishes subsystem counters",
	)


func _test_checkpoint_rotation() -> void:
	var checkpoints = CHECKPOINT_MANAGER.new(3, 0.0)
	_expect(checkpoints.reserve_slot("level_start") == "checkpoint_1", "first checkpoint uses slot one")
	_expect(checkpoints.reserve_slot("objective") == "checkpoint_2", "second checkpoint advances")
	_expect(checkpoints.reserve_slot("objective") == "checkpoint_3", "third checkpoint advances")
	_expect(checkpoints.reserve_slot("objective") == "checkpoint_1", "checkpoint slots rotate safely")


func _test_privacy_safe_diagnostics() -> void:
	var diagnostics = RUNTIME_DIAGNOSTICS.new()
	diagnostics.build_id = "test"
	diagnostics.record_command("move", {"position": Vector2(12.0, 34.0)})
	var document: Dictionary = diagnostics.build_document(
		"m000",
		{
			"display_mode": "windowed",
			"controls": {"pause": {"keycode": KEY_ESCAPE}},
			"private_path": "C:/Users/example",
		},
		{},
	)
	var exported_settings := document["settings"] as Dictionary
	_expect(exported_settings.get("display_mode") == "windowed", "diagnostics retain reproducible settings")
	_expect(not exported_settings.has("controls"), "diagnostics omit custom key bindings")
	_expect(not exported_settings.has("private_path"), "diagnostics omit unknown private values")
	_expect((document["recent_commands"] as Array).size() == 1, "diagnostics retain a bounded command trail")


func _test_content_package_validation() -> void:
	var fixture_root := ProjectSettings.globalize_path(
		"user://qa-modernization-content-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(fixture_root)
	var critical_path := fixture_root.path_join("level.json")
	var critical_file := FileAccess.open(critical_path, FileAccess.WRITE)
	critical_file.store_string("{}")
	critical_file.close()
	var manifest_path := fixture_root.path_join("content-manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify({
		"schema_version": 1,
		"profile_id": "test-profile",
		"content_identity_sha256": "fixture",
		"files": [{
			"path": "level.json",
			"bytes": 2,
			"sha256": FileAccess.get_sha256(critical_path),
			"critical": true,
		}],
	}))
	manifest_file.close()
	var valid: Dictionary = CONTENT_PACKAGE_VALIDATOR.validate(
		manifest_path,
		fixture_root,
		"test-profile",
	)
	_expect(
		bool(valid["ok"]) and int(valid["checked_critical_files"]) == 1,
		"runtime content validation checks the portable package identity",
	)
	var mismatched: Dictionary = CONTENT_PACKAGE_VALIDATOR.validate(
		manifest_path,
		fixture_root,
		"other-profile",
	)
	_expect(
		not bool(mismatched["ok"]),
		"runtime content validation rejects an unexpected content profile",
	)
	var corrupt_file := FileAccess.open(critical_path, FileAccess.WRITE)
	corrupt_file.store_string("[]")
	corrupt_file.close()
	var corrupted: Dictionary = CONTENT_PACKAGE_VALIDATOR.validate(
		manifest_path,
		fixture_root,
		"test-profile",
	)
	_expect(
		not bool(corrupted["ok"])
			and not (corrupted["failures"] as Array).is_empty(),
		"runtime content validation rejects corrupted critical content",
	)
	DirAccess.remove_absolute(critical_path)
	var missing: Dictionary = CONTENT_PACKAGE_VALIDATOR.validate(
		manifest_path,
		fixture_root,
		"test-profile",
	)
	_expect(
		not bool(missing["ok"])
			and str((missing["failures"] as Array)[0]).contains("missing"),
		"runtime content validation rejects missing critical content",
	)
	DirAccess.remove_absolute(manifest_path)
	DirAccess.remove_absolute(fixture_root)


func _test_command_and_service_boundary() -> void:
	var bus = GAME_COMMAND_BUS.new()
	var observed: Array[Dictionary] = []
	bus.command_issued.connect(
		func(command: Dictionary) -> void:
			observed.append(command)
	)
	bus.register_handler(
		"move",
		func(payload: Dictionary) -> bool:
			return payload.has("destination")
	)
	var command: Dictionary = bus.issue(
		"Move",
		{"destination": Vector2(12.0, 16.0)},
		"test",
	)
	_expect(
		bool(command.get("result", false)) and observed.size() == 1,
		"command bus presents one normalized command boundary",
	)
	var hub = RUNTIME_SERVICE_HUB.new()
	hub.begin_level("m003")
	var stats: Dictionary = hub.stats()
	_expect(
		str(stats["level_id"]) == "m003"
			and int((stats["commands"] as Dictionary)["history_count"]) == 1,
		"runtime service hub owns lifecycle, commands and world services",
	)


func _test_navigation_request_budget() -> void:
	var queue = NAVIGATION_REQUEST_QUEUE.new()
	var completed: Array[int] = []
	for scene_index: int in range(4):
		queue.enqueue(
			scene_index,
			Vector2.ZERO,
			Vector2(32.0 + scene_index, 16.0),
			func(path: PackedVector2Array, request: Dictionary, _elapsed: int) -> void:
				if path.size() == 2:
					completed.append(int(request["scene_index"])),
		)
	var processed: int = int(
		queue.process_budget(null, FakeNavigation.new(), 1_000_000, 2)
	)
	_expect(
		processed == 2 and queue.pending_count() == 2 and completed == [0, 1],
		"navigation queue enforces a per-frame request budget",
	)
	queue.cancel_all()
	_expect(queue.pending_count() == 0, "level changes cancel stale navigation requests")


func _test_modern_difficulty_policy() -> void:
	var authored := {
		"source_status": "remake_editorial",
		"reaction_time_multiplier": 1.0,
		"sense_radius_multiplier": 1.0,
		"shared_alert_radius_multiplier": 1.0,
		"reinforcement_budget": 4,
	}
	var story: Dictionary = MODERN_DIFFICULTY_POLICY.compose(
		authored, "story"
	)
	var hard: Dictionary = MODERN_DIFFICULTY_POLICY.compose(
		authored, "hard"
	)
	_expect(
		float(story["enemy_hit_chance"]) < float(hard["enemy_hit_chance"])
		and float(story["reaction_time_multiplier"])
			> float(hard["reaction_time_multiplier"]),
		"difficulty coherently changes accuracy and reaction time",
	)
	_expect(
		float(story["sense_radius_multiplier"])
			< float(hard["sense_radius_multiplier"])
		and int(story["reinforcement_budget"])
			< int(hard["reinforcement_budget"]),
		"difficulty coherently changes perception and reinforcement pressure",
	)
	_expect(
		float(story["player_resource_multiplier"])
			> float(hard["player_resource_multiplier"])
		and float(story["search_duration_multiplier"])
			< float(hard["search_duration_multiplier"]),
		"difficulty balances player resources and search persistence",
	)
	var custom: Dictionary = MODERN_DIFFICULTY_POLICY.compose(
		authored,
		"custom",
		{
			"enemy_accuracy": 0.61,
			"reaction_multiplier": 0.91,
			"perception_multiplier": 1.11,
			"search_multiplier": 0.73,
			"alert_multiplier": 1.47,
			"reinforcement_multiplier": 1.19,
		},
	)
	_expect(
		is_equal_approx(float(custom["enemy_hit_chance"]), 0.61)
			and is_equal_approx(
				float(custom["shared_alert_radius_multiplier"]),
				1.47,
			)
			and is_equal_approx(
				float(custom["search_duration_multiplier"]),
				0.73,
			),
		"custom difficulty keeps accuracy, alert radius and search duration independent",
	)


func _test_background_level_loading() -> void:
	var fixture_root := ProjectSettings.globalize_path(
		"user://qa-level-pipeline-%d" % OS.get_process_id()
	)
	DirAccess.make_dir_recursive_absolute(fixture_root)
	var json_path := fixture_root.path_join("level.json")
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	json_file.store_string('{"schema_version":1,"name":"fixture"}')
	json_file.close()
	var image_path := fixture_root.path_join("terrain.png")
	var fixture_image := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	fixture_image.fill(Color(0.2, 0.3, 0.4, 1.0))
	fixture_image.save_png(image_path)
	var pipeline = LEVEL_LOAD_PIPELINE.new()
	_expect(
		pipeline.begin(json_path, image_path),
		"background level pipeline starts one immutable read task",
	)
	var bundle: Dictionary = pipeline.finish()
	_expect(
		int((bundle["level_source"] as Dictionary)["schema_version"]) == 1
		and bundle["terrain_image"] is Image
		and (bundle["terrain_image"] as Image).get_size() == Vector2i(4, 3),
		"background level pipeline decodes JSON and terrain before scene creation",
	)
	DirAccess.remove_absolute(json_path)
	DirAccess.remove_absolute(image_path)
	DirAccess.remove_absolute(fixture_root)


func _test_history_archive_and_debrief() -> void:
	var archive = HISTORY_ARCHIVE.new()
	_expect(archive.load_catalog(), "history archive loads its versioned catalog")
	var level_ids: Array[String] = [
		"m000", "m001", "m002", "m003", "m004", "m005",
		"m006", "m007", "m008", "m009", "m010", "m011",
	]
	_expect(
		archive.validate_required_missions(level_ids).is_empty(),
		"all twelve missions provide context, boundaries and knowledge terms",
	)
	var statistics = MISSION_STATISTICS.new()
	statistics.begin_mission("m000")
	statistics.observe_event({
		"name": "attack_started",
		"payload": {"player": true},
	})
	statistics.observe_event({
		"name": "attack_hit",
		"payload": {"player": true},
	})
	var snapshot: Dictionary = statistics.snapshot()
	var debrief: String = archive.build_debrief("m000", snapshot)
	_expect(
		int(snapshot["attacks"]) == 1
			and int(snapshot["hits"]) == 1
			and debrief.contains("史实与艺术加工"),
		"mission statistics feed a fact-versus-fiction completion debrief",
	)


func _test_diagnostics_bundle() -> void:
	var diagnostics = RUNTIME_DIAGNOSTICS.new()
	var bundle_path := "user://qa-diagnostics-%d.zip" % OS.get_process_id()
	var result: Dictionary = diagnostics.export_bundle(
		diagnostics.build_document("m000", {"display_mode": "windowed"}, {}),
		bundle_path,
	)
	var reader := ZIPReader.new()
	var opened := reader.open(bundle_path) == OK
	var files := reader.get_files() if opened else PackedStringArray()
	_expect(
		bool(result.get("ok", false))
			and opened
			and files.has("diagnostics.json")
			and files.has("README.txt"),
		"privacy-safe diagnostics export as a portable ZIP bundle",
	)
	if opened:
		reader.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bundle_path))


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
