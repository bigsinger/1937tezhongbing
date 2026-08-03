#pragma once

#include <cstdint>

namespace m1937::sdk::mission7_exchange {

// Recovered from Mission7DocumentCarrierUpdate (sub_459840) and
// Mission7DocumentRecipientUpdate (sub_4596E0).
inline constexpr std::int32_t engine_mission_number = 7;
inline constexpr std::int32_t document_item_id = 101;
inline constexpr std::int32_t document_world_actor_type = 101;
inline constexpr std::int32_t document_world_gfl_index = 246;

inline constexpr std::int32_t carrier_scene_index = 1457;
inline constexpr std::int32_t carrier_runtime_actor_type = 15;
inline constexpr std::int32_t recipient_scene_index = 1460;
inline constexpr std::int32_t recipient_runtime_actor_type = 22;
inline constexpr std::int32_t exit_detector_scene_index = 1462;
inline constexpr std::int32_t exit_detector_runtime_actor_type = 100;

inline constexpr float carrier_handoff_radius = 32.0f;
inline constexpr float recipient_chase_radius = 256.0f;
inline constexpr float document_drop_offset_x = -16.0f;
inline constexpr float document_drop_offset_y = 0.0f;

constexpr bool within_radius(
    float delta_x,
    float delta_y,
    float radius) noexcept {
    return delta_x * delta_x + delta_y * delta_y <= radius * radius;
}

constexpr bool can_carrier_place_document(
    std::int32_t mission_number,
    bool carrier_alive,
    std::int32_t carrier_type,
    bool carrier_has_document,
    std::int32_t exit_type,
    float delta_x,
    float delta_y) noexcept {
    return mission_number == engine_mission_number && carrier_alive &&
        carrier_type == carrier_runtime_actor_type && carrier_has_document &&
        exit_type == exit_detector_runtime_actor_type &&
        within_radius(delta_x, delta_y, carrier_handoff_radius);
}

constexpr bool can_recipient_pursue_document(
    std::int32_t mission_number,
    bool recipient_alive,
    std::int32_t recipient_type,
    bool recipient_has_document,
    bool document_available,
    std::int32_t world_actor_type,
    float delta_x,
    float delta_y) noexcept {
    return mission_number == engine_mission_number && recipient_alive &&
        recipient_type == recipient_runtime_actor_type &&
        !recipient_has_document && document_available &&
        world_actor_type == document_world_actor_type &&
        within_radius(delta_x, delta_y, recipient_chase_radius);
}

static_assert(can_carrier_place_document(7, true, 15, true, 100, 32, 0));
static_assert(!can_carrier_place_document(7, true, 15, true, 100, 33, 0));
static_assert(can_recipient_pursue_document(
    7, true, 22, false, true, 101, 256, 0));
static_assert(!can_recipient_pursue_document(
    7, true, 22, true, true, 101, 1, 0));

}  // namespace m1937::sdk::mission7_exchange
