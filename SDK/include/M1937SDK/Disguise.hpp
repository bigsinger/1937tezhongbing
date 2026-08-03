#pragma once

#include <array>
#include <cstdint>

namespace m1937::sdk {

inline constexpr std::int32_t tie_dan_covert_runtime_type = 9;
inline constexpr std::int32_t gu_ming_normal_runtime_type = 10;
inline constexpr std::int32_t gu_ming_disguised_runtime_type = 91;
inline constexpr std::int32_t gu_ming_normal_gfl_index = 270;
inline constexpr std::int32_t gu_ming_disguised_gfl_index = 272;
inline constexpr std::int32_t player_faction_id = 3;
inline constexpr std::int32_t disguised_enemy_faction_id = 1;
inline constexpr std::int32_t japanese_uniform_item_id = 54;
inline constexpr std::int32_t civilian_clothing_item_id = 92;
inline constexpr std::int32_t special_attention_item_id = 99;
inline constexpr std::int32_t disguise_change_tick_limit = 100;
inline constexpr std::int32_t disguise_recovery_tick_limit = 100;
inline constexpr std::int32_t disguise_observer_radius = 640;
inline constexpr std::int32_t disguise_close_detection_radius = 128;
inline constexpr std::int32_t cover_actor_updates_per_second = 60;

struct DisguiseTransition final {
    std::int32_t from_runtime_type;
    std::int32_t used_item_id;
    std::int32_t to_runtime_type;
    std::int32_t to_gfl_index;
    std::int32_t to_faction_id;
    std::int32_t granted_backpack_item_id;
    std::int32_t granted_weapon_item_id;
    std::int32_t removed_weapon_item_id;
};

inline constexpr std::array<DisguiseTransition, 2>
    gu_ming_disguise_transitions{{
        {
            gu_ming_normal_runtime_type,
            japanese_uniform_item_id,
            gu_ming_disguised_runtime_type,
            gu_ming_disguised_gfl_index,
            disguised_enemy_faction_id,
            civilian_clothing_item_id,
            special_attention_item_id,
            0,
        },
        {
            gu_ming_disguised_runtime_type,
            civilian_clothing_item_id,
            gu_ming_normal_runtime_type,
            gu_ming_normal_gfl_index,
            player_faction_id,
            japanese_uniform_item_id,
            0,
            special_attention_item_id,
        },
    }};

constexpr const DisguiseTransition* disguise_transition_for(
    std::int32_t runtime_type,
    std::int32_t item_id) noexcept {
    for (const auto& transition : gu_ming_disguise_transitions) {
        if (transition.from_runtime_type == runtime_type &&
            transition.used_item_id == item_id)
            return &transition;
    }
    return nullptr;
}

constexpr bool disguise_breaks_on_attack(
    std::int32_t runtime_type,
    std::int32_t attack_type) noexcept {
    return runtime_type == gu_ming_disguised_runtime_type &&
           (attack_type == 1 || attack_type == 4);
}

// sub_456AB0 dispatches sub_45EC20 only after type 9 completes a target or
// container pickup.  sub_459200 and sub_459370 then use the same faction-1
// cover and strict 101-update recovery fields for types 9 and 91.
constexpr bool pickup_breaks_cover(std::int32_t runtime_type) noexcept {
    return runtime_type == tie_dan_covert_runtime_type;
}

constexpr bool has_cover_recovery(std::int32_t runtime_type) noexcept {
    return runtime_type == tie_dan_covert_runtime_type ||
           runtime_type == gu_ming_disguised_runtime_type;
}

enum class DisguiseDetectionMode : std::uint8_t {
    none,
    ordinary_vision,
    close_without_line_of_sight,
};

constexpr bool inside_disguise_ellipse(
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

constexpr bool inside_disguise_radius_exclusive(
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

// Recovered from sub_45C390 and the mission-specific type-91 checks in the
// actor update dispatch. Type 4/12 use ordinary directional visibility.
// Mission 2 type 19/26 and mission 8 type 18 use a 128x64 ellipse without
// LOS; mission 6 type 24 uses a strict 128-pixel Euclidean radius.
constexpr DisguiseDetectionMode disguise_detection_mode(
    std::int32_t observer_runtime_type,
    std::int32_t mission_number,
    std::int32_t delta_x,
    std::int32_t delta_y) noexcept {
    if (observer_runtime_type == 4 || observer_runtime_type == 12)
        return DisguiseDetectionMode::ordinary_vision;
    if (mission_number == 2 &&
        (observer_runtime_type == 19 || observer_runtime_type == 26) &&
        inside_disguise_ellipse(
            delta_x,
            delta_y,
            disguise_close_detection_radius,
            disguise_close_detection_radius / 2))
        return DisguiseDetectionMode::close_without_line_of_sight;
    if (mission_number == 6 && observer_runtime_type == 24 &&
        inside_disguise_radius_exclusive(
            delta_x, delta_y, disguise_close_detection_radius))
        return DisguiseDetectionMode::close_without_line_of_sight;
    if (mission_number == 8 && observer_runtime_type == 18 &&
        inside_disguise_ellipse(
            delta_x,
            delta_y,
            disguise_close_detection_radius,
            disguise_close_detection_radius / 2))
        return DisguiseDetectionMode::close_without_line_of_sight;
    return DisguiseDetectionMode::none;
}

static_assert(
    disguise_transition_for(10, 54)->to_runtime_type == 91);
static_assert(
    disguise_transition_for(91, 92)->removed_weapon_item_id == 99);
static_assert(disguise_breaks_on_attack(91, 1));
static_assert(disguise_breaks_on_attack(91, 4));
static_assert(!disguise_breaks_on_attack(91, 11));
static_assert(pickup_breaks_cover(9));
static_assert(!pickup_breaks_cover(91));
static_assert(has_cover_recovery(9));
static_assert(has_cover_recovery(91));
static_assert(!has_cover_recovery(10));

}  // namespace m1937::sdk
