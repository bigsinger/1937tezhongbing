#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

enum class InventoryContainerKind : std::uint8_t {
    backpack = 0,
    weapon = 1
};

struct InventoryDestination final {
    InventoryContainerKind container = InventoryContainerKind::backpack;
    std::int32_t quantity_mode = 0;
};

// Recovered from the complete branch table in M1937.exe sub_45AE10.
// Item IDs outside the explicit weapon groups enter actor +0x228.
constexpr InventoryDestination classify_original_item(
    std::int32_t item_id) noexcept {
    switch (item_id) {
    case 36:
    case 37:
    case 38:
        return {InventoryContainerKind::weapon, 2};
    case 39:
    case 40:
    case 42:
    case 99:
        return {InventoryContainerKind::weapon, 1};
    case 41:
    case 43:
    case 44:
    case 45:
        return {InventoryContainerKind::weapon, 0};
    default:
        return {InventoryContainerKind::backpack, 0};
    }
}

struct WorldPickupDefinition final {
    std::int32_t database_entry_id = 0;
    std::int32_t item_id = 0;
    InventoryContainerKind container = InventoryContainerKind::backpack;
    std::int32_t quantity = 1;
    std::int32_t quantity_mode = 0;
};

constexpr WorldPickupDefinition make_original_world_pickup(
    std::int32_t database_entry_id,
    std::int32_t item_id) noexcept {
    const auto destination = classify_original_item(item_id);
    return {
        database_entry_id,
        item_id,
        destination.container,
        1,
        destination.quantity_mode};
}

// DBL header[2] supplies item_id. sub_453F70 proves that each world pickup
// transfers exactly one unit through sub_45AE10.
inline constexpr std::array<WorldPickupDefinition, 10>
    original_world_pickups = {{
        make_original_world_pickup(982, 38),
        make_original_world_pickup(983, 46),
        make_original_world_pickup(984, 43),
        make_original_world_pickup(986, 44),
        make_original_world_pickup(987, 36),
        make_original_world_pickup(988, 41),
        make_original_world_pickup(990, 54),
        make_original_world_pickup(993, 51),
        make_original_world_pickup(998, 45),
        make_original_world_pickup(999, 47),
    }};

// DBL 1003 has item-like header[2] value 53, but the original routes it
// through the damageable gasoline-barrel lifecycle rather than pickup code.
inline constexpr std::int32_t gasoline_barrel_database_entry_id = 1003;
inline constexpr std::int32_t gasoline_barrel_item_id = 53;

constexpr const WorldPickupDefinition* find_original_world_pickup(
    std::int32_t database_entry_id) noexcept {
    for (const auto& pickup : original_world_pickups) {
        if (pickup.database_entry_id == database_entry_id)
            return &pickup;
    }
    return nullptr;
}

static_assert(
    classify_original_item(36).container ==
        InventoryContainerKind::weapon &&
    classify_original_item(36).quantity_mode == 2);
static_assert(
    classify_original_item(45).container ==
        InventoryContainerKind::weapon &&
    classify_original_item(45).quantity_mode == 0);
static_assert(
    classify_original_item(46).container ==
        InventoryContainerKind::backpack &&
    classify_original_item(46).quantity_mode == 0);
static_assert(
    find_original_world_pickup(998) != nullptr &&
    find_original_world_pickup(998)->item_id == 45);
static_assert(find_original_world_pickup(1003) == nullptr);

}  // namespace m1937::sdk
