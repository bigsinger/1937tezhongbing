class_name LegacySoundRouteCatalog
extends RefCounted

## Generated from SDK/sound-routes.json. Do not edit.
const SLF_ENTRY_COUNT := 126
const SPRITE_GROUP_PARAMETER_INDEX := 8
const AUDITED_SPRITE_COUNT := 980
const AUDITED_GROUP_COUNT := 2775
const SOUNDED_GROUP_COUNT := 1137
const UI_BUTTON_ZERO_BASED_INDEX := 124
const UI_BUTTON_GFL_INDEX := 1393
const GLOBAL_ALARM_ZERO_BASED_INDEX := 125
const GLOBAL_ALARM_GFL_INDEX := 1324
const GLOBAL_ALARM_UPDATE_COUNTER_LIMIT := 240
const GLOBAL_ALARM_ACTIVE_REQUEST_UPDATES := 241
const SPRITE_GROUP_ONE_BASED_INDICES: Array[int] = [1, 3, 4, 5, 6, 8, 9, 10, 13, 15, 16, 17, 18, 20, 21, 22, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35, 36, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 59, 60, 61, 126]
const ACTOR_VOICE_ZERO_BASED_INDICES: Array[int] = [63, 65, 66, 70, 74, 75, 78, 79, 83, 86, 87, 88, 89, 90, 91, 92, 93, 94, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122]
const REACHABLE_ZERO_BASED_INDICES: Array[int] = [0, 2, 3, 4, 5, 7, 8, 9, 12, 14, 15, 16, 17, 19, 20, 21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 58, 59, 60, 63, 65, 66, 70, 74, 75, 78, 79, 83, 86, 87, 88, 89, 90, 91, 92, 93, 94, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 124, 125]
const ASSET_ONLY_ZERO_BASED_INDICES: Array[int] = [1, 6, 10, 11, 13, 18, 22, 28, 36, 57, 61, 62, 64, 67, 68, 69, 71, 72, 73, 76, 77, 80, 81, 82, 84, 85, 95, 100, 109, 119, 123]
const AUDITED_ENVIRONMENT_ENTRIES: Array[Dictionary] = [
    {"zero_based_index": 10, "one_based_index": 11, "gfl_index": 1277, "category": "vehicle", "event_key": "boat", "resource_name": "船01.wav", "reachability": "asset_only"},
    {"zero_based_index": 11, "one_based_index": 12, "gfl_index": 1278, "category": "vehicle", "event_key": "boat", "resource_name": "船02.wav", "reachability": "asset_only"},
    {"zero_based_index": 12, "one_based_index": 13, "gfl_index": 1279, "category": "animal", "event_key": "dog", "resource_name": "喘气（狗）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 15, "one_based_index": 16, "gfl_index": 1293, "category": "animal", "event_key": "pig", "resource_name": "低吼（猪）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 16, "one_based_index": 17, "gfl_index": 1294, "category": "animal", "event_key": "chicken", "resource_name": "动作（鸡）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 17, "one_based_index": 18, "gfl_index": 1295, "category": "vehicle", "event_key": "handcart", "resource_name": "独轮车.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 20, "one_based_index": 21, "gfl_index": 1318, "category": "animal", "event_key": "seagull", "resource_name": "海鸥01.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 21, "one_based_index": 22, "gfl_index": 1319, "category": "vehicle", "event_key": "train", "resource_name": "火车.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 22, "one_based_index": 23, "gfl_index": 1320, "category": "vehicle", "event_key": "train", "resource_name": "火车蒸汽.wav", "reachability": "asset_only"},
    {"zero_based_index": 23, "one_based_index": 24, "gfl_index": 1321, "category": "vehicle", "event_key": "train", "resource_name": "火车蒸汽01.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 24, "one_based_index": 25, "gfl_index": 1322, "category": "animal", "event_key": "dog", "resource_name": "惊吓（狗）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 25, "one_based_index": 26, "gfl_index": 1323, "category": "animal", "event_key": "chicken", "resource_name": "惊吓（鸡）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 26, "one_based_index": 27, "gfl_index": 1334, "category": "animal", "event_key": "cattle", "resource_name": "鸣叫（牛）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 27, "one_based_index": 28, "gfl_index": 1335, "category": "vehicle", "event_key": "motorcycle", "resource_name": "摩托车.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 28, "one_based_index": 29, "gfl_index": 1336, "category": "vehicle", "event_key": "motorcycle", "resource_name": "摩托车02.wav", "reachability": "asset_only"},
    {"zero_based_index": 30, "one_based_index": 31, "gfl_index": 1340, "category": "vehicle", "event_key": "car", "resource_name": "汽车01.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 31, "one_based_index": 32, "gfl_index": 1341, "category": "vehicle", "event_key": "car", "resource_name": "汽车02.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 32, "one_based_index": 33, "gfl_index": 1342, "category": "vehicle", "event_key": "car", "resource_name": "汽车03.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 33, "one_based_index": 34, "gfl_index": 1343, "category": "vehicle", "event_key": "car", "resource_name": "汽车04.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 60, "one_based_index": 61, "gfl_index": 1307, "category": "animal", "event_key": "dog", "resource_name": "攻击（军犬）.wav", "reachability": "sprite_group_queued"},
    {"zero_based_index": 61, "one_based_index": 62, "gfl_index": 1391, "category": "ambience", "event_key": "rain", "resource_name": "雨声02.wav", "reachability": "asset_only"},
    {"zero_based_index": 100, "one_based_index": 101, "gfl_index": 1333, "category": "ambience", "event_key": "thunder", "resource_name": "雷声.wav", "reachability": "asset_only"},
    {"zero_based_index": 123, "one_based_index": 124, "gfl_index": 1390, "category": "ambience", "event_key": "rain", "resource_name": "雨声.wav", "reachability": "asset_only"},
    {"zero_based_index": 124, "one_based_index": 125, "gfl_index": 1393, "category": "ui", "event_key": "ui_confirm", "resource_name": "按钮.wav", "reachability": "ui_button_immediate"},
    {"zero_based_index": 125, "one_based_index": 126, "gfl_index": 1324, "category": "alert", "event_key": "alert", "resource_name": "警报.wav", "reachability": "sprite_group_and_general_queued"},
]

static func is_reachable_zero_based(index: int) -> bool:
    return REACHABLE_ZERO_BASED_INDICES.has(index)

static func is_asset_only_zero_based(index: int) -> bool:
    return ASSET_ONLY_ZERO_BASED_INDICES.has(index)

static func environment_entry(index: int) -> Dictionary:
    for entry: Dictionary in AUDITED_ENVIRONMENT_ENTRIES:
        if int(entry.get("zero_based_index", -1)) == index:
            return entry.duplicate(true)
    return {}
