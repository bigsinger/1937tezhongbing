extends SceneTree

const MAIN_SCRIPT: Script = preload("res://scripts/main.gd")
const PARTICLE_FIELD: Script = preload(
	"res://scripts/legacy_ambient_particle_field.gd"
)


func _init() -> void:
	var game = MAIN_SCRIPT.new()
	game.call(
		"_apply_original_crt_random_startup_checkpoint",
		"m005",
	)
	game.call(
		"_replay_original_first_gameplay_random_update",
		"m005",
		false,
	)
	var field = PARTICLE_FIELD.new()
	field.configure(game, "m005")
	var update_count := 600
	var started_usec := Time.get_ticks_usec()
	for _index: int in range(update_count):
		if not bool(field.call("_advance_original_update")):
			push_error("ambient particle benchmark update failed")
			field.free()
			game.free()
			quit(1)
			return
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	var average_ms := (
		float(elapsed_usec) / 1000.0 / float(update_count)
	)
	print(
		(
			"Ambient particle simulation benchmark passed: "
			+ "%d updates, %.3f ms/update."
		)
		% [update_count, average_ms]
	)
	field.free()
	game.free()
	quit(0 if average_ms <= 1.0 else 1)
