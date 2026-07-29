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
    // Matches VWF database_header_values[2]. This is a runtime actor type,
    // not the authored DBL database_entry_id.
    std::int32_t runtime_type;            // +0x064
    std::byte unknown_068[12];
    std::int32_t faction_id;              // +0x074
    std::byte unknown_078[96];
    std::int32_t world_x;                 // +0x0D8
    std::int32_t world_height;            // +0x0DC
    std::int32_t world_y;                 // +0x0E0
    std::byte unknown_0e4[36];
    std::int32_t navigation_cell_x;       // +0x108
    std::int32_t navigation_height_cell;  // +0x10C
    std::int32_t navigation_cell_y;       // +0x110
    std::byte unknown_114[100];
    std::int32_t facing_direction;        // +0x178, 1..8
    std::byte unknown_17c[12];
    std::int32_t dead_or_disabled;         // +0x188
    std::byte unknown_18c[4];
    std::int32_t target_status;            // +0x190
    std::int32_t goal_kind;                // +0x194
    std::int32_t goal_x;                   // +0x198
    std::int32_t goal_y;                   // +0x19C
    std::uint32_t interest_actor_address;  // +0x1A0
    std::int32_t command_variant;           // +0x1A4
    std::int32_t command_pending;           // +0x1A8
    std::int32_t selected_for_command;      // +0x1AC
    std::byte unknown_1b0[16];
    std::int32_t current_hit_points;        // +0x1C0
    std::byte unknown_1c4[16];
    std::int32_t search_or_return_active;   // +0x1D4
    std::int32_t movement_active;           // +0x1D8
    std::byte unknown_1dc[32];
    std::int32_t movement_path_state;       // +0x1FC
    std::byte unknown_200[8];
    std::int32_t movement_mode;             // +0x208
    std::int32_t default_attack_type;        // +0x20C
    std::byte unknown_210[4];
    std::uint32_t target_actor_address;     // +0x214
    std::int32_t resolved_goal_x;           // +0x218
    std::byte unknown_21c[4];
    std::int32_t resolved_goal_y;           // +0x220
    std::byte unknown_224[36];
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

struct RuntimeViewportControllerV1 final {
    std::byte unknown_000[40];
    std::int32_t viewport_width;              // +0x028
    std::int32_t viewport_height;             // +0x02C
    std::int32_t camera_left;                 // +0x030
    std::int32_t camera_top;                  // +0x034
    std::int32_t camera_right;                // +0x038
    std::int32_t camera_bottom;               // +0x03C
    std::byte unknown_040[4];
    std::int32_t input_camera_left;           // +0x044
    std::int32_t input_camera_top;            // +0x048
    std::int32_t grid_width;                  // +0x04C
    std::int32_t grid_height;                 // +0x050
    std::int32_t world_width;                 // +0x054
    std::int32_t world_height;                // +0x058
    std::int32_t scroll_velocity;             // +0x05C
    std::int32_t scroll_velocity_limit;       // +0x060
    std::int32_t scroll_direction;            // +0x064
    std::int32_t render_width;                // +0x068
    std::int32_t render_height;               // +0x06C
    std::int32_t scroll_disabled;             // +0x070
};
#pragma pack(pop)

static_assert(offsetof(RuntimeActorV1, runtime_type) == 0x064);
static_assert(offsetof(RuntimeActorV1, faction_id) == 0x074);
static_assert(offsetof(RuntimeActorV1, world_x) == 0x0D8);
static_assert(offsetof(RuntimeActorV1, world_height) == 0x0DC);
static_assert(offsetof(RuntimeActorV1, world_y) == 0x0E0);
static_assert(offsetof(RuntimeActorV1, navigation_cell_x) == 0x108);
static_assert(offsetof(RuntimeActorV1, navigation_height_cell) == 0x10C);
static_assert(offsetof(RuntimeActorV1, navigation_cell_y) == 0x110);
static_assert(offsetof(RuntimeActorV1, facing_direction) == 0x178);
static_assert(offsetof(RuntimeActorV1, dead_or_disabled) == 0x188);
static_assert(offsetof(RuntimeActorV1, goal_kind) == 0x194);
static_assert(offsetof(RuntimeActorV1, goal_x) == 0x198);
static_assert(offsetof(RuntimeActorV1, goal_y) == 0x19C);
static_assert(offsetof(RuntimeActorV1, interest_actor_address) == 0x1A0);
static_assert(offsetof(RuntimeActorV1, command_variant) == 0x1A4);
static_assert(offsetof(RuntimeActorV1, command_pending) == 0x1A8);
static_assert(offsetof(RuntimeActorV1, selected_for_command) == 0x1AC);
static_assert(offsetof(RuntimeActorV1, current_hit_points) == 0x1C0);
static_assert(offsetof(RuntimeActorV1, search_or_return_active) == 0x1D4);
static_assert(offsetof(RuntimeActorV1, movement_active) == 0x1D8);
static_assert(offsetof(RuntimeActorV1, movement_path_state) == 0x1FC);
static_assert(offsetof(RuntimeActorV1, movement_mode) == 0x208);
static_assert(offsetof(RuntimeActorV1, default_attack_type) == 0x20C);
static_assert(offsetof(RuntimeActorV1, target_actor_address) == 0x214);
static_assert(offsetof(RuntimeActorV1, resolved_goal_x) == 0x218);
static_assert(offsetof(RuntimeActorV1, resolved_goal_y) == 0x220);
static_assert(offsetof(RuntimeActorV1, search_delay_limit) == 0x248);
static_assert(offsetof(RuntimeActorV1, contact_state) == 0x250);
static_assert(offsetof(RuntimeActorV1, target_lost) == 0x254);
static_assert(offsetof(RuntimeActorV1, reaction_state) == 0x25C);
static_assert(offsetof(RuntimeActorV1, path_override_active) == 0x290);
static_assert(sizeof(RuntimeActorV1) == 0x294);
static_assert(offsetof(RuntimeWorldV1, actor_array_address) == 0x18);
static_assert(offsetof(RuntimeWorldV1, actor_count) == 0x3C);
static_assert(offsetof(RuntimeViewportControllerV1, viewport_width) == 0x28);
static_assert(offsetof(RuntimeViewportControllerV1, camera_left) == 0x30);
static_assert(offsetof(RuntimeViewportControllerV1, input_camera_left) == 0x44);
static_assert(offsetof(RuntimeViewportControllerV1, world_width) == 0x54);
static_assert(offsetof(RuntimeViewportControllerV1, scroll_velocity) == 0x5C);
static_assert(offsetof(RuntimeViewportControllerV1, scroll_disabled) == 0x70);
static_assert(sizeof(RuntimeViewportControllerV1) == 0x74);

}  // namespace m1937::sdk
