#pragma once

#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

// Runtime layout recovered from the supported 2001 executable. Pointer fields
// intentionally use uint32_t so the ABI remains the 32-bit game's ABI even
// when SDK layout tests are built by a 64-bit host compiler.
#pragma pack(push, 1)
struct RuntimeActorV1 final {
    std::byte unknown_000[100];
    std::int32_t database_entry_id;       // +0x064
    std::byte unknown_068[12];
    std::int32_t faction_id;              // +0x074
    std::byte unknown_078[96];
    std::int32_t world_x;                 // +0x0D8
    std::byte unknown_0dc[4];
    std::int32_t world_y;                 // +0x0E0
    std::byte unknown_0e4[148];
    std::int32_t facing_direction;        // +0x178, 1..8
    std::byte unknown_17c[12];
    std::int32_t dead_or_disabled;         // +0x188
    std::byte unknown_18c[4];
    std::int32_t target_status;            // +0x190
    std::int32_t goal_kind;                // +0x194
    std::int32_t last_known_x;             // +0x198
    std::int32_t last_known_y;             // +0x19C
    std::uint32_t interest_actor_address;  // +0x1A0
    std::int32_t goal_repath_pending;       // +0x1A4
    std::int32_t goal_motion_pending;       // +0x1A8
    std::byte unknown_1ac[40];
    std::int32_t search_or_return_active;   // +0x1D4
    std::byte unknown_1d8[60];
    std::uint32_t target_actor_address;     // +0x214
    std::byte unknown_218[48];
    std::int32_t search_delay_limit;        // +0x248
    std::int32_t search_delay_counter;      // +0x24C
    std::int32_t contact_state;             // +0x250
    std::int32_t target_lost;               // +0x254
    std::byte unknown_258[4];
    std::int32_t reaction_state;            // +0x25C
    std::byte unknown_260[48];
    std::int32_t path_override_active;       // +0x290
};

struct RuntimeWorldV1 final {
    std::byte unknown_000[24];
    std::uint32_t actor_array_address;       // +0x018
    std::byte unknown_01c[32];
    std::int32_t actor_count;                // +0x03C
};
#pragma pack(pop)

static_assert(offsetof(RuntimeActorV1, database_entry_id) == 0x064);
static_assert(offsetof(RuntimeActorV1, faction_id) == 0x074);
static_assert(offsetof(RuntimeActorV1, world_x) == 0x0D8);
static_assert(offsetof(RuntimeActorV1, world_y) == 0x0E0);
static_assert(offsetof(RuntimeActorV1, facing_direction) == 0x178);
static_assert(offsetof(RuntimeActorV1, dead_or_disabled) == 0x188);
static_assert(offsetof(RuntimeActorV1, goal_kind) == 0x194);
static_assert(offsetof(RuntimeActorV1, last_known_x) == 0x198);
static_assert(offsetof(RuntimeActorV1, last_known_y) == 0x19C);
static_assert(offsetof(RuntimeActorV1, interest_actor_address) == 0x1A0);
static_assert(offsetof(RuntimeActorV1, goal_repath_pending) == 0x1A4);
static_assert(offsetof(RuntimeActorV1, goal_motion_pending) == 0x1A8);
static_assert(offsetof(RuntimeActorV1, search_or_return_active) == 0x1D4);
static_assert(offsetof(RuntimeActorV1, target_actor_address) == 0x214);
static_assert(offsetof(RuntimeActorV1, search_delay_limit) == 0x248);
static_assert(offsetof(RuntimeActorV1, contact_state) == 0x250);
static_assert(offsetof(RuntimeActorV1, target_lost) == 0x254);
static_assert(offsetof(RuntimeActorV1, reaction_state) == 0x25C);
static_assert(offsetof(RuntimeActorV1, path_override_active) == 0x290);
static_assert(sizeof(RuntimeActorV1) == 0x294);
static_assert(offsetof(RuntimeWorldV1, actor_array_address) == 0x18);
static_assert(offsetof(RuntimeWorldV1, actor_count) == 0x3C);

}  // namespace m1937::sdk
