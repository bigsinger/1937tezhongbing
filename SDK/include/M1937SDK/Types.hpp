#pragma once

#include <cstddef>
#include <cstdint>
#include <type_traits>

namespace m1937::sdk {

struct PointI32 final {
    std::int32_t x;
    std::int32_t y;
};

struct SizeI32 final {
    std::int32_t width;
    std::int32_t height;
};

#pragma pack(push, 1)

// Serialized prefix of a version-5 SLIST1 scene entity. Unknown members remain
// byte arrays until their semantics are proven; offsets are nevertheless fixed
// so plugins do not duplicate fragile numeric constants.
struct VwfSceneEntityPrefixV5 final {
    std::uint32_t format_version;       // +0x00
    std::uint32_t unknown_04;           // +0x04
    std::int32_t database_entry_id;     // +0x08
    std::byte unknown_0c[32];           // +0x0C
    std::uint32_t direction_index;      // +0x2C
    std::uint32_t death_state;          // +0x30
    std::byte unknown_34[4];            // +0x34
    std::uint32_t crawl_state;          // +0x38
    std::int32_t world_x;               // +0x3C
    std::int32_t world_y;               // +0x40
    std::byte unknown_44[36];           // +0x44
    std::int32_t reference_x;           // +0x68
    std::byte unknown_6c[4];            // +0x6C
    std::int32_t reference_y;           // +0x70
    std::byte unknown_74[84];           // +0x74
};

struct VwfActorExtendedFieldsV5 final {
    std::uint32_t route_update_active;       // field 0 -> RuntimeActor +0x184
    std::uint32_t contact_state;             // field 1 -> RuntimeActor +0x250
    std::uint32_t default_attack_type;       // field 2 -> RuntimeActor +0x20C
    std::uint32_t current_hit_points;        // field 3 -> RuntimeActor +0x1C0
    std::uint32_t hidden_or_removed;         // field 4 -> RuntimeActor +0x03C
    std::uint32_t unknown_runtime_1c4;        // field 5 -> RuntimeActor +0x1C4
    std::uint32_t unknown_runtime_1c8;        // field 6 -> RuntimeActor +0x1C8
    std::uint32_t burial_or_disguise_ready;  // field 7 -> RuntimeActor +0x1CC
    std::uint32_t unknown_runtime_1d0;        // field 8 -> RuntimeActor +0x1D0
    std::uint32_t hypnosis_active;            // field 9 -> RuntimeActor +0x238
    std::uint32_t unknown_runtime_240;        // field 10 -> RuntimeActor +0x240
    std::uint32_t unknown_runtime_244;        // field 11 -> RuntimeActor +0x244
    std::uint32_t corpse_discovered;          // field 12 -> RuntimeActor +0x258
    std::uint32_t target_lost;                // field 13 -> RuntimeActor +0x254
    std::uint32_t movement_active;            // field 14 -> RuntimeActor +0x1D8
    std::uint32_t unknown_runtime_1e0;        // field 15 -> RuntimeActor +0x1E0
    std::uint32_t movement_path_state;        // field 16 -> RuntimeActor +0x1FC
    std::uint32_t movement_mode;              // field 17 -> RuntimeActor +0x208
    std::uint32_t resolved_goal_x;            // field 18 -> RuntimeActor +0x218
    std::uint32_t unknown_runtime_21c;        // field 19 -> RuntimeActor +0x21C
    std::uint32_t resolved_goal_y;            // field 20 -> RuntimeActor +0x220
    std::uint32_t search_delay_limit;         // field 21 -> RuntimeActor +0x248
    std::uint32_t search_delay_counter;       // field 22 -> RuntimeActor +0x24C
    std::uint32_t reaction_state;             // field 23 -> RuntimeActor +0x25C
    std::uint32_t unknown_runtime_260;        // field 24 -> RuntimeActor +0x260
    std::uint32_t poison_active;               // field 25 -> RuntimeActor +0x264
    std::uint32_t poison_counter;              // field 26 -> RuntimeActor +0x268
    std::uint32_t poison_counter_limit;        // field 27 -> RuntimeActor +0x26C
    std::uint32_t hypnosis_counter_limit;      // field 28 -> RuntimeActor +0x278
    std::uint32_t hypnosis_counter;            // field 29 -> RuntimeActor +0x27C
    std::uint32_t unknown_runtime_274;        // field 30 -> RuntimeActor +0x274
    std::uint32_t unknown_runtime_1b0;        // field 31 -> RuntimeActor +0x1B0
    std::uint32_t unknown_runtime_284;        // field 32 -> RuntimeActor +0x284
    std::uint32_t unknown_runtime_280;        // field 33 -> RuntimeActor +0x280
    std::uint32_t burial_action_started;      // field 34 -> RuntimeActor +0x288
    std::uint32_t disguise_change_pending;    // field 35 -> RuntimeActor +0x28C
    std::uint32_t path_override_or_attention; // field 36 -> RuntimeActor +0x290
    std::uint32_t disguise_recovery_active;   // field 37 -> RuntimeActor +0x294
    std::uint32_t disguise_recovery_limit;    // field 38 -> RuntimeActor +0x298
    std::uint32_t recovery_or_pursuit_counter; // field 39 -> RuntimeActor +0x29C
    std::uint32_t unknown_runtime_1dc;        // field 40 -> RuntimeActor +0x1DC
};

// sub_453FE0 reads these 24 values into a temporary and never stores them in
// RuntimeActorV1. They remain part of the serialized record and must be
// preserved by format tools even though the supported executable ignores them.
struct VwfActorExtendedReservedTailV5 final {
    std::uint32_t values[24];
};

struct VwfPatrolHeaderV1 final {
    std::uint32_t signature;
    std::uint32_t point_count;
    std::uint32_t format_version;
    // Two point arrays and the runtime state follow; use VwfPatrolLayout below
    // to calculate their offsets from point_count.
};

#pragma pack(pop)

struct VwfPatrolLayout final {
    static constexpr std::size_t record_offset = 204;
    static constexpr std::uint32_t signature = 1001;
    static constexpr std::uint32_t format_version = 1;

