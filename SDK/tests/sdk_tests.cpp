#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <M1937SDK/M1937SDK.hpp>

namespace {

class PeFile final {
public:
    explicit PeFile(const char* path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream)
            throw std::runtime_error("cannot open executable");
        stream.seekg(0, std::ios::end);
        const auto length = stream.tellg();
        if (length <= 0)
            throw std::runtime_error("empty executable");
        data_.resize(static_cast<std::size_t>(length));
        stream.seekg(0, std::ios::beg);
        stream.read(
            reinterpret_cast<char*>(data_.data()),
            static_cast<std::streamsize>(data_.size()));
        if (!stream)
            throw std::runtime_error("cannot read executable");
        if (data_.size() < sizeof(IMAGE_DOS_HEADER))
            throw std::runtime_error("truncated DOS header");
        dos_ = reinterpret_cast<const IMAGE_DOS_HEADER*>(data_.data());
        if (dos_->e_magic != IMAGE_DOS_SIGNATURE ||
            dos_->e_lfanew <= 0 ||
            static_cast<std::size_t>(dos_->e_lfanew) >
                data_.size() - sizeof(IMAGE_NT_HEADERS32))
            throw std::runtime_error("invalid DOS header");
        nt_ = reinterpret_cast<const IMAGE_NT_HEADERS32*>(
            data_.data() + dos_->e_lfanew);
        if (nt_->Signature != IMAGE_NT_SIGNATURE)
            throw std::runtime_error("invalid PE signature");
    }

    [[nodiscard]] const IMAGE_NT_HEADERS32& nt() const noexcept {
        return *nt_;
    }
    [[nodiscard]] std::size_t size() const noexcept {
        return data_.size();
    }

    [[nodiscard]] const std::byte* at_rva(
        std::uint32_t rva,
        std::size_t length) const {
        const auto* section = IMAGE_FIRST_SECTION(nt_);
        for (std::uint16_t index = 0;
             index < nt_->FileHeader.NumberOfSections;
             index++, section++) {
            const auto virtual_size = section->Misc.VirtualSize;
            const auto mapped_size =
                virtual_size > section->SizeOfRawData
                    ? virtual_size
                    : section->SizeOfRawData;
            if (rva < section->VirtualAddress ||
                rva >= section->VirtualAddress + mapped_size)
                continue;
            const auto offset =
                static_cast<std::size_t>(section->PointerToRawData) +
                (rva - section->VirtualAddress);
            if (offset > data_.size() ||
                length > data_.size() - offset)
                throw std::runtime_error("RVA extends past file");
            return data_.data() + offset;
        }
        if (rva < nt_->OptionalHeader.SizeOfHeaders &&
            rva <= data_.size() &&
            length <= data_.size() - rva)
            return data_.data() + rva;
        throw std::runtime_error("RVA is not mapped by the PE file");
    }

private:
    std::vector<std::byte> data_;
    const IMAGE_DOS_HEADER* dos_{};
    const IMAGE_NT_HEADERS32* nt_{};
};

template <std::size_t Size>
void require_signature(
    const PeFile& file,
    std::uint32_t rva,
    const unsigned char (&expected)[Size],
    const char* name,
    int& checks) {
    if (std::memcmp(file.at_rva(rva, Size), expected, Size) != 0)
        throw std::runtime_error(std::string("signature mismatch: ") + name);
    checks++;
}

