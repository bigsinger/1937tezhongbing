extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GAME_INPUT_BINDINGS: Script = preload(
	"res://scripts/game_input_bindings.gd"
)
const GAME_SAVE_STORE: Script = preload("res://scripts/game_save_store.gd")
const JOURNEY_SPEC_PATH := (
	"res://../validation/replays/remake/12-level-product-input-journey-v1.json"
)
const LEVEL_IDS: Array[String] = [
	"m000",
	"m001",
	"m002",
	"m003",
	"m004",
	"m005",
	"m006",
	"m007",
	"m008",
	"m009",
	"m010",
	"m011",
]
const ORIGINAL_CHARACTER_HOTKEYS: Array[Key] = [
	KEY_F2,
	KEY_F3,
	KEY_F4,
	KEY_F5,
	KEY_F6,
]

const OVERLAY_NONE := 0
const OVERLAY_PAUSE := 1
const OVERLAY_INVENTORY := 3
const OVERLAY_FAILURE := 4
const OVERLAY_HELP := 7

var failures: Array[String] = []
var checks := 0
var submitted_input_events := 0
var trace_records: Array[Dictionary] = []
var save_directory := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var journey_spec := _load_journey_spec()
	_expect(
		journey_spec.get("levels", []) == LEVEL_IDS,
		"the versioned product-input journey covers exactly m000-m011",
	)
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.runtime_settings["controls"] = GAME_INPUT_BINDINGS.default_bindings()
	main.runtime_settings["mission_rule_mode"] = "stable_mod"
	main.runtime_settings["difficulty_mode"] = "original"

	# Never touch a player's normal save slots or settings. This exact,
	# process-unique user:// directory is deleted after the gate completes.
	save_directory = (
		"user://qa-real-input-campaign/%d-%d"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	main.save_store = GAME_SAVE_STORE.new(save_directory)
	main.game_settings = null
	main.campaign_progress = GAME_SAVE_STORE.default_campaign()
	var empty_save_slots: Array[Dictionary] = []
	main.game_shell.set_save_slots(empty_save_slots)

	var requested_level_id := _requested_level_id()
	var exercised_level_count := 0
	for level_index: int in range(LEVEL_IDS.size()):
		if (
			not requested_level_id.is_empty()
			and LEVEL_IDS[level_index] != requested_level_id
		):
			continue
		await _exercise_level(main, level_index)
		exercised_level_count += 1

	if main.game_shell != null:
		main.game_shell.close_for_state_change()
	root.remove_child(main)
	main.free()
	await process_frame
	_cleanup_test_save_directory()

	_expect(
		trace_records.size() == exercised_level_count,
		"every requested level produced one product-input journey record",
	)
	_expect(
		submitted_input_events >= 24 * exercised_level_count,
		"the gate submitted a substantial keyboard/mouse event sequence",
	)
	if failures.is_empty():
		print(
			(
				"Real 12-level product-input journey passed "
				+ "(%d checks, %d viewport events, no global pointer control)."
			)
			% [checks, submitted_input_events]
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _exercise_level(main: Node, level_index: int) -> void:
	var level_id := LEVEL_IDS[level_index]
	main.switch_level(level_index, false, false)
	_expect(
		main.mission_direction_runtime == null
		and main.mission_ai_coordinator == null,
		"%s original profile starts without remake-editorial presentation or AI" % level_id,
	)
	_disable_autonomous_world(main)
	_expect(
		str(main.current_mission.get("id", "")) == level_id,
		"%s starts from the matching real mission graph" % level_id,
	)
	_expect(not main.units.is_empty(), "%s exposes at least one playable actor" % level_id)
	if main.units.is_empty():
		return

	var player: Node2D = main.units[0]
	var selected_player_scene := int(player.get("scene_index"))
	var player_selection_key := _original_character_hotkey(main, player)
	_expect(
		player_selection_key != KEY_NONE,
		"%s first real player has an original fixed character slot" % level_id,
	)
	main.clear_selection()
	if player_selection_key != KEY_NONE:
		await _tap_key(player_selection_key)
	_expect(
		main.selected_units.size() == 1
			and main.selected_units[0] == player
			and bool(player.get("selected")),
		"%s original character hotkey selects its first real player actor" % level_id,
	)
	var expected_camera: Vector2 = main.LEVEL_VIEW.clamp_camera_center(
		player.position,
		main.get_viewport_rect().size,
		main.level_camera.zoom.x,
		main.world_size,
	)
	_expect(
		main.level_camera.position.is_equal_approx(expected_camera),
		"%s original character hotkey recenters the camera on that actor" % level_id,
	)

	var move_destination := _nearby_walkable_destination(main, player)
	_expect(
		move_destination != Vector2.INF,
		"%s has a reachable nearby ground-command point" % level_id,
	)
	if move_destination != Vector2.INF:
		await _click_world(main, move_destination)
		_expect(
			not (player.get("movement_path") as PackedVector2Array).is_empty(),
			"%s accepts an actual left-button movement command" % level_id,
		)
		player.call("cancel_path")

	var running_before := bool(player.get("is_running"))
	await _tap_key(KEY_R)
	_expect(
		bool(player.get("is_running")) != running_before,
		"%s R release toggles run/walk" % level_id,
	)
	await _tap_key(KEY_R)
	_expect(
		bool(player.get("is_running")) == running_before,
		"%s second R release restores the movement mode" % level_id,
	)
	var crawling_before := bool(player.get("is_crawling"))
	await _tap_key(KEY_C)
	_expect(
		bool(player.get("is_crawling")) != crawling_before,
		"%s C release toggles standing/crawl" % level_id,
	)
	await _tap_key(KEY_C)
	_expect(
		bool(player.get("is_crawling")) == crawling_before,
		"%s second C release restores the stance" % level_id,
	)

	await _tap_key(KEY_W)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_INVENTORY
			and str(main.game_shell.get("_inventory_mode")) == "weapons",
		"%s W opens the real weapon grid" % level_id,
	)
	await _tap_key(KEY_W)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_NONE,
		"%s second W closes the weapon grid" % level_id,
	)
	await _tap_key(KEY_A)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_INVENTORY
			and str(main.game_shell.get("_inventory_mode")) == "items",
		"%s A opens the real item grid" % level_id,
	)
	await _tap_key(KEY_A)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_NONE,
		"%s second A closes the item grid" % level_id,
	)

	await _tap_key(KEY_M)
	_expect(
		main.game_shell.is_tactical_map_visible(),
		"%s M release opens the live minimap" % level_id,
	)
	await _tap_key(KEY_M)
	_expect(
		not main.game_shell.is_tactical_map_visible(),
		"%s second M release closes the minimap" % level_id,
	)
	await _tap_key(KEY_F1)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_HELP,
		"%s F1 release opens the control guide" % level_id,
	)
	await _tap_key(KEY_F1)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_NONE,
		"%s second F1 release closes the guide" % level_id,
	)
	await _tap_key(KEY_ESCAPE)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_PAUSE,
		"%s Esc release opens the game menu" % level_id,
	)
	await _tap_key(KEY_ESCAPE)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_NONE,
		"%s second Esc release resumes play" % level_id,
	)

	var enemy: Node2D = _first_living_enemy(main)
	var observed_scene := -1
	var buried_scene := -1
	if enemy != null:
		observed_scene = int(enemy.get("scene_index"))
		await _tap_key(KEY_S)
		_expect(
			bool(main.get("sight_target_pending")),
			"%s S release arms the contextual sight cursor" % level_id,
		)
		await _click_world(main, enemy.position)
		_expect(
			main.get("sight_observation_target") == enemy
				and not bool(main.get("sight_target_pending")),
			"%s clicking a live enemy commits sight observation once" % level_id,
		)

		if player_selection_key != KEY_NONE:
			await _tap_key(player_selection_key)
		var direct_weapon_keycode := _first_direct_weapon_keycode(player)
		if direct_weapon_keycode != KEY_NONE:
			await _tap_key(direct_weapon_keycode)
		var active_weapon := ""
		var active_attack_type := int(
			(player.get("weapon_profile") as Dictionary).get("attack_type", 0)
		)
		if player.get("combat_inventory") != null:
			active_weapon = str(
				player.get("combat_inventory").call("active_weapon_key")
			)
		await _click_world(main, enemy.position)
		var issued_target: Variant = player.get("combat_target")
		var direct_attack_issued: bool = (
			issued_target is Node2D
			and is_instance_valid(issued_target)
			and bool((issued_target as Node2D).get("is_alive"))
			and int((issued_target as Node2D).get("faction_id")) == 1
		)
		var special_command_issued: bool = (
			active_attack_type in [8, 10]
			and (
				not main.legacy_deployment_targets.is_empty()
				or issued_target is Node2D
			)
		)
		_expect(
			active_weapon.is_empty()
				or direct_attack_issued
				or special_command_issued,
			(
				"%s ordinary enemy click submits the selected weapon attack "
				+ "(weapon=%s type=%d target=%s deployments=%d)"
			)
			% [
				level_id,
				active_weapon,
				active_attack_type,
				str(issued_target),
				main.legacy_deployment_targets.size(),
			],
		)
		player.call("clear_combat_target")

		enemy.call("take_damage", 1_000_000, player)
		await process_frame
		if is_instance_valid(enemy) and not bool(enemy.get("is_alive")):
			buried_scene = int(enemy.get("scene_index"))
			player.position = enemy.position
			player.call("cancel_path")
			await _tap_key(KEY_B)
			_expect(
				bool(main.get("burial_mode")),
				"%s B release arms the contextual burial cursor" % level_id,
			)
			await _click_world(main, enemy.position)
			_expect(
				main.get("burial_target") == enemy
					and not bool(main.get("burial_mode")),
				"%s corpse click starts the timed burial command once" % level_id,
			)
			for _tick: int in range(102):
				main.call("_advance_burial_command_world_tick")
			_expect(
				main.buried_enemy_scene_indices.has(buried_scene)
					and not enemy.visible,
				"%s burial completes only after the recovered >100 tick limit"
					% level_id,
			)

	if player_selection_key != KEY_NONE:
		await _tap_key(player_selection_key)
	player = main.units[0]
	var saved_position := player.position
	await _tap_key(KEY_F5, true)
	_expect(
		main.save_store.has_slot("quick"),
		"%s Ctrl+F5 creates the isolated physical quick-save slot" % level_id,
	)
	player.position += Vector2(23.0, 17.0)
	await _tap_key(KEY_F9, true)
	_disable_autonomous_world(main)
	_expect(
		str(main.current_mission.get("id", "")) == level_id,
		"%s Ctrl+F9 reloads the same mission" % level_id,
	)
	player = main.units[0]
	_expect(
		player.position.distance_to(saved_position) <= 0.01,
		"%s Ctrl+F9 restores the saved actor position" % level_id,
	)

	var expected_failure := _trigger_primary_failure(main, level_id)
	await process_frame
	_expect(
		main.current_mission_state.is_failed()
			and str(main.current_mission_state.failure_id) == expected_failure,
		"%s reaches its primary failure through the product runtime" % level_id,
	)
	_expect(
		int(main.game_shell.get("overlay_mode")) == OVERLAY_FAILURE
			and main.game_shell.is_failure_open(),
		"%s failure automatically opens the grey failure menu" % level_id,
	)
	# FAILURE renders the original TextureButton surface; the modern Button is
	# owned by the hidden secondary menu and cannot receive keyboard focus here.
	var restart_button := (
		main.game_shell.get("_failure_restart_button") as BaseButton
	)
	_expect(
		restart_button != null and restart_button.is_visible_in_tree(),
		"%s visible original failure menu owns a restart button" % level_id,
	)
	if restart_button != null:
		restart_button.grab_focus()
		await _tap_key(KEY_ENTER)
		_disable_autonomous_world(main)
		_expect(
			str(main.current_mission.get("id", "")) == level_id
				and not main.current_mission_state.is_failed()
				and int(main.game_shell.get("overlay_mode")) == OVERLAY_NONE,
			(
				"%s Enter on the focused original restart control starts a fresh "
				+ "mission (mission=%s, failed=%s, overlay=%d)"
			)
				% [
					level_id,
					str(main.current_mission.get("id", "")),
					str(main.current_mission_state.is_failed()),
					int(main.game_shell.get("overlay_mode")),
				],
		)

	trace_records.append(
		{
			"level_id": level_id,
			"selected_player_scene": selected_player_scene,
			"selection_keycode": int(player_selection_key),
			"observed_enemy_scene": observed_scene,
			"buried_enemy_scene": buried_scene,
			"physical_quicksave": true,
			"primary_failure": expected_failure,
			"keyboard_restart": true,
		}
	)


