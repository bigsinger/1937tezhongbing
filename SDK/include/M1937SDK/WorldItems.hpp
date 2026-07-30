#pragma once

#include <array>
#include <cstdint>

#include "Commands.hpp"
#include "RuntimeTypes.hpp"

namespace m1937::sdk::world_item {

inline constexpr std::int32_t enemy_faction_id = 1;
inline constexpr std::int32_t target_status = 3;
inline constexpr std::int32_t required_visibility_band = 1;
inline constexpr std::int32_t interaction_range_argument = 32;

inline constexpr std::int32_t chicken = 33;
inline constexpr std::int32_t canned_meat = 48;
inline constexpr std::int32_t hypnosis_doll = 49;
inline constexpr std::int32_t poisoned_wine = 52;
inline constexpr std::int32_t dog_bone = 82;
inline constexpr std::int32_t cigarette = 83;

inline constexpr std::int32_t hypnosis_counter_limit = 600;
inline constexpr std::int32_t poison_counter_limit = 80;
inline constexpr std::int32_t poison_damage = 16;
inline constexpr std::int32_t distraction_minimum_limit = 80;
inline constexpr std::int32_t distraction_random_span = 40;

enum class EffectKind : std::uint8_t {
    none,
    carry,
    hypnosis,
    poison_and_distraction,
    distraction,
};

struct EffectProfile final {
    EffectKind kind;
    bool consume_after_collection;
};

inline constexpr std::array<std::int32_t, 1> type_4_items = {
    poisoned_wine};
inline constexpr std::array<std::int32_t, 5> type_5_7_23_items = {
    poisoned_wine, chicken, cigarette, canned_meat, hypnosis_doll};
inline constexpr std::array<std::int32_t, 4> type_6_21_items = {
    poisoned_wine, cigarette, canned_meat, hypnosis_doll};
inline constexpr std::array<std::int32_t, 3> type_11_items = {
    poisoned_wine, cigarette, hypnosis_doll};
inline constexpr std::array<std::int32_t, 3> type_15_items = {
    poisoned_wine, cigarette, canned_meat};
inline constexpr std::array<std::int32_t, 1> type_56_items = {
    dog_bone};

template <std::size_t Size>
constexpr bool contains(
    const std::array<std::int32_t, Size>& items,
    std::int32_t item_id) noexcept {
    for (const auto item : items) {
        if (item == item_id)
            return true;
    }
    return false;
}

constexpr bool accepts(
    std::int32_t runtime_actor_type,
    std::int32_t item_id,
    std::int32_t faction_id = enemy_faction_id) noexcept {
    if (faction_id != enemy_faction_id)
        return false;
    switch (runtime_actor_type) {
    case 4:
    case 12:
        return contains(type_4_items, item_id);
    case 5:
    case 7:
    case 23:
        return contains(type_5_7_23_items, item_id);
    case 6:
    case 21:
        return contains(type_6_21_items, item_id);
    case 11:
        return contains(type_11_items, item_id);
    case 15:
        return contains(type_15_items, item_id);
    case 56:
        return contains(type_56_items, item_id);
    default:
        return false;
    }
}

constexpr EffectProfile effect(std::int32_t item_id) noexcept {
    switch (item_id) {
    case chicken:
    case canned_meat:
        return {EffectKind::carry, false};
    case hypnosis_doll:
        return {EffectKind::hypnosis, true};
    case poisoned_wine:
        return {EffectKind::poison_and_distraction, true};
    case dog_bone:
    case cigarette:
        return {EffectKind::distraction, false};
    default:
        return {EffectKind::none, false};
    }
}

constexpr std::int32_t distraction_limit(
    std::uint32_t state_before_step) noexcept {
    const auto next = command::msvc_rand_step(state_before_step);
    const auto value = (next >> 16u) & 0x7fffu;
    return static_cast<std::int32_t>(
        value % distraction_random_span + distraction_minimum_limit);
}

constexpr bool counter_has_completed(
    std::int32_t counter,
    std::int32_t limit) noexcept {
    return counter > limit;
}

static_assert(accepts(5, chicken));
static_assert(!accepts(6, chicken));
static_assert(accepts(56, dog_bone));
static_assert(!accepts(56, cigarette));
static_assert(effect(hypnosis_doll).consume_after_collection);
static_assert(!effect(cigarette).consume_after_collection);
static_assert(!counter_has_completed(600, hypnosis_counter_limit));
static_assert(counter_has_completed(601, hypnosis_counter_limit));
static_assert(!counter_has_completed(80, poison_counter_limit));
static_assert(counter_has_completed(81, poison_counter_limit));
static_assert(offsetof(RuntimeActorV1, world_item_player_selected) == 0x168);
static_assert(offsetof(RuntimeActorV1, hypnosis_active) == 0x238);
static_assert(offsetof(RuntimeActorV1, reaction_state) == 0x25C);
static_assert(offsetof(RuntimeActorV1, poison_active) == 0x264);
static_assert(offsetof(RuntimeActorV1, hypnosis_counter) == 0x27C);

}  // namespace m1937::sdk::world_item
