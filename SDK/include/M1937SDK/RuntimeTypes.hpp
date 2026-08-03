#pragma once

#include <cstddef>
#include <cstdint>

#include <M1937SDK/Sprite.hpp>

namespace m1937::sdk {

// Runtime layout recovered from the supported 2001 executable. Pointer fields
// intentionally use uint32_t so the ABI remains the 32-bit game's ABI even
// when SDK layout tests are built by a 64-bit host compiler.
#pragma pack(push, 1)
struct RuntimeActorV1 final {
    std::byte unknown_000[60];
    // sub_4527E0(1) sets this when burial replaces the source corpse.
    std::int32_t hidden_or_removed;        // +0x03C
    // Runtime world-array index used by the L3 grid (stored as index+1000).
    std::int32_t world_scene_index;        // +0x040
    // IEngineSprite::SetCurrentSerial (sub_41C060/sub_41C190) copies the
    // current SPR group's primary triplet to +0x44 and tertiary triplet to
    // +0x50. sub_463290 uses tertiary_x-primary_x for projectile path X and
    // tertiary_z-primary_z for the engine sprite-Z correction.
    std::int32_t sprite_primary_x;          // +0x044
    std::int32_t sprite_primary_middle;     // +0x048
    std::int32_t sprite_primary_z;          // +0x04C
    std::int32_t sprite_tertiary_x;         // +0x050
    std::int32_t sprite_tertiary_middle;    // +0x054
    std::int32_t sprite_tertiary_z;         // +0x058
    std::byte unknown_05c[8];
    // Matches VWF database_header_values[2]. This is a runtime actor type,
    // not the authored DBL database_entry_id.
    std::int32_t runtime_type;            // +0x064
    std::byte unknown_068[8];
    // Actor 78 becomes state 3 when either copied inventory has entries.
    std::int32_t world_object_state;       // +0x070
    std::int32_t faction_id;              // +0x074
    std::byte unknown_078[60];
    // sub_455E30 selects one of these three triplets from movement_mode.
    // It reads only x/z as the planar per-tick component limits. The middle
    // values are faithfully retained by SPR loading but are not consumed by
    // the actor movement function; world_height remains unchanged while
    // following every 2D VWF path.
    SpriteTriplet walk_step;              // +0x0B4
    SpriteTriplet run_step;               // +0x0C0
    SpriteTriplet crawl_step;             // +0x0CC
    std::int32_t world_x;                 // +0x0D8
    std::int32_t world_height;            // +0x0DC
    std::int32_t world_y;                 // +0x0E0
    std::byte unknown_0e4[12];
    // sub_456070 compares the current planar position against this prior
    // update triplet before advancing the shared stationary counter.
    std::int32_t previous_world_x;        // +0x0F0
    std::int32_t previous_world_height;   // +0x0F4
    std::int32_t previous_world_y;        // +0x0F8
    std::byte unknown_0fc[12];
    std::int32_t navigation_cell_x;       // +0x108
    std::int32_t navigation_height_cell;  // +0x10C
    std::int32_t navigation_cell_y;       // +0x110
    std::byte unknown_114[84];
    // sub_458270 sets this while item 49 temporarily exposes the enemy to
    // player commands. sub_45C710 clears it with the hypnosis state.
    std::int32_t world_item_player_selected; // +0x168
    // Shared sub_456070/sub_4587E0 stationary/route counter. The constructor
    // initializes the limit with rand()%160; later resets add 40. Depending
    // on the active controller, sub_456070 resets it at call site 0x56105
    // while stationary and sub_4587E0 resets it at 0x58946 when a route point
    // completes.
    std::int32_t stationary_tick_counter;   // +0x16C
    std::int32_t stationary_tick_limit;     // +0x170
    std::byte unknown_174[4];
    std::int32_t facing_direction;        // +0x178, 1..8
    std::byte unknown_17c[8];
    // sub_4587E0 increments the shared counter only while this flag is one.
    std::int32_t route_update_active;       // +0x184
    std::int32_t dead_or_disabled;         // +0x188
    // Updated from the original global run/forced-target flag and copied by
    // sub_45D330 into a follower's command_variant at +0x1A4.
    std::int32_t pursuit_command_variant;   // +0x18C
    std::int32_t target_status;            // +0x190
    std::int32_t goal_kind;                // +0x194
    std::int32_t goal_x;                   // +0x198
    std::int32_t goal_y;                   // +0x19C
    std::uint32_t interest_actor_address;  // +0x1A0
    std::int32_t command_variant;           // +0x1A4
    std::int32_t command_pending;           // +0x1A8
    std::int32_t selected_for_command;      // +0x1AC
    // sub_451B70/sub_451FA0/sub_452360 gate L2/L3 scene occupancy updates
    // with this value. sub_41D950 recomputes it from the actor footprint.
    std::int32_t navigation_occupancy_enabled; // +0x1B0
    std::byte unknown_1b4[12];
    std::int32_t current_hit_points;        // +0x1C0
    // sub_4553B0 advances this bounded action and sub_455760 draws its bar.
    std::int32_t timed_action_limit;        // +0x1C4, default 100
    std::int32_t timed_action_counter;      // +0x1C8
    union {
        // Burial completion sets this on the source target.
        std::int32_t burial_resolved;       // +0x1CC
        // Gu Ming's normal/disguised update sets the same actor-state slot
        // when the strict transition counter completes. sub_450200 consumes
        // it to replace runtime type 10 with 91 (or 91 with 10).
        std::int32_t disguise_transition_ready; // +0x1CC
    };
    std::int32_t timed_action_progress_active; // +0x1D0
    std::int32_t search_or_return_active;   // +0x1D4
    std::int32_t movement_active;           // +0x1D8
    // m002/m004 one-shot escort recruitment handlers set this after proximity
    // succeeds so the mission transition cannot fire twice.
    std::int32_t escort_recruitment_completed; // +0x1DC
    // Set by accepted ground-coordinate commands and cleared by command reset.
    std::int32_t coordinate_move_command_active; // +0x1E0
    std::byte unknown_1e4[8];
    // Command kind 4 uses this pending/active slot.
    std::int32_t burial_command_active;     // +0x1EC
    std::byte unknown_1f0[12];
    std::int32_t movement_path_state;       // +0x1FC
    std::byte unknown_200[4];
    // Snapshot of default_attack_type used by the current action. The
    // hit-frame dispatcher switches on this value, not the mutable UI
    // selection at +0x20C.
    std::int32_t current_attack_type;        // +0x204
    std::int32_t movement_mode;             // +0x208
    std::int32_t default_attack_type;        // +0x20C
    std::byte unknown_210[4];
    std::uint32_t target_actor_address;     // +0x214
    std::int32_t resolved_goal_x;           // +0x218
    std::byte unknown_21c[4];
    std::int32_t resolved_goal_y;           // +0x220
    std::byte unknown_224[4];
    // Actor-carried non-weapon/backpack item container. It uses the same
    // RuntimeInventoryContainerV1 layout as the weapon container below.
    std::uint32_t item_inventory_address;    // +0x228
    // Points to RuntimeInventoryContainerV1. This is the same container
    // searched by sub_452E40 and rendered by the original inventory HUD.
    std::uint32_t inventory_address;         // +0x22C
    std::byte unknown_230[8];
    std::int32_t hypnosis_active;           // +0x238
    // Persistent actor followed by sub_45D330. This is distinct from the
    // active combat/action target at +0x214 and is also used by authored
    // formation followers.
    std::uint32_t pursuit_actor_address;    // +0x23C
    // Save files replace the pointer above with the followed actor's world
    // scene index; sub_45D2A0 resolves it back to +0x23C after load.
    std::int32_t pursuit_actor_scene_index; // +0x240, -1 when absent
    // Quantity copied to a newly dropped item actor by sub_4583F0.
    std::int32_t world_pickup_quantity;     // +0x244
    std::int32_t search_delay_limit;        // +0x248
    std::int32_t search_delay_counter;      // +0x24C
    std::int32_t contact_state;             // +0x250
    std::int32_t target_lost;               // +0x254
    std::int32_t corpse_discovered;          // +0x258
    std::int32_t reaction_state;            // +0x25C
    // Five-step local search cycle driven by sub_45E4B0.
    std::int32_t search_wander_step_counter; // +0x260
    std::int32_t poison_active;              // +0x264
    std::int32_t poison_counter;             // +0x268
    std::int32_t poison_counter_limit;       // +0x26C
    std::byte unknown_270[8];
    std::int32_t hypnosis_counter_limit;     // +0x278
    std::int32_t hypnosis_counter;           // +0x27C
    // A route with exactly two identical points captures/restores a stationary
    // guard's facing through sub_469820/sub_45E950.
    std::int32_t stationary_route_facing_restore_enabled; // +0x280
    std::int32_t stationary_route_facing_direction; // +0x284
    // Set after the worker reaches the corpse and the 100-limit counter starts.
    std::int32_t burial_action_started;     // +0x288
    // Type 10/91 clothing use sets this while the strict >100 transition
    // counter at +0x24C advances.
    std::int32_t disguise_change_pending;   // +0x28C
    union {
        // Historical SDK name retained for source compatibility.
        std::int32_t path_override_active;   // +0x290
        // Type-11 sets this field to hold idle movement and face the actor
        // referenced by SpecialAttentionSource. Source movement or a combat
        // transition clears it; it is not a timed stun.
        std::int32_t special_attention_hold; // +0x290
    };
    // Type 9 uses these fields after a witnessed pickup; type 91 uses them
    // after a witnessed pistol/dagger action or burial. Unseen actor updates
    // restore faction 1 only when counter > limit.
    std::int32_t disguise_recovery_active;  // +0x294
    std::int32_t disguise_recovery_limit;   // +0x298, default 100
    union {
        std::int32_t disguise_recovery_counter; // +0x29C
        std::int32_t cover_recovery_counter;    // +0x29C
        // sub_45D330 reuses this slot as the type-56 pursuit delay counter.
        std::int32_t pursuit_delay_counter;      // +0x29C
    };
};

struct RuntimeInventoryContainerV1 final {
    std::uint32_t item_ids_address;          // +0x00
    std::uint32_t quantities_address;        // +0x04
    std::uint32_t quantity_modes_address;    // +0x08
    std::int32_t item_count;                 // +0x0C
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
static_assert(offsetof(RuntimeActorV1, world_scene_index) == 0x040);
static_assert(offsetof(RuntimeActorV1, sprite_primary_x) == 0x044);
static_assert(offsetof(RuntimeActorV1, sprite_primary_middle) == 0x048);
static_assert(offsetof(RuntimeActorV1, sprite_primary_z) == 0x04C);
static_assert(offsetof(RuntimeActorV1, sprite_tertiary_x) == 0x050);
static_assert(offsetof(RuntimeActorV1, sprite_tertiary_middle) == 0x054);
static_assert(offsetof(RuntimeActorV1, sprite_tertiary_z) == 0x058);
static_assert(offsetof(RuntimeActorV1, hidden_or_removed) == 0x03C);
static_assert(offsetof(RuntimeActorV1, world_object_state) == 0x070);
static_assert(offsetof(RuntimeActorV1, faction_id) == 0x074);
static_assert(offsetof(RuntimeActorV1, walk_step) == 0x0B4);
static_assert(offsetof(RuntimeActorV1, run_step) == 0x0C0);
static_assert(offsetof(RuntimeActorV1, crawl_step) == 0x0CC);
static_assert(offsetof(RuntimeActorV1, world_x) == 0x0D8);
static_assert(offsetof(RuntimeActorV1, world_height) == 0x0DC);
static_assert(offsetof(RuntimeActorV1, world_y) == 0x0E0);
static_assert(offsetof(RuntimeActorV1, previous_world_x) == 0x0F0);
static_assert(offsetof(RuntimeActorV1, previous_world_height) == 0x0F4);
static_assert(offsetof(RuntimeActorV1, previous_world_y) == 0x0F8);
static_assert(offsetof(RuntimeActorV1, navigation_cell_x) == 0x108);
static_assert(offsetof(RuntimeActorV1, navigation_height_cell) == 0x10C);
static_assert(offsetof(RuntimeActorV1, navigation_cell_y) == 0x110);
static_assert(offsetof(RuntimeActorV1, world_item_player_selected) == 0x168);
static_assert(offsetof(RuntimeActorV1, stationary_tick_counter) == 0x16C);
static_assert(offsetof(RuntimeActorV1, stationary_tick_limit) == 0x170);
static_assert(offsetof(RuntimeActorV1, facing_direction) == 0x178);
static_assert(offsetof(RuntimeActorV1, route_update_active) == 0x184);
static_assert(offsetof(RuntimeActorV1, dead_or_disabled) == 0x188);
static_assert(offsetof(RuntimeActorV1, pursuit_command_variant) == 0x18C);
static_assert(offsetof(RuntimeActorV1, goal_kind) == 0x194);
static_assert(offsetof(RuntimeActorV1, goal_x) == 0x198);
static_assert(offsetof(RuntimeActorV1, goal_y) == 0x19C);
static_assert(offsetof(RuntimeActorV1, interest_actor_address) == 0x1A0);
static_assert(offsetof(RuntimeActorV1, command_variant) == 0x1A4);
static_assert(offsetof(RuntimeActorV1, command_pending) == 0x1A8);
static_assert(offsetof(RuntimeActorV1, selected_for_command) == 0x1AC);
static_assert(offsetof(RuntimeActorV1, navigation_occupancy_enabled) == 0x1B0);
static_assert(offsetof(RuntimeActorV1, current_hit_points) == 0x1C0);
static_assert(offsetof(RuntimeActorV1, timed_action_limit) == 0x1C4);
static_assert(offsetof(RuntimeActorV1, timed_action_counter) == 0x1C8);
static_assert(offsetof(RuntimeActorV1, disguise_transition_ready) == 0x1CC);
static_assert(offsetof(RuntimeActorV1, burial_resolved) == 0x1CC);
static_assert(offsetof(RuntimeActorV1, timed_action_progress_active) == 0x1D0);
static_assert(offsetof(RuntimeActorV1, search_or_return_active) == 0x1D4);
static_assert(offsetof(RuntimeActorV1, movement_active) == 0x1D8);
static_assert(offsetof(RuntimeActorV1, escort_recruitment_completed) == 0x1DC);
static_assert(offsetof(RuntimeActorV1, coordinate_move_command_active) == 0x1E0);
static_assert(offsetof(RuntimeActorV1, burial_command_active) == 0x1EC);
static_assert(offsetof(RuntimeActorV1, movement_path_state) == 0x1FC);
static_assert(offsetof(RuntimeActorV1, current_attack_type) == 0x204);
static_assert(offsetof(RuntimeActorV1, movement_mode) == 0x208);
static_assert(offsetof(RuntimeActorV1, default_attack_type) == 0x20C);
static_assert(offsetof(RuntimeActorV1, target_actor_address) == 0x214);
static_assert(offsetof(RuntimeActorV1, resolved_goal_x) == 0x218);
static_assert(offsetof(RuntimeActorV1, resolved_goal_y) == 0x220);
static_assert(offsetof(RuntimeActorV1, item_inventory_address) == 0x228);
static_assert(offsetof(RuntimeActorV1, inventory_address) == 0x22C);
static_assert(offsetof(RuntimeActorV1, hypnosis_active) == 0x238);
static_assert(offsetof(RuntimeActorV1, pursuit_actor_address) == 0x23C);
static_assert(offsetof(RuntimeActorV1, pursuit_actor_scene_index) == 0x240);
static_assert(offsetof(RuntimeActorV1, world_pickup_quantity) == 0x244);
static_assert(offsetof(RuntimeActorV1, search_delay_limit) == 0x248);
static_assert(offsetof(RuntimeActorV1, search_delay_counter) == 0x24C);
static_assert(offsetof(RuntimeActorV1, contact_state) == 0x250);
static_assert(offsetof(RuntimeActorV1, target_lost) == 0x254);
static_assert(offsetof(RuntimeActorV1, corpse_discovered) == 0x258);
static_assert(offsetof(RuntimeActorV1, reaction_state) == 0x25C);
static_assert(offsetof(RuntimeActorV1, search_wander_step_counter) == 0x260);
static_assert(offsetof(RuntimeActorV1, poison_active) == 0x264);
static_assert(offsetof(RuntimeActorV1, poison_counter) == 0x268);
static_assert(offsetof(RuntimeActorV1, poison_counter_limit) == 0x26C);
static_assert(offsetof(RuntimeActorV1, hypnosis_counter_limit) == 0x278);
static_assert(offsetof(RuntimeActorV1, hypnosis_counter) == 0x27C);
static_assert(offsetof(RuntimeActorV1, stationary_route_facing_restore_enabled) == 0x280);
static_assert(offsetof(RuntimeActorV1, stationary_route_facing_direction) == 0x284);
static_assert(offsetof(RuntimeActorV1, burial_action_started) == 0x288);
static_assert(offsetof(RuntimeActorV1, disguise_change_pending) == 0x28C);
static_assert(offsetof(RuntimeActorV1, path_override_active) == 0x290);
static_assert(offsetof(RuntimeActorV1, special_attention_hold) == 0x290);
static_assert(offsetof(RuntimeActorV1, disguise_recovery_active) == 0x294);
static_assert(offsetof(RuntimeActorV1, disguise_recovery_limit) == 0x298);
static_assert(offsetof(RuntimeActorV1, disguise_recovery_counter) == 0x29C);
static_assert(offsetof(RuntimeActorV1, pursuit_delay_counter) == 0x29C);
static_assert(sizeof(RuntimeActorV1) == 0x2A0);
static_assert(offsetof(RuntimeInventoryContainerV1, item_ids_address) == 0x00);
static_assert(offsetof(RuntimeInventoryContainerV1, quantities_address) == 0x04);
static_assert(offsetof(RuntimeInventoryContainerV1, quantity_modes_address) == 0x08);
static_assert(offsetof(RuntimeInventoryContainerV1, item_count) == 0x0C);
static_assert(sizeof(RuntimeInventoryContainerV1) == 0x10);
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
