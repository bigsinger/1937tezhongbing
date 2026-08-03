#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

#include "Sprite.hpp"
#include "Types.hpp"

namespace m1937::sdk {

#pragma pack(push, 1)
// sub_4634D0 allocates one 12-byte record per inclusive Bresenham point.
struct RuntimeProjectilePathPointV1 final {
    std::int32_t world_x;                // +0x00
    std::int32_t unknown_04;             // +0x04
    std::int32_t world_y;                // +0x08
};

// Exact 0x44-byte object allocated by sub_464DF0 and initialized by
// sub_463290. Pointers stay uint32_t so the layout is host-independent.
struct RuntimeProjectileV1 final {
    std::uint32_t sprite_array_address;  // +0x00
    std::uint32_t path_array_address;    // +0x04
    std::int32_t path_point_count;       // +0x08
    std::int32_t sprite_count;           // +0x0C
    std::int32_t path_index;             // +0x10
    std::int32_t world_step_pixels;      // +0x14
    std::int32_t delivery_mode;          // +0x18
    std::int32_t active;                 // +0x1C
    std::int32_t direct_damage;          // +0x20
    std::int32_t mode_2_spawned;         // +0x24
    std::int32_t arc_height;             // +0x28
    float arc_coefficient;               // +0x2C
    std::int32_t arc_tick;               // +0x30
    std::int32_t owner_launch_x_offset;  // +0x34
    std::int32_t unknown_38;             // +0x38
    std::int32_t owner_vertical_baseline;// +0x3C
    std::uint32_t owner_actor_address;   // +0x40
};
#pragma pack(pop)

static_assert(sizeof(RuntimeProjectilePathPointV1) == 0x0C);
static_assert(offsetof(RuntimeProjectilePathPointV1, world_y) == 0x08);
static_assert(sizeof(RuntimeProjectileV1) == 0x44);
static_assert(offsetof(RuntimeProjectileV1, path_index) == 0x10);
static_assert(offsetof(RuntimeProjectileV1, world_step_pixels) == 0x14);
static_assert(offsetof(RuntimeProjectileV1, delivery_mode) == 0x18);
static_assert(offsetof(RuntimeProjectileV1, direct_damage) == 0x20);
static_assert(offsetof(RuntimeProjectileV1, arc_coefficient) == 0x2C);
static_assert(offsetof(RuntimeProjectileV1, owner_actor_address) == 0x40);

namespace projectile {

// Source-compatible alias for SDK releases that exposed this type here.
using SpriteTriplet = m1937::sdk::SpriteTriplet;

inline constexpr std::int32_t cell_width = 32;
inline constexpr std::int32_t cell_height = 16;
inline constexpr std::int32_t world_ticks_per_second = 60;

enum class DeliveryMode : std::int32_t {
    invisible_linear = 0,
    grenade_parabola = 1,
    // Effect 3 can select this owner-afterimage route in the executable, but
    // no caller of the effect dispatcher and no formal twelve-level weapon
    // profile requests it. Keep the numeric ABI without presenting it as a
    // supported campaign attack.
    dormant_owner_afterimage_trail = 2,
    dart_linear = 3,
    slingshot_linear = 4,
};

inline constexpr std::int32_t dormant_mode_2_effect_type = 3;
inline constexpr std::int32_t dormant_mode_2_initial_actor_type = 58;

enum class CollisionSemantics : std::uint8_t {
    layer3_actor_then_layer2_obstruction,
    ignore_actor_and_layer2_until_destination,
};

struct AttackRule final {
    std::int32_t attack_type;
    std::int32_t effect_type;
    DeliveryMode delivery_mode;
    std::int32_t world_step_pixels;
    std::int32_t runtime_actor_type;
    std::int32_t first_match_gfl_index;
    std::int32_t direct_damage;
    CollisionSemantics collision;
    std::int32_t impact_effect_type;
    std::int32_t impact_actor_type;
    std::int32_t impact_first_match_gfl_index;
    std::int32_t explosion_actor_type;
    std::int32_t explosion_first_match_gfl_index;
};

inline constexpr std::array<AttackRule, 6> attack_rules{{
    {1, 1, DeliveryMode::invisible_linear, 64, 0, 0, 2,
     CollisionSemantics::layer3_actor_then_layer2_obstruction,
     8, 60, 306, 0, 0},
    {2, 1, DeliveryMode::invisible_linear, 64, 0, 0, 2,
     CollisionSemantics::layer3_actor_then_layer2_obstruction,
     8, 60, 306, 0, 0},
    {3, 1, DeliveryMode::invisible_linear, 64, 0, 0, 2,
     CollisionSemantics::layer3_actor_then_layer2_obstruction,
     8, 60, 306, 0, 0},
    {6, 13, DeliveryMode::dart_linear, 16, 80, 251, 8,
     CollisionSemantics::layer3_actor_then_layer2_obstruction,
     8, 60, 306, 0, 0},
    {7, 14, DeliveryMode::slingshot_linear, 5, 81, 635, 1,
     CollisionSemantics::layer3_actor_then_layer2_obstruction,
     8, 60, 306, 0, 0},
    {9, 2, DeliveryMode::grenade_parabola, 8, 57, 528, 0,
     CollisionSemantics::ignore_actor_and_layer2_until_destination,
     4, 61, 19, 61, 19},
}};

inline constexpr std::int32_t explosion_damage = 128;
inline constexpr SizeI32 explosion_ellipse{128, 64};
inline constexpr std::int32_t explosion_alert_radius = 800;

constexpr std::int32_t owner_launch_x_offset(
    SpriteTriplet primary,
    SpriteTriplet tertiary) noexcept {
    return tertiary.x - primary.x;
}

constexpr std::int32_t owner_visual_height(
    SpriteTriplet primary,
    SpriteTriplet tertiary) noexcept {
    // The executable stores tertiary.z-primary.z in RuntimeProjectileV1
    // +0x3c and subtracts that value from the projectile actor's sprite Z.
    return primary.z - tertiary.z;
}

constexpr const AttackRule* find_attack_rule(
    std::int32_t attack_type) noexcept {
    for (const auto& rule : attack_rules) {
        if (rule.attack_type == attack_type) {
            return &rule;
        }
    }
    return nullptr;
}

constexpr std::int32_t absolute(std::int32_t value) noexcept {
    return value < 0 ? -value : value;
}

constexpr std::int32_t inclusive_path_point_count(
    PointI32 start, PointI32 destination) noexcept {
    const auto delta_x = absolute(destination.x - start.x);
    const auto delta_y = absolute(destination.y - start.y);
    return (delta_x > delta_y ? delta_x : delta_y) + 1;
}

constexpr std::int32_t resolution_world_ticks(
    std::int32_t path_point_count,
    std::int32_t world_step_pixels) noexcept {
    if (path_point_count <= 0 || world_step_pixels <= 0) {
        return 0;
    }
    return (path_point_count - 1 + world_step_pixels - 1) /
               world_step_pixels +
           1;
}

constexpr float original_arc_coefficient(
    std::int32_t path_point_count,
    std::int32_t world_step_pixels) noexcept {
    if (world_step_pixels <= 0) {
        return 0.0F;
    }
    const auto integer_denominator =
        path_point_count / world_step_pixels;
    return integer_denominator > 0
               ? static_cast<float>(world_step_pixels) /
                     static_cast<float>(integer_denominator)
               : static_cast<float>(world_step_pixels);
}

constexpr std::int32_t original_arc_height(
    std::int32_t world_step_pixels,
    std::int32_t arc_tick,
    float coefficient) noexcept {
    return world_step_pixels * arc_tick -
           static_cast<std::int32_t>(
               static_cast<float>(arc_tick) * coefficient *
               static_cast<float>(arc_tick));
}

}  // namespace projectile
}  // namespace m1937::sdk
