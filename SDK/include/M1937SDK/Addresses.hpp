#pragma once

// Generated from SDK/address-catalog.json. Do not edit.
#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

struct ExecutableIdentity final {
    static constexpr std::uint32_t preferred_image_base = 0x00400000;
    static constexpr std::uint32_t image_size = 0x00124000;
    static constexpr std::uint32_t pe_timestamp = 0x3AE9BFE6;
    static constexpr std::uint32_t entry_point_rva = 0x0006D567;
    static constexpr std::size_t file_size = 1114162;
    static constexpr const char* sha256 = "F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3";
};

namespace rva {
inline constexpr std::uintptr_t safe_blit = 0x0000EE30;
inline constexpr std::uintptr_t menu_poll = 0x00044800;
inline constexpr std::uintptr_t smooth_scroll = 0x0004C9B0;
inline constexpr std::uintptr_t false_resource_warning_branch = 0x0000734A;
inline constexpr std::uintptr_t startup_movie_enqueue = 0x0000762C;
inline constexpr std::uintptr_t new_game_level_immediate = 0x00003B66;
inline constexpr std::uintptr_t mission_12_vwf_name = 0x000CF4A8;
inline constexpr std::uintptr_t mission_7_vwf_name = 0x000CF4F8;
inline constexpr std::uintptr_t close_hearing_radius_immediate = 0x0005DD27;
inline constexpr std::uintptr_t alert_radius_operand_1 = 0x00056E62;
inline constexpr std::uintptr_t alert_radius_operand_2 = 0x00056E94;
inline constexpr std::uintptr_t alert_radius_operand_3 = 0x00057049;
inline constexpr std::uintptr_t alert_radius_operand_4 = 0x00057187;
inline constexpr std::uintptr_t actor_distance = 0x0005A040;
inline constexpr std::uintptr_t alert_effective_radius = 0x0005A7C0;
inline constexpr std::uintptr_t enemy_ai_update = 0x0005C710;
inline constexpr std::uintptr_t alert_propagation = 0x0005DDA0;
inline constexpr std::uintptr_t load_game_file = 0x0004BB00;
inline constexpr std::uintptr_t save_game_file = 0x0004BEA0;
inline constexpr std::uintptr_t screen_width = 0x000E6E0C;
inline constexpr std::uintptr_t screen_height = 0x000E6E10;
inline constexpr std::uintptr_t input_state_base = 0x000E6E54;
inline constexpr std::uintptr_t input_action_map = 0x000E6E78;
inline constexpr std::uintptr_t input_action_help = 0x000E6E80;
inline constexpr std::uintptr_t input_raw_map = 0x000E6EDA;
inline constexpr std::uintptr_t input_raw_help = 0x000E6EE3;
inline constexpr std::uintptr_t mouse_left_pressed = 0x000E6E64;
inline constexpr std::uintptr_t mouse_left_down = 0x000E6E74;
inline constexpr std::uintptr_t cursor_x = 0x000E6EA0;
inline constexpr std::uintptr_t briefing_advance = 0x000E6EA9;
inline constexpr std::uintptr_t cursor_y = 0x000E6FAC;
inline constexpr std::uintptr_t mouse_left_released = 0x000E6FB0;
inline constexpr std::uintptr_t current_mission = 0x000E7060;
inline constexpr std::uintptr_t selected_save_slot = 0x000E705C;
inline constexpr std::uintptr_t world_root = 0x000E700C;
inline constexpr std::uintptr_t renderer_height = 0x000D6A88;
inline constexpr std::uintptr_t renderer_width = 0x000D6A8C;
inline constexpr std::uintptr_t camera_x = 0x000E7024;
inline constexpr std::uintptr_t camera_y = 0x000E7028;
inline constexpr std::uintptr_t startup_width_1024 = 0x00007706;
inline constexpr std::uintptr_t startup_height_768 = 0x00007710;
inline constexpr std::uintptr_t startup_width_800 = 0x0000771C;
inline constexpr std::uintptr_t startup_height_600 = 0x00007726;
inline constexpr std::uintptr_t startup_width_640 = 0x00007732;
inline constexpr std::uintptr_t startup_height_480 = 0x0000773C;
inline constexpr std::uintptr_t intro_1024_layout_guard = 0x00002F79;
inline constexpr std::uintptr_t menu_1024_layout_guard = 0x00003288;
inline constexpr std::uintptr_t settings_width_640_a = 0x00003E05;
inline constexpr std::uintptr_t settings_height_480_a = 0x00003E0F;
inline constexpr std::uintptr_t settings_height_480_b = 0x00003E2F;
inline constexpr std::uintptr_t settings_width_640_b = 0x00003E34;
inline constexpr std::uintptr_t settings_width_800_a = 0x00003EE2;
inline constexpr std::uintptr_t settings_height_600_a = 0x00003EEC;
inline constexpr std::uintptr_t settings_height_600_b = 0x00003F0C;
inline constexpr std::uintptr_t settings_width_800_b = 0x00003F11;
inline constexpr std::uintptr_t settings_width_1024_a = 0x00003FBF;
inline constexpr std::uintptr_t settings_height_768_a = 0x00003FC9;
inline constexpr std::uintptr_t settings_height_768_b = 0x00003FE9;
inline constexpr std::uintptr_t settings_width_1024_b = 0x00003FEE;

}  // namespace rva
}  // namespace m1937::sdk