func _trigger_primary_failure(main: Node, level_id: String) -> String:
	if level_id in ["m001", "m007", "m010"]:
		var time_limit := float(main.current_mission.get("time_limit_seconds", 0.0))
		_expect(time_limit > 0.0, "%s declares an original time limit" % level_id)
		main.mission_runtime.advance_time(time_limit + 1.0)
		return "time_limit"
	if level_id == "m000":
		for escort_value: Variant in main.escorts:
			var escort := escort_value as Node2D
			if main._is_required_escort_scene(int(escort.get("scene_index"))):
				escort.call("take_damage", 1_000_000, null)
				return "required_character_lost"
		_expect(false, "m000 exposes a living required rescue actor")
		return "required_character_lost"
	for unit_value: Variant in main.units:
		var unit := unit_value as Node2D
		if bool(unit.get("is_alive")):
			unit.call("take_damage", 1_000_000, null)
			return "required_character_lost"
	_expect(false, "%s exposes a living required player for failure" % level_id)
	return "required_character_lost"


func _nearby_walkable_destination(main: Node, player: Node2D) -> Vector2:
	for offset: Vector2 in [
		Vector2(128.0, 0.0),
		Vector2(0.0, 64.0),
		Vector2(-128.0, 0.0),
		Vector2(0.0, -64.0),
		Vector2(128.0, 64.0),
		Vector2(-128.0, 64.0),
	]:
		var route: PackedVector2Array = main.navigation_grid.find_path(
			player.position,
			player.position + offset,
		)
		if route.size() >= 2:
			return route[-1]
	return Vector2.INF


