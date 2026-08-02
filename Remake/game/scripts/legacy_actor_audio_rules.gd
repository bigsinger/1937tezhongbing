class_name LegacyActorAudioRules
extends RefCounted

## Exact actor-voice selectors recovered from M1937.exe and 1937Sound.slf.
##
## sub_45D610/sub_45D7B0/sub_45D900/sub_45DA20/sub_45DA60 were previously
## catalogued as animation selectors. Their callees lead to sub_40B800, which indexes
## the loaded SLF sound array and plays the selected record.  These tables
## preserve both the ordered SLF indices and their non-linear GFL identities.
## Randomized entries consume the process-global MSVCRT stream at the listed
## call-site RVA; an even value selects the first entry and an odd value the
## second.  Fixed entries consume no random value.

const FAMILY_SELECTED := "selected"
const FAMILY_ACKNOWLEDGE := "acknowledge"
const FAMILY_HOSTILE_INITIAL := "hostile_initial_challenge"
const FAMILY_HOSTILE_ALERT := "hostile_corpse_alert"
const FAMILY_HOSTILE_FOLLOWUP := "hostile_followup_challenge"

const AUDIO_CHANNEL := "voice"

const RULES := {
	FAMILY_SELECTED: {
		1: {"random_required": false, "call_site_rva": 0, "slf_indices": [103], "gfl_indices": [1344]},
		2: {"random_required": true, "call_site_rva": 0x0005D64F, "slf_indices": [98, 99], "gfl_indices": [1331, 1332]},
		8: {"random_required": true, "call_site_rva": 0x0005D67C, "slf_indices": [63, 70], "gfl_indices": [1282, 1289]},
		9: {"random_required": true, "call_site_rva": 0x0005D6A9, "slf_indices": [120, 122], "gfl_indices": [1383, 1385]},
		10: {"random_required": true, "call_site_rva": 0x0005D6D6, "slf_indices": [86, 87], "gfl_indices": [1312, 1313]},
		91: {"random_required": true, "call_site_rva": 0x0005D6D6, "slf_indices": [86, 87], "gfl_indices": [1312, 1313]},
	},
	FAMILY_ACKNOWLEDGE: {
		1: {"random_required": true, "call_site_rva": 0x0005D7CF, "slf_indices": [105, 104], "gfl_indices": [1346, 1345]},
		2: {"random_required": true, "call_site_rva": 0x0005D7F8, "slf_indices": [96, 97], "gfl_indices": [1329, 1330]},
		8: {"random_required": true, "call_site_rva": 0x0005D821, "slf_indices": [65, 66], "gfl_indices": [1284, 1285]},
		9: {"random_required": false, "call_site_rva": 0, "slf_indices": [121], "gfl_indices": [1384]},
		10: {"random_required": true, "call_site_rva": 0x0005D855, "slf_indices": [83, 88], "gfl_indices": [1309, 1314]},
		91: {"random_required": true, "call_site_rva": 0x0005D855, "slf_indices": [83, 88], "gfl_indices": [1309, 1314]},
	},
	FAMILY_HOSTILE_INITIAL: {
		4: {"random_required": true, "call_site_rva": 0x0005D921, "slf_indices": [113, 114], "gfl_indices": [1361, 1362]},
		5: {"random_required": false, "call_site_rva": 0, "slf_indices": [107], "gfl_indices": [1354]},
		6: {"random_required": false, "call_site_rva": 0, "slf_indices": [107], "gfl_indices": [1354]},
		7: {"random_required": false, "call_site_rva": 0, "slf_indices": [94], "gfl_indices": [1327]},
		11: {"random_required": false, "call_site_rva": 0, "slf_indices": [107], "gfl_indices": [1354]},
		12: {"random_required": true, "call_site_rva": 0x0005D960, "slf_indices": [90, 91], "gfl_indices": [1316, 1317]},
		13: {"random_required": false, "call_site_rva": 0, "slf_indices": [107], "gfl_indices": [1354]},
		14: {"random_required": false, "call_site_rva": 0, "slf_indices": [107], "gfl_indices": [1354]},
		15: {"random_required": true, "call_site_rva": 0x0005D989, "slf_indices": [117, 118], "gfl_indices": [1380, 1381]},
		21: {"random_required": false, "call_site_rva": 0, "slf_indices": [101], "gfl_indices": [1337]},
		23: {"random_required": true, "call_site_rva": 0x0005D9BD, "slf_indices": [74, 75], "gfl_indices": [1297, 1298]},
	},
	FAMILY_HOSTILE_ALERT: {
		4: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		5: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		6: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		11: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		12: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		13: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
		14: {"random_required": false, "call_site_rva": 0, "slf_indices": [108], "gfl_indices": [1355]},
	},
	FAMILY_HOSTILE_FOLLOWUP: {
		4: {"random_required": true, "call_site_rva": 0x0005DA81, "slf_indices": [111, 112], "gfl_indices": [1359, 1360]},
		5: {"random_required": true, "call_site_rva": 0x0005DAAA, "slf_indices": [106, 110], "gfl_indices": [1353, 1357]},
		6: {"random_required": true, "call_site_rva": 0x0005DAAA, "slf_indices": [106, 110], "gfl_indices": [1353, 1357]},
		7: {"random_required": true, "call_site_rva": 0x0005DAD3, "slf_indices": [92, 93], "gfl_indices": [1325, 1326]},
		11: {"random_required": true, "call_site_rva": 0x0005DAAA, "slf_indices": [106, 110], "gfl_indices": [1353, 1357]},
		12: {"random_required": false, "call_site_rva": 0, "slf_indices": [89], "gfl_indices": [1315]},
		13: {"random_required": true, "call_site_rva": 0x0005DAAA, "slf_indices": [106, 110], "gfl_indices": [1353, 1357]},
		14: {"random_required": true, "call_site_rva": 0x0005DAAA, "slf_indices": [106, 110], "gfl_indices": [1353, 1357]},
		15: {"random_required": true, "call_site_rva": 0x0005DB07, "slf_indices": [115, 116], "gfl_indices": [1378, 1379]},
		21: {"random_required": false, "call_site_rva": 0, "slf_indices": [102], "gfl_indices": [1338]},
		23: {"random_required": true, "call_site_rva": 0x0005DB3B, "slf_indices": [78, 79], "gfl_indices": [1301, 1302]},
	},
}