void require(bool value, const char* description, int& checks) {
    if (!value)
        throw std::runtime_error(description);
    checks++;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 2) {
            std::cerr << "Usage: M1937SDK.Tests.exe M1937.exe\n";
            return 2;
        }
        const PeFile file(argv[1]);
        const auto& nt = file.nt();
        int checks = 0;
        require(
            file.size() == m1937::sdk::ExecutableIdentity::file_size,
            "file size mismatch", checks);
        require(
            nt.FileHeader.Machine == IMAGE_FILE_MACHINE_I386,
            "executable is not x86", checks);
        require(
            nt.FileHeader.TimeDateStamp ==
                m1937::sdk::ExecutableIdentity::pe_timestamp,
            "PE timestamp mismatch", checks);
        require(
            nt.OptionalHeader.ImageBase ==
                m1937::sdk::ExecutableIdentity::preferred_image_base,
            "preferred image base mismatch", checks);
        require(
            nt.OptionalHeader.SizeOfImage ==
                m1937::sdk::ExecutableIdentity::image_size,
            "image size mismatch", checks);
        require(
            nt.OptionalHeader.AddressOfEntryPoint ==
                m1937::sdk::ExecutableIdentity::entry_point_rva,
            "entry point mismatch", checks);

        static constexpr unsigned char safe_blit[] = {
            0x83, 0xEC, 0x2C, 0x53, 0x55, 0x56};
        static constexpr unsigned char menu_poll[] = {
            0x8B, 0x44, 0x24, 0x04, 0x53, 0x55};
        static constexpr unsigned char mission_initializer[] = {
            0xA1, 0x60, 0x70, 0x4E, 0x00, 0x53, 0x48, 0x55,
            0x56, 0x83, 0xF8, 0x0B, 0x57, 0x8B, 0xF1, 0x0F};
        static constexpr unsigned char mission_evaluator[] = {
            0x64, 0xA1, 0x00, 0x00, 0x00, 0x00, 0x6A, 0xFF,
            0x68, 0x88, 0xE3, 0x4B, 0x00, 0x50, 0xA1, 0x58};
        static constexpr unsigned char mission_evaluator_thunk[] = {
            0xE9, 0x9D, 0x43, 0x00, 0x00};
        static constexpr unsigned char world_update[] = {
            0x83, 0xEC, 0x10, 0x56, 0x8B, 0xF1, 0x8B, 0x4E,
            0x40, 0x85, 0xC9, 0x0F, 0x84, 0x7D, 0x02, 0x00};
        static constexpr unsigned char warning[] = {0x74, 0x0C};
        static constexpr unsigned char level[] = {
            0x01, 0x00, 0x00, 0x00};
        require_signature(
            file, m1937::sdk::rva::safe_blit,
            safe_blit, "SafeBlit", checks);
        require_signature(
            file, m1937::sdk::rva::menu_poll,
            menu_poll, "MenuPoll", checks);
        require_signature(
            file, m1937::sdk::rva::initialize_mission_bindings,
            mission_initializer, "InitializeMissionBindings", checks);
        require_signature(
            file, m1937::sdk::rva::evaluate_mission,
            mission_evaluator, "EvaluateMission", checks);
        require_signature(
            file, m1937::sdk::rva::evaluate_mission_thunk,
            mission_evaluator_thunk, "EvaluateMissionThunk", checks);
        require_signature(
            file, m1937::sdk::rva::update_game_world,
            world_update, "UpdateGameWorld", checks);
        require_signature(
            file, m1937::sdk::rva::false_resource_warning_branch,
            warning, "FalseResourceWarningBranch", checks);
        require_signature(
            file, m1937::sdk::rva::new_game_level_immediate,
            level, "NewGameLevelImmediate", checks);
        require(
            std::memcmp(
                file.at_rva(
                    m1937::sdk::rva::mission_12_vwf_name, 13),
                "1937M011.VWF", 13) == 0,
            "mission 12 filename mismatch", checks);
        require(
            std::memcmp(
                file.at_rva(
                    m1937::sdk::rva::mission_7_vwf_name, 13),
                "1937M006.VWF", 13) == 0,
            "mission 7 filename mismatch", checks);
        require(
            m1937::sdk::mission_route_count == 12,
            "mission route count mismatch", checks);
        for (std::size_t index = 0;
             index < m1937::sdk::mission_route_count;
             ++index) {
            const auto& route = m1937::sdk::mission_routes[index];
            require(
                route.selector_level == static_cast<int>(index + 1),
                "mission selector levels are not contiguous", checks);
            require(
                route.engine_mission >= 1 &&
                    route.engine_mission <= 12,
                "mission route targets an invalid engine state", checks);
            require(
                std::strlen(route.vwf_name) == 12,
                "mission VWF name does not fit original fixed slot", checks);
            require(
                m1937::sdk::find_mission_route(
                    route.selector_level) == &route,
                "mission route lookup mismatch", checks);
            require(
                route.title && std::wcslen(route.title) > 0 &&
                    route.briefing && std::wcslen(route.briefing) > 0 &&
                    route.objective_1 &&
                    std::wcslen(route.objective_1) > 0 &&
                    route.objective_2 &&
                    std::wcslen(route.objective_2) > 0 &&
                    route.objective_3 &&
                    std::wcslen(route.objective_3) > 0 &&
                    route.replace_legacy_briefing,
                "mission route has an incomplete in-game text briefing",
                checks);
            if (route.redirect_rva != 0) {
                require(
                    std::strlen(route.redirect_expected) ==
                        std::strlen(route.vwf_name),
                    "mission redirect changes fixed string length", checks);
            }
        }
        require(
            m1937::sdk::find_mission_route(0) == nullptr &&
                m1937::sdk::find_mission_route(16) == nullptr,
            "mission route lookup accepted an invalid level", checks);
        require(
            sizeof(m1937::sdk::mission::RuntimeControllerStateV1) ==
                    0x0C4 &&
                offsetof(
                    m1937::sdk::mission::RuntimeControllerStateV1,
                    game_flow_state) == 0x0A4 &&
                offsetof(
                    m1937::sdk::mission::RuntimeControllerStateV1,
                    evaluation_active) == 0x0BC &&
                offsetof(
                    m1937::sdk::mission::RuntimeControllerStateV1,
                    result_state) == 0x0C0,
            "mission controller state layout mismatch", checks);
        require(
            m1937::sdk::mission::outcome_from_raw(2) ==
                    m1937::sdk::mission::Outcome::failed &&
                m1937::sdk::mission::outcome_from_raw(3) ==
                    m1937::sdk::mission::Outcome::victory &&
                m1937::sdk::mission::outcome_from_raw(1) ==
                    m1937::sdk::mission::Outcome::unknown &&
                std::strcmp(
                    m1937::sdk::mission::outcome_name(
                        m1937::sdk::mission::Outcome::failed),
                    "failed") == 0,
            "mission outcome mapping mismatch", checks);
        {
        using namespace m1937::sdk::mission;
        const auto* mission2 = find_interaction_rule(2);
        const auto* mission4 = find_interaction_rule(4);
        const auto* mission5 = find_interaction_rule(5);
        const auto* mission9 = find_interaction_rule(9);
        require(
            mission2 && mission4 && mission5 && mission9 &&
                mission2->target_predicate ==
                    TargetPredicate::hit_points_nonpositive &&
                mission2->required_exit_actor_runtime_type == 91 &&
                mission4->target_predicate ==
                    TargetPredicate::timed_explosive_within_radius &&
                mission4->required_nearby_runtime_type == 85 &&
                mission4->target_radius_exclusive &&
                character_allowed(
                    mission5->item_101_holder_mask,
                    character_gu_ming) &&
                character_allowed(
                    mission5->item_101_holder_mask,
                    character_daniu) &&
                mission9->exit_radius_exclusive,
            "recovered mission interaction table mismatch", checks);
        require(
            distance_matches(127, 0, 128, true) &&
                !distance_matches(128, 0, 128, true) &&
                distance_matches(128, 0, 128, false) &&
                !damage_destroys_target(8, 7) &&
                damage_destroys_target(8, 8) &&
                find_interaction_rule(6) == nullptr,
            "recovered mission boundary semantics mismatch", checks);
        }

        {
        using namespace m1937::sdk::crt_random;
        require(
            call_site_count == 119,
            "CRT rand direct call-site count mismatch", checks);
        auto state = step(initial_state);
        require(
            value(state) == 41,
            "CRT rand default first value mismatch", checks);
        state = step(state);
        require(
            value(state) == 18467,
            "CRT rand default second value mismatch", checks);
        std::uintptr_t previous_rva = 0;
        std::size_t formal_site_count = 0;
        for (const auto& site : call_sites) {
            require(
                site.rva > previous_rva &&
                    site.caller_rva <= site.rva &&
                    site.engine_symbol && *site.engine_symbol &&
                    site.semantic_name && *site.semantic_name &&
                    site.domain && *site.domain &&
                    site.purpose && *site.purpose &&
                    site.confidence && *site.confidence,
                "CRT rand call-site metadata is incomplete or unsorted",
                checks);
            previous_rva = site.rva;
            if (site.formal_missions)
                formal_site_count++;
            const auto* instruction = file.at_rva(
                static_cast<std::uint32_t>(site.rva), 5);
            require(
                instruction[0] == std::byte{0xE8},
                "CRT rand catalog entry is not a relative CALL", checks);
            std::int32_t displacement = 0;
            std::memcpy(
                &displacement, instruction + 1,
                sizeof(displacement));
            const auto target =
                static_cast<std::int64_t>(site.rva) + 5 +
                displacement;
            require(
                target ==
                    static_cast<std::int64_t>(
                        m1937::sdk::rva::crt_rand) &&
                    find_call_site(site.rva) == &site,
                "CRT rand relative CALL target or lookup mismatch",
                checks);
        }
        require(
            formal_site_count == 110 &&
                find_call_site(0) == nullptr,
            "CRT rand formal-mission classification mismatch", checks);
        }

        {
        using namespace m1937::sdk::input;
        require(
            original_action_binding_count == 28 &&
                find_action_binding(OriginalAction::weapon_1) &&
                find_action_binding(OriginalAction::weapon_1)->scan_code ==
                    DikScanCode::digit_1 &&
                find_action_binding(OriginalAction::weapon_1)->phase ==
                    TriggerPhase::press &&
                find_action_binding(OriginalAction::minimap) &&
                find_action_binding(OriginalAction::minimap)->scan_code ==
                    DikScanCode::m &&
                find_action_binding(OriginalAction::minimap)->phase ==
                    TriggerPhase::release &&
                find_action_binding(OriginalAction::force_target_up)->phase ==
                    TriggerPhase::held,
            "original DirectInput action matrix mismatch", checks);
        const auto pressed = transition(false, true);
        const auto held = transition(true, true);
        const auto released = transition(true, false);
        require(
            pressed.pressed && pressed.down && !pressed.released &&
                !held.pressed && held.down && !held.released &&
                !released.pressed && !released.down && released.released,
            "mouse button transition matrix mismatch", checks);
        require(
            keyboard_state_offset(DikScanCode::m) ==
                    InputStateOffsets::keyboard_state + 0x32 &&
                m1937::sdk::rva::keyboard_state_base -
                    m1937::sdk::rva::input_state_base ==
                    InputStateOffsets::keyboard_state &&
                m1937::sdk::rva::mouse_middle_pressed -
                    m1937::sdk::rva::input_state_base ==
                    InputStateOffsets::mouse_middle_pressed &&
                m1937::sdk::rva::mouse_right_pressed -
                    m1937::sdk::rva::input_state_base ==
                    InputStateOffsets::mouse_right_pressed &&
                m1937::sdk::rva::mouse_right_released -
                    m1937::sdk::rva::input_state_base ==
                    InputStateOffsets::mouse_right_released,
            "input-state field offsets no longer match catalog globals",
            checks);
        require(
            edge_direction(0, 360, 1280, 720) == EdgeDirection::west &&
                edge_direction(1, 360, 1280, 720) ==
                    EdgeDirection::west &&
                edge_direction(2, 360, 1280, 720) ==
                    EdgeDirection::none &&
                edge_direction(1279, 1, 1280, 720) ==
                    EdgeDirection::northeast &&
                edge_direction(1280, 360, 1280, 720) ==
                    EdgeDirection::none &&
                advance_scroll_velocity(0, 64, true) == 8 &&
                advance_scroll_velocity(64, 64, false) == 56,
            "original two-coordinate edge/ramp semantics mismatch", checks);
        require(
            context_cursor(true, true, true, true, true, true, true) ==
                    CursorSerial::burial &&
                context_cursor(
                    false, true, true, true, true, true, true) ==
                    CursorSerial::sight &&
                context_cursor(
                    false, false, true, false, true, false, true) ==
                    CursorSerial::interact &&
                context_cursor(
                    false, false, true, false, false, false, false) ==
                    CursorSerial::blocked,
            "original mouse.spr cursor-priority matrix mismatch", checks);
        require(
            m1937::sdk::rva::direct_input_poll != 0 &&
                m1937::sdk::rva::original_world_input_controller != 0 &&
                m1937::sdk::rva::cursor_set_serial != 0 &&
                m1937::sdk::rva::right_drag_selection != 0 &&
                m1937::sdk::rva::world_input_dispatch != 0 &&
                m1937::sdk::rva::set_scroll_velocity_limit != 0,
            "input/cursor RVA catalog mismatch", checks);
        }

        using m1937::sdk::InventoryContainerKind;
        require(
            m1937::sdk::original_world_pickups.size() == 10,
            "original world pickup table size mismatch", checks);
        const auto* rifle_ammunition =
            m1937::sdk::find_original_world_pickup(982);
        const auto* medicine =
            m1937::sdk::find_original_world_pickup(983);
        const auto* explosives =
            m1937::sdk::find_original_world_pickup(998);
        require(
            rifle_ammunition &&
                rifle_ammunition->item_id == 38 &&
                rifle_ammunition->container ==
                    InventoryContainerKind::weapon &&
                rifle_ammunition->quantity == 1 &&
                rifle_ammunition->quantity_mode == 2,
            "DBL 982 pickup semantics mismatch", checks);
        require(
            medicine &&
                medicine->item_id == 46 &&
                medicine->container ==
                    InventoryContainerKind::backpack &&
                medicine->quantity == 1 &&
                medicine->quantity_mode == 0,
            "DBL 983 pickup semantics mismatch", checks);
        require(
            explosives &&
                explosives->item_id == 45 &&
                explosives->container ==
                    InventoryContainerKind::weapon &&
                explosives->quantity == 1 &&
                explosives->quantity_mode == 0,
            "DBL 998 pickup semantics mismatch", checks);
        require(
            m1937::sdk::find_original_world_pickup(-1) == nullptr &&
                m1937::sdk::find_original_world_pickup(1003) == nullptr,
            "world pickup lookup accepted a non-pickup DBL entry", checks);
        require(
            m1937::sdk::gasoline_barrel_database_entry_id == 1003 &&
                m1937::sdk::gasoline_barrel_item_id == 53,
            "gasoline barrel identity mismatch", checks);

        require(
            m1937::sdk::rva::special_attack_dispatch != 0 &&
                m1937::sdk::rva::explosion_actor_update != 0 &&
                m1937::sdk::rva::special_attention_source != 0 &&
                m1937::sdk::rva::special_attack_dispatch !=
                    m1937::sdk::rva::explosion_actor_update,
            "special-action RVA catalog mismatch", checks);
        require(
            m1937::sdk::direct_actor_damage(2, 1) == 16 &&
                m1937::sdk::direct_actor_damage(2, 5) == 2 &&
                m1937::sdk::direct_actor_damage(4, 56) == 1 &&
                m1937::sdk::direct_actor_damage(4, 1) == 8,
            "ordinary attacker-type damage branches mismatch", checks);
        require(
            m1937::sdk::find_ordinary_attack_rule(3) != nullptr &&
                m1937::sdk::find_ordinary_attack_rule(3)
                        ->direct_actor_hit_count == 1 &&
                m1937::sdk::find_ordinary_attack_rule(3)
                        ->coordinate_projectile_count == 3 &&
                m1937::sdk::attack_target_cell_coincides(
                    {0, 0}, {1, 1}) &&
                !m1937::sdk::attack_target_cell_coincides(
                    {0, 0}, {2, 2}) &&
                m1937::sdk::ordinary_navigation_cell_size.width == 32 &&
                m1937::sdk::ordinary_navigation_cell_size.height == 16 &&
                m1937::sdk::
                        machine_gun_live_target_spread_degrees[1] == -1 &&
                m1937::sdk::
                        machine_gun_coordinate_spread_degrees[2] == 2 &&
                m1937::sdk::accepted_actor_damage(34, 31) == 0 &&
                m1937::sdk::accepted_actor_damage(34, 32) == 32,
            "ordinary target-cell, spread and low-damage rules mismatch",
            checks);
        require(
            m1937::sdk::rva::attack_target_cell_coincides != 0 &&
                m1937::sdk::rva::apply_actor_damage != 0 &&
                m1937::sdk::rva::attack_target_cell_coincides !=
                    m1937::sdk::rva::apply_actor_damage,
            "ordinary combat RVA catalog mismatch", checks);
        {
        using namespace m1937::sdk::projectile;
        const auto* pistol = find_attack_rule(1);
        const auto* rifle = find_attack_rule(2);
        const auto* machine_gun = find_attack_rule(3);
        const auto* dart = find_attack_rule(6);
        const auto* slingshot = find_attack_rule(7);
        const auto* grenade = find_attack_rule(9);
        require(
            pistol && pistol->effect_type == 1 &&
                pistol->delivery_mode ==
                    DeliveryMode::invisible_linear &&
                pistol->world_step_pixels == 64 &&
                pistol->runtime_actor_type == 0 &&
                pistol->first_match_gfl_index == 0 &&
                pistol->direct_damage == 2 &&
                pistol->impact_effect_type == 8 &&
                pistol->impact_actor_type == 60 &&
                pistol->impact_first_match_gfl_index == 306 &&
                rifle &&
                rifle->delivery_mode ==
                    DeliveryMode::invisible_linear &&
                rifle->direct_damage == 2 &&
                machine_gun &&
                machine_gun->delivery_mode ==
                    DeliveryMode::invisible_linear &&
                machine_gun->direct_damage == 2,
            "ordinary effect-1 coordinate projectile table mismatch",
            checks);
        require(
            dart && dart->effect_type == 13 &&
                dart->delivery_mode == DeliveryMode::dart_linear &&
                dart->world_step_pixels == 16 &&
                dart->runtime_actor_type == 80 &&
                dart->first_match_gfl_index == 251 &&
                dart->direct_damage == 8 &&
                dart->impact_effect_type == 8 &&
                dart->impact_actor_type == 60 &&
                dart->impact_first_match_gfl_index == 306 &&
                slingshot && slingshot->effect_type == 14 &&
                slingshot->delivery_mode ==
                    DeliveryMode::slingshot_linear &&
                slingshot->world_step_pixels == 5 &&
                slingshot->runtime_actor_type == 81 &&
                slingshot->first_match_gfl_index == 635 &&
                slingshot->direct_damage == 1 &&
                slingshot->impact_effect_type == 8 &&
                slingshot->impact_actor_type == 60 &&
                slingshot->impact_first_match_gfl_index == 306,
            "linear projectile dispatch table mismatch", checks);
        require(
            grenade && grenade->effect_type == 2 &&
                grenade->delivery_mode ==
                    DeliveryMode::grenade_parabola &&
                grenade->world_step_pixels == 8 &&
                grenade->runtime_actor_type == 57 &&
                grenade->first_match_gfl_index == 528 &&
                grenade->direct_damage == 0 &&
                grenade->impact_effect_type == 4 &&
                grenade->impact_actor_type == 61 &&
                grenade->impact_first_match_gfl_index == 19 &&
                grenade->explosion_actor_type == 61 &&
                grenade->explosion_first_match_gfl_index == 19 &&
                explosion_damage == 128 &&
                explosion_ellipse.width == 128 &&
                explosion_ellipse.height == 64 &&
                explosion_alert_radius == 800,
            "grenade actor-61 delivery table mismatch", checks);
        require(
            find_attack_rule(8) == nullptr &&
                inclusive_path_point_count({0, 0}, {100, 40}) == 101 &&
                inclusive_path_point_count({0, 0}, {40, 100}) == 101 &&
                resolution_world_ticks(101, 16) == 8 &&
                resolution_world_ticks(101, 5) == 21 &&
                resolution_world_ticks(201, 8) == 26 &&
                original_arc_coefficient(201, 8) == 0.32F &&
                original_arc_height(8, 12, 0.32F) == 50 &&
                owner_launch_x_offset(
                    SpriteTriplet{17, 0, 150},
                    SpriteTriplet{4, 2, 2}) == -13 &&
                owner_visual_height(
                    SpriteTriplet{17, 0, 150},
                    SpriteTriplet{4, 2, 2}) == 148,
            "projectile path/tick/parabola/SPR-anchor formulas mismatch",
            checks);
        require(
            m1937::sdk::sprite_lookup_top_left(
                10,
                20,
                m1937::sdk::SpriteTriplet{33, 7, 17}) ==
                m1937::sdk::SpriteLookupOffset{9, 19} &&
                m1937::sdk::sprite_lookup_offset(
                    4,
                    m1937::sdk::SpriteLookupDimensions{3, 3},
                    m1937::sdk::SpriteTriplet{33, 7, 17}) ==
                    m1937::sdk::SpriteLookupOffset{0, 0} &&
                m1937::sdk::sprite_lookup_offset(
                    7,
                    m1937::sdk::SpriteLookupDimensions{3, 3},
                    m1937::sdk::SpriteTriplet{33, 7, 17}) ==
                    m1937::sdk::SpriteLookupOffset{0, 1} &&
                sizeof(m1937::sdk::SpriteFrameGroupRuntime32) == 0x54,
            "SPR lookup anchor, row-major mask, or runtime layout mismatch",
            checks);
        require(
            m1937::sdk::rva::create_projectile_effect != 0 &&
                m1937::sdk::rva::original_endpoint_from_angle != 0 &&
                m1937::sdk::rva::configure_projectile_path != 0 &&
                m1937::sdk::rva::advance_projectile_visual != 0 &&
                m1937::sdk::rva::current_projectile_path_point != 0 &&
                m1937::sdk::rva::projectile_at_destination != 0 &&
                m1937::sdk::rva::update_projectile_collision != 0 &&
                m1937::sdk::rva::update_projectile_manager != 0 &&
                m1937::sdk::rva::create_one_shot_effect_actor != 0 &&
                m1937::sdk::rva::update_one_shot_effect_actor != 0 &&
                m1937::sdk::rva::configure_projectile_path !=
                    m1937::sdk::rva::update_projectile_collision,
            "projectile RVA catalog mismatch", checks);
        require(
            m1937::sdk::rva::load_sprite_frame_group != 0 &&
                m1937::sdk::rva::get_sprite_movement_lookup != 0 &&
                m1937::sdk::rva::get_sprite_line_of_sight_lookup != 0 &&
                m1937::sdk::rva::get_sprite_draw_order_row != 0 &&
            m1937::sdk::rva::actor_lookup_origin_x != 0 &&
                m1937::sdk::rva::actor_lookup_origin_y != 0 &&
                m1937::sdk::rva::actor_component_movement != 0 &&
                m1937::sdk::rva::sprite_world_hit_test != 0 &&
                m1937::sdk::rva::register_actor_lookup != 0 &&
                m1937::sdk::rva::unregister_actor_lookup != 0 &&
                m1937::sdk::rva::get_sprite_movement_lookup !=
                    m1937::sdk::rva::get_sprite_line_of_sight_lookup &&
                m1937::sdk::rva::register_actor_lookup !=
                    m1937::sdk::rva::unregister_actor_lookup,
            "SPR lookup RVA catalog mismatch",
            checks);
        require(
            offsetof(m1937::sdk::RuntimeActorV1, walk_step) == 0x0B4 &&
                offsetof(m1937::sdk::RuntimeActorV1, run_step) == 0x0C0 &&
                offsetof(
                    m1937::sdk::RuntimeActorV1,
                    crawl_step) == 0x0CC &&
                offsetof(
                    m1937::sdk::RuntimeActorV1,
                    world_x) == 0x0D8,
            "actor SPR movement-triplet runtime layout mismatch",
            checks);
        }
        require(
            m1937::sdk::rva::enable_sight_observation_mode != 0 &&
                m1937::sdk::rva::enable_burial_mode != 0 &&
                m1937::sdk::rva::burial_command_update != 0 &&
                m1937::sdk::rva::observation_marker_scan != 0 &&
                m1937::sdk::rva::enable_sight_observation_mode !=
                    m1937::sdk::rva::enable_burial_mode,
            "S/B command RVA catalog mismatch", checks);
        using namespace m1937::sdk::command;
        require(
            is_sight_direct_target(1, 0) &&
                !is_sight_direct_target(1, 1) &&
                !is_sight_direct_target(3, 0) &&
                is_burial_target(1, 1) &&
                !is_burial_target(1, 0) &&
                !is_burial_target(3, 1),
            "S/B original target filters mismatch", checks);
        require(
            observation_marker_actor_type == 90 &&
                observation_marker_gfl_index == 341 &&
                burial_cache_actor_type == 78 &&
                burial_cache_gfl_index == 64 &&
                burial_command_kind == 4,
            "S/B recovered actor identity mismatch", checks);
        require(
            is_burial_adjacent_cell(0, 0, 63, 31) &&
                !is_burial_adjacent_cell(0, 0, 64, 32) &&
                is_pickup_adjacent_cell(0, 0, 63, 31) &&
                !is_pickup_adjacent_cell(0, 0, 64, 32) &&
                !burial_counter_has_completed(100) &&
                burial_counter_has_completed(101),
            "B/pickup range and B counter semantics mismatch", checks);
        require(
            m1937::sdk::rva::create_world_actor != 0 &&
                m1937::sdk::rva::complete_actor_interaction != 0 &&
                m1937::sdk::rva::apply_world_item_effect != 0 &&
                m1937::sdk::rva::complete_world_item_drop != 0 &&
                m1937::sdk::rva::populate_world_item_acceptance != 0 &&
                m1937::sdk::rva::scan_live_targets != 0 &&
                m1937::sdk::rva::scan_corpses != 0 &&
                m1937::sdk::rva::spawn_corpse_reinforcements != 0 &&
                m1937::sdk::rva::scan_world_items != 0 &&
                m1937::sdk::rva::original_directional_visibility_band != 0 &&
                m1937::sdk::rva::global_corpse_alarm != 0,
            "world-item RVA catalog mismatch", checks);
        require(
            m1937::sdk::world_item::accepts(4, 52) &&
                !m1937::sdk::world_item::accepts(4, 48) &&
                m1937::sdk::world_item::accepts(5, 33) &&
                m1937::sdk::world_item::accepts(5, 48) &&
                m1937::sdk::world_item::accepts(6, 49) &&
                !m1937::sdk::world_item::accepts(6, 33) &&
                m1937::sdk::world_item::accepts(11, 83) &&
                !m1937::sdk::world_item::accepts(11, 48) &&
                m1937::sdk::world_item::accepts(15, 48) &&
                !m1937::sdk::world_item::accepts(15, 49) &&
                m1937::sdk::world_item::accepts(56, 82) &&
                !m1937::sdk::world_item::accepts(56, 83),
            "world-item runtime-type acceptance mismatch", checks);
        require(
            m1937::sdk::world_item::effect(49).kind ==
                    m1937::sdk::world_item::EffectKind::hypnosis &&
                m1937::sdk::world_item::effect(49)
                    .consume_after_collection &&
                m1937::sdk::world_item::effect(52).kind ==
                    m1937::sdk::world_item::EffectKind::
                        poison_and_distraction &&
                m1937::sdk::world_item::effect(52)
                    .consume_after_collection &&
                m1937::sdk::world_item::effect(83).kind ==
                    m1937::sdk::world_item::EffectKind::distraction &&
                !m1937::sdk::world_item::effect(83)
                    .consume_after_collection,
            "world-item effect semantics mismatch", checks);
        require(
            !m1937::sdk::world_item::counter_has_completed(600, 600) &&
                m1937::sdk::world_item::counter_has_completed(601, 600) &&
                !m1937::sdk::world_item::counter_has_completed(80, 80) &&
                m1937::sdk::world_item::counter_has_completed(81, 80),
            "world-item counter thresholds mismatch", checks);
        require(
            m1937::sdk::corpse_discovery::is_candidate(1, 1, 0) &&
                !m1937::sdk::corpse_discovery::is_candidate(1, 0, 0) &&
                !m1937::sdk::corpse_discovery::is_candidate(1, 1, 1) &&
                m1937::sdk::corpse_discovery::required_visibility_band == 2 &&
                m1937::sdk::corpse_discovery::reinforcement_marker_actor_type ==
                    93 &&
                m1937::sdk::corpse_discovery::reinforcement_actor_type == 6 &&
                m1937::sdk::corpse_discovery::reinforcement_count == 2,
            "corpse-discovery candidate/reinforcement semantics mismatch",
            checks);
        const auto corpse_reaction_limit =
            m1937::sdk::corpse_discovery::reaction_limit(0x1937u);
        require(
            corpse_reaction_limit >= 40 &&
                corpse_reaction_limit <= 79 &&
                !m1937::sdk::corpse_discovery::reaction_has_completed(
                    corpse_reaction_limit,
                    corpse_reaction_limit) &&
                m1937::sdk::corpse_discovery::reaction_has_completed(
                    corpse_reaction_limit + 1,
                    corpse_reaction_limit),
            "corpse-discovery reaction counter mismatch", checks);
        {
        using namespace m1937::sdk::original_enemy_ai;
        require(
            m1937::sdk::rva::actor_distance != 0 &&
                m1937::sdk::rva::alert_effective_radius != 0 &&
                m1937::sdk::rva::alert_propagation != 0 &&
                m1937::sdk::rva::original_local_search_point != 0 &&
                m1937::sdk::rva::original_local_search_continue != 0,
            "original enemy-AI RVA catalog mismatch", checks);
        require(
            is_within_alert_ellipse({0, 0}, {639, 0}) &&
                !is_within_alert_ellipse({0, 0}, {640, 0}) &&
                is_within_alert_ellipse({0, 0}, {0, 319}) &&
                !is_within_alert_ellipse({0, 0}, {0, 320}) &&
                is_within_alert_ellipse({0, 0}, {320, 320}),
            "original coordinate-alert strict ellipse mismatch", checks);
        require(
            alert_recipient_is_eligible(1, 6, true, false) &&
                !alert_recipient_is_eligible(1, 91, true, false) &&
                !alert_recipient_is_eligible(3, 6, true, false) &&
                !alert_recipient_is_eligible(1, 6, false, false) &&
                !alert_recipient_is_eligible(1, 6, true, true),
            "original coordinate-alert recipient filter mismatch", checks);
        const auto source_reaction =
            alert_source_reaction_from_random(18467);
        require(
            source_reaction.search_delay_limit == 67 &&
                source_reaction.search_delay_counter == 0 &&
                source_reaction.reaction_state == 0 &&
                source_reaction.special_attention_hold == 0,
            "coordinate-alert source-side reaction write mismatch", checks);
        const auto queued_alert =
            coordinate_alert_command({1244, 478});
        require(
            queued_alert.goal_kind == 1 &&
                queued_alert.coordinate.x == 1244 &&
                queued_alert.coordinate.y == 478 &&
                queued_alert.command_variant == 1 &&
                queued_alert.command_pending == 1 &&
                queued_alert.movement_active == 1 &&
                coordinate_alert_winner(false, false) ==
                    CoordinateAlertWinner::queued_alert &&
                coordinate_alert_winner(true, false) ==
                    CoordinateAlertWinner::recipient_ai &&
                coordinate_alert_winner(false, true) ==
                    CoordinateAlertWinner::recipient_ai,
            "coordinate-alert deferred command arbitration mismatch",
            checks);
        require(
            secondary_search_runtime_type_enabled(16) &&
                secondary_search_runtime_type_enabled(20) &&
                secondary_search_runtime_type_enabled(25) &&
                secondary_search_runtime_type_enabled(27) &&
                secondary_search_runtime_type_enabled(28) &&
                secondary_search_runtime_type_enabled(29) &&
                !secondary_search_runtime_type_enabled(19) &&
                !secondary_search_runtime_type_enabled(30),
            "secondary-search runtime-type dispatcher mismatch", checks);
        require(
            secondary_search_candidate_is_eligible(1, true) &&
                !secondary_search_candidate_is_eligible(2, true) &&
                !secondary_search_candidate_is_eligible(1, false) &&
                is_within_secondary_search_radius(
                    {0, 0}, {127, 0}) &&
                !is_within_secondary_search_radius(
                    {0, 0}, {128, 0}),
            "secondary-search strict candidate filter mismatch", checks);
        const WorldBounds secondary_bounds{0, 0, 1000, 500};
        require(
            secondary_search_point_from_values(
                0, 0, 0, 0, {100, 100}, secondary_bounds).x == 164 &&
                secondary_search_point_from_values(
                    0, 0, 0, 0, {100, 100}, secondary_bounds).y == 132 &&
                secondary_search_point_from_values(
                    0, 0, 1, 1, {100, 100}, secondary_bounds).x == 36 &&
                secondary_search_point_from_values(
                    0, 0, 1, 1, {100, 100}, secondary_bounds).y == 68 &&
                secondary_search_point_from_values(
                    0, 0, 1, 1, {70, 50}, secondary_bounds).x == 6 &&
                secondary_search_point_from_values(
                    0, 0, 1, 1, {10, 10}, secondary_bounds).x == 16 &&
                secondary_search_point_from_values(
                    0, 0, 0, 0, {950, 480}, secondary_bounds).x == 984,
            "secondary-search destination sampling mismatch", checks);
        auto original_random_state = 0x1937u;
        for (int sample_index = 0; sample_index < 512; ++sample_index) {
            const auto reaction =
                sample_reaction_limit(original_random_state);
            require(
                reaction.limit >= 40 && reaction.limit <= 79,
                "original AI reaction limit escaped 40..79", checks);
            const auto point = sample_local_search_point(
                reaction.random_state,
                {500, 500},
                {0, 0, 3200, 1600});
            require(
                point.point.x >= 469 && point.point.x <= 531 &&
                    point.point.y >= 485 && point.point.y <= 515 &&
                    point.next_wait_limit >= 40 &&
                    point.next_wait_limit <= 199,
                "original AI local-search sample escaped recovered bounds",
                checks);
            original_random_state = point.random_state;
        }
        const auto edge_search = sample_local_search_point(
            1u, {0, 0}, {0, 0, 3200, 1600});
        require(
            edge_search.point.x >= 16 &&
                edge_search.point.y >= 16 &&
                search_point_count == 5 &&
                !counter_has_completed(40, 40) &&
                counter_has_completed(41, 40),
            "original AI local-search clamp/count/counter mismatch", checks);
        }
        const auto& triggered =
            m1937::sdk::triggered_special_action;
        const auto& timed =
            m1937::sdk::timed_special_action;
        require(
            triggered.attack_type == 8 &&
                triggered.consumed_item_id == 43 &&
                triggered.deployment_actor_type == 84 &&
                triggered.deployment_gfl_index == 470 &&
                triggered.trigger_faction_id == 1 &&
                triggered.trigger_horizontal_radius == 32 &&
                triggered.trigger_vertical_radius == 16,
            "type-8 deployment semantics mismatch", checks);
        require(
            timed.attack_type == 10 &&
                timed.consumed_item_id == 45 &&
                timed.deployment_actor_type == 85 &&
                timed.deployment_gfl_index == 900 &&
                timed.fuse_world_ticks == 100,
            "type-10 deployment semantics mismatch", checks);
        require(
            triggered.explosion_actor_type == 62 &&
                triggered.primary_damage == 128 &&
                triggered.blast_horizontal_radius == 128 &&
                triggered.blast_vertical_radius == 64 &&
                triggered.alert_radius == 800 &&
                timed.explosion_actor_type ==
                    triggered.explosion_actor_type &&
                timed.primary_damage == triggered.primary_damage,
            "actor-62 primary explosion semantics mismatch", checks);
        require(
            m1937::sdk::explosion_actor_extra_damage(
                34, 100, 0) == 128 &&
                m1937::sdk::explosion_actor_extra_damage(
                    34, 385, 0) == 0 &&
                m1937::sdk::explosion_actor_extra_damage(
                    66, 255, 0) == 128 &&
                m1937::sdk::explosion_actor_extra_damage(
                    66, 256, 0) == 0 &&
                m1937::sdk::explosion_actor_extra_damage(
                    1, 100, 0) == 0,
            "actor-62 special damage-band semantics mismatch", checks);
        require(
            m1937::sdk::special_attention_rules.attack_type == 11 &&
                m1937::sdk::special_attention_rules.inventory_item_id ==
                    99 &&
                m1937::sdk::special_attention_rules.target_flag_offset ==
                    0x290 &&
                !m1937::sdk::special_attention_rules.consumes_item &&
                m1937::sdk::special_attention_rules.pauses_idle_movement &&
                m1937::sdk::special_attention_rules.faces_source_actor &&
                m1937::sdk::special_attention_rules
                    .releases_on_source_movement &&
                m1937::sdk::special_attention_rules
                    .releases_on_combat_transition,
            "type-11 attention-hold semantics mismatch", checks);
        const auto* dress =
            m1937::sdk::disguise_transition_for(10, 54);
        const auto* undress =
            m1937::sdk::disguise_transition_for(91, 92);
        require(
            dress != nullptr &&
                dress->to_runtime_type == 91 &&
                dress->to_gfl_index == 272 &&
                dress->to_faction_id == 1 &&
                dress->granted_backpack_item_id == 92 &&
                dress->granted_weapon_item_id == 99 &&
                undress != nullptr &&
                undress->to_runtime_type == 10 &&
                undress->to_gfl_index == 270 &&
                undress->to_faction_id == 3 &&
                undress->granted_backpack_item_id == 54 &&
                undress->removed_weapon_item_id == 99,
            "Gu Ming disguise transition table mismatch", checks);
        require(
            m1937::sdk::disguise_change_tick_limit == 100 &&
                m1937::sdk::disguise_recovery_tick_limit == 100 &&
                m1937::sdk::disguise_breaks_on_attack(91, 1) &&
                m1937::sdk::disguise_breaks_on_attack(91, 4) &&
                !m1937::sdk::disguise_breaks_on_attack(91, 11) &&
                !m1937::sdk::disguise_breaks_on_attack(10, 1),
            "Gu Ming disguise timing/attack exposure mismatch", checks);
        require(
            m1937::sdk::disguise_detection_mode(
                4, 1, 1000, 1000) ==
                    m1937::sdk::DisguiseDetectionMode::ordinary_vision &&
                m1937::sdk::disguise_detection_mode(
                    19, 2, 127, 0) ==
                    m1937::sdk::DisguiseDetectionMode::
                        close_without_line_of_sight &&
                m1937::sdk::disguise_detection_mode(
                    24, 6, 0, 127) ==
                    m1937::sdk::DisguiseDetectionMode::
                        close_without_line_of_sight &&
                m1937::sdk::disguise_detection_mode(
                    24, 6, 0, 128) ==
                    m1937::sdk::DisguiseDetectionMode::none,
            "Gu Ming disguise identification rules mismatch", checks);
        require(
            m1937::sdk::rva::player_disguise_toggle != 0 &&
                m1937::sdk::rva::normal_guming_update != 0 &&
                m1937::sdk::rva::disguised_guming_update != 0 &&
                m1937::sdk::rva::transfer_actor_state_for_disguise !=
                    0 &&
                m1937::sdk::rva::break_disguise_after_attack != 0 &&
                m1937::sdk::rva::scan_disguise_observers != 0 &&
                m1937::sdk::rva::normal_guming_update !=
                    m1937::sdk::rva::disguised_guming_update &&
                m1937::sdk::rva::break_disguise_after_attack !=
                    m1937::sdk::rva::scan_disguise_observers,
            "Gu Ming disguise RVA catalog mismatch", checks);

        using namespace m1937::sdk::enemy_ai;
        const auto novice = tuning_for(0, 0);
        const auto veteran = tuning_for(3, 3);
        require(
            novice.search_point_count == 0 &&
                veteran.search_point_count == 4 &&
                veteran.maximum_reinforcements == 4 &&
                veteran.reaction_delay_ms < novice.reaction_delay_ms,
            "AI difficulty tuning is not monotonic", checks);
        Candidate candidates[] = {
            {30, 300, true},
            {20, 100, true},
            {10, 50, false},
            {40, 200, true},
            {50, 400, true}
        };
        std::uintptr_t selected[8]{};
        const auto selected_count = select_reinforcements(
            candidates, std::size(candidates),
            selected, std::size(selected), 2);
        require(
            selected_count == 2 &&
                selected[0] == 20 &&
                selected[1] == 40,
            "AI reinforcement selection is not bounded/nearest-first",
            checks);
        const LastKnownObservation observation{
            1000, 2000, 8, 1234};
        Point search[4]{};
        const auto search_count = build_search_pattern(
            observation, veteran, search, std::size(search));
        require(
            search_count == 4 &&
                search[0] == Point{1096, 2000} &&
                search[1] == Point{1000, 1904} &&
                search[2] == Point{1000, 2096},
            "AI search pattern is not anchored to last observation",
            checks);
        require(
            decide_search_step(
                false, 1000, 18000, false, false, 1, 4) ==
                SearchDecision::keep_current_goal &&
            decide_search_step(
                false, 1000, 18000, true, false, 1, 4) ==
                SearchDecision::advance_to_next_point &&
            decide_search_step(
                true, 1000, 18000, false, false, 1, 4) ==
                SearchDecision::hand_back_to_original_ai &&
            decide_search_step(
                false, 18000, 18000, false, false, 1, 4) ==
                SearchDecision::hand_back_to_original_ai,
            "AI search exit/advance policy mismatch", checks);
        require(
            !samples_live_target_after_alert,
            "AI policy permits live target sampling after alert", checks);
        require(
            m1937::sdk::plugin::abi_version_v1 == 0x00010000 &&
                m1937::sdk::plugin::mission_schema_version_v1 == 1 &&
                sizeof(m1937::sdk::plugin::WorldEventV1) == 40,
            "plugin ABI v1 layout/version mismatch", checks);
        require(
            offsetof(
                m1937::sdk::plugin::WorldEventV1,
                monotonic_milliseconds) == 16 &&
                offsetof(
                    m1937::sdk::plugin::WorldEventV1,
                    value) == 36,
            "plugin world-event field offsets changed", checks);

        std::cout << "M1937SDK validation passed (" << checks
                  << " executable checks, native layout static_asserts passed).\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << "M1937SDK validation failed: "
                  << exception.what() << "\n";
        return 1;
    }
}
