class_name LegacyDynamicWorldItemCatalog
extends RefCounted

## Original ground SPR previews used by runtime-created backpack items.
## DBL runtime type and GFL identity were recovered from 1937Database.dbl and
## 1937Resources.GFL. These are world sprites, not inventory-panel icons.

const WORLD_GFL_BY_ITEM_ID := {
	33: 2,    # chicken
	46: 373,  # ammunition box
	47: 249,  # medicine box
	48: 241,  # canned meat
	49: 245,  # doll
	50: 247,  # watermelon
	51: 238,  # herb
	52: 242,  # wine bottle
	54: 243,  # uniform box
	82: 240,  # dog bone
	83: 248,  # cigarettes
	101: 246, # document bag
}


static func world_gfl_index(item_id: int) -> int:
	return int(WORLD_GFL_BY_ITEM_ID.get(item_id, 0))


static func supports_item(item_id: int) -> bool:
	return WORLD_GFL_BY_ITEM_ID.has(item_id)


static func supported_item_ids() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in WORLD_GFL_BY_ITEM_ID.keys():
		result.append(int(value))
	result.sort()
	return result