static func selector_profile(
	family: String,
	runtime_actor_type: int,
	activation_flag: int = 1,
) -> Dictionary:
	# sub_45D610 stores its flag at actor+0x168 but only emits a selection
	# voice when the requested value is exactly one.
	if family == FAMILY_SELECTED and activation_flag != 1:
		return {}
	var family_value: Variant = RULES.get(family)
	if not family_value is Dictionary:
		return {}
	var rule_value: Variant = (family_value as Dictionary).get(
		runtime_actor_type
	)
	if not rule_value is Dictionary:
		return {}
	var result := (rule_value as Dictionary).duplicate(true)
	result["family"] = family
	result["runtime_actor_type"] = runtime_actor_type
	result["event_key"] = "original_actor_%s" % family
	result["channel"] = AUDIO_CHANNEL
	return result


static func select(
	family: String,
	runtime_actor_type: int,
	random_value: int = -1,
	activation_flag: int = 1,
) -> Dictionary:
	var result := selector_profile(
		family,
		runtime_actor_type,
		activation_flag,
	)
	if result.is_empty():
		return {}
	var slf_indices := result.get("slf_indices", []) as Array
	var gfl_indices := result.get("gfl_indices", []) as Array
	if slf_indices.is_empty() or slf_indices.size() != gfl_indices.size():
		return {}
	var variant_index := 0
	if bool(result.get("random_required", false)):
		if random_value < 0 or slf_indices.size() != 2:
			return {}
		variant_index = 0 if random_value % 2 == 0 else 1
	result["variant_index"] = variant_index
	result["random_value"] = random_value
	result["slf_index"] = int(slf_indices[variant_index])
	result["gfl_index"] = int(gfl_indices[variant_index])
	return result


static func gfl_indices_for(
	family: String,
	runtime_actor_type: int,
	activation_flag: int = 1,
) -> Array[int]:
	var profile := selector_profile(
		family,
		runtime_actor_type,
		activation_flag,
	)
	var result: Array[int] = []
	for raw_index: Variant in profile.get("gfl_indices", []) as Array:
		var gfl_index := int(raw_index)
		if not result.has(gfl_index):
			result.append(gfl_index)
	return result


static func all_gfl_indices() -> Array[int]:
	var result: Array[int] = []
	for family_value: Variant in RULES.values():
		for rule_value: Variant in (family_value as Dictionary).values():
			for raw_index: Variant in (
				(rule_value as Dictionary).get("gfl_indices", []) as Array
			):
				var gfl_index := int(raw_index)
				if not result.has(gfl_index):
					result.append(gfl_index)
	result.sort()
	return result
