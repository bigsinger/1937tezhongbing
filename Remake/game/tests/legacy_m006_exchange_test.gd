extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const RULES: Script = preload("res://scripts/legacy_m006_exchange_rules.gd")
const WORLD_CATALOG: Script = preload(
	"res://scripts/legacy_dynamic_world_item_catalog.gd"
)
const GAME_SESSION_STATE: Script = preload(
	"res://scripts/game_session_state.gd"
)

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_recovered_boundaries_and_catalog()
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	main.switch_level(6, false, false)
	_disable_actor_processing(main)
	_test_real_document_exchange(main)
	main.queue_free()
	if failures.is_empty():
		print("Mission-7 document exchange tests passed (%d checks)." % checks)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_recovered_boundaries_and_catalog() -> void:
	_expect(
		RULES.can_carrier_place_document(
			"m006", true, 15, true, Vector2.ZERO, 100, Vector2(32.0, 0.0)
		),
		"carrier handoff includes the native 32-unit boundary",
	)
	_expect(
		not RULES.can_carrier_place_document(
			"m006", true, 15, true, Vector2.ZERO, 100, Vector2(32.01, 0.0)
		),
		"carrier handoff rejects a position outside 32 units",
	)
	_expect(
		RULES.can_recipient_pursue_document(
			"m006", true, 22, false, Vector2.ZERO, true, 101,
			Vector2(256.0, 0.0),
		),
		"recipient pursuit includes the native 256-unit boundary",
	)
	_expect(
		not RULES.can_recipient_pursue_document(
			"m005", true, 22, false, Vector2.ZERO, true, 101,
			Vector2(1.0, 0.0),
		),
		"document exchange is restricted to engine mission 7",
	)
	_expect(
		WORLD_CATALOG.world_gfl_index(101) == 246
		and WORLD_CATALOG.world_gfl_index(46) == 373
		and WORLD_CATALOG.supported_item_ids().size() == 12,
		"dynamic world-item catalog owns the recovered ground SPR identities",
	)


