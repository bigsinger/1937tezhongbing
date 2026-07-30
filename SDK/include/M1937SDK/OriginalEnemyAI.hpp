#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>

#include "Commands.hpp"
#include "RuntimeTypes.hpp"

namespace m1937::sdk::original_enemy_ai {

// Exact autonomous alert/search behavior recovered from M1937.exe. These
// constants describe the shipped original mode, not EnemyAI.hpp's explicitly
// editorial difficulty extension.
inline constexpr std::int32_t enemy_faction_id = 1;
inline constexpr std::int32_t excluded_alert_runtime_type = 91;
inline constexpr std::int32_t alert_horizontal_radius = 640;
inline constexpr std::int32_t alert_vertical_radius = 320;
inline constexpr std::int32_t reaction_minimum_limit = 40;
inline constexpr std::int32_t reaction_random_span = 40;
inline constexpr std::int32_t search_point_count = 5;
inline constexpr std::int32_t search_horizontal_span = 32;
inline constexpr std::int32_t search_vertical_span = 16;
inline constexpr std::int32_t search_wait_minimum_limit = 40;
inline constexpr std::int32_t search_wait_random_span = 160;
inline constexpr std::int32_t world_margin = 16;

struct Point final {
    std::int32_t x = 0;
    std::int32_t y = 0;
};

struct WorldBounds final {
    std::int32_t minimum_x = 0;
    std::int32_t minimum_y = 0;
    std::int32_t maximum_x = 0;
    std::int32_t maximum_y = 0;
};

struct LimitSample final {
    std::uint32_t random_state = 1;
    std::int32_t limit = 0;
};

struct SearchPointSample final {
    std::uint32_t random_state = 1;
    Point point{};
    std::int32_t next_wait_limit = 0;
};

constexpr std::uint32_t rand_value(
    std::uint32_t state_after_step) noexcept {
    return (state_after_step >> 16u) & 0x7fffu;
}

constexpr LimitSample sample_reaction_limit(
    std::uint32_t state_before_step) noexcept {
    const auto next = command::msvc_rand_step(state_before_step);
    return {
        next,
        static_cast<std::int32_t>(
            rand_value(next) % reaction_random_span +
            reaction_minimum_limit)};
}

constexpr bool counter_has_completed(
    std::int32_t counter,
    std::int32_t limit) noexcept {
    return counter > limit;
}

constexpr bool alert_recipient_is_eligible(
    std::int32_t faction_id,
    std::int32_t runtime_type,
    bool alive,
    bool has_unlost_live_contact) noexcept {
    return faction_id == enemy_faction_id &&
        runtime_type != excluded_alert_runtime_type &&
        alive &&
        !has_unlost_live_contact;
}

constexpr bool is_within_alert_ellipse(
    Point source,
    Point recipient,
    std::int32_t horizontal_radius =
        alert_horizontal_radius) noexcept {
    if (horizontal_radius <= 0)
        return false;
    if (horizontal_radius / 2 <= 0)
        return false;
    const auto delta_x =
        static_cast<std::int64_t>(recipient.x) - source.x;
    const auto delta_y =
        static_cast<std::int64_t>(recipient.y) - source.y;
    const auto distance_squared =
        delta_x * delta_x + delta_y * delta_y;
    if (distance_squared == 0)
        return true;
    const auto horizontal_squared =
        static_cast<std::int64_t>(horizontal_radius) *
        horizontal_radius;
    // sub_45A7C0 constructs (R*cos(angle), R/2*sin(angle)) at the
    // recipient angle and returns that point's Euclidean length. Compare the
    // squared forms without introducing floating-point drift.
    return distance_squared * distance_squared * 4 <
        horizontal_squared *
            (4 * delta_x * delta_x + delta_y * delta_y);
}

constexpr SearchPointSample sample_local_search_point(
    std::uint32_t state_before_step,
    Point origin,
    WorldBounds bounds) noexcept {
    auto state = command::msvc_rand_step(state_before_step);
    auto offset_x = static_cast<std::int32_t>(
        rand_value(state) % search_horizontal_span);
    state = command::msvc_rand_step(state);
    auto offset_y = static_cast<std::int32_t>(
        rand_value(state) % search_vertical_span);
    state = command::msvc_rand_step(state);
    if (rand_value(state) % 2u > 0u)
        offset_x = -offset_x;
    state = command::msvc_rand_step(state);
    if (rand_value(state) % 2u > 0u)
        offset_y = -offset_y;

    auto minimum_x = bounds.minimum_x + world_margin;
    auto minimum_y = bounds.minimum_y + world_margin;
    auto maximum_x = bounds.maximum_x - world_margin;
    auto maximum_y = bounds.maximum_y - world_margin;
    if (maximum_x < minimum_x) {
        minimum_x = bounds.minimum_x;
        maximum_x = bounds.maximum_x;
    }
    if (maximum_y < minimum_y) {
        minimum_y = bounds.minimum_y;
        maximum_y = bounds.maximum_y;
    }
    const Point point{
        std::clamp(origin.x + offset_x, minimum_x, maximum_x),
        std::clamp(origin.y + offset_y, minimum_y, maximum_y)};
    state = command::msvc_rand_step(state);
    return {
        state,
        point,
        static_cast<std::int32_t>(
            rand_value(state) % search_wait_random_span +
            search_wait_minimum_limit)};
}

static_assert(
    is_within_alert_ellipse({0, 0}, {639, 0}) &&
    !is_within_alert_ellipse({0, 0}, {640, 0}) &&
    is_within_alert_ellipse({0, 0}, {0, 319}) &&
    !is_within_alert_ellipse({0, 0}, {0, 320}) &&
    is_within_alert_ellipse({0, 0}, {320, 320}));
static_assert(alert_recipient_is_eligible(1, 6, true, false));
static_assert(!alert_recipient_is_eligible(1, 91, true, false));
static_assert(!counter_has_completed(40, 40));
static_assert(counter_has_completed(41, 40));
static_assert(offsetof(RuntimeActorV1, runtime_type) == 0x064);
static_assert(offsetof(RuntimeActorV1, faction_id) == 0x074);
static_assert(offsetof(RuntimeActorV1, goal_x) == 0x198);
static_assert(offsetof(RuntimeActorV1, goal_y) == 0x19C);
static_assert(offsetof(RuntimeActorV1, target_actor_address) == 0x214);
static_assert(offsetof(RuntimeActorV1, search_delay_limit) == 0x248);
static_assert(offsetof(RuntimeActorV1, search_delay_counter) == 0x24C);
static_assert(offsetof(RuntimeActorV1, target_lost) == 0x254);

}  // namespace m1937::sdk::original_enemy_ai
