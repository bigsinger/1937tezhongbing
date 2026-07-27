#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>

namespace m1937::sdk::enemy_ai {

// The enhanced policy deliberately operates on an immutable observation made
// when an alert is raised. It never accepts a live target pointer or live
// target coordinates after that observation.
struct LastKnownObservation final {
    std::int32_t world_x = 0;
    std::int32_t world_y = 0;
    std::int32_t facing_index = 0;
    std::uint32_t observed_at_ms = 0;
};

struct Tuning final {
    std::int32_t reaction_delay_ms = 0;
    std::int32_t maximum_reinforcements = 1;
    std::int32_t search_point_count = 0;
    std::int32_t search_timeout_ms = 0;
    std::int32_t intercept_distance = 0;
};

constexpr std::int32_t clamp_level(std::int32_t value) noexcept {
    return value < 0 ? 0 : (value > 3 ? 3 : value);
}

constexpr Tuning tuning_for(
    std::int32_t ai_level,
    std::int32_t difficulty) noexcept {
    constexpr std::array<std::int32_t, 4> reaction = {
        900, 650, 425, 250};
    constexpr std::array<std::int32_t, 4> reinforcements = {
        1, 1, 2, 3};
    constexpr std::array<std::int32_t, 4> search_points = {
        0, 2, 3, 4};
    constexpr std::array<std::int32_t, 4> timeout = {
        0, 8000, 12000, 18000};
    constexpr std::array<std::int32_t, 4> intercept = {
        0, 48, 72, 96};

    const auto ai = static_cast<std::size_t>(clamp_level(ai_level));
    const auto level = clamp_level(difficulty);
    auto result = Tuning{
        reaction[ai],
        reinforcements[ai],
        search_points[ai],
        timeout[ai],
        intercept[ai]};
    if (level >= 2 && ai_level > 0)
        result.reaction_delay_ms =
            (std::max)(100, result.reaction_delay_ms - level * 75);
    if (level >= 3 && ai_level > 0)
        result.maximum_reinforcements =
            (std::min)(4, result.maximum_reinforcements + 1);
    return result;
}

struct Candidate final {
    std::uintptr_t actor = 0;
    std::int32_t distance = 0;
    bool eligible = false;
};

// Selects only eligible nearby allies, nearest first. The fixed output capacity
// and tuning cap make whole-map synchronisation impossible.
inline std::size_t select_reinforcements(
    Candidate* candidates,
    std::size_t candidate_count,
    std::uintptr_t* output,
    std::size_t output_capacity,
    std::int32_t configured_limit) noexcept {
    if (!candidates || !output || output_capacity == 0)
        return 0;
    std::sort(
        candidates,
        candidates + candidate_count,
        [](const Candidate& left, const Candidate& right) noexcept {
            if (left.eligible != right.eligible)
                return left.eligible > right.eligible;
            if (left.distance != right.distance)
                return left.distance < right.distance;
            return left.actor < right.actor;
        });
    const auto limit = static_cast<std::size_t>(
        std::clamp(configured_limit, 1, 4));
    std::size_t written = 0;
    for (std::size_t index = 0;
         index < candidate_count &&
         written < output_capacity &&
         written < limit;
         ++index) {
        if (!candidates[index].eligible ||
            candidates[index].actor == 0)
            continue;
        output[written++] = candidates[index].actor;
    }
    return written;
}

struct Point final {
    std::int32_t x = 0;
    std::int32_t y = 0;

    constexpr bool operator==(const Point& other) const noexcept {
        return x == other.x && y == other.y;
    }
};

constexpr Point facing_vector(std::int32_t facing_index) noexcept {
    // The original actor direction is a 32-step clockwise index. Integer
    // vectors avoid floating-point drift in deterministic mission builds.
    constexpr std::array<Point, 32> vectors = {{
        {0, -1024}, {200, -1004}, {392, -946}, {569, -851},
        {724, -724}, {851, -569}, {946, -392}, {1004, -200},
        {1024, 0}, {1004, 200}, {946, 392}, {851, 569},
        {724, 724}, {569, 851}, {392, 946}, {200, 1004},
        {0, 1024}, {-200, 1004}, {-392, 946}, {-569, 851},
        {-724, 724}, {-851, 569}, {-946, 392}, {-1004, 200},
        {-1024, 0}, {-1004, -200}, {-946, -392}, {-851, -569},
        {-724, -724}, {-569, -851}, {-392, -946}, {-200, -1004}
    }};
    auto normalized = facing_index % 32;
    if (normalized < 0)
        normalized += 32;
    return vectors[static_cast<std::size_t>(normalized)];
}

constexpr Point offset_from_observation(
    const LastKnownObservation& observation,
    std::int32_t forward,
    std::int32_t lateral) noexcept {
    const auto direction = facing_vector(observation.facing_index);
    return {
        observation.world_x +
            (direction.x * forward - direction.y * lateral) / 1024,
        observation.world_y +
            (direction.y * forward + direction.x * lateral) / 1024};
}

// The first point is an intercept in front of the last observed direction.
// Subsequent points form a small deterministic fan around that immutable
// anchor. The returned count is always in the documented 0..4 range.
inline std::size_t build_search_pattern(
    const LastKnownObservation& observation,
    const Tuning& tuning,
    Point* output,
    std::size_t output_capacity) noexcept {
    if (!output || output_capacity == 0)
        return 0;
    constexpr std::array<std::array<std::int32_t, 2>, 4> pattern = {{
        {{1, 0}}, {{0, -1}}, {{0, 1}}, {{-1, 0}}
    }};
    const auto count = (std::min)(
        output_capacity,
        static_cast<std::size_t>(
            std::clamp(tuning.search_point_count, 0, 4)));
    for (std::size_t index = 0; index < count; ++index) {
        output[index] = offset_from_observation(
            observation,
            pattern[index][0] * tuning.intercept_distance,
            pattern[index][1] * tuning.intercept_distance);
    }
    return count;
}

enum class SearchDecision : std::uint8_t {
    keep_current_goal,
    advance_to_next_point,
    hand_back_to_original_ai
};

constexpr SearchDecision decide_search_step(
    bool target_reacquired,
    std::uint32_t elapsed_ms,
    std::int32_t timeout_ms,
    bool arrived,
    bool path_stalled,
    std::size_t next_point,
    std::size_t point_count) noexcept {
    if (target_reacquired ||
        timeout_ms <= 0 ||
        elapsed_ms >= static_cast<std::uint32_t>(timeout_ms) ||
        next_point >= point_count)
        return SearchDecision::hand_back_to_original_ai;
    if (arrived || path_stalled)
        return SearchDecision::advance_to_next_point;
    return SearchDecision::keep_current_goal;
}

// Contract marker used by static/runtime tests and plugin authors.
inline constexpr bool samples_live_target_after_alert = false;

}  // namespace m1937::sdk::enemy_ai
