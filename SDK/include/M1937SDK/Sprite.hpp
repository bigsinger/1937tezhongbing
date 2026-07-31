#pragma once

#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

struct SpriteTriplet final {
    std::int32_t x;
    std::int32_t middle;
    std::int32_t z;
};

struct SpriteLookupDimensions final {
    std::int32_t columns;
    std::int32_t rows;

    [[nodiscard]] constexpr bool valid() const noexcept {
        return columns >= 0 && rows >= 0;
    }

    [[nodiscard]] constexpr std::size_t length() const noexcept {
        return valid()
            ? static_cast<std::size_t>(columns) *
                static_cast<std::size_t>(rows)
            : 0U;
    }
};

struct SpriteLookupOffset final {
    std::int32_t x;
    std::int32_t y;

    [[nodiscard]] constexpr bool operator==(
        const SpriteLookupOffset& other) const noexcept {
        return x == other.x && y == other.y;
    }
};

// sub_451060/sub_451090 use signed x86 IDIV semantics: truncate toward zero.
[[nodiscard]] constexpr SpriteLookupOffset sprite_lookup_top_left(
    std::int32_t actor_cell_x,
    std::int32_t actor_cell_y,
    SpriteTriplet primary,
    std::int32_t cell_width = 32,
    std::int32_t cell_height = 16) noexcept {
    if (cell_width <= 0 || cell_height <= 0)
        return {actor_cell_x, actor_cell_y};
    return {
        actor_cell_x - primary.x / cell_width,
        actor_cell_y - primary.z / cell_height,
    };
}

[[nodiscard]] constexpr SpriteLookupOffset sprite_lookup_offset(
    std::size_t row_major_index,
    SpriteLookupDimensions dimensions,
    SpriteTriplet primary,
    std::int32_t cell_width = 32,
    std::int32_t cell_height = 16) noexcept {
    if (!dimensions.valid() || dimensions.columns <= 0 ||
        row_major_index >= dimensions.length() ||
        cell_width <= 0 || cell_height <= 0)
        return {};
    return {
        static_cast<std::int32_t>(
            row_major_index % static_cast<std::size_t>(dimensions.columns)) -
            primary.x / cell_width,
        static_cast<std::int32_t>(
            row_major_index / static_cast<std::size_t>(dimensions.columns)) -
            primary.z / cell_height,
    };
}

// 32-bit in-process layout recovered from IEngineSpriteFrameGroup::Load
// (sub_427560). Pointer fields are uint32_t so the layout stays auditable
// when SDK tools are compiled as 64-bit processes.
#pragma pack(push, 1)
struct SpriteFrameGroupRuntime32 final {
    std::uint32_t unknown_000;
    std::uint32_t draw_order_row_lookup;       // +0x04, one value per column
    std::uint32_t movement_lookup;             // +0x08, Layer 3 mask
    std::uint32_t line_of_sight_lookup;        // +0x0C, Layer 2 mask
    SpriteTriplet primary;                     // +0x10
    SpriteTriplet secondary;                   // +0x1C
    SpriteTriplet tertiary;                    // +0x28
    std::int32_t frame_count;                  // +0x34
    std::byte unknown_038[0x14];
    std::int32_t lookup_columns;               // +0x4C
    std::int32_t lookup_rows;                  // +0x50
};
#pragma pack(pop)

static_assert(offsetof(SpriteFrameGroupRuntime32, draw_order_row_lookup) == 0x04);
static_assert(offsetof(SpriteFrameGroupRuntime32, movement_lookup) == 0x08);
static_assert(offsetof(SpriteFrameGroupRuntime32, line_of_sight_lookup) == 0x0C);
static_assert(offsetof(SpriteFrameGroupRuntime32, primary) == 0x10);
static_assert(offsetof(SpriteFrameGroupRuntime32, secondary) == 0x1C);
static_assert(offsetof(SpriteFrameGroupRuntime32, tertiary) == 0x28);
static_assert(offsetof(SpriteFrameGroupRuntime32, frame_count) == 0x34);
static_assert(offsetof(SpriteFrameGroupRuntime32, lookup_columns) == 0x4C);
static_assert(offsetof(SpriteFrameGroupRuntime32, lookup_rows) == 0x50);
static_assert(sizeof(SpriteFrameGroupRuntime32) == 0x54);

}  // namespace m1937::sdk
