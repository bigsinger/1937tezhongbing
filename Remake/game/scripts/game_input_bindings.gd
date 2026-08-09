class_name GameInputBindings
extends RefCounted

const LOCALIZATION_SERVICE_SCRIPT: Script = preload(
	"res://scripts/localization_service.gd"
)

const LEGACY_INPUT_RULES: Script = preload("res://scripts/legacy_input_rules.gd")

## Original-game compatible keyboard mapping.  The order is also used by the
## settings screen, so it deliberately follows the 2001 help-page grouping.
const DEFINITIONS: Array[Dictionary] = [
	{"action": "pause", "label_key": "INPUT_PAUSE", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_ESCAPE},
	{"action": "guide", "label_key": "INPUT_GUIDE", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_F1},
	{"action": "select_1", "label_key": "INPUT_SELECT_1", "category_id": "squad", "category_key": "INPUT_CATEGORY_SQUAD", "keycode": KEY_F2},
	{"action": "select_2", "label_key": "INPUT_SELECT_2", "category_id": "squad", "category_key": "INPUT_CATEGORY_SQUAD", "keycode": KEY_F3},
	{"action": "select_3", "label_key": "INPUT_SELECT_3", "category_id": "squad", "category_key": "INPUT_CATEGORY_SQUAD", "keycode": KEY_F4},
	{"action": "select_4", "label_key": "INPUT_SELECT_4", "category_id": "squad", "category_key": "INPUT_CATEGORY_SQUAD", "keycode": KEY_F5},
	{"action": "select_5", "label_key": "INPUT_SELECT_5", "category_id": "squad", "category_key": "INPUT_CATEGORY_SQUAD", "keycode": KEY_F6},
	{"action": "briefing", "label_key": "INPUT_BRIEFING", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_F7},
	{"action": "toggle_run", "label_key": "INPUT_TOGGLE_RUN", "category_id": "movement", "category_key": "INPUT_CATEGORY_MOVEMENT", "keycode": KEY_R},
	{"action": "toggle_crawl", "label_key": "INPUT_TOGGLE_CRAWL", "category_id": "movement", "category_key": "INPUT_CATEGORY_MOVEMENT", "keycode": KEY_C},
	{"action": "weapon_inventory", "label_key": "INPUT_WEAPON_INVENTORY", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_W},
	{"action": "item_inventory", "label_key": "INPUT_ITEM_INVENTORY", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_A},
	{"action": "sight_mode", "label_key": "INPUT_SIGHT_MODE", "category_id": "movement", "category_key": "INPUT_CATEGORY_MOVEMENT", "keycode": KEY_S},
	{"action": "burial_mode", "label_key": "INPUT_BURIAL_MODE", "category_id": "movement", "category_key": "INPUT_CATEGORY_MOVEMENT", "keycode": KEY_B},
	{"action": "minimap", "label_key": "INPUT_MINIMAP", "category_id": "interface", "category_key": "INPUT_CATEGORY_INTERFACE", "keycode": KEY_M},
	{"action": "tactical_pause", "label_key": "INPUT_TACTICAL_PAUSE", "category_id": "tactics", "category_key": "INPUT_CATEGORY_TACTICS", "keycode": KEY_SPACE},
	# The original executable treats either held key as the same force-target
	# modifier. They remain separate bindings so both defaults and both user
	# remaps stay reachable without inventing an unsupported chord list format.
	{"action": "force_target_ctrl", "label_key": "INPUT_FORCE_TARGET_CTRL", "category_id": "targeting", "category_key": "INPUT_CATEGORY_TARGETING", "keycode": KEY_CTRL, "held_only": true},
	{"action": "force_target_up", "label_key": "INPUT_FORCE_TARGET_UP", "category_id": "targeting", "category_key": "INPUT_CATEGORY_TARGETING", "keycode": KEY_UP, "held_only": true},
	{"action": "weapon_1", "label_key": "WEAPON_DAGGER", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_1},
	{"action": "weapon_2", "label_key": "WEAPON_SLINGSHOT", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_2},
	{"action": "weapon_3", "label_key": "WEAPON_BROADSWORD", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_3},
	{"action": "weapon_4", "label_key": "WEAPON_THROWING_KNIFE", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_4},
	{"action": "weapon_5", "label_key": "WEAPON_PISTOL", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_5},
	{"action": "weapon_6", "label_key": "WEAPON_RIFLE", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_6},
	{"action": "weapon_7", "label_key": "WEAPON_MACHINE_GUN", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_7},
	{"action": "weapon_8", "label_key": "WEAPON_LAND_MINE", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_8},
	{"action": "weapon_9", "label_key": "WEAPON_GRENADE", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_9},
	{"action": "weapon_10", "label_key": "WEAPON_EXPLOSIVES", "category_id": "weapon", "category_key": "INPUT_CATEGORY_WEAPON", "keycode": KEY_0},
	{"action": "interact", "label_key": "INPUT_INTERACT", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_E},
	{"action": "reload", "label_key": "INPUT_RELOAD", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_Q},
	{"action": "detonate", "label_key": "INPUT_DETONATE", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_F},
	{"action": "cycle_weapon", "label_key": "INPUT_CYCLE_WEAPON", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_TAB},
	# Plain F5 belongs to the fourth playable actor in the original mapping.
	# Save/load therefore use a modifier and remain accessible from the menu.
	{"action": "quick_save", "label_key": "INPUT_QUICK_SAVE", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_F5, "ctrl": true},
	{"action": "quick_load", "label_key": "INPUT_QUICK_LOAD", "category_id": "extended", "category_key": "INPUT_CATEGORY_EXTENDED", "keycode": KEY_F9, "ctrl": true},
]


