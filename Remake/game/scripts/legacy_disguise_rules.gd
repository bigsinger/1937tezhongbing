class_name LegacyDisguiseRules
extends RefCounted

## Recovered from M1937.exe sub_450200, sub_459290, sub_459370,
## sub_45EA70 and sub_45EE00.  Gu Ming is rebuilt as runtime actor 91 when
## changing into the Japanese uniform; the original actor containers and hit
## points survive that replacement.
const NORMAL_RUNTIME_ACTOR_TYPE := 10
const DISGUISED_RUNTIME_ACTOR_TYPE := 91
const NORMAL_GFL_INDEX := 270
const DISGUISED_GFL_INDEX := 272
const PLAYER_FACTION_ID := 3
const DISGUISED_FACTION_ID := 1
const UNIFORM_ITEM_ID := 54
const CIVILIAN_CLOTHING_ITEM_ID := 92
const SPECIAL_ATTENTION_ITEM_ID := 99
const SPECIAL_ATTENTION_ATTACK_TYPE := 11
const DISGUISE_APPEARANCE_STATE := 100
const CHANGE_TICK_LIMIT := 100
const RECOVERY_TICK_LIMIT := 100
const ORIGINAL_ACTOR_TICK_SECONDS := 1.0 / 30.0
const OBSERVER_ALERT_RADIUS := 640.0
const CLOSE_DETECTION_RADIUS := 128.0

## Types 4 and 12 take the alternate live-target scan which admits type 91
## even though its current faction is 1.
const ORDINARY_IDENTIFYING_ACTOR_TYPES := [4, 12]


static func transition_for(
	runtime_actor_type: int,
	item_id: int,
) -> Dictionary:
	if (
		runtime_actor_type == NORMAL_RUNTIME_ACTOR_TYPE
		and item_id == UNIFORM_ITEM_ID
	):
		return {
			"from_runtime_actor_type": NORMAL_RUNTIME_ACTOR_TYPE,
			"to_runtime_actor_type": DISGUISED_RUNTIME_ACTOR_TYPE,
			"to_gfl_index": DISGUISED_GFL_INDEX,
			"to_faction_id": DISGUISED_FACTION_ID,
			"consume_backpack_item_id": UNIFORM_ITEM_ID,
			"grant_backpack_item_id": CIVILIAN_CLOTHING_ITEM_ID,
			"grant_weapon_item_id": SPECIAL_ATTENTION_ITEM_ID,
			"remove_weapon_item_id": 0,
			"appearance_state": DISGUISE_APPEARANCE_STATE,
		}
	if (
		runtime_actor_type == DISGUISED_RUNTIME_ACTOR_TYPE
		and item_id == CIVILIAN_CLOTHING_ITEM_ID
	):
		return {
			"from_runtime_actor_type": DISGUISED_RUNTIME_ACTOR_TYPE,
			"to_runtime_actor_type": NORMAL_RUNTIME_ACTOR_TYPE,
			"to_gfl_index": NORMAL_GFL_INDEX,
			"to_faction_id": PLAYER_FACTION_ID,
			"consume_backpack_item_id": CIVILIAN_CLOTHING_ITEM_ID,
			"grant_backpack_item_id": UNIFORM_ITEM_ID,
			"grant_weapon_item_id": 0,
			"remove_weapon_item_id": SPECIAL_ATTENTION_ITEM_ID,
			"appearance_state": 0,
		}
	return {}


static func can_begin_transition(
	runtime_actor_type: int,
	item_id: int,
) -> bool:
	return not transition_for(runtime_actor_type, item_id).is_empty()


static func attack_can_break_disguise(
	runtime_actor_type: int,
	attack_type: int,
) -> bool:
	# The type-91 SPR exposes pistol and dagger attack actions. sub_456DF0 calls
	# sub_45EA70 only from the corresponding type-1/type-4 dispatch paths.
	return (
		runtime_actor_type == DISGUISED_RUNTIME_ACTOR_TYPE
		and attack_type in [1, 4]
	)


static func is_disguised_target(
	target_runtime_actor_type: int,
	target_faction_id: int,
) -> bool:
	return (
		target_runtime_actor_type == DISGUISED_RUNTIME_ACTOR_TYPE
		and target_faction_id == DISGUISED_FACTION_ID
	)


static func disguise_detection_mode(
	observer_runtime_actor_type: int,
	mission_number: int,
	observer_position: Vector2,
	target_position: Vector2,
) -> String:
	if observer_runtime_actor_type in ORDINARY_IDENTIFYING_ACTOR_TYPES:
		return "ordinary_vision"
	if (
		mission_number == 2
		and observer_runtime_actor_type in [19, 26]
		and _inside_isometric_ellipse(
			observer_position,
			target_position,
			CLOSE_DETECTION_RADIUS,
			CLOSE_DETECTION_RADIUS * 0.5,
		)
	):
		return "close_without_los"
	if (
		mission_number == 6
		and observer_runtime_actor_type == 24
		and observer_position.distance_to(target_position)
			< CLOSE_DETECTION_RADIUS
	):
		return "close_without_los"
	if (
		mission_number == 8
		and observer_runtime_actor_type == 18
		and _inside_isometric_ellipse(
			observer_position,
			target_position,
			CLOSE_DETECTION_RADIUS,
			CLOSE_DETECTION_RADIUS * 0.5,
		)
	):
		return "close_without_los"
	return ""


static func _inside_isometric_ellipse(
	origin: Vector2,
	target: Vector2,
	horizontal_radius: float,
	vertical_radius: float,
) -> bool:
	if horizontal_radius <= 0.0 or vertical_radius <= 0.0:
		return false
	var delta := target - origin
	return (
		(delta.x * delta.x) / (horizontal_radius * horizontal_radius)
		+ (delta.y * delta.y) / (vertical_radius * vertical_radius)
		<= 1.0
	)
