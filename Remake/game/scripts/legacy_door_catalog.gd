class_name LegacyDoorCatalog
extends RefCounted

## Closed/open visual pairs present in the original GFL/DBL data.
##
## Maps serialize both closed gates and already-open gate sprites.  Both states
## must participate in the same navigation lifecycle: a closed instance starts
## solid and opens on click, while an authored open instance starts permanently
## open and releases the closed-only L2/L3 footprint during level construction.

const PROFILES_BY_CLOSED_DATABASE_ENTRY_ID := {
	175: {"name": "铁丝门-A", "closed_gfl_index": 791, "open_gfl_index": 792, "closed_sprite_relative_path": "sprites/0791.png", "open_sprite_relative_path": "sprites/0792.png", "closed_anchor": [50, 103], "open_anchor": [28, 93], "starts_open": false, "locked_open": false},
	176: {"name": "铁丝门-B", "closed_gfl_index": 793, "open_gfl_index": 794, "closed_sprite_relative_path": "sprites/0793.png", "open_sprite_relative_path": "sprites/0794.png", "closed_anchor": [56, 102], "open_anchor": [22, 91], "starts_open": false, "locked_open": false},
	224: {"name": "大门-A", "closed_gfl_index": 146, "open_gfl_index": 147, "closed_sprite_relative_path": "sprites/0146.png", "open_sprite_relative_path": "sprites/0147.png", "closed_anchor": [71, 79], "open_anchor": [87, 88], "starts_open": false, "locked_open": false},
	225: {"name": "大门-B", "closed_gfl_index": 148, "open_gfl_index": 149, "closed_sprite_relative_path": "sprites/0148.png", "open_sprite_relative_path": "sprites/0149.png", "closed_anchor": [68, 84], "open_anchor": [87, 87], "starts_open": false, "locked_open": false},
	483: {"name": "铁丝高墙大门-A", "closed_gfl_index": 785, "open_gfl_index": 786, "closed_sprite_relative_path": "sprites/0785.png", "open_sprite_relative_path": "sprites/0786.png", "closed_anchor": [69, 151], "open_anchor": [42, 133], "starts_open": false, "locked_open": false},
	485: {"name": "铁丝高墙大门-B", "closed_gfl_index": 787, "open_gfl_index": 788, "closed_sprite_relative_path": "sprites/0787.png", "open_sprite_relative_path": "sprites/0788.png", "closed_anchor": [75, 153], "open_anchor": [31, 130], "starts_open": false, "locked_open": false},
	408: {"name": "围墙门-A", "closed_gfl_index": 837, "open_gfl_index": 839, "closed_sprite_relative_path": "sprites/0837.png", "open_sprite_relative_path": "sprites/0839.png", "closed_anchor": [59, 67], "open_anchor": [68, 95], "starts_open": false, "locked_open": false},
	409: {"name": "围墙门-B", "closed_gfl_index": 838, "open_gfl_index": 839, "closed_sprite_relative_path": "sprites/0838.png", "open_sprite_relative_path": "sprites/0839.png", "closed_anchor": [64, 95], "open_anchor": [68, 95], "starts_open": false, "locked_open": false},
}

## These DBL entries already use the open member of the recovered pair.  They
## previously fell through as ordinary static scenery, leaving eighty visible
## openings blocked in the twelve formal levels.
const PROFILES_BY_OPEN_DATABASE_ENTRY_ID := {
	341: {"name": "大门-A-开", "closed_gfl_index": 146, "open_gfl_index": 147, "closed_sprite_relative_path": "sprites/0146.png", "open_sprite_relative_path": "sprites/0147.png", "closed_anchor": [71, 79], "open_anchor": [87, 88], "starts_open": true, "locked_open": true},
	342: {"name": "大门-B-开", "closed_gfl_index": 148, "open_gfl_index": 149, "closed_sprite_relative_path": "sprites/0148.png", "open_sprite_relative_path": "sprites/0149.png", "closed_anchor": [68, 84], "open_anchor": [87, 87], "starts_open": true, "locked_open": true},
	354: {"name": "铁丝门-A-开", "closed_gfl_index": 791, "open_gfl_index": 792, "closed_sprite_relative_path": "sprites/0791.png", "open_sprite_relative_path": "sprites/0792.png", "closed_anchor": [50, 103], "open_anchor": [28, 93], "starts_open": true, "locked_open": true},
	355: {"name": "铁丝门-B-开", "closed_gfl_index": 793, "open_gfl_index": 794, "closed_sprite_relative_path": "sprites/0793.png", "open_sprite_relative_path": "sprites/0794.png", "closed_anchor": [56, 102], "open_anchor": [22, 91], "starts_open": true, "locked_open": true},
	410: {"name": "围墙门-B-开", "closed_gfl_index": 838, "open_gfl_index": 839, "closed_sprite_relative_path": "sprites/0838.png", "open_sprite_relative_path": "sprites/0839.png", "closed_anchor": [64, 95], "open_anchor": [68, 95], "starts_open": true, "locked_open": true},
	484: {"name": "铁丝高墙大门-A-开", "closed_gfl_index": 785, "open_gfl_index": 786, "closed_sprite_relative_path": "sprites/0785.png", "open_sprite_relative_path": "sprites/0786.png", "closed_anchor": [69, 151], "open_anchor": [42, 133], "starts_open": true, "locked_open": true},
	486: {"name": "铁丝高墙大门-B-开", "closed_gfl_index": 787, "open_gfl_index": 788, "closed_sprite_relative_path": "sprites/0787.png", "open_sprite_relative_path": "sprites/0788.png", "closed_anchor": [75, 153], "open_anchor": [31, 130], "starts_open": true, "locked_open": true},
}


static func profile_for_entity(entity: Dictionary) -> Dictionary:
	var database_entry_id := int(entity.get("database_entry_id", 0))
	var value: Variant = PROFILES_BY_CLOSED_DATABASE_ENTRY_ID.get(
		database_entry_id,
		{},
	)
	if not value is Dictionary or (value as Dictionary).is_empty():
		value = PROFILES_BY_OPEN_DATABASE_ENTRY_ID.get(database_entry_id, {})
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var result := (value as Dictionary).duplicate(true)
	result["database_entry_id"] = database_entry_id
	result["source_status"] = "recovered_visual_pair_modern_navigation_lifecycle"
	return result


static func is_supported_closed_door(database_entry_id: int) -> bool:
	return PROFILES_BY_CLOSED_DATABASE_ENTRY_ID.has(database_entry_id)


static func is_supported_open_passage(database_entry_id: int) -> bool:
	return PROFILES_BY_OPEN_DATABASE_ENTRY_ID.has(database_entry_id)