    static constexpr std::size_t working_points(std::size_t) noexcept {
        return 12;
    }
    static constexpr std::size_t repeated_count(
        std::size_t point_count) noexcept {
        return 12 + point_count * 8;
    }
    static constexpr std::size_t current_waypoint(
        std::size_t point_count) noexcept {
        return 16 + point_count * 8;
    }
    static constexpr std::size_t persistent_flag(
        std::size_t point_count) noexcept {
        return 20 + point_count * 8;
    }
    static constexpr std::size_t cached_world_x(
        std::size_t point_count) noexcept {
        return 24 + point_count * 8;
    }
    static constexpr std::size_t cached_world_y(
        std::size_t point_count) noexcept {
        return 28 + point_count * 8;
    }
    static constexpr std::size_t waypoints(
        std::size_t point_count) noexcept {
        return 32 + point_count * 8;
    }
};

struct VwfLayout final {
    static constexpr std::size_t world_header_size = 331;
    static constexpr std::size_t terrain_preamble_size = 235;
    static constexpr std::size_t terrain_layer_count = 5;
    static constexpr std::size_t terrain_layer_header_size = 16;
    static constexpr std::size_t scene_list_header_size = 137;
    static constexpr std::size_t scene_entity_prefix_size = 200;
    static constexpr std::size_t actor_extended_field_count = 41;
    static constexpr std::size_t actor_extended_tail_u32_count = 24;
    static constexpr std::int32_t cell_width = 32;
    static constexpr std::int32_t cell_height = 16;
};

static_assert(sizeof(PointI32) == 8);
static_assert(sizeof(VwfSceneEntityPrefixV5) == 200);
static_assert(offsetof(VwfSceneEntityPrefixV5, direction_index) == 44);
static_assert(offsetof(VwfSceneEntityPrefixV5, world_x) == 60);
static_assert(offsetof(VwfSceneEntityPrefixV5, world_y) == 64);
static_assert(offsetof(VwfSceneEntityPrefixV5, reference_x) == 104);
static_assert(offsetof(VwfSceneEntityPrefixV5, reference_y) == 112);
static_assert(sizeof(VwfActorExtendedFieldsV5) == 41 * sizeof(std::uint32_t));
static_assert(offsetof(VwfActorExtendedFieldsV5, contact_state) == 1 * 4);
static_assert(offsetof(VwfActorExtendedFieldsV5, default_attack_type) == 2 * 4);
static_assert(offsetof(VwfActorExtendedFieldsV5, current_hit_points) == 3 * 4);
static_assert(offsetof(VwfActorExtendedFieldsV5, reaction_state) == 23 * 4);
static_assert(offsetof(VwfActorExtendedFieldsV5, search_delay_limit) == 21 * 4);
static_assert(sizeof(VwfActorExtendedReservedTailV5) == 24 * sizeof(std::uint32_t));
static_assert(sizeof(VwfPatrolHeaderV1) == 12);
static_assert(std::is_standard_layout_v<VwfSceneEntityPrefixV5>);

}  // namespace m1937::sdk
