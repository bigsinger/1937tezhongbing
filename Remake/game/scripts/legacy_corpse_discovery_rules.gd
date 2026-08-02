class_name LegacyCorpseDiscoveryRules
extends RefCounted

## Exact corpse-discovery branch recovered from M1937.exe.
##
## Evidence:
## - sub_45C4C0 scans the world actor array in insertion order.
## - A candidate must be faction 1, dead (+0x188 == 1), and not previously
##   discovered (+0x258 == 0).
## - The observer must see the corpse in original directional band 2 and pass
##   the ordinary line-of-sight test.
## - sub_45C710 marks the corpse once, enters contact state 3, raises the
##   global alarm and reuses actor+0x248 as the initial reaction limit.
## - While state 3 is stationary, 0x5CB60 consumes rand()%3 every update;
##   value 2 repeats the fixed hostile alert voice. On completion the voice is
##   unconditional and 0x5CB9C draws the next rand()%40+40 search delay.
## - sub_45E2A0 creates two runtime-type-6 soldiers at the nearest live
##   runtime-type-93 reinforcement marker.

const ENEMY_FACTION_ID := 1
const REQUIRED_VISIBILITY_BAND := 2
const REACTION_MINIMUM_LIMIT := 40
const REACTION_RANDOM_SPAN := 40
const ALERT_ANIMATION_RANDOM_MODULUS := 3
const REINFORCEMENT_MARKER_ACTOR_TYPE := 93
const REINFORCEMENT_ACTOR_TYPE := 6
const REINFORCEMENT_COUNT := 2


static func is_candidate(
	faction_id: int,
	is_alive: bool,
	already_discovered: bool,
	is_buried: bool,
) -> bool:
	return (
		faction_id == ENEMY_FACTION_ID
		and not is_alive
		and not already_discovered
		and not is_buried
	)


static func reaction_limit_from_state(state: int) -> Dictionary:
	var next_state := int((state * 214013 + 2531011) & 0x7fffffff)
	var random_value := int((next_state >> 16) & 0x7fff)
	return {
		"state": next_state,
		"random_value": random_value,
		"limit": reaction_limit_from_random_value(random_value),
	}


static func reaction_limit_from_random_value(random_value: int) -> int:
	return (
		random_value % REACTION_RANDOM_SPAN
		+ REACTION_MINIMUM_LIMIT
	)


static func alert_animation_plays_from_random_value(
	random_value: int,
) -> bool:
	return random_value % ALERT_ANIMATION_RANDOM_MODULUS > 1


static func reaction_has_completed(counter: int, limit: int) -> bool:
	return counter > limit
