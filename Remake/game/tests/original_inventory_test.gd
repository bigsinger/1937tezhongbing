extends SceneTree

const COMBAT_INVENTORY: Script = preload("res://scripts/combat_inventory.gd")
const COMBAT_PROFILES: Script = preload("res://scripts/combat_profiles.gd")
const SQUAD_UNIT: Script = preload("res://scripts/squad_unit.gd")
const ORIGINAL_INVENTORY: Script = preload(
	"res://scripts/original_initial_weapon_inventory.gd"
)

var check_count := 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []
	_test_catalog(failures)
	_test_original_quantity_modes(failures)
	_test_runtime_parity_snapshot(failures)
	_test_snapshot_and_schema_1_migration(failures)
	if failures.is_empty():
		print("Original inventory parity tests passed (%d checks)." % check_count)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_catalog(failures: Array[String]) -> void:
	var catalog: Dictionary = ORIGINAL_INVENTORY.load_catalog()
	_expect(
		ORIGINAL_INVENTORY.validate_catalog(catalog),
		"the recovered 12-level initial inventory catalog validates",
		failures,
	)
	var m000: Dictionary = ORIGINAL_INVENTORY.loadout_for_scene("m000", 1436)
	_expect(
		str(m000.get("display_name", "")) == "强子"
		and int(m000.get("default_attack_type", 0)) == 4,
		"m000 scene 1436 resolves to the exact captured player",
		failures,
	)
	var m000_items := m000.get("items", []) as Array
	_expect(
		m000_items.size() == 2
		and int((m000_items[0] as Dictionary).get("item_id", 0)) == 39
		and int((m000_items[0] as Dictionary).get("quantity_mode", -1)) == 1
		and int((m000_items[1] as Dictionary).get("item_id", 0)) == 36
		and int((m000_items[1] as Dictionary).get("quantity", 0)) == 7,
		"m000 preserves original inventory order, modes and direct bullet count",
		failures,
	)
	_expect(
		ORIGINAL_INVENTORY.loadout_for_scene("m000", 999999).is_empty(),
		"unknown scene identity never receives an invented original loadout",
		failures,
	)
	_expect(
		ORIGINAL_INVENTORY.item_id_for_attack_type(1) == 36
		and ORIGINAL_INVENTORY.item_id_for_attack_type(11) == 99
		and ORIGINAL_INVENTORY.attack_type_for_item_id(45) == 10,
		"all original attack types use their recovered inventory item identity",
		failures,
	)


func _test_original_quantity_modes(failures: Array[String]) -> void:
	var inventory = COMBAT_INVENTORY.new()
	var dagger: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(4)
	var pistol: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(1)
	var dart: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(6)
	_expect(
		inventory.register_original_weapon("dagger_attack", dagger, 1, 1),
		"mode-1 dagger registers",
		failures,
	)
	_expect(
		inventory.register_original_weapon("pistol_attack", pistol, 7, 2),
		"mode-2 pistol registers with seven direct rounds",
		failures,
	)
	_expect(
		inventory.register_original_weapon("dart_attack", dart, 2, 0),
		"mode-0 throwing knife registers with two direct uses",
		failures,
	)
	_expect(
		inventory.consume_attack("dagger_attack")
		and inventory.ammo_item_count(39) == 1,
		"normal mode-1 melee attacks never consume the durable item",
		failures,
	)
	for unused_index: int in range(7):
		_expect(
			inventory.consume_attack("pistol_attack"),
			"each pistol attack directly decrements item 36",
			failures,
		)
	_expect(
		inventory.ammo_item_count(36) == 0
		and not inventory.can_consume_attack("pistol_attack")
		and not inventory.weapon_state("pistol_attack").is_empty()
		and not inventory.needs_reload("pistol_attack")
		and inventory.reload_weapon("pistol_attack") == 0,
		"empty mode-2 firearm remains owned and never enters a reload state",
		failures,
	)
	_expect(
		inventory.add_item(36, 2) == 2
		and inventory.remove_item(36, 2) == 2
		and inventory.ammo_item_count(36) == 0
		and not inventory.weapon_state("pistol_attack").is_empty(),
		"generic direct-count removal also retains an empty mode-2 firearm",
		failures,
	)
	_expect(
		inventory.consume_attack("dart_attack")
		and inventory.consume_attack("dart_attack")
		and inventory.ammo_item_count(41) == 0
		and inventory.weapon_state("dart_attack").is_empty(),
		"mode-0 weapon is removed when its direct quantity reaches zero",
		failures,
	)
	_expect(
		inventory.add_item(41, 3) == 3
		and not inventory.weapon_state("dart_attack").is_empty(),
		"collecting a removed mode-0 item restores its known weapon action",
		failures,
	)


