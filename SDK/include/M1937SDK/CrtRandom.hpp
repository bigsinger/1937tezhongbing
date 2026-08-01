#pragma once

// Generated from SDK/crt-rand-call-sites.json. Do not edit.
#include <cstddef>
#include <cstdint>

namespace m1937::sdk::crt_random {

inline constexpr std::uint32_t initial_state = 1;

constexpr std::uint32_t step(std::uint32_t state) noexcept {
    return state * 214013u + 2531011u;
}

constexpr std::uint16_t value(std::uint32_t state_after_step) noexcept {
    return static_cast<std::uint16_t>(
        (state_after_step >> 16u) & 0x7fffu);
}

struct CallSite final {
    std::uintptr_t rva;
    std::uintptr_t caller_rva;
    const char* engine_symbol;
    const char* semantic_name;
    const char* domain;
    const char* purpose;
    const char* confidence;
    bool formal_missions;
};

inline constexpr CallSite call_sites[] = {
    {0x000032ED, 0x000031C0, "sub_4031C0", "load_mission_and_debug_screen", "debug_ui", "invalid_mission_debug_statistics", "decompiled", false},
    {0x000032FF, 0x000031C0, "sub_4031C0", "load_mission_and_debug_screen", "debug_ui", "invalid_mission_debug_statistics", "decompiled", false},
    {0x00003311, 0x000031C0, "sub_4031C0", "load_mission_and_debug_screen", "debug_ui", "invalid_mission_debug_statistics", "decompiled", false},
    {0x00003327, 0x000031C0, "sub_4031C0", "load_mission_and_debug_screen", "debug_ui", "invalid_mission_debug_statistics", "decompiled", false},
    {0x0000335F, 0x000031C0, "sub_4031C0", "load_mission_and_debug_screen", "debug_ui", "invalid_mission_debug_statistics", "decompiled", false},
    {0x00006A73, 0x00006A50, "sub_406A50", "select_level_music", "audio_media", "music_index_rand_mod_6_plus_2", "decompiled", true},
    {0x00050967, 0x00050910, "sub_450910", "initialize_actor_base_state", "actor_initialization", "initial_idle_limit_rand_mod_160", "decompiled", true},
    {0x00050980, 0x00050910, "sub_450910", "initialize_actor_base_state", "actor_initialization", "initial_facing_rand_mod_9_plus_1_clamped_to_8", "decompiled", true},
    {0x00050B64, 0x00050AC0, "sub_450AC0", "reset_actor_base_state", "actor_initialization", "reset_idle_limit_rand_mod_160", "decompiled", true},
    {0x00050B7D, 0x00050AC0, "sub_450AC0", "reset_actor_base_state", "actor_initialization", "reset_facing_rand_mod_9_plus_1_clamped_to_8", "decompiled", true},
    {0x0005340B, 0x000533F0, "sub_4533F0", "initialize_actor_ai_state", "actor_initialization", "initial_ai_phase_rand_mod_60", "decompiled", true},
    {0x0005358B, 0x000533F0, "sub_4533F0", "initialize_actor_ai_state", "actor_initialization", "initial_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x00053655, 0x00053650, "sub_453650", "reset_actor_ai_state", "actor_initialization", "reset_ai_phase_rand_mod_60", "decompiled", true},
    {0x000537A3, 0x00053650, "sub_453650", "reset_actor_ai_state", "actor_initialization", "reset_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x00055216, 0x00055200, "sub_455200", "update_local_observation_search", "enemy_ai", "candidate_scan_gate_rand_mod_2", "decompiled", true},
    {0x0005528C, 0x00055200, "sub_455200", "update_local_observation_search", "enemy_ai", "search_x_magnitude_rand_mod_128_plus_64", "decompiled", true},
    {0x000552A3, 0x00055200, "sub_455200", "update_local_observation_search", "enemy_ai", "search_y_magnitude_rand_mod_64_plus_32", "decompiled", true},
    {0x000552BA, 0x00055200, "sub_455200", "update_local_observation_search", "enemy_ai", "search_x_sign_rand_mod_2", "decompiled", true},
    {0x000552D1, 0x00055200, "sub_455200", "update_local_observation_search", "enemy_ai", "search_y_sign_rand_mod_2", "decompiled", true},
    {0x00055BFB, 0x00055930, "sub_455930", "update_actor_path_command", "navigation", "blocked_retry_x_rand_mod_128", "decompiled", true},
    {0x00055C0F, 0x00055930, "sub_455930", "update_actor_path_command", "navigation", "blocked_retry_y_rand_mod_64", "decompiled", true},
    {0x00055C23, 0x00055930, "sub_455930", "update_actor_path_command", "navigation", "blocked_retry_x_sign_rand_mod_2", "decompiled", true},
    {0x00055C3A, 0x00055930, "sub_455930", "update_actor_path_command", "navigation", "blocked_retry_y_sign_rand_mod_2", "decompiled", true},
    {0x00056105, 0x00056070, "sub_456070", "update_actor_movement_and_facing", "actor_ai", "stationary_idle_limit_rand_mod_160_plus_40", "decompiled", true},
    {0x0005614F, 0x00056070, "sub_456070", "update_actor_movement_and_facing", "actor_ai", "path_state_3_limit_rand_mod_60", "decompiled", true},
    {0x000582BC, 0x00058270, "sub_458270", "apply_world_item_effect", "world_items", "item_52_distraction_limit_rand_mod_40_plus_80", "decompiled", true},
    {0x000582FA, 0x00058270, "sub_458270", "apply_world_item_effect", "world_items", "item_82_83_distraction_limit_rand_mod_40_plus_80", "decompiled", true},
    {0x00058946, 0x000587E0, "sub_4587E0", "advance_actor_route", "navigation", "next_route_wait_rand_mod_160_plus_40", "decompiled", true},
    {0x00059343, 0x00059290, "sub_459290", "update_normal_guming", "disguise", "temporary_state_limit_rand_mod_40_plus_20", "decompiled", true},
    {0x000593E1, 0x00059370, "sub_459370", "update_disguised_guming", "disguise", "temporary_state_limit_rand_mod_40_plus_20", "decompiled", true},
    {0x0005BBBC, 0x0005B950, "sub_45B950", "load_actor_runtime_state", "actor_initialization", "load_facing_rand_mod_9_clamped_to_at_least_1", "decompiled", true},
    {0x0005BFAC, 0x0005BD40, "sub_45BD40", "reload_actor_runtime_state", "actor_initialization", "reload_facing_rand_mod_9_clamped_to_at_least_1", "decompiled", true},
    {0x0005C81C, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "observation_marker_scan_gate_rand_mod_2", "decompiled", true},
    {0x0005C998, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "idle_no_contact_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x0005CB2B, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "tracked_target_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x0005CB60, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "corpse_investigation_animation_gate_rand_mod_3", "decompiled", true},
    {0x0005CB9C, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "corpse_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x0005CC69, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "item_investigation_reaction_limit_rand_mod_40_plus_20", "decompiled", true},
    {0x0005CCCD, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "tracked_target_face_or_continue_gate_rand_mod_20_less_than_10", "decompiled", true},
    {0x0005CD01, 0x0005C710, "sub_45C710", "update_enemy_ai", "enemy_ai", "tracked_target_reaction_limit_rand_mod_20_plus_20", "decompiled", true},
    {0x0005CEA6, 0x0005CE90, "sub_45CE90", "update_secondary_enemy_search", "enemy_ai", "candidate_scan_gate_rand_mod_2", "decompiled", true},
    {0x0005CF33, 0x0005CE90, "sub_45CE90", "update_secondary_enemy_search", "enemy_ai", "search_x_magnitude_rand_mod_128_plus_64", "decompiled", true},
    {0x0005CF4A, 0x0005CE90, "sub_45CE90", "update_secondary_enemy_search", "enemy_ai", "search_y_magnitude_rand_mod_64_plus_32", "decompiled", true},
    {0x0005CF61, 0x0005CE90, "sub_45CE90", "update_secondary_enemy_search", "enemy_ai", "search_x_sign_rand_mod_2", "decompiled", true},
    {0x0005CF78, 0x0005CE90, "sub_45CE90", "update_secondary_enemy_search", "enemy_ai", "search_y_sign_rand_mod_2", "decompiled", true},
    {0x0005D08F, 0x0005D060, "sub_45D060", "choose_local_search_point", "enemy_ai", "search_x_rand_mod_requested_span", "decompiled", true},
    {0x0005D09D, 0x0005D060, "sub_45D060", "choose_local_search_point", "enemy_ai", "search_y_rand_mod_half_requested_span", "decompiled", true},
    {0x0005D0B4, 0x0005D060, "sub_45D060", "choose_local_search_point", "enemy_ai", "search_x_sign_rand_mod_2", "decompiled", true},
    {0x0005D0CB, 0x0005D060, "sub_45D060", "choose_local_search_point", "enemy_ai", "search_y_sign_rand_mod_2", "decompiled", true},
    {0x0005D15F, 0x0005D060, "sub_45D060", "choose_local_search_point", "enemy_ai", "next_search_limit_rand_mod_160_plus_40", "decompiled", true},
    {0x0005D394, 0x0005D330, "sub_45D330", "continue_target_pursuit", "enemy_ai", "runtime_type_56_pursuit_delay_rand_mod_10", "decompiled", true},
    {0x0005D47E, 0x0005D330, "sub_45D330", "continue_target_pursuit", "enemy_ai", "pursuit_far_target_gate_rand_mod_10", "decompiled", true},
    {0x0005D64F, 0x0005D610, "sub_45D610", "select_actor_animation_family_a", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D67C, 0x0005D610, "sub_45D610", "select_actor_animation_family_a", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D6A9, 0x0005D610, "sub_45D610", "select_actor_animation_family_a", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D6D6, 0x0005D610, "sub_45D610", "select_actor_animation_family_a", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D7CF, 0x0005D7B0, "sub_45D7B0", "select_actor_animation_family_b", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D7F8, 0x0005D7B0, "sub_45D7B0", "select_actor_animation_family_b", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D821, 0x0005D7B0, "sub_45D7B0", "select_actor_animation_family_b", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D855, 0x0005D7B0, "sub_45D7B0", "select_actor_animation_family_b", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D921, 0x0005D900, "sub_45D900", "select_actor_animation_family_c", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D960, 0x0005D900, "sub_45D900", "select_actor_animation_family_c", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D989, 0x0005D900, "sub_45D900", "select_actor_animation_family_c", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005D9BD, 0x0005D900, "sub_45D900", "select_actor_animation_family_c", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DA81, 0x0005DA60, "sub_45DA60", "select_actor_animation_family_d", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DAAA, 0x0005DA60, "sub_45DA60", "select_actor_animation_family_d", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DAD3, 0x0005DA60, "sub_45DA60", "select_actor_animation_family_d", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DB07, 0x0005DA60, "sub_45DA60", "select_actor_animation_family_d", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DB3B, 0x0005DA60, "sub_45DA60", "select_actor_animation_family_d", "actor_animation", "runtime_type_specific_two_way_serial_selection", "decompiled", true},
    {0x0005DF71, 0x0005DDA0, "sub_45DDA0", "propagate_alert", "enemy_ai", "recipient_reaction_limit_rand_mod_40_plus_40", "decompiled", true},
    {0x0005E078, 0x0005DFC0, "sub_45DFC0", "investigate_nearby_special_actor", "enemy_ai", "investigation_x_magnitude_rand_mod_128_plus_64", "disassembled", true},
    {0x0005E08F, 0x0005DFC0, "sub_45DFC0", "investigate_nearby_special_actor", "enemy_ai", "investigation_y_magnitude_rand_mod_64_plus_32", "disassembled", true},
    {0x0005E0A6, 0x0005DFC0, "sub_45DFC0", "investigate_nearby_special_actor", "enemy_ai", "investigation_x_sign_rand_mod_2", "disassembled", true},
    {0x0005E0BD, 0x0005DFC0, "sub_45DFC0", "investigate_nearby_special_actor", "enemy_ai", "investigation_y_sign_rand_mod_2", "disassembled", true},
    {0x0005FD2C, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_x", "decompiled", true},
    {0x0005FD41, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_y", "decompiled", true},
    {0x0005FD54, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_alpha_rand_mod_60_plus_100", "decompiled", true},
    {0x0005FD6A, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_lifetime_rand_mod_250_plus_250", "decompiled", true},
    {0x0005FD7F, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_speed_rand_mod_8_plus_6", "decompiled", true},
    {0x0005FDA8, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "primary_particle_size", "decompiled", true},
    {0x0005FDDB, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "secondary_particle_x", "decompiled", true},
    {0x0005FDEE, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "secondary_particle_y", "decompiled", true},
    {0x0005FE02, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "secondary_particle_alpha_rand_mod_70_minus_76", "decompiled", true},
    {0x0005FE19, 0x0005FD10, "sub_45FD10", "reset_ambient_particle_field", "ambient_visuals", "secondary_particle_lifetime_rand_mod_2_plus_1", "decompiled", true},
    {0x0005FF45, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "flash_gate_rand_mod_500", "decompiled", true},
    {0x0005FF65, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "weather_phase_gate_rand_mod_250", "decompiled", true},
    {0x000600F0, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_draw_x_jitter_rand_mod_2", "decompiled", true},
    {0x00060105, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_draw_y_jitter_rand_mod_2", "decompiled", true},
    {0x000601D6, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_decay_component_rand_mod_19", "decompiled", true},
    {0x000601E5, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_decay_component_rand_mod_20", "decompiled", true},
    {0x00060202, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_decay_tail", "decompiled", true},
    {0x0006026D, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_x", "decompiled", true},
    {0x00060291, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_y", "decompiled", true},
    {0x000602A7, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_alpha_rand_mod_80_plus_80", "decompiled", true},
    {0x000602BC, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_lifetime_rand_mod_250_plus_250", "decompiled", true},
    {0x000602D1, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_speed_rand_mod_8_plus_6", "decompiled", true},
    {0x000602FA, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "primary_respawn_size", "decompiled", true},
    {0x00060374, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_respawn_x", "decompiled", true},
    {0x00060396, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_respawn_y", "decompiled", true},
    {0x000603AD, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_respawn_alpha_rand_mod_70_minus_76", "decompiled", true},
    {0x000603C4, 0x0005FF20, "sub_45FF20", "update_ambient_particle_field", "ambient_visuals", "secondary_respawn_lifetime_rand_mod_2_plus_1", "decompiled", true},
    {0x00061DFC, 0x00061D10, "sub_461D10", "choose_matching_sprite_relation", "scene_visuals", "matching_candidate_index_rand_mod_count", "decompiled", true},
    {0x00061E3A, 0x00061D10, "sub_461D10", "choose_matching_sprite_relation", "scene_visuals", "equal_relation_orientation_rand_mod_4", "decompiled", true},
    {0x00064138, 0x00064120, "sub_464120", "initialize_effect_particle", "effect_visuals", "effect_repeat_or_style_rand_mod_3_plus_2", "decompiled", true},
    {0x0006458D, 0x00064580, "sub_464580", "choose_effect_particle_position", "effect_visuals", "initial_angle_rand_mod_360", "decompiled", true},
    {0x000645F2, 0x00064580, "sub_464580", "choose_effect_particle_position", "effect_visuals", "x_jitter_positive_or_negative_branch", "decompiled", true},
    {0x00064604, 0x00064580, "sub_464580", "choose_effect_particle_position", "effect_visuals", "x_jitter_positive_or_negative_branch", "decompiled", true},
    {0x0006461C, 0x00064580, "sub_464580", "choose_effect_particle_position", "effect_visuals", "y_jitter_positive_or_negative_branch", "decompiled", true},
    {0x0006463A, 0x00064580, "sub_464580", "choose_effect_particle_position", "effect_visuals", "y_jitter_positive_or_negative_branch", "decompiled", true},
    {0x00064744, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "particle_attempt_count_max_rand_mod_3_one", "decompiled", true},
    {0x0006476E, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "particle_runtime_type_variant_rand_mod_3", "decompiled", true},
    {0x000647FB, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "x_sign_rand_mod_2", "decompiled", true},
    {0x0006480F, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "y_sign_rand_mod_2", "decompiled", true},
    {0x00064841, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "x_magnitude_positive_or_negative_branch", "decompiled", true},
    {0x00064861, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "x_magnitude_positive_or_negative_branch", "decompiled", true},
    {0x00064883, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "y_magnitude_positive_or_negative_branch", "decompiled", true},
    {0x000648B0, 0x00064730, "sub_464730", "populate_explosion_particles", "combat_effects", "y_magnitude_positive_or_negative_branch", "decompiled", true},
    {0x000653D2, 0x000653B0, "sub_4653B0", "create_random_effect_cluster", "effect_visuals", "effect_count_max_rand_mod_8_one", "decompiled", true},
    {0x00065402, 0x000653B0, "sub_4653B0", "create_random_effect_cluster", "effect_visuals", "effect_runtime_type_rand_mod_5_plus_72", "decompiled", true},
};

inline constexpr std::size_t call_site_count =
    sizeof(call_sites) / sizeof(call_sites[0]);

constexpr const CallSite* find_call_site(
    std::uintptr_t rva) noexcept {
    for (const auto& site : call_sites) {
        if (site.rva == rva)
            return &site;
    }
    return nullptr;
}

}  // namespace m1937::sdk::crt_random
