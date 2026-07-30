#pragma once

#include <array>
#include <cstdint>

namespace m1937::sdk {

struct OrdinaryAttackRule {
    std::int32_t attack_type;
    std::int32_t ordinary_damage;
    std::int32_t direct_actor_hit_count;
    std::int32_t coordinate_projectile_count;
};

inline constexpr std::array<OrdinaryAttackRule, 7> ordinary_attack_rules{{
    {1, 2, 1, 1},
    {2, 2, 1, 1},
    {3, 2, 1, 3},
    {4, 8, 1, 0},
    {5, 16, 1, 0},
    {6, 8, 1, 1},
    {7, 1, 1, 1},
}};

inline constexpr std::array<std::int32_t, 8> low_damage_immune_actor_types{{
    34,
    86,
    87,
    88,
    94,
    95,
    96,
    97,
}};
inline constexpr std::int32_t low_damage_immunity_threshold = 32;

constexpr const OrdinaryAttackRule* find_ordinary_attack_rule(
    std::int32_t attack_type) noexcept {
    for (const auto& rule : ordinary_attack_rules) {
        if (rule.attack_type == attack_type) {
            return &rule;
        }
    }
    return nullptr;
}

constexpr std::int32_t direct_actor_damage(
    std::int32_t attack_type,
    std::int32_t attacker_runtime_type) noexcept {
    if (attack_type == 2 && attacker_runtime_type == 1) {
        return 16;
    }
    if (attack_type == 4 && attacker_runtime_type == 56) {
        return 1;
    }
    const auto* rule = find_ordinary_attack_rule(attack_type);
    return rule == nullptr ? 0 : rule->ordinary_damage;
}

constexpr bool runtime_type_has_low_damage_immunity(
    std::int32_t runtime_type) noexcept {
    for (const auto candidate : low_damage_immune_actor_types) {
        if (candidate == runtime_type) {
            return true;
        }
    }
    return false;
}

constexpr std::int32_t accepted_actor_damage(
    std::int32_t target_runtime_type,
    std::int32_t requested_damage) noexcept {
    if (requested_damage <= 0) {
        return 0;
    }
    if (requested_damage < low_damage_immunity_threshold &&
        runtime_type_has_low_damage_immunity(target_runtime_type)) {
        return 0;
    }
    return requested_damage;
}

static_assert(direct_actor_damage(2, 1) == 16);
static_assert(direct_actor_damage(2, 5) == 2);
static_assert(direct_actor_damage(4, 56) == 1);
static_assert(direct_actor_damage(4, 1) == 8);
static_assert(find_ordinary_attack_rule(3)->direct_actor_hit_count == 1);
static_assert(find_ordinary_attack_rule(3)->coordinate_projectile_count == 3);
static_assert(accepted_actor_damage(34, 31) == 0);
static_assert(accepted_actor_damage(34, 32) == 32);

} // namespace m1937::sdk
