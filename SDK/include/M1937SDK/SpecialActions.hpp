#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

struct SpecialWorldObjectDefinition final {
    std::int32_t attack_type;
    std::int32_t consumed_item_id;
    std::int32_t deployment_actor_type;
    std::int32_t deployment_gfl_index;
    std::int32_t trigger_faction_id;
    std::int32_t trigger_horizontal_radius;
    std::int32_t trigger_vertical_radius;
    std::int32_t fuse_world_ticks;
    std::int32_t explosion_actor_type;
    std::int32_t primary_damage;
    std::int32_t blast_horizontal_radius;
    std::int32_t blast_vertical_radius;
    std::int32_t alert_radius;
};

// Recovered from SpecialAttackDispatch plus actor 84/85/62 update handlers.
inline constexpr SpecialWorldObjectDefinition triggered_special_action{
    8, 43, 84, 470, 1, 32, 16, 0, 62, 128, 128, 64, 800};
inline constexpr SpecialWorldObjectDefinition timed_special_action{
    10, 45, 85, 900, 0, 0, 0, 100, 62, 128, 128, 64, 800};

inline constexpr std::array<std::int32_t, 8>
    explosion_ellipse_actor_types{{34, 88, 86, 87, 94, 95, 96, 97}};
inline constexpr std::array<std::int32_t, 5>
    explosion_radius_actor_types{{66, 67, 68, 77, 93}};

inline constexpr std::int32_t explosion_special_damage = 128;
inline constexpr std::int32_t explosion_ellipse_horizontal_radius = 384;
inline constexpr std::int32_t explosion_ellipse_vertical_radius = 192;
inline constexpr std::int32_t explosion_radius = 256;
inline constexpr std::int32_t explosion_ellipse_visual_effect_type = 11;
inline constexpr std::int32_t explosion_radius_visual_effect_type = 15;

template <std::size_t Size>
constexpr bool contains_actor_type(
    const std::array<std::int32_t, Size>& values,
    std::int32_t runtime_actor_type) noexcept {
    for (const auto value : values) {
        if (value == runtime_actor_type)
            return true;
    }
    return false;
}

constexpr bool inside_isometric_ellipse(
    std::int32_t delta_x,
    std::int32_t delta_y,
    std::int32_t horizontal_radius,
    std::int32_t vertical_radius) noexcept {
    if (horizontal_radius <= 0 || vertical_radius <= 0)
        return false;
    const auto x = static_cast<std::int64_t>(delta_x);
    const auto y = static_cast<std::int64_t>(delta_y);
    const auto h = static_cast<std::int64_t>(horizontal_radius);
    const auto v = static_cast<std::int64_t>(vertical_radius);
    return x * x * v * v + y * y * h * h <= h * h * v * v;
}

constexpr bool inside_exclusive_euclidean_radius(
    std::int32_t delta_x,
    std::int32_t delta_y,
    std::int32_t radius) noexcept {
    if (radius <= 0)
        return false;
    const auto x = static_cast<std::int64_t>(delta_x);
    const auto y = static_cast<std::int64_t>(delta_y);
    const auto r = static_cast<std::int64_t>(radius);
    return x * x + y * y < r * r;
}

// Actor 62 first applies its primary 128-damage 128x64 ellipse. These are
// additional one-shot damage bands for the recovered runtime actor types.
constexpr std::int32_t explosion_actor_extra_damage(
    std::int32_t runtime_actor_type,
    std::int32_t delta_x,
    std::int32_t delta_y) noexcept {
    if (contains_actor_type(
            explosion_ellipse_actor_types, runtime_actor_type) &&
        inside_isometric_ellipse(
            delta_x,
            delta_y,
            explosion_ellipse_horizontal_radius,
            explosion_ellipse_vertical_radius))
        return explosion_special_damage;
    if (contains_actor_type(
            explosion_radius_actor_types, runtime_actor_type) &&
        inside_exclusive_euclidean_radius(
            delta_x, delta_y, explosion_radius))
        return explosion_special_damage;
    return 0;
}

struct SpecialAttentionRules final {
    std::int32_t attack_type;
    std::int32_t inventory_item_id;
    std::size_t target_flag_offset;
    bool consumes_item;
    bool pauses_idle_movement;
    bool faces_source_actor;
    bool releases_on_source_movement;
    bool releases_on_combat_transition;
};

// Type 11 is not a timed stun. The original sets target +0x290, faces the
// dedicated SpecialAttentionSource actor and suppresses only normal idle
// movement until that source moves or the target enters a combat transition.
inline constexpr SpecialAttentionRules special_attention_rules{
    11, 99, 0x290, false, true, true, true, true};

static_assert(triggered_special_action.explosion_actor_type == 62);
static_assert(timed_special_action.fuse_world_ticks == 100);
static_assert(inside_isometric_ellipse(128, 0, 128, 64));
static_assert(!inside_isometric_ellipse(129, 0, 128, 64));
static_assert(explosion_actor_extra_damage(34, 384, 0) == 128);
static_assert(explosion_actor_extra_damage(66, 255, 0) == 128);
static_assert(explosion_actor_extra_damage(66, 256, 0) == 0);
static_assert(!special_attention_rules.consumes_item);

}  // namespace m1937::sdk
