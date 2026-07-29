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
