class_name LegacyMediaRouteCatalog
extends RefCounted

## Generated from SDK/media-routes.json. Do not edit.
const CATALOG_ID := "original-media-routes-v1"
const MOVIE_PLAYER_BLOCKS := true
const EXECUTABLE_SVT_STRING_COUNT := 2
const DIRECT_MOVIE_CALL_COUNT := 2
const INTER_LEVEL_MOVIE_COUNT := 0
const ENDING_SELECTOR_LEVEL := 13
const ENDING_DISMISSAL_NEXT_SELECTOR_LEVEL := 1
const STARTUP_SEQUENCE: Array[Dictionary] = [
    {"order": 0, "id": "logo", "role": "publisher_logo", "source_filename": "GameKingLogo.SVT", "source_disk_filename": "GamekingLogo.svt", "source_string_rva": 0x000CF78C, "call_rva": 0x00007635, "player_argument_1": 0, "player_argument_2": 0, "source_width": 640, "source_height": 480, "duration_seconds": 10.396733, "converted_relative_path": "media/video/logo.ogv"},
    {"order": 1, "id": "historical_intro", "role": "historical_intro", "source_filename": "1937Intro.SVT", "source_disk_filename": "1937Intro.svt", "source_string_rva": 0x000CF77C, "call_rva": 0x00007644, "player_argument_1": 0, "player_argument_2": 100, "source_width": 640, "source_height": 240, "duration_seconds": 139.916667, "converted_relative_path": "media/video/historical_intro.ogv"},
]
const LEVEL_BRIEFINGS: Array[Dictionary] = [
    {"selector_level": 1, "level_id": "m000", "resource_name": "Intro_000.psd", "gfl_index": 1048, "converted_relative_path": "iblock/1048.png"},
    {"selector_level": 2, "level_id": "m001", "resource_name": "Intro_001.psd", "gfl_index": 1049, "converted_relative_path": "iblock/1049.png"},
    {"selector_level": 3, "level_id": "m002", "resource_name": "Intro_002.psd", "gfl_index": 1050, "converted_relative_path": "iblock/1050.png"},
    {"selector_level": 4, "level_id": "m003", "resource_name": "Intro_003.psd", "gfl_index": 1051, "converted_relative_path": "iblock/1051.png"},
    {"selector_level": 5, "level_id": "m004", "resource_name": "Intro_004.psd", "gfl_index": 1052, "converted_relative_path": "iblock/1052.png"},
    {"selector_level": 6, "level_id": "m005", "resource_name": "Intro_005.psd", "gfl_index": 1053, "converted_relative_path": "iblock/1053.png"},
    {"selector_level": 7, "level_id": "m006", "resource_name": "Intro_006.psd", "gfl_index": 1054, "converted_relative_path": "iblock/1054.png"},
    {"selector_level": 8, "level_id": "m007", "resource_name": "Intro_007.psd", "gfl_index": 1055, "converted_relative_path": "iblock/1055.png"},
    {"selector_level": 9, "level_id": "m008", "resource_name": "Intro_008.psd", "gfl_index": 1056, "converted_relative_path": "iblock/1056.png"},
    {"selector_level": 10, "level_id": "m009", "resource_name": "Intro_009.psd", "gfl_index": 1057, "converted_relative_path": "iblock/1057.png"},
    {"selector_level": 11, "level_id": "m010", "resource_name": "Intro_010.psd", "gfl_index": 1058, "converted_relative_path": "iblock/1058.png"},
    {"selector_level": 12, "level_id": "m011", "resource_name": "Intro_011.psd", "gfl_index": 1059, "converted_relative_path": "iblock/1059.png"},
]
const ENDING_IMAGES: Array[Dictionary] = [
    {"target_width": 640, "resource_name": "Intro_012640.psd", "resource_string_rva": 0x000CF3A8, "gfl_index": 1061, "converted_relative_path": "iblock/1061.png"},
    {"target_width": 800, "resource_name": "Intro_012800.psd", "resource_string_rva": 0x000CF3BC, "gfl_index": 1062, "converted_relative_path": "iblock/1062.png"},
    {"target_width": 1024, "resource_name": "Intro_0121024.psd", "resource_string_rva": 0x000CF3D0, "gfl_index": 1060, "converted_relative_path": "iblock/1060.png"},
]

static func startup_sequence() -> Array[Dictionary]:
    return STARTUP_SEQUENCE.duplicate(true)

static func briefing_for_level(level_id: String) -> Dictionary:
    for entry: Dictionary in LEVEL_BRIEFINGS:
        if str(entry.get("level_id", "")) == level_id:
            return entry.duplicate(true)
    return {}

static func ending_for_target_width(target_width: int) -> Dictionary:
    var best: Dictionary = {}
    var best_distance := 0x7fffffff
    for entry: Dictionary in ENDING_IMAGES:
        var distance := absi(int(entry.get("target_width", 0)) - target_width)
        if distance < best_distance:
            best_distance = distance
            best = entry
    return best.duplicate(true)
