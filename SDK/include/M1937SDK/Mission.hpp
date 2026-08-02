#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace m1937::sdk::mission {

// Raw values written by sub_405410 to both the game-flow state at +0xA4 and
// the mission-result state at +0xC0. Values outside this recovered transition
// pair are deliberately treated as active/unknown by observers.
enum class Outcome : std::int32_t {
    unknown = 0,
    failed = 2,
    victory = 3,
};

enum class TargetPredicate : std::uint8_t {
    none = 0,
    hit_points_nonpositive,
    timed_explosive_within_radius,
};

enum CharacterMask : std::uint32_t {
    character_none = 0,
    character_old_zhao = 1u << 0,
    character_qiangzi = 1u << 1,
    character_gu_ming = 1u << 2,
    character_daniu = 1u << 3,
    character_driver = 1u << 4,
};

// Source-backed subsets of sub_404BB0/sub_405410 which cannot be represented
// as a generic context-key hotspot. A zero field means that predicate is not
// used by the corresponding mission case.
struct RecoveredInteractionRule final {
    std::int32_t mission_number;
    TargetPredicate target_predicate;
    std::int32_t target_runtime_type;
    std::int32_t required_nearby_runtime_type;
    std::int32_t target_radius;
    bool target_radius_exclusive;
    std::int32_t exit_runtime_type;
    std::int32_t exit_radius;
    bool exit_radius_exclusive;
    std::uint32_t exit_character_mask;
    std::int32_t required_exit_actor_runtime_type;
    std::uint32_t item_101_holder_mask;
    std::int32_t required_dead_runtime_type_a;
    std::int32_t required_dead_runtime_type_b;
};

inline constexpr std::array<RecoveredInteractionRule, 6>
    recovered_interaction_rules{{
        {2, TargetPredicate::hit_points_nonpositive, 98, 0, 0, false,
         100, 128, false, character_gu_ming | character_driver, 91,
         character_none, 0, 0},
        {3, TargetPredicate::hit_points_nonpositive, 98, 0, 0, false,
         100, 128, true, character_old_zhao | character_qiangzi, 0,
         character_none, 0, 0},
        {4, TargetPredicate::timed_explosive_within_radius, 98, 85, 128,
         true, 100, 128, false,
         character_old_zhao | character_qiangzi | character_gu_ming |
             character_daniu,
         0, character_none, 0, 0},
        {5, TargetPredicate::hit_points_nonpositive, 98, 0, 0, false,
         0, 0, false, character_none, 0,
         character_gu_ming | character_daniu, 0, 0},
        {7, TargetPredicate::none, 0, 0, 0, false,
         0, 0, false, character_none, 0, character_qiangzi, 15, 22},
        {9, TargetPredicate::timed_explosive_within_radius, 98, 85, 128,
         true, 100, 128, true, character_old_zhao | character_daniu, 0,
         character_none, 0, 0},
    }};

constexpr const RecoveredInteractionRule* find_interaction_rule(
    std::int32_t mission_number) noexcept {
    for (const auto& rule : recovered_interaction_rules) {
        if (rule.mission_number == mission_number)
            return &rule;
    }
    return nullptr;
}

constexpr bool distance_matches(
    std::int32_t delta_x,
    std::int32_t delta_y,
    std::int32_t radius,
    bool exclusive_boundary) noexcept {
    if (radius <= 0)
        return false;
    const auto x = static_cast<std::int64_t>(delta_x);
    const auto y = static_cast<std::int64_t>(delta_y);
    const auto r = static_cast<std::int64_t>(radius);
    const auto distance_squared = x * x + y * y;
    const auto radius_squared = r * r;
    return exclusive_boundary
        ? distance_squared < radius_squared
        : distance_squared <= radius_squared;
}

constexpr bool character_allowed(
    std::uint32_t mask,
    CharacterMask character) noexcept {
    return (mask & static_cast<std::uint32_t>(character)) != 0;
}

constexpr bool damage_destroys_target(
    std::int32_t current_hit_points,
    std::int32_t damage) noexcept {
    return current_hit_points > 0 && damage >= current_hit_points;
}

#pragma pack(push, 1)
// State prefix of the main game controller passed as ECX to sub_404BB0 and
// sub_405410. The unknown bytes remain opaque; only fields proven by all
// twelve mission branches are named.
struct RuntimeControllerStateV1 final {
    std::byte unknown_000[0x0A4];
    std::int32_t game_flow_state;        // +0x0A4
    std::byte unknown_0a8[0x14];
    std::int32_t evaluation_active;      // +0x0BC
    std::int32_t result_state;           // +0x0C0
};
#pragma pack(pop)

constexpr Outcome outcome_from_raw(std::int32_t value) noexcept {
    return value == static_cast<std::int32_t>(Outcome::failed)
        ? Outcome::failed
        : value == static_cast<std::int32_t>(Outcome::victory)
            ? Outcome::victory
            : Outcome::unknown;
}

constexpr const char* outcome_name(Outcome value) noexcept {
    switch (value) {
    case Outcome::failed:
        return "failed";
    case Outcome::victory:
        return "victory";
    case Outcome::unknown:
        return "active";
    }
    return "active";
}

static_assert(
    offsetof(RuntimeControllerStateV1, game_flow_state) == 0x0A4);
static_assert(
    offsetof(RuntimeControllerStateV1, evaluation_active) == 0x0BC);
static_assert(
    offsetof(RuntimeControllerStateV1, result_state) == 0x0C0);
static_assert(sizeof(RuntimeControllerStateV1) == 0x0C4);
static_assert(recovered_interaction_rules.size() == 6);
static_assert(
    find_interaction_rule(2)->required_exit_actor_runtime_type == 91);
static_assert(
    find_interaction_rule(4)->target_predicate ==
    TargetPredicate::timed_explosive_within_radius);
static_assert(find_interaction_rule(9)->exit_radius_exclusive);
static_assert(distance_matches(127, 0, 128, true));
static_assert(!distance_matches(128, 0, 128, true));
static_assert(distance_matches(128, 0, 128, false));
static_assert(!damage_destroys_target(8, 7));
static_assert(damage_destroys_target(8, 8));

}  // namespace m1937::sdk::mission
