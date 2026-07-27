#pragma once

#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

struct ExecutableIdentity final {
    static constexpr std::uint32_t preferred_image_base = 0x00400000;
    static constexpr std::uint32_t image_size = 0x00124000;
    static constexpr std::uint32_t pe_timestamp = 0x3AE9BFE6;
    static constexpr std::uint32_t entry_point_rva = 0x0006D567;
    static constexpr std::size_t file_size = 1'114'162;
    static constexpr const char* sha256 =
        "F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3";
};

namespace rva {

// Original routines and hook sites.
inline constexpr std::uintptr_t safe_blit = 0x0000EE30;
inline constexpr std::uintptr_t menu_poll = 0x00044800;
inline constexpr std::uintptr_t smooth_scroll = 0x0004C9B0;

// Startup and mission-selection patch points.
inline constexpr std::uintptr_t false_resource_warning_branch = 0x0000734A;
inline constexpr std::uintptr_t startup_movie_enqueue = 0x0000762C;
inline constexpr std::uintptr_t new_game_level_immediate = 0x00003B66;
inline constexpr std::uintptr_t mission_12_vwf_name = 0x000CF4A8;
inline constexpr std::uintptr_t mission_7_vwf_name = 0x000CF4F8;

// Enemy perception and alert propagation operands.
inline constexpr std::uintptr_t close_hearing_radius_immediate = 0x0005DD27;
inline constexpr std::uintptr_t alert_radius_operand_1 = 0x00056E62;
inline constexpr std::uintptr_t alert_radius_operand_2 = 0x00056E94;
inline constexpr std::uintptr_t alert_radius_operand_3 = 0x00057049;
inline constexpr std::uintptr_t alert_radius_operand_4 = 0x00057187;

// Runtime globals recovered from the supported executable.
inline constexpr std::uintptr_t screen_width = 0x000E6E0C;
inline constexpr std::uintptr_t screen_height = 0x000E6E10;
inline constexpr std::uintptr_t mouse_left_pressed = 0x000E6E64;
inline constexpr std::uintptr_t mouse_left_down = 0x000E6E74;
inline constexpr std::uintptr_t cursor_x = 0x000E6EA0;
inline constexpr std::uintptr_t briefing_advance = 0x000E6EA9;
inline constexpr std::uintptr_t cursor_y = 0x000E6FAC;
inline constexpr std::uintptr_t mouse_left_released = 0x000E6FB0;
inline constexpr std::uintptr_t current_mission = 0x000E7060;
inline constexpr std::uintptr_t renderer_height = 0x000D6A88;
inline constexpr std::uintptr_t renderer_width = 0x000D6A8C;

// Resolution operands used only by the opt-in experimental viewport patch.
inline constexpr std::uintptr_t startup_width_1024 = 0x00007706;
inline constexpr std::uintptr_t startup_height_768 = 0x00007710;
inline constexpr std::uintptr_t startup_width_800 = 0x0000771C;
inline constexpr std::uintptr_t startup_height_600 = 0x00007726;
inline constexpr std::uintptr_t startup_width_640 = 0x00007732;
inline constexpr std::uintptr_t startup_height_480 = 0x0000773C;
inline constexpr std::uintptr_t intro_1024_layout_guard = 0x00002F79;
inline constexpr std::uintptr_t menu_1024_layout_guard = 0x00003288;

}  // namespace rva
}  // namespace m1937::sdk
