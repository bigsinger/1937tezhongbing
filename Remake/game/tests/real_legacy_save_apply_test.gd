extends SceneTree

const GAME_SAVE_STORE: Script = preload(
	"res://scripts/game_save_store.gd"
)
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
)
const MAIN_SCENE: PackedScene = preload(
	"res://scenes/main.tscn"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_directory := _argument_value("--save-directory=")
	if save_directory.is_empty():
		push_error("missing --save-directory argument")
		quit(1)
		return
	var store = GAME_SAVE_STORE.new(save_directory)
	var summaries: Array[Dictionary] = store.list_slots()
	_expect(not summaries.is_empty(), "converted legacy slots are present")
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	for summary: Dictionary in summaries:
		var slot_id := str(summary.get("slot_id", ""))
		var loaded: Dictionary = store.load_slot(slot_id)
		_expect(
			bool(loaded.get("ok", false)),
			"%s passes the product save loader" % slot_id,
		)
		if not bool(loaded.get("ok", false)):
			continue
		var session := (
			(loaded["data"] as Dictionary)["session"] as Dictionary
		)
		var level_id := str(session.get("level_id", ""))
		var level_index := int(level_id.trim_prefix("m"))
		main.switch_level(level_index)
		await process_frame
		_expect(
			str(main.current_mission.get("id", "")) == level_id,
			"%s loads its matched original level" % slot_id,
		)
		var applied: Dictionary = (
			GAME_SESSION_STATE.apply_after_level_loaded(main, session)
		)
		_expect(
			bool(applied.get("ok", false)),
			"%s applies to the real imported world" % slot_id,
		)
		var warnings := applied.get("warnings", []) as Array
		_expect(
			warnings.is_empty(),
			"%s restores every actor identity without warnings: %s"
			% [slot_id, str(warnings)],
		)
		for mapping: Dictionary in [
			{"records": "squad", "runtime": "units"},
			{"records": "enemies", "runtime": "enemies"},
			{"records": "escorts", "runtime": "escorts"},
			{"records": "ambient", "runtime": "ambient_units"},
		]:
			var runtime_actors := main.get(
				str(mapping["runtime"])
			) as Array
			for record_value: Variant in session.get(
				str(mapping["records"]),
				[],
			) as Array:
				if not record_value is Dictionary:
					continue
				var record := record_value as Dictionary
				var actor := _actor_by_scene(
					runtime_actors,
					int(record.get("scene_index", -1)),
				)
				_expect(
					actor != null,
					"%s scene %d exists after restore"
					% [slot_id, int(record.get("scene_index", -1))],
				)
				if actor == null:
					continue
				_expect(
					actor.position.distance_to(
						Vector2(
							float(record.get("x", 0.0)),
							float(record.get("y", 0.0)),
						)
					) < 0.1,
					"%s scene %d restores original reference position"
					% [slot_id, int(record.get("scene_index", -1))],
				)
				_expect(
					int(actor.get("current_hit_points"))
						== int(record.get("current_hit_points", -1))
					and bool(actor.get("is_alive"))
						== bool(record.get("is_alive", false)),
					"%s scene %d restores life/death state"
					% [slot_id, int(record.get("scene_index", -1))],
				)
				_expect(
					_facing_matches_or_is_sparse(actor, record),
					"%s scene %d restores original facing"
					% [slot_id, int(record.get("scene_index", -1))],
				)
				_expect(
					_weapon_container_matches(actor, record),
					"%s scene %d restores its ordered weapon state"
					% [slot_id, int(record.get("scene_index", -1))],
				)
				_expect(
					_backpack_container_matches(actor, record),
					"%s scene %d restores its ordered backpack state"
					% [slot_id, int(record.get("scene_index", -1))],
				)
		var world := session["world"] as Dictionary
		_expect(
			(main.legacy_burial_caches as Array).size()
				== (
					world.get("legacy_burial_caches", []) as Array
				).size(),
			"%s restores every recovered burial cache" % slot_id,
		)
		var active_pickup_count := 0
		for pickup_value: Variant in main.field_pickups as Array:
			if (
				pickup_value is Node
				and is_instance_valid(pickup_value)
				and not bool((pickup_value as Node).get("consumed"))
			):
				active_pickup_count += 1
		_expect(
			active_pickup_count
				== (
					world.get(
						"remaining_field_pickup_scene_indices",
						[],
					) as Array
				).size(),
			"%s restores the original remaining-pickup set" % slot_id,
		)
	main.queue_free()
	if failures.is_empty():
		print(
			"Real legacy SAV apply tests passed (%d checks, %d slots)."
			% [checks, summaries.size()]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _actor_by_scene(
	actors: Array,
	scene_index: int,
) -> Node2D:
	for actor_value: Variant in actors:
		if (
			actor_value is Node2D
			and is_instance_valid(actor_value)
			and int((actor_value as Node2D).get("scene_index"))
				== scene_index
		):
			return actor_value as Node2D
	return null


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _weapon_container_matches(
	actor: Node2D,
	record: Dictionary,
) -> bool:
	if not actor.has_method("parity_inventory_snapshot"):
		return false
	var actual := actor.call("parity_inventory_snapshot") as Dictionary
	var source := record.get("inventory", {}) as Dictionary
	var source_items := source.get("items", {}) as Dictionary
	var source_weapons := source.get("weapons", {}) as Dictionary
	var expected_entries: Array[Dictionary] = []
	for action_value: Variant in record.get(
		"inventory_weapon_order",
		[],
	) as Array:
		var action_key := str(action_value)
		var state_value: Variant = source_weapons.get(action_key)
		if not state_value is Dictionary:
			continue
		var state := state_value as Dictionary
		if not bool(state.get("owned", false)):
			continue
		var item_id := int(state.get("ammo_item_id", 0))
		var quantity := int(
			source_items.get(
				str(item_id),
				source_items.get(item_id, 0),
			)
		)
		expected_entries.append({
			"inventory_index": expected_entries.size(),
			"item_id": item_id,
			"quantity": quantity,
			"quantity_mode": int(state.get("quantity_mode", -1)),
		})
	var expected_active_attack_type := int(
		record.get("original_active_attack_type", 0)
	)
	return (
		actual.get("weapon_entries", []) == expected_entries
		and int(actual.get("active_attack_type", 0))
			== expected_active_attack_type
	)


func _backpack_container_matches(
	actor: Node2D,
	record: Dictionary,
) -> bool:
	if not actor.has_method("parity_inventory_snapshot"):
		return false
	var actual := actor.call("parity_inventory_snapshot") as Dictionary
	var source := record.get("backpack_inventory", {}) as Dictionary
	var expected_entries: Array[Dictionary] = []
	for entry_value: Variant in source.get("entries", []) as Array:
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		expected_entries.append({
			"inventory_index": expected_entries.size(),
			"item_id": int(entry.get("item_id", 0)),
			"quantity": int(entry.get("quantity", 0)),
			"quantity_mode": int(entry.get("quantity_mode", -1)),
		})
	return actual.get("item_entries", []) == expected_entries


func _facing_matches_or_is_sparse(
	actor: Node2D,
	record: Dictionary,
) -> bool:
	var expected_group := int(record.get("animation_group_index", -1))
	if int(actor.get("animation_group_index")) == expected_group:
		return true
	if not actor.has_method("set_animation_group"):
		return false
	# Sparse four-direction vehicle actions preserve their current serial when
	# the requested eight-direction group is absent, exactly like
	# IEngineSprite::SetCurrentSerial. A rejected retry proves this is that
	# supported boundary rather than a lost facing restore.
	return not bool(actor.call("set_animation_group", expected_group))


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
