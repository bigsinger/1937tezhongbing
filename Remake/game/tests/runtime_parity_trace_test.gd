extends SceneTree

const TRACE_SCRIPT: Script = preload("res://scripts/runtime_parity_trace.gd")

var check_count := 0


class FakeMissionState:
	extends RefCounted

	var completed := {"rescue_father": false}
	var progress := {"rescue_family": 0}
	var elapsed_seconds := 1.25
	var failure_id := ""

	func is_victory() -> bool:
		return false

	func is_failed() -> bool:
		return false


class FakeActor:
	extends Node2D

	var display_name := ""
	var scene_index := -1
	var faction_id := 0
	var target_position := Vector2.ZERO
	var original_direction_index := 0
	var animation_group_index := 0
	var animation_frame_index := 0
	var movement_path_index := 0
	var is_alive := true
	var selected := false
	var is_crawling := false
	var is_running := true
	var current_hit_points := 8
	var maximum_hit_points := 8
	var weapon_profile := {"attack_type": 2, "action_key": "rifle_attack"}
	var magazine_ammo := 5
	var reserve_ammo := 10
	var infinite_ammo := false
	var combat_action := 0
	var behavior_state := 0
	var current_target: Node2D
	var movement_path := PackedVector2Array()
	var patrol_wait_remaining := 0.0

	func inventory_snapshot() -> Dictionary:
		return {
			"items": {43: 1},
			"weapons": {"rifle_attack": {"magazine": magazine_ammo}},
		}


class FakeMain:
	extends Node2D

	var units: Array = []
	var escorts: Array = []
	var ambient_units: Array = []
	var enemies: Array = []
	var selected_units: Array = []
	var level_camera: Camera2D
	var world_size := Vector2(4960.0, 2240.0)
	var imported_entity_count := 1572
	var playable_entities := {"强子": {}, "彭鑫": {}}
	var world_entities_by_scene := {
		1436: {"database_entry_id": 924},
		1427: {"database_entry_id": 923},
		1500: {"database_entry_id": 350},
		1621: {"database_entry_id": 888},
	}
	var current_mission := {"id": "m000"}
	var current_mission_state := FakeMissionState.new()


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	var main := FakeMain.new()
	root.add_child(main)
	main.level_camera = Camera2D.new()
	main.level_camera.position = Vector2(241.0, 51.0)
	main.level_camera.zoom = Vector2.ONE
	main.add_child(main.level_camera)

	var second_player := _actor("彭鑫", 1427, 3, Vector2(4176.0, 1128.0), 2)
	var primary := _actor("强子", 1436, 3, Vector2(241.0, 51.0), 5)
	var enemy := _actor("敌军", 1500, 1, Vector2(400.0, 300.0), 7)
	enemy.behavior_state = 2
	enemy.current_target = primary
	var ambient := _actor("d鸡", 1621, 2, Vector2(336.0, 1000.0), 1)
	main.add_child(second_player)
	main.add_child(primary)
	main.add_child(enemy)
	main.add_child(ambient)
	main.units = [primary, second_player]
	main.enemies = [enemy]
	main.ambient_units = [ambient]
	main.selected_units = [primary]

	var trace = TRACE_SCRIPT.new()
	trace.configure(
		"synthetic",
		"m000",
		1,
		1,
		"m000-basic-movement-v1",
		"runtime trace unit fixture",
	)
	var ready: Dictionary = trace.capture_main(
		"gameplay_ready",
		main,
		100.0,
		{"phase": "ready"},
	)
	primary.target_position = Vector2(656.0, 616.0)
	primary.position = Vector2(300.0, 120.0)
	primary.original_direction_index = 4
	trace.capture_main("move_outbound_observed", main, 1900.0)

	_expect(
		int(trace.document.get("schema_version", 0)) == 1
		and str(trace.document.get("content_profile", ""))
		== TRACE_SCRIPT.CONTENT_PROFILE,
		"trace declares the shared stable-MOD content profile",
		failures,
	)
	var actors := ready.get("actors", []) as Array
	_expect(
		actors.size() == 4
		and int((actors[0] as Dictionary).get("scene_index", -1)) == 1427
		and int((actors[1] as Dictionary).get("scene_index", -1)) == 1436
		and int((actors[2] as Dictionary).get("scene_index", -1)) == 1500
		and int((actors[3] as Dictionary).get("scene_index", -1)) == 1621,
		"actors are canonically ordered by original VWF scene index",
		failures,
	)
	var primary_record := actors[1] as Dictionary
	_expect(
		str(primary_record.get("actor_id", "")) == "scene:1436"
		and int(primary_record.get("database_entry_id", 0)) == 924
		and bool(primary_record.get("selected", false)),
		"player identity, DBL entry, and selection state remain observable",
		failures,
	)
	var weapon := primary_record.get("weapon", {}) as Dictionary
	var inventory := primary_record.get("inventory", {}) as Dictionary
	_expect(
		int(weapon.get("attack_type", 0)) == 2
		and int(weapon.get("magazine_ammo", 0)) == 5
		and inventory.has("items"),
		"weapon, ammunition, and inventory are captured in one checkpoint",
		failures,
	)
	var enemy_record := actors[2] as Dictionary
	var enemy_native := enemy_record.get("native", {}) as Dictionary
	_expect(
		int(enemy_native.get("contact_state", 0)) == 1
		and int(enemy_native.get("target_lost", 1)) == 0
		and int(enemy_native.get("interest_scene_index", -1)) == 1436
		and int(enemy_native.get("target_scene_index", -1)) == 1436,
		"native enemy contact retains the live stable-MOD target identity",
		failures,
	)
	var ambient_record := actors[3] as Dictionary
	_expect(
		str(ambient_record.get("role", "")) == "escort"
		and int(ambient_record.get("database_entry_id", 0)) == 888
		and int(ambient_record.get("faction_id", 0)) == 2,
		"live ambient actors use the MOD trace role convention and keep DBL identity",
		failures,
	)
	var mission := ready.get("mission", {}) as Dictionary
	_expect(
		str(mission.get("id", "")) == "m000"
		and str(mission.get("status", "")) == "active"
		and (mission.get("completed", {}) as Dictionary).has("rescue_father"),
		"mission identity and objective state are captured",
		failures,
	)
	var checkpoints := trace.document.get("checkpoints", []) as Array
	_expect(
		checkpoints.size() == 2
		and int((checkpoints[1] as Dictionary).get("sequence", -1)) == 1
		and (
			((checkpoints[1] as Dictionary).get("actors", []) as Array)[1]
			as Dictionary
		).get("position", []) == [300.0, 120.0],
		"later checkpoints preserve sequence and changed actor state",
		failures,
	)

	var output_root := (
		ProjectSettings.globalize_path("user://runtime-parity-trace-test").simplify_path()
	)
	var output_path := output_root.path_join("trace.json")
	_expect(
		trace.write_to_file(output_path) == OK
		and FileAccess.get_file_as_string(output_path).contains("\"m000-basic-movement-v1\""),
		"trace serializes as portable JSON",
		failures,
	)
	main.free()

	if failures.is_empty():
		print("Runtime parity trace tests passed (%d checks)." % check_count)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _actor(
	display_name: String,
	scene_index: int,
	faction_id: int,
	position: Vector2,
	facing_direction: int,
) -> FakeActor:
	var actor := FakeActor.new()
	actor.display_name = display_name
	actor.scene_index = scene_index
	actor.faction_id = faction_id
	actor.position = position
	actor.target_position = position
	actor.original_direction_index = facing_direction
	return actor


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
