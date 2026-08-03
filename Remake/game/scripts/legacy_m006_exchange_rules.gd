class_name LegacyM006ExchangeRules
extends RefCounted

## Mission-7 document exchange recovered from M1937.exe.
##
## sub_459840 lets runtime actor 15 place item/actor 101 when the first
## runtime actor 100 is within 32 world units. sub_4596E0 then lets runtime
## actor 22 pursue that world actor while it is within 256 world units.

const MISSION_ID := "m006"
const ENGINE_MISSION_NUMBER := 7
const DOCUMENT_ITEM_ID := 101
const DOCUMENT_WORLD_ACTOR_TYPE := 101
const DOCUMENT_WORLD_GFL_INDEX := 246

const CARRIER_SCENE_INDEX := 1457
const CARRIER_RUNTIME_ACTOR_TYPE := 15
const RECIPIENT_SCENE_INDEX := 1460
const RECIPIENT_RUNTIME_ACTOR_TYPE := 22
const EXIT_DETECTOR_SCENE_INDEX := 1462
const EXIT_DETECTOR_RUNTIME_ACTOR_TYPE := 100

const HANDOFF_RADIUS := 32.0
const RECIPIENT_CHASE_RADIUS := 256.0
const DROP_OFFSET := Vector2(-16.0, 0.0)


static func is_mission(mission_id: String) -> bool:
	return mission_id == MISSION_ID


static func can_carrier_place_document(
	mission_id: String,
	carrier_alive: bool,
	carrier_runtime_actor_type: int,
	carrier_has_document: bool,
	carrier_position: Vector2,
	exit_runtime_actor_type: int,
	exit_position: Vector2,
) -> bool:
	return (
		is_mission(mission_id)
		and carrier_alive
		and carrier_runtime_actor_type == CARRIER_RUNTIME_ACTOR_TYPE
		and carrier_has_document
		and exit_runtime_actor_type == EXIT_DETECTOR_RUNTIME_ACTOR_TYPE
		and carrier_position.distance_to(exit_position) <= HANDOFF_RADIUS
	)


static func can_recipient_pursue_document(
	mission_id: String,
	recipient_alive: bool,
	recipient_runtime_actor_type: int,
	recipient_has_document: bool,
	recipient_position: Vector2,
	document_available: bool,
	document_actor_type: int,
	document_position: Vector2,
) -> bool:
	return (
		is_mission(mission_id)
		and recipient_alive
		and recipient_runtime_actor_type == RECIPIENT_RUNTIME_ACTOR_TYPE
		and not recipient_has_document
		and document_available
		and document_actor_type == DOCUMENT_WORLD_ACTOR_TYPE
		and recipient_position.distance_to(document_position)
			<= RECIPIENT_CHASE_RADIUS
	)
