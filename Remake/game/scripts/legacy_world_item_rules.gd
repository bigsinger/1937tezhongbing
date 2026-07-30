class_name LegacyWorldItemRules
extends RefCounted

## Exact world-item interaction rules recovered from M1937.exe.
##
## Evidence:
## - sub_45B080 builds the per-runtime-type acceptance list at actor +0x230.
## - sub_45C550 scans world actors in insertion order and accepts only status 3
##   actors in original directional visibility band 1 with unobstructed LOS.
## - sub_456AB0 transfers the world actor and invokes sub_458270 for faction 1.
## - sub_458270 applies the item effects below.
## - sub_45C710 advances the recovered counters.

const ENEMY_FACTION_ID := 1
const WORLD_TARGET_STATUS := 3
const NAVIGATION_CELL_SIZE := Vector2i(32, 16)

const CHICKEN_ITEM_ID := 33
const CANNED_MEAT_ITEM_ID := 48
const HYPNOSIS_DOLL_ITEM_ID := 49
const POISONED_WINE_ITEM_ID := 52
const DOG_BONE_ITEM_ID := 82
const CIGARETTE_ITEM_ID := 83

const HYPNOSIS_COUNTER_LIMIT := 600
const POISON_COUNTER_LIMIT := 80
const POISON_DAMAGE := 16
const DISTRACTION_MINIMUM_LIMIT := 80
const DISTRACTION_RANDOM_SPAN := 40

const ACCEPTED_ITEMS_BY_RUNTIME_ACTOR_TYPE := {
	4: [POISONED_WINE_ITEM_ID],
	5: [
		POISONED_WINE_ITEM_ID,
		CHICKEN_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	6: [
		POISONED_WINE_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	7: [
		POISONED_WINE_ITEM_ID,
		CHICKEN_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	11: [
		POISONED_WINE_ITEM_ID,
		CIGARETTE_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	12: [POISONED_WINE_ITEM_ID],
	15: [
		POISONED_WINE_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
	],
	21: [
		POISONED_WINE_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	23: [
		POISONED_WINE_ITEM_ID,
		CHICKEN_ITEM_ID,
		CIGARETTE_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
	],
	56: [DOG_BONE_ITEM_ID],
}


static func accepted_item_ids(
	runtime_actor_type: int,
	faction_id: int = ENEMY_FACTION_ID,
) -> Array[int]:
	var result: Array[int] = []
	if faction_id != ENEMY_FACTION_ID:
		return result
	var raw_value: Variant = ACCEPTED_ITEMS_BY_RUNTIME_ACTOR_TYPE.get(
		runtime_actor_type,
		[],
	)
	if raw_value is Array:
		for item_value: Variant in raw_value as Array:
			result.append(int(item_value))
	return result


static func accepts_item(
	runtime_actor_type: int,
	item_id: int,
	faction_id: int = ENEMY_FACTION_ID,
) -> bool:
	return item_id in accepted_item_ids(runtime_actor_type, faction_id)


static func is_original_lure_item(item_id: int) -> bool:
	return item_id in [
		CHICKEN_ITEM_ID,
		CANNED_MEAT_ITEM_ID,
		HYPNOSIS_DOLL_ITEM_ID,
		POISONED_WINE_ITEM_ID,
		DOG_BONE_ITEM_ID,
		CIGARETTE_ITEM_ID,
	]


static func effect_profile(item_id: int) -> Dictionary:
	match item_id:
		HYPNOSIS_DOLL_ITEM_ID:
			return {
				"kind": "hypnosis",
				"consume_after_collection": true,
				"counter_limit": HYPNOSIS_COUNTER_LIMIT,
			}
		POISONED_WINE_ITEM_ID:
			return {
				"kind": "poison_and_distraction",
				"consume_after_collection": true,
				"poison_counter_limit": POISON_COUNTER_LIMIT,
				"poison_damage": POISON_DAMAGE,
			}
		DOG_BONE_ITEM_ID, CIGARETTE_ITEM_ID:
			return {
				"kind": "distraction",
				"consume_after_collection": false,
			}
		CHICKEN_ITEM_ID, CANNED_MEAT_ITEM_ID:
			return {
				"kind": "carry",
				"consume_after_collection": false,
			}
	return {}


static func is_adjacent_navigation_cell(
	actor_position: Vector2,
	target_position: Vector2,
) -> bool:
	var actor_cell := Vector2i(
		floori(actor_position.x / float(NAVIGATION_CELL_SIZE.x)),
		floori(actor_position.y / float(NAVIGATION_CELL_SIZE.y)),
	)
	var target_cell := Vector2i(
		floori(target_position.x / float(NAVIGATION_CELL_SIZE.x)),
		floori(target_position.y / float(NAVIGATION_CELL_SIZE.y)),
	)
	var difference := actor_cell - target_cell
	return absi(difference.x) <= 1 and absi(difference.y) <= 1


static func msvc_rand_step(state: int) -> int:
	return int((state * 214013 + 2531011) & 0x7fffffff)


static func msvc_rand_value(state_after_step: int) -> int:
	return int((state_after_step >> 16) & 0x7fff)


static func distraction_limit_from_state(state: int) -> Dictionary:
	var next_state := msvc_rand_step(state)
	return {
		"state": next_state,
		"limit": (
			msvc_rand_value(next_state) % DISTRACTION_RANDOM_SPAN
			+ DISTRACTION_MINIMUM_LIMIT
		),
	}
