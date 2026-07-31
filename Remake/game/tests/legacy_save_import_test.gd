extends SceneTree

const BACKPACK_INVENTORY: Script = preload(
	"res://scripts/backpack_inventory.gd"
)
const COMBAT_INVENTORY: Script = preload(
	"res://scripts/combat_inventory.gd"
)
const GAME_SAVE_STORE: Script = preload(
	"res://scripts/game_save_store.gd"
)


func _initialize() -> void:
	var failures: Array[String] = []
	var checks := 0
	var save_directory := _argument_value("--save-directory=")
	if save_directory.is_empty():
		failures.append("missing --save-directory argument")
	else:
		var store = GAME_SAVE_STORE.new(save_directory)
		var summaries: Array[Dictionary] = store.list_slots()
		checks += 1
		if summaries.is_empty():
			failures.append("no converted legacy save was loadable")
		for summary: Dictionary in summaries:
			var slot_id := str(summary.get("slot_id", ""))
			var result: Dictionary = store.load_slot(slot_id)
			checks += 1
			if not bool(result.get("ok", false)):
				failures.append("slot %s failed schema load" % slot_id)
				continue
			var document := result["data"] as Dictionary
			var session := document["session"] as Dictionary
			var world := session["world"] as Dictionary
			var source_value: Variant = world.get("legacy_source")
			checks += 1
			if (
				not source_value is Dictionary
				or str((source_value as Dictionary).get("format", ""))
					!= "original-vwf-sav-v1"
			):
				failures.append("slot %s lost legacy source metadata" % slot_id)
			var actor_count := 0
			for group_name: String in [
				"squad", "enemies", "escorts", "ambient"
			]:
				for actor_value: Variant in session.get(group_name, []) as Array:
					if not actor_value is Dictionary:
						failures.append(
							"slot %s contains a non-dictionary actor" % slot_id
						)
						continue
					actor_count += 1
					var actor := actor_value as Dictionary
					checks += 1
					if (
						int(actor.get("scene_index", -1)) < 0
						or int(actor.get("animation_group_index", -1))
							not in range(8)
					):
						failures.append(
							"slot %s contains an invalid actor identity/facing"
							% slot_id
						)
					var combat = COMBAT_INVENTORY.new()
					checks += 1
					if not combat.restore_snapshot(
						actor.get("inventory", {}) as Dictionary
					):
						failures.append(
							"slot %s actor %d rejected its weapon container"
							% [slot_id, int(actor.get("scene_index", -1))]
						)
					var backpack = BACKPACK_INVENTORY.new()
					checks += 1
					if not backpack.restore_snapshot(
						actor.get("backpack_inventory", {}) as Dictionary
					):
						failures.append(
							"slot %s actor %d rejected its backpack container"
							% [slot_id, int(actor.get("scene_index", -1))]
						)
			checks += 1
			if actor_count <= 0:
				failures.append("slot %s contains no actor state" % slot_id)
			for cache_value: Variant in world.get(
				"legacy_burial_caches",
				[],
			) as Array:
				if not cache_value is Dictionary:
					failures.append(
						"slot %s contains an invalid burial cache" % slot_id
					)
					continue
				var cache := cache_value as Dictionary
				var combat = COMBAT_INVENTORY.new()
				var backpack = BACKPACK_INVENTORY.new()
				checks += 2
				if not combat.restore_snapshot(
					cache.get("weapon_inventory", {}) as Dictionary
				):
					failures.append(
						"slot %s burial weapon container was rejected" % slot_id
					)
				if not backpack.restore_snapshot(
					cache.get("backpack_inventory", {}) as Dictionary
				):
					failures.append(
						"slot %s burial backpack container was rejected" % slot_id
					)

	if failures.is_empty():
		print(
			"Legacy SAV/SI import tests passed (%d checks, no original bytes embedded)."
			% checks
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