func _test_snapshot_and_schema_1_migration(failures: Array[String]) -> void:
	var inventory = COMBAT_INVENTORY.new()
	inventory.register_original_weapon(
		"pistol_attack",
		COMBAT_PROFILES.weapon_profile_for_attack_type(1),
		7,
		2,
	)
	inventory.consume_attack("pistol_attack")
	var snapshot: Dictionary = inventory.full_snapshot()
	_expect(
		int(snapshot.get("schema_version", 0)) == 2
		and bool(snapshot.get("original_parity", false)),
		"schema 2 marks direct-count original parity explicitly",
		failures,
	)
	var restored = COMBAT_INVENTORY.new()
	_expect(
		restored.restore_snapshot(snapshot)
		and restored.ammo_item_count(36) == 6
		and restored.original_parity_enabled()
		and restored.active_weapon_key() == "pistol_attack",
		"schema-2 save restores direct quantity and active weapon",
		failures,
	)
	var old_profile: Dictionary = COMBAT_PROFILES.weapon_profile_for_attack_type(1)
	var old_state := {
		"action_key": "pistol_attack",
		"profile": old_profile,
		"ammo_item_id": 36,
		"magazine_capacity": 8,
		"magazine": 3,
		"ammo_per_attack": 1,
	}
	var old_snapshot := {
		"schema_version": 1,
		"active_action_key": "pistol_attack",
		"items": {"36": 24},
		"weapons": {"pistol_attack": old_state},
	}
	var migrated = COMBAT_INVENTORY.new()
	_expect(
		migrated.restore_snapshot(old_snapshot)
		and migrated.original_parity_enabled()
		and migrated.ammo_item_count(36) == 27
		and not migrated.needs_reload(),
		"schema-1 magazine plus reserve migrates to one original direct count",
		failures,
	)


func _test_runtime_parity_snapshot(failures: Array[String]) -> void:
	var unit = SQUAD_UNIT.new()
	var empty_groups: Array[Dictionary] = []
	unit.configure_combat(
		3,
		8,
		{},
		empty_groups,
		empty_groups,
		false,
		false,
	)
	_expect(
		unit.register_original_inventory_weapon(
			COMBAT_PROFILES.weapon_profile_for_attack_type(4),
			empty_groups,
			1,
			1,
			true,
		)
		and unit.register_original_inventory_weapon(
			COMBAT_PROFILES.weapon_profile_for_attack_type(1),
			empty_groups,
			7,
			2,
			false,
		),
		"test actor receives the original m000 ordered weapon container",
		failures,
	)
	_expect(
		unit.configure_original_backpack({
			"items": [
				{"item_id": 51, "quantity": 2, "quantity_mode": 0},
				{"item_id": 52, "quantity": 1, "quantity_mode": 1},
			],
		}),
		"test actor receives an ordered original backpack container",
		failures,
	)
	var snapshot: Dictionary = unit.parity_inventory_snapshot()
	var weapons := snapshot.get("weapon_entries", []) as Array
	var items := snapshot.get("item_entries", []) as Array
	_expect(
		int(snapshot.get("schema_version", 0)) == 1
		and int(snapshot.get("active_attack_type", 0)) == 4
		and weapons.size() == 2
		and (weapons[0] as Dictionary)
			== {
				"inventory_index": 0,
				"item_id": 39,
				"quantity": 1,
				"quantity_mode": 1,
			}
		and (weapons[1] as Dictionary)
			== {
				"inventory_index": 1,
				"item_id": 36,
				"quantity": 7,
				"quantity_mode": 2,
			}
		and items.size() == 2
		and int((items[0] as Dictionary).get("inventory_index", -1)) == 0
		and int((items[0] as Dictionary).get("item_id", 0)) == 51
		and int((items[1] as Dictionary).get("inventory_index", -1)) == 1
		and int((items[1] as Dictionary).get("item_id", 0)) == 52,
		"parity snapshot exactly mirrors both recovered ordered containers",
		failures,
	)
	_expect(
		unit.equip_attack_type(1)
		and unit.combat_inventory.consume_active_attack(),
		"test actor performs one original direct-count pistol attack",
		failures,
	)
	snapshot = unit.parity_inventory_snapshot()
	weapons = snapshot.get("weapon_entries", []) as Array
	_expect(
		int(snapshot.get("active_attack_type", 0)) == 1
		and int((weapons[1] as Dictionary).get("quantity", -1)) == 6,
		"parity snapshot observes the post-attack direct ammunition decrement",
		failures,
	)
	unit.free()


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	check_count += 1
	if not condition:
		failures.append(label)