static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = DEFINITIONS.duplicate(true)
	for definition: Dictionary in result:
		var action := str(definition.get("action", ""))
		definition["label"] = _translated(str(definition.get("label_key", "")))
		definition["category"] = _translated(str(definition.get("category_key", "")))
		definition["trigger_phase"] = (
			LEGACY_INPUT_RULES.trigger_phase_for_action(action)
			if is_original_action(action)
			else LEGACY_INPUT_RULES.PHASE_PRESS
		)
		definition["legacy_scan_code"] = (
			LEGACY_INPUT_RULES.direct_input_scan_code_for_action(action)
			if is_original_action(action)
			else -1
		)
	return result


static func action_ids() -> Array[String]:
	var result: Array[String] = []
	for definition: Dictionary in DEFINITIONS:
		result.append(str(definition["action"]))
	return result


static func is_original_action(action: String) -> bool:
	for definition: Dictionary in DEFINITIONS:
		if str(definition["action"]) == action:
			return str(definition.get("category_id", "")) != "extended"
	return false


static func should_trigger_for_event(action: String, event: InputEventKey) -> bool:
	if is_original_action(action):
		return LEGACY_INPUT_RULES.should_trigger_for_event(action, event)
	return not action.is_empty() and not event.echo and event.pressed


static func default_bindings() -> Dictionary:
	var result := {}
	for definition: Dictionary in DEFINITIONS:
		result[str(definition["action"])] = {
			"keycode": int(definition["keycode"]),
			"ctrl": bool(definition.get("ctrl", false)),
			"alt": bool(definition.get("alt", false)),
			"shift": bool(definition.get("shift", false)),
			"meta": bool(definition.get("meta", false)),
		}
	return result


static func normalize_bindings(raw_bindings: Variant) -> Dictionary:
	var normalized := default_bindings()
	if not raw_bindings is Dictionary:
		return normalized
	var raw := raw_bindings as Dictionary
	for action: String in action_ids():
		var raw_binding: Variant = raw.get(action)
		if not raw_binding is Dictionary:
			continue
		var binding := raw_binding as Dictionary
		var keycode_value: Variant = binding.get("keycode")
		if not keycode_value is int and not keycode_value is float:
			continue
		var keycode := int(keycode_value)
		if keycode <= 0:
			continue
		normalized[action] = {
			"keycode": keycode,
			"ctrl": bool(binding.get("ctrl", false)) if binding.get("ctrl") is bool else false,
			"alt": bool(binding.get("alt", false)) if binding.get("alt") is bool else false,
			"shift": bool(binding.get("shift", false)) if binding.get("shift") is bool else false,
			"meta": bool(binding.get("meta", false)) if binding.get("meta") is bool else false,
		}
	return normalized


