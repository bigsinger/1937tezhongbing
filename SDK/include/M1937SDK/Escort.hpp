#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "Addresses.hpp"

namespace m1937::sdk::escort {

// Source-backed neutral/recruit transitions dispatched by sub_454960. These
// are automatic proximity checks; the original handlers do not require a
// generic interaction key.
enum class CharacterIdentity : std::uint8_t {
    none,
    lao_zhao,
    tiedan,
    qiangzi,
    gu_ming,
    daniu,
};

enum class ProximityKind : std::uint8_t {
    strict_euclidean,
    inclusive_isometric_ellipse,
};

struct RescueRule final {
    std::int32_t engine_mission = 0;
    std::int32_t neutral_runtime_type = 0;
    std::array<CharacterIdentity, 4> eligible_rescuers{};
    std::size_t eligible_rescuer_count = 0;
    std::int32_t required_rescuer_runtime_type = 0;
    std::int32_t horizontal_radius = 0;
    ProximityKind proximity = ProximityKind::strict_euclidean;
    bool changes_faction_to_player = false;
    bool follows_rescuer = false;
    bool becomes_commandable = false;
};

inline constexpr std::int32_t player_faction_id = 3;
inline constexpr std::ptrdiff_t movement_path_state_offset = 0x1FC;
inline constexpr std::ptrdiff_t pursuit_target_offset = 0x23C;
inline constexpr std::uintptr_t pursuit_random_call_site_rva =
    rva::actor_pursuit_random_call;

inline constexpr RescueRule rules[] = {
    {1, 17, {CharacterIdentity::qiangzi}, 1, 0, 128,
        ProximityKind::strict_euclidean, true, true, false},
    {1, 3, {CharacterIdentity::qiangzi}, 1, 0, 128,
        ProximityKind::strict_euclidean, true, true, false},
    {2, 19, {CharacterIdentity::gu_ming}, 1, 91, 128,
        ProximityKind::inclusive_isometric_ellipse, false, true, false},
    {3, 1, {CharacterIdentity::lao_zhao}, 1, 2, 128,
        ProximityKind::strict_euclidean, true, false, true},
    {5, 10, {CharacterIdentity::daniu}, 1, 8, 128,
        ProximityKind::strict_euclidean, true, false, true},
    {8, 18, {CharacterIdentity::gu_ming}, 1, 0, 128,
        ProximityKind::inclusive_isometric_ellipse, true, true, false},
    {8, 19,
        {CharacterIdentity::gu_ming, CharacterIdentity::qiangzi,
            CharacterIdentity::lao_zhao, CharacterIdentity::tiedan},
        4, 0, 48, ProximityKind::inclusive_isometric_ellipse,
        true, true, false},
    {8, 26,
        {CharacterIdentity::gu_ming, CharacterIdentity::qiangzi,
            CharacterIdentity::lao_zhao, CharacterIdentity::tiedan},
        4, 0, 48, ProximityKind::inclusive_isometric_ellipse,
        true, true, false},
};

constexpr const RescueRule* find_rule(
    std::int32_t engine_mission,
    std::int32_t neutral_runtime_type) noexcept {
    for (const auto& rule : rules) {
        if (rule.engine_mission == engine_mission &&
            rule.neutral_runtime_type == neutral_runtime_type) {
            return &rule;
        }
    }
    return nullptr;
}

constexpr bool rescuer_is_eligible(
    const RescueRule& rule,
    CharacterIdentity identity,
    std::int32_t runtime_type) noexcept {
    bool identity_matched = false;
    for (std::size_t index = 0; index < rule.eligible_rescuer_count; ++index) {
        if (rule.eligible_rescuers[index] == identity) {
            identity_matched = true;
            break;
        }
    }
    return identity_matched &&
        (rule.required_rescuer_runtime_type == 0 ||
            rule.required_rescuer_runtime_type == runtime_type);
}

constexpr bool within_rescue_range(
    const RescueRule& rule,
    double offset_x,
    double offset_y) noexcept {
    if (rule.horizontal_radius <= 0)
        return false;
    const auto radius = static_cast<double>(rule.horizontal_radius);
    if (rule.proximity == ProximityKind::strict_euclidean) {
        return offset_x * offset_x + offset_y * offset_y < radius * radius;
    }
    const auto vertical_radius = radius * 0.5;
    return offset_x * offset_x / (radius * radius) +
        offset_y * offset_y / (vertical_radius * vertical_radius) <= 1.0;
}

static_assert(sizeof(rules) / sizeof(rules[0]) == 8);
static_assert(find_rule(2, 19) != nullptr);
static_assert(!find_rule(2, 19)->changes_faction_to_player);
static_assert(find_rule(3, 1)->becomes_commandable);
static_assert(find_rule(5, 10)->becomes_commandable);
static_assert(rescuer_is_eligible(
    *find_rule(2, 19), CharacterIdentity::gu_ming, 91));
static_assert(!rescuer_is_eligible(
    *find_rule(2, 19), CharacterIdentity::gu_ming, 10));
static_assert(within_rescue_range(*find_rule(1, 17), 127.0, 0.0));
static_assert(!within_rescue_range(*find_rule(1, 17), 128.0, 0.0));
static_assert(within_rescue_range(*find_rule(8, 19), 48.0, 0.0));
static_assert(!within_rescue_range(*find_rule(8, 19), 0.0, 24.01));

}  // namespace m1937::sdk::escort
