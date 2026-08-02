#pragma once

// Generated from SDK/media-routes.json. Do not edit.
#include <array>
#include <cstdint>

namespace m1937::sdk::media {

inline constexpr bool movie_player_blocks = true;
inline constexpr int executable_svt_string_count = 2;
inline constexpr int direct_movie_call_count = 2;
inline constexpr int inter_level_movie_count = 0;
inline constexpr int ending_selector_level = 13;
inline constexpr int ending_dismissal_next_selector_level = 1;
inline constexpr int presentation_string_count = 27;
inline constexpr int in_mission_dialogue_sequence_count = 0;
inline constexpr int scripted_camera_sequence_count = 0;
inline constexpr int per_level_tutorial_sequence_count = 0;
inline constexpr bool mission_flow_reaches_movie_or_camera = false;
inline constexpr int camera_direct_call_count = 2;
inline constexpr int mission_script_camera_writer_count = 0;
inline constexpr const char* original_profile_policy = "The strict original profile has no in-mission editorial director. It keeps recovered startup movies, briefings, global F1 help and the ending; easy/normal/hard may opt into clearly labelled remake_editorial dialogue, camera and tutorial beats.";

struct GlobalHelpRoute final {
    const char* resource_name;
    std::uintptr_t resource_string_rva;
    const char* presenter_symbol;
    const char* scope;
};

inline constexpr GlobalHelpRoute global_help{"Help.psd", 0x000CF704, "HelpPresenter", "global_f1_help"};

struct CameraDirectCall final {
    const char* caller_symbol;
    const char* call_site_symbol;
    std::uintptr_t call_rva;
    const char* role;
};

inline constexpr std::array<CameraDirectCall, 2> camera_direct_callers{{
    {"WorldInputDispatch", "WorldInputCameraSetCall", 0x0004CC23, "world_input_recenter"},
    {"FocusActorCamera", "FocusActorCameraSetCall", 0x0004CD8B, "explicit_actor_focus"},
}};

inline constexpr std::array<const char*, 8> camera_writer_symbols{{
    "InitializeViewport",
    "SetCameraOrigin",
    "ScrollLeft",
    "ScrollRight",
    "ScrollUp",
    "ScrollDown",
    "ResizeViewportWorld",
    "LoadGameFile",
}};

struct StartupMovie final {
    int order;
    const char* id;
    const char* role;
    const char* source_filename;
    const char* source_disk_filename;
    std::uintptr_t source_string_rva;
    std::uintptr_t call_rva;
    int player_argument_1;
    int player_argument_2;
    int source_width;
    int source_height;
    double duration_seconds;
    const char* converted_relative_path;
};

inline constexpr std::array<StartupMovie, 2> startup_sequence{{
    {0, "logo", "publisher_logo", "GameKingLogo.SVT", "GamekingLogo.svt", 0x000CF78C, 0x00007635, 0, 0, 640, 480, 10.396733, "media/video/logo.ogv"},
    {1, "historical_intro", "historical_intro", "1937Intro.SVT", "1937Intro.svt", 0x000CF77C, 0x00007644, 0, 100, 640, 240, 139.916667, "media/video/historical_intro.ogv"},
}};

struct LevelBriefing final {
    int selector_level;
    const char* level_id;
    const char* resource_name;
    int gfl_index;
    const char* converted_relative_path;
};

inline constexpr std::array<LevelBriefing, 12> level_briefings{{
    {1, "m000", "Intro_000.psd", 1048, "iblock/1048.png"},
    {2, "m001", "Intro_001.psd", 1049, "iblock/1049.png"},
    {3, "m002", "Intro_002.psd", 1050, "iblock/1050.png"},
    {4, "m003", "Intro_003.psd", 1051, "iblock/1051.png"},
    {5, "m004", "Intro_004.psd", 1052, "iblock/1052.png"},
    {6, "m005", "Intro_005.psd", 1053, "iblock/1053.png"},
    {7, "m006", "Intro_006.psd", 1054, "iblock/1054.png"},
    {8, "m007", "Intro_007.psd", 1055, "iblock/1055.png"},
    {9, "m008", "Intro_008.psd", 1056, "iblock/1056.png"},
    {10, "m009", "Intro_009.psd", 1057, "iblock/1057.png"},
    {11, "m010", "Intro_010.psd", 1058, "iblock/1058.png"},
    {12, "m011", "Intro_011.psd", 1059, "iblock/1059.png"},
}};

struct EndingImage final {
    int target_width;
    const char* resource_name;
    std::uintptr_t resource_string_rva;
    int gfl_index;
    const char* converted_relative_path;
};

inline constexpr std::array<EndingImage, 3> ending_images{{
    {640, "Intro_012640.psd", 0x000CF3A8, 1061, "iblock/1061.png"},
    {800, "Intro_012800.psd", 0x000CF3BC, 1062, "iblock/1062.png"},
    {1024, "Intro_0121024.psd", 0x000CF3D0, 1060, "iblock/1060.png"},
}};

}  // namespace m1937::sdk::media
