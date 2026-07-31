#pragma once

#include <cstddef>
#include <cstdint>

#include "RuntimeTypes.hpp"

namespace m1937::sdk::command {

inline constexpr std::int32_t enemy_faction_id = 1;
inline constexpr std::int32_t sight_cursor_mode = 8;
inline constexpr std::int32_t burial_cursor_mode = 4;
inline constexpr std::int32_t burial_command_kind = 4;

inline constexpr std::int32_t observation_marker_actor_type = 90;
inline constexpr std::int32_t observation_marker_gfl_index = 341;
inline constexpr std::int32_t burial_cache_actor_type = 78;
inline constexpr std::int32_t burial_cache_gfl_index = 64;

inline constexpr std::int32_t navigation_cell_width = 32;
inline constexpr std::int32_t navigation_cell_height = 16;
inline constexpr std::int32_t burial_range_argument = 32;
inline constexpr std::int32_t burial_counter_limit = 100;

constexpr bool is_sight_direct_target(
    std::int32_t faction_id,
    std::int32_t dead_or_disabled) noexcept {
    return faction_id == enemy_faction_id && dead_or_disabled == 0;
}

constexpr bool is_burial_target(
    std::int32_t faction_id,
    std::int32_t dead_or_disabled) noexcept {
    return faction_id == enemy_faction_id && dead_or_disabled == 1;
}

// sub_456AB0 uses this same two-axis range before completing pickups and
// other actor interactions. It is an anisotropic navigation-cell rule, not
// a circular world-pixel radius.
constexpr bool is_interaction_adjacent_cell(
    std::int32_t worker_x,
    std::int32_t worker_y,
    std::int32_t target_x,
    std::int32_t target_y) noexcept {
    const auto worker_cell_x = worker_x / navigation_cell_width;
    const auto worker_cell_y = worker_y / navigation_cell_height;
    const auto target_cell_x = target_x / navigation_cell_width;
    const auto target_cell_y = target_y / navigation_cell_height;
    const auto delta_x = worker_cell_x - target_cell_x;
    const auto delta_y = worker_cell_y - target_cell_y;
    return delta_x >= -1 && delta_x <= 1 &&
        delta_y >= -1 && delta_y <= 1;
}

constexpr bool is_burial_adjacent_cell(
    std::int32_t worker_x,
    std::int32_t worker_y,
    std::int32_t target_x,
    std::int32_t target_y) noexcept {
    return is_interaction_adjacent_cell(
        worker_x, worker_y, target_x, target_y);
}

constexpr bool is_pickup_adjacent_cell(
    std::int32_t collector_x,
    std::int32_t collector_y,
    std::int32_t pickup_x,
    std::int32_t pickup_y) noexcept {
    return is_interaction_adjacent_cell(
        collector_x, collector_y, pickup_x, pickup_y);
}

// sub_456CD0 increments first and resolves only for counter > limit.
constexpr bool burial_counter_has_completed(
    std::int32_t counter) noexcept {
    return counter > burial_counter_limit;
}

// The supported executable uses the Windows CRT rand() gate `rand() % 2 > 0`
// before testing actor 90 against an enemy's current directional field + LOS.
constexpr std::uint32_t msvc_rand_step(std::uint32_t state) noexcept {
    return (state * 214013u + 2531011u) & 0x7fffffffu;
}

constexpr bool observation_poll_passes(std::uint32_t state) noexcept {
    const auto next = msvc_rand_step(state);
    return ((next >> 16u) & 0x7fffu) % 2u > 0u;
}

static_assert(
    offsetof(RuntimeActorV1, faction_id) == 0x074 &&
    offsetof(RuntimeActorV1, dead_or_disabled) == 0x188 &&
    offsetof(RuntimeActorV1, target_actor_address) == 0x214);
static_assert(
    offsetof(RuntimeActorV1, item_inventory_address) == 0x228 &&
    offsetof(RuntimeActorV1, inventory_address) == 0x22C);
static_assert(
    offsetof(RuntimeActorV1, search_delay_limit) == 0x248 &&
    offsetof(RuntimeActorV1, search_delay_counter) == 0x24C &&
    offsetof(RuntimeActorV1, burial_action_started) == 0x288);
static_assert(is_sight_direct_target(1, 0));
static_assert(!is_sight_direct_target(1, 1));
static_assert(is_burial_target(1, 1));
static_assert(!is_burial_target(3, 1));
static_assert(is_burial_adjacent_cell(0, 0, 63, 31));
static_assert(!is_burial_adjacent_cell(0, 0, 64, 32));
static_assert(is_pickup_adjacent_cell(0, 0, 63, 31));
static_assert(!is_pickup_adjacent_cell(0, 0, 64, 32));
static_assert(!burial_counter_has_completed(100));
static_assert(burial_counter_has_completed(101));

}  // namespace m1937::sdk::command
