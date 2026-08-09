extends SceneTree

const PACK_LOADER := preload("res://scripts/m1937_pack_loader.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader = PACK_LOADER.new()
	loader.diagnostics.clear()
	var resolved: Array[Dictionary] = loader.resolve_compatible_packages([
		_package("org.test.base"),
		_package("org.test.feature", ["org.test.base"]),
		_package("org.test.missing", ["org.test.absent"]),
		_package("org.test.future", [], [], "9.0.0"),
		_package("org.test.conflict-a", [], ["org.test.conflict-b"]),
		_package("org.test.conflict-b"),
		_package("org.test.transitive", ["org.test.conflict-a"]),
	])
	var ids: Array[String] = []
	for package: Dictionary in resolved:
		ids.append(str((package.get("manifest", {}) as Dictionary).get("pack_id", "")))
	ids.sort()
	_expect(
		ids == ["org.test.base", "org.test.feature"],
		"dependency resolver admits only the compatible closure",
	)
	var codes: Array[String] = []
	for diagnostic: Dictionary in loader.diagnostics:
		codes.append(str(diagnostic.get("code", "")))
	_expect(codes.has("missing_dependencies"), "missing dependency produces an explicit diagnostic")
	_expect(codes.has("runtime_version_incompatible"), "future runtime requirement is rejected")
	_expect(codes.has("content_conflict"), "declared conflicts disable both installed packages")
	_expect(
		codes.count("missing_dependencies") >= 2,
		"blocked dependencies propagate to downstream packages",
	)

	_expect(
		loader._compare_semantic_versions("1.0.0", "1.0.0-rc.1") > 0
			and loader._compare_semantic_versions("1.2.0", "1.1.9") > 0,
		"semantic runtime comparison handles prerelease and core ordering",
	)
	_expect(
		loader._normalize_relative_path("../escape.json").is_empty()
			and loader._normalize_relative_path("C:/escape.json").is_empty()
			and loader._normalize_relative_path("levels/one/level.json") == "levels/one/level.json",
		"runtime path policy rejects traversal and absolute paths",
	)
	loader.developer_hot_reload_enabled = false
	var reload := loader.discover_if_changed("user://does-not-need-to-exist")
	_expect(
		not bool(reload.get("changed", true))
			and (reload.get("packages", []) as Array).is_empty(),
		"release-mode hot reload remains inert",
	)

	if failures.is_empty():
		print("Native content policy tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _package(
	pack_id: String,
	dependencies: Array[String] = [],
	conflicts: Array[String] = [],
	minimum_runtime: String = "1.0.0",
) -> Dictionary:
	return {
		"path": "/synthetic/%s.m1937pack" % pack_id,
		"manifest": {
			"pack_id": pack_id,
			"minimum_runtime_version": minimum_runtime,
			"dependencies": dependencies,
			"conflicts": conflicts,
		},
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