func _original_character_hotkey(main: Node, player: Node2D) -> Key:
	var display_name := str(player.get("display_name"))
	for slot_index: int in range(
		min(main.PLAYABLE_SQUAD.size(), ORIGINAL_CHARACTER_HOTKEYS.size())
	):
		if str(main.PLAYABLE_SQUAD[slot_index].get("name", "")) == display_name:
			return ORIGINAL_CHARACTER_HOTKEYS[slot_index]
	return KEY_NONE


func _first_living_enemy(main: Node):
	for enemy_value: Variant in main.enemies:
		var enemy := enemy_value as Node2D
		if not bool(enemy.get("is_alive")) or int(enemy.get("faction_id")) != 1:
			continue
		if main.legacy_door_at_world_point(enemy.position) != null:
			continue
		var overlaps_player := false
		for unit_value: Variant in main.units:
			var unit := unit_value as Node2D
			if (
				bool(unit.get("is_alive"))
				and unit.call("contains_parent_point", enemy.position)
			):
				overlaps_player = true
				break
		if not overlaps_player:
			return enemy
	return null


func _first_direct_weapon_keycode(player: Node) -> Key:
	if player.get("combat_inventory") == null:
		return KEY_NONE
	var key_by_attack_type := {
		4: KEY_1,
		7: KEY_2,
		5: KEY_3,
		6: KEY_4,
		1: KEY_5,
		2: KEY_6,
		3: KEY_7,
	}
	var inventory: Variant = player.get("combat_inventory")
	for action_key_value: Variant in inventory.call("registered_weapon_keys"):
		var profile: Dictionary = inventory.call(
			"weapon_profile",
			str(action_key_value),
		)
		var attack_type := int(profile.get("attack_type", 0))
		if key_by_attack_type.has(attack_type):
			return key_by_attack_type[attack_type] as Key
	return KEY_NONE


