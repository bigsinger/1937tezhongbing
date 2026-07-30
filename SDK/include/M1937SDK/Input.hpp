#pragma once

#include "Addresses.hpp"

#include <cstddef>
#include <cstdint>

namespace m1937::sdk::input {

// Recovered from the catalogued DirectInputPoll function and its consumers.
// These are DirectInput keyboard scan codes, not Win32 virtual-key values.
enum class DikScanCode : std::uint16_t {
    escape = 0x01,
    digit_1 = 0x02,
    digit_2 = 0x03,
    digit_3 = 0x04,
    digit_4 = 0x05,
    digit_5 = 0x06,
    digit_6 = 0x07,
    digit_7 = 0x08,
    digit_8 = 0x09,
    digit_9 = 0x0A,
    digit_0 = 0x0B,
    w = 0x11,
    r = 0x13,
    left_control = 0x1D,
    a = 0x1E,
    s = 0x1F,
    c = 0x2E,
    b = 0x30,
    m = 0x32,
    f1 = 0x3B,
    f2 = 0x3C,
    f3 = 0x3D,
    f4 = 0x3E,
    f5 = 0x3F,
    f6 = 0x40,
    f7 = 0x41,
    f8 = 0x42,
    up = 0xC8,
};

enum class TriggerPhase : std::uint8_t {
    press,
    release,
    held,
};

enum class OriginalAction : std::uint8_t {
    pause,
    guide,
    select_1,
    select_2,
    select_3,
    select_4,
    select_5,
    briefing,
    toggle_run,
    toggle_crawl,
    weapon_inventory,
    item_inventory,
    sight_mode,
    burial_mode,
    minimap,
    force_target_control,
    force_target_up,
    weapon_1,
    weapon_2,
    weapon_3,
    weapon_4,
    weapon_5,
    weapon_6,
    weapon_7,
    weapon_8,
    weapon_9,
    weapon_10,
    debug_load_m010,
};

struct ActionBinding final {
    OriginalAction action;
    DikScanCode scan_code;
    TriggerPhase phase;
};

inline constexpr ActionBinding original_action_bindings[] = {
    {OriginalAction::pause, DikScanCode::escape, TriggerPhase::release},
    {OriginalAction::guide, DikScanCode::f1, TriggerPhase::release},
    {OriginalAction::select_1, DikScanCode::f2, TriggerPhase::press},
    {OriginalAction::select_2, DikScanCode::f3, TriggerPhase::press},
    {OriginalAction::select_3, DikScanCode::f4, TriggerPhase::press},
    {OriginalAction::select_4, DikScanCode::f5, TriggerPhase::press},
    {OriginalAction::select_5, DikScanCode::f6, TriggerPhase::press},
    {OriginalAction::briefing, DikScanCode::f7, TriggerPhase::release},
    {OriginalAction::toggle_run, DikScanCode::r, TriggerPhase::release},
    {OriginalAction::toggle_crawl, DikScanCode::c, TriggerPhase::release},
    {OriginalAction::weapon_inventory, DikScanCode::w, TriggerPhase::release},
    {OriginalAction::item_inventory, DikScanCode::a, TriggerPhase::release},
    {OriginalAction::sight_mode, DikScanCode::s, TriggerPhase::release},
    {OriginalAction::burial_mode, DikScanCode::b, TriggerPhase::release},
    {OriginalAction::minimap, DikScanCode::m, TriggerPhase::release},
    {
        OriginalAction::force_target_control,
        DikScanCode::left_control,
        TriggerPhase::held,
    },
    {OriginalAction::force_target_up, DikScanCode::up, TriggerPhase::held},
    {OriginalAction::weapon_1, DikScanCode::digit_1, TriggerPhase::press},
    {OriginalAction::weapon_2, DikScanCode::digit_2, TriggerPhase::press},
    {OriginalAction::weapon_3, DikScanCode::digit_3, TriggerPhase::press},
    {OriginalAction::weapon_4, DikScanCode::digit_4, TriggerPhase::press},
    {OriginalAction::weapon_5, DikScanCode::digit_5, TriggerPhase::press},
    {OriginalAction::weapon_6, DikScanCode::digit_6, TriggerPhase::press},
    {OriginalAction::weapon_7, DikScanCode::digit_7, TriggerPhase::press},
    {OriginalAction::weapon_8, DikScanCode::digit_8, TriggerPhase::press},
    {OriginalAction::weapon_9, DikScanCode::digit_9, TriggerPhase::press},
    {OriginalAction::weapon_10, DikScanCode::digit_0, TriggerPhase::press},
    {OriginalAction::debug_load_m010, DikScanCode::f8, TriggerPhase::release},
};

inline constexpr std::size_t original_action_binding_count =
    sizeof(original_action_bindings) / sizeof(original_action_bindings[0]);

[[nodiscard]] constexpr const ActionBinding* find_action_binding(
    OriginalAction action) noexcept {
    for (const auto& binding : original_action_bindings) {
        if (binding.action == action)
            return &binding;
    }
    return nullptr;
}

struct ButtonTransition final {
    bool pressed;
    bool down;
    bool released;
};

[[nodiscard]] constexpr ButtonTransition transition(
    bool previous_down,
    bool current_down) noexcept {
    return {
        current_down && !previous_down,
        current_down,
        previous_down && !current_down,
    };
}

// Byte offsets from rva::input_state_base. All flag fields are 32-bit except
// the 256-byte DirectInput keyboard array at keyboard_state.
struct InputStateOffsets final {
    static constexpr std::size_t a_held = 4;
    static constexpr std::size_t m_held = 12;
    static constexpr std::size_t mouse_left_pressed = 16;
    static constexpr std::size_t b_held = 20;
    static constexpr std::size_t a_released = 24;
    static constexpr std::size_t mouse_middle_down = 28;
    static constexpr std::size_t mouse_left_down = 32;
    static constexpr std::size_t m_released = 36;
    // This field was historically labelled InputScrollBlock in the catalog.
    static constexpr std::size_t mouse_right_down = 40;
    static constexpr std::size_t f1_released = 44;
    static constexpr std::size_t c_held = 48;
    static constexpr std::size_t b_released = 52;
    static constexpr std::size_t r_held = 56;
    static constexpr std::size_t mouse_right_released = 60;
    static constexpr std::size_t c_released = 64;
    static constexpr std::size_t s_held = 68;
    static constexpr std::size_t f7_released = 72;
    static constexpr std::size_t cursor_x = 76;
    static constexpr std::size_t r_released = 80;
    static constexpr std::size_t keyboard_state = 84;
    static constexpr std::size_t s_released = 340;
    static constexpr std::size_t cursor_y = 344;
    static constexpr std::size_t mouse_left_released = 348;
    static constexpr std::size_t f7_held = 352;
    static constexpr std::size_t w_held = 360;
    static constexpr std::size_t f8_held = 364;
    static constexpr std::size_t f1_held = 376;
    static constexpr std::size_t w_released = 380;
    static constexpr std::size_t mouse_middle_pressed = 384;
    static constexpr std::size_t mouse_right_pressed = 388;
    static constexpr std::size_t mouse_middle_released = 392;
    static constexpr std::size_t f8_released = 396;
    static constexpr std::size_t escape_released = 400;
    static constexpr std::size_t escape_previous_or_current = 404;
};

[[nodiscard]] constexpr std::size_t keyboard_state_offset(
    DikScanCode scan_code) noexcept {
    return InputStateOffsets::keyboard_state +
        static_cast<std::uint16_t>(scan_code);
}

enum class CursorSerial : std::uint8_t {
    normal = 0,
    move = 1,
    force_target = 2,
    interact = 3,
    burial = 4,
    alternate_interact = 6,
    sight = 8,
    outside_world = 9,
    blocked = 10,
};

[[nodiscard]] constexpr CursorSerial context_cursor(
    bool burial_mode,
    bool sight_mode,
    bool has_selected_actor,
    bool force_target_held,
    bool hovering_interactable,
    bool hovering_enemy,
    bool ground_is_walkable) noexcept {
    if (burial_mode)
        return CursorSerial::burial;
    if (sight_mode)
        return CursorSerial::sight;
    if (!has_selected_actor)
        return CursorSerial::normal;
    if (force_target_held)
        return CursorSerial::force_target;
    if (hovering_interactable)
        return CursorSerial::interact;
    if (hovering_enemy)
        return CursorSerial::force_target;
    return ground_is_walkable ? CursorSerial::move : CursorSerial::blocked;
}

enum class EdgeDirection : std::uint8_t {
    none = 0,
    north = 1,
    northeast = 2,
    east = 3,
    southeast = 4,
    south = 5,
    southwest = 6,
    west = 7,
    northwest = 8,
};

[[nodiscard]] constexpr EdgeDirection edge_direction(
    int cursor_x,
    int cursor_y,
    int client_width,
    int client_height) noexcept {
    if (client_width <= 0 || client_height <= 0 ||
        cursor_x < 0 || cursor_y < 0 ||
        cursor_x >= client_width || cursor_y >= client_height)
        return EdgeDirection::none;
    const int x =
        cursor_x <= 1 ? -1 : (cursor_x >= client_width - 1 ? 1 : 0);
    const int y =
        cursor_y <= 1 ? -1 : (cursor_y >= client_height - 1 ? 1 : 0);
    if (x == 0 && y < 0)
        return EdgeDirection::north;
    if (x > 0 && y < 0)
        return EdgeDirection::northeast;
    if (x > 0 && y == 0)
        return EdgeDirection::east;
    if (x > 0 && y > 0)
        return EdgeDirection::southeast;
    if (x == 0 && y > 0)
        return EdgeDirection::south;
    if (x < 0 && y > 0)
        return EdgeDirection::southwest;
    if (x < 0 && y == 0)
        return EdgeDirection::west;
    if (x < 0 && y < 0)
        return EdgeDirection::northwest;
    return EdgeDirection::none;
}

[[nodiscard]] constexpr int advance_scroll_velocity(
    int current_velocity,
    int velocity_limit,
    bool at_edge,
    int response_divisor = 8) noexcept {
    if (velocity_limit <= 0)
        return 0;
    if (response_divisor <= 0)
        response_divisor = 1;
    const int step = velocity_limit / response_divisor;
    const int next = current_velocity + (at_edge ? step : -step);
    return next < 0 ? 0 : (next > velocity_limit ? velocity_limit : next);
}

static_assert(
    rva::mouse_left_pressed - rva::input_state_base ==
    InputStateOffsets::mouse_left_pressed);
static_assert(
    rva::mouse_left_down - rva::input_state_base ==
    InputStateOffsets::mouse_left_down);
static_assert(
    rva::mouse_left_released - rva::input_state_base ==
    InputStateOffsets::mouse_left_released);
static_assert(
    rva::cursor_x - rva::input_state_base == InputStateOffsets::cursor_x);
static_assert(
    rva::cursor_y - rva::input_state_base == InputStateOffsets::cursor_y);

}  // namespace m1937::sdk::input