static func binding_from_event(event: InputEventKey) -> Dictionary:
	var resolved_keycode := int(event.keycode)
	if resolved_keycode <= 0:
		resolved_keycode = int(event.physical_keycode)
	return {
		"keycode": resolved_keycode,
		# A modifier used as the primary key is not also a modifier chord. This
		# keeps rebinding Ctrl alone stable and displays it as Ctrl, not Ctrl+Ctrl.
		"ctrl": event.ctrl_pressed and resolved_keycode != KEY_CTRL,
		"alt": event.alt_pressed and resolved_keycode != KEY_ALT,
		"shift": event.shift_pressed and resolved_keycode != KEY_SHIFT,
		"meta": event.meta_pressed and resolved_keycode != KEY_META,
	}


static func event_matches(event: InputEventKey, binding: Dictionary) -> bool:
	var event_keycode := int(event.keycode)
	if event_keycode <= 0:
		event_keycode = int(event.physical_keycode)
	return (
		event_keycode == int(binding.get("keycode", 0))
		and (event.ctrl_pressed and event_keycode != KEY_CTRL) == bool(binding.get("ctrl", false))
		and (event.alt_pressed and event_keycode != KEY_ALT) == bool(binding.get("alt", false))
		and (event.shift_pressed and event_keycode != KEY_SHIFT) == bool(binding.get("shift", false))
		and (event.meta_pressed and event_keycode != KEY_META) == bool(binding.get("meta", false))
	)


static func action_is_held(
	action: String,
	bindings: Dictionary,
	pressed_keycodes: Variant = null,
) -> bool:
	var value: Variant = bindings.get(action)
	if not value is Dictionary:
		return false
	return binding_is_held(value as Dictionary, pressed_keycodes)


static func binding_is_held(binding: Dictionary, pressed_keycodes: Variant = null) -> bool:
	var keycode := int(binding.get("keycode", 0))
	if keycode <= 0 or not _key_is_held(keycode, pressed_keycodes):
		return false
	for modifier: Dictionary in [
		{"field": "ctrl", "keycode": KEY_CTRL},
		{"field": "alt", "keycode": KEY_ALT},
		{"field": "shift", "keycode": KEY_SHIFT},
		{"field": "meta", "keycode": KEY_META},
	]:
		if bool(binding.get(str(modifier["field"]), false)):
			if not _key_is_held(int(modifier["keycode"]), pressed_keycodes):
				return false
	return true


static func _key_is_held(keycode: int, pressed_keycodes: Variant) -> bool:
	if pressed_keycodes is Dictionary:
		var injected := pressed_keycodes as Dictionary
		return bool(injected.get(keycode, injected.get(str(keycode), false)))
	return Input.is_key_pressed(keycode) or Input.is_physical_key_pressed(keycode)


static func action_for_event(event: InputEventKey, bindings: Dictionary) -> String:
	for definition: Dictionary in DEFINITIONS:
		var action := str(definition["action"])
		var value: Variant = bindings.get(action)
		if value is Dictionary and event_matches(event, value as Dictionary):
			return action
	return ""


static func conflicting_action(
	bindings: Dictionary,
	binding: Dictionary,
	except_action: String = "",
) -> String:
	for action: String in action_ids():
		if action == except_action:
			continue
		var other: Variant = bindings.get(action)
		if other is Dictionary and bindings_equal(other as Dictionary, binding):
			return action
	return ""


static func bindings_equal(first: Dictionary, second: Dictionary) -> bool:
	return (
		int(first.get("keycode", 0)) == int(second.get("keycode", 0))
		and bool(first.get("ctrl", false)) == bool(second.get("ctrl", false))
		and bool(first.get("alt", false)) == bool(second.get("alt", false))
		and bool(first.get("shift", false)) == bool(second.get("shift", false))
		and bool(first.get("meta", false)) == bool(second.get("meta", false))
	)


static func display_text(binding: Dictionary) -> String:
	var parts: Array[String] = []
	if bool(binding.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(binding.get("alt", false)):
		parts.append("Alt")
	if bool(binding.get("shift", false)):
		parts.append("Shift")
	if bool(binding.get("meta", false)):
		parts.append("Meta")
	var key_name := OS.get_keycode_string(int(binding.get("keycode", 0)))
	parts.append(key_name if not key_name.is_empty() else _translated("INPUT_UNSET"))
	return "+".join(parts)


static func label_for_action(action: String) -> String:
	for definition: Dictionary in DEFINITIONS:
		if str(definition["action"]) == action:
			return _translated(str(definition.get("label_key", "")))
	return action


static func _translated(key: String) -> String:
	if key.is_empty():
		return ""
	return str(LOCALIZATION_SERVICE_SCRIPT.translate_key(key))