func _requested_level_id() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--journey-level="):
			var requested := argument.trim_prefix("--journey-level=").to_lower()
			if requested in LEVEL_IDS:
				return requested
	return ""


func _disable_autonomous_world(main: Node) -> void:
	if main.mission_direction_runtime != null:
		main.mission_direction_runtime.free()
		main.mission_direction_runtime = null
	if main.mission_ai_coordinator != null:
		main.mission_ai_coordinator.free()
		main.mission_ai_coordinator = null
	for actor_value: Variant in (
		main.units + main.enemies + main.escorts + main.ambient_units
	):
		var actor := actor_value as Node
		actor.set_process(false)
		actor.set_physics_process(false)


func _tap_key(keycode: Key, ctrl_pressed: bool = false) -> void:
	_push_key(keycode, true, ctrl_pressed)
	await process_frame
	_push_key(keycode, false, ctrl_pressed)
	await process_frame


func _push_key(keycode: Key, pressed: bool, ctrl_pressed: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.ctrl_pressed = ctrl_pressed
	root.push_input(event)
	submitted_input_events += 1


func _click_world(main: Node, world_position: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = main.get_global_transform_with_canvas() * world_position
	root.push_input(click, true)
	submitted_input_events += 1
	await process_frame
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	submitted_input_events += 1
	await process_frame


func _load_journey_spec() -> Dictionary:
	if not FileAccess.file_exists(JOURNEY_SPEC_PATH):
		_expect(false, "the versioned product-input journey specification exists")
		return {}
	var file := FileAccess.open(JOURNEY_SPEC_PATH, FileAccess.READ)
	if file == null:
		_expect(false, "the versioned product-input journey specification opens")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "the product-input journey specification parses")
	return parsed as Dictionary if parsed is Dictionary else {}


func _cleanup_test_save_directory() -> void:
	var absolute_directory := ProjectSettings.globalize_path(save_directory)
	var expected_root := ProjectSettings.globalize_path(
		"user://qa-real-input-campaign"
	)
	if (
		absolute_directory.is_empty()
		or expected_root.is_empty()
		or absolute_directory.get_base_dir().simplify_path()
			!= expected_root.simplify_path()
	):
		_expect(false, "isolated save cleanup remains inside its exact QA root")
		return
	var directory := DirAccess.open(absolute_directory)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute_directory.path_join(file_name))
			file_name = directory.get_next()
		directory.list_dir_end()
		DirAccess.remove_absolute(absolute_directory)


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
