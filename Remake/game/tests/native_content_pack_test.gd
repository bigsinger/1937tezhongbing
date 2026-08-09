extends SceneTree

const PACK_LOADER := preload("res://scripts/m1937_pack_loader.gd")
const NATIVE_RUNTIME := preload("res://scripts/native_content_runtime.gd")
const MISSION_STATE := preload("res://scripts/mission_state.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var package_path := _argument("--package=")
	if package_path.is_empty():
		push_error("native content test requires --package=<synthetic.m1937pack>")
		quit(1)
		return
	var loader = PACK_LOADER.new()
	var validation: Dictionary = loader.validate(package_path)
	_expect(bool(validation.get("ok", false)), "Godot validates the synthetic package")
	if bool(validation.get("ok", false)):
		var entries: Array[Dictionary] = loader.campaign_entries(validation)
		_expect(entries.size() == 1, "campaign discovery exposes one level")
		if entries.size() == 1:
			var runtime: Dictionary = NATIVE_RUNTIME.load_entry(entries[0])
			_expect(bool(runtime.get("ok", false)), "native runtime loads level, mission and generated terrain")
			if bool(runtime.get("ok", false)):
				var level := runtime.get("level", {}) as Dictionary
				var terrain := runtime.get("terrain_image") as Image
				_expect(
					int((level.get("world_size", {}) as Dictionary).get("width", 0)) == 640
						and terrain != null and terrain.get_size() == Vector2i(640, 384),
					"synthetic map has its declared playable world size",
				)
				var state = MISSION_STATE.new(runtime.get("mission", {}) as Dictionary)
				state.record_event("trigger_activated", {"role_id": "training_exit"})
				_expect(state.is_victory(), "synthetic package mission reaches a real victory state")
				var failed_state = MISSION_STATE.new(runtime.get("mission", {}) as Dictionary)
				failed_state.record_event("time_expired")
				_expect(failed_state.is_failed(), "synthetic package mission reaches a real failure state")
	if failures.is_empty():
		print("Native content package tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
