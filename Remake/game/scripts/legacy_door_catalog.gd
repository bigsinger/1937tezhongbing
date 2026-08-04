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

## Visible openings which are not two-state doors in the original resources.
## Their sprites depict an already-open arch or doorway, but the VWF retains
## an encoded Layer 2/3 footprint for the decorative scene object.  Treating
## these objects as ordinary scenery makes the opening look usable while A*
## sees a wall.  Keep them separate from interactive doors so no fake open
## animation or save-game state is introduced.
const PERMANENT_PASSAGE_PROFILES_BY_DATABASE_ENTRY_ID := {
	69: {"name": "doorway", "release_sight": true},
	98: {"name": "courtyard_arch_a", "release_sight": true},
	99: {"name": "courtyard_arch_b", "release_sight": true},
	413: {"name": "wall_doorway_e", "release_sight": true},
	420: {"name": "bank_gate_a", "release_sight": true},
	421: {"name": "bank_gate_b", "release_sight": true},
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


static func permanent_passage_profile_for_entity(entity: Dictionary) -> Dictionary:
	var database_entry_id := int(entity.get("database_entry_id", 0))
	var value: Variant = (
		PERMANENT_PASSAGE_PROFILES_BY_DATABASE_ENTRY_ID.get(
			database_entry_id,
			{},
		)
	)
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var result := (value as Dictionary).duplicate(true)
	result["database_entry_id"] = database_entry_id
	result["source_status"] = "authored_open_visual_navigation_passage"
	return result


static func is_permanent_navigation_passage(database_entry_id: int) -> bool:
	return PERMANENT_PASSAGE_PROFILES_BY_DATABASE_ENTRY_ID.has(
		database_entry_id
	)


static func local_source_cells_for_passage(
	entity: Dictionary,
	texture_size: Vector2,
	source_navigation: RefCounted,
	layer_id: int,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if (
		entity.is_empty()
		or texture_size.x <= 0.0
		or texture_size.y <= 0.0
		or source_navigation == null
		or not source_navigation.has_method("source_cells_for_scene")
	):
		return result
	var scene_index := int(entity.get("scene_index", -1))
	if scene_index < 0:
		return result
	var world_position := Vector2(
		float(entity.get("reference_x", entity.get("x", 0.0))),
		float(entity.get("reference_y", entity.get("y", 0.0))),
	)
	var sprite_anchor := texture_size * 0.5
	var raw_anchor: Variant = entity.get("sprite_anchor", {})
	if raw_anchor is Dictionary:
		var anchor := raw_anchor as Dictionary
		sprite_anchor = Vector2(
			float(anchor.get("x", sprite_anchor.x)),
			float(anchor.get("y", sprite_anchor.y)),
		)
	var visual_rect := Rect2(world_position - sprite_anchor, texture_size)
	var cell_size: Vector2i = source_navigation.get("cell_size")
	if cell_size.x <= 0 or cell_size.y <= 0:
		return result
	# Scene indices are reused by a few historical map records.  Only release
	# cells intersecting this concrete visual; blindly releasing every encoded
	# cell for the same number can punch a second hole far across the map.
	var padded_visual_rect := visual_rect.grow(
		maxf(float(cell_size.x), float(cell_size.y)) * 0.5
	)
	for source_cell: Vector2i in source_navigation.call(
		"source_cells_for_scene",
		layer_id,
		scene_index,
	) as Array[Vector2i]:
		var cell_rect := Rect2(
			Vector2(source_cell * cell_size),
			Vector2(cell_size),
		)
		if padded_visual_rect.intersects(cell_rect):
			result.append(source_cell)
	result.sort()
	return result
