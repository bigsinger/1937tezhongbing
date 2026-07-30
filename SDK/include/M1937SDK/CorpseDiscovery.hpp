#pragma once

#include <cstdint>

#include "Commands.hpp"
#include "RuntimeTypes.hpp"

namespace m1937::sdk::corpse_discovery {

inline constexpr std::int32_t enemy_faction_id = 1;
inline constexpr std::int32_t dead_flag_value = 1;
inline constexpr std::int32_t undiscovered_flag_value = 0;
inline constexpr std::int32_t discovered_flag_value = 1;
inline constexpr std::int32_t required_visibility_band = 2;
inline constexpr std::int32_t contact_state = 3;
inline constexpr std::int32_t reaction_minimum_limit = 40;
inline constexpr std::int32_t reaction_random_span = 40;
inline constexpr std::int32_t reinforcement_marker_actor_type = 93;
inline constexpr std::int32_t reinforcement_actor_type = 6;
inline constexpr std::int32_t reinforcement_count = 2;

constexpr bool is_candidate(
    std::int32_t faction_id,
    std::int32_t dead_or_disabled,
    std::int32_t corpse_discovered) noexcept {
    return faction_id == enemy_faction_id &&
        dead_or_disabled == dead_flag_value &&
        corpse_discovered == undiscovered_flag_value;
}

constexpr std::int32_t reaction_limit(
    std::uint32_t state_before_step) noexcept {
    const auto next = command::msvc_rand_step(state_before_step);
    const auto value = (next >> 16u) & 0x7fffu;
    return static_cast<std::int32_t>(
        value % reaction_random_span + reaction_minimum_limit);
}

constexpr bool reaction_has_completed(
    std::int32_t counter,
    std::int32_t limit) noexcept {
    return counter > limit;
}

static_assert(is_candidate(1, 1, 0));
static_assert(!is_candidate(1, 0, 0));
static_assert(!is_candidate(1, 1, 1));
static_assert(!reaction_has_completed(40, 40));
static_assert(reaction_has_completed(41, 40));
static_assert(offsetof(RuntimeActorV1, corpse_discovered) == 0x258);

}  // namespace m1937::sdk::corpse_discovery
