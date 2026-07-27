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
    std::uint32_t unknown_00;
    std::uint32_t reaction_state;
    std::uint32_t default_attack_type;
    std::uint32_t current_hit_points;
    std::uint32_t unknown_10[4];
    std::uint32_t faction_id;
    std::uint32_t unknown_24[32];
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
static_assert(offsetof(VwfActorExtendedFieldsV5, faction_id) == 8 * 4);
static_assert(sizeof(VwfPatrolHeaderV1) == 12);
static_assert(std::is_standard_layout_v<VwfSceneEntityPrefixV5>);

}  // namespace m1937::sdk