func _test_real_document_exchange(main: Node) -> void:
	_expect(
		str(main.current_mission.get("id", "")) == "m006",
		"real m006 mission graph is active",
	)
	var carrier: Node2D = main.call(
		"_enemy_by_scene_index", RULES.CARRIER_SCENE_INDEX
	)
	var recipient: Node2D = main.call(
		"_enemy_by_scene_index", RULES.RECIPIENT_SCENE_INDEX
	)
	var exit_entity_value: Variant = main.world_entities_by_scene.get(
		RULES.EXIT_DETECTOR_SCENE_INDEX
	)
	_expect(
		carrier != null and recipient != null and exit_entity_value is Dictionary,
		"real m006 resolves carrier, recipient, and exit detector identities",
	)
	if carrier == null or recipient == null or not exit_entity_value is Dictionary:
		return
	var exit_entity := exit_entity_value as Dictionary
	_expect(
		carrier.backpack_inventory != null
		and carrier.backpack_inventory.has_item(RULES.DOCUMENT_ITEM_ID)
		and (
			recipient.backpack_inventory == null
			or not recipient.backpack_inventory.has_item(RULES.DOCUMENT_ITEM_ID)
		),
		"original carrier starts with item 101 and recipient does not",
	)
	var exit_position := Vector2(
		float(exit_entity.get("x", 0.0)),
		float(exit_entity.get("y", 0.0)),
	)
	carrier.position = exit_position + Vector2(512.0, 0.0)
	recipient.set("behavior_state", 0)
	recipient.set("current_target", null)
	main.call(
		"_spawn_original_inventory_pickup",
		recipient.position,
		{
			"original_inventory_kind": "backpack",
			"item_id": RULES.DOCUMENT_ITEM_ID,
			"quantity": 1,
			"quantity_mode": 0,
			"source_scene_index": RULES.CARRIER_SCENE_INDEX,
		},
	)
	var ordinary_document := (main.mission_pickups as Array)[-1] as Node2D
	_expect(
		not bool(main.call("_advance_original_m006_document_exchange"))
		and recipient.get("legacy_world_item_target") == null,
		"type-22 recipient ignores an ordinary item-101 drop before the native gate",
	)
	ordinary_document.call("collect")
	main.call("_unregister_mission_pickup", ordinary_document)
	carrier.position = Vector2(
		exit_position.x,
		exit_position.y,
	)
	main.legacy_crt_random_trace_enabled = true
	main.legacy_crt_random_trace.clear()
	_expect(
		bool(main.call("_advance_original_m006_document_exchange")),
		"carrier proximity commits the native document handoff",
	)
	var document: Node2D = main.call(
		"_first_available_original_world_item",
		RULES.DOCUMENT_WORLD_ACTOR_TYPE,
	)
	_expect(
		document != null
		and not carrier.backpack_inventory.has_item(RULES.DOCUMENT_ITEM_ID)
		and document.position
			== carrier.position + RULES.DROP_OFFSET
		and bool(document.get("original_dynamic_actor_lifecycle"))
		and bool(document.get("original_factory_random_consumed"))
		and bool(
			(document.get("item_payload") as Dictionary).get(
				"m006_native_exchange_document",
				false,
			)
		)
		and (main.legacy_crt_random_trace as Array).size() == 5,
		"handoff creates actor 101 at x-16 after exactly five factory draws",
	)
	if document == null:
		return

	var session: Dictionary = GAME_SESSION_STATE.capture(main)
	var checkpoint_random_state := int(main.legacy_crt_random_state)
	main.switch_level(6, false, false)
	_disable_actor_processing(main)
	var restore_result: Dictionary = GAME_SESSION_STATE.apply_after_level_loaded(
		main,
		session,
	)
	document = main.call(
		"_first_available_original_world_item",
		RULES.DOCUMENT_WORLD_ACTOR_TYPE,
	)
	carrier = main.call("_enemy_by_scene_index", RULES.CARRIER_SCENE_INDEX)
	recipient = main.call("_enemy_by_scene_index", RULES.RECIPIENT_SCENE_INDEX)
	_expect(
		bool(restore_result.get("ok", false))
		and document != null
		and carrier != null
		and recipient != null
		and int(main.legacy_crt_random_state) == checkpoint_random_state
		and not carrier.backpack_inventory.has_item(RULES.DOCUMENT_ITEM_ID),
		"save restoration preserves the placed actor without replaying its factory",
	)
	if document == null or carrier == null or recipient == null:
		return

	recipient.position = document.position
	recipient.set("behavior_state", 0)
	recipient.set("current_target", null)
	recipient.call("cancel_path")
	main.legacy_crt_random_trace.clear()
	_expect(
		bool(main.call("_advance_original_m006_document_exchange"))
		and recipient.get("legacy_world_item_target") == document,
		"type-22 recipient accepts actor 101 through its mission-only target path",
	)
	recipient.call("_update_legacy_world_item_investigation", 0.0)
	_expect(
		recipient.backpack_inventory != null
		and recipient.backpack_inventory.has_item(RULES.DOCUMENT_ITEM_ID)
		and not (main.mission_pickups as Array).has(document)
		and (main.legacy_crt_random_trace as Array).size() == 4,
		"recipient collection transfers item 101 and consumes four destructor draws",
	)

	# Killing the new holder must enrich the exact transferred inventory drop;
	# it must not fabricate a second role item from Sun's old binding.
	recipient.call("take_damage", 1_000_000, carrier)
	var recipient_document_count := 0
	for pickup_value: Variant in main.mission_pickups:
		var pickup := pickup_value as Node2D
		var payload := pickup.get("item_payload") as Dictionary
		if (
			int(payload.get("source_scene_index", -1))
				== RULES.RECIPIENT_SCENE_INDEX
			and int(payload.get("item_id", 0)) == RULES.DOCUMENT_ITEM_ID
			and str(payload.get("item_role", "")) == "m006_name_list"
		):
			recipient_document_count += 1
	_expect(
		recipient_document_count == 1,
		"recipient death exposes exactly one mission-bound document pickup",
	)


func _disable_actor_processing(main: Node) -> void:
	for group_name: String in ["units", "enemies", "escorts", "ambient_units"]:
		for actor_value: Variant in main.get(group_name) as Array:
			var actor := actor_value as Node
			actor.set_process(false)
			actor.set_physics_process(false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
