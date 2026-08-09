extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const MISSION_STATE := preload("res://scripts/mission_state.gd")
const MISSION_RUNTIME := preload("res://scripts/mission_runtime.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	var expected_content_id := _argument("--content-id=")
	if expected_content_id.is_empty():
		expected_content_id = "org.m1937.synthetic-training:training"
	var expected_world := Vector2(
		float(_argument_int("--world-width=", 640)),
		float(_argument_int("--world-height=", 384)),
	)
	var expect_rich_content := _has_argument("--expect-rich-content")
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_process(false)

	_expect(
		str(main.current_mission.get("id", "")) == "training"
			and str(main.active_content_entry.get("id", "")) == expected_content_id,
		"product Main selects the discovered native campaign entry (mission=%s active=%s entries=%s diagnostics=%s)"
		% [
			str(main.current_mission.get("id", "")),
			str(main.active_content_entry.get("id", "")),
			str(main.native_content_entries.keys()),
			str(main.native_content_loader.get("diagnostics")),
		],
	)
	_expect(
		main.terrain_loaded
			and main.navigation_grid != null
			and main.world_size == expected_world,
		"product Main constructs generated terrain and authoritative navigation (terrain=%s nav=%s world=%s imported=%s)"
		% [main.terrain_loaded, main.navigation_grid != null, str(main.world_size), str(main.imported_level)],
	)
	_expect(
		main.units.size() == 1
			and main.world_entities_by_scene.has(900000)
			and main.current_mission_state != null,
		"native entities, task anchor and mission runtime enter the real world graph (units=%d scenes=%s mission_state=%s playable=%s)"
		% [
			main.units.size(),
			str(main.world_entities_by_scene.keys()),
			main.current_mission_state != null,
			str(main.playable_entities.keys()),
		],
	)
	if (
		main.units.is_empty()
		or main.navigation_grid == null
		or not main.world_entities_by_scene.has(900000)
	):
		_finish(main)
		return

	var player: Node2D = main.units[0]
	main.select_only(player)
	if expect_rich_content:
		_expect(
			main.enemies.size() == 1
				and main.legacy_doors.size() == 1
				and main.mission_pickups.size() == 1,
			"MapEditor native package constructs patrol, dynamic door and pickup runtime nodes (enemies=%d doors=%d pickups=%d scenes=%s)"
			% [
				main.enemies.size(),
				main.legacy_doors.size(),
				main.mission_pickups.size(),
				str(main.world_entities_by_scene.keys()),
			],
		)
		if not main.enemies.is_empty():
			var patrol: PackedVector2Array = main.enemies[0].get(
				"patrol_waypoints"
			) as PackedVector2Array
			_expect(
				patrol.size() == 2,
				"authored enemy patrol route survives editor export and runtime construction",
			)
		var door_cell := Vector2i(8, 6)
		_expect(
			int(main.navigation_grid.call("source_value", 3, door_cell)) == 1070
				and int(main.navigation_grid.call("source_value", 2, door_cell)) == 1070,
			"native door owns matching L3 movement and L2 sight source cells",
		)
		if not main.legacy_doors.is_empty():
			var door: Node2D = main.legacy_doors[0]
			_expect(
				main._try_open_legacy_door_at(door.position)
					and bool(door.get("is_open"))
					and bool(main.dynamic_occupancy.call(
						"is_source_scene_disabled", 70
					)),
				"opening a native door releases its A* and line-of-sight source footprint",
			)
		if not main.mission_pickups.is_empty():
			var pickup: Node2D = main.mission_pickups[0]
			var pickup_payload: Dictionary = pickup.get("item_payload").duplicate(true)
			player.global_position = pickup.global_position
			await process_frame
			_expect(
				main.issue_original_pickup_order(pickup),
				"native pickup enters the same priority collection flow as ordinary loot",
			)
			main._advance_original_pickup_order()
			await process_frame
			_expect(
				main.mission_pickups.is_empty()
					and player.get("backpack_inventory") != null
					and int(player.get("backpack_inventory").call(
						"item_count", 83
					)) == 2,
				"collected native pickup disappears and updates the actor backpack (remaining=%d count=%d collector=%s target=%s player=%s payload=%s)"
				% [
					main.mission_pickups.size(),
					int(player.get("backpack_inventory").call("item_count", 83)),
					str(main.original_pickup_order_collector),
					str(main.original_pickup_order_target),
					str(player.global_position),
					str(pickup_payload),
				],
			)
		var failure_state = MISSION_STATE.new(main.current_mission)
		var failure_runtime = MISSION_RUNTIME.new()
		root.add_child(failure_runtime)
		var configured := failure_runtime.configure(
			main.current_mission,
			main.imported_level,
			failure_state,
		)
		failure_runtime.publish_world_event("required_character_lost", {})
		_expect(
			configured and failure_state.is_failed(),
			"editor-authored failure condition closes through MissionRuntime",
		)
		root.remove_child(failure_runtime)
		failure_runtime.free()

	# Dispatch an actual logical click to the target Godot viewport.  This never
	# reads, moves, captures or clips the operating-system pointer.
	main.level_camera.position = player.position
	main.clamp_level_camera()
	main.level_camera.force_update_scroll()
	await process_frame
	var requested := player.position + Vector2(96.0, 32.0)
	var route := PackedVector2Array()
	if main.navigation_grid != null:
		route = main.navigation_grid.find_path(player.position, requested)
	_expect(not route.is_empty(), "native synthetic map exposes a reachable move target")
	if not route.is_empty():
		var destination := route[-1]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.pressed = true
		click.position = main.get_global_transform_with_canvas() * destination
		click.global_position = click.position
		root.push_input(click, true)
		await process_frame
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = click.position
		release.global_position = click.position
		root.push_input(release, true)
		await process_frame
		_expect(
			(player.get("movement_path") as PackedVector2Array).size() > 0,
			"real viewport click reaches the product formation movement path",
		)

	var replay_before := main.command_replay.document() as Dictionary
	var recorded_move := false
	for value: Variant in replay_before.get("commands", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("name", "")) == "formation_move":
			var payload := (value as Dictionary).get("payload", {}) as Dictionary
			recorded_move = (
				payload.has("destination")
				and (payload.get("actor_scene_indices", []) as Array).size() == 1
			)
			break
	_expect(recorded_move, "product replay records normalized actor IDs and destination")

	# Complete the native mission through the same exit evaluation path used by
	# gameplay, then verify that its logical mission event joined the replay.
	player.call("cancel_path")
	var exit_entity := main.world_entities_by_scene[900000] as Dictionary
	player.position = Vector2(float(exit_entity.get("x", 0.0)), float(exit_entity.get("y", 0.0)))
	main._evaluate_exit_scene(900000)
	_expect(
		main.current_mission_state.is_victory(),
		"native task trigger completes the real product mission",
	)
	var replay_after := main.command_replay.document() as Dictionary
	var recorded_mission_event := false
	var recorded_door_event := not expect_rich_content
	var recorded_pickup_event := not expect_rich_content
	for value: Variant in replay_after.get("commands", []) as Array:
		if not value is Dictionary:
			continue
		var command := value as Dictionary
		if (
			str(command.get("stream", "")) == "event"
			and str(command.get("name", "")) == "event:trigger_activated"
			and str(command.get("source", "")) == "mission"
		):
			recorded_mission_event = true
		if str(command.get("name", "")) == "event:door_state_changed":
			recorded_door_event = true
		if str(command.get("name", "")) == "event:pickup_collected":
			recorded_pickup_event = true
	_expect(recorded_mission_event, "product replay captures the accepted mission event")
	_expect(
		recorded_door_event and recorded_pickup_event,
		"product replay captures native door and pickup world interactions",
	)
	var header := replay_after.get("header", {}) as Dictionary
	var content_identity := str(header.get("content_identity", ""))
	var identity_hash := content_identity.get_slice(":", 1)
	var expected_pack_id := expected_content_id.get_slice(":", 0)
	_expect(
		content_identity.begins_with("%s@1.0.0:" % expected_pack_id)
			and identity_hash.length() == 64
			and str(header.get("level_id", "")) == expected_content_id,
		"replay header binds playback to the native content identity (identity=%s level=%s)"
		% [content_identity, str(header.get("level_id", ""))],
	)
	_finish(main)


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _argument_int(prefix: String, fallback: int) -> int:
	var value := _argument(prefix)
	return int(value) if value.is_valid_int() else fallback


func _has_argument(value: String) -> bool:
	return value in OS.get_cmdline_user_args()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _finish(main: Node) -> void:
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		main.free()
	await process_frame
	if failures.is_empty():
		print("Native content product tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
