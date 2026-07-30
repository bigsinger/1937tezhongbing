class_name LegacyDoorCatalog
extends RefCounted

## Closed/open visual pairs present in the original GFL/DBL data.
##
## The original maps serialize the open and closed sprites as separate static
## objects. The remake's click-to-open transition is an explicit modern
## interaction, while its visual replacement and L2/L3 scene footprint come
## directly from the original assets and VWF layers.

const PROFILES_BY_CLOSED_DATABASE_ENTRY_ID := {
	175: {
		"name": "铁丝门-A",
		"closed_gfl_index": 791,
		"open_gfl_index": 792,
		"open_sprite_relative_path": "sprites/0792.png",
		"closed_anchor": [50, 103],
		"open_anchor": [28, 93],
	},
	176: {
		"name": "铁丝门-B",
		"closed_gfl_index": 793,
		"open_gfl_index": 794,
		"open_sprite_relative_path": "sprites/0794.png",
		"closed_anchor": [56, 102],
		"open_anchor": [22, 91],
	},
	224: {
		"name": "大门-A",
		"closed_gfl_index": 146,
		"open_gfl_index": 147,
		"open_sprite_relative_path": "sprites/0147.png",
		"closed_anchor": [71, 79],
		"open_anchor": [87, 88],
	},
	225: {
		"name": "大门-B",
		"closed_gfl_index": 148,
		"open_gfl_index": 149,
		"open_sprite_relative_path": "sprites/0149.png",
		"closed_anchor": [68, 84],
		"open_anchor": [87, 87],
	},
	483: {
		"name": "铁丝高墙大门-A",
		"closed_gfl_index": 785,
		"open_gfl_index": 786,
		"open_sprite_relative_path": "sprites/0786.png",
		"closed_anchor": [69, 151],
		"open_anchor": [42, 133],
	},
	485: {
		"name": "铁丝高墙大门-B",
		"closed_gfl_index": 787,
		"open_gfl_index": 788,
		"open_sprite_relative_path": "sprites/0788.png",
		"closed_anchor": [75, 153],
		"open_anchor": [31, 130],
	},
	409: {
		"name": "围墙门-B-关",
		"closed_gfl_index": 838,
		"open_gfl_index": 839,
		"open_sprite_relative_path": "sprites/0839.png",
		"closed_anchor": [64, 95],
		"open_anchor": [68, 95],
	},
}


static func profile_for_entity(entity: Dictionary) -> Dictionary:
	var database_entry_id := int(entity.get("database_entry_id", 0))
	var value: Variant = PROFILES_BY_CLOSED_DATABASE_ENTRY_ID.get(
		database_entry_id,
		{},
	)
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var result := (value as Dictionary).duplicate(true)
	result["closed_database_entry_id"] = database_entry_id
	result["source_status"] = "mixed_recovered_visual_editorial_interaction"
	return result


static func is_supported_closed_door(database_entry_id: int) -> bool:
	return PROFILES_BY_CLOSED_DATABASE_ENTRY_ID.has(database_entry_id)
